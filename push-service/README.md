# push-service

A Cloudflare Worker that gets RWF FEED new-post notifications delivered even while the
app is fully closed. Local notifications (the app's own polling loop) only fire while the
app is running — this Worker polls raider.io independently, on its own 1-minute cron
(Cloudflare's minimum cron granularity), and pushes via APNs the moment something new
shows up.

Deployed at: `https://rwf-feed-push.rwf-feed.workers.dev`

## How it works

Every registered device gets every push — there's no per-device filtering. (Per-guild
notification preferences were tried and removed; the favorited-guild push never fired
reliably enough to be worth the complexity.)

- **Cron** (`* * * * *`, every minute): runs both checks below.
- **`checkForNewPosts`**: fetches the coverage feed, diffs against `lastSeenPostId` in
  KV, and pushes anything newer to every registered device.
- **`checkHeartbreaks`**: "Major Heartbreaker" pushes — a guild pulling a not-yet-killed
  boss under `HEARTBREAK_THRESHOLD_PERCENT` (5.01%) remaining health, sourced from
  `raid-rankings`. Only on a new record close call per guild+boss — tracked in
  `heartbreakBest` in KV — so a guild wiping repeatedly around the same percent doesn't
  get pushed every minute.
- **`POST /register`**: the app calls this after `registerForRemoteNotifications()`
  succeeds, with `{ "deviceToken": "<hex>" }`. A `BadDeviceToken`/410 response from APNs
  on send removes the device automatically (e.g. after a reinstall).
- **`GET /check?secret=<value>`**: manually triggers both checks above. Returns
  `{ posts, heartbreaks }`.
- **`GET /test-push?secret=<value>`**: sends a fixed test notification directly to every
  registered device, bypassing both diffs entirely. Useful for confirming delivery
  without needing a real new post/close-call or fighting KV's eventual consistency
  (writes can take up to ~60s to become visible to the Worker's own reads).

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
- `heartbreakBest` — JSON object, `{ "guildId-bossSlug": lowestPercentSeen }` — the record
  close call already pushed for each guild+boss pair, so only a new record re-pushes.
- `devices` — JSON array of hex token strings. Also accepts (read-only) older per-guild
  shapes left over from the removed notification-filtering feature — `getDevices`
  normalizes any `{ token, guildIds }`/`{ token, guildId }` entries down to plain tokens.
- `deviceTokens` — the original key name, from before `devices` existed. Only read as a
  last-resort fallback if `devices` doesn't exist yet; never written to anymore.

```bash
# Inspect current state
npx wrangler kv key get "lastSeenPostId" --namespace-id e8207fa029d447c1a5e574a43bffef07 --remote
npx wrangler kv key get "devices" --namespace-id e8207fa029d447c1a5e574a43bffef07 --remote
npx wrangler kv key get "heartbreakBest" --namespace-id e8207fa029d447c1a5e574a43bffef07 --remote
```

## Account

Cloudflare account `dd3ff3501d5b570adfc0b4b8e020ce42`, workers.dev subdomain `rwf-feed`.
Logged in via `npx wrangler login` (OAuth) — re-run if the session expires.
