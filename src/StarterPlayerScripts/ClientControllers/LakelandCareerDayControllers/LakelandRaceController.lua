local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local SoundService = game:GetService("SoundService")
local Workspace = game:GetService("Workspace")
local Lighting = game:GetService("Lighting")
local Debris = game:GetService("Debris")

local Packages = ReplicatedStorage.Packages
local Knit = require(Packages.Knit)
local Trove = require(Packages.Trove)
local Signal = require(Packages.Signal)
local Input = require(Packages.Input)

local CustomPackages = ReplicatedStorage.CustomPackages
local CatmullRomSpline = require(CustomPackages.Splines.CatmullRomSpline)

local SFX_Impacts = SoundService:FindFirstChild("Impacts")
local SFX_RandomImpact = SoundService:FindFirstChild("RandonOnImpact")
local SFX_Countdown = SoundService:FindFirstChild("DuringCountDown")
local SFX_Flyby = SoundService:FindFirstChild("flyby")

local SFX_BoostPad = SoundService:FindFirstChild("BoostPad")

local function playSoundAt(sound, worldPos, volume)
	if not sound or not sound:IsA("Sound") then return end
	local emitter = Instance.new("Part")
	emitter.Size = Vector3.new(0.1, 0.1, 0.1)
	emitter.Transparency = 1
	emitter.Anchored = true
	emitter.CanCollide = false
	emitter.CanQuery = false
	emitter.CFrame = CFrame.new(worldPos)
	emitter.Parent = Workspace
	local clone = sound:Clone()
	clone.RollOffMode = Enum.RollOffMode.InverseTapered
	clone.RollOffMinDistance = 20
	clone.RollOffMaxDistance = 200
	clone.PlaybackSpeed = 0.85 + math.random() * 0.3
	if volume then clone.Volume = volume end
	clone.Parent = emitter
	clone:Play()
	Debris:AddItem(emitter, (clone.TimeLength / clone.PlaybackSpeed) + 0.5)
end

