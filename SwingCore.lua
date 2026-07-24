local addonName, ST = ...

-- =====================================================================
--  SwingCore.lua
--  Independent swing-timing engine written against the documented
--  Blizzard APIs (UnitAttackSpeed, UnitRangedDamage, and the combat log).
--
--  Design:
--   * Absolute-expiry model. Each tracked swing is { expiry, speed }; the
--     remaining time is derived on demand as (expiry - GetTime()). There is
--     no per-frame countdown and no drift.
--   * One unified table keyed by unit -> hand, covering player main-hand /
--     off-hand / ranged and the current target's main-hand.
--   * Haste is applied reactively from the UNIT_ATTACK_SPEED and
--     UNIT_RANGEDDAMAGE events (which fire exactly when a unit's speed
--     changes) rather than polling every frame.
--   * The engine only reacts to events; it runs an OnUpdate solely while
--     the player is actively auto-shooting (to catch movement during the
--     ranged cast window). Bars read the derived remaining time when they
--     render.
-- =====================================================================

local SwingCore = {}
ST.SwingCore = SwingCore

-- ---------------------------------------------------------------------
--  Constants
-- ---------------------------------------------------------------------
local SLOT_MAIN, SLOT_OFF, SLOT_RANGED = 16, 17, 18

-- Combat-log field positions (1-based). Base fields occupy 1..11; the
-- subevent-specific payload follows.
local CL_SUBEVENT, CL_SOURCE, CL_DEST = 2, 4, 8
local CL_SWINGDMG_OFFHAND = 21          -- SWING_DAMAGE: isOffHand
local CL_MISS_TYPE, CL_MISS_OFFHAND = 12, 13
local CL_SPELL_ID = 12                  -- SPELL_*: spellId
local CL_EXTRA_AMOUNT = 15              -- SPELL_EXTRA_ATTACKS: amount (extra swing count)

-- Ranged spell ids of interest.
local SPELL_AUTO_SHOT  = 75
local SPELL_SHOOT_WAND = 5019
local SPELL_FEIGN      = 5384
local AIMED_SHOT = {
	[19434] = true, [20900] = true, [20901] = true,
	[20902] = true, [20903] = true, [20904] = true,
}

-- Slam (Warrior) uses a cast that pauses the swing, so it is handled with a
-- pause/resume model rather than the plain on-swing reset below.
local SLAM_SPELLS = { [1464] = true, [8820] = true, [11604] = true, [11605] = true }

-- Melee abilities that consume / restart the main-hand swing, per class.
-- (Spell ids are game facts; grouped here for our own lookup.)
local ON_SWING_SPELLS = {
	WARRIOR = {
		[78] = 1, [284] = 1, [285] = 1, [1608] = 1, [11564] = 1, [11565] = 1,
		[11566] = 1, [11567] = 1, [25286] = 1,                       -- Heroic Strike
		[845] = 1, [7369] = 1, [11608] = 1, [11609] = 1, [20569] = 1, -- Cleave
	},
	DRUID = {
		[6807] = 1, [6808] = 1, [6809] = 1, [8972] = 1, [9745] = 1, [9880] = 1, [9881] = 1, -- Maul
	},
	HUNTER = {
		[2973] = 1, [14260] = 1, [14261] = 1, [14262] = 1,
		[14263] = 1, [14264] = 1, [14265] = 1, [14266] = 1,         -- Raptor Strike
	},
}

-- Ranged-slot equip locations that are real weapons (relics such as
-- Librams/Idols/Totems are INVTYPE_RELIC and must NOT count).
local RANGED_WEAPON_LOC = {
	INVTYPE_RANGED = true, INVTYPE_RANGEDRIGHT = true, INVTYPE_THROWN = true,
}

-- Weapon subclass ids (item class 2 = Weapon) that use the Auto Shot cast
-- window: Bows (2), Guns (3), Crossbows (18). Wands (19) and Thrown (16) do not.
local AUTOSHOT_SUBCLASS = { [2] = true, [3] = true, [18] = true }

-- ---------------------------------------------------------------------
--  State
-- ---------------------------------------------------------------------
local swings = {
	player = {
		mainhand = { expiry = 0, speed = 2, active = false, itemId = nil },
		offhand  = { expiry = 0, speed = 2, active = false, itemId = nil },
		ranged   = { expiry = 0, speed = 3, active = false },
	},
	target = {
		mainhand = { expiry = 0, speed = 2, active = false },
	},
}
SwingCore.swings = swings

