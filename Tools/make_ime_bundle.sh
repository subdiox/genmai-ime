#!/bin/zsh
# Builds the macOS input method bundle build/Genmai.app from the SwiftPM products GenmaiIME and GenmaiTool.
#
# Layout (mirrors the C++ Mozc.app built by mac/BUILD.bazel, minus the separate server/renderer processes,
# which run in-process in the Swift port):
#   Genmai.app/Contents/Info.plist                 <- mac/Info.plist with the ${...} variables substituted
#   Genmai.app/Contents/MacOS/GenmaiIME              <- IMKServer + GenmaiImkInputController + candidate window
#                                                   (+ AI conversion hook; mlx-swift is linked statically)
#   Genmai.app/Contents/MacOS/mlx.metallib         <- MLX's Metal kernels for AI conversion (genmai), compiled
#                                                   with MLX's own safe-math flags (Tools/build_mlx_metallib.sh);
#                                                   MLX loads a metallib colocated with the executable. The genmai
#                                                   model itself is not bundled: Tools/prepare_genmai_model.sh
#                                                   writes it to ~/Library/Application Support/Genmai/model.
#   Genmai.app/Contents/Resources/*.tiff, *.icns   <- data/images/mac (input mode icons, product icon, logo)
#   Genmai.app/Contents/Resources/{English,Japanese}.lproj/InfoPlist.strings
#   Genmai.app/Contents/Resources/credits_en.html  <- data/installer/credits_en.html
#   Genmai.app/Contents/Resources/genmai.data        <- Data/genmai.data (the OSS data set, Tools/build_oracle.sh);
#                                                   OssDataManager finds it via Bundle.main (GenmaiTool.app
#                                                   finds it next to itself)
#   Genmai.app/Contents/Resources/GenmaiTool.app     <- config dialog, dictionary tool, word register, about, error
# Both bundles are ad-hoc code signed.
#
# Usage: Tools/make_ime_bundle.sh [--debug] [--build-data]
#   --build-data                 first (re)builds Data/genmai.data with Tools/build_data.sh --oss (Swift
#                                genmai-datagen; no Bazel needed).
#   UPSTREAM_SRC=<path to mozc/src>  defaults to Vendor/mozc/src (the git submodule).
#   DATA_SET=<path>             the data set to bundle, defaults to Data/genmai.data.
#   BUILD_PATH=<dir>             the SwiftPM build directory, defaults to .build-bundle.
# After assembling, `GenmaiIME --self_test` is run from the bundle (loads the bundled data set, converts a few
# sentences with a temporary user profile, with AI conversion off and, if the model is installed, on; nothing is
# registered or installed).
#
# Installing (manual; this script never installs anything):
#   cp -R build/Genmai.app ~/Library/Input\ Methods/
#   then log out and in (or run `~/Library/Input\ Methods/Genmai.app/Contents/MacOS/GenmaiIME --register_input_source`)
#   and add "Genmai" in System Settings > Keyboard > Input Sources.
set -euo pipefail

ROOT=${0:A:h:h}
UPSTREAM_SRC=${UPSTREAM_SRC:-$ROOT/Vendor/mozc/src}
CONFIGURATION=release
BUILD_DATA=0
for arg in "$@"; do
  case $arg in
    --debug) CONFIGURATION=debug ;;
    --build-data) BUILD_DATA=1 ;;
  esac
done
BUILD_PATH=${BUILD_PATH:-$ROOT/.build-bundle}
OUT=$ROOT/build/Genmai.app

# Bundle identity. Different from the C++ OSS build (org.mozc.inputmethod.Japanese) so both can coexist.
# Input method bundle identifiers must contain ".inputmethod.".
BUNDLE_ID=io.github.subdiox.genmai.inputmethod.Japanese
PRODUCT_NAME=Genmai
DISPLAY_NAME_EN="Genmai"
DISPLAY_NAME_JA="Genmai"
INPUT_MODE_ANNOTATION="Genmai"
VERSION=$(sed -n 's/.*kProductVersion = "\(.*\)"/\1/p' "$ROOT/Sources/GenmaiBase/VersionDef.swift")
SHORT_VERSION=$VERSION
COPYRIGHT="Copyright © 2026 subdiox. Based on Mozc, Copyright © Google LLC (BSD-3-Clause)."

