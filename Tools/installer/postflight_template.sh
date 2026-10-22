#!/bin/sh
# Port of mozc/src/mac/installer/postflight_template.sh (3.35.6354).
#
# The C++ kills the running GenmaiConverter (launched on demand by its LaunchAgent) so that the next key press
# starts the new server. In the Swift port the converter runs inside the input method process (GenmaiIME), so
# that process is killed instead; macOS relaunches the input method from the new bundle when it is next used.
# Then the input source is registered (and enabled / selected if it is not enabled yet) for the console user,
# like the C++ (`Mozc --register_input_source`; here GenmaiIME, see Sources/GenmaiIME/main.swift).
#
# Not in Mozc: the package installs either for all users (/Library/Input Methods, run as root) or only for the
# installing user (~/Library/Input Methods, the "Install for me only" destination of Installer, run as that user
# without administrator rights). $2 is the destination: "/" or the user's home folder. For all users, a copy in
# the console user's ~/Library/Input Methods (an earlier per-user install or a development copy) has the same
# bundle identifier and would shadow the installed one: it is removed. Then the welcome window opens once per
# user (a marker in the profile, so updates do not open it again).
DESTINATION=${2%/}
APP="$DESTINATION/Library/Input Methods/@@@GENMAI_APP_NAME@@@"
CONSOLE_USER=`/usr/bin/stat -f%Su /dev/console`

# as_user <command...>: runs a command as the console user (directly when this script runs as that user).
as_user() {
  if [ "`/usr/bin/id -u`" = "0" ]; then
    /usr/bin/sudo -u "$CONSOLE_USER" "$@"
  else
    "$@"
  fi
}

if [ -z "$DESTINATION" ] && [ -n "$CONSOLE_USER" ] && [ "$CONSOLE_USER" != "root" ]; then
  USER_HOME=`/usr/bin/dscl . -read "/Users/$CONSOLE_USER" NFSHomeDirectory 2>/dev/null | /usr/bin/awk '{print $2}'`
  if [ -n "$USER_HOME" ] && [ -d "$USER_HOME/Library/Input Methods/@@@GENMAI_APP_NAME@@@" ]; then
    /bin/rm -rf "$USER_HOME/Library/Input Methods/@@@GENMAI_APP_NAME@@@"
  fi
fi
as_user /usr/bin/killall GenmaiIME > /dev/null 2>&1

if [ -n "$CONSOLE_USER" ] && [ "$CONSOLE_USER" != "root" ] && [ "$COMMAND_LINE_INSTALL" != "1" ]; then
  as_user "$APP/Contents/MacOS/GenmaiIME" --register_input_source > /dev/null 2>&1 || true
  if [ "`/usr/bin/id -u`" = "0" ]; then
    USER_ID=`/usr/bin/id -u "$CONSOLE_USER"`
    /bin/launchctl asuser "$USER_ID" /usr/bin/sudo -u "$CONSOLE_USER" /usr/bin/open -n \
      "$APP/Contents/Resources/Genmai.app" --args --mode=welcome > /dev/null 2>&1 || true
  else
    /usr/bin/open -n "$APP/Contents/Resources/Genmai.app" --args --mode=welcome > /dev/null 2>&1 || true
  fi
fi

/usr/bin/true
