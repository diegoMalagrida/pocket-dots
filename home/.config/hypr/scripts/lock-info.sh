#!/usr/bin/env bash
# Datos pequenos para hyprlock. No dependen del locale global: la sesion usa
# LC_TIME=C, mientras que el resto de la interfaz presenta las fechas en espanol.
set -uo pipefail

# El idioma sale del mismo language.conf que carga hyprlock, para que la isla
# y esta linea no puedan acabar hablando idiomas distintos.
. "${XDG_CONFIG_HOME:-$HOME/.config}/hypr/scripts/lang.sh" 2>/dev/null || RICE_LANG="${RICE_LANG:-es}"

case "${1:-}" in
  date)
    if [[ "$RICE_LANG" == en ]]; then
      # En ingles no hace falta tabla: la sesion ya corre con LC_TIME=C, que es
      # exactamente ingles, asi que se lo pedimos a date y no se mantiene nada.
      printf '%s · %d %s\n' "$(date +%A)" "$(date +%-d)" "$(date +%B)"
    else
      days=(lunes martes miércoles jueves viernes sábado domingo)
      months=(enero febrero marzo abril mayo junio julio agosto septiembre octubre noviembre diciembre)
      day_index=$((10#$(date +%u) - 1))
      month_index=$((10#$(date +%m) - 1))
      day_name="${days[$day_index]}"
      printf '%s · %d de %s\n' "${day_name^}" "$(date +%-d)" "${months[$month_index]}"
    fi
    ;;

  battery)
    shopt -s nullglob
    batteries=(/sys/class/power_supply/BAT*)
    if ((${#batteries[@]} == 0)); then
      exit 0
    fi

    battery="${batteries[0]}"
    capacity="$(<"$battery/capacity")"
    status="$(<"$battery/status")"
    if [[ "$status" == "Charging" || "$status" == "Full" ]]; then
      icon="󰂄"
    else
      icon="󰁹"
    fi
    printf '%s  %s%%\n' "$icon" "$capacity"
    ;;
esac
