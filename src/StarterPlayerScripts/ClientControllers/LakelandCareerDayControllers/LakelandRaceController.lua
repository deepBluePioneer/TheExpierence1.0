local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local Lighting = game:GetService("Lighting")

local Packages = ReplicatedStorage.Packages
local Knit = require(Packages.Knit)
local Trove = require(Packages.Trove)
local Signal = require(Packages.Signal)
local Input = require(Packages.Input)

local CustomPackages = ReplicatedStorage.CustomPackages
local CatmullRomSpline = require(CustomPackages.Splines.CatmullRomSpline)

local LANE_COUNT = 3
local LANE_SPACING = 10
local TRACK_LENGTH = 20000
local TRACK_HEIGHT = 3
local TRACK_START_Z = 50
local SPLINE_TENSION = 0.5

local CURVE_SEGMENTS = 100
local CURVE_AMPLITUDE = 70

local ELEVATION_PROFILE = {
	{ 0.00,   3 },
	{ 0.06,   3 },
	{ 0.10,  30 },
	{ 0.14,  35 },
	{ 0.17,   5 },
	{ 0.22,   3 },
	{ 0.28,   3 },
	{ 0.32,  20 },
	{ 0.36,  22 },
	{ 0.39,  10 },
	{ 0.42,   3 },
	{ 0.46,   3 },
	{ 0.50,  50 },
	{ 0.54,  55 },
	{ 0.56,   8 },
	{ 0.60,   3 },
	{ 0.65,   3 },
	{ 0.68,  15 },
	{ 0.71,  18 },
	{ 0.73,   5 },
	{ 0.76,  25 },
	{ 0.78,  28 },
	{ 0.80,   3 },
	{ 0.85,   3 },
	{ 0.88,  40 },
	{ 0.91,  45 },
	{ 0.93,   5 },
	{ 0.96,   3 },
	{ 1.00,   3 },
}

local MOVE_SPEED = 80
local BOOST_ACCEL = 35
local MAX_SPEED = 350
local LAUNCH_ACCEL = 160
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
local HAZARD_HIT_COOLDOWN = 1.5
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
local BOOST_POINTS_PER_SEC = 30

local COINS = {}
do
	local coinLanes = {1, 2, 3}
	local coinSections = {
		{from = 0.01, to = 0.99, gap = 0.0015},
	}

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
		roadColor = Color3.fromRGB(5, 5, 10),
		roadMat = Enum.Material.Glass,
		roadAlpha = 0.05,
		accent = Color3.fromRGB(50, 140, 255),
	},
	{
		from = 0.16, to = 0.32,
		roadColor = Color3.fromRGB(5, 5, 10),
		roadMat = Enum.Material.Glass,
		roadAlpha = 0.05,
		accent = Color3.fromRGB(0, 210, 255),
	},
	{
		from = 0.32, to = 0.48,
		roadColor = Color3.fromRGB(5, 5, 10),
		roadMat = Enum.Material.Glass,
		roadAlpha = 0.05,
		accent = Color3.fromRGB(190, 200, 225),
	},
	{
		from = 0.48, to = 0.64,
		roadColor = Color3.fromRGB(5, 5, 10),
		roadMat = Enum.Material.Glass,
		roadAlpha = 0.05,
		accent = Color3.fromRGB(170, 50, 255),
	},
	{
		from = 0.64, to = 0.80,
		roadColor = Color3.fromRGB(5, 5, 10),
		roadMat = Enum.Material.Glass,
		roadAlpha = 0.05,
		accent = Color3.fromRGB(0, 255, 170),
	},
	{
		from = 0.80, to = 1.00,
		roadColor = Color3.fromRGB(5, 5, 10),
		roadMat = Enum.Material.Glass,
		roadAlpha = 0.05,
		accent = Color3.fromRGB(255, 60, 40),
	},
}

