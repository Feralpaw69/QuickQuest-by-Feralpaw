-- QuickQuest
-- Core: saved settings, events, timers, printing, theme and skin helpers

local ADDON, QQ = ...
_G.QuickQuest = QQ

QQ.name = ADDON
QQ.version = GetAddOnMetadata(ADDON, "Version") or "1.0"
QQ.media = "Interface\\AddOns\\" .. ADDON .. "\\Media\\"
QQ.title = "|cff7fb2ffQuick|rQuest"

local floor = math.floor
local tinsert = table.insert

---------------------------------------------------------------------------
-- Defaults
---------------------------------------------------------------------------
QQ.defaults = {
	general = {
		theme = "class_DEATHKNIGHT",
		style = "gold", -- key of QQ.frameStyles
		themeBorder = true,
		bgAlpha = 0.9,
		background = "leather", -- key of QQ.backgrounds
		bgDim = 0.35, -- darkening of picture backgrounds (readability)
		ornaments = "lion", -- key of QQ.ornaments
		banner = true,
		font = "friz",
		outline = "",
		textColor = { 1, 1, 1 },
		headingColor = "auto",
		fontSize = 12,
		locked = false,
		scale = 1,
		hidden = false,
	},
	window = {
		width = 300,
		upcoming = 2, -- upcoming steps shown below the current one
		point = { "RIGHT", "UIParent", "RIGHT", -60, 80 },
	},
	arrow = {
		enabled = true,
		scale = 1.2,
		style = "gem", -- key of QQ.arrowStyles
		colors = "theme", -- key of QQ.arrowColors
		color = { 1, 0.82, 0 }, -- custom colour
		point = { "TOP", "UIParent", "TOP", 0, -120 },
	},
	pins = {
		worldMap = true,
		minimap = true,
	},
	buttons = {
		items = true,
		targets = true,
		macro = true,
		nearbyOnly = false,
		scale = 1,
		itemPoint = { "CENTER", "UIParent", "CENTER", 0, -180 },
		targetPoint = { "CENTER", "UIParent", "CENTER", 0, -230 },
	},
	automation = {
		accept = true,
		turnin = true,
		gossip = true,
	},
	xp = {
		serverRate = 1,
		auto = true,
		manualRate = 1,
		skipLowQuests = true,
		lowQuestDiff = 6,
		suggestNextGuide = true,
		goldMode = false, -- "Quest for gold": every quest, no xp based skipping, best paying reward
		syncProgress = true, -- jump to the own quest progress when a guide is chosen
		skipXpSteps = true,
		buffs = {}, -- { enabled, percent, aura }
	},
	dungeons = false,
}

QQ.charDefaults = {
	guide = nil, -- "group||name"
	steps = {}, -- [guideKey] = current step
	state = {}, -- [guideKey] = { [stepIndex] = "done" | "skip" }
	completed = {}, -- quests turned in (filled from the server and on turn in)
}

local function CopyDefaults(src, dst)
	if type(dst) ~= "table" then dst = {} end
	for k, v in pairs(src) do
		if type(v) == "table" then
			if k == "point" then
				if type(dst[k]) ~= "table" then dst[k] = { v[1], v[2], v[3], v[4], v[5] } end
			else
				dst[k] = CopyDefaults(v, dst[k])
			end
		elseif dst[k] == nil then
			dst[k] = v
		end
	end
	return dst
end
QQ.CopyDefaults = CopyDefaults

---------------------------------------------------------------------------
-- Printing
---------------------------------------------------------------------------
function QQ:Print(...)
	local msg = ""
	for i = 1, select("#", ...) do
		msg = msg .. (i > 1 and " " or "") .. tostring((select(i, ...)))
	end
	DEFAULT_CHAT_FRAME:AddMessage(QQ.title .. ": " .. msg)
end

function QQ:Printf(fmt, ...)
	self:Print(fmt:format(...))
end

---------------------------------------------------------------------------
-- Events (several modules may listen to the same event)
---------------------------------------------------------------------------
local eventFrame = CreateFrame("Frame")
local listeners = {}

