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
local SFX_HyperSpace = SoundService:FindFirstChild("HyperSpace")
local SFX_OnExitHyperSpace = SoundService:FindFirstChild("OnExitHyperSpace")
local SFX_Terrain = SoundService:FindFirstChild("Terrain")

local LakelandSkillTreeUI = require(script.Parent.LakelandSkillTreeUI)

local function playSoundAt(sound, worldPos, volume, pitch)
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
	clone.PlaybackSpeed = pitch or (0.85 + math.random() * 0.3)
	if volume then clone.Volume = volume * sound.Volume end
	clone.Parent = emitter
	clone:Play()
	Debris:AddItem(emitter, (clone.TimeLength / clone.PlaybackSpeed) + 0.5)
end

local function playRandomImpactAt(worldPos, volume, pitch)
	if not SFX_RandomImpact then return end
	local children = SFX_RandomImpact:GetChildren()
	if #children == 0 then return end
	local pick = children[math.random(1, #children)]
	if pick:IsA("Sound") then
		playSoundAt(pick, worldPos, volume, pitch)
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
	clone.Volume = (0.2 + sf * 0.8) * pick.Volume
	clone.PlaybackSpeed = 0.7 + sf * 0.6
	clone.Parent = emitter
	clone:Play()
	Debris:AddItem(emitter, (clone.TimeLength / clone.PlaybackSpeed) + 0.5)
end

local function playGroupOneShot(group, worldPos)
	if not group then return end
	local children = group:GetChildren()
	if #children == 0 then return end
	for _, snd in ipairs(children) do
		if snd:IsA("Sound") then
			playSoundAt(snd, worldPos, 1, 1)
		end
	end
end

local function startGroupLoop(group)
	if not group then return nil end
	local children = group:GetChildren()
	if #children == 0 then return nil end
	local folder = Instance.new("Folder")
	folder.Name = "AmbientLoop_" .. group.Name
	folder.Parent = SoundService
	for _, snd in ipairs(children) do
		if snd:IsA("Sound") then
			local clone = snd:Clone()
			clone.Looped = true
			clone.Volume = 0
			clone.Parent = folder
			clone:Play()
			TweenService:Create(clone, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Volume = snd.Volume }):Play()
		end
	end
	return folder
end

local function stopGroupLoop(container)
	if not container or not container.Parent then return end
	for _, snd in ipairs(container:GetChildren()) do
		if snd:IsA("Sound") then
			TweenService:Create(snd, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Volume = 0 }):Play()
		end
	end
	Debris:AddItem(container, 1)
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
local LATERAL_SPEED = 35

local MAX_BANK_ANGLE = math.rad(12)
local BANK_SMOOTH_SPEED = 14
local LANE_SWITCH_BANK = math.rad(10)

local LANE_SPRING_STIFFNESS = 280
local LANE_SPRING_DAMPING = 18

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

---------------------------------------------------------------------------
-- Portal cubes
---------------------------------------------------------------------------
local PORTAL_SIZE     = 0.0015
local PORTAL_DURATION = 10
local PORTAL_POOL     = 4
local GLOW_PORTAL_COLOR = Color3.fromRGB(200, 0, 255)
local PORTAL_RED = Color3.fromRGB(255, 30, 30)
local PORTAL_HAZARD_BONUS = 100

local PORTALS = {}
do
	local portalPositions = { 0.18, 0.40, 0.62, 0.84 }
	local portalLanes     = { 2, 1, 3, 2 }
	for i, tVal in ipairs(portalPositions) do
		local lane = portalLanes[i]
		local tRound = math.floor(tVal * 10000 + 0.5) / 10000
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
			table.insert(PORTALS, { lane = lane, t = tRound, collected = false })
		end
	end
end

