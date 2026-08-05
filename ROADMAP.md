# Roadmap

What's planned for x-poster, in priority order. Items move up or down based
on real use, not votes — but if one of these matters to you, say so in an
issue, and see [CONTRIBUTING.md](CONTRIBUTING.md) if you want to build it.
The one rule that never moves: every post is approved by a human before it
ships. Nothing on this list adds an autonomous mode.

## Now

### 1. Choose your model: Claude or Codex subscription — SHIPPED 2026-08-04

The setup wizard now asks which subscription to use: Claude (Anthropic
setup-token, the path the voice rules were tuned on) or ChatGPT/Codex
(OpenAI OAuth, with an automatic device-code flow on headless boxes). The
wizard resolves the OpenAI default model against the installed OpenClaw's
catalog, preferring the subscription tier (`gpt-5.6-sol`, falling back to
`-terra`) and never plain `openai/gpt-5.6` — that's the API-key alias and
would bill a developer account. Known landmine, documented in the setup
docs: `openclaw doctor --fix` has rewritten Codex-subscription routes to
API billing in released versions (openclaw#79461, openclaw#87650) — re-check
`openclaw models status` after any `--fix`.

Voice caveat: draft quality has only been validated on Claude. The first
draft we ever got from a weak model was banned-slop; expect to tune
`VOICE.md` compliance per model.

### 2. Per-install pillar config — SHIPPED 2026-08-05

The pillar schedule moved out of the tracked files: CONTENT.md now ships
a generic default set (builds / insights / build-in-public) and an
optional untracked `pillars.local.md` overlay carries an install's own
pillars — copy `pillars.example.md`, edit, done (docs/CUSTOMIZE.md).
Pillar behavior in SKILL.md is property-driven (`media:`, `link:`,
`register:`, `source:`), so custom pillars need no instruction edits,
and `git pull` never conflicts with personalization.

### 3. Media posts — SHIPPED 2026-08-04

Shipped bigger than planned: not just image support but media-first repo
posts with the link in a self-reply (link-card posts are the format X
suppresses hardest), plus a weighted pillar system replacing the flat
topic rotation. The mechanics live in PUBLISH-API.md (media upload, the
reply form, the `media.write` caveat) and CONTENT.md (pillar grid, media
recipes, degradation ladder); the Telegram approval message carries the
rendered media, so approving stays an informed decision.

Cost note that applies to text posts too: X's free tier ended Feb 2026
and posting is pay-per-use. The pricing page lists $0.015 per post and
$0.20 per post containing a URL, but observed billing on this account is
~$0.02 per post, links included. Media upload itself has no listed
price — check the usage meter after the first real upload. The
link-in-reply format bills a repo post as two posts.

## Next

### 4. Engagement readback

The Monday maintenance turn reads `public_metrics` for the last posts and
appends a short "what worked" note to the backlog, so angle selection learns
from results. A stats digest to Telegram falls out of the same fetch almost
for free.

### 5. Per-slot model overrides

OpenClaw's `openclaw cron edit <id> --model <ref>` lets each cron slot run a
different model: cheap model for the Monday backlog refresh, strong model
for drafting. Mostly a documentation task now that provider choice
(item 1) has shipped. Needs a live check first — openclaw#28905 reports cron overrides
being ignored in some versions.

### 6. Thread support

Multi-tweet drafts approved as one unit, published as a reply chain
(`reply.in_reply_to_tweet_id`). The building blocks shipped with media
posts: the reply form, per-tweet length verification, and the half-posted
failure rule all exist for the two-tweet post+link package — threads
generalize that package to N tweets.

## Later

### 7. Second network: Bluesky

A new `PUBLISH-BLUESKY.md` following the same shape as the existing publish
docs. Bluesky's token API needs no OAuth dance, which makes it the easiest
second network. Mastodon would follow the same pattern.
[CONTRIBUTING.md](CONTRIBUTING.md) already invites publish docs for other
networks — this is a good first contribution.

### 8. Skip/edit feedback loop

When the owner skips a draft or asks for an edit, log the reason to a state
file that future drafting turns read. The agent is forbidden from editing
its own instruction files, so learning accumulates in `state/`, and proven
lessons get promoted into `VOICE.md` by a human through git.

### 9. Style refresh for headless installs

`styleAccounts` study currently needs a browser session, which a VPS install
doesn't have. Parked until there's a clean headless path.

## Not planned

- **Autonomous posting** — the approval gate is the product. No.
- **Replies, likes, follows, DMs** — the skill touches nothing on X except
  publishing your own approved package. (The one exception: the link reply
  under the skill's own just-published post, approved as part of the same
  package. Replies to anyone else stay off the table.)
- **Gemini subscription backend** — Google ended consumer Gemini CLI OAuth
  in June 2026; only the API-key path remains, which defeats the
  no-API-bill design.
- **Multi-account** — fights the per-machine state model and the
  single-approver guardrail.
