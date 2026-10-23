#!/usr/bin/env bash
# cliphist-tool.sh — the bridge between cliphist and the launcher's "#" mode.
#
# Replaces ~/.config/rofi/cliphist-menu.sh + cliphist-paste.sh. The difference
# is not just that QML paints it now: that pair of scripts WAS the menu (rofi
# picked and the script copied), and this one only serves data. The one that
# picks is LauncherPanel.
#
# Commands:
#   list            one line per entry:  id \t kind \t thumbnail \t label
#                   kind = text | image ; thumbnail = png path or "-"
#   copy   <id>     puts that entry on the clipboard (text OR image)
#   delete <id>     removes it from the history
#
# Why TSV and not JSON: the clipboard holds arbitrary text —quotes,
# backslashes, stray newlines— and escaping all that by hand in bash is exactly
# where these things break. Here the label is cleaned of tabs and newlines and
# then there is no character left that can lie about where a field ends.
set -uo pipefail

# The image label is the only text here that reaches the screen, so it
# follows the rice language like the notifications do (see lang.sh).
. "$HOME/.config/hypr/scripts/lang.sh" 2>/dev/null || tr_() { printf '%s' "$1"; }

cache="${XDG_CACHE_HOME:-$HOME/.cache}/cliphist/thumbs"

# How many entries are served. cliphist keeps up to 750; painting them all would
# cost one thumbnail per image from the last month for a list nobody scrolls
# down. 150 is plenty of history and the JSON… the TSV fits in a blink.
LIMIT=150

# Wider than the default (100) on purpose: the launcher search can only find
# what is IN the preview, so trimming here is trimming the search. 200
# characters are still elided on screen, but now they can be searched.
PREVIEW=200

# NOTE: grep, sed and tr are NOT called here, even though that is the natural
# thing in a script. It is 150 lines, and one fork per line and per field is
# ~600 processes: measured, that version took 0.56 s with the thumbnails already
# cached. The launcher runs it every time it opens in "#" mode, so that half
# second would show. With bash pattern matching (=~, ${var//}) it drops to
# hundredths.
list() {
    mkdir -p "$cache"
    # Read whole into an array instead of `cliphist list | head -n LIMIT | while`.
    # With the pipe, head shuts the tap when it reaches the limit, cliphist dies of
    # SIGPIPE and the script ends in 141 because of pipefail: a fake failure that
    # sooner or later ends up being taken for a real one. It is 750 lines at most,
    # i.e. nothing.
    local lines=()
    mapfile -t lines < <(cliphist -preview-width "$PREVIEW" list)
    local line id preview thumb label clean
    for line in "${lines[@]:0:$LIMIT}"; do
        id="${line%%$'\t'*}"
        preview="${line#*$'\t'}"

        if [[ $preview == *"binary data"* && $preview =~ (png|jpeg|jpg|gif|bmp|webp|tiff) ]]; then
            thumb="$cache/$id.png"
            # Cached by id: the first time costs one magick, later ones cost nothing.
            # cliphist never reuses an id, so a cached thumbnail cannot belong to a
            # different image.
            [ -s "$thumb" ] || cliphist decode "$id" 2>/dev/null \
                | magick - -thumbnail 200x200 "$thumb" 2>/dev/null
            [ -s "$thumb" ] || thumb="-"

            label="$(tr_ Imagen Image)"
            [[ $preview =~ ([0-9]+)x([0-9]+) ]] && label="$label  ${BASH_REMATCH[1]}×${BASH_REMATCH[2]}"
            [[ $preview =~ ([0-9.]+)[[:space:]]?([KMG]iB) ]] && label="$label  ·  ${BASH_REMATCH[1]} ${BASH_REMATCH[2]}"

            printf '%s\timage\t%s\t%s\n' "$id" "$thumb" "$label"
        else
            # Tabs and carriage returns out: they are the only two characters that could
            # split the line in the wrong place.
            clean=${preview//$'\t'/ }
            printf '%s\ttext\t-\t%s\n' "$id" "${clean//$'\r'/ }"
        fi
    done
}

case "${1:-list}" in
    list)
        list
        ;;
    copy)
        [ -n "${2:-}" ] || exit 1
        # wl-copy inherits the MIME type of whatever it receives, so an image is
        # pasted as an image and not as its text representation.
        cliphist decode "$2" | wl-copy
        ;;
    delete)
        [ -n "${2:-}" ] || exit 1
        # `cliphist delete` wants the WHOLE line on standard input, not the bare id:
        # we look it up in the list so we do not rebuild it by hand.
        cliphist list | grep -m1 -P "^$2\t" | cliphist delete
        ;;
    *)
        echo "$(tr_ "uso: cliphist-tool.sh list|copy <id>|delete <id>" "usage: cliphist-tool.sh list|copy <id>|delete <id>")" >&2
        exit 2
        ;;
esac
