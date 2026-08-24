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

-- Periodic (guild, boss) pull-progress snapshots, used to compute a "trending toward a kill"
-- rate-of-progress indicator client-side (percent now vs. percent ~1 hour ago). Only written
-- for guilds with an active, undefeated pull, and only when the value actually changed or
-- enough time has passed since the last snapshot for that pair (see snapshotPullVelocity in
-- worker.js) — same "don't write unless something changed" discipline as the rest of this
-- schema. Pruned on the 15-minute cron tick to bound growth; nothing here needs to outlive the
-- ~1 hour lookback window by more than a small margin.
CREATE TABLE IF NOT EXISTS pull_velocity_snapshots (
  guild_id INTEGER NOT NULL,
  boss_slug TEXT NOT NULL,
  best_percent REAL NOT NULL,
  num_pulls INTEGER NOT NULL,
  recorded_at TEXT NOT NULL,
  PRIMARY KEY (guild_id, boss_slug, recorded_at)
);
CREATE INDEX IF NOT EXISTS idx_pull_velocity_recorded_at ON pull_velocity_snapshots (recorded_at);
