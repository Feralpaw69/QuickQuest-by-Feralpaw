-- QuickQuest
-- Item buttons (quest items of the active steps) and target buttons (+ a targeting macro)

local _, QQ = ...

local Buttons = {}
QQ.Buttons = Buttons
Buttons.BINDABLE = 4 -- buttons with a fixed key binding (always created)

-- names for Esc > Key Bindings (Bindings.xml)
BINDING_HEADER_QUICKQUEST = "QuickQuest"
for i = 1, Buttons.BINDABLE do
	_G["BINDING_NAME_CLICK QuickQuestItem" .. i .. ":LeftButton"] = "Use quest item " .. i
	_G["BINDING_NAME_CLICK QuickQuestTarget" .. i .. ":LeftButton"] = "Target " .. i
end

local ipairs, pairs, tinsert, wipe = ipairs, pairs, table.insert, wipe
local SIZE = 30
local MACRO_NAME = "QQ Target"

local itemBar, targetBar
local itemButtons, targetButtons = {}, {}
local pending

---------------------------------------------------------------------------
-- bars
---------------------------------------------------------------------------
local function CreateBar(name, point, label)
	local bar = CreateFrame("Frame", name, UIParent)
	bar:SetWidth(SIZE + 8)
	bar:SetHeight(SIZE + 8)
	bar:SetFrameStrata("MEDIUM")
	QQ:Skin(bar, true)
	QQ:LoadPosition(bar, point)
	QQ:MakeDraggable(bar, bar, point)
	bar.qqStore = point
	bar.title = QQ:Text(bar, "OVERLAY", -2, "LEFT")
	bar.title:SetPoint("BOTTOMLEFT", bar, "TOPLEFT", 4, 1)
	bar.title:SetText(label)
	QQ:Accent(bar.title, "text")
	bar:Hide()
	return bar
end

local function ButtonOnEnter(self)
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	if self.item then
		GameTooltip:SetHyperlink("item:" .. self.item)
	elseif self.unit then
		GameTooltip:SetText(self.unit)
		GameTooltip:AddLine("Click to target", 0.7, 0.7, 0.7)
	end
	local key = GetBindingKey("CLICK " .. self:GetName() .. ":LeftButton")
	if key then GameTooltip:AddLine("Key: " .. GetBindingText(key, "KEY_"), 0.7, 0.7, 0.7) end
	GameTooltip:AddLine("Shift + drag to move", 0.5, 0.5, 0.5)
	GameTooltip:Show()
end

local function CreateButton(bar, list, prefix, i)
	local b = CreateFrame("Button", prefix .. i, bar, "SecureActionButtonTemplate")
	b:SetWidth(SIZE)
	b:SetHeight(SIZE)
	b:RegisterForClicks("AnyUp")
	b:SetPoint("LEFT", bar, "LEFT", 4 + (i - 1) * (SIZE + 4), 0)
	b.icon = b:CreateTexture(nil, "ARTWORK")
	b.icon:SetPoint("TOPLEFT", 2, -2)
	b.icon:SetPoint("BOTTOMRIGHT", -2, 2)
	b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	b.border = CreateFrame("Frame", nil, b)
	b.border:SetAllPoints()
	QQ:Border(b.border, 0)
	b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
	b.count = QQ:Text(b, "OVERLAY", -1, "RIGHT")
	b.count:SetPoint("BOTTOMRIGHT", -2, 2)
	b.cooldown = CreateFrame("Cooldown", prefix .. i .. "Cooldown", b, "CooldownFrameTemplate")
	b.cooldown:SetAllPoints(b.icon)
	b.hotkey = QQ:Text(b, "OVERLAY", -2, "RIGHT", 0.75)
	b.hotkey:SetPoint("TOPRIGHT", -1, -2)
	b.hotkey:SetJustifyH("RIGHT")
	b.name = QQ:Text(b, "OVERLAY", -3, "CENTER")
	b.name:SetPoint("TOP", b, "BOTTOM", 0, -1)
	b.name:SetWidth(SIZE + 20)
	b.name:SetHeight(10)
	b:SetScript("OnEnter", ButtonOnEnter)
	b:SetScript("OnLeave", GameTooltip_Hide)
	-- Shift + drag moves the whole bar
	b:RegisterForDrag("LeftButton")
	b:SetScript("OnDragStart", function()
		if not IsShiftKeyDown() or QQ.db.general.locked or InCombatLockdown() then return end
		bar:StartMoving()
		bar.qqMoving = true
	end)
	b:SetScript("OnDragStop", function()
		if not bar.qqMoving then return end
		bar.qqMoving = nil
		bar:StopMovingOrSizing()
		QQ:SavePosition(bar, bar.qqStore)
	end)
	list[i] = b
	return b
