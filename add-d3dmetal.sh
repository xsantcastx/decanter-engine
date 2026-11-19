#!/bin/bash
# Adds Apple's D3DMetal (DirectX 11/12 -> Metal) to a Decanter engine, from a copy the
# user already has. D3DMetal is Apple's and is never shipped with Decanter.
#
#   engine/add-d3dmetal.sh <engine dir> <source>
#
# <source> is either Apple's Game Porting Toolkit "redist" folder (mounted from the DMG
# you downloaded from developer.apple.com), or another engine folder that already has
# D3DMetal installed (lib/external + the shim DLLs), e.g. for local testing.
#
# Layout it produces (relative symlinks matter: D3DMetal finds itself via @loader_path):
#   lib/external/D3DMetal.framework, lib/external/libd3dshared.dylib   (copied)
#   lib/wine/x86_64-unix/<name>.so -> ../../external/libd3dshared.dylib
#   lib/wine/x86_64-windows/<name>.dll                                   (Apple's PE shims)
set -euo pipefail

ENGINE="${1:?usage: add-d3dmetal.sh <engine dir> <GPTK redist folder or engine with D3DMetal>}"
SRC="${2:?usage: add-d3dmetal.sh <engine dir> <GPTK redist folder or engine with D3DMetal>}"
NAMES=(atidxx64 d3d10 d3d11 d3d12 dxgi nvapi64 nvngx-on-metalfx)

die() { printf 'add-d3dmetal.sh: %s\n' "$*" >&2; exit 1; }
[ -x "$ENGINE/bin/wine" ] || die "$ENGINE is not an engine (no bin/wine)"

# Apple's redist folder has lib/external and lib/wine; so does an engine.
EXT="$SRC/lib/external"
WIN="$SRC/lib/wine/x86_64-windows"
[ -f "$EXT/libd3dshared.dylib" ] && [ -d "$EXT/D3DMetal.framework" ] || die "no D3DMetal in $SRC (expected lib/external/D3DMetal.framework)"

# Only accept Apple-signed D3DMetal.
# (Captured first: with pipefail, `grep -q` closing the pipe early would fail the check.)
sig="$(codesign -dv --verbose=2 "$EXT/D3DMetal.framework" 2>&1 || true)"
codesign --verify "$EXT/D3DMetal.framework" 2>/dev/null && [[ "$sig" == *"Authority=Apple Root CA"* ]] \
  || die "D3DMetal.framework in $SRC is not signed by Apple"

mkdir -p "$ENGINE/lib/external"
rm -rf "$ENGINE/lib/external/D3DMetal.framework" "$ENGINE/lib/external/libd3dshared.dylib"
cp -cR "$EXT/D3DMetal.framework" "$ENGINE/lib/external/"
cp -c "$EXT/libd3dshared.dylib" "$ENGINE/lib/external/"

for n in "${NAMES[@]}"; do
  if [ -f "$WIN/$n.dll" ]; then
    dst="$ENGINE/lib/wine/x86_64-windows/$n.dll"
    # Keep Wine's own DLL beside Apple's shim as <name>.dll.wine (D3DMetal falls back to it).
    if [ -f "$dst" ] && [ ! -f "$dst.wine" ] && ! cmp -s "$WIN/$n.dll" "$dst"; then
      mv "$dst" "$dst.wine"
    fi
    cp -c "$WIN/$n.dll" "$dst"
    ln -sfn ../../external/libd3dshared.dylib "$ENGINE/lib/wine/x86_64-unix/$n.so"
  fi
done

# Mark the engine as having D3DMetal.
if [ -f "$ENGINE/decanter-engine.json" ]; then
  /usr/bin/sed -i '' 's/"d3dmetal": false/"d3dmetal": true/' "$ENGINE/decanter-engine.json"
fi
echo "D3DMetal added to $ENGINE"
ls -l "$ENGINE/lib/wine/x86_64-unix" | grep -- '->' || true
