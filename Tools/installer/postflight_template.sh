#!/bin/sh
# Port of mozc/src/mac/installer/postflight_template.sh (3.35.6354).
#
# The C++ kills the running GenmaiConverter (launched on demand by its LaunchAgent) so that the next key press
# starts the new server. In the Swift port the converter runs inside the input method process (GenmaiIME), so
# that process is killed instead; macOS relaunches the input method from the new bundle when it is next used.
# Then the input source is registered (and enabled / selected if it is not enabled yet) for the console user,
# like the C++ (`Mozc --register_input_source`; here GenmaiIME, see Sources/GenmaiIME/main.swift).
#
# Not in Mozc: a copy of Genmai.app in the console user's ~/Library/Input Methods (a development install, see
# Tools/make_ime_bundle.sh) has the same bundle identifier and would shadow the installed one; it is removed.
CONSOLE_USER=`/usr/bin/stat -f%Su /dev/console`
if [ -n "$CONSOLE_USER" ] && [ "$CONSOLE_USER" != "root" ]; then
  USER_HOME=`/usr/bin/dscl . -read "/Users/$CONSOLE_USER" NFSHomeDirectory 2>/dev/null | /usr/bin/awk '{print $2}'`
  if [ -n "$USER_HOME" ] && [ -d "$USER_HOME/Library/Input Methods/@@@GENMAI_APP_NAME@@@" ]; then
    /bin/rm -rf "$USER_HOME/Library/Input Methods/@@@GENMAI_APP_NAME@@@"
  fi
fi
/usr/bin/sudo -u $CONSOLE_USER /usr/bin/killall GenmaiIME > /dev/null 2>&1

if [ -n "$CONSOLE_USER" ] && [ "$CONSOLE_USER" != "root" ] && [ "$COMMAND_LINE_INSTALL" != "1" ]; then
  /usr/bin/sudo -u "$CONSOLE_USER" "@@@GENMAI_APP_PATH@@@/Contents/MacOS/GenmaiIME" --register_input_source > /dev/null 2>&1 || true
  # Not in Mozc: the welcome window (how to switch to Genmai, turning on AI conversion), in the user's GUI
  # session. It shows only once per user (a marker in the profile), so updates do not open it again.
  USER_ID=`/usr/bin/id -u "$CONSOLE_USER"`
  /bin/launchctl asuser "$USER_ID" /usr/bin/sudo -u "$CONSOLE_USER" /usr/bin/open -n \
    "@@@GENMAI_APP_PATH@@@/Contents/Resources/Genmai.app" --args --mode=welcome > /dev/null 2>&1 || true
fi

/usr/bin/true
