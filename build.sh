#!/usr/bin/env bash
# Builds proton-btw: Valve's Proton at a fixed commit, with the patches in patches/.
#
#   ./build.sh            fetch (first time), patch, configure and build
#   ./build.sh install    the same, then install as a Steam compat tool
#   ./build.sh patch      only fetch and patch the sources (to look at or edit them)
#   ./build.sh clean      remove the build folder (the sources stay)
#
# Settings (environment, or a file build.env beside this script):
#   X86_64_MARCH   CPU target of the 64-bit build. Default: Valve's, any x86-64 CPU.
#                  For one machine, e.g. "-march=znver4 -mno-avx" (Zen 4; keep -mno-avx:
#                  mingw's GCC misaligns the stack for AVX in Windows DLLs).
#   BUILD_NAME     name of the compat tool (default: victory-ntdll)
#   JOBS           parallel jobs (default: all cores)
#   SRC, BUILD     source and build folders (default: ./Proton, ./build)
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[[ -f "$HERE/build.env" ]] && source "$HERE/build.env"

PROTON_URL="https://github.com/ValveSoftware/Proton.git"
PROTON_COMMIT="e78e12322b45bb31e95420a98d41e9aa13c2c07f"    # proton_11.0, "update wine"
VKD3D_PROTON_COMMIT="71cae091b06571e51446cf2a937f0b04c237c04d" # master: VIctory's shaders need it

SRC="${SRC:-$HERE/Proton}"
BUILD="${BUILD:-$HERE/build}"
BUILD_NAME="${BUILD_NAME:-victory-ntdll}"
JOBS="${JOBS:-$(nproc)}"
X86_64_MARCH="${X86_64_MARCH:-}"

say() { printf '\033[1m==> %s\033[0m\n' "$*"; }

fetch() {
  if [[ ! -d "$SRC/.git" ]]; then
    say "cloning Valve's Proton into $SRC"
    git clone "$PROTON_URL" "$SRC"
  fi
  if [[ "$(git -C "$SRC" rev-parse HEAD)" != "$PROTON_COMMIT" ]]; then
    say "checking out Proton $PROTON_COMMIT"
    git -C "$SRC" fetch origin
    git -C "$SRC" checkout -q "$PROTON_COMMIT"
  fi
  say "submodules (the first time this downloads several GB)"
  git -C "$SRC" submodule update --init --recursive --jobs "$JOBS"
  if [[ "$(git -C "$SRC/vkd3d-proton" rev-parse HEAD)" != "$VKD3D_PROTON_COMMIT" ]]; then
    say "vkd3d-proton at $VKD3D_PROTON_COMMIT"
    git -C "$SRC/vkd3d-proton" fetch -q origin
    git -C "$SRC/vkd3d-proton" checkout -q "$VKD3D_PROTON_COMMIT"
    git -C "$SRC/vkd3d-proton" submodule update --init --recursive
  fi
}

# Applies each patch of $1 in the repository $2, unless it is in already.
apply_patches() {
  local dir="$1" repo="$2" p
  for p in "$HERE/patches/$dir"/*.patch; do
    [[ -e "$p" ]] || continue
    if git -C "$repo" apply --check -R "$p" 2> /dev/null; then
      echo "   in already: $dir/$(basename "$p")"
    else
      git -C "$repo" apply "$p"
      echo "   applied:    $dir/$(basename "$p")"
    fi
  done
}

patch_sources() {
  say "patches"
  apply_patches proton "$SRC"
  apply_patches wine "$SRC/wine"
}

configure() {
  if [[ ! -f "$BUILD/Makefile" ]]; then
    say "configuring $BUILD (compat tool: $BUILD_NAME)"
    mkdir -p "$BUILD"
    (cd "$BUILD" && "$SRC/configure.sh" --build-name="$BUILD_NAME")
  fi
  # The CPU target lives in the build folder's Makefile, so that the build in the
  # container sees it too.
  sed -i '/^X86_64_MARCH :=/d' "$BUILD/Makefile"
  if [[ -n "$X86_64_MARCH" ]]; then
    sed -i "/^include /i X86_64_MARCH := $X86_64_MARCH" "$BUILD/Makefile"
    say "CPU target: $X86_64_MARCH"
  fi
}

build() {
  command -v docker > /dev/null || { echo "docker is needed (Valve's Steam Runtime container)" >&2; exit 1; }
  say "building with $JOBS jobs (the first build takes a while)"
  make -C "$BUILD" -j"$JOBS"
}

case "${1:-build}" in
  build) fetch; patch_sources; configure; build ;;
  install) fetch; patch_sources; configure; build; make -C "$BUILD" install ;;
  patch) fetch; patch_sources ;;
  clean) say "removing $BUILD"; rm -rf "$BUILD" ;;
  *) sed -n '2,8p' "$0"; exit 1 ;;
esac
