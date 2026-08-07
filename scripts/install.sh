#!/usr/bin/env bash
# Installs the Postflight skill into an OpenClaw workspace and prints next steps.
# Default mode copies the skill; --dev symlinks it for live editing (requires
# whitelisting the target via skills.load.allowSymlinkTargets in OpenClaw config).
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SKILL_SRC="$REPO_DIR/skill/postflight"
WORKSPACE="${OPENCLAW_WORKSPACE:-$HOME/.openclaw/workspace}"
SKILL_DEST="$WORKSPACE/skills/postflight"

MODE="copy"
QUIET=0
for arg in "$@"; do
  case "$arg" in
    --dev)   MODE="dev" ;;
    # setup.sh runs this script as one of its steps and prints its own
    # progress, so it suppresses the closing pointer to itself.
    --quiet) QUIET=1 ;;
    *) echo "usage: install.sh [--dev] [--quiet]" >&2; exit 1 ;;
  esac
done

if [[ ! -d "$WORKSPACE" ]]; then
  echo "error: OpenClaw workspace not found at $WORKSPACE" >&2
  echo "Set OPENCLAW_WORKSPACE or run 'openclaw onboard' first." >&2
  exit 1
fi

mkdir -p "$WORKSPACE/skills"

# ---------- one-time: this skill was named x-poster before the rename ----------
# Supported until 2026-11-01, then this whole block comes out (along with
# cron_migrate_names in setup.sh and the upgrade notes in README /
# docs/DEPLOY-VPS.md). Temporary migration code, dated so it stays temporary.

LEGACY_DEST="$WORKSPACE/skills/x-poster"
PARKED_DEST="$WORKSPACE/x-poster-pre-rename-backup"

# A dev symlink holds no state of its own — that lives in the repo, which the
# rename already moved — and it now points at a path that no longer exists.
if [[ -L "$LEGACY_DEST" ]]; then
  rm "$LEGACY_DEST"
  echo "Removed the pre-rename symlink at $LEGACY_DEST"
fi

# Carries across the two things install.sh never writes and cannot recreate:
# state/ (post log, metrics, photo library) and *.local.md. Then moves the old
# directory OUT of skills/, because a leftover copy still has a valid SKILL.md
# named x-poster and OpenClaw would load two skills. Nothing is deleted.
migrate_legacy_state() {
  [[ -d "$LEGACY_DEST" ]] || return 0
  if [[ -e "$PARKED_DEST" ]]; then
    echo "error: $PARKED_DEST already exists from an earlier run." >&2
    echo "Move or delete it, then rerun." >&2
    exit 1
  fi
  mkdir -p "$SKILL_DEST"
  if [[ -d "$LEGACY_DEST/state" ]]; then
    if [[ -d "$SKILL_DEST/state" ]]; then
      echo "Note: $SKILL_DEST/state already exists, so the pre-rename state was"
      echo "      left in the parked copy below rather than overwriting it."
    else
      mv "$LEGACY_DEST/state" "$SKILL_DEST/state"
      echo "Moved state/ from the pre-rename install"
    fi
  fi
  local lf
  for lf in "$LEGACY_DEST"/*.local.md; do
    [[ -f "$lf" ]] || continue
    [[ -e "$SKILL_DEST/$(basename "$lf")" ]] && continue
    mv "$lf" "$SKILL_DEST/"
    echo "Moved $(basename "$lf") from the pre-rename install"
  done
  mv "$LEGACY_DEST" "$PARKED_DEST"
  echo "Parked the pre-rename skill at $PARKED_DEST"
  echo "  (delete it once postflight has run a full draft loop)"
}

if [[ "$MODE" == "dev" ]]; then
  if [[ -e "$SKILL_DEST" && ! -L "$SKILL_DEST" ]]; then
    echo "error: $SKILL_DEST exists and is not a symlink." >&2
    echo "Remove it, then rerun with --dev. State lives in" >&2
    echo "$WORKSPACE/postflight-state and is not affected." >&2
    exit 1
  fi
  ln -sfn "$SKILL_SRC" "$SKILL_DEST"
  echo "Linked $SKILL_DEST -> $SKILL_SRC"
  echo "Add this to ~/.openclaw/openclaw.json so the symlink is trusted:"
  echo "  \"skills\": { \"load\": { \"allowSymlinkTargets\": [\"$REPO_DIR/skill\"] } }"
else
  command -v rsync >/dev/null || { echo "error: rsync is required" >&2; exit 1; }
  if [[ -L "$SKILL_DEST" ]]; then
    echo "error: $SKILL_DEST is a symlink (dev install); remove it or rerun with --dev." >&2
    exit 1
  fi
  if [[ -d "$SKILL_DEST" && ! -f "$SKILL_DEST/SKILL.md" ]]; then
    echo "error: $SKILL_DEST exists but doesn't look like a Postflight install." >&2
    echo "Refusing to overwrite it; move it out of the way first." >&2
    exit 1
  fi
  migrate_legacy_state
  mkdir -p "$SKILL_DEST"
  # The .clawhub/_meta/skill-card trio is written by `openclaw skills install`
  # and is how the registry recognizes its own install. This script overwrites
  # the skill files it owns; deleting someone else's provenance on the way past
  # is not part of the job, and the wizard runs on top of a ClawHub install by
  # design (README, "Want the skill files from a registry instead?").
  rsync -a --delete \
    --exclude 'state/' \
    --exclude '*.local.md' \
    --exclude '.clawhub/' \
    --exclude '_meta.json' \
    --exclude 'skill-card.md' \
    "$SKILL_SRC/" "$SKILL_DEST/"
  echo "Copied skill to $SKILL_DEST"
  SKILL_SRC="$SKILL_DEST"
fi

# State lives outside the skill folder, so this both moves a pre-move install
# and creates a fresh one. It runs after migrate_legacy_state, which means a
# pre-v1.0.0 tree hops x-poster/state -> postflight/state -> postflight-state
# in a single run.
OPENCLAW_WORKSPACE="$WORKSPACE" bash "$REPO_DIR/scripts/relocate-state.sh"

STATE_DIR="$WORKSPACE/postflight-state"

cat <<EOF

Skill files: $SKILL_SRC
Settings:    $STATE_DIR/settings.json
Voice anchor (add 3-5 of your own tweets): $STATE_DIR/voice-examples.local.md
Your pillars (copy pillars.example.md there and edit): $STATE_DIR/pillars.local.md
EOF

if [[ $QUIET -eq 0 ]]; then
  cat <<EOF

A model, X API access, Telegram approvals, and cron complete the install.
The wizard sets up whatever is missing and leaves the rest alone, so it
reads the same on a first run as it does after an upgrade:

  $REPO_DIR/scripts/setup.sh --check   # report every layer, change nothing
  $REPO_DIR/scripts/setup.sh           # set up whatever is missing

Every command it runs is written out in docs/SETUP-MANUAL.md, if you would
rather do them by hand.
EOF
fi