function QQ:On(event, fn)
	if not listeners[event] then
		listeners[event] = {}
		eventFrame:RegisterEvent(event)
	end
	tinsert(listeners[event], fn)
end

function QQ:Fire(event, ...)
	local list = listeners[event]
	if not list then return end
	for i = 1, #list do
		local ok, err = pcall(list[i], event, ...)
		if not ok then geterrorhandler()(err) end
	end
end

eventFrame:SetScript("OnEvent", function(_, event, ...)
	QQ:Fire(event, ...)
end)

---------------------------------------------------------------------------
-- Timers
---------------------------------------------------------------------------
local timers = {}
local timerFrame = CreateFrame("Frame")
timerFrame:Hide()
timerFrame:SetScript("OnUpdate", function(self)
	local now = GetTime()
	local i = 1
	while i <= #timers do
		local t = timers[i]
		if now >= t.at then
			if t.every then
				t.at = now + t.every
				i = i + 1
			else
				table.remove(timers, i)
			end
			local ok, err = pcall(t.fn)
			if not ok then geterrorhandler()(err) end
		else
			i = i + 1
		end
	end
	if #timers == 0 then self:Hide() end
end)

function QQ:After(delay, fn)
	tinsert(timers, { at = GetTime() + delay, fn = fn })
	timerFrame:Show()
end

function QQ:Every(interval, fn)
	local t = { at = GetTime() + interval, every = interval, fn = fn }
	tinsert(timers, t)
	timerFrame:Show()
	return t
end

-- runs fn once, a short moment after the last call (for bursts of events)
function QQ:Debounce(key, delay, fn)
	self.debounced = self.debounced or {}
	if self.debounced[key] then return end
	self.debounced[key] = true
	self:After(delay, function()
		self.debounced[key] = nil
		fn()
	end)
end

---------------------------------------------------------------------------
-- Themes (same set as the other addons of this collection)
---------------------------------------------------------------------------
QQ.themes = {
	{ key = "black",    name = "Black (default)", top = { 0.10, 0.10, 0.11 }, bottom = { 0.02, 0.02, 0.02 }, border = { 0.30, 0.30, 0.32 }, accent = { 0.92, 0.96, 1.00 } },
	{ key = "midnight", name = "Midnight Blue", top = { 0.05, 0.12, 0.30 }, bottom = { 0.01, 0.02, 0.07 }, border = { 0.35, 0.55, 1.00 }, accent = { 0.35, 0.60, 1.00 } },
	{ key = "crimson",  name = "Crimson Gold",  top = { 0.30, 0.05, 0.03 }, bottom = { 0.07, 0.01, 0.01 }, border = { 1.00, 0.78, 0.20 }, accent = { 1.00, 0.30, 0.25 } },
	{ key = "emerald",  name = "Emerald",       top = { 0.03, 0.22, 0.14 }, bottom = { 0.01, 0.05, 0.03 }, border = { 0.30, 0.90, 0.60 }, accent = { 0.30, 1.00, 0.50 } },
}
do
	local CLASSES = {
		{ "DEATHKNIGHT", "Death Knight", 0.77, 0.12, 0.23 }, { "DRUID", "Druid", 1.00, 0.49, 0.04 },
		{ "HUNTER", "Hunter", 0.67, 0.83, 0.45 }, { "MAGE", "Mage", 0.41, 0.80, 0.94 },
		{ "PALADIN", "Paladin", 0.96, 0.55, 0.73 }, { "PRIEST", "Priest", 1.00, 1.00, 1.00 },
		{ "ROGUE", "Rogue", 1.00, 0.96, 0.41 }, { "SHAMAN", "Shaman", 0.00, 0.44, 0.87 },
		{ "WARLOCK", "Warlock", 0.58, 0.51, 0.79 }, { "WARRIOR", "Warrior", 0.78, 0.61, 0.43 },
	}
	for _, class in ipairs(CLASSES) do
		local token, name, r, g, b = class[1], class[2], class[3], class[4], class[5]
		local c = RAID_CLASS_COLORS and RAID_CLASS_COLORS[token]
		if c then r, g, b = c.r, c.g, c.b end
		tinsert(QQ.themes, {
			key = "class_" .. token, name = name,
			top = { r * 0.32, g * 0.32, b * 0.32 }, bottom = { r * 0.07, g * 0.07, b * 0.07 },
			border = { r, g, b }, accent = { r, g, b },
		})
	end
	local EXTRA = {
		{ key = "purple", name = "Royal Purple", top = { 0.20, 0.06, 0.32 }, bottom = { 0.04, 0.01, 0.07 }, border = { 0.73, 0.45, 1.00 }, accent = { 0.80, 0.52, 1.00 } },
		{ key = "frost",  name = "Frost",        top = { 0.06, 0.22, 0.30 }, bottom = { 0.01, 0.05, 0.07 }, border = { 0.55, 0.90, 1.00 }, accent = { 0.62, 0.95, 1.00 } },
		{ key = "amber",  name = "Amber",        top = { 0.30, 0.17, 0.02 }, bottom = { 0.07, 0.04, 0.00 }, border = { 1.00, 0.65, 0.15 }, accent = { 1.00, 0.72, 0.22 } },
		{ key = "rose",   name = "Rose",         top = { 0.30, 0.05, 0.18 }, bottom = { 0.07, 0.01, 0.04 }, border = { 1.00, 0.45, 0.70 }, accent = { 1.00, 0.52, 0.76 } },
		{ key = "steel",  name = "Steel",        top = { 0.18, 0.20, 0.23 }, bottom = { 0.05, 0.05, 0.06 }, border = { 0.70, 0.75, 0.82 }, accent = { 0.82, 0.87, 0.94 } },
	}
	for _, t in ipairs(EXTRA) do tinsert(QQ.themes, t) end
