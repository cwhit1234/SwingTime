local addonName, ST = ...

-- =====================================================================
--  Core.lua
--  Addon bootstrap: initializes storage and modules, tracks combat state
--  (for bar opacity), drives the bar animation, and owns the slash
--  commands. Swing timing lives entirely in SwingCore.lua.
-- =====================================================================

local Core = {}
ST.Core = Core

ST.inCombat = false
ST.initialized = false

-- Set once both warning modules have initialized cleanly; gates every call
-- into them so a load failure there can't take the rest of the addon down.
local warningsReady = false

local frame = CreateFrame("Frame", "SwingTimeCore", UIParent)
Core.frame = frame

-- ---------------------------------------------------------------------
--  Startup
-- ---------------------------------------------------------------------
local function OnPlayerLogin()
	if ST.initialized then return end
	ST.playerGUID = UnitGUID("player")
	local _, class = UnitClass("player")
	ST.playerClass = class

	ST.SwingCore.Initialize()
	ST.Bars.Initialize()

	-- The warning modules are optional extras: the swing bars and the config
	-- window must still come up if either one failed to load.
	if ST.CombatState and ST.CombatState.Initialize
		and ST.Warnings and ST.Warnings.Initialize then
		ST.CombatState.Initialize()
		ST.Warnings.Initialize()
		warningsReady = true
	end

	if ST.Panel and ST.Panel.Initialize then
		ST.Panel.Initialize()
	end

	ST.inCombat = (InCombatLockdown() and true) or (UnitAffectingCombat("player") and true) or false
	ST.initialized = true
end

-- ---------------------------------------------------------------------
--  Event handling (bootstrap + combat state only)
-- ---------------------------------------------------------------------
frame:SetScript("OnEvent", function(_, event, ...)
	if event == "ADDON_LOADED" then
		if ... == addonName then
			ST.Config.Initialize()
		end
	elseif event == "PLAYER_LOGIN" then
		OnPlayerLogin()
	elseif event == "PLAYER_ENTERING_WORLD" then
		if ST.initialized then
			ST.Bars.ApplyAll()
			if warningsReady then ST.Warnings.ApplyAll() end
		end
	elseif event == "PLAYER_REGEN_DISABLED" then
		ST.inCombat = true
	elseif event == "PLAYER_REGEN_ENABLED" then
		ST.inCombat = false
	end
end)

frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("PLAYER_REGEN_ENABLED")
frame:RegisterEvent("PLAYER_REGEN_DISABLED")

-- Display driver (reads derived state each frame; no timing math here).
-- CombatState must tick first so the warnings read fresh state, and it is
-- driven from here rather than from its own frame because this one is
-- always shown -- a hidden frame's OnUpdate never runs again.
frame:SetScript("OnUpdate", function(_, elapsed)
	if not ST.initialized then return end
	ST.Bars.OnUpdate(elapsed)
	if warningsReady then
		ST.CombatState.Update(elapsed)   -- must tick before the warnings read it
		ST.Warnings.OnUpdate(elapsed)
	end
end)

-- ---------------------------------------------------------------------
--  Slash commands
-- ---------------------------------------------------------------------
local function SetLocked(locked)
	ST.Config.Set("locked", locked)   -- fires listeners -> bars re-apply lock/visibility
end
ST.SetLocked = SetLocked

SLASH_SWINGTIME1 = "/swingtime"
SLASH_SWINGTIME2 = "/st"
local PREFIX = "|cff33aaffSwingTime|r"

SlashCmdList["SWINGTIME"] = function(msg)
	local cmd = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
	local L = ST.L
	if cmd == "lock" then
		SetLocked(true)
		print(PREFIX .. ": " .. L["Lock bars"])
	elseif cmd == "unlock" or cmd == "move" then
		SetLocked(false)
		print(PREFIX .. ": " .. L["Drag the bars to reposition them, then lock."])
	elseif cmd == "toggle" then
		SetLocked(not ST.Config.Get("locked"))
		local locked = ST.Config.Get("locked")
		print(PREFIX .. ": " .. (locked and L["Lock bars"] or L["Drag the bars to reposition them, then lock."]))
	elseif cmd == "config" or cmd == "options" or cmd == "" then
		if ST.OpenConfig then
			ST.OpenConfig()
		end
	else
		print(PREFIX .. " " .. L["Commands:"])
		print("  " .. L["/st config - open options"])
		print("  " .. L["/st unlock - unlock bars for moving"])
		print("  " .. L["/st lock - lock bars"])
		print("  " .. L["/st toggle - toggle lock"])
	end
end
