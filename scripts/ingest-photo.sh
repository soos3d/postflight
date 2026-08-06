#!/usr/bin/env bash
# Thin wrapper: the real script ships inside the skill folder so installed
# copies (which have no scripts/ dir) can run it as {baseDir}/ingest-photo.sh.
exec "$(cd "$(dirname "$0")/.." && pwd)/skill/x-poster/ingest-photo.sh" "$@"
