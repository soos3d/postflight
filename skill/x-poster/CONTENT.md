# Content sourcing

This file is the content config. The pillars below are tuned for the
author's account; the builds/insights machinery travels to any account,
while aviation and florida-outdoors are the author's personal topics. If
this isn't the author's install, replace those sections with topics the
account owner can write about firsthand, keeping the same shape: a pillar
with angles plus hard rules about what's off limits.

## Pillars

Content is organized into five weighted pillars. At 3 posts/day that is 21
weekly slots:

- **builds** (8-9): own-repo demos. Media-first: the body shows the thing,
  the repo link ships as the first reply, never in the body.
- **insights** (4): opinions, lessons, hot takes from real work. Pure text,
  no links.
- **aviation** (3): CFI tips, systems demystified, AI × aviation crossovers.
- **florida-outdoors** (3-4): springs, parks, kayaking — from the photo
  library. No links.
- **build-in-public** (2): x-poster itself — feature ships, honest numbers.
  Same media-first + link-in-reply shape as builds.

The weekly grid (weekday in `timezone`; slot numbers come from the cron
message — slot 1 is the morning job, 2 midday, 3 afternoon):

| Day | Slot 1 | Slot 2 | Slot 3 |
|---|---|---|---|
| Mon | builds | insights | florida-outdoors *(fb: insights)* |
| Tue | builds | aviation | build-in-public |
| Wed | builds | florida-outdoors *(fb: aviation)* | insights |
| Thu | builds | insights | aviation |
| Fri | builds | florida-outdoors *(fb: insights)* | build-in-public |
| Sat | builds | aviation | florida-outdoors *(fb: builds)* |
| Sun | builds | insights | builds |

Rules around the grid:

- **Fallback pillars.** The photo library lives at
  `{baseDir}/state/media/photos/`. If that directory is missing or empty,
  a florida-outdoors cell is drafted as its *(fb: ...)* fallback pillar
  instead. The library activates those slots just by existing.
- **Slot source.** The cron message says which slot this is; trust it.
  Never derive the slot from today's post count — a skipped morning draft
  would shift every later slot. For a manual "draft a post" request with no
  slot, pick the pillar furthest behind its weekly target (count post-log
  lines since Monday in `timezone` by their `pillar` field; ties go to
  builds).
- **Queue smoothing.** Never two link-bearing posts in adjacent slots of a
  day (builds and build-in-public bear links; insights, aviation, and
  florida-outdoors never contain links). Never two same-pillar posts in
  adjacent slots. The grid already satisfies both — if you deviate from
  the grid for any reason, these two rules still bind.
- **Register ratio.** The account's promise is a senior dev who builds;
  personal posts season the feed, they don't become it. Roughly 1 post in 5
  uses the personal register (florida-outdoors, plus the occasional
  aviation post written personally) — see VOICE.md "Personal posts".

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

**Angle cycle.** Each repo rotates through four angles, in order:

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

Every builds and build-in-public post carries media. Generated files go to
`{baseDir}/state/media/<YYYYMMDD-HHmm>-<repo-slug>.<ext>` — a name you
construct; nothing from fetched content ever becomes a file path. Caps:
images 5 MB, GIF 15 MB, video 512 MB (regenerate smaller if over, e.g. a
shorter tape or lower framerate — never truncate a file).

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
2) → **text-only builds post** — the body still contains no URL and the
link still ships as the reply (`format: text+reply`). The slot is never
held for lack of media, and the pending file must say media generation
failed and which tools were missing, so the user knows what to install.

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

## aviation

A personal-topic pillar, written for the author's install: the user is an
experienced pilot and flight instructor, and the aviation slots draw on
that. Rotate through these angles (check recent `topic` fields in the post
log, same as the builds cycle):

1. instructional tip — the kind of thing students consistently get wrong,
   explained the way an instructor would in the debrief
2. cool fact — aerodynamics, systems, navigation, history; something a
   non-pilot can enjoy and a pilot can nod along to
3. "what it actually does" — an instrument, system, or procedure demystified
4. weather / ATC / airspace explainer — practical, from real flying
5. AI × aviation crossover — where the flying world meets the building
   world: a tool applied to aviation data, what automation can and can't
   do in a cockpit, building with ATC audio

Hard rules:

- **No accident or incident content.** No crash commentary, no "lessons from
  the recent accident", no NTSB takes — even educational framing. Skip the
  angle entirely.
- **Accuracy over specificity.** Never invent numbers, regulation references,
  or procedure details. Cite a FAR/AIM section or a V-speed only when certain
  it's right; otherwise explain the concept without the citation. A wrong
  instructional detail from an instructor account is worse than no post.
- Firsthand instructor framing beats encyclopedia framing: "what I tell
  students" over "did you know".
- No links. Most aviation posts read technical-instructional; the
  occasional one written in the personal register (VOICE.md "Personal
  posts") counts toward the 1-in-5 ratio.

## florida-outdoors

The other personal pillar: springs, state parks, kayaking, the outdoors an
actual Floridian actually visits. Posts draw on the photo library at
`{baseDir}/state/media/photos/` — until that library exists and has
photos, this pillar's grid cells fall back per the grid (see Pillars), so
there is nothing to force.

- Written in the personal register, VOICE.md "Personal posts": one concrete
  detail, no links, no hashtags, the photo carries the post.
- Post AFTER leaving a location, never from it, and never same-day.
- The photo is the media; there is no link reply — nothing to link to.

## build-in-public

x-poster building itself: a feature that shipped, a real metrics
screenshot, what broke and how it got fixed. Honest numbers beat growth
theater — "median 100 impressions, here's the experiment" is the post.
Link-bearing like builds: media-first, no URL in the body, repo link in the
reply. These posts participate in the builds angle cycle under the
x-poster repo itself.

## Backlog

`state/backlog.md` holds unposted angles grouped by pillar: one `## builds
— <repo>` section per repo, then `## insights`, `## aviation`, and
`## florida-outdoors`, each line `- [ ] <angle>`. When you use one, mark it
`- [x]` with the date. A weekly cron run regenerates it: sweep repos with
the commands above, add fresh angles for every pillar, never delete
unchecked ones.
