local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Packages = ReplicatedStorage.Packages
local Knit = require(Packages.Knit)
local Trove = require(Packages.Trove)
local Signal = require(Packages.Signal)
local Input = require(Packages.Input)

local CustomPackages = ReplicatedStorage.CustomPackages
local CatmullRomSpline = require(CustomPackages.Splines.CatmullRomSpline)

local LANE_COUNT = 3
local LANE_SPACING = 10
local TRACK_LENGTH = 50000
local TRACK_HEIGHT = 3
local TRACK_START_Z = 50
local SPLINE_TENSION = 0.5

local CURVE_SEGMENTS = 220
local CURVE_AMPLITUDE = 70

local ELEVATION_PROFILE = {
	{ 0.00,   3 },   -- start flat
	{ 0.06,   3 },   -- flat run-up
	{ 0.10,  30 },   -- steep climb
	{ 0.14,  35 },   -- crest
	{ 0.17,   5 },   -- steep drop-off
	{ 0.22,   3 },   -- valley floor
	{ 0.28,   3 },   -- flat stretch
	{ 0.32,  20 },   -- moderate climb
	{ 0.36,  22 },   -- gentle ridge
	{ 0.39,  10 },   -- moderate descent
	{ 0.42,   3 },   -- valley
	{ 0.46,   3 },   -- flat
	{ 0.50,  50 },   -- big steep climb
	{ 0.54,  55 },   -- tall crest
	{ 0.56,   8 },   -- sharp cliff drop
	{ 0.60,   3 },   -- valley floor
	{ 0.65,   3 },   -- flat stretch
	{ 0.68,  15 },   -- rolling hill up
	{ 0.71,  18 },   -- small crest
	{ 0.73,   5 },   -- dip down
	{ 0.76,  25 },   -- quick climb
	{ 0.78,  28 },   -- crest
	{ 0.80,   3 },   -- steep drop
	{ 0.85,   3 },   -- flat approach
	{ 0.88,  40 },   -- final steep ramp
	{ 0.91,  45 },   -- high point
	{ 0.93,   5 },   -- big drop
	{ 0.96,   3 },   -- flat finish
	{ 1.00,   3 },   -- end flat
}

local MOVE_SPEED = 80
local BOOST_ACCEL = 120
local MAX_SPEED = 350
local LANE_SWITCH_SPEED = 8

local MAX_BANK_ANGLE = math.rad(12)
local BANK_SMOOTH_SPEED = 14
local LANE_SWITCH_BANK = math.rad(10)

local BOOST_LENGTH = 0.008
local BOOST_ZONES = {}
do
	local boostLanes = {1, 3, 2}
	local boostSections = {
		{from = 0.01, to = 0.33, gap = 0.012},
		{from = 0.33, to = 0.66, gap = 0.009},
		{from = 0.66, to = 0.99, gap = 0.006},
	}
	local idx = 1
	for _, sec in ipairs(boostSections) do
		local t = sec.from
		while t < sec.to do
			table.insert(BOOST_ZONES, {
				lane = boostLanes[((idx - 1) % 3) + 1],
				tStart = math.floor(t * 1000 + 0.5) / 1000,
			})
			t = t + sec.gap
			idx = idx + 1
		end
	end
end

local MAX_HEALTH = 100
local HAZARD_DAMAGE = 25
local HAZARD_HIT_COOLDOWN = 0.5
local HAZARD_SIZE = 0.0015

local HAZARDS = {}
do
	local hazLanes = {2, 1, 3}
	local hazSections = {
		{from = 0.005, to = 0.33, gap = 0.006},
		{from = 0.333, to = 0.66, gap = 0.004},
		{from = 0.663, to = 0.99, gap = 0.003},
	}
	local idx = 1
	for _, sec in ipairs(hazSections) do
		local t = sec.from
		while t < sec.to do
			local lane = hazLanes[((idx - 1) % 3) + 1]
			local tRound = math.floor(t * 1000 + 0.5) / 1000
			table.insert(HAZARDS, {lane = lane, t = tRound})
			t = t + sec.gap
			idx = idx + 1
		end
	end
end

local COIN_VALUE = 50
local COIN_SIZE = 0.0008

local COINS = {}
do
	local coinLanes = {1, 2, 3}
	local coinSections = {
		{from = 0.01,  to = 0.33, gap = 0.004},
		{from = 0.33,  to = 0.66, gap = 0.003},
		{from = 0.66,  to = 0.99, gap = 0.0025},
	}

	local hazardSet = {}
	for _, h in ipairs(HAZARDS) do
		hazardSet[h.lane .. "_" .. h.t] = true
	end
	local boostSet = {}
	for _, b in ipairs(BOOST_ZONES) do
		boostSet[b.lane .. "_" .. b.tStart] = true
	end

	local idx = 1
	for _, sec in ipairs(coinSections) do
		local t = sec.from
		while t < sec.to do
			local lane = coinLanes[((idx - 1) % 3) + 1]
			local tRound = math.floor(t * 10000 + 0.5) / 10000

			local overlaps = false
			for _, h in ipairs(HAZARDS) do
				if h.lane == lane and math.abs(h.t - tRound) < 0.003 then
					overlaps = true
					break
				end
			end
			if not overlaps then
				for _, b in ipairs(BOOST_ZONES) do
					if b.lane == lane and tRound >= b.tStart and tRound <= b.tStart + BOOST_LENGTH then
						overlaps = true
						break
					end
				end
			end

			if not overlaps then
				table.insert(COINS, {lane = lane, t = tRound, collected = false})
			end
			t = t + sec.gap
			idx = idx + 1
		end
	end
end

