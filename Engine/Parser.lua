-- QuickQuest
-- Guide registry and parser for the guide text format
-- (guides are registered as plain text and parsed when they are loaded)

local _, QQ = ...
local Tags = QQ.Tags

local tinsert, tonumber, strtrim = table.insert, tonumber, strtrim
local fmt = string.format

QQ.guides = {} -- key -> guide
QQ.groups = {} -- group -> { guides in order of registration }

local GAME_FLAGS = { classic = true, tbc = true, wotlk = true, cata = true, mop = true, retail = true, df = true, era = true, som = true }
local SKIP_GROUPS = { ["RestedXP TBC Preparation"] = true }
local INTERNAL_GROUPS = { RXPGuides = true }

-- short names for the menu
function QQ:GroupName(group)
	local name = group:gsub("^[%+%*]", ""):gsub("^RestedXP%s+", ""):gsub("^RXP%s+", "")
	local side = name:match("%((%a)%)%s*$")
	local faction = side == "H" and "Horde" or side == "A" and "Alliance" or nil
	if name:match("^TBC Guide") and faction then return faction .. " 1-70 (classic route)" end
	if name:match("^Cataclysm 60%-80") and faction then return faction .. " 60-80 (Outland & Northrend)" end
	return name
end

local function Key(group, name)
	return (group or "?") .. "||" .. (name or "?")
end
QQ.GuideKey = Key

local function Lines(text)
	local i = 0
	local lines = {}
	for line in text:gmatch("[^\r\n]+") do
		line = line:gsub("^%s+", ""):gsub("%s+$", "")
		-- comments: "-- ..." at the start or after a space
		if line:sub(1, 2) == "--" then
			line = ""
		else
			line = line:gsub("%s+%-%-[^|]*$", "")
		end
		if line ~= "" then
			i = i + 1
			lines[i] = line
		end
	end
	return lines
end

---------------------------------------------------------------------------
-- Registration (header only)
---------------------------------------------------------------------------
local function ParseHeader(text)
	local header = { tags = {}, next = {} }
	local lines = Lines(text)
	local stepStart
	for i, line in ipairs(lines) do
		if line:match("^step") then
			stepStart = i
			break
		end
		local code, tags = line:match("^(.-)%s*<<%s*(.-)%s*$")
		code = code or line
		if code == "" then
			header.applies = tags -- guide wide filter ("<< Horde")
		else
			local key, value = code:match("^#(%S+)%s*(.*)$")
			if key then
				key = key:lower()
				if GAME_FLAGS[key] and value == "" then
					header.tags[key] = true
				elseif key == "next" then
					tinsert(header.next, { name = value, tags = tags })
				elseif not tags or Tags:Applies(tags) then
					header[key] = value ~= "" and value or true
				end
			end
		end
	end
	header.lines = lines
	header.stepStart = stepStart
	return header
end

-- which game rules a guide is parsed with on 3.3.5 (nil = not usable here)
local function GuideGame(h)
	local t = h.tags
	if t.wotlk then return "WOTLK" end
	if t.tbc then return "TBC" end
	for flag in pairs(GAME_FLAGS) do
		if t[flag] then return nil end
	end
	return "WOTLK"
end

-- one spelling for all guide names in the menus: "060-70" -> "60-70", "part 1" -> "Part 1",
-- "Un'goro" -> "Un'Goro", "Gorge/Burning" -> "Gorge / Burning"
local SMALL = { ["and"] = true, ["of"] = true, ["the"] = true, ["to"] = true, ["in"] = true, ["en"] = true, ["a"] = true, ["an"] = true, ["for"] = true, ["on"] = true, ["at"] = true, ["with"] = true }
function QQ:NiceGuideName(name)
	if type(name) ~= "string" then return name end
	-- no colour codes in menu names
	name = name:gsub("|c[Rr][Xx][Pp]_%u+_", ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
	name = name:gsub("^0+(%d)", "%1"):gsub("^(%d+)%-0+(%d)", "%1-%2")
	name = name:gsub("%s*/%s*", " / "):gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
	local first = true
	name = name:gsub("[%a][%a'%-]*", function(word)
		local lower = word:lower()
		if not first and SMALL[lower] then return lower end
		first = false
		word = word:sub(1, 1):upper() .. word:sub(2)
		-- Un'goro, Zul'drak, Quel'thalas (but not Blade's)
		word = word:gsub("^(%a%a?%a?%a?)'(%l)(%l%l+)", function(a, b, c) return a .. "'" .. b:upper() .. c end)
		return word
	end)
	return name