end

function QQ:GetTheme()
	local key = self.db and self.db.general.theme
	for _, t in ipairs(self.themes) do
		if t.key == key then return t end
	end
	return self.themes[1]
end

---------------------------------------------------------------------------
-- Frame styles, backgrounds, ornaments and fonts
---------------------------------------------------------------------------
QQ.frameStyles = {
	{ key = "blizzard", name = "Blizzard (silver border)", edge = "Interface\\Tooltips\\UI-Tooltip-Border", big = { 16, 4 }, small = { 10, 2 } },
	{ key = "dialog", name = "WoW window (stone border)", edge = "Interface\\DialogFrame\\UI-DialogBox-Border", big = { 26, 8 }, small = { 12, 3 } },
	{ key = "gold", name = "WoW window (gold border)", edge = "Interface\\DialogFrame\\UI-DialogBox-Gold-Border", big = { 26, 8 }, small = { 12, 3 } },
	{ key = "pixel", name = "Pixel (thin lines)", edge = "Interface\\Buttons\\WHITE8X8", big = { 1, 1 }, small = { 1, 1 } },
}

-- image: stretched picture (cropped to the frame), tile: tiled Blizzard texture, none: theme gradient
QQ.backgrounds = {
	{ key = "leather", name = "Dark leather", image = QQ.media .. "BG-Leather" },
	{ key = "wood", name = "Dark wood", image = QQ.media .. "BG-Wood" },
	{ key = "stone", name = "Dark stone", image = QQ.media .. "BG-Stone" },
	{ key = "marble", name = "Obsidian", image = QQ.media .. "BG-Marble" },
	{ key = "frost", name = "Northrend frost", image = QQ.media .. "BG-Frost" },
	{ key = "midnight", name = "Midnight", image = QQ.media .. "BG-Midnight" },
	{ key = "nether", name = "Twisting Nether", image = QQ.media .. "BG-Nether" },
	{ key = "emerald", name = "Emerald Dream", image = QQ.media .. "BG-Emerald" },
	{ key = "blood", name = "Blood", image = QQ.media .. "BG-Blood" },
	{ key = "dialog", name = "Blizzard dialog (black)", tile = "Interface\\DialogFrame\\UI-DialogBox-Background" },
	{ key = "theme", name = "Theme colour (gradient)" },
}