local function playRandomImpactAt(worldPos, volume)
	if not SFX_RandomImpact then return end
	local children = SFX_RandomImpact:GetChildren()
	if #children == 0 then return end
	local pick = children[math.random(1, #children)]
	if pick:IsA("Sound") then
		playSoundAt(pick, worldPos, volume)
	end
end

local function playRandomFlybyAt(worldPos, speedFrac)
	if not SFX_Flyby then return end
	local children = SFX_Flyby:GetChildren()
	if #children == 0 then return end
	local pick = children[math.random(1, #children)]
	local sf = math.clamp(speedFrac or 0.5, 0, 1)
	local emitter = Instance.new("Part")
	emitter.Size = Vector3.new(0.1, 0.1, 0.1)
	emitter.Transparency = 1
	emitter.Anchored = true
	emitter.CanCollide = false
	emitter.CanQuery = false
	emitter.CFrame = CFrame.new(worldPos)
	emitter.Parent = Workspace
	local clone = pick:Clone()
	clone.RollOffMode = Enum.RollOffMode.InverseTapered
	clone.RollOffMinDistance = 20
	clone.RollOffMaxDistance = 200
	clone.Volume = 0.2 + sf * 0.8
	clone.PlaybackSpeed = 0.7 + sf * 0.6
	clone.Parent = emitter
	clone:Play()
	Debris:AddItem(emitter, (clone.TimeLength / clone.PlaybackSpeed) + 0.5)
end

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
local BOOST_ACCEL = 20
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
local HIT_FREEZE_BASE = 0.25
local HIT_FREEZE_MAX  = 0.45
local BOMB_HIT_FREEZE = 0.06
local BOMB_HIT_ZOOM   = 3

-- Difficulty saw phases shared by hazard generation and visual difficulty
local HAZARD_PHASES = {
	{ from = 0.04,  to = 0.12, gapMax = 0.012, gapMin = 0.008,  dipFrac = 0.0  }, -- tutorial
	{ from = 0.12,  to = 0.30, gapMax = 0.009,  gapMin = 0.005,  dipFrac = 0.25 }, -- level 1
	{ from = 0.30,  to = 0.50, gapMax = 0.010,  gapMin = 0.004,  dipFrac = 0.20 }, -- level 2
	-- slightly eased higher phases: bigger gapMin + longer dip (reprieve)
	{ from = 0.50,  to = 0.70, gapMax = 0.009,  gapMin = 0.0042, dipFrac = 0.28 }, -- level 3
	{ from = 0.70,  to = 0.88, gapMax = 0.008,  gapMin = 0.0032, dipFrac = 0.25 }, -- level 4
	{ from = 0.88,  to = 0.99, gapMax = 0.006,  gapMin = 0.0027, dipFrac = 0.25 }, -- climax
}

local HAZARDS = {}
do
	--[[
		Difficulty Saw — hazard density follows a sawtooth curve:
		Each phase ramps up in density, then drops at the start of the next phase
		before climbing again to a higher ceiling. The baseline rises over time.
	]]
	local phases = HAZARD_PHASES

	local hazLanes = {2, 1, 3}
	local idx = 1
	for _, phase in ipairs(phases) do
		local t = phase.from
		while t < phase.to do
			local span = phase.to - phase.from
			if span <= 0 then break end

			local phaseFrac = (t - phase.from) / span

			local gap
			if phaseFrac < phase.dipFrac then
				gap = phase.gapMax
			else
				local denom = 1 - phase.dipFrac
				local rampFrac = (denom > 1e-6) and ((phaseFrac - phase.dipFrac) / denom) or 1
				if rampFrac < 0 then rampFrac = 0 elseif rampFrac > 1 then rampFrac = 1 end
				gap = phase.gapMax + (phase.gapMin - phase.gapMax) * rampFrac
			end

			local lane = hazLanes[((idx - 1) % 3) + 1]
			local tRound = math.floor(t * 1000 + 0.5) / 1000
			table.insert(HAZARDS, { lane = lane, t = tRound })

			t = t + gap
			idx = idx + 1
		end
	end
end

-- Returns a 0–1 difficulty value at normalized track position t
local function getHazardDifficulty(t)
	if t <= 0 then
		return 0
	end

	for index, phase in ipairs(HAZARD_PHASES) do
		if t >= phase.from and t < phase.to then
			local span = phase.to - phase.from
			if span <= 0 then
				return 0
			end

			local phaseFrac = (t - phase.from) / span
			local dipFrac = phase.dipFrac or 0

			local rampFrac
			if phaseFrac <= dipFrac then
				rampFrac = 0
			else
				local denom = 1 - dipFrac
				if denom <= 1e-6 then
					rampFrac = 1
				else
					rampFrac = (phaseFrac - dipFrac) / denom
				end
			end

			if rampFrac < 0 then rampFrac = 0 elseif rampFrac > 1 then rampFrac = 1 end

			local maxIndex = #HAZARD_PHASES - 1
			local global = (maxIndex > 0) and ((index - 1) / maxIndex) or 0

			-- Blend global phase and in-phase ramp to get a smooth 0–1 difficulty
			local difficulty = 0.3 * global + 0.7 * rampFrac
			if difficulty < 0 then difficulty = 0 elseif difficulty > 1 then difficulty = 1 end
			return difficulty
		end
	end

	-- After last phase treat as max difficulty, before first as zero
	if t < HAZARD_PHASES[1].from then
		return 0
	end
	return 1
end

-- Buckets track-position difficulty into tiers (used only for reference; visuals use score)
local function getDifficultyTier(t)
	local d = getHazardDifficulty(t)
	if d < 0.3 then
		return "reprieve", d
	elseif d > 0.7 then
		return "hard", d
	else
		return "normal", d
	end
end

-- Difficulty saw-curve driven by score (points).
local SCORE_DIFFICULTY_PHASES = {
	{ from = 0,     to = 500,   minD = 0,    maxD = 0.25 },
	{ from = 500,   to = 1500,  minD = 0.2,  maxD = 0.65 },
	{ from = 1500,  to = 2200,  minD = 0.25, maxD = 0.45 },
	{ from = 2200,  to = 4000,  minD = 0.45, maxD = 0.85 },
	{ from = 4000,  to = 5000,  minD = 0.35, maxD = 0.55 },
	{ from = 5000,  to = 8000,  minD = 0.55, maxD = 1    },
	{ from = 8000,  to = 1e9,   minD = 0.7,  maxD = 1    },
}

local function getDifficultyFromScore(score)
	if score <= 0 then return 0 end
	for _, phase in ipairs(SCORE_DIFFICULTY_PHASES) do
		if score >= phase.from and score < phase.to then
			local span = phase.to - phase.from
			if span <= 0 then return phase.maxD end
			local frac = (score - phase.from) / span
			if frac < 0 then frac = 0 elseif frac > 1 then frac = 1 end
			return phase.minD + (phase.maxD - phase.minD) * frac
		end
	end
	return 1
end

local function getDifficultyTierFromScore(score)
	local d = getDifficultyFromScore(score)
	if d < 0.35 then
		return "reprieve", d
	elseif d > 0.65 then
		return "hard", d
	else
		return "normal", d
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

local BOMB_SIZE = 0.0012
local BOMB_CHAIN_LENGTH = 24
local BOMB_CHAIN_SPEED  = 0.45
local BOMB_CHAIN_T_SPAN = 0.022
local BOMB_CHAIN_LIFE   = 0.8
local BOMB_POOL         = 8
local BOMB_CHAIN_POOL   = 26
local BOMB_IND_MAX      = 5

local BOMBS = {}
do
	local bombLanes = {2, 1, 3, 2, 3, 1}
	local bombGap = 0.045
	local t = 0.06
	local idx = 1
	while t < 0.94 do
		local lane = bombLanes[((idx - 1) % #bombLanes) + 1]
		local tRound = math.floor(t * 10000 + 0.5) / 10000

		local overlaps = false
		for _, h in ipairs(HAZARDS) do
			if h.lane == lane and math.abs(h.t - tRound) < 0.004 then overlaps = true; break end
		end
		if not overlaps then
			for _, b in ipairs(BOOST_ZONES) do
				if b.lane == lane and tRound >= b.tStart and tRound <= b.tStart + BOOST_LENGTH then
					overlaps = true; break
				end
			end
		end
		if not overlaps then
			table.insert(BOMBS, {lane = lane, t = tRound, collected = false})
		end

		t = t + bombGap
		idx = idx + 1
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
local WINDOW_AHEAD  = 0.025
local WINDOW_BEHIND = 0.015

local ROAD_HALF_W = LANE_SPACING * 1.5
local ROAD_W      = ROAD_HALF_W * 2

local ROAD_T_STEP    = 0.0015
local LANE_T_STEP    = 0.00075
local LIGHT_T_STEP   = 0.005
local TUNNEL_T_STEP  = 0.0025

local CUBE_FADE_ZONE = 0.35

local ROAD_POOL       = 40
local LANE_POOL       = 200
local LIGHT_POOL      = 16
local TUNNEL_POOL     = 40
local HAZARD_POOL     = 20

local TUNNEL_HEIGHT      = 14
local TUNNEL_HALF_W      = ROAD_HALF_W + 2
local TUNNEL_BAR_THICK   = 0.18
local TUNNEL_GLOW_RANGE  = 30
local TUNNEL_GLOW_BRIGHT = 1.2

local SIDE_LASER_POOL        = 16
local SIDE_LASER_T_STEP      = 0.005
local SIDE_LASER_BARS        = 4
local SIDE_LASER_RADIUS      = 3.5
local SIDE_LASER_SPIN        = 1.2
local SIDE_LASER_BAR_THICK   = 0.12
local SIDE_LASER_OFFSET      = ROAD_HALF_W + 5
local SIDE_LASER_HEIGHT      = 7
local SIDE_LASER_PULSE_SPEED = 2.5
local SIDE_LASER_GLOW_RANGE  = 18

local COIN_POOL        = 30
local BOMB_PICKUP_POOL = 10
local BOOST_PAD_POOL   = 35
local BOOST_CHEV_POOL  = 90

local BOOST_VIS_SEGS  = 6
local BOOST_VIS_WIDTH = LANE_SPACING * 0.7
local BOOST_CHEVRONS_PER_ZONE = 8
local BOOST_CHASE_SPEED       = 8
local BOOST_FADE_TAIL       = 2
local BOOST_DIM_FLOOR       = 0.1
local BOOST_OFF_COLOR       = Color3.fromRGB(155, 115, 50)
local BOOST_ON_COLOR        = Color3.fromRGB(255, 200, 50)

local HARD_TRANSITION_SPEED = 2.5
local DIFFICULTY_SECTION_SCORE_STEP = 500

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

local SPEC_BAND_COUNT   = 32
local SPEC_SIDE_OFFSET  = ROAD_HALF_W + 1
local SPEC_BAR_WIDTH    = 1.2
local SPEC_BAR_DEPTH    = 0.8
local SPEC_BAR_SPACING  = 4.0
local SPEC_MAX_HEIGHT   = 12
local SPEC_MIN_HEIGHT   = 0.5
local SPEC_GLOW_RANGE   = 20
local SPEC_GLOW_BRIGHT  = 2.5
local SPEC_BASS_COLOR   = Color3.fromRGB(255, 50, 180)
local SPEC_TREBLE_COLOR = Color3.fromRGB(50, 200, 255)

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

	_lastDifficultyTier = nil,
	_hardTransitionSmooth = false,
	_difficultyTransitionProgress = 0,

	_hitFreezeTimer = 0,

	_bombCount = 0,
	_bombIndicators = {},
	_bombChainActive = false,
	_bombChainParts = {},
	_bombChainTimer = 0,
	_bombChainCount = 0,
	_bombChainLane = 2,
	_bombChainStartT = 0,

	_machineLoadEmitter = nil,
	_boostSfxEmitter = nil,

	_specBars = {},
	_specBands = {},

	LaneChanged = Signal.new(),
	RaceProgress = Signal.new(),
	BoostChanged = Signal.new(),
	SpeedChanged = Signal.new(),
	HealthChanged = Signal.new(),
	HazardHit = Signal.new(),
	CoinCollected = Signal.new(),
	BombCollected = Signal.new(),
	BombDeployed = Signal.new(),
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

	self._cameraController = Knit.GetController("LakelandCameraController")

	local gameController = Knit.GetController("LakelandGameController")
	self._beatIntensity = gameController:GetBeatIntensity()
	gameController.GameStateChanged:Connect(function(newState)
		if newState == "COUNTDOWN" then
			self._obstaclesVisible = false
			self:PositionAtStart()
			if SFX_Countdown then
				local ml = SFX_Countdown:FindFirstChild("MachineLoad")
				if ml then
					if self._machineLoadEmitter then
						self._machineLoadEmitter:Destroy()
						self._machineLoadEmitter = nil
					end
					local emitter = Instance.new("Part")
					emitter.Size = Vector3.new(0.1, 0.1, 0.1)
					emitter.Transparency = 1
					emitter.Anchored = true
					emitter.CanCollide = false
					emitter.CanQuery = false
					emitter.CFrame = CFrame.new(FIXED_MACHINE_POS)
					emitter.Parent = Workspace
					local clone = ml:Clone()
					clone.Parent = emitter
					clone:Play()
					self._machineLoadEmitter = emitter
				end
			end
		elseif newState == "PLAYING" then
			self._obstaclesVisible = true
			self:StartRace()
			if self._machineLoadEmitter then
				self._machineLoadEmitter:Destroy()
				self._machineLoadEmitter = nil
			end
		elseif newState == "GAME_OVER" or newState == "MENU" then
			self:StopRace()
			if self._machineLoadEmitter then
				self._machineLoadEmitter:Destroy()
				self._machineLoadEmitter = nil
			end
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

	-- Laser tunnel frames: each frame = left post + top bar + right post (3 parts)
	self._pools.tunnel = {}
	for i = 1, TUNNEL_POOL do
		local frame = {}
		for _, name in ipairs({ "left", "top", "right" }) do
			local bar = Instance.new("Part")
			bar.Name = "TunnelBar_" .. name
			bar.Anchored = true
			bar.CanCollide = false
			bar.Material = Enum.Material.Neon
			bar.Color = Color3.fromRGB(50, 140, 255)
			bar.Transparency = 1
			bar.Parent = folder
			local glow = Instance.new("PointLight")
			glow.Brightness = 0
			glow.Range = TUNNEL_GLOW_RANGE
			glow.Shadows = false
			glow.Parent = bar
			frame[name] = bar
		end
		self._pools.tunnel[i] = frame
	end

	-- Side laser decorations: spinning asterisk shapes on alternating sides
	self._pools.sideLaser = {}
	for i = 1, SIDE_LASER_POOL do
		local bars = {}
		for b = 1, SIDE_LASER_BARS do
			local bar = Instance.new("Part")
			bar.Name = "SideLaserBar"
			bar.Anchored = true
			bar.CanCollide = false
			bar.Material = Enum.Material.Neon
			bar.Color = Color3.fromRGB(50, 140, 255)
			bar.Transparency = 1
			bar.Parent = folder
			local glow = Instance.new("PointLight")
			glow.Brightness = 0
			glow.Range = SIDE_LASER_GLOW_RANGE
			glow.Shadows = false
			glow.Parent = bar
			bars[b] = bar
		end
		self._pools.sideLaser[i] = bars
	end

	local function buildCubeAssembly(size, outerColor, innerColor, glowColor, hlFill, hlOutline, lightRange)
		local model = Instance.new("Model")
		model.Name = "CubeAssembly"

		local shell = Instance.new("Part")
		shell.Name = "Shell"
		shell.Shape = Enum.PartType.Block
		shell.Size = Vector3.new(size, size, size)
		shell.Anchored = true
		shell.CanCollide = false
		shell.Color = outerColor
		shell.Material = Enum.Material.Glass
		shell.Transparency = 1
		shell.Parent = model
		model.PrimaryPart = shell

		local hl = Instance.new("Highlight")
		hl.FillColor = hlFill
		hl.FillTransparency = 0.3
		hl.OutlineColor = hlOutline
		hl.OutlineTransparency = 0
		hl.Enabled = false
		hl.Parent = shell

		local core = Instance.new("Part")
		core.Name = "Core"
		core.Shape = Enum.PartType.Block
		core.Size = Vector3.new(size * 0.45, size * 0.45, size * 0.45)
		core.Anchored = true
		core.CanCollide = false
		core.Color = innerColor
		core.Material = Enum.Material.Neon
		core.Transparency = 1
		core.Parent = model

		local glow = Instance.new("PointLight")
		glow.Color = glowColor
		glow.Brightness = 0.8
		glow.Range = lightRange
		glow.Shadows = false
		glow.Enabled = false
		glow.Parent = shell

		local edgeLen = size
		local edgeThick = size * 0.06
		local half = size / 2
		local edgeOffsets = {
			{ Vector3.new(0,  half,  half), Vector3.new(edgeLen, edgeThick, edgeThick) },
			{ Vector3.new(0,  half, -half), Vector3.new(edgeLen, edgeThick, edgeThick) },
			{ Vector3.new(0, -half,  half), Vector3.new(edgeLen, edgeThick, edgeThick) },
			{ Vector3.new(0, -half, -half), Vector3.new(edgeLen, edgeThick, edgeThick) },
			{ Vector3.new( half, 0,  half), Vector3.new(edgeThick, edgeLen, edgeThick) },
			{ Vector3.new( half, 0, -half), Vector3.new(edgeThick, edgeLen, edgeThick) },
			{ Vector3.new(-half, 0,  half), Vector3.new(edgeThick, edgeLen, edgeThick) },
			{ Vector3.new(-half, 0, -half), Vector3.new(edgeThick, edgeLen, edgeThick) },
			{ Vector3.new( half,  half, 0), Vector3.new(edgeThick, edgeThick, edgeLen) },
			{ Vector3.new( half, -half, 0), Vector3.new(edgeThick, edgeThick, edgeLen) },
			{ Vector3.new(-half,  half, 0), Vector3.new(edgeThick, edgeThick, edgeLen) },
			{ Vector3.new(-half, -half, 0), Vector3.new(edgeThick, edgeThick, edgeLen) },
		}
		for idx, e in ipairs(edgeOffsets) do
			local edge = Instance.new("Part")
			edge.Name = "Edge_" .. idx
			edge.Shape = Enum.PartType.Block
			edge.Size = e[2]
			edge.Anchored = true
			edge.CanCollide = false
			edge.Color = glowColor
			edge.Material = Enum.Material.Neon
			edge.Transparency = 1
			edge.Parent = model
			edge:SetAttribute("LocalOffset", e[1])
		end

		model:SetAttribute("BaseSize", size)
		model:SetAttribute("CoreSize", size * 0.45)
		model.Parent = folder
		return model
	end

	self._pools.hazard = {}
	for i = 1, HAZARD_POOL do
		self._pools.hazard[i] = buildCubeAssembly(
			5,
			Color3.fromRGB(180, 20, 20),
			Color3.fromRGB(255, 60, 60),
			Color3.fromRGB(255, 80, 80),
			Color3.fromRGB(255, 50, 50),
			Color3.fromRGB(255, 100, 100),
			25
		)
	end

	self._pools.coin = {}
	for i = 1, COIN_POOL do
		self._pools.coin[i] = buildCubeAssembly(
			4,
			Color3.fromRGB(20, 80, 180),
			Color3.fromRGB(60, 150, 255),
			Color3.fromRGB(80, 160, 255),
			Color3.fromRGB(50, 140, 255),
			Color3.fromRGB(100, 180, 255),
			20
		)
	end

	self._pools.bomb = {}
	for i = 1, BOMB_PICKUP_POOL do
		self._pools.bomb[i] = buildCubeAssembly(
			4.2,
			Color3.fromRGB(20, 160, 40),
			Color3.fromRGB(80, 255, 100),
			Color3.fromRGB(60, 255, 80),
			Color3.fromRGB(50, 220, 70),
			Color3.fromRGB(100, 255, 120),
			22
		)
	end

	self._bombIndicators = {}
	for i = 1, BOMB_IND_MAX do
		local ind = Instance.new("Part")
		ind.Name = "BombIndicator_" .. i
		ind.Shape = Enum.PartType.Block
		ind.Size = Vector3.new(2, 2, 2)
		ind.Anchored = true
		ind.CanCollide = false
		ind.Material = Enum.Material.Neon
		ind.Color = Color3.fromRGB(60, 255, 80)
		ind.Transparency = 1
		ind.Parent = folder
		local gl = Instance.new("PointLight")
		gl.Color = Color3.fromRGB(60, 255, 80)
		gl.Brightness = 0
		gl.Range = 20
		gl.Shadows = false
		gl.Parent = ind
		self._bombIndicators[i] = ind
	end

	self._bombChainParts = {}
	for i = 1, BOMB_CHAIN_POOL do
		local p = Instance.new("Part")
		p.Name = "BombChain"
		p.Shape = Enum.PartType.Block
		p.Size = Vector3.new(3.5, 3.5, 3.5)
		p.Anchored = true
		p.CanCollide = false
		p.Material = Enum.Material.Neon
		p.Color = Color3.fromRGB(60, 255, 80)
		p.Transparency = 1
		p.Parent = folder
		local gl = Instance.new("PointLight")
		gl.Color = Color3.fromRGB(60, 255, 80)
		gl.Brightness = 0
		gl.Range = 18
		gl.Shadows = false
		gl.Parent = p
		self._bombChainParts[i] = { part = p, spawnTime = 0, active = false }
	end

	makePool("boostPad", BOOST_PAD_POOL, function(p)
		p.Color = Color3.fromRGB(165, 125, 60)
		p.Material = Enum.Material.Glass
	end)
	self._pools.boostChev = {}
	for i = 1, BOOST_CHEV_POOL do
		local chev = Instance.new("Part")
		chev.Name = "BoostChevron"
		chev.Size = Vector3.new(0.8, 0.2, 0.5)
		chev.Anchored = true
		chev.CanCollide = false
		chev.Color = BOOST_OFF_COLOR
		chev.Material = Enum.Material.Neon
		chev.Transparency = 1
		chev.Parent = folder
		local pl = Instance.new("PointLight")
		pl.Color = BOOST_ON_COLOR
		pl.Brightness = 0
		pl.Range = 18
		pl.Shadows = false
		pl.Parent = chev
		self._pools.boostChev[i] = chev
	end

	-- Spectrum visualizer bars (fixed alongside the player)
	self._specBars = {}
	self._specBands = {}
	for i = 1, SPEC_BAND_COUNT do
		self._specBands[i] = 0

		local entry = {}
		for _, sign in ipairs({ -1, 1 }) do
			local bar = Instance.new("Part")
			bar.Size = Vector3.new(SPEC_BAR_WIDTH, SPEC_MIN_HEIGHT, SPEC_BAR_DEPTH)
			bar.Anchored = true
			bar.CanCollide = false
			bar.Material = Enum.Material.Neon
			bar.Color = Color3.fromRGB(50, 200, 255)
			bar.Transparency = 0
			bar.Parent = folder

			local key = sign == -1 and "left" or "right"
			entry[key] = bar
		end
		self._specBars[i] = entry
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

	local beat = self._beatIntensity and self._beatIntensity:get() or 0
	local cubeBeatScale = 1 + beat * 0.25

	local hue = (time() * 0.08) % 1
	local beatColor = Color3.fromHSV(hue, 0.7, 1)
	local function beatAccent(zoneAccent)
		return zoneAccent:Lerp(beatColor, beat * 0.85)
	end

	local function toWorld(splinePos)
		return FIXED_MACHINE_POS + (splinePos - centerRef)
	end

	-- Difficulty tier from current score (points), not track position — same for whole view
	local currentScore = self:GetCurrentScore()
	local tier = select(1, getDifficultyTierFromScore(currentScore))

	-- Smooth vs sudden transition into hard (chosen at random each time we enter hard)
	if tier == "hard" and self._lastDifficultyTier ~= "hard" then
		self._hardTransitionSmooth = (math.random() > 0.5)
		self._difficultyTransitionProgress = 0
	end
	if tier ~= "hard" then
		self._difficultyTransitionProgress = 0
	elseif self._hardTransitionSmooth then
		self._difficultyTransitionProgress = math.min(1, self._difficultyTransitionProgress + dt * HARD_TRANSITION_SPEED)
	else
		self._difficultyTransitionProgress = 1
	end
	self._lastDifficultyTier = tier
	local hardBlend = (tier == "hard") and self._difficultyTransitionProgress or 0

	local visibleRange = tMax - tMin
	local fadeStart = tMax - visibleRange * CUBE_FADE_ZONE

	-- Road surface (snap to fixed grid so parts slide smoothly)
	local ri = 1
	local t = math.floor(tMin / ROAD_T_STEP) * ROAD_T_STEP
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
			road.Transparency = 0
			ri = ri + 1
		end
		t = t + ROAD_T_STEP
	end
	for i = ri, ROAD_POOL do self._pools.road[i].Transparency = 1 end

	-- Lane dividers
	local li = 1
	for _, laneData in ipairs(self._splines) do
		local spline = laneData.spline
		local lt = math.floor(tMin / LANE_T_STEP) * LANE_T_STEP
		while lt < tMax and li <= LANE_POOL do
			local lt1 = math.min(lt + LANE_T_STEP, tMax)
			local ltMid = (lt + lt1) / 2
			local zone = getTrackZone(ltMid)
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
				local accent = beatAccent(zone.accent)
				local hardColor = Color3.fromRGB(255, 80, 80)
				if tier == "hard" then
					line.Color = accent:Lerp(hardColor, 0.55 * hardBlend)
					line.Transparency = 0.15 * hardBlend + 0.25 * (1 - hardBlend)
				elseif tier == "reprieve" then
					line.Color = accent:Lerp(Color3.fromRGB(140, 220, 255), 0.45)
					line.Transparency = 0.4
				else
					line.Color = accent
					line.Transparency = 0.25
				end
				li = li + 1
			end
			lt = lt + LANE_T_STEP
		end
	end
	for i = li, LANE_POOL do self._pools.lane[i].Transparency = 1 end

	-- Track lights (snap to grid)
	local tli = 1
	local tlt = math.floor(tMin / LIGHT_T_STEP) * LIGHT_T_STEP
	while tlt < tMax and tli <= LIGHT_POOL do
		local zone = getTrackZone(tlt)
		local pos = centerSpline:CalculatePositionAt(tlt)
		local wP = toWorld(pos)
		local info = self._pools.light[tli]
		info.part.Position = wP + Vector3.new(0, 6, 0)
		local accent = beatAccent(zone.accent)
		local hardColor = Color3.fromRGB(255, 80, 80)
		local color = accent
		local brightness = 0.6
		if tier == "hard" then
			color = accent:Lerp(hardColor, 0.55 * hardBlend)
			brightness = 0.6 + 0.4 * hardBlend
		elseif tier == "reprieve" then
			color = accent:Lerp(Color3.fromRGB(140, 220, 255), 0.45)
			brightness = 0.4
		end
		info.light.Color = color
		info.light.Brightness = brightness
		tli = tli + 1
		tlt = tlt + LIGHT_T_STEP
	end
	for i = tli, LIGHT_POOL do self._pools.light[i].light.Brightness = 0 end

	-- Laser tunnel frames — shape variety: gate |-|  aframe /‾\  cross X  arch \_/
	local function placeBar(bar, s, e, color, trans, bright)
		local mid = (s + e) * 0.5
		local len = (e - s).Magnitude
		if len < 0.01 then
			bar.Transparency = 1; bar.PointLight.Brightness = 0; return
		end
		bar.Size = Vector3.new(TUNNEL_BAR_THICK, TUNNEL_BAR_THICK, len)
		bar.CFrame = CFrame.lookAt(mid, e)
		bar.Color = color
		bar.Transparency = trans
		bar.PointLight.Color = color
		bar.PointLight.Brightness = bright
	end

	local tfi = 1
	local tft = math.floor(tMin / TUNNEL_T_STEP) * TUNNEL_T_STEP
	while tft < tMax and tfi <= TUNNEL_POOL do
		local zone = getTrackZone(tft)
		local posA = centerSpline:CalculatePositionAt(tft)
		local posB = centerSpline:CalculatePositionAt(math.min(tft + TUNNEL_T_STEP * 0.1, 1))
		local dir = posB - posA
		if dir.Magnitude > 0.001 then
			local wP = toWorld(posA)
			local fwd = dir.Unit
			local right = fwd:Cross(Vector3.new(0, 1, 0)).Unit
			local up = Vector3.new(0, 1, 0)

			local accent = beatAccent(zone.accent)
			local hardColor = Color3.fromRGB(255, 80, 80)
			local color = accent
			if tier == "hard" then
				color = accent:Lerp(hardColor, 0.6 * hardBlend)
			elseif tier == "reprieve" then
				color = accent:Lerp(Color3.fromRGB(140, 220, 255), 0.45)
			end

			local tAlpha = 1
			if tft > fadeStart then
				tAlpha = math.clamp(1 - (tft - fadeStart) / (tMax - fadeStart), 0, 1)
			end
			local trans = 1 - tAlpha
			local bright = TUNNEL_GLOW_BRIGHT * tAlpha

			local frame = self._pools.tunnel[tfi]
			local baseY = wP.Y + 0.1
			local hw = TUNNEL_HALF_W
			local h = TUNNEL_HEIGHT

			local bl = wP - right * hw + up * (baseY - wP.Y)
			local br = wP + right * hw + up * (baseY - wP.Y)
			local tl = bl + up * h
			local tr = br + up * h

			placeBar(frame.left,  bl, tl, color, trans, bright)
			placeBar(frame.top,   tl, tr, color, trans, bright)
			placeBar(frame.right, br, tr, color, trans, bright)

			tfi = tfi + 1
		end
		tft = tft + TUNNEL_T_STEP
	end
	for i = tfi, TUNNEL_POOL do
		local frame = self._pools.tunnel[i]
		frame.left.Transparency = 1;  frame.left.PointLight.Brightness = 0
		frame.right.Transparency = 1; frame.right.PointLight.Brightness = 0
		frame.top.Transparency = 1;   frame.top.PointLight.Brightness = 0
	end

	-- Side laser decorations — spinning asterisk shapes on alternating sides
	local sli = 1
	local slt = math.floor(tMin / SIDE_LASER_T_STEP) * SIDE_LASER_T_STEP
	local now = time()
	while slt < tMax and sli <= SIDE_LASER_POOL do
		local zone = getTrackZone(slt)
		local posA = centerSpline:CalculatePositionAt(slt)
		local posB = centerSpline:CalculatePositionAt(math.min(slt + SIDE_LASER_T_STEP * 0.1, 1))
		local dir = posB - posA
		if dir.Magnitude > 0.001 then
			local wP = toWorld(posA)
			local fwd = dir.Unit
			local right = fwd:Cross(Vector3.new(0, 1, 0)).Unit
			local up = Vector3.new(0, 1, 0)

			local side = (sli % 2 == 0) and 1 or -1
			local center = wP + right * (SIDE_LASER_OFFSET * side) + up * SIDE_LASER_HEIGHT

			local accent = beatAccent(zone.accent)
			local color = accent
			if tier == "hard" then
				color = accent:Lerp(Color3.fromRGB(255, 80, 80), 0.6 * hardBlend)
			elseif tier == "reprieve" then
				color = accent:Lerp(Color3.fromRGB(140, 220, 255), 0.45)
			end

			local slAlpha = 1
			if slt > fadeStart then
				slAlpha = math.clamp(1 - (slt - fadeStart) / (tMax - fadeStart), 0, 1)
			end

			local pulse = 0.7 + 0.3 * math.sin(now * SIDE_LASER_PULSE_SPEED + sli * 1.7)
			local spin = now * SIDE_LASER_SPIN + sli * 0.8

			local bars = self._pools.sideLaser[sli]
			for b = 1, SIDE_LASER_BARS do
				local angle = spin + (b - 1) * math.pi / SIDE_LASER_BARS
				local planeDir = math.cos(angle) * up + math.sin(angle) * right
				local bar = bars[b]
				bar.Size = Vector3.new(SIDE_LASER_BAR_THICK, SIDE_LASER_BAR_THICK, SIDE_LASER_RADIUS * 2)
				bar.CFrame = CFrame.lookAt(center, center + planeDir)
				bar.Color = color
				bar.Transparency = 1 - slAlpha * pulse
				bar.PointLight.Color = color
				bar.PointLight.Brightness = TUNNEL_GLOW_BRIGHT * 0.5 * slAlpha * pulse
			end
			sli = sli + 1
		end
		slt = slt + SIDE_LASER_T_STEP
	end
	for i = sli, SIDE_LASER_POOL do
		for b = 1, SIDE_LASER_BARS do
			self._pools.sideLaser[i][b].Transparency = 1
			self._pools.sideLaser[i][b].PointLight.Brightness = 0
		end
	end

	local function showCubeAssembly(model, cf, show, alpha, beatScale)
		alpha = alpha or 1
		beatScale = beatScale or 1
		local shell = model.PrimaryPart
		local baseSize = model:GetAttribute("BaseSize") or 4
		local coreSize = model:GetAttribute("CoreSize") or (baseSize * 0.45)
		local s = baseSize * beatScale
		local cs = coreSize * beatScale

		shell.Size = Vector3.new(s, s, s)
		shell.CFrame = cf
		shell.Transparency = show and (1 - 0.75 * alpha) or 1

		local hl = shell:FindFirstChildOfClass("Highlight")
		if hl then
			hl.Enabled = show and alpha > 0.1
			if hl.Enabled then hl.FillTransparency = 1 - 0.7 * alpha end
		end
		local light = shell:FindFirstChildOfClass("PointLight")
		if light then
			light.Enabled = show and alpha > 0.1
			if light.Enabled then light.Brightness = 0.8 + (beatScale - 1) * 8 end
		end

		for _, child in ipairs(model:GetChildren()) do
			if child == shell or not child:IsA("BasePart") then continue end
			if child.Name == "Core" then
				local spin = (time() * 2.5) % (math.pi * 2)
				child.Size = Vector3.new(cs, cs, cs)
				child.CFrame = cf * CFrame.Angles(spin, spin * 0.7, 0)
				child.Transparency = show and (1 - alpha) or 1
			else
				local localOff = child:GetAttribute("LocalOffset")
				if localOff then
					child.CFrame = cf * CFrame.new(localOff * beatScale)
				end
				child.Transparency = show and (1 - alpha) or 1
			end
		end
	end

	local function hideCubeAssembly(model)
		local shell = model.PrimaryPart
		shell.Transparency = 1
		local hl = shell:FindFirstChildOfClass("Highlight")
		if hl then hl.Enabled = false end
		local light = shell:FindFirstChildOfClass("PointLight")
		if light then light.Enabled = false end
		for _, child in ipairs(model:GetChildren()) do
			if child:IsA("BasePart") and child ~= shell then
				child.Transparency = 1
			end
		end
	end

	-- Hazards
	local playerT = self._t
	local hi = 1
	for _, hazard in ipairs(HAZARDS) do
		if hi > HAZARD_POOL then break end
		if not hazard._hit and hazard.t >= tMin and hazard.t <= tMax then
			local show = self._obstaclesVisible
			local alpha = 1
			if hazard.t > fadeStart then
				alpha = math.clamp(1 - (hazard.t - fadeStart) / (tMax - fadeStart), 0, 1)
				alpha = alpha * alpha
			end
			local spline = self._splines[hazard.lane].spline
			local pos = spline:CalculatePositionAt(hazard.t)
			local wP = toWorld(pos)
			showCubeAssembly(self._pools.hazard[hi], CFrame.new(wP + Vector3.new(0, 2.5, 0)), show, alpha, cubeBeatScale)
			if not hazard._flybyPlayed and hazard.t <= playerT then
				hazard._flybyPlayed = true
				playRandomFlybyAt(wP + Vector3.new(0, 2.5, 0), self._currentSpeed / MAX_SPEED)
			end
			hi = hi + 1
		end
	end
	for i = hi, HAZARD_POOL do hideCubeAssembly(self._pools.hazard[i]) end

	-- Coins
	local ci = 1
	for _, coin in ipairs(COINS) do
		if ci > COIN_POOL then break end
		if not coin.collected and coin.t >= tMin and coin.t <= tMax then
			local show = self._obstaclesVisible
			local alpha = 1
			if coin.t > fadeStart then
				alpha = math.clamp(1 - (coin.t - fadeStart) / (tMax - fadeStart), 0, 1)
				alpha = alpha * alpha
			end
			local spline = self._splines[coin.lane].spline
			local pos = spline:CalculatePositionAt(coin.t)
			local wP = toWorld(pos)
			showCubeAssembly(self._pools.coin[ci], CFrame.new(wP + Vector3.new(0, 2.5, 0)), show, alpha, cubeBeatScale)
			if not coin._flybyPlayed and coin.t <= playerT then
				coin._flybyPlayed = true
				playRandomFlybyAt(wP + Vector3.new(0, 2.5, 0), self._currentSpeed / MAX_SPEED)
			end
			ci = ci + 1
		end
	end
	for i = ci, COIN_POOL do hideCubeAssembly(self._pools.coin[i]) end

	-- Bomb pickups
	local bi = 1
	for _, bomb in ipairs(BOMBS) do
		if bi > BOMB_PICKUP_POOL then break end
		if not bomb.collected and bomb.t >= tMin and bomb.t <= tMax then
			local show = self._obstaclesVisible
			local alpha = 1
			if bomb.t > fadeStart then
				alpha = math.clamp(1 - (bomb.t - fadeStart) / (tMax - fadeStart), 0, 1)
				alpha = alpha * alpha
			end
			local spline = self._splines[bomb.lane].spline
			local pos = spline:CalculatePositionAt(bomb.t)
			local wP = toWorld(pos)
			showCubeAssembly(self._pools.bomb[bi], CFrame.new(wP + Vector3.new(0, 2.5, 0)), show, alpha, cubeBeatScale)
			if not bomb._flybyPlayed and bomb.t <= playerT then
				bomb._flybyPlayed = true
				playRandomFlybyAt(wP + Vector3.new(0, 2.5, 0), self._currentSpeed / MAX_SPEED)
			end
			bi = bi + 1
		end
	end
	for i = bi, BOMB_PICKUP_POOL do hideCubeAssembly(self._pools.bomb[i]) end

	-- Bomb indicators orbiting the player's machine (evenly spaced)
	local showCount = math.min(self._bombCount, BOMB_IND_MAX)
	for i = 1, BOMB_IND_MAX do
		local ind = self._bombIndicators[i]
		if i <= showCount and self._lastCFrame then
			local orbitSpeed = 2.2
			local orbitRadius = 4.5
			local orbitHeight = 2.5
			local bobY = 0.3 * math.sin(time() * 3 + i * 0.5)
			local spacing = (2 * math.pi) / showCount
			local angle = time() * orbitSpeed + (i - 1) * spacing
			local selfSpin = (time() * 2.5 + i) % (math.pi * 2)
			local center = self._lastCFrame.Position
			local offsetX = math.cos(angle) * orbitRadius
			local offsetZ = math.sin(angle) * orbitRadius
			local indPos = center + Vector3.new(offsetX, orbitHeight + bobY, offsetZ)
			ind.CFrame = CFrame.new(indPos) * CFrame.Angles(selfSpin, selfSpin * 0.6, 0)
			ind.Size = Vector3.new(2, 2, 2)
			ind.Transparency = 0.15
			ind.PointLight.Brightness = 1.2 + 0.4 * math.sin(time() * 4 + i)
		else
			ind.Transparency = 1
			ind.PointLight.Brightness = 0
		end
	end

	-- Bomb chain animation
	local now = time()
	for i = 1, BOMB_CHAIN_POOL do
		local entry = self._bombChainParts[i]
		if entry.active then
			local age = now - entry.spawnTime
			if age > BOMB_CHAIN_LIFE then
				entry.active = false
				entry.part.Transparency = 1
				entry.part.PointLight.Brightness = 0
			else
				local fade = 1 - (age / BOMB_CHAIN_LIFE)
				local pop = math.min(age / 0.08, 1)
				local s = 3.5 * pop
				entry.part.Size = Vector3.new(s, s, s)
				entry.part.Transparency = 1 - fade * 0.85
				entry.part.PointLight.Brightness = 1.5 * fade
			end
		end
	end

	-- Boost zones (pad surface + chevrons down the middle, edge to edge, runway effect)
	local boostChaseHead = (time() * BOOST_CHASE_SPEED) % BOOST_CHEVRONS_PER_ZONE
	local pi, chi = 1, 1
	for _, bz in ipairs(BOOST_ZONES) do
		local tEnd = bz.tStart + BOOST_LENGTH
		if tEnd < tMin or bz.tStart > tMax then continue end
		local show = self._obstaclesVisible
		local spline = self._splines[bz.lane].spline
		local zoneLen = tEnd - bz.tStart
		local zoneLenStuds = (spline:CalculatePositionAt(tEnd) - spline:CalculatePositionAt(bz.tStart)).Magnitude
		local chevDepth = math.max(0.4, zoneLenStuds / BOOST_CHEVRONS_PER_ZONE * 0.85)

		for s = 0, BOOST_VIS_SEGS - 1 do
			if pi > BOOST_PAD_POOL then break end
			local bt0 = bz.tStart + zoneLen * (s / BOOST_VIS_SEGS)
			local bt1 = bz.tStart + zoneLen * ((s + 1) / BOOST_VIS_SEGS)
			local posA = spline:CalculatePositionAt(bt0)
			local posB = spline:CalculatePositionAt(bt1)
			local mid = (posA + posB) / 2
			local dir = posB - posA
			local segLen = dir.Magnitude
			if segLen < 0.01 then continue end

			local wM = toWorld(mid)
			local pad = self._pools.boostPad[pi]
			pad.Size = Vector3.new(BOOST_VIS_WIDTH, 0.12, segLen + 0.15)
			pad.CFrame = CFrame.lookAt(wM + Vector3.new(0, 0.03, 0), wM + Vector3.new(0, 0.03, 0) + dir.Unit)
			pad.Transparency = show and 0.25 or 1
			pi = pi + 1
		end

		-- Single row of chevrons (rectangles) down the center, runway chase
		for chevIdx = 0, BOOST_CHEVRONS_PER_ZONE - 1 do
			if chi > BOOST_CHEV_POOL then break end
			local tFrac = (chevIdx + 0.5) / BOOST_CHEVRONS_PER_ZONE
			local chevT = bz.tStart + zoneLen * tFrac
			local chevPos = spline:CalculatePositionAt(chevT)
			local chevDir = spline:CalculateDerivativeAt(chevT)
			if chevDir.Magnitude < 0.001 then continue end
			chevDir = chevDir.Unit
			local wP = toWorld(chevPos)
			local chevCF = CFrame.lookAt(wP + Vector3.new(0, 0.12, 0), wP + Vector3.new(0, 0.12, 0) + chevDir)

			local chev = self._pools.boostChev[chi]
			chev.Size = Vector3.new(BOOST_VIS_WIDTH, 0.18, chevDepth)
			chev.CFrame = chevCF
			if show then
				local behind = (boostChaseHead - chevIdx) % BOOST_CHEVRONS_PER_ZONE
				local intensity
				if behind < 1 then intensity = 1
				elseif behind < 1 + BOOST_FADE_TAIL then intensity = math.max(BOOST_DIM_FLOOR, 1 - (behind - 1) / BOOST_FADE_TAIL)
				else intensity = BOOST_DIM_FLOOR end
				chev.Color = BOOST_OFF_COLOR:Lerp(BOOST_ON_COLOR, intensity)
				chev.Transparency = 1 - intensity * 0.35
				local pl = chev:FindFirstChildOfClass("PointLight")
				if pl then pl.Brightness = intensity * 4 end
			else
				chev.Transparency = 1
				local pl = chev:FindFirstChildOfClass("PointLight")
				if pl then pl.Brightness = 0 end
			end
			chi = chi + 1
		end
	end
	for i = pi, BOOST_PAD_POOL do self._pools.boostPad[i].Transparency = 1 end
	for i = chi, BOOST_CHEV_POOL do
		self._pools.boostChev[i].Transparency = 1
		local pl = self._pools.boostChev[i]:FindFirstChildOfClass("PointLight")
		if pl then pl.Brightness = 0 end
	end

	-- Spectrum visualizer bars (follow spline, Y-scaled per band + chase effect)
	local specTime = time()
	local specLoud = beat
	local halfSpan = (SPEC_BAND_COUNT - 1) * SPEC_BAR_SPACING * 0.5
	local specTCenter = self._t

	local chaseSpeed = RW_CHASE_SPEED * (0.5 + specLoud * 1.5)
	self._rwElapsed = self._rwElapsed + dt * chaseSpeed
	local chaseHead = self._rwElapsed % SPEC_BAND_COUNT

	for i = 1, SPEC_BAND_COUNT do
		local frac = (i - 1) / (SPEC_BAND_COUNT - 1)
		local curve = frac * frac
		local freq = 1.2 + curve * 14
		local phase = i * 1.1
		local target = specLoud * (0.55 + 0.45 * math.sin(specTime * freq + phase))
		target = math.clamp(target, 0, 1)

		local smoothRate = 3 + curve * 22
		local prev = self._specBands[i] or 0
		local smoothed = prev + (target - prev) * math.min(dt * smoothRate, 1)
		self._specBands[i] = smoothed

		local behind = (chaseHead - (i - 1)) % SPEC_BAND_COUNT
		local chaseIntensity
		if behind < 1 then chaseIntensity = 1
		elseif behind < 1 + RW_FADE_TAIL then chaseIntensity = math.max(RW_DIM_FLOOR, 1 - (behind - 1) / RW_FADE_TAIL)
		else chaseIntensity = RW_DIM_FLOOR end

		local h = SPEC_MIN_HEIGHT + smoothed * (SPEC_MAX_HEIGHT - SPEC_MIN_HEIGHT)

		local chaseColor = beatColor:Lerp(Color3.new(1, 1, 1), chaseIntensity * 0.5)

		local zOff = (i - 1) * SPEC_BAR_SPACING - halfSpan
		local specT = math.clamp(specTCenter + zOff / TRACK_LENGTH, 0, 1)
		local sPos = centerSpline:CalculatePositionAt(specT)
		local sDir = centerSpline:CalculateDerivativeAt(specT)
		if sDir.Magnitude < 0.001 then sDir = Vector3.new(0, 0, -1) end
		local wP = toWorld(sPos)
		local fwd = sDir.Unit
		local right = fwd:Cross(Vector3.new(0, 1, 0)).Unit

		local entry = self._specBars[i]
		if entry then
			for _, side in ipairs({ { key = "left", sign = -1 }, { key = "right", sign = 1 } }) do
				local bar = entry[side.key]
				if bar then
					local sidePos = wP + right * side.sign * SPEC_SIDE_OFFSET
					bar.Size = Vector3.new(SPEC_BAR_WIDTH, h, SPEC_BAR_DEPTH)
					bar.Color = chaseColor
					bar.CFrame = CFrame.lookAt(
						sidePos + Vector3.new(0, h * 0.5, 0),
						sidePos + Vector3.new(0, h * 0.5, 0) + fwd
					)
				end
			end
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

	for _, hazard in ipairs(HAZARDS) do hazard._hit = false; hazard._flybyPlayed = false end
	self._laneEntryT = 0
	self._lastEffectiveLane = 2
	self._countdownDrive = true
	self._coinScore = 0
	self._coinsCollected = 0
	self._boostScore = 0
	self._currentBoostTally = 0

	for _, coin in ipairs(COINS) do coin.collected = false; coin._flybyPlayed = false end
	for _, bomb in ipairs(BOMBS) do bomb.collected = false; bomb._flybyPlayed = false end
	self._bombCount = 0
	self._hitFreezeTimer = 0
	self._bombChainActive = false
	self._bombChainTimer = 0
	self._bombChainCount = 0
	self._lastDifficultyTier = nil
	self._difficultyTransitionProgress = 0

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
		elseif input.KeyCode == Enum.KeyCode.Space then
			self:_deployBomb()
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
		if self._running or self._countdownDrive then
			self:_updateMovement(dt)
		end
		self:_updateWorldScroll(dt)
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
		if not coin.collected and coin.lane == lane and coin.t >= self._laneEntryT and self._t >= coin.t and self._t <= coin.t + COIN_SIZE then
			coin.collected = true
			self._coinScore = self._coinScore + COIN_VALUE
			self._coinsCollected = self._coinsCollected + 1
			self.CoinCollected:Fire(self._coinScore, self._coinsCollected)
			self:_spawnBurst(Color3.fromRGB(50, 140, 255), Color3.fromRGB(100, 180, 255))
			playRandomImpactAt(self._lastCFrame and self._lastCFrame.Position or FIXED_MACHINE_POS)
			if self._cameraController then
				self._cameraController:ShakeCamera(1.2, 0.15, 0, 0, 0.15, Vector3.new(0.6, 0.6, 0.1), Vector3.new(0.03, 0.03, 0.02))
			end
		end
	end
end

function LakelandRaceController:_checkBombCollection()
	local lane = self:_getEffectiveLane()
	for _, bomb in ipairs(BOMBS) do
		if not bomb.collected and bomb.lane == lane and bomb.t >= self._laneEntryT and self._t >= bomb.t and self._t <= bomb.t + BOMB_SIZE then
			bomb.collected = true
			self._bombCount = self._bombCount + 1
			self.BombCollected:Fire(self._bombCount)
			self:_spawnBurst(Color3.fromRGB(50, 220, 70), Color3.fromRGB(100, 255, 120))
			if SFX_Impacts then playSoundAt(SFX_Impacts:FindFirstChild("FirePickup"), self._lastCFrame and self._lastCFrame.Position or FIXED_MACHINE_POS) end
			if self._cameraController then
				self._cameraController:ShakeCamera(1.5, 0.12, 0, 0, 0.15, Vector3.new(0.7, 0.7, 0.1), Vector3.new(0.03, 0.03, 0.02))
			end
			return
		end
	end
end

function LakelandRaceController:_deployBomb()
	if self._bombCount <= 0 or self._bombChainActive then return end
	self._bombCount = self._bombCount - 1
	self._bombChainActive = true
	self._bombChainTimer = 0
	self._bombChainCount = 0
	self._bombChainLane = self:_getEffectiveLane()
	self._bombChainStartT = self._t
	self.BombDeployed:Fire()
	if self._cameraController then
		self._cameraController:ShakeCamera(2, 0.08, 0, 0.03, 0.25, Vector3.new(1, 1, 0.2), Vector3.new(0.05, 0.05, 0.03))
	end
end

function LakelandRaceController:_updateBombChain(dt)
	if not self._bombChainActive then return end
	self._bombChainTimer = self._bombChainTimer + dt

	local centerSpline = self._splines[2].spline
	local centerRef = centerSpline:CalculatePositionAt(self._t)

	local interval = BOMB_CHAIN_SPEED / BOMB_CHAIN_LENGTH
	while self._bombChainCount < BOMB_CHAIN_LENGTH and self._bombChainTimer >= interval do
		self._bombChainTimer = self._bombChainTimer - interval
		self._bombChainCount = self._bombChainCount + 1

		local frac = self._bombChainCount / BOMB_CHAIN_LENGTH
		local chainT = self._bombChainStartT + BOMB_CHAIN_T_SPAN * frac
		if chainT > 1 then chainT = chainT - 1 end

		local spline = self._splines[self._bombChainLane].spline
		local pos = spline:CalculatePositionAt(chainT)
		local wP = FIXED_MACHINE_POS + (pos - centerRef)

		local poolIdx = ((self._bombChainCount - 1) % BOMB_CHAIN_POOL) + 1
		local entry = self._bombChainParts[poolIdx]
		entry.active = true
		entry.spawnTime = time()
		entry.part.CFrame = CFrame.new(wP + Vector3.new(0, 2.5, 0))
		entry.part.Size = Vector3.new(0.5, 0.5, 0.5)
		entry.part.Transparency = 0.15
		entry.part.Color = Color3.fromRGB(60, 255, 80)
		entry.part.PointLight.Brightness = 1.5

		for _, hazard in ipairs(HAZARDS) do
			if not hazard._hit and hazard.lane == self._bombChainLane
				and math.abs(hazard.t - chainT) < 0.002 then
				hazard._hit = true
				self:_spawnBurst(Color3.fromRGB(255, 160, 30), Color3.fromRGB(255, 200, 80))
				playRandomImpactAt(wP, 2)
				self._hitFreezeTimer = math.max(self._hitFreezeTimer, BOMB_HIT_FREEZE)
				if self._cameraController then
					self._cameraController:ShakeCamera(2.5, 0.08, 0, 0.04, 0.2, Vector3.new(1.2, 1.2, 0.2), Vector3.new(0.06, 0.06, 0.03))
					self._cameraController:ZoomPunch(BOMB_HIT_ZOOM)
				end
			end
		end

		for _, coin in ipairs(COINS) do
			if not coin.collected and coin.lane == self._bombChainLane
				and math.abs(coin.t - chainT) < 0.002 then
				coin.collected = true
				self._coinScore = self._coinScore + COIN_VALUE
				self._coinsCollected = self._coinsCollected + 1
				self.CoinCollected:Fire(self._coinScore, self._coinsCollected)
				self:_spawnBurst(Color3.fromRGB(50, 140, 255), Color3.fromRGB(100, 180, 255))
				playRandomImpactAt(wP, 2)
				if self._cameraController then
					self._cameraController:ShakeCamera(1.2, 0.15, 0, 0, 0.15, Vector3.new(0.6, 0.6, 0.1), Vector3.new(0.03, 0.03, 0.02))
				end
			end
		end

		for _, bomb in ipairs(BOMBS) do
			if not bomb.collected and bomb.lane == self._bombChainLane
				and math.abs(bomb.t - chainT) < 0.002 then
				bomb.collected = true
				self._bombCount = self._bombCount + 1
				self.BombCollected:Fire(self._bombCount)
				self:_spawnBurst(Color3.fromRGB(50, 220, 70), Color3.fromRGB(100, 255, 120))
				if SFX_Impacts then playSoundAt(SFX_Impacts:FindFirstChild("FirePickup"), wP, 2) end
				if self._cameraController then
					self._cameraController:ShakeCamera(1.5, 0.12, 0, 0, 0.15, Vector3.new(0.7, 0.7, 0.1), Vector3.new(0.03, 0.03, 0.02))
				end
			end
		end
	end

	if self._bombChainCount >= BOMB_CHAIN_LENGTH then
		self._bombChainActive = false
	end
end

---------------------------------------------------------------------------
-- Movement (treadmill: machine stays at FIXED_MACHINE_POS)
---------------------------------------------------------------------------
function LakelandRaceController:_updateMovement(dt)
	local machine = Workspace:FindFirstChild("ActiveMachine")
	if not machine or not machine.PrimaryPart then return end

	if self._bombChainActive then
		self:_updateBombChain(dt)
	end

	if self._hitFreezeTimer > 0 then
		self._hitFreezeTimer = self._hitFreezeTimer - dt
		return
	end

	if self._bombChainActive then
		return
	end

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
			if inBoost then
				self._currentBoostTally = 0
				local boostSfx = SFX_BoostPad and SFX_BoostPad:FindFirstChild("BoostPad")
				if boostSfx then
					if self._boostSfxEmitter then
						self._boostSfxEmitter:Destroy()
						self._boostSfxEmitter = nil
					end
					local sf = math.clamp(self._currentSpeed / MAX_SPEED, 0, 1)
					local emitter = Instance.new("Part")
					emitter.Size = Vector3.new(0.1, 0.1, 0.1)
					emitter.Transparency = 1
					emitter.Anchored = true
					emitter.CanCollide = false
					emitter.CanQuery = false
					emitter.CFrame = CFrame.new(self._lastCFrame and self._lastCFrame.Position or FIXED_MACHINE_POS)
					emitter.Parent = Workspace
					local targetVol = 0.3 + sf * 0.7
					local clone = boostSfx:Clone()
					clone.RollOffMode = Enum.RollOffMode.InverseTapered
					clone.RollOffMinDistance = 20
					clone.RollOffMaxDistance = 200
					clone.Volume = 0
					clone.PlaybackSpeed = 0.75 + sf * 0.5
					clone.Parent = emitter
					clone:Play()
					TweenService:Create(clone, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Volume = targetVol }):Play()
					self._boostSfxEmitter = emitter
				end
			else
				if self._boostSfxEmitter then
					local em = self._boostSfxEmitter
					self._boostSfxEmitter = nil
					local snd = em:FindFirstChildOfClass("Sound")
					if snd then
						TweenService:Create(snd, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Volume = 0 }):Play()
					end
					Debris:AddItem(em, 0.5)
				end
			end
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
			self:_spawnBurst(Color3.fromRGB(255, 50, 50), Color3.fromRGB(255, 100, 100))
			if self._health <= 0 then
				if SFX_Impacts then playSoundAt(SFX_Impacts:FindFirstChild("OnImpactHazardFinal"), self._lastCFrame and self._lastCFrame.Position or FIXED_MACHINE_POS) end
			else
				playRandomImpactAt(self._lastCFrame and self._lastCFrame.Position or FIXED_MACHINE_POS)
			end
			if self._cameraController then
				self._cameraController:ShakeCamera(3, 0.1, 0, 0.05, 0.3, Vector3.new(1.5, 1.5, 0.3), Vector3.new(0.08, 0.08, 0.04))
				local speedFrac = math.clamp((self._currentSpeed - MOVE_SPEED) / (MAX_SPEED - MOVE_SPEED), 0, 1)
				self._cameraController:ZoomPunch(8 + 10 * speedFrac)
			end
			local speedFrac = math.clamp((self._currentSpeed - MOVE_SPEED) / (MAX_SPEED - MOVE_SPEED), 0, 1)
			self._hitFreezeTimer = HIT_FREEZE_BASE + (HIT_FREEZE_MAX - HIT_FREEZE_BASE) * speedFrac
			return
		end

		self:_checkCoinCollection()
		self:_checkBombCollection()
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
-- Cube burst VFX
---------------------------------------------------------------------------
local BURST_COUNT        = 28
local BURST_BASE_SIZE    = Vector3.new(2.8, 2.8, 2.8)
local BURST_BASE_LIFE    = 0.7
local BURST_BASE_SPD_MIN = 140
local BURST_BASE_SPD_MAX = 260
local BURST_SPREAD_ANGLE = math.rad(85)

function LakelandRaceController:_spawnBurst(color, highlightColor)
	local cf = self._lastCFrame
	if not cf then return end

	local origin = cf.Position
	local forward = cf.LookVector
	local right = cf.RightVector
	local up = cf.UpVector

	local folder = self._folder
	if not folder then return end

	local speedFrac = math.clamp(self._currentSpeed / MAX_SPEED, 0, 1)

	local sizeScale = 1 - speedFrac * 0.45
	local cubeSize = BURST_BASE_SIZE * sizeScale
	local lifetime = BURST_BASE_LIFE * (1 - speedFrac * 0.55)
	local spdMin = BURST_BASE_SPD_MIN * (1 + speedFrac * 1.2)
	local spdMax = BURST_BASE_SPD_MAX * (1 + speedFrac * 1.2)

	for i = 1, BURST_COUNT do
		local cube = Instance.new("Part")
		cube.Size = cubeSize * (0.6 + math.random() * 0.8)
		cube.Anchored = false
		cube.CanCollide = false
		cube.Color = color
		cube.Material = Enum.Material.Neon
		cube.Transparency = 0
		cube.Shape = Enum.PartType.Block
		cube.Parent = folder

		local hl = Instance.new("Highlight")
		hl.FillColor = highlightColor
		hl.FillTransparency = 0.4
		hl.OutlineTransparency = 1
		hl.Parent = cube

		local hAngle = (math.random() - 0.5) * 2 * BURST_SPREAD_ANGLE
		local vAngle = (math.random() - 0.5) * BURST_SPREAD_ANGLE
		local dir = (forward + right * math.sin(hAngle) + up * math.sin(vAngle)).Unit
		local speed = spdMin + math.random() * (spdMax - spdMin)

		cube.CFrame = CFrame.new(origin + forward * 3) * CFrame.Angles(
			math.random() * math.pi * 2,
			math.random() * math.pi * 2,
			0
		)
		cube.AssemblyLinearVelocity = dir * speed + Vector3.new(0, math.random() * 15 + 5, 0)
		cube.AssemblyAngularVelocity = Vector3.new(
			(math.random() - 0.5) * 20,
			(math.random() - 0.5) * 20,
			(math.random() - 0.5) * 20
		)

		TweenService:Create(cube, TweenInfo.new(lifetime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Transparency = 1,
			Size = cube.Size * 0.2,
		}):Play()

		Debris:AddItem(cube, lifetime + 0.1)
	end
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
function LakelandRaceController:GetCurrentScore() return math.floor(self._totalDistance * 10) + self._coinScore + math.floor(self._boostScore) end

return LakelandRaceController
