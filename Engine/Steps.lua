-- QuickQuest
-- Step engine: element states, active steps, progress through the guide

local _, QQ = ...
local Quests = QQ.Quests

local tinsert, wipe, pairs, ipairs = table.insert, wipe, pairs, ipairs
local GetTime = GetTime

local TODO, DONE, INFO, SKIP = 1, 2, 3, 4
QQ.ELEMENT_TODO, QQ.ELEMENT_DONE, QQ.ELEMENT_INFO, QQ.ELEMENT_SKIP = TODO, DONE, INFO, SKIP

QQ.guide = nil
QQ.active = {} -- steps shown as "current" (main step last)
local events = {} -- one shot happenings for the active steps (casts, merchant opened ...)

---------------------------------------------------------------------------
-- helpers
---------------------------------------------------------------------------
local function Norm(s)
	return s and s:lower():gsub("[^%w]", "") or ""
end

local function XPReached(level, e)
	local pl = UnitLevel("player") or 1
	if pl > level then return true end
	local cur, max = UnitXP("player") or 0, UnitXPMax("player") or 1
	if pl == level then
		if e.xpAbove then return cur >= e.xpAbove end
		if e.fraction and e.fraction > 0 then return cur >= max * e.fraction end
		return true
	end
	if pl == level - 1 and e.xpBelow then
		return cur >= max - e.xpBelow
	end
	return false
end

local skillAliases = { firstaid = "firstaid", ["first aid"] = "firstaid" }
local function SkillRank(name)
	local want = Norm(name)
	for i = 1, GetNumSkillLines() do
		local skillName, isHeader, _, rank = GetSkillLineInfo(i)
		if not isHeader and skillName and Norm(skillName) == want then return rank or 0 end
	end
	return 0
end

local function HasAura(spellId)
	local name = GetSpellInfo(spellId)
	if not name then return false end
	return UnitAura("player", name) ~= nil
end

local function SpellKnown(spellId)
	if IsSpellKnown then
		local ok, known = pcall(IsSpellKnown, spellId)
		if ok and known then return true end
		ok, known = pcall(IsSpellKnown, spellId, true)
		if ok and known then return true end
	end
	local name, rank = GetSpellInfo(spellId)
	if not name then return false end
	local i = 1
	while true do
		local n, r = GetSpellName(i, BOOKTYPE_SPELL)
		if not n then break end
		if n == name and (not rank or rank == "" or r == rank) then return true end
		i = i + 1
	end
	return false
end

local function Compare(value, op, target)
	if op == "<" then return value < target end
	if op == ">" then return value > target end
	return value >= target
end

local function InSubZone(area)
	local name = QQ.areaNames and QQ.areaNames[area]
	if not name then return false end
	return GetSubZoneText() == name or GetMinimapZoneText() == name or GetRealZoneText() == name
end

local function InZone(name)
	if not name then return false end
	local real = GetRealZoneText()
	if Norm(real) == Norm(name) then return true end
	local id = QQ:ResolveZone(name)
	return id and QQ:ResolveZone(real) == id
end

---------------------------------------------------------------------------
-- element evaluation
---------------------------------------------------------------------------
local eval = {}
QQ.elementEval = eval

eval.accept = function(e)
	local id = e.questId
	if Quests:IsOnQuest(id) or Quests:IsTurnedIn(id) then return DONE end
	return TODO
end

eval.turnin = function(e)
	local id = e.questId
	if Quests:IsTurnedIn(id) then return DONE end
	if not Quests:IsOnQuest(id) then return DONE, true end -- nothing to turn in (skipped)
	return TODO
end

eval.complete = function(e)
	local id = e.questId
	if Quests:IsTurnedIn(id) then return DONE end
	if not Quests:IsOnQuest(id) then return DONE, true end
	if e.objective then
		if Quests:IsObjectiveDone(id, e.objective) then return DONE end
	elseif Quests:IsComplete(id) then
		return DONE
	end
	return TODO
end

eval.abandon = function(e)
	return Quests:IsOnQuest(e.questId) and TODO or DONE
end

eval.collect = function(e)
	if e.questId and not Quests:IsOnQuest(e.questId) and Quests:IsTurnedIn(e.questId) then return DONE end
	if (GetItemCount(e.item) or 0) >= e.count then return DONE end
	return TODO
end

