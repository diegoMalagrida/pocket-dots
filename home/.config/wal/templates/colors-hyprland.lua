-- pywal -> ~/.cache/wal/colors-hyprland.lua  (wallpaper colours)
-- Twin of colors-hyprland.conf, for Hyprland 0.56+'s Lua config.
-- The .conf stays in case you go back to the legacy config; both are generated
-- in the same pywal pass and say the same thing.
return {{
    active_border   = {{ "rgb({color4.strip})", "rgb({color6.strip})" }},
    active_angle    = 45,
    inactive_border = "rgb({color8.strip})",
    shadow_color    = "rgba({background.strip}ee)",
    background      = "rgb({background.strip})",
}}
