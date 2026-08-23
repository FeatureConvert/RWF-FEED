# push-service

A Cloudflare Worker that gets RWF FEED new-post notifications delivered even while the
app is fully closed. Local notifications (the app's own polling loop) only fire while the
app is running — this Worker polls raider.io independently, on its own 1-minute cron
(Cloudflare's minimum cron granularity), and pushes via APNs the moment something new
shows up.

Deployed at: `https://rwf-feed-push.rwf-feed.workers.dev`

## How it works

Each device registers with a list of favorite guild IDs (`guildIds`). An empty list is
the default: a push for every new post in the global coverage feed. A non-empty list
switches that device to guild-specific mode: a push only when one of those guilds' boss
count goes up, independent of whether the editorial feed ever mentions that guild.

- **Cron** (`* * * * *`, every minute): runs all three checks below.
- **`checkForNewPosts`**: fetches the coverage feed, diffs against `lastSeenPostId` in
  KV, and pushes anything newer to every device with an empty `guildIds` list.
- **`checkGuildKills`**: fetches `raid-rankings` (not the raid-race timeline — see the
  comment at the top of `worker.js` for why: the timeline caps each progress step to a
  handful of guilds, which would silently drop most favorited guilds), diffs each
  tracked guild's boss count against `guildProgress` in KV, and pushes devices that
  favorited a guild whose count just went up.
- **`checkHeartbreaks`**: "Major Heartbreaker" pushes — a guild pulling a not-yet-killed
  boss under `HEARTBREAK_THRESHOLD_PERCENT` (5.01%) remaining health. Goes to the same
  "all feed posts" devices as `checkForNewPosts` (a near-miss is race news regardless of
  favorited guild), and only on a new record close call per guild+boss — tracked in
  `heartbreakBest` in KV — so a guild wiping repeatedly around the same percent doesn't
  get pushed every minute.
- **`POST /register`**: the app calls this after `registerForRemoteNotifications()`
  succeeds (and again whenever the user changes their notification preferences), with
  `{ "deviceToken": "<hex>", "guildIds": [<number>, ...] }`. A `BadDeviceToken`/410
  response from APNs on send removes the device automatically (e.g. after a reinstall).
- **`GET /check?secret=<value>`**: manually triggers all three checks above. Returns
  `{ posts, kills, heartbreaks }`.
- **`GET /test-push?secret=<value>`**: sends a fixed test notification directly to every
  registered device, bypassing both diffs entirely. Useful for confirming delivery
  without needing a real new post/kill or fighting KV's eventual consistency (writes can
  take up to ~60s to become visible to the Worker's own reads).

`/check` and `/test-push` require the `ADMIN_SECRET` Worker secret as a `secret` query
param — without it they 401. `/register` has no such gate; it only ever touches the
caller's own device token.

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

## KV namespace

Binding `PUSH_KV`, id `e8207fa029d447c1a5e574a43bffef07` (see `wrangler.toml`). Holds:

- `lastSeenPostId` — integer, the highest feed post ID seen so far.
- `guildProgress` — JSON object, `{ [guildId]: bossesDown }` as of the last cron tick.
- `heartbreakBest` — JSON object, `{ "guildId-bossSlug": lowestPercentSeen }` — the record
  close call already pushed for each guild+boss pair, so only a new record re-pushes.
- `devices` — JSON array of `{ token, guildIds }`. Also accepts (read-only) two older
  shapes for devices that haven't re-registered since a schema change: `{ token,
  guildId: number | null }` (pre-multi-select), normalized on read in `getDevices`.
- `deviceTokens` — the original flat array of token strings, from before any
  notification preferences existed. Only read as a last-resort fallback if `devices`
  doesn't exist yet; never written to anymore.

```bash
# Inspect current state
npx wrangler kv key get "lastSeenPostId" --namespace-id e8207fa029d447c1a5e574a43bffef07 --remote
npx wrangler kv key get "devices" --namespace-id e8207fa029d447c1a5e574a43bffef07 --remote
npx wrangler kv key get "guildProgress" --namespace-id e8207fa029d447c1a5e574a43bffef07 --remote
```

## Account

Cloudflare account `dd3ff3501d5b570adfc0b4b8e020ce42`, workers.dev subdomain `rwf-feed`.
Logged in via `npx wrangler login` (OAuth) — re-run if the session expires.