eval["goto"] = function(e, step)
	-- in steps that only travel somewhere the waypoints are the task
	if step.waypointOnly and not e.passive then return e.reached and DONE or TODO end
	return INFO
end
eval.groundgoto = eval["goto"]
eval.waypoint = function() return INFO end

eval.xp = function(e)
	local reached = XPReached(e.level, e)
	if e.skip then
		if QQ.db and not QQ.db.xp.skipXpSteps and e.op ~= "<" then return INFO end
		if reached == (e.op ~= "<") then return SKIP end
		return INFO
	end
	if e.op == "<" then return reached and SKIP or INFO end
	return reached and DONE or TODO
end

eval.train = function(e) return SpellKnown(e.spell) and DONE or TODO end
eval.cast = function(e) return events.cast and events.cast[e.spell] and DONE or TODO end
eval.usespell = eval.cast
eval.aura = function(e) return HasAura(e.spell) and DONE or TODO end
eval.fp = function(e)
	if e.place and QQ.char.flightPaths and QQ.char.flightPaths[Norm(e.place)] then return DONE end
	return events.fp and DONE or TODO
end
eval.fly = function() return (events.fly or UnitOnTaxi("player")) and DONE or TODO end
eval.hs = function() return events.hs and DONE or TODO end
eval.home = function() return events.home and DONE or TODO end
eval.vendor = function() return events.vendor and DONE or TODO end
-- all class spells of this level learned? (saved when a class trainer had nothing left to learn;
-- new spells only come at even levels)
local function AllSpellsTrained()
	local t = QQ.char.trainedLevel
	if not t then return false end
	local level = UnitLevel("player")
	return t >= level or (level % 2 == 1 and t >= level - 1)
end
QQ.AllSpellsTrained = AllSpellsTrained

eval.trainer = function() return (events.trainer or AllSpellsTrained()) and DONE or TODO end
eval.deathskip = function() return (events.dead or UnitIsDeadOrGhost("player")) and DONE or TODO end
eval.vehicle = function() return (UnitInVehicle and UnitInVehicle("player")) and DONE or TODO end
eval.zone = function(e) return InZone(e.zoneName) and DONE or TODO end
eval.subzone = function(e)
	if e.kind == "subzoneskip" then
		if InSubZone(e.area) == not e.reverse then return SKIP end
		return INFO
	end
	return InSubZone(e.area) and DONE or TODO
end
eval.subzoneskip = eval.subzone
eval.zoneskip = function(e)
	if InZone(e.zoneName) == not e.reverse then return SKIP end
	return INFO
end
eval.bindlocation = function(e)
	local name = QQ.areaNames and QQ.areaNames[e.area]
	if name and (GetBindLocation() == name) == not e.skip then return SKIP end
	return INFO
end

local function QuestCondition(check)
	return function(e)
		for _, id in ipairs(e.quests) do
			if check(id) then return INFO end
		end
		return SKIP
	end
end
eval.isOnQuest = QuestCondition(function(id) return Quests:IsOnQuest(id) end)
eval.isQuestComplete = QuestCondition(function(id) return Quests:IsComplete(id) end)
eval.isQuestTurnedIn = QuestCondition(function(id) return Quests:IsTurnedIn(id) end)
eval.isQuestNotTurnedIn = QuestCondition(function(id) return not Quests:IsTurnedIn(id) end)
eval.isQuestAvailable = QuestCondition(function(id) return Quests:IsAvailable(id) end)

eval.itemcount = function(e)
	local count = GetItemCount(e.item) or 0
	if Compare(count, e.op, e.count) then return INFO end
	return SKIP
end
eval.money = function(e)
	local gold = (GetMoney() or 0) / 10000
	if Compare(gold, e.op, e.gold) then return INFO end
	return SKIP
end
eval.skill = function(e)
	local reached = SkillRank(e.skill) >= e.value
	if e.skip then
		if reached == (e.op ~= "<") then return SKIP end
		return INFO
	end
	if e.op == "<" then return reached and SKIP or INFO end
	return reached and DONE or TODO
end
eval.cooldown = function(e)
	if e.cdType ~= "item" then return INFO end
	local start, duration = GetItemCooldown(e.item)
	local remaining = (start and start > 0) and (start + duration - GetTime()) or 0
	local cond
	if e.op == "<" then cond = remaining < (e.seconds or 0) else cond = remaining > (e.seconds or 0) end
	if cond and e.skip then return SKIP end
	return INFO
