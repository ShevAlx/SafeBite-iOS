# ProductScanner — starter project

## How to set up in Xcode

1. Open Xcode → File → New → Project → iOS App.
   - Interface: SwiftUI
   - Language: Swift
   - Project name: ProductScanner
2. Delete the auto-created `ContentView.swift` and `ProductScannerApp.swift`, replace them with the files from this archive, keeping the folder structure (Models / Services / Views / ViewModels).
3. In `Info.plist` add the camera key (required, otherwise the app crashes when requesting access):
   - `NSCameraUsageDescription` — "Camera access is needed to scan barcodes and products"
   - `NSPhotoLibraryUsageDescription` — "Photo library access is needed to upload a product photo"
4. Target iOS 16+ (uses PhotosPicker with `loadTransferable` and the new `.onChange` syntax).
5. Build and run on a real device — the simulator doesn't provide camera access.

## What already works

- Real-time barcode scanning (EAN-8/13, UPC-E, Code128) → query to Open Food Facts → ingredients, allergens, Nutri-Score, macros.
- Photo capture when there's no barcode: first visual product recognition (Google Cloud Vision Web Detection) → search for the found name in Open Food Facts → if that doesn't work, OCR of the ingredient list via the Vision framework as a second fallback, with allergens detected by keyword straight from the label text (keywords are provided in both Russian and English).
- User profile with personal allergies — the product card highlights specifically the allergens that are risky for that user.
- The card separately shows "contains" (allergens_tags) and "may contain traces" (traces_tags) — previously the traces_tags field wasn't read at all, which meant products with a cross-contact warning on the label were incorrectly shown as fully safe.
- Tapping the card opens the full product screen: all allergens (including "may contain"), calories and macros per 100 g, full ingredient list, NOVA group explanation.
- Haptic feedback on successful product recognition — no extra on-screen UI.
- The interface is entirely in English; the UI follows Apple's "glass" design style (`.ultraThinMaterial` + stroke + shadow — compatible with iOS 16+, not tied to the iOS 26 Liquid Glass API).

## Setting up Google Cloud Vision (for visual recognition)

The Vision API key **is not stored in the app** — it lives only on the server, as a
secret on the Supabase Edge Function `vision-proxy` (`supabase/functions/vision-proxy`).
The app talks to that function, not to Google directly, so the key can't be
extracted from the binary.

1. Go to [Google Cloud Console](https://console.cloud.google.com), create a project, enable **Cloud Vision API**, create an API key (Credentials → Create Credentials → API Key).
2. Install the [Supabase CLI](https://supabase.com/docs/guides/cli) and log in (`supabase login`).
3. Link the project: `supabase link --project-ref <your-project-ref>` (from the root of `ProductScanner/`).
4. Run the migration (creates the daily scan-limit table, see below): `supabase db push`.
5. Deploy the function: `supabase functions deploy vision-proxy`.
6. Set the secret on the server: `supabase secrets set GOOGLE_VISION_API_KEY=your_key`.
   (`SUPABASE_URL`/`SUPABASE_SERVICE_ROLE_KEY` for the scan limit are injected into the function by Supabase itself — nothing extra to set there.)
7. In `Services/Secrets.swift` (copied from `Secrets.swift.example`) fill in:
   - `supabaseProjectURL` — your project's URL (Project Settings → API → Project URL).
   - `supabaseAnonKey` — the anon/public key from the same place (public by design, not a secret at the level of the Vision key).
8. The Vision API free tier is 1000 requests/month for Web Detection and Label Detection, billed beyond that (check current pricing on the Vision API pricing page).

## Moving the project to another machine

`Secrets.swift` is in `.gitignore` and never travels with the repo — cloning this project fresh on another computer will *not* bring your filled-in keys with it. The services themselves (the Supabase project, the deployed `vision-proxy` function, the Vision API key stored on the server, the USDA account) all stay live in the cloud and don't need to be set up again. All that's needed locally is:

1. Copy `Secrets.swift.example` → `Secrets.swift`.
2. Fill it in with the exact same values already sitting in your current `Secrets.swift` (Supabase project URL, Supabase anon key, USDA API key) — just copy the existing values over, nothing needs to be re-registered.

Back up the current `Secrets.swift` somewhere safe (e.g. your own cloud storage / password manager) before wiping or switching machines, so you have those three values on hand. Its full path on this machine:

```
VIbe_Coding/ProductScanner/ProductScanner/Services/Secrets.swift
```

## Daily photo-scan limit

`vision-proxy` counts photo scans per `X-Device-Id` (a UUID from the Keychain, `DeviceIdentifier.swift` — survives reinstalls) and rejects the request with 429 if there are more than 50 in a day (`DAILY_SCAN_LIMIT` in `supabase/functions/vision-proxy/index.ts`). This isn't a mechanism for distinguishing trial vs. paid subscribers — the limit always applies, to everyone, as a flat safety net against free-month abuse. The counter lives in the `scan_usage` table (migration `supabase/migrations/0001_scan_usage.sql`).

## Subscription

All scanning (barcode and photo) is gated behind a subscription via StoreKit 2 (`Services/SubscriptionManager.swift`, `Views/PaywallView.swift`) — without an active subscription, `PaywallView` is shown instead of the main screen. The free month is the subscription's own intro offer in App Store Connect; there's no separate free code path.

Setup in App Store Connect:
1. Create a Subscription Group (e.g. "SafeBite Premium").
2. Add two auto-renewable plans in it:
   - `com.vibecoding.ProductScanner.premium.monthly` — $1.99/month
   - `com.vibecoding.ProductScanner.premium.annual` — $14.99/year
   (these are the placeholders from `SubscriptionManager.swift` — either create products with the same IDs, or change the `monthlyID`/`annualID` constants to your own.)
3. On both (or at least one), set up an Introductory Offer → Free Trial, 1 month.
4. Fill in the required metadata (localized names, per-storefront prices) and submit for review together with the binary.
5. For local testing in the simulator without App Store Connect: a StoreKit Configuration file with these two product IDs is already included at `Configuration.storekit` (linked to the shared scheme) — no need to create one from scratch, just adjust prices/products there if needed.
6. The "Manage Subscription" button in the profile (`AllergyProfileView`) opens the system `.manageSubscriptionsSheet` — cancellation is entirely handled by Apple, no custom UI needed for that.

## What's worth doing next

- Cache Open Food Facts responses in Core Data — right now every scan hits the network again.
- Network error handling (retry, offline mode).
- Localization of the quality card (Nutri-Score/NOVA are currently taken as-is from OFF, without adapting to Cyrillic data if the product is from the Russian-language part of the database).
- Accept "product not found, please add" submissions — either through the Open Food Facts write API, or through our own table in the same Supabase database with moderation before publishing.