QQ.ornaments = {
	{ key = "none", name = "None" },
	{ key = "gryphon", name = "Gryphons", file = "Interface\\MainMenuBar\\UI-MainMenuBar-EndCap-Dwarf" },
	{ key = "lion", name = "Lions", file = "Interface\\MainMenuBar\\UI-MainMenuBar-EndCap-Human" },
	{ key = "skull", name = "Skulls", file = QQ.media .. "Orn-Skull", own = true },
	{ key = "crystals", name = "Ice crystals", file = QQ.media .. "Orn-Crystals", own = true },
	{ key = "horns", name = "Horns", file = QQ.media .. "Orn-Horns", own = true },
	{ key = "gem", name = "Gems", file = QQ.media .. "Orn-Gem", own = true },
	{ key = "spikes", name = "Spikes", file = QQ.media .. "Orn-Spikes", own = true },
}

QQ.fonts = {
	{ key = "friz", name = "Friz Quadrata (default)", file = "Fonts\\FRIZQT__.TTF" },
	{ key = "arial", name = "Arial Narrow", file = "Fonts\\ARIALN.TTF" },
	{ key = "morpheus", name = "Morpheus", file = "Fonts\\MORPHEUS.TTF" },
	{ key = "skurri", name = "Skurri", file = "Fonts\\SKURRI.TTF" },
}

local function Find(list, key)
	for _, v in ipairs(list) do
		if v.key == key then return v end
	end
	return list[1]
end

function QQ:GetFrameStyle() return Find(self.frameStyles, self.db and self.db.general.style) end
function QQ:GetBackground() return Find(self.backgrounds, self.db and self.db.general.background) end

function QQ:IsPixelStyle()
	return self:GetFrameStyle().key == "pixel"
end

-- inner padding of a skinned frame (content starts here)
function QQ:FramePad(big)
	local st = self:GetFrameStyle()
	return (big and st.big or st.small)[2]
end

local function Backdrop(big, tile)
	local st = QQ:GetFrameStyle()
	local edge, inset = unpack(big and st.big or st.small)
	return {
		bgFile = tile or "Interface\\Buttons\\WHITE8X8", edgeFile = st.edge,
		tile = tile and true or false, tileSize = tile and 32 or 0,
		edgeSize = edge, insets = { left = inset, right = inset, top = inset, bottom = inset },
	}
end

-- small bordered box (icons, buttons)
function QQ:Border(frame, a)
	local st = self:GetFrameStyle()
	frame:SetBackdrop({
		bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = st.key == "pixel" and st.edge or "Interface\\Tooltips\\UI-Tooltip-Border",
		edgeSize = st.key == "pixel" and 1 or 10, insets = { left = 2, right = 2, top = 2, bottom = 2 },
	})
	frame:SetBackdropColor(0, 0, 0, a or 0.6)
	if st.key == "pixel" then
		frame:SetBackdropBorderColor(0, 0, 0, 1)
	else
		frame:SetBackdropBorderColor(0.6, 0.6, 0.6, 1)
	end
end

QQ.skinned = {}
QQ.accents = {}

-- crops a square picture so it fills the frame without stretching
local function FitImage(frame)
	local tex, bg = frame.qqTint, frame.qqImage
	if not bg then return end
	local w, h = tex:GetWidth(), tex:GetHeight()
	if not w or not h or w <= 0 or h <= 0 then return end
	local fx, fy = bg.fx or 0.5, bg.fy or 0.5
	local aspect = w / h
	if aspect < 1 then
		local left = math.max(0, math.min(1 - aspect, fx - aspect / 2))
		tex:SetTexCoord(left, left + aspect, 0, 1)
	else
		local part = 1 / aspect
		local top = math.max(0, math.min(1 - part, fy - part / 2))
		tex:SetTexCoord(0, 1, top, top + part)
	end
end

