#!/bin/zsh
# Builds the installer package build/Genmai.pkg (port of mozc/src/mac/build_package.py,
# mac/tweak_installer_files.py --productbuild and the installer rules of mac/BUILD.bazel, 3.35.6354).
#
# Payload (the C++ layout, with the Swift product name so that the C++ Mozc can stay installed):
#   /Library/Input Methods/Genmai.app                     <- build/Genmai.app (Tools/make_ime_bundle.sh)
#                                                              (C++: /Library/Input Methods/Mozc.app)
# The uninstaller is inside Genmai.app (Contents/Resources/UninstallGenmai.app, opened from the settings); unlike
# the C++ (/Applications/Mozc/UninstallMozc.app) nothing is installed into /Applications.
# Scripts (Tools/installer/*_template.sh with @@@...@@@ substituted, like build_tools/tweak_macinstaller_script.py):
#   preinstall   removes /Applications/Genmai, where 0.1.0 put the uninstaller
#   postinstall  removes a development copy in the console user's ~/Library/Input Methods (same bundle id), kills
#                the running input method (GenmaiIME, which hosts the converter in-process; the C++ kills
#                GenmaiConverter) and runs `GenmaiIME --register_input_source` as the console user. No logout is
#                required (distribution.xml); the input method restarts with the new bundle when next used.
# Not ported: /Library/LaunchAgents/org.mozc.inputmethod.Japanese.{Converter,Renderer}.plist. The C++ starts
# mozc_server and mozc_renderer through launchd; the Swift IME runs both in-process, so there is nothing to
# launch. The Qt ConfigDialog / DictionaryTool symlinks in /Applications/Mozc (TweakForProductbuild with Qt)
# are n/a as well: the dialogs live in the tool app inside the input method bundle.
#
# As in build_package.py, the component plist from `pkgbuild --analyze` gets BundleOverwriteAction = "" so an
# upgrade overwrites the bundle in place and keeps the input source registration (google/mozc#1439). In
# addition BundleIsRelocatable is set to false: otherwise Installer would "upgrade" any other copy of a bundle
# with the same identifier it finds (e.g. build/Genmai.app or ~/Library/Input Methods/Genmai.app) instead of
# installing to /Library/Input Methods.
#
# Installer UI (not in Mozc): productbuild --resources gets Tools/installer/Resources ({en,ja}.lproj welcome /
# conclusion pages, referenced by distribution.xml) plus background.tiff, the app icon (128 pt, 1x and 2x) made
# here from Tools/assets/genmai.icns and shown at the bottom left of the Installer window in both appearances.
#
# Signing: the app bundles are ad-hoc signed by the bundle scripts. The .pkg itself is unsigned unless
# PKG_SIGN_IDENTITY names a "Developer ID Installer" identity (then productsign is run, like build_package.py
# with --codesign_identity); an ad-hoc signature does not exist for packages. An unsigned package that was not
# downloaded (no quarantine attribute) installs with `sudo installer -pkg build/Genmai.pkg -target /` or by
# opening it; a downloaded one needs right click > Open. This script never installs anything.
#
# Usage: Tools/make_installer_pkg.sh [--skip-build]
#   --skip-build   reuse build/Genmai.app and build/UninstallGenmai.app instead of running the bundle scripts.
#   PKG_SIGN_IDENTITY=<identity>  sign the package with productsign.
set -euo pipefail

ROOT=${0:A:h:h}
INSTALLER_SRC=$ROOT/Tools/installer
BUILD_DIR=$ROOT/build
WORK=$BUILD_DIR/pkg
OUT=$BUILD_DIR/Genmai.pkg

# Keep in sync with UninstallerLayout (Sources/GenmaiUninstaller/Uninstaller.swift).
PRODUCT_NAME=Genmai
IDENTIFIER=io.github.subdiox.genmai.pkg
PKG_NAME=$PRODUCT_NAME.pkg  # configured in distribution.xml
APPLICATIONS_DIR=/Applications/$PRODUCT_NAME  # the uninstaller's folder of 0.1.0, removed by preinstall
APP_PATH="/Library/Input Methods/$PRODUCT_NAME.app"
VERSION=$(sed -n 's/.*kProductVersion = "\(.*\)"/\1/p' "$ROOT/Sources/GenmaiBase/VersionDef.swift")

if [[ ${1:-} != --skip-build ]]; then
  "$ROOT/Tools/make_ime_bundle.sh"
fi
IME_BUNDLE=$BUILD_DIR/Genmai.app
if [[ ! -d $IME_BUNDLE/Contents/Resources/Uninstall$PRODUCT_NAME.app ]]; then
  echo "error: $IME_BUNDLE (with the uninstaller) not found (run without --skip-build)" >&2
  exit 1
