#!/usr/bin/env bash
# One-command setup for the Postflight OpenClaw skill.
#
#   curl -fsSL https://raw.githubusercontent.com/soos3d/postflight/main/scripts/setup.sh | bash
#   ./scripts/setup.sh [--check] [--dev]
#
# Every step probes real state first and skips what's already done, so the
# script is safe to rerun after any failure and doubles as a health check.
# --check reports the state of every step and changes nothing.
# --dev installs the skill as a symlink instead of a copy.
#
# The two things it cannot do for you: create the X app (console.x.com) and
# create the Telegram bot (@BotFather). It pauses and walks you through both.
set -Eeuo pipefail

REPO_URL="${POSTFLIGHT_REPO:-https://github.com/soos3d/postflight}"
REPO_DIR="${POSTFLIGHT_DIR:-$HOME/postflight}"
WORKSPACE="${OPENCLAW_WORKSPACE:-$HOME/.openclaw/workspace}"
XURL_APP="postflight"
XURL_VERSION="${XURL_VERSION:-1.3.1}"
MODEL_ANTHROPIC="anthropic/claude-fable-5"
# OpenAI ids, best first. gpt-5.6-sol is the Codex-subscription tier but only
# newer OpenClaw releases list it; plain "openai/gpt-5.6" is deliberately
# absent — it is the API-key alias and would bill a developer account.
MODEL_OPENAI_CANDIDATES=(openai/gpt-5.6-sol openai/gpt-5.6-terra openai/gpt-5.5)

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
CURRENT_STEP="startup"
ok()   { printf '  \033[32m✓\033[0m %s\n' "$1"; RESULTS+=("✓ $1"); }
todo() { printf '  \033[33m•\033[0m %s\n' "$1"; RESULTS+=("• $1"); }
fail() { printf '  \033[31m✗\033[0m %s\n' "$1" >&2; RESULTS+=("✗ $1"); }
step() { CURRENT_STEP="$1"; printf '\n\033[1m%s\033[0m\n' "$1"; }
die()  { printf '\033[31merror:\033[0m %s\n' "$1" >&2; exit 1; }

# Temp files are registered here and removed on exit. RETURN traps are
# deliberately avoided: bash 3.2 (macOS) drops them after the setting
# function returns, bash 5 (Linux) keeps them firing on later returns —
# code that is correct on one breaks on the other.
CLEANUP=()
trap 'rm -rf ${CLEANUP[@]+"${CLEANUP[@]}"} 2>/dev/null' EXIT

# With -E this fires for unexpected failures inside functions too, so the
# wizard always says where it stopped instead of exiting silently.
on_err() {
  local rc=$1
  fail "step \"$CURRENT_STEP\" failed (exit $rc) — fix the message above and rerun to resume"
  summary
  exit "$rc"
}
trap 'on_err $?' ERR

# In --check mode a missing prerequisite is reported, not fatal, so the
# health check still covers the remaining layers.
halt() {
  if [[ $CHECK_ONLY -eq 1 ]]; then fail "$1"; return 0; fi
  die "$1"
}

# Interactive input must come from the terminal even when the script itself
# arrives on stdin via curl | bash. /dev/tty exists but is unopenable in
# cron/CI/docker-without-tty, so probe by opening it.
TTY=/dev/tty
interactive() { [[ $CHECK_ONLY -eq 0 ]] && (exec 3<>"$TTY") 2>/dev/null; }
ask()  { local v; read -r -p "$1" v < "$TTY"; printf '%s' "$v"; }
ask_secret() { local v; read -r -s -p "$1" v < "$TTY"; printf '\n' > "$TTY"; printf '%s' "$v"; }
ask_default() { local v; v="$(ask "$1 [$2]: ")"; printf '%s' "${v:-$2}"; }

