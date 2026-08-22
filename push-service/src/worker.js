// rwf-feed-push — polls raider.io's Venomous Abyss coverage feed once a minute (Cloudflare
// Cron's minimum granularity) and pushes a notification via APNs the moment a new post
// appears. This is what lets RWF FEED notify you even while the app is fully closed —
// local notifications only fire while the app's own polling loop is running.
//
// Endpoints:
//   POST /register   { "deviceToken": "<hex>" }  — called by the app after it registers
//                                                   for remote notifications
//   GET  /check                                   — manually trigger a poll, for testing

const FEED_SLUG = "the-venomous-abyss-global-coverage";
const LAST_SEEN_KEY = "lastSeenPostId";
const TOKENS_KEY = "deviceTokens";

export default {
  async scheduled(_event, env, ctx) {
    ctx.waitUntil(checkForNewPosts(env));
  },

  async fetch(request, env) {
    const url = new URL(request.url);

    if (request.method === "POST" && url.pathname === "/register") {
      const body = await request.json().catch(() => null);
      if (!body || typeof body.deviceToken !== "string" || !body.deviceToken) {
        return new Response("Missing deviceToken", { status: 400 });
      }
      await addToken(env, body.deviceToken);
      return new Response("OK");
    }

    if (request.method === "GET" && url.pathname === "/check") {
      const result = await checkForNewPosts(env);
      return new Response(JSON.stringify(result), {
        headers: { "content-type": "application/json" },
      });
    }

    if (request.method === "GET" && url.pathname === "/test-push") {
      const tokens = await getTokens(env);
      const results = [];
      for (const token of tokens) {
        const result = await sendPush(
          env,
          token,
          "Test push",
          "If you see this, push delivery works.",
          `test-${Date.now()}`
        );
        results.push({ token, ...result });
      }
      return new Response(JSON.stringify({ tokenCount: tokens.length, results }, null, 2), {
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
    const tokens = await getTokens(env);
    for (const post of newPosts) {
      const title = post.author || "Global Coverage";
      const body = post.contentPreview || "New update";
      for (const token of tokens) {
        await sendPush(env, token, title, body, `post-${post.id}`);
      }
    }
  }

  await env.PUSH_KV.put(LAST_SEEN_KEY, String(maxId));
  return { ok: true, newPosts: newPosts.length };
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
    await removeToken(env, deviceToken);
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

// ---- Device token storage ----

async function getTokens(env) {
  const raw = await env.PUSH_KV.get(TOKENS_KEY);
  return raw ? JSON.parse(raw) : [];
}

async function addToken(env, token) {
  const tokens = await getTokens(env);
  if (!tokens.includes(token)) {
    tokens.push(token);
    await env.PUSH_KV.put(TOKENS_KEY, JSON.stringify(tokens));
  }
}

async function removeToken(env, token) {
  const tokens = (await getTokens(env)).filter((t) => t !== token);
  await env.PUSH_KV.put(TOKENS_KEY, JSON.stringify(tokens));
}
