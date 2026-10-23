#!/usr/bin/env bash
# Super+O: a Pokédex that recomposes itself when the Hyprland tiling changes.
exec python3 "$(dirname -- "${BASH_SOURCE[0]}")/pokemon-popup.py" "$@"
