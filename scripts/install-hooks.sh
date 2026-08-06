#!/usr/bin/env bash
# Point this checkout's git hooks at scripts/hooks/.
#
# Hooks live in .git/, which is not versioned, so a fresh clone has none. This
# sets core.hooksPath instead of copying files in: the hook you get is the hook
# in the commit, and updating it is a pull rather than a reinstall.
#
# Usage: ./scripts/install-hooks.sh [--check]
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

CHECK_ONLY=0
[ "${1:-}" = "--check" ] && CHECK_ONLY=1

git rev-parse --git-dir >/dev/null 2>&1 || {
  printf 'error: not a git checkout, nothing to install\n' >&2
  exit 1
}

current="$(git config --local --get core.hooksPath || true)"

if [ "$current" = "scripts/hooks" ]; then
  printf 'hooks already installed (core.hooksPath=scripts/hooks)\n'
  exit 0
fi

if [ "$CHECK_ONLY" -eq 1 ]; then
  printf 'hooks not installed — run ./scripts/install-hooks.sh\n'
  exit 1
fi

if [ -n "$current" ]; then
  printf 'note: core.hooksPath was %s, repointing to scripts/hooks\n' "$current"
fi

chmod +x scripts/hooks/*
git config --local core.hooksPath scripts/hooks
printf 'hooks installed: %s\n' "$(find scripts/hooks -type f -exec basename {} \; | tr '\n' ' ')"
