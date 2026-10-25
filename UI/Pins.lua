-- QuickQuest
-- Waypoints on the world map and the minimap

local _, QQ = ...

local maps = QQ.maps
local ipairs, wipe = ipairs, wipe
local sin, cos, sqrt = math.sin, math.cos, math.sqrt

---------------------------------------------------------------------------
-- world map
---------------------------------------------------------------------------
local worldPins = {}

local function WorldPin(i)
	local p = worldPins[i]
	if p then return p end
	p = CreateFrame("Frame", nil, WorldMapButton)
	p:SetWidth(20)
	p:SetHeight(20)
	p.tex = p:CreateTexture(nil, "OVERLAY")
	p.tex:SetAllPoints()
	p.tex:SetTexture(QQ.media .. "Pin")
	p.num = QQ:Text(p, "OVERLAY", -2, "CENTER")
	p.num:SetPoint("CENTER", 0, 0)
	p:EnableMouse(true)
	p:SetScript("OnEnter", function(self)
		local e = self.e
		if not e then return end
		WorldMapTooltip:SetOwner(self, "ANCHOR_RIGHT")
		WorldMapTooltip:AddLine(QQ.title)
		local step = e.step
		if step then WorldMapTooltip:AddLine("Step " .. step.index, 1, 1, 1) end
		for _, other in ipairs(step and step.elements or {}) do
			if other.text then WorldMapTooltip:AddLine(other.text:gsub("|T.-|t", ""), 0.85, 0.85, 0.85, true) end
		end
		WorldMapTooltip:Show()
	end)
	p:SetScript("OnLeave", function() WorldMapTooltip:Hide() end)
	worldPins[i] = p
	return p
end

local function UpdateWorldMap()
	for _, p in ipairs(worldPins) do p:Hide() end
	if not QQ.db or not QQ.db.pins.worldMap or not WorldMapFrame:IsShown() then return end
	local shown = QQ.DisplayedUiMap()
	if not shown then return end
	local w, h = WorldMapButton:GetWidth(), WorldMapButton:GetHeight()
	local current = QQ:GetWaypoint()
	local n = 0
	for _, e in ipairs(QQ.waypoints) do
		local x, y
		if e.zone == shown then
			x, y = e.x, e.y
		else
			-- waypoint of another zone shown on its continent map
			local wx, wy, instance = QQ:ZoneToWorld(e.zone, e.x, e.y)
			local d = maps[shown]
			if wx and d and d.instance == instance then
				x, y = QQ:WorldToZone(shown, wx, wy)
				if x and (x < 0 or x > 1 or y < 0 or y > 1) then x = nil end
			end
		end
		if x then
			n = n + 1
			local p = WorldPin(n)
			p.e = e
			p:ClearAllPoints()
			p:SetPoint("CENTER", WorldMapButton, "TOPLEFT", x * w, -y * h)
			p:SetFrameLevel(WorldMapButton:GetFrameLevel() + 10)
			local c = QQ:GetTheme().accent
			if e == current then
				p.tex:SetVertexColor(1, 0.82, 0)
				p:SetWidth(24) p:SetHeight(24)
			elseif e.reached then
				p.tex:SetVertexColor(0.5, 0.5, 0.5)
				p:SetWidth(16) p:SetHeight(16)
			else
				p.tex:SetVertexColor(c[1], c[2], c[3])
				p:SetWidth(20) p:SetHeight(20)
			end
			p.num:SetText(e.step and e.step.index or "")
			p:Show()
		end
	end
end
QQ.UpdateWorldPins = UpdateWorldMap

QQ:On("WORLD_MAP_UPDATE", UpdateWorldMap)
QQ:On("QQ_WAYPOINTS_CHANGED", UpdateWorldMap)
QQ:On("QQ_WAYPOINT_REACHED", UpdateWorldMap)
QQ:On("QQ_INIT", function()
	WorldMapFrame:HookScript("OnShow", UpdateWorldMap)
end)

