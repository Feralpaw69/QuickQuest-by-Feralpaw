-- QuickQuest
-- Direction arrow to the current waypoint

local _, QQ = ...

local Arrow = {}
QQ.Arrow = Arrow

local frame
local PI2 = math.pi * 2
local fmt = string.format
local abs = math.abs

QQ.arrowStyles = {
	{ key = "classic", name = "Classic", file = QQ.media .. "Arrow" },
	{ key = "blade", name = "Blade", file = QQ.media .. "Arrow-Blade" },
	{ key = "chevron", name = "Chevrons", file = QQ.media .. "Arrow-Chevron" },
	{ key = "gem", name = "Crystal", file = QQ.media .. "Arrow-Gem" },
	{ key = "spear", name = "Spear", file = QQ.media .. "Arrow-Spear" },
	{ key = "compass", name = "Compass", file = QQ.media .. "Arrow-Compass" },
}

QQ.arrowColors = {
	{ key = "direction", name = "Direction: green > yellow > red" },
	{ key = "frost", name = "Direction: blue > purple > red" },
	{ key = "distance", name = "Distance: red far > green near" },
	{ key = "theme", name = "Theme colour" },
	{ key = "gold", name = "Gold" },
	{ key = "white", name = "White" },
	{ key = "custom", name = "Custom colour" },
}

local function Find(list, key)
	for _, v in ipairs(list) do if v.key == key then return v end end
	return list[1]
end

local function Lerp(a, b, t)
	return a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t, a[3] + (b[3] - a[3]) * t
end

-- three colour scale: t = 0 .. 1
local function Scale(c1, c2, c3, t)
	if t < 0.5 then return Lerp(c1, c2, t * 2) end
	return Lerp(c2, c3, (t - 0.5) * 2)
end

local GREEN, YELLOW, RED = { 0.2, 1, 0.2 }, { 1, 1, 0.2 }, { 1, 0.15, 0.15 }
local BLUE, PURPLE = { 0.3, 0.75, 1 }, { 0.75, 0.35, 1 }

-- colour of the arrow (rel: angle to the waypoint, 0 = ahead)
local function ArrowColor(rel, dist, arrived)
	local mode = QQ.db.arrow.colors
	if mode == "theme" then local c = QQ:GetTheme().accent return c[1], c[2], c[3] end
	if mode == "gold" then return 1, 0.82, 0 end
	if mode == "white" then return 1, 1, 1 end
	if mode == "custom" then local c = QQ.db.arrow.color return c[1], c[2], c[3] end
	if arrived then return GREEN[1], GREEN[2], GREEN[3] end
	if mode == "distance" then
		local t = math.min(1, (dist or 0) / 500)
		return Scale(GREEN, YELLOW, RED, t)
	end
	local d = rel
	if d > math.pi then d = PI2 - d end -- 0 (ahead) .. pi (behind)
	local t = d / math.pi
	if mode == "frost" then return Scale(BLUE, PURPLE, RED, t) end
	return Scale(GREEN, YELLOW, RED, t)
end

local function OnUpdate(self, elapsed)
	self.t = (self.t or 0) + elapsed
	if self.t < 0.03 then return end
	self.t = 0
	local nav = QQ.nav
	local e = nav.waypoint
	if not e or not nav.dist then
		self.arrow:Hide()
		self.dist:SetText(e and "|cffaaaaaa" .. (QQ:ZoneName(e.zone) or "") .. "|r" or "")
		self.label:SetText("")
		return
	end
	self.arrow:Show()
	local dist = nav.dist
	local facing = GetPlayerFacing() or 0
	local rel = (nav.angle - facing) % PI2
	if dist <= (e.radius or 10) then
		self.arrow:SetRotation(0)
		self.arrow:SetVertexColor(ArrowColor(0, dist, true))
	else
		self.arrow:SetRotation(rel)
		self.arrow:SetVertexColor(ArrowColor(rel, dist))
	end
	self.dist:SetText(fmt("%d yd", dist))
	local step = e.step
	local text = e.text
	if not text and step then
		for _, other in ipairs(step.elements) do
			if other.text and other.kind ~= "goto" then text = other.text break end
		end
	end
	self.label:SetText(text and text:gsub("|T.-|t", ""):sub(1, 80) or "")
end

local function Create()
	frame = CreateFrame("Button", "QuickQuestArrow", UIParent)
	frame:SetWidth(56)
	frame:SetHeight(56)
	frame:SetFrameStrata("MEDIUM")
	frame:SetScale(QQ.db.arrow.scale or 1)
	QQ:LoadPosition(frame, QQ.db.arrow.point)
	QQ:MakeDraggable(frame, frame, QQ.db.arrow.point)
	frame:RegisterForClicks("RightButtonUp")
	frame:SetScript("OnClick", function() QQ:SkipWaypoint() end)
	frame:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
		GameTooltip:AddLine(QQ.title)
		local e = QQ.nav.waypoint
		if e then GameTooltip:AddLine(fmt("%s (%.1f, %.1f)", QQ:ZoneName(e.zone) or "", e.x * 100, e.y * 100), 1, 1, 1) end
		GameTooltip:AddLine("Drag to move, right-click to skip the waypoint", 0.7, 0.7, 0.7)
		GameTooltip:Show()
	end)
	frame:SetScript("OnLeave", GameTooltip_Hide)

	frame.arrow = frame:CreateTexture(nil, "ARTWORK")
	frame.arrow:SetTexture(QQ.media .. "Arrow")
	frame.arrow:SetAllPoints()

	frame.dist = QQ:Text(frame, "OVERLAY", 1, "CENTER")
	frame.dist:SetPoint("TOP", frame, "BOTTOM", 0, -1)
	frame.label = QQ:Text(frame, "OVERLAY", -1, "CENTER", 0.85)
	frame.label:SetPoint("TOP", frame.dist, "BOTTOM", 0, -2)
	frame.label:SetWidth(220)

	frame:SetScript("OnUpdate", OnUpdate)
	Arrow.frame = frame
	Arrow:Refresh()
end

function Arrow:Refresh()
	if not frame then return end
	frame:SetScale(QQ.db.arrow.scale or 1)
	frame.arrow:SetTexture(Find(QQ.arrowStyles, QQ.db.arrow.style).file)
	local show = QQ.db.arrow.enabled and QQ.guide and QQ.nav.waypoint and not QQ.db.general.hidden
	if show then frame:Show() else frame:Hide() end
end

QQ:On("QQ_INIT", Create)
QQ:On("QQ_WAYPOINTS_CHANGED", function() QQ:After(0.15, function() Arrow:Refresh() end) end)
QQ:On("QQ_WINDOW_TOGGLED", function() Arrow:Refresh() end)
QQ:On("QQ_POSITIONS_RESET", function() if frame then QQ:LoadPosition(frame, QQ.db.arrow.point) end end)
