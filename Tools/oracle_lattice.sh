#!/bin/bash
# Runs the reference C++ immutable_converter_main (ImmutableConverter only, no rewriters / predictors) and prints
# the lattice dump (converter/debug_util DumpNodes) for one query.
# Build it first: (cd Vendor/mozc/src && ../../Tools/bin/bazelisk build //converter:immutable_converter_main --config oss_macos)
# usage: Tools/oracle_lattice.sh <hiragana query> [oss|mock]
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$(mktemp)"
cd "$ROOT/Vendor/mozc/src"
bazel-bin/converter/immutable_converter_main --query="$1" --dictionary="${2:-oss}" --output="$OUT" 2>/dev/null
cat "$OUT"; rm -f "$OUT"
