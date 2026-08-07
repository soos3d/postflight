#!/usr/bin/env bash
# Exercises scripts/relocate-state.sh against scratch workspaces under $TMPDIR.
#
#   ./scripts/tests/relocate-fixture.sh
#
# Every other file in this repo is prose or a wizard step that a person watches
# run. relocate-state.sh moves a photo library and an append-only post log that
# exist in exactly one copy, so it gets the tests.
#
# Nothing here needs openclaw, network, or a real install: the script's only
# inputs are OPENCLAW_WORKSPACE and what it finds on disk.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$REPO_DIR/scripts/relocate-state.sh"
[[ -x "$SCRIPT" ]] || { echo "error: $SCRIPT is missing or not executable" >&2; exit 1; }

if command -v sha256sum >/dev/null 2>&1; then HASHER=(sha256sum); else HASHER=(shasum -a 256); fi

SCRATCH=()
trap 'rm -rf ${SCRATCH[@]+"${SCRATCH[@]}"} 2>/dev/null' EXIT

FAILURES=0
CASE="startup"

pass() { printf '  \033[32m✓\033[0m %s\n' "$1"; }
fail() { printf '  \033[31m✗\033[0m %s: %s\n' "$CASE" "$1" >&2; FAILURES=$((FAILURES + 1)); }
testcase() { CASE="$1"; printf '\n\033[1m%s\033[0m\n' "$1"; }

check() { # description, then a command that must succeed
  local desc="$1"; shift
  if "$@" >/dev/null 2>&1; then pass "$desc"; else fail "$desc"; fi
}

# "<hash>  ./relative/path" for every file, sorted. Comparing two of these
# proves content and layout together, which is the only claim that matters
# here: the same bytes under the same names.
hash_tree() {
  ( cd "$1" && find . -type f -exec "${HASHER[@]}" {} + ) | LC_ALL=C sort
}

# A workspace holding a pre-move install: state inside the skill folder, with
# the files a real install cannot recreate.
seed_workspace() {
  local ws skill
  ws="$(mktemp -d)"
  SCRATCH+=("$ws")
  skill="$ws/skills/postflight"

  mkdir -p "$skill/state/pending" "$skill/state/skipped" "$skill/state/media/photos"
  cp "$REPO_DIR/skill/postflight/settings.example.json" "$skill/settings.example.json"
  printf '# Postflight\n' > "$skill/SKILL.md"

  printf '{"date":"2026-08-01","topic":"sentinel-topic","url":"https://x.com/i/status/1"}\n' \
    > "$skill/state/post-log.jsonl"
  printf '{"maxPerDay":3,"telegramTo":"sentinel-user-id","postVia":"api"}\n' \
    > "$skill/state/settings.json"
  printf '{"date":"2026-08-01","impressions":41}\n' > "$skill/state/metrics.jsonl"
  printf '## Backlog\n\n- sentinel backlog item\n' > "$skill/state/backlog.md"
  printf 'sentinel pending draft\n' > "$skill/state/pending/20260801-0930.md"
  printf 'sentinel photo bytes\n' > "$skill/state/media/photos/sunset.jpg"
  printf 'sunset.jpg: a sentinel caption\n' > "$skill/state/media/photos/manifest.yaml"
  printf '# Pillars\n\nslot 1: builds\n' > "$skill/pillars.local.md"
  printf '# Voice\n\nsentinel tweet\n' > "$skill/voice-examples.local.md"

  printf '%s' "$ws"
}

run() { # workspace, then flags
  local ws="$1"; shift
  OPENCLAW_WORKSPACE="$ws" "$SCRIPT" "$@"
}

# ---------- a pre-move install moves without losing anything ----------

testcase "moves a pre-move install"

ws="$(seed_workspace)"
before="$(hash_tree "$ws/skills/postflight/state")"
run "$ws" >/dev/null

after="$(hash_tree "$ws/postflight-state")"
missing="$(comm -23 <(printf '%s\n' "$before") <(printf '%s\n' "$after") || true)"
if [[ -z "$missing" ]]; then
  pass "every seeded file arrived with identical bytes"
else
  fail "files lost or altered in the move:
$missing"
fi

check "the photo library came across" \
  test -f "$ws/postflight-state/media/photos/sunset.jpg"
check "the pending draft came across" \
  test -f "$ws/postflight-state/pending/20260801-0930.md"
check "pillars.local.md came across" \
  test -f "$ws/postflight-state/pillars.local.md"
check "voice-examples.local.md came across" \
  test -f "$ws/postflight-state/voice-examples.local.md"
check "the sentinel telegramTo survived" \
  grep -q sentinel-user-id "$ws/postflight-state/settings.json"

# ---------- the skill folder is left clean, the originals parked ----------

testcase "parks the originals and empties the skill folder"

check "state/ is gone from the skill folder" \
  test ! -e "$ws/skills/postflight/state"
check "pillars.local.md is gone from the skill folder" \
  test ! -e "$ws/skills/postflight/pillars.local.md"
check "voice-examples.local.md is gone from the skill folder" \
  test ! -e "$ws/skills/postflight/voice-examples.local.md"
check "the parked post log is still readable" \
  grep -q sentinel-topic "$ws/postflight-state-pre-move-backup/state/post-log.jsonl"
check "the parked photo is still there" \
  test -f "$ws/postflight-state-pre-move-backup/state/media/photos/sunset.jpg"
