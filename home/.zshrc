# Enable Powerlevel10k instant prompt. Should stay close to the top of ~/.zshrc.
# Initialization code that may require console input (password prompts, [y/n]
# confirmations, etc.) must go above this block; everything else may go below.
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi


# If you come from bash you might have to change your $PATH.
# export PATH=$HOME/bin:$HOME/.local/bin:/usr/local/bin:$PATH

# Path to your Oh My Zsh installation.
export ZSH="$HOME/.oh-my-zsh"

# --wait is NOT optional here. Without it, `code` hands control back at once and
# whoever called the editor carries on without waiting: `git commit` without -m
# reads the STILL EMPTY message file and aborts with "Aborting commit due to
# empty commit message". The same with `systemctl edit`, `crontab -e` or
# `visudo`: the window opens, the command has already finished, and whatever
# you type goes nowhere.
# VISUAL follows because git and sudo prefer it over EDITOR when it exists.
export EDITOR='code --wait'
export VISUAL="$EDITOR"

# Set name of the theme to load --- if set to "random", it will
# load a random theme each time Oh My Zsh is loaded, in which case,
# to know which specific one was loaded, run: echo $RANDOM_THEME
# See https://github.com/ohmyzsh/ohmyzsh/wiki/Themes
ZSH_THEME="powerlevel10k/powerlevel10k"

# Set list of themes to pick from when loading at random
# Setting this variable when ZSH_THEME=random will cause zsh to load
# a theme from this variable instead of looking in $ZSH/themes/
# If set to an empty array, this variable will have no effect.
# ZSH_THEME_RANDOM_CANDIDATES=( "robbyrussell" "agnoster" )

# Uncomment the following line to use case-sensitive completion.
# CASE_SENSITIVE="true"

# Uncomment the following line to use hyphen-insensitive completion.
# Case-sensitive completion must be off. _ and - will be interchangeable.
# HYPHEN_INSENSITIVE="true"

# Uncomment one of the following lines to change the auto-update behavior
# zstyle ':omz:update' mode disabled  # disable automatic updates
# zstyle ':omz:update' mode auto      # update automatically without asking
# zstyle ':omz:update' mode reminder  # just remind me to update when it's time

# Uncomment the following line to change how often to auto-update (in days).
# zstyle ':omz:update' frequency 13

# Uncomment the following line if pasting URLs and other text is messed up.
# DISABLE_MAGIC_FUNCTIONS="true"

# Uncomment the following line to disable colors in ls.
# DISABLE_LS_COLORS="true"

# Uncomment the following line to disable auto-setting terminal title.
# DISABLE_AUTO_TITLE="true"

# Uncomment the following line to enable command auto-correction.
# ENABLE_CORRECTION="true"

# Uncomment the following line to display red dots whilst waiting for completion.
# You can also set it to another string to have that shown instead of the default red dots.
# e.g. COMPLETION_WAITING_DOTS="%F{yellow}waiting...%f"
# Caution: this setting can cause issues with multiline prompts in zsh < 5.7.1 (see #5765)
# COMPLETION_WAITING_DOTS="true"

# Uncomment the following line if you want to disable marking untracked files
# under VCS as dirty. This makes repository status check for large repositories
# much, much faster.
# DISABLE_UNTRACKED_FILES_DIRTY="true"

# Uncomment the following line if you want to change the command execution time
# stamp shown in the history command output.
# You can set one of the optional three formats:
# "mm/dd/yyyy"|"dd.mm.yyyy"|"yyyy-mm-dd"
# or set a custom format using the strftime function format specifications,
# see 'man strftime' for details.
# HIST_STAMPS="mm/dd/yyyy"

# Would you like to use another custom folder than $ZSH/custom?
# ZSH_CUSTOM=/path/to/new-custom-folder

# Which 
# plugins would you like to load?
# Standard plugins can be found in $ZSH/plugins/
# Custom plugins may be added to $ZSH_CUSTOM/plugins/
# Example format: plugins=(rails git textmate ruby lighthouse)
# Add wisely, as too many plugins slow down shell startup.
plugins=(git zsh-autosuggestions zsh-syntax-highlighting)

source $ZSH/oh-my-zsh.sh

# User configuration

