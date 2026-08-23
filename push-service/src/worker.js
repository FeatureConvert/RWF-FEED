// rwf-feed-push — polls raider.io's Venomous Abyss coverage feed and Wowhead's WoW news RSS
// once a minute (Cloudflare Cron's minimum granularity) and pushes a notification via APNs
// the moment something new appears. This is what lets RWF FEED notify you even while the app
// is fully closed — local notifications only fire while the app's own polling loop is running.
//
// Each registered device carries three independent preference flags, set from the toggles in
// Settings — raiderioEnabled (new feed posts, "Major Heartbreaker" close calls, "World
// First!" kill announcements), wowheadEnabled (new WoW news articles), and spoilerFreeEnabled
// (redacts World First kill pushes to a generic "Spoiler Alert" instead of naming the
// guild/boss; off by default). Filtering/redaction has to happen here rather than on-device:
// once APNs has delivered a push while the app is closed, there's no client-side hook to veto
// or rewrite it. There's no per-guild filtering within raiderioEnabled (removed; it wasn't
// working reliably).
//
// Endpoints:
//   POST /register  { "deviceToken": "<hex>", "raiderioEnabled": bool, "wowheadEnabled": bool, "spoilerFreeEnabled": bool }
//   GET  /check?secret=<value>  — manually trigger a poll, for testing
//   GET  /test-push?secret=<value> — send a placeholder push to every registered device
//
// /check and /test-push require ADMIN_SECRET (a Worker secret, see README) as a `secret`
// query param — without it, anyone who finds the URL could enumerate every registered
// device token from /test-push's response, or spam real polls via /check. /register has no
// such gate: it only ever adds/updates one device's own token, nothing to protect.

const FEED_SLUG = "the-venomous-abyss-global-coverage";
const RAID_SLUG = "the-venomous-abyss";
const LAST_SEEN_KEY = "lastSeenPostId";
const DEVICES_KEY = "devices";
const LEGACY_TOKENS_KEY = "deviceTokens";
const HEARTBREAK_BEST_KEY = "heartbreakBest";
const HEARTBREAK_THRESHOLD_PERCENT = 5.01;
const WORLD_FIRST_SEEN_KEY = "worldFirstKillsSeen";
const WOWHEAD_NEWS_URL = "https://www.wowhead.com/news/rss/retail";
const WOWHEAD_LAST_SEEN_KEY = "wowheadLastSeenPubDate";

