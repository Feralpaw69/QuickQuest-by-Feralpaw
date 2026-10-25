-- QuickQuest
-- Experience rates (server rate, buffs), skipping quests that are too low, suggesting a guide that fits the level

local _, QQ = ...
local Quests = QQ.Quests

local Leveling = {}
QQ.Leveling = Leveling

local tonumber, ipairs, pairs = tonumber, ipairs, pairs
local fmt = string.format

Leveling.NUM_BUFFS = 4

---------------------------------------------------------------------------
-- experience rate
---------------------------------------------------------------------------
-- aura: spell id or (part of) the buff name; empty = always counts
local function HasAura(aura)
	if not aura or aura == "" then return true end
	local id = tonumber(aura)
	local wanted = not id and aura:lower()
	for i = 1, 40 do
		local name, _, _, _, _, _, _, _, _, _, spellId = UnitAura("player", i, "HELPFUL")
		if not name then break end
		if id and spellId == id then return true end
		if wanted and name:lower():find(wanted, 1, true) then return true end
	end
	return false
end
Leveling.HasAura = HasAura

local function HeirloomBonus()
	local bonus = 0
	for _, slot in ipairs({ 3, 5 }) do -- shoulders and chest give 10% each on 3.3.5
		local link = GetInventoryItemLink("player", slot)
		if link and select(3, GetItemInfo(link)) == 7 then bonus = bonus + 0.1 end
	end
	return bonus
end

-- base server rate x heirlooms x every enabled buff (5x with +20% and +50% = 9x)
function QQ:GetXPRate()
	local x = self.db and self.db.xp
	if not x then return 1 end
	if not x.auto then return tonumber(x.manualRate) or 1 end
	local rate = (tonumber(x.serverRate) or 1) * (1 + HeirloomBonus())
	for i = 1, Leveling.NUM_BUFFS do
		local b = x.buffs[i]
		if b and b.enabled and (tonumber(b.percent) or 0) ~= 0 and HasAura(b.aura) then
			rate = rate * (1 + b.percent / 100)
		end
	end
	return rate
end

function QQ:IsGoldMode()
	return self.db and self.db.xp.goldMode and true or false
end

-- "#xprate <1.5", "#xprate >1.49", "#xprate 1.2-1.5"
-- (Quest for gold mode: always the full 1x route, the one with every quest)
function QQ:XPRateMatches(spec)
	local rate = self:IsGoldMode() and 1 or self:GetXPRate()
	local op, a, b = tostring(spec):match("^%s*([<>]?)%s*([%d%.]+)%-?([%d%.]*)")
	a, b = tonumber(a), tonumber(b)
	if not a then return true end
	if op == "<" then return rate < a end
	if op == ">" then return rate > a end
	return rate >= a and rate <= (b or 1e9)
end

local lastRate
function Leveling:CheckRate()
	local rate = QQ:GetXPRate()
	if lastRate and math.abs(rate - lastRate) > 0.001 then
		QQ:Printf("Experience rate is now %.2fx.", rate)
		QQ:Fire("QQ_XPRATE_CHANGED", rate)
		QQ:RequestUpdate()
	end
	lastRate = rate
end
QQ:On("UNIT_AURA", function(_, unit)
	if unit == "player" then QQ:Debounce("xprate", 1, function() Leveling:CheckRate() end) end
end)
QQ:On("PLAYER_EQUIPMENT_CHANGED", function() QQ:Debounce("xprate", 1, function() Leveling:CheckRate() end) end)
QQ:On("QQ_LOGIN", function() lastRate = QQ:GetXPRate() end)

---------------------------------------------------------------------------
-- quests that are too low
---------------------------------------------------------------------------
local data = QQ.questData or {}

local function QuestLevel(id)
	local d = data[id]
	local level = d and d[2]
	if level and level > 0 then return level end
	return Quests:Level(id)
end

-- too low: far below the player and nothing that still gives experience depends on it
local lowCache, lowLevel, lowDiff = {}, nil, nil
local function TooLow(id, level, diff)
	local v = lowCache[id]
	if v ~= nil then return v end
	lowCache[id] = false -- cycle guard
	local ql = QuestLevel(id)
	v = ql and level - ql >= diff or false
	local d = data[id]
	if v and d and d[4] then
		for _, follow in ipairs(d[4]) do
			if not TooLow(follow, level, diff) then v = false break end
		end
	end
	lowCache[id] = v
	return v
