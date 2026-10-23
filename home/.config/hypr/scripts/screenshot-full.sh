#!/usr/bin/env bash
# Instant FULL screenshot with grim.
# grim does not steal focus → it also captures overlays and open menus.
# Saves, copies to the clipboard and notifies (the notification can be clicked
# to edit).
set -uo pipefail
#
# The notifications go through tr_() so they follow the rice's language (lang.sh
# reads the same language.conf as hyprlock, so the lock screen and these
# notifications cannot drift apart). If lang.sh were missing, the `||` leaves a
# tr_ that returns the Spanish: never any extra text, and never a blank one.
. "$HOME/.config/hypr/scripts/lang.sh" 2>/dev/null || tr_() { printf '%s' "$1"; }


dir="$HOME/Pictures/screenshots"
mkdir -p "$dir"
file="$dir/screenshot-$(date +%Y%m%d_%H%M%S).png"

# With a single screen this changes nothing; with two, a bare `grim` returns
# BOTH stuck together in one very long image, which is almost never what you
# wanted when you pressed Print Screen. It captures the screen that has the
# focus, which is where you were looking. If hyprctl or jq fail, `mon` stays
# empty and grim captures everything as before: one capture too many, maybe;
# no capture at all, never.
mon=$(hyprctl monitors -j 2>/dev/null | jq -r 'first(.[] | select(.focused) | .name) // empty' 2>/dev/null)
sel=()
[ -n "$mon" ] && sel=(-o "$mon")

if grim "${sel[@]}" "$file"; then
    wl-copy < "$file"
    "$HOME/.config/hypr/scripts/notify-shot.sh" "$file" &
else
    rm -f "$file"
    notify-send -u critical -a "$(tr_ Captura Screenshot)" "$(tr_ 'Captura de pantalla' 'Screenshot')" "$(tr_ 'Error al capturar' 'Capture failed')"
fi
