#!/bin/zsh
# Builds the uninstaller app build/UninstallGenmai.app from the SwiftPM product GenmaiUninstaller.
#
# Mirrors the uninstaller_macos rule of mac/BUILD.bazel (bundle UninstallGenmai.app, infoplist
# mac/Uninstaller/Info.plist, strings {English,Japanese}.lproj/InfoPlist.strings, icon product_icon.icns).
# The xib dialogs are SwiftUI views compiled into the executable, so there is no Dialogs.nib and
# NSMainNibFile is dropped from the Info.plist. The bundle is ad-hoc code signed.
#
# Usage: Tools/make_uninstaller_bundle.sh [--debug]
#   UPSTREAM_SRC=<path to mozc/src>  defaults to Vendor/mozc/src (the git submodule).
#   BUILD_PATH=<dir>             the SwiftPM build directory, defaults to .build-bundle.
# Nothing is installed or run; Tools/make_installer_pkg.sh puts the bundle in /Applications/Genmai.
set -euo pipefail

ROOT=${0:A:h:h}
UPSTREAM_SRC=${UPSTREAM_SRC:-$ROOT/Vendor/mozc/src}
CONFIGURATION=release
[[ ${1:-} == --debug ]] && CONFIGURATION=debug
BUILD_PATH=${BUILD_PATH:-$ROOT/.build-bundle}

# Keep in sync with Tools/make_ime_bundle.sh and UninstallerLayout (Sources/GenmaiUninstaller/Uninstaller.swift).
PRODUCT_NAME=Genmai
BUNDLE_ID=io.github.subdiox.genmai.inputmethod.Japanese.Uninstaller
APP_NAME=Uninstall$PRODUCT_NAME
OUT=$ROOT/build/$APP_NAME.app
VERSION=$(sed -n 's/.*kProductVersion = "\(.*\)"/\1/p' "$ROOT/Sources/GenmaiBase/VersionDef.swift")
SHORT_VERSION=$VERSION

if [[ ! -f $UPSTREAM_SRC/mac/Uninstaller/Info.plist ]]; then
  echo "error: Mozc sources not found at $UPSTREAM_SRC (set UPSTREAM_SRC or run git submodule update --init)" >&2
  exit 1
fi

echo "==> swift build -c $CONFIGURATION (GenmaiUninstaller)"
swift build --package-path "$ROOT" --build-path "$BUILD_PATH" -c $CONFIGURATION --product GenmaiUninstaller
BIN_DIR=$(swift build --package-path "$ROOT" --build-path "$BUILD_PATH" -c $CONFIGURATION --show-bin-path)

echo "==> assembling $OUT"
rm -rf "$OUT"
mkdir -p "$OUT/Contents/MacOS" "$OUT/Contents/Resources"

sed -e "s|\${PRODUCT_NAME}|$APP_NAME|g" \
    -e "s|\${EXECUTABLE_NAME}|GenmaiUninstaller|g" \
    -e "s|\${PRODUCT_BUNDLE_IDENTIFIER}|$BUNDLE_ID|g" \
    -e "s|\${CURRENT_PROJECT_VERSION}|$VERSION|g" \
    "$UPSTREAM_SRC/mac/Uninstaller/Info.plist" >| "$OUT/Contents/Info.plist"
PLIST=$OUT/Contents/Info.plist
/usr/libexec/PlistBuddy -c "Delete :NSMainNibFile" "$PLIST"
/usr/libexec/PlistBuddy -c "Add :CFBundleName string $APP_NAME" "$PLIST"
/usr/libexec/PlistBuddy -c "Add :CFBundleShortVersionString string $SHORT_VERSION" "$PLIST"
/usr/libexec/PlistBuddy -c "Add :LSMinimumSystemVersion string 15.0" "$PLIST"
/usr/libexec/PlistBuddy -c "Add :CFBundleLocalizations array" "$PLIST"
/usr/libexec/PlistBuddy -c "Add :CFBundleLocalizations:0 string en" "$PLIST"
/usr/libexec/PlistBuddy -c "Add :CFBundleLocalizations:1 string ja" "$PLIST"
plutil -lint "$PLIST" >/dev/null

cp "$BIN_DIR/GenmaiUninstaller" "$OUT/Contents/MacOS/GenmaiUninstaller"
cp "$ROOT/Tools/assets/genmai.icns" "$OUT/Contents/Resources/product_icon.icns"
for lproj in English Japanese; do
  mkdir -p "$OUT/Contents/Resources/$lproj.lproj"
  cp "$UPSTREAM_SRC/mac/Uninstaller/$lproj.lproj/InfoPlist.strings" "$OUT/Contents/Resources/$lproj.lproj/"
  plutil -lint "$OUT/Contents/Resources/$lproj.lproj/InfoPlist.strings" >/dev/null
done

echo "==> codesign (ad hoc)"
codesign --force --sign - --timestamp=none "$OUT"
codesign --verify --strict "$OUT"

echo "==> done: $OUT"
