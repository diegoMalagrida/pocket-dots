#!/usr/bin/env bash
# Eyedropper: picks a colour from the screen and copies the hex.
#
# The notifications go through tr_() so they follow the rice's language (lang.sh
# reads the same language.conf as hyprlock, so the lock screen and these
# notifications cannot drift apart). If lang.sh were missing, the `||` leaves a
# tr_ that returns the Spanish: never any extra text, and never a blank one.
. "$HOME/.config/hypr/scripts/lang.sh" 2>/dev/null || tr_() { printf '%s' "$1"; }

col=$(hyprpicker -a -f hex) || exit 0
[ -n "$col" ] || exit 0
# The notice carries the colour itself as its icon and says who sends it:
# without -a and -i it came up as "notify-send" with the missing-icon
# checkerboard, because the generic icon is not in the icon theme.
swatch="${XDG_RUNTIME_DIR:-/tmp}/colorpicker-swatch.png"
magick -size 64x64 "xc:$col" "$swatch" 2>/dev/null || swatch=""
notify-send -t 2000 -a "$(tr_ Cuentagotas 'Colour picker')" ${swatch:+-i "$swatch"} \
    "󰃉 $(tr_ 'Color copiado' 'Colour copied')" "$col"
