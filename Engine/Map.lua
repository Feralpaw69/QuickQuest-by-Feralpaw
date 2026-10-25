-- QuickQuest
-- Zones and positions: zone names of the guides, player position in world coordinates

local _, QQ = ...

local maps = QQ.maps
local floor, sqrt, atan2, PI2 = math.floor, math.sqrt, math.atan2, math.pi * 2

---------------------------------------------------------------------------
-- zone names -> uiMapID
---------------------------------------------------------------------------
local function Normalize(name)
	return (name:lower():gsub("[^%w]", ""))
end

local byName = {}
for id, data in pairs(maps) do
	if data.name then
		local key = Normalize(data.name)
		local old = byName[key]
		local size = (data[1] or 0) * (data[2] or 0)
		if not old then
			byName[key] = id
		else
			local o = maps[old]
			local oldSize = (o[1] or 0) * (o[2] or 0)
			if size > oldSize or (size == oldSize and id < old) then byName[key] = id end
		end
	end
end

-- names used by the guides that differ from the map names
local ALIASES = {
	icecrownglacier = "icecrown", stormwindclassic = "stormwindcity", stormwindnew = "stormwindcity",
	stormwind = "stormwindcity", scarletenclave = "plaguelandsthescarletenclave", ironforgecity = "ironforge",
	undercitycity = "undercity", silvermoon = "silvermooncity", shattrath = "shattrathcity", exodar = "theexodar",
	thousandneedles = "thousandneedles", stranglethornvale = "stranglethornvale", stranglethorn = "stranglethornvale",
	northernstranglethorn = "stranglethornvale", capeofstranglethorn = "stranglethornvale", thecapeofstranglethorn = "stranglethornvale",
	alteracmountains = "alteracmountains", dalaran = "dalaran", ruinsofgilneas = "silverpineforest",
}

function QQ:ResolveZone(name)
	if not name then return nil end
	local id = tonumber(name)
	if id then return maps[id] and id end
	local key = Normalize(name)
	return byName[key] or (ALIASES[key] and byName[ALIASES[key]])
end

function QQ:ZoneName(uiMapID)
	local data = maps[uiMapID]
	return data and data.name
end

---------------------------------------------------------------------------
-- 3.3.5 map area id (+ dungeon level) -> uiMapID
---------------------------------------------------------------------------
local areaToUi = {}
for id, data in pairs(maps) do
	if type(data.mapID) == "number" and data.mapID >= 0 then
		local key = floor(data.mapID * 10 + 0.5)
		local old = areaToUi[key]
		if not old or (data.mapType == 3 and maps[old].mapType ~= 3) then areaToUi[key] = id end
	end
end

local function DisplayedUiMap()
	local area = GetCurrentMapAreaID()
	if not area then return nil end
	local level = GetCurrentMapDungeonLevel() or 0
	return areaToUi[area * 10 + level] or (level > 0 and areaToUi[area * 10]) or nil
end
QQ.DisplayedUiMap = DisplayedUiMap

---------------------------------------------------------------------------
-- player position (world yards, like the client uses them internally)
---------------------------------------------------------------------------
local pos = { time = -1 }
local mapDirty = true
local lastReset = -10

function QQ:ZoneToWorld(uiMapID, x, y)
	local d = maps[uiMapID]
	if not d or not x or d[1] == 0 then return nil end
	return d[3] - d[1] * x, d[4] - d[2] * y, d.instance
end

function QQ:WorldToZone(uiMapID, wx, wy)
	local d = maps[uiMapID]
	if not d or not wx or d[1] == 0 then return nil end
	return (d[3] - wx) / d[1], (d[4] - wy) / d[2]
end

local function Read()
	local uiMapID = DisplayedUiMap()
	local d = uiMapID and maps[uiMapID]
	if not d or d[1] == 0 then return nil end
	local x, y = GetPlayerMapPosition("player")
	if not x or (x == 0 and y == 0) then return nil end
	return d[3] - d[1] * x, d[4] - d[2] * y, d.instance, uiMapID, x, y
end

local function Update()
	local now = GetTime()
	if pos.time == now then return end
	pos.time = now
	local mapShown = WorldMapFrame:IsVisible()
	if not mapShown and mapDirty then
		mapDirty = false
		SetMapToCurrentZone()
	end
	local wx, wy, instance, uiMapID, x, y = Read()
	-- the world map may show another zone: reset it (throttled, every reset fires WORLD_MAP_UPDATE)
	if not mapShown and (not wx or (maps[uiMapID] and (maps[uiMapID].mapType or 3) < 3)) and now - lastReset > 3 then
		lastReset = now
		SetMapToCurrentZone()
		wx, wy, instance, uiMapID, x, y = Read()
	end
	if wx then
		pos.wx, pos.wy, pos.instance, pos.zone, pos.x, pos.y = wx, wy, instance, uiMapID, x, y
		pos.valid = true
	else
		pos.valid = false
	end
end

function QQ:GetPlayerPosition()
	Update()
	if not pos.valid then return nil end
	return pos.wx, pos.wy, pos.instance, pos.zone, pos.x, pos.y
end

function QQ:MarkMapDirty()
	mapDirty = true
end

QQ:On("ZONE_CHANGED_NEW_AREA", function() mapDirty = true end)
QQ:On("ZONE_CHANGED", function() mapDirty = true end)
QQ:On("ZONE_CHANGED_INDOORS", function() mapDirty = true end)
QQ:On("PLAYER_ENTERING_WORLD", function() mapDirty = true end)

-- distance and direction (radians, counter clockwise from north) from the player to a zone position
function QQ:GetVector(uiMapID, x, y)
	local px, py, pInstance = self:GetPlayerPosition()
	if not px then return nil end
	local tx, ty, tInstance = self:ZoneToWorld(uiMapID, x, y)
	if not tx or tInstance ~= pInstance then return nil end
	local dx, dy = tx - px, ty - py
	local dist = sqrt(dx * dx + dy * dy)
	local angle = atan2(-dx, dy)
	if angle > 0 then angle = PI2 - angle else angle = -angle end
	return dist, angle, dx, dy
end

function QQ:IsSameInstance(uiMapID)
	local _, _, instance = self:GetPlayerPosition()
	local d = maps[uiMapID]
	return d and instance and d.instance == instance
end
