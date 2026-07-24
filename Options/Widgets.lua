local addonName, ST = ...

-- =====================================================================
--  Options/Widgets.lua
--  A small hand-built widget toolkit (checkbox, slider, dropdown with
--  media preview, color swatch) for a clean, modern config panel with
--  live-apply. Each control writes through ST.Config.Set, which fires the
--  change listeners so bars restyle instantly.
-- =====================================================================

local Widgets = {}
ST.Widgets = Widgets

local WHITE = [[Interface\Buttons\WHITE8X8]]

local function FlatBackdrop(frame, r, g, b, a, er, eg, eb, ea)
	if not frame.SetBackdrop then return end
	frame:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
	frame:SetBackdropColor(r, g, b, a)
	frame:SetBackdropBorderColor(er or 0, eg or 0, eb or 0, ea or 1)
end
Widgets.FlatBackdrop = FlatBackdrop

-- ---------------------------------------------------------------------
--  Checkbox
-- ---------------------------------------------------------------------
function Widgets.CreateCheckbox(parent, labelText, cfg)
	local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
	cb:SetSize(24, 24)
	cb.text = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	cb.text:SetPoint("LEFT", cb, "RIGHT", 2, 0)
	cb.text:SetText(labelText)

	cb:SetScript("OnClick", function(self)
		cfg.set(self:GetChecked() and true or false)
	end)
	cb.Refresh = function()
		cb:SetChecked(cfg.get() and true or false)
	end
	cb.Refresh()
	return cb
end

-- ---------------------------------------------------------------------
--  Slider (flat, custom track)
-- ---------------------------------------------------------------------
function Widgets.CreateSlider(parent, labelText, minV, maxV, step, cfg)
	local container = CreateFrame("Frame", nil, parent)
	container:SetSize(260, 40)

	local label = container:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	label:SetPoint("TOPLEFT", 0, 0)

	local value = container:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	value:SetPoint("TOPRIGHT", 0, 0)

	-- Show enough decimals to represent the step (e.g. 0.05 -> 2 decimals),
	-- otherwise the displayed value looks like it isn't changing by a step.
	local decimals = (step >= 1) and 0 or ((step >= 0.1) and 1 or 2)
	local function fmt(v) return string.format("%." .. decimals .. "f", v) end
	local function snap(v)
		v = math.floor(v / step + 0.5) * step
		if v < minV then v = minV elseif v > maxV then v = maxV end
		return v
	end

	-- Small stepper button for the -/+ controls that flank the track.
	local function StepBtn(sym)
		local b = CreateFrame("Button", nil, container, "BackdropTemplate")
		b:SetSize(18, 16)
		FlatBackdrop(b, 0.16, 0.20, 0.28, 0.95, 0.30, 0.40, 0.55, 1)
		local t = b:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		t:SetPoint("CENTER", 0, 1)
		t:SetText(sym)
		b:SetScript("OnEnter", function(self) self:SetBackdropColor(0.24, 0.32, 0.44, 1) end)
		b:SetScript("OnLeave", function(self) self:SetBackdropColor(0.16, 0.20, 0.28, 0.95) end)
		return b
	end

	local minus = StepBtn("-")
	minus:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -6)
	local plus = StepBtn("+")
	plus:SetPoint("TOP", minus, "TOP", 0, 0)
	plus:SetPoint("RIGHT", container, "RIGHT", 0, 0)

	local slider = CreateFrame("Slider", nil, container, "BackdropTemplate")
	slider:SetOrientation("HORIZONTAL")
	slider:SetPoint("LEFT", minus, "RIGHT", 6, 0)
	slider:SetPoint("RIGHT", plus, "LEFT", -6, 0)
	slider:SetHeight(14)
	slider:SetMinMaxValues(minV, maxV)
	slider:SetValueStep(step)
	slider:SetObeyStepOnDrag(true)
	slider:SetHitRectInsets(0, 0, -6, -6)
	FlatBackdrop(slider, 0.12, 0.12, 0.14, 0.9)

	local thumb = slider:CreateTexture(nil, "OVERLAY")
	thumb:SetTexture(WHITE)
	thumb:SetVertexColor(0.55, 0.75, 1.0, 1.0)
	thumb:SetSize(10, 18)
	slider:SetThumbTexture(thumb)

	slider:SetScript("OnValueChanged", function(self, v)
		if self._refreshing then return end
		v = snap(v)
		value:SetText(fmt(v))
		cfg.set(v)
	end)

	-- -/+ nudge the value by exactly one step for precise control.
	minus:SetScript("OnClick", function() cfg.set(snap((cfg.get() or minV) - step)) end)
	plus:SetScript("OnClick", function() cfg.set(snap((cfg.get() or minV) + step)) end)

	container.Refresh = function()
		slider._refreshing = true
		local v = cfg.get() or minV
		slider:SetValue(v)
		value:SetText(fmt(v))
		label:SetText(labelText)
		slider._refreshing = false
	end
	container.slider = slider
	container.Refresh()
	return container
end

