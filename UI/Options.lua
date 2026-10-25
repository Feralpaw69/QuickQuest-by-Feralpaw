-- QuickQuest
-- Options in Esc > Interface > AddOns > QuickQuest

local _, QQ = ...

local Options = {}
QQ.Options = Options

local widgets = {}
local count = 0
local function NewName()
	count = count + 1
	return "QuickQuestOption" .. count
end

local function Changed()
	QQ:ApplyTheme()
	if QQ.Window then QQ.Window:ApplySettings() end
	if QQ.Arrow then QQ.Arrow:Refresh() end
	if QQ.Buttons then QQ.Buttons:ApplySettings() end
	if QQ.UpdateWorldPins then QQ.UpdateWorldPins() end
	QQ:RequestUpdate()
end

---------------------------------------------------------------------------
-- widgets
---------------------------------------------------------------------------
local function Header(panel, text, y)
	local fs = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	fs:SetPoint("TOPLEFT", 16, y)
	fs:SetText(text)
	local line = panel:CreateTexture(nil, "ARTWORK")
	line:SetHeight(1)
	line:SetPoint("LEFT", fs, "RIGHT", 8, 0)
	line:SetPoint("RIGHT", panel, "RIGHT", -16, 0)
	line:SetTexture(1, 0.82, 0, 0.25)
	return fs
end