local function getTrackZone(t)
	for _, z in ipairs(TRACK_ZONES) do
		if t >= z.from and t < z.to then return z end
	end
	return TRACK_ZONES[#TRACK_ZONES]
end

---------------------------------------------------------------------------
-- Treadmill constants
---------------------------------------------------------------------------
local FIXED_MACHINE_POS = Vector3.new(0, TRACK_HEIGHT + 5, 0)
local WINDOW_AHEAD  = 0.015
local WINDOW_BEHIND = 0.005

local ROAD_HALF_W = LANE_SPACING * 1.5
local ROAD_W      = ROAD_HALF_W * 2

local ROAD_T_STEP    = 0.0015
local LANE_T_STEP    = 0.00075
local LIGHT_T_STEP   = 0.005
local STREAK_T_STEP  = 0.002

local ROAD_POOL       = 25
local LANE_POOL       = 120
local LIGHT_POOL      = 10
local STREAK_POOL     = 100
local HAZARD_POOL     = 20
local COIN_POOL       = 30
local BOOST_PAD_POOL  = 35
local BOOST_EDGE_POOL = 70
local BOOST_CHEV_POOL = 18

local BOOST_VIS_SEGS  = 6
local BOOST_VIS_WIDTH = LANE_SPACING * 0.7

local TUNNEL_RADIUS    = 22
local STREAK_THICKNESS = 0.2
local STREAK_HEIGHT    = 0.15
local STREAK_LINES     = 10
local STREAK_ARCH_START = math.rad(-10)
local STREAK_ARCH_END   = math.rad(190)
local STREAK_ARCH_SPAN  = STREAK_ARCH_END - STREAK_ARCH_START

local STREAK_COLORS = {
	Color3.fromRGB(50, 140, 255),
	Color3.fromRGB(0, 255, 200),
	Color3.fromRGB(170, 50, 255),
	Color3.fromRGB(255, 60, 100),
	Color3.fromRGB(0, 210, 255),
	Color3.fromRGB(255, 180, 40),
	Color3.fromRGB(80, 255, 80),
	Color3.fromRGB(255, 100, 255),
	Color3.fromRGB(100, 200, 255),
	Color3.fromRGB(255, 60, 40),
}

local STREAK_PATTERNS = {
	{ gap = 2, duty = 0.8 },
	{ gap = 3, duty = 0.6 },
	{ gap = 4, duty = 0.5 },
	{ gap = 2, duty = 1.0 },
	{ gap = 5, duty = 0.4 },
	{ gap = 3, duty = 0.7 },
	{ gap = 6, duty = 0.3 },
	{ gap = 2, duty = 0.9 },
	{ gap = 4, duty = 0.6 },
	{ gap = 3, duty = 1.0 },
}

local RW_COUNT         = 10
local RW_SPACING_STUDS = 20
local RW_SIDE_OFFSET   = ROAD_HALF_W + 3
local RW_BAR_HEIGHT    = 4
local RW_BAR_WIDTH     = 1.5
local RW_BAR_DEPTH     = 0.6
local RW_OFF_COLOR     = Color3.fromRGB(5, 10, 25)
local RW_ON_COLOR      = Color3.fromRGB(80, 200, 255)
local RW_CHASE_SPEED   = 12
local RW_FADE_TAIL     = 3
local RW_DIM_FLOOR     = 0.08

---------------------------------------------------------------------------
-- Controller
---------------------------------------------------------------------------
local LakelandRaceController = Knit.CreateController({
	Name = "LakelandRaceController",

	_trove = nil,
	_splines = {},
	_currentLane = 2,
	_targetLane = 2,
	_laneBlend = 0,
	_t = 0,
	_currentSpeed = 0,
	_running = false,
	_launching = false,
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
	_coinScore = 0,
	_coinsCollected = 0,
	_boostScore = 0,
	_currentBoostTally = 0,

	_pools = {},
	_folder = nil,
	_obstaclesVisible = false,
	_rwLights = {},
	_rwElapsed = 0,
	_gateParts = {},

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

function LakelandRaceController:_setupDarkEnvironment()
	Lighting.ClockTime = 0
	Lighting.Brightness = 0
	Lighting.Ambient = Color3.fromRGB(10, 10, 18)
	Lighting.OutdoorAmbient = Color3.fromRGB(8, 8, 14)
	Lighting.FogColor = Color3.fromRGB(0, 0, 0)
	Lighting.FogEnd = 2000
	Lighting.FogStart = 200
	Lighting.GlobalShadows = true
	Lighting.EnvironmentDiffuseScale = 0
	Lighting.EnvironmentSpecularScale = 0

	local sky = Lighting:FindFirstChildOfClass("Sky")
	if sky then sky:Destroy() end

	local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
	if atmosphere then
		atmosphere.Density = 0.5
		atmosphere.Offset = 0
		atmosphere.Color = Color3.fromRGB(0, 0, 0)
		atmosphere.Decay = Color3.fromRGB(0, 0, 0)
		atmosphere.Glare = 0
		atmosphere.Haze = 0
	end
end

function LakelandRaceController:KnitStart()
	self:_setupDarkEnvironment()
	self:_buildSplines()
	self:_initPools()

	local gameController = Knit.GetController("LakelandGameController")
	gameController.GameStateChanged:Connect(function(newState)
		if newState == "COUNTDOWN" then
			self._obstaclesVisible = false
			self:PositionAtStart()
		elseif newState == "PLAYING" then
			self._obstaclesVisible = true
			self:StartRace()
		elseif newState == "GAME_OVER" or newState == "MENU" then
			self:StopRace()
		end
	end)
end

---------------------------------------------------------------------------
-- Spline construction (math only, no visuals)
---------------------------------------------------------------------------
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
		local x = math.sin(frac * 8 * 2 * math.pi) * CURVE_AMPLITUDE
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
		if dir.Magnitude < 0.001 then return Vector3.new(0, 0, -1) end
		return dir.Unit
	end

	local function getPerp(tangent)
		local flat = Vector3.new(tangent.X, 0, tangent.Z)
		if flat.Magnitude < 0.001 then return Vector3.new(1, 0, 0) end
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
		self._splines[laneIndex] = { spline = spline, offsetX = laneOffset }
	end

	print("[LakelandRaceController] Built " .. #self._splines .. " lane splines (" .. (CURVE_SEGMENTS + 3) .. " ctrl pts, " .. TRACK_LENGTH .. " studs)")
end

---------------------------------------------------------------------------
-- Pool initialization (create reusable parts once)
---------------------------------------------------------------------------
function LakelandRaceController:_initPools()
	local existing = Workspace:FindFirstChild("LaneVisualization")
	if existing then existing:Destroy() end

	local folder = Instance.new("Folder")
	folder.Name = "LaneVisualization"
	folder.Parent = Workspace
	self._trove:Add(folder)
	self._folder = folder
	self._pools = {}

	local function makePool(name, count, setup)
		local pool = {}
		for i = 1, count do
			local part = Instance.new("Part")
			part.Anchored = true
			part.CanCollide = false
			part.Transparency = 1
			part.Parent = folder
			setup(part, i)
			pool[i] = part
		end
		self._pools[name] = pool
	end

	makePool("road", ROAD_POOL, function(p)
		p.Color = Color3.fromRGB(5, 5, 10)
		p.Material = Enum.Material.Glass
	end)

	makePool("lane", LANE_POOL, function(p)
		p.Material = Enum.Material.Neon
	end)

	self._pools.light = {}
	for i = 1, LIGHT_POOL do
		local anchor = Instance.new("Part")
		anchor.Size = Vector3.new(0.5, 0.5, 0.5)
		anchor.Anchored = true
		anchor.CanCollide = false
		anchor.Transparency = 1
		anchor.Parent = folder
		local pl = Instance.new("PointLight")
		pl.Brightness = 0
		pl.Range = 60
		pl.Parent = anchor
		self._pools.light[i] = { part = anchor, light = pl }
	end

	makePool("streak", STREAK_POOL, function(p)
		p.Material = Enum.Material.Neon
	end)

	self._pools.hazard = {}
	for i = 1, HAZARD_POOL do
		local cube = Instance.new("Part")
		cube.Shape = Enum.PartType.Block
		cube.Size = Vector3.new(6, 5, 6)
		cube.Anchored = true
		cube.CanCollide = false
		cube.Color = Color3.fromRGB(255, 40, 40)
		cube.Material = Enum.Material.Neon
		cube.Transparency = 1
		cube.Parent = folder
		local hl = Instance.new("Highlight")
		hl.FillColor = Color3.fromRGB(255, 50, 50)
		hl.FillTransparency = 0.3
		hl.OutlineColor = Color3.fromRGB(255, 100, 100)
		hl.OutlineTransparency = 0
		hl.Enabled = false
		hl.Parent = cube
		self._pools.hazard[i] = cube
	end

	self._pools.coin = {}
	for i = 1, COIN_POOL do
		local cube = Instance.new("Part")
		cube.Shape = Enum.PartType.Block
		cube.Size = Vector3.new(5, 4, 5)
		cube.Anchored = true
		cube.CanCollide = false
		cube.Color = Color3.fromRGB(40, 120, 255)
		cube.Material = Enum.Material.Neon
		cube.Transparency = 1
		cube.Parent = folder
		local hl = Instance.new("Highlight")
		hl.FillColor = Color3.fromRGB(50, 140, 255)
		hl.FillTransparency = 0.3
		hl.OutlineColor = Color3.fromRGB(100, 180, 255)
		hl.OutlineTransparency = 0
		hl.Enabled = false
		hl.Parent = cube
		self._pools.coin[i] = cube
	end

	makePool("boostPad", BOOST_PAD_POOL, function(p)
		p.Color = Color3.fromRGB(255, 175, 0)
		p.Material = Enum.Material.Neon
	end)
	makePool("boostEdge", BOOST_EDGE_POOL, function(p)
		p.Color = Color3.fromRGB(255, 120, 0)
		p.Material = Enum.Material.Neon
	end)
	makePool("boostChev", BOOST_CHEV_POOL, function(p)
		p.Color = Color3.fromRGB(255, 240, 120)
		p.Material = Enum.Material.Neon
	end)

	-- Runway lights (fixed small set)
	self._rwLights = {}
	local centerSpline = self._splines[2].spline
	for i = 0, RW_COUNT - 1 do
		local rwT = (i * RW_SPACING_STUDS) / TRACK_LENGTH
		local cDir = centerSpline:CalculateDerivativeAt(rwT)
		if cDir.Magnitude < 0.001 then cDir = Vector3.new(0, 0, -1) end

		local pair = { t = rwT, entries = {} }
		for _, sign in ipairs({ -1, 1 }) do
			local bar = Instance.new("Part")
			bar.Size = Vector3.new(RW_BAR_WIDTH, RW_BAR_HEIGHT, RW_BAR_DEPTH)
			bar.Anchored = true
			bar.CanCollide = false
			bar.Color = RW_OFF_COLOR
			bar.Material = Enum.Material.Neon
			bar.Transparency = 1
			bar.Parent = folder

			local glow = Instance.new("PointLight")
			glow.Color = RW_ON_COLOR
			glow.Brightness = 0
			glow.Range = 30
			glow.Parent = bar

			local pad = Instance.new("Part")
			pad.Size = Vector3.new(3, 0.15, 3)
			pad.Anchored = true
			pad.CanCollide = false
			pad.Color = RW_OFF_COLOR
			pad.Material = Enum.Material.Neon
			pad.Transparency = 1
			pad.Parent = folder

			table.insert(pair.entries, { bar = bar, light = glow, pad = pad, sign = sign })
		end
		table.insert(self._rwLights, pair)
	end

	-- Start / finish gate parts
	self._gateParts = {}
	for _, gateInfo in ipairs({
		{ name = "start", t = 0.001, color = Color3.fromRGB(255, 255, 255) },
		{ name = "finish", t = 0.998, color = Color3.fromRGB(255, 215, 40) },
	}) do
		local parts = {}
		local line = Instance.new("Part")
		line.Size = Vector3.new(ROAD_W, 0.12, 2)
		line.Anchored = true
		line.CanCollide = false
		line.Color = gateInfo.color
		line.Material = Enum.Material.Neon
		line.Transparency = 1
		line.Parent = folder
		parts.line = line

		parts.posts = {}
		for _, sv in ipairs({ -1, 1 }) do
			local post = Instance.new("Part")
			post.Size = Vector3.new(0.5, 7, 0.5)
			post.Anchored = true
			post.CanCollide = false
			post.Color = gateInfo.color
			post.Material = Enum.Material.Neon
			post.Transparency = 1
			post.Parent = folder
			table.insert(parts.posts, { part = post, sign = sv })
		end

		local beam = Instance.new("Part")
		beam.Size = Vector3.new(ROAD_W + 1, 0.4, 0.4)
		beam.Anchored = true
		beam.CanCollide = false
		beam.Color = gateInfo.color
		beam.Material = Enum.Material.Neon
		beam.Transparency = 1
		beam.Parent = folder
		parts.beam = beam
		parts.t = gateInfo.t

		self._gateParts[gateInfo.name] = parts
	end

	-- Static ambient lights around the stationary machine
	self._machineLights = {}
	local lightConfigs = {
		{ offset = Vector3.new(0, 18, 0),   color = Color3.fromRGB(180, 200, 255), brightness = 1.2, range = 80 },
		{ offset = Vector3.new(0, 10, 0),   color = Color3.fromRGB(140, 160, 255), brightness = 0.8, range = 50 },
		{ offset = Vector3.new(-15, 8, 0),  color = Color3.fromRGB(80, 140, 255),  brightness = 0.6, range = 45 },
		{ offset = Vector3.new(15, 8, 0),   color = Color3.fromRGB(80, 140, 255),  brightness = 0.6, range = 45 },
		{ offset = Vector3.new(0, 8, 12),   color = Color3.fromRGB(120, 80, 255),  brightness = 0.5, range = 40 },
		{ offset = Vector3.new(0, 8, -12),  color = Color3.fromRGB(120, 80, 255),  brightness = 0.5, range = 40 },
		{ offset = Vector3.new(-10, 5, 10), color = Color3.fromRGB(60, 180, 255),  brightness = 0.4, range = 35 },
		{ offset = Vector3.new(10, 5, -10), color = Color3.fromRGB(60, 180, 255),  brightness = 0.4, range = 35 },
	}
	for _, cfg in ipairs(lightConfigs) do
		local anchor = Instance.new("Part")
		anchor.Size = Vector3.new(0.5, 0.5, 0.5)
		anchor.Anchored = true
		anchor.CanCollide = false
		anchor.Transparency = 1
		anchor.CFrame = CFrame.new(FIXED_MACHINE_POS + cfg.offset)
		anchor.Parent = folder
		local pl = Instance.new("PointLight")
		pl.Color = cfg.color
		pl.Brightness = cfg.brightness
		pl.Range = cfg.range
		pl.Shadows = false
		pl.Parent = anchor
		table.insert(self._machineLights, anchor)
	end

	print("[LakelandRaceController] Pools initialized — treadmill ready")
end

---------------------------------------------------------------------------
-- World scroll — repositions all pooled parts each frame
---------------------------------------------------------------------------
function LakelandRaceController:_updateWorldScroll(dt)
	local centerSpline = self._splines[2].spline
	local centerRef = centerSpline:CalculatePositionAt(self._t)

	local tMin = math.max(0, self._t - WINDOW_BEHIND)
	local tMax = math.min(1, self._t + WINDOW_AHEAD)

	local function toWorld(splinePos)
		return FIXED_MACHINE_POS + (splinePos - centerRef)
	end

	-- Road surface
	local ri = 1
	local t = tMin
	while t < tMax and ri <= ROAD_POOL do
		local t1 = math.min(t + ROAD_T_STEP, tMax)
		local posA = centerSpline:CalculatePositionAt(t)
		local posB = centerSpline:CalculatePositionAt(t1)
		local mid = (posA + posB) / 2
		local dir = posB - posA
		local segLen = dir.Magnitude
		if segLen > 0.01 then
			local wM = toWorld(mid)
			local road = self._pools.road[ri]
			road.Size = Vector3.new(ROAD_W + 2, 0.25, segLen + 0.5)
			road.CFrame = CFrame.lookAt(wM - Vector3.new(0, 0.15, 0), wM - Vector3.new(0, 0.15, 0) + dir.Unit)
			road.Transparency = 0.05
			ri = ri + 1
		end
		t = t + ROAD_T_STEP
	end
	for i = ri, ROAD_POOL do self._pools.road[i].Transparency = 1 end

	-- Lane dividers
	local li = 1
	for _, laneData in ipairs(self._splines) do
		local spline = laneData.spline
		local lt = tMin
		while lt < tMax and li <= LANE_POOL do
			local lt1 = math.min(lt + LANE_T_STEP, tMax)
			local zone = getTrackZone((lt + lt1) / 2)
			local posA = spline:CalculatePositionAt(lt)
			local posB = spline:CalculatePositionAt(lt1)
			local mid = (posA + posB) / 2
			local dir = posB - posA
			local segLen = dir.Magnitude
			if segLen > 0.01 then
				local wM = toWorld(mid)
				local line = self._pools.lane[li]
				line.Size = Vector3.new(0.35, 0.1, segLen + 0.25)
				line.CFrame = CFrame.lookAt(wM + Vector3.new(0, 0.01, 0), wM + Vector3.new(0, 0.01, 0) + dir.Unit)
				line.Color = zone.accent
				line.Transparency = 0.25
				li = li + 1
			end
			lt = lt + LANE_T_STEP
		end
	end
	for i = li, LANE_POOL do self._pools.lane[i].Transparency = 1 end

	-- Track lights
	local tli = 1
	local tlt = tMin
	while tlt < tMax and tli <= LIGHT_POOL do
		local zone = getTrackZone(tlt)
		local pos = centerSpline:CalculatePositionAt(tlt)
		local wP = toWorld(pos)
		local info = self._pools.light[tli]
		info.part.Position = wP + Vector3.new(0, 6, 0)
		info.light.Color = zone.accent
		info.light.Brightness = 0.6
		tli = tli + 1
		tlt = tlt + LIGHT_T_STEP
	end
	for i = tli, LIGHT_POOL do self._pools.light[i].light.Brightness = 0 end

	-- Tunnel streaks
	local si = 1
	local st = tMin
	local segCounter = math.floor(tMin / STREAK_T_STEP)
	while st < tMax do
		local st1 = math.min(st + STREAK_T_STEP, tMax)
		local stMid = (st + st1) / 2
		local zone = getTrackZone(stMid)
		local posA = centerSpline:CalculatePositionAt(st)
		local posB = centerSpline:CalculatePositionAt(st1)
		local mid = (posA + posB) / 2
		local dir = posB - posA
		local segLen = dir.Magnitude

		if segLen > 0.01 then
			local wM = toWorld(mid)
			local fwdCF = CFrame.lookAt(wM, wM + dir.Unit)

			for lineIdx = 1, STREAK_LINES do
				if si > STREAK_POOL then break end
				local pat = STREAK_PATTERNS[lineIdx]
				if (segCounter % pat.gap) < math.ceil(pat.gap * pat.duty) then
					local frac = (lineIdx - 1) / (STREAK_LINES - 1)
					local angle = STREAK_ARCH_START + STREAK_ARCH_SPAN * frac
					local ex = math.cos(angle) * TUNNEL_RADIUS
					local ey = math.sin(angle) * TUNNEL_RADIUS
					local baseColor = STREAK_COLORS[lineIdx]
					local blended = baseColor:Lerp(zone.accent, 0.4)

					local streak = self._pools.streak[si]
					streak.Size = Vector3.new(STREAK_THICKNESS, STREAK_HEIGHT, segLen + 0.12)
					streak.CFrame = fwdCF * CFrame.new(ex, ey, 0)
					streak.Color = blended
					streak.Transparency = 0
					si = si + 1
				end
			end
		end
		segCounter = segCounter + 1
		st = st + STREAK_T_STEP
		if si > STREAK_POOL then break end
	end
	for i = si, STREAK_POOL do self._pools.streak[i].Transparency = 1 end

	-- Hazards
	local hi = 1
	for _, hazard in ipairs(HAZARDS) do
		if hi > HAZARD_POOL then break end
		if hazard.t >= tMin and hazard.t <= tMax then
			local show = self._obstaclesVisible
			local spline = self._splines[hazard.lane].spline
			local pos = spline:CalculatePositionAt(hazard.t)
			local wP = toWorld(pos)
			local cube = self._pools.hazard[hi]
			cube.CFrame = CFrame.new(wP + Vector3.new(0, 2.25, 0))
			cube.Transparency = show and 0.15 or 1
			local hl = cube:FindFirstChildOfClass("Highlight")
			if hl then hl.Enabled = show end
			hi = hi + 1
		end
	end
	for i = hi, HAZARD_POOL do
		self._pools.hazard[i].Transparency = 1
		local hl = self._pools.hazard[i]:FindFirstChildOfClass("Highlight")
		if hl then hl.Enabled = false end
	end

	-- Coins
	local ci = 1
	for _, coin in ipairs(COINS) do
		if ci > COIN_POOL then break end
		if not coin.collected and coin.t >= tMin and coin.t <= tMax then
			local show = self._obstaclesVisible
			local spline = self._splines[coin.lane].spline
			local pos = spline:CalculatePositionAt(coin.t)
			local wP = toWorld(pos)
			local cube = self._pools.coin[ci]
			cube.CFrame = CFrame.new(wP + Vector3.new(0, 3, 0))
			cube.Transparency = show and 0.15 or 1
			local hl = cube:FindFirstChildOfClass("Highlight")
			if hl then hl.Enabled = show end
			ci = ci + 1
		end
	end
	for i = ci, COIN_POOL do
		self._pools.coin[i].Transparency = 1
		local hl = self._pools.coin[i]:FindFirstChildOfClass("Highlight")
		if hl then hl.Enabled = false end
	end

	-- Boost zones
	local pi, ei, chi = 1, 1, 1
	for _, bz in ipairs(BOOST_ZONES) do
		local tEnd = bz.tStart + BOOST_LENGTH
		if tEnd < tMin or bz.tStart > tMax then continue end
		local show = self._obstaclesVisible
		local spline = self._splines[bz.lane].spline

		for s = 0, BOOST_VIS_SEGS - 1 do
			if pi > BOOST_PAD_POOL then break end
			local bt0 = bz.tStart + (tEnd - bz.tStart) * (s / BOOST_VIS_SEGS)
			local bt1 = bz.tStart + (tEnd - bz.tStart) * ((s + 1) / BOOST_VIS_SEGS)
			local posA = spline:CalculatePositionAt(bt0)
			local posB = spline:CalculatePositionAt(bt1)
			local mid = (posA + posB) / 2
			local dir = posB - posA
			local segLen = dir.Magnitude
			if segLen < 0.01 then continue end

			local wM = toWorld(mid)
			local lookCF = CFrame.lookAt(wM, wM + dir.Unit)

			local pad = self._pools.boostPad[pi]
			pad.Size = Vector3.new(BOOST_VIS_WIDTH, 0.12, segLen + 0.15)
			pad.CFrame = CFrame.lookAt(wM + Vector3.new(0, 0.03, 0), wM + Vector3.new(0, 0.03, 0) + dir.Unit)
			pad.Transparency = show and 0.15 or 1
			pi = pi + 1

			for _, edgeSign in ipairs({ -1, 1 }) do
				if ei > BOOST_EDGE_POOL then break end
				local off = lookCF.RightVector * edgeSign * (BOOST_VIS_WIDTH * 0.5)
				local edge = self._pools.boostEdge[ei]
				edge.Size = Vector3.new(0.25, 0.18, segLen + 0.15)
				edge.CFrame = CFrame.lookAt(wM + off + Vector3.new(0, 0.06, 0), wM + off + Vector3.new(0, 0.06, 0) + dir.Unit)
				edge.Transparency = show and 0.1 or 1
				ei = ei + 1
			end
		end

		for c = 0, 2 do
			if chi > BOOST_CHEV_POOL then break end
			local chevT = bz.tStart + (tEnd - bz.tStart) * ((c + 0.5) / 3)
			local chevPos = spline:CalculatePositionAt(chevT)
			local chevDir = spline:CalculateDerivativeAt(chevT)
			if chevDir.Magnitude > 0.001 then
				local wP = toWorld(chevPos)
				local chev = self._pools.boostChev[chi]
				chev.Size = Vector3.new(BOOST_VIS_WIDTH * 0.4, 0.16, 0.5)
				chev.CFrame = CFrame.lookAt(wP + Vector3.new(0, 0.1, 0), wP + Vector3.new(0, 0.1, 0) + chevDir.Unit)
				chev.Transparency = show and 0.05 or 1
				chi = chi + 1
			end
		end
	end
	for i = pi, BOOST_PAD_POOL do self._pools.boostPad[i].Transparency = 1 end
	for i = ei, BOOST_EDGE_POOL do self._pools.boostEdge[i].Transparency = 1 end
	for i = chi, BOOST_CHEV_POOL do self._pools.boostChev[i].Transparency = 1 end

	-- Runway lights (reposition + chase animation)
	self._rwElapsed = self._rwElapsed + dt * RW_CHASE_SPEED
	local rwHead = self._rwElapsed % RW_COUNT

	for idx, pair in ipairs(self._rwLights) do
		local rwT = pair.t
		local inWindow = rwT >= tMin and rwT <= tMax
		local cPos = centerSpline:CalculatePositionAt(rwT)
		local cDir = centerSpline:CalculateDerivativeAt(rwT)
		if cDir.Magnitude < 0.001 then cDir = Vector3.new(0, 0, -1) end
		local wP = toWorld(cPos)
		local cf = CFrame.lookAt(wP, wP + cDir.Unit)

		local behind = (rwHead - (idx - 1)) % RW_COUNT
		local intensity
		if behind < 1 then intensity = 1
		elseif behind < 1 + RW_FADE_TAIL then intensity = math.max(RW_DIM_FLOOR, 1 - (behind - 1) / RW_FADE_TAIL)
		else intensity = RW_DIM_FLOOR end

		local color = RW_OFF_COLOR:Lerp(RW_ON_COLOR, intensity)
		local bright = inWindow and (intensity * 5) or 0

		for _, entry in ipairs(pair.entries) do
			local sidePos = wP + cf.RightVector * entry.sign * RW_SIDE_OFFSET
			entry.bar.CFrame = CFrame.lookAt(
				sidePos + Vector3.new(0, RW_BAR_HEIGHT * 0.5, 0),
				sidePos + Vector3.new(0, RW_BAR_HEIGHT * 0.5, 0) + cDir.Unit
			)
			entry.bar.Color = color
			entry.bar.Transparency = inWindow and 0 or 1
			entry.light.Brightness = bright
			entry.pad.CFrame = CFrame.new(sidePos + Vector3.new(0, 0.08, 0))
			entry.pad.Color = color
			entry.pad.Transparency = inWindow and 0 or 1
		end
	end

	-- Start / finish gates
	for _, gateInfo in pairs(self._gateParts) do
		local gT = gateInfo.t
		local inWin = gT >= tMin and gT <= tMax
		if inWin then
			local gPos = centerSpline:CalculatePositionAt(gT)
			local gDir = centerSpline:CalculateDerivativeAt(gT)
			if gDir.Magnitude < 0.001 then gDir = Vector3.new(0, 0, -1) end
			local wP = toWorld(gPos)
			local gCF = CFrame.lookAt(wP, wP + gDir.Unit)

			gateInfo.line.CFrame = gCF + Vector3.new(0, 0.02, 0)
			gateInfo.line.Transparency = 0.1

			for _, postInfo in ipairs(gateInfo.posts) do
				local pPos = wP + gCF.RightVector * postInfo.sign * (ROAD_HALF_W + 0.5)
				postInfo.part.CFrame = CFrame.new(pPos + Vector3.new(0, 3.5, 0))
				postInfo.part.Transparency = 0.1
			end

			gateInfo.beam.CFrame = gCF * CFrame.new(0, 7, 0)
			gateInfo.beam.Transparency = 0.1
		else
			gateInfo.line.Transparency = 1
			for _, postInfo in ipairs(gateInfo.posts) do postInfo.part.Transparency = 1 end
			gateInfo.beam.Transparency = 1
		end
	end
end

---------------------------------------------------------------------------
-- Obstacle visibility (flag checked by scroll)
---------------------------------------------------------------------------
function LakelandRaceController:_setObstacleVisibility(show)
	self._obstaclesVisible = show
end

---------------------------------------------------------------------------
-- Position at start
---------------------------------------------------------------------------
function LakelandRaceController:PositionAtStart()
	self._currentLane = 2
	self._targetLane = 2
	self._laneBlend = 0
	self._t = 0
	self._currentSpeed = 0
	self._launching = false
	self._boosting = false
	self._currentRoll = 0
	self._lastXPos = 0
	self._switchDir = 0
	self._health = MAX_HEALTH
	self._totalDistance = 0

	for _, hazard in ipairs(HAZARDS) do hazard._hit = false end
	self._laneEntryT = 0
	self._lastEffectiveLane = 2
	self._countdownDrive = true
	self._coinScore = 0
	self._coinsCollected = 0
	self._boostScore = 0
	self._currentBoostTally = 0

	for _, coin in ipairs(COINS) do coin.collected = false end

	task.spawn(function()
		local machine = Workspace:WaitForChild("ActiveMachine", 5)
		if not machine then
			warn("[LakelandRaceController] ActiveMachine not found")
			return
		end

		local dir = self._splines[2].spline:CalculateDerivativeAt(0)
		if dir.Magnitude < 0.001 then dir = Vector3.new(0, 0, -1) end
		dir = dir.Unit

		local startCF = CFrame.lookAt(FIXED_MACHINE_POS, FIXED_MACHINE_POS + dir)
		machine:PivotTo(startCF)
		self._lastCFrame = startCF

		self:_startRenderLoop()
		print("[LakelandRaceController] Machine at fixed position — ready for countdown")
	end)
end

---------------------------------------------------------------------------
-- Race start / stop
---------------------------------------------------------------------------
function LakelandRaceController:StartRace()
	if self._running then return end
	self._running = true
	self._countdownDrive = false
	self._launching = true
	self._currentSpeed = 0
	self._laneEntryT = self._t
	self:_bindInput()
	if not self._renderConn then self:_startRenderLoop() end
	print("[LakelandRaceController] LAUNCH on lane " .. self._currentLane)
end

function LakelandRaceController:StopRace()
	self._running = false
	self._countdownDrive = false
	self._launching = false

	if self._boosting then
		self._boosting = false
		self.BoostChanged:Fire(false, math.floor(self._currentBoostTally))
	end
	self._currentBoostTally = 0
	self._boostScore = 0
	self._inputTrove:Clean()

	if self._renderConn then
		RunService:UnbindFromRenderStep("LakelandMachineUpdate")
		self._renderConn = nil
	end
end

---------------------------------------------------------------------------
-- Input
---------------------------------------------------------------------------
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
	if self._laneBlend > 0 then self._currentLane = self._targetLane end
	self._laneBlend = 0
	self._targetLane = newLane
	self._switchDir = direction
	self.LaneChanged:Fire(self._targetLane)
end

---------------------------------------------------------------------------
-- Render loop
---------------------------------------------------------------------------
function LakelandRaceController:_startRenderLoop()
	if self._renderConn then
		RunService:UnbindFromRenderStep("LakelandMachineUpdate")
		self._renderConn = nil
	end

	RunService:BindToRenderStep("LakelandMachineUpdate", Enum.RenderPriority.Camera.Value - 1, function(dt)
		self:_updateWorldScroll(dt)
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

---------------------------------------------------------------------------
-- Game logic helpers (unchanged)
---------------------------------------------------------------------------
function LakelandRaceController:_getEffectiveLane()
	if self._laneBlend < 0.5 then return self._currentLane end
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

function LakelandRaceController:_getHitHazard()
	local lane = self:_getEffectiveLane()
	for _, hazard in ipairs(HAZARDS) do
		if hazard.lane == lane and hazard.t >= self._laneEntryT and self._t >= hazard.t and self._t <= hazard.t + HAZARD_SIZE then
			return hazard
		end
	end
	return nil
end

function LakelandRaceController:_checkCoinCollection()
	local lane = self:_getEffectiveLane()
	for _, coin in ipairs(COINS) do
		if not coin.collected and coin.lane == lane and self._t >= coin.t and self._t <= coin.t + COIN_SIZE then
			coin.collected = true
			self._coinScore = self._coinScore + COIN_VALUE
			self._coinsCollected = self._coinsCollected + 1
			self.CoinCollected:Fire(self._coinScore, self._coinsCollected)
		end
	end
end

---------------------------------------------------------------------------
-- Movement (treadmill: machine stays at FIXED_MACHINE_POS)
---------------------------------------------------------------------------
function LakelandRaceController:_updateMovement(dt)
	local machine = Workspace:FindFirstChild("ActiveMachine")
	if not machine or not machine.PrimaryPart then return end

	if not self._countdownDrive then
		if self._launching then
			self._currentSpeed = self._currentSpeed + LAUNCH_ACCEL * dt
			if self._currentSpeed >= MOVE_SPEED then
				self._currentSpeed = MOVE_SPEED
				self._launching = false
			end
		end

		local inBoost = self:_isInBoostZone()
		if inBoost ~= self._boosting then
			self._boosting = inBoost
			if inBoost then self._currentBoostTally = 0 end
			self.BoostChanged:Fire(inBoost, math.floor(self._currentBoostTally))
		end
		if inBoost then
			self._currentSpeed = math.min(self._currentSpeed + BOOST_ACCEL * dt, MAX_SPEED)
			self._boostScore = self._boostScore + BOOST_POINTS_PER_SEC * dt
			self._currentBoostTally = self._currentBoostTally + BOOST_POINTS_PER_SEC * dt
		end

		local hitHazard = self:_getHitHazard()
		if hitHazard and not hitHazard._hit then
			hitHazard._hit = true
			self._health = math.max(self._health - HAZARD_DAMAGE, 0)
			self.HealthChanged:Fire(self._health)
			self.HazardHit:Fire(self._health)
		end

		self:_checkCoinCollection()
		self.SpeedChanged:Fire(self._currentSpeed)
	end

	-- Advance virtual progress
	local tDelta = (self._currentSpeed / TRACK_LENGTH) * dt
	if not self._countdownDrive then
		self._totalDistance = self._totalDistance + self._currentSpeed * dt
	end
	self._t = self._t + tDelta
	if self._t > 1 then self._t = self._t - 1 end

	-- Lane blending
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

	-- Compute lane offset relative to center spline
	local centerSpline = self._splines[2].spline
	local centerPos = centerSpline:CalculatePositionAt(self._t)
	local currentLanePos = self._splines[self._currentLane].spline:CalculatePositionAt(self._t)
	local targetLanePos = self._splines[self._targetLane].spline:CalculatePositionAt(self._t)
	local lanePos = currentLanePos:Lerp(targetLanePos, self._laneBlend)
	local laneOffset = lanePos - centerPos

	-- Direction from center spline for forward orientation
	local centerDir = centerSpline:CalculateDerivativeAt(self._t)
	if centerDir.Magnitude < 0.001 then centerDir = Vector3.new(0, 0, -1) end
	centerDir = centerDir.Unit

	-- Banking
	local machineWorldPos = FIXED_MACHINE_POS + laneOffset
	local lateralDelta = machineWorldPos.X - self._lastXPos
	self._lastXPos = machineWorldPos.X

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

	local targetRoll = math.clamp(curvatureBank + switchBank, -MAX_BANK_ANGLE, MAX_BANK_ANGLE)
	self._currentRoll = self._currentRoll + (targetRoll - self._currentRoll) * math.min(BANK_SMOOTH_SPEED * dt, 1)

	local lookTarget = machineWorldPos + centerDir
	local baseCF = CFrame.lookAt(machineWorldPos, lookTarget)
	local finalCF = baseCF * CFrame.Angles(0, 0, self._currentRoll)
	machine:PivotTo(finalCF)
	self._lastCFrame = finalCF

	self.RaceProgress:Fire(self._t)
end

---------------------------------------------------------------------------
-- Public getters
---------------------------------------------------------------------------
function LakelandRaceController:GetProgress() return self._t end
function LakelandRaceController:GetCurrentLane() return self._currentLane end
function LakelandRaceController:GetCurrentSpeed() return self._currentSpeed end
function LakelandRaceController:GetMachineCFrame() return self._lastCFrame end
function LakelandRaceController:GetMaxSpeed() return MAX_SPEED end
function LakelandRaceController:IsBoosting() return self._boosting end
function LakelandRaceController:GetBoostTally() return math.floor(self._currentBoostTally) end
function LakelandRaceController:GetHealth() return self._health end
function LakelandRaceController:GetMaxHealth() return MAX_HEALTH end
function LakelandRaceController:GetDistance() return self._totalDistance end
function LakelandRaceController:GetTrackLength() return TRACK_LENGTH end
function LakelandRaceController:GetCoinScore() return self._coinScore + math.floor(self._boostScore) end
function LakelandRaceController:GetCoinsCollected() return self._coinsCollected end

return LakelandRaceController