# export MANPATH="/usr/local/man:$MANPATH"

# You may need to manually set your language environment
# export LANG=en_US.UTF-8

# Preferred editor for local and remote sessions
# if [[ -n $SSH_CONNECTION ]]; then
#   export EDITOR='vim'
# else
#   export EDITOR='nvim'
# fi

# Compilation flags
# export ARCHFLAGS="-arch $(uname -m)"

# Set personal aliases, overriding those provided by Oh My Zsh libs,
# plugins, and themes. Aliases can be placed here, though Oh My Zsh
# users are encouraged to define aliases within a top-level file in
# the $ZSH_CUSTOM folder, with .zsh extension. Examples:
# - $ZSH_CUSTOM/aliases.zsh
# - $ZSH_CUSTOM/macos.zsh
# For a full list of active aliases, run `alias`.
#
# Example aliases
# alias zshconfig="mate ~/.zshrc"
# alias ohmyzsh="mate ~/.oh-my-zsh"

alias ls="exa -l"

# fzf uses the 16 ANSI colours that kitty reloads from pywal.
# It respects any custom --color the user has already defined.
case " ${FZF_DEFAULT_OPTS-} " in
  *" --color="*) ;;
  *) export FZF_DEFAULT_OPTS="${FZF_DEFAULT_OPTS:+$FZF_DEFAULT_OPTS }--color=base16" ;;
esac

# Glow and gh's Markdown help share the same pywal Glamour style.
export GLAMOUR_STYLE="$HOME/.cache/wal/colors-glamour.json"


