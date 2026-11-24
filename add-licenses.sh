#!/bin/bash
# Copies the license texts of everything in the engine into share/doc/<component>/
# (Wine's LGPL and the GNU licenses require shipping them). Called by build.sh.
#
#   engine/add-licenses.sh <engine dir>
set -euo pipefail

ENGINE="${1:?usage: add-licenses.sh <engine dir>}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK="${DECANTER_ENGINE_WORK:-$HOME/.cache/decanter-engine}"
SRC="$WORK/src/sources"
die() { printf 'add-licenses.sh: %s\n' "$*" >&2; exit 1; }
[ -x "$ENGINE/bin/wine" ] || die "$ENGINE is not an engine"

DOC="$ENGINE/share/doc"
copy() {  # copy <component> <files...>
  local c="$1"; shift
  mkdir -p "$DOC/$c"
  for f in "$@"; do [ -f "$f" ] || die "missing $f"; cp "$f" "$DOC/$c/"; done
}
copy wine     "$SRC/wine/COPYING.LIB" "$SRC/wine/LICENSE" "$SRC/wine/AUTHORS"
copy gnutls   "$SRC/gnutls/gnutls/LICENSE"
copy gmp      "$SRC/gnutls/gmp/COPYING" "$SRC/gnutls/gmp/COPYING.LESSERv3" "$SRC/gnutls/gmp/COPYINGv2" "$SRC/gnutls/gmp/COPYINGv3"
copy nettle   "$WORK/extra/nettle-3.10/COPYING.LESSERv3" "$WORK/extra/nettle-3.10/COPYINGv2" "$WORK/extra/nettle-3.10/COPYINGv3"
copy freetype "$SRC/freetype/LICENSE.TXT" "$SRC/freetype/docs/FTL.TXT" "$SRC/freetype/docs/GPLv2.TXT"
copy sdl2     "$(ls -d "$WORK"/extra/SDL2-*/ | tail -1)LICENSE.txt"   # the SDL build-deps.sh built
mkdir -p "$DOC/wine-mono"
printf 'Wine Mono %s: https://gitlab.winehq.org/mono/wine-mono (mostly MIT; see its COPYING and the licenses of its components).\n' \
  "$(ls "$ENGINE/share/wine/mono" 2>/dev/null | sed 's/wine-mono-//' | head -1)" > "$DOC/wine-mono/SOURCE.txt"
cp "$HERE/LICENSES.md" "$DOC/LICENSES.md" 2>/dev/null || true
echo "License texts added to $DOC"
