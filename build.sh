#!/bin/bash
# Builds the Decanter game engine: Wine 11 from CodeWeavers' published CrossOver
# source (LGPL/GPL), as an x86_64 build that runs on Apple silicon through Rosetta 2.
#
#   engine/build.sh            download (if needed), verify, configure, build, install
#   engine/build.sh --clean    start over from a fresh configure
#
# Output: ~/.cache/decanter-engine/dist/<ENGINE_ID>/ (bin, lib, share), imported by Decanter's Setup.
# Apple's D3DMetal is NOT part of this build (it can't be redistributed); it is added
# afterwards from the user's own copy of the Game Porting Toolkit: engine/add-d3dmetal.sh.
#
# Needs: Xcode 26+ and Homebrew (arm64) with bison flex pkgconf mingw-w64 autoconf
# automake libtool. The x86_64 libraries the engine links (gmp, nettle, gnutls, freetype)
# are built from the copies in the CrossOver package by engine/build-deps.sh.
set -euo pipefail

CX_VERSION="26.3.0"
CX_SHA256="ac99c8ca4b3848f3e81784135f023df266b61c2345726ea55a50b3e030dd6872"
CX_URL="https://media.codeweavers.com/pub/crossover/source/crossover-sources-${CX_VERSION}.tar.gz"
ENGINE_ID="wine-11.0-cx${CX_VERSION}"

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Autotools can't cope with spaces in paths (".../1. Projects/..."), so the work area
# (sources, objects, output) lives in a space-free folder outside the repo.
WORK="${DECANTER_ENGINE_WORK:-$HOME/.cache/decanter-engine}"
case "$WORK" in *" "*) printf 'set DECANTER_ENGINE_WORK to a folder without spaces\n' >&2; exit 1;; esac
TARBALL="$WORK/crossover-sources-${CX_VERSION}.tar.gz"
SRC="$WORK/src/sources/wine"
BUILD="$WORK/build-$ENGINE_ID"
OUT="$WORK/dist/$ENGINE_ID"
ARM_BREW=/opt/homebrew
X86_BREW="$WORK/deps"   # x86_64 libraries built by build-deps.sh
JOBS="$(sysctl -n hw.ncpu)"

say() { printf '\n== %s\n' "$*"; }
die() { printf 'engine/build.sh: %s\n' "$*" >&2; exit 1; }

[ "${1:-}" = "--clean" ] && rm -rf "$BUILD" "$OUT"

# --- tools ------------------------------------------------------------------------
say "Checking tools"
xcode-select -p | grep -q Xcode.app || die "select Xcode: sudo xcode-select -s /Applications/Xcode.app"
arch -x86_64 /usr/bin/true 2>/dev/null || die "Rosetta 2 is not installed (softwareupdate --install-rosetta)"
for t in bison flex pkgconf; do
  [ -x "$ARM_BREW/opt/$t/bin/$t" ] || die "missing $t: brew install $t"
done
command -v "$ARM_BREW/bin/x86_64-w64-mingw32-gcc" >/dev/null || die "missing mingw-w64: brew install mingw-w64"
command -v "$ARM_BREW/bin/i686-w64-mingw32-gcc" >/dev/null || die "missing mingw-w64 (i686): brew install mingw-w64"

# --- source -----------------------------------------------------------------------
mkdir -p "$WORK/src"
if [ ! -f "$TARBALL" ]; then
  say "Downloading CrossOver $CX_VERSION source"
  curl -fL --progress-bar -o "$TARBALL.part" "$CX_URL" && mv "$TARBALL.part" "$TARBALL"
fi
say "Verifying source checksum"
echo "$CX_SHA256  $TARBALL" | shasum -a 256 -c - >/dev/null || die "checksum mismatch for $TARBALL"
if [ ! -f "$SRC/configure" ] || [ ! -d "$WORK/src/sources/gnutls" ] || [ ! -d "$WORK/src/sources/freetype" ]; then
  say "Extracting Wine and library sources"
  tar -xzf "$TARBALL" -C "$WORK/src" sources/wine sources/gnutls sources/freetype
