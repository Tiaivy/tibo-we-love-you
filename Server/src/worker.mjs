const STATE_KEY = "monitor-state";
const SOURCE_USERNAME = "thsottiaux";
const TWITTER_API_URL =
  "https://api.twitterapi.io/twitter/user/last_tweets?userName=thsottiaux&includeReplies=false";

const productTerms = ["chatgpt", "codex"];

const allowanceTerms = [
  "usage limit",
  "usage limits",
  "rate limit",
  "rate limits",
  "weekly limit",
  "weekly limits",
  "quota",
  "banked reset",
  "usage cap",
  "usage caps",
  "allowance",
];

const completedTerms = [
  "have now been reset",
  "has now been reset",
  "have been reset",
  "has been reset",
  "were reset",
  "was reset",
  "are now reset",
  "is now reset",
  "just reset",
  "we reset",
  "i reset",
  "reset is complete",
  "reset completed",
  "added a banked reset",
  "refilled",
  "replenished",
  "have been restored",
  "has been restored",
  "limits restored",
  "quota restored",
];

const rejectedTerms = [
  "will reset",
  "will be reset",
  "going to reset",
  "plan to reset",
  "planning to reset",
  "should reset",
  "may reset",
  "might reset",
  "can reset",
  "could reset",
  "reset later",
  "reset this evening",
  "reset tonight",
  "reset tomorrow",
  "reset soon",
  "reset in ",
  "reset within ",
  "reset is coming",
  "reset coming",
  "working on",
  "trying to",
  "not reset",
  "not been reset",
  "haven't reset",
  "hasn't reset",
  "didn't reset",
  "did not reset",
  "won't reset",
  "can't reset",
  "cannot reset",
  "unable to reset",
  "no reset",
];

export function classifyReset(text) {
  const normalized = text
    .toLowerCase()
    .replaceAll("’", "'")
    .split(/\s+/)
    .join(" ")
    .trim();

  if (normalized.includes("?")) {
    return null;
  }
  if (rejectedTerms.some((term) => normalized.includes(term))) {
    return null;
  }
  if (!productTerms.some((term) => normalized.includes(term))) {
    return null;
  }
  if (!allowanceTerms.some((term) => normalized.includes(term))) {
    return null;
  }
  if (!completedTerms.some((term) => normalized.includes(term))) {
    return null;
  }
  return "confirmed";
}

export function parseTimeline(body) {
  if (Array.isArray(body?.tweets)) {
    return body.tweets;
  }
  if (Array.isArray(body?.data?.tweets)) {
    return body.data.tweets;
  }
  if (Array.isArray(body?.data)) {
    return body.data;
  }
  return [];
}

export async function pollTwitter(env, now = new Date()) {
  requireBindings(env);

  const fetcher = env.UPSTREAM_FETCH ?? fetch;
  const response = await fetcher(TWITTER_API_URL, {
    headers: { "X-API-Key": env.TWITTERAPI_IO_KEY },
  });

  if (!response.ok) {
    const message = await safeResponseMessage(response);
    throw new Error(
      `TwitterAPI.io returned HTTP ${response.status}${message ? `: ${message}` : ""}`,
    );
  }

  const body = await response.json();
  const tweets = parseTimeline(body);
  const state = await readState(env);
  const seen = new Set(state.seenIds);
  const originalTweets = tweets
    .filter(isOriginalTweet)
    .sort((left, right) => tweetTimestamp(left) - tweetTimestamp(right));

  if (!state.seeded) {
    for (const tweet of tweets) {
      const id = tweetID(tweet);
      if (id) {
        seen.add(id);
      }
    }

    const seededState = {
      ...state,
      seeded: true,
      seenIds: limitSeenIDs(seen),
      checkedAt: now.toISOString(),
      lastError: null,
    };
    await writeState(env, seededState);
    return publicSnapshot(seededState);
  }

  let latestEvent = state.latestEvent;
  for (const tweet of originalTweets) {
    const id = tweetID(tweet);
    if (!id || seen.has(id)) {
      continue;
    }
    seen.add(id);

    const text = typeof tweet.text === "string" ? tweet.text : "";
    const signal = classifyReset(text);
    if (!signal) {
      continue;
    }

    latestEvent = {
      id,
      signal,
      text,
      url:
        typeof tweet.url === "string" && tweet.url.length > 0
          ? tweet.url
          : `https://x.com/${SOURCE_USERNAME}/status/${id}`,
      createdAt: normalizedTweetDate(tweet, now),
      detectedAt: now.toISOString(),
    };
  }

  for (const tweet of tweets) {
    const id = tweetID(tweet);
    if (id) {
      seen.add(id);
    }
  }

  const nextState = {
    ...state,
    seeded: true,
    latestEvent,
    seenIds: limitSeenIDs(seen),
    checkedAt: now.toISOString(),
    lastError: null,
  };
  await writeState(env, nextState);
  return publicSnapshot(nextState);
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);

    if (request.method === "OPTIONS") {
      return new Response(null, {
        status: 204,
        headers: corsHeaders(),
      });
    }

    if (request.method === "GET" && url.pathname === "/v1/reset/latest") {
      requireStateBinding(env);
      const state = await readState(env);
      return json(publicSnapshot(state), 200, 30);
    }

    if (request.method === "GET" && url.pathname === "/healthz") {
      requireStateBinding(env);
      const state = await readState(env);
      return json(
        {
          ok: state.lastError === null,
          checkedAt: state.checkedAt,
        },
        state.lastError === null ? 200 : 503,
      );
    }

    if (request.method === "POST" && url.pathname === "/v1/admin/poll") {
      if (!env.ADMIN_TOKEN || !hasBearerToken(request, env.ADMIN_TOKEN)) {
        return json({ error: "Unauthorized" }, 401);
      }

      try {
        return json(await pollTwitter(env), 200);
      } catch (error) {
        await recordFailure(env, error, new Date());
        return json({ error: safeErrorMessage(error) }, 502);
      }
    }

    return json({ error: "Not found" }, 404);
  },

  async scheduled(_controller, env, ctx) {
    ctx.waitUntil(
      pollTwitter(env).catch(async (error) => {
        await recordFailure(env, error, new Date());
        throw error;
      }),
    );
  },
};