ask_hhmm() {
  local v
  while :; do
    v="$(ask_default "$1" "$2")"
    [[ "$v" =~ ^([01][0-9]|2[0-3]):[0-5][0-9]$ ]] && break
    printf '  use HH:MM, 24-hour\n' > "$TTY"
  done
  printf '%s' "$v"
}

# ---------- step 0: run from a checkout ----------

ensure_repo() {
  local script_dir=""
  if [[ -n "${BASH_SOURCE[0]:-}" && -f "${BASH_SOURCE[0]}" ]]; then
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  fi
  if [[ -n "$script_dir" && -f "$script_dir/../skill/postflight/SKILL.md" ]]; then
    REPO_DIR="$(cd "$script_dir/.." && pwd)"
    return
  fi
  [[ -z "${POSTFLIGHT_REEXEC:-}" ]] || die "re-exec loop: $REPO_DIR is not a valid postflight checkout"
  # curl | bash: fetch the repo, then hand off to the checked-out script.
  command -v git >/dev/null || die "git is required to fetch $REPO_URL"
  if [[ -d "$REPO_DIR/.git" ]]; then
    local origin
    origin="$(git -C "$REPO_DIR" remote get-url origin 2>/dev/null || true)"
    [[ "$origin" == "$REPO_URL" || "$origin" == "$REPO_URL.git" ]] \
      || die "$REPO_DIR points at ${origin:-no remote}, not $REPO_URL — remove it or set POSTFLIGHT_DIR"
    [[ $CHECK_ONLY -eq 1 ]] || git -C "$REPO_DIR" pull --ff-only \
      || die "could not update $REPO_DIR (dirty or diverged checkout?)"
  else
    [[ $CHECK_ONLY -eq 1 ]] && die "no checkout at $REPO_DIR — clone it first, --check changes nothing"
    git clone "$REPO_URL" "$REPO_DIR"
  fi
  POSTFLIGHT_REEXEC=1 exec bash "$REPO_DIR/scripts/setup.sh" "$@"
}

# ---------- step 1: dependencies ----------

