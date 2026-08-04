# Manual setup

`scripts/setup.sh` automates everything on this page and is the recommended
path. This walkthrough exists for people who want to see every command before
running it, or need to debug a single layer. Total time is maybe half an hour
if the X console cooperates.

Prerequisites: an X account, a Telegram account, and
[OpenClaw](https://docs.openclaw.ai) on a supported Node (22.22+ or 24.15+;
`nvm install 24` settles it). The `gh` CLI must be authenticated
(`gh auth status`) so the agent can read your repos.

## 1. Install the skill

```sh
./scripts/install.sh          # copies the skill into <workspace>/skills/x-poster
./scripts/install.sh --dev    # symlinks it for live editing
```

Dev mode needs the symlink target trusted via
`skills.load.allowSymlinkTargets` in `~/.openclaw/openclaw.json`; the
installer prints the exact snippet. Confirm with `openclaw skills list` —
x-poster should show `✓ ready`.

## 2. Point the agent at a real model

Small local models write exactly the slop VOICE.md bans, so use a frontier
model. Either a Claude or a ChatGPT/Codex subscription works — no API bill
in both cases. The voice rules were tuned and validated on Claude; the
OpenAI path is supported but its draft quality hasn't been through the same
runs yet.

**Claude subscription:**

```sh
openclaw models auth setup-token --provider anthropic
openclaw config set agents.defaults.model.primary "anthropic/claude-fable-5"
```

`setup-token` needs a real terminal — it walks you through a browser approval
on claude.ai and stores the token.

**ChatGPT/Codex subscription:**

```sh
openclaw models auth login --provider openai    # add --device-code on a headless box
openclaw models list --provider openai          # pick the subscription tier from this list
openclaw config set agents.defaults.model.primary "openai/gpt-5.6-sol"
```

