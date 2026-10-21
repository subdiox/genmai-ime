#!/bin/bash
# Generates the ImmutableConverter parity fixtures for Tests/Fixtures/oracle/conversion_inputs.txt:
#   Tests/Fixtures/oracle/lattice/NNNN.tsv  (converter/debug_util DumpNodes of the lattice, as Tools/oracle_lattice.sh)
#   Tests/Fixtures/oracle/lattice/segments.tsv (segments + top-5 candidates of ImmutableConverter::Convert)
# Same options as converter/immutable_converter_main.cc, OSS data set.
# The oracle tool (Tools/oracle_src/swift_parity) is copied into the Mozc tree temporarily, built with Bazel
# (--nocheck_visibility since converter targets are package-private), and removed again.
# usage: Tools/make_lattice_fixtures.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/Vendor/mozc/src"
OUT="$ROOT/Tests/Fixtures/oracle/lattice"
rm -rf "$SRC/swift_parity"
cp -R "$ROOT/Tools/oracle_src/swift_parity" "$SRC/swift_parity"
trap 'rm -rf "$SRC/swift_parity"' EXIT
(cd "$SRC" && "$ROOT/Tools/bin/bazelisk" build //swift_parity:lattice_fixture_main --config oss_macos --nocheck_visibility)
rm -rf "$OUT"
mkdir -p "$OUT/lattice"
(cd "$SRC" && bazel-bin/swift_parity/lattice_fixture_main --out_dir="$OUT" \
  < "$ROOT/Tests/Fixtures/oracle/conversion_inputs.txt" 2>/dev/null)
mv "$OUT/lattice"/*.tsv "$OUT/"
rmdir "$OUT/lattice"
echo "wrote $(ls "$OUT" | wc -l | tr -d ' ') files to $OUT ($(du -sh "$OUT" | cut -f1))"
