-- QuickQuest
-- Waypoints of the active steps: which one the arrow points to, arrival

local _, QQ = ...

local ipairs, tinsert, wipe = ipairs, table.insert, wipe
local ARRIVAL = 10 -- yards, for waypoints without a radius

local list = {} -- waypoints of the active steps (in display order)
QQ.waypoints = list

local function IsWaypoint(e)
	return (e.kind == "goto" or e.kind == "groundgoto" or e.kind == "waypoint") and e.zone and e.x
end

local function Rebuild()
	wipe(list)
	local active = QQ.active
	-- main step first, its waypoints are the ones to follow
	for i = #active, 1, -1 do
		local step = active[i]
		for _, e in ipairs(step.elements) do
			if IsWaypoint(e) then tinsert(list, e) end
		end
	end
	QQ:Fire("QQ_WAYPOINTS_CHANGED")
end
QQ:On("QQ_STEPS_CHANGED", Rebuild)
QQ:On("QQ_GUIDE_LOADED", function() wipe(list) end)

-- the waypoint the arrow shows: first one of the main step that is not reached yet
function QQ:GetWaypoint()
	local first
	for _, e in ipairs(list) do
		if not e.reached then return e end
		first = first or e
	end
	-- every waypoint reached: looped routes start again, otherwise keep the last one
	local main = self.active[#self.active]
	if main and main.loop and first then
		for _, e in ipairs(list) do
			if e.step == main then e.reached = nil end
		end
		return first
	end
	return list[#list]
end

-- called by the arrow / map updates with the distance to the shown waypoint
function QQ:CheckArrival(e, dist)
	if not e or not dist or e.reached then return end
	local radius = e.radius or ARRIVAL
	if dist <= radius then
		e.reached = true
		local step = e.step
		-- waypoint only steps are done when their last waypoint is reached
		self:RequestUpdate()
		self:Fire("QQ_WAYPOINT_REACHED", e)
	end
end

function QQ:SkipWaypoint()
	local e = self:GetWaypoint()
	if e then
		e.reached = true
		self:RequestUpdate()
		self:Fire("QQ_WAYPOINT_REACHED", e)
	end
end

-- distance / direction to the current waypoint, refreshed for the arrow
QQ.nav = {}
QQ:On("QQ_LOGIN", function()
	QQ:Every(0.1, function()
		local nav = QQ.nav
		local e = QQ:GetWaypoint()
		nav.waypoint = e
		if not e then nav.dist = nil return end
		local dist, angle = QQ:GetVector(e.zone, e.x, e.y)
		nav.dist, nav.angle = dist, angle
		if dist then QQ:CheckArrival(e, dist) end
	end)
end)
