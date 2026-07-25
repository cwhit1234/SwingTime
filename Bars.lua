local addonName, ST = ...

-- =====================================================================
--  Bars.lua
--  StatusBar-based swing bars (main-hand / off-hand / ranged), styled
--  live from the active profile, with a lock/unlock mover overlay. Each
--  bar is independently movable and stores its own anchor in the profile.
-- =====================================================================

local Bars = {}
ST.Bars = Bars

local BAR_KEYS = { "mainhand", "offhand", "ranged", "target" }

local WHITE   = [[Interface\Buttons\WHITE8X8]]
local SPARK   = [[Interface\CastingBar\UI-CastingBar-Spark]]

local function LabelFor(key)
	local L = ST.L
	if key == "mainhand" then return L["Main Hand"]
	elseif key == "offhand" then return L["Off Hand"]
	elseif key == "ranged" then return L["Ranged"]
	else return L["Target"] end
end

-- ---------------------------------------------------------------------
--  Frame construction
-- ---------------------------------------------------------------------
local function CreateBar(key)
	local f = CreateFrame("Frame", "SwingTimeBar_" .. key, UIParent, "BackdropTemplate")
	f.key = key
	f:SetMovable(true)
	f:SetClampedToScreen(true)
	f:RegisterForDrag("LeftButton")
	f:EnableMouse(false)
	f:SetScript("OnDragStart", function(self)
		if not ST.Config.Get("locked") then self:StartMoving() end
	end)
	f:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		local point, _, relPoint, x, y = self:GetPoint()
		ST.Config.Set("bars." .. key .. ".point", point, true)
		ST.Config.Set("bars." .. key .. ".relPoint", relPoint, true)
		ST.Config.Set("bars." .. key .. ".x", x, true)
		ST.Config.Set("bars." .. key .. ".y", y, true)
	end)

	local sb = CreateFrame("StatusBar", nil, f)
	sb:SetPoint("TOPLEFT", f, "TOPLEFT", 1, -1)
	sb:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -1, 1)
	sb:SetMinMaxValues(0, 1)
	sb:SetValue(0)
	f.sb = sb

	-- Cast-window zone (ranged only): a tinted region at the right end of
	-- the bar marking the auto-shot cast / clip window (YAHT-style).
	local castZone = sb:CreateTexture(nil, "ARTWORK", nil, 1)
	castZone:SetTexture(WHITE)
	castZone:Hide()
	f.castZone = castZone

	-- Timing marker: a thin vertical line (Multi-Shot clip / seal-twist window).
	local marker = sb:CreateTexture(nil, "OVERLAY", nil, 1)
	marker:SetTexture(WHITE)
	marker:Hide()
	f.marker = marker

	-- Paladin seal-twist: a red "danger zone" band and a red tick at its start.
	local dangerZone = sb:CreateTexture(nil, "ARTWORK", nil, 1)
	dangerZone:SetTexture(WHITE)
	dangerZone:Hide()
	f.dangerZone = dangerZone

	local dangerTick = sb:CreateTexture(nil, "OVERLAY", nil, 1)
	dangerTick:SetTexture(WHITE)
	dangerTick:Hide()
	f.dangerTick = dangerTick

	local spark = sb:CreateTexture(nil, "OVERLAY")
	spark:SetTexture(SPARK)
	spark:SetBlendMode("ADD")
	spark:SetWidth(16)
	f.spark = spark

	f.label = sb:CreateFontString(nil, "OVERLAY")
	f.label:SetPoint("LEFT", sb, "LEFT", 4, 0)
	f.timer = sb:CreateFontString(nil, "OVERLAY")
	f.timer:SetPoint("RIGHT", sb, "RIGHT", -4, 0)

	-- Mover overlay: a highlighted labeled box shown only while unlocked.
	local mover = CreateFrame("Frame", nil, f, "BackdropTemplate")
	mover:SetAllPoints(f)
	mover:SetFrameStrata("HIGH")
	mover:EnableMouse(false)
	mover:Hide()
	if mover.SetBackdrop then
		mover:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
		mover:SetBackdropColor(0.10, 0.55, 1.0, 0.40)
		mover:SetBackdropBorderColor(0.35, 0.80, 1.0, 1.0)
	else
		local mbg = mover:CreateTexture(nil, "BACKGROUND")
		mbg:SetAllPoints()
		mbg:SetColorTexture(0.10, 0.55, 1.0, 0.40)
	end
	mover.text = mover:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	mover.text:SetPoint("CENTER")
	f.mover = mover

	return f
end

