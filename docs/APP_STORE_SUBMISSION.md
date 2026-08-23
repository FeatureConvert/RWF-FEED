# App Store Submission — Reference Checklist

Working notes for getting RWF Feed into TestFlight and, eventually, the App Store. Nothing
here is time-sensitive — it's a reference to pick back up whenever. Status current as of
2026-08-23.

## Current facts

| | |
|---|---|
| Bundle ID | `RIO.RWF-FEED` (widget: `RIO.RWF-FEED.RWFFeedWidget`, watch app: `RIO.RWF-FEED.watchkitapp`, watch widget: `RIO.RWF-FEED.watchkitapp.RWFFeedWatchWidget`) |
| Team ID | `5X98G8X3FJ` |
| Marketing version | 1.0 (build 1) |
| Deployment target | iOS 26.5 (main app), watchOS companion also present |
| Code signing | Automatic, Apple Development (dev-signed) |
| Repo | https://github.com/FeatureConvert/RWF-FEED (private) |

## What's already done

- [x] **App icon** — 1024×1024 universal icon set with dark/tinted variants (`Assets.xcassets/AppIcon.appiconset`). No further action needed for submission.
- [x] **Export compliance key** — `ITSAppUsesNonExemptEncryption = NO` added to the main target's build settings (Debug + Release). The app only uses standard HTTPS/APNs, which is exempt from export documentation requirements — this answers Apple's encryption question automatically on every future upload instead of prompting each time.
- [x] **Trademark disclaimer** — added to the bottom of Settings, covering Blizzard/WoW, Raider.IO, and Wowhead: *"RWF Feed is a fan-made, unofficial app and is not affiliated with, endorsed by, or sponsored by Blizzard Entertainment, Inc., Raider.IO, or Wowhead/ZAM Network, LLC. World of Warcraft and Blizzard Entertainment are trademarks of Blizzard Entertainment, Inc. Raider.IO and Wowhead are trademarks of their respective owners."* Standard practice for any WoW-adjacent fan app and something App Review commonly checks for.
- [x] **Raider.IO attribution** — required by their API terms (a link back to raider.io from any public-facing app using their data). Present on the Feed tab header and in Settings, with their official brand mark (sourced from their own CDN).
- [x] **Wowhead attribution** — same pattern, present on the News tab and in Settings.
- [x] **No third-party logo/Marks reproduced without review** — both credits use official, sourced marks (not fabricated), added after checking each site's terms of use for logo-reproduction restrictions.

## Still needed before submitting

### 1. App Store Connect app record
Requires your own browser session (Apple ID with a paid Developer Program membership,
$99/year, if not already enrolled) — I can't do this step. At https://appstoreconnect.apple.com:
- Register the bundle ID (`RIO.RWF-FEED`) under Certificates, Identifiers & Profiles if not already there.
- Create a new app record: pick a display name (App Store name, not necessarily "RWF Feed" — check availability), primary language, bundle ID, SKU (any unique internal string).
- **Name collision risk**: "RWF" is used across multiple fan sites/apps for "Race to World First" — worth a quick App Store search for name conflicts before committing to a display name.

### 2. Privacy Policy URL
**Required** — Apple requires every app to have a privacy policy URL in App Store Connect,
regardless of how little data is collected. RWF Feed doesn't have one yet. It needs to be
hosted somewhere public (a GitHub Pages page off this repo would work, or any static host)
and cover:
- Device push token — collected and sent to `rwf-feed-push.rwf-feed.workers.dev` (a
  Cloudflare Worker you operate) solely to deliver push notifications. Not linked to any
  identity, not shared with third parties, not used for tracking or advertising.
- No accounts, no analytics SDKs, no ads, no in-app purchases.
- No other personal data is collected.

I can draft the actual policy text and a simple hosted page once you're ready — flagging it
here as a blocker rather than writing it blind, since the hosting location affects the URL.

### 3. App Privacy "nutrition label" (App Store Connect → App Privacy)
Based on the above, the honest answers are:
- **Data collected**: Identifiers → Device ID (the push token) — used for App Functionality
  only, **not linked to the user's identity**, **not used for tracking**.