step_deps() {
  step "Dependencies"
  local tool missing=()
  local needed=(git curl jq python3)
  [[ $DEV_MODE -eq 0 ]] && needed+=(rsync)
  for tool in "${needed[@]}"; do
    if command -v "$tool" >/dev/null; then ok "$tool"; else missing+=("$tool"); fi
  done
  [[ ${#missing[@]} -eq 0 ]] || halt "install first: ${missing[*]}"
  if gh auth status >/dev/null 2>&1; then
    ok "gh CLI authenticated"
  else
    todo "gh CLI not authenticated — own-repo sourcing won't work (gh auth login)"
  fi
}

# OpenClaw supports Node 22.22+ and 24.15+ (23 is rejected).
node_ok() {
  local v major minor
  v="$(node -v 2>/dev/null)" || return 1
  v="${v#v}"; major="${v%%.*}"; minor="${v#*.}"; minor="${minor%%.*}"
  [[ "$major" =~ ^[0-9]+$ && "$minor" =~ ^[0-9]+$ ]] || return 1
  (( (major == 22 && minor >= 22) || (major == 24 && minor >= 15) || major >= 25 ))
}

step_node() {
  step "Node.js (OpenClaw needs 22.22+ / 24.15+)"
  if node_ok; then ok "node $(node -v)"; return 0; fi
  local candidate
  candidate="$(find "$HOME/.nvm/versions/node" -maxdepth 1 \( -name 'v2[4-9].*' -o -name 'v[3-9][0-9].*' \) 2>/dev/null | sort -V | tail -1 || true)"
  if [[ -n "$candidate" ]]; then
    export PATH="$candidate/bin:$PATH"
    if node_ok; then
      ok "node $(node -v) (via $candidate — add its bin to PATH permanently)"
      return 0
    fi
  fi
  halt "no supported Node found — install one first: nvm install 24"
}

step_openclaw() {
  step "OpenClaw"
  command -v openclaw >/dev/null \
    || { halt "OpenClaw not installed — see https://docs.openclaw.ai, then run: openclaw onboard"; return 0; }
  [[ -d "$WORKSPACE" ]] \
    || { halt "workspace missing at $WORKSPACE — run: openclaw onboard"; return 0; }
  ok "openclaw $(openclaw --version 2>/dev/null | head -1 || echo present)"
}

# ---------- step 2: skill install ----------

skill_dir() {
  if [[ $DEV_MODE -eq 1 ]]; then printf '%s' "$REPO_DIR/skill/postflight";
  else printf '%s' "$WORKSPACE/skills/postflight"; fi
}

symlink_trusted() {
  local cfg tilde=""
  cfg="$(openclaw config get skills.load.allowSymlinkTargets 2>/dev/null || true)"
  # The config may store the path in ~ form; accept both spellings.
  [[ "$REPO_DIR" == "$HOME"* ]] && tilde="~${REPO_DIR#"$HOME"}"
  grep -qF "$REPO_DIR/skill" <<<"$cfg" \
    || { [[ -n "$tilde" ]] && grep -qF "$tilde/skill" <<<"$cfg"; }
}

dev_install_ok() {
  local dest="$1"
  [[ -L "$dest" && "$(readlink "$dest")" == "$REPO_DIR/skill/postflight" ]] && symlink_trusted
}

step_skill() {
  step "Skill install"
  local dest="$WORKSPACE/skills/postflight"
  if [[ $DEV_MODE -eq 1 ]]; then
    if dev_install_ok "$dest"; then ok "skill symlinked and trusted at $dest"; return 0; fi
    if [[ $CHECK_ONLY -eq 1 ]]; then todo "dev install missing, wrong target, or symlink not trusted"; return 0; fi
    bash "$REPO_DIR/scripts/install.sh" --dev --quiet
    if ! symlink_trusted; then
      echo "  Trusting the symlink target in OpenClaw config (skills.load.allowSymlinkTargets)."
      openclaw config set skills.load.allowSymlinkTargets "[\"$REPO_DIR/skill\"]"
    fi
    ok "skill symlinked and trusted at $dest"
    return 0
  fi
  if [[ -f "$dest/SKILL.md" && ! -L "$dest" ]]; then ok "skill installed at $dest"; return 0; fi
  if [[ $CHECK_ONLY -eq 1 ]]; then todo "skill not installed"; return 0; fi
  bash "$REPO_DIR/scripts/install.sh" --quiet
  ok "skill installed at $dest"
}

# ---------- step 3: xurl ----------

# Pinned version + checksum verification: "latest" is a mutable pointer and
# this binary is later handed the X client secret. The checksums file ships
# unsigned in the same release, so this defeats transport tampering; the pin
# is what keeps a future malicious "latest" out.
install_xurl() {
  local os arch tmp asset
  os="$(uname -s)" arch="$(uname -m)"
  [[ "$arch" == "aarch64" ]] && arch="arm64"
  asset="xurl_${os}_${arch}.tar.gz"
  tmp="$(mktemp -d)"
  CLEANUP+=("$tmp")
  local base="https://github.com/xdevplatform/xurl/releases/download/v${XURL_VERSION}"
  curl -fsSL "$base/$asset" -o "$tmp/$asset" \
    || die "no xurl v$XURL_VERSION release for ${os}_${arch} — install manually: https://github.com/xdevplatform/xurl"
  curl -fsSL "$base/xurl_${XURL_VERSION}_checksums.txt" -o "$tmp/checksums.txt" \
    || die "could not fetch xurl checksums for v$XURL_VERSION"
  if command -v shasum >/dev/null; then
    (cd "$tmp" && grep " $asset\$" checksums.txt | shasum -a 256 -c -) >/dev/null \
      || die "xurl checksum mismatch — refusing to install"
  else
    (cd "$tmp" && grep " $asset\$" checksums.txt | sha256sum -c -) >/dev/null \
      || die "xurl checksum mismatch — refusing to install"
  fi
  tar xzf "$tmp/$asset" -C "$tmp" xurl
  chmod +x "$tmp/xurl"
  mkdir -p "$HOME/.local/bin"
  mv "$tmp/xurl" "$HOME/.local/bin/xurl"
  export PATH="$HOME/.local/bin:$PATH"
}

step_xurl() {
  step "xurl (X's official OAuth CLI)"
  if command -v xurl >/dev/null; then ok "xurl present"; return 0; fi
  if [[ $CHECK_ONLY -eq 1 ]]; then todo "xurl not installed"; return 0; fi
  install_xurl
  ok "xurl v$XURL_VERSION installed to ~/.local/bin (make sure that's on your PATH)"
}

# ---------- step 4: model auth ----------

provider_ready() {
  openclaw models status --json 2>/dev/null | jq -e --arg p "$1" '
    ([.auth.providers[]? | select(.provider==$p) | .profiles.count] | add // 0) > 0
    and (.defaultModel | startswith($p + "/"))' >/dev/null
}

# The catalog varies by OpenClaw release (gpt-5.6-sol appears only in newer
# ones), so resolve the default model against what this install actually
# lists — a name the scheduler can't resolve fails every cron run.
openai_pick_model() {
  local listed m
  listed="$(openclaw models list --provider openai 2>/dev/null | awk '{print $1}')"
  for m in "${MODEL_OPENAI_CANDIDATES[@]}"; do
    grep -qxF "$m" <<<"$listed" && { printf '%s' "$m"; return 0; }
  done
  return 1
}

auth_anthropic() {
  echo "  A browser approval on claude.ai will open."
  openclaw models auth setup-token --provider anthropic < "$TTY"
  openclaw config set agents.defaults.model.primary "$MODEL_ANTHROPIC"
  provider_ready anthropic || die "model auth still not detected after setup-token"
  ok "anthropic auth + default model ($MODEL_ANTHROPIC)"
}

auth_openai() {
  local flags=() model
  # A box with no display (typical VPS) can't take the localhost OAuth
  # callback; device-code prints a URL + one-time code to approve from
  # any browser instead.
  [[ "$(uname -s)" == "Linux" && -z "${DISPLAY:-}" ]] && flags+=(--device-code)
  echo "  OAuth against your ChatGPT account will start."
  openclaw models auth login --provider openai ${flags[@]+"${flags[@]}"} < "$TTY"
  model="$(openai_pick_model)" \
    || die "no known Codex-subscription model in 'openclaw models list --provider openai' — update OpenClaw and rerun"
  openclaw config set agents.defaults.model.primary "$model"
  provider_ready openai || die "model auth still not detected after login"
  ok "openai auth + default model ($model)"
  # Released versions have rewritten Codex-subscription model routes to
  # API-billed ones during doctor --fix (openclaw#79461, #87650).
  echo "  Caution: after any 'openclaw doctor --fix', re-check the default model"
  echo "  ('openclaw models status') — it must NOT become plain openai/gpt-5.6,"
  echo "  which is the API-billed alias, not your subscription."
}

step_model() {
  step "Model auth (Claude or ChatGPT/Codex subscription, no API bill)"
  local p
  for p in anthropic openai; do
    if provider_ready "$p"; then ok "$p auth + default model configured"; return 0; fi
  done
  if ! interactive; then todo "model auth not configured (run without --check, in a terminal)"; return 0; fi
  echo "  Which subscription should draft the posts?"
  echo "    1) Claude (Anthropic) — the voice rules were tuned and validated here"
  echo "    2) ChatGPT/Codex (OpenAI) — supported; draft quality not yet validated"
  case "$(ask_default "  Choice" "1")" in
    1) auth_anthropic ;;
    2) auth_openai ;;
    *) die "answer 1 or 2" ;;
  esac
}

# ---------- step 5: X credentials ----------

x_handle() { xurl /2/users/me 2>/dev/null | jq -er '.data.username' 2>/dev/null; }

step_x() {
  step "X API access"
  local handle
  if handle="$(x_handle)"; then ok "posting as @$handle"; return 0; fi
  if ! interactive; then todo "X auth not configured"; return 0; fi
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
  # xurl v1.3.1 offers no file/stdin/env alternative for these flags, so the
  # secret is briefly visible in the process table. Rotate it if this machine
  # is shared.
  xurl auth apps add "$XURL_APP" --client-id "$client_id" --client-secret "$client_secret"
  echo "  A browser consent window will open (grants offline.access for headless refresh)."
  xurl auth oauth2 --app "$XURL_APP" < "$TTY"
  xurl auth default "$XURL_APP"
  handle="$(x_handle)" || die "auth completed but /2/users/me failed — check the app package on console.x.com"
  ok "posting as @$handle"
  echo "  Note: media upload needs the media.write scope. If the first upload"
  echo "  returns 403, re-consent with: xurl auth oauth2 --app $XURL_APP"
}

# ---------- step 5b: media tools (optional) ----------

# Builds posts are media-first (CONTENT.md "Media recipes"). Missing tools
# are never fatal: the skill degrades to text-only posts on its own.
step_media_tools() {
  step "Media tools (optional, for builds-post media)"
  local t any=0
  for t in vhs freeze; do
    if command -v "$t" >/dev/null; then ok "$t present"; any=1; fi
  done
  [[ $any -eq 1 ]] \
    || todo "neither vhs nor freeze installed — builds posts ship text-only until one exists (see CONTENT.md Media recipes)"
  if command -v exiftool >/dev/null; then
    ok "exiftool present (photo-library ingestion)"
  else
    # Informational, not a todo: most installs have no photo pillar.
    echo "  note: exiftool not installed — only needed if you add a photo pillar (scripts/ingest-photo.sh uses it to strip EXIF/GPS)"
  fi
}

# ---------- step 6: telegram ----------

settings_file() { printf '%s/state/settings.json' "$(skill_dir)"; }

telegram_to() { jq -r '.telegramTo // empty' "$(settings_file)" 2>/dev/null || true; }

telegram_channel_installed() {
  openclaw channels list --json 2>/dev/null | jq -e '.chat.telegram.installed == true' >/dev/null
}

write_telegram_to() {
  local file tmp
  file="$(settings_file)"
  [[ -f "$file" ]] || die "settings.json missing at $file — rerun scripts/install.sh"
  tmp="$(mktemp "$file.XXXXXX")"
  CLEANUP+=("$tmp")
  jq --arg id "$1" '.telegramTo = $id' "$file" > "$tmp" || die "could not update $file"
  mv "$tmp" "$file"
}

add_telegram_channel() {
  echo "  Create a bot with @BotFather (/newbot) and copy its token."
  # --token-file keeps the token out of the process table, but OpenClaw
  # stores the PATH and reads it at runtime — the file must persist for as
  # long as the channel exists, so it lives under ~/.openclaw, not /tmp.
  local tokfile="$HOME/.openclaw/credentials/telegram-bot-token"
  mkdir -p "$(dirname "$tokfile")" && chmod 700 "$(dirname "$tokfile")"
  ask_secret "  Bot token (hidden): " > "$tokfile"
  chmod 600 "$tokfile"
  [[ -s "$tokfile" ]] || die "bot token required"
  openclaw channels add --channel telegram --token-file "$tokfile"
  openclaw gateway install
}

owner_allowlisted() {
  openclaw config get commands.ownerAllowFrom 2>/dev/null | grep -qF "telegram:"
}

step_telegram() {
  step "Telegram approvals"
  local to
  to="$(telegram_to)"
  # All three must hold: channel configured, approval target set, AND the
  # owner allowlist present. Migrated installs can have the first two while
  # pairing on this machine never happened.
  if telegram_channel_installed && [[ -n "$to" ]] && owner_allowlisted; then
    ok "telegram channel installed, approvals go to $to"
    return 0
  fi
  if ! interactive; then todo "telegram not fully configured"; return 0; fi
  telegram_channel_installed || add_telegram_channel
  echo "  Now send any message to your bot from your own Telegram account."
  echo "  It replies with your numeric user id and a pairing code."
  local code user_id
  code="$(ask "  Pairing code: ")"
  [[ "$code" =~ ^[A-Za-z0-9_-]+$ ]] || die "pairing code required"
  openclaw pairing approve telegram "$code"
  user_id="$(ask "  Your numeric Telegram user id: ")"
  [[ "$user_id" =~ ^[0-9]+$ ]] || die "user id must be numeric"
  echo "  Setting commands.ownerAllowFrom (replaces any existing allowlist)."
  openclaw config set commands.ownerAllowFrom "[\"telegram:$user_id\"]"
  write_telegram_to "$user_id"
  openclaw gateway restart
  ok "telegram paired; approvals restricted to $user_id"
}

# ---------- step 7: cron ----------

CRON_NAMES=(postflight-own-work postflight-ai-news postflight-aviation postflight-backlog)
EXPR_OWN="" EXPR_NEWS="" EXPR_AVIATION=""

cron_expr_for() {
  case "$1" in
    postflight-own-work) printf '%s' "$EXPR_OWN" ;;
    postflight-ai-news)  printf '%s' "$EXPR_NEWS" ;;
    postflight-aviation) printf '%s' "$EXPR_AVIATION" ;;
    postflight-backlog)  printf '0 8 * * 1' ;;
  esac
}

