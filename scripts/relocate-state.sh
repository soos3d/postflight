#!/usr/bin/env bash
# Puts the skill's state where no installer can delete it.
#
#   ./scripts/relocate-state.sh          # move it, or create it
#   ./scripts/relocate-state.sh --check  # report what it would do, write nothing
#
# Through v1.1.0 the post log, metrics, settings, pending drafts, the photo
# library, and both *.local.md files lived inside the installed skill folder.
# `openclaw skills update` and `openclaw skills install --force` replace that
# folder wholesale — the old one is moved aside and deleted once the new files
# land — so every upgrade through ClawHub took the whole history with it.
#
# They live in <workspace>/postflight-state now, a sibling of skills/ that no
# installer reaches. This script moves a pre-move install across and does
# nothing to one that has already moved, so install.sh and setup.sh can call
# it on every run.
#
# Nothing here deletes anything. The originals are copied, the copy is renamed
# into place, and only then are the originals parked under
# postflight-state-pre-move-backup for the user to delete once a loop has run.
#
# Migration shim, supported until 2027-02-01. On that date this script, its
# call sites in install.sh and setup.sh, the pre-move branch in SKILL.md, and
# the `photos:state/…` tolerance in CONTENT.md all come out.
set -euo pipefail

WORKSPACE="${OPENCLAW_WORKSPACE:-$HOME/.openclaw/workspace}"
STATE_DIR="$WORKSPACE/postflight-state"
# Written only by this script and never read back, so a leftover one is a
# partial copy from a run that died mid-copy. It is the single path here that
# is safe to remove.
INCOMING="$STATE_DIR.incoming"
PARK="$WORKSPACE/postflight-state-pre-move-backup"

CHECK_ONLY=0
for arg in "$@"; do
  case "$arg" in
    --check) CHECK_ONLY=1 ;;
    *) echo "usage: relocate-state.sh [--check]" >&2; exit 1 ;;
  esac
done

say() { printf '%s\n' "$1"; }
die() { printf 'error: %s\n' "$1" >&2; exit 1; }

# A --dev install points skills/postflight at the checkout, so the state to
# move is in the checkout rather than the workspace. Both spellings converge
# on the same destination, which is the point: after this, dev and copy
# installs read the same state.
resolved_skill_dir() {
  local dest="$WORKSPACE/skills/postflight"
  if [[ -L "$dest" ]]; then readlink "$dest"; else printf '%s' "$dest"; fi
}

SKILL_DIR="$(resolved_skill_dir)"
OLD_STATE="$SKILL_DIR/state"

# The directories and files the skill expects to find. Creating them is
# separate from moving them: a fresh install needs this and nothing else.
scaffold() {
  mkdir -p "$STATE_DIR/pending" "$STATE_DIR/skipped" "$STATE_DIR/media"
  touch "$STATE_DIR/post-log.jsonl" "$STATE_DIR/backlog.md"
  [[ -f "$STATE_DIR/settings.json" ]] && return 0
  if [[ ! -f "$SKILL_DIR/settings.example.json" ]]; then
    say "note: no settings.example.json at $SKILL_DIR — install the skill, then rerun"
    return 0
  fi
  cp "$SKILL_DIR/settings.example.json" "$STATE_DIR/settings.json"
  say "Created postflight-state/settings.json from settings.example.json"
}

# A photos: path written before the move still points into the old state
# folder. Rewriting the user's own file is the one thing this script will not
# do, so it says which line to change and leaves it alone.
warn_stale_photo_paths() {
  local pillars="$STATE_DIR/pillars.local.md"
  [[ -f "$pillars" ]] || return 0
  grep -q 'photos:[[:space:]]*state/' "$pillars" || return 0
  say ""
  say "note: pillars.local.md has a photos: path starting with state/, which"
  say "      no longer resolves. Drop the state/ prefix — 'photos:state/media/"
  say "      photos/foo' becomes 'photos:media/photos/foo'."
}

if [[ -e "$INCOMING" && $CHECK_ONLY -eq 0 ]]; then
  rm -rf "$INCOMING"
  say "Cleared a partial copy left by an interrupted run"
fi

# Two live state directories cannot be merged without guessing which post log
# is the real one. Refusing costs a manual decision; guessing costs history.
if [[ -d "$STATE_DIR" && -d "$OLD_STATE" ]]; then
  die "state exists in both places:
  $STATE_DIR
  $OLD_STATE
Keep the one you want, move the other out of the way, then rerun."
fi

if [[ -d "$STATE_DIR" ]]; then
  if [[ $CHECK_ONLY -eq 0 ]]; then scaffold; fi
  say "State is at $STATE_DIR"
  exit 0
fi

if [[ ! -d "$OLD_STATE" ]]; then
  if [[ $CHECK_ONLY -eq 1 ]]; then say "would create $STATE_DIR"; exit 0; fi
  scaffold
  say "Created $STATE_DIR"
  exit 0
fi

if [[ $CHECK_ONLY -eq 1 ]]; then
  say "would move $OLD_STATE to $STATE_DIR"
  exit 0
fi

mkdir -p "$WORKSPACE"
cp -R "$OLD_STATE" "$INCOMING"

collisions=0
for lf in "$SKILL_DIR"/*.local.md; do
  [[ -f "$lf" ]] || continue
  if [[ -e "$INCOMING/$(basename "$lf")" ]]; then
    say "note: $(basename "$lf") exists in both places — kept the state/ copy"
    collisions=1
    continue
  fi
  cp "$lf" "$INCOMING/"
done

# The commit point. Everything above wrote to .incoming, so an interrupt up to
# here leaves the originals whole and the next run clears the partial copy.
mv "$INCOMING" "$STATE_DIR"

mkdir -p "$PARK"
mv "$OLD_STATE" "$PARK/state"
for lf in "$SKILL_DIR"/*.local.md; do
  [[ -f "$lf" ]] || continue
  mv "$lf" "$PARK/"
done

scaffold
warn_stale_photo_paths

say ""
say "Moved the skill's state out of the skill folder:"
say "  $OLD_STATE"
say "  -> $STATE_DIR"
say ""
say "The originals are parked at $PARK."
say "Delete them once a full draft loop has run."
if [[ $collisions -eq 1 ]]; then
  say "One or more *.local.md files existed in both places; the parked copies"
  say "are the ones from the skill folder."
fi
say ""
say "Send /new to your bot. A running session read the old paths when it"
say "started and will keep using them until it restarts."
