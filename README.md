# Tibo, We Love You

A tiny macOS menu bar app that lets you know when Tibo posts a ChatGPT or
Codex limit reset.

> Unofficial fan-made utility. Not affiliated with Tibo, X, or OpenAI.

![Tibo, We Love You preview](DesignPreview/app-preview-v12-final.png)

## What it does

- Lives quietly in the macOS menu bar.
- Watches a shared central feed for new posts from `@thsottiaux`.
- Alerts only when a post clearly confirms a completed ChatGPT or Codex
  allowance reset.
- Shows a compact, silent red-button animation in the top-right corner.
- Keeps the alert visible until you close it or open the original post on X.
- Never ships the TwitterAPI.io key inside the Mac app.

## Shared API architecture

The central Worker checks `@thsottiaux` every 10 minutes, for 144 upstream
TwitterAPI.io requests per day. Every installed app reads the same cached feed,
so adding more users does not multiply TwitterAPI.io usage.

The Mac app polls the shared feed once per minute. Server code and deployment
instructions are in [`Server/`](Server/).

## Reset detection rules

A post must satisfy every rule below before an alert is published:

1. It comes from `@thsottiaux`.
2. It is an original post, not a reply, repost, or quote.
3. It mentions ChatGPT or Codex.
4. It includes allowance context such as usage limits, weekly limits, or quota.
5. It clearly states that the reset has already happened.

Scheduled, uncertain, negated, hypothetical, and question-form posts are
rejected. A standalone `reset` keyword is never enough to trigger an alert.

## Build

Deploy the central Worker first, then build the Mac app with its public feed
URL:

```bash
TIBO_RESET_FEED_URL="https://your-worker.example/v1/reset/latest" \
  ./scripts/build_app.sh
```

Build outputs:

```text
dist/TiboWeLoveYou.app
dist/TiboWeLoveYou-macOS.zip
```

Do not publish a build with an empty `TIBO_RESET_FEED_URL`.