end

function Leveling:IsQuestTooLow(id)
	local x = QQ.db.xp
	if not x.skipLowQuests or x.goldMode or not id then return false end
	local level = UnitLevel("player") or 1
	local diff = tonumber(x.lowQuestDiff) or 6
	if lowLevel ~= level or lowDiff ~= diff then lowCache, lowLevel, lowDiff = {}, level, diff end
	return TooLow(id, level, diff)
end

-- the pre quest was (or will be) skipped, so this one can never be picked up
local function Blocked(id, depth)
	if depth > 20 or Quests:IsOnQuest(id) or Quests:IsTurnedIn(id) then return false end
	local d = data[id]
	if not d then return false end
	local function unusable(pre)
		pre = pre < 0 and -pre or pre
		if Quests:IsTurnedIn(pre) or Quests:IsOnQuest(pre) then return false end
		return Leveling:IsQuestTooLow(pre) or Blocked(pre, depth + 1)
	end
	if d[5] then
		for _, pre in ipairs(d[5]) do
			if unusable(pre) then return true end
		end
	end
	if d[6] and #d[6] > 0 then
		for _, pre in ipairs(d[6]) do
			if not unusable(pre) then return false end
		end
		return true
	end
	return false
end

function Leveling:IsQuestBlocked(id)
	if not QQ.db.xp.skipLowQuests or QQ.db.xp.goldMode or not id then return false end
	return Blocked(id, 0)
end

local QUEST_KINDS = { accept = true, turnin = true, complete = true }
local PASSIVE = {
	["goto"] = true, groundgoto = true, waypoint = true, target = true, mob = true, unitscan = true, text = true,
	link = true, timer = true, isOnQuest = true, isQuestComplete = true, isQuestAvailable = true, isQuestTurnedIn = true,
	zoneskip = true, subzoneskip = true, itemcount = true, money = true, maxlevel = true, xp = true,
}

-- items that only matter for the quests of the step
local QUEST_ITEMS = { collect = true, use = true }

function Leveling:IsLowQuestStep(step)
	if not QQ.db.xp.skipLowQuests or QQ.db.xp.goldMode or not step.elements then return false end
	local found = false
	for _, e in ipairs(step.elements) do
		if QUEST_ITEMS[e.kind] and not (e.questId and not self:IsQuestTooLow(e.questId) and not self:IsQuestBlocked(e.questId)) then
			-- decided by the quests of the step
		else
		local k = e.kind
		if QUEST_KINDS[k] and e.questId then
			local id = e.questId
			if self:IsQuestTooLow(id) then
				-- a finished quest in the log is still worth turning in (rewards)
				if k == "turnin" and Quests:IsComplete(id) then return false end
			elseif not self:IsQuestBlocked(id) then
				return false
			end
			found = true
		elseif k == "xp" and not e.skip then
			return false
		elseif not PASSIVE[k] then
			return false
		end
		end
	end
	return found
end

---------------------------------------------------------------------------
-- outleveled guides
---------------------------------------------------------------------------
function QQ:GuideRange(guide)
	local name = guide and guide.name
	if type(name) ~= "string" then return nil end
	local a, b = name:match("^%s*0?(%d+)%-0?(%d+)")
	a, b = tonumber(a), tonumber(b)
	if not a or not b or b < a then return nil end
	return a, b
end

---------------------------------------------------------------------------
-- level bands for the guide menu: 1 = 1-58 Classic, 2 = 58-68 Burning Crusade, 3 = 68-80 Wrath
-- (the guide sets overlap, only one guide per zone is shown)
---------------------------------------------------------------------------
QQ.BANDS = { "1-58 Classic", "58-68 The Burning Crusade", "68-80 Wrath of the Lich King" }

local OUTLAND = { "hellfire", "zangarmarsh", "terokkar", "nagrand", "blade's edge", "netherstorm", "shadowmoon", "shattrath", "dungeon cleave" }
local NORTHREND = { "howling fjord", "borean", "dragonblight", "grizzly", "zul'drak", "sholazar", "storm peaks", "icecrown", "crystalsong", "wintergrasp", "mage aoe" }

local function NameHas(name, list)
	name = name:lower()
	for _, k in ipairs(list) do
		if name:find(k, 1, true) then return true end
	end
	return false
end

local function IsClassicRoute(guide)
	return guide.group:match("TBC Guide") ~= nil
