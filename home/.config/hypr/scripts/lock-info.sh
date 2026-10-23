#!/usr/bin/env bash
# Small bits of data for hyprlock. They do not depend on the global locale: the
# session uses LC_TIME=C, while the rest of the interface shows dates in Spanish.
set -uo pipefail

# The language comes from the same language.conf hyprlock loads, so that the
# island and this line cannot end up speaking different languages.
. "${XDG_CONFIG_HOME:-$HOME/.config}/hypr/scripts/lang.sh" 2>/dev/null || RICE_LANG="${RICE_LANG:-es}"

case "${1:-}" in
  date)
    if [[ "$RICE_LANG" == en ]]; then
      # In English no table is needed: date is asked for it. It runs with an
      # EXPLICIT LC_ALL=C instead of trusting the session to have LC_TIME=C: if
      # someone exports LC_TIME or LC_ALL in Spanish -which happens- the day
      # would come out in Spanish with the shell in English, and nobody would
      # notice until they saw the lock screen. The environment is not inherited
      # here, it is pinned.
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
