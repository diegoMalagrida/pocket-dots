#!/usr/bin/env bash
# Captura de región y la abre en satty para anotar; guarda y copia al portapapeles.
# Va sobre pantalla congelada (capture-region.sh), así que también puedes anotar
# un menú abierto o el notch.
set -uo pipefail

dir="$HOME/Pictures/screenshots"
mkdir -p "$dir"
tmp=$(mktemp --suffix=.png)
trap 'rm -f "$tmp"' EXIT

"$HOME/.config/hypr/scripts/capture-region.sh" > "$tmp" || exit 0
[ -s "$tmp" ] || exit 0

satty --filename "$tmp" \
      --output-filename "$dir/satty-$(date +%Y%m%d_%H%M%S).png" \
      --copy-command wl-copy --early-exit
