#!/usr/bin/env bash
# Toggles the recording started by this script. It does not interfere with other wf-recorders.
set -uo pipefail
#
# The notifications go through tr_() so they follow the rice's language (lang.sh
# reads the same language.conf as hyprlock, so the lock screen and these
# notifications cannot drift apart). If lang.sh were missing, the `||` leaves a
# tr_ that returns the Spanish: never any extra text, and never a blank one.
. "$HOME/.config/hypr/scripts/lang.sh" 2>/dev/null || tr_() { printf '%s' "$1"; }


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
      notify-send -u critical "󰑊 $(tr_ 'Grabación' 'Recording')" "$(tr_ 'wf-recorder no terminó todavía' 'wf-recorder has not finished yet')"
      exit 1
    fi
    rm -f "$state_file"
    notify-send -t 2500 "󰑊 $(tr_ 'Grabación' 'Recording')" "$(tr_ 'Guardada en' 'Saved to') ${out/#"$HOME"/\~}"
    exit 0
  fi

  # A "STOP" MUST NOT TURN INTO A "START".
  #
  # If we get here there is saved state but the pid is no longer wf-recorder:
  # the previous take died on its own. This used to just delete the file, and
  # the `fi` below stopped nothing: execution CARRIED ON to slurp. So you
  # pressed to stop and it dropped the selection tool on top of the screen, and
  # if you dragged you started a recording you had not asked for. On top of
  # that nobody told you the previous one was lost or that a half-written mp4
  # was left behind.
  rm -f "$state_file"
  if [ -n "$out" ] && [ -e "$out" ]; then
    notify-send -u critical "󰑊 $(tr_ 'Grabación' 'Recording')" "$(tr_ 'La grabación anterior se cortó sola; el vídeo a medias está en' 'The previous recording died on its own; the partial video is in') ${out/#"$HOME"/\~}"
  else
    notify-send -u critical "󰑊 $(tr_ 'Grabación' 'Recording')" "$(tr_ 'La grabación anterior se cortó sola y no dejó vídeo' 'The previous recording died on its own and left no video')"
  fi
  exit 1
fi

# Sound, only if you ask for it: `screenrecord.sh --sonido`.
#
# It is opt-in on purpose. A quick recording should not grab whatever is playing
# at that moment without warning, and a bare `wf-recorder -a` takes the default
# device, which is THE MICROPHONE. What you almost always want when recording
# the screen is the opposite: the sound coming out of the speakers, i.e. the
# default sink's `.monitor`. If pactl does not answer, it records silent and
# says so.
audio=()
if [ "${1:-}" = "--sonido" ] || [ "${1:-}" = "--audio" ]; then
  sink="$(pactl get-default-sink 2>/dev/null)"
  if [ -n "$sink" ]; then
    audio=(-a"${sink}.monitor")
  else
    notify-send -t 2500 "󰑊 $(tr_ 'Grabacion' 'Recording')" "$(tr_ 'Sin sonido: no hay salida por defecto' 'No sound: no default output')"
  fi
fi

# LOCK BEFORE SLURP, BECAUSE THAT IS WHERE THE GAP IS.
#
# Between the key press and the `printf > "$state_file"` at the end there is no
# state written, and that gap lasts ALL the time you take to drag with slurp.
# Two presses in there left two slurps stacked, and if you completed both
# selections two wf-recorders started: the state_file kept the second one's pid
# and the first kept encoding to ~/Videos until you logged out, with nothing in
# the bar or the notch to give it away.
#
# The noclobber is what makes it atomic (check-and-write in a single step, not
# in three). If the file already exists, it checks whether its owner is still
# alive: a lock orphaned by a SIGKILL gets stolen, because being unable to
# record for the whole session would be worse than the bug this fixes.
lock_file="$runtime_dir/screenrecord.lock"
tomar_cerrojo() {
  if ( set -o noclobber; printf '%s\n' "$$" > "$lock_file" ) 2>/dev/null; then
    return 0
  fi
  local lpid=""
  [ -r "$lock_file" ] && IFS= read -r lpid < "$lock_file"
  if [[ "$lpid" =~ ^[0-9]+$ ]] && kill -0 "$lpid" 2>/dev/null; then
    return 1
  fi
  printf '%s\n' "$$" > "$lock_file"
  return 0
}

if ! tomar_cerrojo; then
  notify-send -t 2000 "󰑊 $(tr_ 'Grabación' 'Recording')" "$(tr_ 'Ya estás eligiendo la zona a grabar' 'You are already picking the area to record')"
  exit 0
fi
# Released on exit. By then the state_file is already written, so the next
# press goes down the stop branch and not this one.
trap 'rm -f "$lock_file"' EXIT

geom="$(slurp)" || exit 0
[ -n "$geom" ] || exit 0
out="$HOME/Videos/rec-$(date +%Y%m%d_%H%M%S).mp4"
wf-recorder -g "$geom" "${audio[@]}" -f "$out" >/dev/null 2>&1 &
pid=$!
sleep 0.2

if ! kill -0 "$pid" 2>/dev/null; then
  wait "$pid" 2>/dev/null || true
  notify-send -u critical "󰑊 $(tr_ 'Grabación' 'Recording')" "$(tr_ 'No se pudo iniciar wf-recorder' 'Could not start wf-recorder')"
  exit 1
fi

printf '%s\n%s\n' "$pid" "$out" > "$state_file"
notify-send -t 2000 "󰑊 $(tr_ 'Grabación' 'Recording')" "$(tr_ 'Grabando… (repite la tecla para parar)' 'Recording… (press the key again to stop)')${audio:+ · $(tr_ 'con sonido' 'with sound')}"
