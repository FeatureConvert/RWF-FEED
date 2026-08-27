-- One-time migration: splits the single raiderio_enabled column into three independent
-- per-category preferences (feed_posts_enabled, major_heartbreaker_enabled,
-- world_first_kill_enabled) now that Settings exposes them as separate toggles instead of one
-- combined "Raider.IO Updates" switch. Existing devices keep their current behavior — each new
-- column is backfilled from raiderio_enabled, so a device that had it on/off stays on/off for
-- all three categories until the user changes them independently in Settings.
--
-- Recreates the table (same approach as 001_add_token_check_constraints.sql) rather than
-- leaving raiderio_enabled around as dead weight, since SQLite has no ALTER TABLE DROP COLUMN
-- prior to 3.35 and this keeps schema.sql and the live table in sync either way.

CREATE TABLE devices_new (
  token TEXT PRIMARY KEY CHECK (length(token) = 64 AND token NOT GLOB '*[^0-9a-fA-F]*'),
  feed_posts_enabled INTEGER NOT NULL DEFAULT 1,
  major_heartbreaker_enabled INTEGER NOT NULL DEFAULT 1,
  world_first_kill_enabled INTEGER NOT NULL DEFAULT 1,
  wowhead_enabled INTEGER NOT NULL DEFAULT 1,
  spoiler_free_enabled INTEGER NOT NULL DEFAULT 0,
  heartbreak_threshold_percent REAL NOT NULL DEFAULT 5.0,
  notify_non_world_first_heartbreaks INTEGER NOT NULL DEFAULT 0
);

INSERT INTO devices_new
  (token, feed_posts_enabled, major_heartbreaker_enabled, world_first_kill_enabled,
   wowhead_enabled, spoiler_free_enabled, heartbreak_threshold_percent, notify_non_world_first_heartbreaks)
  SELECT
    token, raiderio_enabled, raiderio_enabled, raiderio_enabled,
    wowhead_enabled, spoiler_free_enabled, heartbreak_threshold_percent, notify_non_world_first_heartbreaks
  FROM devices;

DROP TABLE devices;
ALTER TABLE devices_new RENAME TO devices;
