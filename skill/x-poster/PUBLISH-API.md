# Publishing via the X API (primary path)

Posts through X API v2 using `xurl`, X's official OAuth CLI (OpenClaw bundles
an xurl skill). This is the default `postVia` mode: it works headless, needs
no browser, and stays inside X's automation rules.

## Publishing steps

1. Verify xurl is authenticated with exactly `xurl /2/users/me` — bare
   endpoint, nothing between `xurl` and the path. A response with your user
   object means auth is good. Only a 401 with an error body means auth is
   actually missing or expired: then stop and tell the user to re-run
   `xurl auth oauth2`. Never attempt authentication yourself.
2. Build the request body without shell-interpolating the tweet text (it
   derives from external content). xurl's `-d` takes a literal string and
   does NOT support curl's `@file` form — `-d @path` sends the characters
   `@path` as data. Never paste the tweet text inline inside `-d '...'`
   either: quotes in the text would break the command. Write the text with
   a quoted heredoc (the same `draft.txt` from the SKILL.md length check)
   and let jq build the body:

   ```sh
   cat > "${TMPDIR:-/tmp}/draft.txt" <<'XPOSTER_EOF_3f9c1a'
   <tweet text verbatim>
   XPOSTER_EOF_3f9c1a
   BODY="$(jq -Rsc '{text: rtrimstr("\n")}' < "${TMPDIR:-/tmp}/draft.txt")"
   xurl -X POST /2/tweets -d "$BODY"
   ```

   The obscure delimiter is a security measure (see the length-check step in
   SKILL.md): if the tweet text contains that exact line, discard the draft
   rather than adjusting the command. Pass `$BODY` only as a quoted argument,
   exactly as above; never route it through `echo` (zsh's echo expands the `\n` escapes and corrupts the
   JSON). xurl also has no `get`/`post` HTTP-verb subcommands: a bare word
   between `xurl` and the path is parsed as an endpoint or as tweet text,
   so `xurl get /2/users/me` requests a nonsense URL (returns `{}` /
   "request failed" even with valid auth) and `xurl post /2/tweets` would
   publish the literal string "/2/tweets". The HTTP method is only ever set
   with `-X`. The only two request forms this skill uses are:

   ```sh
   xurl /2/users/me
   xurl -X POST /2/tweets -d "$BODY"
   ```

3. Read `.data.id` from the response. The permalink is
   `https://x.com/<username>/status/<id>`. Return it and delete the temp file.

## Error handling

- **`{}` plus "request failed" with no HTTP status or error body** — a
  malformed command or path, not an auth failure. Re-check the command
  against the two forms above and retry the corrected form once before
  concluding anything about auth.
- **401 / auth failure** — token refresh failed. Alert the user, stop.
- **403** — usually a duplicate post or a policy block. Report the response
  body verbatim; do not modify the text and retry on your own.
- **429** — rate limited. Report and stop; the next cron run tries fresh.
- Any other failure: one retry, then stop and report per SKILL.md failure
  rules. A response without `.data.id` counts as unverified — say so.

## One-time setup (user)

1. Create an X developer account and, at console.x.com, a **project with
   the app inside it** — a standalone app authenticates but fails every v2
   call with `client-not-enrolled`. The project needs a package with write
   access; the entry tier covers 3 posts/day with room to spare.
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
   re-prompt for consent. The `apps add` command puts the client secret in
   your shell history as typed — prefix it with a space (with
   `HIST_IGNORE_SPACE`/`ignorespace` set) or scrub the history line after,
   and rotate the secret if it leaked. `setup.sh` avoids this with a hidden
   prompt.
4. Tokens live in `~/.xurl`. For a server deployment, run the auth locally
   and copy that directory over. Never commit it or copy it into skill state.
