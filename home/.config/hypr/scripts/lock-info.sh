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
      # En ingles no hace falta tabla: se le pide a date. Va con LC_ALL=C
      # EXPLICITO y no confiando en que la sesion tenga LC_TIME=C: si alguien
      # exporta LC_TIME o LC_ALL en espanol -cosa que pasa- el dia saldria en
      # castellano con el shell en ingles, y nadie lo notaria hasta ver el
      # bloqueo. Aqui no se hereda el entorno, se fija.
      printf '%s · %d %s\n' "$(LC_ALL=C date +%A)" "$(date +%-d)" "$(LC_ALL=C date +%B)"
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
