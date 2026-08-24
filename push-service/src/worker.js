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
const LAST_SEEN_KEY = "lastSeenPostId";
const HEARTBREAK_BEST_KEY = "heartbreakBest";
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

export default {
  // Two independent cron triggers fire this (see wrangler.toml): "*/15 * * * *" also matches
  // every "* * * * *" tick, so Cloudflare invokes scheduled() once per matching expression —
  // routing on event.cron keeps the Wowhead check from also running (and double-fetching) on
  // the every-minute trigger.
  async scheduled(event, env, ctx) {
    if (event.cron === "*/15 * * * *") {
      ctx.waitUntil(checkWowheadNews(env));
      return;
    }
    ctx.waitUntil(Promise.all([checkForNewPosts(env), checkRaiderIOEvents(env)]));
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

  // This cron overlapping a manual /check could both read the same lastSeenRaw before either
  // writes back and both push the same "new" post — apns-collapse-id means the device sees one
  // alert, not two, so this is a latent double-send rather than a user-visible bug. Same
  // tradeoff as the device-storage races documented near addDevice: not worth a transaction
  // for this app's scale.
  const maxId = posts.reduce((m, p) => Math.max(m, p.id), 0);
  const lastSeenRaw = await getCronState(env, LAST_SEEN_KEY);

  if (lastSeenRaw === null) {
    // First run ever: just record the baseline so we don't blast a notification for
    // every post already in the feed's backlog.
    await setCronState(env, LAST_SEEN_KEY, String(maxId));
    return { ok: true, newPosts: 0, baseline: maxId };
  }

  const lastSeen = parseInt(lastSeenRaw, 10);
  const newPosts = posts
    .filter((p) => p.id > lastSeen)
    .sort((a, b) => new Date(a.published_at) - new Date(b.published_at));

  if (newPosts.length > 0) {
    const devices = (await getDevices(env)).filter((d) => d.raiderioEnabled);
    for (const post of newPosts) {
      const title = "Venomous Abyss";
      // Coverage posts routinely announce kills in the first sentence ("Method one-shots
      // Mythic Ula'tek!") — spoilerFreeEnabled only redacted World First pushes until now,
      // which meant a spoiler-free user got the kill spoiled here first anyway.
      const body = post.contentPreview || "New update";
      const spoilerFreeBody = "New coverage update — open the app when you're ready to see it.";
      for (const device of devices) {
        await sendPush(env, device.token, title, device.spoilerFreeEnabled ? spoilerFreeBody : body, `post-${post.id}`);
      }
    }
    // Only write when maxId actually advanced — this cron runs every minute, and writing
    // unconditionally on a KV-backed version of this (before the D1 migration below) burned
    // ~1440 writes/day from this function alone toward KV's 1000/day free-tier cap, even on
    // minutes with nothing new. D1's free tier is 100k writes/day, but there's no reason to
    // reintroduce the churn.
    await setCronState(env, LAST_SEEN_KEY, String(maxId));
  }
  return { ok: true, newPosts: newPosts.length };
}

/// Fetches raid-race (for boss names) and raid-rankings (for live pull/defeat data) once and
/// runs both the heartbreak and world-first checks against it — they'd otherwise each need
/// the same two fetches every minute.
async function checkRaiderIOEvents(env) {
  const devices = (await getDevices(env)).filter((d) => d.raiderioEnabled);
  if (devices.length === 0) return { ok: true, watchedDevices: 0 };

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

  const [heartbreaks, worldFirsts] = await Promise.all([
    checkHeartbreaks(env, rankings, encounterBySlug, devices),
    checkWorldFirstKills(env, rankings, encounterBySlug, devices),
  ]);

  return { ok: true, watchedDevices: devices.length, heartbreaks, worldFirsts };
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

  const bestRaw = await getCronState(env, HEARTBREAK_BEST_KEY);
  const isFirstRun = bestRaw === null;
  const best = isFirstRun ? {} : JSON.parse(bestRaw);
  const nextBest = { ...best };
  let changed = false;

  let pushCount = 0;
  for (const entry of rankings) {
    for (const pull of entry.encountersPulled || []) {
      if (pull.isDefeated) continue;
      if (typeof pull.bestPercent !== "number") continue;

      const key = `${entry.guild.id}-${pull.slug}`;
      const previousBest = best[key];
      const isNewRecord = previousBest === undefined || pull.bestPercent < previousBest;
      if (isNewRecord) {
        nextBest[key] = pull.bestPercent;
        changed = true;
      }
      // First run ever: record the baseline (so re-notifying doesn't depend on someone
      // happening to improve past a pull we never saw) without pushing for every close call
      // already in progress the moment this ships. Record-tracking itself isn't gated by any
      // threshold — it has to stay threshold-agnostic so it means the same thing regardless of
      // which device's threshold ends up applying at push time below.
      if (!isNewRecord || isFirstRun) continue;

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
          `heartbreak-${key}-${Math.round(pull.bestPercent * 100)}`
        );
        pushCount++;
      }
    }
  }

  // This cron runs every minute; only write when a pull actually set a new record, not on
  // every tick — see the LAST_SEEN_KEY comment above for why that matters.
  if (changed) await setCronState(env, HEARTBREAK_BEST_KEY, JSON.stringify(nextBest));
  return { pushCount };
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
      await sendPush(env, device.token, title, body, `worldfirst-${slug}`);
      pushCount++;
    }
  }

  // Same reasoning as HEARTBREAK_BEST_KEY above — only write when a boss was newly claimed.
  if (changed) await setCronState(env, WORLD_FIRST_SEEN_KEY, JSON.stringify(nextSeen));
  return { pushCount };
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
        await sendPush(env, device.token, "WoW News", article.title, collapseId);
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
async function sendPush(env, deviceToken, title, body, collapseId) {
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
      body: JSON.stringify({ aps: { alert: { title, body }, sound: "default", badge: 1 } }),
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
