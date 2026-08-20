#!/usr/bin/env bash
# OCR: selecciona zona -> extrae texto -> portapapeles.
# Sobre pantalla congelada: también lee el texto de un menú o de un panel que
# se cerraría al perder el foco.
set -uo pipefail

img=$(mktemp --suffix=.png)
trap 'rm -f "$img"' EXIT

"$HOME/.config/hypr/scripts/capture-region.sh" > "$img" || exit 0
[ -s "$img" ] || exit 0

txt=$(tesseract "$img" - -l spa+eng 2>/dev/null)
if [ -n "${txt// /}" ]; then
    printf '%s' "$txt" | wl-copy
    notify-send -t 2500 "OCR" "Texto copiado al portapapeles"
else
    notify-send -t 2000 "OCR" "No se detectó texto"
fi
