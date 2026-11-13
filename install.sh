#!/usr/bin/env bash
#
# install.sh -- brings the whole desktop up from a fresh Arch install.
#
# All the new machine needs is Arch and git:
#
#     git clone https://github.com/diegoMalagrida/pocket-dots
#     cd pocket-dots
#     ./install.sh
#
# It can be re-run as many times as you like: it does not redo what is already
# done, and it never overwrites a file of yours without first saving it to
# ~/.dotfiles-backup/<date>/.
#
# It does NOT install or configure a kernel, a bootloader or microcode, and it
# never edits /boot, the partitions or fstab. The only thing that may land in
# /boot during a run is what your OWN kernel's upgrade writes there when the
# system is brought up to date (pacman -Syu), exactly as it would without us.
#
# Every real run is logged to ~/.local/state/pocket-dots/install.log, and ends
# with a list of what was left out and what failed.

set -uo pipefail

# A login always sets USER, but a container, a cron job or `su` without -l may
# not, and under set -u the first "$USER" ended the whole run at the preflight
# (seen in a clean Arch container on 2026-11-01). The account name is what
# every use below means, so it is taken from the account itself when missing.
: "${USER:=$(id -un)}"
export USER

REPO="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
BACKUP="$HOME/.dotfiles-backup/$(date +%Y%m%d-%H%M%S)"
# Where the digest manifest lives: the sha256 of every file the repo and $HOME
# were last seen to AGREE on, so ./diagnose can say WHO moved and not just that
# something did. Spelled out from $HOME and deliberately NOT from
# $XDG_STATE_HOME: `verify` installs into a throwaway $HOME while the real
# XDG_STATE_HOME is still exported, and reading the variable would let a test
# run overwrite the real manifest -- the same trap adapt_home_paths guards
# against. ~/.local/state is gitignored, so it can never be committed either.
DIGESTS="$HOME/.local/state/dotfiles/digests"
DRY=0
ASSUME_YES=0
MODE=link            # link | copy
UI_LANG=             # es | en | it | pt; empty means "ask, or take the default"
DEFAULT_LANG=        # what is offered when nobody says; see current_lang()
FALLBACK_LANG=es     # what a MISSING key or file means: the strings are written
                     # in Spanish, so that is what every program falls back to
KEYBOARD_KEEP=       # a keyboard.lua that existed before 'config' replaced the dir
RESTORE_FROM=        # restore: the backup to put back; empty = pick it (see there)

# Where both scripts keep their own state: the run logs, the package baseline,
# the migration markers and the pointer to the last update's backup. Spelled
# out from $HOME for the same reason as DIGESTS above.
STATE_DIR="$HOME/.local/state/pocket-dots"
BASELINE="$STATE_DIR/packages.baseline"
LAST_UPDATE_PTR="$STATE_DIR/last-update"
LOG_FILE=""          # set by log_start; stays empty in a dry run, which logs nothing

# What the run has to say at the end. A warning printed twenty screens up is a
# warning nobody reads, so everything that failed or was left out is also
# collected here and listed again in the summary.
FAILED=()            # something the desktop needs did not happen -> exit 1
SKIPPED=()           # left out on purpose, or because you said no
KEPT_EDITS=()        # files of yours that were kept over the repo's version
REBOOT_REASON=""     # set when the running system no longer matches the disk
SUMMARY_DONE=0

# Files under system/etc that were renamed (they had Spanish names), old -> new,
# relative to /etc. See phase_system: the old one is moved aside.
declare -A RENAMED_ETC=(
    [UPower/UPower.conf.d/90-apagar-en-vez-de-agonizar.conf]=UPower/UPower.conf.d/90-power-off-instead-of-sleep.conf
    [sysctl.d/99-memoria-antibloqueo.conf]=sysctl.d/99-memory-anti-freeze.conf
    [sysctl.d/99-sysrq-rescate.conf]=sysctl.d/99-sysrq-rescue.conf
    [systemd/coredump.conf.d/00-limites.conf]=systemd/coredump.conf.d/00-limits.conf
    [systemd/journald.conf.d/00-limites.conf]=systemd/journald.conf.d/00-limits.conf
    [systemd/oomd.conf.d/99-antibloqueo.conf]=systemd/oomd.conf.d/99-anti-freeze.conf
    [systemd/system/paccache.service.d/desinstalados.conf]=systemd/system/paccache.service.d/uninstalled.conf
    [systemd/system/reflector.service.d/99-reintentos.conf]=systemd/system/reflector.service.d/99-retries.conf
)
REQUESTED_PHASES=()

# 'system' runs BEFORE 'config' on purpose, and this is the one thing in this
# list you must not reshuffle. Anything under $HOME that names a file in /etc --
# a PAM service, a drop-in, a theme the greeter reads -- has to find it already
# there. Laid down the other way round, the lock screen would spend the rest of
# the install pointing at something that does not exist yet, and on Arch a PAM
# service that is missing falls through to /etc/pam.d/other, which is pam_deny:
# a lock screen that opens with neither the face nor the password.
#
# The swap is free: phase_system reads nothing that phase_config writes -- it
# only walks $REPO/system -- while 'sddm' does read ~/.config, which is why
# that one stays where it was. It is not enough on its own either: you can
# still say no to the sudo prompt, or ask for 'config' by itself, so
# phase_config checks the service is really there and says so out loud.
ALL_PHASES=(base aur packages repos system config graphics services sddm spicetify final)
# Neither of these is part of the default run. 'restore' undoes what 'config'
# did; 'digests' only re-reads the manifest, which 'config' already writes at
# the end -- you name it by hand after copying files INTO the repo.
ON_DEMAND_PHASES=(restore digests)

# Old Spanish names, kept working so nothing that used them breaks.
canonical_phase() {
    case "$1" in
        paquetes)  printf 'packages' ;;
        sistema)   printf 'system'   ;;
        servicios) printf 'services' ;;
        restaurar) printf 'restore'  ;;
        *)         printf '%s' "$1"  ;;
    esac
}

# ----------------------------------------------------------------- presentation

if [ -t 1 ] && [ "${NO_COLOR:-}" = "" ]; then
    C_TIT=$'\033[1;34m'; C_OK=$'\033[32m'; C_WARN=$'\033[33m'
    C_BAD=$'\033[31m';   C_DIM=$'\033[2m'; C_OFF=$'\033[0m'
else
    C_TIT=; C_OK=; C_WARN=; C_BAD=; C_DIM=; C_OFF=
fi

heading() { printf '\n%s== %s ==%s\n' "$C_TIT" "$*" "$C_OFF"; }
ok()      { printf '  %sok%s   %s\n' "$C_OK" "$C_OFF" "$*"; }
skip()    { printf '  %s--%s   %s%s%s\n' "$C_DIM" "$C_OFF" "$C_DIM" "$*" "$C_OFF"; }
warn()    { printf '  %swarn%s %s\n' "$C_WARN" "$C_OFF" "$*"; }
err()     { printf '  %sERROR%s %s\n' "$C_BAD" "$C_OFF" "$*" >&2; }
die()     { err "$*"; FAILED+=("$*"); exit 1; }

# The two ways something ends up in the summary. failed() is for what the
# desktop needed and did not get, and makes the run exit non-zero; left_out()
# is for what was skipped on purpose -- a conflict settled in your favour, a
# step you said no to.
failed()   { err "$*"; FAILED+=("$*"); }
left_out() { warn "$*"; SKIPPED+=("$*"); }

# Runs a command, honouring --dry-run.
run() {
    if [ "$DRY" = 1 ]; then
        printf '  %s[dry]%s %s\n' "$C_DIM" "$C_OFF" "$*"
        return 0
    fi
    "$@"
}

# Where a question is printed. While the run is being logged, stdout and
# stderr go through tee, and a prompt with no newline at the end would sit in
# its buffer; so questions go straight to the terminal the run started on.
prompt_fd() { printf '%s' "${LOG_ERR:-2}"; }

ask() {
    [ "$ASSUME_YES" = 1 ] && return 0
    [ "$DRY" = 1 ] && return 0
    local answer
    read -r -p "  $1 [y/N] " answer 2>&"$(prompt_fd)"
    [ -n "$LOG_FILE" ] && printf '  (asked: %s -> %s)\n' "$1" "${answer:-N}" >> "$LOG_FILE"
    [[ "$answer" =~ ^[sSyY]$ ]]
}

# The same question for the few things that could lock you out of your own
# machine. Here -y and --dry-run answer NO: an unattended run must never pick
# the risky side of a choice on your behalf.
ask_risky() {
    [ "$ASSUME_YES" = 1 ] && return 1
    [ "$DRY" = 1 ] && return 1
    [ -t 0 ] || return 1
    local answer
    read -r -p "  $1 [y/N] " answer 2>&"$(prompt_fd)"
    [ -n "$LOG_FILE" ] && printf '  (asked: %s -> %s)\n' "$1" "${answer:-N}" >> "$LOG_FILE"
    [[ "$answer" =~ ^[sSyY]$ ]]
}

# pacman, yay and localectl translate their field names, and the parsers here
# look for the English ones. LC_ALL=C alone is not enough: yay reads LANGUAGE
# before LC_ALL (pacman does not), and on a desktop with LANGUAGE=es it printed
# "Conflictos con" and the AUR conflict check silently found nothing.
c_locale() { env -u LANGUAGE LC_ALL=C "$@"; }

# ----------------------------------------------------------------- run bookkeeping

# Temporary files and directories removed on exit, whatever the exit is.
EXIT_TMP=()
SUDO_KEEPALIVE_PID=""
LOG_TEE_PID=""

# One log per script, appended to, with a header per run so you can find the
# one that went wrong. Not in a dry run: a dry run changes nothing, and that
# includes ~/.local/state.
log_start() {
    local name="$1"
    [ "$DRY" = 1 ] && return 0
    mkdir -p "$STATE_DIR" 2>/dev/null || return 0
    LOG_FILE="$STATE_DIR/$name.log"
    # Trimmed from the front: the last few thousand lines are many runs' worth,
    # and a log nobody can open is no better than no log.
    if [ -f "$LOG_FILE" ] && [ "$(wc -l < "$LOG_FILE")" -gt 20000 ]; then
        tail -n 10000 "$LOG_FILE" > "$LOG_FILE.tmp.$$" && mv -f "$LOG_FILE.tmp.$$" "$LOG_FILE"
    fi
    {
        printf '\n===== %s  %s %s\n' "$(date '+%F %T')" "$name" "${RUN_ARGS[*]:-}"
        printf 'repo %s at %s, user %s, HOME %s, %s\n' "$REPO" \
            "$(git -C "$REPO" rev-parse --short HEAD 2>/dev/null || printf '?')" \
            "${USER:-$(id -un)}" "$HOME" \
            "$(sed -n 's/^PRETTY_NAME=//p' /etc/os-release 2>/dev/null | tr -d '"')"
    } >> "$LOG_FILE" 2>/dev/null || { LOG_FILE=""; return 0; }
    # The terminal is kept on two spare descriptors: questions go there (see
    # prompt_fd), and so does pacman's own output, which needs a real terminal
    # for its progress bars (see pkg_run).
    exec {LOG_OUT}>&1 {LOG_ERR}>&2
    exec > >(tee -a "$LOG_FILE") 2>&1
    LOG_TEE_PID=$!
}

# Puts the terminal back and gives tee a moment to write the last lines. Not
# an unbounded wait: anything started in the background that kept the pipe
# open would hang the end of the run forever.
log_stop() {
    [ -n "$LOG_TEE_PID" ] || return 0
    exec 1>&"$LOG_OUT" 2>&"$LOG_ERR"
    local i
    for i in 1 2 3 4 5 6 7 8 9 10; do
        kill -0 "$LOG_TEE_PID" 2>/dev/null || break
        sleep 0.1
    done
    LOG_TEE_PID=""
}

# Only one of install.sh / update.sh at a time: two of them laying files down
# or calling pacman over each other is how half-written configs happen.
#
# The flock is held by a small helper process, not by this shell. A lock
# descriptor in this shell would be inherited by everything it starts, and a
# Quickshell restarted at the end of an update lives on for days: it would
# keep the lock, and every later run would be "already running". The helper
# lets go when this shell exits, or when the token file is emptied (which is
# how update.sh hands the lock over before it re-executes itself).
LOCK_TOKEN=""
LOCK_HELPER=""
# Only "the lock is taken" (flock's 99) means another run: any other failure
# -- a runtime directory that does not exist, one that is not writable -- is
# a place problem, and the next place is tried. With none left the run goes
# on without a lock, and says so.
take_run_lock() {
    [ "$DRY" = 1 ] && return 0
    command -v flock >/dev/null 2>&1 || return 0
    local dir f i rc
    for dir in "${XDG_RUNTIME_DIR:-}" /tmp "$HOME/.cache"; do
        [ -n "$dir" ] && [ -d "$dir" ] && [ -w "$dir" ] || continue
        f="$dir/pocket-dots-$(id -u).lock"
        LOCK_TOKEN="$(mktemp "${TMPDIR:-/tmp}/pocket-lock.XXXXXXXX")" || { LOCK_TOKEN=""; return 0; }
        flock -n -E 99 "$f" sh -c 'echo held > "$2"
            while kill -0 "$1" 2>/dev/null && [ -s "$2" ]; do sleep 0.2; done' \
            sh "$$" "$LOCK_TOKEN" </dev/null >/dev/null 2>&1 &
        LOCK_HELPER=$!
        for i in $(seq 1 60); do
            [ -s "$LOCK_TOKEN" ] && return 0
            kill -0 "$LOCK_HELPER" 2>/dev/null || break
            sleep 0.05
        done
        [ -s "$LOCK_TOKEN" ] && return 0
        wait "$LOCK_HELPER" 2>/dev/null; rc=$?
        rm -f "$LOCK_TOKEN"; LOCK_TOKEN=""; LOCK_HELPER=""
        [ "$rc" = 99 ] && die "another install.sh or update.sh is already running (lock: $f)"
    done
    warn "could not take the run lock anywhere; carrying on without it"
}

release_run_lock() {
    [ -n "$LOCK_TOKEN" ] || return 0
    : > "$LOCK_TOKEN"
    local i
    for i in $(seq 1 20); do
        kill -0 "$LOCK_HELPER" 2>/dev/null || break
        sleep 0.05
    done
    rm -f "$LOCK_TOKEN"
    LOCK_TOKEN=""; LOCK_HELPER=""
}

# sudo once, at the start, and kept alive for the whole run. Without it the
# password prompt comes back in the middle of an AUR build twenty minutes in,
# and an unattended run just sits there. The keeper writes nowhere: anything
# holding the log pipe open would keep tee alive after the run.
sudo_begin() {
    [ "$DRY" = 1 ] && return 0
    [ -n "$SUDO_KEEPALIVE_PID" ] && return 0
    command -v sudo >/dev/null 2>&1 || return 1
    if ! sudo -v; then
        warn "sudo could not ask for your password here (is there a terminal?):"
        warn "every step that needs it will fail. Run this from a terminal."
        return 1
    fi
    ( while kill -0 "$$" 2>/dev/null; do
          sudo -n -v 2>/dev/null || exit 0
          sleep 50
      done ) </dev/null >/dev/null 2>&1 &
    SUDO_KEEPALIVE_PID=$!
}

cleanup_run() {
    [ -n "$SUDO_KEEPALIVE_PID" ] && kill "$SUDO_KEEPALIVE_PID" 2>/dev/null
    SUDO_KEEPALIVE_PID=""
    local d
    for d in "${EXIT_TMP[@]}"; do rm -rf -- "$d"; done
    EXIT_TMP=()
}

# What is left out, what was kept as yours, and what failed, at the very end,
# where you are looking when the run stops.
print_summary() {
    SUMMARY_DONE=1
    local s
    if [ ${#SKIPPED[@]} -gt 0 ]; then
        printf '\n  %sLeft out%s\n' "$C_WARN" "$C_OFF"
        for s in "${SKIPPED[@]}"; do printf '    - %s\n' "$s"; done
    fi
    if [ ${#KEPT_EDITS[@]} -gt 0 ]; then
        printf '\n  %sYour edits, kept%s\n' "$C_WARN" "$C_OFF"
        for s in "${KEPT_EDITS[@]}"; do printf '    - ~/%s\n' "$s"; done
    fi
    if [ ${#FAILED[@]} -gt 0 ]; then
        printf '\n  %sFailed%s\n' "$C_BAD" "$C_OFF"
        for s in "${FAILED[@]}"; do printf '    - %s\n' "$s"; done
    fi
    if [ -n "$REBOOT_REASON" ]; then
        printf '\n  %sReboot needed:%s %s\n' "$C_WARN" "$C_OFF" "$REBOOT_REASON"
    fi
    if [ -n "$LOG_FILE" ] && [ ${#FAILED[@]} -gt 0 ]; then
        printf '\n  The whole run, pacman included, is in %s\n' "$LOG_FILE"
    fi
}

on_exit() {
    local rc=$?
    cleanup_run
    # update.sh tidies its backup here too, so a run that stopped half-way
    # does not leave an empty one as "the last update" for restore to undo.
    declare -F on_exit_hook >/dev/null && on_exit_hook
    # A run that stopped half-way (die) still says what it got through.
    if [ "$SUMMARY_DONE" = 0 ] && { [ "$rc" -ne 0 ] || [ ${#FAILED[@]} -gt 0 ]; }; then
        print_summary
    fi
    release_run_lock
    log_stop
    return "$rc"
}

# Everything a real run needs before its first phase, shared by both scripts.
start_run() {
    trap on_exit EXIT
    take_run_lock
    log_start "$1"
}

# After pacman: does the running system still match what is on disk?
check_reboot_needed() {
    [ "$DRY" = 1 ] && return 0
    if [ ! -d "/usr/lib/modules/$(uname -r)" ]; then
        REBOOT_REASON="the kernel was upgraded; the running one has no modules on disk any more"
        return 0
    fi
    local pid
    pid="$(pgrep -u "$(id -u)" -x Hyprland 2>/dev/null | head -1)"
    if [ -n "$pid" ] && grep -qE '\.so[^ ]* \(deleted\)$' "/proc/$pid/maps" 2>/dev/null; then
        REBOOT_REASON="Hyprland is running on libraries pacman just replaced: log out and back in soon"
    fi
}

# The language question. It is not a yes/no, so it cannot go through ask(), but
# it plays by the same rules: --lang settles it, -y and --dry-run do not ask,
# and what nobody chooses comes from the machine, in this order:
#
#   1. what the desktop speaks right now. Without this, re-running the
#      installer without --lang silently undid a language picked in Settings:
#      the default was hard-wired to 'es' and set_language_quickshell dutifully
#      wrote it back.
#   2. on a fresh machine, your locale: Spanish for an es_* locale, Italian for
#      it_*, English for anything else. It used to be Spanish for everybody,
#      which is how people who do not speak it ended up with a desktop they
#      could not read. Portuguese is not picked from the locale: only the
#      shell speaks it, the lock screen and the scripts would stay in Spanish.
#
# The usual order, LC_ALL over LC_MESSAGES over LANG. C and POSIX are English,
# and they also switch LANGUAGE off, as gettext does; otherwise LANGUAGE, a
# priority list (es:en), speaks first, and only its first entry counts.
locale_lang() {
    local eff="${LC_ALL:-${LC_MESSAGES:-${LANG:-}}}" first="${LANGUAGE:-}" l
    case "$eff" in C|C.*|POSIX) printf 'en'; return 0 ;; esac
    first="${first%%:*}"
    for l in "$first" "$eff"; do
        [ -n "$l" ] || continue
        case "$l" in
            es|es_*|es.*|es@*) printf 'es' ;;
            it|it_*|it.*|it@*) printf 'it' ;;
            *) printf 'en' ;;
        esac
        return 0
    done
    printf 'en'
}

current_lang() {
    local rice="$HOME/.config/quickshell-rice.json" cur=""
    if [ -f "$rice" ]; then
        if command -v jq >/dev/null 2>&1; then
            cur="$(jq -r '.language // empty' "$rice" 2>/dev/null)"
        else
            cur="$(sed -n 's/.*"language"[[:space:]]*:[[:space:]]*"\([a-z]*\)".*/\1/p' "$rice" | head -1)"
        fi
    fi
    case "$cur" in
        es|en|it|pt) printf '%s' "$cur" ;;
        # The file is there but says nothing: Quickshell reads that as Spanish,
        # so that is what this desktop speaks. Only a machine with no file at
        # all has nothing to keep, and gets its locale's.
        *) if [ -f "$rice" ]; then printf '%s' "$FALLBACK_LANG"; else locale_lang; fi ;;
    esac
}

ask_lang() {
    [ -n "$UI_LANG" ] && return 0
    DEFAULT_LANG="$(current_lang)"
    UI_LANG="$DEFAULT_LANG"
    [ "$ASSUME_YES" = 1 ] && return 0
    [ "$DRY" = 1 ] && return 0
    [ -t 0 ] || return 0          # no keyboard (a pipe, a cron job): the default
    local answer
    read -r -p "  language for the desktop, es, en, it or pt? [$DEFAULT_LANG] " answer 2>&"$(prompt_fd)"
    case "$answer" in
        en|EN) UI_LANG=en ;;
        es|ES) UI_LANG=es ;;
        it|IT) UI_LANG=it ;;
        pt|PT) UI_LANG=pt ;;
        # A bare Enter = whatever the desktop already spoke. And 'es' typed by hand
        # has to ASSIGN: once the default became what is installed, an empty case
        # here left UI_LANG on 'en' and what you asked for was ignored.
        '') ;;
        *) warn "'$answer' is not es, en, it or pt; keeping $DEFAULT_LANG" ;;
    esac
}

# --lang, validated where it is read. Not a subshell helper on purpose: die()
# inside $(...) only kills the subshell and the run would carry on with nothing
# set.
set_lang() {
    case "$1" in
        es|en|it|pt) UI_LANG="$1" ;;
        *) die "unknown language: $1  (only 'es', 'en', 'it' or 'pt')" ;;
    esac
}

# ----------------------------------------------------------------- arguments