fi
codesign --verify --strict --deep "$IME_BUNDLE"
IME_ID=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$IME_BUNDLE/Contents/Info.plist")
if [[ $IME_ID != io.github.subdiox.genmai.inputmethod.Japanese ]]; then
  echo "error: unexpected bundle identifier $IME_ID in $IME_BUNDLE" >&2
  exit 1
fi

echo "==> staging $WORK"
rm -rf "$WORK" "$OUT"
mkdir -p "$WORK/root/Library/Input Methods" "$WORK/scripts"
ditto "$IME_BUNDLE" "$WORK/root$APP_PATH"
# The bundles keep their ad-hoc signatures (renaming Genmai.app does not invalidate them).
codesign --verify --strict --deep "$WORK/root$APP_PATH"

substitute() {
  sed -e "s|@@@GENMAI_APPLICATIONS_DIR@@@|$APPLICATIONS_DIR|g" \
      -e "s|@@@GENMAI_APP_PATH@@@|$APP_PATH|g" \
      -e "s|@@@GENMAI_APP_NAME@@@|${APP_PATH:t}|g" \
      -e "s|@@@GENMAI_PACKAGE_NAME@@@|$PKG_NAME|g" \
      -e "s|@@@GENMAI_VERSION@@@|$VERSION|g" \
      -e "s|@@@HOST_ARCHITECTURES@@@|$HOST_ARCHITECTURES|g" \
      "$1"
}
# hostArchitectures: the architectures the input method binary was built for (lipo: "arm64 x86_64").
HOST_ARCHITECTURES=$(lipo -archs "$IME_BUNDLE/Contents/MacOS/GenmaiIME" | tr ' ' ',')
substitute "$INSTALLER_SRC/preflight_template.sh" >| "$WORK/scripts/preinstall"
substitute "$INSTALLER_SRC/postflight_template.sh" >| "$WORK/scripts/postinstall"
chmod 755 "$WORK/scripts/preinstall" "$WORK/scripts/postinstall"
substitute "$INSTALLER_SRC/distribution.xml" >| "$WORK/distribution.xml"
if grep -q '@@@' "$WORK/scripts/preinstall" "$WORK/scripts/postinstall" "$WORK/distribution.xml"; then
  echo "error: a @@@...@@@ placeholder was not replaced" >&2
  exit 1
fi
sh -n "$WORK/scripts/preinstall"
sh -n "$WORK/scripts/postinstall"
xmllint --noout "$WORK/distribution.xml"

echo "==> pkgbuild"
COMPONENT_PLIST=$WORK/component.plist
/usr/bin/pkgbuild --analyze --root "$WORK/root" "$COMPONENT_PLIST" >/dev/null
count=0
while /usr/libexec/PlistBuddy -c "Print :$count" "$COMPONENT_PLIST" >/dev/null 2>&1; do
  /usr/libexec/PlistBuddy -c "Set :$count:BundleOverwriteAction ''" "$COMPONENT_PLIST"
  # Recent pkgbuild versions omit the key when it is false; Delete + Add works either way.
  /usr/libexec/PlistBuddy -c "Delete :$count:BundleIsRelocatable" "$COMPONENT_PLIST" >/dev/null 2>&1 || true
  /usr/libexec/PlistBuddy -c "Add :$count:BundleIsRelocatable bool false" "$COMPONENT_PLIST"
  count=$((count + 1))
done
/usr/bin/pkgbuild \
  --root "$WORK/root" \
  --component-plist "$COMPONENT_PLIST" \
  --identifier "$IDENTIFIER" \
  --version "$VERSION" \
  --install-location / \
  --scripts "$WORK/scripts" \
  "$WORK/$PKG_NAME"

echo "==> installer resources"
RESOURCES=$WORK/resources
ICONSET=$WORK/genmai.iconset
ditto "$INSTALLER_SRC/Resources" "$RESOURCES"
iconutil --convert iconset --output "$ICONSET" "$ROOT/Tools/assets/genmai.icns"
tiffutil -cathidpicheck "$ICONSET/icon_128x128.png" "$ICONSET/icon_128x128@2x.png" \
  -out "$RESOURCES/background.tiff" >/dev/null 2>&1
for page in "$RESOURCES"/*.lproj/*.html; do
  xmllint --html --noout "$page"
done

echo "==> productbuild"
/usr/bin/productbuild \
  --distribution "$WORK/distribution.xml" \
  --resources "$RESOURCES" \
  --package-path "$WORK" \
  "$WORK/package.pkg"

if [[ -n ${PKG_SIGN_IDENTITY:-} ]]; then
  echo "==> productsign ($PKG_SIGN_IDENTITY)"
  /usr/bin/productsign --sign "$PKG_SIGN_IDENTITY" "$WORK/package.pkg" "$OUT"
else
  cp "$WORK/package.pkg" "$OUT"
fi

echo "==> done: $OUT"
pkgutil --check-signature "$OUT" || true
echo "Inspect: pkgutil --expand \"$OUT\" /tmp/x; pkgutil --payload-files \"$WORK/$PKG_NAME\""
