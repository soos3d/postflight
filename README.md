# x-openclaw

An [OpenClaw](https://docs.openclaw.ai) skill that keeps my X account active.
It drafts posts about my open source repos, sends each one to my Telegram, and
publishes only when I reply `ship`.

I built it because my posting pattern was three tweets in one afternoon, then
five weeks of silence. Cadence is what grows an account, and cadence is
exactly the kind of boring discipline a personal agent is good at. What I
didn't want was a bot posting to my real account unsupervised, so the contract
is fixed: the agent drafts, I approve, it ships. There is no autonomous mode.

## The loop

Three times a day, a cron job wakes the agent in an isolated session — each
slot with its own focus (my open source work, AI tools/news, aviation) and
timed for when a US audience is actually scrolling:

1. Check the post log. Three posts a day maximum, nothing resembling the last
   ten topics.
2. Gather real material: recent commits, releases, and READMEs from my public
   repos via the `gh` CLI, plus AI stories from the Hacker News API. Facts it
   didn't retrieve don't go in a draft. The aviation slot draws on my flying
   and instructing instead — instructional tips and cool facts, never
   accident commentary.
3. Write one tweet following the voice guide, picking the best of three
   internal candidates, then verify the length by running X's character
   weighting as a shell one-liner instead of counting in its head.
4. Send it to my Telegram: reply `ship` to post, `skip` to discard, or
   describe a change and it revises.
5. On `ship`, post through the X API v2 (via `xurl`, X's official OAuth CLI),
   confirm the returned tweet id, log the URL.

Approval means the exact word `ship`, from my Telegram user id, while a draft
is pending. "ship it" is an edit request. A message from anyone else is
ignored. Drafts older than 24 hours get archived, never posted.

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
  me, my reply arrives as a normal turn with reply-chain context, and the
  agent acts on it. The approval flow needed zero custom plumbing.
- **The whole thing runs headless.** API posting plus Telegram approvals
  means no display server anywhere, so the same install works on a laptop or
  a small VPS. (For accounts without a developer app, OpenClaw's managed
  browser profile is the documented fallback: an isolated Chromium you log
  into X once.)
- **Model auth reuses my Claude subscription** through
  `openclaw models auth setup-token`. No separate API bill for a tool that
  runs four short turns a day.

## The voice guide is the actual product

Generating tweets is trivial. Generating tweets a developer would read
without wincing took most of the design work. `VOICE.md` bans hashtags,
engagement bait, thread emoji, "excited to announce", and the phrasing tics
that mark text as machine output. Every post must contain something a reader
can use: a command, a gotcha, an error message, a number, a link to real
code. Drafts that fail the test get rewritten before I ever see them.

The register is calibrated on real developer accounts you pick yourself (a
local `styleAccounts` setting, kept out of the repo), and 3 to 5 of your own
tweets in `voice-examples.local.md` outrank everything else, so the account
still sounds like you. As a side effect, my test run made the case for model
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

## Getting started

One command runs everything scriptable and walks you through the two things
that can't be automated — creating the X app and the Telegram bot:

```sh
curl -fsSL https://raw.githubusercontent.com/Soos3D/x-openclaw/main/scripts/setup.sh | bash
```

Or, if piping curl into bash isn't your thing, clone first and run
`./scripts/setup.sh` — same script (`--dev` symlinks the skill for live
editing). Have three things ready before you start:

- [OpenClaw](https://docs.openclaw.ai) installed and onboarded, on Node
  22.22+ or 24.15+ (`nvm install 24` settles it)
- An X account with access to [console.x.com](https://console.x.com/) —
  the wizard tells you the exact three clicks when it gets there
- A Telegram bot token from [@BotFather](https://t.me/BotFather) (`/newbot`)

Every step probes real state before acting — it verifies model auth, X auth
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

## About X's terms

The default path posts through the official API with OAuth, which is exactly
what X's automation rules ask for, and per-post human approval keeps it well
clear of their spam policies. The browser fallback exists for accounts
without a developer app; that mode sits outside the automation rules, so
treat it as a stopgap and use it at your own risk.

## License

MIT.
