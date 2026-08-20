#!/usr/bin/env bash
# Captura de región: congela la pantalla, recorta, guarda y copia.
# El congelado (capture-region.sh) es lo que permite fotografiar menús, el
# notch o cualquier cosa que se cierre al perder el foco.
set -uo pipefail

dir="$HOME/Pictures/screenshots"
mkdir -p "$dir"
file="$dir/screenshot-$(date +%Y%m%d_%H%M%S).png"

if "$HOME/.config/hypr/scripts/capture-region.sh" > "$file" && [ -s "$file" ]; then
    wl-copy < "$file"
    # Al fondo: la notificación se queda esperando por si pulsas "Editar".
    "$HOME/.config/hypr/scripts/notify-shot.sh" "$file" &
else
    rm -f "$file"   # cancelada: no dejes un PNG de 0 bytes en Pictures
fi
