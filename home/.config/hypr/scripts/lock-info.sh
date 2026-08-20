#!/usr/bin/env bash
# Datos pequenos para hyprlock. No dependen del locale global: la sesion usa
# LC_TIME=C, mientras que el resto de la interfaz presenta las fechas en espanol.
set -uo pipefail

case "${1:-}" in
  date)
    days=(lunes martes miércoles jueves viernes sábado domingo)
    months=(enero febrero marzo abril mayo junio julio agosto septiembre octubre noviembre diciembre)
    day_index=$((10#$(date +%u) - 1))
    month_index=$((10#$(date +%m) - 1))
    day_name="${days[$day_index]}"
    printf '%s · %d de %s\n' "${day_name^}" "$(date +%-d)" "${months[$month_index]}"
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
