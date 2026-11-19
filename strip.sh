#!/bin/bash
# Removes debug data from an engine's Windows files (about 85% of their size).
# Players never need it; it only helps developers read crash traces.
#
#   engine/strip.sh <engine dir>
#
# Only debug sections are removed (--strip-debug), so exported names and everything
# Wine loads stay as they are. Apple's D3DMetal shims (the names add-d3dmetal.sh
# installs) are left exactly as Apple ships them. Each file is stripped into a temp
# file first and only replaced when that succeeds. Called by build.sh; safe to re-run.
set -euo pipefail

ENGINE="${1:?usage: strip.sh <engine dir>}"
ARM_BREW=/opt/homebrew
[ -x "$ENGINE/bin/wine" ] || { echo "strip.sh: $ENGINE is not an engine" >&2; exit 1; }

strip_dir() {  # strip_dir <dir> <mingw strip tool>
  local dir="$1" tool="$2"
  [ -d "$dir" ] || return 0
  [ -x "$tool" ] || { echo "strip.sh: missing $tool (brew install mingw-w64)" >&2; exit 1; }
  find "$dir" -type f ! -name '*.a' \
    ! -name atidxx64.dll ! -name d3d10.dll ! -name d3d11.dll ! -name d3d12.dll \
    ! -name dxgi.dll ! -name nvapi64.dll ! -name nvngx-on-metalfx.dll -print0 | TOOL="$tool" xargs -0 -n 50 -P "$(sysctl -n hw.ncpu)" bash -c '
    for f in "$@"; do
      tmp="$f.strip.$$"
      if "$TOOL" --strip-debug -o "$tmp" "$f" 2>/dev/null && [ -s "$tmp" ]; then
        chmod "$(stat -f %Lp "$f")" "$tmp"
        mv -f "$tmp" "$f"
      else
        rm -f "$tmp"                        # not a PE file (data, fonts): keep as is
      fi
    done' _
}

before="$(du -sh "$ENGINE" | cut -f1)"
strip_dir "$ENGINE/lib/wine/x86_64-windows" "$ARM_BREW/bin/x86_64-w64-mingw32-strip"
strip_dir "$ENGINE/lib/wine/i386-windows"   "$ARM_BREW/bin/i686-w64-mingw32-strip"
echo "Stripped $ENGINE: $before -> $(du -sh "$ENGINE" | cut -f1)"
