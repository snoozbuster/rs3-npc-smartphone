#!/usr/bin/env bash
# Run LuaLS --check over the workspace (EmmyLua / editor diagnostics).
#
# First-time setup:
#   ./scripts/setup-luals.sh

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LUALS="${ROOT}/.tools/lua-language-server/bin/lua-language-server"
LOGPATH="${ROOT}/.tools/luals-check"
CHECKLEVEL="${LUALS_CHECKLEVEL:-Warning}"

if [[ ! -x "$LUALS" ]]; then
  echo "error: lua-language-server not found at ${LUALS}" >&2
  echo "run: ./scripts/setup-luals.sh" >&2
  exit 1
fi

mkdir -p "$LOGPATH"
cd "$ROOT"

# --check uses .luarc.json; pretty report on stdout; nonzero exit on findings.
exec "$LUALS" \
  --check="$ROOT" \
  --checklevel="$CHECKLEVEL" \
  --check_format=pretty \
  --logpath="$LOGPATH" \
  --configpath="${ROOT}/.luarc.json" \
  "$@"
