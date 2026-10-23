#!/usr/bin/env bash
# set-wallpaper.sh <image> [--paleta-de <image>] — changes the wallpaper and
# re-themes EVERYTHING (pywal) live.
#
# Normally the palette comes from the wallpaper itself, where it has always come
# from. --paleta-de breaks that link on purpose: the wallpaper is one image and
# the colours come from ANOTHER. Pokémon mode ('poke-theme wear') uses it: there
# the creature rules -its artwork gives the palette- and the wallpaper is just
# the collection's best match. Everything else in this script -the eleven
# reloads, the lock, the lock-screen background, the bar strip- is shared as is.
set -uo pipefail

# The one notification here follows the rice language, like the other scripts.
. "$HOME/.config/hypr/scripts/lang.sh" 2>/dev/null || tr_() { printf '%s' "$1"; }

IMG=""
PALETA=""
while [ $# -gt 0 ]; do
  case "$1" in
    --paleta-de)
      PALETA="${2:-}"
      [ -z "$PALETA" ] && { echo "$(tr_ "--paleta-de necesita una imagen" "--paleta-de requires an image")"; exit 1; }
      shift 2
      ;;
    -h|--help)
      echo "$(tr_ "uso: set-wallpaper.sh <imagen> [--paleta-de <imagen>]" "usage: set-wallpaper.sh <image> [--paleta-de <image>]")"; exit 0
      ;;
    *)
      [ -z "$IMG" ] && IMG="$1" || { echo "$(tr_ "argumento de sobra: $1" "Unexpected argument: $1")"; exit 1; }
      shift
      ;;
  esac
done

[ -z "$IMG" ] && { echo "$(tr_ "uso: set-wallpaper.sh <imagen> [--paleta-de <imagen>]" "usage: set-wallpaper.sh <image> [--paleta-de <image>]")"; exit 1; }
[ -f "$IMG" ] || { echo "$(tr_ "no existe: $IMG" "Does not exist: $IMG")"; exit 1; }
IMG="$(realpath -- "$IMG")" || exit 1

# Where the COLOURS come from. Without --paleta-de it is the wallpaper itself,
# i.e. the usual behaviour, byte for byte.
if [ -n "$PALETA" ]; then
  [ -f "$PALETA" ] || { echo "$(tr_ "no existe la imagen de paleta: $PALETA" "Palette image does not exist: $PALETA")"; exit 1; }
  PALETA="$(realpath -- "$PALETA")" || exit 1
else
  PALETA="$IMG"
fi

# Serialises the whole chain: the picker launches this script with execDetached
# on every selection, and two concurrent wal runs leave the desktop MIXED (A's
# wallpaper with B's palette, colors.json half-written). With the lock, each
# selection waits for the previous one to finish instead of trampling it. Same
# pattern as pacman-updates.sh. The background jobs close fd 9 (9>&-) so they do
# not hold the lock beyond the script itself.
#
# Mind the `if`: a bare `exec 9>...` that fails -say, another user's lock in
# /tmp- kills the whole script right there without a word, and the wallpaper
# would not change. This way, if the lock cannot be opened, it runs without it.
if exec 9>"${XDG_RUNTIME_DIR:-/tmp}/set-wallpaper.lock" 2>/dev/null; then
    flock 9
fi

# --saturate 0.5: raises the palette's saturation for more vivid colours (0.4 gentle, 0.6 strong, remove it for the original)
# $PALETA is $IMG unless --paleta-de was passed (pokémon mode).
if ! wal -i "$PALETA" --saturate 0.5 -n -q -s -t; then
  notify-send -u critical "$(tr_ "Tema dinámico" "Dynamic theme")" "$(tr_ "Pywal no pudo generar la paleta" "Pywal could not generate the palette")" 2>/dev/null || true
  exit 1
fi

