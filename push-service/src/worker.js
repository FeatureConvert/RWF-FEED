// rwf-feed-push — polls raider.io's Venomous Abyss coverage feed and Wowhead's WoW news RSS
// once a minute (Cloudflare Cron's minimum granularity) and pushes a notification via APNs
// the moment something new appears. This is what lets RWF FEED notify you even while the app
// is fully closed — local notifications only fire while the app's own polling loop is running.
//
// Each registered device carries five independent preferences, set from Settings —
// raiderioEnabled (new feed posts, "Major Heartbreaker" close calls, "World First!" kill
// announcements), wowheadEnabled (new WoW news articles), spoilerFreeEnabled (redacts both
// World First kill pushes and new-post pushes to a generic body instead of naming/previewing
// what happened — coverage posts routinely announce kills in the first sentence, so both had
// to be covered or the feature didn't deliver what enabling it implies; off by default),
// heartbreakThresholdPercent (how close a pull has to be to push, default
// HEARTBREAK_DEFAULT_THRESHOLD_PERCENT), and notifyNonWorldFirstHeartbreaks (also push for a
// guild's close call on a boss another guild already claimed, not just genuine title-race
// close calls; off by default — matches the Heartbreak tab's own per-guild scope when on).
// Filtering/redaction has to happen here rather than on-device: once APNs has delivered a
// push while the app is closed, there's no client-side hook to veto or rewrite it. There's no
// per-guild filtering within raiderioEnabled (removed; it wasn't working reliably).
//
// Endpoints:
//   POST /register  { "deviceToken": "<hex>", "raiderioEnabled": bool, "wowheadEnabled": bool,
//                      "spoilerFreeEnabled": bool, "heartbreakThresholdPercent": number,
//                      "notifyNonWorldFirstHeartbreaks": bool }
//   POST /live-activity/register  { "pushToken": "<hex>" } — registers a Live Activity's own
//        ActivityKit push token (separate from a device's regular APNs token above), so
//        checkLiveActivity can push content updates as the leader's frontier boss changes.
//   POST /live-activity/unregister  { "pushToken": "<hex>" }
//   GET  /velocity  — read-only, unauthenticated; returns recent (guild, boss) pull-percent
//        snapshots from the periodic cron (see snapshotPullVelocity) for the client's own
//        "trending toward a kill" indicator. See getVelocitySnapshots for the response shape.
//   GET  /check  — manually trigger a poll, for testing (requires X-Admin-Secret header)
//   GET  /test-push — send a placeholder push to every registered device (same header)
//
// /check and /test-push require ADMIN_SECRET (a Worker secret, see README) as an
// `X-Admin-Secret` header — without it, anyone who finds the URL could enumerate every registered
// device token from /test-push's response, or spam real polls via /check. /register has no
// such gate — it only ever adds/updates one device's own token, nothing to protect — but it
// does validate deviceToken's shape (APNs tokens are 64 hex chars) and cap total devices at
// MAX_DEVICES, since an unauthenticated endpoint that accepted anything could otherwise be
// looped to grow `devices` unboundedly.

const FEED_SLUG = "the-venomous-abyss-global-coverage";
const RAID_SLUG = "the-venomous-abyss";
// The Venomous Abyss's real boss count — a floor checkRaceComplete requires `encounterBySlug`
// to actually reach before it will ever fire (see checkRaceComplete). A new raid tier needs
// this updated alongside RAID_SLUG.
const RAID_BOSS_COUNT = 8;
// How long checkRaceComplete's RACE_COMPLETE_KEY claim is honored before a still-"claimed"
// (never completed) state is treated as abandoned and reclaimed — see checkRaceComplete. Cron
// ticks are 1 minute apart; this is generous relative to how long one tick's device-push loop
// can plausibly take, so a genuinely still-running invocation is never mistaken for a dead one.
const STALE_CLAIM_MS = 5 * 60 * 1000;
const LAST_SEEN_KEY = "lastSeenPostId";
// Legacy single-JSON-blob key checkHeartbreaks used to store every (guild, boss) best percent
// under — migrated on first run (see migrateHeartbreakBestKey) to one row per pair under
// HEARTBREAK_BEST_PREFIX, so each new-record claim can be its own atomic UPSERT.
const HEARTBREAK_BEST_KEY = "heartbreakBest";
const HEARTBREAK_BEST_PREFIX = "heartbreakBest:";
// Matches NotificationPreferences.defaultHeartbreakThresholdPercent on the client — kept as a
// clean 5.0 so it lands on the Settings slider's 0.5-step grid rather than snapping on first touch.
const HEARTBREAK_DEFAULT_THRESHOLD_PERCENT = 5.0;
const HEARTBREAK_MIN_THRESHOLD_PERCENT = 1;
const HEARTBREAK_MAX_THRESHOLD_PERCENT = 25;
const WORLD_FIRST_SEEN_KEY = "worldFirstKillsSeen";
const WOWHEAD_NEWS_URL = "https://www.wowhead.com/news/rss/retail";
const WOWHEAD_LAST_SEEN_KEY = "wowheadLastSeenPubDate";
// APNs device tokens are exactly 32 bytes, hex-encoded.
const DEVICE_TOKEN_PATTERN = /^[0-9a-f]{64}$/i;
// /register is deliberately unauthenticated (see below) — without some cap, anyone who finds
// the URL (it's in the app binary) could grow `devices` unboundedly by POSTing junk tokens in
// a loop, and every cron tick then attempts an APNs send per junk entry.
const MAX_DEVICES = 200;
// Same shape/reasoning as MAX_DEVICES — /live-activity/register is also unauthenticated.
const MAX_LIVE_ACTIVITIES = 50;
const LIVE_ACTIVITY_STATE_KEY = "liveActivityState";
const RACE_COMPLETE_KEY = "raceCompleteAnnounced";

// Cloudflare retries a whole scheduled() invocation from scratch if the promise passed to
// ctx.waitUntil() rejects. checkForNewPosts (and friends) already push to devices before
// persisting their "seen" state, so a rejection here — even one from an unrelated sibling check
// bundled into the same Promise.all, or a transient D1 write failure after the push already
// went out — used to cause Cloudflare to re-run the same tick a couple minutes later, re-detect
// the same "new" item against the not-yet-updated state, and re-push it. This repeated up to
// Cloudflare's retry limit: identical notifications, a few minutes apart, on every device.
// Swallowing (and logging) the error here instead means one tick's genuine failure just gets
// picked up cleanly by the *next* naturally-scheduled tick, not by Cloudflare re-running this
// one — which is what actually made the double/triple-push possible.
async function runCheck(label, promise) {
  try {
    return await promise;
  } catch (err) {
    console.error(`${label} failed:`, err);
    return { ok: false, error: String(err) };
  }
}

