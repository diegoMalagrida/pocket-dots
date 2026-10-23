#!/usr/bin/env bash
# Reversible reading mode for Hyprland >= 0.55 (Lua config).
#
# It only touches four runtime values: shader, animations, blur and shadows.
# Before doing so it saves the compositor's REAL values; on the way out it
# restores those very values, not some made-up defaults. Wallpaper, pywal and
# brightness are left out on purpose.

set -euo pipefail

. "$HOME/.config/hypr/scripts/lang.sh" 2>/dev/null || tr_() { printf '%s' "$1"; }

mode="${1:-toggle}"
rice_home="${HOME:?$(tr_ "HOME no esta definido" "HOME is not defined")}"
runtime_root="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
state_dir="$runtime_root/quickshell-rice"
snapshot="$state_dir/reading-mode.json"
shader="$rice_home/.config/hypr/shaders/reading-mode.glsl"

get_bool() {
    local value
    value="$(hyprctl getoption "$1" -j | jq -r '.bool')"
    [[ "$value" == true || "$value" == false ]] || return 1
    printf '%s\n' "$value"
}

get_shader() {
    local value
    value="$(hyprctl getoption decoration:screen_shader -j | jq -er '.str | select(type == "string")')"
    [[ "$value" == "[[EMPTY]]" ]] && value=""
    printf '%s\n' "$value"
}

is_active() {
    [[ "$(get_shader)" == "$shader" ]]
}

lua_string() {
    jq -Rn --arg value "$1" '$value'
}

apply_state() {
    local shader_value="$1" animations="$2" blur="$3" shadow="$4"
    local shader_literal
    shader_literal="$(lua_string "$shader_value")"
    hyprctl eval "hl.config({ decoration = { screen_shader = ${shader_literal}, blur = { enabled = ${blur} }, shadow = { enabled = ${shadow} } }, animations = { enabled = ${animations} } })" >/dev/null
}

restore_snapshot() {
    if [[ ! -r "$snapshot" ]]; then
        # Safety net for a lost state: the reload goes back to the rice's source
        # of truth and does not touch windows or workspaces.
        hyprctl reload >/dev/null
        return
    fi

    local previous_shader previous_animations previous_blur previous_shadow
    if ! previous_shader="$(jq -er '.screenShader | select(type == "string")' "$snapshot")" \
        || ! previous_animations="$(jq -r '.animations' "$snapshot")" \
        || ! previous_blur="$(jq -r '.blur' "$snapshot")" \
        || ! previous_shadow="$(jq -r '.shadow' "$snapshot")" \
        || [[ "$previous_animations" != true && "$previous_animations" != false ]] \
        || [[ "$previous_blur" != true && "$previous_blur" != false ]] \
        || [[ "$previous_shadow" != true && "$previous_shadow" != false ]]; then
        # Truncated or tampered snapshot: the rice's source is the safe way out.
        hyprctl reload >/dev/null
        unlink "$snapshot"
        return
    fi
    if ! apply_state "$previous_shader" "$previous_animations" "$previous_blur" "$previous_shadow"; then
        # The previous shader may have been deleted while the mode was on. A
        # reload is safer than leaving the mode half applied or jamming the toggle.
        hyprctl reload >/dev/null
    fi
    unlink "$snapshot"
}

activate() {
    [[ -r "$shader" ]] || { printf "$(tr_ 'No existe el shader: %s\n' 'Shader does not exist: %s\n')" "$shader" >&2; exit 1; }
    is_active && { printf 'on\n'; return; }

    # A snapshot with no active shader is left over from an interrupted session.
    # We close it properly first, so as not to stack states on top of states.
    [[ -e "$snapshot" ]] && restore_snapshot

    mkdir -p "$state_dir"
    local temp_snapshot
    temp_snapshot="$(mktemp "$state_dir/reading-mode.XXXXXX")"
    jq -n \
        --arg screenShader "$(get_shader)" \
        --argjson animations "$(get_bool animations:enabled)" \
        --argjson blur "$(get_bool decoration:blur:enabled)" \
        --argjson shadow "$(get_bool decoration:shadow:enabled)" \
        '{screenShader: $screenShader, animations: $animations, blur: $blur, shadow: $shadow}' \
        >"$temp_snapshot"
    mv "$temp_snapshot" "$snapshot"

    if ! apply_state "$shader" false false false; then
        # Even if Hyprland rejects the shader, go back to the captured state.
        # Keeping the snapshot until the restore avoids half-applied effects.
        restore_snapshot || true
        exit 1
    fi
    printf 'on\n'
}

deactivate() {
    if ! is_active && [[ ! -e "$snapshot" ]]; then
        printf 'off\n'
        return
    fi
    restore_snapshot
    printf 'off\n'
}

case "$mode" in
    on) activate ;;
    off) deactivate ;;
    toggle)
        if is_active; then deactivate; else activate; fi
        ;;
    status)
        if is_active; then printf 'on\n'; else printf 'off\n'; fi
        ;;
    reapply)
        # THE SHADER DOES NOT SURVIVE A `hyprctl reload`, AND IT HAS TO BE PUT BACK.
        #
        # All of this is applied through `hyprctl eval`, i.e. ONLY at runtime:
        # neither hyprland.lua nor efectos.lua mentions screen_shader, so after
        # a reload the shader is empty again by definition. And set-wallpaper.sh
        # reloads on EVERY wallpaper change: pressing Super+Shift+W was enough
        # for reading mode to switch itself off.
        #
        # The truth is on disk, not in the shell: if there is a snapshot, the
        # mode was on when the reload happened. That is why we do NOT snapshot
        # again here -the existing one already holds the good state from
        # before- and only the effect is put back. Idempotent: calling it too
        # often costs nothing.
        if is_active; then
            printf 'on\n'
        elif [[ -e "$snapshot" ]]; then
            apply_state "$shader" false false false
            printf 'on\n'
        else
            printf 'off\n'
        fi
        ;;
    *)
        printf "$(tr_ 'Uso: %s {on|off|toggle|status|reapply}\n' 'Usage: %s {on|off|toggle|status|reapply}\n')" "${0##*/}" >&2
        exit 2
        ;;
esac