- Everything else (contact info, location, browsing history, purchases, etc.): **not collected**.
- The in-app browser (`SFSafariViewController`) for external links doesn't collect anything
  itself — it's the same sandboxed browser Safari uses.

### 4. Push notification entitlement: sandbox → production
The app is currently signed with `aps-environment: development` (`RWF FEED/RWF FEED.entitlements`),
which only works with dev-signed builds. **Before archiving for TestFlight/App Store**, this
needs to change to `production`, and the Worker's `APNS_ENV` secret needs to match:
```bash
cd push-service
npx wrangler secret put APNS_ENV   # enter "production"
```
Do this switch and the archive together — a sandbox-issued token won't accept a production
push and vice versa, so testing push after the switch matters. See `push-service/README.md`
for the full secrets list.

### 5. Screenshots
Apple requires screenshots for at least one device size per size class (iPhone 6.9" is the
current baseline requirement; iPhone 6.5" and iPad screenshots are optional but recommended
if the app supports iPad — this one does, `TARGETED_DEVICE_FAMILY = "1,2"`). Can be captured
from the Simulator once we're ready — no real device needed for these.

### 6. App Store metadata
Not drafted yet:
- **Subtitle** (30 chars) and **description** (up to 4000 chars)
- **Keywords** (100 chars, comma-separated)
- **Category** — likely *Reference* or *Utilities*; *Games* doesn't fit since this isn't the
  game itself, and *Sports* is a mismatch despite the "race" framing
- **Support URL** — needs to exist somewhere (could be the GitHub repo if made public, or a
  simple page)
- **Marketing URL** (optional)
- **Age rating questionnaire** — the in-app browser gives unrestricted access to raider.io/
  Wowhead pages, which Apple's questionnaire treats as "Unrestricted Web Access"; combined
  with no other mature content, this should land at 12+ or similar rather than 17+, but the
  questionnaire itself determines the final rating.

### 7. TestFlight path (once the app record exists)
- **Internal testers** (up to 100, must be users on your App Store Connect team): no
  review, available almost immediately after a build finishes processing.
  Fastest path to get it on your own devices/friends who you add as testers.
- **External testers**: first build needs a one-time **Beta App Review** (usually
  1-2 days), after which further builds update automatically without re-review unless the
  app changes significantly.
- Either path needs the production APNs switch (#4) done first if you want push notifications
  to actually work in the TestFlight build — a dev-signed build can't even be archived for
  distribution, so this happens automatically as part of archiving.

## Things to decide, not yet decided

- **Display name** for the App Store listing (currently just "RWF FEED" as the Xcode product name).
- **Category**: Reference vs. Utilities vs. something else.
- **Public repo or stays private?** — doesn't block submission either way (App Review doesn't
  need repo access), but affects whether a GitHub Pages privacy policy / support page is
  straightforward (public repos get free Pages hosting; private repos need GitHub Pro/Team or
  an alternate host).
- **Internal-only vs. eventually public on the App Store** — internal TestFlight testing
  doesn't require most of the above (no privacy policy prompt until you actually submit for
  review), so if the near-term goal is just "get it on my phone and a few friends' phones,"
  items #2, #3, #5, #6 can wait and only #1 + #4 are real blockers.

## Third-party terms this app relies on (for reference, already satisfied)

- **Raider.IO** (`raider.io/api`, `raider.io/terms-of-use`): public API is for community/
  personal use; automated scraping beyond documented endpoints and reselling data are
  prohibited; a link back to raider.io is required from any public-facing app using their
  data (done). Their Marks/logo are proprietary and can't be reproduced for commercial
  purposes without written permission — the mark used here is their own official asset, used
  purely for non-commercial attribution.
- **Wowhead** (`wowhead.com/news/rss/*`): RSS feeds are explicitly published for syndication/
  subscription (their own 2010 announcement post promotes this). No explicit attribution
  requirement found in their ToS, but the same "link back + official mark, no commercial use"
  pattern was applied anyway for consistency.
- Neither has a "no App Store distribution" clause — the "personal/non-commercial use" language
  is about not reselling their data or running a competing service, not about whether the
  consuming app itself is distributed via the App Store. RWF Feed doesn't charge for anything
  or resell their data, so this should be fine, but it's not a formal legal opinion — worth
  keeping in mind if the app ever adds monetization.
