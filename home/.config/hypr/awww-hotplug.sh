#!/bin/sh
#
# awww-hotplug.sh -- repaints the wallpaper on an output that has just appeared.
#
# THE BUG: you plugged in the second screen with the session open and it came
# up with awww's empty fill colour instead of your wallpaper.
#
# And it is not an oversight in awww: it is on purpose. Its own installed README
# (/usr/share/doc/awww/README.md:187-197, version 0.12.1) says they removed the
# automatic repaint of reconnected outputs and that "you should use a program
# that lets you run commands when a new output is connected". This is that
# program.
#
# The fix was already written, but hooked where it was no use: awww-start.sh
# knows how to do exactly this, and it hangs off hl.on("hyprland.start"), which
# never runs again for the whole session. Only the cheap half goes here.
#
# WHAT THIS SCRIPT DOES NOT DO, ON PURPOSE: re-theme. Plugging in a screen does
# not change the palette, so calling set-wallpaper.sh would mean regenerating
# pywal, reloading Hyprland and half a dozen programs for nothing. It reuses the
# image the other outputs are ALREADY showing.

# Without the daemon there is nothing to do (and query touches nothing, it only asks).
/usr/bin/awww query >/dev/null 2>&1 || exit 0

estado="$(/usr/bin/awww query 2>/dev/null)"
[ -n "$estado" ] || exit 0

# If NO output is blank, there is nothing to fix. That is the normal case.
sin_fondo="$(printf '%s\n' "$estado" | /usr/bin/grep -cv 'currently displaying: image:')"
[ "${sin_fondo:-0}" -gt 0 ] || exit 0

# A restore first: if awww has the output in its cache, it sets it by itself
# and with its own transition. The cache is versioned (~/.cache/awww/0.12.1/,
# one file per output) and the daemon reads it at startup, not on hotplug.
/usr/bin/awww restore >/dev/null 2>&1
estado="$(/usr/bin/awww query 2>/dev/null)"

# The reference image: the one already showing on another output. That way both
# screens end up with the same wallpaper without asking anyone. If there is
# none (all blank), it falls back to the one pywal used last time.
img="$(printf '%s\n' "$estado" | /usr/bin/sed -n 's/.*currently displaying: image: //p' | /usr/bin/head -n 1)"
if [ -z "$img" ] || [ ! -f "$img" ]; then
    img=""
    if [ -r "$HOME/.cache/wal/wal" ]; then
        img="$(/usr/bin/head -n 1 "$HOME/.cache/wal/wal" 2>/dev/null)"
        [ -n "$img" ] && [ -f "$img" ] || img=""
    fi
fi
[ -n "$img" ] || exit 0

# Only to the outputs that are still blank. The format of a query line is
#   ": eDP-1: 1920x1080, scale: 1, currently displaying: image: /path"
# so the name is whatever sits between the first ": " and the next ":".
printf '%s\n' "$estado" | while IFS= read -r linea; do
    case "$linea" in
        *"currently displaying: image:"*) continue ;;
        "") continue ;;
    esac
    resto="${linea#*: }"
    salida="${resto%%:*}"
    [ -n "$salida" ] || continue
    # No transition: the screen has just come on, there is nothing to come
    # from. A fade here would only be one more flicker.
    /usr/bin/awww img --outputs "$salida" --transition-type none "$img" >/dev/null 2>&1
done

exit 0
