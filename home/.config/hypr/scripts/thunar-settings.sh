#!/usr/bin/env bash
# Leaves Thunar configured like the rest of the desktop. Idempotent: it can be
# run again whenever you like, and it is what you run when setting the machine
# up from scratch (or the tower) so as not to reconfigure it by hand through
# the menu.
#
# WHY A SCRIPT AND NOT A CONFIG FILE: Thunar 4.20 NO LONGER reads
# ~/.config/Thunar/thunarrc. All its configuration lives in xfconf, channel
# `thunar`, and the on-disk backing is
# ~/.config/xfce4/xfconf/xfce-perchannel-xml/thunar.xml -- which xfconfd
# writes whenever it feels like it, so editing it by hand is no use: it gets
# overwritten. The first attempt in this batch was precisely a complete
# thunarrc, and Thunar ignored all of it without a word (not even a console
# warning): the window came up with the classic menu bar and no client-side
# decoration, i.e. with the factory defaults.
#
# Close it first (`thunar -q`): with a window open, Thunar rewrites the last-*
# keys on exit and tramples whatever was set here.
set -uo pipefail

. "$HOME/.config/hypr/scripts/lang.sh" 2>/dev/null || tr_() { printf '%s' "$1"; }

fallos=0

poner() { # poner <type> <property> <value>
	local tipo="$1" prop="$2" valor="$3"
	if ! xfconf-query -c thunar -p "$prop" -n -t "$tipo" -s "$valor" 2>/dev/null; then
		echo "$(tr_ "  no se pudo poner $prop=$valor ($tipo)" "  Could not set $prop=$valor ($tipo)")" >&2
		fallos=$((fallos + 1))
	fi
}

# --- View ---
# Icons at 100 %: with tumbler and ffmpegthumbnailer behind it, the grid is a
# contact sheet, which is what you open a folder of images or screenshots for.
# The detailed list is still one keystroke away (Ctrl+2).
poner string /default-view                    ThunarIconView
poner string /last-view                       ThunarIconView
poner string /last-icon-view-zoom-level       THUNAR_ZOOM_LEVEL_100_PERCENT
poner string /last-details-view-zoom-level    THUNAR_ZOOM_LEVEL_38_PERCENT
poner string /last-compact-view-zoom-level    THUNAR_ZOOM_LEVEL_38_PERCENT
poner string /last-sort-column                THUNAR_COLUMN_NAME
poner string /last-sort-order                 GTK_SORT_ASCENDING
poner bool   /last-details-view-fixed-columns false
poner bool   /misc-folders-first              true
poner bool   /misc-text-beside-icons          false

# --- Window ---
# CSD no matter what: Hyprland draws no title bar and no borders (border_size
# = 0, law 2: focus is marked with light), so without client-side decoration
# the window is literally left without a close button. The menu bar moves into
# the hamburger button, which is where it lives in the rest of the desktop.
poner bool   /misc-use-csd                    true
poner bool   /last-menubar-visible            false
poner bool   /last-statusbar-visible          true
poner bool   /misc-remember-geometry          true
poner bool   /misc-change-window-icon         true
poner bool   /last-window-maximized           false
poner int    /last-window-width               1280
poner int    /last-window-height              800
poner string /misc-window-title-style         THUNAR_WINDOW_TITLE_STYLE_FOLDER_NAME_WITHOUT_THUNAR_SUFFIX

# Toolbar: navigation, path and search. Out go the zoom buttons and the three
# view buttons (the single switcher already does that job) so the toolbar is
# not a row of icons nobody looks at.
poner string /last-location-bar               ThunarLocationButtons
poner string /last-toolbar-visible-buttons \
	"menu:1,back:1,forward:1,open-parent:1,open-home:1,new-tab:0,new-window:0,toggle-split-view:1,undo:0,redo:0,zoom-out:0,zoom-in:0,zoom-reset:0,view-as-icons:0,view-as-detailed-list:0,view-as-compact-list:0,view-switcher:1,location-bar:1,reload:0,search:1"

# --- Side pane ---
poner string /last-side-pane                  ThunarShortcutsPane
poner int    /last-separator-position         186
poner bool   /shortcuts-icon-emblems          true
poner bool   /misc-tree-lines-in-tree-sidepane true
# The image preview in its own column (Ctrl+Shift+I), not embedded in the side
# pane: when going through screenshots you need it big.
poner string /misc-image-preview-mode         THUNAR_IMAGE_PREVIEW_MODE_STANDALONE
poner bool   /last-image-preview-visible      false

# --- Thumbnails ---
# Without the frame tumbler draws around them: it dates from the days of light
# backgrounds, and here it only muddies the edge of every thumbnail.
poner bool   /misc-thumbnail-draw-frames      false
poner bool   /misc-image-size-in-statusbar    true
poner string /misc-folder-item-count          THUNAR_FOLDER_ITEM_COUNT_ONLY_LOCAL

# --- Tabs and navigation ---
poner bool   /misc-open-new-window-as-tab     true
poner bool   /misc-switch-to-new-tab          false
poner bool   /misc-always-show-tabs           false
poner bool   /misc-middle-click-in-tab        true
poner bool   /misc-tab-close-middle-click     true
poner bool   /misc-full-path-in-tab-title     false
poner bool   /misc-horizontal-wheel-navigates true
poner bool   /misc-ctrl-scroll-wheel-to-zoom  true
poner bool   /misc-vertical-split-pane        false
poner bool   /misc-always-enable-split-view   false
poner bool   /misc-expandable-folders         true
poner bool   /last-restore-tabs               true
poner bool   /last-show-hidden                false
poner string /misc-recursive-search           THUNAR_RECURSIVE_SEARCH_LOCAL

# --- Behaviour ---
# Double click to open: with single click, a clumsy drag opens things.
poner bool   /misc-single-click               false
poner bool   /misc-case-sensitive             false
poner bool   /misc-volume-management          true
poner bool   /misc-exec-shell-scripts-by-default false
poner bool   /misc-show-delete-action         true
poner bool   /misc-confirm-move-to-trash      true
poner bool   /misc-confirm-close-multiple-tabs true
poner int    /misc-undo-redo-history-size     20
poner string /misc-parallel-copy-mode         THUNAR_PARALLEL_COPY_MODE_ONLY_LOCAL_SAME_DEVICES
poner string /misc-transfer-use-partial       THUNAR_USE_PARTIAL_MODE_REMOTE
poner string /misc-transfer-verify-file       THUNAR_VERIFY_FILE_MODE_REMOTE

if [ "$fallos" -gt 0 ]; then
	echo "$(tr_ "thunar-settings: $fallos ajuste(s) no se pudieron aplicar" "thunar-settings: could not apply $fallos setting(s)")" >&2
	exit 1
fi
echo "$(tr_ "thunar-settings: aplicado" "thunar-settings: applied")"
