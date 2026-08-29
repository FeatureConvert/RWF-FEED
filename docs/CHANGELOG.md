# Changelog

Running log of user-facing fixes and changes, kept so future App Store "What's New" release
notes can be written accurately instead of from memory. This file itself isn't submitted
anywhere — see `docs/APP_STORE_SUBMISSION.md` for what actually goes into App Store Connect.

Format: newest first. Each dated section corresponds to a shipped version; `[Unreleased]`
holds whatever's landed since the last one.

## [Unreleased]

### Fixed
- Push notifications stopped registering entirely for every device starting the evening of
  1.1's release (2026-08-27) — the push-service Worker's code was never actually redeployed
  after the same-day Notification-preferences-split migration (`002_split_raiderio_enabled.sql`),
  so it kept running its pre-split `addDevice` logic, which wrote to a `raiderio_enabled` column
  the migration had already dropped. Every `POST /register` (both the initial registration after
  granting permission and the re-send on every Settings toggle change) threw a D1 error
  server-side; the app's `URLSession` call doesn't inspect HTTP status, so nothing ever
  surfaced client-side. Devices that had registered before the migration kept receiving pushes
  (their rows were untouched), silently masking the outage for existing installs sending no new
  registration; new/reinstalled devices got nothing, with no error anywhere to point at.
  Redeployed the current Worker code — registration and delivery confirmed working via
  `/test-push` immediately after.

## [1.1] — 2026-08-27

### Added
- Tracker tab: pin any guild (tap the star) to keep it visible in its own section above the
  main standings, regardless of its rank.
- Region filter (Settings → Region: World/US/EU/KR/TW/CN) — narrows Tracker, Bosses, and
  Heartbreak to one region's guilds. Push notifications always reflect the true global race
  regardless of this filter.
- Notifications now open directly to the relevant tab (new post → Feed, Major Heartbreaker →
  Heartbreak, World First!/Spoiler Alert/Race Complete → Bosses, WoW News → News) instead of
  whatever Default Tab happens to be set.
- Live Activity (Settings → Live Activity → Start) showing the race leader's next boss and the
  best current pull on it, on the Lock Screen and in the Dynamic Island. Kept live by the server
  even when the app is closed — no need to reopen it for updates.
- Watch app now shows a Top 3 guild standings list (bosses down) below the leader's next-boss
  summary.
- First-visit tips (TipKit) on the Heartbreak screen, the Boss List (explaining you can tap a
  boss to see its kills), and the Close Call Threshold slider in Settings, explaining each to
  newcomers. Shown once per device, never again after dismissed.
- Race Complete: once the world's leading guild clears every boss, everyone gets a distinct
  "🏆 Race Complete!" push (separate from the final boss's own World First push), a "Final
  Standings" recap banner on the Bosses tab, and the Live Activity shows a proper "Race
  Complete — [Guild] wins!" card instead of going stale or blank.
- Bosses and Heartbreak now show a "trending toward a kill" indicator (e.g. "−4.2% in the last
  hour") next to a guild's live pull, once there's enough history to say something meaningful —
  an app-derived estimate, not a raider.io number.
- VoiceOver accessibility pass across the app, widgets, and watch app: dense stat rows (Tracker,
  Bosses, Heartbreak, Final Standings, watch Top 3) now read as one coherent sentence instead of
  each guild name/percent/pull count/rank arriving as separate disconnected stops; icon-only
  controls (Settings gear, boss-row disclosure, pin button, VOD links) got real labels; purely
  decorative art (guild avatars, dividers, trend arrows, boss icons) is hidden from VoiceOver
  instead of announced as noise; and the expand/collapse animation on a boss's kills now
  respects Reduce Motion.
- Notification preferences: "Raider.IO Updates" is now three independent toggles — New Feed
  Posts, Major Heartbreaker, and World First Kills — so you can, say, keep World First alerts
  without the chattier Heartbreak close-call pushes. Existing preferences carry over
  automatically; nothing needs re-enabling.

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
- Boss kill data had the same issue as Tracker above (same root cause) — recent kills could be
  missing entirely. Fixed the same way.
- Push notifications never showed a badge on the app icon — the push payload never requested
  one. Now requests a badge, and it clears when the app is opened (via two independent
  triggers, since the first one alone wasn't reliably firing).
- The app wasn't adapted for iPad at all — content and the tab bar stretched to fill a full
  iPad's width, ballooning card/video sizes and spacing the tab bar icons far apart. Now capped
  to a sensible column width and centered, matching a real iPad layout. Checked against the
  largest (iPad Pro 13") and smallest (iPad mini) supported sizes.
- The watchOS app and Home Screen widget could show a guild that was merely scouting/wiping on
  a later boss as the race "leader," even while another guild with more confirmed kills was
  genuinely ahead. Both now anchor on the real leader (most bosses killed) instead.
- The medium and large/extra-large Home Screen widgets mostly showed empty space — each only
  ever displayed a small, fixed block of text regardless of how much room the widget actually
  had. Both now fill that space with a short guild standings list/strip.
- A stray tab character embedded in some raider.io coverage posts could render as a large,
  broken-looking gap inside a push notification's body text. Now sanitized before sending.
- Some coverage posts run two sentences together with no space at all between them (e.g.
  "...Sentinels!Congratulations Instant_Dollars...") — now a space is inserted automatically.
- The Heartbreak tab's "close call" cutoff was hardcoded to 10%, completely separate from the
  Settings slider that (confusingly) only ever affected push notifications. Both now use the
  same threshold.
- "Watch the Kill" VOD links (Bosses tab) never appeared for any raid, for any boss — a decoding
  mismatch against raider.io's actual Hall of Fame response silently broke the fetch every time.
  Now decodes correctly and VOD links show up as intended.
- Feed post tags were showing raw internal values like "day-6" instead of anything readable.
  Now only shows the guild-name tags, which are the only ones meant to be user-facing.
- A Live Activity could get silently orphaned — the server was wiping its entire token registry
  on every boss change instead of just the tokens it had actually just sent an "end" update to,
  so a device registering at the wrong moment lost its Live Activity's updates with no error and
  no way to recover short of restarting it.
- Tapping "Watch the Kill" on a boss row could occasionally be swallowed by the row's own
  tap-to-expand-kills gesture instead of opening the VOD. The link now always wins.
- A device with Default Tab set to the old standalone Kills tab now opens to Bosses (where that
  content lives now) instead of silently resetting to Feed.

### Changed
- Tracker tab's guild list is now capped at the top 25 (was up to 50) — more focused at a
  glance.
- The standalone Kills tab is gone — every boss row in Bosses now expands (tap it) to show its
  top 3 kills right there, so you get the full kill log without leaving the boss list. The app
  is back to 5 tabs (Feed, Tracker, Bosses, Heartbreak, News) with Apple's standard tab bar.
- Removed the Live Now strip from Tracker (the horizontal row of currently-streaming guilds) —
  a guild's live badge on its own Tracker row still shows when they're streaming.

## [1.0] — 2026-08-23
Initial App Store submission (in Apple review as of this writing). See
`docs/APP_STORE_SUBMISSION.md` for the full feature set as of this release.
