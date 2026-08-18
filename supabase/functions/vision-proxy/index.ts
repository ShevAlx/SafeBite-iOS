// Supabase Edge Function: proxies Google Cloud Vision requests so the app
// never ships the Vision API key in the binary. The key lives only as a
// server-side secret (GOOGLE_VISION_API_KEY), set via `supabase secrets set`.
//
// Also enforces a daily per-device photo-scan quota (see migration
// 0001_scan_usage.sql) — a flat safety net against subscription-trial abuse,
// not a mechanism for distinguishing trial vs. paid subscribers.
//
// The client (VisualRecognitionService.swift) calls this function with the
// Supabase anon key and an X-Device-Id header instead of talking to Google
// directly.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const GOOGLE_VISION_ENDPOINT = "https://vision.googleapis.com/v1/images:annotate";
const DAILY_SCAN_LIMIT = 50;

interface VisionProxyRequest {
  imageBase64?: string;
}

function jsonError(message: string, status: number): Response {
  return new Response(JSON.stringify({ error: message }), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return new Response("Method not allowed", { status: 405 });
  }

  const apiKey = Deno.env.get("GOOGLE_VISION_API_KEY");
  if (!apiKey) {
    return jsonError("Server misconfigured: missing GOOGLE_VISION_API_KEY", 500);
  }

  const deviceId = req.headers.get("x-device-id");
  if (!deviceId) {
    return jsonError("Missing X-Device-Id header", 400);
  }

  let body: VisionProxyRequest;
  try {
    body = await req.json();
  } catch {
    return jsonError("Invalid JSON body", 400);
  }

  if (!body.imageBase64) {
    return jsonError("Missing imageBase64", 400);
  }

  // SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY are auto-injected into every
  // Edge Function by the Supabase runtime — no manual secret needed for these.
  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
  );
  const today = new Date().toISOString().slice(0, 10);

  const { data: newCount, error: usageError } = await supabase.rpc("increment_scan_usage", {
    p_device_id: deviceId,
    p_date: today,
  });

  if (usageError) {
    return jsonError("Usage tracking failed", 500);
  }
  if ((newCount as number) > DAILY_SCAN_LIMIT) {
    return jsonError("Daily scan limit reached, try again tomorrow", 429);
  }

  const visionRequest = {
    requests: [
      {
        image: { content: body.imageBase64 },
        features: [
          { type: "WEB_DETECTION", maxResults: 5 },
          { type: "LABEL_DETECTION", maxResults: 5 },
        ],
      },
    ],
  };

  const visionResponse = await fetch(`${GOOGLE_VISION_ENDPOINT}?key=${apiKey}`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(visionRequest),
  });

  const responseBody = await visionResponse.text();
  return new Response(responseBody, {
    status: visionResponse.status,
    headers: { "Content-Type": "application/json" },
  });
});
