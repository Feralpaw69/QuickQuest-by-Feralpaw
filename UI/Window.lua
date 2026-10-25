-- QuickQuest
-- Guide window: current steps (with their tasks) and the next steps

local _, QQ = ...
local Quests = QQ.Quests

local Window = {}
QQ.Window = Window

local ipairs, tinsert = ipairs, table.insert
local fmt = string.format
local HEADER = 24 -- header row incl. the line below it
local PAD = 6 -- side padding, changes with the frame style
local TOP = 4 -- space above the header (frame style, banner)

local frame, body
local blocks = {}

local ICON_DONE = "|TInterface\\RaidFrame\\ReadyCheck-Ready:0|t"
local ICON_TODO = "|cffaaaaaa\226\128\162|r" -- bullet
local ICON_SKIP = "|TInterface\\RaidFrame\\ReadyCheck-NotReady:0|t"

---------------------------------------------------------------------------
-- element texts
---------------------------------------------------------------------------
-- asks the server for an item that is not in the cache yet (the window refreshes a moment later)
local scanTip
local function RequestItem(id)
	if not id then return end
	scanTip = scanTip or CreateFrame("GameTooltip", "QuickQuestScanTooltip", UIParent, "GameTooltipTemplate")
	scanTip:SetOwner(UIParent, "ANCHOR_NONE")
	scanTip:SetHyperlink("item:" .. id)
	scanTip:Hide()
	QQ:Debounce("itemcache", 1.5, function() Window:Refresh() end)
end

local function ItemName(id)
	local name = id and GetItemInfo(id)
	if not name then RequestItem(id) end
	return name or ("item " .. tostring(id))
end

local function QuestName(id)
	return Quests:Name(id) or ("quest " .. tostring(id))
end

local DEFAULT_TEXT = {
	accept = function(e) return "Accept " .. QuestName(e.questId) end,
	turnin = function(e) return "Turn in " .. QuestName(e.questId) end,
	complete = function(e)
		local text = e.objective and Quests:ObjectiveText(e.questId, e.objective)
		return text or ("Complete " .. QuestName(e.questId))
	end,
	abandon = function(e) return "Abandon " .. QuestName(e.questId) end,
	collect = function(e) return fmt("Collect |cff00bfff[%s]|r (%d/%d)", ItemName(e.item), math.min(GetItemCount(e.item) or 0, e.count), e.count) end,
	xp = function(e)
		if e.skip or e.op == "<" then return nil end
		return "Grind to level " .. e.level
	end,
	train = function(e) return "Train " .. (GetSpellInfo(e.spell) or "spell") end,
	cast = function(e) return "Cast " .. (GetSpellInfo(e.spell) or "spell") end,
	fp = function(e) return "Get the " .. (e.place or "") .. " flight path" end,
	fly = function(e) return "Fly to " .. (e.place or "") end,
	hs = function() return "Use your Hearthstone" end,
	home = function() return "Set your Hearthstone" end,
	vendor = function() return "Sell junk / restock" end,
	trainer = function() return "Train your spells" end,
	zone = function(e) return "Travel to " .. (e.zoneName or "") end,
	subzone = function(e) return "Travel to " .. (QQ.areaNames[e.area] or "") end,
	deathskip = function() return "Die and respawn at the Spirit Healer" end,
	manual = function(e) return e.text end,
}

local function ElementText(e)
	local text = e.text
	-- live progress for objectives
	if e.kind == "complete" and e.objective then
		local live = Quests:ObjectiveText(e.questId, e.objective)
		if live and text then
			text = text .. " |cffaaaaaa(" .. (live:match("(%d+/%d+)") or "") .. ")|r"
			text = text:gsub(" |cffaaaaaa%(%)|r", "")
		elseif live then
			text = live
		end
	elseif e.kind == "collect" and text then
		text = fmt("%s |cffaaaaaa(%d/%d)|r", text, math.min(GetItemCount(e.item) or 0, e.count), e.count)
	end
	if not text then
		local f = DEFAULT_TEXT[e.kind]
		text = f and f(e)
	end
	return text
end

local function LineFor(e)
	local text = ElementText(e)
	if not text or text == "" then return nil end
	local icon = ""
	local state = e.state
	if state == QQ.ELEMENT_DONE then
		icon = e.skipped and ICON_SKIP or ICON_DONE
		text = "|cff9a9a9a" .. text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "") .. "|r"
	elseif state == QQ.ELEMENT_TODO or e.kind == "manual" then
		icon = ICON_TODO
	end
	return (icon ~= "" and icon .. " " or "") .. text
