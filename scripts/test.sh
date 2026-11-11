#!/usr/bin/env bash
# Run unit tests + LuaLS typecheck.
#
# First-time setup:
#   ./scripts/setup-busted.sh
#   ./scripts/setup-luals.sh

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LUAENV="${ROOT}/.luaenv"
BUSTED="${LUAENV}/bin/busted"

if [[ ! -x "$BUSTED" ]]; then
  echo "error: busted not found at ${BUSTED}" >&2
  echo "run: ./scripts/setup-busted.sh" >&2
  exit 1
fi

export PATH="${LUAENV}/bin:${PATH}"
cd "$ROOT"

echo "==> unit tests"
# busted defaults ROOT to ./spec; search src/ for colocated *_spec.lua files.
if [[ $# -eq 0 ]]; then
  "$BUSTED" src
else
  "$BUSTED" "$@"
fi

echo
echo "==> typecheck"
exec "${ROOT}/scripts/typecheck.sh"
