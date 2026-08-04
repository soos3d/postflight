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

### 2. Media posts

Text posts are boring now. Add image support. Research is done and the
path is clear:

- `xurl media upload <img>` drives X's v2 chunked upload natively (4 MB
  chunks, auto-detects type), and the media id goes into the existing
  `POST /2/tweets` body as `media.media_ids` (max 4). Caveats: the upload
  command's stdout mixes JSON with a human-readable trailer, and OAuth
  tokens minted by older xurl versions may lack the `media.write` scope —
  re-consent fixes that.
- Non-negotiable: the Telegram approval message must show the actual image
  (`openclaw message send --media <path>`), so approving stays an informed
  decision. The agent-side `sendMessage` action is disabled by default and
  reported flaky in issues; the CLI path is the documented reliable one.
- Sourcing rules go in `CONTENT.md`: only images the agent can verify
  (repo assets, generated diagrams), never stock art.
- Cost note that applies to text posts too: X's free tier ended Feb 2026
  and posting is pay-per-use. The pricing page lists $0.015 per post and
  $0.20 per post containing a URL, but observed billing on this account is
  ~$0.02 per post, links included. Media upload itself has no listed
  price — check the usage meter after the first real upload.

## Next

### 3. Engagement readback

The Monday maintenance turn reads `public_metrics` for the last posts and
appends a short "what worked" note to the backlog, so angle selection learns
from results. A stats digest to Telegram falls out of the same fetch almost
for free.

### 4. Per-slot model overrides

OpenClaw's `openclaw cron edit <id> --model <ref>` lets each cron slot run a
different model: cheap model for the Monday backlog refresh, strong model
for drafting. Mostly a documentation task once provider choice (item 2)
lands. Needs a live check first — openclaw#28905 reports cron overrides
being ignored in some versions.

### 5. Thread support

Multi-tweet drafts approved as one unit, published as a reply chain
(`reply.in_reply_to_tweet_id`). Needs per-tweet length verification and an
explicit failure rule for a thread that dies half-posted.

## Later

### 6. Second network: Bluesky

A new `PUBLISH-BLUESKY.md` following the same shape as the existing publish
docs. Bluesky's token API needs no OAuth dance, which makes it the easiest
second network. Mastodon would follow the same pattern.
[CONTRIBUTING.md](CONTRIBUTING.md) already invites publish docs for other
networks — this is a good first contribution.

### 7. Skip/edit feedback loop

When the owner skips a draft or asks for an edit, log the reason to a state
file that future drafting turns read. The agent is forbidden from editing
its own instruction files, so learning accumulates in `state/`, and proven
lessons get promoted into `VOICE.md` by a human through git.

### 8. Style refresh for headless installs

`styleAccounts` study currently needs a browser session, which a VPS install
doesn't have. Parked until there's a clean headless path.

## Not planned

- **Autonomous posting** — the approval gate is the product. No.
- **Replies, likes, follows, DMs** — the skill touches nothing on X except
  publishing your own approved post.
- **Gemini subscription backend** — Google ended consumer Gemini CLI OAuth
  in June 2026; only the API-key path remains, which defeats the
  no-API-bill design.
- **Multi-account** — fights the per-machine state model and the
  single-approver guardrail.
