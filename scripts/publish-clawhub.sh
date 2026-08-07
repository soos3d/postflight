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
MANIFEST="scripts/clawhub-manifest.txt"

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

# The checks above only catch personal files whose names were predicted. The
# manifest catches the rest: it is the reviewed list of what may ship, so a
# file nobody meant to publish shows up here as a diff instead of on ClawHub.
[ -f "$MANIFEST" ] || die "missing $MANIFEST — refusing to publish an unreviewed file list"

staged_files="$(cd "$STAGE" && find . -type f | sed 's|^\./||' | LC_ALL=C sort)"
allowed_files="$(grep -vE '^[[:space:]]*(#|$)' "$MANIFEST" | LC_ALL=C sort)"

if [ "$staged_files" != "$allowed_files" ]; then
  printf 'error: the staged copy does not match %s\n\n' "$MANIFEST" >&2
  # diff exits 1 on a difference, which is the expected case here; without the
  # `|| true` errexit would kill the script before it prints what to do next.
  { diff <(printf '%s\n' "$allowed_files") <(printf '%s\n' "$staged_files") \
    | sed 's|^< |  listed but not staged: |; s|^> |  NOT IN MANIFEST: |' || true; } >&2
  printf '\nAdd intended files to %s in the same commit. Anything you did not\n' "$MANIFEST" >&2
  printf 'mean to publish must not be committed under %s.\n' "$SKILL_PATH" >&2
  exit 1
fi

# State moved out of the skill folder in v1.2.0 because an installer replaces
# that folder wholesale. A doc still pointing the agent at the old paths is
# not a stale doc — it is a live instruction to write into a directory the
# next upgrade deletes, and it would ship to a public registry. The two greps
# below are what make a half-updated instruction set a red build instead.
stale="$(grep -rIln -e '{baseDir}/state' \
                    -e '{baseDir}/pillars.local.md' \
                    -e '{baseDir}/voice-examples.local.md' "$STAGE" || true)"
if [ -n "$stale" ]; then
  printf 'error: these staged files still point at the pre-v1.2.0 state paths:\n' >&2
  printf '%s\n' "$stale" | sed "s|$STAGE/|  |" >&2
  printf '\nState lives in <workspace>/postflight-state now. See SKILL.md\n' >&2
  printf '"Where things live" for the spelling these should use.\n' >&2
  exit 1
fi

# The definition itself. Without it every relative postflight-state/ path in
# the other docs is a string the agent has no way to resolve.
grep -q 'postflight-state/' "$STAGE/SKILL.md" \
  || die "SKILL.md never mentions postflight-state/ — the state directory is undefined for the agent"

if grep -rIl --exclude-dir=.git -E '[0-9]{8,}' "$STAGE" >/dev/null 2>&1; then
  printf 'note: the staged copy contains long digit runs. Check them before publishing:\n' >&2
  grep -rIn --exclude-dir=.git -E '[0-9]{8,}' "$STAGE" | sed "s|$STAGE/||" >&2
fi

# ClawHub links a listing back to its repo only when the publish carries these
# four. Without them the page is a dead end: no source to read, no issues to
# file, no license to check. Derived from the origin remote rather than
# hardcoded, so publishing a fork points at the fork.
SOURCE_ARGS=()
origin_url="$(git remote get-url origin 2>/dev/null || true)"
case "$origin_url" in
  git@github.com:*)     source_repo="${origin_url#git@github.com:}" ;;
  https://github.com/*) source_repo="${origin_url#https://github.com/}" ;;
  *)                    source_repo="" ;;
esac
source_repo="${source_repo%.git}"

if [ -n "$source_repo" ]; then
  # A tag when the commit carries one (what a release publish is), the branch
  # otherwise. Never the bare sha: --source-commit already pins that exactly.
  source_ref="$(git describe --tags --exact-match 2>/dev/null || git rev-parse --abbrev-ref HEAD)"
  SOURCE_ARGS=(
    --source-repo "$source_repo"
    --source-commit "$(git rev-parse HEAD)"
    --source-ref "$source_ref"
    --source-path "$SKILL_PATH"
  )
else
  printf 'note: origin is not a GitHub remote — the listing will have no source link\n' >&2
fi

printf '\nStaged for ClawHub as %s v%s:\n\n' "$SLUG" "$VERSION"
(cd "$STAGE" && find . -type f | sed 's|^\./|  |' | sort)
printf '\n  %s files, %s\n\n' \
  "$(find "$STAGE" -type f | wc -l | tr -d ' ')" \
  "$(du -sh "$STAGE" | cut -f1)"

if [ -n "$source_repo" ]; then
  printf '  source: %s %s @ %s, path %s\n\n' \
    "$source_repo" "$source_ref" "$(git rev-parse --short HEAD)" "$SKILL_PATH"
fi

if [ "$DO_PUBLISH" -eq 0 ]; then
  printf 'Dry run. Re-run with --publish to upload.\n'
  exit 0
fi

command -v clawhub >/dev/null 2>&1 || die "clawhub CLI not found — npm i -g clawhub, then clawhub login"

# bash 3.2 (macOS) treats "${arr[@]}" on an empty array as unbound under set -u,
# so the expansion has to be guarded rather than written plainly.
clawhub skill publish "$STAGE" \
  --slug "$SLUG" \
  --name "$NAME" \
  --version "$VERSION" \
  ${SOURCE_ARGS[@]+"${SOURCE_ARGS[@]}"}

# The listing lives under the publisher handle; a bare /<slug> is a 404.
PUBLISHER="$(clawhub whoami 2>/dev/null | grep -oE '[A-Za-z0-9_-]+' | tail -1 || true)"
printf '\nPublished. Verify at https://clawhub.ai/%s/skills/%s\n' "${PUBLISHER:-<your-handle>}" "$SLUG"