DATA_SET=${DATA_SET:-$ROOT/Data/genmai.data}
if (( BUILD_DATA )); then
  echo "==> Tools/build_data.sh --oss (genmai-datagen)"
  "$ROOT/Tools/build_data.sh" --oss --output-dir "${DATA_SET:h}"
  [[ ${DATA_SET:t} == genmai.data ]] || mv -f "${DATA_SET:h}/genmai.data" "$DATA_SET"
fi
if [[ ! -f $DATA_SET ]]; then
  echo "error: data set not found at $DATA_SET (pass --build-data, run Tools/build_data.sh, or set DATA_SET)" >&2
  exit 1
fi

if [[ ! -f $UPSTREAM_SRC/mac/Info.plist ]]; then
  echo "error: Mozc sources not found at $UPSTREAM_SRC (set UPSTREAM_SRC or run git submodule update --init)" >&2
  exit 1
fi

echo "==> swift build -c $CONFIGURATION (GenmaiIME, GenmaiTool)"
swift build --package-path "$ROOT" --build-path "$BUILD_PATH" -c $CONFIGURATION --product GenmaiIME
swift build --package-path "$ROOT" --build-path "$BUILD_PATH" -c $CONFIGURATION --product GenmaiTool
BIN_DIR=$(swift build --package-path "$ROOT" --build-path "$BUILD_PATH" -c $CONFIGURATION --show-bin-path)

echo "==> mlx.metallib (Tools/build_mlx_metallib.sh, safe math)"
OUT="$BIN_DIR/mlx.metallib" "$ROOT/Tools/build_mlx_metallib.sh" "$BUILD_PATH" $CONFIGURATION

echo "==> assembling $OUT"
rm -rf "$OUT"
mkdir -p "$OUT/Contents/MacOS" "$OUT/Contents/Resources"

substitute() {
  sed -e "s|\${PRODUCT_NAME}|$PRODUCT_NAME|g" \
      -e "s|\${EXECUTABLE_NAME}|$2|g" \
      -e "s|\${PRODUCT_BUNDLE_IDENTIFIER}|$3|g" \
      -e "s|\${CURRENT_PROJECT_VERSION}|$VERSION|g" \
      -e "s|\${MARKETING_VERSION}|$SHORT_VERSION|g" \
      -e "s|\${GOOGLE_VERSIONINFO_FINDER}|$DISPLAY_NAME_EN $VERSION|g" \
      -e "s|\${GOOGLE_VERSIONINFO_ABOUT}|$COPYRIGHT|g" \
      -e "s|\${CF_BUNDLE_NAME_EN}|$DISPLAY_NAME_EN|g" \
      -e "s|\${CF_BUNDLE_NAME_JA}|$DISPLAY_NAME_JA|g" \
      -e "s|\${NS_HUMAN_READABLE_COPYRIGHT}|$COPYRIGHT|g" \
      -e "s|\${INPUT_MODE_ANNOTATION}|$INPUT_MODE_ANNOTATION|g" \
      "$1"
}

# --- Genmai.app (the input method) ---
substitute "$UPSTREAM_SRC/mac/Info.plist" GenmaiIME "$BUNDLE_ID" \
  | sed -e "s|MozcImkInputController|GenmaiImkInputController|g" >| "$OUT/Contents/Info.plist"
# The display name shown in the input menu.
/usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName $DISPLAY_NAME_EN" "$OUT/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleName $DISPLAY_NAME_EN" "$OUT/Contents/Info.plist"
plutil -lint "$OUT/Contents/Info.plist" >/dev/null
cp "$BIN_DIR/GenmaiIME" "$OUT/Contents/MacOS/GenmaiIME"
cp "$BIN_DIR/mlx.metallib" "$OUT/Contents/MacOS/mlx.metallib"
cp "$DATA_SET" "$OUT/Contents/Resources/genmai.data"