local function Check(panel, x, y, label, tip, get, set)
	local cb = CreateFrame("CheckButton", NewName(), panel, "OptionsCheckButtonTemplate")
	cb:SetPoint("TOPLEFT", x, y)
	_G[cb:GetName() .. "Text"]:SetText(label)
	cb.tooltipText = label
	cb.tooltipRequirement = tip
	cb:SetScript("OnClick", function(self)
		set(self:GetChecked() and true or false)
		Changed()
	end)
	cb.refresh = function() cb:SetChecked(get() and true or false) end
	widgets[#widgets + 1] = cb
	return cb
end

local function Slider(panel, x, y, label, minV, maxV, step, get, set, format)
	local s = CreateFrame("Slider", NewName(), panel, "OptionsSliderTemplate")
	s:SetPoint("TOPLEFT", x, y)
	s:SetWidth(180)
	s:SetMinMaxValues(minV, maxV)
	s:SetValueStep(step)
	local name = s:GetName()
	_G[name .. "Low"]:SetText(minV)
	_G[name .. "High"]:SetText(maxV)
	local function Label(v)
		_G[name .. "Text"]:SetText(label .. ": " .. (format and format(v) or v))
	end
	s:SetScript("OnValueChanged", function(self, v)
		v = math.floor(v / step + 0.5) * step
		Label(v)
		if self.refreshing then return end
		set(v)
		Changed()
	end)
	s.refresh = function()
		s.refreshing = true
		local v = get()
		s:SetValue(v)
		Label(v)
		s.refreshing = false
	end
	widgets[#widgets + 1] = s
	return s
end

local function Dropdown(panel, x, y, label, values, get, set)
	local dd = CreateFrame("Frame", NewName(), panel, "UIDropDownMenuTemplate")
	dd:SetPoint("TOPLEFT", x - 16, y - 14)
	local title = dd:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	title:SetPoint("BOTTOMLEFT", dd, "TOPLEFT", 20, 2)
	title:SetText(label)
	UIDropDownMenu_SetWidth(dd, 160)
	UIDropDownMenu_Initialize(dd, function()
		for _, v in ipairs(values()) do
			local info = UIDropDownMenu_CreateInfo()
			info.text = v.text
			info.value = v.value
			info.checked = get() == v.value
			info.func = function()
				set(v.value)
				UIDropDownMenu_SetSelectedValue(dd, v.value)
				UIDropDownMenu_SetText(dd, v.text)
				Changed()
			end
			UIDropDownMenu_AddButton(info)
		end
	end)
	dd.refresh = function()
		for _, v in ipairs(values()) do
			if v.value == get() then
				UIDropDownMenu_SetSelectedValue(dd, v.value)
				UIDropDownMenu_SetText(dd, v.text)
			end
		end
	end
	widgets[#widgets + 1] = dd
	return dd
end

local function EditBox(panel, x, y, width, label, get, set)
	local eb = CreateFrame("EditBox", NewName(), panel, "InputBoxTemplate")
	eb:SetPoint("TOPLEFT", x + 6, y)
	eb:SetWidth(width)
	eb:SetHeight(20)
	eb:SetAutoFocus(false)
	if label then
		local title = eb:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
		title:SetPoint("BOTTOMLEFT", eb, "TOPLEFT", -4, 2)
		title:SetText(label)
	end
	local function Commit(self)
		set(self:GetText() or "")
		self:ClearFocus()
		Changed()
	end
	eb:SetScript("OnEnterPressed", Commit)
	eb:SetScript("OnEditFocusLost", function(self) set(self:GetText() or "") Changed() end)
	eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
	eb.refresh = function() eb:SetText(get() or "") eb:SetCursorPosition(0) end
	widgets[#widgets + 1] = eb
	return eb
end

local function Button(panel, x, y, text, width, onClick)
	local b = CreateFrame("Button", NewName(), panel, "UIPanelButtonTemplate")
	b:SetPoint("TOPLEFT", x, y)
	b:SetWidth(width or 140)
	b:SetHeight(22)
	b:SetText(text)
	b:SetScript("OnClick", onClick)
	return b
end

local function ColorSwatch(panel, x, y, label, get, set)
	local b = CreateFrame("Button", NewName(), panel)
	b:SetPoint("TOPLEFT", x, y)
	b:SetWidth(20)
	b:SetHeight(20)
	local bg = b:CreateTexture(nil, "BACKGROUND")
	bg:SetWidth(16)
	bg:SetHeight(16)
	bg:SetPoint("CENTER")
	bg:SetTexture(0.6, 0.6, 0.6, 1)
	b:SetNormalTexture("Interface\\ChatFrame\\ChatFrameColorSwatch")
	local text = b:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	text:SetPoint("LEFT", b, "RIGHT", 6, 0)
	text:SetText(label)
	local function Paint()
		local c = get()
		b:GetNormalTexture():SetVertexColor(c[1], c[2], c[3])
	end
	b:SetScript("OnClick", function()
		local c = get()
		local function Apply(r, g, bl)
			set({ r, g, bl })
			Paint()
			Changed()
		end
		ColorPickerFrame.hasOpacity = false
		ColorPickerFrame.previousValues = { c[1], c[2], c[3] }
		ColorPickerFrame.func = function() Apply(ColorPickerFrame:GetColorRGB()) end
		ColorPickerFrame.cancelFunc = function(prev) Apply(prev[1], prev[2], prev[3]) end
		ColorPickerFrame:SetColorRGB(c[1], c[2], c[3])
		ColorPickerFrame:Hide()
		ColorPickerFrame:Show()
	end)
	b.refresh = Paint
	widgets[#widgets + 1] = b
	return b
end

-- button that captures a key and binds it to a click on a frame
local MODIFIERS = { LSHIFT = true, RSHIFT = true, LCTRL = true, RCTRL = true, LALT = true, RALT = true, UNKNOWN = true }
local function KeyBind(panel, x, y, label, buttonName)
	local command = "CLICK " .. buttonName .. ":LeftButton"
	local b = CreateFrame("Button", NewName(), panel, "UIPanelButtonTemplate")
	b:SetPoint("TOPLEFT", x + 110, y)
	b:SetWidth(110)
	b:SetHeight(22)
	b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	local text = b:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	text:SetPoint("RIGHT", b, "LEFT", -8, 0)
	text:SetText(label)
	local function Show()
		local key = GetBindingKey(command)
		b:SetText(key and GetBindingText(key, "KEY_") or "|cff888888Not bound|r")
	end
	local function Save()
		SaveBindings(GetCurrentBindingSet())
		QQ:Fire("QQ_BINDINGS_CHANGED")
	end
	local function Clear()
		local k1, k2 = GetBindingKey(command)
		if k1 then SetBinding(k1) end
		if k2 then SetBinding(k2) end
	end
	local function Stop()
		b.waiting = nil
		b:EnableKeyboard(false)
		b:UnlockHighlight()
		Show()
	end
	b:SetScript("OnClick", function(self, button)
		if InCombatLockdown() then return end
		if button == "RightButton" then
			Clear()
			Save()
			Stop()
			return
		end
		if self.waiting then Stop() return end
		self.waiting = true
		self:EnableKeyboard(true)
		self:LockHighlight()
		self:SetText("|cffffd200Press a key|r")
	end)
	b:SetScript("OnKeyDown", function(self, key)
		if not self.waiting or MODIFIERS[key] then return end
		if key == "ESCAPE" then Stop() return end
		local combo = (IsAltKeyDown() and "ALT-" or "") .. (IsControlKeyDown() and "CTRL-" or "") .. (IsShiftKeyDown() and "SHIFT-" or "") .. key
		Clear()
		SetBindingClick(combo, buttonName, "LeftButton")
		Save()
		Stop()
	end)
	b:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText(label)
		GameTooltip:AddLine("Click, then press a key. Right-click removes the key.", 1, 1, 1, true)
		GameTooltip:Show()
	end)
	b:SetScript("OnLeave", GameTooltip_Hide)
	b:SetScript("OnHide", Stop)
	b.refresh = Show
	widgets[#widgets + 1] = b
	return b
end

local function ListValues(list)
	return function()
		local t = {}
		for _, v in ipairs(list) do t[#t + 1] = { text = v.name, value = v.key } end
		return t
	end
end

local function NewPanel(name, parent)
	local p = CreateFrame("Frame", nil, UIParent)
	p.name = name
	p.parent = parent
	p:Hide()
	p:SetScript("OnShow", function()
		for _, w in ipairs(widgets) do
			if w.refresh and w:GetParent() == p then w.refresh() end
		end
		if p.onShow then p.onShow() end
	end)
	InterfaceOptions_AddCategory(p)
	return p
end

local function Title(p, text, sub)
	local t = p:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
	t:SetPoint("TOPLEFT", 16, -16)
	t:SetText(text)
	if sub then
		local s = p:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
		s:SetPoint("TOPLEFT", t, "BOTTOMLEFT", 0, -6)
		s:SetPoint("RIGHT", p, "RIGHT", -16, 0)
		s:SetHeight(28)
		s:SetJustifyH("LEFT")
		s:SetJustifyV("TOP")
		s:SetText(sub)
	end
end

local function ThemeValues()
	local t = {}
	for _, theme in ipairs(QQ.themes) do t[#t + 1] = { text = theme.name, value = theme.key } end
	return t
end

---------------------------------------------------------------------------
-- panels
---------------------------------------------------------------------------
function Options:Init()
	local g, w, a, b, x, au = QQ.db.general, QQ.db.window, QQ.db.arrow, QQ.db.buttons, QQ.db.xp, QQ.db.automation

	-- main panel: look and window
	local main = NewPanel("QuickQuest")
	self.main = main
	Title(main, QQ.title .. " |cff888888v" .. QQ.version .. "|r", "Leveling guides with a direction arrow, quest item and target buttons.")
	Header(main, "Guide window", -70)
	Slider(main, 24, -102, "Width", 200, 500, 10, function() return w.width end, function(v) w.width = v end)
	Slider(main, 230, -102, "Upcoming steps", 0, 6, 1, function() return w.upcoming end, function(v) w.upcoming = v end)
	Slider(main, 24, -146, "Scale", 0.6, 1.6, 0.05, function() return g.scale end, function(v) g.scale = v end)
	Check(main, 16, -180, "Lock frames", "Frames can not be dragged", function() return g.locked end, function(v) g.locked = v end)
	Button(main, 16, -216, "Choose a guide", 140, function() QQ:ShowGuideMenu("cursor") end)
	Button(main, 164, -216, "Reset positions", 140, function() QQ:ResetPositions() end)
	local hint = main:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	hint:SetPoint("TOPLEFT", 16, -256)
	hint:SetPoint("RIGHT", main, "RIGHT", -16, 0)
	hint:SetJustifyH("LEFT")
	hint:SetText("Look, background and fonts: see the Appearance page. Shift + drag moves the quest item and target buttons.")

	-- appearance
	local look = NewPanel("Appearance", "QuickQuest")
	Title(look, "Appearance", "Frame design, background, ornaments and fonts.")
	Header(look, "Frame", -66)
	Dropdown(look, 16, -88, "Colour theme", ThemeValues, function() return g.theme end, function(v) g.theme = v end)
	Dropdown(look, 220, -88, "Frame style", ListValues(QQ.frameStyles), function() return g.style end, function(v) g.style = v end)
	Check(look, 16, -122, "Border in theme colour", "Colour the frame border in the theme colour", function() return g.themeBorder end, function(v) g.themeBorder = v end)
	Check(look, 220, -122, "Title banner", "Blizzard style banner with the addon name above the guide window", function() return g.banner end, function(v) g.banner = v end)
	Dropdown(look, 16, -162, "Background", ListValues(QQ.backgrounds), function() return g.background end, function(v) g.background = v end)
	Dropdown(look, 220, -162, "Ornaments", ListValues(QQ.ornaments), function() return g.ornaments end, function(v) g.ornaments = v end)
	Slider(look, 24, -212, "Background opacity", 0.3, 1, 0.05, function() return g.bgAlpha end, function(v) g.bgAlpha = v end, function(v) return math.floor(v * 100 + 0.5) .. "%" end)
	Slider(look, 230, -212, "Darken background", 0, 0.9, 0.05, function() return g.bgDim end, function(v) g.bgDim = v end, function(v) return math.floor(v * 100 + 0.5) .. "%" end)

	Header(look, "Text", -246)
	Dropdown(look, 16, -268, "Font", ListValues(QQ.fonts), function() return g.font end, function(v) g.font = v end)
	Dropdown(look, 220, -268, "Outline", function()
		return { { text = "None (shadow)", value = "" }, { text = "Outline", value = "OUTLINE" }, { text = "Thick outline", value = "THICKOUTLINE" } }
	end, function() return g.outline end, function(v) g.outline = v end)
	Dropdown(look, 16, -314, "Heading colour", function()
		return { { text = "Automatic", value = "auto" }, { text = "Gold", value = "gold" }, { text = "Theme colour", value = "theme" }, { text = "White", value = "white" } }
	end, function() return g.headingColor end, function(v) g.headingColor = v end)
	ColorSwatch(look, 236, -318, "Text colour", function() return g.textColor end, function(v) g.textColor = v end)
	Slider(look, 24, -364, "Font size", 9, 16, 1, function() return g.fontSize end, function(v) g.fontSize = v end)
	Button(look, 230, -360, "Reset appearance", 150, function()
		for _, k in ipairs({ "theme", "style", "themeBorder", "bgAlpha", "background", "bgDim", "ornaments", "banner", "font", "outline", "headingColor", "fontSize" }) do
			g[k] = QQ.defaults.general[k]
		end
		g.textColor = { 1, 1, 1 }
		Changed()
		look:Hide()
		look:Show()
	end)

	local credits = main:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
	credits:SetPoint("BOTTOMLEFT", 16, 16)
	credits:SetPoint("RIGHT", main, "RIGHT", -16, 0)
	credits:SetJustifyH("LEFT")
	credits:SetText("Guide content: RestedXP Guides (CC BY-NC-SA 4.0), adapted - not for commercial use. Map data from the 3.3.5 client, quest data from the AzerothCore world database (GPL-2.0).\nCommands: /qq, /qq guides, /qq next, /qq prev, /qq options")

	-- navigation and buttons
	local nav = NewPanel("Navigation & Buttons", "QuickQuest")
	Title(nav, "Navigation & Buttons")
	Header(nav, "Arrow and map", -50)
	Check(nav, 16, -70, "Show direction arrow", "Arrow pointing to the next waypoint (right-click it to skip a waypoint)", function() return a.enabled end, function(v) a.enabled = v end)
	Slider(nav, 24, -116, "Arrow scale", 0.5, 2, 0.05, function() return a.scale end, function(v) a.scale = v end)
	Dropdown(nav, 220, -84, "Arrow design", ListValues(QQ.arrowStyles), function() return a.style end, function(v) a.style = v end)
	Dropdown(nav, 220, -130, "Arrow colours", ListValues(QQ.arrowColors), function() return a.colors end, function(v) a.colors = v end)
	ColorSwatch(nav, 236, -166, "Custom arrow colour", function() return a.color end, function(v) a.color = v a.colors = "custom" end)
	Check(nav, 16, -146, "Waypoints on the world map", nil, function() return QQ.db.pins.worldMap end, function(v) QQ.db.pins.worldMap = v end)
	Check(nav, 16, -172, "Waypoints on the minimap", nil, function() return QQ.db.pins.minimap end, function(v) QQ.db.pins.minimap = v end)
	Header(nav, "Buttons", -210)
	Check(nav, 16, -230, "Quest item buttons", "Buttons for the items you have to use in the current step", function() return b.items end, function(v) b.items = v end)
	Check(nav, 16, -256, "Target buttons", "One button per NPC / enemy of the current step", function() return b.targets end, function(v) b.targets = v end)
	Check(nav, 16, -282, "Only nearby targets", "Show target buttons only while their nameplate is visible (V / Shift+V)", function() return b.nearbyOnly end, function(v) b.nearbyOnly = v end)
	Check(nav, 16, -308, "Targeting macro \"QQ Target\"", "Character macro that always targets the units of the current step - put it on an action bar", function() return b.macro end, function(v) b.macro = v end)
	Slider(nav, 24, -356, "Button scale", 0.6, 1.6, 0.05, function() return b.scale end, function(v) b.scale = v end)

	-- automation and guides
	local auto = NewPanel("Quests & Guides", "QuickQuest")
	Title(auto, "Quests & Guides", "Hold Shift while talking to an NPC to handle the quest yourself.")
	Header(auto, "Automation", -60)
	Check(auto, 16, -80, "Auto accept quests", nil, function() return au.accept end, function(v) au.accept = v end)
	Check(auto, 16, -106, "Auto turn in quests", "Quests with several rewards stay open so you can choose", function() return au.turnin end, function(v) au.turnin = v end)
	Check(auto, 16, -132, "Auto select quests in NPC dialogs", nil, function() return au.gossip end, function(v) au.gossip = v end)
	Header(auto, "Guide content", -170)
	Check(auto, 16, -190, "Show dungeon steps", "Steps for dungeon quests", function() return QQ.db.dungeons end, function(v) QQ.db.dungeons = v end)
	Dropdown(auto, 16, -232, "Shattrath faction", function()
		return { { text = "Aldor", value = "aldor" }, { text = "Scryers", value = "scryer" } }
	end, function() return QQ.db.shattrath or "aldor" end, function(v) QQ.db.shattrath = v end)
	Check(auto, 16, -292, "Suggest a guide for my level when outleveled", nil, function() return x.suggestNextGuide end, function(v) x.suggestNextGuide = v end)

	-- experience
	local xp = NewPanel("Experience", "QuickQuest")
	Title(xp, "Experience", "Buffs multiply the server rate: 5x with +20% and +50% = 9x.")
	xp.rateText = xp:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	xp.rateText:SetPoint("TOPRIGHT", -16, -18)
	local function ShowRate() xp.rateText:SetText(string.format("Current rate: |cffffffff%.2fx|r", QQ:GetXPRate())) end
	xp.onShow = ShowRate
	xp:SetScript("OnUpdate", function(self, e)
		self.t = (self.t or 0) + e
		if self.t > 0.5 then self.t = 0 ShowRate() end
	end)
	Header(xp, "Rate", -64)
	Check(xp, 16, -82, "Calculate the rate automatically", "Server rate x heirlooms x active buffs.\nOff: the fixed rate is used.", function() return x.auto end, function(v) x.auto = v end)
	Slider(xp, 24, -132, "Server rate", 1, 20, 0.5, function() return x.serverRate end, function(v) x.serverRate = v end, function(v) return v .. "x" end)
	Slider(xp, 230, -132, "Fixed rate", 1, 40, 0.5, function() return x.manualRate end, function(v) x.manualRate = v end, function(v) return v .. "x" end)

	Header(xp, "Buffs", -170)
	local l1 = xp:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	l1:SetPoint("TOPLEFT", 52, -188)
	l1:SetText("Bonus %")
	local l2 = xp:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	l2:SetPoint("TOPLEFT", 120, -188)
	l2:SetText("Only with buff (name / spell ID)")
	for i = 1, QQ.Leveling.NUM_BUFFS do
		local y = -204 - (i - 1) * 26
		local function B()
			x.buffs[i] = x.buffs[i] or { enabled = false, percent = 0, aura = "" }
			return x.buffs[i]
		end
		Check(xp, 16, y + 3, "", "Enable this buff", function() return B().enabled end, function(v) B().enabled = v end)
		EditBox(xp, 46, y, 50, nil, function() return tostring(B().percent or 0) end, function(v) B().percent = tonumber(v) or 0 end)
		EditBox(xp, 114, y, 190, nil, function() return B().aura or "" end, function(v) B().aura = v end)
	end

	Header(xp, "Skipping", -318)
	Check(xp, 16, -336, "Skip low level quests", "Quests far below your level are skipped, unless a later quest that still gives experience needs them. Quests that need a skipped quest are skipped too.", function() return x.skipLowQuests end, function(v) x.skipLowQuests = v end)
	Check(xp, 16, -362, "Skip outleveled steps", "Steps the guide marks for lower levels", function() return x.skipXpSteps end, function(v) x.skipXpSteps = v end)
	Slider(xp, 24, -412, "Low level: levels below you", 2, 15, 1, function() return x.lowQuestDiff end, function(v) x.lowQuestDiff = v end)

	-- key bindings
	local keys = NewPanel("Key Bindings", "QuickQuest")
	Title(keys, "Key Bindings", "Fixed keys for the quest item and target buttons (also in Esc > Key Bindings > QuickQuest). Click a button and press a key, right-click removes it.")
	Header(keys, "Quest items", -70)
	for i = 1, QQ.Buttons.BINDABLE do
		KeyBind(keys, 16, -70 - i * 28, "Quest item " .. i, "QuickQuestItem" .. i)
	end
	Header(keys, "Targets", -96 - QQ.Buttons.BINDABLE * 28)
	for i = 1, QQ.Buttons.BINDABLE do
		KeyBind(keys, 16, -96 - QQ.Buttons.BINDABLE * 28 - i * 28, "Target " .. i, "QuickQuestTarget" .. i)
	end
end

function Options:Open()
	if not self.main then return end
	InterfaceOptionsFrame_OpenToCategory(self.main)
	InterfaceOptionsFrame_OpenToCategory(self.main)
end

QQ:On("QQ_INIT", function() Options:Init() end)
