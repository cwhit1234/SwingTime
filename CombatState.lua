local addonName, ST = ...

-- =====================================================================
--  CombatState.lua
--  Derives the two states the on-screen warnings need: is the player
--  actually auto-attacking, and is the current target out of range.
--
--  Design:
--   * Detection only. This file owns no frames and draws nothing; it
--     publishes booleans that Warnings.lua reads.
--   * SwingCore.lua is deliberately untouched. Its contract is to run an
--     OnUpdate only while auto-shooting, and a range poll is a different
--     concern at a different cadence. Everything needed from it here is
--     already public read-only state. The events it registers are
--     re-registered on our own frame -- WoW events are multicast, so
--     there is no conflict.
--   * Polled at 10 Hz rather than per frame. That beats human reaction
--     time and is more responsive than Blizzard's own action-bar range
--     colouring (TOOLTIP_UPDATE_TIME = 0.2).
--   * Every uncertain API is feature-detected once at Initialize, because
--     Classic Era 1.15.x is mid-migration to the C_Spell namespace.
-- =====================================================================

local CS = {}
ST.CombatState = CS

-- Published state (read by Warnings.lua).
CS.outOfRange    = false
CS.attacking     = false
CS.hasLiveTarget = false

-- ---------------------------------------------------------------------
--  Tuning
-- ---------------------------------------------------------------------
local POLL          = 0.1    -- detection tick (10 Hz)
local SHOW_DEBOUNCE = 0.15   -- raw signal must hold this long to warn
local HIDE_DEBOUNCE = 0.30   -- ...and this long to stop warning
local ERR_LATCH     = 1.2    -- how long a range error keeps us "out of range"
local UNKNOWN_DECAY = 1.0    -- give up and clear after this long with no signal
-- "Stopped attacking" must be sustained before we believe it. Auto Shot has a
-- cast window and a reload gap, so several of the state queries dip for a tick
-- between shots; without this the warning blinks once per shot cycle.
local ATTACK_DEBOUNCE = 0.5

-- Auto-attack spell ids (game facts; grouped here for our own lookup).
local SPELL_ATTACK     = 6603
local SPELL_AUTO_SHOT  = 75
local SPELL_SHOOT_WAND = 5019

-- ---------------------------------------------------------------------
--  Local state
-- ---------------------------------------------------------------------
local attackSlot, autoRepeatSlot   -- action slots holding Attack / auto-repeat
local barsDirty      = true        -- rescan the action bars on the next tick
local meleeOn        = false       -- PLAYER_ENTER_COMBAT / PLAYER_LEAVE_COMBAT latch
local autoRepeatOn   = false       -- START_ / STOP_AUTOREPEAT_SPELL latch
local errLatchUntil  = 0           -- UI_ERROR_MESSAGE "out of range" latch
local lastMainExpiry = 0           -- to notice that a main-hand swing landed
local lastRangedExpiry = 0         -- ...and that a shot went off
local notAttackingSince            -- when the attack signals first went quiet
local accum          = 0           -- poll accumulator

-- Debounce bookkeeping: the raw reading and when it last changed.
local rawOut, rawOutSince = false, 0
local lastKnownAt = 0

-- Resolved API references (nil when unavailable on this client).
local IsSpellInRangeFn
local IsCurrentSpellFn

-- ---------------------------------------------------------------------
--  Out-of-range error strings
--  Matched exactly against the localized globals rather than by substring,
--  so this stays locale-safe and cannot false-positive on other errors.
-- ---------------------------------------------------------------------
local OOR = {}
do
	local keys = {
		"ERR_OUT_OF_RANGE",
		"SPELL_FAILED_OUT_OF_RANGE",
		"ERR_SPELL_OUT_OF_RANGE",
		"SPELL_FAILED_TOO_CLOSE",
	}
	for _, g in ipairs(keys) do
		local s = _G[g]
		if type(s) == "string" and s ~= "" then OOR[s] = true end
	end
end