SwingCore.hasOffhand    = false
SwingCore.hasRanged     = false
SwingCore.rangedIsAutoShot = false   -- equipped ranged weapon is a bow/gun/crossbow
SwingCore.hasTarget     = false
SwingCore.isWandClass   = false
SwingCore.rangedCastTime = 0.5
SwingCore.rangedReady   = true

local playerClass
local playerGUID
local targetGUID
local suppressMainCount = 0       -- pending main-hand resets to skip (extra attacks)
local suppressSpeedUntil = 0      -- ignore UNIT_ATTACK_SPEED bursts until this time
local shooting          = false
local lastShotTime      = 0

-- ---------------------------------------------------------------------
--  Timestamp primitives
-- ---------------------------------------------------------------------
local function StartSwing(s, speed)
	if speed and speed > 0 then s.speed = speed end
	s.expiry = GetTime() + s.speed
	s.active = true
	s.paused = nil
end

local function RemainingOf(s)
	local r = s.expiry - GetTime()
	if r < 0 then return 0 end
	if r > s.speed then return s.speed end
	return r
end

-- Haste change: keep the fraction of the swing already completed.
local function Rescale(s, newSpeed)
	if not newSpeed or newSpeed <= 0 then return end
	if s.active and s.speed > 0 then
		local t = GetTime()
		local remaining = s.expiry - t
		if remaining < 0 then remaining = 0 end
		local frac = remaining / s.speed
		s.expiry = t + newSpeed * frac
	end
	s.speed = newSpeed
end

-- Parry-haste: the parrying unit's swing is reduced by 40% of its weapon
-- speed, but never below 20% of weapon speed (and never increased).
local function ParryHaste(s)
	if not s.active then return end
	local t = GetTime()
	local remaining = s.expiry - t
	if remaining <= 0 then return end
	local reduced = remaining - 0.4 * s.speed
	local floor = 0.2 * s.speed
	if reduced < floor then reduced = floor end
	if reduced < remaining then
		s.expiry = t + reduced
	end
end

-- ---------------------------------------------------------------------
--  Speed / weapon helpers
-- ---------------------------------------------------------------------
local function MeleeSpeeds()
	local m, o = UnitAttackSpeed("player")
	if not m or m <= 0 then m = 2 end
	return m, o     -- o is nil / 0 when no off-hand
end

-- Returns: hasRangedWeapon, isAutoShotWeapon (bow/gun/crossbow).
local function ClassifyRanged()
	local itemId = GetInventoryItemID("player", SLOT_RANGED)
	if not itemId then return false, false end
	local loc, classID, subID
	if GetItemInfoInstant then
		local _
		_, _, _, loc, _, classID, subID = GetItemInfoInstant(itemId)
	else
		local _
		_, _, _, _, _, _, _, _, loc, _, _, classID, subID = GetItemInfo(itemId)
	end
	local isRanged = RANGED_WEAPON_LOC[loc] == true
	-- Auto Shot (the ranged attack with the ~0.5s cast window) is hunter-only
	-- and uses a bow / gun / crossbow. Non-hunters with those weapons use
	-- "Shoot", and wands/thrown use "Shoot"/"Throw" -- none of which have a
	-- partial cast window (moving cancels the whole shot), so no overlay.
	local isAutoShot = isRanged and playerClass == "HUNTER"
		and classID == 2 and AUTOSHOT_SUBCLASS[subID] == true
	return isRanged, isAutoShot
end

local function ComputeCastTime()
	if SwingCore.isWandClass then
		SwingCore.rangedCastTime = 0.5
	else
		local speed = UnitRangedDamage("player")
		local base  = ST.RangedDB and ST.RangedDB.GetBaseSpeed()
		local mod = (speed and base and base > 0) and (speed / base) or 1
		SwingCore.rangedCastTime = 0.5 * mod
	end
end

-- Resting ranged state: sitting in the cast window, ready to fire.
local function SetRangedRest()
	local r = swings.player.ranged
	r.expiry = GetTime() + SwingCore.rangedCastTime
	r.active = true
	SwingCore.rangedReady = true
end