end

-- gathering routes only say "Mining" / "Herbalism": add what you find in that zone
local GATHER = {
	["Hellfire Peninsula"] = { "Fel Iron, Adamantite", "Felweed, Dreaming Glory, Nightmare Vine" },
	["Zangarmarsh"] = { "Fel Iron, Adamantite", "Felweed, Ragveil, Flame Cap, Dreaming Glory" },
	["Terokkar Forest"] = { "Fel Iron, Adamantite, Khorium", "Felweed, Terocone, Dreaming Glory, Mana Thistle" },
	["Nagrand"] = { "Fel Iron, Adamantite, Khorium", "Felweed, Dreaming Glory" },
	["Blades Edge Mountains"] = { "Fel Iron, Adamantite, Khorium", "Felweed, Dreaming Glory, Mana Thistle" },
	["Netherstorm"] = { "Fel Iron, Adamantite, Khorium", "Netherbloom, Felweed, Dreaming Glory, Mana Thistle" },
	["Shadowmoon Valley"] = { "Fel Iron, Adamantite, Khorium", "Nightmare Vine, Terocone, Felweed, Mana Thistle" },
	["Borean Tundra"] = { "Cobalt", "Goldclover, Tiger Lily, Fire Leaf" },
	["Howling Fjord"] = { "Cobalt", "Goldclover, Tiger Lily" },
	["Dragonblight"] = { "Cobalt, Saronite", "Goldclover" },
	["Grizzly Hills"] = { "Cobalt", "Goldclover, Tiger Lily, Talandra's Rose" },
	["Zul'Drak"] = { "Cobalt, Saronite", "Talandra's Rose" },
	["Sholazar Basin"] = { "Saronite, Titanium", "Adder's Tongue, Tiger Lily, Goldclover" },
	["The Storm Peaks"] = { "Saronite, Titanium", "Lichbloom, Icethorn" },
	["Icecrown"] = { "Saronite, Titanium", "Lichbloom, Icethorn" },
	["Wintergrasp"] = { "Saronite, Titanium", "Lichbloom, Icethorn, Frost Lotus" },
	["Un'Goro Crater"] = { "Thorium", "Golden Sansam, Dreamfoil, Mountain Silversage" },
	["Winterspring"] = { "Thorium, Mithril", "Icecap, Mountain Silversage, Black Lotus" },
}
local function GatherName(name, zone)
	local g = zone and GATHER[zone]
	if not g then return name end
	if name == "Mining" then return "Mining: " .. g[1] end
	if name == "Herbalism" then return "Herbalism: " .. g[2] end
	if name == "Mining & Herbalism" then return "Both: " .. g[1] .. " + " .. g[2] end
	return name
end

function QQ:RegisterGuide(groupOrText, text)
	local group
	if text then
		group = groupOrText
	else
		text = groupOrText
	end
	if type(text) ~= "string" then return end
	local h = ParseHeader(text)
	group = h.group or group
	local name = h.name
	if not group or not name or SKIP_GROUPS[group] then return end
	local game = GuideGame(h)
	if not game then return end
	Tags:SetGame(game)
	if h.applies and not Tags:Applies(h.applies) then
		Tags:SetGame("WOTLK")
		return
	end
	Tags:SetGame("WOTLK")

	local farm = group:sub(1, 1) == "+"
	local guide = {
		key = Key(group, name),
		group = group,
		name = name,
		displayname = GatherName(QQ:NiceGuideName(type(h.displayname) == "string" and h.displayname or name), type(h.subgroup) == "string" and h.subgroup or nil),
		subgroup = h.subgroup,
		game = game,
		farm = farm,
		internal = (h.internal or INTERNAL_GROUPS[group]) and true or nil,
		next = h.next,
		defaultfor = h.defaultfor,
		xprate = type(h.xprate) == "string" and h.xprate or nil,
		maxlevel = tonumber(h.maxlevel or h.maxLevel),
		minlevel = tonumber(h.minlevel or h.minLevel),
		text = text,
	}
	if self.guides[guide.key] then return end -- first registration wins
	self.guides[guide.key] = guide
	if not self.groups[group] then self.groups[group] = {} end
	tinsert(self.groups[group], guide)
	return guide
end

_G.QuickQuest_RegisterGuide = function(...) return QQ:RegisterGuide(...) end

function QQ:GetGuide(group, name)
	if name == nil and type(group) == "string" then
		local g, n = group:match("^(.-)||(.*)$")
		if g then group, name = g, n end
	end
	return self.guides[Key(group, name)]