-- ---------------------------------------------------------------------
--  API resolution (once, at init)
-- ---------------------------------------------------------------------
local function ResolveAPIs()
	-- Range: prefer the modern namespace, fall back to the global. The
	-- Classic global takes a localized spell NAME, so wrap it to keep one
	-- call signature (spellId, unit) for the caller.
	if type(C_Spell) == "table" and type(C_Spell.IsSpellInRange) == "function" then
		IsSpellInRangeFn = function(spellId, unit)
			local ok, r = pcall(C_Spell.IsSpellInRange, spellId, unit)
			if not ok then return nil end
			if r == true then return 1 elseif r == false then return 0 end
			return r
		end
	elseif type(IsSpellInRange) == "function" then
		IsSpellInRangeFn = function(spellId, unit)
			local name = GetSpellInfo and GetSpellInfo(spellId)
			if not name then return nil end
			local ok, r = pcall(IsSpellInRange, name, unit)
			if not ok then return nil end
			if r == true then return 1 elseif r == false then return 0 end
			return r
		end
	end

	-- "Is this spell toggled on right now" -- the no-action-bar fallback.
	if type(C_Spell) == "table" and type(C_Spell.IsCurrentSpell) == "function" then
		IsCurrentSpellFn = function(id)
			local ok, r = pcall(C_Spell.IsCurrentSpell, id)
			if ok then return r end
			return nil
		end
	elseif type(IsCurrentSpell) == "function" then
		IsCurrentSpellFn = function(id)
			local ok, r = pcall(IsCurrentSpell, id)
			if ok then return r end
			return nil
		end
	end
end

-- ---------------------------------------------------------------------
--  Action-bar scan
--  Finds the slots holding Attack and the ranged auto-repeat, which give
--  us the most accurate range and attack-state queries available.
-- ---------------------------------------------------------------------
local function ScanActionBars()
	attackSlot, autoRepeatSlot = nil, nil
	if type(HasAction) ~= "function" then return end
	local getInfo = (type(GetActionInfo) == "function") and GetActionInfo or nil

	for slot = 1, 120 do
		if HasAction(slot) then
			local matched = false

			-- Match on spell id. IsAttackAction / IsAutoRepeatAction report
			-- whether that attack is running RIGHT NOW, not what the action
			-- is, so they only find the slot while you are already attacking
			-- -- useless for a scan that runs at login or on a bar swap.
			if getInfo then
				local ok, aType, id = pcall(getInfo, slot)
				if ok and aType == "spell" and id then
					if id == SPELL_ATTACK then
						if not attackSlot then attackSlot = slot end
						matched = true
					elseif id == SPELL_AUTO_SHOT or id == SPELL_SHOOT_WAND then
						if not autoRepeatSlot then autoRepeatSlot = slot end
						matched = true
					end
				end
			end

			-- Fallback for clients without GetActionInfo. Order matters here:
			-- on some builds IsAttackAction() is also true for Auto Shot.
			if not matched then
				if IsAutoRepeatAction and IsAutoRepeatAction(slot) then
					if not autoRepeatSlot then autoRepeatSlot = slot end
				elseif IsAttackAction and IsAttackAction(slot) then
					if not attackSlot then attackSlot = slot end
				end
			end

			if attackSlot and autoRepeatSlot then return end
		end
	end
end

-- ---------------------------------------------------------------------
--  Range
-- ---------------------------------------------------------------------
-- Which weapon's range applies right now.
local function PickMode()
	local m = ST.Config.Get("warnings.rangeMode")
	if m == "melee" or m == "ranged" then return m end   -- user override

	if autoRepeatOn then return "ranged" end
	if meleeOn then return "melee" end

	-- Idle: guess from class and equipment.
	local Core = ST.SwingCore
	if Core and Core.hasRanged then
		if Core.rangedIsAutoShot then return "ranged" end   -- hunter with a bow
		if Core.isWandClass then return "ranged" end        -- mage/priest/warlock wand
	end
	return "melee"
end

-- Returns 1 = in range, 0 = out of range, nil = unknown.
-- Unknown must never *start* a warning; the caller holds and decays instead.
local function RawInRange(mode)
	-- Tier A: exact game truth (includes combat reach). Needs the action on a bar.
	local slot = (mode == "ranged") and autoRepeatSlot or attackSlot
	if slot and type(IsActionInRange) == "function" then
		local ok, r = pcall(IsActionInRange, slot, "target")
		if ok then
			if r == true or r == 1 then return 1 end
			if r == false or r == 0 then return 0 end
		end
	end

	-- Tier B: spell range API (availability varies; resolved once at init).
	if IsSpellInRangeFn then
		local id = SPELL_ATTACK
		if mode == "ranged" then
			id = (ST.SwingCore and ST.SwingCore.rangedIsAutoShot)
				and SPELL_AUTO_SHOT or SPELL_SHOOT_WAND
		end
		local r = IsSpellInRangeFn(id, "target")
		if r == 1 or r == 0 then return r end
	end

	-- Tier C: coarse proxy, MELEE ONLY (~9.9 yd vs a real 5 yd + combat reach).
	-- There is no acceptable coarse proxy for the 5-35 yd ranged band, so
	-- ranged deliberately FAILS OPEN: no signal, therefore no warning.
	if mode == "melee" and type(CheckInteractDistance) == "function" then
		local ok, r = pcall(CheckInteractDistance, "target", 3)
		if ok and r ~= nil then return r and 1 or 0 end
	end

	return nil
