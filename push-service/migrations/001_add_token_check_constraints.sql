-- One-time migration: adds the CHECK constraints now in schema.sql's devices/live_activity_tokens
-- definitions to the already-live tables. SQLite has no ALTER TABLE ADD CONSTRAINT, so this
-- recreates each table and copies the data across instead. Safe to run only because both tables
-- were confirmed clean first (devices: the one malformed 160-char token already deleted;
-- live_activity_tokens: empty). Idempotent to re-run only in the sense that a second run is a
-- harmless no-op recreate — not needed once applied.

CREATE TABLE devices_new (
  token TEXT PRIMARY KEY CHECK (length(token) = 64 AND token NOT GLOB '*[^0-9a-fA-F]*'),
  raiderio_enabled INTEGER NOT NULL DEFAULT 1,
  wowhead_enabled INTEGER NOT NULL DEFAULT 1,
  spoiler_free_enabled INTEGER NOT NULL DEFAULT 0,
  heartbreak_threshold_percent REAL NOT NULL DEFAULT 5.0,
  notify_non_world_first_heartbreaks INTEGER NOT NULL DEFAULT 0
);
INSERT INTO devices_new SELECT * FROM devices;
DROP TABLE devices;
ALTER TABLE devices_new RENAME TO devices;

CREATE TABLE live_activity_tokens_new (
  push_token TEXT PRIMARY KEY CHECK (length(push_token) = 64 AND push_token NOT GLOB '*[^0-9a-fA-F]*')
);
INSERT INTO live_activity_tokens_new SELECT * FROM live_activity_tokens;
DROP TABLE live_activity_tokens;
ALTER TABLE live_activity_tokens_new RENAME TO live_activity_tokens;
