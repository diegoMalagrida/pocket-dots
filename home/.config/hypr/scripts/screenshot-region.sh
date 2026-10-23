#!/usr/bin/env bash
# Region capture: freezes the screen, crops, saves and copies.
# The freeze (capture-region.sh) is what lets you shoot menus, the notch or
# anything else that closes when it loses focus.
set -uo pipefail
#
# Notifications go through tr_() so they follow the rice's language (lang.sh
# reads the same language.conf as hyprlock, so the lock screen and these
# notifications cannot drift apart). If lang.sh were missing, the `||` leaves
# a tr_ that returns the Spanish: never extra text, and never, ever blank text.
. "$HOME/.config/hypr/scripts/lang.sh" 2>/dev/null || tr_() { printf '%s' "$1"; }


dir="$HOME/Pictures/screenshots"
mkdir -p "$dir"
file="$dir/screenshot-$(date +%Y%m%d_%H%M%S).png"

"$HOME/.config/hypr/scripts/capture-region.sh" > "$file"
rc=$?

if [ "$rc" -eq 0 ] && [ -s "$file" ]; then
    wl-copy < "$file"
    # In the background: the notification sits waiting in case you press "Editar" (Edit).
    "$HOME/.config/hypr/scripts/notify-shot.sh" "$file" &
else
    rm -f "$file"   # do not leave a 0-byte PNG in Pictures
    # 2 is "you cancelled it": not a word, naturally. Any other code is a real
    # failure -the typical one is a full disk- and it used to be swallowed by
    # the same `else` as the cancellation, so you were left with no screenshot
    # and no idea why. This is what screenshot-full.sh already did.
    if [ "$rc" -ne 2 ]; then
        notify-send -u critical -a "$(tr_ Captura Screenshot)" \
            "$(tr_ 'Captura de pantalla' 'Screenshot')" \
            "$(tr_ 'Error al capturar' 'Capture failed')"
    fi
fi
