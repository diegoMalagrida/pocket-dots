#!/usr/bin/env bash
# Cuentagotas: coge un color de pantalla y copia el hex.
col=$(hyprpicker -a -f hex) || exit 0
[ -n "$col" ] && notify-send -t 2000 "󰃉 Color copiado" "$col"
