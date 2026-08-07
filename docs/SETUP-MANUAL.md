# Manual setup

`./scripts/setup.sh` automates everything on this page and is the
recommended path. This walkthrough is for people who want to see every
command before running it, or who need to debug one layer.

Budget about half an hour, most of it in the X console.

**Before you start:** an X account, a Telegram account, and
[OpenClaw](https://docs.openclaw.ai) on Node 22.22+ or 24.15+
(`nvm install 24` settles it). The `gh` CLI must be authenticated
(`gh auth status`) so the agent can read your repos.

Six steps:

1. [Install the skill](#1-install-the-skill)
2. [Connect a model](#2-connect-a-model)
3. [Set up X API access](#3-set-up-x-api-access)
4. [Set up Telegram approvals](#4-set-up-telegram-approvals)
5. [Add your personal files](#5-add-your-personal-files)
6. [Test, then schedule](#6-test-then-schedule)

---

## 1. Install the skill

Pick one:

```sh
./scripts/install.sh          # copies the skill into <workspace>/skills/postflight
./scripts/install.sh --dev    # symlinks it, for live editing
```

Verify:

```sh
openclaw skills list          # postflight should show ✓ ready
```

> **Using `--dev`?** The symlink target must be trusted via
> `skills.load.allowSymlinkTargets` in `~/.openclaw/openclaw.json`. The
> installer prints the exact snippet to paste.

### From ClawHub instead

The skill is published at
[clawhub.ai/soos3d/skills/postflight](https://clawhub.ai/soos3d/skills/postflight),
so you can install it without cloning anything:

```sh
openclaw skills install @soos3d/postflight
openclaw skills install @soos3d/postflight --version 1.2.0   # or pin it
```

It prompts you to acknowledge ClawHub's trust warning before unpacking. The
files land in `~/.openclaw/workspace/skills/postflight`, the same place
`install.sh` copies them, and it refuses to run if something is already
there — that refusal keeps it from overwriting an install you already have.

What ships is the reviewed list in `scripts/clawhub-manifest.txt`: the
instruction files, `ingest-photo.sh`, `pillars.example.md`, and
`settings.example.json`. Nothing personal is on it, and nothing personal
lives in that folder any more either — since v1.2.0 your settings, post log,
metrics, photo library, and both `*.local.md` files live in
`~/.openclaw/workspace/postflight-state/`, one level up from `skills/`.

That is what makes the registry path work as more than a first install. The
skill folder holds instructions and nothing else, so replacing it costs
nothing:

```sh
openclaw skills update @soos3d/postflight    # safe from 1.2.0 onward
```

The state directory is created on demand — by `setup.sh`, by
`scripts/install.sh`, or by the skill itself on its first turn — so a
ClawHub install needs no scaffolding step. Steps 2 through 6 below are
unchanged either way: the registry hands you instructions, not a working X
app, Telegram bot, or cron schedule.

> **The one upgrade that is not safe is 1.1.0 → 1.2.0.** Before 1.2.0 the
> state directory was *inside* the skill folder, and `openclaw skills
> update` replaces that folder wholesale — the old one is moved aside and
> deleted once the new files land. The relocation cannot run until the new
> files exist, and by then the old directory is gone. So this specific hop
> takes your post log, metrics, photo library, and both `*.local.md` files
> with it.
>
> Make that one hop with `git pull && ./scripts/install.sh`, which moves
> your state out of the way first. With no checkout, copy the directory
> somewhere safe and put it back under its new name afterward:
>
> ```sh
> cp -R ~/.openclaw/workspace/skills/postflight/state /tmp/pf-state
> openclaw skills update @soos3d/postflight
> mv /tmp/pf-state ~/.openclaw/workspace/postflight-state
> ```
>
> Every upgrade after that one is a plain `skills update`.

## 2. Connect a model

Use a frontier model. Small local models write exactly the slop `VOICE.md`
bans. A Claude or ChatGPT/Codex subscription works, with no API bill in
either case.

> The voice rules were tuned and validated on Claude. The OpenAI path is
> supported, but its draft quality hasn't been through the same runs.

**If you have a Claude subscription:**

```sh
openclaw models auth setup-token --provider anthropic
openclaw config set agents.defaults.model.primary "anthropic/claude-fable-5"
openclaw models list --provider anthropic     # check these ids exist in your release
openclaw config set agents.defaults.model.fallbacks \
  '["anthropic/claude-opus-4-8","anthropic/claude-sonnet-5"]' --strict-json
```

`setup-token` needs a real terminal. It walks you through a browser
approval on claude.ai and stores the token.

Fable has its own usage pool. Once it's spent there's still Opus budget on
the same subscription, and the fallback chain drops to it instead of failing
the slot. Run `models list` first: the catalog differs by OpenClaw release,
and `config set` accepts an id that doesn't exist without complaining — you
find out when an unattended slot dies. `setup.sh` tries
`anthropic/claude-opus-5` ahead of these two and keeps it only when the
install lists it; do the same by hand if it's in your catalog.

**If you have a ChatGPT/Codex subscription:**

```sh
openclaw models auth login --provider openai    # add --device-code on a headless box
openclaw models list --provider openai          # pick your subscription tier from this list
openclaw config set agents.defaults.model.primary "openai/gpt-5.6-sol"
openclaw config set agents.defaults.model.fallbacks \
  '["openai/gpt-5.6-terra","openai/gpt-5.5"]' --strict-json
```

Use `openai/gpt-5.6-sol` if it's listed. Older OpenClaw releases show only
`openai/gpt-5.6-terra`, which is the right choice there — in that case drop
it from the fallback list, since a model can't fall back to itself.

> **Never set plain `openai/gpt-5.6`.** That's the API-key alias, and it
> silently bills a developer account instead of your subscription. For the
> same reason, re-check `openclaw models status` after any
> `openclaw doctor --fix` — released versions have rewritten
> Codex-subscription routes to API-billed ones
> ([openclaw#79461](https://github.com/openclaw/openclaw/issues/79461)).

**Then verify the wiring, whichever provider you chose:**

```sh
openclaw agent --local --agent main -m "Reply with exactly: auth-ok"
```

## 3. Set up X API access

The fiddly part, because the developer console has opinions.

### 3.1 Create a project and an app

At [console.x.com](https://console.x.com/), create a **project**, then
create an app **inside it**.

> A standalone app authenticates fine and then fails every v2 call with
> `client-not-enrolled`. The app must be project-attached, and the project
> on a package with write access. The entry-level tier covers three posts a
> day with room to spare.

Budget roughly 4–5 posts a day of quota rather than 3: a repo post ships as
two, the tweet plus its link reply. Posting is pay-per-use since the free
tier ended in Feb 2026, observed at about $0.02 per post.

### 3.2 Configure authentication

In the app's **User authentication settings**:

- Enable **OAuth 2.0**
- App type: **Web App, Automated App or Bot**
- Callback URI: exactly `http://localhost:8080/callback`
- Website URL: any real URL

### 3.3 Install xurl

[xurl](https://github.com/xdevplatform/xurl) is X's official OAuth CLI.
Release binaries only, no brew formula.

```sh
XURL_VERSION=1.3.1
curl -sLO "https://github.com/xdevplatform/xurl/releases/download/v${XURL_VERSION}/xurl_Darwin_arm64.tar.gz"
curl -sLO "https://github.com/xdevplatform/xurl/releases/download/v${XURL_VERSION}/xurl_${XURL_VERSION}_checksums.txt"
grep " xurl_Darwin_arm64.tar.gz$" "xurl_${XURL_VERSION}_checksums.txt" | shasum -a 256 -c -
tar xzf xurl_Darwin_arm64.tar.gz && mkdir -p ~/.local/bin && mv xurl ~/.local/bin/
```

`~/.local/bin` has to be on your `PATH` — the skill calls `xurl` by name.

> **Pin the version and verify the checksum.** This binary is about to be
> handed your client secret, and `latest` is a mutable pointer. `setup.sh`
> does exactly the same.

That's Apple Silicon. The releases page has Linux and Windows tarballs
under the same naming scheme; on Linux use `sha256sum -c -` instead of
`shasum -a 256 -c -`.

### 3.4 Authorize

```sh
xurl auth apps add postflight --client-id YOUR_CLIENT_ID --client-secret YOUR_CLIENT_SECRET
xurl auth oauth2 --app postflight
xurl auth default postflight    # bare xurl commands now use this app
xurl /2/users/me              # prints your handle when everything works
```

> **The secret lands in your shell history in plaintext**, because xurl
> accepts it only as a flag. Start the command with a leading space if your
> shell ignores space-prefixed commands (zsh `setopt HIST_IGNORE_SPACE`,
> bash `HISTCONTROL=ignorespace`). Otherwise delete the history line
> afterward, and rotate the secret at console.x.com if you suspect it
> leaked. `setup.sh` avoids this with a hidden prompt.

The consent flow requests `offline.access`, so headless runs refresh their
own tokens and never re-prompt, and `media.write`, which media posts need.
A token minted by an older xurl predates that scope and 403s on the first
upload; re-running `xurl auth oauth2 --app postflight` fixes it.

Tokens live in `~/.xurl`. For a server, authorize locally and copy that
directory over.

### 3.5 No developer app? The browser fallback

Everything above is the default path and the one built for headless
servers. If you can't get API access, the skill can drive a logged-in
browser instead:

```sh
openclaw browser open https://x.com     # log in once, in the managed profile
```

Then set `"postVia": "browser"` in `postflight-state/settings.json`. That mode needs a
machine with a display, publishes single text posts only, and sits outside
X's automation rules — see `PUBLISH-BROWSER.md` in the skill folder before
you rely on it.

### 3.6 Optional: media tools

Repo posts are media-first — a demo GIF or code screenshot, with the link
posted as a reply. The agent generates that media with whatever it finds on
`PATH`:

```sh
brew install vhs charmbracelet/tap/freeze   # macOS; both have Linux builds
```

`vhs` renders terminal demos to GIF, `freeze` screenshots code to PNG.
Neither is required. Without them the skill falls back to existing repo
assets, then to text-only posts (the ladder is in `CONTENT.md` under "Media
recipes"). The media posts are the point, so install at least one.

## 4. Set up Telegram approvals

### 4.1 Create the bot

Create it with [@BotFather](https://t.me/BotFather) (`/newbot`), then
register it:

```sh
mkdir -p ~/.openclaw/credentials && chmod 700 ~/.openclaw/credentials
read -rs token && printf '%s' "$token" > ~/.openclaw/credentials/telegram-bot-token \
  && chmod 600 ~/.openclaw/credentials/telegram-bot-token && unset token
openclaw channels add --channel telegram --token-file ~/.openclaw/credentials/telegram-bot-token
openclaw gateway install
```

The `read -rs` line waits silently. Paste the token and press enter.

> The token-file form keeps the token out of your shell history and the
> process table. **The file must persist** — OpenClaw stores the path and
> reads it at runtime.

### 4.2 Pair your account

Message your new bot once from your own account. It replies with your user
id and a pairing code:

```sh
openclaw pairing approve telegram THE_CODE
openclaw config set commands.ownerAllowFrom '["telegram:YOUR_USER_ID"]'
openclaw gateway restart
```

### 4.3 Set the approval gate

Put the same user id in `~/.openclaw/workspace/postflight-state/settings.json`
as `telegramTo`. That is one path for every install shape — copy, `--dev`
symlink, or ClawHub — because the state directory is anchored to the
workspace rather than to wherever the skill files landed.

That field is the approval gate: only that sender can ship a draft. While
it's empty the skill runs in draft mode, writing to
`postflight-state/drafts.md`, sending nothing and posting nothing.

## 5. Add your personal files

Three local files the repo never sees. Full walkthrough in
[CUSTOMIZE.md](CUSTOMIZE.md).

| File | What goes in it |
|---|---|
| `pillars.local.md` | Your content pillars and weekly schedule. Copy the skill folder's `pillars.example.md` into `postflight-state/`, edit it, and delete its `TEMPLATE` line. Without this file, the generic default schedule runs |
| `voice-examples.local.md` | 3 to 5 of your own tweets. These outrank everything else, so the output stays yours rather than generically fluent |
| `settings.json` → `styleAccounts` | A few public accounts whose register you want studied during style refreshes |

## 6. Test, then schedule

Work through these in order. Don't register cron jobs until the round trip
works.

### 6.1 Draft mode

Leave `telegramTo` empty and run one turn:

```sh
openclaw agent --local --agent main -m "postflight drafting turn: draft one post for slot 1 of the pillar schedule (CONTENT.md Pillars)."
```

Read the result in `postflight-state/drafts.md` against `VOICE.md`.

### 6.2 Telegram round trip

Set `telegramTo`, message your bot `postflight: draft a post`, and reply
`skip`. The draft should land in `postflight-state/skipped/` and nowhere else.

Then run one full `ship` and confirm the permalink.

### 6.3 Register cron

Only now. Four jobs: three drafting turns a day plus a weekly maintenance
turn (backlog refresh and metrics readback), all in isolated sessions.
These are exactly what `setup.sh` registers.

```sh
TO=YOUR_TELEGRAM_USER_ID
TZ_NAME=America/New_York

openclaw cron create "30 9 * * *" \
  "Run the postflight skill: draft one post for slot 1 of the pillar schedule (CONTENT.md Pillars) and request approval." \
  --name postflight-own-work --session isolated --tz "$TZ_NAME" --channel telegram --to "$TO"

openclaw cron create "30 12 * * *" \
  "Run the postflight skill: draft one post for slot 2 of the pillar schedule (CONTENT.md Pillars) and request approval." \
  --name postflight-ai-news --session isolated --tz "$TZ_NAME" --channel telegram --to "$TO"

openclaw cron create "0 15 * * *" \
  "Run the postflight skill: draft one post for slot 3 of the pillar schedule (CONTENT.md Pillars) and request approval." \
  --name postflight-aviation --session isolated --tz "$TZ_NAME" --channel telegram --to "$TO"

openclaw cron create "0 8 * * 1" \
  "postflight maintenance turn: refresh the content backlog per CONTENT.md, all pillar sections, then run the weekly metrics readback per CONTENT.md \"Metrics readback\". Do not draft or publish." \
  --name postflight-backlog --session isolated --tz "$TZ_NAME" --channel telegram --to "$TO"
```

> **Always pass `--channel telegram --to YOUR_USER_ID`.** Cron delivery
> defaults to `announce -> last`, which has no route in an isolated session
> and fails closed. `setup.sh` does this for you; by hand it's the easiest
> thing to forget.

> The three drafting job **names** are historical — `own-work`, `ai-news`,
> and `aviation` were the original fixed topics. Keep them as written:
> `setup.sh` matches on those names, and renaming one makes it register a
> duplicate slot. What each job posts comes from the weekly grid, not its
> name.

The example times target US engagement windows, anchored to
`America/New_York` so they track US DST. Shift them to fit your audience
and your own waking hours, since every draft waits on your reply.

Drafting messages are slot-numbered and pillar-agnostic. Which pillar a
slot gets comes from the weekly grid in `CONTENT.md`, so rescheduling never
means editing cron messages.

> **Installed before the pillar system?** Your jobs still carry the old
> per-topic messages. Rerun `./scripts/setup.sh` and it detects the drift
> and recreates them in place, keeping the same schedule and route.

---

Something not working? See [TROUBLESHOOTING.md](TROUBLESHOOTING.md).
