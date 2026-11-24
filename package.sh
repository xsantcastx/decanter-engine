#!/bin/bash
# Packages a built engine for download: <id>.tar.xz plus engines.json, the feed Decanter
# reads on first launch (id, Wine version, URL, SHA-256, sizes).
#
#   engine/package.sh <engine dir> <out dir> <base URL>
#
# <engine dir> must be straight from build.sh: Apple's D3DMetal is never redistributed, so
# the script refuses an engine that has anything in lib/external or Apple's shim DLLs.
set -euo pipefail

ENGINE="${1:?usage: package.sh <engine dir> <out dir> <base URL>}"
OUT="${2:?usage: package.sh <engine dir> <out dir> <base URL>}"
BASE="${3:?usage: package.sh <engine dir> <out dir> <base URL>}"
die() { printf 'package.sh: %s\n' "$*" >&2; exit 1; }

[ -x "$ENGINE/bin/wine" ] && [ -f "$ENGINE/decanter-engine.json" ] || die "$ENGINE is not an engine built by build.sh"
ID="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["id"])' "$ENGINE/decanter-engine.json")"
WINEV="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["wine"])' "$ENGINE/decanter-engine.json")"

# Nothing of Apple's may ship.
[ -z "$(ls -A "$ENGINE/lib/external" 2>/dev/null)" ] || die "lib/external is not empty (D3DMetal must not be packaged)"
for n in atidxx64 nvapi64 nvngx-on-metalfx; do
  [ ! -e "$ENGINE/lib/wine/x86_64-windows/$n.dll" ] || die "$n.dll is Apple's D3DMetal shim; package an engine without D3DMetal"
done
ls "$ENGINE"/lib/wine/x86_64-windows/*.dll.wine >/dev/null 2>&1 && die "found <name>.dll.wine: D3DMetal was added to this engine"
find "$ENGINE" -type l -lname '*external*' | grep -q . && die "found links into lib/external: D3DMetal was added to this engine"

# Nothing personal may ship: compilers record build paths, so release builds use a work
# folder outside the home folder (e.g. DECANTER_ENGINE_WORK=/Users/Shared/decanter-engine).
if grep -rqaF "$HOME/" "$ENGINE" 2>/dev/null; then
  die "the engine contains paths under $HOME; rebuild with DECANTER_ENGINE_WORK outside your home folder"
fi

mkdir -p "$OUT"
ARCHIVE="$OUT/$ID.tar.xz"
echo "Packaging $ID (this compresses ~750 MB; a few minutes)"
# The archive holds one top-level folder named after the engine id.
tar -C "$(dirname "$ENGINE")" -cf - -s "|^$(basename "$ENGINE")|$ID|" "$(basename "$ENGINE")" \
  | xz -T0 -6 > "$ARCHIVE.part"
mv "$ARCHIVE.part" "$ARCHIVE"

SHA="$(shasum -a 256 "$ARCHIVE" | cut -d' ' -f1)"
SIZE="$(stat -f %z "$ARCHIVE")"
UNPACKED="$(du -sk "$ENGINE" | cut -f1)"
python3 - "$OUT/engines.json" "$ID" "$WINEV" "${BASE%/}/$ID.tar.xz" "$SHA" "$SIZE" "$((UNPACKED * 1024))" <<'PY'
import json, sys, time
path, id_, wine, url, sha, size, unpacked = sys.argv[1:]
feed = {"schema": 1, "issued": int(time.time()), "engines": [{"id": id_, "wine": wine, "url": url, "sha256": sha,
                                   "size": int(size), "unpacked_size": int(unpacked), "min_macos": "14.0"}]}
open(path, "w").write(json.dumps(feed, indent=2) + "\n")
PY
# Signed with the release key: Decanter ignores an unsigned engine list. Publish both files.
# The signing script lives in Decanter's app repository; a build from this folder alone
# gets an unsigned list, fine for a local test feed (DECANTER_ENGINE_FEED on this Mac).
SIGNER="$(dirname "$0")/../scripts/feed-sign.swift"
if [ -f "$SIGNER" ]; then
  swift "$SIGNER" sign "$OUT/engines.json"
  echo "Wrote $ARCHIVE ($((SIZE / 1048576)) MB), $OUT/engines.json and engines.json.sig"
else
  echo "Wrote $ARCHIVE ($((SIZE / 1048576)) MB) and $OUT/engines.json (unsigned: no feed-sign.swift beside this folder)"
fi
