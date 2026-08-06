#!/usr/bin/env bash
# Installs the x-poster skill into an OpenClaw workspace and prints next steps.
# Default mode copies the skill; --dev symlinks it for live editing (requires
# whitelisting the target via skills.load.allowSymlinkTargets in OpenClaw config).
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SKILL_SRC="$REPO_DIR/skill/x-poster"
WORKSPACE="${OPENCLAW_WORKSPACE:-$HOME/.openclaw/workspace}"
SKILL_DEST="$WORKSPACE/skills/x-poster"

MODE="copy"
if [[ $# -gt 0 ]]; then
  if [[ "$1" == "--dev" ]]; then
    MODE="dev"
  else
    echo "usage: install.sh [--dev]" >&2
    exit 1
  fi
fi

if [[ ! -d "$WORKSPACE" ]]; then
  echo "error: OpenClaw workspace not found at $WORKSPACE" >&2
  echo "Set OPENCLAW_WORKSPACE or run 'openclaw onboard' first." >&2
  exit 1
fi

mkdir -p "$WORKSPACE/skills"

if [[ "$MODE" == "dev" ]]; then
  if [[ -e "$SKILL_DEST" && ! -L "$SKILL_DEST" ]]; then
    echo "error: $SKILL_DEST exists and is not a symlink." >&2
    echo "Back up its state/ directory, remove it, then rerun with --dev." >&2
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
    echo "error: $SKILL_DEST exists but doesn't look like an x-poster install." >&2
    echo "Refusing to overwrite it; move it out of the way first." >&2
    exit 1
  fi
  mkdir -p "$SKILL_DEST"
  rsync -a --delete \
    --exclude 'state/' \
    --exclude '*.local.md' \
    "$SKILL_SRC/" "$SKILL_DEST/"
  echo "Copied skill to $SKILL_DEST"
  SKILL_SRC="$SKILL_DEST"
fi

mkdir -p "$SKILL_SRC/state/pending" "$SKILL_SRC/state/skipped" "$SKILL_SRC/state/media"
touch "$SKILL_SRC/state/post-log.jsonl" "$SKILL_SRC/state/backlog.md"
if [[ ! -f "$SKILL_SRC/state/settings.json" ]]; then
  cp "$SKILL_SRC/settings.example.json" "$SKILL_SRC/state/settings.json"
  echo "Created state/settings.json from settings.example.json"
fi

cat <<EOF

Skill files: $SKILL_SRC
Settings:    $SKILL_SRC/state/settings.json
Voice anchor (add 3-5 of your own tweets): $SKILL_SRC/voice-examples.local.md
Your pillars (copy pillars.example.md here and edit): $SKILL_SRC/pillars.local.md

Next steps (one-time, interactive; details in the repo README):
  1. Model auth (Claude subscription reuse; needs a real terminal):
       openclaw models auth setup-token --provider anthropic
       openclaw config set agents.defaults.model.primary "anthropic/claude-fable-5"
  2. X API auth (default posting mode; see skill PUBLISH-API.md):
       at console.x.com create a project with an app INSIDE it, enable
       OAuth 2.0 (callback http://localhost:8080/callback), install xurl, then:
       xurl auth apps add x-poster --client-id ID --client-secret SECRET
       xurl auth oauth2 --app x-poster
       xurl auth default x-poster
       xurl /2/users/me   # prints your handle when it all works
     (typing the secret inline leaves it in shell history — prefer running
      scripts/setup.sh, which prompts for it hidden; see docs/SETUP-MANUAL.md)
     (browser fallback instead: openclaw browser open https://x.com and log in,
      then set "postVia": "browser" in the settings file below)
  3. Telegram approvals (optional, enables ship/skip from your phone):
       create a bot with @BotFather, save its token to a private file
       (kept out of shell history; SETUP-MANUAL.md shows the exact commands):
       openclaw channels add --channel telegram --token-file ~/.openclaw/credentials/telegram-bot-token
       openclaw gateway install
       message the bot once; it replies with your user id and a pairing code:
       openclaw pairing approve telegram <CODE>
       openclaw config set commands.ownerAllowFrom '["telegram:<YOUR_USER_ID>"]'
       openclaw gateway restart
       put your Telegram user id into "telegramTo" in the settings file above
       (if the bot later ignores skill edits or a model change, send /new to
        the bot: the persistent session only re-reads config when it starts)
  4. Cron (after a supervised test run; times target US engagement windows —
     adjust to your audience and waking hours, and note every draft waits on
     your Telegram reply). The --channel/--to flags are required: isolated
     sessions have no default route, so a job without them fails closed:
       openclaw cron create "30 9 * * *"  "Run the x-poster skill: draft one post for slot 1 of the pillar schedule (CONTENT.md Pillars) and request approval." --name x-poster-own-work --session isolated --tz America/New_York --channel telegram --to <YOUR_USER_ID>
       openclaw cron create "30 12 * * *" "Run the x-poster skill: draft one post for slot 2 of the pillar schedule (CONTENT.md Pillars) and request approval." --name x-poster-ai-news --session isolated --tz America/New_York --channel telegram --to <YOUR_USER_ID>
       openclaw cron create "0 15 * * *"  "Run the x-poster skill: draft one post for slot 3 of the pillar schedule (CONTENT.md Pillars) and request approval." --name x-poster-aviation --session isolated --tz America/New_York --channel telegram --to <YOUR_USER_ID>
       openclaw cron create "0 8 * * 1"   "x-poster maintenance turn: refresh the content backlog per CONTENT.md, all pillar sections, then run the weekly metrics readback per CONTENT.md \"Metrics readback\". Do not draft or publish." --name x-poster-backlog --session isolated --tz America/New_York --channel telegram --to <YOUR_USER_ID>
EOF
