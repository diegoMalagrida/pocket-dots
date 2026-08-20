-- pywal -> ~/.cache/wal/colors-hyprland.lua  (colores del wallpaper)
-- Gemelo de colors-hyprland.conf, para la config Lua de Hyprland 0.56+.
-- La .conf se queda por si vuelves a la config legacy; las dos se generan
-- en la misma pasada de pywal y dicen lo mismo.
return {{
    active_border   = {{ "rgb({color4.strip})", "rgb({color6.strip})" }},
    active_angle    = 45,
    inactive_border = "rgb({color8.strip})",
    shadow_color    = "rgba({background.strip}ee)",
    background      = "rgb({background.strip})",
}}