-- ---------------------------------------------------------------------
--  Styling / layout
-- ---------------------------------------------------------------------
function Bars.ApplyStyle(bar)
	local key = bar.key
	local get = ST.Config.Get
	local barCfg = get("bars." .. key)

	bar:SetSize(barCfg.width, barCfg.height)

	if bar.SetBackdrop then
		bar:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
		local bg, border = get("colors.bg"), get("colors.border")
		bar:SetBackdropColor(bg[1], bg[2], bg[3], bg[4])
		bar:SetBackdropBorderColor(border[1], border[2], border[3], border[4])
	end

	bar.sb:SetStatusBarTexture(ST.Media.Texture(get("texture")))
	local c = barCfg.color
	bar.sb:SetStatusBarColor(c[1], c[2], c[3], c[4])

	local font = ST.Media.Font(get("font"))
	local size = get("fontSize")
	local outline = get("fontOutline")
	local flags = (outline == "NONE") and "" or outline
	bar.label:SetFont(font, size, flags)
	bar.timer:SetFont(font, size, flags)
	local tc = get("colors.text")
	bar.label:SetTextColor(tc[1], tc[2], tc[3], tc[4])
	bar.timer:SetTextColor(tc[1], tc[2], tc[3], tc[4])
	bar.label:SetShown(get("showLabel"))
	bar.timer:SetShown(get("showTimerText"))
	bar.label:SetText(LabelFor(key))

	bar.spark:SetHeight(barCfg.height * 2.1)
end

function Bars.ApplyLayout(bar)
	local barCfg = ST.Config.Get("bars." .. bar.key)
	bar:ClearAllPoints()
	bar:SetPoint(barCfg.point or "CENTER", UIParent, barCfg.relPoint or "CENTER",
		barCfg.x or 0, barCfg.y or 0)
end

function Bars.ApplyLock()
	local locked = ST.Config.Get("locked")
	for _, bar in pairs(Bars.bars) do
		bar:EnableMouse(not locked)
		bar.mover.text:SetText(LabelFor(bar.key))
		bar.mover:SetShown(not locked)
	end
end

function Bars.ApplyAll()
	if not Bars.bars then return end
	for _, bar in pairs(Bars.bars) do
		Bars.ApplyStyle(bar)
		Bars.ApplyLayout(bar)
	end
	Bars.ApplyLock()
	Bars.UpdateVisibility()
end

-- ---------------------------------------------------------------------
--  Per-frame update
-- ---------------------------------------------------------------------
local function TimerAndSpeedFor(key)
	if key == "mainhand" then
		return ST.SwingCore.GetSwing("player", "mainhand")
	elseif key == "offhand" then
		return ST.SwingCore.GetSwing("player", "offhand")
	elseif key == "ranged" then
		return ST.SwingCore.GetSwing("player", "ranged")
	else
		return ST.SwingCore.GetSwing("target", "mainhand")
	end
end

