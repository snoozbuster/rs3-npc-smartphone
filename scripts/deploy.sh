#!/usr/bin/env bash
# Sync this plugin into the RS3 beta client's local dev_plugins folder.
#
# Usage:
#   ./scripts/deploy.sh          # one-shot copy
#   ./scripts/deploy.sh --watch  # re-copy whenever plugin files change (needs inotifywait)
#
# After deploy, in the beta client console (ALT+`):
#   prf
#   pon npc-smartphone    # first time
#   prl npc-smartphone    # after subsequent deploys

set -euo pipefail

PLUGIN_NAME="npc-smartphone"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="${ROOT}/src"
MANIFEST="${ROOT}/plugin.json"
DEST_ROOT="${RS3_DEV_PLUGINS:-/mnt/c/ProgramData/Jagex/RuneScape-BETA/dev_plugins}"
DEST="${DEST_ROOT}/${PLUGIN_NAME}"

sync_once() {
  if [[ ! -d "$SRC" ]]; then
    echo "error: missing plugin source dir: ${SRC}" >&2
    exit 1
  fi
  if [[ ! -f "$MANIFEST" ]]; then
    echo "error: missing plugin manifest: ${MANIFEST}" >&2
    exit 1
  fi

  if [[ ! -d "$DEST_ROOT" ]]; then
    echo "Creating ${DEST_ROOT}"
    mkdir -p "$DEST_ROOT"
  fi

  mkdir -p "$DEST"
  # --delete clears stale files from src/; copy manifest after so it isn't removed.
  rsync -a --delete --exclude '*_spec.lua' "${SRC}/" "${DEST}/"
  rsync -a "$MANIFEST" "${DEST}/plugin.json"

  echo "Deployed ${PLUGIN_NAME} -> ${DEST}"
  echo "Files:"
  find "$DEST" -type f | sed "s|^|  |"
}

watch_loop() {
  if ! command -v inotifywait >/dev/null 2>&1; then
    echo "error: --watch requires inotifywait (install inotify-tools)" >&2
    exit 1
  fi

  sync_once
  echo "Watching ${SRC} and plugin.json for changes (Ctrl+C to stop)..."
  while inotifywait -r -e modify,create,delete,move \
      --exclude '_spec\.lua$' \
      "$SRC" "$MANIFEST" >/dev/null 2>&1; do
    sync_once
  done
}

case "${1:-}" in
  "" ) sync_once ;;
  --watch | -w ) watch_loop ;;
  -h | --help )
    sed -n '2,14p' "$0"
    ;;
  * )
    echo "unknown option: $1 (try --help)" >&2
    exit 1
    ;;
esac
