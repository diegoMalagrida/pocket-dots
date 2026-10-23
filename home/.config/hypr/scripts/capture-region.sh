#!/usr/bin/env bash
# Region selection OVER THE FROZEN SCREEN. Writes the PNG to stdout.
#
# THE PROBLEM: slurp steals focus, and everything that depends on focus closes
# before you get to shoot — the notch (Super+D), the launcher, a context menu,
# a dropdown. You captured the empty desktop exactly where the thing you wanted
# to photograph had been.
#
# THE FIX: hyprpicker lays a COPY of the screen over everything. From that
# instant on, whatever is underneath may close, move or die: what you select
# and what gets cropped is the photo, not the live desktop. The capture becomes
# independent of whatever you were doing.
#
# It also notes which notch panel was open and reopens it at the end (freezing
# sends focus elsewhere, and that cancels its grab), so taking a screenshot no
# longer closes the control centre on you.
#
# EXIT CODES, and the difference matters:
#   0  there is a photo on stdout
#   2  CANCELLED by hand (ESC or a click without dragging) -> stay quiet, you asked for it
#   1  REAL FAILURE (grim could not write: disk full, no permission...)
#
# Cancelling and failing used to both exit with 1, so the caller could not tell
# them apart and had to stay quiet every time. The case it swallowed was the
# worst one: disk full, no screenshot and not a word. With 2 kept separate, the
# caller only speaks up when there is something to report.
set -uo pipefail

freeze=""
panel=""

salir() {
    [ -n "$freeze" ] && kill "$freeze" 2>/dev/null
    freeze=""
    # Unfreeze before restoring: otherwise the panel would open underneath the
    # photo and you would not see it come back.
    [ -n "$panel" ] && qs ipc call notch restore "$panel" >/dev/null 2>&1
    return 0
}
trap salir EXIT INT TERM HUP

if command -v qs >/dev/null 2>&1; then
    panel=$(qs ipc call notch current 2>/dev/null | tr -d '"[:space:]')
fi

if command -v hyprpicker >/dev/null 2>&1; then
    # -r freezes the inactive monitors too; -z drops the picker's magnifier
    # (here we only want the freeze, not to pick a colour).
    # timeout is the safety net: if this script dies badly (SIGKILL, and the
    # trap never gets to run), hyprpicker would stay alive and you would see
    # the screen frozen forever. This way it unfreezes by itself after 3 minutes.
    timeout 180 hyprpicker -r -z >/dev/null 2>&1 &
    freeze=$!
    # The frozen layer has to be on top BEFORE slurp; otherwise the selection
    # is drawn underneath and you cannot see what you are cropping.
    sleep 0.2
fi

geom=$(slurp) || exit 2
[ -n "$geom" ] || exit 2

# grim's exit code goes out unchanged: 1 if it could not write the PNG.
grim -g "$geom" -
