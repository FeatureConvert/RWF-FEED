# App Store Submission — Reference Checklist

Working notes for getting Azeroth Watch (formerly branded "RWF Feed" — see naming decision
below) into TestFlight and, eventually, the App Store. Nothing here is time-sensitive — it's
a reference to pick back up whenever. Status current as of 2026-08-23 (post code-review
hardening pass — see "Recent hardening" below).

## Current facts

| | |
|---|---|
| App display name | **Azeroth Watch** (set via `INFOPLIST_KEY_CFBundleDisplayName` — what shows under the icon and in TestFlight/App Store, not the same as the project/scheme name below) |
| Xcode project / scheme / repo name | "RWF FEED" / RWF-FEED — internal identifiers only, not renamed (not user-facing, not worth the churn/risk of a project rename) |
| Bundle ID | `RIO.RWF-FEED` (widget: `RIO.RWF-FEED.RWFFeedWidget`, watch app: `RIO.RWF-FEED.watchkitapp`, watch widget: `RIO.RWF-FEED.watchkitapp.RWFFeedWatchWidget`) |
| Team ID | `5X98G8X3FJ` |
| Marketing version | 1.0 (build 1) |
| Deployment target | iOS 26.5 (main app), watchOS companion also present |
| Code signing | Automatic, Apple Development (dev-signed) |
| Repo | https://github.com/FeatureConvert/RWF-FEED (**public** as of 2026-08-23 — see below) |
| Privacy Policy | https://featureconvert.github.io/RWF-FEED/PRIVACY_POLICY.html (GitHub Pages, serving `docs/`) |

Repo went public specifically so GitHub Pages could host the Privacy Policy URL Apple requires
(see "Privacy Policy URL" below) without paying for separate hosting. Swept the full git
history first for secrets/credentials/PII before flipping visibility — clean (no hardcoded
keys, no `.env`/`.p8`/credential files ever committed; the Worker's actual secrets live in
Cloudflare, referenced by name only). GitHub Pages is configured to serve `main` branch's
`/docs` folder, so this file and the privacy policy are both publicly browsable there — fine,
since a public repo already makes every file readable via the normal GitHub file browser
regardless of Pages.

## Naming decision (final, 2026-08-23)

Went through several rounds on this — see git history on this file for the full trail. Short
version: flagged a real App Store collision with "Method RWF" (an existing, functionally
similar app from an actual competing raid guild); explored dropping "RWF" entirely; landed on
**Azeroth Watch**, checked against the App Store and found no collisions (a few loose
community-project name overlaps — a private-server fan newspaper, an X account — but nothing
that's an app). This also better reflects the app's scope now that it covers general WoW news
(via Wowhead) alongside RWF-specific tracking, not just the race.

Implemented:
- Main app `CFBundleDisplayName` → "Azeroth Watch" (Home Screen icon label, TestFlight, App
  Store listing name default).
- Widget, watch app, and watch widget `CFBundleDisplayName` → "Azeroth Watch" (watch Home
  Screen app list, in particular, is user-facing).
- In-app trademark disclaimer and feedback email subject line updated to match.
- **Not** renamed: the Xcode project file, scheme, target names, bundle ID, or the GitHub
  repo — all internal/technical identifiers nobody but you and I ever see. Renaming those
  would be pure churn with real risk (broken references, git history noise) for zero
  user-facing benefit.

## What's already done

- [x] **App name** — "Azeroth Watch," see naming decision above.
- [x] **App icon** — 1024×1024 universal icon set with dark/tinted variants (`Assets.xcassets/AppIcon.appiconset`). No further action needed for submission.
- [x] **Export compliance key** — `ITSAppUsesNonExemptEncryption = NO` added to the main target's build settings (Debug + Release). The app only uses standard HTTPS/APNs, which is exempt from export documentation requirements — this answers Apple's encryption question automatically on every future upload instead of prompting each time.
- [x] **Trademark disclaimer** — added to the bottom of Settings, covering Blizzard/WoW, Raider.IO, and Wowhead: *"Azeroth Watch is a fan-made, unofficial app and is not affiliated with, endorsed by, or sponsored by Blizzard Entertainment, Inc., Raider.IO, or Wowhead/ZAM Network, LLC. World of Warcraft and Blizzard Entertainment are trademarks of Blizzard Entertainment, Inc. Raider.IO and Wowhead are trademarks of their respective owners."* Standard practice for any WoW-adjacent fan app and something App Review commonly checks for.
- [x] **Raider.IO attribution** — required by their API terms (a link back to raider.io from any public-facing app using their data). Present on the Feed tab header and in Settings, with their official brand mark (sourced from their own CDN).
- [x] **Wowhead attribution** — same pattern, present on the News tab and in Settings.
- [x] **No third-party logo/Marks reproduced without review** — both credits use official, sourced marks (not fabricated), added after checking each site's terms of use for logo-reproduction restrictions.
- [x] **Privacy Policy** — drafted and hosted, see `docs/PRIVACY_POLICY.md` / the live URL above.
- [x] **Repo made public**, GitHub Pages enabled to host the above.

## Recent hardening (full list in git log; summarized here)

A background code-review pass (5 parallel research/audit agents, one full read-only code
review) surfaced a handful of real bugs, all fixed and deployed before this submission push:

- Push registration used to only trigger from the Feed tab's view model — a user with a
  different Default Tab could go a whole session unregistered, or a rotated APNs token never
  get re-sent. Now happens at app launch regardless of which tab opens.
- Hidden tabs kept polling raider.io/Wowhead forever in the background once visited (the
  custom 6-tab bar keeps tabs mounted rather than tearing them down, so `.onDisappear` never
  fired) — ~9 requests/min sustained regardless of which single tab was on screen. Now
  properly paused/resumed based on which tab is actually selected.
- The Close Call Threshold slider fired a network POST on every drag tick instead of once on
  release — dozens of racing requests where the last to *arrive*, not the value released, won.
- The widget/watch complication's "falls back to last known state on failure" comment was
  aspirational — nothing was ever persisted, so a network blip blanked them for a full
  15+-minute refresh cycle. Now genuinely persists and falls back.
- Guild logos re-downloaded from scratch every time a row scrolled out of and back into view.
  Now cached app-wide in memory, keyed by URL.
- The push Worker's `/register` endpoint had no input validation (unbounded device growth
  risk) — now validates the device-token shape and caps total devices.
