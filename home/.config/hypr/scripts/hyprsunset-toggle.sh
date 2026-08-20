#!/usr/bin/env bash
# Toggle luz nocturna (hyprsunset). Off = temperatura normal.
if pgrep -x hyprsunset >/dev/null; then
    pkill -x hyprsunset
    notify-send -t 1500 "󰌵 Luz nocturna" "Desactivada"
else
    hyprsunset -t 4000 >/dev/null 2>&1 &
    notify-send -t 1500 "󰃝 Luz nocturna" "Activada · 4000K"
fi
