#!/usr/bin/env bash
# Toggle night light (hyprsunset). Off = normal temperature.
#
# Notifications go through tr_() so they follow the rice's language, as lang.sh
# requires (its header used this very script as the example, and yet it was
# one of the nine that did not use it). If lang.sh were not there, the `||`
# leaves a tr_ that returns the Spanish: never extra text, and never, ever
# blank text.
. "$HOME/.config/hypr/scripts/lang.sh" 2>/dev/null || tr_() { printf '%s' "$1"; }
if pgrep -x hyprsunset >/dev/null; then
    pkill -x hyprsunset
    notify-send -t 1500 "󰌵 $(tr_ 'Luz nocturna' 'Night light')" "$(tr_ 'Desactivada' 'Off')"
else
    hyprsunset -t 4000 >/dev/null 2>&1 &
    notify-send -t 1500 "󰃝 $(tr_ 'Luz nocturna' 'Night light')" "$(tr_ 'Activada · 4000K' 'On · 4000K')"
fi
