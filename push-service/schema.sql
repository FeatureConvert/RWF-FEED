CREATE TABLE IF NOT EXISTS devices (
  token TEXT PRIMARY KEY,
  raiderio_enabled INTEGER NOT NULL DEFAULT 1,
  wowhead_enabled INTEGER NOT NULL DEFAULT 1,
  spoiler_free_enabled INTEGER NOT NULL DEFAULT 0,
  heartbreak_threshold_percent REAL NOT NULL DEFAULT 5.0,
  notify_non_world_first_heartbreaks INTEGER NOT NULL DEFAULT 0
);

-- Small key/value table for the cron's own tracking state (last-seen post id, best pull
-- percent per guild/boss, which bosses have already had a World First push, last-seen
-- Wowhead article date). Kept generic rather than one column per field since these are
-- independent, occasionally-changing blobs, not a single evolving record.
CREATE TABLE IF NOT EXISTS cron_state (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL
);

-- ActivityKit push-to-update tokens for the race Live Activity, registered from Settings (see
-- RaceLiveActivityController.swift). A separate registry from `devices` — different push type
-- entirely (liveactivity vs. alert), and the app can have a Live Activity running independent
-- of whether regular push notifications are also on.
CREATE TABLE IF NOT EXISTS live_activity_tokens (
  push_token TEXT PRIMARY KEY
);