end

-- ---------------------------------------------------------------------
--  Attack state
-- ---------------------------------------------------------------------
-- The event latches are edge-triggered, so they go stale across a /reload
-- mid-combat. Polling IsCurrentAction reconciles them within one tick.
local function ReconcileAttackState()
	-- Melee: IsCurrentAction is the toggle state -- the same thing that draws
	-- the checked border on the attack button.
	if attackSlot and type(IsCurrentAction) == "function" then
		local ok, r = pcall(IsCurrentAction, attackSlot)
		if ok and r ~= nil then meleeOn = (r and true or false) end
	end

	-- Ranged: deliberately NOT IsCurrentAction. For an auto-repeat spell that
	-- is only true during the cast window and goes false between shots, which
	-- blinks the warning once per shot cycle. IsAutoRepeatAction is the state
	-- Blizzard uses to keep the auto-repeat flash running continuously.
	if autoRepeatSlot and type(IsAutoRepeatAction) == "function" then
		local ok, r = pcall(IsAutoRepeatAction, autoRepeatSlot)
		if ok and r ~= nil then autoRepeatOn = (r and true or false) end
	end

	-- No Attack on any action bar: fall back to the spell query.
	if not attackSlot and IsCurrentSpellFn then
		local r = IsCurrentSpellFn(SPELL_ATTACK)
		if r ~= nil then meleeOn = (r and true or false) end
	end
end

-- A main-hand swing landing proves we are attacking. Reading the expiry
-- costs nothing; registering a second COMBAT_LOG_EVENT_UNFILTERED handler
-- would double the cost of the addon's hottest event. A haste rescale can
-- make this read true spuriously, but a false true only ever *suppresses*
-- a warning, which is the safe direction to fail.
local function SwingLanded()
	local Core = ST.SwingCore
	if not (Core and Core.swings) then return false end
	local p = Core.swings.player
	local changed = false

	local mh = p.mainhand
	if mh and mh.expiry ~= lastMainExpiry then
		lastMainExpiry = mh.expiry
		if mh.active then changed = true end
	end

	-- Ranged too: a hunter mid-volley is unambiguously attacking, and this
	-- holds through the reload gap where the action-state queries dip.
	local r = p.ranged
	if r and r.expiry ~= lastRangedExpiry then
		lastRangedExpiry = r.expiry
		if r.active then changed = true end
	end

	return changed
end

-- ---------------------------------------------------------------------
--  Events
-- ---------------------------------------------------------------------
local frame = CreateFrame("Frame", "SwingTimeCombatState", UIParent)
CS.frame = frame

-- 1.15 fires (errorType, message); older builds fired (message).
local function OnUIError(a, b)
	local msg = (type(b) == "string") and b or a
	if msg and OOR[msg] then
		errLatchUntil = GetTime() + ERR_LATCH
	end
end

frame:SetScript("OnEvent", function(_, event, ...)
	if event == "PLAYER_ENTER_COMBAT" then
		-- NOT the combat-lockdown event: in Classic this pair is the melee
		-- auto-attack toggle (Blizzard's own ActionButton.lua uses it to
		-- drive the attack-button flash).
		meleeOn = true
	elseif event == "PLAYER_LEAVE_COMBAT" then
		meleeOn = false
	elseif event == "START_AUTOREPEAT_SPELL" then
		autoRepeatOn = true
	elseif event == "STOP_AUTOREPEAT_SPELL" then
		autoRepeatOn = false
	elseif event == "UI_ERROR_MESSAGE" then
		OnUIError(...)
	elseif event == "PLAYER_TARGET_CHANGED" then
		-- A fresh target invalidates the debounce; start clean.
		errLatchUntil = 0
		rawOut, rawOutSince = false, GetTime()
		CS.outOfRange = false
	else
		-- Anything that can remap or repopulate the action bars.
		barsDirty = true
	end
end)