export default {
  // Two independent cron triggers fire this (see wrangler.toml): "*/15 * * * *" also matches
  // every "* * * * *" tick, so Cloudflare invokes scheduled() once per matching expression —
  // routing on event.cron keeps the Wowhead check from also running (and double-fetching) on
  // the every-minute trigger.
  async scheduled(event, env, ctx) {
    if (event.cron === "*/15 * * * *") {
      ctx.waitUntil(Promise.all([
        runCheck("checkWowheadNews", checkWowheadNews(env)),
        runCheck("prunePullVelocitySnapshots", prunePullVelocitySnapshots(env)),
      ]));
      return;
    }
    ctx.waitUntil(Promise.all([
      runCheck("checkForNewPosts", checkForNewPosts(env)),
      runCheck("checkRaiderIOEvents", checkRaiderIOEvents(env)),
    ]));
  },

  async fetch(request, env) {
    const url = new URL(request.url);

    if (request.method === "POST" && url.pathname === "/register") {
      const body = await request.json().catch(() => null);
      if (!body || typeof body.deviceToken !== "string" || !DEVICE_TOKEN_PATTERN.test(body.deviceToken)) {
        return new Response("Invalid deviceToken", { status: 400 });
      }
      const added = await addDevice(env, body.deviceToken, {
        raiderioEnabled: body.raiderioEnabled,
        wowheadEnabled: body.wowheadEnabled,
        spoilerFreeEnabled: body.spoilerFreeEnabled,
        heartbreakThresholdPercent: body.heartbreakThresholdPercent,
        notifyNonWorldFirstHeartbreaks: body.notifyNonWorldFirstHeartbreaks,
      });
      if (!added) return new Response("Too many registered devices", { status: 429 });
      return new Response("OK");
    }

    // Registers/unregisters the push-to-update token for the race Live Activity (see
    // RaceLiveActivityController.swift) — a different token from /register's regular device
    // token, even though both happen to be 64-hex-char APNs tokens.
    if (request.method === "POST" && url.pathname === "/live-activity/register") {
      const body = await request.json().catch(() => null);
      if (!body || typeof body.pushToken !== "string" || !DEVICE_TOKEN_PATTERN.test(body.pushToken)) {
        return new Response("Invalid pushToken", { status: 400 });
      }
      const existing = await env.DB.prepare("SELECT 1 FROM live_activity_tokens WHERE push_token = ?")
        .bind(body.pushToken)
        .first();
      if (!existing) {
        const countRow = await env.DB.prepare("SELECT COUNT(*) as count FROM live_activity_tokens").first();
        if (countRow.count >= MAX_LIVE_ACTIVITIES) return new Response("Too many live activities", { status: 429 });
      }
      await env.DB.prepare("INSERT INTO live_activity_tokens (push_token) VALUES (?) ON CONFLICT(push_token) DO NOTHING")
        .bind(body.pushToken)
        .run();
      return new Response("OK");
    }

    if (request.method === "POST" && url.pathname === "/live-activity/unregister") {
      const body = await request.json().catch(() => null);
      if (!body || typeof body.pushToken !== "string") {
        return new Response("Invalid pushToken", { status: 400 });
      }
      await env.DB.prepare("DELETE FROM live_activity_tokens WHERE push_token = ?").bind(body.pushToken).run();
      return new Response("OK");
    }

    // Read-only, unauthenticated — same posture as the rest of this app: it's a thin derived
    // view over raider.io's own public pull data (guild id, boss slug, a past percent/pull
    // count), not anything sensitive. See getVelocitySnapshots for the response shape.
    if (request.method === "GET" && url.pathname === "/velocity") {
      const snapshots = await getVelocitySnapshots(env);
      return new Response(JSON.stringify(snapshots), { headers: { "content-type": "application/json" } });
    }

    if (request.method === "GET" && url.pathname === "/check") {
      if (!isAuthorized(request, env)) return new Response("Unauthorized", { status: 401 });
      const [posts, raiderioEvents, wowheadNews] = await Promise.all([
        checkForNewPosts(env),
        checkRaiderIOEvents(env),
        checkWowheadNews(env),
      ]);
      return new Response(JSON.stringify({ posts, raiderioEvents, wowheadNews }), {
        headers: { "content-type": "application/json" },
      });
    }

    if (request.method === "GET" && url.pathname === "/test-push") {
      if (!isAuthorized(request, env)) return new Response("Unauthorized", { status: 401 });
      const devices = await getDevices(env);
      const results = [];
      for (const device of devices) {
        const result = await sendPush(
          env,
          device.token,
          "Test push",
          "If you see this, push delivery works.",
          `test-${Date.now()}`
        );
        results.push({ token: device.token, ...result });
      }
      return new Response(JSON.stringify({ deviceCount: devices.length, results }, null, 2), {
        headers: { "content-type": "application/json" },
      });
    }

    return new Response("Not found", { status: 404 });
  },
};

// A header, not a `?secret=` query param — query strings end up in Cloudflare's request logs
// and browser history verbatim, which a bearer-style header avoids.
function isAuthorized(request, env) {
  const provided = request.headers.get("X-Admin-Secret");
  return typeof env.ADMIN_SECRET === "string" && env.ADMIN_SECRET.length > 0 && provided === env.ADMIN_SECRET;
}

async function checkForNewPosts(env) {
  const resp = await fetch(
    `https://raider.io/api/threads/list?slug=${FEED_SLUG}`
  );
  if (!resp.ok) {
    return { ok: false, status: resp.status };
  }
  const data = await resp.json();
  const posts = (data.posts || []).filter((p) => !p.deleted_at && p.content);
  if (posts.length === 0) {
    return { ok: true, newPosts: 0 };
  }

  const maxId = posts.reduce((m, p) => Math.max(m, p.id), 0);
  const lastSeenRaw = await getCronState(env, LAST_SEEN_KEY);

  if (lastSeenRaw === null) {
    // First run ever: just record the baseline so we don't blast a notification for every post
    // already in the feed's backlog. ON CONFLICT DO NOTHING rather than an unconditional write
    // so a concurrent first run (cron racing a manual /check) can't both think they're the one
    // setting the baseline and both fall through to treating some later tick's posts as new.
    await env.DB.prepare("INSERT INTO cron_state (key, value) VALUES (?, ?) ON CONFLICT(key) DO NOTHING")
      .bind(LAST_SEEN_KEY, String(maxId))
      .run();
    return { ok: true, newPosts: 0, baseline: maxId };
  }

  const lastSeen = parseInt(lastSeenRaw, 10);
  const newPosts = posts
    .filter((p) => p.id > lastSeen)
    .sort((a, b) => new Date(a.published_at) - new Date(b.published_at));

  if (newPosts.length > 0) {
    // Compare-and-swap claim, not a read-then-later-write: this cron overlapping a manual
    // /check (or two overlapping cron ticks) could otherwise both read the same lastSeenRaw
    // above before either writes back, and both push the same "new" post — apns-collapse-id
    // only replaces a still-undelivered/undismissed notification with the same ID, so a user
    // who already saw and dismissed the first copy gets a second one. The UPDATE below only
    // succeeds if `value` still matches the exact lastSeenRaw this invocation read, so only one
    // concurrent invocation can ever win the claim for a given lastSeen; the loser skips pushing
    // entirely, since the winner is (or already has) pushed for these same posts. Same TOCTOU
    // class closed for RACE_COMPLETE_KEY and HEARTBREAK_BEST_KEY — this was the one spot left
    // that wasn't, and matches a "Venomous Abyss" feed post landing on the device more than once.
    const claim = await env.DB.prepare("UPDATE cron_state SET value = ? WHERE key = ? AND value = ?")
      .bind(String(maxId), LAST_SEEN_KEY, lastSeenRaw)
      .run();
    if (claim.meta.changes === 0) return { ok: true, newPosts: 0, skipped: "claim lost" };

    const devices = (await getDevices(env)).filter((d) => d.raiderioEnabled);
    for (const post of newPosts) {
      const title = "Venomous Abyss";
      // Coverage posts routinely announce kills in the first sentence ("Method one-shots
      // Mythic Ula'tek!") — spoilerFreeEnabled only redacted World First pushes until now,
      // which meant a spoiler-free user got the kill spoiled here first anyway.
      // raider.io's contentPreview isn't guaranteed clean plain text — seen a literal tab
      // character embedded mid-sentence ("...23.49%\tafter 7 pulls!"), which renders as a
      // large, broken-looking gap in a notification banner. Collapse any whitespace run to a
      // single space rather than trusting the source.
      const body = normalizeWhitespace(post.contentPreview) || "New update";
      const spoilerFreeBody = "New coverage update — open the app when you're ready to see it.";
      for (const device of devices) {
        await sendPush(env, device.token, title, device.spoilerFreeEnabled ? spoilerFreeBody : body, `post-${post.id}`, "feed");
      }
    }
  }
  return { ok: true, newPosts: newPosts.length };
}

