#!/usr/bin/env bash
# Syncs the login (SDDM's hyprisland theme) with the current wallpaper.
#
# It copies TWO things, and both matter: the wallpaper and the accent pywal
# generated for hyprlock. That way the boot screen and the notch's lock screen
# do not just look alike, they change together and with the same colour.
#
# IT RUNS AS YOUR USER. There is no root service behind it, and that is the
# reason this file exists. It used to be done by
# /usr/local/bin/sddm-wallpaper-sync.sh, launched by a system .path: root read
# the PATH written in ~/.cache/wal/wal -a file any process of yours can
# rewrite- and handed it to ImageMagick. That is, root opened a file chosen by
# an unprivileged process, with ImageMagick delegates enabled (Arch's
# policy.xml restricts none of them) and leaving the result at 0644. A process
# running as you could leak files only root can read that way. Now the work is
# done by your user and the only shared place is $SHARED, which root owns but
# your group can write; the worst that can be written there is a JPEG that Qt
# then loads as the `sddm` user.
#
# It is called by set-wallpaper.sh, which is the only path through which the
# wallpaper changes (the Quickshell picker and awww-start.sh go through it too).
#
# Usage:  login-sync.sh [image]
#         With no argument it takes the wallpaper ~/.cache/wal/wal points to.
set -uo pipefail

SHARED=/var/lib/sddm-hyprisland
WAL_FILE="$HOME/.cache/wal/wal"
LOCK_COLORS="$HOME/.cache/wal/colors-hyprlock.conf"

# If the theme is not installed, this directory does not exist and there is
# nothing to sync. Exit with 0: this is a cosmetic extra, it must not bring down
# the wallpaper change of whoever calls us.
[ -d "$SHARED" ] && [ -w "$SHARED" ] || exit 0

# --- wallpaper -----------------------------------------------------------
IMG="${1:-}"
if [ -z "$IMG" ] && [ -r "$WAL_FILE" ]; then
    IMG="$(cat "$WAL_FILE")"
fi

if [ -n "$IMG" ] && [ -f "$IMG" ]; then
    dest="$SHARED/current.jpg"
    tmp="$SHARED/.current.jpg.tmp"
    # Re-encoded to JPEG because the source wallpaper may be png or webp.
    #
    # The JPEG: prefix is not decoration. ImageMagick picks the output format by
    # the EXTENSION, and here it writes first to a temporary file ending in .tmp,
    # so without it no conversion happens: the wallpaper came out as a 1.1 MB PNG
    # inside a file called current.jpg. With the prefix, 282 KB of real JPEG.
    #
    # Without ImageMagick the cp will do: the greeter loads with Qt, which looks
    # at the content and not the extension, so a png called .jpg shows up too.
    if command -v magick >/dev/null 2>&1; then
        magick "$IMG" "JPEG:$tmp" 2>/dev/null || cp -f -- "$IMG" "$tmp"
    else
        cp -f -- "$IMG" "$tmp"
    fi
    # Atomic rename: the greeter never sees a half-written file.
    if [ -s "$tmp" ]; then
        chmod 644 "$tmp" && mv -f -- "$tmp" "$dest"
    else
        rm -f -- "$tmp"
    fi
fi

# --- accent --------------------------------------------------------------
# Single source of truth: the same file hyprlock reads. If you ever change the
# template ~/.config/wal/templates/colors-hyprlock.conf, the login follows the
# change without touching anything else.
if [ -r "$LOCK_COLORS" ]; then
    acc="$(grep -oP '^\$accent\s*=\s*rgba\(\K[0-9a-fA-F]{6}' "$LOCK_COLORS" | head -1)"
    if [ -n "${acc:-}" ]; then
        tmp="$SHARED/.accent.tmp"
        printf '#%s\n' "$acc" >"$tmp" &&
            chmod 644 "$tmp" &&
            mv -f -- "$tmp" "$SHARED/accent"
    fi
fi

exit 0