fi

# --- Decanter's patches -------------------------------------------------------------
# Our own changes to Wine (engine/patches/*.patch, applied in order). Each is skipped when
# it is already in the source, so re-running the build is safe.
for p in "$HERE"/patches/*.patch; do
  [ -f "$p" ] || continue
  if patch -d "$SRC" -p1 -R -s -f --dry-run < "$p" >/dev/null 2>&1; then
    echo "patch $(basename "$p"): already applied"
  else
    patch -d "$SRC" -p1 -s -N < "$p" || die "patch $(basename "$p") does not apply"
    echo "patch $(basename "$p"): applied"
  fi
done

# --- x86_64 libraries ----------------------------------------------------------------
"$HERE/build-deps.sh"

# --- configure ---------------------------------------------------------------------
# Everything runs under Rosetta as x86_64. Build tools (bison, flex, pkg-config, mingw)
# are native arm64 binaries; only the libraries we link must be x86_64.
export PATH="$ARM_BREW/opt/bison/bin:$ARM_BREW/opt/flex/bin:$ARM_BREW/bin:/usr/bin:/bin:/usr/sbin:/sbin"
export MACOSX_DEPLOYMENT_TARGET=14.0
export CC="clang -arch x86_64"
export CXX="clang++ -arch x86_64"
export PKG_CONFIG="$ARM_BREW/opt/pkgconf/bin/pkg-config"
export PKG_CONFIG_LIBDIR="$X86_BREW/lib/pkgconfig:$X86_BREW/share/pkgconfig"
export CPPFLAGS="-I$X86_BREW/include"
export LDFLAGS="-L$X86_BREW/lib -Wl,-headerpad_max_install_names"
export CROSSCC=x86_64-w64-mingw32-gcc

mkdir -p "$BUILD"
cd "$BUILD"
if [ ! -f Makefile ]; then
  say "Configuring ($ENGINE_ID)"
  # OpenGL is left to auto-detect: Wine 11 wants EGL for it, which macOS lacks, and the
  # games we target draw through D3DMetal instead.
  arch -x86_64 "$SRC/configure" \
    --prefix="$OUT" \
    --enable-archs=i386,x86_64 \
    --disable-tests \
    --with-mingw \
    --with-coreaudio \
    --with-freetype \
    --with-gnutls \
    --without-alsa --without-capi --without-cups --without-dbus --without-fontconfig \
    --without-gettext --without-gphoto --without-gssapi --without-gstreamer \
    --without-krb5 --without-netapi --without-oss --without-pcap --without-pcsclite \
    --without-pulse --without-sane --without-sdl --without-udev --without-usb \
    --without-v4l2 --without-vulkan --without-wayland --without-x \
    > "$WORK/configure-$ENGINE_ID.log" 2>&1 \
    || { tail -30 "$WORK/configure-$ENGINE_ID.log"; die "configure failed (log: $WORK/configure-$ENGINE_ID.log)"; }
  grep -E "^configure: (WARNING|error)" "$WORK/configure-$ENGINE_ID.log" || true
fi

# CrossOver's win32u (CW HACK 25909) always names SONAME_LIBVULKAN, which configure only
# defines when it finds MoltenVK. We don't bundle MoltenVK yet (D3DMetal doesn't need it),
# so give it the usual name: at runtime a missing library just means "no Vulkan".
grep -q "^#define SONAME_LIBVULKAN" include/config.h \
  || printf '\n/* Decanter: see engine/build.sh */\n#define SONAME_LIBVULKAN "libMoltenVK.dylib"\n' >> include/config.h

# --- build + install ---------------------------------------------------------------
say "Building with $JOBS jobs (this takes a while)"
arch -x86_64 make -j"$JOBS" > "$WORK/make-$ENGINE_ID.log" 2>&1 \
  || { tail -40 "$WORK/make-$ENGINE_ID.log"; die "build failed (log: $WORK/make-$ENGINE_ID.log)"; }