-- ---------------------------------------------------------------------
--  Public read API (consumed by Bars.lua)
-- ---------------------------------------------------------------------
function SwingCore.GetSwing(unit, hand)
	local u = swings[unit]
	local s = u and u[hand]
	if not s or not s.active then return 0, 0 end
	if s.paused then return s.paused, s.speed end   -- frozen while a Slam-style cast pauses the swing
	return RemainingOf(s), s.speed
end

-- ---------------------------------------------------------------------
--  Melee
-- ---------------------------------------------------------------------
local function ResetMain()
	-- Extra attacks (Windfury / Sword Spec / Hand of Justice) fire their own
	-- SWING_DAMAGE but must not restart the main-hand; skip one reset per
	-- extra swing announced by SPELL_EXTRA_ATTACKS.
	if suppressMainCount > 0 then
		suppressMainCount = suppressMainCount - 1
		return
	end
	local m = MeleeSpeeds()
	StartSwing(swings.player.mainhand, m)
end

local function ResetOff()
	if not SwingCore.hasOffhand then return end
	local _, o = MeleeSpeeds()
	StartSwing(swings.player.offhand, o)
end

-- Slam-style pause: freeze the main-hand at its current remaining time; the
-- cast completing restarts it, an interrupt/fail resumes it where it was.
local function PauseMain()
	local s = swings.player.mainhand
	if s.active and not s.paused then
		s.paused = RemainingOf(s)
	end
end

local function ResumeMain()
	local s = swings.player.mainhand
	if s.paused then
		s.expiry = GetTime() + s.paused
		s.paused = nil
	end
end

local function HandleOnSwingSpell(spellId)
	local t = ON_SWING_SPELLS[playerClass]
	if t and t[spellId] then
		ResetMain()
	end
end

-- ---------------------------------------------------------------------
--  Ranged
-- ---------------------------------------------------------------------
local function FireRanged()
	local r = swings.player.ranged
	local ns = UnitRangedDamage("player")
	if ns and ns > 0 then r.speed = ns end
	r.expiry = GetTime() + r.speed
	r.active = true
	lastShotTime = GetTime()
	ComputeCastTime()
	SwingCore.rangedReady = false
end

-- Runs only while auto-shooting: refresh the cast window, flag readiness,
-- and hold the shot at the cast window while moving (movement delays it).
local function RangedTick()
	ComputeCastTime()
	local r = swings.player.ranged
	local remaining = r.expiry - GetTime()
	if remaining <= SwingCore.rangedCastTime then
		SwingCore.rangedReady = true
		if GetUnitSpeed("player") > 0 then
			r.expiry = GetTime() + SwingCore.rangedCastTime
		end
	else
		SwingCore.rangedReady = false
	end
end

-- ---------------------------------------------------------------------
--  Target
-- ---------------------------------------------------------------------
local function TargetSpeed()
	local s = UnitAttackSpeed("target")
	if not s or s <= 0 then s = 2 end
	return s
end

local function AcquireTarget()
	if UnitExists("target") and UnitCanAttack("player", "target") then
		targetGUID = UnitGUID("target")
		local s = swings.target.mainhand
		s.speed = TargetSpeed()
		s.expiry = GetTime()     -- swing phase unknown -> reads as ready until first swing
		s.active = true
		SwingCore.hasTarget = true
	else
		targetGUID = nil
		swings.target.mainhand.active = false
		SwingCore.hasTarget = false
	end
end

-- ---------------------------------------------------------------------
--  Weapon / speed refresh
-- ---------------------------------------------------------------------
local function RefreshWeapons()
	local m, o = MeleeSpeeds()
	SwingCore.hasOffhand = (o and o > 0) and true or false

	local newMain = GetInventoryItemID("player", SLOT_MAIN)
	local newOff  = GetInventoryItemID("player", SLOT_OFF)
	local mh, oh = swings.player.mainhand, swings.player.offhand
	if mh.itemId ~= newMain then
		StartSwing(mh, m)
	end
	mh.itemId = newMain
	if oh.itemId ~= newOff and SwingCore.hasOffhand then
		StartSwing(oh, o)
	end
	oh.itemId = newOff

	SwingCore.hasRanged, SwingCore.rangedIsAutoShot = ClassifyRanged()
end

