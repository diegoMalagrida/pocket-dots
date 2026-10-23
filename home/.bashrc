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


# The greeting of the desktop's first terminal.
#
# THIS IS A COPY OF ~/.zshrc, kept in sync by hand because the two start-ups do
# not share a file. Zsh is the real shell here; bash is the emergency one
# -a tty, a container, a `bash` typed by hand-, and precisely because of that
# this copy fell behind with TWO bugs that were already fixed over there:
#
#   · It called bare `fastfetch` instead of `pokefetch`, which is the one that
#     filters out the pokemon sprites with a truncated PNG. From bash the broken
#     ones came through.
#   · It did not check whether there was a compositor. With no Hyprland behind
#     it, `hyprctl` does not stay quiet: it spits its complaint to STDOUT, that
#     is, down the pipe, and jq tries to parse it as JSON -> "parse error:
#     Invalid numeric literal" the moment a terminal opens. The full reason is
#     told in ~/.zshrc; the guard is the same.
#
# If you touch one, touch the other.
fetch_ws_if_first() {
    command -v hyprctl >/dev/null 2>&1 || return
    command -v jq >/dev/null 2>&1 || return
    [[ -n ${HYPRLAND_INSTANCE_SIGNATURE:-} ]] || return

    local ws
    ws=$(hyprctl activeworkspace -j 2>/dev/null | jq -r '.id' 2>/dev/null) || return
    [[ -z "$ws" || "$ws" == "null" ]] && return

    # PID of the kitty window that contains us (the shell's parent)
    local kitty_pid
    kitty_pid=$(ps -o ppid= -p $$ --no-headers 2>/dev/null | tr -d ' ') || return
    [[ -z "$kitty_pid" ]] && return

    # Count OTHER kitty windows on the same workspace (excluding this one)
    local others
    others=$(hyprctl clients -j 2>/dev/null \
        | jq --argjson ws "$ws" --argjson pid "$kitty_pid" '
            [ .[]
              | select(.class == "kitty" and .workspace.id == $ws and .pid != $pid)
            ]
            | length
        ' 2>/dev/null) || return

    if [ "${others:-0}" -eq 0 ]; then
        command -v pokefetch >/dev/null 2>&1 && pokefetch || fastfetch
    fi
}

fetch_ws_if_first

alias cls='clear'