function requireBindings(env) {
  requireStateBinding(env);
  if (!env.TWITTERAPI_IO_KEY) {
    throw new Error("Missing TWITTERAPI_IO_KEY secret");
  }
}

function requireStateBinding(env) {
  if (!env.TIBO_STATE) {
    throw new Error("Missing TIBO_STATE KV binding");
  }
}

function isOriginalTweet(tweet) {
  const type = String(tweet?.type ?? "").toLowerCase();
  return (
    tweet?.isReply !== true &&
    tweet?.isRetweet !== true &&
    tweet?.isQuote !== true &&
    !["reply", "repost", "retweet", "like", "mention", "quote"].includes(type)
  );
}

function tweetID(tweet) {
  const value = tweet?.id;
  return typeof value === "string" || typeof value === "number"
    ? String(value)
    : null;
}

function tweetTimestamp(tweet) {
  const timestamp = Date.parse(tweet?.createdAt ?? "");
  return Number.isFinite(timestamp) ? timestamp : 0;
}

function normalizedTweetDate(tweet, fallback) {
  const timestamp = tweetTimestamp(tweet);
  return timestamp > 0 ? new Date(timestamp).toISOString() : fallback.toISOString();
}

function limitSeenIDs(seen) {
  return Array.from(seen).slice(-300);
}

async function safeResponseMessage(response) {
  try {
    const body = await response.json();
    return body.message ?? body.msg ?? null;
  } catch {
    return null;
  }
}

function hasBearerToken(request, token) {
  return request.headers.get("Authorization") === `Bearer ${token}`;
}

function defaultState() {
  return {
    seeded: false,
    seenIds: [],
    latestEvent: null,
    checkedAt: null,
    lastError: null,
  };
}

async function readState(env) {
  return (await env.TIBO_STATE.get(STATE_KEY, "json")) ?? defaultState();
}

async function writeState(env, state) {
  await env.TIBO_STATE.put(STATE_KEY, JSON.stringify(state));
}

async function recordFailure(env, error, now) {
  if (!env.TIBO_STATE) {
    return;
  }
  const state = await readState(env);
  await writeState(env, {
    ...state,
    lastError: safeErrorMessage(error),
    failedAt: now.toISOString(),
  });
}

function publicSnapshot(state) {
  return {
    version: 1,
    source: SOURCE_USERNAME,
    checkedAt: state.checkedAt,
    event: state.latestEvent,
  };
}

function safeErrorMessage(error) {
  return error instanceof Error ? error.message : "Unknown error";
}

function corsHeaders() {
  return {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Methods": "GET, OPTIONS",
    "Access-Control-Allow-Headers": "Content-Type",
  };
}

function json(value, status, cacheSeconds = 0) {
  return new Response(JSON.stringify(value), {
    status,
    headers: {
      "Content-Type": "application/json; charset=utf-8",
      "Cache-Control":
        cacheSeconds > 0
          ? `public, max-age=${cacheSeconds}, s-maxage=${cacheSeconds}`
          : "no-store",
      ...corsHeaders(),
    },
  });
}
