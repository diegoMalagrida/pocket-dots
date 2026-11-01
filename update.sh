#!/usr/bin/env bash
#
# update.sh -- updates an existing pocket desktop in place.
#
# Adapted in part from 43PR/dotfiles (update.sh / update2.sh):
#   MIT License
#   Copyright (c) 2026 43PR
#   Permission is hereby granted, free of charge, to any person obtaining a copy
#   of this software and associated documentation files (the "Software"), to deal
#   in the Software without restriction, including without limitation the rights
#   to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
#   copies of the Software, and to permit persons to whom the Software is
#   furnished to do so, subject to the following conditions:
#   The above copyright notice and this permission notice shall be included in
#   all copies or substantial portions of the Software.
#   THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
#   IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
#   FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
#   AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
#   LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
#   OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
#   SOFTWARE.
#
# What it does, in order:
#   1. pulls the latest commits as a fast-forward. What the desktop rewrites by
#      itself (pywal's files, quickshell-rice.json) and install.sh's /home/diego
#      rewrites are carried across the pull, and YOUR version stays on top. It
#      only stops when the new commits change a file you edited by hand, and
#      then it says which, and how to take the update without losing the edit.
#      If the pull changed this script, it carries on with the new one.
#   2. installs only the packages ADDED to packages/*.txt since last time (the
#      baseline in ~/.local/state/pocket-dots), after bringing the system up to
#      date; a package you removed yourself is never put back
#   3. brings into $HOME only the copied files that changed, three ways
#      (see sync_one in install.sh): untouched ones are updated, edited ones
#      kept with the new version next to them as .new, files you deleted stay
#      deleted, and files the repo dropped go if you never edited them
#   4. leaves pywal-generated files and your own settings (quickshell-rice.json,
#      keyboard.lua, monitors, wallpapers...) untouched, and runs each settings
#      migration once (markers in ~/.local/state/pocket-dots/migrations)
#   5. reloads Hyprland, and Quickshell if it was running
#
# Everything it replaces is saved in ~/.dotfiles-backup/<date>-update.*, with
# the commit it started from, and `./update.sh restore` undoes the last update,
# repo included. `./update.sh -n` shows the whole plan -- the new commits too --
# and changes nothing. Each real run is logged to
# ~/.local/state/pocket-dots/update.log.

set -uo pipefail

REPO="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

# Reuse the presentation helpers, backup primitives, package machinery, the
# three-way sync, the git helpers and restore from install.sh instead of
# duplicating them.
# shellcheck source=install.sh
. "$REPO/install.sh"

RUN_ARGS=("$@")
BACKUP="$HOME/.dotfiles-backup/$(date +%Y%m%d-%H%M%S)-update"
BACKUP_INITIALISED=0
PREV_LAST_UPDATE=""

DO_PULL=1
DO_PACKAGES=1
DO_RELOAD=1
OLD_HEAD="${POCKET_OLD_HEAD:-}"
NEW_HEAD=""
UPDATE_ACTIONS=()
PLAN_REV=""            # dry run: the commit the pull would bring, planned against
INSTALLED_NEW=()       # packages this update installed, written into its backup
CHANGED_SOMETHING=0    # decides the closing message, and whether the backup stays
DROPPED_REMOVED=0
QS_WAS_RUNNING=0
MIGRATIONS_DIR="$STATE_DIR/migrations"
NOTED_FILE="$STATE_DIR/packages.noted"

