#!/bin/sh
#
# awww-start.sh -- brings up the wallpaper daemon and guarantees there is ALWAYS
# a wallpaper set, also on the first boot of a freshly installed machine.
#
# The bug behind the second half of this script: Diego installed the repo on a
# tower with a clean Arch, logged into Hyprland and found a BLACK screen with
# the correct system colours. The chain was this:
#
#   1. `install.sh` generates the palette with `wal -i "$img" -n -q`. That `-n`
#      tells pywal precisely "generate the palette but do NOT set the wallpaper".
#   2. Here only `awww restore` was called, which restores *the last wallpaper
#      shown*. On a new machine there is none: ~/.cache/awww is empty.
#   3. And `awww restore` returns 0 even when it restored nothing (checked: with
#      an empty HOME it exits with code 0), so the retry loop was satisfied on
#      the first attempt and there was not even a warning.
#
# It was never seen on the laptop because a wallpaper was already set there.
#
# Now, after the restore, awww is ASKED what it is really showing (`awww query`
# prints "currently displaying: image: ..." or "... color: ..."), and only if
# some output was left without an image is a default wallpaper set. That
# condition only holds on the first day: on any normal boot the restore works,
# the check passes and NOTHING is re-themed -- which would be slow and
# pointless, because set-wallpaper.sh regenerates the palette and reloads half
# a dozen programs.

uid="$(/usr/bin/id -u)"

if ! /usr/bin/pgrep -u "$uid" -x awww-daemon >/dev/null 2>&1; then
    /usr/bin/awww-daemon >/dev/null 2>&1 &
fi

# All of this runs in the background so Hyprland's startup is not left waiting
# for the daemon's socket to exist.
(
    # Wait for the daemon. The probe is `awww query`, not `awww restore`: query
    # really fails while there is no socket ("Socket file ... not found") and
    # touches nothing, so it is the honest check for "it is up now".
    listo=0
    intento=0
    while [ "$intento" -lt 50 ]; do
        if /usr/bin/awww query >/dev/null 2>&1; then
            listo=1
            break
        fi
        intento=$((intento + 1))
        /usr/bin/sleep 0.1
    done
    [ "$listo" = 1 ] || exit 0

    /usr/bin/awww restore >/dev/null 2>&1

    # Was any output left without an image? It counts lines (one per monitor)
    # instead of looking only at the first, so that a second monitor without a
    # wallpaper gets one too.
    salidas="$(/usr/bin/awww query 2>/dev/null | /usr/bin/wc -l)"
    con_fondo="$(/usr/bin/awww query 2>/dev/null | /usr/bin/grep -c 'currently displaying: image:')"
    [ "${salidas:-0}" -gt 0 ] || exit 0
    [ "${con_fondo:-0}" -lt "${salidas:-0}" ] || exit 0   # wallpaper already set: touch nothing

    # Which wallpaper to set. First the one pywal used last time (~/.cache/wal/wal
    # holds its path): that way the first-boot wallpaper is EXACTLY the image the
    # palette already on screen came from, and there is no odd jump in colour. If
    # it does not exist or points to a file that is gone, it takes the first
    # image in ~/Pictures/wallpapers with the same criterion install.sh uses
    # (alphabetical order), which is the same one the installer picked.
    img=""
    if [ -r "$HOME/.cache/wal/wal" ]; then
        img="$(/usr/bin/head -n 1 "$HOME/.cache/wal/wal" 2>/dev/null)"
        [ -n "$img" ] && [ -f "$img" ] || img=""
    fi
    if [ -z "$img" ]; then
        img="$(/usr/bin/find "$HOME/Pictures/wallpapers" -maxdepth 1 -type f \
                 \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' \) 2>/dev/null \
               | /usr/bin/sort | /usr/bin/head -n 1)"
    fi
    [ -n "$img" ] && [ -f "$img" ] || exit 0

    # set-wallpaper.sh is the right path: it sets the wallpaper AND writes the
    # things the installer's `wal -i` does not (the ~/.cache/wal/lockbg link that
    # hyprlock uses, the bar-strip.txt the bar watches, the derived themes).
    # It needs ~/.local/bin in PATH and Hyprland does not always inherit it.
    if [ -x "$HOME/.config/hypr/set-wallpaper.sh" ]; then
        PATH="$HOME/.local/bin:/usr/local/bin:/usr/bin:$PATH"
        export PATH
        "$HOME/.config/hypr/set-wallpaper.sh" "$img" >/dev/null 2>&1
    else
        # Without the script, at least let something show.
        /usr/bin/awww img "$img" >/dev/null 2>&1
    fi
) >/dev/null 2>&1 &

exit 0
