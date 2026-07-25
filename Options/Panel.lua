local addonName, ST = ...

-- =====================================================================
--  Options/Panel.lua
--  The config panel: left-rail tabs (Bars / Style / Profiles), a live
--  preview bar, and Settings-API registration with a legacy fallback.
-- =====================================================================

local Panel = {}
ST.Panel = Panel

local Widgets = ST.Widgets
local L

Panel.refreshers = {}
Panel.selectedBar = "mainhand"   -- which bar the size sliders currently edit

local function AddRefresher(widget)
	if widget and widget.Refresh then
		table.insert(Panel.refreshers, widget.Refresh)
	end
	return widget
end

function Panel.RefreshAll()
	for _, fn in ipairs(Panel.refreshers) do
		-- pcall so one bad control can't break the whole panel refresh
		pcall(fn)
	end
	if Panel.lockButton then
		local locked = ST.Config.Get("locked")
		Panel.lockButton:SetText(locked and L["Unlock bars"] or L["Lock bars"])
	end
end

-- ---------------------------------------------------------------------
--  Layout helpers
-- ---------------------------------------------------------------------
-- Two-column layout over a content frame. Each column has its own x offset
-- and independent y cursor, so widgets can be placed left or right.
local COL_W   = 260   -- widget column width
local COL_GAP = 70    -- gap between the two columns
local ROW_GAP = 10

local function NewGrid(content)
	return { content = content, colX = { 0, COL_W + COL_GAP }, colY = { -4, -4 } }
end

-- Place a widget into column c (1 = left, 2 = right).
local function GAdd(g, c, widget, height, indent)
	widget:SetParent(g.content)
	widget:ClearAllPoints()
	widget:SetPoint("TOPLEFT", g.content, "TOPLEFT", g.colX[c] + (indent or 0), g.colY[c])
	g.colY[c] = g.colY[c] - (height or 24) - ROW_GAP
	return widget
end

local function GHeader(g, c, text)
	local fs = g.content:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	fs:SetPoint("TOPLEFT", g.content, "TOPLEFT", g.colX[c], g.colY[c])
	fs:SetText(text)
	g.colY[c] = g.colY[c] - 28
	return fs
end

