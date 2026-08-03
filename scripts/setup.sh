#!/usr/bin/env bash
# One-command setup for the x-poster OpenClaw skill.
#
#   curl -fsSL https://raw.githubusercontent.com/Soos3D/x-openclaw/main/scripts/setup.sh | bash
#   ./scripts/setup.sh [--check] [--dev]
#
# Every step probes real state first and skips what's already done, so the
# script is safe to rerun after any failure and doubles as a health check.
# --check reports the state of every step and changes nothing.
# --dev installs the skill as a symlink instead of a copy.
#
# The two things it cannot do for you: create the X app (console.x.com) and
# create the Telegram bot (@BotFather). It pauses and walks you through both.
set -euo pipefail

REPO_URL="${X_OPENCLAW_REPO:-https://github.com/Soos3D/x-openclaw}"
REPO_DIR="${X_OPENCLAW_DIR:-$HOME/x-openclaw}"
WORKSPACE="${OPENCLAW_WORKSPACE:-$HOME/.openclaw/workspace}"
XURL_APP="x-poster"
MODEL="anthropic/claude-fable-5"

CHECK_ONLY=0
DEV_MODE=0
for arg in "$@"; do
  case "$arg" in
    --check) CHECK_ONLY=1 ;;
    --dev) DEV_MODE=1 ;;
    *) echo "usage: setup.sh [--check] [--dev]" >&2; exit 1 ;;
  esac
done

# ---------- output helpers ----------

RESULTS=()
ok()   { printf '  \033[32m✓\033[0m %s\n' "$1"; RESULTS+=("✓ $1"); }
todo() { printf '  \033[33m•\033[0m %s\n' "$1"; RESULTS+=("• $1"); }
fail() { printf '  \033[31m✗\033[0m %s\n' "$1" >&2; RESULTS+=("✗ $1"); }
step() { printf '\n\033[1m%s\033[0m\n' "$1"; }
die()  { printf '\033[31merror:\033[0m %s\n' "$1" >&2; exit 1; }

# Interactive input must come from the terminal even when the script itself
# arrives on stdin via curl | bash.
TTY=/dev/tty
interactive() { [[ -e $TTY ]] && [[ $CHECK_ONLY -eq 0 ]]; }
ask()  { local v; read -r -p "$1" v < "$TTY"; printf '%s' "$v"; }
ask_secret() { local v; read -r -s -p "$1" v < "$TTY"; printf '\n' > "$TTY"; printf '%s' "$v"; }
ask_default() { local v; v="$(ask "$1 [$2]: ")"; printf '%s' "${v:-$2}"; }
pause_tty() { read -r -p "$1" _ < "$TTY"; }

# ---------- step 0: run from a checkout ----------

ensure_repo() {
  local script_dir=""
  if [[ -n "${BASH_SOURCE[0]:-}" && -f "${BASH_SOURCE[0]}" ]]; then
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  fi
  if [[ -n "$script_dir" && -f "$script_dir/../skill/x-poster/SKILL.md" ]]; then
    REPO_DIR="$(cd "$script_dir/.." && pwd)"
    return
  fi
  # curl | bash: fetch the repo, then hand off to the checked-out script.
  command -v git >/dev/null || die "git is required to fetch $REPO_URL"
  if [[ -d "$REPO_DIR/.git" ]]; then
    git -C "$REPO_DIR" pull --ff-only
  else
    git clone "$REPO_URL" "$REPO_DIR"
  fi
  exec bash "$REPO_DIR/scripts/setup.sh" "$@"
}

# ---------- step 1: dependencies ----------

