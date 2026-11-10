#!/usr/bin/env bash
# Download a project-local selene binary into .tools/ (no sudo).

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TOOLS="${ROOT}/.tools"
VERSION="${SELENE_VERSION:-0.32.0}"
ARCHIVE="selene-${VERSION}-linux.zip"
URL="https://github.com/Kampfkarren/selene/releases/download/${VERSION}/${ARCHIVE}"

mkdir -p "$TOOLS"

if [[ -x "${TOOLS}/selene" ]]; then
  current="$("${TOOLS}/selene" --version 2>/dev/null || true)"
  if [[ "$current" == "selene ${VERSION}" ]]; then
    echo "selene ${VERSION} already installed at ${TOOLS}/selene"
    exit 0
  fi
fi

echo "Downloading selene ${VERSION}..."
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
curl -fsSL -o "${tmp}/${ARCHIVE}" "$URL"
unzip -o "${tmp}/${ARCHIVE}" -d "$TOOLS"
chmod +x "${TOOLS}/selene"

echo
echo "Done. Lint with:"
echo "  ./scripts/lint.sh"
"${TOOLS}/selene" --version