# The three drafting messages are slot-numbered and pillar-agnostic: which
# pillar a slot gets is the weekly grid in CONTENT.md, so schedule changes
# never require touching cron again.
cron_msg_for() {
  case "$1" in
    postflight-own-work) printf 'Run the postflight skill: draft one post for slot 1 of the pillar schedule (CONTENT.md Pillars) and request approval.' ;;
    postflight-ai-news)  printf 'Run the postflight skill: draft one post for slot 2 of the pillar schedule (CONTENT.md Pillars) and request approval.' ;;
    postflight-aviation) printf 'Run the postflight skill: draft one post for slot 3 of the pillar schedule (CONTENT.md Pillars) and request approval.' ;;
    postflight-backlog)  printf 'postflight maintenance turn: refresh the content backlog per CONTENT.md, all pillar sections, then run the weekly metrics readback per CONTENT.md "Metrics readback". Do not draft or publish.' ;;
  esac
}

# A failed listing must never read as "nothing exists" — that would create
# duplicate jobs on the next line.
cron_missing() {
  local existing status=0 name out=()
  existing="$(openclaw cron list --json 2>/dev/null | jq -r '.jobs[]?.name')" || status=$?
  [[ $status -eq 0 ]] || die "could not read cron jobs (openclaw cron list failed) — refusing to guess"
  for name in "${CRON_NAMES[@]}"; do
    grep -qxF "$name" <<<"$existing" || out+=("$name")
  done
  printf '%s\n' "${out[@]:-}"
}

