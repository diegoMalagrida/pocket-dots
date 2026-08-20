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

export EDITOR=code

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
alias lisp='cd ~/uni/lisp/practica-lisp && ./scritps/run.sh'

# fzf usa los 16 colores ANSI que kitty recarga desde pywal.
# Respeta cualquier --color personalizado que el usuario ya haya definido.
case " ${FZF_DEFAULT_OPTS-} " in
  *" --color="*) ;;
  *) export FZF_DEFAULT_OPTS="${FZF_DEFAULT_OPTS:+$FZF_DEFAULT_OPTS }--color=base16" ;;
esac

# Glow y la ayuda Markdown de gh comparten el mismo estilo Glamour pywal.
export GLAMOUR_STYLE="$HOME/.cache/wal/colors-glamour.json"


# To customize prompt, run `p10k configure` or edit ~/.p10k.zsh.
[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh





# ---- fastfetch solo en la primera kitty del workspace ----

fastfetch_ws_if_first() {
  command -v hyprctl >/dev/null 2>&1 || return
  command -v jq >/dev/null 2>&1 || return

  # Sin compositor, ni se intenta. Esta guarda es la reparacion de un susto
  # real: la noche que la torre se quedo sin escritorio, ABRIR UNA TERMINAL
  # escupia
  #     parse error: Invalid numeric literal at line 1, column 28
  # y eso fue lo primero que se vio, asi que parecia LA causa del problema
  # cuando no tenia nada que ver. El motivo: `hyprctl` sin Hyprland detras no
  # falla en silencio, imprime su queja ("Couldn't connect to ...") por STDOUT,
  # o sea directamente por la tuberia, y jq intenta parsearla como JSON. El
  # `2>/dev/null` que habia solo tapaba el stderr de hyprctl, que estaba vacio.
  #
  # HYPRLAND_INSTANCE_SIGNATURE la exporta Hyprland a todo lo que lanza (y uwsm
  # la propaga a la sesion), asi que existe dentro del escritorio y no existe en
  # una tty pelada, que es exactamente la distincion que hace falta.
  [[ -n ${HYPRLAND_INSTANCE_SIGNATURE:-} ]] || return

  local ws
  # jq tambien callado: si hyprctl responde una cosa rara, se vuelve sin ruido.
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
# Evita duplicados al combinar .profile, uv y recargas manuales de .zshrc.
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

# ---- Prompt naranja+azul (overrides de Powerlevel10k) ----
[[ -f ~/.config/p10k/diego-theme.zsh ]] && source ~/.config/p10k/diego-theme.zsh


# ---- Sprites tematizados: sesga la ELECCION del pokemon segun el tema pywal ----
# Solo decide QUE fichero sale; el pintado (kitten icat / chafa) no se toca.
# El ranking lo calcula 'poke-theme' comparando la paleta de cada sprite con la
# del tema; aqui solo se lee un fichero ya ordenado (0 forks, 0 ms perceptibles).
# Si no hay ranking valido devuelve 1 y quien llama se queda con el azar de antes.
poke_theme_pick() {
  emulate -L zsh
  REPLY=""
  local tipo=${1:-gif}
  local rank="$HOME/.cache/pokepalette/rank-${tipo}.txt"
  local wal="$HOME/.cache/wal/colors.json"

  # Interruptor (pokeball del centro de control / 'poke-theme off'). Sin fichero
  # = activado. $(<fichero) en zsh es lectura interna, no lanza ningun proceso.
  local estado="$HOME/.config/poke-theme/state"
  [[ -r $estado && $(<$estado) == off ]] && return 1

  # Ranking ausente o mas viejo que el tema -> se regenera en 2o plano (~0.1 s)
  # y esta terminal tira del ranking anterior; la siguiente ya sale al dia.
  if [[ ! -s $rank || ( -f $wal && $wal -nt $rank ) ]]; then
    [[ -s $HOME/.cache/pokepalette/sprites.tsv ]] && \
      (poke-theme rank -q >/dev/null 2>&1 &) 2>/dev/null
    [[ -s $rank ]] || return 1
  fi

  local -a mejores=("${(@f)$(<$rank)}")
  (( ${#mejores} )) || return 1
  # De los N que mas pegan, sesgo hacia la cabeza: dos tiradas y me quedo la menor
  # (los que mas se ajustan salen mas, pero sigue habiendo variedad).
  local n=$(( ${#mejores} < 40 ? ${#mejores} : 40 ))
  local a=$(( RANDOM % n )) b=$(( RANDOM % n ))
  local i=$(( (a < b ? a : b) + 1 ))
  [[ -f ${mejores[i]} ]] || return 1
  REPLY=${mejores[i]}
}

# ---- Logo de fastfetch = pokemon aleatorio (pokeshell) ----
# Elige un sprite cacheado con glob NATIVO de zsh (NO 'ls', que esta aliaseado a eza).
# Copia a un nombre sin ':' y lo pinta fastfetch (kitty). En 2o plano caza otro.
pokefetch() {
  emulate -L zsh
  local adir="$HOME/.cache/pokeanim" aart="$HOME/.cache/pokeart"

  # === Preferido: pokemon ANIMADO (imagen kitty izq + info derecha) ===
  local -a gifs=("$adir"/*.gif(N))
  if (( ${#gifs} )) && command -v kitten >/dev/null 2>&1; then
    poke_theme_pick gif   # sesga por tema; si no hay ranking cae al azar de siempre
    local gif=${REPLY:-${gifs[RANDOM % ${#gifs} + 1]}}
    # POKE_FIJO=<numero> clava el sprite de ESTA terminal. Manda sobre el sesgo
    # por tema y sobre el azar, y solo afecta a quien lleve la variable puesta:
    #   POKE_FIJO=254 kitty        una terminal con Sceptile, el resto igual
    # Lo usa la grabacion del video para que el escritorio abra siempre con el
    # mismo. Si ese numero no esta descargado, se ignora sin decir nada.
    [[ -n ${POKE_FIJO:-} && -f $adir/$POKE_FIJO.gif ]] && gif=$adir/$POKE_FIJO.gif
    local play="$gif"
    local big="$adir/.box/${gif:t}"
    if [[ ! -f $big ]]; then
      mkdir -p "$adir/.box"
      if command -v ffmpeg >/dev/null 2>&1; then
        # frames de lienzo completo (-gifflags -offsetting) + dispose background (default ffmpeg)
        # = sin fragmentos ni trails en kitten icat; nearest-neighbor = pixel art nitido; ~0.2s
        ffmpeg -y -i "$gif" -filter_complex 'fps=15,scale=w=200:h=168:force_original_aspect_ratio=decrease:flags=neighbor,format=rgba,pad=200:ih:(200-iw)/2:0:color=#00000000,split[s0][s1];[s0]palettegen=reserve_transparent=1[p];[s1][p]paletteuse=alpha_threshold=128:diff_mode=none' -gifflags -offsetting "$big" >/dev/null 2>&1
      elif command -v magick >/dev/null 2>&1; then
        magick "$gif" -coalesce -filter point -resize 200x168 "$big" 2>/dev/null
      fi
    fi
    [[ -f $big ]] && play="$big"
    local -a il=("${(@f)$(fastfetch --logo none 2>/dev/null)}")
    local n=${#il} indent=32 ln
    printf "\033[2J\033[H"                          # limpia el instant-prompt de p10k (evita prompt doble)
    printf "\0337"                                  # guarda cursor
    for ln in "${il[@]}"; do printf "%*s%s\n" $indent "" "$ln"; done   # info a la derecha
    printf "\0338"                                  # vuelve arriba
    printf "\033[2B"                                # baja SOLO el sprite 2 filas (lo centra con la info)
    kitten icat --align left --loop -1 "$play" 2>/dev/null   # gif animado izq (no bloquea)
    printf "\0338"                                  # vuelve arriba otra vez
    printf "\033[%dB" $n                            # baja n filas -> debajo de la info
    return
  fi

  # === Fallback: bloques estaticos de alta-res ===
  local -a sprites=("$aart"/*.png(N.))
  local sprite="" idx
  poke_theme_pick png   # mismo sesgo por tema para el fallback de chafa
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

# ---- pokeanim: pokemon ANIMADO a demanda (kitty, pixeles reales) ----
# Los sprites animados (gen5) son pequenos: los pre-escalo x5 con vecino-cercano
# (pixel-art nitido) y los reproduce kitten icat en bucle. Ctrl+C para salir.
# El grafico animado NO va en el arranque (kitty no pinta en el hook precmd), por eso
# es un comando aparte. Ejecuta:  pokeanim
pokeanim() {
  emulate -L zsh
  local dir="$HOME/.cache/pokeanim"
  local -a gifs=("$dir"/*.gif(N))
  if (( ! ${#gifs} )); then
    print -- "No hay animados en cache todavia (se estan descargando)."
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

# ---- pokefa: PRUEBA del pokemon animado integrado (imagen izq + info derecha) ----
pokefa() {
  emulate -L zsh
  local adir="$HOME/.cache/pokeanim"
  local -a gifs=("$adir"/*.gif(N))
  (( ${#gifs} )) || { print -- "no hay gifs"; return 1; }
  command -v kitten >/dev/null 2>&1 || { print -- "no kitten"; return 1; }
  local gif=${gifs[RANDOM % ${#gifs} + 1]} play="$gif"
  if command -v magick >/dev/null 2>&1; then
    local tmp="$adir/.play.gif"
    magick "$gif" -coalesce -filter point -resize 320x260 "$tmp" 2>/dev/null && play="$tmp"
  fi
  local -a il=("${(@f)$(fastfetch --logo none 2>/dev/null)}")
  local n=${#il}
  local W=26 gap=4 H=$n
  # consulta la fila del cursor -> colocamos con --place (fija, sin scroll)
  local pos row
  printf "\033[6n"
  read -s -t 1 -d R pos 2>/dev/null
  pos=${pos##*\[}; row=${pos%%;*}
  [[ $row == <-> ]] || row=1
  # gif animado (bucle server-side, no bloquea) en WxH celdas, columna 0, fila actual
  kitten icat --align left --place ${W}x${H}@0x$((row-1)) "$play" 2>/dev/null
  # info a la derecha, alineada
  local r=$row ln
  for ln in "${il[@]}"; do
    printf "\033[%d;%dH%s" $r $((W+gap+1)) "$ln"
    (( r++ ))
  done
  printf "\033[%d;1H" $(( row + H ))   # cursor debajo -> prompt limpio
}

# --- tooling moderno ---
eval "$(zoxide init zsh)"        # z <dir> = salto inteligente; zi = con fzf
