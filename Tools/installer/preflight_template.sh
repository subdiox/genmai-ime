#!/bin/sh
# Port of mozc/src/mac/installer/preflight_template.sh (3.35.6354): removes the applications folder with the
# uninstaller (/Applications/Mozc -> @@@GENMAI_APPLICATIONS_DIR@@@). Genmai 0.1.0 installed it there; later
# versions keep the uninstaller inside the input method bundle, so the folder only has to go.

rm -Rf "@@@GENMAI_APPLICATIONS_DIR@@@"
/usr/bin/true
