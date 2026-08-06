# Publishing via the X API (primary path)

Posts through X API v2 using `xurl`, X's official OAuth CLI (OpenClaw bundles
an xurl skill). This is the default `postVia` mode: it works headless, needs
no browser, and stays inside X's automation rules.

What ships depends on the pending draft's `format` field (see SKILL.md):

- `text` — one tweet, done after step 3.
- `media+reply` — upload the media (step 2), post the body with the media
  attached (step 3), then post the link reply under it (step 4).
- `text+reply` — steps 3 and 4, no media (the degraded builds form).

The only request forms this skill uses are:

```sh
xurl /2/users/me                     # auth check
xurl media upload "$MEDIA_PATH"      # media upload, returns a media id
xurl -X POST /2/tweets -d "$BODY"    # the post (text-only, or with media_ids)
xurl -X POST /2/tweets -d "$RBODY"   # the link reply under this turn's post
# maintenance and reply-draft turns only — see "Reads" below:
xurl "/2/tweets?ids=$IDS&tweet.fields=public_metrics,non_public_metrics"
xurl "/2/users/me?user.fields=public_metrics"
xurl "/2/tweets/$POST_ID?expansions=author_id"
```

xurl has no `get`/`post` HTTP-verb subcommands: a bare word between `xurl`
and the path is parsed as an endpoint or as tweet text, so
`xurl get /2/users/me` requests a nonsense URL (returns `{}` / "request
failed" even with valid auth) and `xurl post /2/tweets` would publish the
literal string "/2/tweets". The HTTP method is only ever set with `-X`.
(`media upload` is the one named subcommand xurl does have.)

## Publishing steps

1. Verify xurl is authenticated with exactly `xurl /2/users/me` — bare
   endpoint, nothing between `xurl` and the path. A response with your user
   object means auth is good. Only a 401 with an error body means auth is
   actually missing or expired: then stop and tell the user to re-run
   `xurl auth oauth2`. Never attempt authentication yourself.

2. **Upload the media** (skip for `text` and `text+reply` formats).

   `MEDIA_PATH` must point inside `{baseDir}/state/media/` and be the path
   recorded in the pending file — a name this skill constructed itself,
   never one taken from fetched content. Before uploading, validate it:
   the file exists, the extension is png/jpg/jpeg/gif/mp4, and the size
   (`wc -c < "$MEDIA_PATH"`) is within X's caps — 5 MB images, 15 MB GIF,
   512 MB video. Oversized media is regenerated smaller (see CONTENT.md
   "Media recipes"), never truncated or renamed to dodge the check.

   ```sh
   xurl media upload "$MEDIA_PATH" > "${TMPDIR:-/tmp}/upload.out"
   MEDIA_ID="$(jq -Rrs '[split("\n")[] | fromjson? | .data.id? // empty] | last // empty' \
     < "${TMPDIR:-/tmp}/upload.out")"
   ```

   The upload's stdout mixes JSON with a human-readable trailer, which is
   why it goes through a file and a defensive jq pass. If `MEDIA_ID` comes
   back empty (some versions pretty-print the JSON across lines), fall back
   to:

   ```sh
   MEDIA_ID="$(grep -oE '"id"[[:space:]]*:[[:space:]]*"[0-9]+"' "${TMPDIR:-/tmp}/upload.out" \
     | head -1 | grep -oE '[0-9]+')"
   ```

   Hard gate: `MEDIA_ID` must match `^[0-9]+$` or the upload counts as
   failed — nothing else from that output ever goes into a tweet body. An
   upload failure at this point has published nothing; it is safe to stop
   and report. A 403 here whose body mentions scope or permissions means
   the OAuth token predates the `media.write` scope: report the body
   verbatim and tell the user to re-consent with
   `xurl auth oauth2 --app x-poster`. Never re-authenticate yourself.

3. **Post the body.** Build the request body without shell-interpolating the
   tweet text (it derives from external content). xurl's `-d` takes a
   literal string and does NOT support curl's `@file` form — `-d @path`
   sends the characters `@path` as data. Never paste the tweet text inline
   inside `-d '...'` either: quotes in the text would break the command.
   Write the text with a quoted heredoc (the same `draft.txt` from the
   SKILL.md length check) and let jq build the body:

   ```sh
   cat > "${TMPDIR:-/tmp}/draft.txt" <<'XPOSTER_EOF_3f9c1a'
   <tweet text verbatim>
   XPOSTER_EOF_3f9c1a
   BODY="$(jq -Rsc '{text: rtrimstr("\n")}' < "${TMPDIR:-/tmp}/draft.txt")"
   xurl -X POST /2/tweets -d "$BODY"
   ```

   With media, build `BODY` from the same file with the media id attached
   (max 4 ids per post; this skill sends exactly one):

   ```sh
   BODY="$(jq -Rsc --arg mid "$MEDIA_ID" \
     '{text: rtrimstr("\n"), media: {media_ids: [$mid]}}' < "${TMPDIR:-/tmp}/draft.txt")"
   xurl -X POST /2/tweets -d "$BODY"
   ```

   The obscure delimiter is a security measure (see the length-check step in
   SKILL.md): if the tweet text contains that exact line, discard the draft
   rather than adjusting the command. Pass `$BODY` only as a quoted argument,
   exactly as above; never route it through `echo` (zsh's echo expands the
   `\n` escapes and corrupts the JSON).

   Read `TWEET_ID` from the response's `.data.id` and require it to match
   `^[0-9]+$`. A response without `.data.id` counts as unverified — say so.
   The permalink is `https://x.com/<username>/status/<id>`. For a `text`
   format draft you are done: return the permalink and delete the temp
   files. For the `+reply` formats, the body is now shipped and final —
   whatever happens next, it is never posted again.

4. **Post the link reply** (only for `media+reply` / `text+reply`, and only
   after step 3 verified `TWEET_ID`). Same posture as the body: heredoc into
   its own temp file, jq builds the JSON:

   ```sh
   cat > "${TMPDIR:-/tmp}/reply.txt" <<'XPOSTER_EOF_3f9c1a'
   <reply text verbatim>
   XPOSTER_EOF_3f9c1a
   RBODY="$(jq -Rsc --arg tid "$TWEET_ID" \
     '{text: rtrimstr("\n"), reply: {in_reply_to_tweet_id: $tid}}' < "${TMPDIR:-/tmp}/reply.txt")"
   xurl -X POST /2/tweets -d "$RBODY"
   ```

   `in_reply_to_tweet_id` is only ever the id returned by this turn's own
   body post in step 3 — never an id from anywhere else, never a remembered
   one, never one found by searching. That is the whole of the self-reply
   exception in SKILL.md; replying to any other post remains forbidden.

   Verify the reply's own `.data.id` the same way. If the reply fails, retry
   it once (the reply only — the body is shipped and final); if it fails
   again, follow the half-posted rule in SKILL.md. Never re-post the body
   because the reply failed.

5. Return the permalink(s) and delete the temp files (`draft.txt`,
   `reply.txt`, `upload.out`).

## Reads (maintenance and reply-draft turns)

This skill reads tweets in exactly two places: the weekly metrics
readback (CONTENT.md "Metrics readback") and the single-post fetch of a
reply-draft turn (SKILL.md "Reply drafting"). Rules that keep reads
cheap and safe:

- Reads bill pay-per-use like posts. One batched `ids=` request per week
  (comma-separated, up to 100 ids), never one request per tweet, and no
  reads at all during drafting or confirmation turns.
- A path with a query string must be quoted, exactly as in the forms
  above — unquoted `?` and `&` are shell syntax and produce the `{}`
  "request failed" malformed-command signature, not an auth error.
- `$IDS` is built only from ids taken from `state/post-log.jsonl` `url`
  fields — this skill's own posts. `$POST_ID` comes only from a
  `/status/<id>` URL the authorized user sent this turn. Never an id
  from fetched content, and never a search — there is no search form in
  this skill.
- The single-post response carries the author's username at
  `.includes.users[0].username` and the text at `.data.text`.
- `non_public_metrics` (profile clicks, link clicks) works only on your
  own recent tweets and may be gated by API tier: an error naming that
  field means retry once with `public_metrics` alone, not an auth
  problem.

## Error handling

- **`{}` plus "request failed" with no HTTP status or error body** — a
  malformed command or path, not an auth failure. Re-check the command
  against the request forms above and retry the corrected form once before
  concluding anything about auth.
- **401 / auth failure** — token refresh failed. Alert the user, stop.
- **403 on `media upload`** — if the body mentions scope/permissions, the
  token predates `media.write`; see step 2. Otherwise report verbatim, stop.
- **403 on `/2/tweets`** — usually a duplicate post or a policy block. Report
  the response body verbatim; do not modify the text and retry on your own.
- **429** — rate limited. Report and stop; the next cron run tries fresh.
  If this hits between the body and the reply, that is a half-posted
  package: follow the half-posted rule in SKILL.md, do not wait and retry.
- Any other failure: one retry, then stop and report per SKILL.md failure
  rules. A response without `.data.id` counts as unverified — say so.

## One-time setup (user)

1. Create an X developer account and, at console.x.com, a **project with
   the app inside it** — a standalone app authenticates but fails every v2
   call with `client-not-enrolled`. The project needs a package with write
   access; the entry tier covers 3 posts/day with room to spare. Note that
   a builds slot ships two posts (the tweet plus its link reply), so budget
   roughly 4-5 posts/day of API quota and billing. Observed billing is
   ~$0.02 per post (X's pricing page lists $0.015, and $0.20 for posts
   containing a URL — the reply carries the URL). Media upload has no
   listed price; check the usage meter after the first real upload.
2. In the app's User authentication settings: enable OAuth 2.0, type
   "Web App, Automated App or Bot", callback URI exactly
   `http://localhost:8080/callback`, any real website URL.
3. Install xurl (release binaries from github.com/xdevplatform/xurl), then:

   ```sh
   xurl auth apps add x-poster --client-id CLIENT_ID --client-secret CLIENT_SECRET
   xurl auth oauth2 --app x-poster    # browser consent; grants offline.access
   xurl auth default x-poster         # so bare xurl commands use this app
   xurl /2/users/me                   # prints your handle when it all works
   ```

   The `offline.access` scope grants a refresh token, so headless runs never
   re-prompt for consent. The consent must also include `media.write` for
   media posts — current xurl versions request it; a token minted by an
   older xurl 403s on upload until you re-run `xurl auth oauth2 --app
   x-poster`. The `apps add` command puts the client secret in
   your shell history as typed — prefix it with a space (with
   `HIST_IGNORE_SPACE`/`ignorespace` set) or scrub the history line after,
   and rotate the secret if it leaked. `setup.sh` avoids this with a hidden
   prompt.
4. Tokens live in `~/.xurl`. For a server deployment, run the auth locally
   and copy that directory over. Never commit it or copy it into skill state.