# The worn pokémon stops being true as soon as the palette comes from elsewhere.
# A normal wallpaper change -the picker, the shortcut- passes through here
# WITHOUT --paleta-de, so this is the exact point to forget it: otherwise the
# notch would keep announcing a Gengar that no longer paints anything.
# 'poke-theme wear' rewrites it afterwards, when the call does carry --paleta-de.
[ "$PALETA" = "$IMG" ] && rm -f "$HOME/.config/poke-theme/worn" 2>/dev/null

# In its 'wallpaper' field pywal points to the image it took the colours from,
# which with --paleta-de is NOT the wallpaper. And that field gets consumed:
# Colors.qml reads it and publishes it as Colors.wallpaper, which is what the
# overview (OverviewPanel.qml) and the bar preview (SettingsBarPreview.qml)
# paint. Without this, both would show the cropped pokémon artwork instead of
# the real wallpaper. It is fixed IN PLACE -- 'cat >' and not 'mv' -- to keep
# the inode, which is what makes Quickshell's watcher notice the change; the
# temp file + rename trick slips past it (same reason as in
# qt-pywal.py).
if [ "$PALETA" != "$IMG" ]; then
  CJ="$HOME/.cache/wal/colors.json"
  if tmp_cj="$(mktemp)" && jq --arg w "$IMG" '.wallpaper = $w' "$CJ" > "$tmp_cj" 2>/dev/null \
     && [ -s "$tmp_cj" ]; then
    cat "$tmp_cj" > "$CJ"
  fi
  rm -f "${tmp_cj:-}" 2>/dev/null
  # colors.sh is the other one consumed as data (wallpaper='...').
  CS="$HOME/.cache/wal/colors.sh"
  if [ -f "$CS" ] && tmp_cs="$(mktemp)" \
     && sed "s|^wallpaper=.*|wallpaper='${IMG}'|" "$CS" > "$tmp_cs" && [ -s "$tmp_cs" ]; then
    cat "$tmp_cs" > "$CS"
  fi
  rm -f "${tmp_cs:-}" 2>/dev/null
  # And the third, which had been left out: ~/.cache/wal/wal holds the bare
  # path. Its only consumer is awww-start.sh:69-72, which passes it to this
  # same script WITHOUT --paleta-de... and then line 71 up above deletes the
  # worn pokémon and leaves you the ARTWORK full screen as the wallpaper. It
  # only fires if after an `awww restore` some output is still blank -awww
  # updated (its cache goes by version), `awww clear-cache`, a freshly
  # installed machine-, but when it fires it changes your wallpaper without
  # you asking for anything. impasto does not infer the wallpaper from the
  # palette cache: it reads it from its state (theme_manager.py:427-431).
  CW="$HOME/.cache/wal/wal"
  [ -f "$CW" ] && printf '%s' "$IMG" > "$CW"
fi

ln -sfn -- "$IMG" "$HOME/.cache/wal/lockbg"  # lock-screen background follows the wallpaper

# The login (SDDM's hyprisland theme) follows the wallpaper just like the lock.
# It runs as you, not as root: see the header comment of login-sync.sh.
# In the background because it re-encodes the image and there is no reason for
# it to delay the wallpaper transition, which is what you see.
[ -x "$HOME/.config/sddm-hyprisland/login-sync.sh" ] &&
    "$HOME/.config/sddm-hyprisland/login-sync.sh" "$IMG" >/dev/null 2>&1 9>&- &

