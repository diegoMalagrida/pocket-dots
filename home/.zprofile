#
# ~/.zprofile -- SOLO para shells de login de zsh (o sea: entrar por una tty).
# Las terminales del escritorio no lo leen (kitty arranca `zsh` a secas, no
# `zsh -l`), asi que nada de esto afecta al dia a dia.
#
# Por que existe
# -------------
# La noche que la torre se quedo sin escritorio no habia NADA capaz de
# arrancarlo a mano. El bloque de rescate estaba -y sigue estando- en
# ~/.bash_profile, pero el instalador pone zsh como shell por defecto
# (`chsh -s zsh` en la fase final) y zsh NO lee .bash_profile nunca. Con lo
# cual: si el gestor de inicio de sesion no levanta, entras por tty1, escribes
# la contrasena, y ahi se acaba el viaje. Hubo que llegar hasta la linea del
# kernel en el gestor de arranque para salir de esa.
#
# Esto NO es un autologin y NO sustituye a sddm. Es la red de abajo.
#
# Por que es seguro (o sea: por que no te quedas sin consola de texto)
# -------------------------------------------------------------------
# Las condiciones no las pongo yo, las pone `uwsm check may-start`, y son
# exactamente las que hacen falta:
#   - solo desde un shell de LOGIN,
#   - solo en la VT 1 -> las tty2..tty6 siguen siendo consolas normales SIEMPRE,
#   - solo si el sistema llego a graphical.target (si arrancas a multi-user
#     para reparar algo, esto no se dispara; y no se queda esperando los 60 s
#     de rigor porque uwsm corta en cuanto ve que el target ni siquiera esta
#     encolado),
#   - y solo si no hay ya un compositor o un graphical-session* activo.
# Con sddm funcionando esto no llega a ejecutarse: sddm ocupa la VT y no hay
# ningun login de shell de por medio.

if uwsm check may-start; then

    # Salida de emergencia, y es la parte importante del asunto.
    #
    # Si lo que esta roto es Hyprland, `exec` te saca de la sesion en cuanto
    # falla, getty vuelve a pintar el login, entras otra vez, y vuelta a
    # empezar: un bucle en el que nunca llegas a ver un prompt. Seria cambiar
    # un problema por otro peor.
    #
    # Con esto, dos segundos y cualquier tecla te dejan en zsh. Si no tocas
    # nada, arranca el escritorio y no te enteras.
    #
    # El mensaje va en ASCII pelado a proposito: esto se lee en la consola del
    # kernel, en el peor dia posible, y no es momento de averiguar si las
    # tildes se ven.
    _zp_arrancar=1
    if [[ -o interactive ]]; then
        # Vaciar antes lo que quedara escrito en el buffer del teclado. Sin
        # esto, el Enter de mas que sueltas al escribir la contrasena lo
        # recogeria el `read` de abajo y cancelaria el arranque sin querer.
        # El tope de 32 no es decorativo: si la entrada esta en EOF, `read -t 0`
        # devuelve 0 para siempre y esto seria un cuelgue en el arranque.
        integer _zp_n=0
        while (( _zp_n < 32 )) && read -t 0 -k 1 -s 2>/dev/null; do (( _zp_n++ )); done
        unset _zp_n

        print -n -- "Arrancando Hyprland. Pulsa una tecla en 2 s para quedarte en la consola... "
        if read -t 2 -k 1 -s 2>/dev/null; then
            _zp_arrancar=0
            print -- ""
            print -- "Consola. Para arrancarlo a mano:  uwsm start hyprland.desktop"
            print -- "Para ver que falla:               ~/dotfiles/diagnose"
        else
            print -- ""
        fi
    fi

    if (( _zp_arrancar )); then
        unset _zp_arrancar
        exec uwsm start hyprland.desktop
    fi
    unset _zp_arrancar
fi

# Lo pone el instalador de uv. Con guarda: si uv no esta instalado el fichero
# no existe y el shell escupe "No such file or directory" en CADA arranque de
# sesion; se veia en una maquina limpia antes de instalar nada.
[ -r "$HOME/.local/bin/env" ] && . "$HOME/.local/bin/env"
