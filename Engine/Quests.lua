-- QuickQuest
-- Quest log and quest history (3.3.5: quest ids from GetQuestLogTitle, history from QueryQuestsCompleted)

local _, QQ = ...

local Quests = {}
QQ.Quests = Quests

local log = {} -- questID -> { index, title, level, complete, objectives = { {text, done} } }
local byTitle = {} -- title -> questID (quests in the log)
local lastLog = {}

local function ScanLog()
	local newLog, newTitles = {}, {}
	local numEntries = GetNumQuestLogEntries()
	for i = 1, numEntries do
		local title, level, _, _, isHeader, _, isComplete, _, questID = GetQuestLogTitle(i)
		if title and not isHeader and questID then
			local q = { index = i, title = title, level = level, complete = isComplete == 1, failed = isComplete == -1, objectives = {} }
			local n = GetNumQuestLeaderBoards(i) or 0
			for j = 1, n do
				local text, _, done = GetQuestLogLeaderBoard(j, i)
				q.objectives[j] = { text = text, done = done and true or false }
			end
			if n == 0 and isComplete ~= -1 then q.complete = true end
			newLog[questID] = q
			newTitles[title] = questID
		end
	end
	-- quests that left the log while they were complete are most likely turned in
	for id, q in pairs(log) do
		if not newLog[id] and q.complete and Quests.pendingTurnIn == q.title then
			Quests:MarkCompleted(id)
		end
	end
	lastLog = log
	log, byTitle = newLog, newTitles
	QQ:Fire("QQ_QUESTLOG_CHANGED")
end

function Quests:Get(id) return log[id] end
function Quests:IsOnQuest(id) return log[id] ~= nil end
function Quests:IsComplete(id)
	local q = log[id]
	return q and q.complete
end
function Quests:IdByTitle(title) return byTitle[title] end

function Quests:IsObjectiveDone(id, objective)
	local q = log[id]
	if not q then return false end
	if q.complete then return true end
	local o = objective and q.objectives[objective]
	if o then return o.done end
	return false
end

function Quests:ObjectiveText(id, objective)
	local q = log[id]
	local o = q and objective and q.objectives[objective]
	return o and o.text
end

function Quests:IsTurnedIn(id)
	return QQ.char and QQ.char.completed[id] and true or false
end

function Quests:MarkCompleted(id)
	if not id or not QQ.char then return end
	QQ.char.completed[id] = true
	QQ:Fire("QQ_QUEST_TURNED_IN", id)
end

function Quests:Name(id)
	local q = log[id]
	if q then return q.title end
	local d = QQ.questData and QQ.questData[id]
	return d and d[1] ~= "" and d[1] or nil
end

function Quests:Level(id)
	local q = log[id]
	if q and q.level and q.level > 0 then return q.level end
	local d = QQ.questData and QQ.questData[id]
	local level = d and d[2]
	if level and level > 0 then return level end
end

-- not in the log, not turned in and every pre quest done
function Quests:IsAvailable(id)
	if log[id] or self:IsTurnedIn(id) then return false end
	local d = QQ.questData and QQ.questData[id]
	if not d then return true end
	if d[3] and d[3] > (UnitLevel("player") or 1) then return false end
	if d[5] then
		for _, pre in ipairs(d[5]) do
			if not self:IsTurnedIn(pre < 0 and -pre or pre) then return false end
		end
	end
	if d[6] and #d[6] > 0 then
		for _, pre in ipairs(d[6]) do
			if self:IsTurnedIn(pre < 0 and -pre or pre) then return true end
		end
		return false
	end
	return true
end

---------------------------------------------------------------------------
-- turn in detection
---------------------------------------------------------------------------
QQ:On("QUEST_COMPLETE", function()
	Quests.pendingTurnIn = GetTitleText()
end)

hooksecurefunc("GetQuestReward", function()
	local title = Quests.pendingTurnIn or GetTitleText()
	local id = title and byTitle[title]
	if id then Quests:MarkCompleted(id) end
end)

-- "%s completed."
local COMPLETE_PATTERN = ERR_QUEST_COMPLETE_S and "^" .. ERR_QUEST_COMPLETE_S:gsub("%%s", "(.+)") .. "$"
QQ:On("CHAT_MSG_SYSTEM", function(_, msg)
	if not COMPLETE_PATTERN or not msg then return end
	local title = msg:match(COMPLETE_PATTERN)
	local id = title and (byTitle[title])
	if not id and title then
		for qid, q in pairs(lastLog) do
			if q.title == title then id = qid break end
		end
	end
	if id then Quests:MarkCompleted(id) end
end)

QQ:On("QUEST_LOG_UPDATE", function()
	QQ:Debounce("questlog", 0.2, ScanLog)
end)
QQ:On("UNIT_QUEST_LOG_CHANGED", function(_, unit)
	if unit == "player" then QQ:Debounce("questlog", 0.2, ScanLog) end
end)

---------------------------------------------------------------------------
-- history from the server
---------------------------------------------------------------------------
QQ:On("QUEST_QUERY_COMPLETE", function()
	local t = {}
	GetQuestsCompleted(t)
	local completed = QQ.char.completed
	for id in pairs(t) do completed[id] = true end
	Quests.historyLoaded = true
	QQ:Fire("QQ_QUEST_HISTORY")
end)

QQ:On("QQ_LOGIN", function()
	ScanLog()
	QQ:After(2, function() QueryQuestsCompleted() end)
end)

function Quests:Scan() ScanLog() end
