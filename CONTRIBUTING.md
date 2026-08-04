# Contributing

x-poster is five markdown files and three shell scripts. Most useful
contributions are edits to instructions, not code, and the bar for both is
the same: the change came from a real run, not from reading the file and
guessing.

## What's welcome

- Voice or content rules that fixed a bad draft you actually got, with the
  before/after in the PR description.
- Setup script fixes for platforms and shells that broke (`setup.sh` targets
  bash 3.2 on macOS and bash 5 on Linux; both have to keep working).
- Docs corrections, especially where a step failed for you as written.
- A publish doc for another network (a new `PUBLISH-*.md`). Open an issue
  first so we agree on the approval semantics before you write it.

## The one non-negotiable

The agent never posts without an explicit `ship` from the allowlisted
Telegram user, and there is no autonomous mode. PRs that weaken the approval
gate, raise the default caps, or add engagement features (replies to other
accounts, likes, follows) will be closed without much ceremony. The link
reply under the account's own just-published post is part of the approved
package, not an engagement feature — it is the one reply the skill makes.

## Testing your change

Skill files are prompts; test them by running turns, not by rereading them.

```sh
./scripts/setup.sh --dev      # symlinks the skill so edits apply on the next turn
./scripts/setup.sh --check    # health-check every layer, change nothing
bash -n scripts/*.sh          # syntax gate for script changes
```

Leave `telegramTo` empty in `state/settings.json` and the skill runs in
draft mode: drafts land in `state/drafts.md`, nothing is sent or posted.
That's the safe way to exercise a voice or content change end to end.

Remember the running Telegram session caches the skill files: send `/new` to
the bot after editing, or your change silently isn't being tested.

## Pull requests

- Small and focused. Say which run or failure motivated the change.
- Commit format: `<type>: <description>` (feat, fix, docs, chore).
- Never commit anything from `state/`, `voice-examples.local.md`, or `.env`;
  they're gitignored for a reason.