function Bars.UpdateBar(bar)
	local remaining, speed = TimerAndSpeedFor(bar.key)
	if not speed or speed <= 0 then speed = 1 end
	if not remaining or remaining < 0 then remaining = 0 end

	local frac = 1 - (remaining / speed)
	if frac < 0 then frac = 0 elseif frac > 1 then frac = 1 end
	bar.sb:SetValue(frac)

	local w = bar.sb:GetWidth() * frac
	bar.spark:ClearAllPoints()
	bar.spark:SetPoint("CENTER", bar.sb, "LEFT", w, 0)
	bar.spark:SetShown(frac > 0.001 and frac < 0.999)

	-- Auto Shot cast window, tinted red at the right of the bar: only for the
	-- hunter Auto Shot ability (the ~0.5s cast, scaled by ranged haste).
	-- "Shoot" (wand / non-hunter ranged) and "Throw" cancel on any movement,
	-- so they have no partial window and get no overlay.
	if bar.key == "ranged" and ST.SwingCore.rangedIsAutoShot then
		local _, rs = ST.SwingCore.GetSwing("player", "ranged")
		local act = ST.SwingCore.rangedCastTime
		local castFrac
		if rs and act and rs > 0 and act > 0 and act < rs then
			castFrac = act / rs
		end
		if castFrac then
			bar.castZone:ClearAllPoints()
			bar.castZone:SetPoint("TOPRIGHT", bar.sb, "TOPRIGHT", 0, 0)
			bar.castZone:SetPoint("BOTTOMRIGHT", bar.sb, "BOTTOMRIGHT", 0, 0)
			bar.castZone:SetWidth(bar.sb:GetWidth() * castFrac)
			if ST.SwingCore.rangedReady then
				bar.castZone:SetVertexColor(0.95, 0.35, 0.30, 0.55)   -- ready to fire
			else
				bar.castZone:SetVertexColor(0.85, 0.20, 0.20, 0.28)   -- upcoming window
			end
			bar.castZone:Show()
		else
			bar.castZone:Hide()
		end
	else
		bar.castZone:Hide()
	end

	-- Vertical timing markers at mechanic-fixed points on the bar.
	local sbw = bar.sb:GetWidth()
	local function fracAt(rem)              -- bar fill fraction for `rem` seconds remaining
		if speed <= 0 then return 0 end
		local f = 1 - rem / speed
		if f < 0 then return 0 elseif f > 1 then return 1 end
		return f
	end
	local function placeTick(tick, rem, texture, r, g, b, a, width)
		local x = sbw * fracAt(rem)
		tick:ClearAllPoints()
		tick:SetPoint("TOP", bar.sb, "TOPLEFT", x, 0)
		tick:SetPoint("BOTTOM", bar.sb, "BOTTOMLEFT", x, 0)
		tick:SetWidth(width or 3)
		tick:SetTexture(ST.Media.Texture(texture))
		tick:SetVertexColor(r, g, b, a or 1)
		tick:Show()
	end

	if bar.key == "ranged" and ST.SwingCore.rangedIsAutoShot then
		-- Hunter Multi-Shot clip line: at (auto-shot cast + multi-shot cast)
		-- before the shot; cast Multi-Shot to the left of it to avoid clipping.
		bar.dangerZone:Hide()
		bar.dangerTick:Hide()
		local cfg = ST.Config.Get("markers.multishot")
		if cfg and cfg.enabled and speed > 0 then
			local c = cfg.color
			placeTick(bar.marker, 2 * (ST.SwingCore.rangedCastTime or 0.5),
				cfg.texture, c[1], c[2], c[3], c[4], cfg.width)
		else
			bar.marker:Hide()
		end

	elseif bar.key == "mainhand" and ST.playerClass == "PALADIN" then
		-- Paladin seal twist: red danger band (0.4s + GCD .. 0.4s), a red tick
		-- at its start, and a configurable twist tick at the 0.4s window start.
		local cfg = ST.Config.Get("markers.sealtwist")
		if cfg and cfg.enabled and speed > 0 then
			local twistStart, dangerStart = 0.4, 0.4 + 1.5   -- twist window + GCD
			local fDanger, fTwist = fracAt(dangerStart), fracAt(twistStart)
			bar.dangerZone:ClearAllPoints()
			bar.dangerZone:SetPoint("TOPLEFT", bar.sb, "TOPLEFT", sbw * fDanger, 0)
			bar.dangerZone:SetPoint("BOTTOMLEFT", bar.sb, "BOTTOMLEFT", sbw * fDanger, 0)
			bar.dangerZone:SetWidth(math.max(sbw * (fTwist - fDanger), 0.001))
			bar.dangerZone:SetVertexColor(0.85, 0.20, 0.20, 0.60)
			bar.dangerZone:SetShown((fTwist - fDanger) > 0)
			placeTick(bar.dangerTick, dangerStart, cfg.texture, 0.90, 0.15, 0.15, 1.0, cfg.width)
			local c = cfg.color
			placeTick(bar.marker, twistStart, cfg.texture, c[1], c[2], c[3], c[4], cfg.width)
		else
			bar.marker:Hide()
			bar.dangerZone:Hide()
			bar.dangerTick:Hide()
		end

	else
		bar.marker:Hide()
		bar.dangerZone:Hide()
		bar.dangerTick:Hide()
	end

	if bar.timer:IsShown() then
		bar.timer:SetFormattedText("%.1f", remaining)
	end
end

function Bars.UpdateVisibility()
	if not Bars.bars then return end
	local unlocked = not ST.Config.Get("locked")
	for key, bar in pairs(Bars.bars) do
		local show = ST.Config.Get("bars." .. key .. ".enabled")
		if key == "offhand" then show = show and ST.SwingCore.hasOffhand end
		if key == "ranged" then show = show and ST.SwingCore.hasRanged end
		if key == "target" then show = show and ST.SwingCore.hasTarget end
		if unlocked then show = true end          -- always visible while configuring
		bar:SetShown(show)
	end

	local a = ST.inCombat and ST.Config.Get("inCombatAlpha") or ST.Config.Get("oocAlpha")
	if unlocked then a = 1.0 end
	for _, bar in pairs(Bars.bars) do
		bar:SetAlpha(a)
	end
end

function Bars.OnUpdate(elapsed)
	if not Bars.bars then return end
	Bars.UpdateVisibility()
	for _, bar in pairs(Bars.bars) do
		if bar:IsShown() then
			Bars.UpdateBar(bar)
		end
	end
end

-- ---------------------------------------------------------------------
--  Init
-- ---------------------------------------------------------------------
function Bars.Initialize()
	Bars.bars = {}
	for _, key in ipairs(BAR_KEYS) do
		Bars.bars[key] = CreateBar(key)
	end
	ST.Config.OnChange(Bars.ApplyAll)
	Bars.ApplyAll()
end
