-- ###########################################################################
--  HYPRLAND CONFIG IN LUA  (Hyprland 0.56+)
--
--  Translated from hyprland.conf on 2026-08-05. The original .conf stays next
--  to it as a fallback: if you delete or rename THIS file, Hyprland goes back
--  to reading it by itself ("Lua config not found, using legacy config at ...").
--  The two do not coexist: if hyprland.lua exists, hyprland.lua is in charge.
--
--  THE REASON FOR THE SWITCH: springs. A bezier does not know where it is,
--  only how much it has left, so if you change its target mid-flight it has
--  to cut and start from zero -- that is the rubbery feeling when you chain
--  two Super+arrow presses in a row. A spring has state (position and
--  velocity) and carries on from where it was. In Hyprland that ONLY exists
--  in the Lua config.
--
--  If something fails to load, Hyprland goes into emergency mode and keeps
--  SUPER+Q alive so you can open a terminal. You are not locked out.
-- ###########################################################################


------------------
---- MONITORS ----
------------------

-- The WILDCARD rule (output = "") applies to any output, so plugging in a
-- second monitor needs no changes at all: 'preferred' takes the native mode and
-- 'auto' places it to the right of the previous one, in the order they appear.
-- This is deliberate and is NOT to be replaced by hard-coded names: 'eDP-1' on
-- the laptop and 'DP-4'/'DP-6' on the tower are the same config, and a list of
-- specific names would only work on the machine it was written on.
hl.monitor({ output = "", mode = "preferred", position = "auto", scale = 1 })

-- If some machine needs fine-tuning (two screens of different sizes that you
-- want aligned at the bottom, a 4K that looks tiny at scale 1, or the
-- left/right order reversed), the way to do it is to add NAMED rules BELOW
-- the wildcard: the last one that matches wins, so the one above still
-- covers any output you do not mention.
--
--   hl.monitor({ output = "DP-4", mode = "preferred", position = "0x0",    scale = 1 })
--   hl.monitor({ output = "DP-6", mode = "preferred", position = "2560x0", scale = 1 })
--
-- The names come from `hyprctl monitors`. The position is the top-left
-- corner in ALREADY SCALED pixels, so if the left-hand one is 2560 wide at
-- scale 1, the next one starts at 2560.


---------------------
---- MY PROGRAMS ----
---------------------

local terminal    = "kitty"
-- Thunar since 2026-09-12, instead of nautilus: it is GTK3, so it takes the
-- same adw-gtk3-dark + pywal accent as everything else, and it also lets you
-- configure what nautilus does not (sidebar, right-click menu actions in
-- ~/.config/Thunar/uca.xml, thumbnails through tumbler).
local fileManager = "thunar"


-------------------
---- AUTOSTART ----
-------------------

-- UWSM exports the session environment to D-Bus and systemd.
-- Quickshell (bar + notch) is supervised by quickshell.service: if it crashes,
-- systemd brings it back up. Hypridle and the PolicyKit agent are supervised
-- by their user services. Waybar has been replaced by MenuBar.qml + Notch.qml.
hl.on("hyprland.start", function()
    hl.exec_cmd(os.getenv("HOME") .. "/.config/hypr/awww-start.sh")
    hl.exec_cmd("wl-paste --type text --watch cliphist store")   -- clipboard (text)
    hl.exec_cmd("wl-paste --type image --watch cliphist store")  -- clipboard (images)
    -- Shake to find (like macOS): shaking the mouse enlarges the cursor. The
    -- script loads the dynamic-cursors plugin pinned to this Hyprland
    -- version and leaves it with ONLY the shake (mode none); if Hyprland has
    -- been updated and the .so does not match, it rebuilds itself and says so.
    hl.exec_cmd(os.getenv("HOME") .. "/.config/hypr/scripts/dynamic-cursors.sh")
end)


-------------------------------
---- ENVIRONMENT VARIABLES ----
-------------------------------

hl.env("XCURSOR_THEME",   "Bibata-Modern-Ice")
hl.env("XCURSOR_SIZE",    "19")
hl.env("HYPRCURSOR_THEME","Bibata-Modern-Ice")
hl.env("HYPRCURSOR_SIZE", "19")


-----------------------------
---- PYWAL COLOURS ----
-----------------------------

-- pywal writes ~/.cache/wal/colors-hyprland.lua from the template
-- ~/.config/wal/templates/colors-hyprland.lua (twin of the usual .conf one,
-- which is still generated in case you go back to the legacy config).
-- pcall: if the file does not exist yet -- first boot, cache cleared --
-- the config does NOT blow up, it keeps these fallback colours.
local wal = {
    active_border   = { "rgb(394aad)", "rgb(a15bc8)" },
    active_angle    = 45,
    inactive_border = "rgb(648a91)",
    shadow_color    = "rgba(000000ee)",
    background      = "rgb(000000)",
}
do
    local ok, loaded = pcall(dofile, os.getenv("HOME") .. "/.cache/wal/colors-hyprland.lua")
    if ok and type(loaded) == "table" then
        for k, v in pairs(loaded) do wal[k] = v end
    end
end


-----------------------
---- LOOK AND FEEL ----
-----------------------

