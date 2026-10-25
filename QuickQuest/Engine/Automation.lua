-- QuickQuest
-- Accepts and turns in the quests of the active steps (hold Shift to do it yourself)

local _, QQ = ...
local Quests = QQ.Quests

local ipairs = ipairs

local function Norm(s)
	return s and s:lower():gsub("[^%w]", "") or ""
end

-- quest names wanted by the active steps
local function Wanted(kind)
	local names = {}
	for _, step in ipairs(QQ.active) do
		for _, e in ipairs(step.elements) do
			if e.kind == kind and e.questId and e.state ~= QQ.ELEMENT_DONE then
				local name = Quests:Name(e.questId)
				if not name and e.text then
					name = e.text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):match("^%s*%a+%s+in%s+(.+)$") or
						e.text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):match("^%s*%a+%s+(.+)$")
				end
				if name then names[Norm(name)] = e.questId end
			end
		end
	end
	return names
end

local function Enabled(what)
	return QQ.db and QQ.db.automation[what] and not IsShiftKeyDown()
end

QQ:On("QUEST_DETAIL", function()
	if not Enabled("accept") then return end
	if Wanted("accept")[Norm(GetTitleText())] then AcceptQuest() end
end)

QQ:On("QUEST_ACCEPT_CONFIRM", function()
	if Enabled("accept") then ConfirmAcceptQuest() end
end)

QQ:On("QUEST_PROGRESS", function()
	if not Enabled("turnin") then return end
	if Wanted("turnin")[Norm(GetTitleText())] and IsQuestCompletable() then CompleteQuest() end
end)

QQ:On("QUEST_COMPLETE", function()
	if not Enabled("turnin") then return end
	if not Wanted("turnin")[Norm(GetTitleText())] then return end
	local choices = GetNumQuestChoices() or 0
	if choices <= 1 then
		GetQuestReward(choices)
	elseif QQ:IsGoldMode() then
		-- Quest for gold: take the reward that sells for the most
		local best, bestValue = nil, -1
		for i = 1, choices do
			local link = GetQuestItemLink("choice", i)
			local _, _, count = GetQuestItemInfo("choice", i)
			local price = link and select(11, GetItemInfo(link))
			if not price then return end -- unknown item: the choice stays yours
			local value = price * (count or 1)
			if value > bestValue then best, bestValue = i, value end
		end
		if best then GetQuestReward(best) end
	end -- otherwise the choice stays yours
end)

local function TrySelect(names, count, getName, select)
	for i = 1, count do
		local name = getName(i)
		if name and names[Norm(name)] then
			select(i)
			return true
		end
	end
end

QQ:On("GOSSIP_SHOW", function()
	if not Enabled("gossip") then return end
	-- 3.3.5: active quests come in groups of 4 values, available ones in groups of 5
	local active = { GetGossipActiveQuests() }
	local turnin = Wanted("turnin")
	for i = 1, #active, 4 do
		local name, _, _, isComplete = active[i], active[i + 1], active[i + 2], active[i + 3]
		if name and turnin[Norm(name)] and Quests:IsComplete(turnin[Norm(name)]) then
			SelectGossipActiveQuest((i + 3) / 4)
			return
		end
	end
	local available = { GetGossipAvailableQuests() }
	local accept = Wanted("accept")
	for i = 1, #available, 5 do
		local name = available[i]
		if name and accept[Norm(name)] then
			SelectGossipAvailableQuest((i + 4) / 5)
			return
		end
	end
end)

QQ:On("QUEST_GREETING", function()
	if not Enabled("gossip") then return end
	local turnin = Wanted("turnin")
	for i = 1, GetNumActiveQuests() do
		local name = GetActiveTitle(i)
		local id = name and turnin[Norm(name)]
		if id and Quests:IsComplete(id) then
			SelectActiveQuest(i)
			return
		end
	end
	TrySelect(Wanted("accept"), GetNumAvailableQuests(), GetAvailableTitle, SelectAvailableQuest)
end)
