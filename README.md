# Postflight

Drafts on schedule. Publishes on your word.

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

This skill was called x-poster until v1.0.0. Old links still resolve.
Upgrading an existing install takes one extra command, in [Upgrading from
x-poster](docs/DEPLOY-VPS.md#upgrading-from-x-poster) — automatic until
2026-11-01, by hand after that.

<!-- TODO(screenshot): the page's strongest asset goes here. Save the
     shot as docs/assets/approval-flow.png and replace this comment with:

     ![the approval flow](docs/assets/approval-flow.png)

     *The whole interface: a draft arrives, you reply `ship`, it posts.*

     What it needs to show, in one vertical crop of the Telegram thread:
     the bot's draft with its media attached, the reply `ship`, and the
     bot's confirmation carrying the permalink. Nothing in that thread
     leaks a user id; redact the bot's @name only if you'd rather not
     publish it. A real phone screenshot beats a mockup. -->

## Quickstart

### 1. Get three things ready

- **[OpenClaw](https://docs.openclaw.ai)** installed and onboarded, on Node
  22.22+ or 24.15+ (`nvm install 24` settles it)
- **An authenticated `gh` CLI** (`gh auth login`), so the agent can read
  your repos
- **An X account** with access to [console.x.com](https://console.x.com/),
  and a **Telegram bot token** from [@BotFather](https://t.me/BotFather)
  (`/newbot`)

### 2. Run the wizard

```sh
curl -fsSL https://raw.githubusercontent.com/soos3d/postflight/main/scripts/setup.sh | bash
```

Prefer not to pipe curl into bash? Clone the repo and run
`./scripts/setup.sh`, which is the same script.

It automates everything scriptable and walks you through the two steps that
can't be: creating the X app and pairing the Telegram bot. It probes real
state before each step and skips whatever already works, so rerunning after
a failure is safe.

**Want the skill files from a registry instead?** It's published on
[ClawHub](https://clawhub.ai/soos3d/skills/postflight):

```sh
openclaw skills install @soos3d/postflight
```

That unpacks the skill into `~/.openclaw/workspace/skills/postflight` and
stops there. It is the skill's instructions and nothing else: no X or
Telegram auth, no cron jobs, no `setup.sh`. Run the wizard afterwards for
those — it leaves the installed files alone and picks up from there.

From v1.2.0 on, `openclaw skills update @soos3d/postflight` is also a safe
way to upgrade, because your settings, post log, and photo library live
outside the folder it replaces. The one hop it cannot make safely is
**1.1.0 → 1.2.0**; [Manual
setup](docs/SETUP-MANUAL.md#from-clawhub-instead) says why and what to do
instead.

### 3. Watch one loop run

Message your bot:

```
postflight: draft a post
```

Reply `skip`. You'll see the whole loop run without posting anything.

### 4. Go live

Once a draft looks right, reply `ship` instead. The wizard has already
registered the cron jobs, so the next slot fires on its own.

---

Useful afterwards:

```sh
./scripts/setup.sh --check    # reports every layer, changes nothing
```

If the bot ignores an edit you just made, send `/new` to it. Sessions
re-read skill files only when they start. More fixes in
[TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md).

## Make it yours

Everything personal lives in untracked local files, so `git pull` never
conflicts with your customization. Full walkthrough in
[docs/CUSTOMIZE.md](docs/CUSTOMIZE.md).

| What | Where | Why |
|---|---|---|
| Your topics and weekly schedule | `pillars.local.md` | Without it, the default builds / insights / build-in-public schedule runs |
| 3 to 5 of your own tweets | `voice-examples.local.md` | They outrank every other style rule. Don't skip this one |
| Accounts whose register to study | `styleAccounts` in `settings.json` | Patterns only, never named in posts |

These live in `~/.openclaw/workspace/postflight-state/`, next to the post
log and your photo library — deliberately outside the skill folder, which
every upgrade replaces wholesale. Nothing that installs or updates the skill
can reach them.

## Guardrails

- The agent drafts; **you** approve. Publishing requires the exact word
  `ship` from your Telegram user id. There is no autonomous mode.
- It sends nothing else on X: no replies to anyone else, no likes, follows,
  or DMs, ever.
- Fetched content (READMEs, commit messages, HN titles) is treated as data.
  A source carrying instructions aimed at the agent gets discarded.
- Expired auth means stop and alert. The agent never attempts a login.

These are instructions the model follows, not technical controls. The
approval gate exists so anything that slips through still has to get past
you. [Full detail and honest limits](docs/HOW-IT-WORKS.md#guardrails).

## Running it on a server

A laptop install stops working every time the lid closes, so mine lives on
a small DigitalOcean VM. Any 1–2 GB Ubuntu box works, since the skill posts
through the API and approvals go through Telegram.

Set up on the laptop first anyway: two auth steps open a browser, and the
server can't do that. It receives the finished credentials instead.

One rule matters more than the rest: **never have the laptop and the server
live at the same time.** Two gateways fight over the same bot's updates,
and two cron sets double-post.

[docs/DEPLOY-VPS.md](docs/DEPLOY-VPS.md) walks the cutover in the safe
order.

## Docs

| Doc | What's in it |
|---|---|
| [How it works](docs/HOW-IT-WORKS.md) | The daily loop, content pillars, guardrails, X's terms and cost |
| [Manual setup](docs/SETUP-MANUAL.md) | Every command the wizard runs, for people who want to see them |
| [Customize](docs/CUSTOMIZE.md) | Pillars, voice examples, photo libraries, posting times |
| [Deploy to a VPS](docs/DEPLOY-VPS.md) | Server install and the laptop-to-server cutover |
| [Troubleshooting](docs/TROUBLESHOOTING.md) | Symptoms and fixes |

## Contributing

The interesting contributions here are instructions, not code: voice rules
that survived real runs, content angles that produced posts worth shipping,
setup fixes for platforms that broke, a publish doc for another network.
See [CONTRIBUTING.md](CONTRIBUTING.md). The one non-negotiable is the
approval gate.

What's coming next (thread support, a second network, per-slot model
overrides) lives in [ROADMAP.md](ROADMAP.md).

Questions, setups worth showing, and drafts that came out badly enough to
be interesting go in
[Discussions](https://github.com/soos3d/postflight/discussions). Bugs go in
issues.

## Support

The contribution I want is a voice rule that survived a real run. Second
best is telling me what broke on your platform. If you'd rather put money
behind it, [sponsorship](https://github.com/sponsors/soos3d) is there, and
it buys no influence over the roadmap.

## License

MIT. See [LICENSE](LICENSE).
