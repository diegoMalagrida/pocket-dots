#
# ~/.bash_profile
#

[[ -f ~/.bashrc ]] && . ~/.bashrc

if uwsm check may-start; then
	exec uwsm start hyprland.desktop
fi

# Put there by the uv installer. It is guarded because if uv is not installed
# the file does not exist and bash spits out "No such file or directory" on
# EVERY session start; it showed up on a clean machine before installing
# anything.
[ -r "$HOME/.local/bin/env" ] && . "$HOME/.local/bin/env"