end

---------------------------------------------------------------------------
-- what the active steps need
---------------------------------------------------------------------------
local function ActiveItems()
	local items, seen = {}, {}
	for _, step in ipairs(QQ.active) do
		for _, e in ipairs(step.elements) do
			if e.kind == "use" and e.item and not seen[e.item] and (GetItemCount(e.item) or 0) > 0 then
				seen[e.item] = true
				tinsert(items, e.item)
			end
		end
	end
	return items
end

local function ActiveUnits()
	local units, seen = {}, {}
	for _, step in ipairs(QQ.active) do
		for _, e in ipairs(step.elements) do
			if e.units and (e.state ~= QQ.ELEMENT_DONE) then
				local enemy = e.kind ~= "target"
				for _, u in ipairs(e.units) do
					if not seen[u.name] then
						seen[u.name] = true
						tinsert(units, { name = u.name, enemy = enemy, priority = u.priority })
					end
				end
			end
		end
	end
	table.sort(units, function(a, b)
		if a.priority ~= b.priority then return a.priority and true or false end
		if a.enemy ~= b.enemy then return not a.enemy end
		return false
	end)
	return units
end

---------------------------------------------------------------------------
-- nameplates (children of WorldFrame on 3.3.5) for "only nearby targets"
---------------------------------------------------------------------------
local plates, numChildren = {}, 0
local function IsNameplate(f)
	if f:GetName() then return false end
	local hasBar
	for _, c in ipairs({ f:GetChildren() }) do
		if c:GetObjectType() == "StatusBar" then hasBar = true break end
	end
	if not hasBar then return false end
	for _, r in ipairs({ f:GetRegions() }) do
		if r:GetObjectType() == "FontString" then return true end
	end
	return false
end

local visible = {}
local function VisibleNameplates()
	wipe(visible)
	local n = WorldFrame:GetNumChildren()
	if n ~= numChildren then
		numChildren = n
		for _, f in ipairs({ WorldFrame:GetChildren() }) do
			if plates[f] == nil then plates[f] = IsNameplate(f) end
		end
	end
	for f, isPlate in pairs(plates) do
		if isPlate and f:IsShown() then
			for _, r in ipairs({ f:GetRegions() }) do
				if r:GetObjectType() == "FontString" then
					local t = r:GetText()
					if t and t ~= "" and not t:match("^[%d%?%+]+$") then visible[t] = true break end
				end
			end
		end
	end
	return visible
end
Buttons.VisibleNameplates = VisibleNameplates

---------------------------------------------------------------------------
-- updating (only out of combat, secure buttons)
---------------------------------------------------------------------------
local function UpdateMacro(units)
	if not QQ.db.buttons.macro then return end
	local lines = {}
	for i, u in ipairs(units) do
		if i > 6 then break end
		tinsert(lines, "/targetexact " .. u.name)
	end
	local body = #lines > 0 and table.concat(lines, "\n") or "/run QuickQuest:Print(\"No target in this step\")"
	if #body > 250 then body = body:sub(1, 250):gsub("\n[^\n]*$", "") end
	local index = GetMacroIndexByName(MACRO_NAME)
	if index == 0 then
		local _, numChar = GetNumMacros()
		if numChar >= 18 then return end
		CreateMacro(MACRO_NAME, 1, body, 1)
	elseif GetMacroBody(index) ~= body then
		EditMacro(index, MACRO_NAME, 1, body)
	end
end

