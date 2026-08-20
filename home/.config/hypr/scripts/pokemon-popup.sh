#!/usr/bin/env bash
# Popup flotante que invoca un pokemon animado al azar (SUPER+O).
# Una tecla cualquiera (o 10s) lo cierra.
d="$HOME/.cache/pokeanim/.box"
shopt -s nullglob
gifs=("$d"/*.gif)
[ ${#gifs[@]} -eq 0 ] && exit 0
gif="${gifs[RANDOM % ${#gifs[@]}]}"
printf '\033[2J\033[H\n'
kitten icat --align center --loop -1 "$gif" 2>/dev/null
read -rsn1 -t 10