local function Ornaments(frame)
	local o = Find(QQ.ornaments, QQ.db.general.ornaments)
	if not o.file then
		if frame.qqDeco then frame.qqDeco:Hide() end
		return
	end
	if not frame.qqDeco then
		local d = CreateFrame("Frame", nil, frame)
		d:SetAllPoints()
		d.left = d:CreateTexture(nil, "OVERLAY")
		d.right = d:CreateTexture(nil, "OVERLAY")
		d.right:SetTexCoord(1, 0, 0, 1)
		frame.qqDeco = d
	end
	local d = frame.qqDeco
	d:SetFrameLevel(frame:GetFrameLevel() + 6)
	-- sitting on the top corners of the frame
	local size = o.own and 44 or 64
	for _, t in ipairs({ d.left, d.right }) do
		t:SetTexture(o.file)
		t:SetWidth(size)
		t:SetHeight(size)
		t:ClearAllPoints()
	end
	local sink = QQ:FramePad(true) + (o.own and 0 or 2)
	-- inside the frame width, nothing sticks out at the sides
	d.left:SetPoint("BOTTOMLEFT", frame, "TOPLEFT", 0, -sink)
	d.right:SetPoint("BOTTOMRIGHT", frame, "TOPRIGHT", 0, -sink)
	d:Show()
end

-- themed panel: background (gradient, picture or texture) + border
function QQ:Skin(frame, inset)
	frame.qqBig = not inset
	frame.qqInset = inset and true or nil
	local bg = self:GetBackground()
	-- pictures only on the big frames, the small bars use the theme gradient
	if inset and bg.image then bg = Find(self.backgrounds, "theme") end
	frame:SetBackdrop(Backdrop(not inset, bg.tile))
	if not frame.qqTint then
		frame.qqTint = frame:CreateTexture(nil, "BACKGROUND")
		frame.qqDim = frame:CreateTexture(nil, "BORDER")
		frame.qqDim:SetAllPoints(frame.qqTint)
		frame:HookScript("OnSizeChanged", FitImage)
	end
	local p = self:FramePad(not inset)
	if self:GetFrameStyle().key == "blizzard" then p = inset and 3 or 4 end
	frame.qqTint:ClearAllPoints()
	frame.qqTint:SetPoint("TOPLEFT", frame, "TOPLEFT", p, -p)
	frame.qqTint:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -p, p)
	frame.qqBgDef = bg
	if not frame.qqSkinned then
		frame.qqSkinned = true
		tinsert(self.skinned, frame)
	end
	if not inset then Ornaments(frame) end
	self:ApplyThemeTo(frame)
end

function QQ:ApplyThemeTo(frame)
	local t = self:GetTheme()
	local a = self.db.general.bgAlpha or 0.9
	local bg = frame.qqBgDef or self:GetBackground()
	local tint, dim = frame.qqTint, frame.qqDim
	frame.qqImage = nil
	if bg.image then
		frame:SetBackdropColor(0, 0, 0, a)
		tint:SetTexture(bg.image)
		tint:SetVertexColor(1, 1, 1, a)
		tint:SetGradientAlpha("VERTICAL", 1, 1, 1, a, 1, 1, 1, a)
		frame.qqImage = bg
		FitImage(frame)
		dim:SetTexture(0, 0, 0, 1)
		dim:SetGradientAlpha("VERTICAL", 0, 0, 0, math.min(1, (self.db.general.bgDim or 0.5) * 1.15), 0, 0, 0, (self.db.general.bgDim or 0.5) * 0.85)
		dim:Show()
		tint:Show()
	elseif bg.tile then
		frame:SetBackdropColor(1, 1, 1, a)
		tint:Hide()
		dim:Hide()
	else
		frame:SetBackdropColor(t.bottom[1], t.bottom[2], t.bottom[3], a)
		tint:SetTexture(1, 1, 1, 1)
		tint:SetTexCoord(0, 1, 0, 1)
		tint:SetGradientAlpha("VERTICAL",
			t.bottom[1], t.bottom[2], t.bottom[3], a,
			t.top[1], t.top[2], t.top[3], a)
		tint:Show()
		dim:Hide()
	end
	if self:IsPixelStyle() or self.db.general.themeBorder or frame.qqInset then
		frame:SetBackdropBorderColor(t.border[1], t.border[2], t.border[3], 1)
	else
		frame:SetBackdropBorderColor(self:GetFrameStyle().key == "blizzard" and 0.85 or 1, self:GetFrameStyle().key == "blizzard" and 0.85 or 1, self:GetFrameStyle().key == "blizzard" and 0.85 or 1, 1)
	end
