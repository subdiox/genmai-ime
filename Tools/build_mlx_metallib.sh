#!/bin/zsh
# Builds mlx.metallib for the mlx-swift checkout of a SwiftPM build directory, with MLX's own Metal flags
# (-fno-fast-math, as mlx/backend/metal/kernels/CMakeLists.txt), and puts it next to the built executables.
#
# Why: `swift build` (Swift Build engine, Swift 6.4) does compile mlx-swift's Metal kernels into
# mlx-swift_Cmlx.bundle/Contents/Resources/default.metallib, but with Xcode's default `-fmetal-math-mode=fast`.
# Fast math changes e.g. layer_norm results by 1 bf16 ulp, which flips beam-search near-ties against the Python MLX
# reference (pip wheels are built with -fno-fast-math). MLX looks for a colocated `mlx.metallib` (directory of the
# binary that links MLX, then `Resources/mlx.metallib`) BEFORE the SwiftPM bundle, so dropping this file next to
# the executable (or into Contents/MacOS of an app) is enough. Only the precompiled kernels live in the metallib
# (mlx-swift uses MLX's JIT mode for the rest, compiled at run time with safe math).
#
# Usage: Tools/build_mlx_metallib.sh [build path] [configuration]
#   build path     SwiftPM --build-path (default .build); must already contain checkouts/mlx-swift
#   configuration  release (default) or debug; output: <build path>/<configuration>/mlx.metallib
#   OUT=<file>     write the metallib somewhere else instead
set -euo pipefail

ROOT=${0:A:h:h}
BUILD_PATH=${1:-$ROOT/.build}
CONFIGURATION=${2:-release}
SRC=$BUILD_PATH/checkouts/mlx-swift/Source/Cmlx/mlx-generated/metal
[[ -d $SRC ]] || { echo "missing $SRC (run swift package resolve / swift build first)" >&2; exit 1; }
OUT=${OUT:-$BUILD_PATH/$CONFIGURATION/mlx.metallib}
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

FLAGS=(-x metal -Wall -Wextra -fno-fast-math -Wno-c++17-extensions -Wno-c++20-extensions -mmacosx-version-min=15.0)
airs=()
for f in "$SRC"/**/*.metal; do
  air=$TMP/${${f#$SRC/}//\//_}.air
  xcrun -sdk macosx metal "${FLAGS[@]}" -c "$f" -I"$SRC" -o "$air"
  airs+=("$air")
done
mkdir -p "${OUT:h}"
xcrun -sdk macosx metal -mmacosx-version-min=15.0 "${airs[@]}" -o "$OUT"
echo "wrote $OUT (${#airs} kernels files)"
