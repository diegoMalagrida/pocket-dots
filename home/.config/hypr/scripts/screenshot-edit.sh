#!/usr/bin/env bash
# Abre una captura YA HECHA en satty para anotarla. Lo llama la acción "Editar"
# de la notificación (ver notify-shot.sh), pero sirve suelto:
#   screenshot-edit.sh ~/Pictures/screenshots/loquesea.png
set -uo pipefail

img="${1:-}"
if [ ! -s "$img" ]; then
    notify-send -u critical -a "Captura" "Editar captura" "No encuentro esa imagen"
    exit 1
fi

dir="$HOME/Pictures/screenshots"
mkdir -p "$dir"

# Guarda la versión anotada aparte: el original no se toca.
exec satty --filename "$img" \
           --output-filename "$dir/satty-$(date +%Y%m%d_%H%M%S).png" \
           --copy-command wl-copy --early-exit
