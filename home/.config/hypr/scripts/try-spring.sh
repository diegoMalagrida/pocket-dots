#!/usr/bin/env bash
# Calibrate the `windowsMove` spring LIVE (super + arrow keys).
#
# Needs the Lua config active (~/.config/hypr/hyprland.lua). It touches no
# file: it defines a new curve through `hyprctl eval` and hooks it up. Undo it
# with `hyprctl reload`.
#
# Usage: ./try-spring.sh [config|forma|seco|nervioso|vivo|reset]
#        ./try-spring.sh <stiffness> <dampening>     # by hand
#        ./try-spring.sh todas                       # tries them in a row

set -euo pipefail

. "$HOME/.config/hypr/scripts/lang.sh" 2>/dev/null || tr_() { printf '%s' "$1"; }

# zeta = dampening / (2*sqrt(stiffness*mass)), with mass = 1.
#   zeta = 1  -> arrives as fast as possible WITHOUT overshooting (law 5)
#   zeta < 1  -> bounces. Breaks law 5 on purpose.
aplicar() {
    local k="$1" d="$2" nota="${3:-}"
    local n="muelle$RANDOM"

    hyprctl eval "hl.curve('$n', { type = 'spring', stiffness = $k, dampening = $d, mass = 1 })
                  hl.animation({ leaf = 'windowsMove', enabled = true, speed = 4.4, spring = '$n' })" >/dev/null

    python3 -c "
import math
k, d = $k, $d
w0   = math.sqrt(k)
zeta = d / (2*math.sqrt(k))
# settling time to 2 %, an approximation valid near critical damping
ts   = (5.83 if abs(zeta-1) < .15 else 4/zeta) / w0
print(f'  stiffness={k:<6} dampening={d:<6} zeta={zeta:.2f}  ~{ts*1000:.0f} ms  '
      f'{\"$(tr_ 'REBOTA' 'BOUNCES')\" if zeta < 0.98 else \"$(tr_ 'sin rebote' 'no bounce')\"}  $nota')
"
}

case "${1:-todas}" in
  config)   aplicar 130 23   "$(tr_ "<- lo que hay en hyprland.lua" "<- current values in hyprland.lua")" ;;
  forma)    aplicar 180 26.8 "$(tr_ "<- justo en el escalon FORMA (440 ms)" "<- exactly at the FORMA step (440 ms)")" ;;
  seco)     aplicar 250 31.6 "$(tr_ "<- mas nervioso" "<- snappier")" ;;
  nervioso) aplicar 340 36.9 "$(tr_ "<- casi instantaneo" "<- almost instant")" ;;
  vivo)     aplicar 180 21   "$(tr_ "<- zeta 0.78, se pasa un pelin (rompe la ley 5 a proposito)" "<- zeta 0.78, slight overshoot (deliberately breaks law 5)")" ;;

  reset)
    hyprctl reload >/dev/null
    echo "$(tr_ "  Recargado desde hyprland.lua." "  Reloaded from hyprland.lua.")"
    ;;

  todas)
    echo
    echo "$(tr_ "  Cada uno se queda 12 s. Dale a super+flechitas -- y sobre todo" "  Each stays for 12 s. Press Super+arrow keys -- especially")"
    echo "$(tr_ "  ENCADENA dos o tres seguidas, que es donde se nota el muelle." "  CHAIN two or three presses to feel the spring.")"
    echo
    for p in config forma seco nervioso vivo; do "$0" "$p"; sleep 12; done
    echo
    echo "$(tr_ "  Fin. Recargando..." "  Done. Reloading...")"; hyprctl reload >/dev/null
    ;;

  [0-9]*)
    [ $# -eq 2 ] || { echo "$(tr_ "uso: $0 <stiffness> <dampening>" "usage: $0 <stiffness> <dampening>")"; exit 1; }
    aplicar "$1" "$2" "$(tr_ "<- a mano" "<- manual values")"
    ;;

  *) echo "presets: config | forma | seco | nervioso | vivo | reset | todas"
     echo "$(tr_ "o a mano: $0 <stiffness> <dampening>" "or manually: $0 <stiffness> <dampening>")"; exit 1 ;;
esac
