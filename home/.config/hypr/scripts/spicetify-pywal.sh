#!/usr/bin/env bash
# Re-themes Spotify (spicetify) with the pywal palette. Called by set-wallpaper.sh.
#
# It uses the 'termspot' theme (github.com/fdeox/termspot): a CRT-phosphor TUI.
# Its color.ini ships 19 schemes of its own, so spicetify-colors.py only
# inserts/updates the [pywal] block with a vivid accent derived from the
# wallpaper's dominant hue, and leaves the rest of the file as it is.
#
# How the colour reaches the Spotify that is already open:
#
#   1. Live (the normal case). spicetify-push-colors.py comes in through the
#      DevTools WebSocket and rewrites documentElement's --spice-* variables. It
#      is instant and unnoticeable: no restart, no reload, the scroll is not lost.
#      It needs Spotify to have been launched with --remote-debugging-port (set
#      by the .desktop in ~/.local/share/applications and by
#      spicetify-restart-spotify.sh).
#
#   2. By restarting (plan B). Only if the push fails: Spotify simply closed, or
#      opened from before the port existed. It is what we always used to do.
#
# Why not 'spicetify watch': it does a FULL reload of xpui (a 1-2 s flash and
# you are back at the top of the scroll), it leaves a process running, and the
# maintainer himself says it often fails on Linux (spicetify/cli#1091). Mind,
# the reason 'watch' does not detect changes in #2384 does NOT apply here: that
# user had ${xrdb:...} in the color.ini and the file never changed; ours is
# rewritten with real hex values.
set -u

command -v spicetify >/dev/null 2>&1 || exit 0

SCRIPTS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GEN="$SCRIPTS/spicetify-colors.py"
PUSH="$SCRIPTS/spicetify-push-colors.py"
THEME_DIR="$HOME/.config/spicetify/Themes/termspot"
[ -r "$HOME/.cache/wal/colors.json" ] || exit 0
mkdir -p "$THEME_DIR"

# Regenerate the color.ini (vivid accent) from the current pywal palette + rebuild
# to disk. The refresh does not touch the open window, but it leaves the right
# colour for the next launch.
python3 "$GEN" "$THEME_DIR/color.ini" 2>/dev/null || exit 0
spicetify refresh >/dev/null 2>&1 || true

pgrep -x spotify >/dev/null 2>&1 || exit 0

# --- 1. live attempt ----------------------------------------------------------
if python3 "$PUSH" "$THEME_DIR/color.ini" >/dev/null 2>&1; then
  exit 0
fi

# --- 2. plan B: restart, putting it back on ITS workspace without stealing focus
if pgrep -x spotify >/dev/null 2>&1; then
  WS="$(hyprctl clients -j 2>/dev/null | python3 -c "
import json,sys
try: cs=json.load(sys.stdin)
except Exception: sys.exit()
for c in cs:
    if c.get('class')=='Spotify':
        w=c.get('workspace',{}).get('id')
        if w is not None: print(w)
        break" 2>/dev/null)"
  setsid -f "$SCRIPTS/spicetify-restart-spotify.sh" "$WS" >/dev/null 2>&1 &
fi
