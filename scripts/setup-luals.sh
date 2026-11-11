#!/usr/bin/env bash
# Download a project-local lua-language-server into .tools/ (no sudo).

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TOOLS="${ROOT}/.tools"
VERSION="${LUALS_VERSION:-3.19.2}"
ARCHIVE="lua-language-server-${VERSION}-linux-x64.tar.gz"
URL="https://github.com/LuaLS/lua-language-server/releases/download/${VERSION}/${ARCHIVE}"
DEST="${TOOLS}/lua-language-server"
BIN="${DEST}/bin/lua-language-server"
MARKER="${DEST}/.version"

mkdir -p "$TOOLS"

if [[ -x "$BIN" && -f "$MARKER" ]] && [[ "$(cat "$MARKER")" == "$VERSION" ]]; then
  echo "lua-language-server ${VERSION} already installed at ${BIN}"
  exit 0
fi

echo "Downloading lua-language-server ${VERSION}..."
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
curl -fsSL -o "${tmp}/${ARCHIVE}" "$URL"
rm -rf "$DEST"
mkdir -p "$DEST"
tar -xzf "${tmp}/${ARCHIVE}" -C "$DEST"
printf '%s\n' "$VERSION" >"$MARKER"
chmod +x "$BIN"

echo
echo "Done. Typecheck with:"
echo "  ./scripts/typecheck.sh"
"$BIN" --version
