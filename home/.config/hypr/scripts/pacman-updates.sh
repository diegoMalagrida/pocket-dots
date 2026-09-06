#!/usr/bin/env bash

set -u

readonly state_dir="${XDG_CACHE_HOME:-$HOME/.cache}/waybar"
readonly stamp_file="$state_dir/pacman-updates.last-sync"
readonly lock_file="$state_dir/pacman-updates.lock"
readonly error_log="$state_dir/pacman-updates.error.log"
readonly check_db="${CHECKUPDATES_DB:-${TMPDIR:-/tmp}/checkup-db-${UID}}"
readonly sync_interval=3600  # 1 h: el dato cambia pocas veces al dia; 600 s era ~6x mas agresivo de lo necesario

mkdir -p "$state_dir"

emit_json() {
    printf '{"text":"%s","tooltip":"%s","class":"%s"}\n' "$1" "$2" "$3"
}

sync_description() {
    local last_sync=0

    if [[ -r "$stamp_file" ]]; then
        read -r last_sync < "$stamp_file"
    fi
    if [[ "$last_sync" =~ ^[0-9]+$ ]] && (( last_sync > 0 )); then
        printf 'repos sincronizados a las %s' "$(date --date="@$last_sync" '+%H:%M')"
    else
        printf 'repos aun no sincronizados'
    fi
}

run_check() {
    local -a args=(--nocolor --nosync)
    local last_sync=0
    local now

    now=$(date +%s)
    if [[ -r "$stamp_file" ]]; then
        read -r last_sync < "$stamp_file"
    fi
    [[ "$last_sync" =~ ^[0-9]+$ ]] || last_sync=0

    full_sync=false
    if (( now < last_sync || now - last_sync >= sync_interval )) ||
        [[ ! -d "$check_db/sync" ]]; then
        args=(--nocolor)
        full_sync=true
    fi

    updates=$(timeout 60 checkupdates "${args[@]}" 2>"$error_log")
    check_status=$?

    if $full_sync && (( check_status == 0 || check_status == 2 )); then
        printf '%s\n' "$now" > "$stamp_file"
    fi
    if (( check_status == 0 || check_status == 2 )); then
        rm -f "$error_log"
    fi
}

exec 9> "$lock_file"
if ! flock -w 65 9; then
    emit_json "?" "Otra consulta de actualizaciones sigue en curso" "error"
    exit 0
fi

case "${1:-}" in
    --list)
        rm -f "$stamp_file"
        run_check
        case $check_status in
            0) printf '%s\n' "$updates" ;;
            2) printf 'Sin actualizaciones\n' ;;
            *) printf 'No se pudieron consultar las actualizaciones\n' ;;
        esac
        exit 0
        ;;
    --refresh)
        # Esto hacia `pkill -RTMIN+8 waybar` para que waybar releyera el modulo.
        # Ya no hay waybar -- la barra es quickshell -- asi que la senal se la
        # llevaba el viento y el clic derecho no hacia NADA. Ahora solo
        # invalidamos la marca de tiempo y NO salimos: seguimos hasta la consulta
        # de abajo, que al no encontrar marca hara sincronizacion completa y
        # emitira el JSON nuevo por stdout, que es justo lo que la barra lee.
        rm -f "$stamp_file"
        ;;
esac

run_check
case $check_status in
    0)
        count=$(awk 'NF { count++ } END { print count + 0 }' <<< "$updates")
        emit_json "$count" "$count actualizaciones disponibles · $(sync_description)" "updates"
        ;;
    2)
        emit_json "0" "Sistema actualizado · $(sync_description)" "none"
        ;;
    *)
        emit_json "?" "Fallo al consultar · detalles en $error_log" "error"
        ;;
esac
