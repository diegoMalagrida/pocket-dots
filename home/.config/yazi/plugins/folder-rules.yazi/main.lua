--- Reglas de orden por carpeta.
---
--- Downloads se ordena por fecha de modificación, lo más reciente arriba, y
--- sin anclar las carpetas al principio (si no, no sería un orden por fecha
--- de verdad). Cualquier otra carpeta recupera lo que dice yazi.toml.
---
--- Si algún día cambias [mgr] sort_* en yazi.toml, cambia también `defecto()`
--- o esta regla te lo pisará al salir de Downloads.

local function defecto()
	return { "alphabetical", reverse = false, dir_first = true, sensitive = false }
end

local function por_fecha()
	return { "mtime", reverse = true, dir_first = false }
end

local function setup()
	ps.sub("cd", function()
		local cwd = cx.active.current.cwd
		ya.emit("sort", cwd:ends_with("Downloads") and por_fecha() or defecto())
	end)
end

return { setup = setup }