-- ---------------------------------------------------------------------
--  Dropdown (with optional media preview per row)
--   cfg = { get=fn, set=fn(value), items=fn -> { {value=,text=,texture=,font=}, ... } }
-- ---------------------------------------------------------------------
local ROW_H = 20
local MAX_ROWS = 12

function Widgets.CreateDropdown(parent, labelText, cfg)
	local container = CreateFrame("Frame", nil, parent)
	container:SetSize(260, 44)

	local label = container:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	label:SetPoint("TOPLEFT", 0, 0)
	label:SetText(labelText)

	local button = CreateFrame("Button", nil, container, "BackdropTemplate")
	button:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -4)
	button:SetSize(260, 22)
	FlatBackdrop(button, 0.12, 0.12, 0.14, 0.95)

	button.preview = button:CreateTexture(nil, "ARTWORK")
	button.preview:SetPoint("TOPLEFT", 2, -2)
	button.preview:SetPoint("BOTTOMRIGHT", -18, 2)
	button.preview:SetAlpha(0.55)
	button.preview:Hide()

	button.text = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	button.text:SetPoint("LEFT", 6, 0)
	button.text:SetPoint("RIGHT", -18, 0)
	button.text:SetJustifyH("LEFT")

	local arrow = button:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	arrow:SetPoint("RIGHT", -6, 0)
	arrow:SetText("v")

	-- Pop-up list. Parented to UIParent (not the button) so it renders
	-- above everything and is never clipped by a scrolling container.
	local list = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
	list:SetPoint("TOPLEFT", button, "BOTTOMLEFT", 0, -2)
	list:SetPoint("TOPRIGHT", button, "BOTTOMRIGHT", 0, -2)
	list:SetFrameStrata("FULLSCREEN_DIALOG")
	list:SetToplevel(true)
	FlatBackdrop(list, 0.06, 0.06, 0.07, 0.98)
	list:EnableMouseWheel(true)
	list:Hide()
	list.rows = {}
	list.offset = 0
	list.filter = ""
	-- Close the list if the owning control is hidden (tab switch / panel close).
	button:HookScript("OnHide", function() list:Hide() end)

	local Populate   -- forward declaration (the search box references it)

	-- Optional search box at the top of the list, for long media lists.
	local SEARCH_H = 0
	local searchBox
	if cfg.searchable then
		SEARCH_H = 26
		searchBox = CreateFrame("EditBox", nil, list, "InputBoxTemplate")
		searchBox:SetAutoFocus(false)
		searchBox:SetHeight(18)
		searchBox:SetPoint("TOPLEFT", list, "TOPLEFT", 12, -5)
		searchBox:SetPoint("TOPRIGHT", list, "TOPRIGHT", -8, -5)
		searchBox:SetScript("OnTextChanged", function(self)
			list.filter = (self:GetText() or ""):lower()
			list.offset = 0
			Populate()
		end)
		searchBox:SetScript("OnEscapePressed", function(self) self:SetText(""); self:ClearFocus() end)
	end

	local function RowText(item)
		return item.text or tostring(item.value)
	end

	-- Items after applying the search filter (case-insensitive substring).
	local function GetItems()
		local items = cfg.items() or {}
		local f = list.filter
		if not f or f == "" then return items end
		local out = {}
		for _, it in ipairs(items) do
			if RowText(it):lower():find(f, 1, true) then
				out[#out + 1] = it
			end
		end
		return out
	end

	Populate = function()
		local items = GetItems()
		list._items = items
		local shown = math.min(#items, MAX_ROWS)
		list:SetHeight(SEARCH_H + math.max(shown, 1) * ROW_H + 4)

		for i = 1, shown do
			local row = list.rows[i]
			if not row then
				row = CreateFrame("Button", nil, list)
				row:SetHeight(ROW_H)
				row:SetPoint("TOPLEFT", list, "TOPLEFT", 2, -2 - SEARCH_H - (i - 1) * ROW_H)
				row:SetPoint("TOPRIGHT", list, "TOPRIGHT", -2, -2 - SEARCH_H - (i - 1) * ROW_H)
				row.tex = row:CreateTexture(nil, "ARTWORK")
				row.tex:SetAllPoints()
				row.tex:SetAlpha(0.45)
				row.tex:Hide()
				row.fs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
				row.fs:SetPoint("LEFT", 6, 0)
				row.hl = row:CreateTexture(nil, "HIGHLIGHT")
				row.hl:SetAllPoints()
				row.hl:SetColorTexture(0.3, 0.5, 0.9, 0.3)
				list.rows[i] = row
			end
			row:Show()
		end
		for i = shown + 1, #list.rows do
			list.rows[i]:Hide()
		end
		list.Refresh()
	end

	function list.Refresh()
		local items = list._items or {}
		local shown = math.min(#items, MAX_ROWS)
		local maxOffset = math.max(0, #items - MAX_ROWS)
		if list.offset > maxOffset then list.offset = maxOffset end
		if list.offset < 0 then list.offset = 0 end
		for i = 1, shown do
			local item = items[i + list.offset]
			local row = list.rows[i]
			if item then
				row.fs:SetText(RowText(item))
				if item.texture then
					row.tex:SetTexture(item.texture)
					row.tex:Show()
				else
					row.tex:Hide()
				end
				if item.font then
					row.fs:SetFont(item.font, 12, "")
				else
					row.fs:SetFontObject("GameFontHighlightSmall")
				end
				row:SetScript("OnClick", function()
					cfg.set(item.value)
					list:Hide()
					container.Refresh()
				end)
				row:Show()
			else
				row:Hide()
			end
		end
	end

	list:SetScript("OnMouseWheel", function(self, delta)
		self.offset = self.offset - delta
		self.Refresh()
	end)

	button:SetScript("OnClick", function()
		if list:IsShown() then
			list:Hide()
		else
			if searchBox then
				searchBox:SetText("")
				list.filter = ""
			end
			list.offset = 0
			Populate()
			list:Show()
			if searchBox then searchBox:SetFocus() end
		end
	end)

	-- Close when clicking elsewhere
	list:SetScript("OnHide", function() list.offset = 0 end)

	container.Refresh = function()
		local cur = cfg.get()
		button.text:SetText(cur or "")
		-- preview current if it is a statusbar texture value
		if cfg.previewTexture then
			local path = cfg.previewTexture(cur)
			if path then
				button.preview:SetTexture(path)
				button.preview:Show()
			else
				button.preview:Hide()
			end
		end
		if cfg.previewFont then
			local path = cfg.previewFont(cur)
			if path then button.text:SetFont(path, 12, "") end
		end
	end
	container.list = list
	container.Refresh()
	return container
end

-- ---------------------------------------------------------------------
--  Color picker + swatch
-- ---------------------------------------------------------------------
function Widgets.ShowColorPicker(r, g, b, a, callback)
	local hasOpacity = (a ~= nil)
	if ColorPickerFrame.SetupColorPickerAndShow then
		-- Modern API (Dragonflight / Classic 1.15+)
		local info = {
			r = r, g = g, b = b,
			hasOpacity = hasOpacity,
			opacity = a,
			swatchFunc = function()
				local nr, ng, nb = ColorPickerFrame:GetColorRGB()
				local na = hasOpacity and ColorPickerFrame:GetColorAlpha() or 1
				callback(nr, ng, nb, na)
			end,
			opacityFunc = function()
				local nr, ng, nb = ColorPickerFrame:GetColorRGB()
				local na = hasOpacity and ColorPickerFrame:GetColorAlpha() or 1
				callback(nr, ng, nb, na)
			end,
			cancelFunc = function()
				callback(r, g, b, a)
			end,
		}
		ColorPickerFrame:SetupColorPickerAndShow(info)
	else
		-- Legacy API
		ColorPickerFrame:SetColorRGB(r, g, b)
		ColorPickerFrame.hasOpacity = hasOpacity
		ColorPickerFrame.opacity = hasOpacity and (1 - a) or nil
		local function apply()
			local nr, ng, nb = ColorPickerFrame:GetColorRGB()
			local na = 1
			if hasOpacity and OpacitySliderFrame then
				na = 1 - OpacitySliderFrame:GetValue()
			end
			callback(nr, ng, nb, na)
		end
		ColorPickerFrame.func = apply
		ColorPickerFrame.opacityFunc = apply
		ColorPickerFrame.cancelFunc = function() callback(r, g, b, a) end
		ColorPickerFrame:Hide()
		ColorPickerFrame:Show()
	end
end

function Widgets.CreateColorSwatch(parent, labelText, cfg)
	local container = CreateFrame("Frame", nil, parent)
	container:SetSize(260, 22)

	local swatch = CreateFrame("Button", nil, container, "BackdropTemplate")
	swatch:SetPoint("LEFT", 0, 0)
	swatch:SetSize(22, 22)
	FlatBackdrop(swatch, 1, 1, 1, 1)
	swatch.color = swatch:CreateTexture(nil, "ARTWORK")
	swatch.color:SetPoint("TOPLEFT", 2, -2)
	swatch.color:SetPoint("BOTTOMRIGHT", -2, 2)
	swatch.color:SetTexture(WHITE)

	local label = container:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	label:SetPoint("LEFT", swatch, "RIGHT", 8, 0)
	label:SetText(labelText)

	swatch:SetScript("OnClick", function()
		local c = cfg.get()
		Widgets.ShowColorPicker(c[1], c[2], c[3], c[4], function(r, g, b, a)
			cfg.set({ r, g, b, a })
			container.Refresh()
		end)
	end)

	container.Refresh = function()
		local c = cfg.get()
		swatch.color:SetVertexColor(c[1], c[2], c[3], c[4] or 1)
	end
	container.Refresh()
	return container
end

-- ---------------------------------------------------------------------
--  Section header
-- ---------------------------------------------------------------------
function Widgets.CreateHeader(parent, text)
	local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	fs:SetText(text)
	return fs
end
