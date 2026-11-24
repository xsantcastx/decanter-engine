#!/bin/bash
# Builds the x86_64 libraries the engine links against (gmp, nettle, gnutls, freetype from the
# copies inside CodeWeavers' CrossOver source package; SDL2 from libsdl.org's release), into ~/.cache/decanter-engine/deps.
# Homebrew no longer installs Intel packages on Apple silicon, so we build them here.
# Called by engine/build.sh; safe to re-run (finished libraries are skipped).
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Autotools can't cope with spaces in paths (".../1. Projects/..."), so the work area
# (sources, objects, output) lives in a space-free folder outside the repo.
WORK="${DECANTER_ENGINE_WORK:-$HOME/.cache/decanter-engine}"
case "$WORK" in *" "*) printf 'set DECANTER_ENGINE_WORK to a folder without spaces\n' >&2; exit 1;; esac
SRC="$WORK/src/sources"
DEPS="$WORK/deps"
B="$WORK/build-deps"
ARM_BREW=/opt/homebrew
JOBS="$(sysctl -n hw.ncpu)"

say() { printf '\n== deps: %s\n' "$*"; }
die() { printf 'engine/build-deps.sh: %s\n' "$*" >&2; exit 1; }
for t in autoreconf automake glibtoolize; do
  [ -x "$ARM_BREW/bin/$t" ] || die "missing $t: brew install autoconf automake libtool"
done
export LIBTOOLIZE=glibtoolize   # Homebrew names GNU libtool's tools with a g prefix
[ -d "$SRC/gnutls/gnutls" ] && [ -d "$SRC/freetype" ] || die "extract the CrossOver source first (engine/build.sh does this)"

export PATH="$ARM_BREW/bin:/usr/bin:/bin:/usr/sbin:/sbin"
export MACOSX_DEPLOYMENT_TARGET=14.0
export CC="clang -arch x86_64"
export CXX="clang++ -arch x86_64"
export CPPFLAGS="-I$DEPS/include"
export LDFLAGS="-L$DEPS/lib -Wl,-headerpad_max_install_names"
export PKG_CONFIG="$ARM_BREW/bin/pkg-config"
export PKG_CONFIG_LIBDIR="$DEPS/lib/pkgconfig"
HOST=x86_64-apple-darwin
mkdir -p "$DEPS" "$B"

build() {  # build <name> <marker file in $DEPS/lib> <source dir> [configure args...]
  local name="$1" marker="$2" dir="$3"; shift 3
  if [ -f "$DEPS/lib/$marker" ]; then echo "deps: $name already built"; return; fi
  say "building $name"
  rm -rf "$B/$name"; mkdir -p "$B/$name"; cd "$B/$name"
  arch -x86_64 "$dir/configure" --host=$HOST --prefix="$DEPS" --disable-static --enable-shared "$@" \
    > "$B/$name.configure.log" 2>&1 || { tail -20 "$B/$name.configure.log"; die "$name configure failed"; }
  arch -x86_64 make -j"$JOBS" > "$B/$name.make.log" 2>&1 || { tail -30 "$B/$name.make.log"; die "$name build failed"; }
  arch -x86_64 make install > "$B/$name.install.log" 2>&1 || { tail -20 "$B/$name.install.log"; die "$name install failed"; }
}

# GMP (bignum math, needed by nettle's public-key code)
build gmp libgmp.dylib "$SRC/gnutls/gmp" --enable-cxx=no

# nettle (crypto primitives). CrossOver's package leaves out nettle's top-level
# Makefile.in, so we use GNU's release of the same version. Its 876 source files were
# checked to be byte-identical to CrossOver's copy; the checksum below pins that file.
NETTLE_VERSION=3.10
NETTLE_SHA256=b4c518adb174e484cb4acea54118f02380c7133771e7e9beb98a0787194ee47c
NETTLE_TGZ="$WORK/extra/nettle-$NETTLE_VERSION.tar.gz"
NETTLE_SRC="$WORK/extra/nettle-$NETTLE_VERSION"
mkdir -p "$WORK/extra"
if [ ! -f "$NETTLE_TGZ" ]; then
  say "downloading nettle $NETTLE_VERSION from GNU"
  curl -fsSL -o "$NETTLE_TGZ.part" "https://ftp.gnu.org/gnu/nettle/nettle-$NETTLE_VERSION.tar.gz" && mv "$NETTLE_TGZ.part" "$NETTLE_TGZ"
fi
echo "$NETTLE_SHA256  $NETTLE_TGZ" | shasum -a 256 -c - >/dev/null || die "checksum mismatch for $NETTLE_TGZ"
[ -x "$NETTLE_SRC/configure" ] || tar -xzf "$NETTLE_TGZ" -C "$WORK/extra"
build nettle libnettle.dylib "$NETTLE_SRC" --disable-documentation --disable-openssl --enable-mini-gmp=no