# The REAL colour of the strip where the bar lives. It is needed because the bar
# has no surface of its own: its bodies are painted straight onto the
# wallpaper, and to know whether they will show you have to measure against
# what is BEHIND. pywal's `background` is no use for that: it is a darkened
# derivative of the palette, not a piece of the image (measured with this very
# wallpaper: 0.011 luminance against 0.087 for the real strip, eight times
# darker), so computing against it leaves the bodies dull exactly where the
# wallpaper is light. This averages the top 5 % of the image and leaves it
# where Colors.qml watches it. If magick fails, the file is left empty and
# Colors falls back to pywal's background as before.
#
# It is written to a temporary file and moved on top, which within the same
# directory is atomic: Colors.qml watches this file with watchChanges and with
# the direct redirect it saw TWO changes -- first the file truncated to zero
# (the redirect truncates before magick starts) and then the colour -- or it was
# left with the empty one if magick failed halfway. If no colour comes out, it is
# deleted: no file is better, as Colors already falls back to pywal's background,
# than the PREVIOUS wallpaper's colour, the only value that is never correct.
#
# AND IT IS THE CROP THAT GETS MEASURED, NOT THE FILE.
#
# `awww img` uses `--resize crop` by default: it scales to COVER the screen and
# crops whatever is left over, centred. So the top strip of the file and the
# top strip of what you see need not be the same, and with an image whose
# aspect ratio differs from the screen's they are not.
#
# Measured over the 21 wallpapers: 19 match (deviation 1.00-1.02) and
# art-an-eruption goes to 1.09, imperceptible. But art-sunset-after-a-storm gives
# #222221 in the file against #4D5452 on screen -deviation 2.05-, and with its
# palette the bar's real contrast drops to 2.28:1 while Colors.qml:39-66 thinks
# it is guaranteeing 3:1. With scrimAlpha at 0 the bar is painted straight onto
# the wallpaper, so this measurement is not cosmetic.
#
# If hyprctl or jq fail, it measures as before: an approximate measurement
# always; no measurement at all, never.
GEOPAN="$(hyprctl monitors -j 2>/dev/null \
          | jq -r 'first(.[] | select(.focused) | "\(.width)x\(.height)") // empty' 2>/dev/null)"
recorte=()
case "${GEOPAN:-}" in
  [0-9]*x[0-9]*) recorte=(-resize "${GEOPAN}^" -gravity center -extent "$GEOPAN") ;;
esac

strip="$HOME/.cache/wal/bar-strip.txt"
if magick "$IMG" "${recorte[@]}" -gravity north -crop '100%x5%+0+0' +repage -alpha off -resize 1x1! txt:- 2>/dev/null \
     | awk 'NR==2 && $3 ~ /^#[0-9A-Fa-f]{6}$/ {print $3}' > "$strip.new" && [ -s "$strip.new" ]; then
  mv -f "$strip.new" "$strip"
else
  rm -f "$strip.new" "$strip"
fi

# Spotify, THE FIRST of the reloads, and in the background.
#
# It used to be last on the list and it showed: the bar and the terminals had
# already changed colour and Spotify stayed blue for a good second and a half.
# Measured on the desktop video, changing the wallpaper with Spotify in front:
# the wallpaper came in, the bar changed, and Spotify's repaint arrived 1.3-1.7 s
# later. It is not that it is slow -the push through DevTools takes 0.07 s- it
# is that its turn came last, behind yazi, cava, btop and discord.
#
# Now it goes out here, with the palette freshly written and BEFORE the
# wallpaper transition starts, and in the background so as not to delay it.
# That way the wallpaper and the biggest window on screen change together,
# which is how you read that the whole system is one.
~/.config/hypr/scripts/spicetify-pywal.sh >/dev/null 2>&1 9>&- &

# The wallpaper is visual; an awww failure does not invalidate the freshly generated palette.
# apply ilyamiro style: random transition + from the centre + 144fps + 1s
awww_transitions=(simple fade left right top bottom wipe grow center outer random wave)
awww_rt="${awww_transitions[RANDOM % ${#awww_transitions[@]}]}"
awww img "$IMG" --transition-type "$awww_rt" --transition-pos 0.5,0.5 --transition-fps 144 --transition-duration 1 >/dev/null 2>&1 || awww img "$IMG" >/dev/null 2>&1 || true

