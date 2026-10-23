#!/usr/bin/env bash
# Opens the NetworkManager editor for a WPA-EAP network without passing the
# identity or the password through argv. The shell only hands over the SSID,
# which is not a secret.

set -euo pipefail

. "$HOME/.config/hypr/scripts/lang.sh" 2>/dev/null || tr_() { printf '%s' "$1"; }

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
            # Two profiles with the same SSID may have different identities or
            # CAs. We do not guess which: the editor will show the list.
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
        # If Quickshell marked it as known but NetworkManager returns no profile
        # matched by SSID, it shows the list: better to ask for a choice than to
        # edit the wrong profile.
        exec nm-connection-editor --show
        ;;
    create)
        # Quickshell may take a moment to mark `known`; it looks again before
        # creating so as not to duplicate a profile that already exists.
        if uuid="$(find_profile_uuid)"; then
            exec nm-connection-editor --edit="$uuid"
        else
            result=$?
            [[ "$result" -ne 2 ]] || exec nm-connection-editor --show
        fi
        # The editor stores the secrets through NetworkManager. We do not build
        # an `nmcli ... password ...` because that would expose the key in `ps`.
        exec nm-connection-editor --create --type=802-11-wireless
        ;;
    *)
        printf "$(tr_ 'Uso: %s {edit|create} SSID\n' 'Usage: %s {edit|create} SSID\n')" "${0##*/}" >&2
        exit 2
        ;;
esac
