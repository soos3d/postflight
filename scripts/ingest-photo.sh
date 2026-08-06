#!/usr/bin/env bash
# Thin wrapper: the real script ships inside the skill folder so installed
# copies (which have no scripts/ dir) can run it as {baseDir}/ingest-photo.sh.
set -euo pipefail
exec "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/skill/x-poster/ingest-photo.sh" "$@"