end

---------------------------------------------------------------------------
-- step blocks
---------------------------------------------------------------------------
local function OnBlockClick(self, button)
	local step = self.step
	if not step then return end
	if button == "RightButton" then
		Window:ShowStepMenu(step)
	elseif IsShiftKeyDown() and self.upcoming then
		QQ:GoToStep(step.index)
	end
end

local function CreateBlock(i)
	local b = CreateFrame("Button", nil, body)
	b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	b:SetScript("OnClick", OnBlockClick)
	b.bar = b:CreateTexture(nil, "ARTWORK")
	b.bar:SetWidth(2)
	b.bar:SetPoint("TOPLEFT", b, "TOPLEFT", 0, -1)
	b.bar:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 0, 1)
	b.bar:SetTexture(1, 1, 1, 1)
	QQ:Accent(b.bar, "texture", 0.9)
	b.hl = b:CreateTexture(nil, "HIGHLIGHT")
	b.hl:SetAllPoints()
	b.hl:SetTexture(1, 1, 1, 0.05)
	b.number = QQ:Text(b, "OVERLAY", -1, "RIGHT")
	b.number:SetPoint("TOPLEFT", b, "TOPLEFT", 4, -2)
	b.number:SetWidth(22)
	b.check = CreateFrame("CheckButton", nil, b, "UICheckButtonTemplate")
	b.check:SetWidth(18)
	b.check:SetHeight(18)
	b.check:SetPoint("TOPRIGHT", b, "TOPRIGHT", 0, 1)
	b.check:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText("Mark this step as done")
		GameTooltip:Show()
	end)
	b.check:SetScript("OnLeave", GameTooltip_Hide)
	b.check:SetScript("OnClick", function(self)
		self:SetChecked(false)
		QQ:CompleteStep(b.step)
	end)
	b.text = QQ:Text(b, "OVERLAY", 0, "LEFT")
	b.text:SetJustifyV("TOP")
	b.text:SetPoint("TOPLEFT", b, "TOPLEFT", 30, -2)
	b.text:SetSpacing(2)
	blocks[i] = b
	return b
end

local function StepText(step)
	local lines = {}
	if step.title and type(step.title) == "string" then
		tinsert(lines, "|cffffd100" .. QQ.CleanText(step.title) .. "|r")
	end
	for _, e in ipairs(step.elements) do
		local line = LineFor(e)
		if line then tinsert(lines, line) end
	end
	if #lines == 0 then
		-- a step with only a waypoint
		for _, e in ipairs(step.elements) do
			if e.kind == "goto" and e.zone then
				tinsert(lines, ICON_TODO .. " Go to " .. (QQ:ZoneName(e.zone) or "") .. fmt(" (%.1f, %.1f)", e.x * 100, e.y * 100))
				break
			end
		end
	end
	return table.concat(lines, "\n")
end

---------------------------------------------------------------------------
-- own line wrapping, so the item names "[...]" can get mouse areas (tooltip / click)
---------------------------------------------------------------------------
local measure
local function Measure(text)
	measure:SetText(text)
	return measure:GetStringWidth()
end

local function Wrap(text, width)
	local out = {}
	for raw in (text .. "\n"):gmatch("(.-)\n") do
		local line = ""
		for word in raw:gmatch("%S+") do
			local candidate = line == "" and word or (line .. " " .. word)
			if line ~= "" and Measure(candidate) > width then
				tinsert(out, line)
				line = word
			else
				line = candidate
			end
		end
		tinsert(out, line)
	end
	-- colour codes continue on the next line
	local carry
	for i, line in ipairs(out) do
		if carry then line = carry .. line end
		carry = nil
		local last
		for code, p in line:gmatch("(|c%x%x%x%x%x%x%x%x)()") do last = { code, p } end
		if last and not line:find("|r", last[2], true) then
			carry = last[1]
			line = line .. "|r"
		end
		out[i] = line
	end
	return out
end

-- item ids a step knows (collect / use / equip ...), used to resolve the names in its text
local function StepItems(step)
	local ids = {}
	for _, e in ipairs(step.elements) do
		if e.item and not ids[e.item] then
			ids[e.item] = true
			tinsert(ids, e.item)
		end
	end
	return ids
end