end

-- "6-10 Mulgore" or "Group\Name"
function QQ:FindGuide(name, preferGroup)
	if not name then return end
	local group, guideName = name:match("^(.-)\\(.+)$")
	if group then return self.guides[Key(group, guideName)] end
	if preferGroup and self.guides[Key(preferGroup, name)] then return self.guides[Key(preferGroup, name)] end
	for _, guide in pairs(self.guides) do
		if guide.name == name then return guide end
	end
end

---------------------------------------------------------------------------
-- Elements
---------------------------------------------------------------------------
local function SplitArgs(s)
	local t = {}
	if not s or s == "" then return t end
	for part in (s .. ","):gmatch("([^,]*),") do
		tinsert(t, strtrim(part))
	end
	return t
end

local COLOR_CODES = {
	RXP_FRIENDLY_ = "|cff00ff25", RXP_ENEMY_ = "|cffff5050", RXP_LOOT_ = "|cff00bfff",
	RXP_WARN_ = "|cffffcc33", RXP_BUY_ = "|cffffdd88", RXP_PICK_ = "|cffdb7aff",
}
local function CleanText(text)
	if not text then return nil end
	text = text:gsub("|c(RXP_[A-Z]+_)", function(code) return COLOR_CODES[code] or "|cffffffff" end)
	text = text:gsub("|T[Ii]nterface/worldmap/chatbubble_64grey%.blp:20|t", "")
	text = text:gsub("^%s+", "")
	return text
end
QQ.CleanText = CleanText

-- zone argument: name, uiMapID or "uiMapID/instance"
local function ZoneArg(z)
	if not z then return nil end
	z = z:gsub("^@%d+,?", "")
	local id = tonumber(z) or tonumber(z:match("^(%d+)/%d+$"))
	if id then return id end
	return QQ:ResolveZone(z)
end

local parsers = {}
QQ.elementParsers = parsers

local function QuestElement(kind)
	return function(e, args)
		local id = tonumber(args[1])
		if not id then return false end
		if id < 0 then id, e.optional = -id, true end
		e.questId = id
		if kind == "complete" then
			e.objective = tonumber(args[2])
		end
		return true
	end
end
parsers.accept = QuestElement("accept")
parsers.daily = function(e, args)
	e.kind = "accept"
	e.daily = true
	return parsers.accept(e, args)
end
parsers.turnin = QuestElement("turnin")
parsers.complete = QuestElement("complete")
parsers.abandon = QuestElement("abandon")

local function Waypoint(e, args)
	local zone = ZoneArg(args[1])
	local x, y = tonumber(args[2]), tonumber(args[3])
	if not zone or not x or not y then return false end
	e.zone, e.x, e.y = zone, x / 100, y / 100
	e.radius = tonumber(args[4])
	e.passive = args[5] == "0" -- does not complete the step on arrival
	return true
end
parsers["goto"] = Waypoint
parsers.groundgoto = Waypoint
parsers.waypoint = function(e, args)
	if not Waypoint(e, args) then return false end
	e.passive = true
	return true
end

local function Units(e, args, priorityKey)
	e.units = {}
	for _, name in ipairs(args) do
		local priority = name:sub(1, 1) == "+"
		if priority then name = name:sub(2) end
		if name ~= "" then tinsert(e.units, { name = name, priority = priority }) end
	end
	return #e.units > 0
end
parsers.target = Units
parsers.mob = Units
parsers.unitscan = Units

parsers.collect = function(e, args)
	e.item = tonumber(args[1])
	e.count = tonumber(args[2]) or 1
	e.questId = tonumber(args[3])
	return e.item ~= nil
end
parsers.use = function(e, args)
	e.item = tonumber(args[1])
	return e.item ~= nil
end
parsers.destroy = parsers.use
parsers.equip = function(e, args)
	e.slot, e.item = tonumber(args[1]), tonumber(args[2])
	return true
end

-- level / xp: ".xp 10", ".xp 6-1450", ".xp 5+2395", ".xp 9.5", ".xp <15,1", ".xp >12,1"
parsers.xp = function(e, args)
	local s = args[1] or ""
	local op, rest = s:match("^([<>]?)%s*(.*)$")
	local level, sign, amount = rest:match("^(%d+)([%+%-]?)(%d*)")
	level = tonumber(level)
	if not level then
		level = tonumber(rest)
		if not level then return false end
	end
	e.level = math.floor(level)
	e.fraction = level - math.floor(level)
	if sign == "+" then e.xpAbove = tonumber(amount) elseif sign == "-" then e.xpBelow = tonumber(amount) end
	e.op = op
	e.skip = args[2] == "1"
	return true
