# proton-btw

Valve's [Proton](https://github.com/ValveSoftware/Proton) 11 with a few changes to Wine for running the Xbox Series
build of GTA VI through [VIctory](https://github.com/Marvisak/VIctory) on Linux: see
[GTA6-btw](https://github.com/JokiiiBoy/GTA6-btw). It works as an ordinary Steam compat tool for anything else too.

This repository holds only the changes and a build script. `build.sh` fetches Valve's Proton at a fixed commit,
applies the patches and builds it in Valve's Steam Runtime container.

## What is changed

| Patch | What it does | Why |
|---|---|---|
| [wine/0001](patches/wine/0001-server-memory-views-in-a-tree.patch) | The Wine server finds a process's memory views through a red-black tree beside its list | The title maps and unmaps 64 KiB views 1,000-14,000 times a second with 20,000-70,000 alive; each call walked the whole list (150-200 µs, now about 15 µs). Loading and streaming get much faster |
| [wine/0002](patches/wine/0002-ntdll-kernel-write-watch-without-the-lock.patch) | `NtGetWriteWatch`/`NtResetWriteWatch` on a range the kernel tracks leave ntdll's virtual-memory lock before scanning | VIctory asks for written pages thousands of times a frame; every other memory call of the process waited behind those scans |
| [wine/0003](patches/wine/0003-ntdll-int3-no-rewind-switch.patch) | `WINE_INT3_NO_REWIND=1` leaves the instruction pointer after an `int3` | For a program that steps over `int3` itself (off unless set) |
| [proton/0001](patches/proton/0001-makefile-x86-64-march.patch) | `X86_64_MARCH` sets the CPU target of the 64-bit build | Building for one CPU (see below) |

Also: vkd3d-proton is taken at master `71cae091` instead of Proton 11's own: with the older one some of VIctory's
shaders become invalid SPIR-V and the driver crashes on them.

The numbers in the first row are [zeex64](https://github.com/zeex64/VIctory-7900XTX/tree/main/linux/wine)'s
measurements of the same change on an RX 9070 XT.

## Building

You need: Linux x86-64, `git`, `make`, [Docker](https://docs.docker.com/engine/install/) usable by your user (the
build runs in Valve's container), about 40 GB of disk and some time (the first build compiles Wine, DXVK,
vkd3d-proton, FFmpeg and GStreamer; later builds only what changed).

```bash
git clone https://github.com/JokiiiBoy/proton-btw
cd proton-btw
cp build.env.example build.env     # optional: your CPU target
./build.sh install
```

`./build.sh install` clones Proton into `Proton/` with its submodules (several GB the first time), applies the
patches, builds into `build/` and installs the result as the compat tool **victory-ntdll** in
`~/.steam/root/compatibilitytools.d/`. Restart Steam to see it there, or point a launcher at
`~/.steam/root/compatibilitytools.d/victory-ntdll/proton`.

| Command | |
|---|---|
| `./build.sh` | fetch, patch and build |
| `./build.sh install` | the same, then install |
| `./build.sh patch` | only fetch and patch the sources (to read or change them in `Proton/`) |
| `./build.sh clean` | remove `build/` (the sources stay) |

### Settings

In `build.env` (not in git) or the environment:

| Variable | Default | |
|---|---|---|
| `X86_64_MARCH` | Valve's (`-march=nocona -mtune=core-avx2`, any x86-64 CPU) | the 64-bit build's CPU target |
| `BUILD_NAME` | `victory-ntdll` | the compat tool's name |
| `JOBS` | all cores | parallel jobs |
| `SRC`, `BUILD` | `./Proton`, `./build` | where the sources and the build go |

For one machine, set its CPU but keep AVX out: mingw's GCC misaligns the stack for AVX in Windows DLLs, which crashes
at random (DXVK refuses to build with AVX for that reason). Zen 4, for example: `X86_64_MARCH="-march=znver4 -mno-avx"`.
A build for one CPU runs only on that CPU family and newer.

## Changing a patch

```bash
./build.sh patch                  # sources in Proton/, patches applied
# edit Proton/wine/..., then write the change back:
git -C Proton/wine diff -- server/ > patches/wine/0001-server-memory-views-in-a-tree.patch
./build.sh install
```

(The text above the first `diff --git` line of a patch is its description; keep it when you write a patch again.)

## Known issues

- A build folder must not be moved or renamed: Proton's build records absolute paths. Use `./build.sh clean`.
- The game's audio is choppy at low frame rates; that is the title's own audio engine, not Wine's output.

## Licence

Proton is under the [BSD 3-Clause licence](https://github.com/ValveSoftware/Proton/blob/proton_11.0/LICENSE) and
Wine under the LGPL 2.1 or later; the patches to Wine are under Wine's licence. These changes are not part of Valve's
Proton or of Wine and are not submitted to either.