# GnuTLS (TLS for schannel: store logins, HTTPS inside games)
# The link flags are given explicitly, each a single word: gnutls's configure tests
# them unquoted (`test x$NETTLE_LIBS != x`), so a value with a space silently turns
# nettle off and the library then fails to link. LDFLAGS already has -L$DEPS/lib.
build gnutls libgnutls.dylib "$SRC/gnutls/gnutls" \
  NETTLE_CFLAGS="-I$DEPS/include" NETTLE_LIBS="-lnettle" \
  HOGWEED_CFLAGS="-I$DEPS/include" HOGWEED_LIBS="-lhogweed" \
  GMP_CFLAGS="-I$DEPS/include" GMP_LIBS="-lgmp" \
  --with-included-libtasn1 --with-included-unistring --without-p11-kit --without-idn \
  --without-zstd --without-brotli --without-tpm --without-tpm2 --disable-doc --disable-tests \
  --disable-tools --disable-cxx --disable-guile --disable-nls --enable-local-libopts=yes \
  --disable-gost   # gnutls 3.8.3's bundled GOST code collides with nettle 3.10's own; unused by games

# FreeType (font rendering)
if [ ! -x "$SRC/freetype/builds/unix/configure" ]; then
  say "generating freetype's configure"
  (cd "$SRC/freetype" && ./autogen.sh > "$B/freetype.autogen.log" 2>&1) || die "freetype autogen failed"
fi
# FreeType's build tries to `git submodule update` its debug-logging add-on (dlg) when
# src/dlg/dlg.* is missing, which a source package can't do. dlg is only compiled with
# FT_DEBUG_LOGGING, which we leave off, so a placeholder file satisfies the check.
mkdir -p "$SRC/freetype/include/dlg"
for f in src/dlg/dlg.c include/dlg/dlg.h include/dlg/output.h; do
  [ -e "$SRC/freetype/$f" ] || printf '/* placeholder: dlg is only used with FT_DEBUG_LOGGING, which Decanter leaves off */\n' > "$SRC/freetype/$f"
done
build freetype libfreetype.dylib "$SRC/freetype" \
  --without-harfbuzz --without-png --without-brotli --without-bzip2 --with-zlib=yes

# SDL2 (game controllers). Wine's controller driver uses it to recognize Xbox, PlayStation and
# Switch controllers and offer them to games as Xbox controllers; without it, macOS's view of an
# Xbox Series controller has no buttons Wine can read. Not in CrossOver's package: libsdl.org's
# release (zlib license), pinned by checksum.
SDL_VERSION=2.32.10
SDL_SHA256=5f5993c530f084535c65a6879e9b26ad441169b3e25d789d83287040a9ca5165
SDL_TGZ="$WORK/extra/SDL2-$SDL_VERSION.tar.gz"
SDL_SRC="$WORK/extra/SDL2-$SDL_VERSION"
if [ ! -f "$SDL_TGZ" ]; then
  say "downloading SDL $SDL_VERSION from libsdl.org's GitHub releases"
  curl -fsSL -o "$SDL_TGZ.part" "https://github.com/libsdl-org/SDL/releases/download/release-$SDL_VERSION/SDL2-$SDL_VERSION.tar.gz" && mv "$SDL_TGZ.part" "$SDL_TGZ"
fi
echo "$SDL_SHA256  $SDL_TGZ" | shasum -a 256 -c - >/dev/null || die "checksum mismatch for $SDL_TGZ"
[ -x "$SDL_SRC/configure" ] || tar -xzf "$SDL_TGZ" -C "$WORK/extra"
build sdl2 libSDL2.dylib "$SDL_SRC"   # default options, as in the SDL builds Wine is usually tested with

# MoltenVK (Vulkan on Metal). Wine looks for libMoltenVK.dylib at runtime; with it, Vulkan games
# run and Wine's Direct3D 9-11 can draw through Vulkan instead of OpenGL. Khronos' prebuilt
# release (Apache-2.0), pinned by checksum; the standard build, not the private-API one. Only
# its x86_64 half is kept: the engine runs under Rosetta.
MVK_VERSION=1.4.2
MVK_SHA256=f95765a6229cb7b915990a2890ce12ebe36a730b021545d3d52ae69ce4c4024e
MVK_TAR="$WORK/extra/MoltenVK-macos-$MVK_VERSION.tar"
MVK_SRC="$WORK/extra/MoltenVK-$MVK_VERSION"
if [ ! -f "$MVK_TAR" ]; then
  say "downloading MoltenVK $MVK_VERSION from KhronosGroup's GitHub releases"
  curl -fsSL -o "$MVK_TAR.part" "https://github.com/KhronosGroup/MoltenVK/releases/download/v$MVK_VERSION/MoltenVK-macos.tar" && mv "$MVK_TAR.part" "$MVK_TAR"
fi
echo "$MVK_SHA256  $MVK_TAR" | shasum -a 256 -c - >/dev/null || die "checksum mismatch for $MVK_TAR"
if [ ! -f "$DEPS/lib/libMoltenVK.dylib" ]; then
  rm -rf "$MVK_SRC"; mkdir -p "$MVK_SRC"
  tar -xf "$MVK_TAR" -C "$MVK_SRC" --strip-components 1 MoltenVK/LICENSE MoltenVK/MoltenVK/dynamic/dylib/macOS/libMoltenVK.dylib
  mkdir -p "$DEPS/lib"
  lipo "$MVK_SRC/MoltenVK/dynamic/dylib/macOS/libMoltenVK.dylib" -thin x86_64 -output "$DEPS/lib/libMoltenVK.dylib"
  install_name_tool -id "$DEPS/lib/libMoltenVK.dylib" "$DEPS/lib/libMoltenVK.dylib" 2>/dev/null
fi

say "done"
ls "$DEPS/lib"/*.dylib
