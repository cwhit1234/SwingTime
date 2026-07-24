local addonName, ST = ...

-- =====================================================================
--  RangedDB.lua
--  Resolves the equipped ranged weapon's BASE (unhasted) speed, used to
--  derive the ranged haste modifier (UnitRangedDamage returns the hasted
--  speed; base / hasted gives the modifier that scales the ~0.5s cast
--  window). Rather than shipping a giant static itemID table, we scan the
--  weapon tooltip for its "Speed X.XX" line, with an optional seed table
--  and a sane fallback.
-- =====================================================================

local RangedDB = {}
ST.RangedDB = RangedDB

local RANGED_SLOT = 18

-- Optional seed of known base speeds by itemID (tooltip scan covers the rest).
RangedDB.baseSpeeds = {}

local scanTip
local function EnsureTip()
	if not scanTip then
		scanTip = CreateFrame("GameTooltip", "SwingTimeScanTooltip", UIParent, "GameTooltipTemplate")
		scanTip:SetOwner(UIParent, "ANCHOR_NONE")
	end
	return scanTip
end

local SPEED_WORD = _G.SPEED or "Speed"
local SPEED_NUM  = "([0-9]+%.[0-9]+)"

-- Returns the base (unhasted) speed of the equipped ranged weapon, or nil.
function RangedDB.GetBaseSpeed()
	local itemId = GetInventoryItemID("player", RANGED_SLOT)
	if not itemId then return nil end

	local seeded = RangedDB.baseSpeeds[itemId]
	if seeded then return seeded end

	local tip = EnsureTip()
	tip:ClearLines()
	tip:SetInventoryItem("player", RANGED_SLOT)
	for i = 1, tip:NumLines() do
		local right = _G["SwingTimeScanTooltipTextRight" .. i]
		local text = right and right:GetText()
		if text and text:find(SPEED_WORD, 1, true) then
			local s = text:match(SPEED_NUM)
			if s then
				local n = tonumber(s)
				RangedDB.baseSpeeds[itemId] = n   -- cache
				return n
			end
		end
	end
	return nil
end
