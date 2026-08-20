#
# ~/.bashrc
#

# If not running interactively, don't do anything
[[ $- != *i* ]] && return

alias ls='ls --color=auto'
alias grep='grep --color=auto'
PS1='[\u@\h \W]\$ '
alias code='ELECTRON_ENABLE_WAYLAND=1 code --ozone-platform=wayland'

[ -r "$HOME/.local/bin/env" ] && . "$HOME/.local/bin/env"


fastfetch_ws_if_first() {
    # Necesitas hyprctl y jq
    command -v hyprctl >/dev/null 2>&1 || return
    command -v jq >/dev/null 2>&1 || return

    # Workspace actual
    local ws
    ws=$(hyprctl activeworkspace -j 2>/dev/null | jq -r '.id') || return
    [[ -z "$ws" || "$ws" == "null" ]] && return

    # PID de la ventana de kitty que nos contiene (padre del shell)
    local kitty_pid
    kitty_pid=$(ps -o ppid= -p $$ --no-headers 2>/dev/null | tr -d ' ') || return
    [[ -z "$kitty_pid" ]] && return

    # Contamos OTRAS kitty en el mismo workspace (excluyendo esta)
    local others
    others=$(hyprctl clients -j 2>/dev/null \
        | jq --argjson ws "$ws" --argjson pid "$kitty_pid" '
            [ .[] 
              | select(.class == "kitty" and .workspace.id == $ws and .pid != $pid)
            ] 
            | length
        ') || return

    # Si no hay ninguna otra kitty en este workspace → fastfetch
    if [ "${others:-0}" -eq 0 ]; then
        fastfetch
    fi
}

# Llamamos a la función al abrir cada terminal
fastfetch_ws_if_first

alias cls='clear'