hhmm_to_expr() { printf '%s %s * * *' "${1#*:}" "${1%%:*}"; }

# One job's JSON object from the listing, or empty. Field names vary across
# OpenClaw releases, so callers probe alternatives and treat "not found" as
# "cannot compare", never as license to guess.
cron_job_json() {
  openclaw cron list --json 2>/dev/null | jq -c --arg n "$1" '.jobs[]? | select(.name==$n)' 2>/dev/null
}

# Field readers for one job object. Kept together so the name-rename and the
# message-drift migrations can never disagree about where a field lives.
cron_field_msg() { jq -r '[.payload.message?, .message?, .msg?, .prompt?] | map(select(type=="string")) | first // empty' <<<"$1"; }
cron_field_expr() { jq -r '[.schedule.expr?, .expr?, .schedule?, .cron?] | map(select(type=="string")) | first // empty' <<<"$1"; }
cron_field_tz() { jq -r '[.schedule.tz?, .tz?, .timezone?] | map(select(type=="string")) | first // empty' <<<"$1"; }

# Supported until 2026-11-01, then this function and its call site come out
# (see the matching note in install.sh).
# Jobs registered before the x-poster -> postflight rename carry the old name,
# and cron_missing keys on the name — without this, a rerun would register a
# second full set and every slot would draft twice. Recreates each job under
# the new name with its schedule and Telegram route intact, then removes the
# old one. Removal comes first on purpose: a half-failed rename that leaves no
# job is loud and recoverable, one that leaves two double-posts for days.
# The doctor heartbeat keeps whatever message it already had; the slot jobs
# take the current canonical message, which also mentions the new skill name.
cron_migrate_names() {
  local name legacy job expr tz to jid want
  to="$(telegram_to)"
  for name in "${CRON_NAMES[@]}" postflight-doctor; do
    legacy="x-poster-${name#postflight-}"
    [[ -z "$(cron_job_json "$name")" ]] || continue
    job="$(cron_job_json "$legacy")"
    [[ -n "$job" ]] || continue
    if ! interactive; then
      todo "cron $legacy still has its pre-rename name — rerun setup.sh (no --check) to migrate"
      continue
    fi
    want="$(cron_msg_for "$name")"
    [[ -n "$want" ]] || want="$(cron_field_msg "$job")"
    expr="$(cron_field_expr "$job")"
    tz="$(cron_field_tz "$job")"
    jid="$(jq -r '.id // empty' <<<"$job")"
    if [[ -z "$expr" || -z "$tz" || -z "$to" || -z "$jid" || -z "$want" ]]; then
      todo "cron $legacy should be renamed to $name but could not be read in full — rename it by hand (openclaw cron rm <id>, then the command in docs/SETUP-MANUAL.md)"
      continue
    fi
    openclaw cron rm "$jid" >/dev/null
    openclaw cron create "$expr" "$want" \
      --name "$name" --session isolated --tz "$tz" \
      --channel telegram --to "$to" >/dev/null \
      || die "removed cron $legacy but could not create $name. Recreate it with:
  openclaw cron create \"$expr\" \"$want\" --name $name --session isolated --tz $tz --channel telegram --to $to"
    ok "cron $legacy renamed to $name ($expr @ $tz)"
  done
}