# To customize prompt, run `p10k configure` or edit ~/.p10k.zsh.
[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh





# ---- fastfetch only in the workspace's first kitty ----

fastfetch_ws_if_first() {
  command -v hyprctl >/dev/null 2>&1 || return
  command -v jq >/dev/null 2>&1 || return

  # Without a compositor, it is not even attempted. This guard is the fix for a
  # real scare: the night the tower was left without a desktop, OPENING A
  # TERMINAL spat out
  #     parse error: Invalid numeric literal at line 1, column 28
  # and that was the first thing anyone saw, so it looked like THE cause of the
  # problem when it had nothing to do with it. The reason: `hyprctl` with no
  # Hyprland behind it does not fail silently, it prints its complaint
  # ("Couldn't connect to ...") on STDOUT, that is, straight down the pipe, and
  # jq tries to parse it as JSON. The `2>/dev/null` that was there only hid
  # hyprctl's stderr, which was empty.
  #
  # Hyprland exports HYPRLAND_INSTANCE_SIGNATURE to everything it launches (and
  # uwsm propagates it to the session), so it exists inside the desktop and does
  # not exist on a bare tty, which is exactly the distinction needed.
  [[ -n ${HYPRLAND_INSTANCE_SIGNATURE:-} ]] || return

  local ws
  # jq silenced too: if hyprctl answers something odd, return without noise.
  ws=$(hyprctl activeworkspace -j 2>/dev/null | jq -r '.id' 2>/dev/null) || return
  [[ -z "$ws" || "$ws" == "null" ]] && return

  local kitty_pid
  kitty_pid=$(ps -o ppid= -p $$ --no-headers 2>/dev/null | tr -d ' ') || return
  [[ -z "$kitty_pid" ]] && return

  local others
  others=$(hyprctl clients -j 2>/dev/null \
    | jq --argjson ws "$ws" --argjson pid "$kitty_pid" '
      [ .[]
        | select(.class == "kitty" and .workspace.id == $ws and .pid != $pid)
      ]
      | length
    ' 2>/dev/null) || return

  if [ "${others:-0}" -eq 0 ]; then
    pokefetch
  fi
}

# ---- Run fastfetch AFTER prompt (Powerlevel10k safe) ----
autoload -Uz add-zsh-hook

run_fastfetch_once() {
  fastfetch_ws_if_first
  add-zsh-hook -d precmd run_fastfetch_once
}

add-zsh-hook precmd run_fastfetch_once

typeset -g POWERLEVEL9K_INSTANT_PROMPT=quiet



alias cls='clear'
alias pussy='fzf'
alias matrix='unimatrix -n -s 96 -l 'o''



export PATH="$HOME/.local/bin:$PATH"
# Avoids duplicates when combining .profile, uv and manual reloads of .zshrc.
#
# The :A goes BEFORE the typeset -U on purpose. typeset -U deduplicates by
# comparing STRINGS, and "/home/diego/.local/bin" and
# "/home/diego/.local/share/../bin" are different strings pointing to the SAME
# directory, so both survived (the second is added by the `. ~/.local/bin/env`
# in ~/.profile). Every command the shell had not cached made one extra call
# while looking for the executable.
# :A resolves the .. and the symlinks, and then typeset -U sees only one.
path=( ${path[@]:A} )
typeset -U path PATH

# BEGIN YAZI Y WRAPPER
function y() {
  local tmp="$(mktemp -t "yazi-cwd.XXXXXX")" cwd
  yazi "$@" --cwd-file="$tmp"
  if cwd="$(command cat -- "$tmp")" && [ -n "$cwd" ] && [ "$cwd" != "$PWD" ]; then
    builtin cd -- "$cwd"
  fi
  rm -f -- "$tmp"
}
# END YAZI Y WRAPPER

# ---- Orange+blue prompt (Powerlevel10k overrides) ----
[[ -f ~/.config/p10k/diego-theme.zsh ]] && source ~/.config/p10k/diego-theme.zsh


# ---- Themed sprites: biases the CHOICE of pokemon by the pywal theme ----
# It only decides WHICH file comes out; the drawing (kitten icat / chafa) is
# left alone. The ranking is computed by 'poke-theme' comparing each sprite's
# palette with the theme's; here an already sorted file is only read (0 forks,
# 0 ms you could notice). If there is no valid ranking it returns 1 and the
# caller keeps the old random pick.
poke_theme_pick() {
  emulate -L zsh
  REPLY=""
  local tipo=${1:-gif}
  local rank="$HOME/.cache/pokepalette/rank-${tipo}.txt"
  local wal="$HOME/.cache/wal/colors.json"

  # Switch (the Control Centre pokeball / 'poke-theme off'). No file = on.
  # $(<file) in zsh is an internal read, it does not launch any process.
  local estado="$HOME/.config/poke-theme/state"
  [[ -r $estado && $(<$estado) == off ]] && return 1

  # Ranking missing or older than the theme -> it is regenerated in the
  # background (~0.1 s) and this terminal makes do with the previous ranking;
  # the next one comes out up to date.
  if [[ ! -s $rank || ( -f $wal && $wal -nt $rank ) ]]; then
    [[ -s $HOME/.cache/pokepalette/sprites.tsv ]] && \
      (poke-theme rank -q >/dev/null 2>&1 &) 2>/dev/null
    [[ -s $rank ]] || return 1
  fi

  local -a mejores=("${(@f)$(<$rank)}")
  (( ${#mejores} )) || return 1
  # Of the N that fit best, bias towards the head: two rolls and keep the lower
  # (the best matches come out more often, but there is still variety).
  local n=$(( ${#mejores} < 40 ? ${#mejores} : 40 ))
  local a=$(( RANDOM % n )) b=$(( RANDOM % n ))
  local i=$(( (a < b ? a : b) + 1 ))
  [[ -f ${mejores[i]} ]] || return 1
  REPLY=${mejores[i]}
}

# ---- fastfetch logo = random pokemon (pokeshell) ----
# Picks a cached sprite with a NATIVE zsh glob (NOT 'ls', which is aliased to eza).
# Copies to a name without ':' and fastfetch draws it (kitty). In the background
# it hunts for another.
pokefetch() {
  emulate -L zsh
  local adir="$HOME/.cache/pokeanim" aart="$HOME/.cache/pokeart"

  # === Preferred: ANIMATED pokemon (kitty image left + info right) ===
  local -a gifs=("$adir"/*.gif(N))
  if (( ${#gifs} )) && command -v kitten >/dev/null 2>&1; then
    poke_theme_pick gif   # biased by theme; with no ranking it falls back to the usual random pick
    local gif=${REPLY:-${gifs[RANDOM % ${#gifs} + 1]}}
    # POKE_FIJO=<number> pins the sprite of THIS terminal. It overrides the theme
    # bias and the random pick, and only affects whoever has the variable set:
    #   POKE_FIJO=254 kitty        one terminal with Sceptile, the rest as usual
    # The video recording uses it so that the desktop always opens with the
    # same one. If that number is not downloaded, it is ignored without a word.
    [[ -n ${POKE_FIJO:-} && -f $adir/$POKE_FIJO.gif ]] && gif=$adir/$POKE_FIJO.gif
    local play="$gif"
    local big="$adir/.box/${gif:t}"
    if [[ ! -f $big ]]; then
      mkdir -p "$adir/.box"
      if command -v ffmpeg >/dev/null 2>&1; then
        # full-canvas frames (-gifflags -offsetting) + dispose background (ffmpeg default)
        # = no fragments or trails in kitten icat; nearest-neighbour = crisp pixel art; ~0.2s
        ffmpeg -y -i "$gif" -filter_complex 'fps=15,scale=w=200:h=168:force_original_aspect_ratio=decrease:flags=neighbor,format=rgba,pad=200:ih:(200-iw)/2:0:color=#00000000,split[s0][s1];[s0]palettegen=reserve_transparent=1[p];[s1][p]paletteuse=alpha_threshold=128:diff_mode=none' -gifflags -offsetting "$big" >/dev/null 2>&1
      elif command -v magick >/dev/null 2>&1; then
        magick "$gif" -coalesce -filter point -resize 200x168 "$big" 2>/dev/null
      fi
    fi
    [[ -f $big ]] && play="$big"
    local -a il=("${(@f)$(fastfetch --logo none 2>/dev/null)}")
    local n=${#il} indent=32 ln
    printf "\033[2J\033[H"                          # clears the p10k instant prompt (avoids a double prompt)
    printf "\0337"                                  # save cursor
    for ln in "${il[@]}"; do printf "%*s%s\n" $indent "" "$ln"; done   # info on the right
    printf "\0338"                                  # back to the top
    printf "\033[2B"                                # moves ONLY the sprite down 2 rows (centres it against the info)
    kitten icat --align left --loop -1 "$play" 2>/dev/null   # animated gif on the left (non-blocking)
    printf "\0338"                                  # back to the top again
    printf "\033[%dB" $n                            # down n rows -> below the info
    return
  fi

  # === Fallback: static high-res blocks ===
  local -a sprites=("$aart"/*.png(N.))
  local sprite="" idx
  poke_theme_pick png   # same theme bias for the chafa fallback
  [[ -n ${POKE_FIJO:-} && -f $aart/$POKE_FIJO.png ]] && REPLY=$aart/$POKE_FIJO.png
  if [[ -n $REPLY ]] && tail -c 12 -- "$REPLY" 2>/dev/null | grep -qa IEND; then
    sprite="$REPLY"
  fi
  while (( ${#sprites} )) && [[ -z $sprite ]]; do
    idx=$(( RANDOM % ${#sprites} + 1 ))
    if tail -c 12 -- "${sprites[idx]}" 2>/dev/null | grep -qa IEND; then
      sprite="${sprites[idx]}"; break
    fi
    sprites[idx]=()
  done
  if [[ -n $sprite ]] && command -v chafa >/dev/null 2>&1; then
    local logo=$(chafa -c full --format symbols --symbols block+sextant+octant+half+quad+space --dither none -w 9 --size 40x24 "$sprite" 2>/dev/null)
    [[ -n $logo ]] && fastfetch --logo-type data-raw --logo "$logo" --logo-padding-top 1 || fastfetch
  else
    fastfetch
  fi
}

# ---- pokeanim: ANIMATED pokemon on demand (kitty, real pixels) ----
# The animated sprites (gen5) are small: they are pre-scaled x5 with nearest
# neighbour (crisp pixel art) and kitten icat plays them in a loop. Ctrl+C to quit.
# The animated graphic does NOT go at startup (kitty does not draw in the precmd
# hook), which is why it is a separate command. Run:  pokeanim
pokeanim() {
  emulate -L zsh
  local dir="$HOME/.cache/pokeanim"
  local -a gifs=("$dir"/*.gif(N))
  if (( ! ${#gifs} )); then
    # lang.sh in a subshell: read now, so it follows a language changed after
    # this terminal opened, and nothing of it is left in the interactive shell.
    print -- "$(. "$HOME/.config/hypr/scripts/lang.sh" 2>/dev/null || tr_() { printf '%s' "$1"; }
               tr_ "No hay animados en cache todavia (se estan descargando)." "No animated sprites cached yet (downloading).")"
    return 1
  fi
  local gif=${gifs[RANDOM % ${#gifs} + 1]}
  if command -v kitten >/dev/null 2>&1; then
    local play="$gif"
    if command -v magick >/dev/null 2>&1; then
      local tmp="${dir}/.play.gif"
      magick "$gif" -coalesce -filter point -resize 500% "$tmp" 2>/dev/null && play="$tmp"
    fi
    kitten icat --loop -1 "$play"
  elif command -v chafa >/dev/null 2>&1; then
    chafa --symbols all --size 44x44 "$gif"
  fi
}

# ---- pokefa: TEST of the built-in animated pokemon (image left + info right) ----
pokefa() {
  emulate -L zsh
  local adir="$HOME/.cache/pokeanim"
  local -a gifs=("$adir"/*.gif(N))
  (( ${#gifs} )) || { print -- "$(. "$HOME/.config/hypr/scripts/lang.sh" 2>/dev/null || tr_() { printf '%s' "$1"; }
                                    tr_ "no hay gifs" "No GIFs")"; return 1; }
  command -v kitten >/dev/null 2>&1 || { print -- "no kitten"; return 1; }
  local gif=${gifs[RANDOM % ${#gifs} + 1]} play="$gif"
  if command -v magick >/dev/null 2>&1; then
    local tmp="$adir/.play.gif"
    magick "$gif" -coalesce -filter point -resize 320x260 "$tmp" 2>/dev/null && play="$tmp"
  fi
  local -a il=("${(@f)$(fastfetch --logo none 2>/dev/null)}")
  local n=${#il}
  local W=26 gap=4 H=$n
  # query the cursor row -> place with --place (fixed, no scrolling)
  local pos row
  printf "\033[6n"
  read -s -t 1 -d R pos 2>/dev/null
  pos=${pos##*\[}; row=${pos%%;*}
  [[ $row == <-> ]] || row=1
  # animated gif (server-side loop, non-blocking) in WxH cells, column 0, current row
  kitten icat --align left --place ${W}x${H}@0x$((row-1)) "$play" 2>/dev/null
  # info on the right, aligned
  local r=$row ln
  for ln in "${il[@]}"; do
    printf "\033[%d;%dH%s" $r $((W+gap+1)) "$ln"
    (( r++ ))
  done
  printf "\033[%d;1H" $(( row + H ))   # cursor below -> clean prompt
}

# --- modern tooling ---
eval "$(zoxide init zsh)"        # z <dir> = smart jump; zi = with fzf

# --- tool credentials, if there are any ---
#
# NO secret lives here, and none can: this file is versioned in ~/dotfiles,
# which is a public repo. They go in ~/.config/environment.d/, outside the
# repo, one per file and in mode 600.
#
# systemd --user already reads that directory when the session starts, so the
# variables reach everything the desktop opens. This loop is only for the
# terminals of a session that was ALREADY open when the credential changed,
# which would otherwise have to wait for a session restart.
#
# `set -a` exports everything defined while it is on: those files are in
# environment.d format (KEY=value, no `export`), and without this the variable
# would be defined but not exported, that is, invisible to the program
# waiting for it.
for _cred in "$HOME"/.config/environment.d/*.conf(N); do
  [ -r "$_cred" ] || continue
  set -a
  . "$_cred"
  set +a
done
unset _cred

# --- conda (the miniconda from the Arch package, in /opt/miniconda3) ---
#
# It is done with the hook and NOT with `conda init zsh`, which would write a
# generated fifteen-line block here. This defines the `conda` function and
# little else; above all it does NOT activate `base` on its own, so the (name)
# at the start of the prompt only shows up when you activate an environment of
# yours and not in every terminal.
#
# Environments go to ~/.conda/envs: /opt/miniconda3 belongs to root and cannot
# be written to without sudo, which is exactly what you do not want for an
# environment.
[ -r /opt/miniconda3/etc/profile.d/conda.sh ] && . /opt/miniconda3/etc/profile.d/conda.sh
