#!/usr/bin/env bash
# Captura de pantalla COMPLETA e instantánea con grim.
# grim no roba el foco → captura también overlays y menús abiertos.
# Guarda, copia al portapapeles y avisa (el aviso se puede pulsar para editar).
set -uo pipefail

dir="$HOME/Pictures/screenshots"
mkdir -p "$dir"
file="$dir/screenshot-$(date +%Y%m%d_%H%M%S).png"

if grim "$file"; then
    wl-copy < "$file"
    "$HOME/.config/hypr/scripts/notify-shot.sh" "$file" &
else
    rm -f "$file"
    notify-send -u critical -a "Captura" "Captura de pantalla" "Error al capturar"
fi
