#!/bin/bash
# Adds Wine Mono (WineHQ's open-source .NET runtime for Wine) to an engine, as a shared
# install in share/wine/mono. Bottles use it from there: nothing is installed into each
# bottle, and Wine no longer asks to download it when a bottle starts or is updated.
#
#   engine/add-mono.sh <engine dir>
#
# Called by build.sh; safe to re-run. The version must match the one this Wine expects
# (MONO_VERSION in dlls/appwiz.cpl/addons.c), and the download's SHA-256 is pinned.
set -euo pipefail

MONO_VERSION=10.4.1
MONO_SHA256=a16606ef0724202e6a6848ece6e0cbba64d11e2f11aefe744af1d93c6d9f99bb
MONO_URL="https://dl.winehq.org/wine/wine-mono/$MONO_VERSION/wine-mono-$MONO_VERSION-x86.tar.xz"

ENGINE="${1:?usage: add-mono.sh <engine dir>}"
WORK="${DECANTER_ENGINE_WORK:-$HOME/.cache/decanter-engine}"
TARBALL="$WORK/extra/wine-mono-$MONO_VERSION-x86.tar.xz"
die() { printf 'add-mono.sh: %s\n' "$*" >&2; exit 1; }
[ -x "$ENGINE/bin/wine" ] || die "$ENGINE is not an engine (no bin/wine)"

# Wine only uses the Mono version it was built for.
ADDONS="$WORK/src/sources/wine/dlls/appwiz.cpl/addons.c"
if [ -f "$ADDONS" ]; then
  want="$(sed -n 's/^#define MONO_VERSION "\(.*\)"/\1/p' "$ADDONS")"
  [ "$want" = "$MONO_VERSION" ] || die "this Wine wants Mono $want; update MONO_VERSION and MONO_SHA256 here"
fi

DEST="$ENGINE/share/wine/mono/wine-mono-$MONO_VERSION"
if [ -d "$DEST" ]; then echo "Wine Mono $MONO_VERSION already in $ENGINE"; exit 0; fi

mkdir -p "$WORK/extra"
if [ ! -f "$TARBALL" ]; then
  echo "Downloading Wine Mono $MONO_VERSION from WineHQ"
  curl -fL --progress-bar -o "$TARBALL.part" "$MONO_URL" && mv "$TARBALL.part" "$TARBALL"
fi
echo "$MONO_SHA256  $TARBALL" | shasum -a 256 -c - >/dev/null || die "checksum mismatch for $TARBALL"

mkdir -p "$ENGINE/share/wine/mono"
tmp="$(mktemp -d "$ENGINE/share/wine/mono/.extract.XXXXXX")"
tar -xJf "$TARBALL" -C "$tmp"
[ -d "$tmp/wine-mono-$MONO_VERSION" ] || { rm -rf "$tmp"; die "unexpected layout in $TARBALL"; }
mv "$tmp/wine-mono-$MONO_VERSION" "$DEST"
rmdir "$tmp"
echo "Wine Mono $MONO_VERSION added to $ENGINE ($(du -sh "$DEST" | cut -f1))"
