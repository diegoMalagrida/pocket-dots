# dotfiles

My **Arch + Hyprland** desktop, kept as a repository.
Clone it on a fresh Arch install and one script brings the whole thing up: compositor, bar, theme, packages and services. Everything is recoloured from the wallpaper via pywal, so there are no hardcoded colours anywhere in the shell.

## Demo

A full run-through of the desktop.

[<video src="media/rice.mp4" controls width="600"></video>](https://github.com/user-attachments/assets/2b35a6fb-5a08-4539-99a9-7c525eb463b3)

## Install

```sh
git clone https://github.com/diegoMalagrida/dotfiles
cd dotfiles
./install.sh
```

Needs **Hyprland 0.56+** — the config is `hyprland.lua`, not `hyprland.conf`.

- `./install.sh --lang en` — bring the desktop up in English. It speaks Spanish
  by default, and you can switch either way at any time in Settings → Appearance,
  without restarting anything
- `./install.sh --dry-run` — see the plan, change nothing
- `./install.sh restore` — undo it
- `./diagnose` — what is missing or will not start

It never touches `/boot`, the bootloader or your partitions. Outside `$HOME` it writes only the twelve files in `system/etc/`, and asks before every phase that needs sudo.

## Licence

GPL-3.0 — see [LICENSE](LICENSE).
