# Publishing via the X API (primary path)

Posts through X API v2 using `xurl`, X's official OAuth CLI (OpenClaw bundles
an xurl skill). This is the default `postVia` mode: it works headless, needs
no browser, and stays inside X's automation rules.

## Publishing steps

1. Verify xurl is authenticated: `xurl auth status` (or a cheap
   `xurl get /2/users/me`). If auth is missing or expired: stop and tell the
   user to re-run `xurl auth oauth2`. Never attempt authentication yourself.
2. Build the request body without shell-interpolating the tweet text (it
   derives from external content):

   ```sh
   jq -n --arg text "$DRAFT_TEXT" '{text: $text}' > "$TMPDIR/tweet.json"
   xurl post /2/tweets -d @"$TMPDIR/tweet.json"
   ```

3. Read `.data.id` from the response. The permalink is
   `https://x.com/<username>/status/<id>`. Return it and delete the temp file.

## Error handling

- **401 / auth failure** — token refresh failed. Alert the user, stop.
- **403** — usually a duplicate post or a policy block. Report the response
  body verbatim; do not modify the text and retry on your own.
- **429** — rate limited. Report and stop; the next cron run tries fresh.
- Any other failure: one retry, then stop and report per SKILL.md failure
  rules. A response without `.data.id` counts as unverified — say so.

## One-time setup (user)

1. Create a free X developer account and a project + app at
   developer.x.com. Free tier write access (~500 posts/month) covers 2/day.
2. Install xurl and run `xurl auth oauth2` with scopes `tweet.read`,
   `tweet.write`, `users.read`, `offline.access` (offline grants the refresh
   token that makes headless runs possible).
3. Tokens live in `~/.xurl`. For a server deployment, run the auth locally
   and copy that directory over. Never commit it or copy it into skill state.
