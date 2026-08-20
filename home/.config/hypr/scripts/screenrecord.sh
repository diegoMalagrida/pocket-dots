#!/usr/bin/env bash
# Toggle de la grabación iniciada por este script. No interfiere con otros wf-recorder.
set -uo pipefail

runtime_dir="${XDG_RUNTIME_DIR:-/tmp/runtime-$UID}/hypr-tools"
state_file="$runtime_dir/screenrecord.state"
mkdir -p "$runtime_dir" "$HOME/Videos"

if [ -r "$state_file" ]; then
  mapfile -t state < "$state_file"
  pid="${state[0]:-}"
  out="${state[1]:-}"
  comm=""
  if [[ "$pid" =~ ^[0-9]+$ ]] && [ -r "/proc/$pid/comm" ]; then
    IFS= read -r comm < "/proc/$pid/comm" || true
  fi

  if [ "$comm" = "wf-recorder" ] && kill -INT "$pid" 2>/dev/null; then
    for _ in {1..30}; do
      kill -0 "$pid" 2>/dev/null || break
      sleep 0.1
    done
    if kill -0 "$pid" 2>/dev/null; then
      notify-send -u critical "󰑊 Grabación" "wf-recorder no terminó todavía"
      exit 1
    fi
    rm -f "$state_file"
    notify-send -t 2500 "󰑊 Grabación" "Guardada en ${out/#$HOME/~}"
    exit 0
  fi

  rm -f "$state_file"
fi

geom="$(slurp)" || exit 0
[ -n "$geom" ] || exit 0
out="$HOME/Videos/rec-$(date +%Y%m%d_%H%M%S).mp4"
wf-recorder -g "$geom" -f "$out" >/dev/null 2>&1 &
pid=$!
sleep 0.2

if ! kill -0 "$pid" 2>/dev/null; then
  wait "$pid" 2>/dev/null || true
  notify-send -u critical "󰑊 Grabación" "No se pudo iniciar wf-recorder"
  exit 1
fi

printf '%s\n%s\n' "$pid" "$out" > "$state_file"
notify-send -t 2000 "󰑊 Grabación" "Grabando… (repite la tecla para parar)"