- Spoiler-Free Mode only redacted "World First!" pushes, not the regular new-post push — which
  routinely spoils the same kill in its preview text first. Both paths redact now.
- Feed post HTML was being re-parsed (a real, non-trivial cost — NSAttributedString's HTML
  importer) on every single re-render instead of once per post; now cached per post.

## Feature set as of this submission pass

Beyond what's described above: 6 tabs (Feed, Tracker, Kills, Bosses, Heartbreak, News — News
pulls general WoW patch/tuning news from Wowhead, added after the app's initial build), a
"Watch the Kill" Twitch VOD deep-link on World First boss kills (raider.io's Hall of Fame
endpoint), per-category push notification toggles (Raider.IO updates, Wowhead news) plus a
Spoiler-Free Mode and a configurable close-call alert threshold, a Settings screen (appearance
mode, default startup tab, feedback email, all the attribution/legal content described
above), an in-app browser for all external links, a watchOS companion app with 4 complication
families, and an iOS home-screen widget.

## Still needed before submitting

### 1. App Store Connect app record
Requires your own browser session (Apple ID with a paid Developer Program membership,
$99/year, if not already enrolled) — I can't do this step. At https://appstoreconnect.apple.com:
- Register the bundle ID (`RIO.RWF-FEED`) under Certificates, Identifiers & Profiles if not already there.
- Create a new app record: display name **Azeroth Watch** (see naming decision above — already checked against the App Store, no collisions found), primary language, bundle ID, SKU (any unique internal string).

### 2. ~~Privacy Policy URL~~ — done
Drafted at `docs/PRIVACY_POLICY.md` and live at
https://featureconvert.github.io/RWF-FEED/PRIVACY_POLICY.html via GitHub Pages (repo made
public specifically to host this for free — see "Current facts" above). Paste that URL into
App Store Connect's Privacy Policy field when creating the app record.

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

### 6. App Store metadata — drafted, ready to paste in

**Subtitle** (27/30 chars):
> Race to World First Tracker

**Description** (~1,300/4,000 chars):
> Follow World of Warcraft's Race to World First in real time.
>
> Azeroth Watch tracks Mythic raid progress across every competing guild, built on Raider.IO's
> live data:
>
> • Feed — Raider.IO's own live coverage posts, as they happen
> • Tracker — every guild's current standings, ranked by bosses down
> • Kills — a chronological log of every boss kill worldwide, with placement (World First,
>   2nd, 3rd...)
> • Bosses — who's claimed World First on each boss, plus the closest live pull on ones still
>   unclaimed — including a direct link to watch the kill on Twitch
> • Heartbreak — every close call under 10% remaining health on a boss nobody's killed yet
> • News — general WoW patch notes and tuning changes from Wowhead, so you know why a guild's
>   pace just changed
>
> Push notifications keep you posted even when the app's closed — new coverage, close-call
> alerts, World First kill announcements, and WoW news, each independently toggleable. Want to
> follow the race without spoilers? Turn on Spoiler-Free Mode and kill announcements are
> redacted until you're ready to look.
>
> A watchOS companion app and complications put the current boss and closest pull right on
> your wrist, and a home screen widget keeps it visible without opening the app.
>
> Azeroth Watch is a fan-made, unofficial companion app. It is not affiliated with, endorsed
> by, or sponsored by Blizzard Entertainment, Raider.IO, or Wowhead. All race data is provided
> by Raider.IO; all WoW news is provided by Wowhead.

