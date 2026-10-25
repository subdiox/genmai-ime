#!/bin/zsh
# Installs the genmai AI conversion model from the command line, like the "Download" button in the settings (tab
# "AI"): `genmai-cli install` downloads the newest release this IME can run of the chosen model (the highest vX.Y.Z
# tag of Hugging Face subdiox/genmai-310M, or subdiox/genmai-90M with --size small; its Core ML model,
# model-coreml.zip), checks the checksums Hugging Face lists, compiles the model and installs it with config.json,
# tokenizer.json and genmai_model.json. A local HF checkpoint is converted with Tools/coreml/genmai_coreml.py instead.
#
# Usage: Tools/prepare_genmai_model.sh [--size small|medium] [destination dir]
#   destination  defaults to ~/Library/Application Support/Genmai/model (where the IME loads it from)
#   BUILD_PATH=<dir>  SwiftPM build directory for genmai-cli (default .build-genmai)
set -euo pipefail

ROOT=${0:A:h:h}
SIZE=medium
if [[ ${1:-} == --size ]]; then
  SIZE=${2:?--size needs small or medium}
  shift 2
fi
DST=${1:-$HOME/Library/Application Support/Genmai/model}
BUILD_PATH=${BUILD_PATH:-$ROOT/.build-genmai}

echo "==> swift build genmai-cli ($BUILD_PATH)"
swift build --package-path "$ROOT" --build-path "$BUILD_PATH" -c release --product genmai-cli
"$BUILD_PATH/release/genmai-cli" install --size "$SIZE" "$DST"
