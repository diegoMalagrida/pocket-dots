#!/usr/bin/env bash
# Calibrar EN VIVO el muelle de `windowsMove` (super + flechitas).
#
# Requiere la config Lua activa (~/.config/hypr/hyprland.lua). No toca ningun
# fichero: define una curva nueva por `hyprctl eval` y la engancha. Se deshace
# con `hyprctl reload`.
#
# Uso:  ./probar-muelle.sh [config|forma|seco|nervioso|vivo|reset]
#       ./probar-muelle.sh <stiffness> <dampening>     # a mano
#       ./probar-muelle.sh todas                       # las prueba en fila

set -euo pipefail

# zeta = dampening / (2*sqrt(stiffness*mass)), con mass = 1.
#   zeta = 1  -> llega lo mas rapido posible SIN pasarse (ley 5)
#   zeta < 1  -> rebota. Se sale de la ley 5 a proposito.
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
# tiempo de asentamiento al 2 %, aproximacion valida cerca del critico
ts   = (5.83 if abs(zeta-1) < .15 else 4/zeta) / w0
print(f'  stiffness={k:<6} dampening={d:<6} zeta={zeta:.2f}  ~{ts*1000:.0f} ms  '
      f'{\"REBOTA\" if zeta < 0.98 else \"sin rebote\"}  $nota')
"
}

case "${1:-todas}" in
  config)   aplicar 130 23   "<- lo que hay en hyprland.lua" ;;
  forma)    aplicar 180 26.8 "<- justo en el escalon FORMA (440 ms)" ;;
  seco)     aplicar 250 31.6 "<- mas nervioso" ;;
  nervioso) aplicar 340 36.9 "<- casi instantaneo" ;;
  vivo)     aplicar 180 21   "<- zeta 0.78, se pasa un pelin (rompe la ley 5 a proposito)" ;;

  reset)
    hyprctl reload >/dev/null
    echo "  Recargado desde hyprland.lua."
    ;;

  todas)
    echo
    echo "  Cada uno se queda 12 s. Dale a super+flechitas -- y sobre todo"
    echo "  ENCADENA dos o tres seguidas, que es donde se nota el muelle."
    echo
    for p in config forma seco nervioso vivo; do "$0" "$p"; sleep 12; done
    echo
    echo "  Fin. Recargando..."; hyprctl reload >/dev/null
    ;;

  [0-9]*)
    [ $# -eq 2 ] || { echo "uso: $0 <stiffness> <dampening>"; exit 1; }
    aplicar "$1" "$2" "<- a mano"
    ;;

  *) echo "presets: config | forma | seco | nervioso | vivo | reset | todas"
     echo "o a mano: $0 <stiffness> <dampening>"; exit 1 ;;
esac
