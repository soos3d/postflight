# Content sourcing

This file is the content machinery: how pillars are defined, where
material comes from, and how media gets made. It ships with a generic
default pillar set that works for any developer account; your own
pillars live in an untracked overlay file, never here.

## Pillar configuration

At the start of every drafting turn, check for `{baseDir}/pillars.local.md`.
If it exists and does not contain the template marker line (the
`<!-- TEMPLATE` comment `pillars.example.md` starts with), its
`## Pillars` list and `## Weekly grid` replace the same-named sections
in this file **wholesale — never merge the two lists**. A pillar named
in the overlay uses the overlay's `## <pillar>` section when it has one,
otherwise the same-named section in this file. Everything else in this
file — sourcing commands, media recipes, the rules around the grid, the
backlog format — always applies. If the overlay is absent or still
carries the marker, the defaults below are the active configuration.
To customize, copy `pillars.example.md` to `pillars.local.md` and edit
it (docs/CUSTOMIZE.md walks through it).

## Pillar properties

Every pillar declares five properties; the workflow in SKILL.md keys off
these, never off pillar names:

- `weight:` — target slots per week (the grid is where weights become real)
- `media:` — `generated` (media recipes below), `photos:<dir>` (pick an
  unused photo from `{baseDir}/<dir>`), or `none`
- `link:` — `reply` (two-text draft: body with no URL, link as the first
  reply) or `none` (single body, zero links)
