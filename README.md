# Decanter engine

The Windows compatibility engine used by Decanter, a free Mac app for playing Windows
games. It is Wine 11, built from CodeWeavers' published CrossOver 26.3.0 source as an
x86_64 build that runs on Apple silicon through Rosetta 2, with a few patches of our own
and Wine Mono included.

Decanter downloads a release from here on first launch. You only need this repository to
build the engine yourself or to see exactly what is in it.

## What's in a release

- `wine-<version>.tar.xz`: the engine (about 130 MB; about 740 MB unpacked).
- The feed Decanter reads, `https://xsantcastx.com/decanter/engines.json`, points at the
  release file with its SHA-256. Decanter checks that checksum before installing.

Apple's D3DMetal is **not** included (see [LICENSES.md](LICENSES.md)); each user adds it from
Apple's free Game Porting Toolkit.

## Building

Needs Xcode 26+, Rosetta 2, and Homebrew (arm64) with
`bison flex pkgconf mingw-w64 autoconf automake libtool`.

```bash
./build.sh                                                        # about an hour
./package.sh <engine> <out dir> <base URL>                        # .tar.xz + engines.json
./add-d3dmetal.sh <engine> <Game Porting Toolkit redist folder>   # local use only
```

The work area is `~/.cache/decanter-engine/` (`DECANTER_ENGINE_WORK` changes it; it must not
contain spaces, which autotools can't handle). Compilers record build paths, so **release
builds use a folder outside your home folder**, e.g.
`DECANTER_ENGINE_WORK=/Users/Shared/decanter-engine ./build.sh`; `package.sh` refuses an
engine that contains your home path.

## What the scripts do

- **`build-deps.sh`** builds the x86_64 libraries Wine links (GMP, Nettle, GnuTLS, FreeType),
  because Homebrew no longer installs Intel packages on Apple silicon.
- **`build.sh`** verifies the CrossOver source's SHA-256, applies `patches/`, configures Wine
  with `--enable-archs=i386,x86_64` (new WoW64), builds and installs it, bundles the
  libraries with `@loader_path` references, strips debug data, adds Wine Mono and the
  license texts, ad-hoc signs it and writes `decanter-engine.json`.
- **`strip.sh`** removes debug sections from the Windows files (1.3 GB → about 510 MB).
- **`add-mono.sh`** adds Wine Mono 10.4.1 as a shared install, so bottles never ask to download it.
- **`package.sh`** makes the release archive and feed, and refuses engines containing D3DMetal.

## Patches

All LGPL-2.1-or-later, like Wine.

- **`0001-winemac-dock-reopen`**: when a program's Dock icon is clicked and it has no window
  to show (a launcher closed to its tray), run `WINE_DOCK_REOPEN_CMD` so it opens again.
- **`0002-kernelbase-child-args`**: `WINE_DECANTER_CHILD_ARGS="name.exe=args;…"` appends
  arguments to every process started from a program with that name. Steam's web view needs
  Chromium's `--in-process-gpu` to draw its window on macOS, and Battle.net needs the same
  when its installer or updater starts it.
- **`0003-winemac-snapshot-surface`**: hand Cocoa a copy of a window's pixels instead of the
  live surface memory, so windows that redraw often never show half-drawn, black frames.

## Build workarounds (commented in the scripts)

- GnuTLS: `--disable-gost`, and single-word `NETTLE_LIBS`/`HOGWEED_LIBS`/`GMP_LIBS`.
- FreeType: placeholder `dlg` files, so the build doesn't try to fetch a git submodule.
- Wine: OpenGL left to auto-detect (Wine 11 wants EGL, which macOS lacks), and
  `SONAME_LIBVULKAN` defined after configure. MoltenVK isn't bundled yet.
- The engine finds GnuTLS and FreeType through `DYLD_FALLBACK_LIBRARY_PATH`. macOS drops
  `DYLD_*` when a process starts through a protected system tool (`nohup`, `arch`,
  `/bin/sh`), so start `bin/wine` directly.

## Clean-room rule

These scripts and patches are written from public documentation and the source itself.
Don't copy from projects without a license.