for image in "$UPSTREAM_SRC"/data/images/mac/*.tiff; do
  cp "$image" "$OUT/Contents/Resources/"
done
cp "$ROOT/Tools/assets/genmai.icns" "$OUT/Contents/Resources/product_icon.icns"
cp "$ROOT/Tools/assets/product_logo.png" "$OUT/Contents/Resources/product_logo.png"
[[ -f $UPSTREAM_SRC/data/installer/credits_en.html ]] && cp "$UPSTREAM_SRC/data/installer/credits_en.html" "$OUT/Contents/Resources/"
for lproj in English Japanese; do
  mkdir -p "$OUT/Contents/Resources/$lproj.lproj"
  # Convert to UTF-8 if the file is UTF-16 (CFBundle accepts both).
  if file "$UPSTREAM_SRC/mac/$lproj.lproj/InfoPlist.strings" | grep -q "UTF-16"; then
    iconv -f UTF-16 -t UTF-8 "$UPSTREAM_SRC/mac/$lproj.lproj/InfoPlist.strings" >| "$OUT/strings.tmp"
  else
    cp "$UPSTREAM_SRC/mac/$lproj.lproj/InfoPlist.strings" "$OUT/strings.tmp"
  fi
  substitute "$OUT/strings.tmp" GenmaiIME "$BUNDLE_ID" >| "$OUT/Contents/Resources/$lproj.lproj/InfoPlist.strings"
  rm "$OUT/strings.tmp"
  plutil -lint "$OUT/Contents/Resources/$lproj.lproj/InfoPlist.strings" >/dev/null
done

# --- GenmaiTool.app (the dialogs) ---
TOOL=$OUT/Contents/Resources/GenmaiTool.app
mkdir -p "$TOOL/Contents/MacOS" "$TOOL/Contents/Resources"
cp "$BIN_DIR/GenmaiTool" "$TOOL/Contents/MacOS/GenmaiTool"
cp "$ROOT/Tools/assets/genmai.icns" "$TOOL/Contents/Resources/product_icon.icns"
cp "$ROOT/Tools/assets/product_logo.png" "$TOOL/Contents/Resources/product_logo.png"
cat >| "$TOOL/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key>
	<string>Japanese</string>
	<key>CFBundleLocalizations</key>
	<array>
		<string>en</string>
		<string>ja</string>
	</array>
	<key>CFBundleExecutable</key>
	<string>GenmaiTool</string>
	<key>CFBundleIconFile</key>
	<string>product_icon.icns</string>
	<key>CFBundleIdentifier</key>
	<string>$BUNDLE_ID.Tool</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>CFBundleName</key>
	<string>$DISPLAY_NAME_EN</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleVersion</key>
	<string>$VERSION</string>
	<key>CFBundleShortVersionString</key>
	<string>$SHORT_VERSION</string>
	<key>NSHumanReadableCopyright</key>
	<string>$COPYRIGHT</string>
	<key>NSPrincipalClass</key>
	<string>NSApplication</string>
	<key>LSMinimumSystemVersion</key>
	<string>15.0</string>
</dict>
</plist>
PLIST
plutil -lint "$TOOL/Contents/Info.plist" >/dev/null

echo "==> codesign (ad hoc)"
codesign --force --sign - --timestamp=none "$TOOL"
# A non-Mach-O file in Contents/MacOS is a code subcomponent: sign it, or --verify --strict rejects the bundle.
codesign --force --sign - --timestamp=none "$OUT/Contents/MacOS/mlx.metallib"
codesign --force --sign - --timestamp=none "$OUT"
codesign --verify --strict --deep "$OUT"

echo "==> self test (bundled data set)"
GENMAI_DATA_FILE= "$OUT/Contents/MacOS/GenmaiIME" --self_test

echo "==> done: $OUT"
echo "Install manually: cp -R \"$OUT\" ~/Library/Input\\ Methods/ && log out and in."
