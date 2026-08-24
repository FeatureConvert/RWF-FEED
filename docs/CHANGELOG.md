# Changelog

Running log of user-facing fixes and changes, kept so future App Store "What's New" release
notes can be written accurately instead of from memory. This file itself isn't submitted
anywhere — see `docs/APP_STORE_SUBMISSION.md` for what actually goes into App Store Connect.

Format: newest first. Each dated section corresponds to a shipped version; `[Unreleased]`
holds whatever's landed since the last one.

## [Unreleased]

### Fixed
- Push notifications could silently stop for hours at a time, recurring roughly daily — caused
  by the Cloudflare Worker backend hitting a free-tier write-operation limit a few hours after
  every daily reset (the cron was writing to storage on every single poll, even when nothing
  had changed). Writes are now conditional on real state actually changing, and the backend's
  storage was migrated to a service with ~100x more headroom, so this class of outage
  shouldn't recur.
- Tracker tab standings could be significantly out of date — a guild's real progress (e.g. a
  boss kill from 20+ minutes earlier) sometimes wasn't reflected at all, because the tab read
  from a raider.io data source that was observed lagging well behind raider.io's own public
  leaderboard. Now reads from the same live, real-time source the leaderboard itself uses.
- Kills tab had the same issue as Tracker above (same root cause) — recent kills could be
  missing entirely. Fixed the same way.

### Changed
- Tracker tab's guild list is now capped at the top 25 (was up to 50) — more focused at a
  glance.
- Kills tab reworked from one flat chronological list into a section per boss (each capped to
  its top 3 placements) — the flat version made it hard to tell at a glance which boss a kill
  belonged to once several were in progress at once, and buried World Firsts under a wall of
  low placements.

## [1.0] — 2026-08-23
Initial App Store submission (in Apple review as of this writing). See
`docs/APP_STORE_SUBMISSION.md` for the full feature set as of this release.