/// Fetches raid-race (for boss names) and raid-rankings (for live pull/defeat data) once and
/// runs both the heartbreak and world-first checks against it — they'd otherwise each need
/// the same two fetches every minute.
async function checkRaiderIOEvents(env) {
  const devices = (await getDevices(env)).filter((d) => d.raiderioEnabled);
  const liveActivityTokens = await getLiveActivityTokens(env);
  // Live Activities are a separate registry from push devices — someone could in principle
  // have one running without any raiderioEnabled device (unlikely in practice, since app
  // launch always tries to register a device token too, but cheap to handle correctly rather
  // than silently skipping their updates).
  if (devices.length === 0 && liveActivityTokens.length === 0) return { ok: true, watchedDevices: 0 };

  const [raceResp, rankResp] = await Promise.all([
    fetch(`https://raider.io/api/raids/raid-race?raid=${RAID_SLUG}&region=world&difficulty=mythic`),
    fetch(`https://raider.io/api/v1/raiding/raid-rankings?raid=${RAID_SLUG}&difficulty=mythic&region=world`),
  ]);
  if (!raceResp.ok) return { ok: false, status: raceResp.status };
  if (!rankResp.ok) return { ok: false, status: rankResp.status };

  const raceData = await raceResp.json();
  const encounterBySlug = {};
  for (const encounter of raceData.worldFirstTracker?.raid?.encounters || []) {
    encounterBySlug[encounter.slug] = encounter;
  }

  const rankData = await rankResp.json();
  const rankings = rankData.raidRankings || [];

  const [heartbreaks, worldFirsts, liveActivity, raceComplete] = await Promise.all([
    checkHeartbreaks(env, rankings, encounterBySlug, devices),
    checkWorldFirstKills(env, rankings, encounterBySlug, devices),
    checkLiveActivity(env, rankings, encounterBySlug, liveActivityTokens),
    checkRaceComplete(env, rankings, encounterBySlug, devices),
  ]);
  // Not part of the Promise.all above deliberately — a slow/failed snapshot write shouldn't be
  // able to delay or fail the push-notification-critical checks it's racing alongside.
  await snapshotPullVelocity(env, rankings).catch(() => {});

  return { ok: true, watchedDevices: devices.length, heartbreaks, worldFirsts, liveActivity, raceComplete };
}

/// "Major Heartbreaker" pushes: a guild pulling a boss down to a new-record-low remaining
/// health%, the same close-call signal as the app's Heartbreak tab, but pushed the moment it
/// happens instead of requiring the tab to be open. "New record" tracking itself is threshold-
/// agnostic (see below) — each device applies its own heartbreakThresholdPercent and
/// notifyNonWorldFirstHeartbreaks preference independently at push time, since two devices can
/// disagree on both.
///
/// Only pushes on a new record (this guild's lowest-ever percent on this boss) so a guild
/// stuck wiping around the same percent for an hour doesn't get a push every single minute.
async function checkHeartbreaks(env, rankings, encounterBySlug, devices) {
  // A boss stops being part of the title race the moment any guild claims it, even for a
  // guild that personally hasn't killed it yet — used below to gate devices that only want
  // genuine title-race close calls (notifyNonWorldFirstHeartbreaks === false).
  const claimedSlugs = new Set();
  for (const entry of rankings) {
    for (const defeat of entry.encountersDefeated || []) claimedSlugs.add(defeat.slug);
  }

  await migrateHeartbreakBestKey(env);

  // Computed once per tick, same as the old single-blob isFirstRun flag: true only for the very
  // first invocation ever (no legacy blob to migrate, no per-(guild,boss) rows yet).
  const initialized = await env.DB.prepare(
    "SELECT 1 FROM cron_state WHERE key LIKE ? LIMIT 1"
  )
    .bind(HEARTBREAK_BEST_PREFIX + "%")
    .first();

  let pushCount = 0;
  for (const entry of rankings) {
    for (const pull of entry.encountersPulled || []) {
      if (pull.isDefeated) continue;
      if (typeof pull.bestPercent !== "number") continue;

      const key = `${entry.guild.id}-${pull.slug}`;
      const stateKey = HEARTBREAK_BEST_PREFIX + key;

      if (!initialized) {
        // First run ever: record the baseline (so re-notifying doesn't depend on someone
        // happening to improve past a pull we never saw) without pushing for every close call
        // already in progress the moment this ships. Record-tracking itself isn't gated by any
        // threshold — it has to stay threshold-agnostic so it means the same thing regardless of
        // which device's threshold ends up applying at push time below.
        await env.DB.prepare(
          "INSERT INTO cron_state (key, value) VALUES (?, ?) ON CONFLICT(key) DO NOTHING"
        )
          .bind(stateKey, String(pull.bestPercent))
          .run();
        continue;
      }

      // Atomic claim, not a read-then-later-write: the UPSERT's DO UPDATE only fires when this
      // pull's bestPercent is still strictly lower than whatever's currently stored for this
      // (guild, boss) at the moment this single statement runs, so an overlapping cron tick or a
      // manual /check racing the cron can't both read the same "not yet recorded" state and both
      // push. Same TOCTOU class closed for RACE_COMPLETE_KEY above (see checkRaceComplete),
      // closed here the same way — this used to be the one spot that wasn't, and was the
      // repeatable double/triple-send source for "Major Heartbreaker" pushes.
      const claim = await env.DB.prepare(
        `INSERT INTO cron_state (key, value) VALUES (?, ?)
         ON CONFLICT(key) DO UPDATE SET value = excluded.value
         WHERE CAST(cron_state.value AS REAL) > CAST(excluded.value AS REAL)`
      )
        .bind(stateKey, String(pull.bestPercent))
        .run();

      if (claim.meta.changes === 0) continue;

      const isWorldFirstRace = !claimedSlugs.has(pull.slug);
      const bossName = encounterBySlug[pull.slug]?.name ?? pull.slug;
      for (const device of devices) {
        const threshold =
          typeof device.heartbreakThresholdPercent === "number" && device.heartbreakThresholdPercent > 0
            ? device.heartbreakThresholdPercent
            : HEARTBREAK_DEFAULT_THRESHOLD_PERCENT;
        if (pull.bestPercent >= threshold) continue;
        if (!isWorldFirstRace && !device.notifyNonWorldFirstHeartbreaks) continue;

        await sendPush(
          env,
          device.token,
          "Major Heartbreaker",
          `${entry.guild.displayName} wipes on ${bossName} at ${pull.bestPercent.toFixed(2)}%`,
          `heartbreak-${key}-${Math.round(pull.bestPercent * 100)}`,
          "heartbreak"
        );
        pushCount++;
      }
    }
  }

  return { pushCount };
}

