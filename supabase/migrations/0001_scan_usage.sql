-- Per-device daily counter for the vision-proxy photo-scan quota. Guards
-- against free-trial abuse (see supabase/functions/vision-proxy) — only the
-- service role (used by the edge function) ever touches this table, so RLS
-- is enabled with no client-facing policies.
create table public.scan_usage (
  device_id text not null,
  scan_date date not null,
  count integer not null default 0,
  primary key (device_id, scan_date)
);

alter table public.scan_usage enable row level security;

-- Atomic upsert-and-increment so concurrent requests from the same device on
-- the same day can't race past the daily limit.
create or replace function public.increment_scan_usage(p_device_id text, p_date date)
returns integer
language sql
as $$
  insert into public.scan_usage (device_id, scan_date, count)
  values (p_device_id, p_date, 1)
  on conflict (device_id, scan_date)
  do update set count = scan_usage.count + 1
  returning count;
$$;
