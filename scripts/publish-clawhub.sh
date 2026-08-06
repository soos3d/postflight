#!/usr/bin/env bash
# Publish the skill to ClawHub from a clean staging copy.
#
# The working skill folder is not safe to publish directly. It holds
# state/settings.json (your Telegram user id), state/post-log.jsonl, your
# photo library, and the *.local.md files carrying your pillars and your own
# tweets. All of that is gitignored, so staging from `git archive` ships
# exactly the tracked files and nothing else.
#
# Usage:
#   ./scripts/publish-clawhub.sh 1.0.0            # stage and show what would ship
#   ./scripts/publish-clawhub.sh 1.0.0 --publish  # actually publish
set -euo pipefail

SLUG="postflight"
NAME="Postflight"
SKILL_PATH="skill/postflight"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

die() { printf 'error: %s\n' "$1" >&2; exit 1; }

VERSION="${1:-}"
[ -n "$VERSION" ] || die "usage: $0 <version> [--publish]  (e.g. $0 1.0.0)"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "version must be semver, got '$VERSION'"

DO_PUBLISH=0
[ "${2:-}" = "--publish" ] && DO_PUBLISH=1

# Publishing from a dirty tree is how the wrong thing ships. git archive reads
# committed state, so an uncommitted fix would silently not be in the upload.
if ! git diff --quiet HEAD -- "$SKILL_PATH"; then
  die "uncommitted changes in $SKILL_PATH — commit them first, or they won't be published"
fi

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

git archive HEAD:"$SKILL_PATH" | tar -x -C "$STAGE"

# git archive should make the checks below impossible. They run anyway: the
# cost of being wrong here is a public upload of personal data, and an upload
# cannot be taken back.
[ -f "$STAGE/SKILL.md" ] || die "no SKILL.md in the staged copy — ClawHub requires one"

leaked=""
[ -e "$STAGE/state" ] && leaked="${leaked} state/"
while IFS= read -r f; do leaked="${leaked} ${f#"$STAGE"/}"; done < <(
  find "$STAGE" -name '*.local.md' -o -name '.env' -o -name 'settings.json'
)
[ -z "$leaked" ] || die "staged copy contains files that must never be published:${leaked}"

if grep -rIl --exclude-dir=.git -E '[0-9]{8,}' "$STAGE" >/dev/null 2>&1; then
  printf 'note: the staged copy contains long digit runs. Check them before publishing:\n' >&2
  grep -rIn --exclude-dir=.git -E '[0-9]{8,}' "$STAGE" | sed "s|$STAGE/||" >&2
fi

printf '\nStaged for ClawHub as %s v%s:\n\n' "$SLUG" "$VERSION"
(cd "$STAGE" && find . -type f | sed 's|^\./|  |' | sort)
printf '\n  %s files, %s\n\n' \
  "$(find "$STAGE" -type f | wc -l | tr -d ' ')" \
  "$(du -sh "$STAGE" | cut -f1)"

if [ "$DO_PUBLISH" -eq 0 ]; then
  printf 'Dry run. Re-run with --publish to upload.\n'
  exit 0
fi

command -v clawhub >/dev/null 2>&1 || die "clawhub CLI not found — npm i -g clawhub, then clawhub login"

clawhub skill publish "$STAGE" \
  --slug "$SLUG" \
  --name "$NAME" \
  --version "$VERSION"

printf '\nPublished. Verify at https://clawhub.ai/%s\n' "$SLUG"
