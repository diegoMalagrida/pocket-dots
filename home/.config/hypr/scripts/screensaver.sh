#!/usr/bin/env bash
# Salvapantallas de terminal aleatorio (sal con q / Ctrl+C).
savers=("pipes.sh -t 0 -f 60" "cbonsai -l -i -w 0.5" "cmatrix -ab" "tty-clock -c -C 4 -s -D")
pick="${savers[$RANDOM % ${#savers[@]}]}"
# Si kitty muere sin que pipes.sh salga por tecla, el bucle de pipes queda
# huérfano al 25% de CPU y solo lo mata SIGKILL (su trap se cuelga en tput
# reset sin terminal). Barrido antes de lanzar y caza al salir; el patrón va
# anclado a los args exactos de ESTE script para no tocar otros pipes.sh.
# El barrido de entrada se lleva por delante cualquier salvapantallas anterior
# que siguiera vivo, huérfano o no: solo tiene sentido uno a la vez.
pkill -KILL -f 'pipes\.sh -t 0 -f 60' 2>/dev/null || true
kitty --start-as=fullscreen -o confirm_os_window_close=0 sh -c "$pick"
pkill -KILL -f 'pipes\.sh -t 0 -f 60' 2>/dev/null || true