/// One-time migration off the legacy single-JSON-blob HEARTBREAK_BEST_KEY. That blob required a
/// read-the-whole-map-then-write-it-back-later cycle to update any single (guild, boss) entry —
/// exactly the TOCTOU gap closed for RACE_COMPLETE_KEY, but never closed here — so it's replaced
/// with one row per (guild, boss) under HEARTBREAK_BEST_PREFIX, each updatable by its own atomic
/// UPSERT. Safe to call every tick: once the blob is gone this is a single cheap read that finds
/// nothing to do, and a concurrent invocation racing this same migration just re-seeds the same
/// rows (ON CONFLICT DO NOTHING makes that a no-op).
async function migrateHeartbreakBestKey(env) {
  const legacyRaw = await getCronState(env, HEARTBREAK_BEST_KEY);
  if (legacyRaw === null) return;

  const legacy = JSON.parse(legacyRaw);
  for (const [key, percent] of Object.entries(legacy)) {
    await env.DB.prepare(
      "INSERT INTO cron_state (key, value) VALUES (?, ?) ON CONFLICT(key) DO NOTHING"
    )
      .bind(HEARTBREAK_BEST_PREFIX + key, String(percent))
      .run();
  }
  await env.DB.prepare("DELETE FROM cron_state WHERE key = ?").bind(HEARTBREAK_BEST_KEY).run();
}

/// "World First!" pushes — the first guild to defeat each boss, from the same
/// encountersDefeated data checkHeartbreaks already builds claimedSlugs from. For devices
/// with spoilerFreeEnabled set, the guild/boss are redacted to a generic "Spoiler Alert" so
/// players avoiding spoilers still know something happened without seeing who/what.
async function checkWorldFirstKills(env, rankings, encounterBySlug, devices) {
  const claimedNow = new Map();
  for (const entry of rankings) {
    for (const defeat of entry.encountersDefeated || []) {
      const existing = claimedNow.get(defeat.slug);
      if (!existing || new Date(defeat.firstDefeated) < new Date(existing.firstDefeated)) {
        claimedNow.set(defeat.slug, { guildName: entry.guild.displayName, firstDefeated: defeat.firstDefeated });
      }
    }
  }

  const seenRaw = await getCronState(env, WORLD_FIRST_SEEN_KEY);
  const isFirstRun = seenRaw === null;
  const seen = isFirstRun ? {} : JSON.parse(seenRaw);
  const nextSeen = { ...seen };
  let changed = false;

  let pushCount = 0;
  for (const [slug, claim] of claimedNow) {
    if (seen[slug]) continue;
    nextSeen[slug] = true;
    changed = true;
    // First run ever: record the baseline (bosses already killed before this shipped)
    // without pushing for every one of them at once.
    if (isFirstRun) continue;

    const bossName = encounterBySlug[slug]?.name ?? slug;
    for (const device of devices) {
      const spoilerFree = device.spoilerFreeEnabled === true;
      const title = spoilerFree ? "Spoiler Alert" : "World First!";
      const body = spoilerFree
        ? "A boss has fallen for the first time. Open the app when you're ready to see who."
        : `${claim.guildName} claims World First on ${bossName}!`;
      await sendPush(env, device.token, title, body, `worldfirst-${slug}`, "kills");
      pushCount++;
    }
  }

  // Same reasoning as HEARTBREAK_BEST_KEY above — only write when a boss was newly claimed.
  if (changed) await setCronState(env, WORLD_FIRST_SEEN_KEY, JSON.stringify(nextSeen));
  return { pushCount };
}

/// A distinct, one-time push once the world's leading guild (most confirmed kills, same
/// invariant used everywhere else in this file) has defeated every boss in the raid — separate
/// from the ordinary per-boss World First push in checkWorldFirstKills above, which already
/// covers the final boss's own kill but doesn't call out that the *entire race* just ended.
/// RACE_COMPLETE_KEY guards against re-sending on every subsequent tick once the race is over
/// (it never resets — a new raid tier needs RAID_SLUG updated anyway, same existing constraint
/// as the rest of this file).
async function checkRaceComplete(env, rankings, encounterBySlug, devices) {
  const totalBosses = Object.keys(encounterBySlug).length;
  // Below the known real boss count, not just 0: raid-race is fetched fresh every tick with no
  // retry (see the scheduled() call site), so a transient/partial 200 response that omits one
  // boss would otherwise understate totalBosses for that single tick — and if the leader's
  // confirmed kill count already met that understated total, this would fire the one-time,
  // unrecoverable "Race Complete" push on a false positive (RACE_COMPLETE_KEY never resets, so
  // there's no self-correction next tick). Requiring the known-good count means a partial
  // response just gets treated the same as "race not complete" and retried next tick instead.
  if (totalBosses < RAID_BOSS_COUNT) return { ok: true, skipped: "no encounters" };

  const leader = rankings.reduce((best, entry) => {
    return !best || entry.encountersDefeated.length > best.encountersDefeated.length ? entry : best;
  }, null);
  if (!leader || leader.encountersDefeated.length < totalBosses) return { ok: true, skipped: "race not complete" };

  // Two-phase claim rather than a plain read-then-later-write: a bare read here (the previous
  // version of this check) has a real TOCTOU gap — a scheduled cron tick and a manually
  // triggered /check could both read "not yet announced" before either writes back, and both
  // send the push. apns-collapse-id doesn't fully cover this (see the comment on
  // LAST_SEEN_KEY's own version of this race, near checkForNewPosts): it only replaces a
  // still-undelivered notification, so a user who already dismissed the first copy sees a
  // second one. `claimed` first, atomically, via D1's own uniqueness constraint on `key` —
  // only one concurrent caller can ever get `meta.changes > 0` back — closes that gap
  // completely, without reintroducing the *other* failure mode this function used to have
  // (writing the flag before sending, which stranded every device after a mid-loop Worker
  // interruption with no retry — see STALE_CLAIM_MS below for how this version still recovers
  // from that).
  const claim = await env.DB.prepare(
    "INSERT INTO cron_state (key, value) VALUES (?, ?) ON CONFLICT(key) DO NOTHING"
  )
    .bind(RACE_COMPLETE_KEY, JSON.stringify({ status: "claimed", claimedAt: Date.now() }))
    .run();

  if (claim.meta.changes === 0) {
    const existing = JSON.parse(await getCronState(env, RACE_COMPLETE_KEY));
    if (existing.status === "completed") return { ok: true, skipped: "already announced" };
    // status is "claimed" by someone — either a concurrent invocation genuinely still in
    // flight (let it finish; this tick just backs off) or a past invocation that crashed
    // mid-send and never got to write "completed" (self-heal by reclaiming, since nothing else
    // ever will). STALE_CLAIM_MS is generous relative to how long a single tick's device loop
    // can plausibly take, so a live invocation is never mistaken for a stale one.
    if (Date.now() - (existing.claimedAt ?? 0) < STALE_CLAIM_MS) {
      return { ok: true, skipped: "claim in progress" };
    }
    await setCronState(env, RACE_COMPLETE_KEY, JSON.stringify({ status: "claimed", claimedAt: Date.now() }));
  }

  let pushCount = 0;
  for (const device of devices) {
    const spoilerFree = device.spoilerFreeEnabled === true;
    const title = spoilerFree ? "Spoiler Alert" : "🏆 Race Complete!";
    const body = spoilerFree
      ? "The Race to World First has ended. Open the app when you're ready to see who won."
      : `${leader.guild.displayName} wins the Race to World First!`;
    await sendPush(env, device.token, title, body, "race-complete", "bosses");
    pushCount++;
  }
  await setCronState(env, RACE_COMPLETE_KEY, JSON.stringify({
    status: "completed", winner: leader.guild.displayName, announcedAt: new Date().toISOString(),
  }));
  return { ok: true, raceComplete: true, winner: leader.guild.displayName, pushCount };
}