# Jobs created by pre-pillar versions carry the old slot messages. Creating
# jobs is idempotent by name, so a rerun never updates them — this detects
# the drift and recreates the job in place, preserving its schedule and
# route. Silent when the listing exposes no message field: a migration that
# cannot read the old message must not delete a working job.
cron_migrate_messages() {
  local name job cur want expr tz to jid
  to="$(telegram_to)"
  for name in "${CRON_NAMES[@]}"; do
    job="$(cron_job_json "$name")"
    [[ -n "$job" ]] || continue
    cur="$(cron_field_msg "$job")"
    [[ -n "$cur" ]] || continue
    want="$(cron_msg_for "$name")"
    [[ "$cur" == "$want" ]] && continue
    if ! interactive; then
      todo "cron $name still has an outdated message — rerun setup.sh (no --check) to migrate"
      continue
    fi
    expr="$(cron_field_expr "$job")"
    tz="$(cron_field_tz "$job")"
    jid="$(jq -r '.id // empty' <<<"$job")"
    if [[ -z "$expr" || -z "$tz" || -z "$to" || -z "$jid" ]]; then
      todo "cron $name needs the new pillar-slot message but its schedule could not be read — recreate it by hand (openclaw cron rm, then the command in docs/SETUP-MANUAL.md)"
      continue
    fi
    openclaw cron rm "$jid" >/dev/null
    openclaw cron create "$expr" "$want" \
      --name "$name" --session isolated --tz "$tz" \
      --channel telegram --to "$to" >/dev/null
    ok "cron $name migrated to the current message ($expr @ $tz)"
  done
}

