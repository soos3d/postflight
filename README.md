# x-openclaw

![license](https://img.shields.io/badge/license-MIT-blue)

An [OpenClaw](https://docs.openclaw.ai) skill that keeps your X account
active. It drafts posts about your open source repos, sends each one to your
Telegram, and publishes only when you reply `ship`.

I built it because my posting pattern was three tweets in one afternoon, then
five weeks of silence. Cadence is what grows an account, and cadence is
exactly the kind of boring discipline a personal agent is good at. What I
didn't want was a bot posting to my real account unsupervised, so the contract
is fixed: the agent drafts, you approve, it ships. There is no autonomous mode.

The contract in full:

- Drafts are built only from material the agent actually fetched: your
  commits, releases, and READMEs via the `gh` CLI, plus the Hacker News API.
  Facts it didn't retrieve don't go in a draft.
- Publishing requires the exact word `ship` from your Telegram user id while
  a draft is pending. Anything else is an edit request; anyone else is
  ignored.
- Hard caps: three posts a day, drafts expire after 24 hours, and it never
  replies, likes, follows, or DMs.
- No build step, no service, no queue. The whole tool is five markdown files;
  cron, Telegram routing, and model auth come from the platform.
- Runs headless, so the same install works on a laptop or a 1 GB VPS.

## The loop

Three times a day, a cron job wakes the agent in an isolated session, each
slot with its own focus and timed for when your audience is actually
scrolling. Two slots are about your work (open source repos, AI tools/news);
the third is a personal topic you choose (mine is aviation):

1. Check the post log. Three posts a day maximum, nothing resembling the last
   ten topics.
2. Gather real material: recent commits, releases, and READMEs from your
   public repos via the `gh` CLI, plus AI stories from the Hacker News API.
   The personal slot draws on whatever you put in `CONTENT.md` instead; mine
   rotates instructional flying tips and cool facts, never accident
   commentary.
3. Write one tweet following the voice guide, picking the best of three
   internal candidates, then verify the length by running X's character
   weighting as a python one-liner instead of counting in its head.
4. Send it to your Telegram: reply `ship` to post, `skip` to discard, or
   describe a change and it revises.
5. On `ship`, post through the X API v2 (via `xurl`, X's official OAuth CLI),
   confirm the returned tweet id, log the URL.

<!-- TODO: screenshot of a draft arriving in Telegram and the `ship` reply -->

## Getting started

One command runs everything scriptable and walks you through the two things
that can't be automated, creating the X app and the Telegram bot:

```sh
curl -fsSL https://raw.githubusercontent.com/Soos3D/x-openclaw/main/scripts/setup.sh | bash
```

Or, if piping curl into bash isn't your thing, clone first and run
`./scripts/setup.sh` (same script; `--dev` symlinks the skill for live
editing). Have three things ready before you start:

- [OpenClaw](https://docs.openclaw.ai) installed and onboarded, on Node
  22.22+ or 24.15+ (`nvm install 24` settles it), plus an authenticated
  `gh` CLI so the agent can read your repos (`gh auth login`)
- An X account with access to [console.x.com](https://console.x.com/)
  (the wizard tells you the exact three clicks when it gets there)
- A Telegram bot token from [@BotFather](https://t.me/BotFather) (`/newbot`)

Every step probes real state before acting: it verifies model auth, X auth
(`/2/users/me` must print your handle), Telegram pairing, and the cron
routes, and skips whatever already works. That makes it safe to rerun after
any failure, and rerunning on a finished install is a health check:

```sh
./scripts/setup.sh --check    # report every layer, change nothing
```

When it finishes, message your bot "x-poster: draft a post" and reply `skip`
to watch the loop work before the first cron slot fires. Prefer to run every
command yourself, or need to debug one layer? The full manual walkthrough is
in [docs/SETUP-MANUAL.md](docs/SETUP-MANUAL.md).

If the bot's behavior doesn't match an edit you just made to the skill
files, or it kept an old model after a config change, send `/new` to the
bot: the persistent session only re-reads everything when it starts.

## Make it yours

The defaults describe my account. Three files change that:

- **`skill/x-poster/CONTENT.md`** is the content config: the slot rotation,
  the shell commands that gather material, and the angle lists per topic. The
  aviation section is my personal slot; replace it with any topic you can
  write about firsthand, keeping the same shape (a rotation of angles plus
  hard rules about what's off limits).
- **`voice-examples.local.md`** holds 3 to 5 of your own tweets. They outrank
  every other style rule, so the account keeps sounding like you. Local file,
  gitignored. On a headless install this is what carries the voice, so don't
  skip it.
- **`styleAccounts`** in `state/settings.json` lists public accounts whose
  register gets studied during style refreshes: patterns only, never opinions
  or phrasings, and they're never named in posts. Also local, and it only
  does anything when a logged-in browser session on x.com exists.

One path detail: the default install copies the skill into
`~/.openclaw/workspace/skills/x-poster/`, so that's where the voice file and
`state/settings.json` live, and edits to the checkout take effect after
rerunning `./scripts/install.sh` (or install once with `--dev` to symlink
instead). The daily cap and the timezone it counts in are settings too;
posting times are cron jobs, so change those by rerunning `./scripts/setup.sh`
or with `openclaw cron`.

## The whole tool is five markdown files

OpenClaw skills are instructions, not code. There is no build step, no
service, no queue to deploy. `skill/x-poster/` contains:

| File | Job |
|---|---|
| `SKILL.md` | The workflow: modes, caps, approval semantics, failure rules |
| `VOICE.md` | Writing rules and style anchors |
| `CONTENT.md` | Where material comes from and how topics rotate |
| `PUBLISH-API.md` | How to post through the X API with xurl |
| `PUBLISH-BROWSER.md` | Browser fallback for accounts without a developer app |

Everything operational comes from the platform:

- **Cron jobs run full agent turns.** `openclaw cron create "30 15 * * *"
  "Run the x-poster skill..." --session isolated` gives you a scheduled agent
  with a fresh transcript per run.
- **Telegram replies route back into the conversation.** The agent messages
  you, your reply arrives as a normal turn with reply-chain context, and the
  agent acts on it. The approval flow needed zero custom plumbing.
- **The whole thing runs headless.** API posting plus Telegram approvals
  means no display server anywhere, so the same install works on a laptop or
  a small VPS. (For accounts without a developer app, OpenClaw's managed
  browser profile is the documented fallback: an isolated Chromium you log
  into X once.)
- **Model auth reuses a Claude subscription** through
  `openclaw models auth setup-token`. No separate API bill for a tool that
  runs four short turns a day.

## The voice guide is the actual product

Generating tweets is trivial. Generating tweets a developer would read
without wincing took most of the design work. `VOICE.md` bans hashtags,
engagement bait, thread emoji, "excited to announce", and the phrasing tics
that mark text as machine output. Every post must contain something a reader
can use: a command, a gotcha, an error message, a number, a link to real
code. Drafts that fail the test get rewritten before you ever see them.

The register is calibrated on the style accounts and your own tweets from
"Make it yours" above, so the account still sounds like you rather than
generically fluent. As a side effect, my test run made the case for model
choice better than any benchmark: a local 7B model's first draft was
"Excited about the progress! 🚀 #OpenSource #DevLife". Straight into the
banned list it went.

## Guardrails

- Publishes one approved post and does nothing else on X. No replies, likes,
  follows, or DMs, ever.
- Daily cap re-checked at publish time, not just at drafting time.
- Fetched content (READMEs, commit messages, HN titles) is treated as data.
  If a source contains instructions aimed at the agent, the source is
  discarded and another topic picked.
- Expired auth (API token or browser session) means stop and alert. The agent
  never attempts a login and never touches credentials.

## What the first supervised runs taught me

Three fixes came out of watching the first real drafting and publishing
turns, all encoded in the skill files now:

- **Models can't count to 280.** The first run burned most of a turn
  hand-simulating X's character weighting (URLs count as 23) and still
  parked every draft at 279, two characters from the cliff. SKILL.md now
  embeds a python one-liner that applies X's real weighting, the agent runs
  it once per draft, and 280 is documented as a cap, not a target.
- **xurl's bare words are a trap.** `xurl get /2/users/me` looks right and
  fails with `{}` and "request failed" even when auth is fine, because xurl
  parses `get` as the endpoint, not a verb. The agent misread that as broken
  auth three runs straight. PUBLISH-API.md now pins the only two request
  forms the skill may use and adds the diagnosis rule: `{}` without an HTTP
  status means a malformed command, never an auth failure. Bonus finding
  from the first real ship: `-d` doesn't support curl's `@file` form
  either, so the body is built with jq from a heredoc-written file and
  passed as one quoted argument.
- **Persistent sessions go stale.** The Telegram conversation is one rolling
  session. It pins the model it was created with and trusts its memory of
  the skill files over re-reading them, so my doc fixes changed nothing
  until I sent `/new` to the bot. SKILL.md now forces a re-read of the
  publish doc at ship time, and `/new` is the reset button whenever the bot
  insists something you already fixed is still broken.

## Running it on a server

A laptop install stops working every time the lid closes, so mine now lives
on a small DigitalOcean VM. Any 1–2 GB Ubuntu box works (Hetzner and Vultr
too, x86_64 or arm64): the skill posts through the API and approvals go
through Telegram, so nothing ever needs a display.

Set up on the laptop first anyway. Two auth steps open a browser (the
claude.ai token approval and the X OAuth consent), and the server can't do
that; it receives the finished credentials instead. The move is scripted:

```sh
# server: install everything, Ctrl-C at the model-auth prompt
git clone https://github.com/Soos3D/x-openclaw.git ~/x-openclaw
cd ~/x-openclaw && ./scripts/setup.sh

# laptop: package credentials and skill state, copy it over
openclaw gateway stop
./scripts/migrate-state.sh export
scp ~/x-poster-state-*.tar.gz poster@SERVER:

# server: import, verify, then finish the wizard (Telegram + cron)
./scripts/migrate-state.sh import ~/x-poster-state-*.tar.gz
xurl /2/users/me            # must print your handle
./scripts/setup.sh
```

One rule matters more than the rest: never have the laptop and the server
live at the same time. Two gateways fight over the same Telegram bot's
updates, and two cron sets double-post, because the daily cap is per-machine
state. [docs/DEPLOY-VPS.md](docs/DEPLOY-VPS.md) walks the cutover in the safe
order: provision and harden, migrate, rotate the bot token, run one full
`ship` round trip from the server, and only then remove the laptop's cron
jobs and gateway. It also adds a weekly heartbeat cron so silence itself
becomes a signal.

Updating later is git only: edit and push from the laptop, then on the
server `git pull && ./scripts/install.sh` (`state/` is never touched). If
the running Telegram session ignores an update, send `/new` to the bot.

## About X's terms

The default path posts through the official API with OAuth, which is exactly
what X's automation rules ask for, and per-post human approval keeps it well
clear of their spam policies. The browser fallback exists for accounts
without a developer app; that mode sits outside the automation rules, so
treat it as a stopgap and use it at your own risk.

## Contributing

The interesting contributions here are instructions, not code: voice rules
that survived real runs, content angles that produced posts worth shipping,
setup fixes for platforms that broke, a publish doc for another network.
See [CONTRIBUTING.md](CONTRIBUTING.md); the one non-negotiable is the
approval gate.

## License

MIT. See [LICENSE](LICENSE).