usage() {
    cat <<'USAGE'
Usage: install.sh [options] [phase...]

Options:
  -n, --dry-run     show what it would do without touching anything
  -y, --yes         never ask (for unattended runs)
      --copy        copy the configs instead of symlinking them
      --link        symlink the configs into the repo (default)
      --lang es|en|it|pt
                    what the desktop speaks (default: your locale's, Spanish for
                    es_*, Italian for it_* and English otherwise; it asks if you
                    do not say, and Settings changes it later anyway). pt only
                    translates the shell: the rest stays in Spanish
  -h, --help        this

Phases (if you name none, all of them run in this order):
  base        preflight checks: Arch, network, sudo, not-root
  aur         builds yay if it is missing
  packages    installs pacman.txt + extra.txt + aur.txt
  repos       clones oh-my-zsh, powerlevel10k and the zsh plugins
  system      copies system/ into /etc  (asks for sudo, and comes before
              config so nothing in $HOME points at a file in /etc that is
              not there yet)
  config      puts home/ into your $HOME (symlinks or copies, with backup)
  graphics    detects the graphics card(s) and installs their drivers
  services    enables what is in packages/services.txt
  sddm        installs the hyprisland login theme  (asks for sudo)
  spicetify   injects the theme into Spotify  (asks for sudo once)
  final       fonts, default shell, groups, first pywal palette, sprites

Separate phases, only if you name them:
  restore [backup]
              undoes the last update if there is one still to undo, and
              otherwise 'config': removes the symlinks to the repo, moves
              aside the copies that are still exactly the repo's, and puts
              back what you had before the first install, from
              ~/.dotfiles-backup. It lists the backups first; name one (its
              folder name or path) to put back that one instead
  digests     writes down which files the repo and $HOME currently agree on,
              so ./diagnose can tell "changed here" from "changed there".
              Run it after copying files BY HAND into the repo. 'config'
              already does it at the end of its own run.

Examples:
  ./install.sh -n                 see the whole plan without running it
  ./install.sh --lang en          bring the desktop up in English
  ./install.sh config             just lay the dotfiles down again
  ./install.sh digests            after copying files by hand into the repo
  ./install.sh packages services  only packages and services
  ./install.sh restore            go back to how things were

Separate diagnostics:
  ./diagnose                      says what is missing or will not start, read-only
USAGE
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    RUN_ARGS=("$@")
    while [ $# -gt 0 ]; do
        case "$1" in
            -n|--dry-run) DRY=1 ;;
            -y|--yes|--si) ASSUME_YES=1 ;;
            --copy|--copiar) MODE=copy ;;
            --link|--enlazar) MODE=link ;;
            --lang|--idioma)
                shift; [ $# -gt 0 ] || die "--lang needs a value: es, en, it or pt"
                set_lang "$1" ;;
            --lang=*|--idioma=*) set_lang "${1#*=}" ;;
            -h|--help|--ayuda) usage; exit 0 ;;
            --from)
                shift; [ $# -gt 0 ] || die "--from needs a backup folder"
                RESTORE_FROM="$1" ;;
            -*) die "unknown option: $1  (try --help)" ;;
            *)
                # A backup to restore can follow 'restore', as a path or as
                # the folder's name under ~/.dotfiles-backup.
                if [[ " ${REQUESTED_PHASES[*]:-} " == *" restore "* ]] \
                   && { [ -d "$1" ] || [ -d "$HOME/.dotfiles-backup/$1" ]; }; then
                    RESTORE_FROM="$1"
                else
                    REQUESTED_PHASES+=("$(canonical_phase "$1")")
                fi ;;
        esac
        shift
    done

    if [ ${#REQUESTED_PHASES[@]} -eq 0 ]; then
        PHASES=("${ALL_PHASES[@]}")
    else
        for f in "${REQUESTED_PHASES[@]}"; do
            [[ " ${ALL_PHASES[*]} ${ON_DEMAND_PHASES[*]} " == *" $f "* ]] \
                || die "unknown phase: $f  (try --help)"
        done
        PHASES=("${REQUESTED_PHASES[@]}")
    fi
fi

doing() { [[ " ${PHASES[*]:-} " == *" $1 "* ]]; }

# ----------------------------------------------------------------- helpers

# Saves whatever is at the destination path before replacing it. Symlinks that
# already point where they should are left alone, which is what makes this
# script genuinely idempotent.
save_aside() {
    local dest="$1"
    [ -e "$dest" ] || [ -L "$dest" ] || return 0
    local rel="${dest#"$HOME"/}"
    local saved="$BACKUP/$rel"
    run mkdir -p "$(dirname "$saved")" || die "cannot prepare a backup for $dest"
    run mv -- "$dest" "$saved" || die "cannot back up $dest; stopping before replacement"
    printf '       %s(saved to %s)%s\n' "$C_DIM" "${saved/#$HOME/\~}" "$C_OFF"
}

# Rewrites the /home/diego spelled out inside the repo's own files so they work
# for whoever is installing.
#
# WHY THIS EXISTS. A good part of the rice points at ~/.cache/wal with an
# ABSOLUTE path, and it has to: kitty's `include`, the GTK and
# satty `@import url(file://...)`, hyprlock's lock background... none of them
# expand `~` or `$HOME`, so a relative path would be resolved against whatever
# directory the program happened to start in. On diego's machine that absolute
# path is right by definition; on anyone else's it points at a home that does
# not exist, and the result is a desktop that comes up in default colours with
# nothing failing out loud.
#
# It was worse than colours: `sddm-hyprisland/install.sh` had its own source
# directory hardcoded, so the whole `sddm` phase died with "cannot stat
# /home/diego/.config/sddm-hyprisland/Main.qml", and
# `luminous-autoselect.service` pointed its ExecStart at a binary under
# /home/diego that is not there.
#
# This runs at the START of `config`, before anything is deployed, so every
# phase after it -services, sddm, final- sees files that already say
# the right thing. It rewrites the repo tree itself, which is deliberate and
# the same thing the symlink repointing already did: `git diff` shows it, and
# update.sh knows these rewrites well enough to set them aside when it pulls.

# True when adapt_home_paths has work to do: $HOME is not /home/diego and it
# really is the installing user's home.
#
# That second half is a GUARD, and not a paranoid one: adapting REWRITES THE
# REPO, so it may only happen when $HOME really is the installing user's home.
# A test harness that runs the config phase with HOME pointing at a temporary
# directory, without this check the first pass left the whole repo pointing at a
# /tmp/tmp.XXXX that vanished when the test finished: 20 files and 3 symlinks
# broken, silently and without anything failing. It actually happened.
home_paths_need_adapting() {
    [ "$HOME" != /home/diego ] || return 1
    local passwd_home
    passwd_home="$(getent passwd "${USER:-$(id -un)}" 2>/dev/null | cut -d: -f6)"
    [ -n "$passwd_home" ] && [ "$HOME" = "$passwd_home" ]
}

# The one substitution adapt_home_paths makes, as a sed script. A \, # or & in
# $HOME is escaped so it cannot end or bend the expression.
home_paths_sed() {
    printf 's#/home/diego#%s#g' "$(printf '%s' "$HOME" | sed 's/[\\#&]/\\&/g')"
}

adapt_home_paths() {
    [ "$HOME" = /home/diego ] && return 0
    if ! home_paths_need_adapting; then
        skip "not adapting paths: HOME ($HOME) is not $USER's home"
        return 0
    fi

    local n_files=0 n_links=0 f link target expr
    expr="$(home_paths_sed)"

    # 1) contents. Text files only, and never the wallpapers or the .git.
    while IFS= read -r f; do
        grep -Iq "/home/diego" "$f" 2>/dev/null || continue
        run sed -i "$expr" "$f"
        n_files=$((n_files + 1))
    done < <(find "$REPO/home" -type f \
                  -not -path "*/.git/*" \
                  -not -path "*/Pictures/*" \
                  -not -path "*/share/fonts/*" 2>/dev/null)

    # 2) symlinks. These have to stay absolute -a relative one would resolve
    #    against the repo instead of your $HOME- so they get repointed.
    while IFS= read -r link; do
        target="$(readlink "$link")"
        case "$target" in
            /home/diego/*) run ln -sfn "$HOME${target#/home/diego}" "$link" ;;
            *) continue ;;
        esac
        n_links=$((n_links + 1))
    done < <(find "$REPO/home" -type l 2>/dev/null)

    if [ $((n_files + n_links)) -gt 0 ]; then
        ok "adapted to $HOME: $n_files files and $n_links symlinks rewritten"
        warn "that leaves changes in the repo: 'git diff' will show them,"
        warn "and ./update.sh sets them aside on its own when it pulls"
    fi
}

# ----------------------------------------------------------------- three-way sync
#
# Shared by install.sh (--copy mode, and the trees that are always copied:
# ~/.local/bin, fonts, icons...) and by update.sh. A copied file can be in one
# of three states, and the digest manifest (see digests_write) is what tells
# them apart:
#
#     $HOME == repo                         nothing to do
#     $HOME == manifest, repo moved         you never touched it: replace it,
#                                           saving the old one first
#     $HOME moved, repo == manifest         your edit: keep it
#     both moved (or no manifest entry)     keep yours, put ours next to it
#                                           as <file>.new
#
# Before this, a second `./install.sh --copy` moved every one of your copied
# configs into a backup and laid the repo's down again: every edit reverted,
# and files of yours that live next to ours (efectos.lua, monitors) gone from
# the live tree.

# Files that set-wallpaper.sh and the *-pywal* helpers rewrite every time the
# wallpaper or palette changes. Overwriting them with whatever snapshot happens
# to be in git would flash stale colours until the next wallpaper switch.
is_pywal_generated() {
    case "$1" in
        .gtkrc-2.0|.config/gtkrc-2.0) return 0 ;;
        .config/gtk-3.0/gtk.css|.config/gtk-4.0/gtk.css) return 0 ;;
        .config/gtk-3.0/settings.ini|.config/gtk-4.0/settings.ini) return 0 ;;
        .config/kdeglobals) return 0 ;;
        .config/qt5ct/qt5ct.conf|.config/qt6ct/qt6ct.conf) return 0 ;;
        .config/qt5ct/colors/*|.config/qt6ct/colors/*) return 0 ;;
        .config/spicetify/Themes/termspot/color.ini|.config/spicetify/Themes/text/color.ini) return 0 ;;
        .config/yazi/flavors/pywal.yazi/*) return 0 ;;
        .config/vesktop/settings/*|.config/Vencord/settings/*|.config/equibop/settings/*|.config/VencordDesktop/settings/*) return 0 ;;
        *) return 1 ;;
    esac
}

# Files that belong to the user or hold live desktop state. If they already
# exist in $HOME they are never overwritten and never get a .new sidecar.
is_user_owned() {
    case "$1" in
        .gitconfig|.gitconfig.local) return 0 ;;
        .config/quickshell-rice.json) return 0 ;;
        .config/hypr/keyboard.lua|.config/hypr/efectos.lua) return 0 ;;
        .config/hypr/hypridle.conf|.config/hypr/language.conf|.config/hypr/hyprlock-lang.conf) return 0 ;;
        .config/hypr/monitors.conf|.config/hypr/monitors.lua|.config/hypr/workspaces.conf|.config/hypr/workspaces.lua) return 0 ;;
        .config/mimeapps.list|.config/user-dirs.dirs|.config/user-dirs.locale) return 0 ;;
        .config/gtk-3.0/bookmarks) return 0 ;;
        .config/poke-theme/*|.config/poke-equipo/*|.config/poke-team/*) return 0 ;;
        .config/spicetify/config-xpui.ini|.config/spotify/prefs) return 0 ;;
        .config/vlc/vlc-qt-interface.conf) return 0 ;;
        Pictures/wallpapers/*) return 0 ;;
        *) return 1 ;;
    esac
}

# The digest of a file, or of a symlink's TARGET when it is a symlink. Two
# symlinks that say the same thing are the same, whether or not what they
# point at exists, and whether it is a file or a directory: hashing through
# them made gtk-4.0/assets, a link to a directory, a "conflict" on every
# single update.
file_sha256() {
    local path="$1" sum
    if [ -L "$path" ]; then
        printf 'link:%s' "$(readlink -- "$path")" | sha256sum | awk '{print $1}'
        return 0
    fi
    [ -f "$path" ] || return 1
    sum="$(sha256sum -- "$path" 2>/dev/null)" || return 1
    printf '%s' "${sum%% *}"
}

# The manifest, loaded once into AGREED[rel]=sha.
declare -A AGREED=()
AGREED_LOADED=0
digests_load() {
    [ "$AGREED_LOADED" = 1 ] && return 0
    AGREED_LOADED=1
    [ -f "$DIGESTS" ] || return 0
    local line dsum drel
    while IFS= read -r line; do
        dsum="${line%% *}"; drel="${line#* }"; drel="${drel# }"
        [ ${#dsum} -eq 64 ] && [ -n "$drel" ] && AGREED["$drel"]="$dsum"
    done < "$DIGESTS"
}

# The paths under home/ that git ignores: runtime state that can sit inside
# the repo in --link mode (seeded files, .wants symlinks). They are never
# copied over your live state.
declare -A IGNORED_IN_REPO=()
IGNORED_LOADED=0
repo_ignored_load() {
    [ "$IGNORED_LOADED" = 1 ] && return 0
    IGNORED_LOADED=1
    command -v git >/dev/null 2>&1 && [ -f "$REPO/.gitignore" ] || return 0
    local ign
    while IFS= read -r ign; do
        [ -n "$ign" ] && IGNORED_IN_REPO["${ign#home/}"]=1
    done < <(cd "$REPO" && find home \( -type f -o -type l \) 2>/dev/null \
             | git check-ignore --no-index --stdin 2>/dev/null || true)
}

# Hooks update.sh fills in; install.sh leaves them empty. A function that does
# not exist is simply not called.
sync_backup_init()  { declare -F update_backup_init >/dev/null && update_backup_init; return 0; }
sync_record_added() { declare -F record_added >/dev/null && record_added "$1"; return 0; }
sync_old_base()     { declare -F update_old_base >/dev/null && update_old_base "$1"; return 0; }
sync_record_installed() { declare -F record_installed >/dev/null && record_installed "$1" "$2"; return 0; }

SYNC_UPDATED=0 SYNC_ADDED=0 SYNC_SAME=0 SYNC_KEPT=0 SYNC_CONFLICTS=0
SYNC_PROTECTED=0 SYNC_DELETED_KEPT=0
SYNC_LAST=""        # what sync_one did with the last file: same, added, updated...
SYNC_QUIET_NEW=0    # deploy_tree on install: one line per tree, not per new file
DELETED_KEPT=()

# The decision itself, on three digests, so update.sh's dry run can ask it
# about a commit that has not been pulled yet:
#   same | update | keep | conflict | foreign
sync_decide() {
    local rsum="$1" hsum="$2" base="$3"
    if [ -n "$rsum" ] && [ "$rsum" = "$hsum" ]; then printf same
    elif [ -z "$base" ]; then printf foreign
    elif [ "$hsum" = "$base" ]; then printf update
    elif [ "$rsum" = "$base" ]; then printf keep
    else printf conflict
    fi
}

# sync_one <rel> <src> <install|update>
#   rel  path relative to $HOME (and to $REPO/home)
#   src  the repo's copy
# install: a file missing here is laid down again (re-running config is how
#          you repair), and one we never deployed is saved aside and replaced
#          -- that is the first install over a file of yours.
# update:  a file you deleted stays deleted, and one with no baseline is
#          never replaced: ours goes next to it as .new.
sync_one() {
    local rel="$1" src="$2" how="$3" dest="$HOME/$1" rsum hsum base action sidecar ssum
    SYNC_LAST=same

    if is_pywal_generated "$rel" || is_user_owned "$rel"; then
        if [ -e "$dest" ] || [ -L "$dest" ] || [ "$rel" = .config/quickshell-rice.json ]; then
            SYNC_PROTECTED=$((SYNC_PROTECTED + 1)); SYNC_LAST=protected
            return 0
        fi
    fi

    if [ ! -e "$dest" ] && [ ! -L "$dest" ]; then
        if [ "$how" = update ] && [ -n "${AGREED[$rel]:-}" ]; then
            # It was here, both sides agreed on it, and now it is gone: you
            # deleted it. Putting it back on every update would be arguing.
            SYNC_DELETED_KEPT=$((SYNC_DELETED_KEPT + 1)); DELETED_KEPT+=("$rel")
            SYNC_LAST=deleted
            return 0
        fi
        sync_backup_init
        run mkdir -p "$(dirname "$dest")" || die "cannot prepare $dest"
        run cp -a -- "$src" "$dest" || die "cannot install $dest"
        sync_record_added "$rel"
        sync_record_installed "$rel" "$dest"
        [ "$SYNC_QUIET_NEW" = 1 ] || ok "$rel (new)"
        SYNC_ADDED=$((SYNC_ADDED + 1)); SYNC_LAST=added
        return 0
    fi

    rsum="$(file_sha256 "$src" || true)"
    hsum="$(file_sha256 "$dest" || true)"
    base="${AGREED[$rel]:-}"
    [ -n "$base" ] || base="$(sync_old_base "$rel")"
    action="$(sync_decide "$rsum" "$hsum" "$base")"
    [ "$action" = foreign ] && [ "$how" = install ] && action=replace-foreign

    case "$action" in
        same)
            SYNC_SAME=$((SYNC_SAME + 1))
            ;;
        update|replace-foreign)
            sync_backup_init
            save_aside "$dest"
            run mkdir -p "$(dirname "$dest")" || die "cannot prepare $dest"
            run cp -a -- "$src" "$dest" || die "cannot install $dest; the old one is in the backup"
            sync_record_installed "$rel" "$dest"
            if [ "$action" = update ]; then ok "$rel (updated)"; else ok "$rel (yours saved, ours in place)"; fi
            SYNC_UPDATED=$((SYNC_UPDATED + 1)); SYNC_LAST=updated
            ;;
        keep)
            skip "$rel (kept your local edits)"
            SYNC_KEPT=$((SYNC_KEPT + 1)); KEPT_EDITS+=("$rel"); SYNC_LAST=kept
            ;;
        *)
            # Yours moved and so did ours (or there is nothing to say which
            # moved): never overwrite, leave ours alongside.
            sidecar="$dest.new"
            ssum=""
            { [ -e "$sidecar" ] || [ -L "$sidecar" ]; } && ssum="$(file_sha256 "$sidecar" || true)"
            if [ "$ssum" != "$rsum" ]; then
                sync_backup_init
                if [ -e "$sidecar" ] || [ -L "$sidecar" ]; then
                    save_aside "$sidecar"
                else
                    sync_record_added "$rel.new"
                fi
                run cp -a -- "$src" "$sidecar" || die "cannot write $sidecar"
                sync_record_installed "$rel.new" "$sidecar"
            fi
            warn "$rel: edited here and changed in the repo -- kept yours, ours is ~/$rel.new"
            SYNC_CONFLICTS=$((SYNC_CONFLICTS + 1)); KEPT_EDITS+=("$rel  (the new version is next to it as .new)")
            SYNC_LAST=conflict
            ;;
    esac
}

# Every file of a copied tree through sync_one. $1 is relative to home/. On
# install, new files are counted rather than listed one by one: a first
# install lays down hundreds, and what matters is what was replaced or kept.
deploy_tree() {
    local top="$1" how="$2" f rel before=$SYNC_ADDED
    [ -e "$REPO/home/$top" ] || return 0
    digests_load
    repo_ignored_load
    [ "$how" = install ] && SYNC_QUIET_NEW=1
    while IFS= read -r f; do
        rel="${f#"$REPO"/home/}"
        [ -n "${IGNORED_IN_REPO[$rel]:-}" ] && continue
        sync_one "$rel" "$f" "$how"
    done < <(find "$REPO/home/$top" \( -type f -o -type l \) 2>/dev/null | sort)
    SYNC_QUIET_NEW=0
    [ "$how" = install ] && [ "$SYNC_ADDED" -gt "$before" ] \
        && ok "~/$top: $((SYNC_ADDED - before)) new file(s)"
    return 0
}

# The top-level entries a --copy install has laid down, one per line, so a
# re-run knows which copies are ours and goes through them file by file. The
# manifest alone could not say: a file that disagrees with the repo from the
# start -- quickshell-rice.json, once the language is written into it -- has
# no line there, and the re-run took it for a stranger's file and replaced
# it, with every setting in it.
DEPLOYED_FILE="$STATE_DIR/deployed"
declare -A DEPLOYED=()
DEPLOYED_LOADED=0
deployed_load() {
    [ "$DEPLOYED_LOADED" = 1 ] && return 0
    DEPLOYED_LOADED=1
    local e
    [ -f "$DEPLOYED_FILE" ] || return 0
    while IFS= read -r e; do [ -n "$e" ] && DEPLOYED["$e"]=1; done < "$DEPLOYED_FILE"
}

deployed_write() {
    [ "$DRY" = 1 ] && return 0
    [ ${#DEPLOYED[@]} -gt 0 ] || return 0
    mkdir -p "$STATE_DIR" 2>/dev/null || return 0
    printf '%s\n' "${!DEPLOYED[@]}" | sort > "$DEPLOYED_FILE.tmp.$$" \
        && mv -f "$DEPLOYED_FILE.tmp.$$" "$DEPLOYED_FILE"
}

# True when we deployed at $1 before -- it is in the list above, or, for
# installs older than that list, the manifest knows a file at or under it.
deployed_here() {
    local top="$1" k
    deployed_load
    [ -n "${DEPLOYED[$top]:-}" ] && return 0
    digests_load
    for k in "${!AGREED[@]}"; do
        case "$k" in "$top"|"$top"/*) return 0 ;; esac
    done
    return 1
}

# Puts src -> dest, symlinking or copying depending on $MODE.
place() {
    local src="$1" dest="$2" label="$3"
    local rel="${dest#"$HOME"/}"

    if [ "$MODE" = link ]; then
        if [ -L "$dest" ] && [ "$(readlink -f "$dest")" = "$(readlink -f "$src")" ]; then
            skip "$label (already linked)"
            return 0
        fi
        save_aside "$dest"
        run mkdir -p "$(dirname "$dest")"
        run ln -s "$src" "$dest"
        ok "$label -> symlink"
        return 0
    fi

    # --copy. A copy that is already here from an earlier run is gone through
    # file by file (see sync_one); only something we never put here -- the
    # config you had before, or a symlink from a --link install -- is saved
    # aside whole and replaced.
    local same_kind=0
    { [ -d "$dest" ] && [ -d "$src" ]; } && same_kind=1
    { [ -f "$dest" ] && [ -f "$src" ]; } && same_kind=1
    if [ -e "$dest" ] && [ ! -L "$dest" ] && [ "$same_kind" = 1 ] && deployed_here "$rel"; then
        local before=$((SYNC_UPDATED + SYNC_ADDED + SYNC_CONFLICTS))
        deploy_tree "$rel" install
        [ $((SYNC_UPDATED + SYNC_ADDED + SYNC_CONFLICTS)) -eq "$before" ] && skip "$label (copy up to date)"
        DEPLOYED["$rel"]=1
        return 0
    fi
    save_aside "$dest"
    run mkdir -p "$(dirname "$dest")"
    run cp -a "$src" "$dest"
    DEPLOYED["$rel"]=1
    ok "$label -> copy"
}

# ----------------------------------------------------------------- digests

# WHAT THIS IS FOR. In --copy mode ~/.config holds copies, so the repo and the
# desktop can disagree. `diagnose` could see THAT they disagreed -- 16 files on
# 2026-09-25 -- and nothing else, so all it could say was "decide each one",
# which means reading 16 diffs and remembering which side you touched last.
# Three months later nobody remembers.
#
# Writing down the digest of what the two sides last AGREED on turns that into a
# three-way comparison (repo / manifest / disk) that answers the only question
# worth asking:
#
#     repo == manifest, disk != manifest  ->  the desktop moved
#     disk == manifest, repo != manifest  ->  the repo moved
#     neither matches the manifest        ->  a real conflict, read both
#
# WHAT GETS RECORDED, and this is the whole trick: only files where the repo
# copy and the $HOME copy are ALREADY IDENTICAL. One digest then stands for both
# sides, so the rule holds whichever way the copy went. That is what makes the
# manual flow work -- diego edits ~/.config and then copies INTO the repo --
# which the obvious design (record what the installer wrote out) would have
# called a conflict on every single hand-synced file.
#
# And what still disagrees KEEPS its old digest instead of being forgotten:
# rebuilding the file from scratch turned a "the desktop moved" that diagnose
# could answer into a "decide yourself" the moment you re-ran this.
#
# Files reached through a symlink into the repo are skipped: a symlink cannot
# disagree with its target, so there is nothing to remember. That is also why
# this needs no --copy check -- it looks at what is on disk, not at $MODE.
digests_write() {
    if [ "$DRY" = 1 ]; then
        skip "would write the digest manifest to ${DIGESTS/#$HOME/\~}"
        return 0
    fi
    if ! command -v sha256sum >/dev/null 2>&1; then
        warn "no sha256sum: the digest manifest is skipped"
        return 0
    fi
    mkdir -p "$(dirname "$DIGESTS")" 2>/dev/null \
        || { warn "cannot create $(dirname "$DIGESTS"): no manifest written"; return 0; }

    local tmp="$DIGESTS.new.$$"
    : > "$tmp" 2>/dev/null \
        || { warn "cannot write in $(dirname "$DIGESTS"): no manifest written"; return 0; }

    local repo_real f rel real rsum hsum line osum orel n=0 kept=0
    declare -A OLD=()
    if [ -f "$DIGESTS" ]; then
        while IFS= read -r line; do
            osum="${line%% *}"; orel="${line#* }"; orel="${orel# }"
            [ ${#osum} -eq 64 ] && [ -n "$orel" ] && OLD["$orel"]="$osum"
        done < "$DIGESTS"
    fi

    repo_real="$(readlink -f -- "$REPO" 2>/dev/null || printf '%s' "$REPO")"
    while IFS= read -r f; do
        rel="${f#"$REPO"/home/}"
        # Gone from $HOME after both sides agreed on it: you deleted it. The
        # old line stays, which is how update.sh knows not to put it back.
        if [ ! -e "$HOME/$rel" ] && [ ! -L "$HOME/$rel" ]; then
            [ -n "${OLD[$rel]:-}" ] && { printf '%s  %s\n' "${OLD[$rel]}" "$rel" >> "$tmp"; kept=$((kept + 1)); }
            continue
        fi
        # A symlink of yours where the repo has a file is yours, whatever it
        # points at; sync_one compares symlinks by target, never by content.
        [ -f "$HOME/$rel" ] && [ ! -L "$HOME/$rel" ] || continue
        real="$(readlink -f -- "$HOME/$rel" 2>/dev/null)"
        case "$real" in "$repo_real"/*) continue ;; esac
        rsum="$(sha256sum -- "$f" 2>/dev/null)";         rsum="${rsum%% *}"
        hsum="$(sha256sum -- "$HOME/$rel" 2>/dev/null)"; hsum="${hsum%% *}"
        if [ -n "$rsum" ] && [ "$rsum" = "$hsum" ]; then
            printf '%s  %s\n' "$rsum" "$rel" >> "$tmp"
            n=$((n + 1))
        elif [ -n "${OLD[$rel]:-}" ]; then
            printf '%s  %s\n' "${OLD[$rel]}" "$rel" >> "$tmp"
            kept=$((kept + 1))
        fi
    done < <(find "$REPO/home" -type f 2>/dev/null | sort)

    if mv -f "$tmp" "$DIGESTS" 2>/dev/null; then
        ok "digest manifest: $n file(s) agree, $kept still to settle"
        # Anything later in this run reads the new one.
        AGREED=(); AGREED_LOADED=0
    else
        rm -f "$tmp"
        warn "could not write ${DIGESTS/#$HOME/\~}"
    fi
}

# ----------------------------------------------------------------- lock screen

# Does the lock screen name a PAM service that actually exists on this machine?
#
# hyprlock 0.9.6 lets its config pick the PAM service it authenticates against
# (auth:pam:module), which is how you add something in front of the password --
# a fingerprint, a face -- without patching the file the hyprlock package owns
# and that comes back as a .pacnew on every update.
#
# THIS REPO SHIPS NO SUCH SERVICE, and the check below is a no-op unless you add
# one: hyprlock.conf here names no module, so the lock screen authenticates
# against the stock `hyprlock` service. The check exists for the day you do add
# one, because the price of naming your own service is that the file has to BE
# there. PAM falls back to /etc/pam.d/other when the named service is missing,
# and on Arch that is pam_deny: the lock screen would then refuse whatever you
# added AND the password, and the only way back in is Ctrl+Alt+F2.
#
# This only looks and talks. Installing the file here would mean sudo inside a
# phase that has never asked for it, and rewriting hyprlock.conf is not an
# option either: in the default link mode that file IS the repo's.
check_lock_pam() {
    # The file hyprlock reads is the one in $HOME, not the one in the repo. In
    # --copy mode the two drift apart -- that is the entire reason the digest
    # manifest above exists -- and set_language_hyprlock, a few lines up in this
    # same phase, already reaches into $HOME for this very file. The repo's copy
    # is only the fallback, so a dry run on a machine with nothing laid down yet
    # still has something to read.
    local conf="$HOME/.config/hypr/hyprlock.conf" mod
    [ -f "$conf" ] || conf="$REPO/home/.config/hypr/hyprlock.conf"
    [ -f "$conf" ] || return 0

    # The key is nested two blocks deep (auth { pam { module = ... } }), so the
    # indentation is not fixed. hyprlang has no other `module` key, and the
    # first hit is the one hyprlock would use.
    mod="$(sed -n 's/^[[:space:]]*module[[:space:]]*=[[:space:]]*\([A-Za-z0-9_.-]\{1,\}\).*/\1/p' \
        "$conf" 2>/dev/null | head -1)"
    [ -n "$mod" ] || return 0

    if [ -f "/etc/pam.d/$mod" ]; then
        # Being there is not the same as being usable. The face line is
        # `sufficient`, so something has to sit BEHIND it; a stack made only of
        # pam_howdy would turn a camera that will not start into a locked door
        # -- the same failure as a missing file, only with a green ok in front.
        #
        # What counts as "there is a password behind it": an `include` or
        # `substack` of another service (hyprlock-face does `include login`,
        # and login itself does `include system-local-login`), or pam_unix.so
        # spelled out. Not a chain walk: this is a smoke alarm, not a parser.
        if grep -qE '^[[:space:]]*-?auth[[:space:]].*(include|substack|pam_unix\.so)' \
               "/etc/pam.d/$mod" 2>/dev/null; then
            ok "lock screen PAM service /etc/pam.d/$mod is in place"
        else
            warn "/etc/pam.d/$mod is there, but its auth stack never reaches a"
            warn "password: no 'include', no 'substack', no pam_unix.so. If the"
            warn "face fails there is nothing behind it. Read that file before"
            warn "you lock the screen."
        fi
        return 0
    fi

    # In a dry run nothing has been installed, so the file being absent says
    # nothing about how the machine will end up. State the fact, skip the alarm.
    if [ "$DRY" = 1 ]; then
        warn "/etc/pam.d/$mod is not there yet; the 'system' phase is what puts it in"
        return 0
    fi

    warn "hyprlock.conf authenticates against PAM service '$mod', and"
    warn "/etc/pam.d/$mod is NOT on this machine. Until you run"
    warn "  ./install.sh system"
    warn "the lock screen will open with neither your face nor your password."
    warn "DO NOT LOCK THE SCREEN before that. If you already did: Ctrl+Alt+F2,"
    warn "log in there, and run 'pkill -x hyprlock' (never 'pkill -f')."
}

# ----------------------------------------------------------------- language

# The desktop speaks Spanish or English. That is ONE setting living in three
# files, because three different programs read it at three different moments:
# Quickshell reads its own JSON when the shell starts, the SDDM theme reads
# theme.conf before you have even logged in, and hyprlock reads its language
# file when the screen locks.
#
# Two rules run through all of this. First, none of the three is required: if a
# file is not there, that one is skipped and the other two are still set, so a
# partial checkout never stops the install. Second, NOTHING IS WRITTEN WHEN THE
# VALUE IS ALREADY RIGHT, and "no key at all" counts as Spanish ($FALLBACK_LANG),
# because that is what the three programs fall back to: their strings are
# written in Spanish. So a Spanish run writes nothing here, and an English one
# writes one key in each file.

# ~/.config/quickshell-rice.json, key "language".
#
# This file is the shell's own state, not repo configuration: Quickshell
# rewrites it whole every time you touch a setting, and it already exists, full
# of your choices, on any machine that has run the desktop once. So it is
# edited in place and one key at a time -never replaced- and when it is not
# there yet, the minimum that says what we mean is created instead.
set_language_quickshell() {
    local rice="$HOME/.config/quickshell-rice.json" current tmp

    if [ ! -f "$rice" ]; then
        [ "$UI_LANG" = "$FALLBACK_LANG" ] && return 0
        if [ "$DRY" = 1 ]; then
            skip "would create ~/.config/quickshell-rice.json with \"language\": \"$UI_LANG\""
        else
            printf '{\n    "language": "%s"\n}\n' "$UI_LANG" > "$rice" \
                && ok "quickshell language: $UI_LANG (new quickshell-rice.json)"
        fi
        return 0
    fi

    if command -v jq >/dev/null 2>&1; then
        current="$(jq -r '.language // "'"$FALLBACK_LANG"'"' "$rice" 2>/dev/null)"
    else
        current="$(sed -n 's/.*"language"[[:space:]]*:[[:space:]]*"\([a-z]*\)".*/\1/p' "$rice" | head -1)"
    fi
    [ -n "$current" ] || current="$FALLBACK_LANG"
    if [ "$current" = "$UI_LANG" ]; then
        skip "quickshell is already in $UI_LANG"
        return 0
    fi

    if [ "$DRY" = 1 ]; then
        skip "would set \"language\": \"$UI_LANG\" in ~/.config/quickshell-rice.json"
        return 0
    fi

    if command -v jq >/dev/null 2>&1; then
        tmp="$(mktemp)"
        # --indent 4 is how Quickshell itself writes the file: without it every
        # install would reindent all twenty keys for one changed line.
        if jq --indent 4 --arg l "$UI_LANG" '.language = $l' "$rice" > "$tmp" && [ -s "$tmp" ]; then
            # cat, and not mv: with --link this path is a SYMLINK into the repo,
            # and mv would drop a plain file on top of it. The two would stop
            # being the same file from here on, silently.
            cat "$tmp" > "$rice" && ok "quickshell language: $UI_LANG"
        else
            warn "could not rewrite quickshell-rice.json; its language is unchanged"
        fi
        rm -f "$tmp"
    elif grep -q '"language"' "$rice"; then
        # --follow-symlinks for the same reason as the cat above.
        sed -i --follow-symlinks \
            "s/\(\"language\"[[:space:]]*:[[:space:]]*\)\"[a-z]*\"/\1\"$UI_LANG\"/" "$rice" \
            && ok "quickshell language: $UI_LANG"
    else
        warn "jq is missing: add  \"language\": \"$UI_LANG\"  to ~/.config/quickshell-rice.json yourself"
    fi
}

# The login theme, key language (lower case, like accent and background).
#
# It writes the INSTALLED theme, /usr/share/sddm/themes/hyprisland/theme.conf,
# and not the copy under ~/.config. Two reasons, both learned the hard way:
# SDDM reads the installed one and never the copy, so writing the copy left the
# login screen in Spanish without a word; and with the default --link mode
# ~/.config/sddm-hyprisland IS the repo, so writing there left `git status`
# dirty on every install.
#
# On a machine with no theme installed yet this does nothing and says so: the
# 'sddm' phase runs afterwards, lays the theme down and calls this again.
set_language_sddm() {
    local conf=/usr/share/sddm/themes/hyprisland/theme.conf current

    if [ ! -f "$conf" ]; then
        skip "the login theme is not installed: the 'sddm' phase will set it to $UI_LANG"
        return 0
    fi

    current="$(sed -n 's/^[[:space:]]*[Ll]anguage[[:space:]]*=[[:space:]]*\([A-Za-z]*\).*/\1/p' "$conf" | head -1)"
    [ -n "$current" ] || current="$FALLBACK_LANG"
    if [ "$current" = "$UI_LANG" ]; then
        skip "the login theme is already in $UI_LANG"
        return 0
    fi

    if [ "$DRY" = 1 ]; then
        skip "would set language=$UI_LANG in $conf  (needs sudo)"
        return 0
    fi

    warn "the login theme lives in /usr, so this needs sudo"
    if grep -q '^[[:space:]]*[Ll]anguage[[:space:]]*=' "$conf"; then
        sudo sed -i "s/^[[:space:]]*[Ll]anguage[[:space:]]*=.*/language=$UI_LANG/" "$conf" \
            && ok "login theme language: $UI_LANG"
    else
        # The file is one [General] section and nothing else, so the end of it
        # is still inside that section.
        printf 'language=%s\n' "$UI_LANG" | sudo tee -a "$conf" >/dev/null \
            && ok "login theme language: $UI_LANG"
    fi
}

# hyprlock, whose strings live in a file of their own under ~/.config/hypr.
#
# The NAME of that file is not spelled out here: it is read out of hyprlock.conf,
# from whatever it `source`s with 'lang' in it, so renaming it on the hyprlock
# side does not quietly break the installer. Two shapes are understood, which
# are the two anyone would write: either the strings ship one file per language
# (hyprlock-lang.es.conf, hyprlock-lang.en.conf) and the chosen one is copied
# into place, or there is a single file with a $lang variable at the top and the
# variable is rewritten. Anything else, and the lock screen is left alone.
set_language_hyprlock() {
    local dir="$HOME/.config/hypr" target src current

    target="$(sed -n \
        's/^[[:space:]]*source[[:space:]]*=[[:space:]]*\(.*lang.*[^[:space:]]\)[[:space:]]*$/\1/p' \
        "$dir/hyprlock.conf" 2>/dev/null | head -1)"
    target="${target/#\~/$HOME}"
    target="${target/#\$HOME/$HOME}"
    [ -n "$target" ] || target="$dir/hyprlock-lang.conf"

    src="${target%.conf}.$UI_LANG.conf"

    if [ -f "$src" ]; then
        if [ -f "$target" ] && cmp -s "$src" "$target"; then
            skip "hyprlock is already in $UI_LANG"
        elif [ "$DRY" = 1 ]; then
            skip "would copy $(basename "$src") over $(basename "$target")"
        else
            cp -- "$src" "$target" && ok "hyprlock language: $UI_LANG"
        fi
    elif [ -f "$target" ] && grep -q '^[[:space:]]*\$lang' "$target"; then
        current="$(sed -n 's/^[[:space:]]*\$lang[a-z]*[[:space:]]*=[[:space:]]*\([A-Za-z]*\).*/\1/p' "$target" | head -1)"
        [ -n "$current" ] || current="$FALLBACK_LANG"
        if [ "$current" = "$UI_LANG" ]; then
            skip "hyprlock is already in $UI_LANG"
        elif [ "$DRY" = 1 ]; then
            skip "would set \$lang = $UI_LANG in $(basename "$target")"
        else
            sed -i "s/^\([[:space:]]*\$lang[a-z]*[[:space:]]*=[[:space:]]*\).*/\1$UI_LANG/" "$target" \
                && ok "hyprlock language: $UI_LANG"
        fi
    else
        skip "no hyprlock language file in ~/.config/hypr: the lock screen keeps its language"
    fi
}

# ----------------------------------------------------------------- keyboard

# The keyboard layout this machine already uses, as xkb names ("layout
# variant"): X11's if localectl has one, else the console keymap (es,
# de-latin1 -> de, uk -> gb...), else US, which is what an untouched console
# types in anyway.
detect_keyboard() {
    local st x11 var vc
    st="$(c_locale localectl status 2>/dev/null)"
    x11="$(printf '%s\n' "$st" | sed -n 's/^[[:space:]]*X11 Layout:[[:space:]]*//p' | head -1)"
    var="$(printf '%s\n' "$st" | sed -n 's/^[[:space:]]*X11 Variant:[[:space:]]*//p' | head -1)"
    case "$x11" in ''|'(unset)'|n/a) x11="" ;; esac
    case "$var" in '(unset)'|n/a) var="" ;; esac
    if [ -z "$x11" ]; then
        var=""
        vc="$(printf '%s\n' "$st" | sed -n 's/^[[:space:]]*VC Keymap:[[:space:]]*//p' | head -1)"
        case "$vc" in ''|'(unset)'|n/a) vc=us ;; esac
        # Console names are not xkb names (uk is gb, la-latin1 is latam,
        # dvorak is us with a variant), and systemd ships the table it uses
        # itself for `localectl set-keymap`: the first row for that keymap wins.
        local row
        row="$(awk -v k="$vc" '$1 == k { print $2, $4; exit }' /usr/share/systemd/kbd-model-map 2>/dev/null)"
        if [ -n "$row" ]; then
            x11="${row%% *}"; var="${row#* }"
            [ "$var" = "-" ] && var=""
        else
            x11="${vc%%-*}"
        fi
    fi
    printf '%s %s' "$x11" "$var"
}

