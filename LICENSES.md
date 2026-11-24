# Licenses of what the engine contains

The engine is built from source by `build.sh`. Every component is open source; the license
texts are inside each engine under `share/doc/<component>/`.

| Component | Version | License | Source |
|---|---|---|---|
| Wine (CodeWeavers' CrossOver tree) | 11.0 / CrossOver 26.3.0 | LGPL-2.1-or-later | [crossover-sources-26.3.0.tar.gz](https://media.codeweavers.com/pub/crossover/source/crossover-sources-26.3.0.tar.gz) (SHA-256 in `build.sh`) |
| Decanter's Wine patches (`patches/`) | — | LGPL-2.1-or-later | this repository |
| GnuTLS | 3.8.3 | LGPL-2.1-or-later | from the CrossOver source package |
| Nettle | 3.10 | LGPL-3.0-or-later or GPL-2.0-or-later | [GNU release](https://ftp.gnu.org/gnu/nettle/nettle-3.10.tar.gz) (SHA-256 in `build-deps.sh`) |
| GMP | 6.3.0 | LGPL-3.0-or-later or GPL-2.0-or-later | from the CrossOver source package |
| FreeType | 2.13.3 | FreeType License (FTL) or GPL-2.0 | from the CrossOver source package |
| SDL2 | 2.32.10 | zlib | [libsdl.org release on GitHub](https://github.com/libsdl-org/SDL/releases/tag/release-2.32.10) (SHA-256 in `build-deps.sh`) |
| MoltenVK | 1.4.2 | Apache-2.0 | [Khronos release on GitHub](https://github.com/KhronosGroup/MoltenVK/releases/tag/v1.4.2), prebuilt `MoltenVK-macos.tar`, x86_64 half (SHA-256 in `build-deps.sh`) |
| Wine Mono | 10.4.1 | mostly MIT; see [wine-mono](https://gitlab.winehq.org/mono/wine-mono) | [WineHQ release](https://dl.winehq.org/wine/wine-mono/10.4.1/) (SHA-256 in `add-mono.sh`) |

The build scripts in this repository are also LGPL-2.1-or-later (see `LICENSE`).

## Not included

**Apple's D3DMetal** (part of Apple's Game Porting Toolkit) is Apple software under Apple's
license and is never part of an engine release. Each user downloads the toolkit from Apple;
Decanter checks Apple's signature and copies D3DMetal into the user's own engine
(`add-d3dmetal.sh` does the same from the command line). `package.sh` refuses to package an
engine that contains it.