usage_update() {
    cat <<'USAGE'
Usage: update.sh [options] [step...]

Options:
  -n, --dry-run      show the whole update plan without touching anything
                     (it fetches, so the plan includes the new commits)
  -y, --yes          never ask (for unattended runs)
      --no-pull      skip the pull and sync the current checkout
      --no-packages  skip checking and installing new packages
      --no-reload    do not reload Hyprland or Quickshell at the end
  -h, --help         this help text

Steps (if you name none, all of them run in this order):
  pull        fast-forward to the remote (your edits and the desktop's own
              rewrites are kept; it stops only if the update changes a file
              you edited, and says how to go on)
  packages    installs the packages added to packages/*.txt since last time
  config      3-way sync of home/ into $HOME using the digest manifest
  migrations  one-time settings migrations, and state files older installs lack
  reload      reloads Hyprland, and Quickshell if it was running

Separate actions, only if you name them:
  restore [backup]
              undoes the last update: files, digest manifest, package
              baseline and the repo's commit. Name a backup to undo that one
  digests     refreshes the digest manifest after manual edits

Examples:
  ./update.sh                 pull, install new packages, sync configs, reload
  ./update.sh -n              see what would change without touching anything
  ./update.sh --no-packages   update configs and reload without calling pacman
  ./update.sh restore         undo the last update
USAGE
}

canonical_update_step() {
    case "$1" in
        paquetes)    printf 'packages'   ;;
        migraciones) printf 'migrations' ;;
        recargar)    printf 'reload'     ;;
        restaurar)   printf 'restore'    ;;
        *)           printf '%s' "$1"    ;;
    esac
}

while [ $# -gt 0 ]; do
    case "$1" in
        -n|--dry-run) DRY=1 ;;
        -y|--yes|--si) ASSUME_YES=1 ;;
        --no-pull) DO_PULL=0 ;;
        --no-packages|--sin-paquetes) DO_PACKAGES=0 ;;
        --no-reload|--sin-recargar) DO_RELOAD=0 ;;
        --from)
            shift; [ $# -gt 0 ] || die "--from needs a backup folder"
            RESTORE_FROM="$1" ;;
        -h|--help|--ayuda) usage_update; exit 0 ;;
        -*) die "unknown option: $1  (try --help)" ;;
        *)
            if [[ " ${UPDATE_ACTIONS[*]:-} " == *" restore "* ]] \
               && { [ -d "$1" ] || [ -d "$HOME/.dotfiles-backup/$1" ]; }; then
                RESTORE_FROM="$1"
            else
                UPDATE_ACTIONS+=("$(canonical_update_step "$1")")
            fi ;;
    esac
    shift
done

ALL_UPDATE_STEPS=(pull packages config migrations reload)
ON_DEMAND_UPDATE_STEPS=(restore digests)

if [ ${#UPDATE_ACTIONS[@]} -eq 0 ]; then
    UPDATE_STEPS=()
    [ "$DO_PULL" = 1 ]     && UPDATE_STEPS+=(pull)
    [ "$DO_PACKAGES" = 1 ] && UPDATE_STEPS+=(packages)
    UPDATE_STEPS+=(config migrations)
    [ "$DO_RELOAD" = 1 ]   && UPDATE_STEPS+=(reload)
else
    for s in "${UPDATE_ACTIONS[@]}"; do
        [[ " ${ALL_UPDATE_STEPS[*]} ${ON_DEMAND_UPDATE_STEPS[*]} " == *" $s "* ]] \
            || die "unknown step: $s  (try --help)"
    done
    UPDATE_STEPS=("${UPDATE_ACTIONS[@]}")
fi

# Relaunched by the previous version of this script after its own pull: the
# pull is done, and so is the backup it started.
if [ "${POCKET_RELAUNCHED:-0}" = 1 ]; then
    steps=()
    for s in "${UPDATE_STEPS[@]}"; do [ "$s" = pull ] || steps+=("$s"); done
    UPDATE_STEPS=("${steps[@]}")
    if [ -n "${POCKET_BACKUP:-}" ] && [ -f "$POCKET_BACKUP/.update-backup" ]; then
        BACKUP="$POCKET_BACKUP"
        BACKUP_INITIALISED=1
        PREV_LAST_UPDATE="${POCKET_PREV_LAST_UPDATE:-}"
    fi
    NEW_HEAD="$(git -C "$REPO" rev-parse HEAD 2>/dev/null || true)"
fi

update_doing() { [[ " ${UPDATE_STEPS[*]:-} " == *" $1 "* ]]; }

# ----------------------------------------------------------------- backup book-keeping

# The backup of this update, created at the start of every real run, with the
# commit the repo was at: without it, "undo the last update" in --link mode --
# where the update IS the pull -- had nothing to go back to. A run that
# changes nothing removes it again at the end (finish_update_backup), so
# ~/.dotfiles-backup does not fill up with empty folders.
#
# The pointer in $LAST_UPDATE_PTR is how restore finds THIS backup, and not
# whichever folder happens to be newest.
update_backup_init() {
    [ "$BACKUP_INITIALISED" = 1 ] && return 0
    [ "$DRY" = 1 ] && return 0
    mkdir -p "$HOME/.dotfiles-backup" || die "cannot prepare the backup directory"
    BACKUP="$(mktemp -d "${BACKUP}.XXXXXXXX")" || die "cannot create an update backup"
    {
        printf 'OLD_HEAD=%s\n' "$(git -C "$REPO" rev-parse HEAD 2>/dev/null)"
        printf 'STARTED=%s\n' "$(date '+%F %T')"
        [ -f "$BASELINE" ] || printf 'BASELINE=none\n'
    } > "$BACKUP/.update-backup" || die "cannot initialise the update backup"
    if [ -f "$DIGESTS" ]; then
        cp -a "$DIGESTS" "$BACKUP/.digests" || die "cannot back up the digest manifest"
    fi
    if [ -f "$BASELINE" ]; then
        cp -a "$BASELINE" "$BACKUP/.baseline" || die "cannot back up the package baseline"
    fi
    mkdir -p "$STATE_DIR" || die "cannot create $STATE_DIR"
    PREV_LAST_UPDATE="$(cat "$LAST_UPDATE_PTR" 2>/dev/null)"
    printf '%s\n' "$BACKUP" > "$LAST_UPDATE_PTR.tmp.$$" && mv -f "$LAST_UPDATE_PTR.tmp.$$" "$LAST_UPDATE_PTR"
    BACKUP_INITIALISED=1
}

# One more KEY=value line in the backup's marker.
record_backup_kv() {
    [ "$BACKUP_INITIALISED" = 1 ] && [ "$DRY" = 0 ] || return 0
    printf '%s=%s\n' "$1" "$2" >> "$BACKUP/.update-backup"
}

# Records a path (relative to $HOME) that did not exist before this update so
# `restore` knows to remove it when undoing the run.
record_added() {
    local rel="$1"
    update_backup_init
    [ "$DRY" = 1 ] && return 0
    printf '%s\n' "$rel" >> "$BACKUP/.added" || die "cannot record added path: $rel"
    CHANGED_SOMETHING=1
}

# The digest of what this update put at a path (relative to $HOME), so that
# restore can tell it from an edit made after the update -- which it then
# keeps instead of overwriting.
record_installed() {
    [ "$BACKUP_INITIALISED" = 1 ] && [ "$DRY" = 0 ] || return 0
    local sum
    sum="$(file_sha256 "$2" 2>/dev/null)" || return 0
    printf '%s  %s\n' "$sum" "$1" >> "$BACKUP/.installed"
}

# At the end: a backup of a run that changed nothing is taken away again, and
# the pointer goes back to the update before it.
BACKUP_FINISHED=0
finish_update_backup() {
    [ "$BACKUP_FINISHED" = 0 ] || return 0
    BACKUP_FINISHED=1
    [ "$BACKUP_INITIALISED" = 1 ] && [ "$DRY" = 0 ] || return 0
    local head; head="$(git -C "$REPO" rev-parse HEAD 2>/dev/null || true)"
    local files
    files="$(find "$BACKUP" \( -type f -o -type l \) ! -name .update-backup ! -name .digests \
                 ! -name .baseline 2>/dev/null | head -1)"
    if [ "$CHANGED_SOMETHING" = 0 ] && [ -z "$files" ] && [ "$head" = "$(sed -n 's/^OLD_HEAD=//p' "$BACKUP/.update-backup" | head -1)" ]; then
        rm -rf -- "$BACKUP"
        if [ -n "$PREV_LAST_UPDATE" ]; then
            printf '%s\n' "$PREV_LAST_UPDATE" > "$LAST_UPDATE_PTR"
        else
            rm -f "$LAST_UPDATE_PTR"
        fi
        BACKUP_INITIALISED=0
        return 0
    fi
    record_backup_kv FINISHED "$(date '+%F %T')"
    [ ${#INSTALLED_NEW[@]} -gt 0 ] && record_backup_kv PACKAGES "${INSTALLED_NEW[*]}"
    return 0
}

# Also on the way out of a run that died (see on_exit in install.sh).
on_exit_hook() { finish_update_backup; }

# The base for the three-way sync when the manifest has no line for a file:
# the file as it was committed at the commit this update started from, as
# installed on this machine.
update_old_base() {
    local rel="$1"
    [ -n "$OLD_HEAD" ] && [ -n "$NEW_HEAD" ] && [ "$OLD_HEAD" != "$NEW_HEAD" ] || return 0
    git -C "$REPO" cat-file -e "$OLD_HEAD:home/$rel" 2>/dev/null || return 0
    blob_sha "$OLD_HEAD" "home/$rel"
}

fix_file_mode() {
    local rel="$1" target="$2"
    [ "$DRY" = 1 ] && return 0
    [ -L "$target" ] && return 0
    case "$rel" in
        .local/bin/*|*.sh)
            chmod +x "$target" 2>/dev/null || true
            ;;
    esac
}

# ----------------------------------------------------------------- step: pull

update_pull() {
    heading "Repository (git pull --ff-only)"

    command -v git >/dev/null 2>&1 || die "git is missing. Install it with: sudo pacman -S git"
    [ -d "$REPO/.git" ] || die "$REPO is not a git repository"

    OLD_HEAD="$(git -C "$REPO" rev-parse HEAD 2>/dev/null || true)"
    NEW_HEAD="$OLD_HEAD"

    local upstream target n
    upstream="$(git -C "$REPO" rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null || true)"
    if [ -z "$upstream" ]; then
        if git -C "$REPO" remote get-url origin >/dev/null 2>&1; then
            die "this branch has no upstream to fast-forward to: git -C \"$REPO\" branch --set-upstream-to=origin/main"
        fi
        skip "no git remote configured; keeping current HEAD (${OLD_HEAD:0:7})"
        return 0
    fi

    # Fetching only updates what .git knows about the remote: no file you use
    # changes. That is why even the dry run fetches -- a plan that cannot see
    # the new commits is not a plan.
    git -C "$REPO" fetch --quiet || die "git fetch failed — check the network or the remote before updating"
    target="$(git -C "$REPO" rev-parse --verify --quiet '@{u}')" \
        || die "cannot read the upstream of this branch ($upstream)"

    if git -C "$REPO" merge-base --is-ancestor "$target" HEAD; then
        ok "already at the latest commit (${OLD_HEAD:0:7})"
        return 0
    fi
    if ! git -C "$REPO" merge-base --is-ancestor HEAD "$target"; then
        err "this checkout has commits of its own that the remote does not have, so the"
        err "update cannot simply move forward. To replay yours on top of it:"
        err "  git -C \"$REPO\" pull --rebase"
        err "and then ./update.sh again (or ./update.sh --no-pull to deploy what you have)."
        die "nothing was pulled: the branch and its upstream have diverged"
    fi
    n="$(git -C "$REPO" rev-list --count "HEAD..$target")"

    if [ "$DRY" = 1 ]; then
        update_preview "$target" "$n"
        return 0
    fi

    git_move_head ff "$target"
    case $? in
        0) ;;
        2)
            err "the update changes these files, and they have edits of yours:"
            printf '    %s\n' "${MOVE_BLOCKED[@]}" >&2
            err "Your edits are where they were. To take the update and keep them:"
            err "  git -C \"$REPO\" stash push -- <the files above>"
            err "  ./update.sh"
            err "  git -C \"$REPO\" stash pop     (git says so if a line of yours collides with"
            err "                                 the update: then fix that file before reloading)"
            err "A file marked 'not in git' sits where the update brings one: move it away."
            err "Or deploy what you have, as it is:  ./update.sh --no-pull"
            die "nothing was pulled: ${#MOVE_BLOCKED[@]} file(s) of yours are in the way"
            ;;
        3)
            die "could not set aside $CARRY_FAILED before the pull; nothing was pulled"
            ;;
        *)
            die "git could not fast-forward (its message is above); nothing was pulled"
            ;;
    esac

    NEW_HEAD="$(git -C "$REPO" rev-parse HEAD 2>/dev/null || true)"
    CHANGED_SOMETHING=1
    record_backup_kv NEW_HEAD "$NEW_HEAD"
    ok "updated ${OLD_HEAD:0:7} -> ${NEW_HEAD:0:7} ($n commit(s))"
    git -C "$REPO" log --oneline --no-decorate "$OLD_HEAD..$NEW_HEAD" 2>/dev/null \
        | head -10 | sed 's/^/         /'
    if [ ${#RUNTIME_CARRIED[@]} -gt 0 ]; then
        ok "kept your version of what the desktop rewrites as you use it: ${RUNTIME_CARRIED[*]#home/}"
    fi

    relaunch_if_updater_changed
}

# The dry run's view of the pull: the commits it brings, whether anything of
# yours would stop it, and what each changed file under home/ would do HERE,
# through the same decision the real run makes (sync_decide). Read straight
# out of git: nothing on disk moves.
update_preview() {
    local target="$1" n="$2" st path rel dest real rsum hsum base repo_real
    printf '  %s[dry]%s git pull --ff-only: %s new commit(s)\n' "$C_DIM" "$C_OFF" "$n"
    git -C "$REPO" log --oneline --no-decorate "HEAD..$target" 2>/dev/null \
        | head -10 | sed 's/^/         /'
    if ! git_move_head check "$target"; then
        warn "the pull would stop: the update changes these files, and they have edits of yours:"
        printf '    %s\n' "${MOVE_BLOCKED[@]}"
    elif [ ${#RUNTIME_CARRIED[@]} -gt 0 ]; then
        skip "your version of ${#RUNTIME_CARRIED[@]} file(s) the desktop rewrites would be kept across it"
    fi
    if ! git -C "$REPO" diff --quiet HEAD "$target" -- update.sh install.sh; then
        skip "the update changes the updater itself: the real run carries on with the new one"
    fi

    # From here on, the rest of the dry run reads the lists from that commit.
    PLAN_REV="$target"
    digests_load
    repo_real="$(readlink -f -- "$REPO" 2>/dev/null || printf '%s' "$REPO")"
    while IFS=$'\t' read -r st path; do
        rel="${path#home/}"
        dest="$HOME/$rel"
        if [ -e "$dest" ] || [ -L "$dest" ]; then
            real="$(readlink -f -- "$dest" 2>/dev/null || true)"
        else
            real="$(readlink -f -- "$(dirname "$dest")" 2>/dev/null || true)/x"
        fi
        case "$real" in
            "$repo_real"/*)
                if [[ " ${RUNTIME_CARRIED[*]:-} " == *" $path "* ]]; then
                    printf '  %s[dry]%s %s: keeps your version (the desktop rewrites it)\n' "$C_DIM" "$C_OFF" "$rel"
                else
                    printf '  %s[dry]%s %s: arrives with the pull (linked)\n' "$C_DIM" "$C_OFF" "$rel"
                fi
                continue ;;
        esac
        if [ "$st" = D ]; then
            [ -f "$dest" ] || [ -L "$dest" ] || continue
            hsum="$(file_sha256 "$dest" || true)"
            base="${AGREED[$rel]:-}"; [ -n "$base" ] || base="$(blob_sha HEAD "$path" || true)"
            if [ "$hsum" = "$base" ]; then
                printf '  %s[dry]%s %s: would be removed (the repo dropped it; you never edited it)\n' "$C_DIM" "$C_OFF" "$rel"
            else
                printf '  %s[dry]%s %s: the repo dropped it; yours stays (you edited it)\n' "$C_DIM" "$C_OFF" "$rel"
            fi
            continue
        fi
        if { is_pywal_generated "$rel" || is_user_owned "$rel"; } && { [ -e "$dest" ] || [ -L "$dest" ]; }; then
            printf '  %s[dry]%s %s: left alone (the desktop or you own it)\n' "$C_DIM" "$C_OFF" "$rel"
            continue
        fi
        if [ ! -e "$dest" ] && [ ! -L "$dest" ]; then
            if [ -n "${AGREED[$rel]:-}" ]; then
                printf '  %s[dry]%s %s: stays deleted (you deleted it)\n' "$C_DIM" "$C_OFF" "$rel"
            else
                printf '  %s[dry]%s %s: would be added\n' "$C_DIM" "$C_OFF" "$rel"
            fi
            continue
        fi
        rsum="$(blob_sha "$target" "$path" || true)"
        hsum="$(file_sha256 "$dest" || true)"
        base="${AGREED[$rel]:-}"; [ -n "$base" ] || base="$(blob_sha HEAD "$path" || true)"
        case "$(sync_decide "$rsum" "$hsum" "$base")" in
            same)   ;;
            update) printf '  %s[dry]%s %s: would be updated\n' "$C_DIM" "$C_OFF" "$rel" ;;
            keep)   printf '  %s[dry]%s %s: keeps your edits\n' "$C_DIM" "$C_OFF" "$rel" ;;
            *)      printf '  %s[dry]%s %s: keeps yours; the new one would go next to it as .new\n' "$C_DIM" "$C_OFF" "$rel" ;;
        esac
    done < <(git -C "$REPO" diff --name-status --no-renames HEAD "$target" -- home/ 2>/dev/null)
}

# When the pull changed this script (or install.sh, which it sources), the
# rest of the run has to be the NEW code: the old one in memory would sync
# with yesterday's rules. The backup, the starting commit and the arguments
# carry over; the lock and the log are handed back first.
relaunch_if_updater_changed() {
    [ "${POCKET_RELAUNCHED:-0}" = 1 ] && return 0
    git -C "$REPO" diff --quiet "$OLD_HEAD" "$NEW_HEAD" -- update.sh install.sh 2>/dev/null && return 0
    [ -f "$REPO/update.sh" ] || return 0
    ok "this pull changed the updater itself: carrying on with the new version"
    cleanup_run
    release_run_lock
    log_stop
    trap - EXIT
    exec env POCKET_RELAUNCHED=1 POCKET_OLD_HEAD="$OLD_HEAD" POCKET_BACKUP="$BACKUP" \
        POCKET_PREV_LAST_UPDATE="$PREV_LAST_UPDATE" \
        bash "$REPO/update.sh" --no-pull "${RUN_ARGS[@]}"
}

# ----------------------------------------------------------------- step: packages

# Entries of the list that nothing on this machine satisfies (an entry with
# alternatives counts as satisfied by any of them). One pacman -T for all the
# plain names: one per name took seconds on a list this long.
entries_absent() {
    local e a alts=() singles=()
    local -A missing=()
    for e in "$@"; do
        [[ "$e" == *'|'* ]] || singles+=("$e")
    done
    if [ ${#singles[@]} -gt 0 ]; then
        while IFS= read -r a; do
            [ -n "$a" ] && missing[$a]=1
        done < <(pacman -T -- "${singles[@]}" 2>/dev/null)
    fi
    for e in "$@"; do
        if [[ "$e" != *'|'* ]]; then
            [ -n "${missing[$e]:-}" ] && printf '%s\n' "$e"
            continue
        fi
        IFS='|' read -r -a alts <<<"$e"
        for a in "${alts[@]}"; do
            [ -n "$a" ] && pkg_present "$a" && continue 2
        done
        printf '%s\n' "$e"
    done
}

# Only what was ADDED to the lists since the last run that installed them.
# The baseline (see baseline_write) is what tells "new in the list" from "you
# removed it": comparing the list with what is installed, as this used to,
# reinstalled every package you had taken out, on every update. With no
# baseline yet -- an install older than it -- the list at the commit this
# update started from stands in for it, and failing that the list as it is.
update_packages() {
    heading "Packages (new in the list only)"

    command -v pacman >/dev/null 2>&1 || die "this is for Arch: I cannot find pacman."

    local now_native=() now_aur=() base=() new_native=() new_aur=() absent=() unnoted=() e
    local -A in_base=() noted=()
    mapfile -t now_native < <(read_native_packages)
    mapfile -t now_aur < <(read_aur_packages)

    if [ -s "$BASELINE" ]; then
        mapfile -t base < "$BASELINE"
    elif [ -n "$OLD_HEAD" ] && [ -n "$NEW_HEAD" ] && [ "$OLD_HEAD" != "$NEW_HEAD" ]; then
        mapfile -t base < <(PLAN_REV="$OLD_HEAD" read_native_packages; PLAN_REV="$OLD_HEAD" read_aur_packages)
    elif [ -n "$PLAN_REV" ]; then
        mapfile -t base < <(PLAN_REV="" read_native_packages; PLAN_REV="" read_aur_packages)
    else
        base=("${now_native[@]}" "${now_aur[@]}")
    fi
    for e in "${base[@]}"; do [ -n "$e" ] && in_base[$e]=1; done
    for e in "${now_native[@]}"; do [ -n "${in_base[$e]:-}" ] || new_native+=("$e"); done
    for e in "${now_aur[@]}"; do [ -n "${in_base[$e]:-}" ] || new_aur+=("$e"); done

    # What the list has and this machine does not, but that is not new: you
    # removed it, or a conflict kept it out at install time. Never put back;
    # said once per package, not on every run.
    if [ -f "$NOTED_FILE" ]; then
        while IFS= read -r e; do [ -n "$e" ] && noted[$e]=1; done < "$NOTED_FILE"
    fi
    local listed_before=()
    for e in "${now_native[@]}" "${now_aur[@]}"; do
        [ -n "${in_base[$e]:-}" ] && listed_before+=("$e")
    done
    mapfile -t absent < <(entries_absent "${listed_before[@]}")
    for e in "${absent[@]}"; do [ -n "${noted[$e]:-}" ] || unnoted+=("$e"); done
    if [ ${#unnoted[@]} -gt 0 ]; then
        skip "not installed here, and not put back (said once): ${unnoted[*]}"
        skip "  if you want them: ./install.sh packages"
        if [ "$DRY" = 0 ]; then
            mkdir -p "$STATE_DIR" && printf '%s\n' "${unnoted[@]}" >> "$NOTED_FILE"
        fi
    fi

    if [ $(( ${#new_native[@]} + ${#new_aur[@]} )) -eq 0 ]; then
        ok "no package was added to the lists since last time"
        baseline_write "${now_native[@]}" "${now_aur[@]}"
        phase_repos
        return 0
    fi
    ok "added to the lists since last time: ${new_native[*]} ${new_aur[*]}"

    local want_native=("${new_native[@]}") want_aur=("${new_aur[@]}") missing=()
    pick_alternatives want_native
    pick_alternatives want_aur
    drop_power_conflicts want_native
    mapfile -t missing < <(entries_absent "${want_native[@]}" "${want_aur[@]}")
    if [ ${#missing[@]} -eq 0 ]; then
        skip "they are all on this machine already"
        baseline_write "${now_native[@]}" "${now_aur[@]}"
        phase_repos
        return 0
    fi

    # Installing a package against a system that is not up to date is a
    # partial upgrade, and against old databases every download 404s. So the
    # system comes up to date first -- which is a bigger thing than "two new
    # packages", and is asked.
    warn "installing them means bringing the whole system up to date first (pacman -Syu)"
    if ! ask "upgrade the system and install ${missing[*]}?"; then
        left_out "new packages not installed, at your request: ${missing[*]} (./update.sh packages later)"
        # Not written into the baseline: the next update offers them again.
        local keep=()
        for e in "${now_native[@]}" "${now_aur[@]}"; do [ -n "${in_base[$e]:-}" ] && keep+=("$e"); done
        baseline_write "${keep[@]}"
        phase_repos
        return 0
    fi
    update_backup_init
    check_free_space || { left_out "new packages skipped: not enough disk space"; return 0; }


    if install_native "new packages" want_native; then
        if [ ${#want_aur[@]} -gt 0 ] && ! aur_helper >/dev/null; then
            phase_aur || true
        fi
        install_aur want_aur
    else
        left_out "new packages: not installed, because the system upgrade failed first"
        return 0
    fi
    for e in "${missing[@]}"; do
        pkg_present "${e%%|*}" && INSTALLED_NEW+=("${e%%|*}")
    done
    [ ${#INSTALLED_NEW[@]} -gt 0 ] && CHANGED_SOMETHING=1
    baseline_write "${now_native[@]}" "${now_aur[@]}"
    phase_repos
}

# ----------------------------------------------------------------- step: config

# The top-level entry of $HOME a repo file belongs to -- the unit install.sh
# links or copies whole: .config/<name>, or a dotfile at the root. Empty for
# the trees that are always copied file by file (.local, Pictures).
top_entry() {
    local t
    case "$1" in
        .local/*|Pictures/*) ;;
        .config/*) t="${1#.config/}"; printf '.config/%s' "${t%%/*}" ;;
        */*) printf '%s' "${1%%/*}" ;;
        *) printf '%s' "$1" ;;
    esac
}

