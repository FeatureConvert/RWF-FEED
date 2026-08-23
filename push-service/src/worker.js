// rwf-feed-push — polls raider.io's Venomous Abyss coverage feed once a minute (Cloudflare
// Cron's minimum granularity) and pushes a notification via APNs the moment a new post
// appears. This is what lets RWF FEED notify you even while the app is fully closed —
// local notifications only fire while the app's own polling loop is running.
//
// Each device picks a notification mode: `guildId: null` gets every global feed post
// (the original behavior); `guildId: <id>` instead gets a push only when that specific
// guild's boss count increases, sourced independently from the raid-race timeline so it
// doesn't depend on the editorial feed ever posting about that guild.
//
// Endpoints:
//   POST /register   { "deviceToken": "<hex>", "guildId": <number|null> }
//   GET  /check                                   — manually trigger a poll, for testing

const FEED_SLUG = "the-venomous-abyss-global-coverage";
const RAID_SLUG = "the-venomous-abyss";
const LAST_SEEN_KEY = "lastSeenPostId";
const DEVICES_KEY = "devices";
const LEGACY_TOKENS_KEY = "deviceTokens";
const GUILD_PROGRESS_KEY = "guildProgress";

export default {
  async scheduled(_event, env, ctx) {
    ctx.waitUntil(Promise.all([checkForNewPosts(env), checkGuildKills(env)]));
  },

  async fetch(request, env) {
    const url = new URL(request.url);

    if (request.method === "POST" && url.pathname === "/register") {
      const body = await request.json().catch(() => null);
      if (!body || typeof body.deviceToken !== "string" || !body.deviceToken) {
        return new Response("Missing deviceToken", { status: 400 });
      }
      const guildId = typeof body.guildId === "number" ? body.guildId : null;
      await upsertDevice(env, body.deviceToken, guildId);
      return new Response("OK");
    }

    if (request.method === "GET" && url.pathname === "/check") {
      const [posts, kills] = await Promise.all([checkForNewPosts(env), checkGuildKills(env)]);
      return new Response(JSON.stringify({ posts, kills }), {
        headers: { "content-type": "application/json" },
      });
    }

    if (request.method === "GET" && url.pathname === "/test-push") {
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
        results.push({ token: device.token, guildId: device.guildId, ...result });
      }
      return new Response(JSON.stringify({ deviceCount: devices.length, results }, null, 2), {
        headers: { "content-type": "application/json" },
      });
    }

    return new Response("Not found", { status: 404 });
  },
};

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
    const devices = (await getDevices(env)).filter((d) => d.guildId === null);
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

/// Pushes to devices that picked a specific favorite guild the moment that guild's boss
/// count increases — independent of the editorial feed, which might lag behind or never
/// mention a given guild's kill at all.
async function checkGuildKills(env) {
  const devices = (await getDevices(env)).filter((d) => d.guildId !== null);
  if (devices.length === 0) return { ok: true, watchedDevices: 0 };

  const resp = await fetch(
    `https://raider.io/api/raids/raid-race?raid=${RAID_SLUG}&region=world&difficulty=mythic`
  );
  if (!resp.ok) return { ok: false, status: resp.status };
  const data = await resp.json();
  const tracker = data.worldFirstTracker || {};
  const timeline = tracker.timelines?.[0]?.timeline || [];
  const encounters = [...(tracker.raid?.encounters || [])].sort((a, b) => a.ordinal - b.ordinal);

  const bestProgress = {};
  for (const step of timeline) {
    for (const kill of step.guilds) {
      const gid = String(kill.guild.id);
      if (!bestProgress[gid] || step.progress > bestProgress[gid].progress) {
        bestProgress[gid] = { progress: step.progress, guildName: kill.guild.displayName };
      }
    }
  }

  const previousRaw = await env.PUSH_KV.get(GUILD_PROGRESS_KEY);
  const nextProgress = {};
  for (const [gid, current] of Object.entries(bestProgress)) {
    nextProgress[gid] = current.progress;
  }

  if (previousRaw === null) {
    // First run ever: record the baseline so every already-in-progress guild doesn't look
    // like a fresh kill the moment someone favorites them.
    await env.PUSH_KV.put(GUILD_PROGRESS_KEY, JSON.stringify(nextProgress));
    return { ok: true, watchedDevices: devices.length, baseline: true };
  }

  const previous = JSON.parse(previousRaw);
  let pushCount = 0;
  for (const [gid, current] of Object.entries(bestProgress)) {
    const prevProgress = previous[gid] ?? 0;
    if (current.progress <= prevProgress) continue;

    const boss = encounters[current.progress - 1];
    const bossName = boss ? boss.name : `boss ${current.progress}`;
    const watchers = devices.filter((d) => String(d.guildId) === gid);
    for (const device of watchers) {
      await sendPush(
        env,
        device.token,
        current.guildName,
        `Killed ${bossName}! (${current.progress}/${encounters.length})`,
        `guild-${gid}-${current.progress}`
      );
      pushCount++;
    }
  }

  await env.PUSH_KV.put(GUILD_PROGRESS_KEY, JSON.stringify(nextProgress));
  return { ok: true, watchedDevices: devices.length, pushCount };
}

// ---- APNs ----

async function sendPush(env, deviceToken, title, body, collapseId) {
  const jwt = await makeApnsJwt(env);
  const apnsHost =
    (env.APNS_ENV || "sandbox") === "production"
      ? "https://api.push.apple.com"
      : "https://api.sandbox.push.apple.com";

  const res = await fetch(`${apnsHost}/3/device/${deviceToken}`, {
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
// { token: "<hex>", guildId: number | null } — guildId null means "all feed posts".

async function getDevices(env) {
  const raw = await env.PUSH_KV.get(DEVICES_KEY);
  if (raw) return JSON.parse(raw);

  // Fall back to the flat token-array format used before per-guild notifications existed.
  // Never written again — the first re-registration migrates a device to the new key.
  const legacyRaw = await env.PUSH_KV.get(LEGACY_TOKENS_KEY);
  if (!legacyRaw) return [];
  return JSON.parse(legacyRaw).map((token) => ({ token, guildId: null }));
}

async function upsertDevice(env, token, guildId) {
  const devices = await getDevices(env);
  const existing = devices.find((d) => d.token === token);
  if (existing) {
    existing.guildId = guildId;
  } else {
    devices.push({ token, guildId });
  }
  await env.PUSH_KV.put(DEVICES_KEY, JSON.stringify(devices));
}

async function removeDevice(env, token) {
  const devices = (await getDevices(env)).filter((d) => d.token !== token);
  await env.PUSH_KV.put(DEVICES_KEY, JSON.stringify(devices));
}