export default {
  async scheduled(_event, env, ctx) {
    ctx.waitUntil(Promise.all([checkForNewPosts(env), checkRaiderIOEvents(env), checkWowheadNews(env)]));
  },

  async fetch(request, env) {
    const url = new URL(request.url);

    if (request.method === "POST" && url.pathname === "/register") {
      const body = await request.json().catch(() => null);
      if (!body || typeof body.deviceToken !== "string" || !body.deviceToken) {
        return new Response("Missing deviceToken", { status: 400 });
      }
      await addDevice(env, body.deviceToken, {
        raiderioEnabled: body.raiderioEnabled,
        wowheadEnabled: body.wowheadEnabled,
        spoilerFreeEnabled: body.spoilerFreeEnabled,
      });
      return new Response("OK");
    }

    if (request.method === "GET" && url.pathname === "/check") {
      if (!isAuthorized(url, env)) return new Response("Unauthorized", { status: 401 });
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
      if (!isAuthorized(url, env)) return new Response("Unauthorized", { status: 401 });
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

function isAuthorized(url, env) {
  const provided = url.searchParams.get("secret");
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

  // KV reads can be up to ~60s stale across colos, and this cron overlapping a manual
  // /check hitting a different colo could both read the same lastSeenRaw and both push the
  // same "new" post — apns-collapse-id means the device sees one alert, not two, so this is
  // a latent double-send rather than a user-visible bug. Same tradeoff as the device-storage
  // races documented near addDevice: not worth a Durable Object for this app's scale.
  const maxId = posts.reduce((m, p) => Math.max(m, p.id), 0);
  const lastSeenRaw = await env.PUSH_KV.get(LAST_SEEN_KEY);

  if (lastSeenRaw === null) {
    // First run ever: just record the baseline so we don't blast a notification for
    // every post already in the feed's backlog.
    await env.PUSH_KV.put(LAST_SEEN_KEY, String(maxId));
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
      const body = post.contentPreview || "New update";
      for (const device of devices) {
        await sendPush(env, device.token, title, body, `post-${post.id}`);
      }
    }
  }

  await env.PUSH_KV.put(LAST_SEEN_KEY, String(maxId));
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

/// "Major Heartbreaker" pushes: a guild pulling a globally-unclaimed boss (nobody has killed
/// it yet, not just this guild) down under HEARTBREAK_THRESHOLD_PERCENT remaining health —
/// the same close-call signal as the app's Heartbreak tab, but pushed the moment it happens
/// instead of requiring the tab to be open.
///
/// Only pushes on a new record (this guild's lowest-ever percent on this boss) so a guild
/// stuck wiping around the same percent for an hour doesn't get a push every single minute.
async function checkHeartbreaks(env, rankings, encounterBySlug, devices) {
  // A boss stops being a "close call" the moment any guild claims it, even for a guild that
  // personally hasn't killed it yet — the race for that boss is over.
  const claimedSlugs = new Set();
  for (const entry of rankings) {
    for (const defeat of entry.encountersDefeated || []) claimedSlugs.add(defeat.slug);
  }

  const bestRaw = await env.PUSH_KV.get(HEARTBREAK_BEST_KEY);
  const isFirstRun = bestRaw === null;
  const best = isFirstRun ? {} : JSON.parse(bestRaw);
  const nextBest = { ...best };

  let pushCount = 0;
  for (const entry of rankings) {
    for (const pull of entry.encountersPulled || []) {
      if (pull.isDefeated || claimedSlugs.has(pull.slug)) continue;
      if (typeof pull.bestPercent !== "number" || pull.bestPercent >= HEARTBREAK_THRESHOLD_PERCENT) continue;

      const key = `${entry.guild.id}-${pull.slug}`;
      const previousBest = best[key];
      const isNewRecord = previousBest === undefined || pull.bestPercent < previousBest;
      if (isNewRecord) nextBest[key] = pull.bestPercent;
      // First run ever: record the baseline (so re-notifying doesn't depend on someone
      // happening to improve past a pull we never saw) without pushing for every close call
      // already in progress the moment this ships.
      if (!isNewRecord || isFirstRun) continue;

      const bossName = encounterBySlug[pull.slug]?.name ?? pull.slug;
      for (const device of devices) {
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

  await env.PUSH_KV.put(HEARTBREAK_BEST_KEY, JSON.stringify(nextBest));
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

  const seenRaw = await env.PUSH_KV.get(WORLD_FIRST_SEEN_KEY);
  const isFirstRun = seenRaw === null;
  const seen = isFirstRun ? {} : JSON.parse(seenRaw);
  const nextSeen = { ...seen };

  let pushCount = 0;
  for (const [slug, claim] of claimedNow) {
    if (seen[slug]) continue;
    nextSeen[slug] = true;
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

  await env.PUSH_KV.put(WORLD_FIRST_SEEN_KEY, JSON.stringify(nextSeen));
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

  const lastSeenRaw = await env.PUSH_KV.get(WOWHEAD_LAST_SEEN_KEY);
  if (lastSeenRaw === null) {
    // First run ever: record the baseline so we don't blast a notification for every
    // article already sitting in the feed's backlog.
    await env.PUSH_KV.put(WOWHEAD_LAST_SEEN_KEY, newest.pubDate.toISOString());
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
  }

  await env.PUSH_KV.put(WOWHEAD_LAST_SEEN_KEY, newest.pubDate.toISOString());
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
// lastSeenPostId/heartbreakBest KV write that follows it and causing every "new" item to be
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
      body: JSON.stringify({ aps: { alert: { title, body }, sound: "default" } }),
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

// ---- Device storage ----
// Array of { token, raiderioEnabled, wowheadEnabled, spoilerFreeEnabled }. Per-guild
// notification filtering (a `guildIds` field per device) was tried and removed — it didn't
// work reliably; these are much simpler binary per-category toggles, not guild-matching
// logic, so the same concern doesn't really apply. getDevices normalizes away older shapes (a
// plain token string, or an object missing some flags) by defaulting raiderioEnabled/
// wowheadEnabled to true and spoilerFreeEnabled to false — so a device that registered before
// a given flag existed keeps its old behavior (both categories on, spoilers not redacted).
//
// addDevice/removeDevice are read-modify-write, not atomic: two calls racing (e.g. two
// devices registering close together, or a register racing the cron's own removeDevice on a
// stale token) can both read the same blob and the second write clobbers the first. KV has
// no compare-and-swap to close that window, and doing this properly would mean moving device
// storage into a Durable Object. Deliberately not doing that here — with a personal app's
// handful of devices registering rarely (basically just app launch, or a Settings toggle),
// the actual odds of two writes landing in the same few-hundred-ms window are low enough not
// to be worth the rewrite. Revisit if this ever tracks more than a few devices.

async function getDevices(env) {
  const raw = await env.PUSH_KV.get(DEVICES_KEY);
  if (raw) {
    return JSON.parse(raw).map((d) =>
      typeof d === "string"
        ? { token: d, raiderioEnabled: true, wowheadEnabled: true, spoilerFreeEnabled: false }
        : {
            token: d.token,
            raiderioEnabled: d.raiderioEnabled !== false,
            wowheadEnabled: d.wowheadEnabled !== false,
            spoilerFreeEnabled: d.spoilerFreeEnabled === true,
          }
    );
  }

  // Fall back to the original key, from before this one existed. Never written again — the
  // first re-registration migrates a device to the current key.
  const legacyRaw = await env.PUSH_KV.get(LEGACY_TOKENS_KEY);
  if (!legacyRaw) return [];
  return JSON.parse(legacyRaw).map((token) => ({
    token,
    raiderioEnabled: true,
    wowheadEnabled: true,
    spoilerFreeEnabled: false,
  }));
}

async function addDevice(env, token, prefs) {
  const devices = await getDevices(env);
  const raiderioEnabled = prefs?.raiderioEnabled !== false;
  const wowheadEnabled = prefs?.wowheadEnabled !== false;
  const spoilerFreeEnabled = prefs?.spoilerFreeEnabled === true;
  const existing = devices.findIndex((d) => d.token === token);
  if (existing >= 0) {
    devices[existing] = { token, raiderioEnabled, wowheadEnabled, spoilerFreeEnabled };
  } else {
    devices.push({ token, raiderioEnabled, wowheadEnabled, spoilerFreeEnabled });
  }
  await env.PUSH_KV.put(DEVICES_KEY, JSON.stringify(devices));
}

async function removeDevice(env, token) {
  const devices = (await getDevices(env)).filter((d) => d.token !== token);
  await env.PUSH_KV.put(DEVICES_KEY, JSON.stringify(devices));
}
