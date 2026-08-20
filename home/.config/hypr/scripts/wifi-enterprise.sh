#!/usr/bin/env bash
# Abre el editor de NetworkManager para una red WPA-EAP sin pasar identidad ni
# contrasena por argv. El shell solo entrega el SSID, que no es un secreto.

set -euo pipefail

action="${1:-edit}"
ssid="${2:-}"

find_profile_uuid() {
    local line uuid type candidate found=""
    while IFS= read -r line; do
        uuid="${line%%:*}"
        type="${line#*:}"
        [[ "$type" == "802-11-wireless" ]] || continue
        candidate="$(nmcli --escape no -g 802-11-wireless.ssid connection show uuid "$uuid" 2>/dev/null | head -n 1 || true)"
        if [[ "$candidate" == "$ssid" ]]; then
            # Dos perfiles con el mismo SSID pueden tener identidades o CA
            # distintas. No adivinamos cuál: el editor enseñará la lista.
            [[ -z "$found" ]] || return 2
            found="$uuid"
        fi
    done < <(nmcli -t -f UUID,TYPE connection show)
    [[ -n "$found" ]] || return 1
    printf '%s\n' "$found"
}

case "$action" in
    edit)
        if uuid="$(find_profile_uuid)"; then
            exec nm-connection-editor --edit="$uuid"
        fi
        # Si Quickshell la marcaba como conocida pero NetworkManager no devuelve
        # un perfil casado por SSID, ensena la lista: mejor pedir una eleccion que
        # editar el perfil equivocado.
        exec nm-connection-editor --show
        ;;
    create)
        # Quickshell puede tardar un instante en marcar `known`; vuelve a mirar
        # antes de crear para no duplicar un perfil que ya existe.
        if uuid="$(find_profile_uuid)"; then
            exec nm-connection-editor --edit="$uuid"
        else
            result=$?
            [[ "$result" -ne 2 ]] || exec nm-connection-editor --show
        fi
        # El editor guarda los secretos mediante NetworkManager. No construimos
        # un `nmcli ... password ...` porque eso expondria la clave en `ps`.
        exec nm-connection-editor --create --type=802-11-wireless
        ;;
    *)
        printf 'Uso: %s {edit|create} SSID\n' "${0##*/}" >&2
        exit 2
        ;;
esac
