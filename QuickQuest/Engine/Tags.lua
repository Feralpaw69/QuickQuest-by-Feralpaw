-- QuickQuest
-- "<<" tag expressions of the guide format: "Horde", "Warrior/Paladin", "!Undead Mage", "(Shaman/Hunter) !tbc", "20" ...

local _, QQ = ...

local Tags = {}
QQ.Tags = Tags

-- game version tags the guides use; the parse game decides which one is "current"
local GAME_TAGS = { CLASSIC = true, ERA = true, SOM = true, SOD = true, TBC = true, WOTLK = true, CATA = true, MOP = true, RETAIL = true, DF = true }

Tags.game = "WOTLK"
local cache = {}

function Tags:SetGame(game)
	if game ~= self.game then
		self.game = game
	end
end

local function TokenMatches(token)
	local p = QQ.player
	local upper = token:upper()
	if upper == "DK" then upper = "DEATHKNIGHT" end
	if upper == p.class then return true end
	local race = p.race
	if token == race or (token == "Undead" and race == "Scourge") or upper == (race or ""):upper() then return true end
	if token == p.faction then return true end
	local level = tonumber(token)
	if level then return (p.level or UnitLevel("player") or 1) >= level end
	if GAME_TAGS[upper] then
		if upper == "DF" then upper = "RETAIL" end
		return upper == Tags.game
	end
	if upper == "MALE" then return UnitSex("player") == 2 end
	if upper == "FEMALE" then return UnitSex("player") == 3 end
	if upper == "SOFTCORE" then return true end
	return false
end

local function Evaluate(text)
	-- parenthesis groups first
	text = text:gsub("(!?)%(%s*([^()]-)%s*%)", function(neg, inner)
		local v = Evaluate(inner)
		if neg == "!" then v = not v end
		return v and "__TRUE__" or "__FALSE__"
	end)
	for alternative in text:gmatch("[^/]+") do
		local all = true
		local any = false
		for word in alternative:gmatch("%S+") do
			any = true
			local negate = word:sub(1, 1) == "!"
			if negate then word = word:sub(2) end
			local v
			if word == "__TRUE__" then v = true elseif word == "__FALSE__" then v = false else v = TokenMatches(word) end
			if negate then v = not v end
			if not v then all = false break end
		end
		if any and all then return true end
	end
	return false
end

function Tags:Applies(text)
	if not text or text == "" then return true end
	local key = self.game .. "\1" .. (QQ.player.level or 0) .. "\1" .. text
	local v = cache[key]
	if v == nil then
		v = Evaluate(text)
		cache[key] = v
	end
	return v
end

-- splits "code << tags" and returns code (or nil if the tags do not apply)
function Tags:Filter(line)
	local code, tags = line:match("^(.-)%s*<<%s*(.-)%s*$")
	if not code then return line end
	if self:Applies(tags) then return code end
	return nil
end

QQ:On("PLAYER_LEVEL_UP", function() cache = {} end)
