# How it works

## The platform

[OpenClaw](https://docs.openclaw.ai) is a personal AI agent that runs on
your own machine. It connects a model to messaging channels like Telegram,
runs scheduled jobs, and is extended with **skills**: folders of markdown
instructions the agent reads and follows. No code, no build step, no
service to deploy.

Model auth reuses your Claude or ChatGPT/Codex subscription, so there's no
separate API bill. The setup wizard asks which you have. The voice rules
were tuned on Claude. The wizard also configures a fallback chain, so a slot
that finds the primary model's usage pool spent drops to the next model and
still drafts.

Postflight is one skill. The platform supplies the moving parts, and a
handful of markdown files in `skill/postflight/` tell the agent what to do.
`SKILL.md` is the one every turn reads; the rest get read on demand, when
the turn actually needs them.

| File | Job |
|---|---|
| `SKILL.md` | The workflow: modes, caps, approval semantics, failure rules |
| `VOICE.md` | Writing rules, style anchors, and the personal-post register |
| `CONTENT.md` | The pillar schedule, media recipes, and where material comes from |
| `PUBLISH-API.md` | Posting through the X API with xurl, including media upload and the link reply |
| `PUBLISH-BROWSER.md` | Browser fallback for accounts without a developer app |
| `REPLY-DRAFTING.md` | The forwarded-link turn: draft reply options, send nothing |
| `PHOTO-INGESTION.md` | The photo-attachment turn: file a photo into a library |

## The daily loop

Each cron slot runs the same five steps.

**1. Sweep, then check the budget.** Pending drafts older than 24h move to
`state/skipped/`, which is itself swept at 30 days; generated media older than
a week that no pending draft references is deleted, and photo libraries are
never touched. Then the budget: three posts a day maximum, nothing resembling
the last ten topics. Look up the slot's pillar in the weekly grid. Every
question asked of the post log is answered from a `tail` of it rather than the
whole file, so a turn costs the same on day 400 as it does on day 4.

**2. Gather real material.** Commits, releases, and READMEs from your
public repos via the `gh` CLI; AI stories from the Hacker News API; your
own notes and photos for any personal pillars you've added. Facts the agent
didn't fetch don't go in a draft.

**3. Write the post** following the voice rules. For a repo post that means
a media-first package: a demo GIF or code screenshot with no URL in the
body, plus the repo link as separate reply text. Both are verified against
X's real character weighting.

**4. Send it to Telegram**, media included, so you approve the post as it
will actually appear. Reply `ship` to post, `skip` to discard, or describe
a change and it revises.

**5. On `ship`, publish** through the X API v2 via [xurl](https://github.com/xdevplatform/xurl),
X's official OAuth CLI: upload the media, publish the tweet, confirm the
returned id, then publish the link as the first reply under it. Log the
URLs.

## Content pillars

Content runs on weighted pillars instead of a flat rotation. At three posts
a day that's 21 weekly slots. The shipped defaults:

| Pillar | Slots | Format |
|---|---|---|
| `builds` | 8 | Own-repo demos: media-first, link in the reply |
| `insights` | 10 | Pure text, no links |
| `build-in-public` | 3 | This pipeline itself: media-first, link in the reply |

Those names are load-bearing: the grid, the post log, and any overlay in
`pillars.local.md` key on them.

Builds posts put the link in a reply because link-card posts are the format X
suppresses hardest.

Personal pillars — a hobby backed by a photo library, a craft you teach —
are per-install and live in one untracked file. See
[CUSTOMIZE.md](CUSTOMIZE.md).

## Outside the daily loop

**Weekly maintenance.** Refreshes the content backlog and reads last week's
metrics into a Telegram digest: median impressions by pillar and format,
plus follower delta. Adjusting the schedule becomes an informed edit rather
than a guess.

**Reply drafting.** Forward someone's post link to the bot and it drafts
two or three reply options in your voice. Each has to carry code, a gotcha,
or a real number. Sending stays manual, from your own client.

**Photo ingestion.** Send the bot a photo as a file with a one-line
caption. It lands in your library with location metadata stripped, tagged,
and postable once its cooldowns clear. See
[CUSTOMIZE.md](CUSTOMIZE.md#3-photo-libraries).

## Guardrails

**It publishes one approved package and sends nothing else on X.** The
post, plus — for repo posts — one reply under that same just-published post
carrying the link, approved together as a unit. No replies to anyone else,
no likes, follows, or DMs, ever.

**It reads exactly two things.** Its own posts' metrics during weekly
maintenance, and a single post you explicitly forward for reply drafting.

**Publishing requires the exact word `ship`** from your Telegram user id
while a draft is pending. Anything else is an edit request. Anyone else is
ignored. Drafts expire after 24 hours.

**The daily cap is re-checked at publish time**, not only at drafting time.

**Fetched content is data, not instruction.** READMEs, commit messages, and
HN titles are treated as untrusted. If a source contains instructions aimed
at the agent, the source is discarded and another topic picked.

**Expired auth means stop and alert.** The agent never attempts a login and
never touches credentials.

### Honest limits

These rules are instructions the model follows, not technical controls. The
agent holds working X credentials and a shell, so a sufficiently clever
prompt injection could in principle bypass them. The per-post approval gate
exists precisely so anything that slips through still has to get past you
before it reaches your account. Supervise it like any automation with keys
to something you care about.

## Why the voice rules matter

`VOICE.md` does the heavy lifting on quality. It bans hashtags, engagement
bait, thread emoji, "excited to announce", and the phrasing tics that mark
text as machine output. Every post has to contain something a reader can
use: a command, a gotcha, a number, a link to real code.

The first draft I got from a local 7B model was "Excited about the
progress! 🚀 #OpenSource #DevLife". That file exists to prevent exactly
that.

`VOICE.md` prevents machine-sounding output. Only your own tweets in
`voice-examples.local.md` make it sound like *you*.

## About X's terms

The default path posts through the official API with OAuth, which is what
X's automation rules ask for, and per-post human approval keeps it well
clear of their spam policies.

The browser fallback exists for accounts without a developer app. That mode
sits outside the automation rules, so treat it as a stopgap and use it at
your own risk.

**Cost.** X's API posting is pay-per-use, observed at roughly $0.02 per
post. The link-in-reply format means a repo post bills as two. That's the
price of not shipping the format X suppresses hardest.
