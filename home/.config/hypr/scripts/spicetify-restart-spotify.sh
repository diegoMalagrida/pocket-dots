#!/usr/bin/env bash
# Reinicia Spotify y lo devuelve al workspace donde estaba, EN SILENCIO
# (sin cambiarte de espacio). Lo llama el hook spicetify-pywal.sh en segundo plano.
#   $1 = id del workspace donde estaba Spotify (vacío = no mover)
set -u

WS="${1:-}"

# cerrar Spotify (SIGTERM; si se resiste, SIGKILL)
pkill -x spotify 2>/dev/null
for i in $(seq 1 12); do pgrep -x spotify >/dev/null 2>&1 || break; sleep 0.25; done
pgrep -x spotify >/dev/null 2>&1 && pkill -9 -x spotify 2>/dev/null
sleep 0.3

# relanzar CON el puerto de depuracion, para que spicetify-push-colors.py pueda
# recolorear en caliente la proxima vez y no haga falta volver a pasar por aqui.
# (El mismo flag esta en ~/.local/share/applications/spotify.desktop, que cubre
# los lanzamientos desde el menu; esta linea cubre los de este script.)
FLAGS="--remote-debugging-port=9333 --remote-allow-origins=http://127.0.0.1:9333"
# Sintaxis Lua (Hyprland 0.55+): `exec` a secas ya no es Lua valido. Aqui el
# fallo era discreto porque el `|| setsid` de al lado recogia el codigo 7 y
# lanzaba Spotify igual; lo que SI se perdia era la vuelta a su workspace.
hyprctl dispatch "hl.dsp.exec_cmd(\"spotify $FLAGS\")" >/dev/null 2>&1 || setsid spotify $FLAGS >/dev/null 2>&1

# devolverlo a su workspace cuando aparezca la ventana (silent = no cambia el foco)
[ -n "$WS" ] || exit 0
for i in $(seq 1 40); do
  hyprctl clients -j 2>/dev/null | grep -q '"class": "Spotify"' && break
  sleep 0.5
done
sleep 0.6
# `follow = false` es el equivalente Lua de movetoworkspacesilent.
hyprctl dispatch "hl.dsp.window.move({ workspace = $WS, follow = false, window = \"class:^(Spotify)$\" })" >/dev/null 2>&1