local TRACK_ZONES = {
	{
		from = 0.00, to = 0.16,
		roadColor = Color3.fromRGB(25, 28, 42),
		roadMat = Enum.Material.SmoothPlastic,
		roadAlpha = 0,
		accent = Color3.fromRGB(50, 140, 255),
	},
	{
		from = 0.16, to = 0.32,
		roadColor = Color3.fromRGB(35, 65, 85),
		roadMat = Enum.Material.Glass,
		roadAlpha = 0.3,
		accent = Color3.fromRGB(0, 210, 255),
	},
	{
		from = 0.32, to = 0.48,
		roadColor = Color3.fromRGB(55, 55, 65),
		roadMat = Enum.Material.DiamondPlate,
		roadAlpha = 0,
		accent = Color3.fromRGB(190, 200, 225),
	},
	{
		from = 0.48, to = 0.64,
		roadColor = Color3.fromRGB(18, 10, 35),
		roadMat = Enum.Material.SmoothPlastic,
		roadAlpha = 0,
		accent = Color3.fromRGB(170, 50, 255),
	},
	{
		from = 0.64, to = 0.80,
		roadColor = Color3.fromRGB(12, 38, 30),
		roadMat = Enum.Material.Glass,
		roadAlpha = 0.25,
		accent = Color3.fromRGB(0, 255, 170),
	},
	{
		from = 0.80, to = 1.00,
		roadColor = Color3.fromRGB(45, 15, 10),
		roadMat = Enum.Material.Neon,
		roadAlpha = 0.15,
		accent = Color3.fromRGB(255, 60, 40),
	},
}

