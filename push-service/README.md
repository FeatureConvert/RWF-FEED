# push-service

A Cloudflare Worker that gets RWF FEED new-post notifications delivered even while the
app is fully closed. Local notifications (the app's own polling loop) only fire while the
app is running — this Worker polls raider.io independently, on its own 1-minute cron
(Cloudflare's minimum cron granularity), and pushes via APNs the moment something new
shows up.

Deployed at: `https://rwf-feed-push.rwf-feed.workers.dev`

## How it works

- **Cron** (`* * * * *`, every minute): fetches raider.io's coverage feed, diffs against
  `lastSeenPostId` in KV, and sends a push for anything newer.
- **`POST /register`**: the app calls this after `registerForRemoteNotifications()`
  succeeds, with `{ "deviceToken": "<hex>" }`. Tokens are stored in KV under
  `deviceTokens`; a `BadDeviceToken`/410 response from APNs on send removes a token
  automatically (e.g. after a reinstall).
- **`GET /check`**: manually triggers the same poll-and-diff logic as the cron. Returns
  `{ ok, newPosts }`.
- **`GET /test-push`**: sends a fixed test notification directly to every registered
  token, bypassing the raider.io fetch and the `lastSeenPostId` diff entirely. Useful for
  confirming delivery without needing a real new post or fighting KV's eventual
  consistency (writes can take up to ~60s to become visible to the Worker's own reads).

## Redeploying after a code change

```bash
cd push-service
npx wrangler deploy
```

## Secrets (already set — for reference / rotating the key)

```bash
npx wrangler secret put APNS_KEY_ID       # the .p8 key's Key ID, e.g. 446M78Q934
npx wrangler secret put APNS_TEAM_ID      # Apple Developer Team ID (5X98G8X3FJ)
npx wrangler secret put APNS_BUNDLE_ID    # RIO.RWF-FEED
npx wrangler secret put APNS_PRIVATE_KEY  # full contents of the AuthKey_*.p8 file
npx wrangler secret put APNS_ENV          # "sandbox" (dev-signed builds) or "production"
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

## KV namespace

Binding `PUSH_KV`, id `e8207fa029d447c1a5e574a43bffef07` (see `wrangler.toml`). Holds two
keys: `lastSeenPostId` (integer) and `deviceTokens` (JSON array of hex token strings).

```bash
# Inspect current state
npx wrangler kv key get "lastSeenPostId" --namespace-id e8207fa029d447c1a5e574a43bffef07 --remote
npx wrangler kv key get "deviceTokens" --namespace-id e8207fa029d447c1a5e574a43bffef07 --remote
```

## Account

Cloudflare account `dd3ff3501d5b570adfc0b4b8e020ce42`, workers.dev subdomain `rwf-feed`.
Logged in via `npx wrangler login` (OAuth) — re-run if the session expires.