check "the parked pillars file is still there" \
  test -f "$ws/postflight-state-pre-move-backup/pillars.local.md"
check "no .incoming directory was left behind" \
  test ! -e "$ws/postflight-state.incoming"

# ---------- rerunning changes nothing ----------

testcase "is a no-op on rerun"

snapshot="$(hash_tree "$ws/postflight-state")"
if run "$ws" >/dev/null 2>&1; then
  pass "a second run exits 0"
else
  fail "a second run exited non-zero"
fi
if [[ "$snapshot" == "$(hash_tree "$ws/postflight-state")" ]]; then
  pass "a second run changes nothing"
else
  fail "a second run modified the state directory"
fi

# ---------- two live state directories are refused ----------

testcase "refuses when state exists in both places"

ws_both="$(seed_workspace)"
mkdir -p "$ws_both/postflight-state"
printf '{"date":"2026-08-02","topic":"the-other-one"}\n' \
  > "$ws_both/postflight-state/post-log.jsonl"

if run "$ws_both" >/dev/null 2>&1; then
  fail "merged two state directories instead of refusing"
else
  pass "exits non-zero rather than guessing"
fi
check "left the pre-move state alone" \
  grep -q sentinel-topic "$ws_both/skills/postflight/state/post-log.jsonl"
check "left the new state alone" \
  grep -q the-other-one "$ws_both/postflight-state/post-log.jsonl"

# ---------- a fresh install gets a scaffold ----------

testcase "scaffolds a fresh install"

ws_fresh="$(mktemp -d)"
SCRATCH+=("$ws_fresh")
mkdir -p "$ws_fresh/skills/postflight"
cp "$REPO_DIR/skill/postflight/settings.example.json" "$ws_fresh/skills/postflight/"
run "$ws_fresh" >/dev/null

check "settings.json is created from the example" \
  test -f "$ws_fresh/postflight-state/settings.json"
check "pending/ is created" test -d "$ws_fresh/postflight-state/pending"
check "skipped/ is created" test -d "$ws_fresh/postflight-state/skipped"
check "media/ is created" test -d "$ws_fresh/postflight-state/media"
check "post-log.jsonl is created" test -f "$ws_fresh/postflight-state/post-log.jsonl"
check "backlog.md is created" test -f "$ws_fresh/postflight-state/backlog.md"

# ---------- an interrupted run leaves nothing that blocks the next one ----------

testcase "clears a partial copy from an interrupted run"

ws_partial="$(seed_workspace)"
mkdir -p "$ws_partial/postflight-state.incoming/pending"
printf 'half-written\n' > "$ws_partial/postflight-state.incoming/post-log.jsonl"
run "$ws_partial" >/dev/null

check "the partial copy is gone" test ! -e "$ws_partial/postflight-state.incoming"
check "the real post log won, not the partial one" \
  grep -q sentinel-topic "$ws_partial/postflight-state/post-log.jsonl"

# ---------- a --dev symlink is followed to the checkout ----------

testcase "follows a --dev symlink to the checkout"

ws_dev="$(mktemp -d)"
checkout="$(mktemp -d)"
SCRATCH+=("$ws_dev" "$checkout")
mkdir -p "$ws_dev/skills" "$checkout/state/pending"
cp "$REPO_DIR/skill/postflight/settings.example.json" "$checkout/"
printf '{"date":"2026-08-01","topic":"dev-sentinel"}\n' > "$checkout/state/post-log.jsonl"
printf '# Pillars\n' > "$checkout/pillars.local.md"
ln -s "$checkout" "$ws_dev/skills/postflight"
run "$ws_dev" >/dev/null

check "state moved into the workspace, not the checkout" \
  grep -q dev-sentinel "$ws_dev/postflight-state/post-log.jsonl"
check "the checkout's state/ is gone" test ! -e "$checkout/state"
check "the checkout's pillars.local.md is gone" test ! -e "$checkout/pillars.local.md"
check "the symlink itself is intact" test -L "$ws_dev/skills/postflight"

# ---------- --check writes nothing ----------

testcase "--check reports without writing"

ws_check="$(seed_workspace)"
out="$(run "$ws_check" --check)"
check "no state directory was created" test ! -e "$ws_check/postflight-state"
check "the pre-move state is untouched" \
  test -f "$ws_check/skills/postflight/state/post-log.jsonl"
if printf '%s' "$out" | grep -q 'would move'; then
  pass "says it would move the directory"
else
  fail "did not report the pending move"
fi

# ---------- a stale photos: path is called out, not rewritten ----------

testcase "names a pre-move photos: path without editing it"

ws_photo="$(seed_workspace)"
printf '# Pillars\n\nslot 3: photos:state/media/photos/\n' \
  > "$ws_photo/skills/postflight/pillars.local.md"
out="$(run "$ws_photo")"

if printf '%s' "$out" | grep -q 'photos:'; then
  pass "warns about the stale path"
else
  fail "moved on without mentioning the stale path"
fi
check "left the user's file exactly as written" \
  grep -q 'photos:state/media/photos/' "$ws_photo/postflight-state/pillars.local.md"

# ---------- result ----------

printf '\n'
if [[ $FAILURES -eq 0 ]]; then
  printf '\033[32mAll checks passed.\033[0m\n'
  exit 0
fi
printf '\033[31m%s check(s) failed.\033[0m\n' "$FAILURES" >&2
exit 1