// How often (at minimum) a fresh snapshot is written per (guild, boss) pair even when the
// percent hasn't moved — the client needs *some* datapoint reliably older than an hour to show
// a trend against, not just one whenever progress happens to change. Written far more often
// than PULL_VELOCITY_LOOKBACK_MINUTES needs, since a pull that's genuinely stalled should still
// produce a "0% change" datapoint rather than silently having no history.
const PULL_VELOCITY_MIN_SNAPSHOT_INTERVAL_MINUTES = 10;
const PULL_VELOCITY_LOOKBACK_MINUTES = 60;
// Kept well beyond the lookback window (with margin for a delayed prune tick) rather than right
// at it, so a temporarily-slow prune cycle can never eat into data /velocity is actively using.
const PULL_VELOCITY_RETENTION_HOURS = 25;

/// One row per (guild, boss) with an active, undefeated pull — written at most once every
/// PULL_VELOCITY_MIN_SNAPSHOT_INTERVAL_MINUTES per pair, or immediately if the percent actually
/// changed since the last snapshot for that pair (same "only write on real change" discipline
/// as the rest of this file, loosened slightly here since "no change in N minutes" is itself
/// meaningful information for a stalled-pull indicator, not just noise to skip).
async function snapshotPullVelocity(env, rankings) {
  const now = new Date();
  const cutoff = new Date(now.getTime() - PULL_VELOCITY_MIN_SNAPSHOT_INTERVAL_MINUTES * 60 * 1000).toISOString();

  const activePulls = [];
  for (const entry of rankings) {
    for (const pull of entry.encountersPulled || []) {
      if (pull.isDefeated) continue;
      if (typeof pull.bestPercent !== "number" || typeof pull.numPulls !== "number") continue;
      activePulls.push({ guildId: entry.guild.id, bossSlug: pull.slug, percent: pull.bestPercent, pulls: pull.numPulls });
    }
  }
  if (activePulls.length === 0) return { ok: true, snapshotted: 0 };

  let snapshotted = 0;
  for (const pull of activePulls) {
    const last = await env.DB.prepare(
      "SELECT best_percent, recorded_at FROM pull_velocity_snapshots WHERE guild_id = ? AND boss_slug = ? ORDER BY recorded_at DESC LIMIT 1"
    )
      .bind(pull.guildId, pull.bossSlug)
      .first();
    const changed = !last || last.best_percent !== pull.percent;
    const dueForFreshSnapshot = !last || last.recorded_at < cutoff;
    if (!changed && !dueForFreshSnapshot) continue;

    await env.DB.prepare(
      "INSERT OR REPLACE INTO pull_velocity_snapshots (guild_id, boss_slug, best_percent, num_pulls, recorded_at) VALUES (?, ?, ?, ?, ?)"
    )
      .bind(pull.guildId, pull.bossSlug, pull.percent, pull.pulls, now.toISOString())
      .run();
    snapshotted++;
  }
  return { ok: true, snapshotted };
}

async function prunePullVelocitySnapshots(env) {
  const cutoff = new Date(Date.now() - PULL_VELOCITY_RETENTION_HOURS * 60 * 60 * 1000).toISOString();
  const result = await env.DB.prepare("DELETE FROM pull_velocity_snapshots WHERE recorded_at < ?").bind(cutoff).run();
  return { ok: true, pruned: result.meta?.changes ?? 0 };
}

/// The closest snapshot to PULL_VELOCITY_LOOKBACK_MINUTES ago, per (guild, boss) pair, for every
/// pair with at least one snapshot that old. The client already has the *current* percent from
/// its own raid-rankings fetch, so this only needs to return the past datapoint — the delta is
/// computed client-side, keeping this endpoint a plain read with no derived-data drift risk.
/// SQLite (which D1 is) guarantees that a bare column alongside a single MAX()/MIN() aggregate,
/// under the same GROUP BY, comes from the row that produced that aggregate — this is
/// documented SQLite behavior, not the ambiguous "arbitrary row" semantics other databases have
/// for the same pattern.
async function getVelocitySnapshots(env) {
  const cutoff = new Date(Date.now() - PULL_VELOCITY_LOOKBACK_MINUTES * 60 * 1000).toISOString();
  const { results } = await env.DB.prepare(
    `SELECT guild_id, boss_slug, best_percent, num_pulls, MAX(recorded_at) as recorded_at
     FROM pull_velocity_snapshots
     WHERE recorded_at <= ?
     GROUP BY guild_id, boss_slug`
  )
    .bind(cutoff)
    .all();
  return results.map((r) => ({
    guildId: r.guild_id,
    bossSlug: r.boss_slug,
    percent: r.best_percent,
    pulls: r.num_pulls,
    recordedAt: r.recorded_at,
  }));
}

