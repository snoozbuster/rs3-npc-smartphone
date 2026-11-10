#!/usr/bin/env bash
# Bootstrap a project-local Lua 5.4.8 + LuaRocks + busted toolchain.
# Uses micromamba/conda-forge so no system packages or sudo are required.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LUAENV="${ROOT}/.luaenv"
MAMBA_ROOT="${ROOT}/.mamba"
MICROMAMBA="${MAMBA_ROOT}/bin/micromamba"
RT_DIR="${LUAENV}/x86_64-conda-linux-gnu/sysroot/usr"

mkdir -p "${MAMBA_ROOT}/bin"

if [[ ! -x "$MICROMAMBA" ]]; then
  echo "Downloading micromamba..."
  curl -fsSL https://micro.mamba.pm/api/micromamba/linux-64/latest -o /tmp/micromamba.tar.bz2
  python3 -c "import tarfile; tarfile.open('/tmp/micromamba.tar.bz2','r:bz2').extract('bin/micromamba', '${MAMBA_ROOT}')"
fi

export MAMBA_ROOT_PREFIX="$MAMBA_ROOT"

echo "Creating Lua 5.4.8 + LuaRocks env at ${LUAENV}..."
"$MICROMAMBA" create -y -p "$LUAENV" -c conda-forge \
  'lua=5.4.8' \
  'luarocks=3.9.2=lua54*' \
  compilers \
  make

export PATH="${LUAENV}/bin:${PATH}"

echo "Installing busted..."
luarocks install busted --tree "$LUAENV" \
  RT_DIR="$RT_DIR" \
  RT_LIBDIR="${RT_DIR}/lib64"

echo
echo "Done. Run tests with:"
echo "  ./scripts/test.sh"