local function ResolveItem(name, ids, used)
	local plain = name:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
	local id = tonumber(plain:match("^item (%d+)$"))
	if id then return id end
	for _, i in ipairs(ids) do
		if not used[i] and GetItemInfo(i) == plain then return i end
	end
	local link = select(2, GetItemInfo(plain))
	id = link and tonumber(link:match("item:(%d+)"))
	if id then return id end
	-- not cached yet: the next item of the step that has no name yet
	for _, i in ipairs(ids) do
		if not used[i] and not GetItemInfo(i) then return i end
	end
end

local function HotspotEnter(self)
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	GameTooltip:SetHyperlink("item:" .. self.item)
	GameTooltip:Show()
end

local function HotspotClick(self, button)
	if button == "RightButton" then
		local block = self:GetParent()
		block:GetScript("OnClick")(block, button)
		return
	end
	local name, link = GetItemInfo(self.item)
	link = link or ("|cffffffff|Hitem:" .. self.item .. "|h[" .. (name or "item " .. self.item) .. "]|h|r")
	if not HandleModifiedItemClick(link) then
		SetItemRef("item:" .. self.item, link, button)
	end
end

local function Hotspot(b, n)
	b.spots = b.spots or {}
	local h = b.spots[n]
	if not h then
		h = CreateFrame("Button", nil, b)
		h:RegisterForClicks("LeftButtonUp", "RightButtonUp")
		h:SetScript("OnEnter", HotspotEnter)
		h:SetScript("OnLeave", GameTooltip_Hide)
		h:SetScript("OnClick", HotspotClick)
		h:SetHighlightTexture("Interface\\Buttons\\WHITE8X8")
		h:GetHighlightTexture():SetVertexColor(1, 1, 1, 0.08)
		b.spots[n] = h
	end
	return h
end