end

-- highest level the newer (1-30) guides of the player's faction reach
local newRouteTop
local function NewRouteTop()
	if newRouteTop then return newRouteTop end
	newRouteTop = 0
	for group, list in pairs(QQ.groups) do
		if not group:match("TBC Guide") and not group:match("Cataclysm") and group:sub(1, 1) ~= "+" then
			for _, g in ipairs(list) do
				local a, b = QQ:GuideRange(g)
				if b and b <= 40 and not g.internal then newRouteTop = math.max(newRouteTop, b) end
			end
		end
	end
	return newRouteTop
end

-- band of a guide, nil when it is hidden (duplicate of a zone of another guide set)
function QQ:GuideBand(guide)
	if guide.qqBand ~= nil then return guide.qqBand or nil end
	local band
	local name = guide.name or ""
	local a, b = self:GuideRange(guide)
	if NameHas(name, NORTHREND) then
		band = 3
	elseif NameHas(name, OUTLAND) then
		band = 2
		if IsClassicRoute(guide) and not name:lower():find("dungeon cleave", 1, true) then band = false end
	else
		band = 1
		if IsClassicRoute(guide) and a and a < NewRouteTop() then band = false end
	end
	guide.qqBand = band
	return band or nil
end

function QQ:IsGuideShown(guide)
	if guide.internal or guide.farm then return false end
	if guide.xprate and not self:XPRateMatches(guide.xprate) then return false end
	if not self:GuideBand(guide) then return false end
	return true
end

-- next guide when a guide has no (usable) "#next": the shown guide that starts where this one ends
function QQ:FollowingGuide(current)
	local _, b = self:GuideRange(current)
	if not b then return nil end
	local best, bestA, bestScore
	for _, list in pairs(self.groups) do
		for _, g in ipairs(list) do
			local ga = self:GuideRange(g)
			if ga and g ~= current and ga >= b - 1 and self:IsGuideShown(g) and not g.name:find("Optional", 1, true) then
				local score = (g.group == current.group) and 1 or 0
				if not best or ga < bestA or (ga == bestA and score > bestScore) then
					best, bestA, bestScore = g, ga, score
				end
			end
		end
	end
	return best
end

function QQ:FindGuideForLevel(level, current)
	local best, bestScore
	for group, list in pairs(self.groups) do
		for _, guide in ipairs(list) do
			local a, b = self:GuideRange(guide)
			if a and a <= level and level < b and guide ~= current and self:IsGuideShown(guide) then
				local score = a * 100
				if current and group == current.group then score = score + 50 end
				if not best or score > bestScore then best, bestScore = guide, score end
			end
		end
	end
	return best
end

StaticPopupDialogs["QUICKQUEST_NEXT_GUIDE"] = {
	text = "%s",
	button1 = ACCEPT or "Accept",
	button2 = CANCEL or "Cancel",
	OnAccept = function() if Leveling.suggested then QQ:LoadGuide(Leveling.suggested) end end,
	timeout = 0, whileDead = 1, hideOnEscape = 1,
}

local announced = {}
function Leveling:CheckOutleveled()
	if not QQ.db.xp.suggestNextGuide or QQ.db.xp.goldMode or InCombatLockdown() then return end
	local guide = QQ.guide
	if not guide or guide.farm then return end
	local a, b = QQ:GuideRange(guide)
	local level = UnitLevel("player") or 1
	if not b or level <= b then return end
	local key = guide.key .. "|" .. level
	if announced[key] then return end
	announced[key] = true
	local nextGuide = QQ:FindGuideForLevel(level, guide)
	if nextGuide then
		self.suggested = nextGuide
		StaticPopup_Show("QUICKQUEST_NEXT_GUIDE", fmt(
			"%s\n\nYou are level %d, this guide is meant for levels %d-%d.\n\nSwitch to:\n|cffffd100%s|r\n(%s)",
			QQ.title, level, a, b, nextGuide.displayname or nextGuide.name, QQ:GroupName(nextGuide.group)))
	else
		QQ:Printf("You are level %d, the current guide is meant for levels %d-%d.", level, a, b)
	end
end

QQ:On("PLAYER_LEVEL_UP", function() QQ:After(2, function() Leveling:CheckOutleveled() end) end)
QQ:On("QQ_GUIDE_LOADED", function() QQ:After(3, function() Leveling:CheckOutleveled() end) end)
