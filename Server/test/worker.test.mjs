import assert from "node:assert/strict";
import test from "node:test";

import worker, {
  classifyReset,
  parseTimeline,
  pollTwitter,
} from "../src/worker.mjs";

class FakeKV {
  values = new Map();

  async get(key, type) {
    const value = this.values.get(key) ?? null;
    return type === "json" && value !== null ? JSON.parse(value) : value;
  }

  async put(key, value) {
    this.values.set(key, value);
  }
}

function twitterResponse(tweets) {
  return new Response(JSON.stringify({ status: "success", tweets }), {
    status: 200,
    headers: { "Content-Type": "application/json" },
  });
}

test("classifies only completed allowance resets", () => {
  assert.equal(
    classifyReset("Codex usage limits have now been reset."),
    "confirmed",
  );
  assert.equal(
    classifyReset(
      "To celebrate a week of efficiency and let you run 100'000 Luna threads this weekend... that's right... wait for it... I have reset usage limits for Codex and ChatGPT Work. Enjoy.",
    ),
    "confirmed",
  );
  assert.equal(
    classifyReset("I've just reset the weekly limits for ChatGPT and Codex."),
    "confirmed",
  );
  assert.equal(
    classifyReset("We have already reset the Codex usage caps."),
    "confirmed",
  );
  assert.equal(classifyReset("ChatGPT Work usage limits will reset tonight."), null);
  assert.equal(classifyReset("I may reset Codex usage limits later."), null);
  assert.equal(classifyReset("I have not reset Codex usage limits yet."), null);
  assert.equal(classifyReset("Have I reset Codex usage limits?"), null);
  assert.equal(classifyReset("Codex usage limits have not been reset yet."), null);
  assert.equal(classifyReset("Have ChatGPT usage limits been reset?"), null);
  assert.equal(classifyReset("Usage limits have now been reset."), null);
  assert.equal(classifyReset("Codex has now been reset."), null);
  assert.equal(classifyReset("Reset your password."), null);
});

test("parses supported timeline response shapes", () => {
  assert.deepEqual(parseTimeline({ tweets: [{ id: "1" }] }), [{ id: "1" }]);
  assert.deepEqual(parseTimeline({ data: { tweets: [{ id: "2" }] } }), [
    { id: "2" },
  ]);
  assert.deepEqual(parseTimeline({ data: [{ id: "3" }] }), [{ id: "3" }]);
});

test("first poll seeds history; next poll publishes only the new reset", async () => {
  const kv = new FakeKV();
  const responses = [
    [
      {
        id: "old",
        text: "Codex usage limits have now been reset.",
        type: "tweet",
        createdAt: "2026-07-30T00:00:00.000Z",
      },
    ],
    [
      {
        id: "new",
        text: "ChatGPT Work usage limits have been reset again.",
        type: "tweet",
        createdAt: "2026-07-30T00:05:00.000Z",
      },
      {
        id: "old",
        text: "Codex usage limits have now been reset.",
        type: "tweet",
        createdAt: "2026-07-30T00:00:00.000Z",
      },
    ],
  ];
  const env = {
    TIBO_STATE: kv,
    TWITTERAPI_IO_KEY: "test-only",
    UPSTREAM_FETCH: async () => twitterResponse(responses.shift()),
  };

  const seeded = await pollTwitter(env, new Date("2026-07-30T00:01:00.000Z"));
  assert.equal(seeded.event, null);
  assert.equal(seeded.lastResetAt, "2026-07-30T00:00:00.000Z");

  const updated = await pollTwitter(env, new Date("2026-07-30T00:06:00.000Z"));
  assert.equal(updated.event.id, "new");
  assert.equal(updated.event.signal, "confirmed");
  assert.equal(updated.lastResetAt, "2026-07-30T00:05:00.000Z");
});