# ~/.config/hypr/keyboard.lua: the keyboard of THIS machine. hyprland.lua loads
# it right after its own input block, so it wins over the "es" written there.
#
# It is written once and never again: after that it is yours to edit, and an
# existing one is left alone. Spanish needs no file, because that is what
# hyprland.lua already says -- so a Spanish machine ends up exactly as before.
# Like efectos.lua, it is ignored by git: in --link mode ~/.config/hypr IS the
# repo.
set_keyboard() {
    local f="$HOME/.config/hypr/keyboard.lua" layout variant
    if [ -f "$f" ]; then
        skip "keyboard.lua already exists: your layout is left alone"
        return 0
    fi
    # In --copy mode the whole ~/.config/hypr was just replaced (and saved
    # aside), so a keyboard.lua you had edited would be gone: put it back.
    if [ -n "$KEYBOARD_KEEP" ]; then
        if [ "$DRY" = 1 ]; then
            skip "would put back your ~/.config/hypr/keyboard.lua"
        else
            mkdir -p "$(dirname "$f")"
            printf '%s\n' "$KEYBOARD_KEEP" > "$f" && ok "keyboard.lua put back as it was"
        fi
        return 0
    fi
    read -r layout variant <<<"$(detect_keyboard)"
    if [ "$layout" = es ] && [ -z "$variant" ]; then
        skip "keyboard: es, which is what hyprland.lua already says"
        return 0
    fi
    if [ "$DRY" = 1 ]; then
        skip "would write ~/.config/hypr/keyboard.lua with layout '$layout'${variant:+ variant '$variant'}"
        return 0
    fi
    mkdir -p "$(dirname "$f")"
    printf '%s\n' \
        '-- Written by install.sh from what localectl reported on this machine.' \
        '-- hyprland.lua loads it after its own input block, so this wins. It is' \
        '-- not rewritten: edit it at will (kb_layout takes a list, e.g. "us,es").' \
        "hl.config({ input = { kb_layout = \"$layout\", kb_variant = \"$variant\" } })" \
        > "$f" && ok "keyboard: $layout${variant:+ ($variant)}, in ~/.config/hypr/keyboard.lua"
}

# Asks (if it has to) and then writes the three of them.
apply_language() {
    ask_lang
    set_language_quickshell
    set_language_sddm
    set_language_hyprlock
}

# ----------------------------------------------------------------- phase: base

# Which Arch this is. Read once, at the start of every run, because several
# phases decide things by it: whose tools manage the mirrors, whether a
# pacman guard is in the way. From /etc/os-release, plus Omarchy's own marks:
# Omarchy installs on top of Arch, so its os-release still says "arch".
DISTRO_ID=""
DISTRO_LIKE=""
DISTRO_NAME=""
IS_OMARCHY=0
detect_distro() {
    if [ -r /etc/os-release ]; then
        DISTRO_ID="$(sed -n 's/^ID=//p' /etc/os-release | tr -d '"' | head -1)"
        DISTRO_LIKE="$(sed -n 's/^ID_LIKE=//p' /etc/os-release | tr -d '"' | head -1)"
        DISTRO_NAME="$(sed -n 's/^NAME=//p' /etc/os-release | tr -d '"' | head -1)"
    fi
    IS_OMARCHY=0
    if [ -d "$HOME/.local/share/omarchy" ] || grep -qs '^\[omarchy\]' /etc/pacman.conf \
       || omarchy_guard_hook >/dev/null; then
        IS_OMARCHY=1
    fi
}

describe_distro() {
    if [ "$IS_OMARCHY" = 1 ]; then
        warn "detected: Omarchy, on Arch. It works, but it is not where this is made: its own"
        warn "Hyprland config is saved aside, not merged, and pacman may be guarded (see below)"
        return 0
    fi
    case "$DISTRO_ID" in
        arch)  ok "detected: Arch Linux" ;;
        manjaro*)
            warn "detected: $DISTRO_NAME -- NOT supported. Its repos run weeks behind Arch's,"
            warn "and the AUR packages this needs are built against Arch's current libraries" ;;
        endeavouros|cachyos|garuda|artix|arcolinux|*)
            if [ -n "$DISTRO_ID" ]; then
                warn "detected: ${DISTRO_NAME:-$DISTRO_ID} (based on ${DISTRO_LIKE:-arch}). Not where this is made:"
                warn "it should work, and what it already chose (audio, power, firewall, mirrors) is kept"
            fi ;;
    esac
}

phase_base() {
    heading "Preflight checks"

    [ "$(id -u)" -ne 0 ] || die "do not run this as root. Run it as your user; it will ask for sudo when it needs to."
    ok "regular user ($USER)"

    command -v pacman >/dev/null || die "this is for Arch: I cannot find pacman."
    ok "Arch detected"

    command -v git >/dev/null || die "git is missing. Install it with: sudo pacman -S git"
    ok "git present"

    if ping -c1 -W3 archlinux.org >/dev/null 2>&1; then
        ok "network is up"
    else
        warn "cannot reach archlinux.org. With no network, the 'aur' and 'packages' phases will fail."
    fi

    # sudo is NOT part of the 'base' metapackage: an Arch installed by hand may
    # not have it. Without it there is no way to run the 'packages', 'system' or
    # 'sddm' phases, so it is better said here than three screens further down.
    if ! command -v sudo >/dev/null 2>&1; then
        warn "there is no sudo on this system"
        printf '       %s%s%s\n' "$C_DIM" "Install it as root and add yourself to wheel:" "$C_OFF"
        printf '       %s  pacman -S sudo  &&  usermod -aG wheel %s%s\n' "$C_DIM" "$USER" "$C_OFF"
        printf '       %s  then uncomment the %%wheel line in /etc/sudoers (visudo)%s\n' "$C_DIM" "$C_OFF"
        warn "without sudo, only the 'repos', 'config' and 'restore' phases work"
    elif sudo -n -k true 2>/dev/null; then
        # -k: judged without the password the start of the run may already
        # have cached, or everybody was "passwordless" here.
        ok "passwordless sudo"
    elif sudo -n true 2>/dev/null; then
        ok "sudo is open: asked once, at the start, and kept open for the whole run"
    else
        warn "sudo will ask for your password when a phase needs it"
    fi

    if [ "$HOME" != /home/diego ]; then
        ok "your home is $HOME: the 'config' phase rewrites the /home/diego written"
        printf '       %sinside some of the repo'"'"'s files to point there (git diff shows it)%s\n' "$C_DIM" "$C_OFF"
    fi

    describe_distro

    printf '\n  config install mode: %s%s%s\n' "$C_TIT" "$MODE" "$C_OFF"
    [ "$DRY" = 1 ] && printf '  %sDRY RUN: nothing will be modified%s\n' "$C_WARN" "$C_OFF"
    return 0
}

# ----------------------------------------------------------------- phase: aur

# The AUR helper this machine already has: yay, or paru (CachyOS ships paru).
# Both take the same flags for everything done here.
aur_helper() {
    if command -v yay >/dev/null 2>&1; then printf yay
    elif command -v paru >/dev/null 2>&1; then printf paru
    else return 1
    fi
}

phase_aur() {
    heading "AUR helper (yay)"

    local have
    if have="$(aur_helper)"; then
        skip "$have is already installed"
        return 0
    fi

    ok "yay is missing: it has to be built (the AUR's chicken-and-egg problem)"
    # The build tools go in like every other package: the system brought up
    # to date first (see system_upgrade), then only what is missing.
    local tools=(base-devel git)
    if ! install_native "AUR build tools" tools; then
        failed "yay could not be built: base-devel and git did not install. The AUR packages are skipped"
        return 1
    fi

    # mktemp, not /tmp/...-$$. The PID is predictable, and on a shared /tmp that
    # lets another user get there first with a directory or a symlink of their
    # own, right where a build is about to run. Cheap to get right.
    local tmp
    if [ "$DRY" = 1 ]; then
        tmp='$(mktemp -d)'
    else
        tmp="$(mktemp -d "${TMPDIR:-/tmp}/yay-bootstrap.XXXXXXXX")" \
            || { failed "could not create a temporary directory to build yay in"; return 1; }
        EXIT_TMP+=("$tmp")
    fi
    # None of this is fatal any more. The AUR goes down for hours at a time --
    # for days, once, in 2025 -- and when a failure here ended the run, the
    # official packages, which are the whole desktop, never went in either.
    if ! run git clone --depth 1 https://aur.archlinux.org/yay-bin.git "$tmp"; then
        failed "could not download yay from the AUR (is aur.archlinux.org up?). AUR packages skipped: run ./install.sh aur packages later"
        return 1
    fi
    if [ "$DRY" = 0 ]; then
        sudo_begin || true
        if ! ( cd "$tmp" && makepkg -si --noconfirm ); then
            failed "building yay failed (its output is above). AUR packages skipped"
            return 1
        fi
    fi
    ok "yay installed"
}

# ----------------------------------------------------------------- phase: packages

# The lists, one entry per line. An entry can name alternatives, a|b (see
# pick_alternatives). In update.sh's dry run they are read from the commit the
# pull would bring (PLAN_REV), so its plan shows what that commit asks for.
list_cat() {
    local f
    for f in "$@"; do
        if [ -n "${PLAN_REV:-}" ]; then
            git -C "$REPO" show "$PLAN_REV:packages/$f" 2>/dev/null
        else
            cat "$REPO/packages/$f" 2>/dev/null
        fi
    done
}

read_native_packages() {
    list_cat pacman.txt extra.txt | grep -vE '^\s*(#|$)' | tr -d ' \t' | sort -u
}

read_aur_packages() {
    list_cat aur.txt | grep -vE '^\s*(#|$)' | tr -d ' \t' | grep -v '^yay$' | sort -u
}

# Reads `pacman -Si`, `pacman -Qi` or `yay -Si` on stdin and prints one line per
# package: name|version|provides|conflicts|replaces|depends, the lists
# space-separated and empty where pacman says None. The command has to run
# under c_locale: the field names are translated, and on a Spanish system there
# is no "Conflicts With" to find. A package that two repos carry is printed
# once, the first time, which is the one pacman would pick.
pkg_info_table() {
    awk '
        function flush() {
            if (name != "" && !(name in seen)) {
                seen[name] = 1
                print name "|" f["Version"] "|" f["Provides"] "|" f["Conflicts With"] "|" f["Replaces"] "|" f["Depends On"]
            }
            name = ""; split("", f)
        }
        /^$/ { flush(); next }
        /^[^ ]/ {
            key = $0; sub(/ *:.*/, "", key)
            val = $0; sub(/^[^:]*: */, "", val)
        }
        # A line that starts with spaces carries on the field above it.
        /^ / { val = f[key] " " $0 }
        {
            if (val == "None") val = ""
            gsub(/ +/, " ", val); sub(/^ /, "", val); sub(/ $/, "", val)
            f[key] = val
            if (key == "Name") name = val
        }
        END { flush() }
    '
}

# True when something called $1 at version $2 -- a package, or something one
# provides, in which case the version may be empty -- satisfies the dependency
# string $3: 'tldr', 'foo<2', 'libbar.so=3-64'. The same rule pacman applies,
# down to its one surprise: a provision without a version never satisfies a
# dependency that asks for one.
pkg_satisfies() {
    local name=$1 ver=$2 dep=$3 dname rest dver op cmp
    dname="${dep%%[<>=]*}"
    [ "$dname" = "$name" ] || return 1
    [ "$dname" = "$dep" ] && return 0
    [ -n "$ver" ] || return 1
    rest="${dep#"$dname"}"
    dver="${rest#"${rest%%[!<>=]*}"}"
    op="${rest%"$dver"}"
    cmp="$(vercmp "$ver" "$dver" 2>/dev/null)" || return 1
    case "$op" in
        '<')  [ "$cmp" -lt 0 ] ;;
        '<=') [ "$cmp" -le 0 ] ;;
        '=')  [ "$cmp" -eq 0 ] ;;
        '>=') [ "$cmp" -ge 0 ] ;;
        '>')  [ "$cmp" -gt 0 ] ;;
        *)    return 1 ;;
    esac
}

# True when something installed satisfies $1: by name, or by what a package
# provides (gvim answers for vim, python-pywal16 for python-pywal). pacman -T
# is pacman's own answer to exactly that question.
pkg_present() { pacman -T -- "$1" >/dev/null 2>&1; }

# A line can name alternatives, `tealdeer|tldr`. Any of them already on the
# machine satisfies it, and only when none is does the first go in. Without
# this a list written on one laptop fights choices other machines have already
# made: Omarchy ships tldr, and asking for tealdeer there cancelled the whole
# pacman transaction.
pick_alternatives() {
    local -n alt_ref="$1"
    local out=() entry a chosen alts=()
    for entry in "${alt_ref[@]}"; do
        case "$entry" in
            *'|'*)
                IFS='|' read -r -a alts <<<"$entry"
                chosen=""
                for a in "${alts[@]}"; do
                    [ -n "$a" ] && pkg_present "$a" && { chosen="$a"; break; }
                done
                if [ -z "$chosen" ]; then
                    out+=("${alts[0]}")
                elif [ "$chosen" != "${alts[0]}" ]; then
                    skip "${alts[0]}: you have $chosen, which does the same job, and it stays"
                    alternative_note "${alts[0]}" "$chosen"
                fi
                ;;
            *) out+=("$entry") ;;
        esac
    done
    alt_ref=("${out[@]}")
}

# The alternatives that cost something you would notice, said once.
alternative_note() {
    case "$1:$2" in
        pipewire-pulse:pulseaudio)
            left_out "pipewire-pulse: you run PulseAudio. The notch's volume and audio controls talk to PipeWire and show nothing without it; to switch: sudo pacman -S pipewire-pulse (pacman offers to replace pulseaudio)" ;;
    esac
}

# The power manager this machine already runs, when it is not ours. TLP and
# power-profiles-daemon (or tuned, or auto-cpufreq) write the same CPU and
# platform settings, and with two of them running each undoes the other. tlp
# declares no conflict with power-profiles-daemon -- only tlp-pd does -- so
# pacman would happily put it next to one. Asked by exact name, because tlp-pd
# itself PROVIDES power-profiles-daemon.
other_power_daemon() {
    local p
    for p in power-profiles-daemon tuned tuned-ppd auto-cpufreq; do
        [ "$(pacman -Qq -- "$p" 2>/dev/null | head -1)" = "$p" ] && { printf '%s' "$p"; return 0; }
    done
    return 1
}

