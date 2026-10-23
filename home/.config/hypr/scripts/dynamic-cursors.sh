#!/usr/bin/env bash
# dynamic-cursors.sh — shake to find: shaking the mouse enlarges the cursor so
# you can find it, as on macOS. It loads the hypr-dynamic-cursors plugin (built
# by hand in ~/.local/share/hypr-dynamic-cursors against the commit its
# hyprpm.toml pins for the EXACT Hyprland version) and leaves it with ONLY the
# shake: mode none turns off the cursor physics (stretch/rotate), which are not
# wanted here.
#
# If Hyprland/aquamarine get updated, the .so stops matching the running
# compositor ("version mismatch"): then this script looks up the commit pin for
# the RUNNING Hyprland, rebuilds and retries, with a notification.
# Mind: if the session is older than the installed package (updating without
# restarting the session), no pin will do — you will have to wait for the next
# login.

# The zoom comes out SHARP if there is a hyprcursor (SVG) theme installed in
# ~/.local/share/icons with the same name as your cursor theme -- here,
# Bibata-Modern-Ice, from the rtgiskard/bibata_cursor releases. It is not
# versioned: it is 340 KB of third-party binaries. Without it nothing breaks,
# the plugin scales up the XCursor bitmap and it looks a bit softer.
#
# The notifications go through tr_() so they follow the rice's language (lang.sh
# reads the same language.conf as hyprlock, so the lock screen and these
# notifications cannot drift apart). If lang.sh were missing, the `||` leaves a
# tr_ that returns the Spanish: never any extra text, and never a blank one.
. "$HOME/.config/hypr/scripts/lang.sh" 2>/dev/null || tr_() { printf '%s' "$1"; }

REPO="$HOME/.local/share/hypr-dynamic-cursors"
SO="$REPO/out/dynamic-cursors.so"

[ -d "$REPO" ] || exit 0

cargar() { hyprctl plugin load "$SO" 2>&1; }

cargado() { hyprctl plugin list 2>/dev/null | grep -q dynamic-cursors; }

aplicar_config() {
    # The plugin's config LIVES IN hyprland.lua (the pcall block "Shake to
    # find"), not here: every reload resets the plugin's options to defaults
    # (mode=tilt), so it has to be reapplied on every re-evaluation of the
    # .lua. This reload is what makes that block take effect after loading the
    # plugin (when the startup config was parsed the keys did not exist yet).
    hyprctl reload >/dev/null 2>&1
}

pin_para_hyprland_vivo() {
    local hl
    hl=$(hyprctl -j version 2>/dev/null | jq -r '.commit')
    [ -n "$hl" ] || return 1
    local pin
    pin=$(sed -n "s/.*\"$hl\", \"\([0-9a-f]\{40\}\)\".*/\1/p" "$REPO/hyprpm.toml" | head -1)
    if [ -z "$pin" ]; then
        # The local hyprpm.toml does not know this version yet: fetch main's.
        git -C "$REPO" fetch -q origin main 2>/dev/null &&
            git -C "$REPO" checkout -q origin/main -- hyprpm.toml 2>/dev/null
        pin=$(sed -n "s/.*\"$hl\", \"\([0-9a-f]\{40\}\)\".*/\1/p" "$REPO/hyprpm.toml" | head -1)
    fi
    [ -n "$pin" ] && printf '%s' "$pin"
}

compilar() {
    local pin
    pin=$(pin_para_hyprland_vivo) || return 1
    [ -n "$pin" ] || return 1
    git -C "$REPO" fetch -q origin "$pin" 2>/dev/null
    # -f: discards the old local patch before jumping to another commit.
    git -C "$REPO" checkout -q -f "$pin" 2>/dev/null || return 1
    # The pinned commit's toml does not carry its own pin (it is added later
    # on main): always keep it up to date for the next lookup.
    git -C "$REPO" checkout -q origin/main -- hyprpm.toml 2>/dev/null || true
    # Re-applies the local PATCH in highres.cpp: the shake zoom must load
    # the SVG theme even with cursor:enable_hyprcursor turned off (off on
    # purpose: the NORMAL cursor is the usual XCursor).
    # If upstream changes that line, the sed does not match and it builds
    # WITHOUT the patch (blurry but working zoom) — better than not building.
    sed -i 's/ || !\*PUSEHYPRCURSOR//' "$REPO/src/highres.cpp" 2>/dev/null || true
    make -s -C "$REPO" all >/dev/null 2>&1
}

# Freshly cloned: packages/git-repos.txt brings the repo, but not the .so, which
# has to be built against THIS machine's Hyprland version. It only happens once.
if [ ! -f "$SO" ]; then
    notify-send -u low "Shake to find" "$(tr_ 'Compilando dynamic-cursors por primera vez…' 'Building dynamic-cursors for the first time…')" 2>/dev/null || true
    compilar || true
fi

salida=$(cargar)
case "$salida" in
*"version mismatch"*)
    notify-send -u low "Shake to find" "$(tr_ 'Recompilando dynamic-cursors para este Hyprland…' 'Rebuilding dynamic-cursors for this Hyprland…')" 2>/dev/null || true
    compilar && salida=$(cargar)
    ;;
esac

if cargado; then
    aplicar_config
else
    notify-send -u normal "Shake to find" "$(tr_ 'dynamic-cursors no pudo cargarse' 'dynamic-cursors could not load'): ${salida:0:120}" 2>/dev/null || true
fi