end

parsers.train = function(e, args)
	e.spell = tonumber(args[1])
	return e.spell ~= nil
end
parsers.cast = function(e, args)
	e.spell = tonumber(args[1])
	return e.spell ~= nil
end
parsers.usespell = parsers.cast
parsers.aura = function(e, args)
	e.spell = tonumber(args[1])
	return e.spell ~= nil
end

parsers.fp = function(e, args)
	e.place = args[1]
	return true
end
parsers.fly = function(e, args)
	e.place = args[1]
	return true
end
parsers.hs = function() return true end
parsers.home = function() return true end
parsers.bindlocation = function(e, args)
	e.area = tonumber(args[1])
	e.skip = args[2] == "1"
	return e.area ~= nil
end
parsers.vendor = function() return true end
parsers.trainer = function() return true end
parsers.deathskip = function() return true end
parsers.vehicle = function() return true end

parsers.zone = function(e, args)
	e.zoneName = args[1]
	return e.zoneName ~= nil
end
parsers.zoneskip = function(e, args)
	e.zoneName = args[1]
	e.reverse = args[2] == "1"
	return true
end
parsers.subzone = function(e, args)
	e.area = tonumber(args[1])
	e.reverse = args[2] == "1"
	return e.area ~= nil
end
parsers.subzoneskip = parsers.subzone

parsers.isOnQuest = function(e, args)
	e.quests = {}
	for _, a in ipairs(args) do
		local id = tonumber(a)
		if id then tinsert(e.quests, id) end
	end
	return #e.quests > 0
end
parsers.isQuestComplete = parsers.isOnQuest
parsers.isQuestTurnedIn = parsers.isOnQuest
parsers.isQuestAvailable = parsers.isOnQuest
parsers.isQuestNotTurnedIn = parsers.isOnQuest

parsers.itemcount = function(e, args)
	e.item = tonumber(args[1])
	local s = args[2] or "1"
	e.op, e.count = s:match("^([<>]?)%s*(%d+)")
	e.count = tonumber(e.count) or 1
	return e.item ~= nil
end
parsers.money = function(e, args)
	local s = args[1] or ""
	e.op, e.gold = s:match("^([<>]?)%s*([%d%.]+)")
	e.gold = tonumber(e.gold)
	return e.gold ~= nil
end
parsers.skill = function(e, args)
	e.skill = args[1] and args[1]:lower()
	local s = args[2] or ""
	e.op, e.value = s:match("^([<>]?)%s*(%d+)")
	e.value = tonumber(e.value)
	e.skip = args[3] == "1"
	return e.skill ~= nil and e.value ~= nil
end
parsers.reputation = function(e, args)
	e.faction = tonumber(args[1])
	e.standing = args[2] and args[2]:lower()
	e.repOp = args[3]
	e.skip = args[4] == "1"
	return e.faction ~= nil
end
parsers.cooldown = function(e, args)
	e.cdType, e.item = args[1], tonumber(args[2])
	local s = args[3] or ""
	e.op, e.seconds = s:match("^([<>]?)%s*(%d+)")
	e.seconds = tonumber(e.seconds)
	e.skip = args[4] == "1"
	return e.item ~= nil
end
parsers.maxlevel = function(e, args)
	e.level = tonumber(args[1])
	return e.level ~= nil
end
parsers.dungeon = function(e, args)
	e.dungeon = args[1]
	return true
end
parsers.requires = function(e, args)
	local kind, id = args[1], tonumber(args[2])
	if not kind or not id then return false end
	e.requireQuest = id
	e.negate = kind:sub(1, 1) == "!"
	return true
end
parsers.timer = function(e, args)
	e.seconds = tonumber(args[1])
	e.text = e.text or args[2]
	return true
end
parsers.link = function(e, args, raw)
	e.url = raw
	return true
end

-- commands that only show their text (no logic in this addon)
local TEXT_ONLY = {
	line = "hide", loop = "hide", openmap = "hide", clicknext = "hide", disablecheckbox = "flag",
	skipgossip = "hide", gossipoption = "text", convertquest = "hide", talent = "hide", itemStat = "hide",
	questguide = "hide", emote = "text", stable = "text", tame = "text", achievement = "text",
	bankdeposit = "text", bankwithdraw = "text", ah = "text", engrave = "text", buy = "text",
	petskill = "text", rep = "text", spell = "text", xprate = "hide", season = "hide", phase = "hide",
	isQuestNotComplete = "hide", subgroup = "hide",
}

