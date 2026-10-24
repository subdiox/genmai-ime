#!/bin/bash
# Builds the data sets Data/genmai.data (OSS) and Data/mock_genmai.data (testing) with the Swift
# generator genmai-datagen -- no Bazel, Python or C++ needed.  The output is byte-identical to the Bazel targets
# //data_manager/oss:mozc_dataset_for_oss and //data_manager/testing:mozc_dataset_for_testing.
#
# Inputs: Vendor/mozc/src/data (git submodule), Vendor/mozc/src/version.bzl, and three external files of
# Mozc's MODULE.bazel:
#   @ja_usage_dict//:usage_dict.txt     downloaded (pinned tag, sha256-checked) into Data/external/
#   @zip_code_ken_all//:KEN_ALL.CSV     downloaded (pinned revision, sha256-checked) into Data/external/
#   @zip_code_jigyosyo//:JIGYOSYO.CSV   (only the OSS set needs the zip code data)
#
# --extended also builds Data/genmai_extended.data, the data set the input method ships (not part of Mozc): the
# OSS set plus the proper nouns of Japan Post's KEN_ALL.CSV and SudachiDict (small_lex / core_lex, Apache-2.0,
# pinned, downloaded into Data/external/) that the OSS dictionary lacks (genmai-datagen extra-dictionary,
# GenExtraDictionary.swift). genmai.data stays byte-identical to Mozc's (the parity tests use it).
#
# Usage: Tools/build_data.sh [--oss | --mock] [--extended] [--output-dir DIR] [--verify] [--debug]
#   --oss / --mock     build only one of the two sets (default: both)
#   --extended         also build genmai_extended.data (implies the OSS inputs)
#   --output-dir DIR   where genmai.data / mock_genmai.data are written (default: Data/)
#   --verify           compare the outputs with the Bazel outputs in Vendor/mozc/src/bazel-bin, if present
#   BUILD_PATH=<dir>   SwiftPM build directory (default: .build-datagen)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
UPSTREAM_SRC=${UPSTREAM_SRC:-$ROOT/Vendor/mozc/src}
BUILD_PATH=${BUILD_PATH:-$ROOT/.build-datagen}
OUT_DIR=$ROOT/Data
CONFIGURATION=release
SETS="oss mock"
VERIFY=0
EXTENDED=0
while [ $# -gt 0 ]; do
  case $1 in
    --oss) SETS=oss ;;
    --mock) SETS=mock ;;
    --output-dir) OUT_DIR=$2; shift ;;
    --verify) VERIFY=1 ;;
    --extended) EXTENDED=1 ;;
    --debug) CONFIGURATION=debug ;;
    *) echo "usage: $0 [--oss | --mock] [--extended] [--output-dir DIR] [--verify] [--debug]" >&2; exit 2 ;;
  esac
  shift
done

if [ $EXTENDED = 1 ]; then
  case " $SETS " in *" oss "*) ;; *) SETS="$SETS oss" ;; esac
fi

if [ ! -f "$UPSTREAM_SRC/data/dictionary_oss/id.def" ]; then
  echo "error: Mozc sources not found at $UPSTREAM_SRC (run git submodule update --init)" >&2
  exit 1
fi

USAGE_DICT=$ROOT/Data/external/usage_dict.txt
EXTERNAL=$ROOT/Data/external
mkdir -p "$EXTERNAL" "$OUT_DIR"

# fetch NAME URL SHA256 MEMBER: downloads a zip once and extracts MEMBER into Data/external.
fetch() {
  local name=$1 url=$2 sha=$3 member=$4
  [ -f "$EXTERNAL/$member" ] && return
  echo "==> downloading $name"
  local tmp
  tmp=$(mktemp -d)
  curl -sSfL -o "$tmp/$name.zip" "$url"
  echo "$sha  $tmp/$name.zip" | shasum -a 256 -c - >/dev/null
  unzip -q -o "$tmp/$name.zip" "$member" -d "$tmp"
  mv "$tmp/$member" "$EXTERNAL/$member"
  rm -rf "$tmp"
}

# Pinned in Vendor/mozc/src/MODULE.bazel (japanese-usage-dictionary 2025-01-25, BSD-2-Clause).
USAGE_TAG=2025-01-25
if [ ! -f "$USAGE_DICT" ]; then
  echo "==> downloading ja_usage_dict"
  tmp=$(mktemp -d)
  curl -sSfL -o "$tmp/usage.zip" \
    "https://github.com/hiroyuki-komatsu/japanese-usage-dictionary/archive/refs/tags/$USAGE_TAG.zip"
  echo "140f24f71f7d78d5eb5b93a9c079f44f23728dca5ab16bf857fe8a3fa1bf20ed  $tmp/usage.zip" | shasum -a 256 -c - >/dev/null
  unzip -q -p "$tmp/usage.zip" "japanese-usage-dictionary-$USAGE_TAG/usage_dict.txt" >| "$USAGE_DICT"
  rm -rf "$tmp"
