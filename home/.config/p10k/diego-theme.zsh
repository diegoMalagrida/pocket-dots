# ~/.config/p10k/diego-theme.zsh
# Overrides de Powerlevel10k: estilo LEAN de 1 linea, paleta pywal.
# Se carga DESPUES de ~/.p10k.zsh (ver el source al final de ~/.zshrc).
# Revertir: borra esa linea de source en ~/.zshrc y abre una terminal nueva.

() {
  emulate -L zsh

  # --- Paleta ANSI de kitty (sus slots 0-15 los regenera pywal) ---
  # Usar indices, en vez de RGB fijos, hace que el prompt siga al fondo incluso
  # en shells que ya estaban abiertos cuando kitty recarga su paleta.
  local orange=4 blue=6 cream=7 muted=8
  local red=1 green=2 yellow=3 dim=8

  # --- Segmentos: 1 linea, curados y utiles ---
  typeset -g POWERLEVEL9K_LEFT_PROMPT_ELEMENTS=(os_icon dir vcs prompt_char)
  typeset -g POWERLEVEL9K_RIGHT_PROMPT_ELEMENTS=(
    status                  # codigo de error del ultimo comando
    command_execution_time  # cuanto tardo el ultimo comando (>=2s)
    background_jobs         # trabajos en segundo plano
    direnv                  # entorno direnv
    virtualenv pyenv        # python (venv / pyenv)
    node_version            # node (solo en proyectos node)
    rust_version            # rust (solo en proyectos rust)
    go_version              # go (solo en proyectos go)
    time                    # hora
  )

  # --- Estilo LEAN: fuera fondos y separadores powerline ---
  typeset -g POWERLEVEL9K_LEFT_SEGMENT_SEPARATOR=' '
  typeset -g POWERLEVEL9K_RIGHT_SEGMENT_SEPARATOR=' '
  typeset -g POWERLEVEL9K_LEFT_SUBSEGMENT_SEPARATOR=' '
  typeset -g POWERLEVEL9K_RIGHT_SUBSEGMENT_SEPARATOR=' '
  typeset -g POWERLEVEL9K_LEFT_PROMPT_FIRST_SEGMENT_START_SYMBOL=''
  typeset -g POWERLEVEL9K_LEFT_PROMPT_LAST_SEGMENT_END_SYMBOL=''
  typeset -g POWERLEVEL9K_RIGHT_PROMPT_FIRST_SEGMENT_START_SYMBOL=''
  typeset -g POWERLEVEL9K_RIGHT_PROMPT_LAST_SEGMENT_END_SYMBOL=''
  typeset -g POWERLEVEL9K_MULTILINE_FIRST_PROMPT_GAP_CHAR=' '

  # Quita el fondo de todos los segmentos que uso (transparente)
  local seg
  for seg in OS_ICON DIR PROMPT_CHAR STATUS COMMAND_EXECUTION_TIME BACKGROUND_JOBS \
             DIRENV VIRTUALENV PYENV NODE_VERSION RUST_VERSION GO_VERSION TIME; do
    typeset -g POWERLEVEL9K_${seg}_BACKGROUND=
  done
  local st
  for st in CLEAN MODIFIED UNTRACKED CONFLICTED LOADING; do
    typeset -g POWERLEVEL9K_VCS_${st}_BACKGROUND=
  done

  # --- Colores por segmento ---
  typeset -g POWERLEVEL9K_OS_ICON_FOREGROUND=$orange

  typeset -g POWERLEVEL9K_DIR_FOREGROUND=$blue
  typeset -g POWERLEVEL9K_DIR_ANCHOR_FOREGROUND=$cream
  typeset -g POWERLEVEL9K_DIR_ANCHOR_BOLD=true
  typeset -g POWERLEVEL9K_DIR_SHORTENED_FOREGROUND=$muted

  typeset -g POWERLEVEL9K_VCS_CLEAN_FOREGROUND=$green
  typeset -g POWERLEVEL9K_VCS_MODIFIED_FOREGROUND=$yellow
  typeset -g POWERLEVEL9K_VCS_UNTRACKED_FOREGROUND=$green
  typeset -g POWERLEVEL9K_VCS_CONFLICTED_FOREGROUND=$red
  typeset -g POWERLEVEL9K_VCS_LOADING_FOREGROUND=$muted

  typeset -g POWERLEVEL9K_PROMPT_CHAR_OK_{VIINS,VICMD,VIVIS,VIOWR}_FOREGROUND=$green
  typeset -g POWERLEVEL9K_PROMPT_CHAR_ERROR_{VIINS,VICMD,VIVIS,VIOWR}_FOREGROUND=$red

  # status: mostrar solo el error (sin el tic verde en cada comando OK)
  typeset -g POWERLEVEL9K_STATUS_OK=false
  typeset -g POWERLEVEL9K_STATUS_ERROR=true
  typeset -g POWERLEVEL9K_STATUS_ERROR_FOREGROUND=$red
  typeset -g POWERLEVEL9K_STATUS_ERROR_SIGNAL_FOREGROUND=$red
  typeset -g POWERLEVEL9K_STATUS_ERROR_PIPE_FOREGROUND=$red

  typeset -g POWERLEVEL9K_COMMAND_EXECUTION_TIME_FOREGROUND=$dim
  typeset -g POWERLEVEL9K_COMMAND_EXECUTION_TIME_THRESHOLD=2
  typeset -g POWERLEVEL9K_COMMAND_EXECUTION_TIME_PRECISION=0
  typeset -g POWERLEVEL9K_COMMAND_EXECUTION_TIME_PREFIX=''

  typeset -g POWERLEVEL9K_BACKGROUND_JOBS_FOREGROUND=$blue
  typeset -g POWERLEVEL9K_DIRENV_FOREGROUND=$yellow
  typeset -g POWERLEVEL9K_VIRTUALENV_FOREGROUND=$green
  typeset -g POWERLEVEL9K_PYENV_FOREGROUND=$green
  typeset -g POWERLEVEL9K_NODE_VERSION_FOREGROUND=$green
  typeset -g POWERLEVEL9K_RUST_VERSION_FOREGROUND=$orange
  typeset -g POWERLEVEL9K_GO_VERSION_FOREGROUND=$blue

  typeset -g POWERLEVEL9K_TIME_FOREGROUND=$muted
  typeset -g POWERLEVEL9K_TIME_FORMAT='%D{%H:%M}'
  typeset -g POWERLEVEL9K_TIME_PREFIX=''

  (( ! $+functions[p10k] )) || p10k reload
}
