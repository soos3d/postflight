# Content sourcing

## Rotation

Alternate content types so the account doesn't repeat itself. Default rotation
(check the post log's recent `topic` fields to see where you are):

1. project spotlight or dev log (own repos)
2. TIL / tip / gotcha (own code or tools used)
3. AI tool or news take
4. project spotlight or dev log (a different repo than last time)

The cron message names the focus for each slot: the first daily run leans
own-work, the second leans AI tools/news, and the third is aviation (its own
rotation below — aviation posts don't consume the tech rotation). Multiple
posts about the same repo are fine and encouraged, but each must use a
different angle and be spaced at least 4 days apart.

## Own repos

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

Angles per repo (aim for 4-6 per project in the backlog):

- what it does, in one plain sentence, and why it exists
- the one implementation detail that was hard or surprising
- a library/API used and what it was like in practice
- a bug hit while building it, with the fix
- what you'd do differently now
- a short "how to do X" extracted from the code

## Backlog

`state/backlog.md` holds unposted angles, grouped by repo, each line
`- [ ] <angle>`. When you use one, mark it `- [x]` with the date. A weekly cron
run regenerates it: sweep repos with the commands above, add fresh angles,
never delete unchecked ones.

## AI news and tools

Only comment on things verifiable right now. Sources, no API keys needed:

```sh
# HN front page, filter for AI-relevant items
curl -s https://hacker-news.firebaseio.com/v0/topstories.json | \
  jq -r '.[:30][]' | while read id; do
  curl -s "https://hacker-news.firebaseio.com/v0/item/$id.json" | \
    jq -r 'select((.title? // "")|test("(?i)llm|claude|gpt|agent|model|ai "))|"\(.score) \(.title) \(.url // "")"'
done
```

Rules for news takes: only pick items you can add a developer-relevant opinion
or firsthand context to. Summarizing headlines is not a tweet. If nothing on
the list clears that bar, fall back to an own-repo angle instead.

## Aviation

The user is an experienced pilot and flight instructor; the daily aviation
slot draws on that. Rotate through these angles (check recent `topic` fields
in the post log, same as the tech rotation):

1. instructional tip — the kind of thing students consistently get wrong,
   explained the way an instructor would in the debrief
2. cool fact — aerodynamics, systems, navigation, history; something a
   non-pilot can enjoy and a pilot can nod along to
3. "what it actually does" — an instrument, system, or procedure demystified
4. weather / ATC / airspace explainer — practical, from real flying

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

Backlog: keep an `## aviation` section in `state/backlog.md` with unposted
angles, same `- [ ]` format as repos. The weekly maintenance run refreshes it
alongside the repo angles.