# Whether this $HOME was installed in --link mode: a top-level entry links
# into the repo, and there is no list of --copy deployments.
link_install_here() {
    local l repo_real
    [ -f "$DEPLOYED_FILE" ] && return 1
    repo_real="$(readlink -f -- "$REPO" 2>/dev/null || printf '%s' "$REPO")"
    for l in "$HOME"/.[!.]* "$HOME"/.config/*; do
        [ -L "$l" ] || continue
        case "$(readlink -f -- "$l" 2>/dev/null)" in "$repo_real"/*) return 0 ;; esac
    done
    return 1
}

update_config() {
    heading "Configuration (changed files only)"

    local root="$REPO/home"
    [ -d "$root" ] || die "cannot find $root"

    adapt_home_paths

    [ -z "$OLD_HEAD" ] && OLD_HEAD="$(git -C "$REPO" rev-parse HEAD 2>/dev/null || true)"
    [ -z "$NEW_HEAD" ] && NEW_HEAD="$(git -C "$REPO" rev-parse HEAD 2>/dev/null || true)"

    digests_load
    repo_ignored_load

    local repo_real
    repo_real="$(readlink -f -- "$REPO" 2>/dev/null || printf '%s' "$REPO")"

    local linked_count=0 apps_changed=0 thunar_changed=0
    local src rel dest real parent_real top has_install=0 link_mode=0 removed_tops=0
    local -A top_state=()
    deployed_load
    link_install_here && link_mode=1
    { [ -f "$DIGESTS" ] || [ -f "$DEPLOYED_FILE" ] || [ "$link_mode" = 1 ]; } && has_install=1
    while IFS= read -r src; do
        rel="${src#"$root"/}"
        [ -n "${IGNORED_IN_REPO[$rel]:-}" ] && continue

        dest="$HOME/$rel"

        # A whole top-level entry missing from an installed $HOME. Either you
        # took it out -- unlinked our kitty config, say -- and then it stays
        # out: putting it back as copies, as this used to, undid your choice
        # and planted a real directory where there had been a link. Or it is
        # new in the repo, and then it arrives the way the rest did: as a
        # symlink in --link mode, as copies in --copy mode.
        top="$(top_entry "$rel")"
        if [ -n "$top" ] && [ "$has_install" = 1 ] && [ -z "${top_state[$top]:-}" ] \
           && [ ! -e "$HOME/$top" ] && [ ! -L "$HOME/$top" ]; then
            if [ -n "${DEPLOYED[$top]:-}" ] \
               || { [ -n "$OLD_HEAD" ] && git -C "$REPO" cat-file -e "$OLD_HEAD:home/$top" 2>/dev/null; }; then
                top_state[$top]=removed
                skip "~/$top: you took it out, and it stays out (./install.sh config puts it back)"
                removed_tops=$((removed_tops + 1))
            elif [ "$link_mode" = 1 ]; then
                top_state[$top]=linked
                update_backup_init
                run mkdir -p "$(dirname "$HOME/$top")"
                run ln -s "$REPO/home/$top" "$HOME/$top"
                record_added "$top"
                record_installed "$top" "$HOME/$top"
                ok "$top -> symlink (new in the repo)"
                SYNC_ADDED=$((SYNC_ADDED + 1))
            else
                top_state[$top]=copy
            fi
        fi
        if [ -n "$top" ]; then
            case "${top_state[$top]:-}" in removed|linked) continue ;; esac
        fi

        # If the destination (or its parent directory) is a symlink pointing
        # inside the repo, the pull has already updated what the desktop
        # reads: there is nothing to copy.
        if [ -e "$dest" ] || [ -L "$dest" ]; then
            real="$(readlink -f -- "$dest" 2>/dev/null || true)"
            case "$real" in
                "$repo_real"/*) linked_count=$((linked_count + 1)); continue ;;
            esac
        else
            parent_real="$(readlink -f -- "$(dirname "$dest")" 2>/dev/null || true)"
            case "$parent_real" in
                "$repo_real"/*) linked_count=$((linked_count + 1)); continue ;;
            esac
        fi

        sync_one "$rel" "$src" update
        case "$SYNC_LAST" in
            updated|added)
                fix_file_mode "$rel" "$dest"
                case "$rel" in
                    .local/share/applications/*) apps_changed=1 ;;
                    .config/hypr/scripts/thunar-*) thunar_changed=1 ;;
                esac
                ;;
            conflict) fix_file_mode "$rel" "$dest.new" ;;
        esac
    done < <(find "$root" \( -type f -o -type l \) 2>/dev/null | sort)

    update_dropped_upstream "$repo_real"

    if [ ! -e "$HOME/.gitconfig.local" ] && [ ! -L "$HOME/.gitconfig.local" ] && [ "$DRY" = 0 ]; then
        update_backup_init
        gitconfig_local_template > "$HOME/.gitconfig.local"
        record_added ".gitconfig.local"
        record_installed ".gitconfig.local" "$HOME/.gitconfig.local"
        ok ".gitconfig.local created: uncomment the [user] lines and put your name in them"
    fi

    if [ "$apps_changed" = 1 ]; then
        run update-desktop-database "$HOME/.local/share/applications" 2>/dev/null || true
    fi
    if [ "$thunar_changed" = 1 ] && [ -x "$HOME/.config/hypr/scripts/thunar-language.sh" ]; then
        run sh -c "'$HOME/.config/hypr/scripts/thunar-language.sh' >/dev/null 2>&1" || true
    fi

    printf '  summary: %d updated, %d new, %d unchanged, %d local edit(s) kept, %d conflict(s) (.new)\n' \
           "$SYNC_UPDATED" "$SYNC_ADDED" "$SYNC_SAME" "$SYNC_KEPT" "$SYNC_CONFLICTS"
    [ "$linked_count" -gt 0 ] && printf '  (%d symlinked directly to the repo)\n' "$linked_count"
    [ "$SYNC_PROTECTED" -gt 0 ] && printf '  (%d pywal/user-owned file(s) left untouched)\n' "$SYNC_PROTECTED"
    [ "$SYNC_DELETED_KEPT" -gt 0 ] && printf '  (%d file(s) you deleted stay deleted)\n' "$SYNC_DELETED_KEPT"
    [ "$removed_tops" -gt 0 ] && printf '  (%d top-level entr(y/ies) you took out stay out)\n' "$removed_tops"
    [ $((SYNC_UPDATED + SYNC_ADDED + SYNC_CONFLICTS + DROPPED_REMOVED)) -gt 0 ] && CHANGED_SOMETHING=1

    digests_write
    check_lock_pam
}

# Files the new commits delete. In --link mode git took them away with the
# pull, but a COPY of one -- in --copy mode, or ~/.local/bin in both -- stayed
# behind for good, an orphan the repo no longer knew about. One you never
# edited goes now (into the backup: restore brings it back); one you edited
# stays, and is listed. A symlink of ours left pointing at nothing goes too.
update_dropped_upstream() {
    local repo_real="$1" path rel dest hsum base
    if [ -n "$OLD_HEAD" ] && [ -n "$NEW_HEAD" ] && [ "$OLD_HEAD" != "$NEW_HEAD" ]; then
        while IFS= read -r path; do
            rel="${path#home/}"
            dest="$HOME/$rel"
            [ -f "$dest" ] || [ -L "$dest" ] || continue
            case "$(readlink -f -- "$(dirname "$dest")" 2>/dev/null)" in "$repo_real"/*) continue ;; esac
            is_user_owned "$rel" && continue
            hsum="$(file_sha256 "$dest" || true)"
            base="${AGREED[$rel]:-}"
            [ -n "$base" ] || base="$(blob_sha "$OLD_HEAD" "$path" || true)"
            if [ -n "$base" ] && [ "$hsum" = "$base" ]; then
                update_backup_init
                save_aside "$dest"
                ok "$rel (removed: the repo dropped it)"
                DROPPED_REMOVED=$((DROPPED_REMOVED + 1))
            else
                skip "$rel: the repo dropped it; yours stays, because you edited it"
                KEPT_EDITS+=("$rel  (dropped from the repo)")
            fi
        done < <(git -C "$REPO" diff --name-only --no-renames --diff-filter=D "$OLD_HEAD" "$NEW_HEAD" -- home/ 2>/dev/null)
    fi

    local link
    for link in "$HOME"/.[!.]* "$HOME"/.config/*; do
        [ -L "$link" ] && [ ! -e "$link" ] || continue
        case "$(readlink -- "$link")" in
            "$REPO"/*|"$repo_real"/*)
                update_backup_init
                save_aside "$link"
                ok "${link#"$HOME"/} (removed: a link to something the repo dropped)"
                DROPPED_REMOVED=$((DROPPED_REMOVED + 1))
                ;;
        esac
    done
}

# ----------------------------------------------------------------- step: migrations

# Each migration runs ONCE per machine: a marker under
# ~/.local/state/pocket-dots/migrations says it is done, so re-running the
# updater never repeats one, and one that failed is tried again next time.
# ~/.config/quickshell-rice.json is NOT migrated, not even to add keys a newer
# version introduced: Config.qml declares a default for every key, and a key
# that is missing reads as that default. Writing the defaults in would change
# nothing today, freeze them for good if Config.qml ever changes one, and race
# the shell, which rewrites that file whenever a setting moves.
migrate() {
    local id="$1" fn="$2"
    [ -f "$MIGRATIONS_DIR/$id" ] && return 0
    if "$fn"; then
        if [ "$DRY" = 0 ]; then
            mkdir -p "$MIGRATIONS_DIR" && date '+%F %T' > "$MIGRATIONS_DIR/$id"
            # Undoing this update undoes the marker too, so the migration
            # runs again after a restore put the old file back.
            record_backup_kv MIGRATION "$id"
        fi
    else
        failed "migration $id did not complete; it is tried again on the next update"
    fi
}

# The state directory of colorpicker.py, input-settings.py and
# notification-store.py, 0700 so other local users cannot read notifications
# or input overrides.
mig_state_dir_private() {
    local d="$HOME/.local/state/pocket"
    if [ ! -d "$d" ]; then
        run mkdir -p -m 700 "$d" && ok "created ~/.local/state/pocket (0700)"
        CHANGED_SOMETHING=1
    else
        [ "$DRY" = 0 ] && chmod 700 "$d" 2>/dev/null
    fi
    return 0
}

# The old Spanish unit name, retired.
mig_poke_humor_to_mood() {
    command -v systemctl >/dev/null 2>&1 || return 0
    systemctl --user is-enabled poke-humor.service >/dev/null 2>&1 || return 0
    run systemctl --user disable --now poke-humor.service >/dev/null 2>&1 || true
    run systemctl --user enable poke-mood.service >/dev/null 2>&1 || true
    ok "migrated poke-humor.service -> poke-mood.service"
    CHANGED_SOMETHING=1
    return 0
}

# ~/.gitconfig.local as older installs wrote it: [user] filled in with a
# placeholder, which git took for a real identity, so commits went out as
# "Your Name <you@example.com>" without git ever asking. Only the untouched
# placeholder lines are commented out; a name of yours is never touched.
mig_gitconfig_placeholder() {
    local f="$HOME/.gitconfig.local"
    [ -f "$f" ] && [ ! -L "$f" ] || return 0
    grep -qE '^[[:space:]]*name = Your Name[[:space:]]*$' "$f" \
        && grep -qE '^[[:space:]]*email = you@example\.com[[:space:]]*$' "$f" || return 0
    if [ "$DRY" = 1 ]; then
        skip "would comment out the placeholder identity in ~/.gitconfig.local"
        return 0
    fi
    update_backup_init
    mkdir -p "$BACKUP" && cp -a -- "$f" "$BACKUP/.gitconfig.local" || return 1
    sed -i -e 's/^\([[:space:]]*\)name = Your Name[[:space:]]*$/#\1name = Your Name/' \
           -e 's/^\([[:space:]]*\)email = you@example\.com[[:space:]]*$/#\1email = you@example.com/' "$f" \
        || return 1
    record_installed .gitconfig.local "$f"
    ok "~/.gitconfig.local: the placeholder identity is commented out (git will ask who you are)"
    CHANGED_SOMETHING=1
    return 0
}

update_migrations() {
    heading "Settings migrations"

    migrate 2026-10-state-dir-private mig_state_dir_private
    migrate 2026-10-poke-humor-to-mood mig_poke_humor_to_mood
    migrate 2026-11-gitconfig-placeholder mig_gitconfig_placeholder

    # Not migrations but checks, on every run: the gitignored runtime state
    # files a desktop needs (see step 7 of install.sh's config phase).
    local hypridle="$HOME/.config/hypr/hypridle.conf"
    if [ ! -f "$hypridle" ] && [ -f "$REPO/home/.config/hypr/hypridle.d/normal.conf" ]; then
        update_backup_init
        run mkdir -p "$(dirname "$hypridle")"
        run cp -- "$REPO/home/.config/hypr/hypridle.d/normal.conf" "$hypridle"
        record_added ".config/hypr/hypridle.conf"
        record_installed ".config/hypr/hypridle.conf" "$hypridle"
        ok "hypridle.conf seeded from the normal profile"
    fi

    local pokestate="$HOME/.config/poke-theme/state"
    if [ ! -f "$pokestate" ]; then
        update_backup_init
        run mkdir -p "$(dirname "$pokestate")"
        [ "$DRY" = 0 ] && printf 'on\n' > "$pokestate"
        record_added ".config/poke-theme/state"
        record_installed ".config/poke-theme/state" "$pokestate"
        ok "poke-theme state seeded"
    fi
}

# ----------------------------------------------------------------- step: reload

qs_running() {
    pgrep -u "$(id -u)" -x qs >/dev/null 2>&1 \
        || pgrep -u "$(id -u)" -x quickshell >/dev/null 2>&1 \
        || { command -v systemctl >/dev/null 2>&1 && systemctl --user is-active --quiet quickshell.service 2>/dev/null; }
}

update_reload() {
    heading "Reload desktop"

    if [ "$DRY" = 1 ]; then
        printf '  %s[dry]%s hyprctl reload\n' "$C_DIM" "$C_OFF"
        [ "$QS_WAS_RUNNING" = 1 ] && printf '  %s[dry]%s %s/.config/quickshell/reload.sh\n' "$C_DIM" "$C_OFF" "$HOME"
        return 0
    fi

    # Guard against reloading the host's live session when update.sh is being
    # tested against a throwaway $HOME.
    local real_home=""
    if command -v getent >/dev/null 2>&1; then
        real_home="$(getent passwd "$(id -un)" 2>/dev/null | cut -d: -f6)"
    fi
    if [ -n "$real_home" ] && [ "$HOME" != "$real_home" ] && [ "${POCKET_UPDATE_FORCE_RELOAD:-0}" != 1 ]; then
        skip "running inside a test HOME ($HOME); skipping live Hyprland/Quickshell reload"
        return 0
    fi

    if command -v hyprctl >/dev/null 2>&1 \
       && { [ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ] || pgrep -u "$(id -u)" -x Hyprland >/dev/null 2>&1; }; then
        if hyprctl reload >/dev/null 2>&1; then
            ok "Hyprland reloaded"
        else
            warn "hyprctl reload returned an error (is Hyprland running in this session?)"
        fi
    else
        skip "Hyprland is not running in this session"
    fi

    # Quickshell is restarted only if it was running when this update began:
    # a run from a TTY must not start a shell nobody asked for. If it was, and
    # is not any more -- a Qt upgrade under it can do that -- it is started
    # again, and said so.
    if [ "$QS_WAS_RUNNING" = 0 ]; then
        skip "Quickshell was not running; nothing to reload"
        return 0
    fi
    # If hyprlock is currently locking the screen, do not kill and restart qs
    # underneath it: Quickshell already hot-reloads changed QML files via
    # inotify, and a full restart can wait until unlock.
    if command -v pidof >/dev/null 2>&1 && pidof hyprlock >/dev/null 2>&1; then
        skip "hyprlock is active: leaving running Quickshell instance to hot-reload via inotify"
        return 0
    fi
    local was_up=0
    qs_running && was_up=1
    # Its output goes to the log, never through the log's pipe: a shell it
    # starts in the background would hold that pipe open and the run would
    # never finish.
    if [ -x "$HOME/.config/quickshell/reload.sh" ]; then
        "$HOME/.config/quickshell/reload.sh" </dev/null >>"${LOG_FILE:-/dev/null}" 2>&1
    elif command -v systemctl >/dev/null 2>&1; then
        systemctl --user restart quickshell.service >/dev/null 2>&1
    fi
    if qs_running; then
        if [ "$was_up" = 1 ]; then ok "Quickshell reloaded"; else ok "Quickshell had stopped during the update: started again"; fi
    else
        failed "Quickshell is not running after the reload: systemctl --user status quickshell"
    fi
}

# ----------------------------------------------------------------- step: restore

# Undoes the LAST update, found through the pointer update_backup_init
# leaves. Never an older update by accident, and never the whole install:
# that is ./install.sh restore, said out loud.
update_restore() {
    heading "Undo the last update"
    list_backups
    local which=""
    if [ -n "$RESTORE_FROM" ]; then
        if [ -d "$RESTORE_FROM" ]; then
            which="$(cd "$RESTORE_FROM" && pwd)"
        elif [ -d "$HOME/.dotfiles-backup/$RESTORE_FROM" ]; then
            which="$HOME/.dotfiles-backup/$RESTORE_FROM"
        fi
        if [ -z "$which" ] || [ ! -f "$which/.update-backup" ]; then
            failed "$RESTORE_FROM is not an update backup. To put back an install backup: ./install.sh restore $RESTORE_FROM"
            return 0
        fi
    else
        which="$(cat "$LAST_UPDATE_PTR" 2>/dev/null)"
        if [ -z "$which" ] || [ ! -f "$which/.update-backup" ]; then
            skip "there is no update to undo: the last one was already undone, or none changed anything."
            skip "To undo the install itself: ./install.sh restore"
            return 0
        fi
    fi
    restore_update_backup "$which"
}

# ----------------------------------------------------------------- go

start_run update
detect_distro
qs_running && QS_WAS_RUNNING=1

printf '%s' "$C_TIT"
cat <<'HEADER'
   pocket -- desktop updater
HEADER
printf '%s' "$C_OFF"
printf '  repo:   %s\n  steps:  %s\n' "$REPO" "${UPDATE_STEPS[*]}"
[ -n "$LOG_FILE" ] && printf '  log:    %s\n' "${LOG_FILE/#$HOME/\~}"
[ "${POCKET_RELAUNCHED:-0}" = 1 ] && printf '  (carrying on with the updated updater)\n'
[ "$DRY" = 1 ] && printf '  %sDRY RUN: nothing will be modified%s\n' "$C_WARN" "$C_OFF"

if [ "$DRY" = 0 ] && { update_doing pull || update_doing packages || update_doing config || update_doing migrations; }; then
    update_backup_init
fi

for step in "${UPDATE_STEPS[@]}"; do
    case "$step" in
        pull)       update_pull ;;
        packages)   update_packages ;;
        config)     update_config ;;
        migrations) update_migrations ;;
        reload)     update_reload ;;
        restore)    update_restore ;;
        digests)    phase_digests ;;
    esac
done

finish_update_backup

heading "Done"
print_summary
printf '\n'
if [ "$DRY" = 1 ]; then
    printf '  That was a dry run: nothing was touched.\n  Drop --dry-run to apply the update.\n\n'
elif [ "$BACKUP_INITIALISED" = 1 ]; then
    head_now="$(git -C "$REPO" rev-parse HEAD 2>/dev/null || true)"
    start_head="$(sed -n 's/^OLD_HEAD=//p' "$BACKUP/.update-backup" 2>/dev/null | head -1)"
    if [ -n "$start_head" ] && [ "$start_head" != "$head_now" ]; then
        printf '  Updated %s -> %s.\n' "${start_head:0:7}" "${head_now:0:7}"
    fi
    printf '  Previous files saved in: %s\n' "${BACKUP/#$HOME/\~}"
    printf '  To undo this update:     ./update.sh restore\n\n'
elif ! update_doing restore && ! update_doing digests; then
    printf '  Everything was already up to date.\n\n'
fi
[ ${#FAILED[@]} -eq 0 ] || exit 1
exit 0
