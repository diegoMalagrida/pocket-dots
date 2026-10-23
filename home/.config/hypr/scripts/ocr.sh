#!/usr/bin/env bash
# OCR: select an area -> extract text -> clipboard.
# On a frozen screen: it also reads the text of a menu or a panel that would
# close when it lost focus.
set -uo pipefail
#
# The notifications go through tr_() so they follow the rice's language (lang.sh
# reads the same language.conf as hyprlock, so the lock screen and these
# notifications cannot drift apart). If lang.sh were missing, the `||` leaves a
# tr_ that returns the Spanish: never any extra text, and never a blank one.
. "$HOME/.config/hypr/scripts/lang.sh" 2>/dev/null || tr_() { printf '%s' "$1"; }


img=$(mktemp --suffix=.png)
trap 'rm -f "$img"' EXIT

# 2 is a manual cancel and stays quiet; any other code is a real failure (disk
# full, no permission) and it used to leave through the same `|| exit 0`,
# indistinguishable from "there was no text".
"$HOME/.config/hypr/scripts/capture-region.sh" > "$img"
rc=$?
if [ "$rc" -ne 0 ] || [ ! -s "$img" ]; then
    [ "$rc" -ne 2 ] && notify-send -u critical "OCR" \
        "$(tr_ 'Error al capturar' 'Capture failed')"
    exit 0
fi

txt=$(tesseract "$img" - -l spa+eng 2>/dev/null)
if [ -n "${txt// /}" ]; then
    printf '%s' "$txt" | wl-copy
    notify-send -t 2500 "OCR" "$(tr_ 'Texto copiado al portapapeles' 'Text copied to the clipboard')"
else
    notify-send -t 2000 "OCR" "$(tr_ 'No se detectó texto' 'No text found')"
fi
