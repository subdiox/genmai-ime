#!/bin/zsh
# Installs the genmai AI conversion model from the command line, like the "Download" button in the settings (tab
# "AI"): `genmai-cli install` downloads the newest release this IME can run (the highest vX.Y.Z tag of Hugging
# Face subdiox/genmai; its model-bf16.safetensors, already in the runtime layout GenmaiAI loads, 0.6 GB), checks the
# checksums Hugging Face lists and installs it with config.json, tokenizer.json and genmai_model.json. With --source,
# a local HF model directory (e.g. a checkpoint that is not a release; fp32 HF layout) is converted instead
# (`genmai-cli prepare`; no genmai_model.json). The same conversion writes model-bf16.safetensors for a release.
#
# Usage: Tools/prepare_genmai_model.sh [--source <HF model dir>] [destination dir]
#   destination  defaults to ~/Library/Application Support/Genmai/model (where the IME loads it from)
#   BUILD_PATH=<dir>  SwiftPM build directory for genmai-cli (default .build-genmai)
set -euo pipefail

ROOT=${0:A:h:h}
SRC=
if [[ ${1:-} == --source ]]; then
  SRC=${2:?--source needs a directory}
  shift 2
fi
DST=${1:-$HOME/Library/Application Support/Genmai/model}
BUILD_PATH=${BUILD_PATH:-$ROOT/.build-genmai}

echo "==> swift build genmai-cli ($BUILD_PATH)"
swift build --package-path "$ROOT" --build-path "$BUILD_PATH" -c release --product genmai-cli
echo "==> mlx.metallib (safe math, next to genmai-cli; for the check conversion)"
"$ROOT/Tools/build_mlx_metallib.sh" "$BUILD_PATH" release
if [[ -n $SRC ]]; then
  echo "==> $SRC -> $DST"
  "$BUILD_PATH/release/genmai-cli" prepare "$SRC" "$DST"
else
  "$BUILD_PATH/release/genmai-cli" install "$DST"
fi
