# Content sourcing

## Rotation

Alternate content types so the account doesn't repeat itself. Default rotation
(check the post log's recent `topic` fields to see where you are):

1. project spotlight or dev log (own repos)
2. TIL / tip / gotcha (own code or tools used)
3. AI tool or news take
4. project spotlight or dev log (a different repo than last time)

Morning cron runs lean toward own-work content; evening runs lean toward AI
tools/news. Multiple posts about the same repo are fine and encouraged, but
each must use a different angle and be spaced at least 4 days apart.

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
