#!/bin/zsh
# Prepares the genmai AI conversion model: downloads it from Hugging Face (subdiox/genmai-v25m-kd: HF GPT-2,
# fp32 safetensors, 1.2 GB) unless a local copy is given, and converts it to the compact runtime layout GenmaiAI
# loads: model.safetensors in bf16 with the Conv1D weights transposed to (out, in) (~0.6 GB; metadata
# format=genmai-bf16-out-in), plus tokenizer.json, config.json, genmai_fmt.txt.
#
# Usage: Tools/prepare_genmai_model.sh [source dir] [destination dir]
#   source       a local copy of the HF model; defaults to $GENMAI_SOURCE_DIR, else it is downloaded into
#                ~/Library/Caches/genmai/genmai-v25m-kd (kept for later runs)
#   destination  defaults to ~/Library/Application Support/Genmai/model/v25m_kd (where the IME loads it from)
#   BUILD_PATH=<dir>  SwiftPM build directory for genmai-cli (default .build-genmai)
set -euo pipefail

ROOT=${0:A:h:h}
HF_REPO=subdiox/genmai-v25m-kd
FILES=(model.safetensors config.json tokenizer.json genmai_fmt.txt)
SRC=${1:-${GENMAI_SOURCE_DIR:-}}
DST=${2:-$HOME/Library/Application Support/Genmai/model/v25m_kd}
BUILD_PATH=${BUILD_PATH:-$ROOT/.build-genmai}

if [[ -z $SRC ]]; then
  SRC=$HOME/Library/Caches/genmai/genmai-v25m-kd
  mkdir -p "$SRC"
  for f in $FILES; do
    [[ -f $SRC/$f ]] && continue
    echo "==> downloading $HF_REPO/$f"
    curl -fL --progress-bar -o "$SRC/$f.part" "https://huggingface.co/$HF_REPO/resolve/main/$f"
    mv "$SRC/$f.part" "$SRC/$f"
  done
fi
for f in $FILES; do
  [[ -f $SRC/$f ]] || { echo "missing $SRC/$f" >&2; exit 1; }
done
echo "==> swift build genmai-cli ($BUILD_PATH)"
swift build --package-path "$ROOT" --build-path "$BUILD_PATH" -c release --product genmai-cli
echo "==> mlx.metallib (safe math, next to genmai-cli)"
"$ROOT/Tools/build_mlx_metallib.sh" "$BUILD_PATH" release
echo "==> $SRC -> $DST"
"$BUILD_PATH/release/genmai-cli" prepare "$SRC" "$DST"
