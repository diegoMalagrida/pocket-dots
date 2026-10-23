# hyprland-cursor — the plugin that tells the Pokémon where your mouse is

A plugin for [wl_shimeji](https://github.com/CluelessCatBurger/wl_shimeji).
Without it, the desktop pet **does not know where the cursor is** and the
chase-you behaviour sends it into the top-left corner, again and again.

## Why it is needed

Wayland does not let a client ask where the pointer is: it only finds out when
the pointer passes over one of its own surfaces. That is why wl_shimeji leaves
the global position to plugins — each compositor resolves it in its own way.

Inside wl_shimeji, `mascot.environment.cursor` is `(0,0)` **always**, except
while you drag a critter with the button held down: the only function that
writes that position is `environment_set_public_cursor_position()`, and its
only caller is the callback the daemon hands to plugins. No plugin, no cursor.

Here Hyprland is asked through its control socket, the same one
`hyprctl cursorpos` uses, twelve times per second (one tick out of every two).

## Build and install

You need wl_shimeji's development files (`/usr/include/wl_shimeji/` and
`libwayland-shimeji-plugins`), which come with the package.

```sh
make            # leaves hyprland-cursor.so right here
make instalar   # copies it to ~/.local/lib/wl_shimeji/
```

It is installed in `~/.local/lib` and not in `/usr/lib/wl_shimeji` —which is
where the daemon looks by default— so that it needs no `sudo` and is not lost
when the package is updated. In exchange you have to tell it where to look, one
line in `~/.local/share/wl_shimeji/shimeji-overlayd.conf`:

```
plugins_location=/home/YOURUSER/.local/lib/wl_shimeji
```

The daemon reads that file **at start-up**, so afterwards it has to be
restarted:

```sh
systemctl --user stop wl_shimeji.service   # the socket starts it again by itself
```

## Check that it is loaded

```sh
journalctl --user -u wl_shimeji.service --since '-1min' | grep Plugins
```

This has to appear:

```
[Plugins] "hyprland-cursor" by diego (...) of version 1.0 successfully initialized
```

If nothing appears, the daemon is still running from before or did not find the
`.so`. If a `Failed to initialize` appears, there was no Hyprland session: the
plugin checks that the socket answers **before** declaring itself good, so as
not to sit trying in vain on every tick.

## Implementation details

- It gives up after 20 connection failures in a row (the session may have
  changed). Better a critter that does not follow you than one that spends its
  time budget on retries: the daemon gives it 40 ms per tick and aborts the
  plugin if it overruns.
- It does not implement `wl_shimeji_plugin_move` or `_activate`: another plugin
  takes care of windows, here only the mouse matters.
- Licence GPL-2.0-or-later, like wl_shimeji, which it links against.