end
eval.maxlevel = function(e)
	if (UnitLevel("player") or 1) > e.level then return SKIP end
	return INFO
end
eval.dungeon = function()
	if QQ.db and QQ.db.dungeons then return INFO end
	return SKIP
end
eval.requires = function(e)
	local done = Quests:IsTurnedIn(e.requireQuest)
	if done == e.negate then return SKIP end
	return INFO
end
eval.reputation = function() return INFO end

---------------------------------------------------------------------------
-- step level filters
---------------------------------------------------------------------------
local function StepFilteredOut(step, guide)
	if step.hardcore or step.tip or step.ah or step.ssf then return true end
	if step.dungeon and not (QQ.db and QQ.db.dungeons) then return true end
	if step.xprate and not QQ:XPRateMatches(step.xprate) then return true end
	local shatt = QQ.db and QQ.db.shattrath or "aldor"
	if step.aldor and shatt ~= "aldor" then return true end
	if step.scryer and shatt ~= "scryer" then return true end
	if step.flyable and not QQ:CanFly() then return true end
	if step.noflyable and QQ:CanFly() then return true end
	if step.requires and type(step.requires) == "string" then
		local index = guide.labels[step.requires]
		local state = index and QQ:GetStepState(guide, index)
		if index and state ~= "done" then return true end
	end
	return false
end

function QQ:CanFly()
	local riding = SkillRank("riding")
	if riding < 225 then return false end
	local _, _, instance = self:GetPlayerPosition()
	if instance == 530 then return true end
	if instance == 571 then return SpellKnown(54197) end
	return false
end

-- tasks (elements) the player skipped himself: char.skips[guide][step][element] = true
local function SkipTable(guide, index, create)
	if not guide then return nil end
	QQ.char.skips = QQ.char.skips or {}
	local g = QQ.char.skips[guide.key]
	if not g then
		if not create then return nil end
		g = {}
		QQ.char.skips[guide.key] = g
	end
	local t = g[index]
	if not t and create then
		t = {}
		g[index] = t
	end
	return t
end

local function ClearSkips(guide, fromIndex)
	local g = QQ.char.skips and QQ.char.skips[guide.key]
	if not g then return end
	for index in pairs(g) do
		if index >= fromIndex then g[index] = nil end
	end
end

-- evaluates one step: returns "skip", "done" or "todo", plus its waypoint step flag
function QQ:EvaluateStep(step)
	local guide = step.guide and QQ.guide
	if StepFilteredOut(step, QQ.guide) then return "skip" end
	if self.Leveling and self.Leveling:IsLowQuestStep(step) then return "skip" end
	local required, done = 0, 0
	local hasRequired = false
	-- steps without quest/other actions complete on arrival at their waypoint
	local waypointOnly = true
	for _, e in ipairs(step.elements) do
		local k = e.kind
		if k ~= "goto" and k ~= "groundgoto" and k ~= "waypoint" and k ~= "text" and k ~= "target" and
			k ~= "mob" and k ~= "unitscan" and k ~= "use" and k ~= "link" and k ~= "timer" and k ~= "equip" and k ~= "destroy" then
			waypointOnly = false
			break
		end
	end
	step.waypointOnly = waypointOnly
	local userSkips = SkipTable(QQ.guide, step.index)
	for i, e in ipairs(step.elements) do
		local f = eval[e.kind]
		local state, skipped = INFO, nil
		if f then state, skipped = f(e, step) end
		if userSkips and userSkips[i] and state == TODO then state, skipped = DONE, true end
		e.state = state
		e.skipped = skipped
		if state == SKIP then return "skip" end
		if state == TODO or state == DONE then
			required = required + 1
			if state == DONE then done = done + 1 end
		end
		if e.kind == "manual" then
			required = required + 1
			if step.manualDone then done = done + 1 end
		end
	end
	if required == 0 then
		return step.manualDone and "done" or "manual"
	end
	if done >= required then return "done" end
	return "todo"
end

---------------------------------------------------------------------------
-- saved progress
---------------------------------------------------------------------------
local function GuideState(guide)
	local s = QQ.char.state[guide.key]
	if not s then
		s = {}
		QQ.char.state[guide.key] = s
	end
	return s
end

function QQ:GetStepState(guide, index)
	return GuideState(guide)[index]
end

local function SetStepState(guide, index, state)
	GuideState(guide)[index] = state
end

local function CurrentIndex(guide)
	return QQ.char.steps[guide.key] or 1
