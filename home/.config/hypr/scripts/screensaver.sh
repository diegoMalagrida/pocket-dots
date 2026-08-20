#!/usr/bin/env bash
# Salvapantallas de terminal aleatorio (sal con q / Ctrl+C).
savers=("pipes.sh -t 0 -f 60" "cbonsai -l -i -w 0.5" "cmatrix -ab" "tty-clock -c -C 4 -s -D")
pick="${savers[$RANDOM % ${#savers[@]}]}"
exec kitty --start-as=fullscreen -o confirm_os_window_close=0 sh -c "$pick"