end

function QQ:HeadingColor()
	local mode = self.db and self.db.general.headingColor or "auto"
	local c = self:GetTheme().accent
	if mode == "gold" or (mode == "auto" and not self:IsPixelStyle()) then return 1, 0.82, 0 end
	if mode == "white" then return 1, 1, 1 end
	return c[1], c[2], c[3]
end

-- kind: "text" (heading colour), "texture" (vertex colour)
function QQ:Accent(region, kind, alpha)
	local e = { region = region, kind = kind or "text", alpha = alpha or 1 }
	region.qqBody = nil
	tinsert(self.accents, e)
	self:ApplyAccent(e)
end

function QQ:ApplyAccent(e)
	if e.kind == "text" then
		e.region:SetTextColor(self:HeadingColor())
	else
		local c = self:GetTheme().accent
		e.region:SetVertexColor(c[1], c[2], c[3], e.alpha)
	end
end

function QQ:ApplyTheme()
	for _, f in ipairs(self.skinned) do
		if f.qqSkinned then self:Skin(f, f.qqInset) end
	end
	for _, e in ipairs(self.accents) do self:ApplyAccent(e) end
	self:ApplyFonts()
	self:Fire("QQ_THEME_CHANGED")
end

QQ.texts = {}

function QQ:FontFile()
	return Find(self.fonts, self.db and self.db.general.font).file
end

function QQ:SetFont(fs, delta)
	local g = self.db and self.db.general
	local file = fs.qqFixedFont and STANDARD_TEXT_FONT or self:FontFile()
	local size = (g and g.fontSize or 12) + (delta or 0)
	fs:SetFont(file, size, g and g.outline or "")
end

-- body text colour (multiplied with "dim", e.g. 0.8 for secondary text)
function QQ:TextColor(dim)
	local c = self.db and self.db.general.textColor or { 1, 1, 1 }
	dim = dim or 1
	return c[1] * dim, c[2] * dim, c[3] * dim
end

function QQ:ApplyFonts()
	for _, fs in ipairs(self.texts) do
		self:SetFont(fs, fs.qqDelta)
		if fs.qqBody then fs:SetTextColor(self:TextColor(fs.qqBody)) end
	end
end

-- dim: body text with this brightness (nil: the caller colours the text itself)
function QQ:Text(parent, layer, delta, justify, dim)
	local fs = parent:CreateFontString(nil, layer or "OVERLAY")
	fs.qqDelta = delta or 0
	fs.qqBody = dim or 1
	self:SetFont(fs, delta)
	fs:SetShadowOffset(1, -1)
	fs:SetShadowColor(0, 0, 0, 1)
	fs:SetJustifyH(justify or "LEFT")
	fs:SetTextColor(self:TextColor(fs.qqBody))
	tinsert(self.texts, fs)
	return fs
end

---------------------------------------------------------------------------
-- Moving frames and saving positions
---------------------------------------------------------------------------
function QQ:SavePosition(frame, store)
	local point, _, relPoint, x, y = frame:GetPoint(1)
	store[1], store[2], store[3], store[4], store[5] = point, "UIParent", relPoint, floor(x + 0.5), floor(y + 0.5)
end

function QQ:LoadPosition(frame, store)
	frame:ClearAllPoints()
	frame:SetPoint(store[1] or "CENTER", UIParent, store[3] or "CENTER", store[4] or 0, store[5] or 0)
end

