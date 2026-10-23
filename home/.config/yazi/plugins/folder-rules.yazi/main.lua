--- Per-folder sort rules.
---
--- Downloads is sorted by modification date, most recent at the top, and
--- without pinning folders to the start (otherwise it would not really be a
--- sort by date). Any other folder gets back what yazi.toml says.
---
--- If some day you change [mgr] sort_* in yazi.toml, change `defecto()` too,
--- or this rule will override it when you leave Downloads.

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
