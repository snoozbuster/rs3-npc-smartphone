#!/usr/bin/env bash
# Run selene over the project (src/ by default).

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SELENE="${ROOT}/.tools/selene"

if [[ ! -x "$SELENE" ]]; then
  echo "error: selene not found at ${SELENE}" >&2
  echo "run: ./scripts/setup-selene.sh" >&2
  exit 1
fi

cd "$ROOT"

if [[ $# -eq 0 ]]; then
  set -- src
fi

exec "$SELENE" "$@"