drop_power_conflicts() {
    local -n pw_ref="$1"
    local other kept=() out=() p
    other="$(other_power_daemon)" || return 0
    for p in "${pw_ref[@]}"; do
        case "$p" in tlp|tlp-pd|tlp-rdw) out+=("$p") ;; *) kept+=("$p") ;; esac
    done
    [ ${#out[@]} -gt 0 ] || return 0
    pw_ref=("${kept[@]}")
    left_out "${out[*]} left out: this machine already manages power with $other, and two power managers undo each other"
}

# Takes out of the array named $1 the names the repos -- or the AUR, with $2 =
# yay or paru -- do not have, saying each one. pacman refuses a whole
# transaction over one "target not found": a single package renamed upstream
# stopped a fresh install dead, and on a re-run it quietly kept every package
# added to the list since then from going in. It fails open: when nothing at
# all could be looked up (no databases, the AUR down), the list stays as it was
# and pacman gets to say why.
drop_unknown() {
    local -n unk_ref="$1"
    local tool="$2" kept=() p name
    local -A found=()
    [ ${#unk_ref[@]} -gt 0 ] || return 0
    while IFS='|' read -r name _; do
        [ -n "$name" ] && found[$name]=1
    done < <(c_locale "$tool" -Si -- "${unk_ref[@]}" 2>/dev/null | pkg_info_table)
    [ ${#found[@]} -gt 0 ] || return 0
    for p in "${unk_ref[@]}"; do
        if [ -n "${found[$p]:-}" ]; then kept+=("$p"); continue; fi
        # Not a package by that name, but maybe still something pacman
        # resolves: a name another package provides, or a group.
        if [ "$tool" = pacman ] \
           && { pacman -Sp --noconfirm --print-format %n -- "$p" >/dev/null 2>&1 \
                || pacman -Sg -- "$p" >/dev/null 2>&1; }; then
            kept+=("$p"); continue
        fi
        left_out "$p is left out: $tool cannot find a package by that name (renamed, or dropped from the repos)"
    done
    unk_ref=("${kept[@]}")
}

# Takes out of the array named $1 every package that could only go in by
# removing one already on this system, says which one it ran into, and keeps
# what is installed. The rest of the arguments are the command that describes
# packages, `pacman -Si` or `yay -Si`, called ONCE for all of them.
#
# Without this, one collision costs the whole list. A report from Omarchy, an
# Arch-based Hyprland distro that ships `tldr`: pacman.txt asked for `tealdeer`,
# the two conflict, and pacman asked "Remove tldr? [y/N]". --noconfirm answers
# the default, which is N, and N means pacman cancels the TRANSACTION: none of
# the 160 packages went in, for the sake of a cheat-sheet viewer. Which
# one of a conflicting pair a machine has is the owner's call, not ours, so the
# one already there stays and ours is left out, out loud. (That pair is now
# written `tealdeer|tldr` in the list; this is the net for the pairs nobody
# thought of.)
#
# pacman refuses in both directions, so both are checked: the new package
# naming an installed one in its Conflicts With (tealdeer vs an installed
# tldr), and an installed one naming the new package, or something it provides
# (an installed tealdeer vs `tldr` on the list). Only packages that are not
# installed yet are looked at; the rest are pacman's to upgrade.
#
# It runs AFTER the system upgrade (see system_upgrade), against fresh
# databases, so a package that -Syu replaces (exa by eza, swww by awww) is
# already gone by the time this looks.
#
# It fails open. With no sync database, no network for the AUR or a package
# it cannot find, it has nothing to compare and leaves the list as it was.
# (The array is passed by name, so nothing in here may be called like the
# caller's array: native, aur, todo, missing_native, missing_aur.)
drop_conflicting() {
    local -n pkg_list_ref="$1"
    shift

    local -A installed=() providers=() inst_conflicts=() dropped=() cand_deps=() dropped_names=()
    local candidates=() kept=()
    local p name ver provides conflicts replaces depends entry pair other hit key kver changed dep dname

    # The lists below are split on spaces and must never be globbed: an AUR
    # package writes its own Provides, and a * in one is not a filename.
    local -
    set -f

    while IFS= read -r p; do
        installed[$p]=1
    done < <(pacman -Qq 2>/dev/null)

    for p in "${pkg_list_ref[@]}"; do
        [ -n "$p" ] && [ -z "${installed[$p]:-}" ] && candidates+=("$p")
    done
    [ ${#candidates[@]} -gt 0 ] || return 0

    # What is installed, indexed by every name it answers to (its own and what
    # it provides, each with the version it gives) and by every name it
    # conflicts with. An empty name is skipped here and below rather than
    # trusted: bash treats an empty key in an assignment as fatal, and that
    # would end the install.
    while IFS='|' read -r name ver provides conflicts replaces depends; do
        [ -n "$name" ] || continue
        providers[$name]+=" $name|$ver"
        for p in $provides; do
            key=${p%%=*} kver=
            [[ "$p" == *=* ]] && kver=${p#*=}
            [ -n "$key" ] && providers[$key]+=" $name|$kver"
        done
        for entry in $conflicts; do
            key=${entry%%[<>=]*}
            [ -n "$key" ] && inst_conflicts[$key]+=" $name|$entry"
        done
    done < <(c_locale pacman -Qi 2>/dev/null | pkg_info_table)

    while IFS='|' read -r name ver provides conflicts replaces depends; do
        [ -n "$name" ] || continue
        cand_deps[$name]="$depends"
        hit=

        # The new package names an installed one.
        for entry in $conflicts; do
            key=${entry%%[<>=]*}
            [ -n "$key" ] || continue
            for pair in ${providers[$key]:-}; do
                other=${pair%%|*}
                pkg_satisfies "$key" "${pair#*|}" "$entry" || continue
                hit=$other
                break 2
            done
        done

        # An installed package names the new one, or something it provides.
        if [ -z "$hit" ]; then
            for p in "$name=$ver" $provides; do
                key=${p%%=*} kver=
                [[ "$p" == *=* ]] && kver=${p#*=}
                [ -n "$key" ] || continue
                for pair in ${inst_conflicts[$key]:-}; do
                    other=${pair%%|*}
                    pkg_satisfies "$key" "$kver" "${pair#*|}" || continue
                    hit=$other
                    break 2
                done
            done
        fi

        [ -n "$hit" ] || continue
        dropped[$name]=1
        dropped_names[$name]=1
        for p in $provides; do
            key=${p%%=*}
            [ -n "$key" ] && dropped_names[$key]=1
        done
        left_out "$name is left out: it conflicts with $hit, which is already installed and stays"
    done < <(c_locale "$@" -- "${candidates[@]}" 2>/dev/null | pkg_info_table)

    [ ${#dropped[@]} -gt 0 ] || return 0

    # Whatever on the list depends on a package that was just left out goes
    # too, or pacman pulls the dropped one straight back in as a dependency and
    # the transaction dies on the very conflict this avoided: tlp-pd needs tlp,
    # and with tuned installed tlp is out. Not when something installed
    # already provides what it needs.
    changed=1
    while [ "$changed" = 1 ]; do
        changed=0
        for name in "${!cand_deps[@]}"; do
            [ -z "${dropped[$name]:-}" ] || continue
            for dep in ${cand_deps[$name]}; do
                dname=${dep%%[<>=]*}
                [ -n "$dname" ] && [ -n "${dropped_names[$dname]:-}" ] || continue
                [ -z "${providers[$dname]:-}" ] || continue
                dropped[$name]=1
                dropped_names[$name]=1
                left_out "$name is left out too: it needs $dname, which was left out"
                changed=1
                break
            done
        done
    done

    warn "pacman cannot have both. To use ours instead, remove yours and run this again."

    for p in "${pkg_list_ref[@]}"; do
        [ -n "${dropped[$p]:-}" ] || kept+=("$p")
    done
    pkg_list_ref=("${kept[@]}")
}

# ---- running pacman

# Goes inside sudo, before pacman. sudo keeps LANG and LC_*, so pacman would
# answer in your language, and every line pkg_diagnose looks for -- "target
# not found", "there is nothing to do" -- would go by unrecognised on a
# Spanish desktop. Our pacman calls speak C; pacman_guard_setup may add to it.
PACMAN_ENV=(env -u LANGUAGE LC_ALL=C)
YAY_FLAGS=()
GUARD_CHECKED=0
PKG_LAST_LOG=""      # what the last pkg_run printed, for pkg_diagnose
PKG_CAUSE=""         # pkg_diagnose's one-line reason, for the summary
PKG_CAUSE_KIND=""    # ...and its kind: conflict files notfound deps keyring lock space download build other
PKG_FAILED_ENTRIES=()  # what would not install: kept out of the baseline, so the next run retries it
INHIBIT=()
INHIBIT_CHECKED=0
SYSTEM_UPGRADED=0

# Omarchy ships a pacman hook that refuses package changes made outside its
# own tools. Found by name, wherever pacman reads hooks from.
omarchy_guard_hook() {
    local h
    for h in /usr/share/libalpm/hooks/*omarchy*guard*.hook /etc/pacman.d/hooks/*omarchy*guard*.hook; do
        [ -e "$h" ] && { printf '%s' "$h"; return 0; }
    done
    return 1
}

pacman_guard_setup() {
    [ "$GUARD_CHECKED" = 1 ] && return 0
    GUARD_CHECKED=1
    local hook
    hook="$(omarchy_guard_hook)" || return 0
    warn "Omarchy guards pacman ($hook): it refuses package changes made"
    warn "outside its own tools. This installer only ADDS packages, and it can let its"
    warn "own pacman calls through with OMARCHY_ALLOW_DIRECT_PACMAN=1 -- for its calls"
    warn "only: nothing in Omarchy is changed, and your own pacman stays guarded."
    if ask "let this installer's pacman calls through Omarchy's guard?"; then
        PACMAN_ENV+=(OMARCHY_ALLOW_DIRECT_PACMAN=1)
        export OMARCHY_ALLOW_DIRECT_PACMAN=1
        # yay runs sudo pacman by itself, and sudo drops the environment:
        # this asks it to keep that one variable.
        YAY_FLAGS=(--sudoflags "--preserve-env=OMARCHY_ALLOW_DIRECT_PACMAN")
    else
        left_out "pacman calls left to Omarchy's guard, which may refuse them"
    fi
}

# systemd-inhibit around pacman, when this session may take the lock: a lid
# closed half-way through a kernel upgrade is how a machine stops booting.
inhibit_init() {
    [ "$INHIBIT_CHECKED" = 1 ] && return 0
    INHIBIT_CHECKED=1
    command -v systemd-inhibit >/dev/null 2>&1 || return 0
    # --no-ask-password: over SSH, or in a session that is not the active
    # one, polkit would otherwise stop the install to ask for an admin
    # password just to keep the machine awake. Not allowed means no lock.
    systemd-inhibit --no-ask-password --what=sleep:shutdown:idle --who=pocket-dots \
        --why=check --mode=block true >/dev/null 2>&1 || return 0
    INHIBIT=(systemd-inhibit --no-ask-password --what=sleep:shutdown:idle --who=pocket-dots
             "--why=installing packages" --mode=block)
}

# pkg_run [--quiet] <command...>
# Runs pacman or yay with its output on screen AND kept, so that pkg_diagnose
# can read pacman's own words afterwards. --quiet keeps it off the screen and
# in the log only (the one-at-a-time retries, which would otherwise scroll a
# hundred transactions past).
#
# A `sudo pacman ...` on a terminal goes through `script`, which gives pacman a
# terminal of its own: piped into tee, pacman drops its progress bars, and a
# 2 GB download with no progress looks hung. sudo stays OUTSIDE that
# terminal: sudo remembers your password per terminal, and `script` opens a
# new one, so `script sudo pacman` asked for it again on every call -- and an
# unattended run sat at a password prompt until it timed out. yay calls sudo
# by itself, inside whatever terminal it runs on, so it never goes through
# `script`.
#
# The capture lives in a private directory: with fs.protected_regular (on by
# default) root may not open a file of yours in a sticky directory like /tmp.
pkg_run() {
    local quiet=0
    [ "${1:-}" = --quiet ] && { quiet=1; shift; }
    if [ "$DRY" = 1 ]; then run "$@"; return 0; fi
    inhibit_init
    local capdir cap rc out_fd=1
    [ -n "${LOG_OUT:-}" ] && out_fd="$LOG_OUT"
    capdir="$(mktemp -d "${TMPDIR:-/tmp}/pocket-pkg.XXXXXXXX")" || { "${INHIBIT[@]}" "$@"; return; }
    EXIT_TMP+=("$capdir")
    cap="$capdir/out"
    : > "$cap"
    PKG_LAST_LOG="$cap"
    if [ "$quiet" = 1 ]; then
        "${INHIBIT[@]}" "$@" > "$cap" 2>&1 </dev/null
        rc=$?
        [ -n "$LOG_FILE" ] && cat "$cap" >> "$LOG_FILE"
    elif [ "${1:-}" = sudo ] && [ -t "$out_fd" ] && command -v script >/dev/null 2>&1; then
        shift
        # sudo env [VAR=value...] script -c "<pacman ...>": the variables reach
        # pacman through script, and SHELL says which shell script uses to
        # run it, whatever root's login shell is.
        local envs=() cmd=("$@")
        if [ "${cmd[0]:-}" = env ]; then
            cmd=("${cmd[@]:1}")
            while [ ${#cmd[@]} -gt 0 ]; do
                case "${cmd[0]}" in
                    -u) envs+=(-u "${cmd[1]}"); cmd=("${cmd[@]:2}") ;;
                    *=*) envs+=("${cmd[0]}"); cmd=("${cmd[@]:1}") ;;
                    *) break ;;
                esac
            done
        fi
        "${INHIBIT[@]}" sudo env "${envs[@]}" SHELL=/bin/bash \
            script -qefc "$(printf '%q ' "${cmd[@]}")" "$cap" >&"$out_fd" 2>&1
        rc=$?
        # A terminal recording is full of colour codes and redrawn progress
        # bars; the log gets the words.
        [ -n "$LOG_FILE" ] && sed 's/\x1b\[[0-9;?]*[A-Za-z]//g; s/\r/\n/g' "$cap" \
            | grep -vE '^[[:space:]]*$|[#-]{6,}\][[:space:]]+[0-9]+%' >> "$LOG_FILE"
    else
        "${INHIBIT[@]}" "$@" 2>&1 | tee "$cap"
        rc=${PIPESTATUS[0]}
    fi
    # Ctrl+C. Under `script` it reaches pacman and not this shell, which then
    # carried on -- into a hundred and fifty one-at-a-time retries.
    if [ "$rc" = 130 ]; then
        FAILED+=("interrupted (Ctrl+C) during: $(printf '%s ' "$@" | cut -c1-70)")
        die "interrupted: stopping here. Everything so far is safe to run again"
    fi
    return "$rc"
}

# What pacman (or yay) actually said, and what to do about it. pacman's last
# lines carry the reason; this finds the line that names it and puts the fix
# next to it, instead of a list of maybes.
pkg_diagnose() {
    local cap="${1:-$PKG_LAST_LOG}" clean line="" fix
    PKG_CAUSE=""
    PKG_CAUSE_KIND=other
    [ -n "$cap" ] && [ -f "$cap" ] || return 0
    clean="$(sed 's/\x1b\[[0-9;?]*[A-Za-z]//g; s/\r/\n/g' "$cap")"
    _said() { line="$(printf '%s\n' "$clean" | grep -m1 -iE "$1")"; [ -n "$line" ]; }
    if _said ' are in conflict'; then
        PKG_CAUSE_KIND=conflict
        fix="one of ours collides with a package you have. Keep yours (ours stays out), or remove yours with sudo pacman -R <it> and run this again"
    elif _said 'conflicting files|exists in filesystem'; then
        PKG_CAUSE_KIND=files
        fix="a file pacman did not put there is in the way: 'pacman -Qo <path>' says who owns it; if nobody does, move it away and run this again"
    elif _said 'target not found|could not find all required packages|no aur package found'; then
        PKG_CAUSE_KIND=notfound
        fix="that name is not in the repos any more (renamed or dropped): leave it out"
    elif _said 'unable to satisfy dependency|breaks dependency|could not satisfy dependencies'; then
        PKG_CAUSE_KIND=deps
        fix="something you hold back (IgnorePkg in /etc/pacman.conf) or a package from another repo is in the way: run sudo pacman -Syu and read what it says"
    elif _said 'invalid or corrupted package|signature from .* is (unknown trust|invalid|marginal)|key .* could not be (looked up|imported)|pgp signature'; then
        PKG_CAUSE_KIND=keyring
        fix="the keyring is out of date: sudo pacman -Sy archlinux-keyring && sudo pacman -Su   (on EndeavourOS or CachyOS, also their own *-keyring)"
    elif _said 'unable to lock database'; then
        PKG_CAUSE_KIND=lock
        if pgrep -x pacman >/dev/null 2>&1; then
            fix="another pacman is running (an updater?): let it finish, then run this again"
        else
            fix="a pacman that died left its lock behind, and none is running now: sudo rm /var/lib/pacman/db.lck"
        fi
    elif _said 'not enough free disk space|no space left on device'; then
        PKG_CAUSE_KIND=space
        fix="the disk is full: sudo paccache -rk1 empties most of the package cache"
    elif _said 'failed retrieving file|operation too slow|failed to retrieve some files|could not resolve host|failed to synchronize'; then
        PKG_CAUSE_KIND=download
        fix="the download: sudo pacman -Syyu refreshes the databases, and if a mirror is dead, rank them again (reflector, or your distro's own tool)"
    elif _said 'error making|failed to build|a failure occurred in (build|package|prepare|check)'; then
        PKG_CAUSE_KIND=build
        fix="an AUR package failed to build: its PKGBUILD may be out of date (look at its AUR page)"
    else
        line="$(printf '%s\n' "$clean" | grep -m1 -E '^(error|==> ERROR| *-> )')"
        fix="see the full output${LOG_FILE:+ in $LOG_FILE}"
    fi
    unset -f _said
    [ -n "$line" ] && err "  it said: $(printf '%s' "$line" | sed 's/^[[:space:]]*//' | cut -c1-160)"
    err "  fix: $fix"
    PKG_CAUSE="$(printf '%s' "${line:-no reason printed}" | sed 's/^[[:space:]]*//; s/^error: //' | cut -c1-100)"
}

# Warns, and asks, when / or the package cache has less than ~1.5 GiB free:
# pacman runs out of space half-way through extracting, not before.
check_free_space() {
    local need=$((1536 * 1024)) path avail low=()
    for path in / /var/cache/pacman/pkg; do
        [ -d "$path" ] || continue
        avail="$(df -Pk "$path" 2>/dev/null | awk 'NR == 2 { print $4 }')"
        [ -n "$avail" ] && [ "$avail" -lt "$need" ] && low+=("$path: $((avail / 1024)) MiB free")
    done
    [ ${#low[@]} -eq 0 ] && return 0
    warn "little disk space (${low[*]}); installing the packages needs about 1.5 GiB"
    ask "carry on anyway?"
}

# The system brought up to date ONCE per run, by itself, before any package of
# ours is asked for. Two reasons. Installing against databases newer than the
# installed system is a partial upgrade -- the one thing Arch tells you never
# to do -- and against older ones every download 404s. And when it fails, the
# failure is the system's own (the keyring, a mirror, a package you hold back),
# not one of our packages, and said that way it is something you can fix.
system_upgrade() {
    [ "$SYSTEM_UPGRADED" = 1 ] && return 0
    pacman_guard_setup
    if [ "$DRY" = 1 ]; then
        run sudo "${PACMAN_ENV[@]}" pacman -Syu --noconfirm --disable-download-timeout
        SYSTEM_UPGRADED=1
        return 0
    fi
    sudo_begin || true
    # --disable-download-timeout: pacman gives up on a mirror that drops below
    # a trickle for ten seconds, and on a slow or shared connection -a phone
    # hotspot, a hotel- that aborted the WHOLE transaction. Seen for real on
    # 2026-08-19 in the clean-Arch container at ~300 kB/s.
    if pkg_run sudo "${PACMAN_ENV[@]}" pacman -Syu --noconfirm --disable-download-timeout; then
        SYSTEM_UPGRADED=1
        ok "system up to date (pacman -Syu)"
        # Only an upgrade that changed something can leave the running system
        # behind what is on disk.
        grep -q 'there is nothing to do' "$PKG_LAST_LOG" 2>/dev/null || check_reboot_needed
        return 0
    fi
    err "the system's own upgrade failed, before any package of ours was asked for:"
    pkg_diagnose
    FAILED+=("system upgrade (pacman -Syu): ${PKG_CAUSE:-see above}")
    return 1
}

# True when pacman.conf names a repo whose database is not on disk yet (one
# just switched on, like [multilib]): pacman says so on every query.
sync_dbs_missing() {
    c_locale pacman -Si pacman 2>&1 >/dev/null | grep -q "database file for .* does not exist"
}

# Whether going package by package can get anything in after pacman refused
# the list. Not when the cause is the machine and not one package -- the
# database locked, the disk full, the network down, an old keyring: then all
# the retries fail the same way, and the summary drowned the one real reason
# under a hundred and fifty identical lines.
retry_makes_sense() {
    case "$PKG_CAUSE_KIND" in
        lock|space|download|keyring) return 1 ;;
    esac
    return 0
}

# install_native <what> <array-name>
# The list through every filter, then ONE pacman transaction; and if pacman
# refuses it, one package at a time, so a single package cannot cost the rest.
# pacman installs a whole transaction or none of it -- the old "everything
# else did install" was never true -- so the retry is the only way to get the
# other 159 in when one of them is broken. Returns 1 only when the system
# upgrade failed.
install_native() {
    local what="$1"
    local -n inst_ref="$2"
    local todo=() p n_bad=0
    [ ${#inst_ref[@]} -gt 0 ] || return 0
    local dbs_missing=0
    if sync_dbs_missing; then
        dbs_missing=1
        SYSTEM_UPGRADED=0
    fi
    system_upgrade || return 1
    mapfile -t todo < <(pacman -T -- "${inst_ref[@]}" 2>/dev/null)
    if [ ${#todo[@]} -eq 0 ]; then
        skip "$what: all ${#inst_ref[@]} already installed"
        return 0
    fi
    # In a dry run the sync above did not really happen, so a missing
    # database is still missing: names are not judged against it.
    if [ "$DRY" = 1 ] && [ "$dbs_missing" = 1 ]; then
        skip "$what: a repo's database is not downloaded yet; names are checked after the real sync"
    else
        drop_unknown todo pacman
    fi
    drop_conflicting todo pacman -Si
    [ ${#todo[@]} -gt 0 ] || return 0

    if [ "$DRY" = 1 ]; then
        run sudo "${PACMAN_ENV[@]}" pacman -S --needed --noconfirm --disable-download-timeout -- "${todo[@]}"
        skip "$what: would install ${#todo[@]} package(s)"
        return 0
    fi
    if pkg_run sudo "${PACMAN_ENV[@]}" pacman -S --needed --noconfirm --disable-download-timeout -- "${todo[@]}"; then
        ok "$what: ${#todo[@]} package(s) installed"
        return 0
    fi
    warn "pacman installs a whole list or none of it, and it refused this one:"
    pkg_diagnose
    if ! retry_makes_sense; then
        PKG_FAILED_ENTRIES+=("${todo[@]}")
        FAILED+=("$what: none of the ${#todo[@]} installed: ${PKG_CAUSE:-see above} -- fix that, then run this again")
        return 0
    fi
    warn "trying the ${#todo[@]} package(s) one at a time, so one cannot cost the rest"
    for p in "${todo[@]}"; do
        pkg_present "$p" && continue
        if pkg_run --quiet sudo "${PACMAN_ENV[@]}" pacman -S --needed --noconfirm --disable-download-timeout -- "$p"; then
            ok "$p"
        else
            err "$p did not install:"
            pkg_diagnose
            n_bad=$((n_bad + 1))
            PKG_FAILED_ENTRIES+=("$p")
            FAILED+=("$what: $p (${PKG_CAUSE:-see the log})")
        fi
    done
    [ "$n_bad" = 0 ] && ok "$what: all of them went in one at a time"
    return 0
}

# The same for the AUR. yay and paru build and install their list as one too,
# and stop at the first package that fails.
install_aur() {
    local -n aur_ref="$1"
    local todo=() p helper n_bad=0
    [ ${#aur_ref[@]} -gt 0 ] || return 0
    mapfile -t todo < <(pacman -T -- "${aur_ref[@]}" 2>/dev/null)
    if [ ${#todo[@]} -eq 0 ]; then
        skip "AUR: all ${#aur_ref[@]} already installed"
        return 0
    fi
    if ! helper="$(aur_helper)"; then
        if [ "$DRY" = 1 ]; then
            helper=yay
        else
            left_out "AUR packages skipped, there is no AUR helper: ${todo[*]}"
            # Not installed, so not in the baseline either: update.sh would
            # otherwise read them as removed by you and never install them.
            PKG_FAILED_ENTRIES+=("${todo[@]}")
            return 0
        fi
    fi
    drop_unknown todo "$helper"
    drop_conflicting todo "$helper" -Si
    [ ${#todo[@]} -gt 0 ] || return 0

    if [ "$DRY" = 1 ]; then
        run "$helper" -S --needed --noconfirm "${YAY_FLAGS[@]}" -- "${todo[@]}"
        skip "AUR: would build and install ${#todo[@]} package(s)"
        return 0
    fi
    sudo_begin || true
    if pkg_run env -u LANGUAGE LC_ALL=C "$helper" -S --needed --noconfirm "${YAY_FLAGS[@]}" -- "${todo[@]}"; then
        ok "AUR: ${#todo[@]} package(s) installed"
        return 0
    fi
    warn "$helper stopped:"
    pkg_diagnose
    if ! retry_makes_sense; then
        PKG_FAILED_ENTRIES+=("${todo[@]}")
        FAILED+=("AUR: none of the ${#todo[@]} installed: ${PKG_CAUSE:-see above} -- fix that, then run this again")
        return 0
    fi
    warn "trying the rest one at a time"
    for p in "${todo[@]}"; do
        pkg_present "$p" && continue
        if pkg_run --quiet env -u LANGUAGE LC_ALL=C "$helper" -S --needed --noconfirm "${YAY_FLAGS[@]}" -- "$p"; then
            ok "$p"
        else
            err "$p did not install:"
            pkg_diagnose
            n_bad=$((n_bad + 1))
            PKG_FAILED_ENTRIES+=("$p")
            FAILED+=("AUR: $p (${PKG_CAUSE:-see the log})")
        fi
    done
    [ "$n_bad" = 0 ] && ok "AUR: all of them went in one at a time"
    return 0
}

# The handful of packages the desktop cannot exist without. If they are not on
# disk after the official repos, nothing after this phase would work: config,
# services, sddm and final would lay symlinks and enable units on a machine with
# no Hyprland, and what you got at the end was a broken desktop and a warning
# lost twenty screens up (the container, 2026-08-19). So the run stops here.
packages_core_check() {
    [ "$DRY" = 1 ] && return 0
    local missing=()
    mapfile -t missing < <(pacman -T -- hyprland quickshell kitty zsh awww 2>/dev/null)
    [ ${#missing[@]} -eq 0 ] && return 0
    err "the desktop's own packages are not installed (missing: ${missing[*]})."
    err "Nothing after this phase would work, so the run stops here. The reason is"
    err "above; once it is fixed, run just this phase again:  ./install.sh packages"
    FAILED+=("the desktop's own packages are missing: ${missing[*]}")
    exit 1
}

# The list as it stood after the last run that installed it. update.sh uses it
# to tell a package newly added to the list (install it) from one you removed
# yourself (leave it removed). What failed to install is not written, so the
# next run tries it again.
baseline_write() {
    [ "$DRY" = 1 ] && return 0
    mkdir -p "$STATE_DIR" 2>/dev/null || return 0
    local e f keep=()
    for e in "$@"; do
        for f in "${PKG_FAILED_ENTRIES[@]}"; do
            [[ "|$e|" == *"|$f|"* ]] && continue 2
        done
        keep+=("$e")
    done
    printf '%s\n' "${keep[@]}" | sort -u > "$BASELINE.tmp.$$" \
        && mv -f "$BASELINE.tmp.$$" "$BASELINE"
}

phase_packages() {
    heading "Packages"

    local entries=() aur_entries=() native=() aur=()
    mapfile -t entries < <(read_native_packages)
    mapfile -t aur_entries < <(read_aur_packages)

    printf '  %d packages from the official repos, %d from the AUR\n' "${#entries[@]}" "${#aur_entries[@]}"

    native=("${entries[@]}")
    aur=("${aur_entries[@]}")
    pick_alternatives native
    pick_alternatives aur
    drop_power_conflicts native

    if ! check_free_space; then
        left_out "packages skipped at your request: not enough disk space"
        return 0
    fi

    if ! install_native "official repos" native; then
        # The system's own upgrade failed. Installing ours on top of a system
        # that is not up to date would be a partial upgrade, so nothing of ours
        # goes in. On a machine that already has the desktop the rest of the
        # run is still safe; on a bare one packages_core_check stops it.
        packages_core_check
        left_out "this repo's packages: not installed, because the system upgrade failed first"
        return 0
    fi
    packages_core_check

    install_aur aur
    baseline_write "${entries[@]}" "${aur_entries[@]}"
}

# ----------------------------------------------------------------- phase: repos

phase_repos() {
    heading "git repos (zsh tooling, Hyprland plugins)"

    local manifest="$REPO/packages/git-repos.txt"
    [ -f "$manifest" ] || { warn "no git-repos.txt, skipping"; return 0; }

    while IFS=$'\t' read -r dest url extra; do
        [[ "$dest" =~ ^[[:space:]]*(#|$) ]] && continue
        local path="$HOME/$dest"
        if [ -d "$path/.git" ]; then
            skip "$dest (already cloned)"
            continue
        fi
        local depth=()
        [ "${extra:-}" = "--depth1" ] && depth=(--depth 1)
        run mkdir -p "$(dirname "$path")"
        run git clone "${depth[@]}" "$url" "$path" && ok "$dest" || warn "could not clone $dest"
    done < "$manifest"
}

# ----------------------------------------------------------------- phase: config

# What a new ~/.gitconfig.local starts as. Shared with update.sh, which seeds
# it on machines installed before it existed.
gitconfig_local_template() {
    cat <<'TEMPLATE'
# Your git identity. Not in the dotfiles repo, and it should not be.
# Uncomment the three lines below and put your own name and address in them.
# Until you do, git asks who you are on your first commit, as it would on any
# new machine.
#[user]
#	name = Your Name
#	email = you@example.com

# How you store credentials is your call. `store` keeps them in
# ~/.git-credentials in PLAIN TEXT; `cache` holds them in memory for a while,
# and libsecret hands them to your keyring.
# [credential]
#	helper = cache --timeout=3600
TEMPLATE
}

phase_config() {
    heading "Configuration ($MODE)"

    local root="$REPO/home"
    [ -d "$root" ] || die "cannot find $root"

    # First of all: if you are not diego, adapt the absolute paths the repo has
    # spelled out. This has to happen BEFORE anything is laid down, because what
    # comes after reads these same files -- 'sddm' runs an installer out of
    # ~/.config, and in link mode that IS the repo's copy.
    #
    # 'system' used to be named here too, and no longer is: it runs BEFORE this
    # phase now (see ALL_PHASES and why), and it never read $REPO/home in the
    # first place -- it walks $REPO/system and rewrites /home/diego in whatever
    # it drops into /etc by itself, a few lines further down.
    adapt_home_paths

    # Decided BEFORE anything is laid down. The repo carries its own
    # quickshell-rice.json, and once it is in place it would answer "es" for
    # every machine: asked now, the answer is what this desktop already speaks,
    # or the locale's on a fresh one. Same for a keyboard.lua you already had.
    ask_lang
    KEYBOARD_KEEP="$(cat "$HOME/.config/hypr/keyboard.lua" 2>/dev/null || true)"

    # 1) loose dotfiles at the root of $HOME
    local f
    for f in "$root"/.[!.]*; do
        [ -e "$f" ] || continue
        local base; base="$(basename "$f")"
        # .config, .local and Pictures are handled separately, further down
        case "$base" in .config|.local) continue ;; esac
        place "$f" "$HOME/$base" "$base"
    done

    # 1b) the git identity, which is the one thing in here that MUST NOT be
    #     mine. ~/.gitconfig is a symlink to the repo, so a [user] block in it
    #     would make your commits go out with my name and address on them. The
    #     repo's .gitconfig includes this file instead. The [user] lines are
    #     written COMMENTED: filled in with a placeholder they were a real
    #     identity, and every commit went out as "Your Name <you@example.com>"
    #     without git ever asking. Commented, git asks on your first commit,
    #     like on any new machine.
    if [ ! -e "$HOME/.gitconfig.local" ] && [ "$DRY" = 0 ]; then
        gitconfig_local_template > "$HOME/.gitconfig.local"
        ok ".gitconfig.local created: uncomment the [user] lines and put your name in them"
    elif [ -e "$HOME/.gitconfig.local" ]; then
        skip ".gitconfig.local already there (your git identity is yours)"
    fi

    # 2) ~/.config, entry by entry (so your configs live alongside those of
    #    programs that are not in the repo)
    run mkdir -p "$HOME/.config"
    for f in "$root"/.config/*; do
        [ -e "$f" ] || continue
        local base; base="$(basename "$f")"
        place "$f" "$HOME/.config/$base" ".config/$base"
    done

    # 3) the trees that are copied in BOTH modes, file by file through the
    #    same three-way rule as --copy (see sync_one): a file you edited is
    #    kept, one you never touched is updated, and one of yours with the same
    #    name as ours is saved aside before ours goes in. They used to be
    #    copied over whatever was there, which broke this script's own promise
    #    for every script of yours in ~/.local/bin.
    #
    #    ~/.local/bin is copied so the scripts are genuinely executable;
    #    .local/lib/pocket holds the Python modules they share; .local/src the
    #    source of the wl_shimeji cursor plugin, which you build by hand (its
    #    README says how). Fonts and icons are copied because fontconfig and
    #    GTK look for them there.
    local tree before
    before=$((SYNC_UPDATED + SYNC_ADDED))
    for tree in .local/bin .local/lib .local/src .local/share/fonts .local/share/icons; do
        deploy_tree "$tree" install
    done
    # 3a) GTK themes of our own, if there ever are any. There are none in git
    #     on purpose: the GTK theme this desktop uses is GENERATED, one per
    #     palette (`pywal-gtk-<hash>`, see gtk-pywal.sh), because GTK caches
    #     themes by name and that hash is the only way an already-open window
    #     ever repaints. Committing one would be committing a snapshot of a
    #     wallpaper. What IS in git is the part you edit: gtk-3.0/rice-gtk3.css.
    deploy_tree .local/share/themes install
    # 3b) .desktop files of our own. They are here to WIN over the ones in
    #     /usr/share/applications -~/.local/share takes precedence in XDG- so
    #     that, for instance, opening a video launches the vlc wrapper in
    #     ~/.local/bin, the one that carries the pywal palette, and not
    #     /usr/bin/vlc straight up. Without this the wrapper gets copied but
    #     nothing ever calls it.
    deploy_tree .local/share/applications install
    if [ -d "$root/.local/share/applications" ]; then
        run update-desktop-database "$HOME/.local/share/applications" 2>/dev/null || true
    fi
    if [ "$DRY" = 0 ]; then
        local b
        for b in "$root"/.local/bin/*; do
            [ -f "$HOME/.local/bin/${b##*/}" ] && chmod +x "$HOME/.local/bin/${b##*/}" 2>/dev/null
        done
    fi
    [ $((SYNC_UPDATED + SYNC_ADDED)) -eq "$before" ] && skip "~/.local: copies up to date"

    # 5) wallpapers: copied without clobbering (they count as yours: see
    #    is_user_owned). If you already have some there, they are left alone.
    deploy_tree Pictures/wallpapers install

    # 6) the rice scripts have to be runnable. Only in --copy mode: in --link
    #    mode these ARE the repo's files, whose modes git already carries, and
    #    a chmod there shows up in `git status` as a change of yours -- which
    #    update.sh would then have to step around. (And find does not descend
    #    into a symlinked directory anyway, so in link mode this did nothing.)
    if [ "$DRY" = 0 ] && [ "$MODE" = copy ]; then
        find "$HOME/.config/hypr" "$HOME/.config/quickshell" \
             -name '*.sh' -type f -exec chmod +x {} + 2>/dev/null
        ok "execute permissions on the rice scripts"
    fi

    # 7) seed the files the rice REWRITES while you use it.
    #
    #    These are state, not configuration, and they are gitignored on purpose.
    #    The reason is a bug that actually shipped: ~/.config is symlinked INTO
    #    this repo, so `remote-mode` copying a profile over hypridle.conf was
    #    writing into git. The repo was published with remote mode switched on,
    #    and every clone came up with screens that never sleep and no suspend.
    #    Keeping them untracked means using the desktop can no longer dirty the
    #    working tree, and `git pull` stops conflicting on files nobody edited
    #    by hand. The cost is that a fresh clone has to be given a starting
    #    value, which is what this does.
    #
    #    Always through $HOME, AFTER step 2. In --link mode $HOME/.config/hypr
    #    IS the repo's directory, so the seed still lands there (gitignored);
    #    in --copy mode it lands in the copy, which is where hypridle reads it.
    #    Seeding into the repo by hand broke both: in copy mode the seed never
    #    reached $HOME (no hypridle.conf at all: no lock, no blanking, no
    #    suspend -- measured 2026-09-26), and poke-theme/, a directory the repo
    #    does not carry, was created in the repo only after step 2 had run, so
    #    on a first install ~/.config/poke-theme never existed.
    local hypridle="$HOME/.config/hypr/hypridle.conf"
    if [ ! -f "$hypridle" ] && [ -f "$root/.config/hypr/hypridle.d/normal.conf" ]; then
        run mkdir -p "$(dirname "$hypridle")"
        run cp -- "$root/.config/hypr/hypridle.d/normal.conf" "$hypridle" \
            && ok "hypridle.conf seeded from the normal profile"
    fi
    local pokestate="$HOME/.config/poke-theme/state"
    if [ ! -f "$pokestate" ]; then
        run mkdir -p "$(dirname "$pokestate")"
        if [ "$DRY" = 0 ]; then
            printf 'on\n' > "$pokestate" && ok "poke-theme state seeded"
        else
            run printf 'on\n' ">" "$pokestate"
        fi
    fi

    #    Thunar (the file manager, Super+E) keeps NOTHING in this repo that it
    #    would read by itself: version 4.20 dropped ~/.config/Thunar/thunarrc
    #    and moved everything into xfconf, whose on-disk backup is rewritten by
    #    xfconfd whenever it feels like it -- so shipping that XML would be
    #    shipping a file that gets overwritten. The settings live in a script
    #    instead, and this is where it runs. Without it Thunar comes up with
    #    the stock XFCE look: classic menu bar, no client-side decorations
    #    (which under Hyprland means no close button at all), tiny icons.
    if [ -x "$HOME/.config/hypr/scripts/thunar-settings.sh" ] && command -v xfconf-query >/dev/null 2>&1; then
        run sh -c "'$HOME/.config/hypr/scripts/thunar-settings.sh' >/dev/null 2>&1" \
            && ok "Thunar configured (xfconf)"
    fi
    #    And its right-click actions, which are generated in the language of
    #    the rice (uca.xml has no way of translating itself).
    if [ -x "$HOME/.config/hypr/scripts/thunar-language.sh" ]; then
        run sh -c "'$HOME/.config/hypr/scripts/thunar-language.sh' >/dev/null 2>&1" \
            && ok "Thunar custom actions written"
    fi

    # 8) the language. Last, because it edits files that have just been laid
    #    down, and before the 'sddm' phase, which copies one of them into /usr.
    apply_language

    #    And the keyboard, for the same reason: it lands next to hyprland.lua.
    set_keyboard

    # 9) and now that both sides agree, write down WHAT they agreed on. From
    #    here on ./diagnose can name the side that moved instead of handing you
    #    a list of files and a shrug.
    digests_write
    [ "$MODE" = copy ] && deployed_write

    # 10) last, the one check that is not about dotfiles at all: hyprlock.conf
    #     has just landed naming its own PAM service. If that service is not on
    #     the machine, the way you find out is by locking your screen, so it is
    #     said out loud here instead.
    check_lock_pam
}

# ----------------------------------------------------------------- phase: system

# The two-letter country of this machine, from its time zone: zone.tab maps
# every zone to a country, and the time zone is the one thing a fresh install
# always asks for. Empty when it cannot tell (UTC, no tzdata).
machine_country() {
    local tz=""
    tz="$(readlink /etc/localtime 2>/dev/null)"
    tz="${tz#*zoneinfo/}"
    [ -n "$tz" ] || return 0
    awk -v z="$tz" '!/^#/ && $3 == z { print $1; exit }' /usr/share/zoneinfo/zone.tab 2>/dev/null
}

# Who already ranks this machine's mirrors, when it is not us. A derivative
# keeps its own mirrorlist tooling (EndeavourOS, CachyOS), Omarchy pins its
# own, and a reflector.conf someone else edited is a choice already made.
# Writing ours, plus a weekly reflector.timer, over any of them meant two
# tools rewriting the same mirrorlist -- with European mirrors, because the
# repo's laptop is in Spain.
mirrors_managed_elsewhere() {
    case "$DISTRO_ID" in
        arch|'') ;;
        *) printf '%s' "${DISTRO_NAME:-$DISTRO_ID}"; return 0 ;;
    esac
    [ "$IS_OMARCHY" = 1 ] && { printf 'Omarchy'; return 0; }
    local t conf=/etc/xdg/reflector/reflector.conf
    for t in cachyos-rate-mirrors eos-rankmirrors rate-mirrors; do
        command -v "$t" >/dev/null 2>&1 && { printf '%s' "$t"; return 0; }
    done
    # Edited, and not by us: ours leaves its .before-dotfiles next to it.
    if [ -f "$conf" ] && [ ! -e "$conf.before-dotfiles" ] \
       && c_locale pacman -Qii reflector 2>/dev/null | grep -qE "$conf \[modified\]"; then
        printf 'your own reflector.conf'
        return 0
    fi
    return 1
}

SYSTEM_EFF=""

# A firewall that is already on. Our nftables ruleset next to ufw's or
# firewalld's means two rulesets, and a packet has to get past both: the ports
# you opened in yours stay closed by ours.
other_firewall() {
    local u
    for u in ufw firewalld; do
        if systemctl is-enabled --quiet "$u.service" 2>/dev/null \
           || systemctl is-active --quiet "$u.service" 2>/dev/null; then
            printf '%s' "$u"
            return 0
        fi
    done
    return 1
}

sshd_enabled() {
    systemctl is-enabled --quiet sshd.service 2>/dev/null \
        || systemctl is-active --quiet sshd.service 2>/dev/null \
        || systemctl is-enabled --quiet sshd.socket 2>/dev/null
}

# The repo's firewall drops everything that comes in unasked, and lets SSH in
# only through Tailscale. Right for the laptop it was written on; on a machine
# you reach over SSH on your own network, it locks you out at the next boot.
# So restricting SSH is a choice: kept where it was already made (the
# installed file has the rule), asked for where an SSH server runs (and an
# unattended run answers no), and otherwise left as the repo has it, because
# with no SSH server the rule opens and closes nothing.
nftables_for_this_machine() {
    local src="$1" gen="$2" out
    local ts='iifname "tailscale0" tcp dport 22 accept comment "allow SSH over Tailscale"'
    local open='tcp dport 22 accept comment "allow SSH on every interface (chosen at install)"'
    local choice=ask
    if grep -qF 'iifname "tailscale0" tcp dport 22 accept' /etc/nftables.conf 2>/dev/null \
       || ! sshd_enabled; then
        choice=restrict
    elif grep -qF 'allow SSH on every interface (chosen at install)' /etc/nftables.conf 2>/dev/null; then
        choice=open
    fi
    if [ "$choice" = ask ]; then
        warn "this machine runs an SSH server, and the firewall in this repo lets SSH in"
        warn "ONLY over Tailscale: from your network, or anywhere else, it would be refused."
        if ask_risky "restrict SSH to Tailscale only?"; then choice=restrict; else choice=open; fi
    fi
    if [ "$choice" = restrict ]; then
        SYSTEM_EFF="$src"
        return 0
    fi
    [ -n "$gen" ] || return 1
    out="$gen/nftables.conf"
    awk -v ts="$ts" -v open="$open" '{ i = index($0, ts); if (i) $0 = substr($0, 1, i - 1) open; print }' \
        "$src" > "$out"
    skip "SSH stays open on every interface in /etc/nftables.conf"
    SYSTEM_EFF="$out"
}

# Which version of a system/etc file goes into THIS machine's /etc, left in
# SYSTEM_EFF -- not printed, because it talks, and a $(...) would swallow both
# its messages and the summary lines it adds. Returns 1 when the file should
# not go in at all. Most files go in exactly as they are. A few carry a choice the repo's own laptop made, and copying
# them verbatim made that choice for every machine.
system_file_for() {
    local rel="$1" src="$2" gen="$3" cc out reason
    case "$rel" in
        conf.d/wireless-regdom)
            # The Wi-Fi regulatory domain is a legal setting -- which channels,
            # at what power -- and the repo says Spain because the laptop is
            # there. Elsewhere it follows your time zone; with no time zone
            # to go by it is left alone, and the access point's own country
            # information applies, as on any fresh Arch.
            cc="$(machine_country)"
            if [ -z "$cc" ]; then
                skip "/etc/$rel left alone: no time zone to tell the country by"
                return 1
            fi
            [ "$cc" = ES ] && { SYSTEM_EFF="$src"; return 0; }
            [ -n "$gen" ] || return 1
            out="$gen/wireless-regdom"
            sed "s/^WIRELESS_REGDOM=.*/WIRELESS_REGDOM=\"$cc\"/" "$src" > "$out"
            SYSTEM_EFF="$out"
            ;;
        xdg/reflector/reflector.conf)
            if reason="$(mirrors_managed_elsewhere)"; then
                skip "/etc/$rel left alone: the mirrors are managed by $reason"
                return 1
            fi
            # The countries follow the time zone too. With none, no --country
            # at all: reflector then ranks the freshest mirrors worldwide.
            cc="$(machine_country)"
            [ "$cc" = ES ] && { SYSTEM_EFF="$src"; return 0; }
            [ -n "$gen" ] || return 1
            out="$gen/reflector.conf"
            if [ -n "$cc" ]; then
                sed "s/^--country .*/--country $cc/" "$src" > "$out"
            else
                grep -v '^--country ' "$src" > "$out"
            fi
            SYSTEM_EFF="$out"
            ;;
        nftables.conf)
            if reason="$(other_firewall)"; then
                left_out "/etc/nftables.conf not installed: $reason is already this machine's firewall"
                return 1
            fi
            nftables_for_this_machine "$src" "$gen"
            ;;
        *)
            SYSTEM_EFF="$src"
            ;;
    esac
}

phase_system() {
    heading "System files (/etc and /usr)"

    local root="$REPO/system/etc"
    local usr_root="$REPO/system/usr"
    # Either branch on its own is reason enough to run: they are unrelated
    # trees, and hanging /usr off the existence of system/etc would quietly
    # drop the pkexec helper and its polkit policy.
    if [ ! -d "$root" ] && [ ! -d "$usr_root" ]; then
        warn "no system/ tree, skipping"
        return 0
    fi

    warn "this phase writes to /etc and /usr, and needs sudo"
    ask "carry on?" || { skip "skipped at your request"; return 0; }

    # sudo has to be able to ask for the password BEFORE anything is copied.
    # Without a terminal (a pipe, a cron job, an assistant's shell) every sudo
    # below fails, and the loop used to carry on printing "ok" over each one
    # while nothing at all reached /etc.
    if [ "$DRY" = 0 ] && ! sudo_begin; then
        warn "nothing was copied. Run it from a terminal:  ./install.sh system"
        SKIPPED+=("system files: sudo could not ask for a password")
        return 0
    fi

    local src dest rel eff
    local gen; gen="$(mktemp -d "${TMPDIR:-/tmp}/pocket-etc.XXXXXXXX")" || gen=""
    [ -n "$gen" ] && EXIT_TMP+=("$gen")
    while IFS= read -r src; do
        rel="${src#"$root"/}"
        dest="/etc/$rel"

        # A few of these files carry a choice of the machine they were written
        # on. system_file_for decides, per machine, whether each goes in as it
        # is, adapted, or not at all; it prints the file to copy.
        system_file_for "$rel" "$src" "$gen" || continue
        eff="$SYSTEM_EFF"

        # Comparing only reads, so it is done for real in dry-run too: otherwise
        # dry mode would call everything "identical" and show you nothing.
        # Almost all of /etc is readable without root; sudo is only reached for
        # when it is not, so a password is asked for only when truly needed.
        # cmp comes from diffutils, which is NOT in a minimal Arch. If it is
        # missing, the comparison is skipped and the file is always copied:
        # noisier, but correct.
        if [ -e "$dest" ] && command -v cmp >/dev/null 2>&1; then
            if [ -r "$dest" ]; then
                cmp -s "$eff" "$dest" && { skip "/etc/$rel (identical)"; continue; }
            elif sudo -n cmp -s "$eff" "$dest" 2>/dev/null; then
                skip "/etc/$rel (identical)"; continue
            fi
        fi

        # The file that was there BEFORE the dotfiles, kept once. Taken on
        # every change, it was overwritten by our own previous version the
        # second time the repo changed that file, and the original was gone.
        if [ -e "$dest" ] && [ ! -e "$dest.before-dotfiles" ]; then
            run sudo cp -a "$dest" "$dest.before-dotfiles"
            printf '       %s(the previous one is kept as %s.before-dotfiles)%s\n' "$C_DIM" "$dest" "$C_OFF"
        fi

        run sudo mkdir -p "$(dirname "$dest")"
        if ! run sudo cp "$eff" "$dest"; then
            failed "could not write /etc/$rel"
            continue
        fi


        # Nothing under system/etc/ spells out /home/diego today -- the unit
        # that did was retired -- but a file dropped into /etc is the one place
        # where that would be invisible until it broke, so the net stays up.
        if [ "$HOME" != /home/diego ] && [ "$DRY" = 0 ] && grep -q '/home/diego' "$dest" 2>/dev/null; then
            sudo sed -i "$(home_paths_sed)" "$dest"
            printf '       %s(rewrote /home/diego -> %s)%s\n' "$C_DIM" "$HOME" "$C_OFF"
        fi
        ok "/etc/$rel"
    done < <(find "$root" -type f 2>/dev/null | sort)

    # A machine installed before the rename has the old file AND, now, the new
    # one -- and two paccache drop-ins that both add an ExecStart= run the purge
    # twice. The old one is moved aside under a name nothing reads (systemd,
    # sysctl and UPower only pick up *.conf), and only once the new one is there.
    local old new
    for old in "${!RENAMED_ETC[@]}"; do
        new="${RENAMED_ETC[$old]}"
        [ -e "/etc/$old" ] || continue
        [ "$DRY" = 1 ] || [ -e "/etc/$new" ] || continue
        run sudo mv "/etc/$old" "/etc/$old.renamed-by-dotfiles"
        ok "/etc/$old moved aside: /etc/$new replaces it"
    done

    # THE HALF THAT CAN LOCK YOU OUT, and the reason this guard is here at all.
    # /etc/hypr/hyprlock-face.conf is what tells hyprlock to authenticate
    # against the PAM service 'hyprlock-face', and that service is a SEPARATE
    # file, system/etc/pam.d/hyprlock-face. The loop above walks in `sort`
    # order, so etc/hypr/ lands before etc/pam.d/: a run that does not get all
    # the way through -- a sudo that times out, a cp that fails, a disk that
    # fills -- can leave the .conf naming a service that is not on the machine.
    # PAM then falls back to /etc/pam.d/other, which on Arch is pam_deny, and
    # the lock screen refuses the face AND the password. The only way back in
    # is Ctrl+Alt+F2.
    #
    # So the orphan is taken back off. Without it hyprlock uses the PAM service
    # its own package ships and the password works again; the face is simply
    # not set up yet, which is the right way for this to fail. Re-running the
    # phase puts the pair back.
    #
    # Not a substitute for finishing the phase: a hard Ctrl+C never gets here,
    # because the shell is gone before the loop returns. Re-run 'system'.
    if [ "$DRY" = 0 ] && [ -f "$root/hypr/hyprlock-face.conf" ] \
       && [ -e /etc/hypr/hyprlock-face.conf ] && [ ! -e /etc/pam.d/hyprlock-face ]; then
        warn "/etc/pam.d/hyprlock-face never landed, and /etc/hypr/hyprlock-face.conf"
        warn "on its own leaves the lock screen refusing the face AND the password."
        if run sudo rm -f /etc/hypr/hyprlock-face.conf; then
            warn "The orphan has been removed; the password works again. Run"
            warn "  ./install.sh system   again to put the pair back."
        else
            warn "IT COULD NOT BE REMOVED. Do it by hand BEFORE you lock the screen:"
            warn "  sudo rm /etc/hypr/hyprlock-face.conf"
        fi
    fi

    # system/usr: what is not a setting in /etc but a PROGRAM, and therefore
    # has to live where the user cannot rewrite it. Today there are two: the
    # helper /usr/lib/hyprisland/face, which pkexec runs as root to list, add
    # and remove howdy's faces, and the polkit policy that says who may ask it
    # to. They go in /usr and not in /etc or ~/.config for exactly that reason:
    # polkit points at a PATH, and if that path were writable by the user, any
    # program of theirs would have root without being asked.
    #
    # No .before-dotfiles copy here: these paths belong to no package and
    # nothing else writes them, so there is nothing previous to keep. The
    # execute bit is set by hand because git only tells 644 from 755, and the
    # helper has to be executable for pkexec to launch it.
    #
    # polkitd watches /usr/share/polkit-1/actions by itself: a new policy takes
    # effect without restarting the daemon or the session.
    if [ -d "$usr_root" ]; then
        while IFS= read -r src; do
            rel="${src#"$usr_root"/}"
            dest="/usr/$rel"

            if [ -r "$dest" ] && command -v cmp >/dev/null 2>&1 && cmp -s "$src" "$dest"; then
                skip "/usr/$rel (identical)"; continue
            fi

            run sudo mkdir -p "$(dirname "$dest")"
            if [ -x "$src" ]; then
                run sudo install -o root -g root -m 755 "$src" "$dest"
            else
                run sudo install -o root -g root -m 644 "$src" "$dest"
            fi
            ok "/usr/$rel"
        done < <(find "$usr_root" -type f 2>/dev/null | sort)
    fi

    run sudo systemctl daemon-reload
    run sudo sysctl --system >/dev/null 2>&1
    # udev too. Nothing under system/etc/ ships a udev rule today -- the NVMe
    # one was deliberately left out, because two of its three rules are
    # unbounded and would switch runtime PM off for every NVMe on any machine
    # that installed this repo -- so right now this reload does nothing. It is
    # here so that the day a rule DOES ship, it goes live for the next uevent
    # instead of sitting written and inert until a reboot.
    if command -v udevadm >/dev/null 2>&1; then
        run sudo udevadm control --reload >/dev/null 2>&1
    fi
    ok "systemd, sysctl and udev reloaded"

    # The rest of /etc is not a file you can drop in, it is a setting inside a
    # file that pacman owns. Each one is checked first so re-running says
    # nothing, and none of them is touched if it is already right.

    # multilib. Not needed by anything in packages/ today -lib32-glibc lives in
    # core now- but it is on in the original machine, and without it any lib32
    # package you reach for later is simply not found.
    if grep -qE '^\[multilib\]' /etc/pacman.conf 2>/dev/null; then
        skip "multilib already enabled"
    elif [ "$DRY" = 1 ]; then
        skip "would enable [multilib] in /etc/pacman.conf"
    else
        if grep -qE '^#\[multilib\]' /etc/pacman.conf; then
            sudo sed -i '/^#\[multilib\]/,/^#Include = .*mirrorlist/ s/^#//' /etc/pacman.conf
        else
            # Not every pacman.conf carries the commented-out block to uncomment:
            # the Arch container image ships one trimmed down without it, and
            # some derivatives rewrite the file. Then the section is added at
            # the end, which is where pacman reads repositories from anyway.
            printf '\n[multilib]\nInclude = /etc/pacman.d/mirrorlist\n' | sudo tee -a /etc/pacman.conf >/dev/null
        fi
        grep -qE '^\[multilib\]' /etc/pacman.conf && ok "multilib enabled" \
            || warn "could not enable multilib; do it by hand in /etc/pacman.conf"
        # A new repo has no database until the next sync, and the packages
        # phase has already had its -Syu: without this, the graphics phase
        # looked the lib32 drivers up in a database that did not exist and
        # called them "renamed or dropped".
        SYSTEM_UPGRADED=0
    fi

    # Locale. en_US.UTF-8 is generated because some tools here assume it
    # exists, but it only becomes the system language on a machine that has
    # none yet. It used to be written over whatever was there, which turned the
    # system of anyone who runs it in German or Spanish into English.
    if locale -a 2>/dev/null | grep -qi '^en_US.utf8$'; then
        skip "locale en_US.UTF-8 already generated"
    elif [ "$DRY" = 1 ]; then
        skip "would generate the en_US.UTF-8 locale"
    else
        sudo sed -i 's/^#\(en_US.UTF-8 UTF-8\)/\1/' /etc/locale.gen
        run sudo locale-gen >/dev/null 2>&1
        ok "locale en_US.UTF-8 generated"
    fi
    if grep -qs '^LANG=' /etc/locale.conf; then
        skip "system language left as it is ($(sed -n 's/^LANG=//p' /etc/locale.conf | head -1))"
    elif [ "$DRY" = 1 ]; then
        skip "would set the system language to en_US.UTF-8 (there is none)"
    else
        echo 'LANG=en_US.UTF-8' | sudo tee /etc/locale.conf >/dev/null
        ok "system language set to en_US.UTF-8 (there was none)"
    fi

    # The keyboard is NOT set here any more. This used to force a Spanish
    # layout on the console and on X11 for everybody; now the system keeps the
    # one you chose when you installed Arch, and the desktop follows it through
    # ~/.config/hypr/keyboard.lua, which the 'config' phase writes
    # (see set_keyboard).

    # Parallel builds for makepkg. The original machine says -j4 on 8 threads;
    # here it is derived from the actual CPU instead of copying that number,
    # because the whole point is that it matches the machine you are on.
    local jobs; jobs=$(( $(nproc 2>/dev/null || echo 2) / 2 ))
    [ "$jobs" -lt 1 ] && jobs=1
    if grep -qE "^MAKEFLAGS=\"-j$jobs\"" /etc/makepkg.conf 2>/dev/null; then
        skip "makepkg already at -j$jobs"
    elif grep -qE '^MAKEFLAGS=' /etc/makepkg.conf 2>/dev/null; then
        # Somebody already chose (CachyOS ships -j$(nproc)); that stays.
        skip "makepkg MAKEFLAGS already set ($(sed -n 's/^MAKEFLAGS=//p' /etc/makepkg.conf | head -1)); left as it is"
    elif [ "$DRY" = 1 ]; then
        skip "would set makepkg MAKEFLAGS to -j$jobs"
    else
        sudo sed -i "s/^#\?MAKEFLAGS=.*/MAKEFLAGS=\"-j$jobs\"/" /etc/makepkg.conf
        ok "makepkg set to -j$jobs (half of $(nproc) threads)"
    fi
}

# ----------------------------------------------------------------- phase: graphics

# Every graphics card in the machine, one line each: "<vendor> <pci-addr> <device-id>".
#
# Straight out of sysfs and NOT out of `lspci`, for two reasons. pciutils is not
# part of `base`, so on a machine that has not reached the 'packages' phase yet
# lspci may simply not exist; and its output is a sentence written for a human,
# while /sys/bus/pci/devices/*/{class,vendor,device} hand you the very numbers
# the kernel matched its own drivers on.
#
# The three classes are the ones that can drive a screen: 0300 VGA, 0302 "3D
# controller" (how a laptop's discrete card almost always shows up, because it
# has no VGA legacy interface) and 0380 "display controller" (virtio and some
# vGPUs). Looking only at 0300 is the classic way to miss a dGPU entirely.
gpu_scan() {
    local dev class vendor devid v
    for dev in /sys/bus/pci/devices/*; do
        [ -r "$dev/class" ] || continue
        class="$(<"$dev/class")"
        case "$class" in 0x0300*|0x0302*|0x0380*) ;; *) continue ;; esac
        vendor="$(<"$dev/vendor")"
        devid="$(<"$dev/device")"
        case "$vendor" in
            0x8086) v=intel  ;;
            0x1002) v=amd    ;;   # AMD/ATI graphics have always been 1002
            0x1022) v=amd    ;;   # AMD's own vendor id, just in case
            0x10de) v=nvidia ;;
            *)      v=other  ;;   # virtio, VMware, Aspeed BMC... mesa and no more
        esac
        printf '%s %s %s\n' "$v" "${dev##*/}" "$devid"
    done
}

# Which kernel driver has actually got hold of that card right now, or "none".
# Worth printing: "nouveau" is the tell-tale that the proprietary NVIDIA driver
# is not in place yet, which is precisely the state the tower was in.
gpu_kernel_driver() {
    local drv="/sys/bus/pci/devices/$1/driver"
    if [ -e "$drv" ]; then printf '%s' "$(basename "$(readlink -f "$drv")")"
    else printf 'none'; fi
}

# How many monitors are plugged into the card at a given PCI address. Each
# connector lives in /sys/class/drm/cardN-<OUTPUT>/, and its card's `device`
# symlink points back at the PCI device, which is how the two are tied together
# without ever trusting the N in cardN.
gpu_connected_outputs() {
    local addr="$1" n=0 st
    for st in /sys/class/drm/card*-*/status; do
        [ -r "$st" ] || continue
        [ "$(basename "$(readlink -f "${st%/status}/../device" 2>/dev/null)")" = "$addr" ] || continue
        [ "$(<"$st")" = connected ] && n=$((n + 1))
    done
    printf '%s' "$n"
}

# The /dev/dri node for a PCI address, by path and never by cardN. The number in
# cardN is handed out in probe order and moves between boots as soon as two
# drivers are racing -- on this very laptop the only card is card1, not card0 --
# while the PCI address is bolted to the slot on the board.
gpu_drm_node() {
    local p="/dev/dri/by-path/pci-$1-card"
    [ -e "$p" ] && printf '%s' "$p"
}

# Is nvidia_drm.modeset=1 in effect? Asked three different ways because at this
# point in an install the module is usually not even loaded yet.
nvidia_modeset_on() {
    # `modprobe -c` merges /etc/modprobe.d, /run/modprobe.d and
    # /usr/lib/modprobe.d without loading anything, and /usr/lib/modprobe.d is
    # where nvidia-utils drops its own file. This works the second pacman
    # finishes, no reboot needed.
    modprobe -c 2>/dev/null | grep -qE '^options[[:space:]]+nvidia[-_]drm\b.*modeset=1' && return 0
    # Already running with it on.
    [ "$(cat /sys/module/nvidia_drm/parameters/modeset 2>/dev/null)" = Y ] && return 0
    # Or somebody put it on the kernel command line by hand.
    grep -qE '(^| )nvidia[-_]drm\.modeset=1( |$)' /proc/cmdline 2>/dev/null && return 0
    return 1
}

# Installs the video drivers for whatever hardware is actually in this machine,
# instead of for the machine the repo happened to be born on.
#
# WHY THIS PHASE RUNS AFTER 'system' AND NOT WITH 'packages'. The 32-bit halves
# of the drivers live in [multilib], and [multilib] is switched on by the
# 'system' phase. Installing them any earlier means every lib32-* line fails
# with "target not found" on the one run where it matters most: the first.
phase_graphics() {
    heading "Graphics drivers"

    local gpus=()
    mapfile -t gpus < <(gpu_scan)

    # ' common ' always applies; the vendors found get appended to it. A string
    # rather than an array so that "does this line apply?" is one glob match.
    local vendor_set=" common "
    local entry vendor addr devid nvidia_modern=0 nvidia_legacy=""

    if [ ${#gpus[@]} -eq 0 ]; then
        warn "no graphics card found in /sys/bus/pci (a VM without passthrough?)"
        warn "installing mesa alone: Hyprland will render in software, slowly, but it will start"
    else
        # Said out loud, because this is the line that would have explained the
        # tower's black screen in one second instead of one evening.
        for entry in "${gpus[@]}"; do
            read -r vendor addr devid <<<"$entry"
            printf '  %s%-6s%s %s  id=%s  driver=%-8s monitors=%s\n' \
                   "$C_TIT" "$vendor" "$C_OFF" "$addr" "$devid" \
                   "$(gpu_kernel_driver "$addr")" "$(gpu_connected_outputs "$addr")"

            if [ "$vendor" = nvidia ]; then
                # nvidia-open only supports Turing (RTX 20xx, 2018) and newer.
                # Rather than carry a table of every card NVIDIA ever made, lean
                # on the fact that they hand PCI device ids out roughly in
                # chronological order: Turing opens at 0x1e00 and everything
                # after it climbs (Ampere 0x22xx, Ada 0x26xx, Blackwell 0x2bxx
                # -- the tower's GB205 among them), while Pascal tops out around
                # 0x1d81. It is a heuristic and it is labelled as one; being
                # wrong costs a warning, not a broken install.
                if [ "$((devid))" -ge "$((0x1e00))" ]; then
                    nvidia_modern=1
                else
                    nvidia_legacy="$nvidia_legacy $devid"
                fi
            fi
            case "$vendor_set" in
                *" $vendor "*) ;;
                *) vendor_set="$vendor_set$vendor " ;;
            esac
        done
    fi

    # An NVIDIA card too old for the open modules must NOT get them: a kernel
    # module that refuses to load is strictly worse than nouveau, which at least
    # paints something. Drop the whole vendor and say what the alternatives are.
    if [ -n "$nvidia_legacy" ] && [ "$nvidia_modern" = 0 ]; then
        vendor_set="${vendor_set/ nvidia / }"
        warn "the NVIDIA card ($nvidia_legacy) looks older than Turing: nvidia-open does not support it"
        printf '       %sIt stays on nouveau (which mesa provides). The closed driver for old cards%s\n' "$C_DIM" "$C_OFF"
        printf '       %sis only in the AUR now: yay -S nvidia-580xx-dkms%s\n' "$C_DIM" "$C_OFF"
    fi

    # Microcode is not a GPU matter, and it is no longer installed here at all:
    # the package drops an image into /boot that the bootloader (or the
    # initramfs) has to load, and this installer does not touch /boot. What
    # stays is saying so when the right one is missing -- intel-ucode used to
    # sit in pacman.txt unconditionally, so an AMD machine got a package that
    # does nothing and missed the one it needs.
    local ucode=""
    case "$(grep -m1 '^vendor_id' /proc/cpuinfo 2>/dev/null)" in
        *GenuineIntel*) ucode=intel-ucode ;;
        *AuthenticAMD*) ucode=amd-ucode ;;
    esac
    if [ -n "$ucode" ] && ! pkg_present "$ucode"; then
        left_out "$ucode (your CPU's microcode) is not installed. It goes into /boot, which this installer leaves to you: sudo pacman -S $ucode, then regenerate your bootloader's config if it needs it"
    fi

    local manifest="$REPO/packages/gpu.txt"
    [ -f "$manifest" ] || { warn "no packages/gpu.txt, skipping"; return 0; }

    local multilib=0
    grep -qE '^\[multilib\]' /etc/pacman.conf 2>/dev/null && multilib=1

    local pkgs=() deferred=() v a p
    while read -r v a p _; do
        [[ "$v" =~ ^(#|$) ]] && continue
        [ -n "${p:-}" ] || continue
        [[ "$vendor_set" == *" $v "* ]] || continue
        if [ "$a" = 32 ] && [ "$multilib" = 0 ]; then
            deferred+=("$p")
            continue
        fi
        pkgs+=("$p")
    done < "$manifest"

    if [ ${#deferred[@]} -gt 0 ]; then
        left_out "32-bit drivers (${deferred[*]}): [multilib] is off. Run the 'system' phase, which enables it, then ./install.sh graphics"
    fi

    if [[ "$vendor_set" == *" nvidia "* ]]; then
        nvidia_kernel_module pkgs
    fi

    if [ ${#pkgs[@]} -eq 0 ]; then
        warn "nothing to install for this hardware (that is odd; check packages/gpu.txt)"
        return 0
    fi

    printf '  %d packages for this hardware: %s\n' "${#pkgs[@]}" "${pkgs[*]}"
    # Through the same path as every other package: the system up to date
    # first, then what pacman cannot find or would have to remove something
    # for is left out by name, and the rest goes in -- one at a time if pacman
    # refuses the list. It used to be one bare `pacman -Syu` here, and on a
    # machine that already had nvidia-open-dkms the "Remove nvidia-open-dkms?"
    # question, answered N by --noconfirm, cancelled every driver in the list.
    local before=${#FAILED[@]}
    if ! install_native "video drivers" pkgs || [ ${#FAILED[@]} -gt "$before" ]; then
        err "Some video drivers did not install. This is the one thing that ends in a"
        err "BLACK SCREEN with nothing in any log, so do not reboot before fixing it."
        err "Once fixed:  ./install.sh graphics"
        FAILED+=("video drivers: see above before rebooting")
    fi

    # --- NVIDIA on Wayland: the kernel parameter this installer will not set ---
    if [[ "$vendor_set" == *" nvidia "* ]] && [ "$DRY" = 0 ]; then
        # Without nvidia_drm.modeset=1 the NVIDIA driver exposes no real KMS,
        # and a Wayland compositor then has nothing to talk to: Hyprland exits
        # at startup and you are looking at a black screen. Since driver 545 the
        # module defaults to on by itself, and Arch's nvidia-utils also drops
        # `options nvidia_drm modeset=1` into /usr/lib/modprobe.d, so on 610 it
        # is almost certainly already fine -- but "almost certainly" is exactly
        # what cost an evening, so it gets checked rather than assumed.
        if nvidia_modeset_on; then
            ok "nvidia_drm.modeset=1 is in effect (nothing to do)"
        else
            warn "could not confirm nvidia_drm.modeset=1"
            printf '       %sOn driver 610 it is the default, so this is probably fine. If you do end up%s\n' "$C_DIM" "$C_OFF"
            printf '       %swith a black screen, it is the first thing to force. THIS INSTALLER WILL NOT%s\n' "$C_DIM" "$C_OFF"
            printf '       %sDO IT FOR YOU: it is a kernel parameter, and the repo never touches /boot or%s\n' "$C_DIM" "$C_OFF"
            printf '       %sthe bootloader. Add nvidia_drm.modeset=1 to your kernel command line:%s\n' "$C_DIM" "$C_OFF"
            printf '       %s  GRUB: GRUB_CMDLINE_LINUX_DEFAULT in /etc/default/grub, then grub-mkconfig%s\n' "$C_DIM" "$C_OFF"
            printf '       %s  systemd-boot: the options line of /boot/loader/entries/*.conf%s\n' "$C_DIM" "$C_OFF"
            printf '       %s  limine: the cmdline of /etc/default/limine (or /boot/limine.conf)%s\n' "$C_DIM" "$C_OFF"
        fi
    fi

    graphics_pick_render_device "${gpus[@]+"${gpus[@]}"}"
}

# The kernels installed on this machine, one name each (linux, linux-lts,
# linux-cachyos...). Every kernel package ships /usr/lib/modules/<version>/
# pkgbase holding its own package name, which is the one answer that does not
# depend on a list of kernel names: the old fixed list (linux, -lts, -zen...)
# did not know linux-cachyos, and on CachyOS it picked the nvidia-open that is
# built for -- and depends on -- the stock `linux`.
installed_kernels() {
    local f out=()
    for f in /usr/lib/modules/*/pkgbase; do
        [ -r "$f" ] && out+=("$(<"$f")")
    done
    if [ ${#out[@]} -eq 0 ]; then
        mapfile -t out < <(pacman -Qq 2>/dev/null | grep -xE 'linux(-[a-z0-9]+)*' \
                           | grep -vxE 'linux-(firmware|api-headers|docs|tools|headers)(-.*)?|.*-(headers|docs)')
    fi
    [ ${#out[@]} -gt 0 ] && printf '%s\n' "${out[@]}" | sort -u
}

# An NVIDIA kernel module that is already installed, whatever its flavour:
# nvidia-open-dkms (what EndeavourOS's nvidia-inst and Omarchy put in),
# CachyOS's linux-cachyos-nvidia-open, the legacy 580xx series... All of them
# provide NVIDIA-MODULE, and pacman -Qq answers for a provision with the
# package that provides it.
nvidia_module_installed() {
    local m
    m="$(pacman -Qq NVIDIA-MODULE 2>/dev/null | head -1)"
    [ -n "$m" ] || m="$(pacman -Qq 2>/dev/null \
        | grep -xE 'nvidia(-open)?(-dkms|-lts)?|nvidia-[0-9]+xx(-dkms)?|linux-.*-nvidia(-open)?' | head -1)"
    [ -n "$m" ] && printf '%s' "$m"
}

# Settles the kernel module in the array named $1, which arrives holding
# nvidia-open from gpu.txt.
#   - a module already installed stays, and nvidia-open is not added next to
#     it (they conflict; that question used to cancel the whole driver list);
#   - every kernel with a prebuilt module of its own in the repos (linux ->
#     nvidia-open, linux-lts -> nvidia-open-lts, linux-cachyos ->
#     linux-cachyos-nvidia-open): those;
#   - anything else: nvidia-open-dkms, plus the headers of EVERY installed
#     kernel, because DKMS builds the module once per kernel and a kernel
#     without its headers boots without a driver.
nvidia_kernel_module() {
    local -n nv_ref="$1"
    local kernels=() k mod rest=() p need_headers=0 prebuilt=()
    mapfile -t kernels < <(installed_kernels)
    for p in "${nv_ref[@]}"; do
        [ "$p" = nvidia-open ] || rest+=("$p")
    done
    nv_ref=("${rest[@]}")

    if mod="$(nvidia_module_installed)"; then
        ok "NVIDIA kernel module already provided by $mod: it stays"
        case "$mod" in *dkms*) need_headers=1 ;; esac
    elif [ ${#kernels[@]} -eq 0 ]; then
        warn "cannot tell which kernels are installed: using nvidia-open-dkms"
        nv_ref+=(nvidia-open-dkms dkms)
    else
        # The prebuilt module of each kernel, under the two names the repos
        # use: Arch's nvidia-open / nvidia-open-lts, CachyOS's
        # linux-cachyos-nvidia-open.
        for k in "${kernels[@]}"; do
            if [ "$k" = linux ]; then
                prebuilt+=(nvidia-open)
            elif pacman -Si -- "$k-nvidia-open" >/dev/null 2>&1; then
                prebuilt+=("$k-nvidia-open")
            elif pacman -Si -- "nvidia-open-${k#linux-}" >/dev/null 2>&1; then
                prebuilt+=("nvidia-open-${k#linux-}")
            fi
        done
        if [ ${#prebuilt[@]} -eq ${#kernels[@]} ]; then
            nv_ref+=("${prebuilt[@]}")
            [ "${prebuilt[*]}" = nvidia-open ] || ok "kernels ${kernels[*]}: their own prebuilt modules (${prebuilt[*]})"
        else
            nv_ref+=(nvidia-open-dkms dkms)
            need_headers=1
            ok "kernels ${kernels[*]}: nvidia-open-dkms, built for each of them"
        fi
    fi

    [ "$need_headers" = 1 ] || return 0
    for k in "${kernels[@]}"; do
        if pacman -Si -- "$k-headers" >/dev/null 2>&1 || pkg_present "$k-headers"; then
            nv_ref+=("$k-headers")
        else
            left_out "$k-headers is not in your repos: DKMS cannot build the NVIDIA module for $k, which will boot without it"
        fi
    done
}

# On a machine with more than one card, tells Hyprland which one to render on.
#
# WHY IT IS NEEDED. Aquamarine (Hyprland's backend) opens every DRM device it
# finds and makes the FIRST one the primary renderer. On the tower that can
# easily be the Ryzen's integrated Radeon, even though both monitors hang off
# the RTX 5070 -- and then every frame is drawn on the iGPU and copied across to
# the NVIDIA card. That multi-GPU path is where the flicker, the stutter and the
# black screens live, especially with NVIDIA.
#
# WHAT IT WRITES. AQ_DRM_DEVICES, which is a PRIORITY LIST and not a lock: every
# card stays in it, just with the one that has the screens first. Plug a monitor
# into the other card later and it still lights up, as a secondary. On a machine
# with a single card this function does nothing at all, because there aquamarine
# has no choice to get wrong and setting the variable could only make it worse.
#
# WHERE IT WRITES IT. /etc/environment, read by pam_env on every login, which
# means both the uwsm session and a plain hyprland.desktop one see it. The
# obvious places -- ~/.config/environment.d/ and ~/.config/uwsm/env -- are no
# good here: after the 'config' phase those directories are symlinks INTO THIS
# REPO, so writing a machine-specific path there would be writing it into git.
graphics_pick_render_device() {
    local gpus=("$@")
    [ ${#gpus[@]} -ge 2 ] || return 0

    heading "Which card Hyprland renders on"

    local entry vendor addr devid node ranked
    ranked="$(
        for entry in "${gpus[@]}"; do
            read -r vendor addr devid <<<"$entry"
            node="$(gpu_drm_node "$addr")"
            [ -n "$node" ] || continue
            printf '%s\t%s\n' "$(gpu_connected_outputs "$addr")" "$node"
        done | sort -k1,1nr -k2,2
    )"

    local top second
    top="$(printf '%s\n' "$ranked" | sed -n 1p | cut -f1)"
    second="$(printf '%s\n' "$ranked" | sed -n 2p | cut -f1)"

    # No monitors reported anywhere, or the same number on two cards: there is
    # no honest way to pick, so nothing gets written. Guessing here is how you
    # turn a working desktop into a black one.
    if [ -z "$top" ] || [ "$top" = 0 ] || [ "$top" = "$second" ]; then
        warn "${#gpus[@]} graphics cards, and no clear one to render on"
        printf '       %sHyprland will pick the first it finds, which may be the wrong one. If the%s\n' "$C_DIM" "$C_OFF"
        printf '       %sdesktop flickers or will not start, pick it by hand in /etc/environment:%s\n' "$C_DIM" "$C_OFF"
        printf '       %s  AQ_DRM_DEVICES=/dev/dri/by-path/pci-<address>-card%s\n' "$C_DIM" "$C_OFF"
        printf '       %sThe addresses are the ones printed just above.%s\n' "$C_DIM" "$C_OFF"
        return 0
    fi

    local devices; devices="$(printf '%s\n' "$ranked" | cut -f2 | paste -sd:)"
    local begin='# dotfiles-graphics-begin' end='# dotfiles-graphics-end'

    if grep -qxF "AQ_DRM_DEVICES=$devices" /etc/environment 2>/dev/null; then
        skip "AQ_DRM_DEVICES is already pointing at the right card"
        return 0
    fi
    if [ "$DRY" = 1 ]; then
        skip "would write AQ_DRM_DEVICES=$devices into /etc/environment"
        return 0
    fi

    # The markers make this idempotent AND undoable: delete the three lines
    # between them and you are back to Hyprland choosing for itself.
    sudo sed -i "/^$begin\$/,/^$end\$/d" /etc/environment
    {
        printf '%s\n' "$begin"
        printf '# Which card Hyprland renders on. First one wins; the rest stay available.\n'
        printf '# Written by dotfiles/install.sh (graphics phase). Delete this block to undo.\n'
        printf 'AQ_DRM_DEVICES=%s\n' "$devices"
        printf '%s\n' "$end"
    } | sudo tee -a /etc/environment >/dev/null

    ok "AQ_DRM_DEVICES -> $devices"
    printf '       %s(%s monitors on that card. Takes effect on your next login.)%s\n' "$C_DIM" "$top" "$C_OFF"
}

# ----------------------------------------------------------------- phase: services

# Why a unit from services.txt should NOT be enabled on this machine, printed;
# nothing (and status 1) when it should. Each of these is a choice the
# machine already made, and enabling ours next to it does not replace that
# choice, it fights it.
service_skip_reason() {
    local unit="$1" dm
    case "$unit" in
        NetworkManager.service|NetworkManager-dispatcher.service)
            # iwd on its own (Omarchy, archinstall's iwd option) or
            # systemd-networkd already runs the network; NetworkManager next
            # to them means two daemons fighting over the same Wi-Fi card,
            # and after the reboot there is no network at all.
            systemctl is-enabled --quiet NetworkManager.service 2>/dev/null && return 1
            if systemctl is-enabled --quiet systemd-networkd.service 2>/dev/null; then
                printf 'systemd-networkd already manages the network'; return 0
            fi
            if systemctl is-enabled --quiet iwd.service 2>/dev/null; then
                printf 'iwd already manages the Wi-Fi on its own'; return 0
            fi
            ;;
        nftables.service)
            if dm="$(other_firewall)"; then printf '%s is already the firewall' "$dm"; return 0; fi
            ;;
        tlp.service)
            if dm="$(other_power_daemon)"; then printf '%s already manages power' "$dm"; return 0; fi
            ;;
        reflector.timer)
            if dm="$(mirrors_managed_elsewhere)"; then printf 'the mirrors are managed by %s' "$dm"; return 0; fi
            ;;
        sddm.service)
            # One display manager per machine: systemd keeps it as the
            # display-manager.service alias, and `enable sddm` fails while
            # another one holds it.
            dm="$(readlink /etc/systemd/system/display-manager.service 2>/dev/null)"
            dm="${dm##*/}"
            if [ -n "$dm" ] && [ "$dm" != sddm.service ]; then
                printf '%s is your login screen. To use this one: sudo systemctl disable %s && sudo systemctl enable sddm' "${dm%.service}" "$dm"
                return 0
            fi
            ;;
        nvme-vmd-runtime-pm.path)
            # The NVMe/VMD guard of the repo's own laptop. Two of its three
            # rules name the Intel VMD domain (10000:...), which only exists
            # on machines with VMD on; the third is an ordinary PCI address
            # that another board may well have.
            compgen -G '/sys/bus/pci/devices/10000:*' >/dev/null || { printf 'this machine has no Intel VMD'; return 0; }
            ;;
    esac
    return 1
}

phase_services() {
    heading "Services"

    local manifest="$REPO/packages/services.txt"
    [ -f "$manifest" ] || { warn "no services.txt, skipping"; return 0; }

    local scope unit why msg
    while read -r scope unit _; do
        [[ "$scope" =~ ^(#|$) ]] && continue
        [ -z "${unit:-}" ] && continue

        case "$scope" in
            system|sistema)
                if ! [ -n "$(systemctl list-unit-files --no-legend "$unit" 2>/dev/null)" ]; then
                    skip "system: $unit (unit does not exist; is its package missing?)"
                    continue
                fi
                if why="$(service_skip_reason "$unit")"; then
                    left_out "$unit not enabled: $why"
                    continue
                fi
                if [ "$DRY" = 1 ]; then
                    run sudo systemctl enable "$unit"
                elif msg="$(sudo systemctl enable "$unit" 2>&1 >/dev/null)"; then
                    ok "system: $unit"
                else
                    # systemctl's own words: "could not enable" alone sent you
                    # looking for a reason it already had.
                    failed "system: could not enable $unit: $(printf '%s' "$msg" | tail -1)"
                fi
                ;;
            user|usuario)
                if ! systemctl --user list-unit-files --no-legend "$unit" 2>/dev/null | grep -q .; then
                    skip "user: $unit (unit does not exist yet)"
                    continue
                fi
                if [ "$DRY" = 1 ]; then
                    run systemctl --user enable "$unit"
                elif msg="$(systemctl --user enable "$unit" 2>&1 >/dev/null)"; then
                    ok "user: $unit"
                else
                    failed "user: could not enable $unit: $(printf '%s' "$msg" | tail -1)"
                fi
                ;;
            *) warn "odd scope in services.txt: $scope" ;;
        esac
    done < "$manifest"

    # sddm.service hangs off graphical.target, and a freshly installed Arch boots
    # into multi-user.target. Enabling the display manager is therefore NOT
    # enough on its own: it sits there enabled and dead, and the machine comes
    # up on a TTY with no desktop. Caught on a real install, not in the container.
    if systemctl is-enabled sddm.service >/dev/null 2>&1; then
        if [ "$(systemctl get-default 2>/dev/null)" != graphical.target ]; then
            run sudo systemctl set-default graphical.target >/dev/null 2>&1 \
                && ok "boot target set to graphical.target" \
                || failed "could not set the boot target to graphical.target"
        else
            ok "boot target is already graphical.target"
        fi
    fi

    warn "user services do not start until you log in to Hyprland"
}

# ----------------------------------------------------------------- phase: sddm

phase_sddm() {
    heading "Login theme (hyprisland)"

    local installer="$HOME/.config/sddm-hyprisland/install.sh"
    if [ ! -f "$installer" ]; then
        skip "cannot find $installer (run the 'config' phase first)"
        return 0
    fi

    # An already-installed theme still gets its language checked. It used to
    # return right here, which is why './install.sh --lang en' on a machine that
    # already had the rice updated the shell and the lock screen and left the
    # login in Spanish, quietly: the theme installer only ever seeds theme.conf
    # the first time, so nothing else was going to write that key.
    if [ -d /usr/share/sddm/themes/hyprisland ]; then
        skip "the theme is already installed"
        ask_lang
        set_language_sddm
        return 0
    fi

    warn "the login theme is installed with sudo"
    ask "install it?" || { skip "skipped at your request"; return 0; }

    run chmod +x "$installer"
    run sudo "$installer" && ok "hyprisland theme installed" \
        || warn "the theme installer failed; login will stay on the default theme"

    # The theme ships with language=es. If this run asked for English, the key
    # has to be written now that the file exists in /usr.
    ask_lang
    set_language_sddm
}

# ----------------------------------------------------------------- phase: spicetify

# Injects the spicetify theme into Spotify. Without this Spotify comes up with
# its stock look no matter what the repo ships.
#
# WHY IT IS A PHASE OF ITS OWN. The `config` phase already lays down
# ~/.config/spicetify with the termspot theme and the pywal colour scheme, and
# `set-wallpaper.sh` already calls `spicetify refresh` on every wallpaper
# change... but `refresh` only does anything once spicetify has been APPLIED at
# least once, and applying means writing inside /opt/spotify, which needs sudo.
# That one-time step was the missing link: everything else was in place and
# Spotify still looked stock.
phase_spicetify() {
    heading "Spotify (spicetify)"

    command -v spicetify >/dev/null 2>&1 || { skip "no spicetify-cli, skipping"; return 0; }
    command -v spotify   >/dev/null 2>&1 || { skip "no spotify, skipping"; return 0; }

    # spicetify patches Spotify in place, so it needs to be able to write there.
    # Arch ships /opt/spotify owned by root, which is why this needs sudo once.
    #
    # Write access for THIS user, not for everyone. The obvious spelling is
    # `chmod a+wr`, which is what the spicetify docs suggest and what this used
    # to do, and it leaves /opt/spotify world-writable: any other account on the
    # machine, or any service UID that gets that far, could then plant code in a
    # tree that Spotify loads as you. An ACL says the same thing about you
    # without saying it about everybody else.
    if [ -d /opt/spotify ] && [ ! -w /opt/spotify/Apps ]; then
        warn "spicetify has to be able to write in /opt/spotify"
        if ask "give it write access?"; then
            if command -v setfacl >/dev/null 2>&1; then
                # -d sets the default too, so files spicetify creates later
                # inherit it. X: execute only where it already applies.
                # The braces are not decoration: in zsh, "$USER:rwX" swallows
                # the ":r" as a history modifier and hands setfacl "u:diegowX".
                # This script is bash, so it would be fine either way, but the
                # line gets copy-pasted into a shell sooner or later.
                run sudo setfacl -Rm  "u:${USER}:rwX" /opt/spotify
                run sudo setfacl -Rdm "u:${USER}:rwX" /opt/spotify
            else
                # No acl package: fall back to the group, still not everyone.
                run sudo chown -R "root:$(id -gn)" /opt/spotify
                run sudo chmod -R g+w /opt/spotify
            fi
            ok "/opt/spotify is writable by $USER"
        else
            skip "skipped; Spotify will stay on its stock theme"
            return 0
        fi
    fi

    # spicetify refuses to do anything without ~/.config/spotify/prefs, and that
    # file does not exist until Spotify has been launched once — which on a
    # fresh install nobody has done yet. Creating it empty is enough: spicetify
    # only needs the path to resolve, and Spotify fills it in on first run.
    # Without this the phase fails on EVERY new machine with
    # "prefs does not exist or is not a valid path".
    local prefs="$HOME/.config/spotify/prefs"
    if [ ! -f "$prefs" ] && [ "$DRY" = 0 ]; then
        mkdir -p "$(dirname "$prefs")"
        : > "$prefs"
        ok "empty prefs created (Spotify fills it in on first run)"
    fi

    # Seed the colours before applying, so the very first paint is already the
    # pywal ones instead of whatever the theme ships with.
    local gen="$HOME/.config/hypr/scripts/spicetify-colors.py"
    local theme="$HOME/.config/spicetify/Themes/termspot"
    if [ -r "$gen" ] && [ -r "$HOME/.cache/wal/colors.json" ] && [ "$DRY" = 0 ]; then
        mkdir -p "$theme"
        python3 "$gen" "$theme/color.ini" >/dev/null 2>&1 \
            && ok "colours generated from the current pywal palette"
    fi

    run spicetify config current_theme termspot color_scheme pywal >/dev/null 2>&1

    if [ "$DRY" = 1 ]; then
        skip "would apply the theme to Spotify (spicetify backup apply)"
        return 0
    fi

    # `backup apply` is the first-time path and complains if a backup already
    # exists; plain `apply` is the re-run path. Trying them in that order makes
    # the phase safe to repeat.
    if spicetify backup apply >/dev/null 2>&1; then
        ok "theme applied to Spotify (first backup taken)"
    elif spicetify apply >/dev/null 2>&1; then
        ok "theme re-applied to Spotify"
    else
        warn "spicetify could not apply; try it by hand with 'spicetify backup apply'"
    fi
}

# ----------------------------------------------------------------- phase: final

phase_final() {
    heading "Finishing touches"

    # Safety net: normally `config` already did this, but if someone runs only
    # `./install.sh final` it should still add up. It is idempotent: if no
    # /home/diego is left, it says nothing.
    adapt_home_paths

    # fonts
    if [ "$DRY" = 1 ]; then
        skip "would rebuild the font cache (fc-cache -f)"
    elif command -v fc-cache >/dev/null 2>&1; then
        fc-cache -f >/dev/null 2>&1 && ok "font cache rebuilt"
    else
        warn "no fc-cache (fontconfig missing): new fonts will not show up until you log back in"
    fi

    # groups: video and input are needed for brightness and for ydotool
    local g
    for g in video input i2c wheel; do
        if getent group "$g" >/dev/null 2>&1; then
            if id -nG "$USER" | tr ' ' '\n' | grep -qx "$g"; then
                skip "already in the $g group"
            else
                run sudo usermod -aG "$g" "$USER" && ok "added to the $g group"
            fi
        fi
    done

    # zsh as the default shell. The resolved files are compared because on Arch
    # /bin/zsh and /usr/bin/zsh are the same binary, and comparing the raw
    # strings would trigger a pointless chsh on every pass.
    if command -v zsh >/dev/null; then
        local current_shell zsh_shell
        current_shell="$(readlink -f "$(getent passwd "$USER" | cut -d: -f7)" 2>/dev/null)"
        zsh_shell="$(readlink -f "$(command -v zsh)")"
        if [ "$current_shell" = "$zsh_shell" ]; then
            skip "zsh is already your shell"
        else
            # chsh only takes a path listed in /etc/shells, and the one PATH
            # finds first need not be it: with /usr/sbin ahead of /usr/bin, as
            # in Docker's default PATH, it finds /usr/sbin/zsh, the same file on
            # Arch but not on the list (seen 2026-11-01). So the path is taken
            # from the list itself.
            local zsh_path="" s
            if [ -r /etc/shells ]; then
                while IFS= read -r s; do
                    case "$s" in ''|'#'*) continue ;; esac
                    [ "$(readlink -f "$s" 2>/dev/null)" = "$zsh_shell" ] && { zsh_path=$s; break; }
                done < /etc/shells
            fi
            if [ -n "$zsh_path" ]; then
                run sudo chsh -s "$zsh_path" "$USER" && ok "zsh set as the default shell"
            else
                warn "zsh is not listed in /etc/shells, so chsh would refuse it."
                warn "Add it there and run:  chsh -s $(command -v zsh)"
            fi
        fi
    fi

    # first pywal run: without this, half the shell comes up colourless
    local wallpaper
    wallpaper="$(find "$HOME/Pictures/wallpapers" -maxdepth 1 -type f \
                  \( -iname '*.jpg' -o -iname '*.png' -o -iname '*.jpeg' \) 2>/dev/null | sort | head -1)"
    if [ -n "$wallpaper" ] && command -v wal >/dev/null; then
        if [ "$DRY" = 1 ]; then
            skip "would generate the pywal palette from $(basename "$wallpaper")"
            skip "would regenerate the derived themes (btop, cava, yazi, discord, spicetify, Qt, GTK+folder icons)"
        else
            wal -i "$wallpaper" -n -q && ok "pywal palette generated from $(basename "$wallpaper")"

            # `wal` only fills ~/.cache/wal. The derived themes are written by
            # these scripts, which day to day are launched by set-wallpaper.sh;
            # that one cannot be called here because it needs a live compositor
            # for the wallpaper itself. Without this, a fresh install would leave
            # Discord, Spotify, btop, cava and yazi on their stock colours until
            # the first wallpaper change. They only read ~/.cache/wal and write
            # config files: no session needed.
            local regenerated=0 s
            # gtk-pywal.sh goes LAST in the loop on purpose: it generates the
            # `pywal-gtk-<hash>` theme and leaves the settings.ini files pointing
            # at it, which is what makes a freshly installed session open GTK
            # applications already in the palette. It calls folders-pywal.py
            # itself.
            for s in yazi-pywal.sh cava-pywal.sh btop-pywal.sh discord-pywal.sh \
                     spicetify-pywal.sh qt-pywal.py gtk-pywal.sh; do
                if [ -x "$HOME/.config/hypr/scripts/$s" ]; then
                    "$HOME/.config/hypr/scripts/$s" >/dev/null 2>&1 && regenerated=$((regenerated + 1))
                fi
            done
            [ "$regenerated" -gt 0 ] && ok "derived themes regenerated ($regenerated of 7)"
        fi
    else
        warn "could not generate the initial palette (python-pywal missing, or no wallpapers)"
    fi

    # The pokemon sprites. Roughly 270 MB, so they are not in git and they are
    # not in the `pokeshell` package either -that ships seven files and caches
    # into a different directory than the one .zshrc reads-. Without them
    # nothing errors: `pokefetch` just falls through to a bare fastfetch and you
    # never learn why the pokemon never showed up.
    local sprites=0
    [ -d "$HOME/.cache/pokeanim" ] && sprites=$(find "$HOME/.cache/pokeanim" -name '*.gif' 2>/dev/null | wc -l)
    if [ "$sprites" -ge 100 ]; then
        skip "pokemon sprites already there ($sprites animated)"
    elif [ ! -x "$HOME/.local/bin/poke-sprites" ]; then
        warn "poke-sprites is missing; run the 'config' phase first"
    elif [ "$DRY" = 1 ]; then
        skip "would offer to download the pokemon sprites (~270 MB)"
    else
        warn "the pokemon sprites are a ~270 MB download and take a few minutes"
        if ask "download them now?"; then
            "$HOME/.local/bin/poke-sprites" | tail -3 | sed 's/^/       /'
            sprites=$(find "$HOME/.cache/pokeanim" -name '*.gif' 2>/dev/null | wc -l)
            ok "pokemon sprites: $sprites animated in ~/.cache/pokeanim"
        else
            skip "skipped; run 'poke-sprites' whenever you like, it resumes"
        fi
    fi

    # The Game Boy clock face. This one is NOT a download we can offer, and the
    # reason is worth spelling out rather than leaving as a silent gap.
    #
    # The notch clock is drawn in `pokemon-font`, the Game Boy typeface from the
    # Pokemon games. Its upstream project (github.com/PascalPixel/pokemon-font)
    # shipped with no LICENSE file at all, and no licence means all rights
    # reserved -- so the .ttf cannot travel in this repository, and this script
    # will not fetch it for you either. Its successor, Johto Mono, is a paid
    # font whose licence reads "exclusively for personal projects". There is a
    # fork carrying an OFL, but a third party added that to an original that
    # never had one, so it does not hold.
    #
    # Nothing breaks without it: Appearance.qml asks the system whether the
    # family is installed and falls back to the interface font, which switches
    # off the pixel-grid quantisation that only ever existed for this typeface.
    # You get the same clock in your own font.
    if fc-list 2>/dev/null | grep -qi 'pokemon-font'; then
        ok "Game Boy clock font found"
    else
        skip "no Game Boy clock font -- the notch clock uses your interface font"
        printf '       %s\n' \
            "that font is not redistributable, so it is not in this repo." \
            "if you own a copy, drop the .ttf in ~/.local/share/fonts, run" \
            "fc-cache -f, and the clock picks it up on the next reload." \
            "any other pixel face works too -- Silkscreen and Pixelify Sans are" \
            "SIL OFL -- by setting fontClock in ~/.config/quickshell/Appearance.qml."
    fi

    if [ -d "$BACKUP" ]; then
        printf '\n  What was there before is saved in:\n    %s\n' "$BACKUP"
    fi
}

# ----------------------------------------------------------------- phase: digests

# Re-reads the manifest and nothing else. This is the phase to run after copying
# files BY HAND from ~/.config into the repo: it tells the next ./diagnose that
# those two sides are square, so it stops asking about them. Safe to run at any
# time -- it only ever records agreement, so it cannot paper over a difference.
phase_digests() {
    heading "Digest manifest"
    digests_write
}

# ----------------------------------------------------------------- moving the checkout
#
# Shared by update.sh (the pull) and by restore (undoing one). On every machine
# but diego's, install.sh rewrites the /home/diego written inside some of the
# repo's own files (adapt_home_paths), and in --link mode the desktop itself
# rewrites a few tracked files as you use it -- the pywal-generated ones on
# every wallpaper change, quickshell-rice.json whenever a setting moves. None
# of that is "your work", and none of it may stop an update or be thrown away
# by one. These helpers tell it apart from what IS yours.

ADAPTING_HOME=""
adapting_home() {
    if [ -z "$ADAPTING_HOME" ]; then
        if home_paths_need_adapting; then ADAPTING_HOME=1; else ADAPTING_HOME=0; fi
    fi
    [ "$ADAPTING_HOME" = 1 ]
}

# Prints a committed file the way adapt_home_paths leaves it on this machine:
# rewritten when it is a text file it would touch, as committed otherwise.
adapted_blob() {
    local rev="$1" path="$2" blob
    blob="$(mktemp)" || return 1
    if git -C "$REPO" cat-file blob "$rev:$path" > "$blob" 2>/dev/null; then
        case "$path" in
            */Pictures/*|*/share/fonts/*) cat "$blob" ;;
            home/*)
                if adapting_home && grep -Iq /home/diego "$blob"; then
                    sed "$(home_paths_sed)" "$blob"
                else
                    cat "$blob"
                fi
                ;;
            *) cat "$blob" ;;
        esac
    fi
    rm -f "$blob"
}

# The digest file_sha256 would give <rev>:<path> once installed on this
# machine: symlinks by their (repointed) target, files by their adapted text.
blob_sha() {
    local rev="$1" path="$2" entry target
    entry="$(git -C "$REPO" ls-tree "$rev" -- "$path" 2>/dev/null)"
    [ -n "$entry" ] || return 1
    if [ "${entry%% *}" = 120000 ]; then
        target="$(git -C "$REPO" cat-file blob "$rev:$path" 2>/dev/null)"
        if adapting_home && [[ "$target" == /home/diego/* ]]; then
            target="$HOME${target#/home/diego}"
        fi
        printf 'link:%s' "$target" | sha256sum | awk '{print $1}'
    else
        adapted_blob "$rev" "$path" | sha256sum | awk '{print $1}'
    fi
}

# True when an unstaged change to a tracked path is ONLY adapt_home_paths'
# rewrite: same mode, and a working copy that is byte for byte what the rewrite
# makes of the committed file (or a symlink repointed the same way). Only then
# can it be put back on the committed text and regenerated after the pull
# without losing a thing. One more line of yours and it is your work.
is_installer_rewrite() {
    local path="$1" entry mode target
    adapting_home || return 1
    case "$path" in home/*) ;; *) return 1 ;; esac
    entry="$(git -C "$REPO" ls-tree HEAD -- "$path" 2>/dev/null)"
    mode="${entry%% *}"
    case "$mode" in
        120000)
            [ -L "$REPO/$path" ] || return 1
            target="$(git -C "$REPO" cat-file blob "HEAD:$path" 2>/dev/null)" || return 1
            case "$target" in /home/diego/*) ;; *) return 1 ;; esac
            [ "$(readlink -- "$REPO/$path")" = "$HOME${target#/home/diego}" ]
            ;;
        100644|100755)
            [ -f "$REPO/$path" ] && [ ! -L "$REPO/$path" ] || return 1
            if [ "$mode" = 100755 ]; then
                [ -x "$REPO/$path" ] || return 1
            else
                [ ! -x "$REPO/$path" ] || return 1
            fi
            cmp -s -- <(adapted_blob HEAD "$path") "$REPO/$path"
            ;;
        *) return 1 ;;
    esac
}

# True for a tracked file under home/ that the desktop rewrites by itself:
# pywal-generated, or your own live settings (see is_pywal_generated and
# is_user_owned).
is_runtime_repo_path() {
    local path="$1" rel
    case "$path" in home/*) ;; *) return 1 ;; esac
    rel="${path#home/}"
    is_pywal_generated "$rel" || is_user_owned "$rel"
}

# True when the only change to a tracked file is its mode: older installers
# chmod'ed every script they found, straight into the repo in --link mode.
is_mode_only_change() {
    [ -z "$(git -C "$REPO" diff --no-ext-diff HEAD -- "$1" 2>/dev/null \
            | grep -vE '^(diff --git|old mode|new mode)')" ]
}

MOVE_BLOCKED=()      # git_move_head: your edits that collide with the move
CARRY_FAILED=""      # git_move_head: the file it could not set aside
RUNTIME_CARRIED=()   # git_move_head: runtime files carried across it
CARRY_TMP=""

# Puts the carried files back on top and rewrites the paths again. Called on
# the way out of git_move_head whatever happened, Ctrl+C included.
carry_back() {
    local q
    if [ -n "$CARRY_TMP" ]; then
        for q in "${RUNTIME_CARRIED[@]}"; do
            [ -e "$CARRY_TMP/$q" ] || [ -L "$CARRY_TMP/$q" ] || continue
            mkdir -p "$REPO/$(dirname "$q")" && cp -a -- "$CARRY_TMP/$q" "$REPO/$q"
        done
    fi
    adapt_home_paths >/dev/null 2>&1
}

# git_move_head <ff|reset|check> <target>
# Moves the checkout to <target> -- a fast-forward for update.sh, a reset
# --keep for restore -- without losing anything that lives only in the working
# tree:
#   - files the update does not touch: git leaves them alone by itself;
#   - the installer's path rewrites: back to the committed text for the move,
#     and written again after it;
#   - runtime files (pywal's, your live settings): set aside, and YOUR version
#     put back on top afterwards;
#   - a change of mode only: the new content comes in, with your mode on it;
#   - anything else of yours that the update also changes: nothing moves, and
#     the paths are left in MOVE_BLOCKED for the caller to explain.
# Returns 0 when it moved (for check: when it could), 1 when git failed, 2
# when it was blocked, 3 when a file could not be set aside (CARRY_FAILED says
# which) -- and then nothing moved.
git_move_head() {
    local how="$1" target="$2" entry path p rc=0
    local rewrites=() runtime=() rdeleted=() modeonly=() modes=() blocked=() i
    local -A upstream=()
    MOVE_BLOCKED=(); RUNTIME_CARRIED=(); CARRY_TMP=""

    while IFS= read -r p; do
        [ -n "$p" ] && upstream[$p]=1
    done < <(git -C "$REPO" diff --name-only --no-renames HEAD "$target" 2>/dev/null)

    while IFS= read -r -d '' entry; do
        # A rename or copy carries its source path as one more field.
        case "$entry" in R*|C*) IFS= read -r -d '' _ || true ;; esac
        path="${entry:3}"
        [ -n "${upstream[$path]:-}" ] || continue
        if [ "${entry:0:2}" = " M" ] && is_installer_rewrite "$path"; then
            rewrites+=("$path")
        elif is_runtime_repo_path "$path"; then
            # Deleted here: there is nothing to set aside. The update comes
            # in, and the file is deleted again after it -- your state wins.
            if [ ! -e "$REPO/$path" ] && [ ! -L "$REPO/$path" ]; then
                rdeleted+=("$path")
            else
                runtime+=("$path")
            fi
        elif [ ! -e "$REPO/$path" ] && [ ! -L "$REPO/$path" ]; then
            blocked+=("$path (deleted here)")
        elif is_mode_only_change "$path"; then
            modeonly+=("$path")
            modes+=("$(stat -c %a -- "$REPO/$path" 2>/dev/null)")
        else
            blocked+=("$path")
        fi
    done < <(git -C "$REPO" status --porcelain=v1 -z --untracked-files=no 2>/dev/null)

    # An untracked file of yours exactly where the update brings one: git
    # would refuse the merge, so it is said before anything moves.
    while IFS= read -r p; do
        [ -n "$p" ] && [ -n "${upstream[$p]:-}" ] && blocked+=("$p (not in git)")
    done < <(git -C "$REPO" ls-files --others --exclude-standard 2>/dev/null)

    if [ ${#blocked[@]} -gt 0 ]; then
        MOVE_BLOCKED=("${blocked[@]}")
        return 2
    fi
    RUNTIME_CARRIED=("${runtime[@]}")
    [ "$how" = check ] && return 0

    CARRY_FAILED=""
    CARRY_TMP="$(mktemp -d "${TMPDIR:-/tmp}/pocket-carry.XXXXXXXX")" || { CARRY_FAILED="(no temporary directory)"; return 3; }
    EXIT_TMP+=("$CARRY_TMP")
    for p in "${runtime[@]}"; do
        if ! { mkdir -p "$CARRY_TMP/$(dirname "$p")" && cp -a -- "$REPO/$p" "$CARRY_TMP/$p"; }; then
            CARRY_FAILED="$p"
            return 3
        fi
    done

    trap 'carry_back; exit 130' INT TERM HUP
    if [ $(( ${#rewrites[@]} + ${#runtime[@]} + ${#rdeleted[@]} + ${#modeonly[@]} )) -gt 0 ]; then
        git -C "$REPO" --literal-pathspecs checkout --quiet -- \
            "${rewrites[@]}" "${runtime[@]}" "${rdeleted[@]}" "${modeonly[@]}" || rc=$?
    fi
    if [ "$rc" = 0 ]; then
        case "$how" in
            ff)    git -C "$REPO" merge --ff-only --quiet "$target" || rc=$? ;;
            reset) git -C "$REPO" reset --keep --quiet "$target" || rc=$? ;;
        esac
    fi
    carry_back
    for p in "${rdeleted[@]}"; do
        rm -f -- "$REPO/$p"
    done
    for i in "${!modeonly[@]}"; do
        [ -n "${modes[$i]}" ] && [ -e "$REPO/${modeonly[$i]}" ] && chmod "${modes[$i]}" -- "$REPO/${modeonly[$i]}" 2>/dev/null
    done
    trap - INT TERM HUP
    [ "$rc" = 0 ] || return 1
    return 0
}

# ----------------------------------------------------------------- phase: restore

backup_kind() {
    if [ -f "$1/.update-backup" ]; then printf 'update'
    elif [ -f "$1/.rice-copies" ]; then printf 'taken-out'
    elif [ -f "$1/.before-restore" ]; then printf 'pre-restore'
    else printf 'install'
    fi
}

# The bookkeeping files a backup carries next to the files it saved.
is_backup_marker() {
    case "${1##*/}" in
        .update-backup|.added|.digests|.baseline|.installed|.rice-copies|.deployed|.before-restore) return 0 ;;
    esac
    return 1
}

backups_newest_first() {
    find "$HOME/.dotfiles-backup" -mindepth 1 -maxdepth 1 -type d -printf '%T@ %p\n' 2>/dev/null \
        | sort -rn | cut -d' ' -f2-
}

# Every backup, newest first, with its kind: restore shows this before it
# touches anything, so which one it will use is never a guess. "taken-out" is
# what a restore itself moved out of the way: the copies of the repo's files.
list_backups() {
    local d n any=0
    while IFS= read -r d; do
        [ "$any" = 1 ] || printf '  backups in ~/.dotfiles-backup, newest first:\n'
        any=1
        n="$(find "$d" -mindepth 1 \( -type f -o -type l \) 2>/dev/null | while IFS= read -r f; do
                 [ "$(dirname "$f")" = "$d" ] && is_backup_marker "$f" && continue; printf 'x\n'; done | wc -l)"
        printf '    %-36s %-9s %s file(s)\n' "$(basename "$d")" "$(backup_kind "$d")" "$n"
    done < <(backups_newest_first)
    [ "$any" = 1 ] || printf '  there are no backups in ~/.dotfiles-backup\n'
    printf '\n'
}

# Undoes 'config', or the last update. Which backup:
#   - the one you name (`restore <folder>`, or --from);
#   - otherwise the LAST update's, while it is still there to undo -- found
#     through the pointer update.sh leaves, never "the newest folder", which
#     after an update that backed nothing up was an older update or the whole
#     install;
#   - otherwise the FIRST install backup still there: the one holding what
#     you had before the desktop went in. Later runs can leave smaller
#     backups too (a copy replaced by a newer one), and restoring the newest
#     of those put back an older copy of the rice instead of your files.
phase_restore() {
    heading "Restore the previous state"
    list_backups

    local which="" last d
    if [ -n "$RESTORE_FROM" ]; then
        if [ -d "$RESTORE_FROM" ]; then
            which="$(cd "$RESTORE_FROM" && pwd)"
        elif [ -d "$HOME/.dotfiles-backup/$RESTORE_FROM" ]; then
            which="$HOME/.dotfiles-backup/$RESTORE_FROM"
        else
            failed "there is no backup called $RESTORE_FROM"
            return 0
        fi
    else
        last="$(cat "$LAST_UPDATE_PTR" 2>/dev/null)"
        if [ -n "$last" ] && [ -f "$last/.update-backup" ]; then
            which="$last"
        else
            while IFS= read -r d; do
                [ "$(backup_kind "$d")" = install ] && which="$d"
            done < <(backups_newest_first)
        fi
    fi

    if [ -n "$which" ] && [ -f "$which/.update-backup" ]; then
        restore_update_backup "$which"
    else
        restore_install "$which"
    fi
}

# Undoes one update: the files it replaced go back, the ones it added go,
# the digest manifest and the package baseline return to what they were, and
# the repo goes back to the commit it was at -- the part that matters in
# --link mode, where the update WAS the pull.
#
# Three rules keep the undo from destroying anything newer than the update:
#   - the repo is moved back only if it is still exactly where that update
#     left it. A commit of yours on top, a later pull, a later update: going
#     back to the old commit would throw all of that away with it;
#   - whether the repo can move is checked BEFORE any file is touched, so a
#     blocked undo leaves everything as it was, ready to be retried;
#   - a file changed since the update installed it (your edit after the
#     update) is moved into a backup of its own before the old one goes back,
#     never overwritten.
# The marker and the pointer go only when all of it worked; anything less, and
# the same restore can be run again.
restore_update_backup() {
    local which="$1" old_head new_head head replaced=() added=() line src rel dest n=0 pkgs
    local move_repo=0 repo_note="" pre="" cur want before_fail=${#FAILED[@]} later=()
    local -A installed=()
    old_head="$(sed -n 's/^OLD_HEAD=//p' "$which/.update-backup" | head -1)"
    new_head="$(sed -n 's/^NEW_HEAD=//p' "$which/.update-backup" | tail -1)"
    pkgs="$(sed -n 's/^PACKAGES=//p' "$which/.update-backup" | head -1)"
    head="$(git -C "$REPO" rev-parse HEAD 2>/dev/null || true)"
    mapfile -t replaced < <(find "$which" \( -type f -o -type l \) 2>/dev/null | sort | while IFS= read -r src; do
        [ "$(dirname "$src")" = "$which" ] && is_backup_marker "$src" && continue
        printf '%s\n' "$src"; done)
    if [ -f "$which/.added" ]; then
        while IFS= read -r line; do
            [ -n "$line" ] && added+=("$line")
        done < "$which/.added"
    fi
    if [ -f "$which/.installed" ]; then
        while IFS= read -r line; do
            [ ${#line} -gt 66 ] && installed["${line:66}"]="${line:0:64}"
        done < "$which/.installed"
    fi

    if [ -n "$new_head" ] && [ -n "$old_head" ] && [ -n "$head" ] && [ "$new_head" != "$old_head" ]; then
        if [ "$head" = "$new_head" ]; then
            move_repo=1
        elif [ "$head" != "$old_head" ]; then
            repo_note="the repo has moved on since that update (it left it at ${new_head:0:7}, it is at ${head:0:7} now): it stays where it is"
        fi
    fi
    if [ "$move_repo" = 1 ]; then
        git_move_head check "$old_head"
        case $? in
            0) ;;
            2)
                failed "nothing was undone: going back to ${old_head:0:7} would change these files, which have edits of yours: ${MOVE_BLOCKED[*]}"
                warn "  set them aside first:  git -C \"$REPO\" stash push -- <those files>"
                warn "  then run the restore again, and  git -C \"$REPO\" stash pop  after it"
                return 0
                ;;
            *)
                failed "nothing was undone: git cannot compare ${head:0:7} with ${old_head:0:7}"
                return 0
                ;;
        esac
    fi

    printf '  undoing the update backed up in %s\n' "${which/#$HOME/\~}"
    printf '    %d file(s) to put back, %d to remove' "${#replaced[@]}" "${#added[@]}"
    [ "$move_repo" = 1 ] && printf ', and the repo back from %s to %s' "${head:0:7}" "${old_head:0:7}"
    printf '\n'
    [ -n "$repo_note" ] && warn "$repo_note"
    printf '\n'
    warn "this undoes that update and puts the previous files back"
    ask "carry on?" || { skip "cancelled"; return 0; }

    # What is there now, if it is not what the update put there, goes into a
    # backup of its own first.
    keep_later() {
        local d="$1" r="$2" saved_backup="$BACKUP"
        if [ -z "$pre" ]; then
            pre="$HOME/.dotfiles-backup/$(date +%Y%m%d-%H%M%S)-before-restore"
            run mkdir -p "$pre" && run touch "$pre/.before-restore"
        fi
        BACKUP="$pre"; save_aside "$d" >/dev/null; BACKUP="$saved_backup"
        later+=("$r")
    }
    # What the update put at $1 (relative to $HOME): written down at the time,
    # or, for a backup older than that record, the file at the commit it
    # pulled.
    installed_sha() {
        if [ -n "${installed[$1]:-}" ]; then printf '%s' "${installed[$1]}"
        elif [ -n "$new_head" ]; then blob_sha "$new_head" "home/${1%.new}" 2>/dev/null
        fi
    }

    for src in "${replaced[@]}"; do
        rel="${src#"$which"/}"
        dest="$HOME/$rel"
        if [ -e "$dest" ] || [ -L "$dest" ]; then
            cur="$(file_sha256 "$dest" 2>/dev/null || true)"
            want="$(installed_sha "$rel")"
            [ -n "$want" ] && [ "$cur" = "$want" ] || keep_later "$dest" "$rel"
        fi
        run mkdir -p "$(dirname "$dest")" || die "cannot prepare $dest for restore"
        run mv -f -- "$src" "$dest" || die "cannot restore $dest; the backup is still there"
        n=$((n + 1))
    done
    [ ${#replaced[@]} -gt 0 ] && ok "$n replaced file(s) put back"

    n=0
    for rel in "${added[@]}"; do
        dest="$HOME/$rel"
        [ -e "$dest" ] || [ -L "$dest" ] || continue
        cur="$(file_sha256 "$dest" 2>/dev/null || true)"
        want="$(installed_sha "$rel")"
        if [ -n "$want" ] && [ "$cur" = "$want" ]; then
            run rm -f -- "$dest" || die "cannot remove $dest"
        else
            keep_later "$dest" "$rel"
        fi
        n=$((n + 1))
    done
    [ ${#added[@]} -gt 0 ] && ok "$n added file(s) taken away"
    unset -f keep_later installed_sha

    if [ ${#later[@]} -gt 0 ]; then
        warn "${#later[@]} file(s) had changed since that update; your version is kept in ${pre/#$HOME/\~}:"
        for rel in "${later[@]:0:5}"; do warn "  ~/$rel"; done
        [ ${#later[@]} -gt 5 ] && warn "  ...and $(( ${#later[@]} - 5 )) more"
    fi

    if [ -f "$which/.digests" ]; then
        run mkdir -p "$(dirname "$DIGESTS")"
        run mv -f -- "$which/.digests" "$DIGESTS" && ok "digest manifest put back"
    fi
    if [ -f "$which/.baseline" ]; then
        run mv -f -- "$which/.baseline" "$BASELINE" && ok "package baseline put back"
    elif grep -qx 'BASELINE=none' "$which/.update-backup" 2>/dev/null; then
        run rm -f -- "$BASELINE"
    fi

    if [ "$move_repo" = 1 ]; then
        if [ "$DRY" = 1 ]; then
            run git -C "$REPO" reset --keep "$old_head"
        else
            git_move_head reset "$old_head"
            case $? in
                0) ok "repo back at ${old_head:0:7}"
                   [ ${#RUNTIME_CARRIED[@]} -gt 0 ] && ok "your versions of ${#RUNTIME_CARRIED[@]} runtime file(s) kept" ;;
                2) failed "the repo stays at ${head:0:7}: ${MOVE_BLOCKED[*]} changed while this ran" ;;
                3) failed "the repo stays at ${head:0:7}: could not set aside $CARRY_FAILED" ;;
                *) failed "git could not move the repo back; by hand:  git -C \"$REPO\" reset --keep $old_head" ;;
            esac
        fi
    fi
    if [ -n "$pkgs" ]; then
        skip "the packages that update installed stay ($pkgs); remove them with sudo pacman -Rs if you want"
    fi

    if [ ${#FAILED[@]} -gt "$before_fail" ]; then
        warn "the undo is not complete: the backup and its marker stay, and the same restore can be run again"
        return 0
    fi
    while IFS= read -r line; do
        [ -n "$line" ] && run rm -f -- "$STATE_DIR/migrations/$line"
    done < <(sed -n 's/^MIGRATION=//p' "$which/.update-backup")
    run rm -f "$which/.update-backup" "$which/.added" "$which/.installed"
    if [ "$DRY" = 0 ]; then
        find "$which" -depth -type d -empty -delete 2>/dev/null || true
        [ "$(cat "$LAST_UPDATE_PTR" 2>/dev/null)" = "$which" ] && rm -f "$LAST_UPDATE_PTR"
    fi
    ok "update undone. Reload the desktop (or log out and back in) to see the old files"
}

# Puts back a folder a restore took out (see restore_install): the copies,
# file by file and never over something that is there now, and the manifest
# and deployment list that described them -- not as stray dotfiles in $HOME.
restore_taken_out() {
    local which="$1" src rel dest n=0 kept=()
    printf '  putting back the copies taken out into %s\n\n' "${which/#$HOME/\~}"
    ask "carry on?" || { skip "cancelled"; return 0; }
    while IFS= read -r src; do
        rel="${src#"$which"/}"
        dest="$HOME/$rel"
        if [ -e "$dest" ] || [ -L "$dest" ]; then
            kept+=("$rel")
            continue
        fi
        run mkdir -p "$(dirname "$dest")"
        run mv -- "$src" "$dest" && n=$((n + 1))
    done < <(find "$which" \( -type f -o -type l \) 2>/dev/null | sort | while IFS= read -r src; do
                 [ "$(dirname "$src")" = "$which" ] && is_backup_marker "$src" && continue
                 printf '%s\n' "$src"; done)
    ok "$n file(s) put back"
    if [ -f "$which/.digests" ] && [ ! -e "$DIGESTS" ]; then
        run mkdir -p "$(dirname "$DIGESTS")" && run mv -- "$which/.digests" "$DIGESTS" && ok "digest manifest put back"
    fi
    if [ -f "$which/.deployed" ] && [ ! -e "$DEPLOYED_FILE" ]; then
        run mkdir -p "$STATE_DIR" && run mv -- "$which/.deployed" "$DEPLOYED_FILE"
    fi
    if [ ${#kept[@]} -gt 0 ]; then
        warn "${#kept[@]} file(s) not put back, because something is in their place now:"
        for rel in "${kept[@]:0:5}"; do warn "  ~/$rel"; done
    elif [ "$DRY" = 0 ]; then
        run rm -f -- "$which/.rice-copies"
        find "$which" -depth -type d -empty -delete 2>/dev/null
    fi
}

# Undoes 'config': out with the symlinks to the repo, out with the copies that
# are still exactly the repo's, and back with whatever was there before.
restore_install() {
    local which="$1" dest target links=() copies=() edited=() rel f src n=0 kept=() taken=""
    # A folder of copies a restore took out is put back as it is, with its
    # manifest and its list of deployments: nothing is unlinked or taken out
    # to make room for it.
    if [ -n "$which" ] && [ "$(backup_kind "$which")" = taken-out ]; then
        restore_taken_out "$which"
        return 0
    fi
    for dest in "$HOME"/.[!.]* "$HOME"/.config/*; do
        [ -L "$dest" ] || continue
        target="$(readlink -f "$dest" 2>/dev/null)"
        case "$target" in "$REPO"/*) links+=("$dest") ;; esac
    done
    # Copies (--copy mode, and the trees copied in both modes) that nobody
    # touched since: identical to the repo's, so taking them out loses
    # nothing -- and they are moved aside, not deleted.
    repo_ignored_load
    while IFS= read -r f; do
        rel="${f#"$REPO"/home/}"
        [ -n "${IGNORED_IN_REPO[$rel]:-}" ] && continue
        dest="$HOME/$rel"
        { [ -f "$dest" ] || [ -L "$dest" ]; } || continue
        case "$(readlink -f "$(dirname "$dest")" 2>/dev/null)" in "$REPO"/*) continue ;; esac
        if [ "$(file_sha256 "$dest" 2>/dev/null)" = "$(file_sha256 "$f" 2>/dev/null)" ]; then
            copies+=("$rel")
        elif ! is_pywal_generated "$rel" && ! is_user_owned "$rel"; then
            edited+=("$rel")
        fi
    done < <(find "$REPO/home" \( -type f -o -type l \) 2>/dev/null | sort)

    if [ ${#links[@]} -eq 0 ] && [ ${#copies[@]} -eq 0 ] && [ -z "$which" ]; then
        warn "no symlinks to this repo, no copies of it and no backup: there is nothing to undo"
        return 0
    fi

    printf '  symlinks to this repo: %d; copies still identical to it: %d\n' "${#links[@]}" "${#copies[@]}"
    if [ -n "$which" ]; then
        printf '  backup to put back: %s\n\n' "${which/#$HOME/\~}"
    else
        printf '  backup: none (there was nothing of yours to save at install time)\n\n'
    fi
    warn "this REMOVES the symlinks to the repo, moves the untouched copies aside and puts the old files back"
    ask "carry on?" || { skip "cancelled"; return 0; }

    # 1) The symlinks to the repo, and only those: one of yours pointing
    #    somewhere else stays put.
    for dest in "${links[@]}"; do
        run rm -- "$dest" && n=$((n + 1))
    done
    ok "$n symlink(s) to the repo removed"

    # 2) The untouched copies, into a folder of their own: a restore never
    #    deletes a file, it only moves it.
    local saved_backup="$BACKUP"
    taken="$HOME/.dotfiles-backup/$(date +%Y%m%d-%H%M%S)-taken-out"
    if [ ${#copies[@]} -gt 0 ]; then
        BACKUP="$taken"
        run mkdir -p "$taken" && run touch "$taken/.rice-copies"
        for rel in "${copies[@]}"; do
            save_aside "$HOME/$rel" >/dev/null
            # The folders they leave empty go too, never one with anything
            # of yours still in it.
            [ "$DRY" = 0 ] && ( cd "$HOME" && rmdir -p --ignore-fail-on-non-empty "$(dirname "$rel")" 2>/dev/null )
        done
        ok "${#copies[@]} untouched copies moved to ${taken/#$HOME/\~}"
    fi
    # Copies you changed since are yours now, and stay where they are.
    if [ ${#edited[@]} -gt 0 ]; then
        warn "${#edited[@]} copied file(s) stay, because they are not the repo's any more (edited):"
        for rel in "${edited[@]:0:5}"; do warn "  ~/$rel"; done
        [ ${#edited[@]} -gt 5 ] && warn "  ...and $(( ${#edited[@]} - 5 )) more"
    fi
    # The manifest described those copies. Left behind, a later --copy install
    # would read your restored files as "edits" and keep them over the repo's.
    if [ -f "$DIGESTS" ]; then
        BACKUP="$taken"
        run mkdir -p "$taken"
        run mv -f -- "$DIGESTS" "$taken/.digests"
    fi
    [ -f "$DEPLOYED_FILE" ] && { run mkdir -p "$taken"; run mv -f -- "$DEPLOYED_FILE" "$taken/.deployed"; }
    BACKUP="$saved_backup"

    # 3) What was there before, file by file. Something already back in its
    #    place is left alone unless it is still exactly the repo's copy.
    if [ -z "$which" ]; then
        printf '\n  There was no backup to put back: your $HOME is left without those files.\n'
        return 0
    fi
    n=0
    while IFS= read -r src; do
        rel="${src#"$which"/}"
        dest="$HOME/$rel"
        if [ -e "$dest" ] || [ -L "$dest" ]; then
            if [ -e "$REPO/home/$rel" ] && [ "$(file_sha256 "$dest" 2>/dev/null)" = "$(file_sha256 "$REPO/home/$rel" 2>/dev/null)" ]; then
                BACKUP="$taken"; save_aside "$dest" >/dev/null; BACKUP="$saved_backup"
            else
                kept+=("$rel")
                continue
            fi
        fi
        run mkdir -p "$(dirname "$dest")"
        run mv -- "$src" "$dest" && n=$((n + 1))
    done < <(find "$which" \( -type f -o -type l \) 2>/dev/null | sort | while IFS= read -r src; do
                 [ "$(dirname "$src")" = "$which" ] && is_backup_marker "$src" && continue
                 printf '%s\n' "$src"; done)
    [ "$DRY" = 0 ] && find "$which" -depth -type d -empty -delete 2>/dev/null
    ok "$n file(s) put back"
    if [ ${#kept[@]} -gt 0 ]; then
        warn "${#kept[@]} file(s) were not put back, because what is there now is not the repo's"
        warn "copy (an edit of yours since): they stay in ${which/#$HOME/\~}"
        for rel in "${kept[@]:0:5}"; do warn "  ~/$rel"; done
        [ ${#kept[@]} -gt 5 ] && warn "  ...and $(( ${#kept[@]} - 5 )) more"
    fi
    printf '\n  The backup is still in %s just in case.\n  Delete it yourself once you are sure.\n' \
           "${which/#$HOME/\~}"
}

# ----------------------------------------------------------------- go

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    start_run install
    detect_distro

    printf '%s' "$C_TIT"
    cat <<'HEADER'
   pocket -- Hyprland + Quickshell desktop
HEADER
    printf '%s' "$C_OFF"
    printf '  repo:   %s\n  phases: %s\n' "$REPO" "${PHASES[*]}"
    [ -n "$LOG_FILE" ] && printf '  log:    %s\n' "${LOG_FILE/#$HOME/\~}"

    # sudo once, up front, when any phase is going to need it -- so the one
    # password prompt comes now and not twenty minutes into an AUR build.
    if [ "$DRY" = 0 ] && [ "$(id -u)" -ne 0 ]; then
        for phase in "${PHASES[@]}"; do
            case "$phase" in
                aur|packages|system|graphics|services|sddm|spicetify|final) sudo_begin || true; break ;;
            esac
        done
    fi

    for phase in "${PHASES[@]}"; do
        case "$phase" in
            base)     phase_base ;;
            aur)      phase_aur ;;
            packages) phase_packages ;;
            repos)    phase_repos ;;
            config)   phase_config ;;
            system)   phase_system ;;
            graphics) phase_graphics ;;
            services) phase_services ;;
            sddm)     phase_sddm ;;
            spicetify) phase_spicetify ;;
            final)    phase_final ;;
            digests)  phase_digests ;;
            restore)  phase_restore ;;
        esac
    done

    heading "Done"
    print_summary
    printf '\n'
    if [ "$DRY" = 1 ]; then
        printf '  That was a dry run: nothing was touched.\n  Drop --dry-run to do it for real.\n\n'
    elif [ ${#FAILED[@]} -gt 0 ]; then
        printf '  Something above did not work. Fix it and run just that phase again\n'
        printf '  (./install.sh <phase>): every phase is safe to repeat.\n\n'
        exit 1
    elif doing packages || doing graphics || doing system || doing services || doing sddm \
         || [ -n "$REBOOT_REASON" ]; then
        cat <<'FOOTER'
  Next step: reboot and log in through SDDM.

  If something does not come up, look here first:
    systemctl --user status quickshell
    journalctl --user -u quickshell -b --no-pager | tail -40
    hyprctl monitors

  The new groups (video, input) do not take effect until you log out.

FOOTER
    elif doing config || doing final; then
        printf '  Nothing here needs a reboot: log out and back in (or run hyprctl reload)\n'
        printf '  to see the new configuration.\n\n'
    else
        printf '\n'
    fi
fi
