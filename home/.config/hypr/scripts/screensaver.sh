#!/usr/bin/env bash
# Random terminal screensaver (quit with q / Ctrl+C).
savers=("pipes.sh -t 0 -f 60" "cbonsai -l -i -w 0.5" "cmatrix -ab" "tty-clock -c -C 4 -s -D")
pick="${savers[$RANDOM % ${#savers[@]}]}"
# If kitty dies without pipes.sh quitting by key press, the pipes loop is left
# orphaned at 25% CPU and only SIGKILL kills it (its trap hangs in tput reset
# with no terminal). A sweep before launching and a hunt on exit; the pattern is
# anchored to the exact args of THIS script so other pipes.sh are not touched.
# The sweep on the way in also takes out any previous screensaver still alive,
# orphaned or not: only one at a time makes sense.
pkill -KILL -f 'pipes\.sh -t 0 -f 60' 2>/dev/null || true
kitty --start-as=fullscreen -o confirm_os_window_close=0 sh -c "$pick"
pkill -KILL -f 'pipes\.sh -t 0 -f 60' 2>/dev/null || true
