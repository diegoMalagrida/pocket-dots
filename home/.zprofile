#
# ~/.zprofile -- ONLY for zsh login shells (that is: logging in on a tty).
# The desktop's terminals do not read it (kitty starts plain `zsh`, not
# `zsh -l`), so none of this affects day-to-day use.
#
# Why it exists
# -------------
# The night the tower was left without a desktop there was NOTHING able to
# start it by hand. The rescue block was -and still is- in ~/.bash_profile,
# but the installer makes zsh the default shell (`chsh -s zsh` in the final
# phase) and zsh NEVER reads .bash_profile. Which means: if the login manager
# does not come up, you log in on tty1, type the password, and that is the end
# of the road. Getting out of that took going all the way to the kernel command
# line in the boot loader.
#
# This is NOT an autologin and does NOT replace sddm. It is the safety net
# underneath.
#
# Why it is safe (that is: why you are not left without a text console)
# ---------------------------------------------------------------------
# I do not set the conditions, `uwsm check may-start` does, and they are
# exactly the ones that are needed:
#   - only from a LOGIN shell,
#   - only on VT 1 -> tty2..tty6 remain ordinary consoles ALWAYS,
#   - only if the system reached graphical.target (if you boot into multi-user
#     to repair something, this does not fire; and it does not sit waiting the
#     customary 60 s because uwsm cuts out as soon as it sees the target is not
#     even queued),
#   - and only if there is no compositor or graphical-session* already active.
# With sddm working this never gets to run: sddm holds the VT and there is no
# shell login involved.

if uwsm check may-start; then

    # Emergency exit, and it is the important part of the whole thing.
    #
    # If what is broken is Hyprland, `exec` throws you out of the session as
    # soon as it fails, getty paints the login again, you log in again, and
    # round it goes: a loop in which you never get to see a prompt. That would
    # be trading one problem for a worse one.
    #
    # With this, two seconds and any key leave you in zsh. If you touch
    # nothing, the desktop starts and you never notice.
    #
    # The message is in bare ASCII on purpose: this is read on the kernel
    # console, on the worst possible day, and it is no time to find out
    # whether accented letters display.
    _zp_arrancar=1
    if [[ -o interactive ]]; then
        # First drain whatever was left in the keyboard buffer. Without this,
        # the extra Enter you let slip while typing the password would be
        # picked up by the `read` below and cancel the start by accident.
        # The cap of 32 is not decorative: if input is at EOF, `read -t 0`
        # returns 0 forever and this would be a hang at boot.
        integer _zp_n=0
        while (( _zp_n < 32 )) && read -t 0 -k 1 -s 2>/dev/null; do (( _zp_n++ )); done
        unset _zp_n

        # The words follow the rice language, read from the same file hyprlock
        # and the scripts read (lang.sh). Without it, Spanish, as always.
        . "$HOME/.config/hypr/scripts/lang.sh" 2>/dev/null || tr_() { print -rn -- "$1"; }
        print -n -- "$(tr_ "Arrancando Hyprland. Pulsa una tecla en 2 s para quedarte en la consola... " \
                           "Starting Hyprland. Press a key within 2 s to stay on the console... ")"
        if read -t 2 -k 1 -s 2>/dev/null; then
            _zp_arrancar=0
            print -- ""
            print -- "$(tr_ "Consola. Para arrancarlo a mano:  uwsm start hyprland.desktop" \
                             "Console. To start it by hand:     uwsm start hyprland.desktop")"
            print -- "$(tr_ "Para ver que falla:               ./diagnose, en la carpeta del repo" \
                             "To see what is failing:           ./diagnose, in the repo's folder")"
        else
            print -- ""
        fi
        unset RICE_LANG; unfunction tr_ 2>/dev/null
    fi

    if (( _zp_arrancar )); then
        unset _zp_arrancar
        exec uwsm start hyprland.desktop
    fi
    unset _zp_arrancar
fi

# Put there by uv's installer. Guarded: if uv is not installed the file does
# not exist and the shell spits out "No such file or directory" at EVERY
# session start; it showed on a clean machine before anything was installed.
[ -r "$HOME/.local/bin/env" ] && . "$HOME/.local/bin/env"
