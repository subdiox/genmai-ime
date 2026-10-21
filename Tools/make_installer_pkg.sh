#!/bin/zsh
# Builds the installer package build/Genmai.pkg (port of mozc/src/mac/build_package.py,
# mac/tweak_installer_files.py --productbuild and the installer rules of mac/BUILD.bazel, 3.35.6354).
#
# Payload (the C++ layout, with the Swift product name so that the C++ Mozc can stay installed):
#   /Library/Input Methods/Genmai.app                     <- build/Genmai.app (Tools/make_ime_bundle.sh)
#                                                              (C++: /Library/Input Methods/Mozc.app)
#   /Applications/Genmai/UninstallGenmai.app           <- Tools/make_uninstaller_bundle.sh
#                                                              (C++: /Applications/Mozc/UninstallGenmai.app)
#   /Applications/Genmai/.localized/{en,ja}.strings       <- Tools/installer/Resources/*.lproj/Localizable.strings
# Scripts (Tools/installer/*_template.sh with @@@...@@@ substituted, like build_tools/tweak_macinstaller_script.py):
#   preinstall   removes the previous /Applications/Genmai
#   postinstall  kills the running input method (GenmaiIME, which hosts the converter in-process; the C++ kills
#                GenmaiConverter) and runs `GenmaiIME --register_input_source` as the console user
# Not ported: /Library/LaunchAgents/org.mozc.inputmethod.Japanese.{Converter,Renderer}.plist. The C++ starts
# mozc_server and mozc_renderer through launchd; the Swift IME runs both in-process, so there is nothing to
# launch. The Qt ConfigDialog / DictionaryTool symlinks in /Applications/Mozc (TweakForProductbuild with Qt)
# are n/a as well: the dialogs live in GenmaiTool.app inside the input method bundle.
#
# As in build_package.py, the component plist from `pkgbuild --analyze` gets BundleOverwriteAction = "" so an
# upgrade overwrites the bundle in place and keeps the input source registration (google/mozc#1439). In
# addition BundleIsRelocatable is set to false: otherwise Installer would "upgrade" any other copy of a bundle
# with the same identifier it finds (e.g. build/Genmai.app or ~/Library/Input Methods/Genmai.app) instead of
# installing to /Library/Input Methods.
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
APPLICATIONS_DIR=/Applications/$PRODUCT_NAME
APP_PATH="/Library/Input Methods/$PRODUCT_NAME.app"
VERSION=$(sed -n 's/.*kProductVersion = "\(.*\)"/\1/p' "$ROOT/Sources/GenmaiBase/VersionDef.swift")

if [[ ${1:-} != --skip-build ]]; then
  "$ROOT/Tools/make_ime_bundle.sh"
  "$ROOT/Tools/make_uninstaller_bundle.sh"
fi
IME_BUNDLE=$BUILD_DIR/Genmai.app
UNINSTALLER_BUNDLE=$BUILD_DIR/Uninstall$PRODUCT_NAME.app
for bundle in "$IME_BUNDLE" "$UNINSTALLER_BUNDLE"; do
  if [[ ! -d $bundle ]]; then
    echo "error: $bundle not found (run without --skip-build)" >&2
    exit 1
  fi
  codesign --verify --strict --deep "$bundle"
done
IME_ID=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$IME_BUNDLE/Contents/Info.plist")
if [[ $IME_ID != io.github.subdiox.genmai.inputmethod.Japanese ]]; then
  echo "error: unexpected bundle identifier $IME_ID in $IME_BUNDLE" >&2
  exit 1
fi

echo "==> staging $WORK"
rm -rf "$WORK" "$OUT"
mkdir -p "$WORK/root/Library/Input Methods" "$WORK/root$APPLICATIONS_DIR/.localized" "$WORK/scripts"
ditto "$IME_BUNDLE" "$WORK/root$APP_PATH"
ditto "$UNINSTALLER_BUNDLE" "$WORK/root$APPLICATIONS_DIR/${UNINSTALLER_BUNDLE:t}"
for lang in en ja; do
  cp "$INSTALLER_SRC/Resources/$lang.lproj/Localizable.strings" "$WORK/root$APPLICATIONS_DIR/.localized/$lang.strings"
done
# The bundles keep their ad-hoc signatures (renaming Genmai.app does not invalidate them).
codesign --verify --strict --deep "$WORK/root$APP_PATH"

substitute() {
  sed -e "s|@@@GENMAI_APPLICATIONS_DIR@@@|$APPLICATIONS_DIR|g" \
      -e "s|@@@GENMAI_APP_PATH@@@|$APP_PATH|g" \
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

echo "==> productbuild"
/usr/bin/productbuild \
  --distribution "$WORK/distribution.xml" \
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