function QQ:MakeDraggable(handle, moveFrame, store, onStop)
	moveFrame:SetMovable(true)
	moveFrame:SetClampedToScreen(true)
	handle:EnableMouse(true)
	handle:RegisterForDrag("LeftButton")
	handle:SetScript("OnDragStart", function()
		if QQ.db.general.locked or InCombatLockdown() and moveFrame:IsProtected() then return end
		moveFrame:StartMoving()
		moveFrame.qqMoving = true
	end)
	handle:SetScript("OnDragStop", function()
		if not moveFrame.qqMoving then return end
		moveFrame.qqMoving = nil
		moveFrame:StopMovingOrSizing()
		if store then QQ:SavePosition(moveFrame, store) end
		if onStop then onStop() end
	end)
end

---------------------------------------------------------------------------
-- Player
---------------------------------------------------------------------------
QQ.player = {}
local function UpdatePlayer()
	local p = QQ.player
	p.name = UnitName("player")
	p.class = select(2, UnitClass("player"))
	p.race = select(2, UnitRace("player"))
	p.faction = UnitFactionGroup("player")
	p.level = UnitLevel("player")
end

UpdatePlayer() -- class / race / faction are known while the addon loads (needed by the guide filters)

---------------------------------------------------------------------------
-- Loading
---------------------------------------------------------------------------
QQ:On("ADDON_LOADED", function(_, name)
	if name ~= ADDON then return end
	QuickQuestDB = CopyDefaults(QQ.defaults, QuickQuestDB)
	QuickQuestCharDB = CopyDefaults(QQ.charDefaults, QuickQuestCharDB)
	QQ.db = QuickQuestDB
	if QQ.db.general.background == "lichking" then QQ.db.general.background = "leather" end
	QQ.char = QuickQuestCharDB
	UpdatePlayer()
	QQ:Fire("QQ_INIT")
end)

QQ:On("PLAYER_LOGIN", function()
	UpdatePlayer()
	QQ.loggedIn = true
	QQ:Fire("QQ_LOGIN")
end)

QQ:On("PLAYER_LEVEL_UP", function(_, level)
	QQ.player.level = tonumber(level) or UnitLevel("player")
end)

---------------------------------------------------------------------------
-- Slash commands
---------------------------------------------------------------------------
SLASH_QUICKQUEST1 = "/qq"
SLASH_QUICKQUEST2 = "/quickquest"
SlashCmdList.QUICKQUEST = function(msg)
	msg = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
	if msg == "" or msg == "show" or msg == "hide" or msg == "toggle" then
		QQ:ToggleWindow(msg == "show" and true or msg == "hide" and false or nil)
	elseif msg == "options" or msg == "config" then
		if QQ.Options then QQ.Options:Open() end
	elseif msg == "lock" then
		QQ.db.general.locked = not QQ.db.general.locked
		QQ:Print(QQ.db.general.locked and "Frames locked." or "Frames unlocked.")
	elseif msg == "reset" then
		QQ:ResetPositions()
	elseif msg == "next" then
		QQ:SkipTask()
	elseif msg == "prev" or msg == "back" then
		QQ:UndoTask()
	elseif msg == "guides" or msg == "menu" then
		QQ:ShowGuideMenu("cursor")
	else
		QQ:Print("Commands:")
		QQ:Print("/qq - show / hide the guide window")
		QQ:Print("/qq guides - choose a guide")
		QQ:Print("/qq next, /qq prev - skip forward / go back one step")
		QQ:Print("/qq options - open the options")
		QQ:Print("/qq lock - lock / unlock frames, /qq reset - reset positions")
	end
end

function QQ:ResetPositions()
	self.db.window.point = { unpack(self.defaults.window.point) }
	self.db.arrow.point = { unpack(self.defaults.arrow.point) }
	self.db.buttons.itemPoint = { unpack(self.defaults.buttons.itemPoint) }
	self.db.buttons.targetPoint = { unpack(self.defaults.buttons.targetPoint) }
	self:Fire("QQ_POSITIONS_RESET")
	self:Print("Positions reset.")
end