Prefer `openai/gpt-5.6-sol` if listed (older OpenClaw releases only show
`gpt-5.6-terra` — use that instead). Never set plain `openai/gpt-5.6`: that
is the API-key alias, and it silently bills a developer account instead of
your subscription. For the same reason, after any `openclaw doctor --fix`
re-check `openclaw models status` — released versions have rewritten
Codex-subscription routes to API-billed ones (openclaw#79461).

Whichever provider you chose, verify the wiring end to end:

```sh
openclaw agent --local --agent main -m "Reply with exactly: auth-ok"
```

## 3. X API access

The fiddly part, because the developer console has opinions. In order:

1. At [console.x.com](https://console.x.com/), create a **project** and an
   app **inside it**. A standalone app authenticates fine and then fails
   every v2 call with `client-not-enrolled` — the app must be
   project-attached and the project on a package with write access (the
   entry-level tier covers three posts a day with room to spare).
2. In the app's **User authentication settings**: enable OAuth 2.0, pick
   **"Web App, Automated App or Bot"**, set the callback URI to exactly
   `http://localhost:8080/callback`, and fill in any real website URL.
3. Install [xurl](https://github.com/xdevplatform/xurl), X's official OAuth
   CLI (release binaries only, no brew formula). Pin the version and verify
   the checksum — this binary is about to be handed your client secret, and
   `latest` is a mutable pointer (`setup.sh` does exactly the same):

   ```sh
   XURL_VERSION=1.3.1
   curl -sLO "https://github.com/xdevplatform/xurl/releases/download/v${XURL_VERSION}/xurl_Darwin_arm64.tar.gz"
   curl -sLO "https://github.com/xdevplatform/xurl/releases/download/v${XURL_VERSION}/xurl_${XURL_VERSION}_checksums.txt"
   grep " xurl_Darwin_arm64.tar.gz$" "xurl_${XURL_VERSION}_checksums.txt" | shasum -a 256 -c -
   tar xzf xurl_Darwin_arm64.tar.gz && mv xurl ~/.local/bin/
   ```

   (That's Apple Silicon; the releases page has Linux and Windows tarballs
   under the same naming scheme — on Linux use `sha256sum -c -` instead of
   `shasum -a 256 -c -`.)

4. Register the app's OAuth 2.0 client credentials and authorize:

   ```sh
   xurl auth apps add x-poster --client-id YOUR_CLIENT_ID --client-secret YOUR_CLIENT_SECRET
   xurl auth oauth2 --app x-poster
   xurl auth default x-poster    # bare xurl commands now use this app
   xurl /2/users/me              # prints your handle when everything works
   ```

   One caveat: xurl only accepts the secret as a flag, so as typed above it
   lands in your shell history in plaintext. Start the command with a leading
   space if your shell ignores space-prefixed commands (zsh
   `setopt HIST_IGNORE_SPACE`, bash `HISTCONTROL=ignorespace`); otherwise
   delete the history line afterward, and rotate the secret at console.x.com
   if you suspect it leaked. (`setup.sh` avoids this with a hidden prompt.)

   The consent flow requests `offline.access`, so headless runs refresh
   their own tokens and never re-prompt. Tokens live in `~/.xurl` — for a
   server, authorize locally and copy that directory over.

### Optional: media tools

Repo posts are media-first (a demo GIF or code screenshot, with the link
posted as a reply). The agent generates that media with whatever it finds
on `PATH`:

```sh
brew install vhs charmbracelet/tap/freeze   # macOS; both have Linux builds
```

`vhs` renders terminal demos to GIF, `freeze` screenshots code to PNG.
Neither is required — without them the skill falls back to existing repo
assets and finally to text-only posts (the ladder is in CONTENT.md "Media
recipes") — but the media posts are the point, so install at least one.

## 4. Telegram approvals

Create a bot with [@BotFather](https://t.me/BotFather) (`/newbot`), then
register it. Use the token-file form so the token stays out of your shell
history and the process table; the file must persist — OpenClaw stores the
path and reads it at runtime:

```sh
mkdir -p ~/.openclaw/credentials && chmod 700 ~/.openclaw/credentials
read -rs token && printf '%s' "$token" > ~/.openclaw/credentials/telegram-bot-token \
  && chmod 600 ~/.openclaw/credentials/telegram-bot-token && unset token
openclaw channels add --channel telegram --token-file ~/.openclaw/credentials/telegram-bot-token
openclaw gateway install
```

(The `read -rs` line waits silently — paste the token and press enter.)

Message your new bot once from your own account. It replies with your user
id and a pairing code; approve it and make yourself the command owner:

```sh
openclaw pairing approve telegram THE_CODE
openclaw config set commands.ownerAllowFrom '["telegram:YOUR_USER_ID"]'
openclaw gateway restart
```

Finally, put the same user id in `skill/x-poster/state/settings.json` as
`telegramTo`. That field is the approval gate: only that sender can ship a
draft, and while it's empty the skill runs in draft mode — writes drafts to
`state/drafts.md`, sends nothing, posts nothing.

## 5. Make it sound like you

Two local files the repo never sees:

- `state/settings.json` → `styleAccounts`: a few public accounts whose
  register you want studied during style refreshes.
- `voice-examples.local.md`: 3 to 5 of your own tweets. These outrank
  everything else, so the output stays yours rather than generically fluent.

## 6. Test, then schedule

Run one turn in draft mode (leave `telegramTo` empty) and read the result in
`state/drafts.md` against VOICE.md:

```sh
openclaw agent --local --agent main -m "x-poster drafting turn: draft one post for slot 1 of the pillar schedule (CONTENT.md Pillars)."
```

Then set `telegramTo`, message your bot "x-poster: draft a post", and reply
`skip` — the draft should land in `state/skipped/` and nowhere else. Only
after a full draft → `ship` → verified permalink round trip should you
register the cron jobs; the installer prints the exact commands (three
drafting turns a day plus a weekly backlog refresh, isolated sessions).
The drafting messages are slot-numbered and pillar-agnostic — which pillar
a slot gets comes from the weekly grid in CONTENT.md, so rescheduling
never means editing cron messages. If you installed before the pillar
system, your jobs still carry the old per-topic messages: rerun
`./scripts/setup.sh` and it detects the drift and recreates them in place
(same schedule, same route), or delete and recreate them by hand.
The example times target US engagement windows (anchored to
America/New_York so they track US DST) — shift them to fit your audience
and your own waking hours, since every draft waits on your reply.

One trap worth knowing: cron delivery defaults to `announce -> last`, which
has no route in an isolated session and fails closed. Always pass
`--channel telegram --to YOUR_USER_ID` when creating the jobs (setup.sh
does this for you).

If the bot's behavior doesn't match an edit you just made to the skill
files, or it kept an old model after a config change, send `/new` to the
bot: the persistent session only re-reads everything when it starts.