/// Keeps every registered race Live Activity in sync with the true global leader's (most
/// confirmed kills, ignoring nothing regional — see client-side leaderNextBossSummary's own
/// comment for why) own next undefeated boss and the best live pull on it. Same "leader's
/// frontier" definition the watchOS app and Home Screen widget use, computed a third time here
/// in JS rather than shared — this Worker and the Swift targets are different languages
/// entirely, unlike RaceLiveActivityAttributes, which genuinely can be one shared Swift file.
///
/// Sends an "end" event (with the old boss's final numbers) the moment the tracked boss
/// changes — the leader killed it — rather than silently morphing the activity into the next
/// boss; the user starts a fresh one from Settings for that. Sends an "update" event only when
/// the content actually changed since last tick, not on every single cron minute. Once the
/// leader has cleared every boss, sends one final "Race Complete" end event instead (see the
/// `!nextSlug` branch below) rather than leaving activities frozen until the OS's 8-hour
/// Live Activity timeout.
async function checkLiveActivity(env, rankings, encounterBySlug, tokens) {
  if (tokens.length === 0) return { ok: true, skipped: "no registered activities" };

  const leader = rankings.reduce((best, entry) => {
    return !best || entry.encountersDefeated.length > best.encountersDefeated.length ? entry : best;
  }, null);
  if (!leader) return { ok: true, skipped: "no leader" };

  const defeatedByLeader = new Set(leader.encountersDefeated.map((d) => d.slug));
  const orderedSlugs = Object.keys(encounterBySlug).sort(
    (a, b) => encounterBySlug[a].ordinal - encounterBySlug[b].ordinal
  );
  const nextSlug = orderedSlugs.find((slug) => !defeatedByLeader.has(slug));

  // The leader has cleared every boss — the race is over. Send every currently-registered
  // activity one final "Race Complete" update via the existing end-and-clean-up path (same one
  // used for a normal boss transition) rather than leaving them frozen on the second-to-last
  // boss's state until the OS's own 8-hour Live Activity timeout. A device that registers
  // *after* this point (a fresh Start tap once the tokens table is empty again) naturally gets
  // the same finale on its next tick — correct, since the race really is over.
  if (!nextSlug) {
    const finalContentState = {
      bossName: encounterBySlug[orderedSlugs[orderedSlugs.length - 1]]?.name ?? "Race Complete",
      bossOrdinal: orderedSlugs.length,
      totalBosses: orderedSlugs.length,
      bossIconData: null,
      bestGuildName: null,
      bestPercent: null,
      pullCount: null,
      isRaceComplete: true,
      winningGuildName: leader.guild.displayName,
    };
    await endAllLiveActivities(env, tokens, finalContentState);
    return { ok: true, raceComplete: true, winner: leader.guild.displayName };
  }

  const boss = encounterBySlug[nextSlug];
  let best = null;
  for (const entry of rankings) {
    const pull = entry.encountersPulled.find((p) => p.slug === nextSlug && !p.isDefeated);
    if (!pull || typeof pull.bestPercent !== "number" || typeof pull.numPulls !== "number") continue;
    if (!best || pull.bestPercent < best.percent) {
      best = { guild: entry.guild.displayName, percent: pull.bestPercent, pullCount: pull.numPulls };
    }
  }

  const previousRaw = await getCronState(env, LIVE_ACTIVITY_STATE_KEY);
  const previous = previousRaw ? JSON.parse(previousRaw) : null;

  // The icon only ever changes when the boss itself does — reuse the last fetch instead of
  // re-downloading the same ~1KB image on every cron tick. Sent as raw base64 bytes rather than
  // a URL because the widget extension can't reliably load images over the network on its own
  // (same reason the Home Screen widget pre-fetches icon bytes — see WidgetData.swift).
  const bossIconData =
    previous && previous.bossSlug === nextSlug && previous.contentState.bossIconData
      ? previous.contentState.bossIconData
      : await fetchBossIconBase64(boss.iconUrl);

  const contentState = {
    bossName: boss.name,
    bossOrdinal: boss.ordinal + 1,
    totalBosses: Object.keys(encounterBySlug).length,
    bossIconData,
    bestGuildName: best?.guild ?? null,
    bestPercent: best?.percent ?? null,
    pullCount: best?.pullCount ?? null,
  };

  if (previous && previous.bossSlug !== nextSlug) {
    await endAllLiveActivities(env, tokens, previous.contentState);
    await setCronState(env, LIVE_ACTIVITY_STATE_KEY, JSON.stringify({ bossSlug: nextSlug, contentState }));
    return { ok: true, ended: previous.bossSlug, nowTracking: nextSlug };
  }

  if (previous && JSON.stringify(previous.contentState) === JSON.stringify(contentState)) {
    return { ok: true, unchanged: true };
  }

  await setCronState(env, LIVE_ACTIVITY_STATE_KEY, JSON.stringify({ bossSlug: nextSlug, contentState }));
  for (const token of tokens) {
    await sendLiveActivityPush(env, token, "update", contentState);
  }
  return { ok: true, updated: nextSlug };
}

// The "medium" CDN icon variant (36x36, ~1.7KB) rather than the "large" one the app itself uses
// (56x56, ~2.7KB) — APNs caps a Live Activity push payload around 4KB total, and this field has
// to share that budget with the rest of contentState. ("small" at 18x18 fits with room to
// spare but renders visibly blurry once scaled back up in the Lock Screen UI.)
async function fetchBossIconBase64(iconUrlPath) {
  if (!iconUrlPath) return null;
  const mediumPath = iconUrlPath.replace("/icons/large/", "/icons/medium/");
  try {
    const resp = await fetch(`https://cdn.raiderio.net${mediumPath}`);
    if (!resp.ok) return null;
    const bytes = new Uint8Array(await resp.arrayBuffer());
    let binary = "";
    const chunkSize = 0x8000;
    for (let i = 0; i < bytes.length; i += chunkSize) {
      binary += String.fromCharCode.apply(null, bytes.subarray(i, i + chunkSize));
    }
    return btoa(binary);
  } catch (e) {
    return null;
  }
}

async function getLiveActivityTokens(env) {
  const { results } = await env.DB.prepare("SELECT push_token FROM live_activity_tokens").all();
  return results.map((r) => r.push_token);
}

async function endAllLiveActivities(env, tokens, finalContentState) {
  for (const token of tokens) {
    await sendLiveActivityPush(env, token, "end", finalContentState);
  }
  // Only remove the tokens we actually just told to end — not the whole table. A device
  // calling /live-activity/register mid-tick (after `tokens` above was already read from D1,
  // e.g. while the two raider.io fetches earlier in checkRaiderIOEvents were in flight) would
  // otherwise be silently deleted here despite never having been sent an "end" push (or any
  // push at all), leaving its Live Activity stuck with no way to update short of the user
  // manually restarting it from Settings. sendLiveActivityPush above already removes any of
  // these tokens on a 410/BadDeviceToken, so this only catches the ones delivered successfully.
  for (const token of tokens) {
    await env.DB.prepare("DELETE FROM live_activity_tokens WHERE push_token = ?").bind(token).run();
  }
}