---------------------------------------------------------------------------
-- minimap
---------------------------------------------------------------------------
-- minimap diameter in yards per zoom level (3.3.5)
local MINIMAP_SIZE = {
	indoor = { [0] = 300, [1] = 240, [2] = 180, [3] = 120, [4] = 80, [5] = 50 },
	outdoor = { [0] = 466 + 2 / 3, [1] = 400, [2] = 333 + 1 / 3, [3] = 266 + 2 / 3, [4] = 200, [5] = 133 + 1 / 3 },
}

local miniPins = {}
local function MiniPin(i)
	local p = miniPins[i]
	if p then return p end
	p = CreateFrame("Frame", nil, Minimap)
	p:SetWidth(12)
	p:SetHeight(12)
	p:SetFrameStrata(Minimap:GetFrameStrata())
	p:SetFrameLevel(Minimap:GetFrameLevel() + 5)
	p.tex = p:CreateTexture(nil, "OVERLAY")
	p.tex:SetAllPoints()
	p.tex:SetTexture(QQ.media .. "Dot")
	miniPins[i] = p
	return p
end

local indoors
local function IsIndoors()
	-- the zoom cvar only follows the outdoor minimap
	local zoom = Minimap:GetZoom()
	local cvar = tonumber(GetCVar("minimapZoom") or "")
	if not cvar then
		indoors = false
	elseif cvar == zoom then
		Minimap:SetZoom(zoom < 2 and zoom + 1 or zoom - 1)
		indoors = tonumber(GetCVar("minimapZoom") or "") == Minimap:GetZoom()
		Minimap:SetZoom(zoom)
	else
		indoors = true
	end
	return indoors
end
QQ:On("MINIMAP_UPDATE_ZOOM", function() indoors = nil end)
QQ:On("ZONE_CHANGED_INDOORS", function() indoors = nil end)
QQ:On("ZONE_CHANGED", function() indoors = nil end)

local function UpdateMinimap()
	for _, p in ipairs(miniPins) do p:Hide() end
	if not QQ.db or not QQ.db.pins.minimap then return end
	local px, py, instance = QQ:GetPlayerPosition()
	if not px then return end
	if indoors == nil then IsIndoors() end
	local zoom = Minimap:GetZoom()
	local diameter = (indoors and MINIMAP_SIZE.indoor or MINIMAP_SIZE.outdoor)[zoom] or 300
	local radius = diameter / 2
	local mw, mh = Minimap:GetWidth() / 2, Minimap:GetHeight() / 2
	local rotate = GetCVar("rotateMinimap") == "1"
	local facing = rotate and (GetPlayerFacing() or 0) or 0
	local current = QQ:GetWaypoint()
	local n = 0
	for _, e in ipairs(QQ.waypoints) do
		if not e.reached or e == current then
			local wx, wy, inst = QQ:ZoneToWorld(e.zone, e.x, e.y)
			if wx and inst == instance then
				-- x: west, y: north
				local east, north = px - wx, wy - py
				if rotate then
					local s, c = sin(facing), cos(facing)
					east, north = east * c - north * s, east * s + north * c
				end
				local dist = sqrt(east * east + north * north)
				local edge = dist > radius
				if edge then
					east, north = east / dist * radius, north / dist * radius
				end
				n = n + 1
				local p = MiniPin(n)
				p:ClearAllPoints()
				p:SetPoint("CENTER", Minimap, "CENTER", east / radius * mw, north / radius * mh)
				if e == current then
					p.tex:SetVertexColor(1, 0.82, 0)
					p:SetWidth(edge and 10 or 14) p:SetHeight(edge and 10 or 14)
				else
					local c = QQ:GetTheme().accent
					p.tex:SetVertexColor(c[1], c[2], c[3])
					p:SetWidth(edge and 7 or 10) p:SetHeight(edge and 7 or 10)
				end
				p:SetAlpha(edge and 0.6 or 1)
				p:Show()
				if n >= 8 then break end
			end
		end
	end
end

QQ:On("QQ_LOGIN", function()
	QQ:Every(0.1, UpdateMinimap)
end)