step_cron() {
  step "Cron schedule"
  local missing
  cron_migrate_names
  missing="$(cron_missing)"
  if [[ -z "$missing" ]]; then
    ok "all four jobs registered"
    cron_migrate_messages
    return 0
  fi
  if ! interactive; then
    todo "missing cron jobs: $(tr '\n' ' ' <<<"$missing")"
    cron_migrate_messages
    return 0
  fi
  local to tz t1 t2 t3
  to="$(telegram_to)"
  [[ -n "$to" ]] || die "finish the Telegram step first — cron alerts need a destination"
  tz="$(ask_default "  Timezone" "$(jq -r '.timezone // "America/New_York"' "$(settings_file)" 2>/dev/null || printf 'America/New_York')")"
  echo "  Defaults target US engagement windows (9:30 / 12:30 / 15:00 ET)."
  t1="$(ask_hhmm "  Slot 1 (morning) HH:MM" "09:30")"
  t2="$(ask_hhmm "  Slot 2 (midday) HH:MM" "12:30")"
  t3="$(ask_hhmm "  Slot 3 (afternoon) HH:MM" "15:00")"
  EXPR_OWN="$(hhmm_to_expr "$t1")"
  EXPR_NEWS="$(hhmm_to_expr "$t2")"
  EXPR_AVIATION="$(hhmm_to_expr "$t3")"
  local name
  for name in "${CRON_NAMES[@]}"; do
    grep -qxF "$name" <<<"$missing" || continue
    openclaw cron create "$(cron_expr_for "$name")" "$(cron_msg_for "$name")" \
      --name "$name" --session isolated --tz "$tz" \
      --channel telegram --to "$to" >/dev/null
    ok "cron $name ($(cron_expr_for "$name") @ $tz)"
  done
  cron_migrate_messages
}