end

local function SetCurrentIndex(guide, index)
	QQ.char.steps[guide.key] = index
end

---------------------------------------------------------------------------
-- active steps
---------------------------------------------------------------------------
local function IsAux(step)
	return step.completewith ~= nil
end

local function AuxEndIndex(guide, step)
	local cw = step.completewith
	if cw == "next" or cw == true then return step.index + 1 end
	return guide.labels[cw] or (step.index + 1)
end

local lastSignature

local function Signature()
	local t = {}
	for _, step in ipairs(QQ.active) do
		t[#t + 1] = step.index
		for _, e in ipairs(step.elements) do t[#t + 1] = e.state or 0 end
		t[#t + 1] = step.qqStatus or ""
	end
	return table.concat(t, ",")
end

-- walks forward from the saved position, skipping and completing steps
local function Advance(guide)
	local steps = guide.steps
	local index = CurrentIndex(guide)
	local guard = 0
	wipe(QQ.active)
	while index <= #steps and guard < 400 do
		guard = guard + 1
		local step = steps[index]
		local state = GuideState(guide)[index]
		local status
		if index == QQ.holdIndex then
			-- a step the player went back to stays until he moves on himself
			status = QQ:EvaluateStep(step)
			if status ~= "skip" then status = "held" end
		elseif state == "done" or state == "skip" then
			status = state
		else
			status = QQ:EvaluateStep(step)
		end
		step.qqStatus = status
		if status == "held" then
			tinsert(QQ.active, step)
			break
		elseif status == "skip" or status == "done" then
			SetStepState(guide, index, status)
			if status == "done" then wipe(events) end
			-- helper steps ("#completewith") end with the step they belong to
			for j = #QQ.active, 1, -1 do
				local aux = QQ.active[j]
				if AuxEndIndex(guide, aux) <= index then
					SetStepState(guide, aux.index, "done")
					table.remove(QQ.active, j)
				end
			end
			index = index + 1
			SetCurrentIndex(guide, index)
		elseif IsAux(step) then
			-- shown together with the following steps
			tinsert(QQ.active, step)
			index = index + 1
		else
			tinsert(QQ.active, step)
			break
		end
	end
	-- auxiliary steps go to the saved position only when the main step is done
	local first = QQ.active[1]
	if first then SetCurrentIndex(guide, first.index) end

	-- earlier steps that stay visible: "#completewith <label>" and "#sticky"
	local main = QQ.active[#QQ.active]
	local mainIndex = main and main.index or (#steps + 1)
	local from = math.max(1, (first and first.index or mainIndex) - 60)
	for i = (first and first.index or mainIndex) - 1, from, -1 do
		local step = steps[i]
		local state = GuideState(guide)[i]
		if state ~= "done" and state ~= "skip" then
			local keep = step.sticky or (IsAux(step) and AuxEndIndex(guide, step) > mainIndex - 1 and step.completewith ~= "next")
			if keep then
				local status = QQ:EvaluateStep(step)
				step.qqStatus = status
				if status == "done" or status == "skip" then
					SetStepState(guide, i, status)
				else
					tinsert(QQ.active, 1, step)
				end
			end
		end
	end

	if index > #steps and #QQ.active == 0 then
		QQ:GuideFinished(guide)
	end
end

function QQ:UpdateSteps()
	local guide = self.guide
	if not guide or not guide.steps then return end
	Advance(guide)
	local sig = Signature()
	if sig ~= lastSignature then
		lastSignature = sig
		self:Fire("QQ_STEPS_CHANGED")
	end
	self:Fire("QQ_STEPS_UPDATED")
end

function QQ:RequestUpdate()
	self:Debounce("steps", 0.1, function() QQ:UpdateSteps() end)
end

-- upcoming steps after the main step (for the window)
function QQ:GetUpcomingSteps(count)
	local out = {}
	local guide = self.guide
	if not guide or not guide.steps then return out end
	local main = self.active[#self.active]
	local i = main and main.index + 1 or CurrentIndex(guide)
	while i <= #guide.steps and #out < count do
		local step = guide.steps[i]
		if not StepFilteredOut(step, guide) and GuideState(guide)[i] ~= "skip" and not step.hidewindow then
			tinsert(out, step)
		end
		i = i + 1
	end
	return out
end

---------------------------------------------------------------------------
-- user actions
---------------------------------------------------------------------------
function QQ:CompleteStep(step)
	if not step or not self.guide then return end
	if self.holdIndex == step.index then self.holdIndex = nil end
	step.manualDone = true
	SetStepState(self.guide, step.index, "done")
	if step.index == CurrentIndex(self.guide) then SetCurrentIndex(self.guide, step.index + 1) end
	self:UpdateSteps()
end

-- ">" : skips the next open task; the whole step only when nothing is left to do
function QQ:SkipTask()
	local guide = self.guide
	if not guide then return end
	for _, step in ipairs(self.active) do
		for i, e in ipairs(step.elements) do
			if e.state == TODO then
				SkipTable(guide, step.index, true)[i] = true
				if self.holdIndex == step.index and self:EvaluateStep(step) == "done" then self.holdIndex = nil end
				self:UpdateSteps()
				return
			end
		end
	end
	self:SkipStep()
end

-- "<" : takes back the last skipped task of the shown steps, otherwise goes one step back
function QQ:UndoTask()
	local guide = self.guide
	if not guide then return end
	for n = #self.active, 1, -1 do
		local step = self.active[n]
		local t = SkipTable(guide, step.index)
		if t then
			for i = #step.elements, 1, -1 do
				if t[i] then
					t[i] = nil
					self:UpdateSteps()
					return
				end
			end
		end
	end
	self:PreviousStep()
end

function QQ:SkipStep()
	local main = self.active[#self.active]
	if not main then return end
	self.holdIndex = nil
	for _, step in ipairs(self.active) do
		if step.index <= main.index then SetStepState(self.guide, step.index, "done") end
	end
	SetCurrentIndex(self.guide, main.index + 1)
	self:UpdateSteps()
end

function QQ:PreviousStep()
	local guide = self.guide
	if not guide or not guide.steps then return end
	local first = self.active[1]
	local state = GuideState(guide)
	local i = (first and first.index or CurrentIndex(guide)) - 1
	-- the last step that was really shown (skipped ones stay skipped)
	while i >= 1 and (state[i] == "skip" or StepFilteredOut(guide.steps[i], guide) or guide.steps[i].hidewindow) do
		i = i - 1
	end
	if i < 1 then return end
	ClearSkips(guide, i + 1)
	for j = i, #guide.steps do
		state[j] = nil
		guide.steps[j].manualDone = nil
	end
	self.holdIndex = i
	SetCurrentIndex(guide, i)
	self:UpdateSteps()
end

function QQ:GoToStep(index)
	local guide = self.guide
	if not guide or not guide.steps or not guide.steps[index] then return end
	local state = GuideState(guide)
	ClearSkips(guide, index)
	for j = 1, #guide.steps do
		if j >= index then
			state[j] = nil
			guide.steps[j].manualDone = nil
		elseif not state[j] then
			state[j] = "done"
		end
	end
	self.holdIndex = index
	SetCurrentIndex(guide, index)
	self:UpdateSteps()
end

---------------------------------------------------------------------------
-- guides
---------------------------------------------------------------------------
function QQ:LoadGuide(guide, fromStart)
	if type(guide) == "string" then guide = self:GetGuide(guide) end
	if not guide then return end
	self:ParseGuide(guide)
	self.guide = guide
	self.holdIndex = nil
	self.char.guide = guide.key
	if fromStart then
		self.char.steps[guide.key] = 1
		self.char.state[guide.key] = {}
		ClearSkips(guide, 1)
	end
	wipe(events)
	lastSignature = nil
	self:Fire("QQ_GUIDE_LOADED", guide)
	self:UpdateSteps()
end

function QQ:GuideFinished(guide)
	if self.finishing == guide then return end
	self.finishing = guide
	local nextGuide
	for _, n in ipairs(guide.next or {}) do
		if not n.tags or self.Tags:Applies(n.tags) then
			for name in n.name:gmatch("[^;]+") do
				name = name:gsub("^%s+", ""):gsub("%s+$", "")
				nextGuide = self:FindGuide(name, guide.group)
				if nextGuide then break end
			end
			if nextGuide then break end
		end
	end
	if not nextGuide then nextGuide = self:FollowingGuide(guide) end
	self:After(0.5, function()
		self.finishing = nil
		if nextGuide then
			self:Printf("Guide finished, loading %s", nextGuide.name)
			self:LoadGuide(nextGuide)
		else
			self:Print("Guide finished.")
			self:Fire("QQ_GUIDE_FINISHED", guide)
		end
	end)
end

-- the guide meant for the race of a new character
function QQ:FindDefaultGuide()
	local race = self.player.race
	for _, list in pairs(self.groups) do
		for _, guide in ipairs(list) do
			if guide.defaultfor and not guide.farm and self.Tags:Applies(guide.defaultfor) then
				local minLevel = tonumber((guide.name or ""):match("^0?(%d+)%-"))
				if minLevel == 1 then return guide end
			end
		end
	end
end

---------------------------------------------------------------------------
-- events that complete elements of the active steps
---------------------------------------------------------------------------
local HEARTHSTONE = 8690
QQ:On("UNIT_SPELLCAST_SUCCEEDED", function(_, unit, spellName)
	if unit ~= "player" then return end
	events.cast = events.cast or {}
	for _, step in ipairs(QQ.active) do
		for _, e in ipairs(step.elements) do
			if (e.kind == "cast" or e.kind == "usespell") and GetSpellInfo(e.spell) == spellName then
				events.cast[e.spell] = true
			end
		end
	end
	if spellName == GetSpellInfo(HEARTHSTONE) then events.hs = true end
	QQ:RequestUpdate()
end)

QQ:On("MERCHANT_SHOW", function() events.vendor = true QQ:RequestUpdate() end)
local function CheckTrainer()
	if IsTradeskillTrainer and IsTradeskillTrainer() then return end
	if GetTrainerServiceTypeFilter and not GetTrainerServiceTypeFilter("available") then return end
	local open = 0
	for i = 1, (GetNumTrainerServices() or 0) do
		local _, _, category = GetTrainerServiceInfo(i)
		if category == "available" then open = open + 1 end
	end
	if open == 0 then QQ.char.trainedLevel = UnitLevel("player") end
end
QQ:On("TRAINER_SHOW", function() events.trainer = true CheckTrainer() QQ:RequestUpdate() end)
QQ:On("TRAINER_UPDATE", function() CheckTrainer() QQ:RequestUpdate() end)
QQ:On("PLAYER_DEAD", function() events.dead = true QQ:RequestUpdate() end)
QQ:On("HEARTHSTONE_BOUND", function() events.home = true QQ:RequestUpdate() end)
QQ:On("PLAYER_CONTROL_LOST", function()
	QQ:After(1, function()
		if UnitOnTaxi("player") then events.fly = true QQ:RequestUpdate() end
	end)
end)
QQ:On("UI_INFO_MESSAGE", function(_, msg)
	if msg == ERR_NEWTAXIPATH then events.fp = true QQ:RequestUpdate() end
end)
QQ:On("TAXIMAP_OPENED", function()
	QQ.char.flightPaths = QQ.char.flightPaths or {}
	for i = 1, NumTaxiNodes() do
		local name = TaxiNodeName(i)
		local status = TaxiNodeGetType(i)
		if name and status ~= "NONE" then
			local short = name:match("^([^,]+)") or name
			QQ.char.flightPaths[Norm(short)] = true
			QQ.char.flightPaths[Norm(name)] = true
		end
	end
	QQ:RequestUpdate()
end)

for _, ev in ipairs({ "QQ_QUESTLOG_CHANGED", "QQ_QUEST_TURNED_IN", "QQ_QUEST_HISTORY", "BAG_UPDATE", "PLAYER_LEVEL_UP",
	"PLAYER_XP_UPDATE", "ZONE_CHANGED", "ZONE_CHANGED_NEW_AREA", "ZONE_CHANGED_INDOORS", "LEARNED_SPELL_IN_TAB",
	"SKILL_LINES_CHANGED", "PLAYER_MONEY", "UNIT_AURA", "UNIT_ENTERED_VEHICLE" }) do
	QQ:On(ev, function() QQ:RequestUpdate() end)
end

-- regular update (waypoint arrival, xp ...)
QQ:On("QQ_LOGIN", function()
	if not next(QQ.guides) then
		QQ.noGuides = true
		QQ:Print("|cffff5050No guides found.|r Please download and install |cffffd200QuickQuest_Guides|r (the guide pack) next to QuickQuest, then restart the game.")
	end
	local key = QQ.char.guide
	local guide = key and QQ:GetGuide(key)
	if not guide then guide = QQ:FindDefaultGuide() end
	if guide then QQ:LoadGuide(guide) end
	QQ:Every(1, function() QQ:UpdateSteps() end)
end)
