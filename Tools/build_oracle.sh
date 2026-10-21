#!/bin/bash
# Builds the reference C++ Mozc tools (converter_main) and the OSS data set, and copies the data set to Data/.
# usage: Tools/build_oracle.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BAZELISK="$ROOT/Tools/bin/bazelisk"
if [ ! -x "$BAZELISK" ]; then
  mkdir -p "$ROOT/Tools/bin"
  curl -sSL -o "$BAZELISK" https://github.com/bazelbuild/bazelisk/releases/download/v1.25.0/bazelisk-darwin-arm64
  chmod +x "$BAZELISK"
fi
cd "$ROOT/Vendor/mozc/src"
# Android NDK / Qt / WiX / LLVM / MSYS are not needed for the reference tools.
python3 build_tools/update_deps.py --noqt --nondk --nowix --nollvm --nomsys >/dev/null
"$BAZELISK" build //converter:converter_main //data_manager/oss:mozc_dataset_for_oss \
  //data_manager/testing:mozc_dataset_for_testing //converter:immutable_converter_main --config oss_macos
mkdir -p "$ROOT/Data"
cp -f bazel-bin/data_manager/oss/mozc.data "$ROOT/Data/genmai.data"
cp -f bazel-bin/data_manager/testing/mock_mozc.data "$ROOT/Data/mock_genmai.data"
chmod u+w "$ROOT/Data/genmai.data" "$ROOT/Data/mock_genmai.data"
echo "oracle: $ROOT/Vendor/mozc/src/bazel-bin/converter/converter_main"
