#!/bin/sh
# Port of mozc/src/mac/installer/preflight_template.sh (3.35.6354): removes the previous applications folder
# (the uninstaller) before the new one is installed. /Applications/Mozc -> @@@GENMAI_APPLICATIONS_DIR@@@.

rm -Rf "@@@GENMAI_APPLICATIONS_DIR@@@"
/usr/bin/true
