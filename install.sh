#!/usr/bin/env bash
#
# install.sh -- brings the whole desktop up from a fresh Arch install.
#
# All the new machine needs is Arch and git:
#
#     git clone https://github.com/diegoMalagrida/dotfiles
#     cd dotfiles
#     ./install.sh
#
# It can be re-run as many times as you like: it does not redo what is already
# done, and it never overwrites a file of yours without first saving it to
# ~/.dotfiles-backup/<date>/.
#
# It does NOT touch /boot, the bootloader, the partitions or fstab.

set -uo pipefail

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
UI_LANG=             # es | en; empty means "ask, or take the default"
DEFAULT_LANG=        # what is offered when nobody says; see current_lang()
FALLBACK_LANG=es     # what a MISSING key or file means: the strings are written
                     # in Spanish, so that is what every program falls back to
KEYBOARD_KEEP=       # a keyboard.lua that existed before 'config' replaced the dir

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
die()     { err "$*"; exit 1; }

# Runs a command, honouring --dry-run.
run() {
    if [ "$DRY" = 1 ]; then
        printf '  %s[dry]%s %s\n' "$C_DIM" "$C_OFF" "$*"
        return 0
    fi
    "$@"
}

ask() {
    [ "$ASSUME_YES" = 1 ] && return 0
    [ "$DRY" = 1 ] && return 0
    local answer
    read -r -p "  $1 [y/N] " answer
    [[ "$answer" =~ ^[sSyY]$ ]]
}

# The language question. It is not a yes/no, so it cannot go through ask(), but
# it plays by the same rules: --lang settles it, -y and --dry-run do not ask,
# and what nobody chooses comes from the machine, in this order:
#
#   1. what the desktop speaks right now. Without this, re-running the
#      installer without --lang silently undid a language picked in Settings:
#      the default was hard-wired to 'es' and set_language_quickshell dutifully
#      wrote it back.
#   2. on a fresh machine, your locale: Spanish for an es_* locale, English for
#      anything else. It used to be Spanish for everybody, which is how people
#      who do not speak it ended up with a desktop they could not read.
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
        case "$l" in es|es_*|es.*|es@*) printf 'es' ;; *) printf 'en' ;; esac
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
        es|en) printf '%s' "$cur" ;;
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
    read -r -p "  language for the desktop, es or en? [$DEFAULT_LANG] " answer
    case "$answer" in
        en|EN) UI_LANG=en ;;
        es|ES) UI_LANG=es ;;
        # A bare Enter = whatever the desktop already spoke. And 'es' typed by hand
        # has to ASSIGN: once the default became what is installed, an empty case
        # here left UI_LANG on 'en' and what you asked for was ignored.
        '') ;;
        *) warn "'$answer' is neither es nor en; keeping $DEFAULT_LANG" ;;
    esac
}

# --lang, validated where it is read. Not a subshell helper on purpose: die()
# inside $(...) only kills the subshell and the run would carry on with nothing
# set.
set_lang() {
    case "$1" in
        es|en) UI_LANG="$1" ;;
        *) die "unknown language: $1  (only 'es' or 'en')" ;;
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
      --lang es|en  what the desktop speaks (default: your locale's, Spanish for
                    es_* and English otherwise; it asks if you do not say, and
                    Settings changes it later anyway)
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
  restore     undoes 'config': removes the symlinks to the repo and puts
              back whatever was there before, from ~/.dotfiles-backup
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

while [ $# -gt 0 ]; do
    case "$1" in
        -n|--dry-run) DRY=1 ;;
        -y|--yes|--si) ASSUME_YES=1 ;;
        --copy|--copiar) MODE=copy ;;
        --link|--enlazar) MODE=link ;;
        --lang|--idioma)
            shift; [ $# -gt 0 ] || die "--lang needs a value: es or en"
            set_lang "$1" ;;
        --lang=*|--idioma=*) set_lang "${1#*=}" ;;
        -h|--help|--ayuda) usage; exit 0 ;;
        -*) die "unknown option: $1  (try --help)" ;;
        *)  REQUESTED_PHASES+=("$(canonical_phase "$1")") ;;
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

doing() { [[ " ${PHASES[*]} " == *" $1 "* ]]; }

# ----------------------------------------------------------------- helpers