local function getTrackZone(t)
	for _, z in ipairs(TRACK_ZONES) do
		if t >= z.from and t < z.to then return z end
	end
	return TRACK_ZONES[#TRACK_ZONES]
end

local function lerpColor(a, b, alpha)
	return Color3.new(
		a.R + (b.R - a.R) * alpha,
		a.G + (b.G - a.G) * alpha,
		a.B + (b.B - a.B) * alpha
	)
end

local LakelandRaceController = Knit.CreateController({
	Name = "LakelandRaceController",

	_trove = nil,
	_splines = {},
	_currentLane = 2,
	_targetLane = 2,
	_laneBlend = 0,
	_t = 0,
	_currentSpeed = MOVE_SPEED,
	_running = false,
	_boosting = false,
	_renderConn = nil,
	_inputTrove = nil,
	_currentRoll = 0,
	_lastXPos = 0,
	_switchDir = 0,
	_health = MAX_HEALTH,
	_hitCooldown = 0,
	_totalDistance = 0,
	_laneEntryT = 0,
	_lastEffectiveLane = 2,
	_lastCFrame = CFrame.new(),
	_countdownDrive = false,
	_boostVisuals = nil,
	_hazardVisuals = nil,
	_coinVisuals = nil,
	_coinParts = {},
	_coinBaseCFs = {},
	_coinScore = 0,
	_coinsCollected = 0,
	_coinSpinConn = nil,
	_railParts = {},
	_railColor = Color3.fromRGB(50, 140, 255),
	_railColorConn = nil,

	LaneChanged = Signal.new(),
	RaceProgress = Signal.new(),
	BoostChanged = Signal.new(),
	SpeedChanged = Signal.new(),
	HealthChanged = Signal.new(),
	HazardHit = Signal.new(),
	CoinCollected = Signal.new(),
})

function LakelandRaceController:KnitInit()
	self._trove = Trove.new()
	self._inputTrove = Trove.new()
	self._trove:Add(self._inputTrove)
end

function LakelandRaceController:KnitStart()
	self:_buildSplines()

	self:_setObstacleVisibility(false)

	local gameController = Knit.GetController("LakelandGameController")
	gameController.GameStateChanged:Connect(function(newState)
		if newState == "COUNTDOWN" then
			self:_setObstacleVisibility(false)
			self:PositionAtStart()
		elseif newState == "PLAYING" then
			self:_setObstacleVisibility(true)
			self:StartRace()
		elseif newState == "GAME_OVER" or newState == "MENU" then
			self:StopRace()
		end
	end)
end

function LakelandRaceController:_buildSplines()
	self._splines = {}

	local laneOffsets = {}
	for i = 1, LANE_COUNT do
		local offset = (i - math.ceil(LANE_COUNT / 2)) * LANE_SPACING
		table.insert(laneOffsets, offset)
	end

	local function sampleElevation(frac)
		local profile = ELEVATION_PROFILE
		if frac <= profile[1][1] then return profile[1][2] end
		if frac >= profile[#profile][1] then return profile[#profile][2] end

		for k = 1, #profile - 1 do
			if frac >= profile[k][1] and frac <= profile[k + 1][1] then
				local t = (frac - profile[k][1]) / (profile[k + 1][1] - profile[k][1])
				t = t * t * (3 - 2 * t)
				return profile[k][2] + (profile[k + 1][2] - profile[k][2]) * t
			end
		end
		return TRACK_HEIGHT
	end

	local centerPoints = {}
	local segmentLen = TRACK_LENGTH / CURVE_SEGMENTS
	for i = 0, CURVE_SEGMENTS do
		local frac = i / CURVE_SEGMENTS
		local z = TRACK_START_Z - i * segmentLen
		local x = math.sin(i * math.pi / 2.5) * CURVE_AMPLITUDE
		local y = sampleElevation(frac)
		table.insert(centerPoints, Vector3.new(x, y, z))
	end

	local buffer = segmentLen
	local firstDir = (centerPoints[2] - centerPoints[1]).Unit
	local lastDir = (centerPoints[#centerPoints] - centerPoints[#centerPoints - 1]).Unit
	table.insert(centerPoints, 1, centerPoints[1] + firstDir * -buffer)
	table.insert(centerPoints, centerPoints[#centerPoints] + lastDir * buffer)

	local function getTangent(pts, idx)
		local prev = pts[math.max(1, idx - 1)]
		local nxt = pts[math.min(#pts, idx + 1)]
		local dir = nxt - prev
		if dir.Magnitude < 0.001 then
			return Vector3.new(0, 0, -1)
		end
		return dir.Unit
	end

	local function getPerp(tangent)
		local flat = Vector3.new(tangent.X, 0, tangent.Z)
		if flat.Magnitude < 0.001 then
			return Vector3.new(1, 0, 0)
		end
		flat = flat.Unit
		return Vector3.new(-flat.Z, 0, flat.X)
	end

	for laneIndex, laneOffset in ipairs(laneOffsets) do
		local lanePoints = {}
		for j, center in ipairs(centerPoints) do
			local tangent = getTangent(centerPoints, j)
			local perp = getPerp(tangent)
			table.insert(lanePoints, center + perp * laneOffset)
		end

		local spline = CatmullRomSpline.new(lanePoints, SPLINE_TENSION)
		self._splines[laneIndex] = {
			spline = spline,
			offsetX = laneOffset,
		}
	end

	print("[LakelandRaceController] Built " .. #self._splines .. " lane splines with " .. (CURVE_SEGMENTS + 3) .. " control points each")

	task.spawn(function()
		self:_visualizeLanes()
	end)
end

function LakelandRaceController:_visualizeLanes()
	local existingVis = Workspace:FindFirstChild("LaneVisualization")
	if existingVis then existingVis:Destroy() end

	local folder = Instance.new("Folder")
	folder.Name = "LaneVisualization"
	folder.Parent = Workspace
	self._trove:Add(folder)

	local centerSpline = self._splines[2].spline
	local leftSpline = self._splines[1].spline
	local rightSpline = self._splines[3].spline

	local ROAD_SEGS = 600
	local RAIL_SEGS = 900
	local LANE_SEGS = 1200
	local MARKER_EVERY = 50
	local ROAD_HALF_W = LANE_SPACING * 1.5
	local ROAD_W = ROAD_HALF_W * 2

	self._railParts = {}
	local getZone = getTrackZone

	-- Road surface (wide panels, lower res is fine)
	for s = 0, ROAD_SEGS - 1 do
		if s % 200 == 0 and s > 0 then task.wait() end
		local t0 = s / ROAD_SEGS
		local t1 = (s + 1) / ROAD_SEGS
		local zone = getZone((t0 + t1) / 2)

		local posA = centerSpline:CalculatePositionAt(t0)
		local posB = centerSpline:CalculatePositionAt(t1)
		local mid = (posA + posB) / 2
		local dir = posB - posA
		local segLen = dir.Magnitude

		if segLen > 0.01 then
			local road = Instance.new("Part")
			road.Size = Vector3.new(ROAD_W + 2, 0.25, segLen + 0.5)
			road.CFrame = CFrame.lookAt(
				mid - Vector3.new(0, 0.15, 0),
				mid - Vector3.new(0, 0.15, 0) + dir.Unit
			)
			road.Anchored = true
			road.CanCollide = false
			road.Color = zone.roadColor
			road.Material = zone.roadMat
			road.Transparency = zone.roadAlpha
			road.Parent = folder
		end
	end

	-- Edge neon rails + marker posts (medium res)
	for _, side in ipairs({
		{ spline = leftSpline, sign = -1 },
		{ spline = rightSpline, sign = 1 },
	}) do
		for s = 0, RAIL_SEGS - 1 do
			if s % 200 == 0 and s > 0 then task.wait() end
			local t0 = s / RAIL_SEGS
			local t1 = (s + 1) / RAIL_SEGS
			local zone = getZone((t0 + t1) / 2)

			local posA = side.spline:CalculatePositionAt(t0)
			local posB = side.spline:CalculatePositionAt(t1)
			local mid = (posA + posB) / 2
			local dir = posB - posA
			local segLen = dir.Magnitude

			if segLen > 0.01 then
				local lookCF = CFrame.lookAt(mid, mid + dir.Unit)
				local outward = lookCF.RightVector * side.sign
				local railPos = mid + outward * (LANE_SPACING * 0.5)

				local rail = Instance.new("Part")
				rail.Size = Vector3.new(0.5, 0.5, segLen + 0.4)
				rail.CFrame = CFrame.lookAt(
					railPos + Vector3.new(0, 0.25, 0),
					railPos + Vector3.new(0, 0.25, 0) + dir.Unit
				)
				rail.Anchored = true
				rail.CanCollide = false
				rail.Color = zone.accent
				rail.Material = Enum.Material.Neon
				rail.Parent = folder
				table.insert(self._railParts, rail)
			end

			if s % MARKER_EVERY == 0 then
				local posM = side.spline:CalculatePositionAt(t0)
				local dirM = side.spline:CalculateDerivativeAt(t0)
				local mZone = getZone(t0)
				if dirM.Magnitude > 0.001 then
					local lookM = CFrame.lookAt(posM, posM + dirM)
					local outM = lookM.RightVector * side.sign
					local mPos = posM + outM * (LANE_SPACING * 0.5 + 0.6)

					local post = Instance.new("Part")
					post.Size = Vector3.new(0.2, 2.5, 0.2)
					post.CFrame = CFrame.new(mPos + Vector3.new(0, 1.25, 0))
					post.Anchored = true
					post.CanCollide = false
					post.Color = mZone.accent
					post.Material = Enum.Material.Neon
					post.Transparency = 0.15
					post.Parent = folder
					table.insert(self._railParts, post)
				end
			end
		end
	end

	-- Lane center lines (highest res — thin lines show faceting most)
	for _, laneData in ipairs(self._splines) do
		local spline = laneData.spline
		for s = 0, LANE_SEGS - 1 do
			if s % 300 == 0 and s > 0 then task.wait() end
			local t0 = s / LANE_SEGS
			local t1 = (s + 1) / LANE_SEGS
			local zone = getZone((t0 + t1) / 2)

			local posA = spline:CalculatePositionAt(t0)
			local posB = spline:CalculatePositionAt(t1)
			local mid = (posA + posB) / 2
			local dir = posB - posA
			local segLen = dir.Magnitude

			if segLen > 0.01 then
				local line = Instance.new("Part")
				line.Size = Vector3.new(0.35, 0.1, segLen + 0.25)
				line.CFrame = CFrame.lookAt(
					mid + Vector3.new(0, 0.01, 0),
					mid + Vector3.new(0, 0.01, 0) + dir.Unit
				)
				line.Anchored = true
				line.CanCollide = false
				line.Color = zone.accent
				line.Material = Enum.Material.Neon
				line.Transparency = 0.25
				line.Parent = folder
			end
		end
	end

	-- Zone transition lines (bright strip across the road at each zone boundary)
	for _, zone in ipairs(TRACK_ZONES) do
		if zone.from > 0.001 then
			local pos = centerSpline:CalculatePositionAt(zone.from)
			local dir = centerSpline:CalculateDerivativeAt(zone.from)
			if dir.Magnitude > 0.001 then
				local cf = CFrame.lookAt(pos, pos + dir)
				local trans = Instance.new("Part")
				trans.Size = Vector3.new(ROAD_W + 1, 0.15, 0.4)
				trans.CFrame = cf + Vector3.new(0, 0.05, 0)
				trans.Anchored = true
				trans.CanCollide = false
				trans.Color = zone.accent
				trans.Material = Enum.Material.Neon
				trans.Transparency = 0.1
				trans.Parent = folder
			end
		end
	end

	-- Start gate
	do
		local sT = 0.001
		local sPos = centerSpline:CalculatePositionAt(sT)
		local sDir = centerSpline:CalculateDerivativeAt(sT)
		if sDir.Magnitude > 0.001 then
			local sCF = CFrame.lookAt(sPos, sPos + sDir)

			local sLine = Instance.new("Part")
			sLine.Size = Vector3.new(ROAD_W, 0.12, 2)
			sLine.CFrame = sCF + Vector3.new(0, 0.02, 0)
			sLine.Anchored = true
			sLine.CanCollide = false
			sLine.Color = Color3.fromRGB(255, 255, 255)
			sLine.Material = Enum.Material.Neon
			sLine.Transparency = 0.1
			sLine.Parent = folder

			for _, sv in ipairs({ -1, 1 }) do
				local pPos = sPos + sCF.RightVector * sv * (ROAD_HALF_W + 0.5)
				local gatePost = Instance.new("Part")
				gatePost.Size = Vector3.new(0.5, 7, 0.5)
				gatePost.CFrame = CFrame.new(pPos + Vector3.new(0, 3.5, 0))
				gatePost.Anchored = true
				gatePost.CanCollide = false
				gatePost.Color = Color3.fromRGB(255, 255, 255)
				gatePost.Material = Enum.Material.Neon
				gatePost.Transparency = 0.1
				gatePost.Parent = folder
			end

			local beam = Instance.new("Part")
			beam.Size = Vector3.new(ROAD_W + 1, 0.4, 0.4)
			beam.CFrame = sCF * CFrame.new(0, 7, 0)
			beam.Anchored = true
			beam.CanCollide = false
			beam.Color = Color3.fromRGB(255, 255, 255)
			beam.Material = Enum.Material.Neon
			beam.Transparency = 0.1
			beam.Parent = folder
		end
	end

	-- Finish gate
	do
		local fT = 0.998
		local fPos = centerSpline:CalculatePositionAt(fT)
		local fDir = centerSpline:CalculateDerivativeAt(fT)
		if fDir.Magnitude > 0.001 then
			local fCF = CFrame.lookAt(fPos, fPos + fDir)

			local fLine = Instance.new("Part")
			fLine.Size = Vector3.new(ROAD_W, 0.12, 2)
			fLine.CFrame = fCF + Vector3.new(0, 0.02, 0)
			fLine.Anchored = true
			fLine.CanCollide = false
			fLine.Color = Color3.fromRGB(255, 215, 40)
			fLine.Material = Enum.Material.Neon
			fLine.Transparency = 0.1
			fLine.Parent = folder

			for _, sv in ipairs({ -1, 1 }) do
				local pPos = fPos + fCF.RightVector * sv * (ROAD_HALF_W + 0.5)
				local gatePost = Instance.new("Part")
				gatePost.Size = Vector3.new(0.5, 7, 0.5)
				gatePost.CFrame = CFrame.new(pPos + Vector3.new(0, 3.5, 0))
				gatePost.Anchored = true
				gatePost.CanCollide = false
				gatePost.Color = Color3.fromRGB(255, 215, 40)
				gatePost.Material = Enum.Material.Neon
				gatePost.Transparency = 0.1
				gatePost.Parent = folder
			end

			local beam = Instance.new("Part")
			beam.Size = Vector3.new(ROAD_W + 1, 0.4, 0.4)
			beam.CFrame = fCF * CFrame.new(0, 7, 0)
			beam.Anchored = true
			beam.CanCollide = false
			beam.Color = Color3.fromRGB(255, 215, 40)
			beam.Material = Enum.Material.Neon
			beam.Transparency = 0.1
			beam.Parent = folder
		end
	end

	-- Rail color tween: rails shift to bronze / silver / gold based on score vs leaderboard
	local RAIL_COLOR_DEFAULT = Color3.fromRGB(70, 90, 120)
	local RAIL_COLOR_BRONZE = Color3.fromRGB(205, 127, 50)
	local RAIL_COLOR_SILVER = Color3.fromRGB(192, 192, 210)
	local RAIL_COLOR_GOLD   = Color3.fromRGB(255, 215, 0)
	if self._railColorConn then
		self._railColorConn:Disconnect()
	end
	self._railColor = RAIL_COLOR_DEFAULT
	self._railColorConn = RunService.Heartbeat:Connect(function(dt)
		if not self._running and not self._countdownDrive then return end
		local gameController = Knit.GetController("LakelandGameController")
		local entries = gameController._topScores:get()
		local score1 = (entries[1] and entries[1].score) or 0
		local score2 = (entries[2] and entries[2].score) or 0
		local score3 = (entries[3] and entries[3].score) or 0
		local myScore = math.floor(self._totalDistance * 10) + self._coinScore
		local targetColor
		if myScore >= score1 and score1 > 0 then
			targetColor = RAIL_COLOR_GOLD
		elseif myScore >= score2 and score2 > 0 then
			targetColor = RAIL_COLOR_SILVER
		elseif myScore >= score3 and score3 > 0 then
			targetColor = RAIL_COLOR_BRONZE
		else
			targetColor = RAIL_COLOR_DEFAULT
		end
		self._railColor = lerpColor(self._railColor, targetColor, math.min(dt * 5, 1))
		local c = self._railColor
		for _, part in ipairs(self._railParts) do
			if part and part.Parent then
				part.Color = c
			end
		end
	end)
	self._trove:Add(self._railColorConn)

	task.wait()
	self:_visualizeBoostZones(folder)
	task.wait()
	self:_visualizeHazards(folder)
	task.wait()
	self:_visualizeCoins(folder)

	print("[LakelandRaceController] Track visualization created (" .. #self._railParts .. " dynamic rail parts)")
end

function LakelandRaceController:_visualizeBoostZones(folder)
	local BOOST_SEGMENTS = 18
	local BOOST_WIDTH = LANE_SPACING * 0.7
	local C_PAD     = Color3.fromRGB(255, 175, 0)
	local C_CHEVRON = Color3.fromRGB(255, 240, 120)
	local C_EDGE    = Color3.fromRGB(255, 120, 0)

	local boostFolder = Instance.new("Folder")
	boostFolder.Name = "BoostVisuals"
	boostFolder.Parent = folder
	self._boostVisuals = boostFolder

	for bIdx, zone in ipairs(BOOST_ZONES) do
		if bIdx % 25 == 0 then task.wait() end
		local spline = self._splines[zone.lane].spline
		local tEnd = zone.tStart + BOOST_LENGTH

		for s = 0, BOOST_SEGMENTS - 1 do
			local t0 = zone.tStart + (tEnd - zone.tStart) * (s / BOOST_SEGMENTS)
			local t1 = zone.tStart + (tEnd - zone.tStart) * ((s + 1) / BOOST_SEGMENTS)

			local posA = spline:CalculatePositionAt(t0)
			local posB = spline:CalculatePositionAt(t1)
			local mid = (posA + posB) / 2
			local dir = posB - posA
			local segLen = dir.Magnitude

			if segLen > 0.01 then
				local lookCF = CFrame.lookAt(mid, mid + dir.Unit)

				local panel = Instance.new("Part")
				panel.Name = "BoostPad"
				panel.Size = Vector3.new(BOOST_WIDTH, 0.12, segLen + 0.15)
				panel.CFrame = CFrame.lookAt(
					mid + Vector3.new(0, 0.03, 0),
					mid + Vector3.new(0, 0.03, 0) + dir.Unit
				)
				panel.Anchored = true
				panel.CanCollide = false
				panel.Color = C_PAD
				panel.Material = Enum.Material.Neon
				panel.Transparency = 0.15
				panel.Parent = boostFolder

				-- Edge accent strips follow the curve per-segment
				for _, edgeSign in ipairs({ -1, 1 }) do
					local offset = lookCF.RightVector * edgeSign * (BOOST_WIDTH * 0.5)
					local strip = Instance.new("Part")
					strip.Name = "BoostEdge"
					strip.Size = Vector3.new(0.25, 0.18, segLen + 0.15)
					strip.CFrame = CFrame.lookAt(
						mid + offset + Vector3.new(0, 0.06, 0),
						mid + offset + Vector3.new(0, 0.06, 0) + dir.Unit
					)
					strip.Anchored = true
					strip.CanCollide = false
					strip.Color = C_EDGE
					strip.Material = Enum.Material.Neon
					strip.Transparency = 0.1
					strip.Parent = boostFolder
				end
			end
		end

		-- Directional chevron arrows on the pad
		local CHEV_COUNT = 3
		for c = 0, CHEV_COUNT - 1 do
			local chevT = zone.tStart + (tEnd - zone.tStart) * ((c + 0.5) / CHEV_COUNT)
			local chevPos = spline:CalculatePositionAt(chevT)
			local chevDir = spline:CalculateDerivativeAt(chevT)
			if chevDir.Magnitude > 0.001 then
				local chevron = Instance.new("Part")
				chevron.Name = "BoostChevron"
				chevron.Size = Vector3.new(BOOST_WIDTH * 0.4, 0.16, 0.5)
				chevron.CFrame = CFrame.lookAt(
					chevPos + Vector3.new(0, 0.1, 0),
					chevPos + Vector3.new(0, 0.1, 0) + chevDir
				)
				chevron.Anchored = true
				chevron.CanCollide = false
				chevron.Color = C_CHEVRON
				chevron.Material = Enum.Material.Neon
				chevron.Transparency = 0.05
				chevron.Parent = boostFolder
			end
		end
	end

	print("[LakelandRaceController] Visualized " .. #BOOST_ZONES .. " boost zones")
end

function LakelandRaceController:_visualizeHazards(folder)
	local BOX_SIZE = Vector3.new(4, 4, 4)
	local C_CORE = Color3.fromRGB(180, 30, 30)
	local C_GLOW = Color3.fromRGB(255, 50, 20)
	local C_WARN = Color3.fromRGB(255, 190, 0)

	local hazardFolder = Instance.new("Folder")
	hazardFolder.Name = "HazardVisuals"
	hazardFolder.Parent = folder
	self._hazardVisuals = hazardFolder

	for i, hazard in ipairs(HAZARDS) do
		if i % 50 == 0 then task.wait() end
		local spline = self._splines[hazard.lane].spline
		local pos = spline:CalculatePositionAt(hazard.t)
		local dir = spline:CalculateDerivativeAt(hazard.t)
		if dir.Magnitude < 0.001 then
			dir = Vector3.new(0, 0, -1)
		end

		local baseCF = CFrame.lookAt(
			pos + Vector3.new(0, BOX_SIZE.Y / 2, 0),
			pos + Vector3.new(0, BOX_SIZE.Y / 2, 0) + dir
		)

		local box = Instance.new("Part")
		box.Name = "Hazard_" .. i
		box.Size = BOX_SIZE
		box.CFrame = baseCF
		box.Anchored = true
		box.CanCollide = false
		box.Color = C_CORE
		box.Material = Enum.Material.SmoothPlastic
		box.Parent = hazardFolder

		local glowFrame = Instance.new("Part")
		glowFrame.Name = "HazardGlow_" .. i
		glowFrame.Size = BOX_SIZE + Vector3.new(0.4, 0.4, 0.4)
		glowFrame.CFrame = baseCF
		glowFrame.Anchored = true
		glowFrame.CanCollide = false
		glowFrame.Color = C_GLOW
		glowFrame.Material = Enum.Material.Neon
		glowFrame.Transparency = 0.65
		glowFrame.Parent = hazardFolder

		local stripe = Instance.new("Part")
		stripe.Name = "HazardStripe_" .. i
		stripe.Size = Vector3.new(BOX_SIZE.X + 0.1, 0.8, BOX_SIZE.Z + 0.1)
		stripe.CFrame = baseCF * CFrame.new(0, 0.8, 0)
		stripe.Anchored = true
		stripe.CanCollide = false
		stripe.Color = C_WARN
		stripe.Material = Enum.Material.Neon
		stripe.Transparency = 0.1
		stripe.Parent = hazardFolder
	end

	print("[LakelandRaceController] Visualized " .. #HAZARDS .. " hazards")
end

function LakelandRaceController:_visualizeCoins(folder)
	local prefabsFolder = ReplicatedStorage:FindFirstChild("Prefabs")
	local coinPrefab = nil
	if prefabsFolder then
		for _, child in ipairs(prefabsFolder:GetChildren()) do
			if child:HasTag("coin") then
				coinPrefab = child
				break
			end
		end
	end
	if not coinPrefab then
		warn("[LakelandRaceController] No coin prefab found in ReplicatedStorage.Prefabs (tagged 'coin')")
		return
	end

	local coinFolder = Instance.new("Folder")
	coinFolder.Name = "CoinVisuals"
	coinFolder.Parent = folder
	self._coinVisuals = coinFolder
	self._coinParts = {}
	self._coinBasePositions = {}

	for i, coin in ipairs(COINS) do
		local spline = self._splines[coin.lane].spline
		local pos = spline:CalculatePositionAt(coin.t)
		local dir = spline:CalculateDerivativeAt(coin.t)
		if dir.Magnitude < 0.001 then
			dir = Vector3.new(0, 0, -1)
		end

		local coinPos = pos + Vector3.new(0, 3, 0)

		local clone = coinPrefab:Clone()
		clone.Name = "Coin_" .. i

		if clone:IsA("Model") then
			clone:PivotTo(CFrame.new(coinPos) * CFrame.Angles(math.rad(90), 0, 0))
			for _, desc in ipairs(clone:GetDescendants()) do
				if desc:IsA("BasePart") then
					desc.Anchored = true
					desc.CanCollide = false
				end
			end
			clone.Parent = coinFolder
			self._coinParts[i] = clone
		end

		self._coinBasePositions[i] = coinPos
	end

	print("[LakelandRaceController] Coin count: " .. #self._coinParts)

	-- Tween spin and bob using CFrame (single tween property to avoid conflicts)
	local BOB_HEIGHT = 2
	local BOB_TIME = 0.6
	local HALF_SPIN_TIME = 2

	self._coinTweenThreads = {}

	for i, model in ipairs(self._coinParts) do
		if model and model:IsA("Model") and model.PrimaryPart then
			local pp = model.PrimaryPart
			local basePos = self._coinBasePositions[i]
			-- baseRot = just the rotation from the current CFrame (includes the 90-degree tilt)
			local baseRot = pp.CFrame - pp.CFrame.Position

			-- Combined spin + bob using chained CFrame tweens
			local spinThread = task.spawn(function()
				local angle = 0
				while pp and pp.Parent do
					-- Tween to +BOB_HEIGHT and +180 degrees (world Y spin, then tilt)
					angle = angle + 180
					local upCF = CFrame.new(basePos + Vector3.new(0, BOB_HEIGHT, 0)) * CFrame.Angles(0, math.rad(angle), 0) * baseRot
					local upInfo = TweenInfo.new(BOB_TIME / 2, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)
					local upTween = TweenService:Create(pp, upInfo, { CFrame = upCF })
					upTween:Play()
					upTween.Completed:Wait()

					-- Tween back down and +180 more degrees (world Y spin, then tilt)
					angle = angle + 180
					local downCF = CFrame.new(basePos) * CFrame.Angles(0, math.rad(angle), 0) * baseRot
					local downInfo = TweenInfo.new(BOB_TIME / 2, Enum.EasingStyle.Sine, Enum.EasingDirection.In)
					local downTween = TweenService:Create(pp, downInfo, { CFrame = downCF })
					downTween:Play()
					downTween.Completed:Wait()
				end
			end)

			table.insert(self._coinTweenThreads, spinThread)
			self._trove:Add(function()
				task.cancel(spinThread)
			end)
		end
	end

	print("[LakelandRaceController] Visualized " .. #COINS .. " coins (prefab)")
end

function LakelandRaceController:_setObstacleVisibility(show)
	if self._boostVisuals then
		for _, part in ipairs(self._boostVisuals:GetChildren()) do
			if part:IsA("BasePart") then
				local name = part.Name
				if name == "BoostChevron" then
					part.Transparency = show and 0.05 or 1
				elseif name == "BoostEdge" then
					part.Transparency = show and 0.1 or 1
				else
					part.Transparency = show and 0.15 or 1
				end
			end
		end
	end
	if self._hazardVisuals then
		for _, part in ipairs(self._hazardVisuals:GetChildren()) do
			if part:IsA("BasePart") then
				if part.Name:find("Glow") then
					part.Transparency = show and 0.65 or 1
				elseif part.Name:find("Stripe") then
					part.Transparency = show and 0.1 or 1
				else
					part.Transparency = show and 0 or 1
				end
			end
		end
	end
	if self._coinVisuals then
		for i, model in ipairs(self._coinParts) do
			if model and model.Parent then
				local coin = COINS[i]
				if coin and not coin.collected then
					for _, desc in ipairs(model:GetDescendants()) do
						if desc:IsA("BasePart") then
							desc.Transparency = show and 0 or 1
						end
					end
				end
			end
		end
	end
end

function LakelandRaceController:PositionAtStart()
	self._currentLane = 2
	self._targetLane = 2
	self._laneBlend = 0
	self._t = 0
	self._currentSpeed = MOVE_SPEED
	self._boosting = false
	self._currentRoll = 0
	self._lastXPos = 0
	self._switchDir = 0
	self._health = MAX_HEALTH
	self._hitCooldown = 0
	self._totalDistance = 0
	self._laneEntryT = 0
	self._lastEffectiveLane = 2
	self._countdownDrive = true
	self._coinScore = 0
	self._coinsCollected = 0

	for i, coin in ipairs(COINS) do
		coin.collected = false
		local model = self._coinParts[i]
		if model and model.Parent then
			for _, desc in ipairs(model:GetDescendants()) do
				if desc:IsA("BasePart") then
					desc.Transparency = 1
				end
			end
		end
	end

	task.spawn(function()
		local machine = Workspace:WaitForChild("ActiveMachine", 5)
		if not machine then
			warn("[LakelandRaceController] ActiveMachine not found for positioning")
			return
		end

		local spline = self._splines[2].spline
		local pos = spline:CalculatePositionAt(0)
		local dir = spline:CalculateDerivativeAt(0)
		if dir.Magnitude < 0.001 then
			dir = Vector3.new(0, 0, -1)
		end
		dir = dir.Unit

		local startCF = CFrame.lookAt(pos, pos + dir)
		machine:PivotTo(startCF)
		self._lastCFrame = startCF

		self:_startRenderLoop()
		print("[LakelandRaceController] Machine positioned at spline start — countdown drive active")
	end)
end

function LakelandRaceController:StartRace()
	if self._running then return end
	self._running = true
	self._countdownDrive = false
	self._laneEntryT = self._t

	self:_bindInput()

	if not self._renderConn then
		self:_startRenderLoop()
	end

	print("[LakelandRaceController] Race started on lane " .. self._currentLane .. " at t=" .. string.format("%.4f", self._t))
end

function LakelandRaceController:StopRace()
	self._running = false
	self._countdownDrive = false

	self._inputTrove:Clean()

	if self._renderConn then
		RunService:UnbindFromRenderStep("LakelandMachineUpdate")
		self._renderConn = nil
	end

	print("[LakelandRaceController] Race stopped")
end

function LakelandRaceController:_bindInput()
	self._inputTrove:Clean()

	self._inputTrove:Add(UserInputService.InputBegan:Connect(function(input, processed)
		if processed then return end

		if input.KeyCode == Enum.KeyCode.A or input.KeyCode == Enum.KeyCode.Left then
			self:SwitchLane(-1)
		elseif input.KeyCode == Enum.KeyCode.D or input.KeyCode == Enum.KeyCode.Right then
			self:SwitchLane(1)
		end
	end), "Disconnect")

	if UserInputService.GamepadEnabled then
		self._inputTrove:Add(UserInputService.InputChanged:Connect(function(input)
			if input.KeyCode == Enum.KeyCode.Thumbstick1 then
				local x = input.Position.X
				if x > 0.5 and self._targetLane < LANE_COUNT then
					self:SwitchLane(1)
				elseif x < -0.5 and self._targetLane > 1 then
					self:SwitchLane(-1)
				end
			end
		end), "Disconnect")
	end
end

function LakelandRaceController:SwitchLane(direction)
	local newLane = math.clamp(self._targetLane + direction, 1, LANE_COUNT)
	if newLane == self._targetLane then return end

	if self._laneBlend > 0 then
		self._currentLane = self._targetLane
	end

	self._laneBlend = 0
	self._targetLane = newLane
	self._switchDir = direction
	self.LaneChanged:Fire(self._targetLane)
end

function LakelandRaceController:_startRenderLoop()
	if self._renderConn then
		RunService:UnbindFromRenderStep("LakelandMachineUpdate")
		self._renderConn = nil
	end

	RunService:BindToRenderStep("LakelandMachineUpdate", Enum.RenderPriority.Camera.Value - 1, function(dt)
		if not self._running and not self._countdownDrive then return end
		self:_updateMovement(dt)
	end)
	self._renderConn = true

	self._trove:Add(function()
		if self._renderConn then
			RunService:UnbindFromRenderStep("LakelandMachineUpdate")
			self._renderConn = nil
		end
	end)
end

function LakelandRaceController:_getEffectiveLane()
	if self._laneBlend < 0.5 then
		return self._currentLane
	end
	return self._targetLane
end

function LakelandRaceController:_isInBoostZone()
	local lane = self:_getEffectiveLane()
	for _, zone in ipairs(BOOST_ZONES) do
		if zone.lane == lane and self._t >= zone.tStart and self._t <= zone.tStart + BOOST_LENGTH then
			return true
		end
	end
	return false
end

function LakelandRaceController:_isInHazard()
	local lane = self:_getEffectiveLane()
	for _, hazard in ipairs(HAZARDS) do
		if hazard.lane == lane and hazard.t >= self._laneEntryT and self._t >= hazard.t and self._t <= hazard.t + HAZARD_SIZE then
			return true
		end
	end
	return false
end

function LakelandRaceController:_checkCoinCollection()
	local lane = self:_getEffectiveLane()
	for i, coin in ipairs(COINS) do
		if not coin.collected and coin.lane == lane and self._t >= coin.t and self._t <= coin.t + COIN_SIZE then
			coin.collected = true
			self._coinScore = self._coinScore + COIN_VALUE
			self._coinsCollected = self._coinsCollected + 1

			local model = self._coinParts[i]
			if model and model.Parent then
				for _, desc in ipairs(model:GetDescendants()) do
					if desc:IsA("BasePart") then
						desc.Transparency = 1
					end
				end
			end

			self.CoinCollected:Fire(self._coinScore, self._coinsCollected)
		end
	end
end

function LakelandRaceController:_updateMovement(dt)
	local machine = Workspace:FindFirstChild("ActiveMachine")
	if not machine or not machine.PrimaryPart then return end

	if not self._countdownDrive then
		if self._hitCooldown > 0 then
			self._hitCooldown = self._hitCooldown - dt
		end

		local inBoost = self:_isInBoostZone()
		if inBoost ~= self._boosting then
			self._boosting = inBoost
			self.BoostChanged:Fire(inBoost)
		end

		if inBoost then
			self._currentSpeed = math.min(self._currentSpeed + BOOST_ACCEL * dt, MAX_SPEED)
		end

		if self._hitCooldown <= 0 and self:_isInHazard() then
			self._health = math.max(self._health - HAZARD_DAMAGE, 0)
			self._hitCooldown = HAZARD_HIT_COOLDOWN
			self.HealthChanged:Fire(self._health)
			self.HazardHit:Fire(self._health)
		end

		self:_checkCoinCollection()
		self.SpeedChanged:Fire(self._currentSpeed)
	end

	local tDelta = (self._currentSpeed / TRACK_LENGTH) * dt
	if not self._countdownDrive then
		self._totalDistance = self._totalDistance + self._currentSpeed * dt
	end
	self._t = self._t + tDelta
	if self._t > 1 then
		self._t = self._t - 1
	end

	if not self._countdownDrive then
		self._laneBlend = self._laneBlend + LANE_SWITCH_SPEED * dt
		if self._laneBlend >= 1 then
			self._laneBlend = 0
			self._currentLane = self._targetLane
		end

		local effectiveLane = self:_getEffectiveLane()
		if effectiveLane ~= self._lastEffectiveLane then
			self._laneEntryT = self._t
			self._lastEffectiveLane = effectiveLane
		end
	end

	local currentSpline = self._splines[self._currentLane].spline
	local targetSpline = self._splines[self._targetLane].spline

	local currentPos = currentSpline:CalculatePositionAt(self._t)
	local targetPos = targetSpline:CalculatePositionAt(self._t)
	local finalPos = currentPos:Lerp(targetPos, self._laneBlend)

	local currentDir = currentSpline:CalculateDerivativeAt(self._t)
	local targetDir = targetSpline:CalculateDerivativeAt(self._t)
	local dir = currentDir:Lerp(targetDir, self._laneBlend)

	if dir.Magnitude < 0.001 then
		dir = Vector3.new(0, 0, -1)
	end
	dir = dir.Unit

	local lateralDelta = finalPos.X - self._lastXPos
	self._lastXPos = finalPos.X

	local curvatureBank = 0
	if dt > 0 then
		local lateralSpeed = lateralDelta / dt
		local speedFrac = self._currentSpeed / MAX_SPEED
		curvatureBank = math.clamp(-lateralSpeed * 0.008 * (0.5 + speedFrac), -MAX_BANK_ANGLE, MAX_BANK_ANGLE)
	end

	local switchBank = 0
	if self._currentLane ~= self._targetLane then
		local blend = math.sin(self._laneBlend * math.pi)
		switchBank = -self._switchDir * LANE_SWITCH_BANK * blend
	end

	local targetRoll = curvatureBank + switchBank
	targetRoll = math.clamp(targetRoll, -MAX_BANK_ANGLE, MAX_BANK_ANGLE)
	self._currentRoll = self._currentRoll + (targetRoll - self._currentRoll) * math.min(BANK_SMOOTH_SPEED * dt, 1)

	local lookTarget = finalPos + dir
	local baseCF = CFrame.lookAt(finalPos, lookTarget)
	local finalCF = baseCF * CFrame.Angles(0, 0, self._currentRoll)
	machine:PivotTo(finalCF)
	self._lastCFrame = finalCF

	self.RaceProgress:Fire(self._t)
end

function LakelandRaceController:GetProgress()
	return self._t
end

function LakelandRaceController:GetCurrentLane()
	return self._currentLane
end

function LakelandRaceController:GetCurrentSpeed()
	return self._currentSpeed
end

function LakelandRaceController:GetMachineCFrame()
	return self._lastCFrame
end

function LakelandRaceController:GetMaxSpeed()
	return MAX_SPEED
end

function LakelandRaceController:IsBoosting()
	return self._boosting
end

function LakelandRaceController:GetHealth()
	return self._health
end

function LakelandRaceController:GetMaxHealth()
	return MAX_HEALTH
end

function LakelandRaceController:GetDistance()
	return self._totalDistance
end

function LakelandRaceController:GetTrackLength()
	return TRACK_LENGTH
end

function LakelandRaceController:GetCoinScore()
	return self._coinScore
end

function LakelandRaceController:GetCoinsCollected()
	return self._coinsCollected
end

return LakelandRaceController