-- RegisterEvent throws on an event name the client doesn't know, which would
-- abort the rest of this file and leave the module half-defined. Event names
-- do get retired between builds, so register defensively: a missing event
-- costs us one refresh trigger, not the whole feature.
CS.unsupportedEvents = {}
local function SafeRegister(event)
	if not pcall(frame.RegisterEvent, frame, event) then
		CS.unsupportedEvents[#CS.unsupportedEvents + 1] = event
	end
end

SafeRegister("PLAYER_ENTER_COMBAT")
SafeRegister("PLAYER_LEAVE_COMBAT")
SafeRegister("START_AUTOREPEAT_SPELL")
SafeRegister("STOP_AUTOREPEAT_SPELL")
SafeRegister("UI_ERROR_MESSAGE")
SafeRegister("PLAYER_TARGET_CHANGED")
-- Action-bar invalidation (bonus bar / shapeshift matter for druids and
-- stance warriors, whose slots 1-12 remap).
SafeRegister("ACTIONBAR_SLOT_CHANGED")
SafeRegister("ACTIONBAR_PAGE_CHANGED")
SafeRegister("UPDATE_BONUS_ACTIONBAR")
SafeRegister("UPDATE_SHAPESHIFT_FORM")
-- Renamed across client versions; whichever exists here will take.
SafeRegister("LEARNED_SPELL_IN_TAB")
SafeRegister("LEARNED_SPELL_IN_SKILL_LINE")
SafeRegister("PLAYER_ENTERING_WORLD")

-- ---------------------------------------------------------------------
--  Tick
-- ---------------------------------------------------------------------
function CS.Update(elapsed)
	accum = accum + (elapsed or 0)
	if accum < POLL then return end
	accum = 0

	if barsDirty then
		barsDirty = false
		ScanActionBars()
	end

	local now = GetTime()

	CS.hasLiveTarget = UnitExists("target")
		and UnitCanAttack("player", "target")
		and not UnitIsDeadOrGhost("target")
		and true or false

	ReconcileAttackState()

	-- Evaluated unconditionally: it advances the expiry baselines, so short-
	-- circuiting past it would leave them stale and read as a phantom swing on
	-- the first tick after auto-attack stops.
	local swung = SwingLanded()

	-- Any of the three signals counts, so a hunter shooting at 30 yd and a
	-- warrior swinging in melee are both "attacking" with no intent-guessing.
	local rawAttacking = (meleeOn or autoRepeatOn or swung) and true or false

	if rawAttacking then
		-- Clear the warning the instant anything says we're attacking.
		CS.attacking = true
		notAttackingSince = nil
	else
		-- ...but require the silence to be sustained before believing it, so
		-- a dip between auto-shots can't flash the warning.
		notAttackingSince = notAttackingSince or now
		if now - notAttackingSince >= ATTACK_DEBOUNCE then
			CS.attacking = false
		end
	end

	if not CS.hasLiveTarget then
		rawOut, rawOutSince = false, now
		CS.outOfRange = false
		return
	end

	local r = RawInRange(PickMode())

	-- The error latch is additive: it can force "out of range" true (catching
	-- big-reach mobs where the coarse proxy lies), but never forces it false.
	local raw
	if now < errLatchUntil then
		raw = true
	elseif r == nil then
		-- No usable signal. Hold the current state, then decay to false so a
		-- stale warning cannot stick around forever.
		if now - lastKnownAt > UNKNOWN_DECAY then
			CS.outOfRange = false
			rawOut = false
		end
		return
	else
		raw = (r == 0)
	end
	lastKnownAt = now

	if raw ~= rawOut then
		rawOut, rawOutSince = raw, now
	end

	-- Asymmetric debounce: warn quickly, clear a little slower, so strafing
	-- across the range boundary cannot make the text strobe.
	local held = now - rawOutSince
	if rawOut and not CS.outOfRange and held >= SHOW_DEBOUNCE then
		CS.outOfRange = true
	elseif (not rawOut) and CS.outOfRange and held >= HIDE_DEBOUNCE then
		CS.outOfRange = false
	end
end

-- ---------------------------------------------------------------------
--  Init
-- ---------------------------------------------------------------------
function CS.Initialize()
	ResolveAPIs()
	ScanActionBars()
	barsDirty = false

	-- Seed the latches so a /reload mid-combat is correct immediately
	-- rather than waiting for the first reconcile tick.
	ReconcileAttackState()

	local Core = ST.SwingCore
	if Core and Core.swings then
		local p = Core.swings.player
		if p.mainhand then lastMainExpiry = p.mainhand.expiry end
		if p.ranged then lastRangedExpiry = p.ranged.expiry end
	end
	lastKnownAt = GetTime()
end