-- Each zone uses 2-3 complementary colors so fog, ambient, tint all unify.
-- accent   = primary neon color (buildings, bars, cubes, beat pulse)
-- accent2  = secondary complement used for subtle variation
-- fog/decay/ambient/ccTint all derived from accent so the whole scene turns one hue.
local TRACK_ZONES = {
	{ -- Deep blue
		from = 0.00, to = 0.16,
		roadColor = Color3.fromRGB(4, 4, 12),
		roadMat = Enum.Material.SmoothPlastic,
		roadAlpha = 0.05,
		accent  = Color3.fromRGB(50, 140, 255),
		accent2 = Color3.fromRGB(100, 180, 255),
		fogColor    = Color3.fromRGB(2, 6, 14),
		fogDecay    = Color3.fromRGB(5, 14, 32),
		ambientTint = Color3.fromRGB(5, 10, 22),
		bloomSize   = 14,
		ccTint      = Color3.fromRGB(195, 210, 255),
	},
	{ -- Cyan / electric blue
		from = 0.16, to = 0.32,
		roadColor = Color3.fromRGB(3, 6, 10),
		roadMat = Enum.Material.SmoothPlastic,
		roadAlpha = 0.05,
		accent  = Color3.fromRGB(0, 210, 255),
		accent2 = Color3.fromRGB(60, 230, 255),
		fogColor    = Color3.fromRGB(1, 10, 14),
		fogDecay    = Color3.fromRGB(2, 22, 30),
		ambientTint = Color3.fromRGB(3, 14, 20),
		bloomSize   = 15,
		ccTint      = Color3.fromRGB(185, 240, 255),
	},
	{ -- Cool silver / ice white
		from = 0.32, to = 0.48,
		roadColor = Color3.fromRGB(6, 6, 10),
		roadMat = Enum.Material.SmoothPlastic,
		roadAlpha = 0.05,
		accent  = Color3.fromRGB(190, 200, 225),
		accent2 = Color3.fromRGB(160, 180, 220),
		fogColor    = Color3.fromRGB(8, 8, 12),
		fogDecay    = Color3.fromRGB(16, 16, 22),
		ambientTint = Color3.fromRGB(12, 12, 18),
		bloomSize   = 12,
		ccTint      = Color3.fromRGB(215, 220, 235),
	},
	{ -- Purple / violet
		from = 0.48, to = 0.64,
		roadColor = Color3.fromRGB(6, 3, 12),
		roadMat = Enum.Material.SmoothPlastic,
		roadAlpha = 0.05,
		accent  = Color3.fromRGB(170, 50, 255),
		accent2 = Color3.fromRGB(200, 100, 255),
		fogColor    = Color3.fromRGB(8, 2, 16),
		fogDecay    = Color3.fromRGB(18, 5, 36),
		ambientTint = Color3.fromRGB(12, 5, 24),
		bloomSize   = 14,
		ccTint      = Color3.fromRGB(220, 195, 255),
	},
	{ -- Emerald / mint green
		from = 0.64, to = 0.80,
		roadColor = Color3.fromRGB(3, 7, 6),
		roadMat = Enum.Material.SmoothPlastic,
		roadAlpha = 0.05,
		accent  = Color3.fromRGB(0, 255, 170),
		accent2 = Color3.fromRGB(50, 255, 200),
		fogColor    = Color3.fromRGB(1, 12, 8),
		fogDecay    = Color3.fromRGB(2, 28, 18),
		ambientTint = Color3.fromRGB(3, 16, 12),
		bloomSize   = 14,
		ccTint      = Color3.fromRGB(185, 255, 225),
	},
	{ -- Hot red / crimson
		from = 0.80, to = 1.00,
		roadColor = Color3.fromRGB(8, 3, 3),
		roadMat = Enum.Material.SmoothPlastic,
		roadAlpha = 0.05,
		accent  = Color3.fromRGB(255, 60, 40),
		accent2 = Color3.fromRGB(255, 120, 60),
		fogColor    = Color3.fromRGB(14, 3, 2),
		fogDecay    = Color3.fromRGB(32, 7, 4),
		ambientTint = Color3.fromRGB(20, 5, 4),
		bloomSize   = 16,
		ccTint      = Color3.fromRGB(255, 200, 195),
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
local LANE_HL_COLOR  = Color3.fromRGB(30, 120, 255)
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
local RW_CHASE_SPEED   = 12
local RW_FADE_TAIL     = 3
local RW_DIM_FLOOR     = 0.08

local SPEC_POOL         = 80
local SPEC_T_STEP       = 0.0005
local SPEC_SIDE_OFFSET  = ROAD_HALF_W + 1
local SPEC_BAR_WIDTH    = 0.6
local SPEC_BAR_GAP      = 0.3
local SPEC_MAX_HEIGHT   = 12
local SPEC_MIN_HEIGHT   = 0.5

---------------------------------------------------------------------------
-- Side buildings
---------------------------------------------------------------------------
local BLDG_POOL         = 120
local BLDG_T_STEP       = 0.0012
local BLDG_OFFSET       = ROAD_HALF_W + 8
local BLDG_WIDTH_MIN    = 5
local BLDG_WIDTH_MAX    = 12
local BLDG_MIN_HEIGHT   = 8
local BLDG_MAX_HEIGHT   = 35
local BLDG_BEAT_EXTRA   = 10

local HYPER = {
	TRIGGER_TIME     = 10,
	DURATION         = 30,
	FADE_IN          = 0.5,
	FADE_OUT         = 1.5,
	FOV              = 110,
	LINE_POOL        = 900,
	LINE_SPEED       = 700,
	LINE_LENGTH_MIN  = 20,
	LINE_LENGTH_MAX  = 60,
	TUNNEL_RADIUS    = 28,
	TUNNEL_THICKNESS = 8,
	LINE_COLORS = {
		Color3.fromRGB(255, 255, 255),
	},
}

local REENTRY_DURATION = 1.6
local REENTRY_FADE_WIDTH = 60

local HYPER_RETURN = {
	DURATION  = 3,
	FADE_IN   = 0.6,
	FADE_OUT  = 1,
}

local TERRAIN_BASE = {
	WIDTH       = 300,
	DEPTH       = 300,
	RESOLUTION  = 4,
	BASE_Y      = -2,
}

local BIOMES = {
	{
		name = "Meadow",
		material = Enum.Material.Grass,
		amp = 10,
		noiseScale = 0.008,
		seed = 42,
		atmosphere = {
			fogColor = Color3.fromRGB(140, 170, 200),
			decay = Color3.fromRGB(180, 160, 130),
			density = 0.15, haze = 1, glare = 0.05,
		},
		bloom = { intensity = 0.03, size = 12, threshold = 1.2 },
		cc = {
			tint = Color3.fromRGB(240, 235, 225),
			brightness = 0.02, contrast = 0.08, saturation = 0.15,
		},
		lighting = {
			clockTime = 14.5,
			brightness = 2,
			ambient = Color3.fromRGB(100, 110, 120),
			outdoorAmbient = Color3.fromRGB(90, 100, 110),
			fogColor = Color3.fromRGB(140, 170, 200),
			fogStart = 150,
			fogEnd = 800,
			envDiffuse = 0.5,
			envSpecular = 0.3,
			globalShadows = true,
		},
	},
	{
		name = "Desert",
		material = Enum.Material.Sand,
		amp = 6,
		noiseScale = 0.005,
		seed = 137,
		atmosphere = {
			fogColor = Color3.fromRGB(235, 200, 140),
			decay = Color3.fromRGB(220, 170, 100),
			density = 0.22, haze = 5, glare = 0.25,
		},
		bloom = { intensity = 0.06, size = 18, threshold = 0.9 },
		cc = {
			tint = Color3.fromRGB(255, 230, 190),
			brightness = 0.06, contrast = 0.12, saturation = 0.0,
		},
		lighting = {
			clockTime = 11,
			brightness = 3,
			ambient = Color3.fromRGB(120, 100, 70),
			outdoorAmbient = Color3.fromRGB(110, 90, 60),
			fogColor = Color3.fromRGB(235, 200, 140),
			fogStart = 80,
			fogEnd = 600,
			envDiffuse = 0.7,
			envSpecular = 0.5,
			globalShadows = true,
		},
	},
	{
		name = "Arctic",
		material = Enum.Material.Glacier,
		amp = 8,
		noiseScale = 0.006,
		seed = 256,
		atmosphere = {
			fogColor = Color3.fromRGB(195, 210, 235),
			decay = Color3.fromRGB(175, 190, 220),
			density = 0.22, haze = 4, glare = 0.08,
		},
		bloom = { intensity = 0.04, size = 14, threshold = 1.0 },
		cc = {
			tint = Color3.fromRGB(215, 228, 250),
			brightness = 0.03, contrast = 0.05, saturation = -0.1,
		},
		lighting = {
			clockTime = 10,
			brightness = 1.8,
			ambient = Color3.fromRGB(100, 115, 140),
			outdoorAmbient = Color3.fromRGB(90, 105, 130),
			fogColor = Color3.fromRGB(195, 210, 235),
			fogStart = 80,
			fogEnd = 600,
			envDiffuse = 0.5,
			envSpecular = 0.6,
			globalShadows = true,
		},
	},
	{
		name = "Volcanic",
		material = Enum.Material.Basalt,
		amp = 15,
		noiseScale = 0.01,
		seed = 404,
		atmosphere = {
			fogColor = Color3.fromRGB(80, 35, 15),
			decay = Color3.fromRGB(130, 55, 20),
			density = 0.25, haze = 4, glare = 0.2,
		},
		bloom = { intensity = 0.06, size = 18, threshold = 0.8 },
		cc = {
			tint = Color3.fromRGB(255, 195, 160),
			brightness = 0.02, contrast = 0.12, saturation = 0.1,
		},
		lighting = {
			clockTime = 17.5,
			brightness = 1.5,
			ambient = Color3.fromRGB(100, 55, 30),
			outdoorAmbient = Color3.fromRGB(90, 45, 25),
			fogColor = Color3.fromRGB(80, 35, 15),
			fogStart = 60,
			fogEnd = 500,
			envDiffuse = 0.3,
			envSpecular = 0.3,
			globalShadows = true,
		},
	},
	{
		name = "Forest",
		material = Enum.Material.LeafyGrass,
		amp = 14,
		noiseScale = 0.009,
		seed = 789,
		atmosphere = {
			fogColor = Color3.fromRGB(70, 110, 70),
			decay = Color3.fromRGB(55, 95, 50),
			density = 0.18, haze = 2, glare = 0.04,
		},
		bloom = { intensity = 0.03, size = 10, threshold = 1.3 },
		cc = {
			tint = Color3.fromRGB(220, 240, 215),
			brightness = 0.02, contrast = 0.08, saturation = 0.2,
		},
		lighting = {
			clockTime = 10,
			brightness = 1.8,
			ambient = Color3.fromRGB(70, 100, 65),
			outdoorAmbient = Color3.fromRGB(60, 90, 55),
			fogColor = Color3.fromRGB(70, 110, 70),
			fogStart = 80,
			fogEnd = 500,
			envDiffuse = 0.5,
			envSpecular = 0.2,
			globalShadows = true,
		},
	},
}

local COMBO_WINDOW = 2.0

local SHOCKWAVE_AMPLITUDE    = 20
local SHOCKWAVE_WAVELENGTH   = 80
local SHOCKWAVE_SPEED        = 600
local SHOCKWAVE_DURATION     = 1.2
local SHOCKWAVE_DAMPEN_START = 0.7
local SHOCKWAVE_COMBO_STEP   = 5

local GLOW_PILLAR_POOL   = 20
local GLOW_PILLAR_SIZE   = Vector3.new(0.15, 20, 0.15)
local GLOW_HAZARD_COLOR  = Color3.fromRGB(255, 50, 50)
local GLOW_COIN_COLOR    = Color3.fromRGB(50, 140, 255)
local GLOW_BOMB_COLOR    = Color3.fromRGB(50, 220, 70)

local AMBIENT_PARTICLE_POOL  = 400
local AMBIENT_PARTICLE_T_STEP = 0.0001
local AMBIENT_SPREAD_X       = ROAD_HALF_W + 12
local AMBIENT_MIN_Y          = 1
local AMBIENT_MAX_Y          = 18
local AMBIENT_SIZE_MIN       = 0.05
local AMBIENT_SIZE_MAX       = 0.25
local AMBIENT_DRIFT_SPEED    = 1.8
local AMBIENT_BEAT_BURST     = 8
local AMBIENT_SYNC_BURST     = 12
local AMBIENT_SYNC_DECAY     = 2.5
local AMBIENT_SYNC_THRESHOLD = 0.55
local AMBIENT_SYNC_CHANCE    = 0.4

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
	_laneSpringPos = 0,
	_laneSpringVel = 0,
	_laneSpringTarget = 0,
	_lateralInput = 0,
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

	_portalActive = false,
	_portalTimer = 0,
	_portalFade = 0,
	_portalRefilling = false,
	_portalRefillT = 1,
	_portalEQ = nil,

	_machineLoadEmitter = nil,
	_boostSfxEmitter = nil,

	_specBars = {},
	_menuRenderConn = nil,
	_demoMode = false,

	_comboCount = 0,
	_comboTimer = 0,

	_shockwaveActive = false,
	_shockwaveTime = 0,
	_shockwaveOriginT = 0,
	_lastShockwaveThreshold = 0,

	_syncBurstDir = Vector3.zero,
	_syncBurstStrength = 0,
	_lastBeatBelow = true,

	_raceElapsed = 0,
	_hyperdriveActive = false,
	_hyperdriveTriggered = false,
	_hyperdriveTimer = 0,
	_hyperdriveBlend = 0,
	_hyperLines = {},
	_hyperLineData = {},
	_hyperBgmVolume = nil,
	_terrainRegion = nil,
	_biomeRegions = {},
	_activeBiome = nil,
	_terrainMode = false,
	_hyperExitBlend = 0,
	_skillTreeUI = nil,

	_savedBlockLighting = nil,
	_hyperSfxEmitter = nil,
	_terrainSfxEmitter = nil,
	_reentryActive = false,
	_reentryTimer = 0,
	_obstacleGraceTimer = 0,
	_waitingForReseat = false,
	_reseatConn = nil,
	_awaitingHyperjump = false,
	_returnHyperActive = false,
	_returnHyperTimer = 0,
	_hyperjumpGui = nil,

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
	if not atmosphere then
		atmosphere = Instance.new("Atmosphere")
		atmosphere.Parent = Lighting
	end
	atmosphere.Density = 0.35
	atmosphere.Offset = 0.25
	atmosphere.Color = Color3.fromRGB(4, 8, 22)
	atmosphere.Decay = Color3.fromRGB(8, 20, 50)
	atmosphere.Glare = 0.1
	atmosphere.Haze = 2
	self._atmosphere = atmosphere

	local bloom = Lighting:FindFirstChild("RaceBloom")
	if not bloom then
		bloom = Instance.new("BloomEffect")
		bloom.Name = "RaceBloom"
		bloom.Parent = Lighting
	end
	bloom.Intensity = 0.015
	bloom.Size = 3
	bloom.Threshold = 2.5
	self._bloom = bloom

	local cc = Lighting:FindFirstChild("RaceCC")
	if not cc then
		cc = Instance.new("ColorCorrectionEffect")
		cc.Name = "RaceCC"
		cc.Parent = Lighting
	end
	cc.Brightness = 0
	cc.Contrast = 0.05
	cc.Saturation = 0.1
	cc.TintColor = Color3.fromRGB(200, 215, 255)
	self._raceCC = cc

	self._envZoneLerp = { fogColor = Color3.fromRGB(4, 8, 22), fogDecay = Color3.fromRGB(8, 20, 50), ambientTint = Color3.fromRGB(10, 14, 28), bloomSize = 16, ccTint = Color3.fromRGB(200, 215, 255) }
end

function LakelandRaceController:_saveBlockSpaceLighting()
	self._savedBlockLighting = {
		clockTime = Lighting.ClockTime,
		brightness = Lighting.Brightness,
		ambient = Lighting.Ambient,
		outdoorAmbient = Lighting.OutdoorAmbient,
		fogColor = Lighting.FogColor,
		fogStart = Lighting.FogStart,
		fogEnd = Lighting.FogEnd,
		globalShadows = Lighting.GlobalShadows,
		envDiffuse = Lighting.EnvironmentDiffuseScale,
		envSpecular = Lighting.EnvironmentSpecularScale,
		atmosphere = self._atmosphere and {
			density = self._atmosphere.Density,
			offset = self._atmosphere.Offset,
			color = self._atmosphere.Color,
			decay = self._atmosphere.Decay,
			glare = self._atmosphere.Glare,
			haze = self._atmosphere.Haze,
		} or nil,
		bloom = self._bloom and {
			intensity = self._bloom.Intensity,
			size = self._bloom.Size,
			threshold = self._bloom.Threshold,
		} or nil,
		cc = self._raceCC and {
			brightness = self._raceCC.Brightness,
			contrast = self._raceCC.Contrast,
			saturation = self._raceCC.Saturation,
			tintColor = self._raceCC.TintColor,
		} or nil,
		envZoneLerp = self._envZoneLerp and {
			fogColor = self._envZoneLerp.fogColor,
			fogDecay = self._envZoneLerp.fogDecay,
			ambientTint = self._envZoneLerp.ambientTint,
			bloomSize = self._envZoneLerp.bloomSize,
			ccTint = self._envZoneLerp.ccTint,
		} or nil,
	}
end

function LakelandRaceController:_restoreBlockSpaceLighting()
	local s = self._savedBlockLighting
	if not s then
		self:_setupDarkEnvironment()
		return
	end

	Lighting.ClockTime = s.clockTime
	Lighting.Brightness = s.brightness
	Lighting.Ambient = s.ambient
	Lighting.OutdoorAmbient = s.outdoorAmbient
	Lighting.FogColor = s.fogColor
	Lighting.FogStart = s.fogStart
	Lighting.FogEnd = s.fogEnd
	Lighting.GlobalShadows = s.globalShadows
	Lighting.EnvironmentDiffuseScale = s.envDiffuse
	Lighting.EnvironmentSpecularScale = s.envSpecular

	if self._atmosphere and s.atmosphere then
		self._atmosphere.Density = s.atmosphere.density
		self._atmosphere.Offset = s.atmosphere.offset
		self._atmosphere.Color = s.atmosphere.color
		self._atmosphere.Decay = s.atmosphere.decay
		self._atmosphere.Glare = s.atmosphere.glare
		self._atmosphere.Haze = s.atmosphere.haze
	end
	if self._bloom and s.bloom then
		self._bloom.Intensity = s.bloom.intensity
		self._bloom.Size = s.bloom.size
		self._bloom.Threshold = s.bloom.threshold
	end
	if self._raceCC and s.cc then
		self._raceCC.Brightness = s.cc.brightness
		self._raceCC.Contrast = s.cc.contrast
		self._raceCC.Saturation = s.cc.saturation
		self._raceCC.TintColor = s.cc.tintColor
	end
	if s.envZoneLerp then
		self._envZoneLerp = {
			fogColor = s.envZoneLerp.fogColor,
			fogDecay = s.envZoneLerp.fogDecay,
			ambientTint = s.envZoneLerp.ambientTint,
			bloomSize = s.envZoneLerp.bloomSize,
			ccTint = s.envZoneLerp.ccTint,
		}
	end

	self._savedBlockLighting = nil
end

function LakelandRaceController:KnitStart()
	self:_setupDarkEnvironment()
	self:_buildSplines()
	self:_initPools()

	self._cameraController = Knit.GetController("LakelandCameraController")

	local gameController = Knit.GetController("LakelandGameController")
	self._gameController = gameController
	self._beatIntensity = gameController:GetBeatIntensity()

	self:_startMenuRenderLoop()

	gameController.GameStateChanged:Connect(function(newState)
		if newState == "COUNTDOWN" then
			self:_stopMenuRenderLoop()
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
		elseif newState == "GAME_OVER" then
			self:StopRace()
			if self._machineLoadEmitter then
				self._machineLoadEmitter:Destroy()
				self._machineLoadEmitter = nil
			end
		elseif newState == "DEMO" then
			self:_stopMenuRenderLoop()
			self._obstaclesVisible = true
			self:PositionAtStart()
			self:StartDemoRace()
		elseif newState == "MENU" then
			self:StopRace()
			if self._machineLoadEmitter then
				self._machineLoadEmitter:Destroy()
				self._machineLoadEmitter = nil
			end
			self:_startMenuRenderLoop()
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
		p.Material = Enum.Material.SmoothPlastic
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

	-- Side buildings
	self._pools.building = {}
	local function makePart(name, mat, col)
		local p = Instance.new("Part")
		p.Name = name
		p.Anchored = true
		p.CanCollide = false
		p.Material = mat
		p.Color = col
		p.Transparency = 1
		p.Parent = folder
		return p
	end
	for i = 1, BLDG_POOL do
		local body = makePart("Building_" .. i, Enum.Material.SmoothPlastic, Color3.fromRGB(8, 10, 20))

		local stripe1 = makePart("Stripe1", Enum.Material.Neon, Color3.fromRGB(50, 140, 255))
		local stripe2 = makePart("Stripe2", Enum.Material.Neon, Color3.fromRGB(50, 140, 255))
		local cap = makePart("Cap", Enum.Material.SmoothPlastic, Color3.fromRGB(12, 16, 30))
		local tower = makePart("Tower", Enum.Material.SmoothPlastic, Color3.fromRGB(6, 8, 16))
		local towerStripe = makePart("TowerStripe", Enum.Material.Neon, Color3.fromRGB(50, 140, 255))
		local antenna = makePart("Antenna", Enum.Material.Neon, Color3.fromRGB(50, 140, 255))

		self._pools.building[i] = {
			body = body,
			stripe1 = stripe1,
			stripe2 = stripe2,
			cap = cap,
			tower = tower,
			towerStripe = towerStripe,
			antenna = antenna,
		}
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
		shell.Material = Enum.Material.SmoothPlastic
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

	self._pools.portal = {}
	for i = 1, PORTAL_POOL do
		self._pools.portal[i] = buildCubeAssembly(
			5.5,
			Color3.fromRGB(80, 0, 160),
			Color3.fromRGB(200, 50, 255),
			Color3.fromRGB(180, 0, 255),
			Color3.fromRGB(160, 30, 255),
			Color3.fromRGB(220, 80, 255),
			30
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
		p.Material = Enum.Material.SmoothPlastic
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
	for i = 1, SPEC_POOL do
		local left = Instance.new("Part")
		left.Anchored = true
		left.CanCollide = false
		left.Material = Enum.Material.Neon
		left.Transparency = 1
		left.Parent = folder

		local right = Instance.new("Part")
		right.Anchored = true
		right.CanCollide = false
		right.Material = Enum.Material.Neon
		right.Transparency = 1
		right.Parent = folder

		self._specBars[i] = { left = left, right = right }
	end

	self._glowPillars = {}
	for i = 1, GLOW_PILLAR_POOL do
		local p = Instance.new("Part")
		p.Name = "GlowPillar_" .. i
		p.Size = GLOW_PILLAR_SIZE
		p.Anchored = true
		p.CanCollide = false
		p.Material = Enum.Material.Neon
		p.Transparency = 1
		p.Parent = folder
		self._glowPillars[i] = p
	end

	self._ambientParticles = {}
	for i = 1, AMBIENT_PARTICLE_POOL do
		local p = Instance.new("Part")
		p.Name = "AmbientParticle_" .. i
		p.Shape = Enum.PartType.Ball
		p.Anchored = true
		p.CanCollide = false
		p.Material = Enum.Material.Neon
		p.Transparency = 1
		p.Parent = folder
		self._ambientParticles[i] = p
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
		table.insert(self._machineLights, { part = anchor, light = pl, baseBrightness = cfg.brightness })
	end

	self._hyperLines = {}
	self._hyperLineData = {}
	for i = 1, HYPER.LINE_POOL do
		local len = HYPER.LINE_LENGTH_MIN + math.random() * (HYPER.LINE_LENGTH_MAX - HYPER.LINE_LENGTH_MIN)
		local p = Instance.new("Part")
		local thick = 0.2 + math.random() * 0.35
		p.Size = Vector3.new(thick, thick, len)
		p.Anchored = true
		p.CanCollide = false
		p.Material = Enum.Material.Neon
		p.Color = HYPER.LINE_COLORS[math.random(1, #HYPER.LINE_COLORS)]
		p.Transparency = 1
		p.CastShadow = false
		p.Parent = folder
		self._hyperLines[i] = p
		local angle = math.random() * math.pi * 2
		local radius = HYPER.TUNNEL_RADIUS + (math.random() - 0.5) * HYPER.TUNNEL_THICKNESS
		self._hyperLineData[i] = {
			offsetX = math.cos(angle) * radius,
			offsetY = math.sin(angle) * radius,
			zOffset = (math.random() - 0.5) * 0.06,
			length = len,
		}
	end

	print("[LakelandRaceController] Pools initialized — treadmill ready")

	task.spawn(function()
		local terrain = Workspace.Terrain
		local cx, cz = FIXED_MACHINE_POS.X, FIXED_MACHINE_POS.Z
		local halfW = TERRAIN_BASE.WIDTH / 2
		local halfD = TERRAIN_BASE.DEPTH / 2
		local res = TERRAIN_BASE.RESOLUTION
		local baseY = TERRAIN_BASE.BASE_Y

		self._biomeRegions = {}

		for i, biome in ipairs(BIOMES) do
			local seed = biome.seed
			local amp = biome.amp
			local nScale = biome.noiseScale

			local function terrainHeight(wx, wz)
				local nx = wx * nScale
				local nz = wz * nScale
				local h = math.noise(nx + seed, nz + seed) * 1.0
					+ math.noise(nx * 2 + seed + 100, nz * 2 + seed + 100) * 0.5
					+ math.noise(nx * 4 + seed + 200, nz * 4 + seed + 200) * 0.25
				return baseY + (h / 1.75 + 0.5) * amp
			end

			for x = cx - halfW, cx + halfW - res, res do
				for z = cz - halfD, cz + halfD - res, res do
					local surfaceY = terrainHeight(x + res / 2, z + res / 2)
					local columnH = math.max(surfaceY - (baseY - 20), res)
					local midY = (baseY - 20 + surfaceY) / 2
					terrain:FillBlock(
						CFrame.new(x + res / 2, midY, z + res / 2),
						Vector3.new(res, columnH, res),
						biome.material
					)
				end
				if math.fmod(x - (cx - halfW), res * 10) < res then
					task.wait()
				end
			end

			local minCorner = Vector3int16.new(
				math.floor((cx - halfW) / res),
				math.floor((baseY - 20) / res),
				math.floor((cz - halfD) / res)
			)
			local maxCorner = Vector3int16.new(
				math.ceil((cx + halfW) / res),
				math.ceil((baseY + amp + 5) / res),
				math.ceil((cz + halfD) / res)
			)
			self._biomeRegions[i] = terrain:CopyRegion(Region3int16.new(minCorner, maxCorner))
			terrain:Clear()
			print("[LakelandRaceController] Biome pre-generated:", biome.name)
			task.wait()
		end

		local chosen = math.random(1, #BIOMES)
		self._activeBiome = BIOMES[chosen]
		self._terrainRegion = self._biomeRegions[chosen]
		print("[LakelandRaceController] Active biome:", self._activeBiome.name)
	end)

	local player = game:GetService("Players").LocalPlayer
	local playerGui = player and player:WaitForChild("PlayerGui", 5)
	if playerGui then
		self._skillTreeUI = LakelandSkillTreeUI.new(playerGui)
	end
end

---------------------------------------------------------------------------
-- Shockwave effect
---------------------------------------------------------------------------
function LakelandRaceController:_triggerShockwave()
	self._shockwaveActive = true
	self._shockwaveTime = 0
	self._shockwaveOriginT = self._t
end

function LakelandRaceController:_updateShockwave(dt)
	if not self._shockwaveActive then return end
	self._shockwaveTime = self._shockwaveTime + dt
	if self._shockwaveTime >= SHOCKWAVE_DURATION then
		self._shockwaveActive = false
		self._shockwaveTime = 0
	end
end

function LakelandRaceController:_getShockwaveOffsetY(elementT)
	if not self._shockwaveActive then return 0 end

	local elapsed = self._shockwaveTime
	local originT = self._shockwaveOriginT

	local distFromOrigin = (elementT - originT) * TRACK_LENGTH
	if distFromOrigin < 0 then return 0 end

	local waveFrontDist = SHOCKWAVE_SPEED * elapsed
	if distFromOrigin > waveFrontDist then return 0 end

	local distAheadOfPlayer = (elementT - self._t) * TRACK_LENGTH
	if distAheadOfPlayer < 0 then return 0 end

	local damping = 1
	if elapsed > SHOCKWAVE_DAMPEN_START then
		local dampFrac = (elapsed - SHOCKWAVE_DAMPEN_START) / (SHOCKWAVE_DURATION - SHOCKWAVE_DAMPEN_START)
		damping = math.max(0, 1 - dampFrac)
	end

	local distBehindFront = waveFrontDist - distFromOrigin
	local envelopeWidth = SHOCKWAVE_WAVELENGTH * 3
	local envelope = math.max(0, 1 - distBehindFront / envelopeWidth)
	local frontEnvelope = math.min(distBehindFront / (SHOCKWAVE_WAVELENGTH * 0.5), 1)

	local phase = (distAheadOfPlayer / SHOCKWAVE_WAVELENGTH) * math.pi * 2
	return SHOCKWAVE_AMPLITUDE * math.sin(phase) * envelope * frontEnvelope * damping
end

---------------------------------------------------------------------------
-- World scroll — repositions all pooled parts each frame
---------------------------------------------------------------------------
function LakelandRaceController:_updateWorldScroll(dt)
	local centerSpline = self._splines[2].spline
	local hBlend
	if self._returnHyperActive and self._reentryActive then
		hBlend = self._hyperdriveBlend
	else
		hBlend = self._terrainMode and 1 or self._hyperdriveBlend
	end

	if hBlend >= 1 then
		if self._folder then
			for _, child in ipairs(self._folder:GetChildren()) do
				if child:IsA("BasePart") then
					child.Transparency = 1
					local pl = child:FindFirstChildOfClass("PointLight")
					if pl then pl.Brightness = 0 end
				end
			end
		end
		for _, entry in ipairs(self._pools.light or {}) do
			entry.part.Transparency = 1
			entry.light.Brightness = 0
		end
		if self._ambientParticles then
			for i = 1, #self._ambientParticles do
				self._ambientParticles[i].Transparency = 1
			end
		end

		if self._cameraController then
			self._cameraController:SetHyperdriveFOV(hBlend)
		end

		if self._terrainMode and not self._returnHyperActive then
			local biome = self._activeBiome or BIOMES[1]
			local atm = biome.atmosphere
			local cc = biome.cc
			local bl = biome.bloom
			local lt = biome.lighting
			if self._atmosphere then
				self._atmosphere.Color = atm.fogColor
				self._atmosphere.Decay = atm.decay
				self._atmosphere.Density = atm.density
				self._atmosphere.Haze = atm.haze
				self._atmosphere.Glare = atm.glare
			end
			if self._bloom and bl then
				self._bloom.Intensity = bl.intensity
				self._bloom.Size = bl.size
				self._bloom.Threshold = bl.threshold
			end
			if self._raceCC then
				self._raceCC.TintColor = cc.tint
				self._raceCC.Brightness = cc.brightness
				self._raceCC.Contrast = cc.contrast
				self._raceCC.Saturation = cc.saturation
			end
			if lt then
				Lighting.ClockTime = lt.clockTime
				Lighting.Brightness = lt.brightness
				Lighting.Ambient = lt.ambient
				Lighting.OutdoorAmbient = lt.outdoorAmbient
				Lighting.FogColor = lt.fogColor
				Lighting.FogStart = lt.fogStart
				Lighting.FogEnd = lt.fogEnd
				Lighting.EnvironmentDiffuseScale = lt.envDiffuse
				Lighting.EnvironmentSpecularScale = lt.envSpecular
				Lighting.GlobalShadows = lt.globalShadows
			end
		else
			if self._atmosphere then
				self._atmosphere.Density = 0.35
				self._atmosphere.Color = Color3.fromRGB(10, 18, 40)
				self._atmosphere.Decay = Color3.fromRGB(15, 30, 70)
				self._atmosphere.Haze = 1.2
				self._atmosphere.Glare = 0.2
			end
			if self._bloom then
				self._bloom.Intensity = 0.15
				self._bloom.Size = 14
				self._bloom.Threshold = 1.0
			end
			if self._raceCC then
				self._raceCC.Saturation = -0.05
				self._raceCC.Brightness = 0.25
				self._raceCC.Contrast = 0.15
				self._raceCC.TintColor = Color3.fromRGB(185, 210, 255)
			end
			Lighting.Brightness = 2
			Lighting.Ambient = Color3.fromRGB(100, 115, 160)
			Lighting.OutdoorAmbient = Color3.fromRGB(80, 95, 140)
			Lighting.EnvironmentDiffuseScale = 0.5
			Lighting.EnvironmentSpecularScale = 0.4
		end
		return
	end

	for _, ml in ipairs(self._machineLights) do
		ml.light.Brightness = ml.baseBrightness * (1 - hBlend)
	end

	local shockActive = self._shockwaveActive
	local function waveVec(tVal)
		if not shockActive then return Vector3.zero end
		local y = self:_getShockwaveOffsetY(tVal)
		if y == 0 then return Vector3.zero end
		return Vector3.new(0, y, 0)
	end

	local centerRef = centerSpline:CalculatePositionAt(self._t) + waveVec(self._t)

	local tMin = math.max(0, self._t - WINDOW_BEHIND)
	local aheadWindow = self._reentryActive and 0.035 or WINDOW_AHEAD
	local tMax = math.min(1, self._t + aheadWindow)

	local beat = self._beatIntensity and self._beatIntensity:get() or 0
	local cubeBeatScale = 1 + beat * 0.7

	local hue = (time() * 0.08) % 1
	local beatColor = Color3.fromHSV(hue, 0.7, 1)
	local portalBlend = self._portalFade
	local function beatAccent(zoneAccent)
		local c = zoneAccent:Lerp(beatColor, beat * 0.85)
		if portalBlend > 0 then
			c = c:Lerp(PORTAL_RED, portalBlend)
		end
		return c
	end
	local function beatAccent2(zone)
		local a2 = zone.accent2 or zone.accent
		local c = a2:Lerp(beatColor, beat * 0.6)
		if portalBlend > 0 then
			c = c:Lerp(PORTAL_RED, portalBlend)
		end
		return c
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
		local posA = centerSpline:CalculatePositionAt(t) + waveVec(t)
		local posB = centerSpline:CalculatePositionAt(t1) + waveVec(t1)
		local mid = (posA + posB) / 2
		local dir = posB - posA
		local segLen = dir.Magnitude
		if segLen > 0.01 then
			local wM = toWorld(mid)
			local road = self._pools.road[ri]
			road.Size = Vector3.new(ROAD_W + 2, 0.25, segLen + 0.5)
			road.CFrame = CFrame.lookAt(wM - Vector3.new(0, 0.15, 0), wM - Vector3.new(0, 0.15, 0) + dir.Unit)
			local rZone = getTrackZone(t)
			local rCol = rZone.roadColor or Color3.fromRGB(5, 5, 10)
			if portalBlend > 0 then
				road.Color = rCol:Lerp(Color3.fromRGB(40, 2, 2), portalBlend)
			else
				road.Color = rCol
			end
			road.Transparency = hBlend
			ri = ri + 1
		end
		t = t + ROAD_T_STEP
	end
	for i = ri, ROAD_POOL do self._pools.road[i].Transparency = 1 end

	-- Lane dividers — active lane lines turn blue
	local li = 1
	local targetLane = self:_getEffectiveLane()
	for laneIdx, laneData in ipairs(self._splines) do
		local spline = laneData.spline
		local isTargetLine = (laneIdx == targetLane)
		local lt = math.floor(tMin / LANE_T_STEP) * LANE_T_STEP
		while lt < tMax and li <= LANE_POOL do
			local lt1 = math.min(lt + LANE_T_STEP, tMax)
			local ltMid = (lt + lt1) / 2
			local zone = getTrackZone(ltMid)
			local posA = spline:CalculatePositionAt(lt) + waveVec(lt)
			local posB = spline:CalculatePositionAt(lt1) + waveVec(lt1)
			local mid = (posA + posB) / 2
			local dir = posB - posA
			local segLen = dir.Magnitude
			if segLen > 0.01 then
				local wM = toWorld(mid)
				local line = self._pools.lane[li]
				line.Size = Vector3.new(0.35, 0.1, segLen + 0.25)
				line.CFrame = CFrame.lookAt(wM + Vector3.new(0, 0.01, 0), wM + Vector3.new(0, 0.01, 0) + dir.Unit)
				if isTargetLine then
					line.Color = LANE_HL_COLOR
					line.Transparency = math.max(0.1, hBlend)
				else
					local accent = beatAccent(zone.accent)
					if tier == "hard" then
						line.Color = accent:Lerp(Color3.fromRGB(255, 80, 80), 0.55 * hardBlend)
						line.Transparency = math.max(0.15 * hardBlend + 0.25 * (1 - hardBlend), hBlend)
					elseif tier == "reprieve" then
						line.Color = accent:Lerp(Color3.fromRGB(140, 220, 255), 0.45)
						line.Transparency = math.max(0.4, hBlend)
					else
						line.Color = accent
						line.Transparency = math.max(0.25, hBlend)
					end
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
		local pos = centerSpline:CalculatePositionAt(tlt) + waveVec(tlt)
		local wP = toWorld(pos)
		local info = self._pools.light[tli]
		info.part.Position = wP + Vector3.new(0, 6, 0)
		local lightCol = (tli % 2 == 0) and beatAccent2(zone) or beatAccent(zone.accent)
		local brightness = 0.6
		if tier == "hard" then
			lightCol = lightCol:Lerp(Color3.fromRGB(255, 80, 80), 0.55 * hardBlend)
			brightness = 0.6 + 0.4 * hardBlend
		elseif tier == "reprieve" then
			lightCol = lightCol:Lerp(Color3.fromRGB(140, 220, 255), 0.45)
			brightness = 0.4
		end
		info.light.Color = lightCol
		info.light.Brightness = brightness * (1 - hBlend)
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
		bar.Transparency = math.max(trans, hBlend)
		bar.PointLight.Color = color
		bar.PointLight.Brightness = bright * (1 - hBlend)
	end

	local tfi = 1
	local tft = math.floor(tMin / TUNNEL_T_STEP) * TUNNEL_T_STEP
	while tft < tMax and tfi <= TUNNEL_POOL do
		local zone = getTrackZone(tft)
		local posA = centerSpline:CalculatePositionAt(tft) + waveVec(tft)
		local tftB = math.min(tft + TUNNEL_T_STEP * 0.1, 1)
		local posB = centerSpline:CalculatePositionAt(tftB) + waveVec(tftB)
		local dir = posB - posA
		if dir.Magnitude > 0.001 then
			local wP = toWorld(posA)
			local fwd = dir.Unit
			local right = fwd:Cross(Vector3.new(0, 1, 0)).Unit
			local up = Vector3.new(0, 1, 0)

			local accent = beatAccent(zone.accent)
			local accent2 = beatAccent2(zone)
			local hardColor = Color3.fromRGB(255, 80, 80)
			local postColor = accent
			local topColor = accent2
			if tier == "hard" then
				postColor = accent:Lerp(hardColor, 0.6 * hardBlend)
				topColor = accent2:Lerp(hardColor, 0.6 * hardBlend)
			elseif tier == "reprieve" then
				postColor = accent:Lerp(Color3.fromRGB(140, 220, 255), 0.45)
				topColor = accent2:Lerp(Color3.fromRGB(140, 220, 255), 0.45)
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

			placeBar(frame.left,  bl, tl, postColor, trans, bright)
			placeBar(frame.top,   tl, tr, topColor, trans, bright)
			placeBar(frame.right, br, tr, postColor, trans, bright)

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
		local posA = centerSpline:CalculatePositionAt(slt) + waveVec(slt)
		local sltB = math.min(slt + SIDE_LASER_T_STEP * 0.1, 1)
		local posB = centerSpline:CalculatePositionAt(sltB) + waveVec(sltB)
		local dir = posB - posA
		if dir.Magnitude > 0.001 then
			local wP = toWorld(posA)
			local fwd = dir.Unit
			local right = fwd:Cross(Vector3.new(0, 1, 0)).Unit
			local up = Vector3.new(0, 1, 0)

			local side = (sli % 2 == 0) and 1 or -1
			local center = wP + right * (SIDE_LASER_OFFSET * side) + up * SIDE_LASER_HEIGHT

			local accent = beatAccent(zone.accent)
			local accent2 = beatAccent2(zone)
			local color = accent
			local color2 = accent2
			if tier == "hard" then
				color = accent:Lerp(Color3.fromRGB(255, 80, 80), 0.6 * hardBlend)
				color2 = accent2:Lerp(Color3.fromRGB(255, 80, 80), 0.6 * hardBlend)
			elseif tier == "reprieve" then
				color = accent:Lerp(Color3.fromRGB(140, 220, 255), 0.45)
				color2 = accent2:Lerp(Color3.fromRGB(140, 220, 255), 0.45)
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
				local barCol = (b % 2 == 0) and color2 or color
				bar.Size = Vector3.new(SIDE_LASER_BAR_THICK, SIDE_LASER_BAR_THICK, SIDE_LASER_RADIUS * 2)
				bar.CFrame = CFrame.lookAt(center, center + planeDir)
				bar.Color = barCol
				bar.Transparency = math.max(1 - slAlpha * pulse, hBlend)
				bar.PointLight.Color = barCol
				bar.PointLight.Brightness = TUNNEL_GLOW_BRIGHT * 0.5 * slAlpha * pulse * (1 - hBlend)
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

	-- Side buildings — varied sci-fi structures packed tightly on both sides
	local bi2 = 1
	local bt = math.floor(tMin / BLDG_T_STEP) * BLDG_T_STEP
	while bt < tMax and bi2 <= BLDG_POOL do
		local bt1 = math.min(bt + BLDG_T_STEP, 1)
		local zone = getTrackZone(bt)
		local posA = centerSpline:CalculatePositionAt(bt) + waveVec(bt)
		local posB = centerSpline:CalculatePositionAt(bt1) + waveVec(bt1)
		local mid = (posA + posB) * 0.5
		local dir = posB - posA
		local segLen = dir.Magnitude
		if segLen > 0.01 then
			local wM = toWorld(mid)
			local fwd = dir.Unit
			local right = fwd:Cross(Vector3.new(0, 1, 0))
			if right.Magnitude > 0.001 then right = right.Unit else right = Vector3.new(1, 0, 0) end

			local accent = beatAccent(zone.accent)
			local accent2 = beatAccent2(zone)

			local seed = bt * 12345.6789
			local h1 = (math.sin(seed) * 43758.5453) % 1
			local h2 = (math.sin(seed * 1.73 + 2.9) * 23421.631) % 1
			local h3 = (math.sin(seed * 2.47 + 5.1) * 67890.123) % 1
			local h4 = (math.sin(seed * 3.19 + 7.7) * 54321.987) % 1
			local h5 = (math.sin(seed * 4.61 + 1.3) * 98765.432) % 1
			local h6 = (math.sin(seed * 5.83 + 3.7) * 31415.926) % 1
			if h1 < 0 then h1 = h1 + 1 end
			if h2 < 0 then h2 = h2 + 1 end
			if h3 < 0 then h3 = h3 + 1 end
			if h4 < 0 then h4 = h4 + 1 end
			if h5 < 0 then h5 = h5 + 1 end
			if h6 < 0 then h6 = h6 + 1 end

			local baseH = BLDG_MIN_HEIGHT + h1 * (BLDG_MAX_HEIGHT - BLDG_MIN_HEIGHT)
			local beatH = beat * beat * BLDG_BEAT_EXTRA
			local h = baseH + beatH
			local w = BLDG_WIDTH_MIN + h2 * (BLDG_WIDTH_MAX - BLDG_WIDTH_MIN)
			local depth = segLen + 0.5

			local hasTower = h4 > 0.4
			local towerW = w * (0.25 + h5 * 0.25)
			local towerH = h * (0.3 + h6 * 0.4)
			local capH = 0.6 + h3 * 0.8

			local bAlpha = 1
			if bt > fadeStart then
				bAlpha = math.clamp(1 - (bt - fadeStart) / (tMax - fadeStart), 0, 1)
			end

			local bodyColor = Color3.fromRGB(8, 10, 20):Lerp(accent2, 0.08 + beat * 0.06)
			local darkBody = Color3.fromRGB(6, 8, 16):Lerp(accent2, 0.05 + beat * 0.04)
			local capColor = Color3.fromRGB(12, 16, 30):Lerp(accent, 0.1 + beat * 0.08)
			local neonAlpha = bAlpha * (0.15 + beat * 0.85)

			for sideIdx = 0, 1 do
				if bi2 > BLDG_POOL then break end
				local side = sideIdx == 0 and -1 or 1
				local lateralOff = BLDG_OFFSET + w * 0.5
				local base = wM + right * (lateralOff * side)
				local center = base + Vector3.new(0, h * 0.5, 0)
				local lookCF = CFrame.lookAt(center, center + fwd)

				local entry = self._pools.building[bi2]

				entry.body.Size = Vector3.new(w, h, depth)
				entry.body.CFrame = lookCF
				entry.body.Color = bodyColor
				entry.body.Transparency = math.max(1 - bAlpha, hBlend)

				local s1H = 0.12 + beat * 0.08
				local s1Y = h * (0.3 + h3 * 0.2)
				entry.stripe1.Size = Vector3.new(w + 0.1, s1H, depth + 0.1)
				entry.stripe1.CFrame = lookCF * CFrame.new(0, s1Y - h * 0.5, 0)
				entry.stripe1.Color = accent
				entry.stripe1.Transparency = math.max(1 - neonAlpha, hBlend)

				local s2Y = h * (0.65 + h5 * 0.2)
				entry.stripe2.Size = Vector3.new(w + 0.1, s1H * 0.7, depth + 0.1)
				entry.stripe2.CFrame = lookCF * CFrame.new(0, s2Y - h * 0.5, 0)
				entry.stripe2.Color = accent2
				entry.stripe2.Transparency = math.max(1 - neonAlpha * 0.7, hBlend)

				local capCenter = base + Vector3.new(0, h + capH * 0.5, 0)
				entry.cap.Size = Vector3.new(w + 1, capH, depth + 0.3)
				entry.cap.CFrame = CFrame.lookAt(capCenter, capCenter + fwd)
				entry.cap.Color = capColor
				entry.cap.Transparency = math.max(1 - bAlpha, hBlend)

				if hasTower then
					local towerCenter = base + Vector3.new(0, h + capH + towerH * 0.5, 0)
					entry.tower.Size = Vector3.new(towerW, towerH, towerW)
					entry.tower.CFrame = CFrame.lookAt(towerCenter, towerCenter + fwd)
					entry.tower.Color = darkBody
					entry.tower.Transparency = math.max(1 - bAlpha, hBlend)

					local tsY = towerH * (0.5 + h6 * 0.3)
					entry.towerStripe.Size = Vector3.new(towerW + 0.1, s1H * 0.5, towerW + 0.1)
					entry.towerStripe.CFrame = CFrame.lookAt(towerCenter, towerCenter + fwd) * CFrame.new(0, tsY - towerH * 0.5, 0)
					entry.towerStripe.Color = accent2
					entry.towerStripe.Transparency = math.max(1 - neonAlpha * 0.6, hBlend)

					local antH = 1.5 + beat * 2
					local antCenter = base + Vector3.new(0, h + capH + towerH + antH * 0.5, 0)
					entry.antenna.Size = Vector3.new(0.15, antH, 0.15)
					entry.antenna.CFrame = CFrame.new(antCenter)
					entry.antenna.Color = accent
					entry.antenna.Transparency = math.max(1 - neonAlpha, hBlend)
				else
					entry.tower.Transparency = 1
					entry.towerStripe.Transparency = 1
					entry.antenna.Transparency = 1
				end

				bi2 = bi2 + 1
			end
		end
		bt = bt + BLDG_T_STEP
	end
	for i = bi2, BLDG_POOL do
		local entry = self._pools.building[i]
		entry.body.Transparency = 1
		entry.stripe1.Transparency = 1
		entry.stripe2.Transparency = 1
		entry.cap.Transparency = 1
		entry.tower.Transparency = 1
		entry.towerStripe.Transparency = 1
		entry.antenna.Transparency = 1
	end

	local function showCubeAssembly(model, cf, show, alpha, beatScale)
		alpha = (alpha or 1) * (1 - hBlend)
		if hBlend > 0.5 then show = false end
		beatScale = beatScale or 1
		local shell = model.PrimaryPart
		local baseSize = model:GetAttribute("BaseSize") or 4
		local coreSize = model:GetAttribute("CoreSize") or (baseSize * 0.45)
		local sy = baseSize * beatScale
		local sxz = baseSize
		local csy = coreSize * beatScale
		local csxz = coreSize
		local yLift = (sy - baseSize) * 0.5

		shell.Size = Vector3.new(sxz, sy, sxz)
		shell.CFrame = cf + Vector3.new(0, yLift, 0)
		shell.Transparency = show and (1 - 0.75 * alpha) or 1

		local hl = shell:FindFirstChildOfClass("Highlight")
		if hl then
			hl.Enabled = show and alpha > 0.1
			if hl.Enabled then hl.FillTransparency = 1 - 0.7 * alpha end
		end
		local liftedCf = cf + Vector3.new(0, yLift, 0)
		for _, child in ipairs(model:GetChildren()) do
			if child == shell or not child:IsA("BasePart") then continue end
			if child.Name == "Core" then
				local spin = (time() * 2.5) % (math.pi * 2)
				child.Size = Vector3.new(csxz, csy, csxz)
				child.CFrame = liftedCf * CFrame.Angles(spin, spin * 0.7, 0)
				child.Transparency = show and (1 - alpha) or 1
			else
				local localOff = child:GetAttribute("LocalOffset")
				if localOff then
					local scaledOff = Vector3.new(localOff.X, localOff.Y * beatScale, localOff.Z)
					child.CFrame = liftedCf * CFrame.new(scaledOff)
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
		for _, child in ipairs(model:GetChildren()) do
			if child:IsA("BasePart") and child ~= shell then
				child.Transparency = 1
			end
		end
	end

	-- Hazards
	local playerT = self._t
	local graceT = self._obstacleGraceTimer > 0 and (playerT + 0.012 * (self._obstacleGraceTimer / 2)) or 0
	local hi = 1
	for _, hazard in ipairs(HAZARDS) do
		if hi > HAZARD_POOL then break end
		if not hazard._hit and hazard.t >= tMin and hazard.t <= tMax then
			local show = self._obstaclesVisible
			if graceT > 0 and hazard.t < graceT then show = false end
			local alpha = 1
			if hazard.t > fadeStart then
				alpha = math.clamp(1 - (hazard.t - fadeStart) / (tMax - fadeStart), 0, 1)
				alpha = alpha * alpha
			end
			local spline = self._splines[hazard.lane].spline
			local pos = spline:CalculatePositionAt(hazard.t) + waveVec(hazard.t)
			local wP = toWorld(pos)
				local hazModel = self._pools.hazard[hi]
			showCubeAssembly(hazModel, CFrame.new(wP + Vector3.new(0, 2.5, 0)), show, alpha, cubeBeatScale)
			if show then
				local pb = portalBlend
				local shell = hazModel.PrimaryPart
				if shell then
					shell.Color = Color3.fromRGB(180, 20, 20):Lerp(Color3.fromRGB(255, 255, 60), pb)
					local hl = shell:FindFirstChildOfClass("Highlight")
					if hl and hl.Enabled then
						hl.FillColor = Color3.fromRGB(255, 50, 50):Lerp(Color3.fromRGB(255, 255, 100), pb)
						hl.OutlineColor = Color3.fromRGB(255, 100, 100):Lerp(Color3.fromRGB(255, 255, 0), pb)
					end
				end
				for _, child in ipairs(hazModel:GetChildren()) do
					if child:IsA("BasePart") and child.Name ~= "Shell" and child.Transparency < 1 then
						if child.Name == "Core" then
							child.Color = Color3.fromRGB(255, 60, 60):Lerp(Color3.fromRGB(255, 255, 0), pb)
						else
							child.Color = Color3.fromRGB(255, 80, 80):Lerp(Color3.fromRGB(255, 255, 0), pb)
						end
					end
				end
			end
			if self._running and not hazard._flybyPlayed and hazard.t <= playerT and not self._hyperdriveActive and not self._terrainMode then
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
			if graceT > 0 and coin.t < graceT then show = false end
			local alpha = 1
			if coin.t > fadeStart then
				alpha = math.clamp(1 - (coin.t - fadeStart) / (tMax - fadeStart), 0, 1)
				alpha = alpha * alpha
			end
			local spline = self._splines[coin.lane].spline
			local pos = spline:CalculatePositionAt(coin.t) + waveVec(coin.t)
			local wP = toWorld(pos)
			showCubeAssembly(self._pools.coin[ci], CFrame.new(wP + Vector3.new(0, 2.5, 0)), show, alpha, cubeBeatScale)
			if self._running and not coin._flybyPlayed and coin.t <= playerT and not self._hyperdriveActive and not self._terrainMode then
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
			if graceT > 0 and bomb.t < graceT then show = false end
			local alpha = 1
			if bomb.t > fadeStart then
				alpha = math.clamp(1 - (bomb.t - fadeStart) / (tMax - fadeStart), 0, 1)
				alpha = alpha * alpha
			end
			local spline = self._splines[bomb.lane].spline
			local pos = spline:CalculatePositionAt(bomb.t) + waveVec(bomb.t)
			local wP = toWorld(pos)
			showCubeAssembly(self._pools.bomb[bi], CFrame.new(wP + Vector3.new(0, 2.5, 0)), show, alpha, cubeBeatScale)
			if self._running and not bomb._flybyPlayed and bomb.t <= playerT and not self._hyperdriveActive and not self._terrainMode then
				bomb._flybyPlayed = true
				playRandomFlybyAt(wP + Vector3.new(0, 2.5, 0), self._currentSpeed / MAX_SPEED)
			end
			bi = bi + 1
		end
	end
	for i = bi, BOMB_PICKUP_POOL do hideCubeAssembly(self._pools.bomb[i]) end

	-- Portal pickups (hidden during portal mode)
	local pi2 = 1
	if not self._portalActive then
		for _, portal in ipairs(PORTALS) do
			if pi2 > PORTAL_POOL then break end
			if not portal.collected and portal.t >= tMin and portal.t <= tMax then
				local show = self._obstaclesVisible
				if graceT > 0 and portal.t < graceT then show = false end
				local alpha = 1
				if portal.t > fadeStart then
					alpha = math.clamp(1 - (portal.t - fadeStart) / (tMax - fadeStart), 0, 1)
					alpha = alpha * alpha
				end
				local spline = self._splines[portal.lane].spline
				local pos = spline:CalculatePositionAt(portal.t) + waveVec(portal.t)
				local wP = toWorld(pos)
				showCubeAssembly(self._pools.portal[pi2], CFrame.new(wP + Vector3.new(0, 2.5, 0)), show, alpha, cubeBeatScale)
				if self._running and not portal._flybyPlayed and portal.t <= playerT and not self._hyperdriveActive and not self._terrainMode then
					portal._flybyPlayed = true
					playRandomFlybyAt(wP + Vector3.new(0, 2.5, 0), self._currentSpeed / MAX_SPEED)
				end
				pi2 = pi2 + 1
			end
		end
	end
	for i = pi2, PORTAL_POOL do hideCubeAssembly(self._pools.portal[i]) end

	-- Anticipation glow pillars above cubes ahead of player
	local gi = 1
	if self._obstaclesVisible then
		local function placeGlow(blockT, lane, color)
			if gi > GLOW_PILLAR_POOL then return end
			if blockT <= self._t then return end
			local spline = self._splines[lane].spline
			local pos = spline:CalculatePositionAt(blockT) + waveVec(blockT)
			local wP = toWorld(pos)
			local dist01 = math.clamp((blockT - self._t) / WINDOW_AHEAD, 0, 1)
			local pillar = self._glowPillars[gi]
			pillar.CFrame = CFrame.new(wP + Vector3.new(0, GLOW_PILLAR_SIZE.Y * 0.5 + 2.5, 0))
			pillar.Color = color
			pillar.Transparency = math.max(0.5 + dist01 * 0.4, hBlend)
			gi = gi + 1
		end
		for _, hazard in ipairs(HAZARDS) do
			if not hazard._hit and hazard.t >= tMin and hazard.t <= tMax and not (graceT > 0 and hazard.t < graceT) then
				placeGlow(hazard.t, hazard.lane, GLOW_HAZARD_COLOR)
			end
		end
		for _, coin in ipairs(COINS) do
			if not coin.collected and coin.t >= tMin and coin.t <= tMax and not (graceT > 0 and coin.t < graceT) then
				placeGlow(coin.t, coin.lane, GLOW_COIN_COLOR)
			end
		end
		for _, bomb in ipairs(BOMBS) do
			if not bomb.collected and bomb.t >= tMin and bomb.t <= tMax and not (graceT > 0 and bomb.t < graceT) then
				placeGlow(bomb.t, bomb.lane, GLOW_BOMB_COLOR)
			end
		end
		if not self._portalActive then
			for _, portal in ipairs(PORTALS) do
				if not portal.collected and portal.t >= tMin and portal.t <= tMax and not (graceT > 0 and portal.t < graceT) then
					placeGlow(portal.t, portal.lane, GLOW_PORTAL_COLOR)
				end
			end
		end
	end
	for i = gi, GLOW_PILLAR_POOL do
		self._glowPillars[i].Transparency = 1
	end

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
			ind.Transparency = math.max(0.15, hBlend)
			ind.PointLight.Brightness = (1.2 + 0.4 * math.sin(time() * 4 + i)) * (1 - hBlend)
		else
			ind.Transparency = 1
			ind.PointLight.Brightness = 0
		end
	end

	-- Bomb chain animation
	local now = time()
	local chainSpin = beat * beat * math.pi * 2
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
				local pos = entry.part.Position
				entry.part.CFrame = CFrame.new(pos) * CFrame.Angles(chainSpin, chainSpin * 0.7, chainSpin * 0.4)
				entry.part.Transparency = math.max(1 - fade * 0.85, hBlend)
				entry.part.PointLight.Brightness = 1.5 * fade * (1 - hBlend)
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
			local posA = spline:CalculatePositionAt(bt0) + waveVec(bt0)
			local posB = spline:CalculatePositionAt(bt1) + waveVec(bt1)
			local mid = (posA + posB) / 2
			local dir = posB - posA
			local segLen = dir.Magnitude
			if segLen < 0.01 then continue end

			local wM = toWorld(mid)
			local pad = self._pools.boostPad[pi]
			pad.Size = Vector3.new(BOOST_VIS_WIDTH, 0.12, segLen + 0.15)
			pad.CFrame = CFrame.lookAt(wM + Vector3.new(0, 0.03, 0), wM + Vector3.new(0, 0.03, 0) + dir.Unit)
			pad.Transparency = show and math.max(0.25, hBlend) or 1
			pi = pi + 1
		end

		-- Single row of chevrons (rectangles) down the center, runway chase
		for chevIdx = 0, BOOST_CHEVRONS_PER_ZONE - 1 do
			if chi > BOOST_CHEV_POOL then break end
			local tFrac = (chevIdx + 0.5) / BOOST_CHEVRONS_PER_ZONE
			local chevT = bz.tStart + zoneLen * tFrac
			local chevPos = spline:CalculatePositionAt(chevT) + waveVec(chevT)
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
				chev.Transparency = math.max(1 - intensity * 0.35, hBlend)
				local pl = chev:FindFirstChildOfClass("PointLight")
				if pl then pl.Brightness = intensity * 4 * (1 - hBlend) end
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

	-- Spectrum visualizer bars — span entire visible track, no gaps, scroll past player
	local specNow = time()
	local sbi = 1
	local sbt = math.floor(tMin / SPEC_T_STEP) * SPEC_T_STEP
	local chaseSpeed = RW_CHASE_SPEED * (0.5 + beat * 1.5)
	self._rwElapsed = self._rwElapsed + dt * chaseSpeed

	while sbt < tMax and sbi <= SPEC_POOL do
		local sbt1 = math.min(sbt + SPEC_T_STEP, 1)
		local posA = centerSpline:CalculatePositionAt(sbt) + waveVec(sbt)
		local posB = centerSpline:CalculatePositionAt(sbt1) + waveVec(sbt1)
		local mid = (posA + posB) * 0.5
		local dir = posB - posA
		local segLen = dir.Magnitude
		if segLen > 0.01 then
			local wM = toWorld(mid)
			local fwd = dir.Unit
			local right = fwd:Cross(Vector3.new(0, 1, 0))
			if right.Magnitude > 0.001 then right = right.Unit else right = Vector3.new(1, 0, 0) end

			local zone = getTrackZone(sbt)
			local accent = beatAccent(zone.accent)
			local accent2 = beatAccent2(zone)

			local seed = sbt * 9973.71
			local h1 = (math.sin(seed) * 43758.5453) % 1
			if h1 < 0 then h1 = h1 + 1 end
			local freq = 2 + h1 * 12
			local phase = seed * 1.7
			local wave = 0.55 + 0.45 * math.sin(specNow * freq + phase)
			local intensity = beat * wave

			local chasePhase = (self._rwElapsed - sbt * 500) % 20
			local chaseGlow
			if chasePhase < 1 then chaseGlow = 1
			elseif chasePhase < 1 + RW_FADE_TAIL then chaseGlow = math.max(RW_DIM_FLOOR, 1 - (chasePhase - 1) / RW_FADE_TAIL)
			else chaseGlow = RW_DIM_FLOOR end

			local h = SPEC_MIN_HEIGHT + intensity * (SPEC_MAX_HEIGHT - SPEC_MIN_HEIGHT)
			local depth = math.max(segLen * SPEC_BAR_GAP, 0.3)

			local barColor = accent:Lerp(accent2, chaseGlow * 0.6)
			if portalBlend > 0 then
				local fireSeed = sbt * 5471.3
				local fireFlicker = 0.5 + 0.5 * math.sin(specNow * (8 + ((math.sin(fireSeed) * 43758.5453) % 1) * 12) + fireSeed)
				local fireColor = Color3.fromRGB(255, 60, 10):Lerp(Color3.fromRGB(255, 160, 30), fireFlicker)
				barColor = barColor:Lerp(fireColor, portalBlend)
			end

			local sbAlpha = 1
			if sbt > fadeStart then
				sbAlpha = math.clamp(1 - (sbt - fadeStart) / (tMax - fadeStart), 0, 1)
			end

			local entry = self._specBars[sbi]
			for _, side in ipairs({ { key = "left", sign = -1 }, { key = "right", sign = 1 } }) do
				local bar = entry[side.key]
				local sidePos = wM + right * (side.sign * SPEC_SIDE_OFFSET)
				local center = sidePos + Vector3.new(0, h * 0.5, 0)
				bar.Size = Vector3.new(SPEC_BAR_WIDTH, h, depth)
				bar.Color = barColor
				bar.Transparency = math.max(1 - sbAlpha, hBlend)
				bar.CFrame = CFrame.lookAt(center, center + fwd)
			end
			sbi = sbi + 1
		end
		sbt = sbt + SPEC_T_STEP
	end
	for i = sbi, SPEC_POOL do
		self._specBars[i].left.Transparency = 1
		self._specBars[i].right.Transparency = 1
	end

	-- Synchronized particle burst: on strong beats, randomly pick a cardinal direction
	if beat >= AMBIENT_SYNC_THRESHOLD and self._lastBeatBelow then
		if math.random() < AMBIENT_SYNC_CHANCE then
			local dirs = {
				Vector3.new(1, 0, 0),
				Vector3.new(-1, 0, 0),
				Vector3.new(0, 1, 0),
				Vector3.new(0, -1, 0),
			}
			self._syncBurstDir = dirs[math.random(#dirs)]
			self._syncBurstStrength = 1
		end
	end
	self._lastBeatBelow = beat < AMBIENT_SYNC_THRESHOLD
	self._syncBurstStrength = math.max(0, self._syncBurstStrength - dt * AMBIENT_SYNC_DECAY)
	local syncOffset = self._syncBurstDir * (self._syncBurstStrength * AMBIENT_SYNC_BURST)

	-- Ambient particles drifting toward the player
	local api = 1
	local apt = math.floor(tMin / AMBIENT_PARTICLE_T_STEP) * AMBIENT_PARTICLE_T_STEP
	local apNow = time()
	while apt < tMax and api <= AMBIENT_PARTICLE_POOL do
		local seed = apt * 7919
		local hash1 = (math.sin(seed) * 43758.5453) % 1
		local hash2 = (math.sin(seed * 1.37 + 1.7) * 23421.631) % 1
		local hash3 = (math.sin(seed * 2.91 + 3.1) * 12345.789) % 1
		if hash1 < 0 then hash1 = hash1 + 1 end
		if hash2 < 0 then hash2 = hash2 + 1 end
		if hash3 < 0 then hash3 = hash3 + 1 end

		local lateralOffset = (hash1 - 0.5) * 2 * AMBIENT_SPREAD_X
		local heightOffset = AMBIENT_MIN_Y + hash2 * (AMBIENT_MAX_Y - AMBIENT_MIN_Y)
		local size = AMBIENT_SIZE_MIN + hash3 * (AMBIENT_SIZE_MAX - AMBIENT_SIZE_MIN)

		local driftX = math.sin(apNow * AMBIENT_DRIFT_SPEED + seed) * 1.5
		local driftY = math.cos(apNow * AMBIENT_DRIFT_SPEED * 0.7 + seed * 1.3) * 0.8

		local hash4 = (math.sin(seed * 3.73 + 5.9) * 67890.123) % 1
		local hash5 = (math.sin(seed * 4.19 + 7.3) * 54321.987) % 1
		local hash6 = (math.sin(seed * 5.61 + 2.1) * 98765.432) % 1
		if hash4 < 0 then hash4 = hash4 + 1 end
		if hash5 < 0 then hash5 = hash5 + 1 end
		if hash6 < 0 then hash6 = hash6 + 1 end
		local burstDirX = (hash4 - 0.5) * 2
		local burstDirY = (hash5 - 0.5) * 2
		local burstDirZ = (hash6 - 0.5) * 2
		local burstMag = beat * beat * AMBIENT_BEAT_BURST
		local burstX = burstDirX * burstMag
		local burstY = burstDirY * burstMag
		local burstZ = burstDirZ * burstMag

		local sPos = centerSpline:CalculatePositionAt(apt) + waveVec(apt)
		local wP = toWorld(sPos)
		local sDir = centerSpline:CalculateDerivativeAt(apt)
		if sDir.Magnitude < 0.001 then sDir = Vector3.new(0, 0, -1) end
		local apFwd = sDir.Unit
		local apRight = apFwd:Cross(Vector3.new(0, 1, 0))
		if apRight.Magnitude > 0.001 then apRight = apRight.Unit else apRight = Vector3.new(1, 0, 0) end

		local particlePos = wP + apRight * (lateralOffset + driftX + burstX) + Vector3.new(0, heightOffset + driftY + burstY, 0) + apFwd * burstZ + syncOffset

		local distFrac = math.clamp((apt - tMin) / (tMax - tMin), 0, 1)
		local fadeAlpha = 1
		if distFrac > 0.7 then
			fadeAlpha = 1 - (distFrac - 0.7) / 0.3
		elseif distFrac < 0.1 then
			fadeAlpha = distFrac / 0.1
		end

		local particle = self._ambientParticles[api]
		particle.Size = Vector3.new(size, size, size)
		particle.CFrame = CFrame.new(particlePos)
		particle.Color = Color3.new(1, 1, 1)
		local beatOpacity = 0.15 + beat * beat * 0.85
		particle.Transparency = math.max(1 - fadeAlpha * beatOpacity, hBlend)
		api = api + 1
		apt = apt + AMBIENT_PARTICLE_T_STEP
	end
	for i = api, AMBIENT_PARTICLE_POOL do
		self._ambientParticles[i].Transparency = 1
	end

	-- Dynamic atmosphere — lerp post-processing toward current zone, pulse with beat
	local playerZone = getTrackZone(self._t)
	if playerZone.fogColor then
		local env = self._envZoneLerp
		local lerpRate = math.min(dt * 1.8, 1)
		env.fogColor = env.fogColor:Lerp(playerZone.fogColor, lerpRate)
		env.fogDecay = env.fogDecay:Lerp(playerZone.fogDecay, lerpRate)
		env.ambientTint = env.ambientTint:Lerp(playerZone.ambientTint, lerpRate)
		env.bloomSize = env.bloomSize + (playerZone.bloomSize - env.bloomSize) * lerpRate
		env.ccTint = env.ccTint:Lerp(playerZone.ccTint, lerpRate)

		local beatSq = beat * beat
		local beatPulse = beatSq * 0.35
		local pb = portalBlend

		local accentPrimary = playerZone.accent
		local accentSecondary = playerZone.accent2 or playerZone.accent
		if pb > 0 then
			accentPrimary = accentPrimary:Lerp(PORTAL_RED, pb)
			accentSecondary = accentSecondary:Lerp(PORTAL_RED, pb)
		end

		if self._atmosphere then
			local baseFog = env.fogColor
			if pb > 0 then baseFog = baseFog:Lerp(Color3.fromRGB(18, 2, 2), pb) end
			local pulsedFog = baseFog:Lerp(accentPrimary, beatPulse * 0.3)
			self._atmosphere.Color = pulsedFog
			local baseDecay = env.fogDecay
			if pb > 0 then baseDecay = baseDecay:Lerp(Color3.fromRGB(40, 6, 4), pb) end
			self._atmosphere.Decay = baseDecay:Lerp(accentSecondary, beatPulse * 0.15)
			self._atmosphere.Density = 0.35 + beatSq * 0.1 + pb * 0.08
			self._atmosphere.Haze = 2 + beatSq * 1.5 + pb * 1
			self._atmosphere.Glare = 0.1 + beatSq * 0.15 + pb * 0.1
		end

		if self._bloom then
			self._bloom.Size = math.min(env.bloomSize, 3) + beatSq * 0.8
			self._bloom.Intensity = 0.015 + beatSq * 0.025 + pb * 0.01
			self._bloom.Threshold = 2.5 - beatSq * 0.04 - pb * 0.02
		end

		if self._raceCC then
			local tint = env.ccTint
			if pb > 0 then tint = tint:Lerp(Color3.fromRGB(255, 180, 170), pb) end
			self._raceCC.TintColor = tint
			self._raceCC.Brightness = beatSq * 0.04 + pb * 0.02
			self._raceCC.Contrast = 0.05 + beatSq * 0.08 + pb * 0.05
			self._raceCC.Saturation = 0.1 + beatSq * 0.15 + pb * 0.1
		end

		local tintedAmbient = env.ambientTint:Lerp(accentPrimary, beatPulse * 0.2)
		Lighting.Ambient = tintedAmbient
		Lighting.OutdoorAmbient = Color3.new(
			tintedAmbient.R * 0.7,
			tintedAmbient.G * 0.7,
			tintedAmbient.B * 0.7
		)
		Lighting.FogColor = env.fogColor
	end

	if hBlend > 0 then
		if self._atmosphere then
			self._atmosphere.Density = self._atmosphere.Density + hBlend * 0.4
		end
		if self._raceCC then
			self._raceCC.Saturation = self._raceCC.Saturation - hBlend * 0.3
			self._raceCC.Brightness = self._raceCC.Brightness - hBlend * 0.05
		end
	end

	if self._cameraController then
		self._cameraController:SetHyperdriveFOV(hBlend)
	end

	if self._terrainMode and not self._reentryActive then
		local biome = self._activeBiome or BIOMES[1]
		local atm = biome.atmosphere
		local cc = biome.cc
		local bl = biome.bloom
		local lt = biome.lighting
		if self._atmosphere then
			self._atmosphere.Color = atm.fogColor
			self._atmosphere.Decay = atm.decay
			self._atmosphere.Density = atm.density
			self._atmosphere.Haze = atm.haze
			self._atmosphere.Glare = atm.glare
		end
		if self._bloom and bl then
			self._bloom.Intensity = bl.intensity
			self._bloom.Size = bl.size
			self._bloom.Threshold = bl.threshold
		end
		if self._raceCC then
			self._raceCC.TintColor = cc.tint
			self._raceCC.Brightness = cc.brightness
			self._raceCC.Contrast = cc.contrast
			self._raceCC.Saturation = cc.saturation
		end
		if lt then
			Lighting.ClockTime = lt.clockTime
			Lighting.Brightness = lt.brightness
			Lighting.Ambient = lt.ambient
			Lighting.OutdoorAmbient = lt.outdoorAmbient
			Lighting.FogColor = lt.fogColor
			Lighting.FogStart = lt.fogStart
			Lighting.FogEnd = lt.fogEnd
			Lighting.EnvironmentDiffuseScale = lt.envDiffuse
			Lighting.EnvironmentSpecularScale = lt.envSpecular
			Lighting.GlobalShadows = lt.globalShadows
		end
	end

	if self._reentryActive and self._folder then
		local progress = math.clamp(self._reentryTimer / REENTRY_DURATION, 0, 1)
		progress = progress * progress * (3 - 2 * progress)

		local fwd = centerSpline:CalculateDerivativeAt(self._t)
		if fwd.Magnitude > 0.001 then fwd = fwd.Unit else fwd = Vector3.new(0, 0, -1) end

		local maxDist = 600
		local sweepPos = maxDist * (1 - progress)

		local function computeReveal(pos)
			local dist = (pos - FIXED_MACHINE_POS):Dot(fwd)
			if dist >= sweepPos then
				return 1
			elseif dist >= sweepPos - REENTRY_FADE_WIDTH then
				return (dist - (sweepPos - REENTRY_FADE_WIDTH)) / REENTRY_FADE_WIDTH
			end
			return 0
		end

		for _, child in ipairs(self._folder:GetChildren()) do
			if child:IsA("BasePart") then
				local revealAlpha = computeReveal(child.Position)
				child.Transparency = math.max(child.Transparency, 1 - revealAlpha)
				local pl = child:FindFirstChildOfClass("PointLight")
				if pl and revealAlpha < 1 then
					pl.Brightness = pl.Brightness * revealAlpha
				end
			elseif child:IsA("Model") then
				local anchor = child.PrimaryPart
				if not anchor then
					local first = child:FindFirstChildWhichIsA("BasePart")
					if first then anchor = first end
				end
				if anchor then
					local revealAlpha = computeReveal(anchor.Position)
					for _, desc in ipairs(child:GetDescendants()) do
						if desc:IsA("BasePart") then
							desc.Transparency = math.max(desc.Transparency, 1 - revealAlpha)
						elseif desc:IsA("PointLight") and revealAlpha < 1 then
							desc.Brightness = desc.Brightness * revealAlpha
						elseif desc:IsA("Highlight") then
							if revealAlpha < 0.5 then
								desc.Enabled = false
							end
						end
					end
				end
			end
		end

		for _, ml in ipairs(self._machineLights) do
			local nearReveal = math.clamp(progress * 1.5 - 0.3, 0, 1)
			ml.light.Brightness = ml.baseBrightness * nearReveal
		end
	end

end

---------------------------------------------------------------------------
-- Hyperdrive speed lines
---------------------------------------------------------------------------
function LakelandRaceController:_updateHyperdriveLines(dt)
	local blend
	if self._returnHyperActive then
		blend = self._hyperdriveBlend
	elseif self._terrainMode then
		blend = self._hyperExitBlend
	else
		blend = self._hyperdriveBlend
	end
	if blend <= 0 then
		for i = 1, HYPER.LINE_POOL do
			if self._hyperLines[i] then self._hyperLines[i].Transparency = 1 end
		end
		return
	end

	local centerSpline = self._splines[2].spline
	local playerT = self._t
	local centerRef = centerSpline:CalculatePositionAt(playerT)
	local tRange = 0.06
	local tSpeed = HYPER.LINE_SPEED / TRACK_LENGTH

	for i = 1, HYPER.LINE_POOL do
		local part = self._hyperLines[i]
		local data = self._hyperLineData[i]
		if not part or not data then continue end

		data.zOffset = data.zOffset - tSpeed * dt
		if data.zOffset < -tRange * 0.5 then
			data.zOffset = data.zOffset + tRange
		end

		local sampleT = playerT + data.zOffset
		if sampleT < 0 or sampleT > 1 then
			part.Transparency = 1
			continue
		end

		local splinePos = centerSpline:CalculatePositionAt(sampleT)
		local deriv = centerSpline:CalculateDerivativeAt(sampleT)
		if deriv.Magnitude < 0.001 then
			part.Transparency = 1
			continue
		end

		local fwd = deriv.Unit
		local worldUp = Vector3.new(0, 1, 0)
		local right = fwd:Cross(worldUp)
		if right.Magnitude < 0.001 then right = Vector3.new(1, 0, 0) else right = right.Unit end
		local up = right:Cross(fwd).Unit

		local worldPos = FIXED_MACHINE_POS + (splinePos - centerRef) + right * data.offsetX + up * data.offsetY
		part.CFrame = CFrame.lookAt(worldPos, worldPos + fwd)
		part.Transparency = 1 - blend
	end
end

---------------------------------------------------------------------------
-- Obstacle visibility (flag checked by scroll)
---------------------------------------------------------------------------
function LakelandRaceController:_setObstacleVisibility(show)
	self._obstaclesVisible = show
end

---------------------------------------------------------------------------
-- Player re-seated on terrain -> show hyperjump button
---------------------------------------------------------------------------
function LakelandRaceController:_onPlayerReseated()
	self._awaitingHyperjump = true

	if self._cameraController then
		self._cameraController:_activate()
	end

	local player = game:GetService("Players").LocalPlayer
	local humanoid = player and player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.WalkSpeed = 0
		humanoid.JumpHeight = 0
		humanoid.JumpPower = 0
	end

	local playerGui = player and player:FindFirstChildOfClass("PlayerGui")
	if not playerGui then return end

	if self._hyperjumpGui then
		self._hyperjumpGui:Destroy()
		self._hyperjumpGui = nil
	end

	local sg = Instance.new("ScreenGui")
	sg.Name = "HyperjumpButton"
	sg.ResetOnSpawn = false
	sg.IgnoreGuiInset = true
	sg.DisplayOrder = 65
	sg.Parent = playerGui
	self._hyperjumpGui = sg

	local btn = Instance.new("TextButton")
	btn.Name = "JumpBtn"
	btn.AnchorPoint = Vector2.new(0.5, 1)
	btn.Position = UDim2.fromScale(0.5, 1.1)
	btn.Size = UDim2.fromScale(0.22, 0.055)
	btn.BackgroundColor3 = Color3.fromRGB(8, 14, 28)
	btn.BackgroundTransparency = 0.1
	btn.Text = "JUMP TO HYPERSPACE"
	btn.TextColor3 = Color3.fromRGB(0, 200, 255)
	btn.Font = Enum.Font.GothamBold
	btn.TextScaled = true
	btn.BorderSizePixel = 0
	btn.AutoButtonColor = false
	btn.ZIndex = 2
	btn.Parent = sg

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.35, 0)
	corner.Parent = btn

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(0, 200, 255)
	stroke.Thickness = 2
	stroke.Transparency = 0.15
	stroke.Parent = btn

	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0.1, 0)
	pad.PaddingBottom = UDim.new(0.1, 0)
	pad.Parent = btn

	TweenService:Create(btn, TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Position = UDim2.fromScale(0.5, 0.92),
	}):Play()

	btn.MouseEnter:Connect(function()
		TweenService:Create(stroke, TweenInfo.new(0.12), { Thickness = 3, Transparency = 0 }):Play()
		TweenService:Create(btn, TweenInfo.new(0.12), { BackgroundTransparency = 0 }):Play()
	end)
	btn.MouseLeave:Connect(function()
		TweenService:Create(stroke, TweenInfo.new(0.12), { Thickness = 2, Transparency = 0.15 }):Play()
		TweenService:Create(btn, TweenInfo.new(0.12), { BackgroundTransparency = 0.1 }):Play()
	end)

	btn.MouseButton1Click:Connect(function()
		if not self._awaitingHyperjump then return end
		self._awaitingHyperjump = false
		TweenService:Create(btn, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			Position = UDim2.fromScale(0.5, 1.1),
		}):Play()
		task.delay(0.3, function()
			if self._hyperjumpGui then
				self._hyperjumpGui:Destroy()
				self._hyperjumpGui = nil
			end
		end)
		self:_triggerReturnHyperdrive()
	end)
end

---------------------------------------------------------------------------
-- Return hyperdrive: short jump back into block space
---------------------------------------------------------------------------
function LakelandRaceController:_triggerReturnHyperdrive()
	self._returnHyperActive = true
	self._returnHyperTimer = 0
	self._hyperdriveBlend = 0

	self:_bindInput()

	Workspace.Terrain:Clear()
	self:_setupDarkEnvironment()

	stopGroupLoop(self._terrainSfxEmitter)
	self._terrainSfxEmitter = nil
	stopGroupLoop(self._hyperSfxEmitter)
	self._hyperSfxEmitter = startGroupLoop(SFX_HyperSpace)

	if self._skillTreeUI then
		self._skillTreeUI.show()
	end
end

function LakelandRaceController:_finishReturnHyperdrive()
	self._returnHyperActive = false
	self._returnHyperTimer = 0
	self._hyperdriveBlend = 0
	self._terrainMode = false
	self._hyperExitBlend = 0
	self._hyperdriveTriggered = false
	self._raceElapsed = 0
	self._obstacleGraceTimer = 2

	stopGroupLoop(self._hyperSfxEmitter)
	self._hyperSfxEmitter = nil
	playGroupOneShot(SFX_OnExitHyperSpace, FIXED_MACHINE_POS)

	if not self._reentryActive then
		self._reentryActive = true
		self._reentryTimer = 0
		self:_restoreBlockSpaceLighting()
	end

	Workspace.Terrain:Clear()

	if self._biomeRegions and #self._biomeRegions > 0 then
		local chosen = math.random(1, #BIOMES)
		self._activeBiome = BIOMES[chosen]
		self._terrainRegion = self._biomeRegions[chosen]
	end

	for i = 1, HYPER.LINE_POOL do
		if self._hyperLines[i] then self._hyperLines[i].Transparency = 1 end
	end

	if self._cameraController then
		self._cameraController:SetHyperdriveFOV(0)
	end

	self._running = true
	self._countdownDrive = false
	self._launching = true
	self._currentSpeed = 0
	self._obstaclesVisible = true
	self._laneSpringTarget = 0
	self._laneSpringPos = 0
	self._laneSpringVel = 0
	self._laneEntryT = self._t
	self:_bindInput()
	if not self._renderConn then self:_startRenderLoop() end

	local player = game:GetService("Players").LocalPlayer
	local humanoid = player and player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.WalkSpeed = 0
		humanoid.JumpHeight = 0
		humanoid.JumpPower = 0
	end

	local playerGui = player and player:FindFirstChildOfClass("PlayerGui")
	if playerGui then
		local hudNames = {
			"LakelandHealthBarUI", "LakelandDistanceUI",
			"LakelandScoreBarUI", "LakelandBombUI",
			"LakelandDangerVignetteUI",
		}
		for _, name in ipairs(hudNames) do
			local sg = playerGui:FindFirstChild(name)
			if sg and sg:IsA("ScreenGui") then
				sg.Enabled = true
				local container = sg:FindFirstChildWhichIsA("Frame") or sg:FindFirstChildWhichIsA("CanvasGroup")
				if container then
					local origPos
					if container:GetAttribute("_origPosXS") then
						origPos = UDim2.new(
							container:GetAttribute("_origPosXS"), container:GetAttribute("_origPosXO"),
							container:GetAttribute("_origPosYS"), container:GetAttribute("_origPosYO")
						)
					else
						origPos = container.Position
					end
					local origBgT = container:GetAttribute("_origBgT") or container.BackgroundTransparency
					container.Position = origPos + UDim2.fromScale(0, -0.1)
					TweenService:Create(container, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
						Position = origPos,
						BackgroundTransparency = origBgT,
					}):Play()
					for _, desc in ipairs(container:GetDescendants()) do
						if desc:IsA("TextLabel") or desc:IsA("TextButton") then
							pcall(function()
								local txtT = desc:GetAttribute("_origTxtT") or 0
								local txtST = desc:GetAttribute("_origTxtST") or 0.5
								TweenService:Create(desc, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { TextTransparency = txtT, TextStrokeTransparency = txtST }):Play()
							end)
						end
						if desc:IsA("GuiObject") then
							pcall(function()
								local bgT = desc:GetAttribute("_origBgT") or desc.BackgroundTransparency
								if bgT < 1 then
									TweenService:Create(desc, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { BackgroundTransparency = bgT }):Play()
								end
							end)
						end
						if desc:IsA("UIStroke") then
							pcall(function()
								local sT = desc:GetAttribute("_origStrokeT") or 0
								TweenService:Create(desc, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Transparency = sT }):Play()
							end)
						end
						if desc:IsA("ImageLabel") or desc:IsA("ImageButton") then
							pcall(function()
								local imgT = desc:GetAttribute("_origImgT") or 0
								TweenService:Create(desc, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { ImageTransparency = imgT }):Play()
							end)
						end
					end
				end
			end
		end
	end

	if self._skillTreeUI then
		self._skillTreeUI.hide()
	end

	if self._gameController and self._gameController._waveformUI then
		self._gameController._waveformUI.show()
	end

	local bgm = self._gameController and self._gameController._bgmCurrent
	if bgm and bgm:IsA("Sound") then
		bgm.Volume = 0
		bgm:Resume()
		TweenService:Create(bgm, TweenInfo.new(1.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Volume = self._hyperBgmVolume or 0.5 }):Play()
		self._hyperBgmVolume = nil
	end

	task.spawn(function()
		local player = game:GetService("Players").LocalPlayer
		local pg = player and player:FindFirstChildOfClass("PlayerGui")
		if not pg then return end
		local flashSg = Instance.new("ScreenGui")
		flashSg.Name = "HyperFlash"
		flashSg.DisplayOrder = 100
		flashSg.IgnoreGuiInset = true
		flashSg.Parent = pg
		local flash = Instance.new("Frame")
		flash.Size = UDim2.fromScale(1, 1)
		flash.BackgroundColor3 = Color3.new(1, 1, 1)
		flash.BackgroundTransparency = 0
		flash.BorderSizePixel = 0
		flash.Parent = flashSg
		local tw = TweenService:Create(flash, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { BackgroundTransparency = 1 })
		tw:Play()
		tw.Completed:Wait()
		flashSg:Destroy()
	end)
end

---------------------------------------------------------------------------
-- Reset atmosphere to neutral dark state (menu / game end)
---------------------------------------------------------------------------
function LakelandRaceController:_resetAtmosphere()
	if self._atmosphere then
		self._atmosphere.Color = Color3.fromRGB(4, 8, 22)
		self._atmosphere.Decay = Color3.fromRGB(8, 20, 50)
		self._atmosphere.Density = 0.35
		self._atmosphere.Haze = 2
		self._atmosphere.Glare = 0.1
	end
	if self._bloom then
		self._bloom.Intensity = 0.015
		self._bloom.Size = 3
		self._bloom.Threshold = 2.5
	end
	if self._raceCC then
		self._raceCC.Brightness = 0
		self._raceCC.Contrast = 0.05
		self._raceCC.Saturation = 0.1
		self._raceCC.TintColor = Color3.fromRGB(200, 215, 255)
	end
	Lighting.Ambient = Color3.fromRGB(10, 10, 18)
	Lighting.OutdoorAmbient = Color3.fromRGB(8, 8, 14)
	Lighting.FogColor = Color3.fromRGB(0, 0, 0)
end

---------------------------------------------------------------------------
-- Position at start
---------------------------------------------------------------------------
function LakelandRaceController:PositionAtStart()
	self._currentLane = 2
	self._targetLane = 2
	self._laneBlend = 0
	self._laneSpringPos = 0
	self._laneSpringVel = 0
	self._laneSpringTarget = 0
	self._lateralInput = 0
	self._t = 0
	self._currentSpeed = 0
	self._launching = false
	self._boosting = false
	self._currentRoll = 0
	self._lastXPos = 0
	self._switchDir = 0
	self._health = MAX_HEALTH
	self._totalDistance = 0
	self.HealthChanged:Fire(self._health)

	for _, hazard in ipairs(HAZARDS) do hazard._hit = false; hazard._flybyPlayed = false; hazard._portalScored = false end
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
	self._comboCount = 0
	self._comboTimer = 0
	self._shockwaveActive = false
	self._shockwaveTime = 0
	self._shockwaveOriginT = 0
	self._lastShockwaveThreshold = 0

	self._portalActive = false
	self._portalTimer = 0
	self._portalFade = 0
	self._portalRefilling = false
	self._portalRefillT = 1
	for _, portal in ipairs(PORTALS) do portal.collected = false; portal._flybyPlayed = false end

	self._raceElapsed = 0
	self._hyperdriveActive = false
	self._hyperdriveTriggered = false
	self._hyperdriveTimer = 0
	self._hyperdriveBlend = 0
	if self._hyperBgmVolume then
		local bgm = self._gameController and self._gameController._bgmCurrent
		if bgm and bgm:IsA("Sound") then
			bgm.Volume = self._hyperBgmVolume
			if bgm.IsPaused then bgm:Resume() end
		end
		self._hyperBgmVolume = nil
	end
	self._terrainMode = false
	self._hyperExitBlend = 0
	stopGroupLoop(self._hyperSfxEmitter)
	self._hyperSfxEmitter = nil
	stopGroupLoop(self._terrainSfxEmitter)
	self._terrainSfxEmitter = nil
	if self._skillTreeUI then
		self._skillTreeUI.hide()
	end
	self._waitingForReseat = false
	self._awaitingHyperjump = false
	self._returnHyperActive = false
	self._returnHyperTimer = 0
	if self._reseatConn then
		self._reseatConn:Disconnect()
		self._reseatConn = nil
	end
	if self._hyperjumpGui then
		self._hyperjumpGui:Destroy()
		self._hyperjumpGui = nil
	end
	self._savedBlockLighting = nil
	self._reentryActive = false
	self._reentryTimer = 0
	self._obstacleGraceTimer = 0
	self:_setupDarkEnvironment()
	Workspace.Terrain:Clear()
	if self._biomeRegions and #self._biomeRegions > 0 then
		local chosen = math.random(1, #BIOMES)
		self._activeBiome = BIOMES[chosen]
		self._terrainRegion = self._biomeRegions[chosen]
	end
	for i = 1, HYPER.LINE_POOL do
		if self._hyperLines[i] then self._hyperLines[i].Transparency = 1 end
	end
	if self._cameraController then
		self._cameraController:SetHyperdriveFOV(0)
	end

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

function LakelandRaceController:StartDemoRace()
	if self._running then return end
	self._running = true
	self._demoMode = true
	self._countdownDrive = false
	self._launching = true
	self._currentSpeed = 0
	self._laneEntryT = self._t
	if not self._renderConn then self:_startRenderLoop() end

	task.spawn(function()
		while self._demoMode and self._running do
			local delay = 0.8 + math.random() * 1.2
			task.wait(delay)
			if not self._demoMode or not self._running then break end

			local current = self._targetLane
			local dir
			if current == 1 then
				dir = 1
			elseif current == LANE_COUNT then
				dir = -1
			else
				dir = math.random() > 0.5 and 1 or -1
			end
			self:SwitchLane(dir)

			if math.random() > 0.7 and self._bombCount > 0 then
				self:_deployBomb()
			end
		end
	end)

	print("[LakelandRaceController] DEMO LAUNCH on lane " .. self._currentLane)
end

function LakelandRaceController:StopRace()
	self._running = false
	self._demoMode = false
	self._countdownDrive = false
	self._launching = false
	self._shockwaveActive = false
	self._shockwaveTime = 0
	self._portalActive = false
	self._portalTimer = 0
	self._portalFade = 0
	self._portalRefilling = false
	self._portalRefillT = 1
	if self._portalEQ then self._portalEQ:Destroy(); self._portalEQ = nil end

	self._raceElapsed = 0
	self._hyperdriveActive = false
	self._hyperdriveTriggered = false
	self._hyperdriveTimer = 0
	self._hyperdriveBlend = 0
	if self._hyperBgmVolume then
		local bgm = self._gameController and self._gameController._bgmCurrent
		if bgm and bgm:IsA("Sound") then
			bgm.Volume = self._hyperBgmVolume
			if bgm.IsPaused then bgm:Resume() end
		end
		self._hyperBgmVolume = nil
	end
	self._terrainMode = false
	self._hyperExitBlend = 0
	stopGroupLoop(self._hyperSfxEmitter)
	self._hyperSfxEmitter = nil
	stopGroupLoop(self._terrainSfxEmitter)
	self._terrainSfxEmitter = nil
	if self._skillTreeUI then
		self._skillTreeUI.hide()
	end
	self._waitingForReseat = false
	self._awaitingHyperjump = false
	self._returnHyperActive = false
	self._returnHyperTimer = 0
	if self._reseatConn then
		self._reseatConn:Disconnect()
		self._reseatConn = nil
	end
	if self._hyperjumpGui then
		self._hyperjumpGui:Destroy()
		self._hyperjumpGui = nil
	end
	self._savedBlockLighting = nil
	self._reentryActive = false
	self._reentryTimer = 0
	self._obstacleGraceTimer = 0
	self:_setupDarkEnvironment()
	Workspace.Terrain:Clear()
	if self._biomeRegions and #self._biomeRegions > 0 then
		local chosen = math.random(1, #BIOMES)
		self._activeBiome = BIOMES[chosen]
		self._terrainRegion = self._biomeRegions[chosen]
	end
	for i = 1, HYPER.LINE_POOL do
		if self._hyperLines[i] then self._hyperLines[i].Transparency = 1 end
	end
	if self._cameraController then
		self._cameraController:SetHyperdriveFOV(0)
	end

	if self._boosting then
		self._boosting = false
		self.BoostChanged:Fire(false, math.floor(self._currentBoostTally))
	end
	self._currentBoostTally = 0
	self._boostScore = 0
	self._lateralInput = 0
	self._inputTrove:Clean()

	if self._boostSfxEmitter then
		local em = self._boostSfxEmitter
		self._boostSfxEmitter = nil
		local snd = em:FindFirstChildOfClass("Sound")
		if snd then
			TweenService:Create(snd, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Volume = 0 }):Play()
		end
		Debris:AddItem(em, 0.7)
	end

	if self._renderConn then
		RunService:UnbindFromRenderStep("LakelandMachineUpdate")
		self._renderConn = nil
	end

	self:_resetAtmosphere()
end

---------------------------------------------------------------------------
-- Input
---------------------------------------------------------------------------
function LakelandRaceController:_bindInput()
	self._inputTrove:Clean()
	self._lateralInput = 0

	self._inputTrove:Add(UserInputService.InputBegan:Connect(function(input, processed)
		if processed then return end
		if input.KeyCode == Enum.KeyCode.A or input.KeyCode == Enum.KeyCode.Left then
			self._lateralInput = -1
		elseif input.KeyCode == Enum.KeyCode.D or input.KeyCode == Enum.KeyCode.Right then
			self._lateralInput = 1
		elseif input.KeyCode == Enum.KeyCode.Space then
			self:_deployBomb()
		end
	end), "Disconnect")

	self._inputTrove:Add(UserInputService.InputEnded:Connect(function(input)
		if input.KeyCode == Enum.KeyCode.A or input.KeyCode == Enum.KeyCode.Left then
			if self._lateralInput == -1 then self._lateralInput = 0 end
		elseif input.KeyCode == Enum.KeyCode.D or input.KeyCode == Enum.KeyCode.Right then
			if self._lateralInput == 1 then self._lateralInput = 0 end
		end
	end), "Disconnect")

	if UserInputService.GamepadEnabled then
		self._inputTrove:Add(UserInputService.InputChanged:Connect(function(input)
			if input.KeyCode == Enum.KeyCode.Thumbstick1 then
				local x = input.Position.X
				if math.abs(x) < 0.15 then
					self._lateralInput = 0
				else
					self._lateralInput = math.clamp(x, -1, 1)
				end
			end
		end), "Disconnect")
	end

	if UserInputService.TouchEnabled and UserInputService.GyroscopeEnabled then
		local GYRO_DEAD_ZONE = math.rad(5)
		local GYRO_MAX_TILT = math.rad(30)
		local tiltRange = GYRO_MAX_TILT - GYRO_DEAD_ZONE
		self._inputTrove:Add(UserInputService.DeviceRotationChanged:Connect(function(_rotation, cframe)
			local _, _, roll = cframe:ToEulerAnglesYXZ()
			if math.abs(roll) < GYRO_DEAD_ZONE then
				self._lateralInput = 0
			else
				local sign = roll > 0 and -1 or 1
				self._lateralInput = math.clamp((math.abs(roll) - GYRO_DEAD_ZONE) / tiltRange * sign, -1, 1)
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
	self._laneSpringTarget = (newLane - 2) * LANE_SPACING
	self.LaneChanged:Fire(self._targetLane)
end

---------------------------------------------------------------------------
-- Menu render loop (static decorative track during menu)
---------------------------------------------------------------------------
local MENU_TRACK_T = 0.15

function LakelandRaceController:_startMenuRenderLoop()
	self:_stopMenuRenderLoop()
	self._t = MENU_TRACK_T
	self._obstaclesVisible = false

	self._menuRenderConn = RunService.RenderStepped:Connect(function(dt)
		self:_updateWorldScroll(dt)
	end)
end

function LakelandRaceController:_stopMenuRenderLoop()
	if self._menuRenderConn then
		self._menuRenderConn:Disconnect()
		self._menuRenderConn = nil
	end
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
		self:_updateShockwave(dt)
		if self._running or self._countdownDrive then
			self:_updateMovement(dt)
		end
		self:_updateWorldScroll(dt)
		self:_updateHyperdriveLines(dt)
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
	local laneFloat = (self._laneSpringTarget / LANE_SPACING) + 2
	return math.clamp(math.floor(laneFloat + 0.5), 1, LANE_COUNT)
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
			self._comboCount = self._comboCount + 1
			self._comboTimer = COMBO_WINDOW
			local multiplier = math.max(self._comboCount, 1)
			local earned = COIN_VALUE * multiplier
			self._coinScore = self._coinScore + earned
			self._coinsCollected = self._coinsCollected + 1
			self.CoinCollected:Fire(self._coinScore, self._coinsCollected, self._comboCount, earned)
			self:_spawnBurst(Color3.fromRGB(50, 140, 255), Color3.fromRGB(100, 180, 255))
			local comboPitch = 0.85 + math.min(self._comboCount, 10) * 0.08
			playRandomImpactAt(self._lastCFrame and self._lastCFrame.Position or FIXED_MACHINE_POS, nil, comboPitch)
			-- Shockwave disabled for now
			-- local newThreshold = math.floor(self._comboCount / SHOCKWAVE_COMBO_STEP)
			-- if newThreshold > self._lastShockwaveThreshold and not self._shockwaveActive then
			-- 	self._lastShockwaveThreshold = newThreshold
			-- 	self:_triggerShockwave()
			-- end
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
			if SFX_Impacts then playSoundAt(SFX_Impacts:FindFirstChild("FirePickup"), self._lastCFrame and self._lastCFrame.Position or FIXED_MACHINE_POS, 2.5) end
			if self._cameraController then
				self._cameraController:ShakeCamera(1.5, 0.12, 0, 0, 0.15, Vector3.new(0.7, 0.7, 0.1), Vector3.new(0.03, 0.03, 0.02))
			end
			return
		end
	end
end

function LakelandRaceController:_checkPortalCollection()
	if self._portalActive then return end
	local lane = self:_getEffectiveLane()
	for _, portal in ipairs(PORTALS) do
		if not portal.collected and portal.lane == lane and portal.t >= self._laneEntryT and self._t >= portal.t and self._t <= portal.t + PORTAL_SIZE then
			portal.collected = true
			self:_activatePortal()
			return
		end
	end
end

function LakelandRaceController:_activatePortal()
	self._portalActive = true
	self._portalTimer = 0
	self._portalFade = 0

	for _, hazard in ipairs(HAZARDS) do hazard._hit = false; hazard._flybyPlayed = false; hazard._portalScored = false end
	for _, coin in ipairs(COINS) do coin.collected = true end
	for _, bomb in ipairs(BOMBS) do bomb.collected = true end

	self:_spawnBurst(Color3.fromRGB(200, 0, 255), Color3.fromRGB(255, 80, 255))
	if SFX_Impacts then
		playSoundAt(SFX_Impacts:FindFirstChild("FirePickup"), self._lastCFrame and self._lastCFrame.Position or FIXED_MACHINE_POS, 3, 0.5)
	end
	if self._cameraController then
		self._cameraController:ShakeCamera(4, 0.15, 0, 0.05, 0.4, Vector3.new(1.5, 1.5, 0.3), Vector3.new(0.08, 0.08, 0.04))
		self._cameraController:ZoomPunch(6)
	end

	local bgm = self._gameController and self._gameController._bgmCurrent
	if bgm then
		if self._portalEQ then self._portalEQ:Destroy() end
		local eq = Instance.new("EqualizerSoundEffect")
		eq.Name = "PortalFilter"
		eq.LowGain = 0
		eq.MidGain = 0
		eq.HighGain = 0
		eq.Parent = bgm
		self._portalEQ = eq
		TweenService:Create(eq, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			HighGain = -40,
			MidGain = -12,
			LowGain = 6,
		}):Play()
	end
end

function LakelandRaceController:_deactivatePortal()
	self._portalActive = false
	self._portalTimer = 0
	self._portalRefilling = true
	self._portalRefillT = 1

	self:_spawnBurst(Color3.fromRGB(50, 140, 255), Color3.fromRGB(100, 180, 255))
	if self._cameraController then
		self._cameraController:ShakeCamera(3, 0.12, 0, 0.04, 0.3, Vector3.new(1.2, 1.2, 0.2), Vector3.new(0.06, 0.06, 0.03))
		self._cameraController:ZoomPunch(4)
	end

	if self._portalEQ then
		local eq = self._portalEQ
		self._portalEQ = nil
		local fadeOut = TweenService:Create(eq, TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			HighGain = 0,
			MidGain = 0,
			LowGain = 0,
		})
		fadeOut:Play()
		fadeOut.Completed:Once(function()
			eq:Destroy()
		end)
	end
end

function LakelandRaceController:_updatePortalRefill(dt)
	if not self._portalRefilling then return end

	local prevT = self._portalRefillT
	self._portalRefillT = self._portalRefillT - dt * 0.15
	local frontT = self._portalRefillT

	for _, hazard in ipairs(HAZARDS) do
		if hazard._hit and hazard.t <= prevT and hazard.t >= frontT then
			hazard._hit = false; hazard._flybyPlayed = false; hazard._portalScored = false
		end
	end
	for _, coin in ipairs(COINS) do
		if coin.collected and coin.t <= prevT and coin.t >= frontT then
			coin.collected = false; coin._flybyPlayed = false
		end
	end
	for _, bomb in ipairs(BOMBS) do
		if bomb.collected and bomb.t <= prevT and bomb.t >= frontT then
			bomb.collected = false; bomb._flybyPlayed = false
		end
	end

	if self._portalRefillT <= self._t + 0.003 then
		self._portalRefilling = false
	end
end

function LakelandRaceController:_deployBomb()
	if self._hyperdriveActive or self._terrainMode then return end
	if self._bombCount <= 0 or self._bombChainActive then return end
	self._bombCount = self._bombCount - 1
	self._bombChainActive = true
	self._bombChainTimer = 0
	self._bombChainCount = 0
	self._bombChainLane = self:_getEffectiveLane()
	self._bombChainStartT = self._t
	self.BombDeployed:Fire()
	local playerPos = self._lastCFrame and self._lastCFrame.Position or FIXED_MACHINE_POS
	if SFX_Impacts then
		playSoundAt(SFX_Impacts:FindFirstChild("FirePickup"), playerPos, 2.5, 0.6)
	end
	if self._cameraController then
		self._cameraController:ShakeCamera(2, 0.08, 0, 0.03, 0.25, Vector3.new(1, 1, 0.2), Vector3.new(0.05, 0.05, 0.03))
	end
end

function LakelandRaceController:_updateBombChain(dt)
	if not self._bombChainActive then return end
	self._bombChainTimer = self._bombChainTimer + dt

	local centerSpline = self._splines[2].spline
	local centerRef = centerSpline:CalculatePositionAt(self._t)
	local playerPos = self._lastCFrame and self._lastCFrame.Position or FIXED_MACHINE_POS

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
				playRandomImpactAt(playerPos, 2)
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
				playRandomImpactAt(playerPos, 2)
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
				if SFX_Impacts then playSoundAt(SFX_Impacts:FindFirstChild("FirePickup"), playerPos, 2.5) end
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

	if self._portalActive then
		self._portalTimer = self._portalTimer + dt
		self._portalFade = math.min(self._portalFade + dt * 3, 1)
		if self._portalTimer >= PORTAL_DURATION then
			self:_deactivatePortal()
		end
	else
		self._portalFade = math.max(self._portalFade - dt * 3, 0)
	end

	self:_updatePortalRefill(dt)

	if self._hitFreezeTimer > 0 then
		self._hitFreezeTimer = self._hitFreezeTimer - dt
		return
	end

	if self._bombChainActive then
		return
	end

	if self._comboTimer > 0 then
		self._comboTimer = self._comboTimer - dt
		if self._comboTimer <= 0 then
			self._comboCount = 0
			self._comboTimer = 0
			self._lastShockwaveThreshold = 0
		end
	end

	if not self._countdownDrive then
		if self._launching then
			self._currentSpeed = self._currentSpeed + LAUNCH_ACCEL * dt
			if self._currentSpeed >= MOVE_SPEED then
				self._currentSpeed = MOVE_SPEED
				self._launching = false
			end
		end

		local inBoost = self:_isInBoostZone() and not self._hyperdriveActive and not self._terrainMode
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
				local targetVol = (0.3 + sf * 0.7) * boostSfx.Volume
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

		if not self._hyperdriveActive and not self._terrainMode and self._obstacleGraceTimer <= 0 then
			local hitHazard = self:_getHitHazard()
			if hitHazard and not hitHazard._hit then
				hitHazard._hit = true
				if not self._demoMode then
					self._health = math.max(self._health - HAZARD_DAMAGE, 0)
					self._comboCount = 0
					self._comboTimer = 0
					self._lastShockwaveThreshold = 0
					if self._shockwaveActive then
						self._shockwaveActive = false
						self._shockwaveTime = 0
					end
					self.HealthChanged:Fire(self._health)
					self.HazardHit:Fire(self._health)
				end
				self:_spawnBurst(Color3.fromRGB(255, 50, 50), Color3.fromRGB(255, 100, 100))
				if self._health <= 0 and not self._demoMode then
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
			self:_checkPortalCollection()
		end

		if self._portalActive then
			for _, hazard in ipairs(HAZARDS) do
				if not hazard._hit and not hazard._portalScored and hazard.t <= self._t then
					hazard._portalScored = true
					self._coinScore = self._coinScore + PORTAL_HAZARD_BONUS
					self._coinsCollected = self._coinsCollected + 1
					self.CoinCollected:Fire(self._coinScore, self._coinsCollected, 0, PORTAL_HAZARD_BONUS)
				end
			end
		end

		self.SpeedChanged:Fire(self._currentSpeed)
	end

	-- Advance virtual progress
	local tDelta = (self._currentSpeed / TRACK_LENGTH) * dt
	if not self._countdownDrive then
		if not self._hyperdriveActive and not self._terrainMode then
			self._totalDistance = self._totalDistance + self._currentSpeed * dt
		end
		self._raceElapsed = self._raceElapsed + dt

		if self._raceElapsed >= HYPER.TRIGGER_TIME and not self._hyperdriveActive and not self._hyperdriveTriggered then
			self:_saveBlockSpaceLighting()

			self._hyperdriveActive = true
			self._hyperdriveTriggered = true
			self._hyperdriveTimer = 0

			stopGroupLoop(self._hyperSfxEmitter)
			self._hyperSfxEmitter = startGroupLoop(SFX_HyperSpace)

			local bgm = self._gameController and self._gameController._bgmCurrent
			if bgm and bgm:IsA("Sound") and bgm.IsPlaying then
				self._hyperBgmVolume = bgm.Volume
				TweenService:Create(bgm, TweenInfo.new(HYPER.FADE_IN, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Volume = 0 }):Play()
				task.delay(HYPER.FADE_IN, function()
					if self._hyperdriveActive and bgm and bgm.Parent then
						bgm:Pause()
					end
				end)
			end

			local playerGui = game:GetService("Players").LocalPlayer
				and game:GetService("Players").LocalPlayer:FindFirstChildOfClass("PlayerGui")
			if playerGui then
				local hudNames = {
					"LakelandHealthBarUI", "LakelandDistanceUI",
					"LakelandScoreBarUI", "LakelandBombUI",
					"LakelandDangerVignetteUI",
				}
				for _, name in ipairs(hudNames) do
					local sg = playerGui:FindFirstChild(name)
					if sg and sg:IsA("ScreenGui") then
						local container = sg:FindFirstChildWhichIsA("Frame") or sg:FindFirstChildWhichIsA("CanvasGroup")
						if container then
							if not container:GetAttribute("_origPosXS") then
								container:SetAttribute("_origPosXS", container.Position.X.Scale)
								container:SetAttribute("_origPosXO", container.Position.X.Offset)
								container:SetAttribute("_origPosYS", container.Position.Y.Scale)
								container:SetAttribute("_origPosYO", container.Position.Y.Offset)
								container:SetAttribute("_origBgT", container.BackgroundTransparency)
							end
							TweenService:Create(container, TweenInfo.new(HYPER.FADE_IN, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
								Position = container.Position + UDim2.fromScale(0, -0.15),
								BackgroundTransparency = 1,
							}):Play()
							for _, desc in ipairs(container:GetDescendants()) do
								if desc:IsA("TextLabel") or desc:IsA("TextButton") then
									if not desc:GetAttribute("_origTxtT") then
										desc:SetAttribute("_origTxtT", desc.TextTransparency)
										desc:SetAttribute("_origTxtST", desc.TextStrokeTransparency)
									end
									TweenService:Create(desc, TweenInfo.new(HYPER.FADE_IN, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
								end
								if desc:IsA("GuiObject") then
									pcall(function()
										if not desc:GetAttribute("_origBgT") then
											desc:SetAttribute("_origBgT", desc.BackgroundTransparency)
										end
										TweenService:Create(desc, TweenInfo.new(HYPER.FADE_IN, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { BackgroundTransparency = 1 }):Play()
									end)
								end
								if desc:IsA("UIStroke") then
									if not desc:GetAttribute("_origStrokeT") then
										desc:SetAttribute("_origStrokeT", desc.Transparency)
									end
									TweenService:Create(desc, TweenInfo.new(HYPER.FADE_IN, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Transparency = 1 }):Play()
								end
								if desc:IsA("ImageLabel") or desc:IsA("ImageButton") then
									if not desc:GetAttribute("_origImgT") then
										desc:SetAttribute("_origImgT", desc.ImageTransparency)
									end
									TweenService:Create(desc, TweenInfo.new(HYPER.FADE_IN, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { ImageTransparency = 1 }):Play()
								end
							end
						end
						task.delay(HYPER.FADE_IN, function()
							sg.Enabled = false
						end)
					end
				end
			end

			if self._gameController and self._gameController._waveformUI then
				self._gameController._waveformUI.hide()
			end

			if self._skillTreeUI then
				self._skillTreeUI.show()
			end
		end

		if self._hyperdriveActive then
			self._hyperdriveTimer = self._hyperdriveTimer + dt
			if self._hyperdriveTimer < HYPER.FADE_IN then
				self._hyperdriveBlend = self._hyperdriveTimer / HYPER.FADE_IN
			elseif self._hyperdriveTimer < HYPER.DURATION then
				self._hyperdriveBlend = 1
			else
				self._hyperdriveBlend = 0
				self._hyperdriveActive = false
				self._terrainMode = true
				self._hyperExitBlend = 1
				self._currentSpeed = 0

				stopGroupLoop(self._hyperSfxEmitter)
				self._hyperSfxEmitter = nil
				playGroupOneShot(SFX_OnExitHyperSpace, FIXED_MACHINE_POS)
				stopGroupLoop(self._terrainSfxEmitter)
				self._terrainSfxEmitter = startGroupLoop(SFX_Terrain)

				if self._skillTreeUI then
					self._skillTreeUI.hide()
				end
				local bgm = self._gameController and self._gameController._bgmCurrent
				if bgm and bgm:IsA("Sound") then
					bgm:Stop()
				end
				self._hyperBgmVolume = nil
				if self._terrainRegion then
					local halfW = TERRAIN_BASE.WIDTH / 2
					local halfD = TERRAIN_BASE.DEPTH / 2
					local minC = Vector3int16.new(
						math.floor((FIXED_MACHINE_POS.X - halfW) / TERRAIN_BASE.RESOLUTION),
						math.floor((TERRAIN_BASE.BASE_Y - 20) / TERRAIN_BASE.RESOLUTION),
						math.floor((FIXED_MACHINE_POS.Z - halfD) / TERRAIN_BASE.RESOLUTION)
					)
					Workspace.Terrain:PasteRegion(self._terrainRegion, minC, true)
				end
				if self._cameraController then
					self._cameraController:ZoomPunch(12)
					self._cameraController:ShakeCamera(3, 0.15, 0, 0.1, 0.4, Vector3.new(1.5, 2, 0.3), Vector3.new(0.06, 0.06, 0.03))
				end
				task.delay(2, function()
					if self._gameController then
						self._gameController:_unseatPlayer()
						self._gameController:_unfreezeCharacter()
					end
					if self._cameraController then
						self._cameraController:_deactivate()
					end
					local player = game:GetService("Players").LocalPlayer
					local character = player and player.Character
					local humanoid = character and character:FindFirstChildOfClass("Humanoid")
					local camera = Workspace.CurrentCamera
					if camera then
						camera.CameraType = Enum.CameraType.Custom
						if humanoid then
							camera.CameraSubject = humanoid
						end
					end

					self._waitingForReseat = true
					if self._reseatConn then
						self._reseatConn:Disconnect()
						self._reseatConn = nil
					end
					if humanoid then
						self._reseatConn = humanoid.Seated:Connect(function(isSeated, seatPart)
							if not isSeated or not self._waitingForReseat then return end
							local machine = Workspace:FindFirstChild("ActiveMachine")
							if machine and seatPart and seatPart:IsDescendantOf(machine) then
								self._waitingForReseat = false
								if self._reseatConn then
									self._reseatConn:Disconnect()
									self._reseatConn = nil
								end
								self:_onPlayerReseated()
							end
						end)
					end
				end)
				task.spawn(function()
					local player = game:GetService("Players").LocalPlayer
					local playerGui = player and player:FindFirstChildOfClass("PlayerGui")
					if not playerGui then return end
					local sg = Instance.new("ScreenGui")
					sg.Name = "HyperFlash"
					sg.DisplayOrder = 100
					sg.IgnoreGuiInset = true
					sg.Parent = playerGui
					local flash = Instance.new("Frame")
					flash.Size = UDim2.fromScale(1, 1)
					flash.BackgroundColor3 = Color3.new(1, 1, 1)
					flash.BackgroundTransparency = 0
					flash.BorderSizePixel = 0
					flash.Parent = sg
					local tw = TweenService:Create(flash, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { BackgroundTransparency = 1 })
					tw:Play()
					tw.Completed:Wait()
					sg:Destroy()
				end)
			end
		end

		if self._terrainMode then
			if self._hyperExitBlend > 0 then
				self._hyperExitBlend = math.max(0, self._hyperExitBlend - dt / 0.5)
			end

			if self._returnHyperActive then
				self._returnHyperTimer = self._returnHyperTimer + dt
				local t = self._returnHyperTimer
				if t < HYPER_RETURN.FADE_IN then
					self._hyperdriveBlend = t / HYPER_RETURN.FADE_IN
				elseif t < HYPER_RETURN.DURATION - HYPER_RETURN.FADE_OUT then
					self._hyperdriveBlend = 1
				elseif t < HYPER_RETURN.DURATION then
					self._hyperdriveBlend = 1 - (t - (HYPER_RETURN.DURATION - HYPER_RETURN.FADE_OUT)) / HYPER_RETURN.FADE_OUT
					if not self._reentryActive then
						self._reentryActive = true
						self._reentryTimer = 0
						self:_restoreBlockSpaceLighting()
					end
				else
					self:_finishReturnHyperdrive()
					return
				end

				if self._cameraController then
					self._cameraController:SetHyperdriveFOV(self._hyperdriveBlend)
				end
			else
				return
			end
		end
	end

	if self._reentryActive then
		self._reentryTimer = self._reentryTimer + dt
		if self._reentryTimer >= REENTRY_DURATION then
			self._reentryActive = false
			self._reentryTimer = 0
		end
	end

	if self._obstacleGraceTimer > 0 then
		self._obstacleGraceTimer = math.max(0, self._obstacleGraceTimer - dt)
	end

	self._t = self._t + tDelta
	if self._t > 1 then
		self._t = self._t - 1
		self._laneEntryT = 0
		for _, hazard in ipairs(HAZARDS) do hazard._hit = false; hazard._flybyPlayed = false; hazard._portalScored = false end
		for _, coin in ipairs(COINS) do coin.collected = false; coin._flybyPlayed = false end
		for _, bomb in ipairs(BOMBS) do bomb.collected = false; bomb._flybyPlayed = false end
		for _, portal in ipairs(PORTALS) do portal.collected = false; portal._flybyPlayed = false end
	end

	-- Continuous lateral movement
	if not self._countdownDrive then
		self._laneSpringTarget = self._laneSpringTarget + self._lateralInput * LATERAL_SPEED * dt
		self._laneSpringTarget = math.clamp(self._laneSpringTarget, -LANE_SPACING, LANE_SPACING)

		local effectiveLane = self:_getEffectiveLane()
		if effectiveLane ~= self._lastEffectiveLane then
			self._laneEntryT = self._t
			self._lastEffectiveLane = effectiveLane
			self.LaneChanged:Fire(effectiveLane)
		end
	end

	-- Compute lane offset (Y from center spline)
	local centerSpline = self._splines[2].spline
	local centerPos = centerSpline:CalculatePositionAt(self._t)
	local laneOffset = Vector3.new(0, 0, 0)

	-- Spring-driven lateral overshoot for visual position
	local springError = self._laneSpringTarget - self._laneSpringPos
	self._laneSpringVel = self._laneSpringVel + (LANE_SPRING_STIFFNESS * springError - LANE_SPRING_DAMPING * self._laneSpringVel) * dt
	self._laneSpringPos = self._laneSpringPos + self._laneSpringVel * dt

	-- Direction from center spline for forward orientation
	local centerDir = centerSpline:CalculateDerivativeAt(self._t)
	if centerDir.Magnitude < 0.001 then centerDir = Vector3.new(0, 0, -1) end
	centerDir = centerDir.Unit

	local rightDir = centerDir:Cross(Vector3.new(0, 1, 0))
	if rightDir.Magnitude > 0.001 then rightDir = rightDir.Unit else rightDir = Vector3.new(1, 0, 0) end
	local springLaneOffset = rightDir * self._laneSpringPos

	-- Banking
	local machineWorldPos = FIXED_MACHINE_POS + springLaneOffset + Vector3.new(0, laneOffset.Y, 0)
	local lateralDelta = machineWorldPos.X - self._lastXPos
	self._lastXPos = machineWorldPos.X

	local curvatureBank = 0
	if dt > 0 then
		local lateralSpeed = lateralDelta / dt
		local speedFrac = self._currentSpeed / MAX_SPEED
		curvatureBank = math.clamp(-lateralSpeed * 0.008 * (0.5 + speedFrac), -MAX_BANK_ANGLE, MAX_BANK_ANGLE)
	end

	local switchBank = -self._lateralInput * LANE_SWITCH_BANK

	local targetRoll = math.clamp(curvatureBank + switchBank, -MAX_BANK_ANGLE, MAX_BANK_ANGLE)
	self._currentRoll = self._currentRoll + (targetRoll - self._currentRoll) * math.min(BANK_SMOOTH_SPEED * dt, 1)

	local now = time()
	local speedFrac01 = math.clamp(self._currentSpeed / MAX_SPEED, 0, 1)
	local bobY = math.sin(now * 2.4) * (0.15 + speedFrac01 * 0.25)
	local swayRoll = math.sin(now * 1.6 + 0.5) * math.rad(0.8 + speedFrac01 * 1.2)
	local swayPitch = math.sin(now * 1.9 + 1.2) * math.rad(0.4 + speedFrac01 * 0.6)

	local bobPos = machineWorldPos + Vector3.new(0, bobY, 0)
	local lookTarget = bobPos + centerDir
	local baseCF = CFrame.lookAt(bobPos, lookTarget)
	local finalCF = baseCF * CFrame.Angles(swayPitch, 0, self._currentRoll + swayRoll)
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
function LakelandRaceController:GetComboCount() return self._comboCount end

return LakelandRaceController
