local addonName, ST = ...

-- =====================================================================
--  Warnings.lua
--  A centered, draggable block of on-screen text warnings driven by
--  CombatState.lua: "OUT OF RANGE" and "NOT ATTACKING".
--
--  Design:
--   * One container frame holding one FontString per message, so the
--     block has a single saved position and a single mover.
--   * The container anchors by its own TOP edge. Anchoring by CENTER and
--     resizing as lines appear would grow the block symmetrically and
--     make the first line visibly jump; anchoring by TOP grows it
--     downward only, so line 1 never moves.
--   * Each message carries its own font, size, outline and color; nothing
--     is inherited from the bar style settings.
--   * Driven from Core's always-shown frame rather than its own OnUpdate,
--     because the container is hidden when nothing is showing and a
--     hidden frame's OnUpdate never runs again.
-- =====================================================================

local Warnings = {}
ST.Warnings = Warnings

local WHITE = [[Interface\Buttons\WHITE8X8]]

-- Fixed top-to-bottom order. Out of range is the more actionable message,
-- so it sits on top; this is deliberately not user-configurable.
local WARN_KEYS = { "range", "attack" }

-- Keeps the mover grabbable even when the text is short or hidden.
local MIN_W, MIN_H = 160, 24

Warnings.lines = {}
Warnings.lastSig = nil

local function DefaultText(key)
	local L = ST.L
	if key == "range" then return L["OUT OF RANGE"] end
	return L["NOT ATTACKING"]
end

-- ---------------------------------------------------------------------
--  Frame
-- ---------------------------------------------------------------------
local function CreateWarningFrame()
	local f = CreateFrame("Frame", "SwingTimeWarnings", UIParent, "BackdropTemplate")
	f:SetSize(MIN_W, MIN_H)
	f:SetFrameStrata("MEDIUM")   -- above the world, below the config window
	f:SetMovable(true)
	f:SetClampedToScreen(true)
	f:RegisterForDrag("LeftButton")
	f:EnableMouse(false)         -- click-through while locked
	f:Hide()
	f:SetScript("OnDragStart", function(self)
		if not ST.Config.Get("locked") then self:StartMoving() end
	end)
	f:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		local point, _, relPoint, x, y = self:GetPoint()
		ST.Config.Set("warnings.point", point, true)
		ST.Config.Set("warnings.relPoint", relPoint, true)
		ST.Config.Set("warnings.x", x, true)
		ST.Config.Set("warnings.y", y, true)
	end)

	for _, key in ipairs(WARN_KEYS) do
		local fs = f:CreateFontString(nil, "OVERLAY")
		fs:SetJustifyH("CENTER")
		fs:Hide()
		Warnings.lines[key] = fs
	end

	-- Mover overlay: same treatment as the bars, shown only while unlocked.
	local mover = CreateFrame("Frame", nil, f, "BackdropTemplate")
	mover:SetAllPoints(f)
	mover:SetFrameStrata("HIGH")
	mover:EnableMouse(false)      -- clicks fall through to the drag handler
	mover:Hide()
	if mover.SetBackdrop then
		mover:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
		mover:SetBackdropColor(0.10, 0.55, 1.0, 0.30)
		mover:SetBackdropBorderColor(0.35, 0.80, 1.0, 1.0)
	else
		local mbg = mover:CreateTexture(nil, "BACKGROUND")
		mbg:SetAllPoints()
		mbg:SetColorTexture(0.10, 0.55, 1.0, 0.30)
	end
	mover.text = mover:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	mover.text:SetPoint("BOTTOM", mover, "TOP", 0, 2)
	f.mover = mover

	return f
end

-- ---------------------------------------------------------------------
--  Styling / layout
-- ---------------------------------------------------------------------
function Warnings.ApplyStyle()
	for _, key in ipairs(WARN_KEYS) do
		local cfg = ST.Config.Get("warnings." .. key)
		local fs = Warnings.lines[key]
		if cfg and fs then
			local outline = cfg.fontOutline
			local flags = (outline == "NONE") and "" or outline
			-- SetFont returns false for an unreadable path and leaves the
			-- string invisible with no error, so fall back explicitly.
			if not fs:SetFont(ST.Media.Font(cfg.font), cfg.fontSize, flags) then
				fs:SetFont([[Fonts\FRIZQT__.TTF]], cfg.fontSize, flags)
			end
			fs.px = cfg.fontSize

			local c = cfg.color
			fs:SetTextColor(c[1], c[2], c[3], c[4] or 1)

			local t = cfg.text
			if not t or t == "" then t = DefaultText(key) end
			fs:SetText(t)
		end
	end
	-- Font size changes line heights, so the cached stack is no longer valid.
	Warnings.lastSig = nil
