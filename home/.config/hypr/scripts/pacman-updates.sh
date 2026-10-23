#!/usr/bin/env bash

set -u
#
# 2026-09-14: these texts are NOT notifications: they travel in the JSON to
# ShellState.qml (root.pacman = JSON.parse(line).text) and from there to the
# notch AS THEY ARE, without going through I18n.tr. Which means that with the
# shell in English they showed up in Spanish. That is why they go through tr_(),
# like the other scripts' notifications: the source of truth is the same one,
# ~/.config/hypr/language.conf.
. "$HOME/.config/hypr/scripts/lang.sh" 2>/dev/null || tr_() { printf '%s' "$1"; }


readonly state_dir="${XDG_CACHE_HOME:-$HOME/.cache}/waybar"
readonly stamp_file="$state_dir/pacman-updates.last-sync"
readonly lock_file="$state_dir/pacman-updates.lock"
readonly error_log="$state_dir/pacman-updates.error.log"
readonly check_db="${CHECKUPDATES_DB:-${TMPDIR:-/tmp}/checkup-db-${UID}}"
readonly sync_interval=3600  # 1 h: the figure changes a few times a day; 600 s was ~6x more aggressive than needed

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
        printf '%s %s' "$(tr_ 'repos sincronizados a las' 'repos synced at')" "$(date --date="@$last_sync" '+%H:%M')"
    else
        printf '%s' "$(tr_ 'repos aun no sincronizados' 'repos not synced yet')"
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
    emit_json "?" "$(tr_ 'Otra consulta de actualizaciones sigue en curso' 'Another update check is still running')" "error"
    exit 0
fi

case "${1:-}" in
    --list)
        rm -f "$stamp_file"
        run_check
        case $check_status in
            0) printf '%s\n' "$updates" ;;
            2) printf '%s\n' "$(tr_ 'Sin actualizaciones' 'No updates')" ;;
            *) printf '%s\n' "$(tr_ 'No se pudieron consultar las actualizaciones' 'Could not check for updates')" ;;
        esac
        exit 0
        ;;
    --refresh)
        # This used to do `pkill -RTMIN+8 waybar` so waybar would reread the
        # module. There is no waybar any more -- the bar is quickshell -- so the
        # signal went nowhere and right-click did NOTHING. Now we only invalidate
        # the timestamp and do NOT exit: we carry on to the check below, which,
        # finding no timestamp, does a full sync and emits the new JSON on
        # stdout, which is exactly what the bar reads.
        rm -f "$stamp_file"
        ;;
esac

run_check
case $check_status in
    0)
        count=$(awk 'NF { count++ } END { print count + 0 }' <<< "$updates")
        emit_json "$count" "$count $(tr_ 'actualizaciones disponibles' 'updates available') · $(sync_description)" "updates"
        ;;
    2)
        emit_json "0" "$(tr_ 'Sistema actualizado' 'System up to date') · $(sync_description)" "none"
        ;;
    *)
        emit_json "?" "$(tr_ "Fallo al consultar · detalles en" "Check failed · details in") $error_log" "error"
        ;;
esac
