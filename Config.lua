local addonName, ST = ...

-- =====================================================================
--  Config.lua
--  Platynator-style storage: an account-wide SwingTimeDB holding a
--  Profiles table, plus a per-character SwingTimeActiveProfile string
--  naming which profile this character uses. No Ace3 / AceDB.
-- =====================================================================

local Config = {}
ST.Config = Config

local DEFAULT_PROFILE = "Default"

-- ---------------------------------------------------------------------
--  Defaults (single source of truth; deep-merged into every profile)
-- ---------------------------------------------------------------------
local defaults = {
	version       = 1,

	locked        = true,      -- movers hidden / bars click-through when true

	-- Shared style
	texture       = "SwingTime Flat",
	font          = "Friz Quadrata TT",
	fontSize      = 12,
	fontOutline   = "OUTLINE", -- "NONE" | "OUTLINE" | "THICKOUTLINE"
	showLabel     = true,
	showTimerText = true,

	inCombatAlpha = 1.0,
	oocAlpha      = 0.55,
	spacing       = 4,         -- vertical gap between stacked bars

	colors = {
		bg     = { 0.05, 0.05, 0.05, 0.80 },
		border = { 0.00, 0.00, 0.00, 1.00 },
		text   = { 1.00, 1.00, 1.00, 1.00 },
	},

	-- Per-bar settings. `color` is the fill color for that specific bar.
	bars = {
		mainhand = {
			enabled = true, width = 260, height = 22,
			point = "CENTER", relPoint = "CENTER", x = 0, y = -140,
			color = { 0.30, 0.55, 0.95, 1.00 },
		},
		offhand = {
			enabled = true, width = 260, height = 22,
			point = "CENTER", relPoint = "CENTER", x = 0, y = -166,
			color = { 0.30, 0.80, 0.75, 1.00 },
		},
		ranged = {
			enabled = true, width = 260, height = 22,
			point = "CENTER", relPoint = "CENTER", x = 0, y = -192,
			color = { 0.95, 0.65, 0.25, 1.00 },
		},
		target = {
			enabled = true, width = 260, height = 22,
			point = "CENTER", relPoint = "CENTER", x = 0, y = -218,
			color = { 0.85, 0.30, 0.35, 1.00 },
		},
	},
}
Config.defaults = defaults

-- ---------------------------------------------------------------------
--  Small table helpers
-- ---------------------------------------------------------------------
local function CopyTable(src)
	local dst = {}
	for k, v in pairs(src) do
		if type(v) == "table" then
			dst[k] = CopyTable(v)
		else
			dst[k] = v
		end
	end
	return dst
end
Config.CopyTable = CopyTable

-- Fill any key present in `src` but missing in `dst` (recursively).
local function DeepMergeDefaults(dst, src)
	for k, v in pairs(src) do
		if type(v) == "table" then
			if type(dst[k]) ~= "table" then dst[k] = {} end
			DeepMergeDefaults(dst[k], v)
		elseif dst[k] == nil then
			dst[k] = v
		end
	end
end

-- ---------------------------------------------------------------------
--  Change listeners (bars + config panel subscribe to re-apply live)
-- ---------------------------------------------------------------------
Config.listeners = {}

function Config.OnChange(fn)
	table.insert(Config.listeners, fn)
end

function Config.NotifyChanged()
	for _, fn in ipairs(Config.listeners) do
		fn()
	end
end

-- ---------------------------------------------------------------------
--  Dotted-path get / set  (e.g. "bars.mainhand.width", "colors.bg")
-- ---------------------------------------------------------------------
function Config.Get(path)
	local node = Config.current
	for key in string.gmatch(path, "[^.]+") do
		if type(node) ~= "table" then return nil end
		node = node[key]
	end
	return node
end

-- Set a value by path. Set silent = true to skip the change notification
-- (useful when applying many values, then calling NotifyChanged once).
function Config.Set(path, value, silent)
	local keys = {}
	for key in string.gmatch(path, "[^.]+") do
		keys[#keys + 1] = key
	end
	if #keys == 0 then return end
	local node = Config.current
	for i = 1, #keys - 1 do
		local k = keys[i]
		if type(node[k]) ~= "table" then node[k] = {} end
		node = node[k]
	end
	node[keys[#keys]] = value
	if not silent then
		Config.NotifyChanged()
	end
end

-- ---------------------------------------------------------------------
--  Initialization (called on ADDON_LOADED)
-- ---------------------------------------------------------------------
function Config.Initialize()
	if type(_G.SwingTimeDB) ~= "table" then
		_G.SwingTimeDB = {}
	end
	local db = _G.SwingTimeDB
	if type(db.profiles) ~= "table" then
		db.profiles = {}
	end
	if db.version == nil then
		db.version = defaults.version
	end

	-- Per-character active profile pointer (a plain string).
	if type(_G.SwingTimeActiveProfile) ~= "string" then
		_G.SwingTimeActiveProfile = DEFAULT_PROFILE
	end

	-- Ensure the named profile exists; fall back to Default.
	if type(db.profiles[_G.SwingTimeActiveProfile]) ~= "table" then
		if type(db.profiles[DEFAULT_PROFILE]) ~= "table" then
			db.profiles[DEFAULT_PROFILE] = {}
		end
		_G.SwingTimeActiveProfile = DEFAULT_PROFILE
	end

	Config.current = db.profiles[_G.SwingTimeActiveProfile]
	DeepMergeDefaults(Config.current, defaults)
end

-- ---------------------------------------------------------------------
--  Profile management
-- ---------------------------------------------------------------------
function Config.GetActiveProfileName()
	return _G.SwingTimeActiveProfile
end

function Config.GetProfileNames()
	local names = {}
	for name in pairs(_G.SwingTimeDB.profiles) do
		table.insert(names, name)
	end
	table.sort(names)
	return names
end

-- Create a new profile. If `clone` is true it is a copy of the current
-- profile; otherwise it starts from defaults. Switches to it.
function Config.MakeProfile(name, clone)
	if not name or name == "" then return end
	local profiles = _G.SwingTimeDB.profiles
	if clone then
		profiles[name] = CopyTable(Config.current)
	else
		profiles[name] = {}
		DeepMergeDefaults(profiles[name], defaults)
	end
	Config.ChangeProfile(name)
end

function Config.ChangeProfile(name)
	local profiles = _G.SwingTimeDB.profiles
	if type(profiles[name]) ~= "table" then return end
	_G.SwingTimeActiveProfile = name
	Config.current = profiles[name]
	DeepMergeDefaults(Config.current, defaults)
	Config.NotifyChanged()
end

function Config.DeleteProfile(name)
	local profiles = _G.SwingTimeDB.profiles
	if name == DEFAULT_PROFILE then return end          -- never delete Default
	if _G.SwingTimeActiveProfile == name then
		Config.ChangeProfile(DEFAULT_PROFILE)
	end
	profiles[name] = nil
end

function Config.ResetProfile()
	local name = _G.SwingTimeActiveProfile
	_G.SwingTimeDB.profiles[name] = {}
	Config.current = _G.SwingTimeDB.profiles[name]
	DeepMergeDefaults(Config.current, defaults)
	Config.NotifyChanged()
end