hl.config({
    general = {
        -- Law 8 -- a single gap in the content layer. Between two windows
        -- there are 6 px (3 + 3) and up to the edge of the screen, another 6:
        -- THE SAME gap. It used to be 6 and 5. One pixel of mismatch cannot be
        -- seen, but it can be felt.
        gaps_in  = 3,
        gaps_out = 6,

        -- Law 2 -- no border, on purpose: focus is marked with light, not
        -- with an outline. If one day you want borders: raise this to 2 and
        -- they already come themed from pywal (above).
        border_size = 0,

        col = {
            active_border   = { colors = wal.active_border, angle = wal.active_angle },
            inactive_border = wal.inactive_border,
        },

        resize_on_border = true,
        allow_tearing    = true,
        layout           = "dwindle",
    },

    decoration = {
        -- Law 1 -- geometry says whose layer it is. Windows are SQUARE
        -- (this is yours and it is anchored to the grid); round things belong
        -- to the shell and float above. Do not round this "for consistency":
        -- consistency comes from motion, not from shape.
        rounding       = 0,
        -- 2 = a quarter circle, which is what Hyprland declares as the minimum
        -- and as the factory value (ConfigValues.cpp:202, "2 is a circle"). There
        -- was a 0 here, out of range: CWindow::roundingPower() clamps it to 1
        -- when reading it, and with power 1 the corner stops being an arc and
        -- becomes a straight chamfer. With rounding = 0 it did not matter, as no
        -- corner was drawn; as soon as Settings > Effects raised the rounding,
        -- you would have seen diamond-shaped windows.
        rounding_power = 2,

        -- Law 2 -- focus is marked with light. The focused window is FULLY
        -- present; the rest sink back. dim_inactive darkens instead of making
        -- things transparent, which is the clean way for something to recede:
        -- transparency lets the background leak in between the letters.
        active_opacity   = 1.0,
        inactive_opacity = 0.90,
        dim_inactive     = true,
        dim_strength     = 0.35,
        dim_special      = 0.5,

        -- The shadow says "this floats". Tiled windows are stuck to the grid
        -- and do not get one (window_rule further down); floating windows and
        -- dialogs do. It is information about the plane, not decoration.
        shadow = {
            enabled      = true,
            range        = 28,
            render_power = 4,
            color        = wal.shadow_color,
        },

        -- At size 3 / passes 1 the blur could not be seen. CAREFUL: kitty is
        -- NOT the only one paying for this (0.95 opacity). With inactive_opacity
        -- = 0.90, EVERY unfocused window has alpha < 1 and Hyprland runs the
        -- full blur chain on it; in a tiling of 2+ windows there is always half
        -- the screen being blurred. The expensive case: workspace slide + motion
        -- blur + this blur, all at once.
        -- IF YOU NOTICE STUTTERING: go back to size = 3 / passes = 1.
        blur = {
            enabled           = true,
            size              = 6,
            passes            = 2,
            noise             = 0.01,
            vibrancy          = 0.1696,
            vibrancy_darkness = 0.2,
            popups            = true,
        },

        -- Law 5 -- whatever CROSSES the screen leaves a trail. Hyprland 0.56
        -- blurs the window in the direction it is moving, and only while the
        -- animation lasts. It is the same idea as the curves below, but
        -- applied to the pixel instead of to time.
        --
        -- It does not fight with rounding because here rounding = 0 (law 1). In
        -- a rice with round corners it would: the two shaders exclude each other
        -- inside Hyprland (USE_ROUNDING && !USE_MOTION_BLUR), so the corners
        -- would come out square precisely while the window travels.
        --
        -- Nor is it paid for when dragging with the mouse: animate_mouse_windowdragging
        -- is already false, and with no animation there is no trail to compute. The
        -- cost lives only in the transitions, which is where it shows.
        --
        -- 'samples' are the copies averaged along the path: more samples, a
        -- smoother and more expensive trail. It does NOT make the trail longer;
        -- that is decided by how far the window has moved.
        --
        -- THESE ARE THE STARTUP VALUES. The switch in Settings > Appearance >
        -- Effects is in charge; see the end of the file.
        motion_blur = {
            enabled = true,
            samples = 7,
        },
    },

    animations = { enabled = true },
})


-- ==========================================================================
--  MOTION. The same scale as quickshell/Appearance.qml.
--  Speed is in DECISECONDS: 1.3 = 130 ms. They are literally the same four
--  numbers as the tokens in ~/.config/quickshell/Appearance.qml, so that a
--  window and the notch move to the same pulse.
--
--     RESPONSE   1.3 / 1.3    focus, zoom, border colour
--     CONTENT    2.1 / 1.1    fades
--     PANEL      3.2 / 1.7    layers
--     SHAPE      4.4 / 2.2    opening and closing a window, and MOVING it
--     TRAVEL     5.0          whatever CROSSES the whole screen
--
--  If something moves here and is not on that scale, it is a bug.
-- ==========================================================================

-- Three curves, and no more. The system's fourth ('entra', the one that
-- bounces) lives ONLY in Quickshell and in scales: by law 5 whatever MOVES
-- ACROSS does not bounce, because overshooting shows the edge of the screen.
hl.curve("respuesta", { type = "bezier", points = { {0.2,  0},    {0,    1} } })
hl.curve("sale",      { type = "bezier", points = { {0.3,  0},    {1,    1} } })
hl.curve("forma",     { type = "bezier", points = { {0.23, 1},    {0.32, 1} } })
hl.curve("entra",     { type = "bezier", points = { {0.16, 1.3},  {0.3,  1} } })

-- 'apple': the curve of iOS/macOS transitions. It starts with a little
-- acceleration instead of shooting off -- that is what makes it look like
-- something with mass getting under way -- and then brakes for almost the
-- whole journey.
hl.curve("apple",     { type = "bezier", points = { {0.32, 0.72}, {0,    1} } })

