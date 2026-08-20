#!/usr/bin/env bash
# Modo lectura reversible para Hyprland >= 0.55 (configuracion Lua).
#
# Solo toca cuatro valores de runtime: shader, animaciones, blur y sombras.
# Antes de hacerlo guarda los valores REALES del compositor; al salir restaura
# esos mismos valores, no unos defaults inventados. Wallpaper, pywal y brillo
# quedan fuera deliberadamente.

set -euo pipefail

mode="${1:-toggle}"
rice_home="${HOME:?HOME no esta definido}"
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
        # Red de seguridad para un estado perdido: la recarga vuelve a la fuente
        # de verdad del rice y no toca ventanas ni workspaces.
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
        # Snapshot truncado o manipulado: la fuente del rice es la salida segura.
        hyprctl reload >/dev/null
        unlink "$snapshot"
        return
    fi
    if ! apply_state "$previous_shader" "$previous_animations" "$previous_blur" "$previous_shadow"; then
        # El shader anterior pudo borrarse mientras el modo estaba activo. Una
        # recarga es más segura que dejar el modo a medias o bloquear el toggle.
        hyprctl reload >/dev/null
    fi
    unlink "$snapshot"
}

activate() {
    [[ -r "$shader" ]] || { printf 'No existe el shader: %s\n' "$shader" >&2; exit 1; }
    is_active && { printf 'on\n'; return; }

    # Un snapshot sin shader activo es resto de una sesion interrumpida. Primero
    # lo cerramos bien para no apilar estados sobre estados.
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
        # Incluso si Hyprland rechaza el shader, vuelve al estado capturado.
        # Conservar el snapshot hasta restaurar evita dejar efectos a medias.
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
    *)
        printf 'Uso: %s {on|off|toggle|status}\n' "${0##*/}" >&2
        exit 2
        ;;
esac