test("public feed reads KV without touching TwitterAPI.io", async () => {
  const kv = new FakeKV();
  await kv.put(
    "monitor-state",
    JSON.stringify({
      seeded: true,
      seenIds: ["new"],
      checkedAt: "2026-07-30T00:06:00.000Z",
      lastResetAt: "2026-07-30T00:05:00.000Z",
      lastError: null,
      latestEvent: {
        id: "new",
        signal: "confirmed",
        text: "Codex usage limits have been reset.",
        url: "https://x.com/thsottiaux/status/new",
        createdAt: "2026-07-30T00:05:00.000Z",
        detectedAt: "2026-07-30T00:06:00.000Z",
      },
    }),
  );
  let upstreamCalls = 0;
  const response = await worker.fetch(
    new Request("https://example.com/v1/reset/latest"),
    {
      TIBO_STATE: kv,
      UPSTREAM_FETCH: async () => {
        upstreamCalls += 1;
        throw new Error("must not run");
      },
    },
  );

  assert.equal(response.status, 200);
  assert.equal(upstreamCalls, 0);
  const body = await response.json();
  assert.equal(body.event.id, "new");
  assert.equal(body.lastResetAt, "2026-07-30T00:05:00.000Z");
});

test("poll backfills the last reset time without replaying an alert", async () => {
  const kv = new FakeKV();
  await kv.put(
    "monitor-state",
    JSON.stringify({
      seeded: true,
      seenIds: ["old"],
      checkedAt: "2026-07-30T00:01:00.000Z",
      latestEvent: null,
      lastError: null,
    }),
  );
  const env = {
    TIBO_STATE: kv,
    TWITTERAPI_IO_KEY: "test-only",
    UPSTREAM_FETCH: async () =>
      twitterResponse([
        {
          id: "old",
          text: "Codex usage limits have now been reset.",
          type: "tweet",
          createdAt: "2026-07-30T00:00:00.000Z",
        },
      ]),
  };

  const snapshot = await pollTwitter(
    env,
    new Date("2026-07-30T00:10:00.000Z"),
  );

  assert.equal(snapshot.event, null);
  assert.equal(snapshot.lastResetAt, "2026-07-30T00:00:00.000Z");
});

test("poll replays a newly classified reset newer than the stored reset", async () => {
  const kv = new FakeKV();
  await kv.put(
    "monitor-state",
    JSON.stringify({
      seeded: true,
      seenIds: ["missed"],
      checkedAt: "2026-08-01T03:40:00.000Z",
      latestEvent: null,
      lastResetAt: "2026-07-29T04:09:02.981Z",
      lastError: null,
    }),
  );
  const env = {
    TIBO_STATE: kv,
    TWITTERAPI_IO_KEY: "test-only",
    UPSTREAM_FETCH: async () =>
      twitterResponse([
        {
          id: "missed",
          text: "I have reset usage limits for Codex and ChatGPT Work.",
          type: "tweet",
          createdAt: "2026-08-01T03:32:37.508Z",
        },
      ]),
  };

  const snapshot = await pollTwitter(
    env,
    new Date("2026-08-01T07:10:00.000Z"),
  );

  assert.equal(snapshot.event.id, "missed");
  assert.equal(snapshot.event.signal, "confirmed");
  assert.equal(snapshot.lastResetAt, "2026-08-01T03:32:37.508Z");
});

test("older cached reset never overrides the verified baseline", async () => {
  const kv = new FakeKV();
  await kv.put(
    "monitor-state",
    JSON.stringify({
      seeded: true,
      seenIds: [],
      checkedAt: "2026-07-30T00:01:00.000Z",
      lastResetAt: "2026-07-28T03:09:23.000Z",
      latestEvent: null,
      lastError: null,
    }),
  );

  const response = await worker.fetch(
    new Request("https://example.com/v1/reset/latest"),
    { TIBO_STATE: kv },
  );
  const snapshot = await response.json();

  assert.equal(snapshot.lastResetAt, "2026-07-29T04:09:02.981Z");
});

test("manual poll is protected by an admin token", async () => {
  const response = await worker.fetch(
    new Request("https://example.com/v1/admin/poll", { method: "POST" }),
    { ADMIN_TOKEN: "secret" },
  );
  assert.equal(response.status, 401);
});

test("public health check never exposes upstream error details", async () => {
  const kv = new FakeKV();
  await kv.put(
    "monitor-state",
    JSON.stringify({
      seeded: true,
      seenIds: [],
      checkedAt: "2026-07-29T00:06:00.000Z",
      latestEvent: null,
      lastError: "upstream response that must stay private",
    }),
  );

  const response = await worker.fetch(
    new Request("https://example.com/healthz"),
    { TIBO_STATE: kv },
  );
  const body = await response.json();

  assert.equal(response.status, 503);
  assert.deepEqual(body, {
    ok: false,
    checkedAt: "2026-07-29T00:06:00.000Z",
  });
});