**Keywords** (90/100 chars):
> wow,warcraft,race to world first,rwf,mythic raid,guild,raider.io,boss kill,esports,tracker

**Category**: **Entertainment** — confirmed precedent: Method RWF (the closest comparable app,
built by an actual competing guild) is listed under Entertainment on the App Store, not
Reference or Utilities.

**Support URL**: https://github.com/FeatureConvert/RWF-FEED (now public — issues can be filed
there directly) or the Privacy Policy page's site root,
https://featureconvert.github.io/RWF-FEED/.

**Marketing URL**: optional, skip unless you want one.

**Age rating questionnaire**: the in-app browser gives unrestricted access to raider.io/
Wowhead/Twitch pages, which Apple's questionnaire treats as "Unrestricted Web Access"; combined
with no other mature content, this should land at 12+ or similar rather than 17+, but the
questionnaire itself determines the final rating — fill it in honestly rather than guessing
from here.

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

- ~~Category~~ — resolved, see #6 above (Entertainment).
- ~~Public repo or stays private?~~ — resolved, made public 2026-08-23 specifically for free
  GitHub Pages hosting of the Privacy Policy.
- **Internal-only vs. eventually public on the App Store** — internal TestFlight testing
  doesn't strictly require the Privacy Policy/metadata either (no prompt for either until you
  actually submit for App Store review, as opposed to just TestFlight), but both are done now
  regardless, so this doesn't change what's left. The two real remaining blockers are #1 (App
  Store Connect app record) and #4 (sandbox→production APNs switch) — everything else in this
  doc is prepared and just needs pasting in once the app record exists.

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
  consuming app itself is distributed via the App Store. Azeroth Watch doesn't charge for anything
  or resell their data, so this should be fine, but it's not a formal legal opinion — worth
  keeping in mind if the app ever adds monetization.

## 2.0 in progress — Ads (AdMob)

1.0 was submitted 2026-08-23 (see above — that section is now historical). Work since then:

- Added the Google Mobile Ads SDK (`GoogleMobileAds`, v12.14.0, via SPM) to the main app
  target only — not the watch or widget extensions.
- A single small banner (`BannerAdView`/`AdBannerBar` in `RWF FEED/BannerAdView.swift`) sits
  above the custom tab bar on every tab, via `ContentView.swift`.
- Ads request **non-personalized only** (`npa=1` extra on every request) — deliberately, to
  stay consistent with the Privacy Policy's existing "never used for tracking" stance and to
  avoid needing an App Tracking Transparency prompt (non-personalized mode never touches IDFA).
- `RWF FEED/Info-Ads.plist` merges `GADApplicationIdentifier` and a minimal `SKAdNetworkItems`
  (Google's own network ID only) into the generated Info.plist via `INFOPLIST_FILE` alongside
  `GENERATE_INFOPLIST_FILE = YES` — currently holds **Google's published test App ID**
  (`ca-app-pub-3940256099942544~1458002511`); `BannerAdView` uses Google's matching **test ad
  unit ID**. Verified working end-to-end in Simulator (real test creative renders).
- `docs/PRIVACY_POLICY.md` updated with an Advertising section disclosing AdMob/non-personalized
  ads and linking Google's privacy policy.

**Still needed before this can ship as a real 2.0 release:**
- Create a Google AdMob account and register the app to get a **real App ID and banner ad unit
  ID** — swap both in (`Info-Ads.plist` and `BannerAdView.testAdUnitID`) before archiving.
  AdMob account creation/payout setup is something only you can do (Google account + payment
  details) — I can't do this step.
- **App Privacy label update** in App Store Connect — adding an ad SDK almost always means
  redeclaring data types (at minimum Identifiers/Usage Data used for "Third-Party
  Advertising" or "Analytics", depending on what AdMob's SDK actually collects even in NPA
  mode) — needs redoing before the 2.0 build is submitted, separate from what's already live
  for 1.0.
- **EU/UK consent (UMP)** — Google's Mobile Ads SDK pulled in `GoogleUserMessagingPlatform`
  automatically as a dependency, but no consent flow is wired up yet. Google's EU User Consent
  Policy generally expects a consent mechanism (their own UMP SDK, or an equivalent CMP) for
  users in the EEA/UK even for non-personalized ads — worth resolving before shipping to those
  regions rather than assuming NPA alone is sufficient. Not yet researched in depth; flagging
  as a real open question, not a solved one.
- Bump `MARKETING_VERSION` (currently still `1.0`) and `CURRENT_PROJECT_VERSION` when this is
  actually ready to archive for the 2.0 build.
