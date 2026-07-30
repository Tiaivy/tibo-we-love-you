# TiboWeLoveYou central feed

This Worker is the only component that talks to TwitterAPI.io. Every installed
Mac app reads the same public snapshot from:

```text
GET /v1/reset/latest
```

The TwitterAPI.io key is stored as a Worker secret and is never shipped in the
Mac app.

## Local verification

```bash
npm test
```

## Cloudflare setup

1. Create a KV namespace:

   ```bash
   npx wrangler kv namespace create TIBO_STATE
   ```

2. Copy `wrangler.example.jsonc` to `wrangler.jsonc` and replace
   `REPLACE_WITH_KV_NAMESPACE_ID` with the returned ID.
3. Add both secrets:

   ```bash
   npx wrangler secret put TWITTERAPI_IO_KEY
   npx wrangler secret put ADMIN_TOKEN
   ```

4. Deploy:

   ```bash
   npm run deploy
   ```

The Cron Trigger runs every 10 minutes. It seeds existing posts on the first run
without sending an old alert. Public feed reads never call TwitterAPI.io.

## Endpoints

- `GET /v1/reset/latest` — cached public snapshot, including `lastResetAt`
- `GET /healthz` — last polling status
- `POST /v1/admin/poll` — protected manual poll using `Authorization: Bearer …`
