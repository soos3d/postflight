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

Twice a day, a cron job wakes the agent in an isolated session:

1. Check the post log. Two posts a day maximum, nothing resembling the last
   ten topics.
2. Gather real material: recent commits, releases, and READMEs from my public
   repos via the `gh` CLI, plus AI stories from the Hacker News API. Facts it
   didn't retrieve don't go in a draft.
3. Write one tweet following the voice guide, picking the best of three
   internal candidates.
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

- **Cron jobs run full agent turns.** `openclaw cron create "30 9 * * *"
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

## Install

```sh
./scripts/install.sh          # copies the skill into <workspace>/skills/x-poster
./scripts/install.sh --dev    # symlinks it for live editing
```

The installer creates the state directory and prints the one-time interactive
steps: model auth, X API auth via xurl (a free developer app covers the
volume comfortably), Telegram bot pairing, and the cron registrations. Dev
mode needs the symlink target trusted via `skills.load.allowSymlinkTargets`
in `~/.openclaw/openclaw.json`; the installer prints the exact snippet.
Requires OpenClaw on Node 22 LTS or 24 and an authenticated `gh` CLI.

## About X's terms

The default path posts through the official API with OAuth, which is exactly
what X's automation rules ask for, and per-post human approval keeps it well
clear of their spam policies. The browser fallback exists for accounts
without a developer app; that mode sits outside the automation rules, so
treat it as a stopgap and use it at your own risk.

## License

MIT.