fi

case " $SETS " in
  *" oss "*)
    # Pinned in Vendor/mozc/src/MODULE.bazel (japanpost_zipcode 621d059, 2026-04-03).
    REV=621d059fbcbfae17bfca15b439692bae934268c3
    fetch ken_all "https://github.com/hiroyuki-komatsu/japanpost_zipcode/raw/$REV/ken_all.zip" \
      3adc97d8e19e1168a6cdcb2fce759d0e9e613a9a3b630cc180aecfd56ae81eaf KEN_ALL.CSV
    fetch jigyosyo "https://github.com/hiroyuki-komatsu/japanpost_zipcode/raw/$REV/jigyosyo.zip" \
      14be1030f607c5f819f2f45a485e89511907bdd1d62e7fb1931b6e48a3431c3a JIGYOSYO.CSV
    ;;
esac
if [ $EXTENDED = 1 ]; then
  # SudachiDict sources (v1 raw lexicons, release 20261015, Apache-2.0).
  SUDACHI=http://sudachi.s3-website-ap-northeast-1.amazonaws.com/sudachidict-raw/v1/20261015
  fetch sudachi_small "$SUDACHI/small_lex.zip" \
    981b78cdc532ce058b34c76cd9acd3c9a6c771cc0ce528d7de92424b21172125 small_lex.csv
  fetch sudachi_core "$SUDACHI/core_lex.zip" \
    e9ac06222f0ce401a0fef9b129e61e93d59e3ff395a1b037f498962ee5b8ad8b core_lex.csv
fi

echo "==> swift build -c $CONFIGURATION (genmai-datagen)"
swift build --package-path "$ROOT" --build-path "$BUILD_PATH" -c $CONFIGURATION --product genmai-datagen
DATAGEN=$(swift build --package-path "$ROOT" --build-path "$BUILD_PATH" -c $CONFIGURATION --show-bin-path)/genmai-datagen

for set in $SETS; do
  if [ "$set" = oss ]; then
    out=$OUT_DIR/genmai.data
    ref=$UPSTREAM_SRC/bazel-bin/data_manager/oss/mozc.data
    work=$(mktemp -d)
    extra=(--zip-code-ken-all "$EXTERNAL/KEN_ALL.CSV" --zip-code-jigyosyo "$EXTERNAL/JIGYOSYO.CSV" --work-dir "$work")
  else
    out=$OUT_DIR/mock_genmai.data
    ref=$UPSTREAM_SRC/bazel-bin/data_manager/testing/mock_mozc.data
    work=
    extra=()
  fi
  compare=()
  if [ $VERIFY = 1 ]; then
    if [ -f "$ref" ]; then compare=(--compare "$ref"); else echo "note: $ref not found; not verifying"; fi
  fi
  echo "==> genmai-datagen build --set $set"
  "$DATAGEN" build --set "$set" --src-root "$UPSTREAM_SRC" --usage-dict "$USAGE_DICT" --output "$out.tmp" \
    --timings ${extra[@]+"${extra[@]}"} ${compare[@]+"${compare[@]}"}
  mv -f "$out.tmp" "$out"
  if [ "$set" = oss ] && [ $EXTENDED = 1 ]; then
    # the extended set reuses the OSS set's preprocessed dictionaries (in $work)
    echo "==> genmai-datagen extra-dictionary"
    "$DATAGEN" extra-dictionary --src-root "$UPSTREAM_SRC" --zip-code-ken-all "$EXTERNAL/KEN_ALL.CSV" \
      --sudachi-small "$EXTERNAL/small_lex.csv" --sudachi-core "$EXTERNAL/core_lex.csv" \
      --output "$work/extra_dictionary.txt"
    echo "==> genmai-datagen build --set oss --extra-dictionary (genmai_extended.data)"
    "$DATAGEN" build --set oss --src-root "$UPSTREAM_SRC" --usage-dict "$USAGE_DICT" \
      --aux-dictionary "$work/aux_dictionary.txt" --filtered-dictionary "$work/dictionary.txt" \
      --extra-dictionary "$work/extra_dictionary.txt" --output "$OUT_DIR/genmai_extended.data.tmp" --timings
    mv -f "$OUT_DIR/genmai_extended.data.tmp" "$OUT_DIR/genmai_extended.data"
  fi
  [ -n "$work" ] && rm -rf "$work"
done
echo "==> done: $(for s in $SETS; do [ $s = oss ] && printf '%s ' "$OUT_DIR/genmai.data" || printf '%s ' "$OUT_DIR/mock_genmai.data"; done)$([ $EXTENDED = 1 ] && echo "$OUT_DIR/genmai_extended.data")"
