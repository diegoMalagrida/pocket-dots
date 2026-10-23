#!/usr/bin/env bash
# Opens an ALREADY TAKEN screenshot in satty to annotate it. The notification's
# "Editar" (Edit) action calls it (see notify-shot.sh), but it works on its own:
#   screenshot-edit.sh ~/Pictures/screenshots/loquesea.png
set -uo pipefail
#
# Notifications go through tr_() so they follow the rice's language (lang.sh
# reads the same language.conf as hyprlock, so the lock screen and these
# notifications cannot drift apart). If lang.sh were missing, the `||` leaves
# a tr_ that returns the Spanish: never extra text, and never, ever blank text.
. "$HOME/.config/hypr/scripts/lang.sh" 2>/dev/null || tr_() { printf '%s' "$1"; }


img="${1:-}"
if [ ! -s "$img" ]; then
    notify-send -u critical -a "$(tr_ Captura Screenshot)" "$(tr_ 'Editar captura' 'Edit screenshot')" "$(tr_ 'No encuentro esa imagen' 'I cannot find that image')"
    exit 1
fi

dir="$HOME/Pictures/screenshots"
mkdir -p "$dir"

# Saves the annotated version separately: the original is left alone.
exec satty --filename "$img" \
           --output-filename "$dir/satty-$(date +%Y%m%d_%H%M%S).png" \
           --copy-command wl-copy --early-exit
