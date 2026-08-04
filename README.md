# x-poster (Twitter poster via OpenClaw)

![license](https://img.shields.io/badge/license-MIT-blue)

An [OpenClaw](https://docs.openclaw.ai) skill that keeps your X account
active. Three times a day it drafts a post about your open source work,
sends it to your Telegram, and publishes only when you reply `ship`.

I built it because my posting pattern was three tweets in one afternoon,
then five weeks of silence. Cadence grows an account, and cadence is the
kind of boring discipline a personal agent is good at. What I didn't want
was a bot posting to my real account unsupervised, so the contract is
fixed: the agent drafts, you approve, it ships. There is no autonomous
mode.

## How it works

OpenClaw is a personal AI agent that runs on your own machine. It connects
a model (Claude or ChatGPT/Codex, through a subscription you already have)
to messaging channels
like Telegram, runs scheduled jobs, and is extended with **skills**:
folders of markdown instructions the agent reads and follows. No code, no
build step, no service to deploy.

This project is one skill. The platform supplies the moving parts — cron
wakes the agent, Telegram carries drafts and approvals back and forth,
model auth reuses your Claude or ChatGPT/Codex subscription (so no API to
set up and pay separately; the setup wizard asks which — the voice rules
were tuned on Claude) — and five markdown files in
`skill/x-poster/` tell the agent what to do:

| File | Job |
|---|---|
| `SKILL.md` | The workflow: modes, caps, approval semantics, failure rules |
| `VOICE.md` | Writing rules, style anchors, and the personal-post register |
| `CONTENT.md` | The pillar schedule, media recipes, and where material comes from |
| `PUBLISH-API.md` | How to post through the X API with xurl, media upload and the link reply included |
| `PUBLISH-BROWSER.md` | Browser fallback for accounts without a developer app |

Each cron slot runs the same loop:

1. Check the post log. Three posts a day maximum, nothing resembling the
   last ten topics. Look up the slot's pillar in the weekly grid.
2. Gather real material: commits, releases, and READMEs from your public
   repos via the `gh` CLI, AI stories from the Hacker News API, or your
   own notes for the personal pillars. Facts the agent didn't fetch don't
   go in a draft.
3. Write the post following the voice rules. For a repo post that means a
   media-first package: a demo (GIF, code screenshot) with no URL in the
   body, plus the repo link as a separate reply text — each verified
   against X's real character weighting as a python one-liner.
4. Send it to your Telegram, media included, so you approve the post as it
   will actually appear. Reply `ship` to post, `skip` to discard, or
   describe a change and it revises.
5. On `ship`, post through the X API v2 (via `xurl`, X's official OAuth
   CLI): upload the media, publish the tweet, confirm the returned id,
   then publish the link as the first reply under it. Log the URLs.

Content runs on weighted pillars instead of a flat rotation — at three
posts a day that's 21 weekly slots: repo demos (8-9, media-first with the
link in the reply, because link-card posts are the format X suppresses
hardest), insights (4, pure text), aviation (3), florida-outdoors (3-4,
from a photo library), and build-in-public (2). The two personal pillars
are mine; `CONTENT.md` shows the shape to swap in your own.

## Quickstart

Have three things ready:

- [OpenClaw](https://docs.openclaw.ai) installed and onboarded, on Node
  22.22+ or 24.15+ (`nvm install 24` settles it), plus an authenticated
  `gh` CLI (`gh auth login`)
- An X account with access to [console.x.com](https://console.x.com/)
- A Telegram bot token from [@BotFather](https://t.me/BotFather) (`/newbot`)

Then run the setup wizard:

```sh
curl -fsSL https://raw.githubusercontent.com/Soos3D/x-poster/main/scripts/setup.sh | bash
```

If piping curl into bash isn't your thing, clone the repo and run
`./scripts/setup.sh` (same script).

The wizard runs everything scriptable and walks you through the two steps
that can't be automated: creating the X app and pairing the Telegram bot.
It probes real state before each step and skips whatever already works, so
it's safe to rerun after any failure.

When it finishes, message your bot "x-poster: draft a post" and reply
`skip`. You'll watch the whole loop run without posting anything.

Afterwards:

- `./scripts/setup.sh --check` reports every layer and changes nothing.
- If the bot ignores an edit you just made to the skill files, send `/new`
  to the bot. The persistent session only re-reads everything when it
  starts.
- Prefer to run every command yourself? The full manual walkthrough is in
  [docs/SETUP-MANUAL.md](docs/SETUP-MANUAL.md).

## Make it yours

The defaults describe my account. Three files change that:

- **`skill/x-poster/CONTENT.md`** is the content config: the pillar grid,
  the shell commands that gather material, the media recipes, and the
  angle lists per pillar. The aviation and florida-outdoors sections are
  my personal pillars; replace them with topics you can write about
  firsthand, keeping the same shape (a pillar of angles plus hard rules
  about what's off limits).
- **`voice-examples.local.md`** holds 3 to 5 of your own tweets. They
  outrank every other style rule, so the account keeps sounding like you.
  Local file, gitignored. Don't skip it.
- **`styleAccounts`** in `state/settings.json` lists public accounts whose
  register gets studied during style refreshes: patterns only, never
  opinions or phrasings, and they're never named in posts.

`VOICE.md` does the heavy lifting on quality. It bans hashtags, engagement
bait, thread emoji, "excited to announce", and the phrasing tics that mark
text as machine output, and requires every post to contain something a
reader can use: a command, a gotcha, a number, a link to real code. The
first draft I got from a local 7B model was "Excited about the progress!
🚀 #OpenSource #DevLife". That file exists to prevent exactly that.

One path detail: the default install copies the skill into
`~/.openclaw/workspace/skills/x-poster/`, so that's where the voice file
and `state/settings.json` live. Edits to the checkout take effect after
rerunning `./scripts/install.sh`, or install once with `--dev` to symlink
instead. Posting times are cron jobs; change them by rerunning
`./scripts/setup.sh` or with `openclaw cron`.

## Guardrails

- Publishes one approved package and does nothing else on X: the post,
  plus — for repo posts — one reply under that same just-published post
  carrying the link, approved together as a unit. No replies to anyone
  else, no likes, follows, or DMs, ever.
- Publishing requires the exact word `ship` from your Telegram user id
  while a draft is pending. Anything else is an edit request; anyone else
  is ignored. Drafts expire after 24 hours.
- The daily cap is re-checked at publish time, not just at drafting time.
- Fetched content (READMEs, commit messages, HN titles) is treated as
  data. If a source contains instructions aimed at the agent, the source
  is discarded and another topic picked.
- Expired auth means stop and alert. The agent never attempts a login and
  never touches credentials.
- Honest limits: these rules are instructions the model follows, not
  technical controls. The agent holds working X credentials and a shell, so
  a sufficiently clever prompt injection could in principle bypass them.
  The per-post approval gate exists precisely so anything that slips
  through still has to get past you before it reaches your account —
  supervise it like any automation with keys to something you care about.

## Running it on a server

A laptop install stops working every time the lid closes, so mine lives on
a small DigitalOcean VM. Any 1–2 GB Ubuntu box works: the skill posts
through the API and approvals go through Telegram, so nothing needs a
display.

Set up on the laptop first anyway. Two auth steps open a browser (the
claude.ai token approval and the X OAuth consent), and the server can't do
that; it receives the finished credentials instead:

```sh
# server: install everything, Ctrl-C at the model-auth prompt
git clone https://github.com/Soos3D/x-poster.git ~/x-poster
cd ~/x-poster && ./scripts/setup.sh

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
updates, and two cron sets double-post, because the daily cap is
per-machine state. [docs/DEPLOY-VPS.md](docs/DEPLOY-VPS.md) walks the
cutover in the safe order.

Updating later is git only: edit and push from the laptop, then on the
server `git pull && ./scripts/install.sh` (`state/` is never touched).

## About X's terms

The default path posts through the official API with OAuth, which is
exactly what X's automation rules ask for, and per-post human approval
keeps it well clear of their spam policies. The browser fallback exists
for accounts without a developer app; that mode sits outside the
automation rules, so treat it as a stopgap and use it at your own risk.

On cost: X's API posting is pay-per-use (observed ~$0.02/post), and the
link-in-reply format means a repo post bills as two posts. That's the
price of not shipping the format X suppresses hardest.

## Contributing

The interesting contributions here are instructions, not code: voice rules
that survived real runs, content angles that produced posts worth
shipping, setup fixes for platforms that broke, a publish doc for another
network. See [CONTRIBUTING.md](CONTRIBUTING.md); the one non-negotiable is
the approval gate. What's coming next — engagement readback, thread
support, a second network — lives in [ROADMAP.md](ROADMAP.md).

## License

MIT. See [LICENSE](LICENSE).