-- ---------------------------------------------------------------------------
--  THE SPRING. What a bezier cannot do.
--
--  Moving a window with Super+arrows is the only thing on the desktop you
--  sometimes chain: you press two or three in a row to place it. With a bezier
--  each press CUTS the previous one and starts from zero from wherever it was,
--  and that reads as rubber. The spring keeps the velocity it had and chains.
--
--  The three numbers, in physics and not in taste:
--    w0 = sqrt(stiffness/mass) = sqrt(130) = 11.4 rad/s  -> natural frequency
--    zeta = dampening / (2*sqrt(stiffness*mass)) = 23 / 22.8 = 1.01
--
--  zeta = 1.01 is critically damped: it arrives as fast as possible WITHOUT
--  overshooting. That is not timidity, it is law 5 -- if it overshot, the
--  window would slip a hair over the neighbour it has just swapped with, and
--  that is not character, it is a placement bug.
--
--  IF YOU WANT IT SNAPPIER: raise stiffness and raise dampening with it, keeping
--  dampening ~= 2*sqrt(stiffness). Pairs that work:
--      180 / 26.8  -> ~440 ms, right on SHAPE
--      250 / 31.6  -> ~370 ms, more nervous
--  If you lower dampening below 2*sqrt(stiffness) it starts to bounce, and then
--  you are stepping outside law 5 on purpose. Try it if you like, but know what
--  you are doing.
-- ---------------------------------------------------------------------------
hl.curve("mover", { type = "spring", stiffness = 130, dampening = 23, mass = 1 })

hl.animation({ leaf = "global", enabled = true, speed = 3.2, bezier = "forma" })

-- Law 6 -- motion has an origin. A tiled window INFLATES in its slot; it does
-- not fly in from an edge. The tiling had already decided the place, and
-- flying in contradicts it.
hl.animation({ leaf = "windows",   enabled = true, speed = 4.4, bezier = "entra", style = "popin 78%" })
hl.animation({ leaf = "windowsIn", enabled = true, speed = 4.4, bezier = "entra", style = "popin 78%" })

-- Opening covers 22 points of scale (78->100) and closing only 10 (100->90).
-- Deliberately asymmetric, not careless: opening is an event and deserves a
-- gesture; closing is a dismissal and only has to get out of the way.
hl.animation({ leaf = "windowsOut", enabled = true, speed = 2.2, bezier = "sale", style = "popin 90%" })

-- THIS IS WHERE THE CHANGE LIVES. Before: speed 3.2 with bezier 'forma'.
-- Two things at once: (1) the spring, for chaining presses; and (2) it was on
-- the PANEL step (3.2) when the table says moving a whole window is SHAPE.
-- Law 4 ("frequency lowers the weight by one step") seemed to justify it, but
-- the nuance of that same law is that "it cannot weigh" means START RIGHT
-- AWAY, not last a short time -- and starting right away is the spring's job,
-- since it leaves with the full force of the compressed spring behind it.
-- With spring, 'speed' is the duration ceiling; physics is in charge.
hl.animation({ leaf = "windowsMove", enabled = true, speed = 4.4, spring = "mover" })

hl.animation({ leaf = "fade",       enabled = true, speed = 2.1, bezier = "forma" })
hl.animation({ leaf = "fadeIn",     enabled = true, speed = 2.1, bezier = "forma" })
hl.animation({ leaf = "fadeOut",    enabled = true, speed = 1.1, bezier = "sale" })
hl.animation({ leaf = "fadeSwitch", enabled = true, speed = 2.1, bezier = "forma" })
hl.animation({ leaf = "fadeShadow", enabled = true, speed = 2.1, bezier = "forma" })

-- Focus. With follow_mouse = 1 it changes constantly, so the dimming has to
-- be RESPONSE: if it were slow, the whole desktop would flicker every time you
-- move the mouse across a window.
hl.animation({ leaf = "fadeDim", enabled = true, speed = 1.3, bezier = "respuesta" })

-- Layers (the bar and the notch panels, the launcher, notifications): they
-- FADE. Nothing full-screen slides in; it would show the edge it comes in
-- through.
hl.animation({ leaf = "layers",        enabled = true, speed = 3.2, bezier = "forma", style = "fade" })
hl.animation({ leaf = "layersIn",      enabled = true, speed = 3.2, bezier = "forma", style = "fade" })
hl.animation({ leaf = "layersOut",     enabled = true, speed = 1.7, bezier = "sale", style = "fade" })
hl.animation({ leaf = "fadeLayersIn",  enabled = true, speed = 3.2, bezier = "forma" })
hl.animation({ leaf = "fadeLayersOut", enabled = true, speed = 1.7, bezier = "sale" })

-- THE WORKSPACE SWITCH, MACOS STYLE. It goes all the way: 'slide', not 'slidefade'.
-- The two workspaces sit side by side like two adjoining rooms and the screen
-- travels 100 % from one to the other, both at once, with no fade at all.
-- The fade is exactly what gives away that they are two overlapping images;
-- without it, they are a place you leave and another you arrive at. (Law 10:
-- the problem was never the duration or the curve, it was that 'slidefade 20%'
-- CUT the journey SHORT.) No bounce: it is a displacement, and overshooting
-- would leave a strip of background peeking in from the opposite side at the end.
hl.animation({ leaf = "workspaces",          enabled = true, speed = 5.0, bezier = "apple", style = "slide" })
hl.animation({ leaf = "workspacesIn",        enabled = true, speed = 5.0, bezier = "apple", style = "slide" })
hl.animation({ leaf = "workspacesOut",       enabled = true, speed = 5.0, bezier = "apple", style = "slide" })
hl.animation({ leaf = "specialWorkspace",    enabled = true, speed = 5.0, bezier = "apple", style = "slidevert" })
hl.animation({ leaf = "specialWorkspaceIn",  enabled = true, speed = 5.0, bezier = "apple", style = "slidevert" })
hl.animation({ leaf = "specialWorkspaceOut", enabled = true, speed = 5.0, bezier = "apple", style = "slidevert" })