- `register:` — `technical` or `personal` (VOICE.md "Personal posts")
- `source:` — `repos` (gh sweep + the angle cycle), `news` (HN sweep), or
  `own-notes` (backlog + the pillar's own angle rotation)

Each pillar then gets a `## <pillar>` section: what it covers, its angle
list, and hard rules about what's off limits.

## Pillars

The default set — three pillars any developer account can run. At 3
posts/day that is 21 weekly slots:

- **builds** (8) — media: generated · link: reply · register: technical ·
  source: repos. Own-repo demos. Media-first: the body shows the thing,
  the repo link ships as the first reply, never in the body.
- **insights** (10) — media: none · link: none · register: technical ·
  source: own-notes. Opinions, lessons, hot takes from real work. Pure
  text, no links — these are the posts that travel on their own.
- **build-in-public** (3) — media: generated · link: reply ·
  register: technical · source: repos. This posting pipeline itself:
  feature ships, honest numbers, what broke and how it got fixed.

## Weekly grid

Weekday in `timezone`; slot numbers come from the cron message — slot 1
is the morning job, 2 midday, 3 afternoon:

| Day | Slot 1 | Slot 2 | Slot 3 |
|---|---|---|---|
| Mon | builds *(fb: insights)* | insights | build-in-public *(fb: insights)* |
| Tue | insights | builds *(fb: insights)* | insights |
| Wed | builds *(fb: insights)* | insights | builds *(fb: insights)* |
| Thu | insights | builds *(fb: insights)* | insights |
| Fri | builds *(fb: insights)* | insights | build-in-public *(fb: insights)* |
| Sat | insights | builds *(fb: insights)* | insights |
| Sun | builds *(fb: insights)* | insights | build-in-public *(fb: insights)* |

Rules around the grid (these apply to any grid, default or overlay):

- **Fallback pillars.** Any cell may carry a *(fb: <pillar>)* fallback.
  Draft the fallback instead when the cell's pillar is unavailable this
  turn: its `media: photos:<dir>` directory is missing or empty, or its
  `source:` yields nothing usable — no eligible repo outside the 4-day
  window, nothing in the backlog worth posting. A pillar activates its
  cells just by having material.
- **Slot source.** The cron message says which slot this is; trust it.
  Never derive the slot from today's post count — a skipped morning draft
  would shift every later slot. For a manual "draft a post" request with no
  slot, pick the pillar furthest behind its weekly target (count post-log
  lines since Monday in `timezone` by their `pillar` field; ties go to
  builds).
- **Queue smoothing.** Never two `link: reply` posts in adjacent slots of
  a day, and never two same-pillar posts in adjacent slots. A well-formed
  grid already satisfies both — if you deviate from the grid for any
  reason, these two rules still bind.
- **Register ratio.** Personal posts season the feed, they don't become
  it: at most roughly 1 slot in 5 goes to a `register: personal` pillar.
  The grid is where the ratio is enforced — a grid that respects it needs
  no per-turn arithmetic.

## builds (own repos)

A builds post is media-first: the body is the demo — what it does or what
changed, shown — carries media, and contains **no URL**. The link ships as
the immediate first reply, exact form `repo + docs: <link>` (or just
`repo: <link>` when there are no docs). Every builds post must have media
or follow the degradation ladder in "Media recipes" below.

List public repos, newest activity first:

```sh
gh repo list --limit 30 --json name,description,stargazerCount,pushedAt,visibility \
  --jq '.[] | select(.visibility=="PUBLIC")'
```

Recent activity in a repo (commits often contain tweet-worthy specifics).
Use the explicit `owner/name` from the `gh repo list` output — `{owner}/{repo}`
placeholders only auto-fill inside a git checkout, which a cron session is not:

```sh
gh api repos/OWNER/NAME/commits --jq '.[:10][] | .commit.message'
gh api repos/OWNER/NAME/releases --jq '.[:3][] | {name, body}'
gh api repos/OWNER/NAME/readme --jq .content | base64 -d
```

**Angle cycle.** Each `source: repos` pillar rotates every repo through
four angles, in order:

1. **problem** — what itch this repo scratches, why it exists, in one plain
   sentence (what it does; the pain before it)
2. **technique** — the one implementation detail that was hard or
   surprising; a library/API used and what it was like in practice
3. **result** — what it does now, shown: the output, the diff, the number
   ("cut X to Y"), the demo GIF doing the thing
4. **lesson** — the bug hit and the fix, what you'd do differently now, a
   short "how to do X" extracted from the code

To find where a repo is in the cycle, read the most recent post-log line
whose `repo` field matches and post the next angle after its `angle` field.
Lines without an `angle` field (pre-pillar log entries) mean: start at
`problem`. Two posts about the same repo must be at least 4 days apart —
same-repo posts on consecutive days split their own audience.

## Media recipes

Every post from a `media: generated` pillar carries media. Generated
files go to `{baseDir}/state/media/<YYYYMMDD-HHmm>-<repo-slug>.<ext>` — a
name you construct; nothing from fetched content ever becomes a file path.
Caps: images 5 MB, GIF 15 MB, video 512 MB (regenerate smaller if over,
e.g. a shorter tape or lower framerate — never truncate a file).

Sourcing is restricted to media you can verify: repo assets and artifacts
you generated this turn. Never stock art, never images fetched from
elsewhere.

Try in this order, per project type:

0. **Existing repo asset** (any project, cheapest — try first): a demo GIF
   or screenshot already in the repo (README-referenced image, `docs/` or
   `assets/`). Download it via
   `gh api repos/OWNER/NAME/contents/<path> --jq .download_url` then
   `curl -sL -o <dest> <url>`, and verify the size caps.
1. **CLI project**: if `command -v vhs` succeeds, write a short `.tape`
   file (under ~15 seconds of terminal action) demonstrating the command,
   render to GIF with `vhs <tape>`. Keep the tape output well under the
   15 MB GIF cap. vhs (0.11) rejects absolute paths in the tape's
   `Output` line — "Invalid command" on a path starting with `/` — so
   use a bare filename in the tape and run `vhs` from inside
   `{baseDir}/state/media/` (or `mv` the file there after rendering).
2. **Code-centric**: if `command -v freeze` succeeds, fetch the
   load-bearing function's file via `gh api`, save it under
   `{baseDir}/state/media/`, and screenshot it with
   `freeze <file> -o <dest>.png`.
3. **Web UI**: a Playwright or managed-browser screenshot of the running
   UI — only when the project already runs locally in this session; never
   install or launch things just for a screenshot.

**Degradation ladder** when the preferred recipe fails or its tool is
missing: existing repo asset (recipe 0) → freeze code screenshot (recipe
2) → **text-only post** — for a `link: reply` pillar the body still
contains no URL and the link still ships as the reply
(`format: text+reply`). The slot is never held for lack of media, and the
pending file must say media generation failed and which tools were
missing, so the user knows what to install.

## insights

Opinions, lessons, and hot takes from your own work: what a tool got
wrong, what a rewrite taught you, a take on how people build with AI. Pure
text, zero links — these are the posts that travel on their own. VOICE.md's
"opinions take a side" rule doubly applies; an insights post with no side
is not a post. Source them from your recent commits, the backlog's lesson
angles, and real friction from this week — not from headlines.

AI news can seed an insights post, but only when you can add a
developer-relevant opinion or firsthand context. Sources, no API keys
needed:

```sh
# HN front page, filter for AI-relevant items
curl -s https://hacker-news.firebaseio.com/v0/topstories.json | \
  jq -r '.[:30][]' | while read id; do
  curl -s "https://hacker-news.firebaseio.com/v0/item/$id.json" | \
    jq -r 'select((.title? // "")|test("(?i)llm|claude|gpt|agent|model|ai "))|"\(.score) \(.title) \(.url // "")"'
done
```

Summarizing headlines is not a tweet. If nothing clears that bar, fall
back to a lesson from your own recent work instead.

## build-in-public

This posting pipeline building itself: a feature that shipped, a real
metrics screenshot, what broke and how it got fixed. Honest numbers beat
growth theater — "median 100 impressions, here's the experiment" is the
post. Link-bearing like builds: media-first, no URL in the body, repo
link in the reply. These posts participate in the builds angle cycle
under the pipeline's own repo.

## Backlog

`state/backlog.md` holds unposted angles grouped by pillar: one `## builds
— <repo>` section per repo, then one `## <pillar>` section for each other
pillar in the active set, each line `- [ ] <angle>`. When you use one,
mark it `- [x]` with the date. A weekly cron run regenerates it: sweep
repos with the commands above, add fresh angles for every active pillar,
never delete unchecked ones.