# Saves whatever is at the destination path before replacing it. Symlinks that
# already point where they should are left alone, which is what makes this
# script genuinely idempotent.
save_aside() {
    local dest="$1"
    [ -e "$dest" ] || [ -L "$dest" ] || return 0
    local rel="${dest#"$HOME"/}"
    local saved="$BACKUP/$rel"
    run mkdir -p "$(dirname "$saved")"
    run mv "$dest" "$saved"
    printf '       %s(saved to %s)%s\n' "$C_DIM" "${saved/#$HOME/\~}" "$C_OFF"
}

# Copies a whole tree. Uses rsync when present, and falls back to cp, which is
# always there because it ships in coreutils. This matters because rsync is NOT
# part of a fresh Arch install: it arrives in the 'packages' phase. If someone
# runs just `./install.sh config` on a virgin machine, without this it would
# stop halfway.
#   $3 = "no-clobber" to leave anything already at the destination alone
copy_tree() {
    local src="$1" dest="$2" mode="${3:-}"
    run mkdir -p "$dest"
    if command -v rsync >/dev/null 2>&1; then
        if [ "$mode" = no-clobber ]; then
            run rsync -a --ignore-existing "$src/" "$dest/"
        else
            run rsync -a "$src/" "$dest/"
        fi
    else
        if [ "$mode" = no-clobber ]; then
            run cp -a -n "$src/." "$dest/"
        else
            run cp -a "$src/." "$dest/"
        fi
    fi
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
# the same thing the symlink repointing already did: `git diff` shows it.
adapt_home_paths() {
    [ "$HOME" = /home/diego ] && return 0

    # A GUARD, and not a paranoid one: this REWRITES THE REPO, so it may only
    # run when $HOME really is the installing user's home. A test harness that runs
    # the config phase with HOME pointing at a temporary directory, without this
    # check the first pass left the whole repo pointing at a /tmp/tmp.XXXX that
    # vanished when the test finished: 20 files and 3 symlinks broken, silently
    # and without anything failing. It actually happened.
    local passwd_home
    passwd_home="$(getent passwd "${USER:-$(id -un)}" 2>/dev/null | cut -d: -f6)"
    if [ -z "$passwd_home" ] || [ "$HOME" != "$passwd_home" ]; then
        skip "not adapting paths: HOME ($HOME) is not $USER's home"
        return 0
    fi

    local n_files=0 n_links=0 f link target

    # 1) contents. Text files only, and never the wallpapers or the .git.
    while IFS= read -r f; do
        grep -Iq "/home/diego" "$f" 2>/dev/null || continue
        run sed -i "s#/home/diego#$HOME#g" "$f"
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
        warn "that leaves changes in the repo: 'git diff' will show them"
    fi
}

# Puts src -> dest, symlinking or copying depending on $MODE.
place() {
    local src="$1" dest="$2" label="$3"

    if [ "$MODE" = link ]; then
        if [ -L "$dest" ] && [ "$(readlink -f "$dest")" = "$(readlink -f "$src")" ]; then
            skip "$label (already linked)"
            return 0
        fi
        save_aside "$dest"
        run mkdir -p "$(dirname "$dest")"
        run ln -s "$src" "$dest"
        ok "$label -> symlink"
    else
        save_aside "$dest"
        run mkdir -p "$(dirname "$dest")"
        run cp -a "$src" "$dest"
        ok "$label -> copy"
    fi
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
        [ -f "$HOME/$rel" ] || continue
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
    st="$(localectl status 2>/dev/null)"
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
    elif sudo -n true 2>/dev/null; then
        ok "passwordless sudo"
    else
        warn "sudo will ask you for your password along the way"
    fi

    if [ "$USER" != diego ]; then
        warn "your user is '$USER', not 'diego'. Some files have /home/diego written inside them;"
        warn "the 'system' phase rewrites them for you, but do check the output."
    fi

    printf '\n  config install mode: %s%s%s\n' "$C_TIT" "$MODE" "$C_OFF"
    [ "$DRY" = 1 ] && printf '  %sDRY RUN: nothing will be modified%s\n' "$C_WARN" "$C_OFF"
    return 0
}

# ----------------------------------------------------------------- phase: aur

phase_aur() {
    heading "AUR helper (yay)"

    if command -v yay >/dev/null; then
        skip "yay is already installed"
        return 0
    fi

    ok "yay is missing: it has to be built (the AUR's chicken-and-egg problem)"
    # -Syu, not -S. A stale database makes pacman ask the mirror for package
    # versions it no longer carries, and every download 404s -- on a machine
    # that has been off for a couple of weeks this is the first thing that
    # breaks, and the error says nothing about the database. The big install
    # below already syncs; this one has to as well, since it runs first.
    run sudo pacman -Syu --needed --noconfirm base-devel git || die "could not install base-devel"

    # mktemp, not /tmp/...-$$. The PID is predictable, and on a shared /tmp that
    # lets another user get there first with a directory or a symlink of their
    # own, right where a build is about to run. Cheap to get right.
    local tmp
    if [ "$DRY" = 1 ]; then
        tmp='$(mktemp -d)'
    else
        tmp="$(mktemp -d "${TMPDIR:-/tmp}/yay-bootstrap.XXXXXXXX")" \
            || die "could not create a temporary directory"
        trap "rm -rf -- '$tmp'" EXIT
    fi
    run git clone --depth 1 https://aur.archlinux.org/yay-bin.git "$tmp" || die "could not clone yay-bin"
    if [ "$DRY" = 0 ]; then
        ( cd "$tmp" && makepkg -si --noconfirm ) || die "building yay failed"
        rm -rf -- "$tmp"
        trap - EXIT
    fi
    ok "yay installed"
}

# ----------------------------------------------------------------- phase: packages

phase_packages() {
    heading "Packages"

    local native=() aur=()
    mapfile -t native < <(cat "$REPO/packages/pacman.txt" "$REPO/packages/extra.txt" 2>/dev/null \
                          | grep -vE '^\s*(#|$)' | tr -d ' \t' | sort -u)
    mapfile -t aur    < <(cat "$REPO/packages/aur.txt" 2>/dev/null \
                          | grep -vE '^\s*(#|$)' | tr -d ' \t' | grep -v '^yay$' | sort -u)

    printf '  %d packages from the official repos, %d from the AUR\n' "${#native[@]}" "${#aur[@]}"

    # --disable-download-timeout: pacman gives up on a mirror that drops below a
    # trickle for ten seconds, and on a slow or shared connection -a phone
    # hotspot, a hotel- that aborts the WHOLE transaction: nothing installs.
    # Seen for real on 2026-08-19 in the clean-Arch container, on a link doing
    # ~300 kB/s: "Operation too slow. Less than 1 bytes/sec", and 655 packages
    # went nowhere. Waiting is the right trade here; you are installing a
    # desktop, not timing a benchmark.
    if [ ${#native[@]} -gt 0 ]; then
        run sudo pacman -Syu --needed --noconfirm --disable-download-timeout -- "${native[@]}" \
            && ok "official repos up to date" \
            || packages_failed "${native[@]}"
    fi

    if [ ${#aur[@]} -gt 0 ]; then
        command -v yay >/dev/null || { warn "no yay: skipping the AUR"; return 0; }
        run yay -S --needed --noconfirm --disable-download-timeout -- "${aur[@]}" \
            && ok "AUR up to date" \
            || warn "yay errored on some AUR package. The rest did install."
    fi
}

# Not every pacman failure means the same thing, and the difference decides
# whether it is worth carrying on.
#
#   - ONE package was renamed or dropped from the repos. Everything else did
#     install, the desktop will come up, and stopping would be theatre.
#   - THE TRANSACTION never committed (a mirror timed out, the disk filled up).
#     Then NOTHING installed, and every phase after this one -config, services,
#     sddm, final- will run against a machine with no Hyprland, no Quickshell
#     and no pywal. They do not fail loudly: they lay symlinks, enable units and
#     skip the palette, and what you get at the end is a broken desktop and a
#     warning lost twenty screens up. That happened in the container on
#     2026-08-19 and is why this function exists.
#
# So: ask the machine, do not guess. If the handful of packages the desktop
# cannot exist without are on disk, this was the first case.
packages_failed() {
    [ "$DRY" = 1 ] && return 0
    local missing=()
    local p
    for p in hyprland quickshell kitty zsh python-pywal awww; do
        pacman -Qq "$p" >/dev/null 2>&1 || missing+=("$p")
    done

    if [ ${#missing[@]} -eq 0 ]; then
        warn "pacman returned an error, but the desktop's own packages are installed."
        warn "Look above for which package does not exist (they get renamed sometimes) and carry on."
        return 0
    fi

    err "pacman failed and the desktop is NOT installed (missing: ${missing[*]})."
    err "Nothing after this phase would work, so it stops here rather than leave you"
    err "with a half-built system. The usual cause is the download, not the list:"
    err "  sudo pacman -Syyu                 refresh the databases"
    err "  sudo reflector --latest 20 --sort rate --save /etc/pacman.d/mirrorlist"
    err "and then just re-run this phase:  ./install.sh packages"
    exit 1
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
    #     repo's .gitconfig includes this file instead; git ignores the include
    #     when it is missing, so the only cost of leaving it half-filled is that
    #     git asks you who you are on your first commit, like on any new machine.
    if [ ! -e "$HOME/.gitconfig.local" ] && [ "$DRY" = 0 ]; then
        cat > "$HOME/.gitconfig.local" <<'EOF'
# Your git identity. Not in the dotfiles repo, and it should not be.
[user]
	name = Your Name
	email = you@example.com

# How you store credentials is your call. `store` keeps them in
# ~/.git-credentials in PLAIN TEXT; `cache` holds them in memory for a while,
# and libsecret hands them to your keyring.
# [credential]
#	helper = cache --timeout=3600
EOF
        ok ".gitconfig.local created — put your name and email in it"
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

    # 3) ~/.local/bin: always copied, so they are genuinely executable
    run mkdir -p "$HOME/.local/bin"
    for f in "$root"/.local/bin/*; do
        [ -e "$f" ] || continue
        local base; base="$(basename "$f")"
        run cp -a "$f" "$HOME/.local/bin/$base"
        run chmod +x "$HOME/.local/bin/$base"
        ok ".local/bin/$base"
    done

    # 4) fonts and icons: copied
    if [ -d "$root/.local/share/fonts" ]; then
        copy_tree "$root/.local/share/fonts" "$HOME/.local/share/fonts"
        ok "user fonts"
    fi
    if [ -d "$root/.local/share/icons" ]; then
        copy_tree "$root/.local/share/icons" "$HOME/.local/share/icons"
        ok "user icons"
    fi
    # 4a) GTK themes of our own, if there ever are any. There are none in git
    #     on purpose: the GTK theme this desktop uses is GENERATED, one per
    #     palette (`pywal-gtk-<hash>`, see gtk-pywal.sh), because GTK caches
    #     themes by name and that hash is the only way an already-open window
    #     ever repaints. Committing one would be committing a snapshot of a
    #     wallpaper. What IS in git is the part you edit: gtk-3.0/rice-gtk3.css.
    if [ -d "$root/.local/share/themes" ]; then
        copy_tree "$root/.local/share/themes" "$HOME/.local/share/themes"
        ok "user GTK themes"
    fi

    # 4b) .desktop files of our own. They are here to WIN over the ones in
    #     /usr/share/applications -~/.local/share takes precedence in XDG- so
    #     that, for instance, opening a video launches the vlc wrapper in
    #     ~/.local/bin, the one that carries the pywal palette, and not
    #     /usr/bin/vlc straight up. Without this the wrapper gets copied but
    #     nothing ever calls it.
    if [ -d "$root/.local/share/applications" ]; then
        copy_tree "$root/.local/share/applications" "$HOME/.local/share/applications"
        run update-desktop-database "$HOME/.local/share/applications" 2>/dev/null || true
        ok "desktop entries"
    fi

    # 5) wallpapers: copied without clobbering. If you already have some there,
    #    they are left alone.
    if [ -d "$root/Pictures/wallpapers" ]; then
        copy_tree "$root/Pictures/wallpapers" "$HOME/Pictures/wallpapers" no-clobber
        ok "wallpapers ($(find "$root/Pictures/wallpapers" -type f | wc -l) images)"
    fi

    # 6) the rice scripts have to be runnable
    if [ "$DRY" = 0 ]; then
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
    #    WHERE the seed goes depends on the mode, and it is not a detail:
    #
    #      link -> $HOME/.config/hypr IS this directory, so seeding into the
    #              repo shows up in $HOME. That is the case this was written
    #              for, and it still works.
    #      copy -> they are two different places, and seeding into the repo is
    #              wrong twice over. It never reaches $HOME (step 2 copied
    #              already), and it leaves a STATE file sitting inside the repo
    #              that the next install would copy over the good one.
    #
    #    Both halves were measured on 2026-09-26 with a throwaway $HOME. A
    #    clean install in copy mode left $HOME with NO hypridle.conf at all --
    #    hypridle with no configuration, so no lock, no screen blanking and no
    #    suspend. And re-running `config` on this laptop would have overwritten
    #    the fixed hypridle.conf with an August copy still sitting in the repo,
    #    bringing back the black screen on lid open.
    local seed_root="$root"
    [ "$MODE" != link ] && seed_root="$HOME"

    local hypridle="$seed_root/.config/hypr/hypridle.conf"
    if [ ! -f "$hypridle" ] && [ -f "$root/.config/hypr/hypridle.d/normal.conf" ]; then
        run mkdir -p "$(dirname "$hypridle")"
        run cp -- "$root/.config/hypr/hypridle.d/normal.conf" "$hypridle" \
            && ok "hypridle.conf seeded from the normal profile"
    fi
    local pokestate="$seed_root/.config/poke-theme/state"
    if [ ! -f "$pokestate" ]; then
        run mkdir -p "$(dirname "$pokestate")"
        run sh -c "printf 'on\n' > '$pokestate'" && ok "poke-theme state seeded"
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

    # 10) last, the one check that is not about dotfiles at all: hyprlock.conf
    #     has just landed naming its own PAM service. If that service is not on
    #     the machine, the way you find out is by locking your screen, so it is
    #     said out loud here instead.
    check_lock_pam
}

# ----------------------------------------------------------------- phase: system

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
    if [ "$DRY" = 0 ] && ! sudo -v; then
        warn "sudo cannot ask for your password here (is there a terminal?):"
        warn "nothing was copied. Run it from a terminal:  ./install.sh system"
        return 0
    fi

    local src dest rel
    while IFS= read -r src; do
        rel="${src#"$root"/}"
        dest="/etc/$rel"

        # Comparing only reads, so it is done for real in dry-run too: otherwise
        # dry mode would call everything "identical" and show you nothing.
        # Almost all of /etc is readable without root; sudo is only reached for
        # when it is not, so a password is asked for only when truly needed.
        # cmp comes from diffutils, which is NOT in a minimal Arch. If it is
        # missing, the comparison is skipped and the file is always copied:
        # noisier, but correct.
        if [ -e "$dest" ] && command -v cmp >/dev/null 2>&1; then
            if [ -r "$dest" ]; then
                cmp -s "$src" "$dest" && { skip "/etc/$rel (identical)"; continue; }
            elif sudo -n cmp -s "$src" "$dest" 2>/dev/null; then
                skip "/etc/$rel (identical)"; continue
            fi
        fi

        if [ -e "$dest" ]; then
            run sudo cp -a "$dest" "$dest.before-dotfiles"
            printf '       %s(the previous one is kept as %s.before-dotfiles)%s\n' "$C_DIM" "$dest" "$C_OFF"
        fi

        run sudo mkdir -p "$(dirname "$dest")"
        if ! run sudo cp "$src" "$dest"; then
            warn "could not write /etc/$rel"
            continue
        fi

        # Nothing under system/etc/ spells out /home/diego today -- the unit
        # that did was retired -- but a file dropped into /etc is the one place
        # where that would be invisible until it broke, so the net stays up.
        if [ "$USER" != diego ] && [ "$DRY" = 0 ] && grep -q '/home/diego' "$dest" 2>/dev/null; then
            sudo sed -i "s#/home/diego#$HOME#g" "$dest"
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
        sudo sed -i '/^#\[multilib\]/,/^#Include = .*mirrorlist/ s/^#//' /etc/pacman.conf
        grep -qE '^\[multilib\]' /etc/pacman.conf && ok "multilib enabled" \
            || warn "could not enable multilib; do it by hand in /etc/pacman.conf"
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

    # Microcode is not a GPU matter, but it is the same bug: intel-ucode sat in
    # pacman.txt with no condition on it, so an AMD machine got a package that
    # does nothing and missed the one it needs.
    case "$(grep -m1 '^vendor_id' /proc/cpuinfo 2>/dev/null)" in
        *GenuineIntel*) vendor_set="$vendor_set intel-cpu " ;;
        *AuthenticAMD*) vendor_set="$vendor_set amd-cpu "   ;;
    esac

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
        warn "[multilib] is off, so the 32-bit drivers are being left out: ${deferred[*]}"
        printf '       %sRun the "system" phase (it enables multilib) and then: ./install.sh graphics%s\n' "$C_DIM" "$C_OFF"
    fi

    # nvidia-open is compiled against the exact `linux` kernel that is in the
    # repos. On linux-lts, -zen or anything else it will not load at all, and
    # the only thing that works there is the DKMS variant, which needs that
    # kernel's headers to build against.
    if [[ "$vendor_set" == *" nvidia "* ]]; then
        local kernels=() k i
        mapfile -t kernels < <(pacman -Qq 2>/dev/null \
                               | grep -xE 'linux|linux-lts|linux-zen|linux-hardened|linux-rt|linux-rt-lts')
        if [ ${#kernels[@]} -eq 1 ] && [ "${kernels[0]}" = linux ]; then
            : # the plain prebuilt module is right
        elif [ ${#kernels[@]} -eq 0 ]; then
            warn "cannot tell which kernel is installed; leaving nvidia-open as it is"
        else
            for i in "${!pkgs[@]}"; do
                [ "${pkgs[$i]}" = nvidia-open ] && pkgs[$i]=nvidia-open-dkms
            done
            pkgs+=(dkms)
            for k in "${kernels[@]}"; do pkgs+=("$k-headers"); done
            ok "kernels ${kernels[*]}: using nvidia-open-dkms plus headers"
        fi
    fi

    if [ ${#pkgs[@]} -eq 0 ]; then
        warn "nothing to install for this hardware (that is odd; check packages/gpu.txt)"
        return 0
    fi

    printf '  %d packages for this hardware: %s\n' "${#pkgs[@]}" "${pkgs[*]}"
    # -Syu for the same reason as base-devel above: a 404 here ends in a black
    # screen, which is the worst place to discover a stale database.
    if run sudo pacman -Syu --needed --noconfirm --disable-download-timeout -- "${pkgs[@]}"; then
        ok "video drivers in place"
    else
        err "pacman could not install the video drivers."
        err "This is the one thing that ends in a BLACK SCREEN with nothing in any log,"
        err "so do not ignore it. Usually it is the download and not the list:"
        err "  sudo pacman -Syyu   &&   ./install.sh graphics"
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
            printf '       %sthe bootloader. Do it yourself, adding it to GRUB_CMDLINE_LINUX_DEFAULT:%s\n' "$C_DIM" "$C_OFF"
            printf '       %s  sudoedit /etc/default/grub          # ...quiet nvidia_drm.modeset=1"%s\n' "$C_DIM" "$C_OFF"
            printf '       %s  sudo grub-mkconfig -o /boot/grub/grub.cfg%s\n' "$C_DIM" "$C_OFF"
        fi
    fi

    graphics_pick_render_device "${gpus[@]+"${gpus[@]}"}"
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

phase_services() {
    heading "Services"

    local manifest="$REPO/packages/services.txt"
    [ -f "$manifest" ] || { warn "no services.txt, skipping"; return 0; }

    local scope unit
    while read -r scope unit _; do
        [[ "$scope" =~ ^(#|$) ]] && continue
        [ -z "${unit:-}" ] && continue

        case "$scope" in
            system|sistema)
                if systemctl list-unit-files "$unit" >/dev/null 2>&1 && \
                   [ -n "$(systemctl list-unit-files --no-legend "$unit" 2>/dev/null)" ]; then
                    run sudo systemctl enable "$unit" >/dev/null 2>&1 \
                        && ok "system: $unit" \
                        || warn "system: could not enable $unit"
                else
                    skip "system: $unit (unit does not exist; is its package missing?)"
                fi
                ;;
            user|usuario)
                if systemctl --user list-unit-files --no-legend "$unit" 2>/dev/null | grep -q .; then
                    run systemctl --user enable "$unit" >/dev/null 2>&1 \
                        && ok "user: $unit" \
                        || warn "user: could not enable $unit"
                else
                    skip "user: $unit (unit does not exist yet)"
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
                || warn "could not set the boot target to graphical.target"
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
            run sudo chsh -s "$(command -v zsh)" "$USER" && ok "zsh set as the default shell"
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

# ----------------------------------------------------------------- phase: restore

# Undoes what 'config' did: removes the symlinks to the repo and puts back what
# was there before. This is the whole point of ~/.dotfiles-backup: without it,
# backups are a graveyard nobody knows how to use.
phase_restore() {
    heading "Restore the previous state"

    local backup_root="$HOME/.dotfiles-backup"
    local which=""
    [ -d "$backup_root" ] && # The MOST RECENT by modification time, not the last alphabetically.
    # With `sort | tail -1` any folder starting with a letter -the ones left by
    # manual deployments, like `i18n-...` or `pre-deploy-...`- sorted after the
    # dated `2026...` ones and hid the right one. Restoring is the safety net:
    # it cannot depend on what the folder happens to be called.
    which="$(find "$backup_root" -maxdepth 1 -mindepth 1 -type d -printf '%T@ %p\n' \
        | sort -rn | head -1 | cut -d' ' -f2-)"

    # How many symlinks to the repo exist right now, to know if there is
    # anything to do at all.
    local pending=0 dest target
    for dest in "$HOME"/.[!.]* "$HOME"/.config/*; do
        [ -L "$dest" ] || continue
        target="$(readlink -f "$dest" 2>/dev/null)"
        case "$target" in "$REPO"/*) pending=$((pending+1)) ;; esac
    done

    if [ "$pending" -eq 0 ] && [ -z "$which" ]; then
        warn "no symlinks to this repo and no backup either: there is nothing to undo"
        return 0
    fi

    printf '  symlinks to this repo in place: %s\n' "$pending"
    if [ -n "$which" ]; then
        printf '  most recent backup: %s (%s items)\n' \
               "${which/#$HOME/\~}" "$(find "$which" -mindepth 1 -maxdepth 2 | wc -l)"
    else
        printf '  backup: none (there was nothing of yours to save at install time)\n'
    fi
    printf '\n'

    warn "this REMOVES the symlinks to the repo and puts the old files back"
    ask "carry on?" || { skip "cancelled"; return 0; }

    # 1) Out with the symlinks pointing at the repo. Only those: a symlink of
    #    yours pointing somewhere else stays put. This happens ALWAYS, backup or
    #    not: if you installed on a clean machine there was nothing to save, but
    #    the symlinks are there all the same and you have to be able to pull them.
    local removed=0
    for dest in "$HOME"/.[!.]* "$HOME"/.config/*; do
        [ -L "$dest" ] || continue
        target="$(readlink -f "$dest" 2>/dev/null)"
        case "$target" in
            "$REPO"/*) run rm "$dest"; removed=$((removed+1)) ;;
        esac
    done
    ok "$removed symlinks to the repo removed"

    # 2) And if there is a backup, its contents go back.
    if [ -z "$which" ]; then
        printf '\n  There was no backup to put back: your $HOME is left without those files.\n'
        return 0
    fi

    local restored=0 src rel
    while IFS= read -r src; do
        rel="${src#"$which"/}"
        dest="$HOME/$rel"
        if [ -e "$dest" ]; then
            warn "$HOME/$rel already exists, leaving it alone"
            continue
        fi
        run mkdir -p "$(dirname "$dest")"
        run mv "$src" "$dest"
        restored=$((restored+1))
    done < <(find "$which" -mindepth 1 -maxdepth 1; find "$which/.config" -mindepth 1 -maxdepth 1 2>/dev/null)

    ok "$restored items put back"
    printf '\n  The backup is still in %s just in case.\n  Delete it yourself once you are sure.\n' \
           "${which/#$HOME/\~}"
}

# ----------------------------------------------------------------- go

printf '%s' "$C_TIT"
cat <<'HEADER'
   diego's dotfiles -- Hyprland + Quickshell desktop
HEADER
printf '%s' "$C_OFF"
printf '  repo:   %s\n  phases: %s\n' "$REPO" "${PHASES[*]}"

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
if [ "$DRY" = 1 ]; then
    printf '  That was a dry run: nothing was touched.\n  Drop --dry-run to do it for real.\n\n'
else
    cat <<'FOOTER'
  Next step: reboot and log in through SDDM.

  If something does not come up, look here first:
    systemctl --user status quickshell
    journalctl --user -u quickshell -b --no-pager | tail -40
    hyprctl monitors

  The new groups (video, input) do not take effect until you log out.

FOOTER
fi