local function ParseElement(cmd, rest)
	local argstr, text = rest:match("^(.-)%s*>>%s*(.*)$")
	if not argstr then argstr = rest end
	local e = { kind = cmd, text = CleanText(text) }
	local mode = TEXT_ONLY[cmd]
	if mode then
		if mode == "hide" then return nil end
		if mode == "flag" then return { kind = "flag", flag = cmd } end
		if not e.text then return nil end
		e.kind = "text"
		return e
	end
	local parser = parsers[cmd]
	if not parser then
		if e.text then
			e.kind = "text"
			return e
		end
		return nil
	end
	local args = SplitArgs(argstr)
	if parser(e, args, argstr) == false then
		QQ.parseFailures = QQ.parseFailures or {}
		QQ.parseFailures[cmd .. " " .. argstr] = (QQ.parseFailures[cmd .. " " .. argstr] or 0) + 1
		if e.text then
			e.kind = "text"
			return e
		end
		return nil
	end
	return e
end

---------------------------------------------------------------------------
-- Full parse of a guide
---------------------------------------------------------------------------
local function ParseSteps(guide, out, depth, startLabel, stopLabel)
	depth = depth or 0
	local h = ParseHeader(guide.text)
	Tags:SetGame(guide.game)
	local lines = h.lines
	local steps = {}
	local step
	local skipStep = false
	for i = (h.stepStart or #lines + 1), #lines do
		local line = lines[i]
		local stepTags = line:match("^step%s*<<%s*(.-)%s*$")
		if line:match("^step") then
			if step then tinsert(steps, step) end
			step = { elements = {}, guide = guide }
			skipStep = stepTags and not Tags:Applies(stepTags) or false
			if skipStep then step = nil end
		elseif step then
			local code = Tags:Filter(line)
			if code and code ~= "" then
				local first = code:sub(1, 1)
				if first == "#" then
					local key, value = code:match("^#(%S+)%s*(.*)$")
					if key then
						key = key:lower()
						if key == "include" then
							step.include = value
						elseif key == "completwith" then
							step.completewith = value
						else
							step[key] = value ~= "" and value or true
						end
					end
				elseif first == "." then
					local cmd, rest = code:match("^%.(%a+)%s*(.*)$")
					if cmd then
						local e = ParseElement(cmd, rest)
						if e then
							if e.kind == "flag" then
								step[e.flag] = true
							else
								e.step = step
								tinsert(step.elements, e)
							end
						end
					end
				elseif first == "+" then
					tinsert(step.elements, { kind = "manual", text = CleanText(code:sub(2)), step = step })
				else
					local text = code:gsub("^>>%s*", "")
					text = CleanText(text)
					if text ~= "" then tinsert(step.elements, { kind = "text", text = text, step = step }) end
				end
			end
		end
	end
	if step then tinsert(steps, step) end

	-- includes and label ranges
	local started = startLabel == nil
	for _, s in ipairs(steps) do
		if not started and s.label == startLabel then started = true end
		if started then
			if s.include and depth < 4 then
				local target = s.include
				if target ~= "QuestDB" then
					local name, a, b = target:match("^(.-)@([^@%-]*)%-?([^@%-]*)$")
					name = name or target
					local included = QQ:FindGuide(name, guide.group)
					if included and included ~= guide then
						ParseSteps(included, out, depth + 1, a ~= "" and a or nil, b ~= "" and b or nil)
						Tags:SetGame(guide.game)
					end
				end
				if #s.elements > 0 then tinsert(out, s) end
			else
				tinsert(out, s)
			end
			if stopLabel and s.label == stopLabel then break end
		end
	end
	return out
end

function QQ:ParseGuide(guide)
	if guide.steps then return guide.steps end
	local ok, steps = pcall(ParseSteps, guide, {})
	Tags:SetGame("WOTLK")
	if not ok then
		geterrorhandler()(steps)
		steps = {}
	end
	local labels = {}
	for i, step in ipairs(steps) do
		step.index = i
		if step.label then labels[step.label] = labels[step.label] or i end
	end
	guide.steps = steps
	guide.labels = labels
	return steps
end

-- guides are re-parsed when the level changes (step filters can depend on the level)
function QQ:ResetParsedGuides()
	for _, guide in pairs(self.guides) do
		guide.steps = nil
		guide.labels = nil
	end
end