local function SetBlockText(b, step, text, width)
	if not measure then
		measure = body:CreateFontString(nil, "BACKGROUND")
		measure:Hide()
	end
	measure:SetFont(b.text:GetFont())
	local lines = Wrap(text, width - 2)
	b.text:SetText(table.concat(lines, "\n"))
	-- mouse areas over "[item]" names
	measure:SetText("Ag")
	local lineH = measure:GetStringHeight()
	local spacing = 2
	local ids, used, n = StepItems(step), {}, 0
	local open -- link that continues on the next line: { id, name }
	for li, line in ipairs(lines) do
		local y = (li - 1) * (lineH + spacing)
		local pos = 1
		while true do
			local s, e, name
			if open then
				s = 1
				e = line:find("]", 1, true)
				name = nil
			else
				s = line:find("%[", pos)
				if not s then break end
				e = line:find("]", s, true)
			end
			local stop = e or #line
			-- include the item icon in front of the name
			local start = s
			if not open and line:sub(1, s - 1):find("|t$") then
				local iconStart
				for p in line:sub(1, s - 1):gmatch("()|T") do iconStart = p end
				start = iconStart or s
			end
			local x0 = start > 1 and Measure(line:sub(1, start - 1)) or 0
			local x1 = Measure(line:sub(1, stop))
			local id
			if open then
				id = open
			else
				id = ResolveItem(line:sub(s + 1, (e or #line + 1) - 1), ids, used)
				if id then used[id] = true end
			end
			if id and x1 > x0 then
				n = n + 1
				local h = Hotspot(b, n)
				h.item = id
				h:ClearAllPoints()
				h:SetPoint("TOPLEFT", b.text, "TOPLEFT", x0, -y)
				h:SetWidth(x1 - x0)
				h:SetHeight(lineH + 1)
				h:Show()
			end
			if e then
				open = nil
				pos = e + 1
			else
				open = id
				break
			end
			if open == nil and not line:find("%[", pos) then break end
		end
	end
	for j = n + 1, #(b.spots or {}) do b.spots[j]:Hide() end
end

local function LayoutBlock(b, step, y, kind)
	b.step = step
	b.upcoming = kind == "upcoming"
	b:ClearAllPoints()
	b:SetPoint("TOPLEFT", body, "TOPLEFT", 0, -y)
	b:SetPoint("RIGHT", body, "RIGHT", 0, 0)
	b.number:SetText(step.index)
	local width = QQ.db.window.width - 2 * PAD - 30 - (kind == "upcoming" and 2 or 20)
	b.text:SetWidth(width)
	SetBlockText(b, step, StepText(step), width)
	if kind ~= "upcoming" then b.check:Show() else b.check:Hide() end
	if kind == "main" then
		b.bar:Show()
		b:SetAlpha(1)
	elseif kind == "aux" then
		b.bar:Hide()
		b:SetAlpha(0.95)
	else
		b.bar:Hide()
		b:SetAlpha(0.5)
	end
	local h = math.max(18, b.text:GetHeight() + 6)
	b:SetHeight(h)
	b:Show()
	return h
end

function Window:Refresh()
	if not frame then return end
	local i, y = 0, 2
	local maxHeight = 600
	local active = QQ.active
	for n, step in ipairs(active) do
		if not step.hidewindow then
			i = i + 1
			local b = blocks[i] or CreateBlock(i)
			y = y + LayoutBlock(b, step, y, n == #active and "main" or "aux") + 2
		end
	end
	local upcoming = QQ:GetUpcomingSteps(QQ.db.window.upcoming or 0)
	if #upcoming > 0 and i > 0 then
		y = y + 2
	end
	for _, step in ipairs(upcoming) do
		if y > maxHeight then break end
		i = i + 1
		local b = blocks[i] or CreateBlock(i)
		y = y + LayoutBlock(b, step, y, "upcoming") + 2
	end
	for j = i + 1, #blocks do blocks[j]:Hide() end
	if i == 0 then
		frame.empty:SetText(QQ.noGuides and "|cffff5050Guide pack missing|r\nInstall QuickQuest_Guides" or "Right-click the title to choose a guide")
		frame.empty:Show()
		y = 40
	else
		frame.empty:Hide()
	end
	frame:SetHeight(TOP + HEADER - 4 + y + PAD)
	local guide = QQ.guide
	frame.guideName:SetText(guide and (guide.displayname or guide.name) or "No guide selected")
end

---------------------------------------------------------------------------
-- menus
---------------------------------------------------------------------------
local menuFrame = CreateFrame("Frame", "QuickQuestMenu", UIParent, "UIDropDownMenuTemplate")

local function SortedGroups()
	local groups = {}
	for group in pairs(QQ.groups) do tinsert(groups, group) end
	table.sort(groups, function(a, b) return QQ:GroupName(a) < QQ:GroupName(b) end)
	return groups
end

local function GuideSort(a, b)
	local la = QQ:GuideRange(a) or 0
	local lb = QQ:GuideRange(b) or 0
	if la ~= lb then return la < lb end
	return (a.name or "") < (b.name or "")
end

function QQ:ShowGuideMenu(anchor)
	local menu = { { text = QQ.title, isTitle = true, notCheckable = true } }
	local level = UnitLevel("player") or 1
	local function GuideList(group, farm)
		local list = {}
		for _, g in ipairs(QQ.groups[group]) do
			if not g.internal and (farm and g.farm or QQ:IsGuideShown(g)) then tinsert(list, g) end
		end
		table.sort(list, GuideSort)
		local sub, zones, zoneOrder = {}, {}, {}
		for _, g in ipairs(list) do
			local a, b = QQ:GuideRange(g)
			local name = g.displayname or g.name
			if a and b and level > b then name = "|cff888888" .. name .. "|r" end
			if QQ.guide == g then name = "|cff7fb2ff> |r" .. name end
			local entry = { text = name, notCheckable = true, func = function() QQ:LoadGuide(g) CloseDropDownMenus() end }
			-- farming guides: one submenu per zone ("#subgroup"), so lists stay short and names unique
			local zone = farm and type(g.subgroup) == "string" and g.subgroup or nil
			if zone then
				if not zones[zone] then
					zones[zone] = {}
					tinsert(zoneOrder, zone)
				end
				tinsert(zones[zone], entry)
			else
				tinsert(sub, entry)
			end
		end
		table.sort(zoneOrder)
		for i, zone in ipairs(zoneOrder) do
			tinsert(sub, i, { text = zone, hasArrow = true, notCheckable = true, menuList = zones[zone] })
		end
		return sub
	end
	-- level bands
	local bands = { {}, {}, {} }
	for _, list in pairs(QQ.groups) do
		for _, g in ipairs(list) do
			local band = QQ:IsGuideShown(g) and QQ:GuideBand(g)
			if band then tinsert(bands[band], g) end
		end
	end
	for i, list in ipairs(bands) do
		table.sort(list, GuideSort)
		local sub = {}
		for _, g in ipairs(list) do
			local a, b = QQ:GuideRange(g)
			local name = g.displayname or g.name
			if a and b and level > b then name = "|cff888888" .. name .. "|r" end
			if QQ.guide == g then name = "|cff7fb2ff> |r" .. name end
			tinsert(sub, { text = name, notCheckable = true, func = function() QQ:LoadGuide(g) CloseDropDownMenus() end })
		end
		if #sub > 0 then tinsert(menu, { text = QQ.BANDS[i], hasArrow = true, notCheckable = true, menuList = sub }) end
	end
	-- farming, dailies and professions
	local farming = {}
	for _, group in ipairs(SortedGroups()) do
		if group:sub(1, 1) == "+" then
			local sub = GuideList(group, true)
			if #sub > 0 then tinsert(farming, { text = QQ:GroupName(group), hasArrow = true, notCheckable = true, menuList = sub }) end
		end
	end
	if #farming > 0 then
		tinsert(menu, { text = "Farming, dailies & professions", hasArrow = true, notCheckable = true, menuList = farming })
	end
	tinsert(menu, { text = "", isTitle = true, notCheckable = true })
	if QQ.guide then
		tinsert(menu, { text = "Restart guide", notCheckable = true, func = function() QQ:LoadGuide(QQ.guide, true) end })
	end
	tinsert(menu, { text = "Options", notCheckable = true, func = function() QQ.Options:Open() end })
	tinsert(menu, { text = QQ.db.general.locked and "Unlock frames" or "Lock frames", notCheckable = true,
		func = function() QQ.db.general.locked = not QQ.db.general.locked end })
	tinsert(menu, { text = "Hide window", notCheckable = true, func = function() QQ:ToggleWindow(false) end })
	-- long lists stay on the screen
	for i = 1, (UIDROPDOWNMENU_MAXLEVELS or 2) do
		local list = _G["DropDownList" .. i]
		if list then list:SetClampedToScreen(true) end
	end
	EasyMenu(menu, menuFrame, anchor or "cursor", 0, 0, "MENU")
end

function Window:ShowStepMenu(step)
	local menu = {
		{ text = "Step " .. step.index, isTitle = true, notCheckable = true },
		{ text = "Go to this step", notCheckable = true, func = function() QQ:GoToStep(step.index) end },
		{ text = "Mark as done", notCheckable = true, func = function() QQ:CompleteStep(step) end },
		{ text = "Skip waypoint", notCheckable = true, func = function() QQ:SkipWaypoint() end },
	}
	EasyMenu(menu, menuFrame, "cursor", 0, 0, "MENU")
end

---------------------------------------------------------------------------
-- frame
---------------------------------------------------------------------------
local function HeaderButton(parent, text, tip, onClick)
	local b = CreateFrame("Button", nil, parent)
	b:SetWidth(18)
	b:SetHeight(18)
	b.label = QQ:Text(b, "OVERLAY", 1, "CENTER")
	b.label.qqFixedFont = true
	QQ:SetFont(b.label, 1)
	b.label:SetPoint("CENTER", 0, 1)
	b.label:SetText(text)
	QQ:Accent(b.label, "text")
	b:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
	b:SetScript("OnClick", onClick)
	b:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:SetText(tip)
		GameTooltip:Show()
	end)
	b:SetScript("OnLeave", GameTooltip_Hide)
	return b
end

local function Create()
	frame = CreateFrame("Frame", "QuickQuestFrame", UIParent)
	frame:SetFrameStrata("MEDIUM")
	frame:SetWidth(QQ.db.window.width)
	frame:SetHeight(80)
	frame:SetScale(QQ.db.general.scale or 1)
	QQ:Skin(frame)
	QQ:LoadPosition(frame, QQ.db.window.point)

	local header = CreateFrame("Button", nil, frame)
	header:SetHeight(HEADER - 4)
	header:RegisterForClicks("RightButtonUp")
	header:SetScript("OnClick", function() QQ:ShowGuideMenu("cursor") end)
	QQ:MakeDraggable(header, frame, QQ.db.window.point)
	frame.header = header

	frame.title = QQ:Text(header, "OVERLAY", 0, "LEFT")
	frame.title:SetPoint("LEFT", 4, 0)
	frame.title:SetText("Quick|cffffffffQuest|r")
	QQ:Accent(frame.title, "text")

	frame.guideName = QQ:Text(header, "OVERLAY", -1, "LEFT", 0.8)
	frame.guideName:SetPoint("RIGHT", header, "RIGHT", -62, 0)

	local menu = HeaderButton(header, "\226\137\161", "Guides and options (or right-click the title)", function() QQ:ShowGuideMenu("cursor") end)
	menu:SetPoint("RIGHT", header, "RIGHT", 0, 0)
	local nextB = HeaderButton(header, ">", "Skip the next task\n(the whole step when nothing is left)", function() QQ:SkipTask() end)
	nextB:SetPoint("RIGHT", menu, "LEFT", -2, 0)
	local prevB = HeaderButton(header, "<", "Undo the last skipped task\n(otherwise back to the previous step)", function() QQ:UndoTask() end)
	prevB:SetPoint("RIGHT", nextB, "LEFT", -2, 0)

	local line = frame:CreateTexture(nil, "ARTWORK")
	line:SetHeight(1)
	line:SetTexture(1, 1, 1, 1)
	frame.line = line
	QQ:Accent(line, "texture", 0.35)

	body = CreateFrame("Frame", nil, frame)

	-- title banner (optional ornament)
	local banner = CreateFrame("Frame", nil, frame)
	banner:SetWidth(220)
	banner:SetHeight(56)
	banner:SetPoint("TOP", frame, "TOP", 0, 14)
	banner.tex = banner:CreateTexture(nil, "ARTWORK")
	banner.tex:SetAllPoints()
	banner.tex:SetTexture("Interface\\DialogFrame\\UI-DialogBox-Header")
	banner.text = QQ:Text(banner, "OVERLAY", 0, "CENTER")
	banner.text:SetPoint("TOP", banner, "TOP", 0, -12)
	banner.text:SetText("Quick|cffffffffQuest|r")
	banner.text:SetTextColor(1, 0.82, 0)
	banner.text.qqBody = nil
	frame.banner = banner

	frame.empty = QQ:Text(body, "OVERLAY", 0, "CENTER", 0.8)
	frame.empty:SetPoint("TOPLEFT", 0, -8)
	frame.empty:SetPoint("TOPRIGHT", 0, -8)
	frame.empty:SetText("Right-click the title to choose a guide")
	Window:Layout()

	if QQ.db.general.hidden then frame:Hide() end
	Window.frame = frame
end

function QQ:ToggleWindow(show)
	if not frame then return end
	if show == nil then show = not frame:IsShown() end
	if show then frame:Show() else frame:Hide() end
	self.db.general.hidden = not show
	self:Fire("QQ_WINDOW_TOGGLED", show)
end

-- positions of header and body (they depend on the frame style and the banner)
function Window:Layout()
	if not frame then return end
	local pad = QQ:FramePad(true)
	local banner = QQ.db.general.banner
	PAD = math.max(6, pad + 2)
	TOP = math.max(4, pad) + (banner and 12 or 0)
	local header = frame.header
	header:ClearAllPoints()
	header:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD - 2, -TOP)
	header:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -(PAD - 2), -TOP)
	frame.line:ClearAllPoints()
	frame.line:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -(TOP + HEADER - 4))
	frame.line:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -PAD, -(TOP + HEADER - 4))
	body:ClearAllPoints()
	body:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -(TOP + HEADER - 2))
	body:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -PAD, PAD)
	frame.guideName:ClearAllPoints()
	frame.guideName:SetPoint("RIGHT", header, "RIGHT", -62, 0)
	if banner then
		frame.banner:Show()
		frame.title:Hide()
		frame.guideName:SetPoint("LEFT", header, "LEFT", 4, 0)
	else
		frame.banner:Hide()
		frame.title:Show()
		frame.guideName:SetPoint("LEFT", frame.title, "RIGHT", 8, 0)
	end
	frame.banner:SetFrameLevel(frame:GetFrameLevel() + 8)
end

function Window:ApplySettings()
	if not frame then return end
	frame:SetWidth(QQ.db.window.width)
	frame:SetScale(QQ.db.general.scale or 1)
	QQ:Skin(frame)
	QQ:ApplyFonts()
	self:Layout()
	self:Refresh()
end

QQ:On("QQ_INIT", Create)
QQ:On("QQ_STEPS_CHANGED", function() Window:Refresh() end)
QQ:On("QQ_GUIDE_LOADED", function() Window:Refresh() end)
QQ:On("QQ_POSITIONS_RESET", function() if frame then QQ:LoadPosition(frame, QQ.db.window.point) end end)
QQ:On("QQ_QUESTLOG_CHANGED", function() QQ:Debounce("windowtext", 0.3, function() Window:Refresh() end) end)
QQ:On("BAG_UPDATE", function() QQ:Debounce("windowtext", 0.3, function() Window:Refresh() end) end)
QQ:On("QQ_LOGIN", function() Window:Refresh() end)