-- ---------------------------------------------------------------------
--  Combat log
-- ---------------------------------------------------------------------
local function OnCombatLog()
	local e = { CombatLogGetCurrentEventInfo() }
	local sub    = e[CL_SUBEVENT]
	local source = e[CL_SOURCE]
	local dest   = e[CL_DEST]

	-- Player's own swings and abilities.
	if source == playerGUID then
		if sub == "SPELL_EXTRA_ATTACKS" then
			suppressMainCount = suppressMainCount + (e[CL_EXTRA_AMOUNT] or 1)
		elseif sub == "SWING_DAMAGE" then
			if e[CL_SWINGDMG_OFFHAND] then ResetOff() else ResetMain() end
		elseif sub == "SWING_MISSED" then
			if e[CL_MISS_OFFHAND] then ResetOff() else ResetMain() end
		elseif sub == "SPELL_DAMAGE" or sub == "SPELL_MISSED" then
			HandleOnSwingSpell(e[CL_SPELL_ID])
		end
	end

	-- Parry-haste against the player (player parried an incoming swing):
	-- the player's next swing is pulled in to <= 20% of weapon speed.
	if dest == playerGUID and sub == "SWING_MISSED" and e[CL_MISS_TYPE] == "PARRY" then
		ParryHaste(swings.player.mainhand)
	end

	-- Target's swings.
	if targetGUID then
		if source == targetGUID and (sub == "SWING_DAMAGE" or sub == "SWING_MISSED") then
			StartSwing(swings.target.mainhand, TargetSpeed())
		elseif source == playerGUID and dest == targetGUID
			and sub == "SWING_MISSED" and e[CL_MISS_TYPE] == "PARRY" then
			-- Player's swing parried by the target -> the target speeds up.
			ParryHaste(swings.target.mainhand)
		end
	end
end

-- ---------------------------------------------------------------------
--  Event frame
-- ---------------------------------------------------------------------
local frame = CreateFrame("Frame", "SwingTimeSwingCore", UIParent)
SwingCore.frame = frame

local function OnEvent(_, event, ...)
	if not playerGUID then return end

	if event == "COMBAT_LOG_EVENT_UNFILTERED" then
		OnCombatLog()

	elseif event == "PLAYER_TARGET_CHANGED" then
		AcquireTarget()

	elseif event == "PLAYER_EQUIPMENT_CHANGED" then
		local slot = ...
		if slot == SLOT_MAIN or slot == SLOT_OFF then
			RefreshWeapons()
		elseif slot == SLOT_RANGED then
			SwingCore.hasRanged, SwingCore.rangedIsAutoShot = ClassifyRanged()
			local rs = UnitRangedDamage("player")
			if rs and rs > 0 then swings.player.ranged.speed = rs end
			ComputeCastTime()
			SetRangedRest()
		end

	elseif event == "UNIT_ATTACK_SPEED" then
		local unit = ...
		if unit == "player" then
			-- Ignore the transient bursts fired during a shapeshift; the
			-- settled speed is applied by the timer below.
			if GetTime() >= suppressSpeedUntil then
				local m, o = MeleeSpeeds()
				Rescale(swings.player.mainhand, m)
				if SwingCore.hasOffhand and o and o > 0 then
					Rescale(swings.player.offhand, o)
				end
			end
		elseif unit == "target" and targetGUID then
			Rescale(swings.target.mainhand, TargetSpeed())
		end

	elseif event == "UPDATE_SHAPESHIFT_FORM" then
		-- A form change fires a burst of transient UNIT_ATTACK_SPEED events;
		-- suppress them briefly, then rescale melee to the settled speed.
		suppressSpeedUntil = GetTime() + 0.15
		if C_Timer and C_Timer.After then
			C_Timer.After(0.15, function()
				local m, o = MeleeSpeeds()
				Rescale(swings.player.mainhand, m)
				if SwingCore.hasOffhand and o and o > 0 then
					Rescale(swings.player.offhand, o)
				end
			end)
		end

	elseif event == "UNIT_SPELLCAST_START" then
		local _, _, spellId = ...
		if SLAM_SPELLS[spellId] then PauseMain() end

	elseif event == "UNIT_SPELLCAST_INTERRUPTED" or event == "UNIT_SPELLCAST_FAILED" then
		local _, _, spellId = ...
		if SLAM_SPELLS[spellId] then ResumeMain() end

	elseif event == "UNIT_RANGEDDAMAGE" then
		if ... == "player" then
			Rescale(swings.player.ranged, UnitRangedDamage("player"))
		end

	elseif event == "START_AUTOREPEAT_SPELL" then
		shooting = true

	elseif event == "STOP_AUTOREPEAT_SPELL" then
		shooting = false
		SetRangedRest()

	elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
		local unit, _, spellId = ...
		if unit == "player" then
			if spellId == SPELL_AUTO_SHOT or spellId == SPELL_SHOOT_WAND then
				FireRanged()
			elseif AIMED_SHOT[spellId] then
				ComputeCastTime()
				SetRangedRest()
			elseif spellId == SPELL_FEIGN then
				lastShotTime = GetTime()
				ComputeCastTime()
				SetRangedRest()
			elseif SLAM_SPELLS[spellId] then
				-- Slam finished: it consumes the swing and starts a fresh one.
				StartSwing(swings.player.mainhand, (MeleeSpeeds()))
			end
		end

	elseif event == "UNIT_SPELLCAST_FAILED_QUIET" then
		local unit, _, spellId = ...
		if unit == "player" and spellId == SPELL_AUTO_SHOT and shooting then
			local r = swings.player.ranged
			if (GetTime() - lastShotTime) > (r.speed - SwingCore.rangedCastTime) then
				r.expiry = GetTime() + SwingCore.rangedCastTime + 0.5
			end
		end

	elseif event == "PLAYER_ENTERING_WORLD" then
		RefreshWeapons()
		AcquireTarget()
	end