-- Align a column's cursor to another's (e.g. start the right column level
-- with the left column's first control, under a spanning header).
local function GAlign(g, fromCol, toCol)
	g.colY[toCol] = g.colY[fromCol]
end

-- Deepest column height, used to size the scroll child.
local function GHeight(g)
	return math.max(-g.colY[1], -g.colY[2]) + 16
end

-- A section header inside a column: an accent-colored title with a thin
-- divider line spanning the column, to visually group the controls below.
local function GSection(g, c, text)
	local y = g.colY[c]
	local fs = g.content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	fs:SetPoint("TOPLEFT", g.content, "TOPLEFT", g.colX[c], y)
	fs:SetText(text)
	fs:SetTextColor(0.55, 0.78, 1.0)
	local line = g.content:CreateTexture(nil, "ARTWORK")
	line:SetColorTexture(0.30, 0.42, 0.58, 0.6)
	line:SetPoint("TOPLEFT", g.content, "TOPLEFT", g.colX[c], y - 18)
	line:SetSize(COL_W, 1)
	g.colY[c] = y - 28
	return fs
end

-- A full-width section header spanning both columns. Syncs both column
-- cursors to below the deeper one first, so the section starts clean.
local function GSectionSpan(g, text)
	local y = math.min(g.colY[1], g.colY[2]) - 6
	local fs = g.content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	fs:SetPoint("TOPLEFT", g.content, "TOPLEFT", g.colX[1], y)
	fs:SetText(text)
	fs:SetTextColor(0.55, 0.78, 1.0)
	local line = g.content:CreateTexture(nil, "ARTWORK")
	line:SetColorTexture(0.30, 0.42, 0.58, 0.6)
	line:SetPoint("TOPLEFT", g.content, "TOPLEFT", g.colX[1], y - 18)
	line:SetSize(COL_W * 2 + COL_GAP, 1)
	g.colY[1] = y - 28
	g.colY[2] = y - 28
	return fs
end

local WHITE8 = [[Interface\Buttons\WHITE8X8]]

-- Flat, modern button (replaces the stock red UIPanelButtonTemplate look).
local function CreateButton(parent, text, w, onclick)
	local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
	b:SetSize(w or 90, 24)
	Widgets.FlatBackdrop(b, 0.16, 0.20, 0.28, 0.95, 0.30, 0.40, 0.55, 1)
	b.label = b:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	b.label:SetPoint("CENTER")
	b.label:SetText(text)
	b.SetText = function(self, t) self.label:SetText(t) end
	b:SetScript("OnEnter", function(self) self:SetBackdropColor(0.24, 0.32, 0.44, 1) end)
	b:SetScript("OnLeave", function(self) self:SetBackdropColor(0.16, 0.20, 0.28, 0.95) end)
	b:SetScript("OnClick", onclick)
	return b
end

-- ---------------------------------------------------------------------
--  Tab: Bars
-- ---------------------------------------------------------------------
local function BuildBarsTab(content)
	local g = NewGrid(content)
	GHeader(g, 1, L["Bars"])
	GAlign(g, 1, 2)   -- right column starts level with the first left control

	-- TOP ROW: per-bar sections side by side -------------------------------
	-- Left: which bars are shown
	GSection(g, 1, L["Enabled Bars"])
	AddRefresher(GAdd(g, 1, Widgets.CreateCheckbox(content, L["Main Hand"], {
		get = function() return ST.Config.Get("bars.mainhand.enabled") end,
		set = function(v) ST.Config.Set("bars.mainhand.enabled", v) end,
	}), 24))
	AddRefresher(GAdd(g, 1, Widgets.CreateCheckbox(content, L["Off Hand"], {
		get = function() return ST.Config.Get("bars.offhand.enabled") end,
		set = function(v) ST.Config.Set("bars.offhand.enabled", v) end,
	}), 24))
	AddRefresher(GAdd(g, 1, Widgets.CreateCheckbox(content, L["Ranged"], {
		get = function() return ST.Config.Get("bars.ranged.enabled") end,
		set = function(v) ST.Config.Set("bars.ranged.enabled", v) end,
	}), 24))
	AddRefresher(GAdd(g, 1, Widgets.CreateCheckbox(content, L["Target"], {
		get = function() return ST.Config.Get("bars.target.enabled") end,
		set = function(v) ST.Config.Set("bars.target.enabled", v) end,
	}), 24))

	-- Right: properties of the one bar picked in the dropdown
	GSection(g, 2, L["Selected Bar"])
	local barChoices = {
		{ value = "mainhand", text = L["Main Hand"] },
		{ value = "offhand",  text = L["Off Hand"] },
		{ value = "ranged",   text = L["Ranged"] },
		{ value = "target",   text = L["Target"] },
	}
	local function SelectedText()
		for _, c in ipairs(barChoices) do
			if c.value == Panel.selectedBar then return c.text end
		end
		return Panel.selectedBar
	end
	AddRefresher(GAdd(g, 2, Widgets.CreateDropdown(content, L["Configure bar"], {
		get = function() return SelectedText() end,
		set = function(v)
			Panel.selectedBar = v
			Panel.RefreshAll()
		end,
		items = function() return barChoices end,
	}), 44))
	AddRefresher(GAdd(g, 2, Widgets.CreateSlider(content, L["Width"], 60, 400, 1, {
		get = function() return ST.Config.Get("bars." .. Panel.selectedBar .. ".width") end,
		set = function(v) ST.Config.Set("bars." .. Panel.selectedBar .. ".width", v) end,
	}), 40))
	AddRefresher(GAdd(g, 2, Widgets.CreateSlider(content, L["Height"], 8, 48, 1, {
		get = function() return ST.Config.Get("bars." .. Panel.selectedBar .. ".height") end,
		set = function(v) ST.Config.Set("bars." .. Panel.selectedBar .. ".height", v) end,
	}), 40))
	AddRefresher(GAdd(g, 2, Widgets.CreateColorSwatch(content, L["Color"], {
		get = function() return ST.Config.Get("bars." .. Panel.selectedBar .. ".color") end,
		set = function(v) ST.Config.Set("bars." .. Panel.selectedBar .. ".color", v) end,
	}), 22))

	-- FULL-WIDTH GLOBAL SECTION (everything that applies to all bars) -------
	GSectionSpan(g, L["Global"])

	-- Global column 1: texture & font
	AddRefresher(GAdd(g, 1, Widgets.CreateDropdown(content, L["Bar texture"], {
		searchable = true,
		get = function() return ST.Config.Get("texture") end,
		set = function(v) ST.Config.Set("texture", v) end,
		items = function()
			local out = {}
			for _, name in ipairs(ST.Media.List("statusbar")) do
				out[#out + 1] = { value = name, text = name, texture = ST.Media.Texture(name) }
			end
			return out
		end,
		previewTexture = function(v) return ST.Media.Texture(v) end,
	}), 44))
	AddRefresher(GAdd(g, 1, Widgets.CreateDropdown(content, L["Font"], {
		searchable = true,
		get = function() return ST.Config.Get("font") end,
		set = function(v) ST.Config.Set("font", v) end,
		items = function()
			local out = {}
			for _, name in ipairs(ST.Media.List("font")) do
				out[#out + 1] = { value = name, text = name, font = ST.Media.Font(name) }
			end
			return out
		end,
		previewFont = function(v) return ST.Media.Font(v) end,
	}), 44))
	AddRefresher(GAdd(g, 1, Widgets.CreateSlider(content, L["Font size"], 6, 24, 1, {
		get = function() return ST.Config.Get("fontSize") end,
		set = function(v) ST.Config.Set("fontSize", v) end,
	}), 40))
	AddRefresher(GAdd(g, 1, Widgets.CreateDropdown(content, L["Font outline"], {
		get = function() return ST.Config.Get("fontOutline") end,
		set = function(v) ST.Config.Set("fontOutline", v) end,
		items = function()
			return {
				{ value = "NONE", text = L["None"] },
				{ value = "OUTLINE", text = L["Outline"] },
				{ value = "THICKOUTLINE", text = L["Thick outline"] },
			}
		end,
	}), 44))

	-- Global column 2: colors + text/opacity behavior
	local function ColorCfg(path)
		return {
			get = function() return ST.Config.Get(path) end,
			set = function(v) ST.Config.Set(path, v) end,
		}
	end
	AddRefresher(GAdd(g, 2, Widgets.CreateColorSwatch(content, L["Background color"], ColorCfg("colors.bg")), 22))
	AddRefresher(GAdd(g, 2, Widgets.CreateColorSwatch(content, L["Border color"], ColorCfg("colors.border")), 22))
	AddRefresher(GAdd(g, 2, Widgets.CreateColorSwatch(content, L["Text color"], ColorCfg("colors.text")), 22))
	AddRefresher(GAdd(g, 2, Widgets.CreateCheckbox(content, L["Show label text"], {
		get = function() return ST.Config.Get("showLabel") end,
		set = function(v) ST.Config.Set("showLabel", v) end,
	}), 24))
	AddRefresher(GAdd(g, 2, Widgets.CreateCheckbox(content, L["Show timer text"], {
		get = function() return ST.Config.Get("showTimerText") end,
		set = function(v) ST.Config.Set("showTimerText", v) end,
	}), 24))
	AddRefresher(GAdd(g, 2, Widgets.CreateSlider(content, L["In-combat opacity"], 0, 1, 0.05, {
		get = function() return ST.Config.Get("inCombatAlpha") end,
		set = function(v) ST.Config.Set("inCombatAlpha", v) end,
	}), 40))
	AddRefresher(GAdd(g, 2, Widgets.CreateSlider(content, L["Out-of-combat opacity"], 0, 1, 0.05, {
		get = function() return ST.Config.Get("oocAlpha") end,
		set = function(v) ST.Config.Set("oocAlpha", v) end,
	}), 40))

	-- CLASS-SPECIFIC TIMING MARKER =========================================
	local markerKey, markerTitle
	if ST.playerClass == "HUNTER" then
		markerKey, markerTitle = "multishot", L["Multi-Shot Marker"]
	elseif ST.playerClass == "PALADIN" then
		markerKey, markerTitle = "sealtwist", L["Seal Twist Marker"]
	end
	if markerKey then
		local base = "markers." .. markerKey
		GSectionSpan(g, markerTitle)
		AddRefresher(GAdd(g, 1, Widgets.CreateCheckbox(content, L["Enable"], {
			get = function() return ST.Config.Get(base .. ".enabled") end,
			set = function(v) ST.Config.Set(base .. ".enabled", v) end,
		}), 24))
		AddRefresher(GAdd(g, 1, Widgets.CreateSlider(content, L["Position (seconds before swing)"], 0.1, 2.0, 0.05, {
			get = function() return ST.Config.Get(base .. ".position") end,
			set = function(v) ST.Config.Set(base .. ".position", v) end,
		}), 40))
		AddRefresher(GAdd(g, 1, Widgets.CreateSlider(content, L["Marker width"], 1, 8, 1, {
			get = function() return ST.Config.Get(base .. ".width") end,
			set = function(v) ST.Config.Set(base .. ".width", v) end,
		}), 40))
		AddRefresher(GAdd(g, 2, Widgets.CreateDropdown(content, L["Marker texture"], {
			searchable = true,
			get = function() return ST.Config.Get(base .. ".texture") end,
			set = function(v) ST.Config.Set(base .. ".texture", v) end,
			items = function()
				local out = {}
				for _, name in ipairs(ST.Media.List("statusbar")) do
					out[#out + 1] = { value = name, text = name, texture = ST.Media.Texture(name) }
				end
				return out
			end,
			previewTexture = function(v) return ST.Media.Texture(v) end,
		}), 44))
		AddRefresher(GAdd(g, 2, Widgets.CreateColorSwatch(content, L["Marker color"], {
			get = function() return ST.Config.Get(base .. ".color") end,
			set = function(v) ST.Config.Set(base .. ".color", v) end,
		}), 22))
	end

	content:SetHeight(GHeight(g))
end

-- ---------------------------------------------------------------------
--  Tab: Profiles
-- ---------------------------------------------------------------------
local function BuildProfilesTab(content)
	local g = NewGrid(content)
	GHeader(g, 1, L["Profiles"])
	GAlign(g, 1, 2)

	-- LEFT COLUMN: active profile ------------------------------------------
	AddRefresher(GAdd(g, 1, Widgets.CreateDropdown(content, L["Active profile"], {
		get = function() return ST.Config.GetActiveProfileName() end,
		set = function(v) ST.Config.ChangeProfile(v) end,
		items = function()
			local out = {}
			for _, name in ipairs(ST.Config.GetProfileNames()) do
				out[#out + 1] = { value = name, text = name }
			end
			return out
		end,
	}), 44))

	-- RIGHT COLUMN: create / manage ----------------------------------------
	local edit = CreateFrame("EditBox", nil, content, "InputBoxTemplate")
	edit:SetAutoFocus(false)
	edit:SetSize(180, 20)
	edit:SetMaxLetters(32)
	local editLabel = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	GAdd(g, 2, edit, 24, 4)
	editLabel:SetPoint("BOTTOMLEFT", edit, "TOPLEFT", -4, 2)
	editLabel:SetText(L["New profile name"])

	local newBtn = CreateButton(content, L["New"], 90, function()
		local name = edit:GetText()
		if name and name ~= "" then
			ST.Config.MakeProfile(name, false)
			edit:SetText("")
			edit:ClearFocus()
		end
	end)
	GAdd(g, 2, newBtn, 24)

	local copyBtn = CreateButton(content, L["Copy"], 90, function()
		local name = edit:GetText()
		if name and name ~= "" then
			ST.Config.MakeProfile(name, true)
			edit:SetText("")
			edit:ClearFocus()
		end
	end)
	copyBtn:SetPoint("LEFT", newBtn, "RIGHT", 8, 0)

	local delBtn = CreateButton(content, L["Delete"], 90, function()
		ST.Config.DeleteProfile(ST.Config.GetActiveProfileName())
		Panel.RefreshAll()
	end)
	GAdd(g, 2, delBtn, 24)

	local resetBtn = CreateButton(content, L["Reset"], 90, function()
		ST.Config.ResetProfile()
	end)
	resetBtn:SetPoint("LEFT", delBtn, "RIGHT", 8, 0)

	content:SetHeight(GHeight(g))
end

local function BarDisplayName(key)
	local L2 = ST.L
	if key == "mainhand" then return L2["Main Hand"]
	elseif key == "offhand" then return L2["Off Hand"]
	elseif key == "ranged" then return L2["Ranged"]
	else return L2["Target"] end
end

-- ---------------------------------------------------------------------
--  Live preview bar (true-to-size: mirrors the selected bar exactly)
-- ---------------------------------------------------------------------
local PREVIEW_CYCLE = 2.6   -- seconds; a representative swing length

local function BuildPreview(panel)
	-- The preview sits bottom-left at the bar's REAL size, not stretched.
	local preview = CreateFrame("Frame", nil, panel, "BackdropTemplate")
	preview:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 16, 16)
	preview:SetSize(260, 22)   -- replaced with the real bar size in Refresh

	local caption = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	caption:SetPoint("BOTTOMLEFT", preview, "TOPLEFT", 0, 4)
	caption:SetText(ST.L["Preview"])

	local sb = CreateFrame("StatusBar", nil, preview)
	sb:SetPoint("TOPLEFT", 1, -1)
	sb:SetPoint("BOTTOMRIGHT", -1, 1)
	sb:SetMinMaxValues(0, 1)
	preview.sb = sb

	local spark = sb:CreateTexture(nil, "OVERLAY")
	spark:SetTexture([[Interface\CastingBar\UI-CastingBar-Spark]])
	spark:SetBlendMode("ADD")
	spark:SetWidth(16)
	preview.spark = spark

	local label = sb:CreateFontString(nil, "OVERLAY")
	label:SetPoint("LEFT", sb, "LEFT", 4, 0)
	local timer = sb:CreateFontString(nil, "OVERLAY")
	timer:SetPoint("RIGHT", sb, "RIGHT", -4, 0)
	preview.label = label
	preview.timer = timer

	preview.t = 0
	preview:SetScript("OnUpdate", function(self, elapsed)
		self.t = (self.t + elapsed) % PREVIEW_CYCLE
		local frac = self.t / PREVIEW_CYCLE
		sb:SetValue(frac)
		local w = sb:GetWidth() * frac
		spark:ClearAllPoints()
		spark:SetPoint("CENTER", sb, "LEFT", w, 0)
		spark:SetShown(frac > 0.001 and frac < 0.999)
		if timer:IsShown() then
			timer:SetFormattedText("%.1f", PREVIEW_CYCLE - self.t)
		end
	end)

	preview.Refresh = function()
		local key = Panel.selectedBar or "mainhand"
		local barCfg = ST.Config.Get("bars." .. key)
		-- Real size of the bar being edited.
		preview:SetSize(barCfg.width, barCfg.height)

		if preview.SetBackdrop then
			preview:SetBackdrop({ bgFile = WHITE8, edgeFile = WHITE8, edgeSize = 1 })
			local bg, border = ST.Config.Get("colors.bg"), ST.Config.Get("colors.border")
			preview:SetBackdropColor(bg[1], bg[2], bg[3], bg[4])
			preview:SetBackdropBorderColor(border[1], border[2], border[3], border[4])
		end

		sb:SetStatusBarTexture(ST.Media.Texture(ST.Config.Get("texture")))
		local c = barCfg.color
		sb:SetStatusBarColor(c[1], c[2], c[3], c[4])

		local font = ST.Media.Font(ST.Config.Get("font"))
		local size = ST.Config.Get("fontSize")
		local outline = ST.Config.Get("fontOutline")
		local flags = (outline == "NONE") and "" or outline
		label:SetFont(font, size, flags)
		timer:SetFont(font, size, flags)
		local tc = ST.Config.Get("colors.text")
		label:SetTextColor(tc[1], tc[2], tc[3], tc[4])
		timer:SetTextColor(tc[1], tc[2], tc[3], tc[4])
		label:SetShown(ST.Config.Get("showLabel"))
		timer:SetShown(ST.Config.Get("showTimerText"))
		label:SetText(BarDisplayName(key))
		spark:SetHeight(barCfg.height * 2.1)
	end
	AddRefresher(preview)
	return preview
end

-- ---------------------------------------------------------------------
--  Tab chrome
-- ---------------------------------------------------------------------
local function ShowTab(name)
	for tabName, frame in pairs(Panel.tabFrames) do
		frame:SetShown(tabName == name)
	end
	for tabName, btn in pairs(Panel.tabButtons) do
		btn:SetSelected(tabName == name)
	end
	Panel.currentTab = name
end

-- Left-rail tab button (flat, with a selection accent bar).
local function CreateTabButton(parent, text)
	local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
	b:SetSize(150, 30)
	Widgets.FlatBackdrop(b, 0.11, 0.12, 0.15, 0.0, 0, 0, 0, 0)
	b.label = b:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	b.label:SetPoint("LEFT", 12, 0)
	b.label:SetText(text)
	b.accent = b:CreateTexture(nil, "ARTWORK")
	b.accent:SetPoint("TOPLEFT")
	b.accent:SetPoint("BOTTOMLEFT")
	b.accent:SetWidth(3)
	b.accent:SetColorTexture(0.40, 0.70, 1.0, 1.0)
	b.accent:Hide()
	b.selected = false
	function b:SetSelected(on)
		self.selected = on
		self.accent:SetShown(on)
		if on then
			self:SetBackdropColor(0.18, 0.24, 0.34, 0.95)
			self.label:SetTextColor(1, 1, 1)
		else
			self:SetBackdropColor(0.11, 0.12, 0.15, 0.0)
			self.label:SetTextColor(0.75, 0.78, 0.85)
		end
	end
	b:SetScript("OnEnter", function(self)
		if not self.selected then self:SetBackdropColor(0.16, 0.19, 0.26, 0.9) end
	end)
	b:SetScript("OnLeave", function(self)
		if not self.selected then self:SetBackdropColor(0.11, 0.12, 0.15, 0.0) end
	end)
	return b
end

-- ---------------------------------------------------------------------
--  A tiny entry in the Blizzard AddOns list whose only job is a button
--  that opens our standalone window.
-- ---------------------------------------------------------------------
local function RegisterBlizzStub(win)
	local stub = CreateFrame("Frame", "SwingTimeBlizzStub", UIParent)
	stub:Hide()

	local title = stub:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", 16, -16)
	title:SetText("SwingTime")

	local desc = stub:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	desc:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
	desc:SetText(L["Weapon swing timer bars."])

	local open = CreateButton(stub, L["Open configuration"], 220, function()
		win:Show()
		Panel.RefreshAll()
		if SettingsPanel and SettingsPanel:IsShown() then
			HideUIPanel(SettingsPanel)
		elseif InterfaceOptionsFrame and InterfaceOptionsFrame:IsShown() then
			HideUIPanel(InterfaceOptionsFrame)
		end
	end)
	open:SetPoint("TOPLEFT", desc, "BOTTOMLEFT", 0, -18)

	if Settings and Settings.RegisterCanvasLayoutCategory then
		local cat = Settings.RegisterCanvasLayoutCategory(stub, "SwingTime")
		Settings.RegisterAddOnCategory(cat)
	elseif InterfaceOptions_AddCategory then
		stub.name = "SwingTime"
		InterfaceOptions_AddCategory(stub)
	end
end

-- ---------------------------------------------------------------------
--  Build the standalone window
-- ---------------------------------------------------------------------
function Panel.Initialize()
	if Panel.window then return end
	L = ST.L

	local WIN_W, WIN_H = 860, 720

	local win = CreateFrame("Frame", "SwingTimeConfigWindow", UIParent, "BackdropTemplate")
	win:SetSize(WIN_W, WIN_H)
	win:SetPoint("CENTER")
	win:SetFrameStrata("HIGH")
	win:SetToplevel(true)
	win:EnableMouse(true)
	win:SetMovable(true)
	win:SetClampedToScreen(true)
	win:Hide()
	win:SetBackdrop({ bgFile = WHITE8, edgeFile = WHITE8, edgeSize = 1 })
	win:SetBackdropColor(0.06, 0.07, 0.09, 0.97)
	win:SetBackdropBorderColor(0.28, 0.45, 0.72, 1.0)
	Panel.window = win
	Panel.frame = win

	-- Escape closes it.
	table.insert(UISpecialFrames, "SwingTimeConfigWindow")

	-- Header + drag handle
	local header = CreateFrame("Frame", nil, win)
	header:SetPoint("TOPLEFT", 1, -1)
	header:SetPoint("TOPRIGHT", -1, -1)
	header:SetHeight(52)
	header:EnableMouse(true)
	header:RegisterForDrag("LeftButton")
	header:SetScript("OnDragStart", function() win:StartMoving() end)
	header:SetScript("OnDragStop", function() win:StopMovingOrSizing() end)
	local hbg = header:CreateTexture(nil, "BACKGROUND")
	hbg:SetAllPoints()
	hbg:SetColorTexture(0.10, 0.13, 0.19, 0.95)

	local title = header:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
	title:SetPoint("TOPLEFT", 18, -10)
	title:SetText("SwingTime")
	title:SetTextColor(0.55, 0.78, 1.0)

	local subtitle = header:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 1, -3)
	subtitle:SetText(L["Weapon swing timer bars."])
	subtitle:SetTextColor(0.70, 0.72, 0.78)

	local close = CreateFrame("Button", nil, header)
	close:SetSize(30, 30)
	close:SetPoint("TOPRIGHT", -8, -11)
	close.x = close:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	close.x:SetPoint("CENTER")
	close.x:SetText("×")
	close.x:SetTextColor(0.80, 0.80, 0.85)
	close:SetScript("OnEnter", function(self) self.x:SetTextColor(1.0, 0.4, 0.4) end)
	close:SetScript("OnLeave", function(self) self.x:SetTextColor(0.80, 0.80, 0.85) end)
	close:SetScript("OnClick", function() win:Hide() end)

	-- Unlock/Lock toggle in the header (a global action, so it lives in the
	-- window chrome rather than in the settings body).
	local unlock = CreateFrame("Button", nil, header, "BackdropTemplate")
	unlock:SetSize(110, 24)
	unlock:SetPoint("RIGHT", close, "LEFT", -6, 0)
	Widgets.FlatBackdrop(unlock, 0.16, 0.20, 0.28, 0.95, 0.30, 0.40, 0.55, 1)
	unlock.label = unlock:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	unlock.label:SetPoint("CENTER")
	unlock.SetText = function(self, t) self.label:SetText(t) end
	unlock:SetScript("OnEnter", function(self) self:SetBackdropColor(0.24, 0.32, 0.44, 1) end)
	unlock:SetScript("OnLeave", function(self) self:SetBackdropColor(0.16, 0.20, 0.28, 0.95) end)
	unlock:SetScript("OnClick", function() ST.SetLocked(not ST.Config.Get("locked")) end)
	Panel.lockButton = unlock

	-- Left rail
	local rail = CreateFrame("Frame", nil, win)
	rail:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 12, -14)
	rail:SetSize(150, WIN_H - 52 - 28)

	-- Content area (leaves room at the bottom for the preview)
	local content = CreateFrame("Frame", nil, win)
	content:SetPoint("TOPLEFT", rail, "TOPRIGHT", 14, 0)
	content:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", -16, 88)

	Panel.tabFrames = {}
	Panel.tabButtons = {}

	local tabs = {
		{ name = L["Bars"], build = BuildBarsTab },
		{ name = L["Profiles"], build = BuildProfilesTab },
	}

	local yy = 0
	for _, tab in ipairs(tabs) do
		-- Each tab scrolls, so content can never overflow the window.
		local scroll = CreateFrame("ScrollFrame", nil, content)
		scroll:SetAllPoints(content)
		scroll:EnableMouseWheel(true)
		scroll:SetScript("OnMouseWheel", function(self, delta)
			local new = self:GetVerticalScroll() - delta * 28
			local maxScroll = self:GetVerticalScrollRange()
			if new < 0 then new = 0 elseif new > maxScroll then new = maxScroll end
			self:SetVerticalScroll(new)
		end)

		local child = CreateFrame("Frame", nil, scroll)
		child:SetSize(400, 700)
		scroll:SetScrollChild(child)
		scroll:SetScript("OnSizeChanged", function(_, w)
			child:SetWidth(w)
		end)

		scroll:Hide()
		Panel.tabFrames[tab.name] = scroll
		tab.build(child)

		local btn = CreateTabButton(rail, tab.name)
		btn:SetPoint("TOPLEFT", 0, yy)
		btn:SetScript("OnClick", function() ShowTab(tab.name) end)
		Panel.tabButtons[tab.name] = btn
		yy = yy - 34
	end

	BuildPreview(win)

	ShowTab(L["Bars"])

	-- Refresh when settings change (including profile switches).
	ST.Config.OnChange(Panel.RefreshAll)

	-- /st toggles the window.
	ST.OpenConfig = function()
		if win:IsShown() then
			win:Hide()
		else
			win:Show()
			Panel.RefreshAll()
		end
	end

	RegisterBlizzStub(win)

	Panel.RefreshAll()
end
