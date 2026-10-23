#!/usr/bin/env bash
# Region capture, opened in satty for annotating; saves and copies to the clipboard.
# It runs over a frozen screen (capture-region.sh), so you can annotate an open
# menu or the notch as well.
set -uo pipefail
#
# Notifications go through tr_() so they follow the rice's language (lang.sh
# reads the same language.conf as hyprlock, so the lock screen and these
# notifications cannot drift apart). If lang.sh were missing, the `||` leaves
# a tr_ that returns the Spanish: never extra text, and never, ever blank text.
. "$HOME/.config/hypr/scripts/lang.sh" 2>/dev/null || tr_() { printf '%s' "$1"; }


dir="$HOME/Pictures/screenshots"
mkdir -p "$dir"
tmp=$(mktemp --suffix=.png)
trap 'rm -f "$tmp"' EXIT

# 2 means cancelled by hand and stays quiet; any other code is a real failure
# (disk full, no permission) and it used to leave through the same `|| exit 0`.
"$HOME/.config/hypr/scripts/capture-region.sh" > "$tmp"
rc=$?
if [ "$rc" -ne 0 ] || [ ! -s "$tmp" ]; then
    [ "$rc" -ne 2 ] && notify-send -u critical -a "$(tr_ Captura Screenshot)" \
        "$(tr_ 'Anotar captura' 'Annotate screenshot')" \
        "$(tr_ 'Error al capturar' 'Capture failed')"
    exit 0
fi

satty --filename "$tmp" \
      --output-filename "$dir/satty-$(date +%Y%m%d_%H%M%S).png" \
      --copy-command wl-copy --early-exit