/// A Live Activity push is a silent content update, not a user-visible notification — no
/// alert/sound/badge, and a different push type/topic suffix from sendPush's regular alerts.
async function sendLiveActivityPush(env, pushToken, event, contentState) {
  let res;
  try {
    const jwt = await getApnsJwt(env);
    const apnsHost =
      (env.APNS_ENV || "sandbox") === "production"
        ? "https://api.push.apple.com"
        : "https://api.sandbox.push.apple.com";

    res = await fetch(`${apnsHost}/3/device/${pushToken}`, {
      method: "POST",
      headers: {
        authorization: `bearer ${jwt}`,
        "apns-topic": `${env.APNS_BUNDLE_ID}.push-type.liveactivity`,
        "apns-push-type": "liveactivity",
        "apns-priority": "10",
      },
      body: JSON.stringify({
        aps: {
          timestamp: Math.floor(Date.now() / 1000),
          event,
          "content-state": contentState,
          ...(event === "end" ? { "dismissal-date": Math.floor(Date.now() / 1000) + 60 } : {}),
        },
      }),
    });
  } catch (error) {
    console.log("Live Activity push failed", pushToken, error);
    return;
  }

  if (!res.ok) {
    const text = await res.text();
    console.log("Live Activity push error", pushToken, res.status, text);
    if (res.status === 410 || text.includes("BadDeviceToken")) {
      await env.DB.prepare("DELETE FROM live_activity_tokens WHERE push_token = ?").bind(pushToken).run();
    }
  }
}

/// New WoW news pushes — Wowhead's public "retail" RSS feed (WoW only, no Diablo/other-game
/// articles). Diffed by pubDate against the newest article seen last run, same shape as
/// checkForNewPosts. Regex-parsed rather than pulling in an XML library for a handful of
/// fields (title/guid/pubDate) out of a feed whose structure is stable and simple.
async function checkWowheadNews(env) {
  const resp = await fetch(WOWHEAD_NEWS_URL);
  if (!resp.ok) return { ok: false, status: resp.status };
  const xml = await resp.text();

  const items = [];
  const itemRegex = /<item>([\s\S]*?)<\/item>/g;
  let match;
  while ((match = itemRegex.exec(xml)) !== null) {
    const block = match[1];
    const title = decodeXmlEntities(extractXmlTag(block, "title"));
    const guid = extractXmlTag(block, "guid") || extractXmlTag(block, "link");
    const pubDateRaw = extractXmlTag(block, "pubDate");
    const pubDate = pubDateRaw ? new Date(pubDateRaw) : null;
    if (title && guid && pubDate && !isNaN(pubDate.getTime())) {
      items.push({ title, guid, pubDate });
    }
  }
  if (items.length === 0) return { ok: true, newArticles: 0 };

  items.sort((a, b) => b.pubDate - a.pubDate);
  const newest = items[0];

  const lastSeenRaw = await getCronState(env, WOWHEAD_LAST_SEEN_KEY);
  if (lastSeenRaw === null) {
    // First run ever: record the baseline so we don't blast a notification for every
    // article already sitting in the feed's backlog.
    await setCronState(env, WOWHEAD_LAST_SEEN_KEY, newest.pubDate.toISOString());
    return { ok: true, newArticles: 0, baseline: newest.guid };
  }

  const lastSeenDate = new Date(lastSeenRaw);
  const newArticles = items.filter((item) => item.pubDate > lastSeenDate).sort((a, b) => a.pubDate - b.pubDate);

  if (newArticles.length > 0) {
    const devices = (await getDevices(env)).filter((d) => d.wowheadEnabled);
    for (const article of newArticles) {
      const collapseId = `wowhead-${article.guid.replace(/[^a-zA-Z0-9]/g, "").slice(-40)}`;
      for (const device of devices) {
        await sendPush(env, device.token, "WoW News", article.title, collapseId, "news");
      }
    }
    // Same reasoning as LAST_SEEN_KEY above — only write when the newest pubDate advanced.
    await setCronState(env, WOWHEAD_LAST_SEEN_KEY, newest.pubDate.toISOString());
  }
  return { ok: true, newArticles: newArticles.length };
}

function extractXmlTag(block, tag) {
  const re = new RegExp(`<${tag}[^>]*>([\\s\\S]*?)<\\/${tag}>`, "i");
  const m = block.match(re);
  return m ? m[1].trim() : null;
}

