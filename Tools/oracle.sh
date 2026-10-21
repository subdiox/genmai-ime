#!/bin/bash
# Runs the reference C++ converter_main with the OSS data set. Commands are read from stdin, one per line,
# e.g. "s きょうははやめにかえります" (start conversion), "p ..." (prediction). See converter_main.cc.
# usage: Tools/oracle.sh [converter_main flags...] < commands.txt
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT/Vendor/mozc/src"
exec bazel-bin/converter/converter_main --engine_data_path="$ROOT/Data/genmai.data" "$@" 2>/dev/null
