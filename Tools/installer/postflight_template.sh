#!/bin/sh
# Port of mozc/src/mac/installer/postflight_template.sh (3.35.6354).
#
# The C++ kills the running GenmaiConverter (launched on demand by its LaunchAgent) so that the next key press
# starts the new server. In the Swift port the converter runs inside the input method process (GenmaiIME), so
# that process is killed instead; macOS relaunches the input method from the new bundle when it is next used.
# Then the input source is registered (and enabled / selected if it is not enabled yet) for the console user,
# like the C++ (`Mozc --register_input_source`; here GenmaiIME, see Sources/GenmaiIME/main.swift).
CONSOLE_USER=`/usr/bin/stat -f%Su /dev/console`
/usr/bin/sudo -u $CONSOLE_USER /usr/bin/killall GenmaiIME > /dev/null 2>&1

if [ -n "$CONSOLE_USER" ] && [ "$CONSOLE_USER" != "root" ] && [ "$COMMAND_LINE_INSTALL" != "1" ]; then
  /usr/bin/sudo -u "$CONSOLE_USER" "@@@GENMAI_APP_PATH@@@/Contents/MacOS/GenmaiIME" --register_input_source > /dev/null 2>&1 || true
fi

/usr/bin/true
