#!/usr/bin/env bash
# Exercises scripts/install.sh end to end against scratch workspaces.
#
#   ./scripts/tests/install-fixture.sh
#
# relocate-fixture.sh tests the relocation in isolation. This one tests the
# chain: install.sh runs the x-poster rename shim, then rsyncs the skill, then
# relocates. A pre-v1.0.0 install therefore hops
# x-poster/state -> postflight/state -> postflight-state in a single run, and
# each hop is a different script believing something about the previous one.
#
# Needs rsync and nothing else — no openclaw, no network.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
command -v rsync >/dev/null || { echo "error: rsync is required" >&2; exit 1; }

SCRATCH=()
trap 'rm -rf ${SCRATCH[@]+"${SCRATCH[@]}"} 2>/dev/null' EXIT

FAILURES=0
CASE="startup"

pass() { printf '  \033[32m✓\033[0m %s\n' "$1"; }
fail() { printf '  \033[31m✗\033[0m %s: %s\n' "$CASE" "$1" >&2; FAILURES=$((FAILURES + 1)); }
testcase() { CASE="$1"; printf '\n\033[1m%s\033[0m\n' "$1"; }

check() {
  local desc="$1"; shift
  if "$@" >/dev/null 2>&1; then pass "$desc"; else fail "$desc"; fi
}

install_into() {
  OPENCLAW_WORKSPACE="$1" bash "$REPO_DIR/scripts/install.sh"
}

# ---------- the full pre-v1.0.0 chain ----------

testcase "carries a pre-rename install through both hops"

ws="$(mktemp -d)"; SCRATCH+=("$ws")
legacy="$ws/skills/x-poster"
mkdir -p "$legacy/state/pending" "$legacy/state/media/photos"
printf '# Postflight\n' > "$legacy/SKILL.md"
printf '{"date":"2026-08-01","topic":"legacy-sentinel"}\n' > "$legacy/state/post-log.jsonl"
printf '{"telegramTo":"legacy-user-id","maxPerDay":3}\n' > "$legacy/state/settings.json"
printf 'legacy photo bytes\n' > "$legacy/state/media/photos/old.jpg"
printf '# Pillars\n\nmedia: photos:state/media/photos/\n' > "$legacy/pillars.local.md"
printf '# Voice\n\nlegacy tweet\n' > "$legacy/voice-examples.local.md"

out="$(install_into "$ws" 2>&1)"

check "the post log survived both hops" \
  grep -q legacy-sentinel "$ws/postflight-state/post-log.jsonl"
check "telegramTo survived both hops" \
  grep -q legacy-user-id "$ws/postflight-state/settings.json"
check "the photo survived both hops" \
  test -f "$ws/postflight-state/media/photos/old.jpg"
check "pillars.local.md survived both hops" \
  test -f "$ws/postflight-state/pillars.local.md"
check "voice-examples.local.md survived both hops" \
  test -f "$ws/postflight-state/voice-examples.local.md"
check "no state/ left inside the skill folder" \
  test ! -e "$ws/skills/postflight/state"
check "no *.local.md left inside the skill folder" \
  test ! -e "$ws/skills/postflight/pillars.local.md"
check "the pre-rename copy is parked, not deleted" \
  test -d "$ws/x-poster-pre-rename-backup"
check "the pre-move copy is parked, not deleted" \
  test -f "$ws/postflight-state-pre-move-backup/state/post-log.jsonl"

# The user's photo path stops resolving after the move and the script must
# say so rather than rewrite their file.
if printf '%s' "$out" | grep -q 'photos:'; then
  pass "warns that the pillar's photos: path needs updating"
else
  fail "silent about the now-broken photos: path"
fi
check "did not rewrite the user's pillars.local.md" \
  grep -q 'photos:state/media/photos/' "$ws/postflight-state/pillars.local.md"

# ---------- rerunning an upgrade ----------

testcase "a second install.sh keeps the state it just moved"

before="$(cat "$ws/postflight-state/post-log.jsonl")"
install_into "$ws" >/dev/null 2>&1
if [[ "$before" == "$(cat "$ws/postflight-state/post-log.jsonl")" ]]; then
  pass "the post log is untouched by a repeat install"
else
  fail "a repeat install modified the post log"
fi
check "settings.json was not reset to the example" \
  grep -q legacy-user-id "$ws/postflight-state/settings.json"

# ---------- a clean first install ----------

testcase "a fresh workspace gets a working state directory"

ws_new="$(mktemp -d)"; SCRATCH+=("$ws_new")
mkdir -p "$ws_new/skills"
install_into "$ws_new" >/dev/null 2>&1

check "settings.json exists" test -f "$ws_new/postflight-state/settings.json"
check "the skill files are installed" test -f "$ws_new/skills/postflight/SKILL.md"
check "nothing was parked, since nothing moved" \
  test ! -e "$ws_new/postflight-state-pre-move-backup"
check "SKILL.md defines the state directory" \
  grep -q 'postflight-state/' "$ws_new/skills/postflight/SKILL.md"

# ---------- result ----------

printf '\n'
if [[ $FAILURES -eq 0 ]]; then
  printf '\033[32mAll checks passed.\033[0m\n'
  exit 0
fi
printf '\033[31m%s check(s) failed.\033[0m\n' "$FAILURES" >&2
exit 1