# ---------- step 8: pillars ----------

# The pillar overlay is optional: absent means the generic default
# schedule in CONTENT.md. An unedited copy of the template never drives
# drafting — CONTENT.md ignores the file while the TEMPLATE marker line
# is still in it.
step_pillars() {
  step "Content pillars"
  local overlay example
  overlay="$(skill_dir)/pillars.local.md"
  example="$(skill_dir)/pillars.example.md"
  if [[ -f "$overlay" ]]; then
    if grep -q '^<!-- TEMPLATE' "$overlay"; then
      todo "pillars.local.md is still the unedited template — edit it (docs/CUSTOMIZE.md), or delete it to run the default schedule"
    else
      ok "custom pillars configured (pillars.local.md)"
    fi
    return 0
  fi
  if ! interactive; then
    todo "no custom pillars — running the default builds/insights schedule (copy pillars.example.md to pillars.local.md to customize)"
    return 0
  fi
  local yn
  yn="$(ask_default "  Add your own content pillars now? (y/N)" "n")"
  if [[ "$yn" =~ ^[Yy] ]]; then
    cp "$example" "$overlay"
    todo "edit $overlay (see docs/CUSTOMIZE.md), delete its TEMPLATE line, then send /new to your bot"
  else
    ok "using the default pillar schedule (customize later via docs/CUSTOMIZE.md)"
  fi
}

# ---------- step 9: voice ----------

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
  printf '\n\033[1m%s\033[0m\n' "Summary"
  printf '  %s\n' ${RESULTS[@]+"${RESULTS[@]}"}
  cat <<'EOF'

Next: message your bot "postflight: draft a post" and reply ship or skip.
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
step_media_tools
step_telegram
step_cron
step_pillars
step_voice
summary