function decodeXmlEntities(str) {
  if (!str) return str;
  return str
    .replace(/<!\[CDATA\[([\s\S]*?)\]\]>/, "$1")
    .replace(/&amp;/g, "&")
    .replace(/&#39;/g, "'")
    .replace(/&quot;/g, '"')
    .replace(/&lt;/g, "<")
    .replace(/&gt;/g, ">");
}

// Collapses any run of whitespace (including tabs/newlines — raider.io's contentPreview has
// been seen with a literal tab embedded mid-sentence) into a single space, then inserts a
// space wherever sentence-ending punctuation is immediately followed by a capital letter with
// none — also seen for real ("...Sentinels!Congratulations Instant_Dollars...", genuinely no
// space in the source at all, not a whitespace-run problem this collapse alone would catch).
function normalizeWhitespace(str) {
  if (!str) return str;
  return str
    .replace(/\s+/g, " ")
    .replace(/([.!?])([A-Z])/g, "$1 $2")
    .trim();
}

// ---- APNs ----

// Module-level, so it's reused across invocations within the same warm Worker isolate —
// Apple throttles how often a provider token can be refreshed (TooManyProviderTokenUpdates),
// and minting a fresh one per push (N devices x M new posts, every minute) risked exactly
// that. Isolates aren't guaranteed to stay warm, so this is a best-effort cache, not a
// persistent one — but it cuts JWT generation by roughly two orders of magnitude in practice.
let cachedApnsJwt = null;
let cachedApnsJwtIssuedAt = 0;
const APNS_JWT_MAX_AGE_SECONDS = 50 * 60; // Apple allows up to ~60 min; refresh a bit early

async function getApnsJwt(env) {
  const now = Math.floor(Date.now() / 1000);
  if (cachedApnsJwt && now - cachedApnsJwtIssuedAt < APNS_JWT_MAX_AGE_SECONDS) {
    return cachedApnsJwt;
  }
  cachedApnsJwt = await makeApnsJwt(env);
  cachedApnsJwtIssuedAt = now;
  return cachedApnsJwt;
}

// Never throws — a rejected fetch (network error reaching APNs, not just a non-2xx
// response) used to propagate straight out of the caller's loop, skipping the
// lastSeenPostId/heartbreakBest state write that follows it and causing every "new" item to be
// re-sent to every device on the next cron tick. Callers get an {status, error} result for
// both failure modes instead, same as they already did for non-2xx.
async function sendPush(env, deviceToken, title, body, collapseId, tab) {
  let res;
  try {
    const jwt = await getApnsJwt(env);
    const apnsHost =
      (env.APNS_ENV || "sandbox") === "production"
        ? "https://api.push.apple.com"
        : "https://api.sandbox.push.apple.com";

    res = await fetch(`${apnsHost}/3/device/${deviceToken}`, {
      method: "POST",
      headers: {
        authorization: `bearer ${jwt}`,
        "apns-topic": env.APNS_BUNDLE_ID,
        "apns-push-type": "alert",
        "apns-priority": "10",
        "apns-collapse-id": collapseId,
      },
      // iOS only shows an app-icon badge when the payload explicitly requests one — we don't
      // track a real per-device unread count (nothing server-side knows what the user has
      // actually seen), so this always requests 1 rather than an incrementing number. The app
      // clears it back to 0 on foreground (see AppDelegate), so in practice it reads as "there's
      // something new" rather than a true count, which is the best we can do without adding
      // read-state tracking.
      // "tab" is a top-level custom field (outside aps, which APNs/iOS don't interpret) — the
      // app reads it on notification tap to open directly to the relevant tab instead of
      // whatever Default Tab happens to be set. See AppDelegate's didReceive response: and
      // AppTab's raw values, which this must match.
      body: JSON.stringify({ aps: { alert: { title, body }, sound: "default", badge: 1 }, tab }),
    });
  } catch (error) {
    console.log("APNs request failed", deviceToken, error);
    return { status: 0, error: String(error) };
  }

  if (res.ok) {
    return { status: res.status, apnsId: res.headers.get("apns-id") };
  }

  const text = await res.text();
  console.log("APNs error", deviceToken, res.status, text);
  if (res.status === 410 || text.includes("BadDeviceToken")) {
    await removeDevice(env, deviceToken);
  }
  return { status: res.status, error: text };
}

async function makeApnsJwt(env) {
  const header = { alg: "ES256", kid: env.APNS_KEY_ID };
  const payload = { iss: env.APNS_TEAM_ID, iat: Math.floor(Date.now() / 1000) };
  const unsigned = `${base64urlJSON(header)}.${base64urlJSON(payload)}`;

  const key = await importP8Key(env.APNS_PRIVATE_KEY);
  const signature = await crypto.subtle.sign(
    { name: "ECDSA", hash: "SHA-256" },
    key,
    new TextEncoder().encode(unsigned)
  );
  return `${unsigned}.${base64urlBytes(new Uint8Array(signature))}`;
}

async function importP8Key(pem) {
  const base64 = pem
    .replace("-----BEGIN PRIVATE KEY-----", "")
    .replace("-----END PRIVATE KEY-----", "")
    .replace(/\s+/g, "");
  const binary = Uint8Array.from(atob(base64), (c) => c.charCodeAt(0));
  return crypto.subtle.importKey(
    "pkcs8",
    binary.buffer,
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["sign"]
  );
}

function base64urlJSON(obj) {
  return base64urlBytes(new TextEncoder().encode(JSON.stringify(obj)));
}

function base64urlBytes(bytes) {
  let str = "";
  for (const b of bytes) str += String.fromCharCode(b);
  return btoa(str).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

// ---- Cron tracking state (D1 `cron_state` table) ----
// Small get/set-by-key helpers over a generic key/value table — these four keys (last-seen
// post id, best pull % per guild/boss, which bosses already got a World First push, last-seen
// Wowhead pubDate) are independent, occasionally-changing blobs, not one evolving record, so a
// single-column-per-field table doesn't fit as naturally as it does for `devices` below.

async function getCronState(env, key) {
  const row = await env.DB.prepare("SELECT value FROM cron_state WHERE key = ?").bind(key).first();
  return row ? row.value : null;
}

async function setCronState(env, key, value) {
  await env.DB.prepare(
    "INSERT INTO cron_state (key, value) VALUES (?, ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value"
  )
    .bind(key, value)
    .run();
}

// ---- Device storage (D1 `devices` table) ----
// One row per device: token, raiderioEnabled, wowheadEnabled, spoilerFreeEnabled,
// heartbreakThresholdPercent, notifyNonWorldFirstHeartbreaks. Per-guild notification filtering
// (a `guildIds` field per device) was tried and removed — it didn't work reliably; these are
// much simpler independent per-category/per-value preferences, not guild-matching logic, so
// the same concern doesn't really apply.
//
// Updating an already-registered device is a single atomic UPSERT (D1/SQLite gives us
// INSERT...ON CONFLICT, unlike KV's old read-modify-write-a-shared-blob approach, which could
// drop a write if two registrations landed in the same window). Adding a brand-new device still
// has a small check-then-insert race against MAX_DEVICES, same as before — with a personal
// app's handful of devices registering rarely (basically just app launch, or a Settings
// toggle), that's not worth closing with a transaction.

function normalizeDevice(d) {
  const threshold =
    typeof d.heartbreakThresholdPercent === "number" && !Number.isNaN(d.heartbreakThresholdPercent)
      ? Math.min(HEARTBREAK_MAX_THRESHOLD_PERCENT, Math.max(HEARTBREAK_MIN_THRESHOLD_PERCENT, d.heartbreakThresholdPercent))
      : HEARTBREAK_DEFAULT_THRESHOLD_PERCENT;
  return {
    token: d.token,
    raiderioEnabled: d.raiderioEnabled !== false,
    wowheadEnabled: d.wowheadEnabled !== false,
    spoilerFreeEnabled: d.spoilerFreeEnabled === true,
    heartbreakThresholdPercent: threshold,
    notifyNonWorldFirstHeartbreaks: d.notifyNonWorldFirstHeartbreaks === true,
  };
}

function rowToDevice(row) {
  return normalizeDevice({
    token: row.token,
    raiderioEnabled: row.raiderio_enabled === 1,
    wowheadEnabled: row.wowhead_enabled === 1,
    spoilerFreeEnabled: row.spoiler_free_enabled === 1,
    heartbreakThresholdPercent: row.heartbreak_threshold_percent,
    notifyNonWorldFirstHeartbreaks: row.notify_non_world_first_heartbreaks === 1,
  });
}

async function getDevices(env) {
  const { results } = await env.DB.prepare("SELECT * FROM devices").all();
  return results.map(rowToDevice);
}

/// Returns false (and writes nothing) if this would add a brand-new device past MAX_DEVICES —
/// updating an already-registered device's preferences is always allowed, since that never
/// grows the list.
async function addDevice(env, token, prefs) {
  const normalized = normalizeDevice({ token, ...prefs });
  const existing = await env.DB.prepare("SELECT 1 FROM devices WHERE token = ?").bind(token).first();
  if (!existing) {
    const countRow = await env.DB.prepare("SELECT COUNT(*) as count FROM devices").first();
    if (countRow.count >= MAX_DEVICES) return false;
  }
  await env.DB.prepare(
    `INSERT INTO devices
       (token, raiderio_enabled, wowhead_enabled, spoiler_free_enabled, heartbreak_threshold_percent, notify_non_world_first_heartbreaks)
     VALUES (?, ?, ?, ?, ?, ?)
     ON CONFLICT(token) DO UPDATE SET
       raiderio_enabled = excluded.raiderio_enabled,
       wowhead_enabled = excluded.wowhead_enabled,
       spoiler_free_enabled = excluded.spoiler_free_enabled,
       heartbreak_threshold_percent = excluded.heartbreak_threshold_percent,
       notify_non_world_first_heartbreaks = excluded.notify_non_world_first_heartbreaks`
  )
    .bind(
      normalized.token,
      normalized.raiderioEnabled ? 1 : 0,
      normalized.wowheadEnabled ? 1 : 0,
      normalized.spoilerFreeEnabled ? 1 : 0,
      normalized.heartbreakThresholdPercent,
      normalized.notifyNonWorldFirstHeartbreaks ? 1 : 0
    )
    .run();
  return true;
}

async function removeDevice(env, token) {
  await env.DB.prepare("DELETE FROM devices WHERE token = ?").bind(token).run();
}