end

function Warnings.ApplyLayout()
	local c = ST.Config.Get("warnings")
	local f = Warnings.frame
	f:ClearAllPoints()
	-- Own point is ALWAYS "TOP" so the block grows downward and the first
	-- line stays put as the second appears or disappears.
	f:SetPoint("TOP", UIParent, c.relPoint or "CENTER", c.x or 0, c.y or 0)
end

function Warnings.ApplyLock()
	local locked = ST.Config.Get("locked")
	local f = Warnings.frame
	f:EnableMouse(not locked)
	f.mover.text:SetText(ST.L["Warnings"])
	f.mover:SetShown(not locked)
	Warnings.lastSig = nil
end

-- Re-anchor every visible line from the top with a running cursor. Because
-- hidden lines are simply skipped, hiding the first one leaves no gap -- the
-- second slides up on its own, with no case analysis.
function Warnings.Restack()
	local spacing = ST.Config.Get("warnings.spacing") or 4
	local y, maxW, total = 0, 0, 0

	for _, key in ipairs(WARN_KEYS) do
		local fs = Warnings.lines[key]
		if fs.wanted then
			fs:ClearAllPoints()
			fs:SetPoint("TOP", Warnings.frame, "TOP", 0, -y)
			fs:Show()
			-- GetStringHeight can report 0 before the string has laid out;
			-- fs.px is the configured font size cached in ApplyStyle.
			local h = fs:GetStringHeight()
			if not h or h <= 0 then h = fs.px or 24 end
			local w = fs:GetStringWidth() or 0
			if w > maxW then maxW = w end
			y = y + h + spacing
			total = total + h + spacing
		else
			fs:Hide()
		end
	end

	if total > 0 then total = total - spacing end   -- drop the trailing gap
	Warnings.frame:SetSize(math.max(maxW + 20, MIN_W), math.max(total, MIN_H))
end

function Warnings.ApplyAll()
	if not Warnings.frame then return end
	Warnings.ApplyStyle()
	Warnings.ApplyLayout()
	Warnings.ApplyLock()
	Warnings.UpdateVisibility()
end

-- ---------------------------------------------------------------------
--  Per-frame update
-- ---------------------------------------------------------------------
function Warnings.UpdateVisibility()
	if not Warnings.frame then return end

	local unlocked = not ST.Config.Get("locked")
	local CS = ST.CombatState
	local base = ST.Config.Get("warnings.enabled")
		and ST.inCombat
		and CS.hasLiveTarget

	-- While unlocked both lines are forced on with their real text and
	-- styling, so unlocking doubles as the style preview.
	local wantRange = unlocked or (base
		and ST.Config.Get("warnings.range.enabled")
		and CS.outOfRange) or false
	local wantAttack = unlocked or (base
		and ST.Config.Get("warnings.attack.enabled")
		and not CS.attacking) or false

	Warnings.lines.range.wanted = wantRange
	Warnings.lines.attack.wanted = wantAttack

	-- Restack only when the visible set actually changes, not every tick.
	local sig = (wantRange and 2 or 0) + (wantAttack and 1 or 0)
	if sig ~= Warnings.lastSig then
		Warnings.lastSig = sig
		Warnings.Restack()
	end
	Warnings.frame:SetShown(sig > 0)
end

function Warnings.OnUpdate(elapsed)
	Warnings.UpdateVisibility()
end

-- ---------------------------------------------------------------------
--  Init
-- ---------------------------------------------------------------------
function Warnings.Initialize()
	Warnings.frame = CreateWarningFrame()
	ST.Config.OnChange(Warnings.ApplyAll)
	Warnings.ApplyAll()
end