say "Installing into $OUT"
rm -rf "$OUT"
arch -x86_64 make install-lib > "$WORK/install-$ENGINE_ID.log" 2>&1 \
  || { tail -30 "$WORK/install-$ENGINE_ID.log"; die "install failed"; }

# --- make it self-contained ---------------------------------------------------------
# Bundle the Intel Homebrew dylibs Wine loads at runtime (gnutls, freetype and their
# dependencies) into lib/, and point the binaries at them, so the engine runs on Macs
# without Homebrew.
say "Bundling runtime libraries"
mkdir -p "$OUT/lib"
# Each reference is rewritten to @loader_path/<path from the file to lib/>, so the
# libraries find each other wherever the engine folder lives.
relto_lib() { python3 -c 'import os,sys; print(os.path.relpath(sys.argv[2], os.path.dirname(sys.argv[1])))' "$1" "$OUT/lib"; }
bundle() {  # copy every deps dylib a file depends on into lib/, recursively
  local f="$1" dep base rel
  rel="$(relto_lib "$f")"
  # `|| true`: most files link nothing from deps, and an empty grep must not stop the script.
  { otool -L "$f" 2>/dev/null | awk 'NR>1 {print $1}' | grep "^$X86_BREW/" || true; } | while read -r dep; do
    base="$(basename "$dep")"
    if [ ! -f "$OUT/lib/$base" ]; then
      cp -L "$dep" "$OUT/lib/$base"; chmod u+w "$OUT/lib/$base"
      install_name_tool -id "@loader_path/$base" "$OUT/lib/$base" 2>/dev/null
      bundle "$OUT/lib/$base"
    fi
    install_name_tool -change "$dep" "@loader_path/$rel/$base" "$f" 2>/dev/null
  done
}
# Wine dlopens gnutls and freetype by file name (found through the engine's lib/ on
# DYLD_FALLBACK_LIBRARY_PATH, which Decanter's Runner sets), so copy them explicitly.
for lib in "$X86_BREW/lib/libgnutls.30.dylib" "$X86_BREW/lib/libfreetype.6.dylib"; do
  [ -f "$lib" ] || die "missing $lib (did build-deps.sh finish?)"
  base="$(basename "$lib")"
  cp -L "$lib" "$OUT/lib/$base"; chmod u+w "$OUT/lib/$base"
  install_name_tool -id "@loader_path/$base" "$OUT/lib/$base"
  bundle "$OUT/lib/$base"
done
find "$OUT/bin" "$OUT/lib/wine/x86_64-unix" -type f -perm -u+x -o -name '*.so' 2>/dev/null | while read -r f; do bundle "$f"; done

# Drop debug data from the Windows files (1.3 GB -> a fraction; see strip.sh).
"$HERE/strip.sh" "$OUT"

# Wine Mono (.NET), shared by every bottle; without it Wine asks to download it.
"$HERE/add-mono.sh" "$OUT"

# License texts of every component (Wine's LGPL and the GNU licenses require shipping them).
"$HERE/add-licenses.sh" "$OUT"

# Room for Apple's D3DMetal, added later by add-d3dmetal.sh from the user's own copy.
mkdir -p "$OUT/lib/external"

# Ad-hoc sign everything we modified (Apple silicon refuses unsigned or broken code).
find "$OUT" -type f \( -name '*.dylib' -o -name '*.so' -o -perm -u+x \) -exec codesign --force --sign - {} \; 2>/dev/null || true

cat > "$OUT/decanter-engine.json" <<JSON
{
  "id": "$ENGINE_ID",
  "wine": "11.0",
  "source": "CrossOver $CX_VERSION (CodeWeavers, LGPL/GPL)",
  "source_url": "$CX_URL",
  "source_sha256": "$CX_SHA256",
  "arch": "x86_64",
  "built": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "d3dmetal": false
}
JSON

say "Done"
"$OUT/bin/wine" --version
du -sh "$OUT"
echo "Next: engine/add-d3dmetal.sh <path to Apple's Game Porting Toolkit redist folder>"
