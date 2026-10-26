#!/bin/zsh
# Generates iOS/Genmai.xcodeproj (the iOS app and its keyboard extension) from iOS/project.yml with XcodeGen
# (brew install xcodegen). The app bundles the extended data set (Data/genmai_extended.data, Tools/build_data.sh
# --oss --extended) as build/ios/genmai.data, the name the engine looks for.
set -euo pipefail
cd "${0:A:h}/.."
[[ -f Data/genmai_extended.data ]] || {
  echo "Data/genmai_extended.data is missing; run Tools/build_data.sh --oss --extended" >&2
  exit 1
}
mkdir -p build/ios
cp -c Data/genmai_extended.data build/ios/genmai.data 2>/dev/null || cp Data/genmai_extended.data build/ios/genmai.data
# Mozc's notices + SudachiDict's (the extended data set's extra dictionary), as in Tools/make_ime_bundle.sh
awk -v extra=Tools/assets/credits_extended.html \
  '/<\/body><\/html>/ { while ((getline line < extra) > 0) print line } { print }' \
  Vendor/mozc/src/data/installer/credits_en.html >| build/ios/credits_en.html
xcodegen --spec iOS/project.yml