-- Invisible (border_size = 0), but the node exists: keep it off the factory
-- speed so it does not clash the day you switch borders on.
hl.animation({ leaf = "border", enabled = true, speed = 1.3, bezier = "respuesta" })

-- borderangle / shadowangle / glowangle in 'loop' force continuous repainting
-- at 60 Hz even when they are not visible. On an Iris Xe that is decoration
-- paid for in frames. They stay off (law 7: nothing moves for no reason).
hl.animation({ leaf = "borderangle", enabled = false, speed = 1, bezier = "default" })
hl.animation({ leaf = "shadowangle", enabled = false, speed = 1, bezier = "default" })
hl.animation({ leaf = "glowangle",   enabled = false, speed = 1, bezier = "default" })

hl.animation({ leaf = "zoomFactor", enabled = true, speed = 1.3, bezier = "respuesta" })


--------------------------
---- WORKSPACES ----
--------------------------

-- Always three workspaces. Hyprland destroys a workspace as soon as it is
-- empty, so the indicator row changed size by itself: you closed the last
-- window on 3 and its dot disappeared. 'persistent' makes them exist even
-- when they are empty.
--
-- It is done HERE, and not by painting extra dots in the shell, on purpose:
-- this way the three workspaces really exist, so the dot is clickable and
-- takes you there. A painted dot that corresponds to nothing would be a
-- decoration telling lies.
--
-- They are a MINIMUM, not a cap: if you create 4 its dot appears by itself,
-- and disappears once it is empty. The first three always stay.
-- WITH TWO SCREENS this gets shared out, and it is worth knowing: workspaces
-- are NOT duplicated per monitor, the numbering is unique for the whole
-- session. Hyprland gives each output one at startup (the first gets 1, the
-- second 2) and puts the remaining persistent ones wherever it can, so Super+2
-- from the left screen does not change what you see there: it takes the FOCUS
-- to the screen where 2 lives. That is Hyprland's stock behaviour, not a bug.
--
-- The bar no longer lies about this: each screen paints ONLY its own
-- workspaces and marks its own active one (see TopShell.qml, the ws.monitor filter).
--
-- If on the tower you would rather split them by hand —say 1 and 2 on the main
-- screen and 3 on the secondary— add the monitor to the rule, with the names
-- that `hyprctl monitors` gives:
--
--   hl.workspace_rule({ workspace = "1", persistent = true, monitor = "DP-4" })
--   hl.workspace_rule({ workspace = "2", persistent = true, monitor = "DP-4" })
--   hl.workspace_rule({ workspace = "3", persistent = true, monitor = "DP-6" })
--
-- It is not done here because the names belong to one particular machine and
-- this file is shared by the laptop and the tower.
for i = 1, 3 do
    hl.workspace_rule({ workspace = tostring(i), persistent = true })
end


---- LAYOUTS ----

hl.config({
    dwindle = { preserve_split = true },
    master  = { new_status = "master" },
})

-- Cursor: hyprcursor switched OFF on purpose (2026-09-06). After installing
-- Bibata's SVG theme (~/.local/share/icons/Bibata-Modern-Ice, for a crisp
-- shake-to-find) Hyprland started using it for the NORMAL cursor too, and
-- Diego noticed it looked different from the usual bitmap XCursor. With this
-- the normal cursor is the one it always was; the shake enlargement scales
-- that bitmap with smooth filtering (hyprcursor:nearest 0, below). The plugin
-- uses the same switch and theme as the compositor, so SVG-in-the-zoom +
-- normal-bitmap cannot coexist: setting this back to true changes the cursor.
hl.config({
    cursor = { enable_hyprcursor = false },
})