end
frame:SetScript("OnEvent", OnEvent)

frame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
frame:RegisterEvent("PLAYER_TARGET_CHANGED")
frame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
frame:RegisterEvent("UNIT_ATTACK_SPEED")
frame:RegisterEvent("UNIT_RANGEDDAMAGE")
frame:RegisterEvent("UPDATE_SHAPESHIFT_FORM")
frame:RegisterEvent("START_AUTOREPEAT_SPELL")
frame:RegisterEvent("STOP_AUTOREPEAT_SPELL")
frame:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
frame:RegisterEvent("UNIT_SPELLCAST_FAILED_QUIET")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
-- Player-only spellcast events for the Slam pause/resume model.
frame:RegisterUnitEvent("UNIT_SPELLCAST_START", "player")
frame:RegisterUnitEvent("UNIT_SPELLCAST_INTERRUPTED", "player")
frame:RegisterUnitEvent("UNIT_SPELLCAST_FAILED", "player")

-- OnUpdate does nothing unless the player is auto-shooting.
frame:SetScript("OnUpdate", function()
	if shooting then RangedTick() end
end)

-- Jumping out of Feign Death restarts the shot clock.
if type(hooksecurefunc) == "function" and type(_G.JumpOrAscendStart) == "function" then
	hooksecurefunc("JumpOrAscendStart", function()
		if SwingCore.hasRanged then
			lastShotTime = GetTime()
			ComputeCastTime()
			SetRangedRest()
		end
	end)
end

-- ---------------------------------------------------------------------
--  Init
-- ---------------------------------------------------------------------
local function SeedSpeeds()
	local m, o = MeleeSpeeds()
	local mh, oh = swings.player.mainhand, swings.player.offhand
	mh.speed = m
	SwingCore.hasOffhand = (o and o > 0) and true or false
	oh.speed = (o and o > 0) and o or 2

	local rs = UnitRangedDamage("player")
	swings.player.ranged.speed = (rs and rs > 0) and rs or 3
end

function SwingCore.Initialize()
	playerGUID = UnitGUID("player")
	local _, class = UnitClass("player")
	playerClass = class
	SwingCore.isWandClass = (class == "MAGE" or class == "PRIEST" or class == "WARLOCK")

	SeedSpeeds()

	local mh, oh = swings.player.mainhand, swings.player.offhand
	mh.itemId = GetInventoryItemID("player", SLOT_MAIN)
	oh.itemId = GetInventoryItemID("player", SLOT_OFF)
	mh.expiry, mh.active = GetTime(), true      -- reads as "ready" until first swing
	oh.expiry, oh.active = GetTime(), true

	SwingCore.hasRanged, SwingCore.rangedIsAutoShot = ClassifyRanged()
	ComputeCastTime()
	SetRangedRest()

	AcquireTarget()

	-- UnitAttackSpeed can return 0 briefly right after login; re-seed once.
	if C_Timer and C_Timer.After then
		C_Timer.After(3, function()
			SeedSpeeds()
			SwingCore.hasRanged, SwingCore.rangedIsAutoShot = ClassifyRanged()
			ComputeCastTime()
		end)
	end
end
