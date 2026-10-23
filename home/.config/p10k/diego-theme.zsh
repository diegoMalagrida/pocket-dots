# ~/.config/p10k/diego-theme.zsh
# Powerlevel10k overrides: 1-line LEAN style, pywal palette.
# Loaded AFTER ~/.p10k.zsh (see the source at the end of ~/.zshrc).
# To revert: delete that source line in ~/.zshrc and open a new terminal.

() {
  emulate -L zsh

  # --- kitty's ANSI palette (pywal regenerates its slots 0-15) ---
  # Using indices, rather than fixed RGB, makes the prompt follow the wallpaper
  # even in shells that were already open when kitty reloads its palette.
  local orange=4 blue=6 cream=7 muted=8
  local red=1 green=2 yellow=3 dim=8

  # --- The Python environment (venv or conda), if it is switched on ---
  # The preference is stored by ~/.local/bin/prompt-env and changed from
  # Settings > System > Terminal. It is read with builtins -no forks- because
  # this runs on every shell start-up, and ONLY here: terminals you already have
  # open do not hear about the change until you open a new one.
  local estado_entorno=on
  local fichero_entorno=${XDG_CONFIG_HOME:-$HOME/.config}/prompt-entorno/state
  [[ -r $fichero_entorno ]] && read -r estado_entorno < $fichero_entorno
  local -a entorno_py=()
  [[ $estado_entorno == off ]] || entorno_py=(virtualenv anaconda)

  # --- Segments: 1 line, curated and useful ---
  # The environment goes IN FRONT of everything: it is what changes what
  # `python` does, and reading it at the opposite end of the screen was useless.
  typeset -g POWERLEVEL9K_LEFT_PROMPT_ELEMENTS=($entorno_py os_icon dir vcs prompt_char)
  typeset -g POWERLEVEL9K_RIGHT_PROMPT_ELEMENTS=(
    status                  # exit code of the last command
    command_execution_time  # how long the last command took (>=2s)
    background_jobs         # background jobs
    direnv                  # direnv environment
    pyenv                   # global python version (the venv goes on the left)
    node_version            # node (only in node projects)
    rust_version            # rust (only in rust projects)
    go_version              # go (only in go projects)
    time                    # time of day
  )

  # --- LEAN style: no backgrounds and no powerline separators ---
  typeset -g POWERLEVEL9K_LEFT_SEGMENT_SEPARATOR=' '
  typeset -g POWERLEVEL9K_RIGHT_SEGMENT_SEPARATOR=' '
  typeset -g POWERLEVEL9K_LEFT_SUBSEGMENT_SEPARATOR=' '
  typeset -g POWERLEVEL9K_RIGHT_SUBSEGMENT_SEPARATOR=' '
  typeset -g POWERLEVEL9K_LEFT_PROMPT_FIRST_SEGMENT_START_SYMBOL=''
  typeset -g POWERLEVEL9K_LEFT_PROMPT_LAST_SEGMENT_END_SYMBOL=''
  typeset -g POWERLEVEL9K_RIGHT_PROMPT_FIRST_SEGMENT_START_SYMBOL=''
  typeset -g POWERLEVEL9K_RIGHT_PROMPT_LAST_SEGMENT_END_SYMBOL=''
  typeset -g POWERLEVEL9K_MULTILINE_FIRST_PROMPT_GAP_CHAR=' '

  # Remove the background from every segment I use (transparent)
  local seg
  for seg in OS_ICON DIR PROMPT_CHAR STATUS COMMAND_EXECUTION_TIME BACKGROUND_JOBS \
             DIRENV VIRTUALENV ANACONDA PYENV NODE_VERSION RUST_VERSION GO_VERSION TIME; do
    typeset -g POWERLEVEL9K_${seg}_BACKGROUND=
  done
  local st
  for st in CLEAN MODIFIED UNTRACKED CONFLICTED LOADING; do
    typeset -g POWERLEVEL9K_VCS_${st}_BACKGROUND=
  done

  # --- Colours per segment ---
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

  # status: show only the error (no green tick on every successful command)
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
  # The Python environment: (name) in green and bold. The p10k wizard left the
  # parentheses empty (VIRTUALENV_{LEFT,RIGHT}_DELIMITER in ~/.p10k.zsh), which
  # is why the name appeared on its own; they are put back here.
  typeset -g POWERLEVEL9K_VIRTUALENV_FOREGROUND=$green
  typeset -g POWERLEVEL9K_VIRTUALENV_LEFT_DELIMITER='('
  typeset -g POWERLEVEL9K_VIRTUALENV_RIGHT_DELIMITER=')'
  typeset -g POWERLEVEL9K_VIRTUALENV_CONTENT_EXPANSION='%B${P9K_CONTENT}%b'
  # conda already carries its parentheses inside CONDA_PROMPT_MODIFIER: they are
  # stripped (as ~/.p10k.zsh used to do) and ours are added, so that a conda
  # (base) and a uv (.venv) read exactly the same.
  typeset -g POWERLEVEL9K_ANACONDA_FOREGROUND=$green
  typeset -g POWERLEVEL9K_ANACONDA_CONTENT_EXPANSION='%B(${${${${CONDA_PROMPT_MODIFIER#\(}% }%\)}:-${CONDA_PREFIX:t}})%b'
  typeset -g POWERLEVEL9K_PYENV_FOREGROUND=$green
  typeset -g POWERLEVEL9K_NODE_VERSION_FOREGROUND=$green
  typeset -g POWERLEVEL9K_RUST_VERSION_FOREGROUND=$orange
  typeset -g POWERLEVEL9K_GO_VERSION_FOREGROUND=$blue

  typeset -g POWERLEVEL9K_TIME_FOREGROUND=$muted
  typeset -g POWERLEVEL9K_TIME_FORMAT='%D{%H:%M}'
  typeset -g POWERLEVEL9K_TIME_PREFIX=''

  (( ! $+functions[p10k] )) || p10k reload
}