-- Shake to find (dynamic-cursors plugin): the SOURCE OF TRUTH for its config
-- is THIS block, not the script. It has to live here because every reload
-- resets the plugin's options to their defaults (and the default is
-- mode=tilt, the cursor tilting as it moves) -- and the wallpaper chain does
-- reloads. The pcall is for STARTUP: the .lua is parsed before
-- dynamic-cursors.sh loads the plugin and these keys do not exist yet; the
-- script does a reload after loading it and then this really takes effect.
-- CAREFUL with syntax: dynamic_cursors with an underscore (it is translated
-- to plugin:dynamic-cursors:*); with a hyphen you get "unknown config key".
-- "smooth" profile (based on alonso-herreros' dotfiles): threshold 3 detects
-- the first back-and-forth; influence 2 makes the zoom grow WITH the intensity
-- of the shaking; timeout 0 deflates it on release, like macOS. Verified over
-- IPC: progression 1 -> 3.6 continuous, no steps.
pcall(function()
    hl.config({
        plugin = {
            dynamic_cursors = {
                mode = "none",
                shake = { threshold = 3.0, base = 2.0, speed = 2.0, influence = 2.0, limit = 4.0, timeout = 0 },
                -- nearest 0: never pixelated scaling. resolution 128: the SVG
                -- theme is rasterised at 128 px -> crisp across the whole zoom
                -- range (19 px x 4 = 76). The plugin is patched to load the SVG
                -- theme even with cursor:enable_hyprcursor set to false (the
                -- NORMAL cursor is still the usual bitmap XCursor).
                hyprcursor = { nearest = 0, resolution = 128 },
            },
        },
    })
end)


----------------
----  MISC  ----
----------------

hl.config({
    misc = {
        force_default_wallpaper = 0,
        disable_hyprland_logo   = true,
        background_color        = wal.background,

        -- From caelestia: animate STATE CHANGES, not live interaction.
        -- Dragging or resizing with the mouse already follows your hand 1:1,
        -- so animating it adds nothing, and on an iGPU it means continuous
        -- repainting tied to the pointer (the most expensive path there is).
        -- Not a pinch of feel is lost and GPU is freed right when it is most needed.
        animate_manual_resizes       = false,
        animate_mouse_windowdragging = false,

        -- THE EMERGENCY EXIT FROM THE BLACK SCREEN.
        --
        -- Both ship as false (ConfigValues.cpp:485-486), and that left the
        -- system with no way at all to switch the screen on: if DPMS stayed
        -- off -and it did, because hypridle toggled it instead of switching
        -- it on- the only way out without SSH was to wait seven minutes for
        -- the idle timer to toggle it again.
        --
        -- The good news is that they do NOT toggle: they call
        -- dpms(TOGGLE_ACTION_ENABLE) guarded by `if (!m_dpmsStateOn)`
        -- (PointerManager.cpp:980-981, InputManager.cpp:1164-1165), so they
        -- switch on and never off, and the value is reread on every event. If
        -- DPMS ever gets out of sync again, moving the mouse or pressing a key
        -- fixes it, which is what anyone would try anyway.
        mouse_move_enables_dpms = true,
        key_press_enables_dpms  = true,
    },
})


---------------
---- INPUT ----
---------------

hl.config({
    input = {
        kb_layout    = "es",
        kb_variant   = "",
        kb_model     = "",
        kb_options   = "",
        kb_rules     = "",
        follow_mouse = 1,
        sensitivity  = 0,
        touchpad     = { natural_scroll = true },
    },
})

-- The keyboard above is this desktop's own. Another machine gets its own in
-- ~/.config/hypr/keyboard.lua, which install.sh writes from what localectl
-- reports, so that whoever installs this does not end up typing on a Spanish
-- layout they do not have. Not in the repo; if it is missing, "es" stands.
pcall(dofile, os.getenv("HOME") .. "/.config/hypr/keyboard.lua")

hl.gesture({ fingers = 3, direction = "horizontal", action = "workspace" })

-- Three fingers down: pulls the month calendar down from the notch.
-- Same hand posture as the gesture above, another axis. `finish` and not
-- `update`: this is not a continuous drag like the workspace one, it is an
-- order that runs once, when you lift your fingers.
--
-- It does not open by clicking the clock, which was the first thing tried: that
-- click had always opened the control centre, and taking away a learned gesture
-- in exchange for a new feature is no way to treat anyone. The calendar also
-- has its tile in the control centre, which is the door you can see.
-- 2026-09-14: this gesture did NOTHING, for two reasons at once.
--   (1) `action` was passed as a TABLE with a `finish` field, and that form does
--       not exist in the API: the stub /usr/share/hypr/stubs/hl.meta.lua types
--       it as `string|function` (the gesture above, the workspace one, uses a string).
--   (2) Inside the callback, `hl.dsp.global(...)` only BUILDS a Dispatcher
--       object; it has to be passed to `hl.dispatch()` for it to run.
-- Checked against the live compositor:
--   hyprctl eval "hl.dsp.exec_cmd('touch X')"                  -> the file does NOT appear
--   hyprctl eval "hl.dispatch(hl.dsp.exec_cmd('touch X'))"     -> the file DOES appear
-- CAREFUL: the `hl.bind(...)` calls further down pass `hl.dsp.*` UNWRAPPED and
-- are FINE, leave them alone: there the dispatcher is passed as a value and hl.bind runs it.
-- The difference is that here we are inside a callback.
--
-- Since `action` is a function and not a `finish`, it may fire on every update
-- of the swipe and not only when you lift your fingers. The target is a
-- toggle, so without a brake the calendar would open and close several times
-- in a single gesture. Hence the debounce: at most one opening per second.
local ultimo_calendario = 0
hl.gesture({
    fingers   = 3,
    direction = "down",
    action    = function()
        local ahora = os.time()
        if ahora == ultimo_calendario then return end
        ultimo_calendario = ahora
        hl.dispatch(hl.dsp.global("quickshell:calendar"))
    end,
})


---------------------
---- KEYBINDINGS ----
---------------------

-- SUPER+n on the workspace you are already on takes you back to the previous
-- one, instead of doing nothing. There and back on the same key: you glance at
-- the browser for a second and return to your work without recalling which
-- number you were on. The compositor does it, not a counter of ours: the binds
-- below dispatch the bare `workspace`, which is the one this option looks at.
hl.config({
    binds = { workspace_back_and_forth = true },
})

local mainMod = "SUPER"

-- Screenshots
-- Region: freezes the screen before you choose the crop, so it also captures
-- whatever closes when it loses focus (the Super+D notch, a menu, a
-- dropdown). See ~/.config/hypr/scripts/capture-region.sh.
hl.bind(mainMod .. " + SHIFT + S", hl.dsp.exec_cmd("~/.config/hypr/scripts/screenshot-region.sh"))
-- Instant FULL screenshot (grim does not steal focus -> it does capture menus like rofi).
-- Super+Shift+P is the RELIABLE key; Print works if your keyboard emits that keysym.
hl.bind(mainMod .. " + SHIFT + P", hl.dsp.exec_cmd("~/.config/hypr/scripts/screenshot-full.sh"))
hl.bind("Print",                   hl.dsp.exec_cmd("~/.config/hypr/scripts/screenshot-full.sh"))

hl.bind(mainMod .. " + L",         hl.dsp.exec_cmd("loginctl lock-session"))
-- Clipboard history. It no longer calls cliphist's rofi: it opens the notch
-- launcher directly in its "#" mode. The data still comes from cliphist
-- (wl-paste --watch stores it, up there in exec-once); all that changes is who
-- paints it and who searches it.
hl.bind(mainMod .. " + SHIFT + V", hl.dsp.global("quickshell:clipboard"))

-- Basics
hl.bind(mainMod .. " + Q", hl.dsp.exec_cmd("uwsm app -- " .. terminal))
hl.bind(mainMod .. " + C", hl.dsp.window.close())
hl.bind(mainMod .. " + M", hl.dsp.exit())
hl.bind(mainMod .. " + E", hl.dsp.exec_cmd("uwsm app -- " .. fileManager))


-- Local AI: a panel that knows this system. Special workspace so that the
-- session and the model stay alive between presses.
--
-- ~/ia-local is a self-contained module: EVERYTHING of its own lives in there,
-- this panel included. The bind is registered ONLY if the module exists, so
-- deleting the directory does not leave a dead Super+I that looks like it works.
-- The module keeps its own record of what it touches outside its directory.
local ia_panel = os.getenv("HOME") .. "/ia-local/bin/ia-panel"
local ia_f = io.open(ia_panel, "r")
if ia_f then
    ia_f:close()
    hl.bind(mainMod .. " + I", hl.dsp.exec_cmd(ia_panel))
end
-- First press: floating at 60 % and centred. Second: back to tiling.
hl.bind(mainMod .. " + V", hl.dsp.exec_cmd("~/.config/hypr/scripts/toggle-float-centered.sh"))
hl.bind(mainMod .. " + P", hl.dsp.window.pseudo())
hl.bind(mainMod .. " + J", hl.dsp.layout("togglesplit"))
hl.bind(mainMod .. " + G", hl.dsp.exec_cmd("~/.config/quickshell/reload.sh"))
hl.bind(mainMod .. " + O", hl.dsp.exec_cmd("kitty --class pokemon-popup -e ~/.config/hypr/scripts/pokemon-popup.sh"))

-- Quickshell (bar + notch). 'global' reaches the shell over IPC.
hl.bind(mainMod .. " + R",         hl.dsp.global("quickshell:launcher"))   -- launcher from the notch
hl.bind(mainMod .. " + SHIFT + M", hl.dsp.global("quickshell:media"))      -- floating player
hl.bind(mainMod .. " + N",         hl.dsp.global("quickshell:notchstyle")) -- toggles notch <-> island
hl.bind(mainMod .. " + SHIFT + W", hl.dsp.global("quickshell:wallpaper"))  -- wallpaper picker
hl.bind(mainMod .. " + TAB",       hl.dsp.global("quickshell:overview"))   -- window overview
hl.bind(mainMod .. " + SHIFT + TAB", hl.dsp.global("quickshell:stage"))    -- Stage Manager sidebar
hl.bind(mainMod .. " + D",         hl.dsp.global("quickshell:notch"))      -- control centre
hl.bind(mainMod .. " + SHIFT + D", hl.dsp.global("quickshell:system"))     -- system status
hl.bind(mainMod .. " + SHIFT + E", hl.dsp.global("quickshell:power"))      -- power menu
-- Under the same key as the popup pokémon (Super+O), so all the pokémon
-- things stay together: O brings one onto the screen, SHIFT+O opens the team.
hl.bind(mainMod .. " + SHIFT + O", hl.dsp.global("quickshell:poke"))       -- pokémon team
hl.bind(mainMod .. " + comma",     hl.dsp.global("quickshell:settings"))   -- Settings (like Cmd+, on macOS)
hl.bind(mainMod .. " + A",         hl.dsp.global("quickshell:settings"))   -- alias of Super+,
-- Super+K used to open ~/.config/hypr/list_keybinds.sh: a rofi that parsed
-- THIS very file (well, its .conf mirror) to show the list of shortcuts. But
-- Settings > Shortcuts already did exactly that parsing, so they were two lists
-- that only matched as long as nobody touched either. The key is the same as
-- ever; what it opens now is the list that already lived in the notch.
hl.bind(mainMod .. " + K",         hl.dsp.global("quickshell:keybinds"))   -- shortcut map (Settings > Shortcuts)

hl.bind(mainMod .. " + W",         hl.dsp.global("quickshell:bar"))        -- hide/show the bar

-- Move the FOCUS with Super + Shift + arrows
hl.bind(mainMod .. " + SHIFT + left",  hl.dsp.focus({ direction = "l" }))
hl.bind(mainMod .. " + SHIFT + right", hl.dsp.focus({ direction = "r" }))
hl.bind(mainMod .. " + SHIFT + up",    hl.dsp.focus({ direction = "u" }))
hl.bind(mainMod .. " + SHIFT + down",  hl.dsp.focus({ direction = "d" }))

-- Move/swap the WINDOW with Super + arrows. This is what triggers
-- 'windowsMove', i.e. the spring above.
hl.bind(mainMod .. " + left",  hl.dsp.window.move({ direction = "l" }))
hl.bind(mainMod .. " + right", hl.dsp.window.move({ direction = "r" }))
hl.bind(mainMod .. " + up",    hl.dsp.window.move({ direction = "u" }))
hl.bind(mainMod .. " + down",  hl.dsp.window.move({ direction = "d" }))

-- Workspaces with Super + [0-9], and send the window there with Super+Shift.
for i = 1, 10 do
    local key = i % 10  -- 10 goes on the 0 key
    hl.bind(mainMod .. " + " .. key,             hl.dsp.focus({ workspace = i }))
    hl.bind(mainMod .. " + SHIFT + " .. key,     hl.dsp.window.move({ workspace = i }))
end

-- Mouse wheel to switch workspace
hl.bind(mainMod .. " + mouse_down", hl.dsp.focus({ workspace = "e+1" }))
hl.bind(mainMod .. " + mouse_up",   hl.dsp.focus({ workspace = "e-1" }))

-- Move/resize by dragging with Super + button
hl.bind(mainMod .. " + mouse:272", hl.dsp.window.drag(),   { mouse = true })
hl.bind(mainMod .. " + mouse:273", hl.dsp.window.resize(), { mouse = true })

-- Volume/brightness: the notch (Quickshell) paints the OSD. It picks up the
-- volume by itself via Pipewire; the brightness is changed by the notch itself
-- over IPC so there is no lag and no value mismatch.
hl.bind("XF86AudioRaiseVolume",  hl.dsp.exec_cmd("wpctl set-volume -l 1.4 @DEFAULT_AUDIO_SINK@ 2%+"), { locked = true, repeating = true })
hl.bind("XF86AudioLowerVolume",  hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 2%-"),        { locked = true, repeating = true })
hl.bind("XF86AudioMute",         hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"),       { locked = true })
hl.bind("XF86AudioMicMute",      hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"),     { locked = true })
hl.bind("XF86MonBrightnessUp",   hl.dsp.exec_cmd("qs ipc call notch bright up"),                      { locked = true, repeating = true })
hl.bind("XF86MonBrightnessDown", hl.dsp.exec_cmd("qs ipc call notch bright down"),                    { locked = true, repeating = true })

-- Requires playerctl
hl.bind("XF86AudioNext",  hl.dsp.exec_cmd("playerctl next"),       { locked = true })
hl.bind("XF86AudioPause", hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
hl.bind("XF86AudioPlay",  hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
hl.bind("XF86AudioPrev",  hl.dsp.exec_cmd("playerctl previous"),   { locked = true })

-- Physical power button
hl.bind("XF86PowerOff", hl.dsp.global("quickshell:power"))

-- Quick wins
hl.bind(mainMod .. " + CTRL + S",  hl.dsp.exec_cmd("~/.config/hypr/scripts/screenshot-annotate.sh")) -- annotate screenshot (satty)
hl.bind(mainMod .. " + SHIFT + C", hl.dsp.exec_cmd("~/.config/hypr/scripts/colorpicker.sh"))         -- colour picker (hyprpicker)
hl.bind(mainMod .. " + SHIFT + N", hl.dsp.exec_cmd("~/.config/hypr/scripts/hyprsunset-toggle.sh"))   -- night light

-- Signature: menu / ocr
-- The command menu is no longer a rofi either: it is the launcher's ">" mode.
-- Same key, same list (plus what that menu could not offer because it lived
-- outside the shell: settings, workspace map, do not disturb, caffeine).
--
-- There was a third bind here, Super+Ctrl+W, which installed a website as an "app".
-- Retired on 19 Aug 2026: it was the LAST thing still launching rofi, and neither
-- ~/.local/share/webapps nor a single web-app .desktop ever came to exist in
-- all that time.
hl.bind(mainMod .. " + ALT + Space", hl.dsp.global("quickshell:actions"))                       -- command menu
hl.bind(mainMod .. " + CTRL + T",    hl.dsp.exec_cmd("~/.config/hypr/scripts/ocr.sh"))          -- screen OCR

-- Screen recording (wf-recorder)
hl.bind(mainMod .. " + CTRL + R", hl.dsp.exec_cmd("~/.config/hypr/scripts/screenrecord.sh"))
-- The same recording, but with whatever plays through the speakers. It is on
-- a separate key, and not an option of the one above, on purpose: a quick
-- recording should not take your music along without you asking for it.
hl.bind(mainMod .. " + CTRL + SHIFT + R", hl.dsp.exec_cmd("~/.config/hypr/scripts/screenrecord.sh --sonido"))


--------------------------------
---- WINDOWS AND LAYERS ----
--------------------------------

-- --- Quickshell's Settings app (SettingsWindow.qml) ---
-- It is the shell's only real window (xdg-toplevel): class org.quickshell,
-- title "Ajustes"; the rest of the shell is layers (layer-shell), which do not
-- go through here. Without these rules it opened TILED and took up half the
-- screen (952x1038). The size is also in the QML (implicitWidth/Height) so
-- there is no big flash before Hyprland resizes it. Do not go below 780 wide:
-- the window has its own minimum there.
hl.window_rule({
    name  = "ajustes-quickshell",
    match = {
        class = "^(org\\.quickshell)$",
        title = "^(Ajustes)$",
    },
    float  = true,
    size   = { 900, 620 },
    center = true,
})

-- --- The Super+O Pokédex (pokemon-popup.py inside kitty) ---
-- Without this rule it went into the TILING: it rearranged your whole
-- workspace and also drew a 700 px card lost in an 1880 window, with black
-- emptiness all around. It opens from a shortcut and goes away with any key,
-- so it is a dialog, not a work window: floating and centred, with the SAME
-- width as Settings -- the other thing that comes out of a key -- so that the
-- two read as the same gesture.
--
-- The height comes from laying out the card for all 563 critters, not from
-- eyeballing it (remeasured 2026-09-14 for the grid card: hexagon with numbers,
-- three columns and evolution band). The longest takes 733 px, the median 713,
-- and kitty's chrome plus the footer with the hint take ~100 px more: with 840
-- all 563 fit without scrolling. A Pokédex that makes you scroll to see it
-- whole looks broken; the scroll is still there in case someone shrinks the window.
hl.window_rule({
    name  = "pokedex-popup",
    match = { class = "^(pokemon-popup)$" },
    float  = true,
    size   = { 900, 840 },
    center = true,
})

-- --- Image viewer (imv) ---
-- Looking at a photo is not settling down to work: it goes into the tiling and
-- rearranges your whole workspace to show something you close ten seconds
-- later. Same criterion as Settings and the Pokédex, which also come out of a
-- gesture and go away. 70% OF WHICHEVER SCREEN IT LANDS ON, NOT 1344x756.
--
-- There were fixed pixels here, with a comment saying the percentage "is
-- accepted without complaint and does nothing". A half-truth, misdiagnosed:
-- what does not exist is the `%` OPERATOR, not the strings. muParser does not
-- know it, throws an exception, CExpression::compute() swallows it and returns
-- nullopt (Expression.cpp:57-61), and the rule is left without a size. That is
-- why it came up at imv's 1280x720.
--
-- The 0.56.2 DSL DOES evaluate expressions, and by two routes:
--   * a single string split by a space -> Math::parseExpressionVec2
--   * a table of two strings            -> expressionVec2ElementToString
-- (LuaConfigExpressionVec2.cpp:13-57). The variables monitor_w and monitor_h
-- are defined against the WINDOW'S monitor in Window.cpp:2010-2011.
--
-- Measured on 2026-09-26 on a 2560x1440 headless monitor: the window comes up
-- at 1792x1008, i.e. exactly 70%. On this 1920x1080 laptop it gives
-- 1344x756, which is what was there by hand; the difference shows on the
-- tower, where the fixed pixels stayed at 52% of the screen.
hl.window_rule({
    name   = "imv-flotante",
    match  = { class = "^(imv)$" },
    float  = true,
    size   = "monitor_w*0.7 monitor_h*0.7",
    center = true,
})

-- The shadow says "this is what you are looking at": ONLY the focused window
-- casts it. Together with dim_inactive, focus stops being a nuance and becomes
-- the first thing the eye sees on arriving at the screen, without a single
-- line of border. (Before, this was "only the floating ones", which in tiling
-- is almost never: the rule was right on paper and in practice never seen.)
hl.window_rule({
    name      = "sombra-solo-en-foco",
    match     = { focus = 0 },
    no_shadow = true,
})

-- --- Law 9: one animation, one owner ---
-- The compositor animates surfaces that APPEAR; the app animates what is inside.
--
-- Quickshell's bar/notch is a PERMANENT layer that resizes itself and already
-- animates itself (Appearance.qml tokens). If Hyprland animated it as well,
-- two animations would chain on the same gesture and you would see a smear.
-- Here control is handed over to Quickshell.
hl.layer_rule({
    name    = "sin-anim-barra",
    match   = { namespace = "^(quickshell:bar)$" },
    no_anim = true,
})

-- The workspace sidebar handles its slide and perspective in QML.
hl.layer_rule({
    name    = "sin-anim-stage",
    match   = { namespace = "^(quickshell:stage)$" },
    no_anim = true,
})

-- Law 6 applied to the shell's surfaces: each one comes in from where it
-- belongs, instead of one generic fade for all of them. The criterion comes
-- from law 9: look at WHAT the app already animates inside and give the
-- compositor only whatever is left free. If both animate the same thing, the
-- two fades multiply and the result is not twice as pretty, it is just late.
--
-- media: it lives stuck to the bottom edge, so it RISES from there. 'slide'
-- moves position and nothing else -- it does not fade -- and the card inside
-- already handles scale and opacity. Different channels, no overlap.
hl.layer_rule({
    name      = "media-sube",
    match     = { namespace = "^(quickshell:media)$" },
    animation = "slide bottom",
})

-- wallpaper: it covers the whole screen, so sliding it would show the edge it
-- comes in through. Besides, its 'stage' already fades by itself (animMed,
-- OutCubic). The compositor has nothing to add here: let it step aside.
hl.layer_rule({
    name    = "sin-anim-wallpaper",
    match   = { namespace = "^(quickshell:wallpaper)$" },
    no_anim = true,
})

-- There was an "overview-funde" rule here (fade on the quickshell:overview
-- layer, so the black veil of the full-screen overview would not appear all at
-- once). Retired on 14 Sep 2026, and it was overdue: the full-screen overview
-- had already gone on 6 Aug 2026, when the workspace map became a FACE OF THE
-- NOTCH. Today it lives inside quickshell:bar and its entrance is done by the
-- notch's own shape morph, so this rule had no layer to apply to: no .qml
-- declares that namespace and hyprctl layers only lists awww-daemon,
-- quickshell:bar and wl_shimeji.
-- The hyprland.conf mirror had already dropped it that same day, with this
-- same explanation; it was the .lua that had fallen behind.

-- There was a "rofi-blur" rule here (blur + ignore_alpha 0.5 on rofi's layer,
-- which was the only thing with real transparency). It went with rofi on 19 Aug
-- 2026: a rule pointing at a layer nobody creates any more does nothing except
-- make you believe rofi is still on the desktop.


-- ==========================================================================
--  WHAT THE SHELL DECIDES
--
--  Settings > Appearance > Effects writes efectos.lua and also
--  applies it live, so the switch takes effect at once. This dofile
--  is what makes it SURVIVE as well: a `hyprctl reload`, which
--  rereads this config and would sweep away any live change, and a
--  session restart.
--
--  It goes LAST so it wins over everything above, and wrapped in pcall: if the
--  file does not exist -- a freshly installed clone, or a start without
--  Quickshell -- nothing happens and the values above stay. Same treatment
--  hyprlock.conf gives language.conf: the defaults first, the layer that may
--  be missing afterwards.
-- ==========================================================================
pcall(dofile, os.getenv("HOME") .. "/.config/hypr/efectos.lua")