# Reloads of running daemons.
# Quickshell (bar + notch) does NOT need a reload: Colors.qml watches
# ~/.cache/wal/colors.json and recolours itself.
pkill -SIGUSR1 -x kitty  2>/dev/null || true
hyprctl reload           >/dev/null 2>&1 || true
# swaync retired on 2026-08-05: the notification server is Quickshell's
~/.config/hypr/scripts/yazi-pywal.sh 2>/dev/null || true
~/.config/hypr/scripts/cava-pywal.sh 2>/dev/null || true
# The two terminal toys. They GO AFTER THE SIGUSR1 TO KITTY above, and it is not
# about tidiness: the aquarium is recoloured by writing the palette via OSC 4 to
# its terminal, and kitty reapplies colors-kitty.conf on a config reload and
# wipes it out. Placed before, the aquarium would revert to its colour on every
# wallpaper change. lavat has no reload of any kind, so its script restarts it
# (SIGTERM) and the ~/.local/bin/lavat wrapper brings it up with the new palette.
~/.config/hypr/scripts/lavat-pywal.sh 2>/dev/null || true
~/.config/hypr/scripts/asciiquarium-pywal.sh 2>/dev/null || true
# VS Code retired on 2026-08-11: pywal theming looked ugly however you looked at
# it, and there is no way to make an entire editor look good from five colours
# of a wallpaper. It keeps its stock theme.
~/.config/hypr/scripts/btop-pywal.sh 2>/dev/null || true
# All of GTK: generates the theme with the new palette (and the icon theme, with
# the folders tinted) and applies it to the windows ALREADY OPEN. The script
# explains why a new theme name is needed every time; the short version is that
# GTK caches themes by name and rereads nothing from disk while the window is
# alive.
~/.config/hypr/scripts/gtk-pywal.sh >/dev/null 2>&1 || true

# Qt applications: writes the qt5ct and qt6ct palettes and the colour sections
# of kdeglobals. Both families are recoloured WITHOUT restarting them, because
# their platform theme watches the .conf and the script rewrites it keeping the
# inode -- which is exactly what makes the watcher notice; with the usual
# temp file + rename trick, it never notices.
#
# THE ORDER MATTERS, AND UNTIL 2026-09-14 IT WAS BACKWARDS. qt-pywal.py does not
# invent the ICON theme's name: it reads it from ~/.config/gtk-3.0/settings.ini.
# Running BEFORE gtk-pywal.sh it read the PREVIOUS wallpaper's name, and six
# lines later folders-pywal.py deleted that old theme while generating the new
# one. Result measured that day: qt5ct and qt6ct pointed at pywal-folders-5ddfa250
# when the only one in existence was pywal-folders-a2486ac4. With a non-existent
# theme, Qt falls back to hicolor, where the freedesktop names are NOT present
# (network-wired, preferences-system-network, applications-system...), not even
# the generic application-x-executable: that is why the launcher, overview and
# notch-notification icons came out empty, and why the quickshell log kept
# repeating "Could not load icon ... from request".
# Now it goes AFTER, so it reads the freshly created name. Do not move it up again.
~/.config/hypr/scripts/qt-pywal.py >/dev/null 2>&1 || true
~/.config/hypr/scripts/discord-pywal.sh 2>/dev/null || true
# (spicetify has already been launched above, before the wallpaper transition)
# Re-ranks the pokémon sprites for the new palette (~0.1 s) so that the next
# terminal already shows the ones that match. If it fails, pokefetch goes random.
# (absolute path: hyprland does not always inherit ~/.local/bin in PATH)
[ -x "$HOME/.local/bin/poke-theme" ] && "$HOME/.local/bin/poke-theme" rank -q >/dev/null 2>&1 9>&- &
# (hyprlock and the SDDM theme read their colours when they open -> no reload.
# This used to list rofi and wlogout too: both were uninstalled on 2026-08-19,
# when the launcher and the power menu became the shell's own.)
exit 0