step_deps() {
  step "Dependencies"
  local missing=()
  for tool in git curl jq rsync; do
    command -v "$tool" >/dev/null && ok "$tool" || missing+=("$tool")
  done
  [[ ${#missing[@]} -eq 0 ]] || die "install first: ${missing[*]}"
  if gh auth status >/dev/null 2>&1; then
    ok "gh CLI authenticated"
  else
    todo "gh CLI not authenticated — own-repo sourcing won't work (gh auth login)"
  fi
}

node_major() { node -v 2>/dev/null | sed -E 's/^v([0-9]+).*/\1/' || true; }

step_node() {
  step "Node.js (OpenClaw needs 22.22+ / 24.15+)"
  if [[ "$(node_major)" -ge 24 ]] 2>/dev/null; then
    ok "node $(node -v)"
    return
  fi
  local candidate
  candidate="$(find "$HOME/.nvm/versions/node" -maxdepth 1 -name 'v2[4-9].*' 2>/dev/null | sort -V | tail -1 || true)"
  if [[ -n "$candidate" ]]; then
    export PATH="$candidate/bin:$PATH"
    ok "node $(node -v) (via $candidate — add its bin to PATH permanently)"
    return
  fi
  fail "no Node >= 24 found"
  die "install one first: nvm install 24"
}

step_openclaw() {
  step "OpenClaw"
  command -v openclaw >/dev/null || die "OpenClaw not installed — see https://docs.openclaw.ai, then run: openclaw onboard"
  [[ -d "$WORKSPACE" ]] || die "workspace missing at $WORKSPACE — run: openclaw onboard"
  ok "openclaw $(openclaw --version 2>/dev/null | head -1 || echo present)"
}

# ---------- step 2: skill install ----------

skill_dir() {
  if [[ $DEV_MODE -eq 1 ]]; then printf '%s' "$REPO_DIR/skill/x-poster";
  else printf '%s' "$WORKSPACE/skills/x-poster"; fi
}

step_skill() {
  step "Skill install"
  local dest="$WORKSPACE/skills/x-poster"
  if [[ $DEV_MODE -eq 1 && -L "$dest" ]] || [[ $DEV_MODE -eq 0 && -f "$dest/SKILL.md" && ! -L "$dest" ]]; then
    ok "skill installed at $dest"
    [[ $CHECK_ONLY -eq 1 ]] && return
  fi
  if [[ $CHECK_ONLY -eq 1 ]]; then todo "skill not installed"; return; fi
  if [[ $DEV_MODE -eq 1 ]]; then
    bash "$REPO_DIR/scripts/install.sh" --dev
  else
    bash "$REPO_DIR/scripts/install.sh"
  fi
  ok "skill installed"
}

# ---------- step 3: xurl ----------

step_xurl() {
  step "xurl (X's official OAuth CLI)"
  if command -v xurl >/dev/null; then ok "xurl present"; return; fi
  if [[ $CHECK_ONLY -eq 1 ]]; then todo "xurl not installed"; return; fi
  local os arch tmp
  os="$(uname -s)" arch="$(uname -m)"
  [[ "$arch" == "aarch64" ]] && arch="arm64"
  tmp="$(mktemp -d)"
  curl -fsSL "https://github.com/xdevplatform/xurl/releases/latest/download/xurl_${os}_${arch}.tar.gz" \
    -o "$tmp/xurl.tar.gz" || die "no xurl release for ${os}_${arch} — install manually: https://github.com/xdevplatform/xurl"
  tar xzf "$tmp/xurl.tar.gz" -C "$tmp"
  mkdir -p "$HOME/.local/bin"
  mv "$tmp/xurl" "$HOME/.local/bin/xurl"
  rm -rf "$tmp"
  export PATH="$HOME/.local/bin:$PATH"
  ok "xurl installed to ~/.local/bin (make sure that's on your PATH)"
}

# ---------- step 4: model auth ----------

anthropic_ready() {
  openclaw models status --json 2>/dev/null | jq -e '
    ([.auth.providers[]? | select(.provider=="anthropic") | .profiles.count] | add // 0) > 0
    and (.defaultModel | startswith("anthropic/"))' >/dev/null
}

step_model() {
  step "Model auth (Claude subscription, no API bill)"
  if anthropic_ready; then ok "anthropic auth + default model configured"; return; fi
  if ! interactive; then todo "model auth not configured (run without --check, in a terminal)"; return; fi
  echo "  A browser approval on claude.ai will open."
  openclaw models auth setup-token --provider anthropic < "$TTY"
  openclaw config set agents.defaults.model.primary "$MODEL"
  anthropic_ready || die "model auth still not detected after setup-token"
  ok "anthropic auth + default model ($MODEL)"
}

# ---------- step 5: X credentials ----------

x_handle() { xurl /2/users/me 2>/dev/null | jq -er '.data.username' 2>/dev/null; }

step_x() {
  step "X API access"
  local handle
  if handle="$(x_handle)"; then ok "posting as @$handle"; return; fi
  if ! interactive; then todo "X auth not configured"; return; fi
  cat <<'EOF'
  Do this once at https://console.x.com/ :
    1. Create a PROJECT, and an app INSIDE it (a standalone app fails every
       v2 call with client-not-enrolled). The project needs a package with
       write access; the entry tier covers 3 posts/day easily.
    2. In the app's User authentication settings: enable OAuth 2.0, choose
       "Web App, Automated App or Bot", callback URI exactly
       http://localhost:8080/callback, any real website URL.
    3. Copy the OAuth 2.0 Client ID and Client Secret.
EOF
  local client_id client_secret
  client_id="$(ask "  Client ID: ")"
  client_secret="$(ask_secret "  Client Secret (hidden): ")"
  [[ -n "$client_id" && -n "$client_secret" ]] || die "client id/secret required"
  xurl auth apps add "$XURL_APP" --client-id "$client_id" --client-secret "$client_secret"
  echo "  A browser consent window will open (grants offline.access for headless refresh)."
  xurl auth oauth2 --app "$XURL_APP" < "$TTY"
  xurl auth default "$XURL_APP"
  handle="$(x_handle)" || die "auth completed but /2/users/me failed — check the app package on console.x.com"
  ok "posting as @$handle"
}

# ---------- step 6: telegram ----------

settings_file() { printf '%s/state/settings.json' "$(skill_dir)"; }

telegram_to() { jq -r '.telegramTo // empty' "$(settings_file)" 2>/dev/null; }

telegram_channel_installed() {
  openclaw channels list --json 2>/dev/null | jq -e '.chat.telegram.installed == true' >/dev/null
}

write_telegram_to() {
  local file tmp
  file="$(settings_file)"
  tmp="$(mktemp)"
  jq --arg id "$1" '.telegramTo = $id' "$file" > "$tmp" && mv "$tmp" "$file"
}

step_telegram() {
  step "Telegram approvals"
  if telegram_channel_installed && [[ -n "$(telegram_to)" ]]; then
    ok "telegram channel installed, approvals go to $(telegram_to)"
    return
  fi
  if ! interactive; then todo "telegram not fully configured"; return; fi
  if ! telegram_channel_installed; then
    echo "  Create a bot with @BotFather (/newbot) and copy its token."
    local bot_token
    bot_token="$(ask_secret "  Bot token (hidden): ")"
    [[ -n "$bot_token" ]] || die "bot token required"
    openclaw channels add --channel telegram --token "$bot_token"
    openclaw gateway install
  fi
  echo "  Now send any message to your bot from your own Telegram account."
  echo "  It replies with your numeric user id and a pairing code."
  local code user_id
  code="$(ask "  Pairing code: ")"
  openclaw pairing approve telegram "$code"
  user_id="$(ask "  Your numeric Telegram user id: ")"
  [[ "$user_id" =~ ^[0-9]+$ ]] || die "user id must be numeric"
  openclaw config set commands.ownerAllowFrom "[\"telegram:$user_id\"]"
  write_telegram_to "$user_id"
  openclaw gateway restart
  ok "telegram paired; approvals restricted to $user_id"
}

# ---------- step 7: cron ----------

CRON_NAMES=(x-poster-own-work x-poster-ai-news x-poster-aviation x-poster-backlog)

cron_missing() {
  local existing
  existing="$(openclaw cron list --json 2>/dev/null | jq -r '.jobs[].name')"
  local name out=()
  for name in "${CRON_NAMES[@]}"; do
    grep -qx "$name" <<<"$existing" || out+=("$name")
  done
  printf '%s\n' "${out[@]:-}"
}

create_cron() { # name, expr, tz, message, to
  openclaw cron create "$2" "$4" --name "$1" --session isolated --tz "$3" \
    --channel telegram --to "$5" >/dev/null
  ok "cron $1 ($2 @ $3)"
}

step_cron() {
  step "Cron schedule"
  local missing
  missing="$(cron_missing)"
  if [[ -z "$missing" ]]; then ok "all four jobs registered"; return; fi
  if ! interactive; then todo "missing cron jobs: $(tr '\n' ' ' <<<"$missing")"; return; fi
  local to tz t1 t2 t3
  to="$(telegram_to)"
  [[ -n "$to" ]] || die "finish the Telegram step first — cron alerts need a destination"
  tz="$(ask_default "  Timezone" "$(jq -r '.timezone // "Europe/Rome"' "$(settings_file)")")"
  echo "  Defaults target US engagement windows (9:30/12:30/15:00 ET from Europe)."
  t1="$(ask_default "  Slot 1 (own work) HH:MM" "15:30")"
  t2="$(ask_default "  Slot 2 (AI tools/news) HH:MM" "18:30")"
  t3="$(ask_default "  Slot 3 (aviation) HH:MM" "21:00")"
  local expr1 expr2 expr3
  expr1="${t1#*:} ${t1%%:*} * * *"
  expr2="${t2#*:} ${t2%%:*} * * *"
  expr3="${t3#*:} ${t3%%:*} * * *"
  grep -qx "x-poster-own-work" <<<"$missing" && create_cron x-poster-own-work "$expr1" "$tz" \
    "Run the x-poster skill: draft one post (own-work focus) and request approval." "$to"
  grep -qx "x-poster-ai-news" <<<"$missing" && create_cron x-poster-ai-news "$expr2" "$tz" \
    "Run the x-poster skill: draft one post (AI tools/news focus) and request approval." "$to"
  grep -qx "x-poster-aviation" <<<"$missing" && create_cron x-poster-aviation "$expr3" "$tz" \
    "Run the x-poster skill: draft one post (aviation focus per CONTENT.md) and request approval." "$to"
  grep -qx "x-poster-backlog" <<<"$missing" && create_cron x-poster-backlog "0 8 * * 1" "$tz" \
    "x-poster maintenance turn: refresh the content backlog per CONTENT.md. Do not draft or publish." "$to"
}

# ---------- step 8: voice ----------

step_voice() {
  step "Voice"
  local voice
  voice="$(skill_dir)/voice-examples.local.md"
  if [[ -s "$voice" ]]; then
    ok "voice-examples.local.md has content"
  else
    todo "add 3-5 of your own tweets to $voice (keeps the output sounding like you)"
  fi
}

summary() {
  step "Summary"
  printf '  %s\n' "${RESULTS[@]}"
  cat <<'EOF'

Next: message your bot "x-poster: draft a post" and reply ship or skip.
Rerun this script anytime — it only touches what's missing.
EOF
}

ensure_repo "$@"
step_deps
step_node
step_openclaw
step_skill
step_xurl
step_model
step_x
step_telegram
step_cron
step_voice
summary
