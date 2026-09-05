# Quickshell system (diego's rice)

> 🇪🇸 [En castellano](README.md)

Hyprland + **live pywal** (`Colors.qml` watches `~/.cache/wal/colors.json` →
everything is recoloured when you change wallpaper, without reloading anything).

The top bar follows caelestia's **architecture** (`modules/drawers/`: one single
window, one single state, one single mask) but **not its looks**. Here another
idea is in charge:

> The notch is the only shape on the screen, and the desktop's entry point:
> panels unfold **out of it**. The bar is not a surface.

```
 Arch  ●━● ●   Kitty    ╭─ 18:01  Tuesday       󰂄 99% ─╮
                       ╰─         4 August              ─╯
```

- The bar **has no background**: no strip, no islands, no pills. They are loose
  glyphs over the wallpaper, with a subtle dark outline so they read the same
  over light and dark backgrounds.
- The notch is a **loose black island** stuck to the top edge, with the
  MacBook's inverted top corners. **The clock lives inside it**: that is what
  makes it mean something at rest instead of being a black hole.
- **At rest it measures exactly the reserved band (32 px)**, so it never covers
  a window. It only sticks out when you ask it to.

The four additions of 9 Aug 2026 —reading mode, battery health, cover-art
accent and enterprise wifi— come from ideas in
[`surface-dots`](https://github.com/snes19xx/surface-dots), but they are
reimplemented for this rice: no hardcoded BAT paths, no external palette
generator, no passwords in `argv` and no trampling of Hyprland's previous
state. Neither its shell nor its looks were copied.

## Settings (`SettingsWindow.qml`)
**It is not a notch panel, and that is deliberate.** The notch panels are
transient: you open one, you do one thing, it closes when you click outside.
A settings window is the opposite — you explore, you drag a slider and you want
to look at the terminal to see whether it worked. Closing on a click outside
would be hostile, and anchored at the top it would cover half the screen. So it
is a **real floating window** (`FloatingWindow`, xdg-toplevel), with the same
visual language as the notch and launched from it.

It opens with `Super+A` (A for Ajustes) or `Super+,` (like `Cmd+,` on macOS),
from the cog in the Control Centre, or `qs ipc call notch settings`.

**It always comes up floating, centred and contained (900x620).** That is not
the QML's decision: it is forced by a `windowrule` in `hyprland.conf` matching
`class org.quickshell` + `title Ajustes` (it is the shell's only real window;
everything else is layers). Without it Hyprland tiled it and it took up half the
screen. The QML carries the same size in `implicitWidth/Height` so there is no
big flash before Hyprland places it. If at some point you want it anchored,
`Super+V` by hand; opening it again brings it back floating and centred.
The width must not drop below 780: each row asks for 120 of label + 14 + 270 of
control, plus 224 of sidebar and the margins. The height can be smaller because
every section is a `Flickable`, but 620 px lets you read the Energy card whole
without having to guess that it carries on below.

| section | what it holds |
|---|---|
| Appearance | everything you used to have to edit in the QML: notch shape, behaviour, bar, typography, and the way into the wallpaper picker |
| System | brightness, night light, reading mode, battery with health/cycles/capacity/time left, caffeine, remote mode, wifi and EAP profiles, do not disturb and themed Pokémon |
| Sound | volume, mute and the choice of output/input device (native Pipewire, no pavucontrol) |
| Bluetooth | pair, connect, disconnect and forget (native Bluez, replaces the rofi one) |
| Shortcuts | the binds from `hyprland.conf`, parsed live and searchable (read only) |
| About | distro, kernel, compositor, shell, CPU, RAM, disk, uptime, packages and where each piece of the rice lives |

### Anatomy of the window
Four decisions that explain how it is built, and why you should NOT go back to
the previous design:

1. **A setting's description does not go under its label.** It used to, and each
   row was three lines tall: the original window fitted seven settings and
   Appearance was an endless scroll. Now the row is 42 px tall and the
   description travels to `ShellState.settingsHint`, which the window paints in
   a **fixed strip at the foot**, up to two lines, when you hover. Zero reflow,
   nothing covering anything, and a long explanation is not lost. Each row
   publishes it with `hint:`.
2. **Settings go in cards** (`SettingsControls.Card_`), rounded and with a
   hairline: law 1 of the shape language, round belongs to the shell. Before it
   was a flat list with 1 px separators that grouped nothing.
3. **The sidebar search box is global.** Type and that is it: it has the focus
   the moment the window opens, it ignores case and accents, it shows the number
   of results in each section and jumps to the first one that matches. `↑`/`↓`
   walk only those sections, `Ctrl+F` gets the focus back and `Esc` empties the
   search (and if it is already empty, closes the window). Each card hides
   itself if it has no rows left — and for that the rows publish `matches` apart
   from `visible`, because in QML `visible` is *effective* and a hidden card
   would make its rows say `false` for ever.
4. **The header does not scroll**: icon, title, description and the section's
   action (`actionText` / `actionRun`). There is a visible close too; `Ctrl+W`
   and `Esc` still work. The destructive "Reset" action demands a second press
   before it runs.

To make a row conditional use `shown:` (e.g. the island settings only in island
mode). **Never `visible:`**, which belongs to whoever filters the search.

### Persistence (`Config.qml`)
`FileView` + `JsonAdapter` over `~/.config/quickshell-rice.json`. Changes are
applied **live** (you move the slider and the notch changes) and save
themselves.

**The file lives OUTSIDE `~/.config/quickshell/` on purpose**: Quickshell
watches its configuration directory to hot reload, and saving in there would
fire a reload for every pixel of slider.

## Architecture
- **`ShellState.qml`** (singleton) — the hub: clock, active window, MPRIS,
  cover-art palette, Pipewire (volume), audio spectrum, brightness,
  battery/UPower/CPU/RAM, network,
  bluetooth, pacman, swaync, caffeine, **and the notch's state machine**.
  Zero UI.
- **`TopShell.qml`** — the single window: the notch shape, the mask, the bar
  contents, fullscreen handling.
- **`NotchContent.qml`** — what you see inside the notch in each mode.
- **`Config.qml`** (singleton) — persistent settings; what used to be baked-in
  constants.
- **Components**: `MediaPanel`, `BarItem`, `NotchSlider`, `SettingsControls`,
  `StyledText`, `PillButton`, `Card`.
- **Design**: `Colors` (pywal + semantic), `Appearance` (tokens), `Icons`.
- **Entrypoint**: `shell.qml` → `TopShell` + `SettingsWindow` + `MediaControls`
  + `WallpaperPicker`. (The fullscreen `Overview` was retired on 6 Aug 2026: it
  is now a face of the notch, `OverviewPanel.qml`.) Autostart:
  `quickshell.service` (user unit, supervised; NOT `exec-once` any more). To
  restart the shell use `systemctl --user restart quickshell`, not `pkill`:
  systemd would relaunch it anyway and you would end up with two startups
  fighting each other.

## Division of responsibilities

**Rule: every piece of data has ONE single place.** If something is in the
notch, it is not repeated in the bar.

**The notch** carries what is permanent and always there: time, date, battery,
media, volume and brightness (OSD when you change them + sliders in the panel),
the way into the computer status panel, and all the
controls (network, bluetooth, notifications, caffeine, wallpaper, lock, shut
down).

**The left bar**: Arch launcher (wheel = volume) · workspaces as dots (the
active one stretches) · app name in bold. None of this is in the notch.

**The right bar only shows exceptions** — what is NOT normal. On a quiet day it
is completely empty:

| item | when it shows up |
|---|---|
| systray | whatever the apps register |
| updates | only if there are any |
| notifications | only if there are any (with the count) or DND is on — click opens the Control Centre, right-click toggles DND |
| caffeine | only while it is on |
| bluetooth | only if something is **connected** (on-with-nothing is noise) |
| network | only if there is **no** network (being connected is the normal state) |
| volume | only if it is **muted** (the level is the notch's OSD job) |
| screen capture | only if something is capturing the **monitor** (a red dot that pulses) |

## The notch

| mode | trigger | what it shows | width × height |
|---|---|---|---|
| `launcher` | `Super+R` / click on the Arch logo | search box + application list | 660 × **fits the content** |
| `control` | click on the notch / `Super+D` / bell | vertical player + sliders + toggles + notifications | 1080 × 526 |
| `system` | Your computer button / `Super+Shift+D` | activity landscape + disk space, temperature and battery | 920 × 420 |
| `network` | "Network" chevron in the Control Centre / network icon | wifis, PSK, WPA-Enterprise profiles, on/off | 470 × 412 |
| `bluetooth` | "Bluetooth" chevron in the Control Centre | pair, connect, forget, on/off | 470 × 412 |
| `power` | `Super+Shift+E` / power key | lock · suspend · log out · restart · shut down | 520 × 158 |
| `notif` | a notification arrives | icon + summary + body + app (4 s) | 430 × 66 |
| `track` | song changes / play | cover + title + artist + visualiser (3 s) | 400 × 52 |
| `activity` | volume or brightness | OSD icon + bar + % (1.8 s) | 330 × 42 |
| `peek` | hover (with a 240 ms delay) | the same, growing: date with the year | 380 × 44 |
| `media` | there is music | cover + time + real spectrum (8 bands, cava) | 268 × **32** |
| `idle` | — | **just the time**, centred | 140 × **32** |

Gestures: **vertical wheel** = volume · **horizontal wheel** = change workspace
· **right-click** = play/pause · **click** = Control Centre.

The horizontal wheel (6 Aug 2026, idea adapted from Tide-island) **accumulates**:
a touchpad sends dozens of events per gesture, so without accumulating them a
short swipe would take you across the ten workspaces in one go; 120 units = one
step, which is Qt's wheel notch. It goes to `workspace e+1`, the same as the
`Super+wheel` of `hyprland.conf`: it jumps to the next one that **exists**, not
to the next id.

And **only this gesture** shows the `ws` face ("Workspace 3") in the notch. With
`Super+1..0` it deliberately does not: there you already know where you are
going because you have just typed the number, and the bar indicator is right
beside it. With the wheel there is no number to type and you are looking at the
notch, so it is the only case where the gesture needs an acknowledgement.

The two passive modes (`idle`, `media`) measure 32 = the reserved band: they
never invade the window below. The **240 ms delay** on hover stops the notch
unfolding just because the mouse went past it.

### Panels: the notch as the entry point
`ShellState.panel` (`""` / `"control"` / `"launcher"` / …) rules over the mode.
**Adding a new panel is three steps**: one more value in `panel`, its size in
`notchW`/`notchH`, and its layer in `NotchContent.qml`.

**Current panels**: `MediaPanel.qml`, `LauncherPanel.qml`, `ControlPanel.qml`,
`NetworkPanel.qml`, `PowerPanel.qml`, `BluetoothPanel.qml`, `OverviewPanel.qml`,
`CalendarPanel.qml`.

#### The calendar (`CalendarPanel.qml`)

One month, and nothing else. Two doors: its **tile in the control centre**, like
Network or Bluetooth, and **three fingers down on the trackpad**, the same hand
posture as the workspace gesture on the other axis. The tile is the door you can
see; the gesture is the quick one.

Opening it by clicking the notch clock — the macOS gesture — was tried first and
taken back out: that click had always opened the control centre, and taking a
gesture people already have in their fingers in exchange for a new feature is a
bad trade. Right-click is no good either: it is the player's play/pause.

The gesture lives **only in `hyprland.lua`**, because it uses a callback table
(`action = { finish = ... }`) that the classic `.conf` syntax does not have.

The grid is **always six rows**, even when the month fits in five, so the height
of the notch does not jump as you move between months. Month names and weekday
initials come from `ShellState.loc`, which follows the language, so the calendar
translates itself and starts the week wherever the locale says. Its only string
of its own is the “Today” button, which exists only once you have left the
current month.

It was asked for with notes alongside it (a YouTube comment). **The notes were
deliberately dropped**: every face of the notch is a view onto something the
system already knows, and notes would make the shell the owner of the user's
data, with the backups, the corruption and the migrations that follow. A
calendar, by contrast, is a view onto time.

#### The workspace map (`OverviewPanel.qml` + `OverviewWindow.qml`)

`Super+Tab`. Ten cells (5x2, exactly the workspaces of `Super+1..0`), each one
the usable area of the screen at 0.14 scale, with the wallpaper underneath and
the windows placed **where they really are**: a small floating window comes out
small and off-centre. It is a MAP, not a list.

**The thumbnails can be dragged.** Dropping one in another cell is
`movetoworkspacesilent`; dropping a floating one inside its own cell is
`movewindowpixel exact`, which means windows can also be repositioned within a
workspace. Click = go to that window · right-click = close it (a close request,
the app may ask to save) · middle-click = floating/tiled · click on the empty
part of a cell = go to that workspace. With the keyboard: arrows, Enter, `1..0`
and Esc. The strip at the foot shows the title of the one you are pointing at
(at this scale it does not fit written on top, and it would cover the window).

It replaced an `Overview.qml` that took the whole screen and showed the windows
in a loose grid. The problem was not aesthetic: **a grid does not tell you which
workspace each thing is on**, which is the only thing you want to know when you
press `Super+Tab`.

**Four things that were hard and do not show when you read the code:**

1. `toplevel.address` comes **without** the `0x` and Hyprland's dispatchers
   demand it. Without the prefix every dispatch answers `moveWindow: no window`
   and the drag does nothing, **silently**.
2. `toplevel.workspace` is kept up to date by Quickshell on its own, but
   `toplevel.lastIpcObject` —where `at` and `size` come from— stays **frozen**
   until somebody calls `Hyprland.refreshToplevels()`. Measured. That is why
   there is a timer that asks for it **only while the overview is open**.
3. The thumbnail is tied to the area of its cell (`Math.min(cellW - tw, …)`),
   and that is why the cell does not need to clip. Clipping would need **two**
   copies of each window (one inside, clipped, and another free to drag), with
   twice the captures: you cannot drag out of a box something that the box
   clips.
4. The model goes through `ScriptModel`. A `Repeater` over a new array destroys
   and recreates its delegates, so every drag would switch the ten captures off
   and on again, with a flicker. `ScriptModel` compares by identity.

While it is dragged the window is given an **optimistic** position (`posHint`)
that retires itself as soon as the real data agrees: Hyprland takes ~100 ms to
confirm, and without the lie the thumbnail would jump back to the old place only
to jump to the new one afterwards.

The **launcher** (`LauncherPanel.qml`) replaces rofi: fuzzy search over
`DesktopEntries`, icons through `Quickshell.iconPath()`, Enter launches, Esc
closes. Keys: ↑/↓, `Ctrl+J/K`, `Ctrl+N/P`, `Tab`/`Shift+Tab`, `Home`/`End`,
`PgUp`/`PgDn`.

**The height fits whatever is there.** If you search and three apps come up, or
if it is a sum, the panel shrinks upwards instead of leaving a black gap
underneath. `LauncherPanel` publishes the number of rows in
`ShellState.launcherRows` and `launcherH` works out the height. Measured: 49
apps → 409 px · 3 apps → 217 · calculator only → 135 · no results → 119.

**Careful with `launcherChrome`**: that constant (73) has to match EXACTLY the
margins of `LauncherPanel.qml` (4 + 50 + 1 + 6 + 12). The first version used 54
and left 19 px out, so the list got less height than its rows took up and **the
last one showed up clipped**. If you touch those margins, update the constant.

**It is a calculator too.** If what you type is a sum, a row with the result
appears at the top and **Enter copies it to the clipboard** (native, through
`Quickshell.clipboardText`, no `wl-copy`). The notch confirms with a brief
toast —here it is needed, because copying has no other sign of having happened.
It supports `+ - * / ^ % ( )`, comma or full stop for decimals, `pi`, `e` and
the usual functions (`sqrt`, `log`, `sin`…). A leading `=` forces calculator
mode.

So that it does not fire at just anything, there has to be **a number and an
operator**, and every word has to be in the whitelist: that way `7zip`,
`firefox` or `code 2` do not trigger the calculator. Also checked that
`0.1+0.2` gives `0.3` and not `0.30000000000000004` — the result is rounded to
10 decimal places before it is shown.

**It is built for the keyboard, and the mouse must not get in the way.** When it
opens the keyboard is always in charge, even if the pointer is right on top of a
row. The only criterion for the mouse to take over is that the **pointer moves**
(`pointerMoved()`), which tells apart the two cases that were annoying:

- when it opens, Wayland delivers an event because the pointer "enters" the
  newly created surface, even if the mouse is standing still → the first event
  only sets the reference and selects nothing;
- while you type, the list refilters and the rows pass under a still cursor,
  firing `onEntered` → same point, so it does not count.

A time-based guard is no good: the enter event arrives **after** the layer is
reconfigured by the `keyboardFocus` change, so it slips in behind any reasonable
arming window. The scoring favours an exact prefix of the name, then a word
prefix, then a substring, and as a last resort a subsequence — typing "kit" puts
`kitty` first.

The **Control Centre** (`ControlPanel.qml`) replaces swaync's **and the old
Sidebar/dashboard**. On the left: media, volume and brightness sliders, seven
toggles (network, bluetooth, do not disturb, caffeine, night light, remote and
Pokémon) and a door labelled “Your computer”. On the right: the notification
history.

The **Your computer** panel keeps 60 samples of the same `sysstats.sh` that was
already feeding the Control Centre (90 seconds, without a second parallel poll):
it overlays CPU and RAM in a single landscape and leaves disk space, temperature
and battery as three quiet readings off to the side. The current wallpaper comes
in at very low opacity as ambient light; there is no grid, no cards and no
admin-panel look. The back button returns to the Control Centre without closing
and reopening the surface.

The **pokéball** toggles the terminal's themed sprites: with it on, the Pokémon
that comes up when you open the first kitty is picked from the ones that go best
with the pywal palette; off, you get a random one again, which is how it used to
be. It is a switch over `~/.local/bin/poke-theme` (`on`/`off`/`is-on`, same
treatment as remote mode: the real state is whatever the script says, nothing is
guessed here). The bias is applied by `poke_theme_pick()` in `~/.zshrc`, which
**only picks the file** — drawing the sprite is not touched from here.

When the Sidebar was retired there were only two things of its own that were not
already here —**the weather** (`wttr.in`, every half hour) and **disk usage**—
so they were migrated to `ShellState` before removing it. The disk already came
in `sysstats.sh`, it was only a matter of reading field 9.

The Network and Bluetooth cards in the Control Centre are **one single zone**:
pressing anywhere on them opens the dedicated panel. They carry no chevron and
no tiny separate target; the switch to turn it on or off is in the header of the
panel itself. The other cards (do not disturb, caffeine, night light…) still act
directly when you press them.

`BluetoothPanel.qml` is `NetworkPanel.qml`'s sibling: same skeleton and same
treatment. If the adapter is **blocked by rfkill** it says so and disables the
switch, instead of pressing it going nowhere with no explanation
(`BluetoothAdapterState.Blocked`).

The **network picker** (`NetworkPanel.qml`) replaces the rofi menu. It
discovers, sorts and connects through `Quickshell.Networking`: wifi switch,
sorted list (connected → saved → by signal, with repeated SSIDs collapsed into
the one with the best signal), and a PSK password is asked for **by unfolding
the row itself**, not in another window. The 802.1X variants (WPA/WPA2-EAP,
Suite B, LEAP and dynamic WEP) are detected separately: a saved one connects
with its profile and shows a pencil to edit it; a new one opens
`nm-connection-editor`. It is deliberate: Quickshell's QML does not expose
identity, EAP method or certificates yet, and building an
`nmcli ... password ...` would leave the secret visible in the process list. The
editor also supports PEAP, TTLS and EAP-TLS, not just one baked-in case.
`scripts/wifi-enterprise.sh` (`~/.config/hypr/`) resolves the UUID by **exact
SSID** without reading or printing identity or key.

The wifi scan and the bluetooth discovery only run while their panel is open, so
as not to have NetworkManager and Bluez sweeping the air the whole time. They
are driven by **declarative `Binding`s**, not by `onPanelChanged`: the
imperative handler only fired when the panel changed, so if you turned bluetooth
on *from inside its own panel* the discovery never started.

The thresholds of the signal icon are 72/48/24 and not the "classic" 75/50/25:
in practice the signals fall between 30 and 60 and with the textbook split they
all came out with the same icon.

The **power menu** (`PowerPanel.qml`) replaces wlogout, which took the whole
screen. It always starts on "Lock" — the least destructive one — so that an
accidental Enter does not shut your laptop down. ←/→ or Tab move, Enter
confirms, Esc closes.

**Our own notifications**: Quickshell is now the D-Bus server
(`NotificationServer` in `ShellState.qml`), because swaync's panel was a GTK
window of its own and could not be put inside the notch. When one arrives the
notch stretches and shows it for 4 s as a live activity; afterwards it stays in
the Control Centre's history. `swaync.service` is left **disabled**.

**Keyboard focus**: the layer goes to `WlrKeyboardFocus.OnDemand` only while the
launcher, the power menu or the network picker are open; the rest of the time it
is `None` so as not to steal the keyboard from the windows.

**`OnDemand`, never `Exclusive`.** With `Exclusive` the focus stays stuck to the
layer and Hyprland stops cancelling the `HyprlandFocusGrab`, so **a click
outside no longer closes the panel and you are trapped inside**. With `OnDemand`
it is the grab itself that forces the keyboard focus (you can type without
clicking) and clicking outside cancels it and the panel closes. Verified by
measuring the width of the notch: with `Exclusive` a click outside left the
launcher open; with `OnDemand` it closes.

**Every panel must answer `Escape`.** On top of that, the notch's `Item` in
`TopShell.qml` carries a `Keys.onEscapePressed` as a safety net: if a panel does
not answer it, the key bubbles up there and closes it anyway. No panel can leave
you locked in.

**A trap that took some finding**: when `keyboardFocus` changes the layer is
reconfigured and Hyprland **cancels the `HyprlandFocusGrab` instantly**, so the
panel closed itself the moment it opened. That is why the grab is armed with a
400 ms delay (`grabArmed` in `TopShell.qml`), once the layer has settled.

### Two-pole structure
The content of the notch is always anchored the same way so that **nothing
jumps** when the state changes: **left** the clock, **right** whatever is
contextual (battery at rest and on hover, cover + peaks with music). Hovering
does not move anything: it only grows and the date is written out in full.

### The visualiser (the little bars)
**Real spectrum, 8 bands, from bass to treble.** It comes out of **cava**
(`scripts/cava.conf`, `raw`/ascii output to stdout) which `ShellState.qml` reads
line by line and publishes in `ShellState.levels`. It runs **only while
something is playing** (`running: mediaLive`, ~4 % of a core) and on pause it
leaves the array at zero so the bars are not left nailed in place during the
fade.

This used to be a `PwNodePeakMonitor` and **it did not work**: it gives ONE
number (the sink's global peak) that was shifted along the array, so all the
bars were the same signal repeated and, since the linear peak nearly always
brushes 1, they stayed glued to the ceiling — a barcode, not a visualiser. On
top of that `onPeakChanged` only fires when the value **changes**: in a
compressed passage the signal stopped arriving and the bars froze.

**Few and thick**: 8 bars of 4 px with a 4 px gap (a 60 px strip). With 14 of
2.5 px it read as a striped pattern, not as an equaliser. The floor of the
height is the width of the bar, so at rest they are 8 round dots. If you change
`ShellState.bands` you have to change `bars` in `cava.conf`: they are the same
number. The vertical player of Super+D reuses those eight bands, but widens them
to 6 px and gives them 58 px of travel so they work as a visual finish.

Two knobs for the feel: `noise_reduction` in `cava.conf` (0 jittery ↔ 100
mushy; 70 right now) and the parsing gamma in `ShellState.qml` (0.6 — without it
the treble is so small next to the bass that you cannot see it move in 18 px).
**No `Behavior on height`**: cava already filters the signal at 60 fps with its
own gravity fall, and a 90 ms animation that never gets to finish only flattens
the travel. If `cava` is missing from the PATH the bars stay flat.

### The clock
At rest the notch shows **just the time**, centred, in a narrow pill: it is as
minimal as it gets without leaving it empty. On hover it grows and the full date
with the year and the battery appear — nothing is lost, it only moves to where
it is needed. With music the clock steps aside to the left to make room for the
cover and the peaks.

The date and the battery at rest can be turned back on in Settings › Appearance.
And the width **adapts on its own**: `Config.idleW` is the width for the time
alone, and `ShellState.idleW` adds room for each element you switch on. If it
were a fixed width, turning the date back on would clip the content.

**Two type families, on purpose**: `Appearance.font` (JetBrains Mono Nerd Font)
for the bar and for EVERYTHING that draws icons — the glyphs only exist in that
family. `Appearance.fontUI` (Adwaita Sans, based on Inter) for the text inside
the notch. A date in monospace looks unravelled: the letters are spaced like the
digits and it looks like it came out of a terminal. The clock uses
`font.features: { "tnum": 1 }` so that the digits do not dance when the minute
changes.

Careful: in QML the `font` type **has no `families`** (only `family`), even
though QFont does have it in C++. Assigning it blows up the whole load.

### Motion
**One single language for everything that moves**, with the tokens in
`Appearance.qml` (`mShape`, `mIn`, `mOut`, `mStagger`, `mQuick`…). The shape is
the reference and the content has to feel like part of it, not like something
stuck on top.

The key piece is **`NotchLayer.qml`**: each "face" of the notch (rest, hover,
OSD, each panel) is a `NotchLayer`, and they all cross over in the same way. The
transition is **asymmetric on purpose**:

- what leaves goes in **110 ms**, half of what the new thing takes to come in;
- what comes in **waits those same 110 ms** (`mStagger`) for the gap to be free,
  and arrives with the same elastic curve as the morph of the shape
  (`OutBack`), growing from 96 %.

If both layers last the same they overlap at 50 % and you see a smear; with the
staggered handover the shape goes first and the content follows it. The content
settles at ~320 ms and the shape at 440, so it is never lagging behind.

**Never animate a derived width.** The volume and brightness bars had a
`Behavior on width` over a width that is `track × fraction`. When the panel
opens the notch widens, which means the track grows, and the bar spent 140 ms
chasing it: it looked like it was filling itself up like a progress bar. The
rule is to animate the **value** (`property real shown` with its `Behavior`) and
work out the width from it with no animation: that way resizing is instant and
only a real change of volume or brightness is animated. It applies to
`NotchSlider`, to the OSD bar and to `SettingsControls.Slider_`.

Before, every layer used `NumberAnimation` **with no curve**, that is, linear
interpolation, the least fluid thing there is. And inside the rest layer the
date, the battery and the cover appeared and disappeared **all at once** when
music started playing; now they fade.

### Two styles: Notch and Island
`Config.notchStyle` switches between the two, live from Settings › Appearance:

- **`notch`** — stuck to the top edge, with the MacBook's inverted top corners.
  It is a `Shape` path with béziers.
- **`island`** — a floating pill detached from the edge and rounded on all four
  sides, like the iPhone's Dynamic Island. Here no `Shape` is needed: it is a
  `Rectangle` with `radius`. The gap (`Config.islandGap`) comes **out of the
  reserved band**, so the island does not cover windows either.

### Details of the shape (notch mode)
`fl` (inverted top corner) = 13, `rb` (bottom radius) =
`min(30, height - fl - 1)`, with bézier `k = 0.5523`. Inside `Path` elements
**there is no `parent`** → everything is referenced through the id of the
`ShapePath` (`sp`).

### Fullscreen
With a fullscreen window the surface slides upwards and the mask is emptied. The
layer is `WlrLayer.Top`, not `Overlay`, so that rofi / wlogout / hyprlock come
out on top of it.

### The mask
It covers **only** the notch and the two groups of glyphs, not the whole band:
the rest of the top edge lets the mouse through, because the bar is not a
surface.

## Colours
`Colors.c1..c5` come from pywal and **change with the wallpaper**: `color2` does
not have to be green. For states that mean something there are **fixed**
colours: `Colors.ok`, `Colors.warn`, `Colors.crit`. (With a blue wallpaper, the
battery charging came out red and looked like an alarm.)

Music is the contextual exception. `ColorQuantizer` reduces the active cover to
eight tones and `ShellState.mediaAccent` picks one that is saturated and
readable over black. That accent travels to `MediaPanel`, to the floating player
and to the notch's two music faces; it changes with a colour animation when the
song changes. If MPRIS publishes no cover, it is still loading or the image is
nearly monochrome, it falls back to `Colors.accent`: pywal is still a complete
fallback, there is never an invalid colour nor an external palette process.

Careful too with `font.capitalization: Font.Capitalize`: it capitalises EVERY
word and in Spanish it leaves "Martes, 4 De Agosto". Use
`ShellState.capitalize()`.

## The language (Spanish and English)

The shell speaks Spanish and English. The layer is three files: `I18n.qml` (the
singleton with `I18n.tr(...)`), `translations-en.js` (the English dictionary,
402 entries) and `tools/i18n-check.py` (the review).

**Spanish is the code.** The strings are still written in Spanish inside each
`.qml`, wrapped in `I18n.tr(...)`, and **the dictionary key is that same Spanish
string, literally**:

```qml
label: I18n.tr("Brillo")
hint: I18n.tr("El mismo brillo que las teclas de función.")
```

There are no symbolic keys (`settings.brightness.label`) on purpose: this way
the code reads by itself, a `grep` of the phrase you see on the screen takes you
to its place, and **whatever is missing from the dictionary comes out in Spanish
instead of coming out empty**. A visible failure, but a harmless one.

The placeholders are `{0}`, `{1}` and `{2}`, and the sentences **are not
concatenated**:

```qml
// wrong: in another language the pieces go in another order
text: "Quedan " + n + " minutos"
// right
text: I18n.tr("Quedan {0} minutos", n)
```

`tr()` takes up to three arguments and substitutes them in place, so the
translation can put the placeholders in whatever order its own language asks
for.

**Why not `qsTr()` with `.ts` files**: the Qt Linguist flow makes you compile
the `.ts` into `.qm` and restart the application to change language. Here
`I18n.lang` is a property, and since every `text: I18n.tr(...)` is a binding
that depends on it, changing language repaints the whole interface in place,
without restarting anything.

**And why a `.js` and not another QML singleton**: it was tried with a
`Translations.qml` exposing `readonly property var en: ({…})` with the 402
entries inside, and at runtime it arrived **undefined** —
`TypeError: Cannot read property '...' of undefined`; before that, with no
explicit import, `ReferenceError: Translations is not defined`. A JS file with
`.pragma library`, imported explicitly (`import "translations-en.js" as Dict`),
works, copes with the size and diffs better into the bargain. Do not take it
back to QML.

### Choosing the language

`Config.language` is `"es"` (the default) or `"en"`, and it is saved in
`~/.config/quickshell-rice.json` along with the rest of the settings. It is
chosen in three ways:

- when installing, with `./install.sh --lang en` (without the option the
  installer asks);
- live, in **Settings › Appearance › Shell language** — the change is immediate
  and it touches neither the language of the system nor that of the
  applications, only the shell;
- by hand, writing `"language": "en"` into the JSON.

`ShellState.loc` follows `Config.language` (`es_ES` / `en_GB`), so the dates and
the numbers of the shell change format with it. `Config.reset()` deliberately
does not touch `language`: restoring the factory values should not leave your
desktop in a language you cannot read.

### Adding a language

1. Add the code and the label to the `languages` list in `I18n.qml`. **The label
   goes in its own language** (`Français`, not `French`): whoever opens the
   shell in a language they cannot read has to be able to find theirs in the
   list.
2. Copy `translations-en.js` into `translations-XX.js` (same `.pragma library`,
   same Spanish keys) and translate the values.
3. Import it in `I18n.qml` next to the other one
   (`import "translations-fr.js" as DictFr`) and make `tr()` look at it. Today
   the line is binary (`root.english && Dict.en[s]`); with three languages it is
   solved by picking the dictionary by code and leaving Spanish as the fallback
   when there is no entry.
4. If the language writes dates in another way, translate the format keys too
   (`d 'de' MMMM`, `d 'de' MMMM 'de' yyyy`) and add its locale to
   `ShellState.loc`.
5. Run `tools/i18n-check.py` over it and add the new code to `install.sh`
   (`--lang`), which today only accepts `es` and `en`.

### The Hyprland shortcuts

`SettingsShortcuts.qml` reads the `bind =` lines of
`~/.config/hypr/hyprland.conf` and **puts the comment of each line through
`I18n.tr(comment)`**. So the Spanish comment in the `.conf` is the dictionary
key, the list of shortcuts comes out in English and **the Hyprland
configuration does not have to be touched**: it is diego's, and it stays in
Spanish on purpose.

Those keys never appear as `I18n.tr("literal")` in any `.qml`, so
`tools/i18n-check.py` collects them separately by reading `hyprland.conf`
itself; otherwise it would take them for dead entries and somebody would end up
deleting them.

### The review

```bash
cd ~/.config/quickshell && python3 tools/i18n-check.py
```

It checks the four ways of breaking this: wrapped strings that are not in the
dictionary (they would come out in Spanish), dictionary entries nobody uses any
more, `{0}` placeholders that get lost or invented in the translation, and
visible literals (`text:`, `label:`, `hint:`…) that are still not wrapped. It
exits 0 if everything is fine and 1 if there is something to look at. The
deliberate exceptions —the window title “Ajustes”, which is what the
`windowrule` matches, or the language labels— are listed inside the script with
their reason.

## Battery health

The quick percentage row still comes out of `sysstats.sh`; the details in
Settings come out of `Quickshell.Services.UPower`, which already delivers stable
units: health (% of the factory capacity), current full charge (Wh), draw (W)
and time to empty or to full. The design capacity is derived from health +
current capacity. The only figure UPower does not expose in QML, the cycles, is
read from `/sys/class/power_supply/<battery>/cycle_count`; `<battery>` comes
from `UPowerDevice.nativePath`, not from assuming `BAT0` or `BAT1`. If the
firmware does not publish a field, its row is hidden or says “calculating”,
without inventing a zero.

## Quick settings
In `TopShell.qml`: `notchColor`, `sideMargin`, `flare`, `roundMax`, and
`scrimAlpha` (0 by default = a 100 % transparent bar; raise it to ~0.35 if with
very light wallpapers you cannot read the glyphs).
In `ShellState.qml`: `bandH` and the sizes of each mode (`notchW` / `notchH`).

## The satellite bubble

A small body that peeks out **from behind the right edge of the notch** while
there is something running in the background. It lives in `TopShell.qml` (the
drawing) and `ShellState.qml` (`bubble*`, data and priority).

**Why a satellite and not another face of the notch**: at rest the notch
measures exactly the reserved band and cannot grow by itself — that is the rule
that keeps it from ever covering a window. A countdown lasts minutes, so it does
not fit in there without breaking it. A separate body does: it is born behind
the edge, it stays **inside** the band (28 of 32 px) and the notch goes on
measuring the same.

It is a **generic slot**, not a timer. Today two things fill it and putting in a
third one is one more line in `bubbleKind`:

| who | what it shows |
|---|---|
| timer | a ring that empties + `mm:ss` on hover |
| `pacman --refresh` | a spinning arc (indeterminate) + "Syncing" |

Three details that do not show when you read the code:

1. **It is declared BEFORE the notch**, which means the notch paints over it. It
   is not an oversight: when the notch grows (an OSD, a panel, the workspace
   map) it swallows the bubble, and when it shrinks the bubble peeks out again.
   That is the whole metaphor — something that was behind — and it comes for
   free, without a single line hiding anything.
2. **Its place is measured against the notch AT REST.** If it followed the live
   edge, opening the workspace map (1396 px) would send it flying to the other
   end of the screen and back.
3. **In the mask it goes by coordinates, not by `item:`**, so that it can
   measure ZERO when there is nothing. With `item:` the mouse zone would still
   be there, invisible, and you would lose your clicks on a piece of desktop
   next to the notch.

Click pauses/resumes · right-click cancels · when it goes off it stays red with
"Time's up" until you dismiss it. The end alert is a plain `notify-send`: since
**we are the notification server**, it comes back round and shows up in our own
notch, and on the way it stays in the Control Centre's history.

### The timer is started from the launcher

Type a duration (`10m`, `25 min`, `1h`, `1h30`, `90s`) and the **same
highlighted row as the calculator** offers the countdown; Enter starts it. It
goes there and not in a new shortcut because the launcher is already where you
type things that are not application names — the calculator opened that door.

**It demands a unit on purpose**: a bare `5` is a search. If the launcher
offered a countdown with any number it would get in the way of every search that
starts with a digit, which is the same reason why the calculator has a whitelist
and does not fire at `7zip`.

## Somebody is capturing your screen

A red dot pulsing in the right bar (where the exceptions live) while something
is capturing the monitor. It comes out of Hyprland's `screencast` event, with no
C++ at all.

**Two things measured on this machine that make it non-trivial:**

```
grim (screenshot)   → screencast 1,monitor  …  0,monitor
region recording    → screencast 1,region
YOUR OWN overview   → screencast 1,window   (one per window)
```

That is why only `monitor` and `region` count: counting everything, the "you are
being recorded" warning would light up **every time you press Super+Tab**. And
that is why there is a 1.5 s wait before lighting it: a screenshot with `grim`
opens and closes the capture in less than half a second, and a red flash exactly
when you take a screenshot is precisely what you do not want.

## The launcher is the command centre

`LauncherPanel.qml` no longer searches only applications. **The first character
decides what is searched**:

| prefix | mode | what Enter does |
|---|---|---|
| *(nothing)* | applications · calculator · timer · favourites | launches the app |
| `#` | clipboard history (text **and images**) | leaves it in the clipboard |
| `>` | system actions | runs it |
| `@` | open windows | jumps to it (changing workspace if it has to) |

**The prefix is consumed**: as you type it, it disappears from the field and in
its place comes a label with the name of the mode. If it stayed written there
would be two things saying the same, and the field would start with a character
that is not part of what you are searching for. You get out with **one backspace
on the empty field**, which is where the hand goes by itself when it wants to
undo.

With the field empty in applications mode, the three prefixes are written on the
right, where the result counter used to go. The counter said “there are 49
applications”, which is not a fact anybody needs; as soon as you type a letter
it comes back, and there it does mean something.

**Why prefixes and not four shortcuts.** Shortcuts have to be remembered with
the fingers and each one opens a window that is learned separately. A prefix
discovers itself, it is corrected with a backspace, and above all: the habit
stays a single one, `Super+R` and type. It is also the door the calculator
opened — typing `2+2` was already typing something that is not an application
name —, so the calculator and the timer stay **without a prefix**: they are not
a mode, they are what happens when what you type turns out to be a sum or a
duration.

**With this the last two rofi menus leave the rice.** There are none left.

### `#` clipboard

The data is served by `scripts/cliphist-tool.sh` (`list` / `copy <id>` /
`delete <id>`), which replaces the pair `~/.config/rofi/cliphist-menu.sh` +
`cliphist-paste.sh`. Here the QML **decodes nothing**: an image entry is a
binary, and putting binaries into a QML string is asking for something to break
silently. The script delivers TSV with `id`, type, thumbnail path and label.

- The thumbnails are cached by `id` in `~/.cache/cliphist/thumbs/` (cliphist's
  `id` is not reused, so a cached thumbnail cannot end up pointing at another
  image).
- The **150** most recent entries are served, with a preview of **200**
  characters. That width is the real limit of the search: you can only find what
  is in the preview.
- **`Del` deletes the entry without closing the panel** (or right-click, or the
  bin on the highlighted row). Rofi could not: choosing closed the menu.
  Clearing the history is exactly the task where you want to keep looking at it.
- The script **does not call `grep`, `sed` or `tr`**. With a fork per line and
  field it took 0.56 s with the thumbnails already cached, and that runs every
  time you open the mode; with bash pattern matching it drops to **0.06 s**. It
  does not use `cliphist list | head` either: with the pipe, `head` closes the
  tap, cliphist dies of SIGPIPE and the script ends in 141 because of
  `pipefail` — a fake failure that sooner or later gets read as a real one.

### `>` actions

The list that used to be in `~/.config/hypr/scripts/menu.sh`, plus what that
menu could not offer because it lived outside the shell: **Settings, workspace
map, do not disturb and coffee**. The ones with a native equivalent no longer
call an external program: “Wifi” opened `kitty -e impala` and now opens
`NetworkPanel`; “Shut down” opened `wlogout` and now opens `PowerPanel`.
Launching a terminal to touch the wifi with the panel right there was a leftover
from an earlier era.

**Reading mode** lives here too: search for `>reading`. It gets no new shortcut
—`Super+D` is still the Control Centre— and it can also be toggled in Settings ›
System. `reading-mode.sh` first captures Hyprland's real shader, animations,
blur and shadows; on the way out it restores those same values. The shader
carries warm paper, ink, static grain and minimal dither. Wallpaper, pywal and
brightness are deliberately left out.

The ones that stay inside the shell **change face without closing** (closing and
reopening in the same instant makes the whole notch flicker); the ones that go
outside close first, because several of them freeze the screen or ask for a crop
and would do it with the panel inside the photo.

### `@` windows

It is read from Hyprland and not from Wayland's `ToplevelManager` because the
**workspace** of each window is needed, and only the compositor knows that. Each
row shows icon, title, class and a pill with the workspace (highlighted if it is
the active one): jumping here can change your workspace and it is worth knowing
beforehand.

Two traps inherited from the overview, in case anyone has to come back: the
`address` comes **without the `0x`** and the dispatchers demand it (without the
prefix `focus` answers “no window” silently), and the jump **closes first and
asks for the focus 60 ms later**, because when the panel closes Hyprland gives
the focus back to the previous window and without that gap it is not guaranteed
who arrives last.

`winTick` exists because `Hyprland.toplevels.values` reports when a window is
born or dies but **not** when its title changes: without it, searching for
“github” would not find the tab you have just opened in a Chrome that was
already running.

### Who picks the delegate

**The data** picks it, not the mode (`root.listKind` looks at the `kind` of the
first row). It is not theoretical: `mode` is a binding declared at the top of
the file and the results are reloaded by a `Connections` declared further down,
so when the mode changes Qt updates the binding first and the handler
afterwards. In that one-frame gap the list repainted with the **new** delegate
and the **old** data —the window delegate got applications and asked for fields
that do not exist— and five `TypeError`s came out in the log for every `@` you
typed. By asking the first row, that cannot happen, because the answer changes
at exactly the same time as the data.

## Launcher favourites

A pinned row of icons right at the top, **only with the field empty** (and only
in applications mode): as soon as
you type, the search takes over and the row disappears so as not to take room
from the results.

| | |
|---|---|
| pin / unpin | the **star** on each row, **right-click** on it, or **Ctrl+D** on the selected one |
| launch | click on the icon, or **Ctrl+1..9** |
| reorder | **drag** the icon; the vertical mark shows where it is going to land |
| remove | right-click on the pinned icon |

They are saved in `favApps` in `~/.config/quickshell-rice.json`, **by the `id`
of the `.desktop` entry** and in order. By `id` and not by name because the `id`
is constant: renaming the app or changing the desktop's language must not lose
you the favourite. An `id` that no longer exists (an uninstalled app) is ignored
when resolving, so the list cleans itself up without saying anything.

That the list has ORDER and is not a set is what makes `Ctrl+1..9` mean
something: the position becomes a shortcut that is learned with the fingers, and
that is why it can be reordered.

**Drag trap**, in case it ever has to be touched: the order that is painted
(`favShown` in `LauncherPanel.qml`) belongs to the panel, not to `Config`. While
you drag, what is saved does not change. If the file were written at every
pixel, the whole list would repaint and the delegates would be recreated right
under your finger, killing the gesture halfway. It is only confirmed on release,
and `favDrag` is cleared **before** touching `Config` so that `syncFavs()` can
repaint.

## Pairing over Bluetooth

Quickshell knows how to pair (`Bluetooth.pair()`) and knows how to tell you it
is at it, but **it does not know how to answer** what BlueZ asks halfway through
the pairing:

```
"does the code 418293 match the one you can see on the device?"
"type 418293 on the keyboard and press Enter"
```

Those are not signals: BlueZ calls methods on a D-Bus object that the desktop
has to **export**, and from QML a D-Bus object cannot be exported — Quickshell's
Bluetooth API has no agent callback at all. With nothing to answer, headphones
pair all the same (they ask nothing) but **a keyboard or a gamepad fails
silently**: no error, no warning, it simply does not pair.

`scripts/bt-agent.py` is that object, supervised by
`~/.config/systemd/user/bt-agent.service`.

```
BlueZ  --(SYSTEM bus)------->  Agent1  --> qs ipc call notch btask …
                                  ^                        |
                                  |                  the notch asks
                                  |                        |
    org.quickshell.BtAgent1.Reply(b) <-- busctl --user <-- your click
```

Two buses on purpose: BlueZ lives on the system one and calls back the object we
register there; the notch lives on the session one and must not be able to touch
anything of the system's. The only bridge is that process.

**The notch's face goes in front of even an open panel.** It is the only one
that breaks that rule, and it is not a whim: it is not a notice, it is a
question with an expiry date and a device waiting on the other side of it.
Behind whatever panel you had open, the pairing would expire without you ever
getting to see it.

Two shapes: **`confirm`/`authorize`** bring two buttons (Yes / No), and
**`display`** brings none — BlueZ makes the code up and you type it on the
keyboard; the little progress bar goes up with each key, and it is the only sign
that the keyboard is really talking to the machine.

If nobody answers within 45 s it rejects itself. Without that, an unattended
prompt would leave the face nailed in front of everything. For the same reason
the agent sends `btclear` when it dies: stopping the service with a question on
screen takes it away.

**What this agent does NOT do**, said out loud instead of failing quietly:
`RequestPasskey` and `RequestPinCode` (the cases where you have to type *here* a
number that the device shows) are rejected with a visible warning, because they
would need a text field with focus. That is not the case for keyboards or
gamepads.

**Careful with blueman.** There is a `~/.config/autostart/blueman.desktop`, but
Hyprland does not process the XDG autostart, so it does not run. If it ever did,
`blueman-applet` would register its own agent and would take the default one.

## IPC and shortcuts
```
qs ipc call notch bright up|down          # changes the brightness AND shows the OSD, with no lag
qs ipc call notch osd volume|brightness|track|charge|ws|toast|notif
qs ipc call notch timer 10m|1h30|90s|stop # timer -> satellite bubble
qs ipc call notch toggle
```
`Super+Tab` workspace map · `Super+N` switches **notch ↔ island** (with no text
notice: the shape changing is the confirmation) · `Super+A` (or `Super+,`)
Settings · `Super+R` launcher · `Super+D` Control Centre · `Super+Shift+D`
computer status · `Super+Shift+E` or the power key → power menu · `Super+W`
hide/show everything · `Super+G` reload (`reload.sh`).

`Super+Shift+V` opens the launcher already in `#` (clipboard) and
`Super+Alt+Space` in `>` (actions). The two modes that **already had one when
they were rofi menus** keep a shortcut of their own: changing how they are
painted inside is no reason to take away from anybody a key they have already
learned. Windows get no new shortcut, you get there by typing `@`.

```
qs ipc call notch launcher     # open/close the launcher (applications mode)
qs ipc call notch open apps|clip|cmd|win   # open it straight in a mode
qs ipc call notch clipboard    # shorthand for `open clip`
qs ipc call notch overview     # open/close the workspace map
qs ipc call notch control      # open/close the Control Centre
qs ipc call notch system       # open/close the computer status
qs ipc call notch power        # open/close the power menu
qs ipc call notch network      # open/close the network picker
qs ipc call notch bluetooth    # open/close the bluetooth panel
qs ipc call notch settings     # open/close the Settings app
qs ipc call notch keys         # Settings already on “Shortcuts” (what Super+K does)
qs ipc call notch style        # toggle notch <-> island
qs ipc call notch close        # close any panel
qs ipc call notch current      # which panel is open (empty if none)
qs ipc call notch restore NAME    # reopen that panel
qs ipc call notch btask confirm|display|authorize NAME CODE TYPED
qs ipc call notch btclear      # remove the pairing face
```
`btask`/`btclear` are not meant to be used by hand: they are called by
`scripts/bt-agent.py` (see “Pairing over Bluetooth”). They are there to SEE the
face without having a device in front of you, the same way `osd` is there to see
the OSDs without plugging the charger in:
```
qs ipc call notch btask confirm "Teclado K380" 418293 -1
qs ipc call notch btask display "Teclado K380" 418293 4
```
`current` + `restore` exist for the screenshots: photographing the notch means
freezing the screen, freezing sends the focus away and that cancels the
`HyprlandFocusGrab`, so the panel closes underneath the photo.
`~/.config/hypr/scripts/capture-region.sh` notes down which one it was before
freezing and gives it back at the end: taking a screenshot no longer closes what
you were looking at.

## What changed outside this directory
- 2026-08-19: **out goes the last rofi menu with a key of its own**. `Super+K`
  no longer calls `~/.config/hypr/list_keybinds.sh`: it opens Settings straight
  on “Shortcuts” (`global, quickshell:keybinds`), which is the SAME list read
  from the same `hyprland.conf` — they were two views of the same parsing and
  they only agreed while nobody touched either of them. New:
  `ShellState.openSettingsAt(id)`, `SettingsWindow.openAt(id)`,
  `qs ipc call notch keys` and the “Keyboard shortcuts” action in the command
  menu. The seven rofi scripts nobody was calling any more
  (`list_keybinds.sh`, `hypr/scripts/menu.sh`, `hypr/wallpaper-picker.sh`,
  `rofi/cliphist-menu.sh`, `rofi/cliphist-paste.sh`,
  `rofi/scripts/network-menu.sh`, `rofi/scripts/bluetooth-menu.sh`) are in
  `~/.config/menus-rofi-retirados-20260819.tar.gz`.

  That same day, a little later: **rofi is gone entirely**. The only survivor
  was `hypr/scripts/webapp-install.sh` (`Super+Ctrl+W`), two chained text
  prompts that the notch launcher does not know how to do — and did not need to
  learn, because `~/.local/share/webapps/` never came to exist: the shortcut was
  not used once. With that retired, rofi was left without a single live use, so
  with it go `~/.config/rofi/` (112 theme files), the
  `wal/templates/colors-rofi.rasi` template, Hyprland's `rofi-blur` layer rule
  and the package in `packages/pacman.txt`. And for the same reason `wlogout`,
  which `PowerPanel.qml` replaced. All in
  `~/.config/rofi-wlogout-retirados-20260819.tar.gz` and
  `~/.config/webapp-install-retirado-20260819.tar.gz`.

  What was left was not just dead code and that is it: it was a false
  description of the desktop in a repo about to be published.
- 2026-08-09: `~/.config/hypr/shaders/reading-mode.glsl` and
  `~/.config/hypr/scripts/reading-mode.sh`. The reversible temporary state lives
  in `$XDG_RUNTIME_DIR/quickshell-rice/reading-mode.json`, so a preference that
  no longer describes the compositor is not persisted. Also added
  `~/.config/hypr/scripts/wifi-enterprise.sh`, a minimal bridge to
  NetworkManager's editor: it takes an action + SSID, never identity or
  password.
- `hyprland.conf`: `exec-once = waybar` commented out; `swayosd-server`
  retired; volume → `wpctl` (the notch sees it instantly through Pipewire),
  brightness → `qs ipc call notch bright`; `Super+R` no longer launches rofi, it
  opens the notch launcher.
- 2026-08-08: **out go the last two rofi menus**. `Super+Shift+V` no longer
  calls `~/.config/rofi/cliphist-paste.sh` and `Super+Alt+Space` no longer calls
  `~/.config/hypr/scripts/menu.sh`: both of them open the notch launcher in
  their mode (`global, quickshell:clipboard` and `quickshell:actions`), in
  `hyprland.lua` and in the `hyprland.conf` backup. The clipboard data still
  comes out of cliphist (`wl-paste --watch` in `exec-once`), only who paints it
  changes. The three rofi scripts were left on disk in case anyone had to go
  back; on 2026-08-19 they were archived (see above).
- `set-wallpaper.sh`: it no longer reloads waybar or swayosd.
- 2026-08-05: `exec-once = qs` replaced by `~/.config/systemd/user/`
  `quickshell.service` (Restart=on-failure). Reason: on 2026-08-05 qs died with
  SIGSEGV and nobody brought it back up; besides, on dying it let go of the
  notifications D-Bus name and swaync took it. `qs --no-duplicate` stops a
  manual launch from creating a second bar.
- 2026-08-05: `swaync` masked and its dead reload taken out of
  `set-wallpaper.sh` (the `swaync-client -rs` line).
- 2026-08-07: the notification of a screenshot can be PRESSED to edit it.
  `notify-shot.sh` sends it with an "Edit" action (`notify-send -A`, which
  implies `--wait`: that is why it goes to the background and with
  `timeout 600`, because our server does not expire notifications on its own).
  Pressing the notice in the notch or its row in the Control Centre invokes the
  action and opens the photo in satty (`screenshot-edit.sh`, which saves the
  annotated one separately). The notch notice now invokes the first action if
  the notification brings any, and only opens the Control Centre when there is
  none — which means any app with actions benefits, not just the screenshots.
- 2026-08-07: region screenshots over a FROZEN screen. `Super+Shift+S` no longer
  calls `hyprshot -m region`, but `screenshot-region.sh`, which leans on
  `capture-region.sh` (hyprpicker freezes → slurp chooses over the photo →
  `grim -g` crops). Reason: slurp steals the focus and the notch, the launcher
  or any menu closed before the shot, so it was impossible to photograph them.
  `screenshot-annotate.sh` (satty) and `ocr.sh` use the same path.
- 2026-08-06: themed pokemon. A new `~/.local/bin/poke-theme` (it indexes the
  palette of each sprite and sorts them for the theme in force),
  `poke_theme_pick()` in `~/.zshrc` and a line in `set-wallpaper.sh` that
  reorders them in the background when the wallpaper changes. The preference is
  in `~/.config/poke-theme/state`.
- Backups: `~/.config/hypr/hyprland.conf.bak-notch-*`, `shell.qml.bak-notch`.

### Back to waybar
```
cp ~/.config/hypr/hyprland.conf.bak-notch-* ~/.config/hypr/hyprland.conf
cp ~/.config/quickshell/shell.qml.bak-notch ~/.config/quickshell/shell.qml
hyprctl reload; ~/.config/quickshell/reload.sh; (waybar >/dev/null 2>&1 &)
```

## Trying it without touching the desktop
```
qs -p ~/.config/quickshell/TopShell.qml
```

## `~/.config/quickshell-old/`
Superseded attempts, outside the load directory: `Bar.qml` (the original
floating bar), `MenuBar.qml` + `Notch.qml` + `NotchState.qml` + `NotchBar.qml`
(the two-window version, which looked like two separate pieces), `Osd.qml` and
`Notifications.qml` (the loose popups, already covered by the `notif` mode) and
`Sidebar.qml` (the `Super+N` dashboard, absorbed by the Control Centre; that
shortcut went on to toggle notch/island).
There was also a version with a solid black strip that the notch hung from:
discarded, the bulge stuck out of the reserved band and got in the way on top of
the windows.

### Back to swaync
swaync has been MASKED since 2026-08-05: it activated itself through D-Bus every
time Quickshell did not have the `org.freedesktop.Notifications` name (startup,
reload or crash) and then never let go of it, leaving the notch's notifications
dead. To go back to it:
```
systemctl --user unmask swaync && systemctl --user enable --now swaync
```
…and take the `NotificationServer` block out of `ShellState.qml` (there cannot
be two owners of `org.freedesktop.Notifications`).

## Known things
- **Systray after restarting the shell**: the `StatusNotifierItem`s register
  against whichever watcher is there at the time. If you kill Quickshell, the
  apps that are already open (e.g. `rustdesk --tray`) do not come back to the
  tray until you restart them. In a normal login it does not happen.
- **Blur**: the new `layerrule` syntax IS known and it works
  (`layerrule = blur on, match:namespace ^(rofi)$`, active in `hyprland.conf`).
  It is not applied to the bar or to the notch on purpose: they are opaque, so
  the blur would be a smudge instead of a material. rofi is the only thing with
  real transparency and that is why it is the only thing that carries it.
- **Mic mute** has no OSD in the notch.

## On a machine that is not this laptop

All of this was designed on an Intel laptop with ONE screen, a battery, a panel
with brightness and wifi. Trying it out on a tower (two DisplayPort monitors, no
battery, no internal panel, wired) brought out the assumptions that had crept
in. What there is now:

**Two screens.** `TopShell` already instantiated one surface per monitor with
`Variants` over `Quickshell.screens`, and `win.primary` decides which one is the
real one by comparing with `ShellState.focusedMon`. The bar comes out on all of
them; so does the notch, but the ones that do not have the focus stay on their
resting face and do not unfold panels, do not ask for the keyboard and do not
arm the `HyprlandFocusGrab`.

What was missing was the workspace indicator: it painted the WHOLE list and
marked the active one with `Hyprland.focusedWorkspace`, which is global. On the
screen without focus that is a pill pointing at a workspace that is on the other
one. Now each bar filters by `ws.monitor.name` and marks the `activeWorkspace`
of ITS monitor (`win.hlMon`, looked up by name in `Hyprland.monitors` — not with
`monitorFor()`, which is a method and does not re-evaluate the binding when you
plug in or unplug an output). If it is not known yet whose each workspace is,
they are all painted: with a single screen the result is identical to before.

Careful with what is NOT a bug: the workspaces are not duplicated per monitor,
the numbering is unique. Super+2 from the left screen takes your focus to
wherever the 2 lives. That is stock Hyprland; in `hyprland.lua` there is a
comment with how to pin them per monitor if one day that is wanted.

The width of the notch (`notchW`) is clamped to the screen minus 48 px per side.
The widths per face are fixed numbers chosen over 1920 px, and there there is
room to spare, but on a narrower output they would stick out on both sides.

**No battery.** `sysstats.sh` returns `bat = -1` and everything that paints
charge demands `batt >= 0`, so the right pole of the notch, the `charge` face
and the Settings rows disappear without leaving a gap (they go by `anchors`, not
by layout). The "Battery" row in Settings no longer presides over an empty block
with a "no battery". And `ac` becomes 1 when there is no battery: the `ac = 0`
fallback literally means "on battery", which on a plugged-in tower is a lie.

**No brightness.** The detail that bites: `brightnessctl` WITHOUT `-c` walks the
classes in order (`backlight`, then `leds`) and keeps the first one that has
anything. On a machine without `/sys/class/backlight` that means ending up
switching the caps-lock LED on and off and showing its 0/100 as if it were the
brightness of the screen. That is why the three calls (`sysstats.sh`,
`stepBrightness`, `setBrightness`) and the ones in `hypridle.d/normal.conf`
carry `-c backlight`. With no panel there is no reading, `bright` stays at -1 and
the Control Centre slider is not drawn.

**No lid.** There is no lid-close action configured, neither in `hyprland.lua`
nor in hypridle. There was nothing to degrade.

**No wifi.** `ShellState.hasWifi` looks at the DEVICE, not at `wifiEnabled`:
NetworkManager reports the radio as disabled also when it simply does not exist,
and the panel could not tell "off" from "there is none". With no adapter, the
Wi-Fi switch disappears (from the panel and from Settings) and the empty list
says that the machine is on a cable instead of sitting on an eternal "Looking
for networks…".

**Temperature.** The search by `thermal_zone` only knew about `x86_pkg_temp` and
`TCPU`, which belong to this Intel. On a Ryzen the sensor is `k10temp` and lives
in hwmon, so the temperature card was dead for ever. There is a hwmon fallback
(`k10temp`/`zenpower`/`coretemp`), resolved once when the script starts.

**What is still nailed to this panel** and has not been touched because it is a
design decision, not a bug: the font sizes in `Appearance.qml` go in fixed
pixels and `hyprland.lua` sets `scale = 1` for every output. On a 27" at 1440p
or on a 4K everything reads small. Fixing it properly means putting DPI scaling
into the whole shell, and that has to be seen with your eyes on the target
screen.
