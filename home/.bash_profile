#
# ~/.bash_profile
#

[[ -f ~/.bashrc ]] && . ~/.bashrc

if uwsm check may-start; then
	exec uwsm start hyprland.desktop
fi

# Lo pone el instalador de uv. Va con guarda porque si uv no esta instalado el
# fichero no existe y bash escupe "No such file or directory" en CADA arranque
# de sesion; se veia en una maquina limpia antes de instalar nada.
[ -r "$HOME/.local/bin/env" ] && . "$HOME/.local/bin/env"
