# push-service

A Cloudflare Worker that gets RWF FEED new-post and WoW-news notifications delivered even
while the app is fully closed. Local notifications (the app's own polling loop) only fire
while the app is running — this Worker polls raider.io and Wowhead independently and pushes
via APNs the moment something new shows up. Raid coverage/pulls run on a 1-minute cron
(Cloudflare's minimum granularity); Wowhead news runs on its own 15-minute cron, since news
posts far less often and doesn't need the same freshness.

Deployed at: `https://rwf-feed-push.rwf-feed.workers.dev`

## How it works

Each registered device carries five independent preferences — `raiderioEnabled`,
`wowheadEnabled`, `spoilerFreeEnabled`, `heartbreakThresholdPercent`, and
`notifyNonWorldFirstHeartbreaks` — set from Settings, filtering/redacting/thresholding
server-side (there's no way to veto or rewrite a push client-side once APNs has
delivered it while the app is closed). There's no per-guild filtering within
`raiderioEnabled` (tried and removed; the favorited-guild push never fired reliably
enough to be worth the complexity) — it's an all-or-nothing category, same as
`wowheadEnabled`.

- **Cron** (`* * * * *`, every minute): runs `checkForNewPosts` and `checkRaiderIOEvents`
  below. A second cron (`*/15 * * * *`) runs `checkWowheadNews` on its own slower cadence;
  `scheduled()` routes on `event.cron` since both triggers fire the handler and the
  15-minute one also matches every 1-minute tick.
- **`checkForNewPosts`**: fetches the coverage feed, diffs against `lastSeenPostId` in
  D1, and pushes anything newer to every `raiderioEnabled` device. Coverage posts
  routinely announce kills in the first sentence, so `spoilerFreeEnabled` devices get a
  generic body here too, not just on `checkWorldFirstKills` pushes.
- **`checkRaiderIOEvents`**: fetches raid-race (boss names) and raid-rankings (live
  pull/defeat data) once, then runs both of the following against that shared data —
  they'd otherwise each need the same two fetches every minute:
  - **`checkHeartbreaks`**: "Major Heartbreaker" pushes — a guild pulling a boss down to
    a new-record-low remaining health%. Record-tracking (`heartbreakBest` in D1, per
    guild+boss) is threshold-agnostic by design — each device then applies its own
    `heartbreakThresholdPercent` (default `HEARTBREAK_DEFAULT_THRESHOLD_PERCENT`, 5.01%)
    and `notifyNonWorldFirstHeartbreaks` (default off — only reach devices that opted in
    for a close call on a boss another guild already claimed) independently at push
    time, since two devices can disagree on both.
  - **`checkWorldFirstKills`**: "World First!" pushes — the first guild to defeat each
    boss, tracked in `worldFirstKillsSeen` in D1 so each boss only pushes once. For
    `spoilerFreeEnabled` devices, the guild/boss are redacted to a generic "Spoiler
    Alert" body instead of naming them.
  - Both only reach `raiderioEnabled` devices.
  - All three of the above only write to D1 when the tracked value actually changes
    (a real new post, a genuine new heartbreak record, a new World First claim) — not
    unconditionally on every cron tick.
- **`checkWowheadNews`**: fetches Wowhead's public WoW-retail-only RSS feed
  (`wowhead.com/news/rss/retail` — excludes Diablo/other-game articles), diffs by
  `pubDate` against `wowheadLastSeenPubDate` in D1, and pushes new articles ("WoW News" /
  article title) to every `wowheadEnabled` device.
- **`POST /register`**: the app calls this after `registerForRemoteNotifications()`
  succeeds, and again whenever a Settings toggle/slider changes, with
  `{ "deviceToken": "<hex>", "raiderioEnabled": bool, "wowheadEnabled": bool, "spoilerFreeEnabled": bool, "heartbreakThresholdPercent": number, "notifyNonWorldFirstHeartbreaks": bool }`.
  Upserts by token — a device that re-registers gets its existing entry's preferences
  updated, not a duplicate. A `BadDeviceToken`/410 response from APNs on send removes
  the device automatically (e.g. after a reinstall).
- **`GET /check`**: manually triggers all three checks above. Returns
  `{ posts, raiderioEvents, wowheadNews }`.
- **`GET /test-push`**: sends a fixed test notification directly to every
  registered device (ignoring all preference flags), bypassing all diffs entirely.
  Useful for confirming delivery without needing a real new post/close-call/kill/article.

```bash
curl -H "X-Admin-Secret: <value>" "https://rwf-feed-push.rwf-feed.workers.dev/check"
curl -H "X-Admin-Secret: <value>" "https://rwf-feed-push.rwf-feed.workers.dev/test-push"
```

`/check` and `/test-push` require the `ADMIN_SECRET` Worker secret as an `X-Admin-Secret`
header — without it they 401. A header instead of a `?secret=` query param, since query
strings end up verbatim in Cloudflare's request logs and browser history. `/register` has no such gate — it only ever touches the
caller's own device token — but it does validate `deviceToken` (must match APNs' 64-hex-char
shape) and caps total registered devices at `MAX_DEVICES` (200), returning 400/429
respectively; `heartbreakThresholdPercent` is clamped to
`[HEARTBREAK_MIN_THRESHOLD_PERCENT, HEARTBREAK_MAX_THRESHOLD_PERCENT]` (1–25) rather than
accepted as any positive number.

## Redeploying after a code change

```bash
cd push-service
npx wrangler deploy
```

## Secrets (already set — for reference / rotating a key)

```bash
npx wrangler secret put APNS_KEY_ID       # the .p8 key's Key ID, e.g. 446M78Q934
npx wrangler secret put APNS_TEAM_ID      # Apple Developer Team ID (5X98G8X3FJ)
npx wrangler secret put APNS_BUNDLE_ID    # RIO.RWF-FEED
npx wrangler secret put APNS_PRIVATE_KEY  # full contents of the AuthKey_*.p8 file
npx wrangler secret put APNS_ENV          # "sandbox" (dev-signed builds) or "production"
npx wrangler secret put ADMIN_SECRET      # gates /check and /test-push — any random string
```

**Sandbox vs production**: the app is currently signed for development
(`aps-environment: development` in `RWF FEED/RWF FEED.entitlements`), which routes
through `api.sandbox.push.apple.com`. If the app is ever archived/distributed
(TestFlight or App Store), the entitlement becomes `production` and `APNS_ENV` must be
updated to match — a sandbox-issued token will not accept a production push and vice
versa.

**Never commit the `.p8` file** — it's gitignored (`*.p8`) and was moved out of the repo
after use. If you need it again, generate a new one at
[developer.apple.com → Keys](https://developer.apple.com/account/resources/authkeys/list)
(only downloadable once) and re-run `wrangler secret put APNS_PRIVATE_KEY`.

**`ADMIN_SECRET` isn't retrievable once set** — Cloudflare secrets are write-only. If you
lose it, generate a new random value and `wrangler secret put ADMIN_SECRET` again; the
old one stops working immediately.

## D1 database

Binding `DB`, database `rwf-feed-push-db` (id `41de81ab-430f-4cd0-8ef9-41235ee7a2cd`, see
`wrangler.toml`; schema in `schema.sql`). This replaced a Workers KV namespace
(`PUSH_KV`, id `e8207fa029d447c1a5e574a43bffef07`, still exists but no longer bound to the
Worker) — KV's free tier caps out at 1,000 write ops/day, and this cron's own unconditional
writes on every tick were repeatedly exceeding it (see git history around 2026-08-23 for
the incident and the conditional-write fix that shipped first). D1's free tier is 100,000
writes/day, ~100x the headroom, for $0/month.

Two tables:

- **`devices`** — one row per device: `token` (primary key), `raiderio_enabled`,
  `wowhead_enabled`, `spoiler_free_enabled`, `heartbreak_threshold_percent`,
  `notify_non_world_first_heartbreaks`. Upserted atomically via
  `INSERT ... ON CONFLICT(token) DO UPDATE`.
- **`cron_state`** — generic `key`/`value` table for the cron's own tracking state:
  - `lastSeenPostId` — the highest feed post ID seen so far, as a string.
  - `heartbreakBest` — JSON object, `{ "guildId-bossSlug": lowestPercentSeen }` — the
    record close call already pushed for each guild+boss pair, so only a new record
    re-pushes.
  - `worldFirstKillsSeen` — JSON object, `{ bossSlug: true }` — which bosses already had
    a World First push.
  - `wowheadLastSeenPubDate` — ISO date string, the newest Wowhead article `pubDate` seen
    so far.

```bash
# Inspect current state
npx wrangler d1 execute rwf-feed-push-db --remote --command="SELECT * FROM devices"
npx wrangler d1 execute rwf-feed-push-db --remote --command="SELECT * FROM cron_state"
```

## Account

Cloudflare account `dd3ff3501d5b570adfc0b4b8e020ce42`, workers.dev subdomain `rwf-feed`.
Logged in via `npx wrangler login` (OAuth) — re-run if the session expires.