function Buttons:Update()
	if InCombatLockdown() then
		pending = true
		return
	end
	pending = false
	local db = QQ.db.buttons

	-- items
	local items = db.items and ActiveItems() or {}
	for i, item in ipairs(items) do
		local b = itemButtons[i] or CreateButton(itemBar, itemButtons, "QuickQuestItem", i)
		b.item = item
		b:SetAttribute("type", "item")
		b:SetAttribute("item", "item:" .. item)
		local name, _, _, _, _, _, _, _, _, texture = GetItemInfo(item)
		b.icon:SetTexture(texture or "Interface\\Icons\\INV_Misc_QuestionMark")
		local count = GetItemCount(item) or 0
		b.count:SetText(count > 1 and count or "")
		b.name:SetText("")
		b:Show()
	end
	for i = #items + 1, #itemButtons do itemButtons[i]:Hide() end
	itemBar:SetWidth(math.max(1, #items) * (SIZE + 4) + 4)
	if #items > 0 and not QQ.db.general.hidden then itemBar:Show() else itemBar:Hide() end

	-- targets
	local units = db.targets and ActiveUnits() or {}
	UpdateMacro(units)
	if db.nearbyOnly then
		local near = VisibleNameplates()
		local filtered = {}
		for _, u in ipairs(units) do
			if near[u.name] then tinsert(filtered, u) end
		end
		units = filtered
	end
	local n = math.min(#units, 6)
	for i = 1, n do
		local u = units[i]
		local b = targetButtons[i] or CreateButton(targetBar, targetButtons, "QuickQuestTarget", i)
		b.unit = u.name
		b:SetAttribute("type", "macro")
		b:SetAttribute("macrotext", "/targetexact " .. u.name)
		b.icon:SetTexture(u.enemy and "Interface\\Icons\\Ability_DualWield" or "Interface\\GossipFrame\\GossipGossipIcon")
		b.icon:SetTexCoord(u.enemy and 0.08 or 0, u.enemy and 0.92 or 1, u.enemy and 0.08 or 0, u.enemy and 0.92 or 1)
		b.name:SetText(u.name)
		b.count:SetText("")
		b:Show()
	end
	for i = n + 1, #targetButtons do targetButtons[i]:Hide() end
	targetBar:SetWidth(math.max(1, n) * (SIZE + 4) + 4)
	if n > 0 and not QQ.db.general.hidden then targetBar:Show() else targetBar:Hide() end
	self.lastUnits = n
end

local function ShortKey(key)
	key = GetBindingText(key, "KEY_", 1) or key
	return key:gsub("SHIFT%-", "S"):gsub("CTRL%-", "C"):gsub("ALT%-", "A"):gsub("Mouse Button ", "M"):gsub("Num Pad ", "N")
end

function Buttons:UpdateHotkeys()
	for _, list in ipairs({ itemButtons, targetButtons }) do
		for _, b in ipairs(list) do
			local key = GetBindingKey("CLICK " .. b:GetName() .. ":LeftButton")
			b.hotkey:SetText(key and ShortKey(key) or "")
		end
	end
end

local function UpdateCooldowns()
	for _, b in ipairs(itemButtons) do
		if b:IsShown() and b.item then
			local start, duration, enabled = GetItemCooldown(b.item)
			if start and duration and duration > 0 then
				b.cooldown:SetCooldown(start, duration)
			else
				b.cooldown:SetCooldown(0, 0)
			end
		end
	end
end

function Buttons:ApplySettings()
	if not itemBar then return end
	local s = QQ.db.buttons.scale or 1
	itemBar:SetScale(s)
	targetBar:SetScale(s)
	QQ:Skin(itemBar, true)
	QQ:Skin(targetBar, true)
	self:Update()
end

QQ:On("QQ_INIT", function()
	itemBar = CreateBar("QuickQuestItemBar", QQ.db.buttons.itemPoint, "Quest items")
	targetBar = CreateBar("QuickQuestTargetBar", QQ.db.buttons.targetPoint, "Targets")
	-- the bindable buttons always exist, so their key bindings work right away
	for i = 1, Buttons.BINDABLE do
		CreateButton(itemBar, itemButtons, "QuickQuestItem", i):Hide()
		CreateButton(targetBar, targetButtons, "QuickQuestTarget", i):Hide()
	end
	Buttons:UpdateHotkeys()
	Buttons:ApplySettings()
end)
QQ:On("QQ_STEPS_CHANGED", function() Buttons:Update() end)
QQ:On("BAG_UPDATE", function() QQ:Debounce("buttons", 0.5, function() Buttons:Update() end) end)
QQ:On("PLAYER_REGEN_ENABLED", function() if pending then Buttons:Update() end end)
QQ:On("SPELL_UPDATE_COOLDOWN", UpdateCooldowns)
QQ:On("BAG_UPDATE_COOLDOWN", UpdateCooldowns)
QQ:On("QQ_WINDOW_TOGGLED", function() Buttons:Update() end)
QQ:On("QQ_POSITIONS_RESET", function()
	if itemBar then
		QQ:LoadPosition(itemBar, QQ.db.buttons.itemPoint)
		QQ:LoadPosition(targetBar, QQ.db.buttons.targetPoint)
	end
end)
QQ:On("QQ_LOGIN", function()
	-- nearby filter follows the nameplates
	QQ:Every(0.5, function()
		if QQ.db.buttons.nearbyOnly and not InCombatLockdown() then
			local before = Buttons.lastUnits
			Buttons:Update()
		end
	end)
end)
QQ:On("UPDATE_BINDINGS", function() if itemBar then Buttons:UpdateHotkeys() end end)
QQ:On("QQ_BINDINGS_CHANGED", function() if itemBar then Buttons:UpdateHotkeys() end end)
