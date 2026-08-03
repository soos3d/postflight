#!/usr/bin/env bash
# Moves the credentials and skill state that cannot be recreated by setup.sh
# from one machine to another (laptop -> VPS). Everything else on the target
# comes from a fresh `git clone` + `scripts/setup.sh`.
#
#   migrate-state.sh export [outfile.tar.gz]   # on the old machine
#   migrate-state.sh import <tarball>          # on the new machine
#
# The tarball contains live credentials (~/.xurl OAuth tokens, the OpenClaw
# model-auth store). Transfer it with scp and delete it on BOTH ends after a
# verified import. Stop the OpenClaw gateway before exporting so the sqlite
# auth store is not copied mid-write.
set -euo pipefail

WORKSPACE="${OPENCLAW_WORKSPACE:-$HOME/.openclaw/workspace}"

say() { printf '%s\n' "$1"; }
die() { printf 'error: %s\n' "$1" >&2; exit 1; }

auth_store_path() {
  openclaw models status --json 2>/dev/null | jq -r '.auth.storePath // empty'
}

resolved_skill_dir() {
  local dest="$WORKSPACE/skills/x-poster"
  if [[ -L "$dest" ]]; then readlink "$dest"; else printf '%s' "$dest"; fi
}

copy_sqlite() { # src, destdir — includes -wal/-shm journal siblings
  local src="$1" destdir="$2" sibling
  cp "$src" "$destdir/"
  for sibling in "$src-wal" "$src-shm"; do
    [[ -f "$sibling" ]] && cp "$sibling" "$destdir/"
  done
  return 0
}

do_export() {
  local out="${1:-$HOME/x-poster-state-$(date +%Y%m%d-%H%M).tar.gz}"
  [[ -e "$out" ]] && die "$out already exists"
  command -v openclaw >/dev/null || die "openclaw not on PATH (need it to locate the auth store)"

  staging="$(mktemp -d)"
  trap 'rm -rf "${staging:-}"' EXIT

  [[ -d "$HOME/.xurl" ]] || die "\$HOME/.xurl not found — nothing to migrate without X auth"
  cp -R "$HOME/.xurl" "$staging/xurl"

  local store rel
  store="$(auth_store_path)"
  [[ -n "$store" && -f "$store" ]] || die "could not locate the OpenClaw model-auth store"
  [[ "$store" == "$HOME"/* ]] || die "auth store outside \$HOME ($store) — migrate it manually"
  rel="${store#"$HOME"/}"
  mkdir -p "$staging/model-auth"
  copy_sqlite "$store" "$staging/model-auth"
  printf 'authStoreRel=%s\n' "$rel" > "$staging/MANIFEST"

  local skill
  skill="$(resolved_skill_dir)"
  [[ -d "$skill/state" ]] || die "skill state not found at $skill/state"
  cp -R "$skill/state" "$staging/skill-state"
  [[ -f "$skill/voice-examples.local.md" ]] && cp "$skill/voice-examples.local.md" "$staging/"

  umask 077
  tar czf "$out" -C "$staging" .
  say "Exported to $out (mode 0600). Contents:"
  tar tzf "$out" | sed 's/^/  /'
  say ""
  say "This file contains live credentials. Next:"
  say "  scp $out user@server:"
  say "  (on the server) ./scripts/migrate-state.sh import ~/$(basename "$out")"
  say "  then delete the tarball on both machines."
}

place_dir() { # src, dest — backs up an existing dest rather than merging
  local src="$1" dest="$2"
  if [[ -e "$dest" ]]; then
    mv "$dest" "$dest.pre-import.bak"
    say "existing $dest moved to $dest.pre-import.bak"
  fi
  mkdir -p "$(dirname "$dest")"
  cp -R "$src" "$dest"
}

do_import() {
  local tarball="${1:-}"
  [[ -n "$tarball" && -f "$tarball" ]] || die "usage: migrate-state.sh import <tarball>"

  staging="$(mktemp -d)"
  trap 'rm -rf "${staging:-}"' EXIT
  tar xzf "$tarball" -C "$staging"
  [[ -f "$staging/MANIFEST" ]] || die "not a migrate-state tarball (MANIFEST missing)"

  place_dir "$staging/xurl" "$HOME/.xurl"
  chmod 700 "$HOME/.xurl"
  find "$HOME/.xurl" -type f -exec chmod 600 {} +

  local rel store
  rel="$(sed -n 's/^authStoreRel=//p' "$staging/MANIFEST")"
  [[ -n "$rel" ]] || die "MANIFEST has no authStoreRel"
  store="$HOME/$rel"
  mkdir -p "$(dirname "$store")"
  if [[ -f "$store" ]]; then
    mv "$store" "$store.pre-import.bak"
    say "existing auth store moved to $store.pre-import.bak"
  fi
  cp "$staging/model-auth/$(basename "$store")" "$store"
  local sibling
  for sibling in "$(basename "$store")-wal" "$(basename "$store")-shm"; do
    [[ -f "$staging/model-auth/$sibling" ]] && cp "$staging/model-auth/$sibling" "$(dirname "$store")/"
  done

  local skill="$WORKSPACE/skills/x-poster"
  [[ -d "$skill" ]] || die "skill not installed at $skill — run scripts/setup.sh first, then re-import"
  place_dir "$staging/skill-state" "$skill/state"
  [[ -f "$staging/voice-examples.local.md" ]] && cp "$staging/voice-examples.local.md" "$skill/"

  say "Imported. Verify before going live:"
  say "  xurl /2/users/me                      # X auth followed the move"
  say "  openclaw models status                # anthropic profile present"
  say "  then continue with docs/DEPLOY-VPS.md"
}

case "${1:-}" in
  export) shift; do_export "$@" ;;
  import) shift; do_import "$@" ;;
  *) die "usage: migrate-state.sh export [outfile.tar.gz] | import <tarball>" ;;
esac
