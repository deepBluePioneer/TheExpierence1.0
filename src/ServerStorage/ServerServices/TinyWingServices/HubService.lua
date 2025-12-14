--[[
	HubService
	
	Creates a hub area where players spawn on a platform.
	Manages package spawning, collection, and kudos system.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local CustomPackages = ReplicatedStorage:WaitForChild("CustomPackages")
local Knit = require(Packages.Knit)
local Timer = require(Packages.timer)

-- Zone+ module
local ZoneRoot = CustomPackages:WaitForChild("ZoneRoot")
local Zone = require(ZoneRoot:WaitForChild("Zone"))

-- Replica module
local Replica = CustomPackages:WaitForChild("Replica")
local ReplicaService = require(Replica.ReplicaService)

-- Spline module
local Splines = CustomPackages:WaitForChild("Splines")
local CatmullRomSpline = require(Splines:WaitForChild("CatmullRomSpline"))

local HubService = Knit.CreateService {
	Name = "HubService",
	Client = {
		KudosEarned = Knit.CreateSignal(),  -- (amount: number, worldPosition: Vector3?)
	},
	
	-- References
	_hubFolder = nil,
	_spawnLocation = nil,
	_startZone = nil,
	
	-- Player timers: { [player] = { timer = Timer, replica = Replica, startTime = number } }
	_playerTimers = {},
	
	-- Track geometry for building collision avoidance
	-- Each entry: { center = Vector3, halfSize = Vector3 } (axis-aligned bounding box)
	_trackGeometry = {},
	
	-- Master collections for Powers system (togglable elements)
	_collections = {
		Crystals = nil,     -- Folder containing all crystals
		Blockades = nil,    -- Folder containing all blockades
		Rails = nil,        -- Folder containing all rails
		Gates = nil,        -- Folder containing all kudos gates
	},
	
	-- Player Kudos tracking
	_playerKudos = {},          -- { [player] = kudosAmount }
	_kudosReplicas = {},        -- { [player] = replica }
	
	-- Package tracking
	_packageStats = {
		totalSpawned = 0,       -- Total packages spawned this session
		totalCollected = 0,     -- Total packages collected/delivered
		activePackages = {},    -- List of currently active package models
	},
	_chuteStatusSign = nil,     -- Reference to status sign GUI
}

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         CONFIGURATION                                       ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

local CONFIG = {
	-- Start platform (SHIPPING CENTER design)
	StartPlatformSize = Vector3.new(150, 6, 100),
	StartPlatformPosition = Vector3.new(0, 50, -60),  -- Moved further back to prevent overlap with spline
	PlatformColor = Color3.fromRGB(70, 70, 75),           -- Industrial gray
	PlatformMaterial = Enum.Material.Concrete,
	
	-- Shipping center decorations
	StartPlatformAccentColor = Color3.fromRGB(255, 180, 0),   -- Warning yellow/orange
	StartPlatformEdgeColor = Color3.fromRGB(40, 40, 45),      -- Dark industrial
	StartPlatformGlowColor = Color3.fromRGB(255, 200, 50),    -- Warm warehouse light
	StartPlatformHasLights = true,
	StartPlatformHasStripes = true,
	StartPlatformHasEdgeTrim = true,
	
	-- Shipping center specific
	ShippingCenterWallHeight = 50,  -- Tall warehouse ceiling
	ShippingCenterWallColor = Color3.fromRGB(80, 85, 90),
	ShippingCenterRoofColor = Color3.fromRGB(60, 65, 70),
	ShippingCenterDoorColor = Color3.fromRGB(100, 110, 120),
	ShippingCenterWarningStripes = true,
	
	
	-- ═══════════════════════════════════════════════════════════════════════
	-- SPLINE-BASED TRACK GENERATION
	-- ═══════════════════════════════════════════════════════════════════════
	UseSplineTrack = true,                       -- Enable spline-based track (vs old segment-based)
	SplineTension = 0.7,                         -- Spline smoothness (0=sharp, 1=loose) - higher = smoother
	SplineSegmentsPerUnit = 0.5,                 -- Segments per stud of spline length (0.5 = segment every 2 studs)
	SplineSegmentLength = 8,                     -- Length of each track segment (overlap with neighbors)
	
	-- Track control points generation (Logistics conveyor path)
	TrackTotalLength = 800,                      -- Compact delivery route
	TrackNumControlPoints = 20,                  -- Minimal control points
	TrackMaxTurnAngle = 50,                      -- Tight industrial turns
	TrackMinSectionLength = 30,                  -- Short sections for snake-like curves
	TrackMaxSectionLength = 70,                  -- Keep sections short for more turns
	
	-- Initial straight section (connects to platform smoothly)
	TrackInitialStraightLength = 60,             -- Short straight before curves begin
	TrackInitialDropDistance = 80,               -- Quick descent for delivery
	
	-- Track height variation (industrial conveyor system)
	TrackStartHeight = 53,                       -- Starting Y position (matches platform top: 50 + 6/2 = 53)
	TrackMinHeight = -50,                        -- Minimum delivery height
	TrackMaxHeight = 150,                        -- Maximum conveyor height
	TrackDropPerSection = {2, 8},                -- Gentle conveyor slopes
	TrackRisePerSection = {2, 8},                -- Gentle rises
	TrackDropChance = 0.5,                       -- Equal chance up/down for varied route
	
	-- Track banking/tilt
	TrackBankingEnabled = true,                  -- Tilt track on turns
	TrackMaxBankAngle = 15,                      -- Gentle banking
	TrackBankSmoothing = 0.6,                    -- Smooth transitions
	
	-- Loops and Twists (ONE per track maximum)
	LoopsEnabled = false,                        -- Loops disabled (need path modification)
	LoopRadius = 40,                             -- Radius of the loop circle
	LoopSegments = 16,                           -- Number of segments per loop
	
	TwistsEnabled = false,                       -- Disabled for industrial conveyor
	TwistChance = 0,                             -- No twists
	TwistLength = 400,                           -- Length of track for the twist
	TwistMaxRotation = 90,                       -- Maximum rotation in degrees (90 = banked, not upside down)
	TwistSegments = 24,                          -- Number of segments per twist (smoothness)
	
	-- Checkpoints (DISABLED - not used)
	CheckpointEnabled = false,
	CheckpointInterval = 400,
	CheckpointSize = Vector3.new(60, 3, 40),
	
	-- Intermediate platform (square, at end of first slide) - Enhanced design
	MiddlePlatformSize = 120,                    -- Square size (same width/depth)
	MiddlePlatformHeight = 5,
	MiddlePlatformColor = Color3.fromRGB(50, 55, 65),
	MiddlePlatformAccentColors = {               -- Cycling accent colors per platform
		Color3.fromRGB(255, 100, 100),   -- Red/coral
		Color3.fromRGB(100, 255, 150),   -- Green/mint  
		Color3.fromRGB(100, 150, 255),   -- Blue
		Color3.fromRGB(255, 200, 100),   -- Orange/gold
		Color3.fromRGB(200, 100, 255),   -- Purple
		Color3.fromRGB(100, 255, 255),   -- Cyan
	},
	MiddlePlatformHasEdgeTrim = true,
	MiddlePlatformHasCornerLights = true,
	MiddlePlatformHasUnderglow = true,
	MiddlePlatformHasCenterMarking = true,
	
	-- Conveyor Slide settings (Industrial logistics style)
	SlideWidth = 80,                             -- Wide industrial conveyor
	SlideColor = Color3.fromRGB(60, 65, 70),     -- Dark metal/steel gray
	SlideMaterial = Enum.Material.DiamondPlate,  -- Industrial metal texture
	SlideSegmentLength = 6,                      -- Smaller = smoother curves
	SlideThickness = 6,                          -- Thick industrial platform
	
	-- Narrow zones (width variation)
	NarrowZoneEnabled = true,                    -- Enable width variation
	NarrowZoneChance = 0.4,                      -- 40% chance a slide has narrow zones
	NarrowZoneMinWidth = 60,                     -- Minimum width at narrowest point
	NarrowZoneTransitionLength = 80,             -- How long it takes to narrow/widen
	NarrowZoneDuration = 100,                    -- How long the narrow section lasts
	NarrowZonesPerSlide = {1, 3},                -- Min/max narrow zones per slide
	
	-- Guide Rails (Industrial safety barriers)
	RailHeight = 5,                              -- Safety rail height
	RailThickness = 2,                           -- Rail post width
	RailColor = Color3.fromRGB(255, 200, 0),     -- Safety yellow
	RailAccentColor = Color3.fromRGB(40, 40, 45), -- Dark metal accent
	RailMaterial = Enum.Material.Metal,          -- Industrial metal
	RailShape = "Bar",                           -- "Bar" for industrial barriers, "Spike" for wedges
	RailSegmentLength = 8,                       -- Spacing between spikes
	RailUseJointSpheres = false,                 -- No spheres for spikes
	RailSpikeStyle = true,                       -- Use spike style instead of tubes
	
	-- Light spires on rails (for visibility)
	RailSpiresEnabled = true,                    -- Enable tall spires with lights
	RailSpireSpacing = 40,                       -- Distance between spires (studs)
	RailSpireHeight = 30,                        -- Height of spire above rail (taller)
	RailSpireThickness = 0.6,                    -- Thickness of spire pole (thinner)
	RailSpireColor = Color3.fromRGB(50, 55, 60), -- Dark metal color
	RailSpireLightColor = Color3.fromRGB(255, 50, 50),  -- Red warning light
	RailSpireLightSize = 1,                      -- Size of light orb (smaller)
	RailSpireLightRange = 30,                    -- Light range
	RailSpireLightBrightness = 2,                -- Light brightness
	RailSpireBlinkSpeed = 1,                     -- Blinks per second
	
	-- Slope settings
	DownhillDropRate = 0.08,                     -- How steep downhill slides are (positive = down)
	UphillDropRate = -0.05,                      -- How steep uphill slides are (negative = up)
	
	-- Height boundaries
	MinHeight = -100,                            -- Don't go below this Y (kill zone safety)
	MaxHeight = 200,                             -- Don't go above this Y
	HeightWarningBuffer = 50,                    -- Start going up when within this distance of MinHeight
	
	-- Wave parameters
	SlideWaves = {
		{ Frequency = 0.02, Amplitude = 12, Phase = 0 },      -- Gentler waves
		{ Frequency = 0.05, Amplitude = 6, Phase = 1.2 },
		{ Frequency = 0.01, Amplitude = 15, Phase = 0.5 },
	},
	
	-- Slide generation settings
	NumSlides = 8,                              -- How many slides to generate
	SlideLengthMin = 400,                       -- Minimum slide length
	SlideLengthMax = 1400,                      -- Maximum slide length (double the min for variety)
	FirstSlideDirection = "z+",                 -- First slide always goes forward
	
	-- Slide colors (Industrial conveyor belt grays)
	SlideColors = {
		Color3.fromRGB(60, 65, 70),      -- Dark steel gray
		Color3.fromRGB(70, 75, 80),      -- Medium steel gray
		Color3.fromRGB(150, 170, 210),   -- Lighter blue
		Color3.fromRGB(135, 155, 195),   -- Medium blue
		Color3.fromRGB(145, 165, 205),   -- Blue tint
		Color3.fromRGB(140, 160, 200),   -- Base blue
		Color3.fromRGB(125, 145, 185),   -- Deep blue
		Color3.fromRGB(155, 175, 215),   -- Light blue
	},
	
	-- Platform colors (cycle through these)
	PlatformColors = {
		Color3.fromRGB(90, 85, 100),   -- Purple-gray
		Color3.fromRGB(100, 90, 80),   -- Brown
		Color3.fromRGB(80, 95, 100),   -- Blue-gray
		Color3.fromRGB(95, 80, 90),    -- Mauve
		Color3.fromRGB(85, 100, 85),   -- Green-gray
		Color3.fromRGB(100, 95, 80),   -- Tan
	},
	
	-- Final landing - Enhanced finish line design
	FinalLandingSize = Vector3.new(150, 3, 150),
	FinalLandingColor = Color3.fromRGB(40, 45, 55),
	FinalLandingAccentColor = Color3.fromRGB(255, 215, 0),  -- Gold finish
	FinalLandingHasCheckerboard = true,
	FinalLandingHasVictoryArch = true,
	
	-- Spawn location
	SpawnOffset = Vector3.new(0, 3, -20),
	
	-- Start Zone (wall at slide entrance)
	StartZoneEnabled = false,                    -- DISABLED - no timer/zone
	StartZoneSize = Vector3.new(120, 20, 5),     -- Wide wall at slide edge
	StartZoneColor = Color3.fromRGB(100, 200, 255),
	StartZoneTransparency = 0.7,
	
	-- Blockades (obstacles on slides)
	BlockadesEnabled = false,
	BlockadesPerSlide = {2, 5},                  -- Min/max blockades per slide
	BlockadeHeight = {15, 30},                   -- Min/max height of blockade
	BlockadeWidth = {20, 50},                    -- Min/max width of blockade (across the slide)
	BlockadeThickness = 6,                       -- How thick the blockade is
	BlockadeMinSpacing = 100,                    -- Minimum distance between blockades
	BlockadeEdgeBuffer = 30,                     -- How far from edges blockades can spawn
	BlockadeColors = {
		Color3.fromRGB(255, 80, 80),     -- Red warning
		Color3.fromRGB(255, 150, 50),    -- Orange
		Color3.fromRGB(80, 80, 90),      -- Dark metal
		Color3.fromRGB(200, 50, 50),     -- Deep red
	},
	BlockadeMaterial = Enum.Material.DiamondPlate,
	BlockadeHazardStripes = true,                -- Add yellow/black stripes
	
	-- Crystals (scattered collectibles/decorations)
	CrystalsEnabled = false,
	CrystalSize = {3, 6},                        -- Min/max size
	CrystalHeight = 2,                           -- How high above slide surface
	CrystalColors = {
		Color3.fromRGB(0, 255, 200),     -- Cyan/teal
		Color3.fromRGB(255, 100, 255),   -- Pink/magenta
		Color3.fromRGB(100, 200, 255),   -- Light blue
		Color3.fromRGB(255, 220, 50),    -- Gold
		Color3.fromRGB(150, 255, 100),   -- Lime green
		Color3.fromRGB(255, 150, 100),   -- Peach/orange
		Color3.fromRGB(200, 150, 255),   -- Lavender
	},
	CrystalMaterial = Enum.Material.Neon,        -- Glowing crystals
	CrystalTransparency = 0.3,                   -- Slightly transparent
	CrystalClusterChance = 0.15,                 -- 15% chance to spawn as a cluster
	CrystalClusterSize = {2, 3},                 -- Min/max crystals in a cluster
	
	-- Crystal Pattern Settings
	CrystalPattern = "zigzag",                   -- "zigzag", "wave", "lanes", "grid", "random"
	CrystalSpacing = 25,                         -- Distance between crystal rows
	CrystalLanes = 3,                            -- Number of lanes for "lanes" pattern
	CrystalWaveAmplitude = 0.7,                  -- How wide the wave pattern sweeps (0-1 of half-width)
	CrystalWaveFrequency = 0.03,                 -- Wave oscillation speed
	CrystalZigzagWidth = 0.6,                    -- How wide zigzag goes (0-1 of half-width)
	CrystalRowOffset = true,                     -- Offset alternate rows in grid pattern
	CrystalJitter = 5,                           -- Random position variation (studs)
	
	-- Crystal Particle Effects (adjustable via Iris)
	CrystalParticles = {
		-- Main burst particles
		BurstSize = 6,                   -- Starting size of sparkle particles
		BurstLifetimeMin = 1.5,          -- Minimum lifetime
		BurstLifetimeMax = 3,            -- Maximum lifetime
		BurstSpeed = 50,                 -- Particle speed
		BurstCount = 35,                 -- Number of particles
		BurstGravity = -20,              -- Downward acceleration
		BurstDrag = 1.5,                 -- Air resistance
		
		-- Glow particles
		GlowSize = 10,                   -- Size of glow orbs
		GlowLifetimeMin = 1,             -- Minimum lifetime
		GlowLifetimeMax = 2,             -- Maximum lifetime
		GlowSpeed = 25,                  -- Glow particle speed
		GlowCount = 15,                  -- Number of glow particles
	},
	
	-- Kudos Gates (ride through to earn currency)
	GatesEnabled = false,  -- DISABLED
	GatesPerSlide = {2, 5},                      -- Min/max gates per slide
	GateWidth = 30,                              -- Width of gate opening
	GateHeight = 20,                             -- Height of gate arch
	GatePillarWidth = 4,                         -- Thickness of gate pillars
	GateMinSpacing = 80,                         -- Minimum distance between gates
	GateKudosReward = {5, 15},                   -- Min/max kudos per gate
	GateColors = {
		Color3.fromRGB(255, 200, 50),    -- Gold (common)
		Color3.fromRGB(100, 220, 255),   -- Cyan (uncommon)
		Color3.fromRGB(220, 100, 255),   -- Purple (rare)
		Color3.fromRGB(255, 100, 150),   -- Pink (epic)
	},
	GateGlowColor = Color3.fromRGB(255, 230, 100),  -- Yellow glow
	GateMaterial = Enum.Material.Neon,
	
	-- Sky City Buildings (massive scale)
	BuildingsEnabled = true,
	BuildingsPerSlide = {8, 15},                 -- More buildings per slide
	BuildingDistanceFromTrack = {150, 1000},     -- Can be closer now with collision detection
	BuildingHeightRange = {400, 1200},           -- MASSIVE towers
	BuildingWidthRange = {60, 200},              -- Wide buildings
	BuildingBaseY = -500,                        -- All buildings extend down to this Y (deep below track)
	TrackCollisionBuffer = 50,                   -- Extra buffer around track geometry
	
	-- Building styles
	BuildingColors = {
		Color3.fromRGB(35, 40, 50),      -- Dark steel
		Color3.fromRGB(50, 55, 65),      -- Medium gray
		Color3.fromRGB(40, 45, 60),      -- Blue-gray
		Color3.fromRGB(55, 50, 48),      -- Warm gray
		Color3.fromRGB(38, 42, 52),      -- Cool gray
		Color3.fromRGB(60, 58, 55),      -- Light concrete
		Color3.fromRGB(30, 35, 45),      -- Very dark
		Color3.fromRGB(45, 48, 58),      -- Slate
	},
	BuildingMaterials = {
		Enum.Material.SmoothPlastic,
		Enum.Material.Concrete,
		Enum.Material.Metal,
		Enum.Material.DiamondPlate,
	},
	BuildingWindowChance = 0.8,                  -- More windows
	BuildingWindowColor = Color3.fromRGB(150, 200, 255),
	BuildingWindowSpacing = 25,                  -- Space between window rows
	
	-- Extra distant background buildings
	BackgroundBuildingsEnabled = true,
	BackgroundBuildingDistance = {800, 1500},    -- Very far away
	BackgroundBuildingsPerSlide = {4, 8},
	BackgroundBuildingScale = {1.5, 3},          -- Even larger scale multiplier
	
	
	
	-- Package Chute System (ceiling drop)
	PackageChuteEnabled = true,
	ChuteWidth = 14,                             -- Diameter of chute pipe
	ChuteColor = Color3.fromRGB(70, 75, 80),     -- Metal gray
	PackageSpawnInterval = 2,                    -- Seconds between package drops (when spawning)
	PackageSize = {8, 6, 8},                     -- Size of packages (X, Y, Z)
	PackageKudosMin = 5,                         -- Minimum kudos per package
	PackageKudosMax = 50,                        -- Maximum kudos per package
	PackageColors = {                            -- Random package colors
		Color3.fromRGB(139, 90, 43),             -- Cardboard brown
		Color3.fromRGB(160, 100, 50),            -- Light brown
		Color3.fromRGB(120, 80, 40),             -- Dark brown
	},
	
	-- Package limits and spawning behavior
	PackageInitialSpawn = 20,                    -- Spawn this many packages initially
	PackageTargetActive = 20,                    -- Try to maintain this many active packages (no max limit)
	
	-- Delivery Bonus System
	DeliveryBonusPerPackage = 5,                 -- Flat bonus kudos for EACH package delivered
	StackBonusThresholds = {                     -- Stack size bonuses (cumulative)
		{ minStack = 3,  bonusPercent = 10 },   -- 3+ packages = +10% bonus
		{ minStack = 5,  bonusPercent = 25 },   -- 5+ packages = +25% bonus
		{ minStack = 8,  bonusPercent = 50 },   -- 8+ packages = +50% bonus
		{ minStack = 12, bonusPercent = 100 },  -- 12+ packages = +100% bonus (double!)
	},
}

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         HELPER FUNCTIONS                                    ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

local function createPart(name, size, position, color, material, parent)
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.Position = position
	part.Color = color
	part.Material = material
	part.Anchored = true
	part.Parent = parent
	return part
end

-- Create industrial safety barriers along a platform edge
-- startPos, endPos: Vector3 positions for the rail
-- yOffset: height above platform surface
-- parent: parent instance
local function createTubularPlatformRail(name, startPos, endPos, yOffset, parent)
	local direction = endPos - startPos
	local length = direction.Magnitude
	if length < 0.1 then return end
	
	local lookDir = direction.Unit
	local numPosts = math.max(2, math.floor(length / CONFIG.RailSegmentLength))
	
	-- Create posts along the edge based on RailShape config
	for i = 0, numPosts do
		local t = i / numPosts
		local postBasePos = startPos:Lerp(endPos, t) + Vector3.new(0, yOffset, 0)
		local cf = CFrame.lookAt(postBasePos, postBasePos + lookDir)
		
		if CONFIG.RailShape == "Bar" then
			-- Industrial safety bar
			local bar = Instance.new("Part")
			bar.Name = name .. "_Bar_" .. i
			bar.Size = Vector3.new(CONFIG.RailThickness, CONFIG.RailHeight, CONFIG.RailThickness * 2)
			bar.Color = CONFIG.RailColor
			bar.Material = CONFIG.RailMaterial
			bar.Anchored = true
			bar.CanCollide = true
			bar.CFrame = cf * CFrame.new(0, CONFIG.RailHeight / 2, 0)
			bar.Parent = parent
			
			-- Add hazard stripe
			if i % 2 == 0 then
				local stripe = Instance.new("Part")
				stripe.Name = name .. "_Stripe_" .. i
				stripe.Size = Vector3.new(CONFIG.RailThickness + 0.1, CONFIG.RailHeight * 0.3, CONFIG.RailThickness * 2 + 0.1)
				stripe.Color = Color3.fromRGB(30, 30, 35)
				stripe.Material = Enum.Material.SmoothPlastic
				stripe.Anchored = true
				stripe.CanCollide = false
				stripe.CFrame = cf * CFrame.new(0, CONFIG.RailHeight * 0.35, 0)
				stripe.Parent = parent
			end
		else
			-- Spike (wedge)
			local spike = Instance.new("WedgePart")
			spike.Name = name .. "_Spike_" .. i
			spike.Size = Vector3.new(CONFIG.RailThickness, CONFIG.RailHeight, CONFIG.RailThickness * 1.5)
			spike.Color = CONFIG.RailColor
			spike.Material = CONFIG.RailMaterial
			spike.Anchored = true
			spike.CanCollide = true
			spike.CFrame = cf * CFrame.new(0, CONFIG.RailHeight / 2, 0)
			spike.Parent = parent
		end
	end
	
	return nil
end

-- Create industrial safety rails (for shipping center - NOT spikes)
local function createSafetyRail(name, startPos, endPos, yOffset, color, parent)
	local direction = endPos - startPos
	local length = direction.Magnitude
	if length < 0.1 then return end
	
	local midPos = (startPos + endPos) / 2 + Vector3.new(0, yOffset, 0)
	local lookDir = direction.Unit
	
	local railHeight = 4
	local railThickness = 0.8
	local postSpacing = 15
	
	-- Horizontal top rail
	local topRail = Instance.new("Part")
	topRail.Name = name .. "_TopRail"
	topRail.Size = Vector3.new(railThickness, railThickness, length)
	topRail.Position = midPos + Vector3.new(0, railHeight, 0)
	topRail.Color = color or Color3.fromRGB(255, 200, 0)  -- Yellow safety
	topRail.Material = Enum.Material.Metal
	topRail.Anchored = true
	topRail.CanCollide = true
	topRail.CFrame = CFrame.lookAt(topRail.Position, topRail.Position + lookDir)
	topRail.Parent = parent
	
	-- Horizontal middle rail
	local midRail = Instance.new("Part")
	midRail.Name = name .. "_MidRail"
	midRail.Size = Vector3.new(railThickness, railThickness, length)
	midRail.Position = midPos + Vector3.new(0, railHeight / 2, 0)
	midRail.Color = color or Color3.fromRGB(255, 200, 0)
	midRail.Material = Enum.Material.Metal
	midRail.Anchored = true
	midRail.CanCollide = true
	midRail.CFrame = CFrame.lookAt(midRail.Position, midRail.Position + lookDir)
	midRail.Parent = parent
	
	-- Vertical posts
	local numPosts = math.max(2, math.floor(length / postSpacing) + 1)
	for i = 0, numPosts - 1 do
		local t = i / math.max(numPosts - 1, 1)
		local postPos = startPos:Lerp(endPos, t) + Vector3.new(0, yOffset + railHeight / 2, 0)
		
		local post = Instance.new("Part")
		post.Name = name .. "_Post_" .. i
		post.Size = Vector3.new(railThickness * 1.5, railHeight, railThickness * 1.5)
		post.Position = postPos
		post.Color = Color3.fromRGB(60, 60, 65)  -- Dark metal posts
		post.Material = Enum.Material.Metal
		post.Anchored = true
		post.CanCollide = true
		post.Parent = parent
	end
	
	return topRail
end

-- Create an end shipping center (receiving/delivery center at end of track)
-- entrancePos: position where the track ends (entrance to the room)
-- trackDirection: Vector3 direction the track was going (tangent at end)
-- platformSize: Vector3 for floor dimensions
-- parent: parent instance
local function createEndShippingCenter(entrancePos, trackDirection, platformSize, parent)
	local endShippingModel = Instance.new("Model")
	endShippingModel.Name = "EndShippingCenter"
	endShippingModel.Parent = parent
	
	-- Calculate rotation: room faces OPPOSITE to track direction (entrance faces track)
	local flatDirection = Vector3.new(trackDirection.X, 0, trackDirection.Z)
	if flatDirection.Magnitude < 0.01 then
		flatDirection = Vector3.new(0, 0, 1)
	else
		flatDirection = flatDirection.Unit
	end
	
	-- Room layout: entrance at +Z local, back wall at -Z local
	local halfX = platformSize.X / 2
	local halfZ = platformSize.Z / 2
	local wallHeight = CONFIG.ShippingCenterWallHeight
	local wallThickness = 3
	
	-- Create rotation CFrame first
	-- CFrame.lookAt makes -Z point toward target
	-- We want +Z (entrance) to face where track CAME FROM (opposite to flatDirection)
	-- So -Z should face flatDirection (where track was going)
	local rotationOnly = CFrame.lookAt(Vector3.zero, flatDirection)
	
	-- Entrance is at +Z local from center
	-- +Z local maps to -flatDirection in world space
	-- So: entrancePos = roomCenter + (-flatDirection) * halfZ
	-- Therefore: roomCenter = entrancePos + flatDirection * halfZ
	local roomCenterXZ = Vector3.new(entrancePos.X, 0, entrancePos.Z) + flatDirection * halfZ
	local floorY = entrancePos.Y - platformSize.Y / 2
	local roomCenter = Vector3.new(roomCenterXZ.X, floorY, roomCenterXZ.Z)
	local floorTopY = floorY + platformSize.Y / 2
	
	-- Helper to create a part with local offset AND rotation
	local function createPartAtOffset(name, size, localOffset, color, material, partParent, canCollide)
		local part = Instance.new("Part")
		part.Name = name
		part.Size = size
		-- Transform local offset to world space and apply rotation
		local worldOffset = rotationOnly:VectorToWorldSpace(localOffset)
		local worldPos = roomCenter + worldOffset
		part.CFrame = CFrame.new(worldPos) * rotationOnly
		part.Color = color
		part.Material = material or Enum.Material.SmoothPlastic
		part.Anchored = true
		part.CanCollide = canCollide ~= false
		part.Parent = partParent or endShippingModel
		return part
	end
	
	-- Create floor
	local floor = createPartAtOffset(
		"ReceivingFloor",
		platformSize,
		Vector3.new(0, 0, 0),
		CONFIG.PlatformColor,
		CONFIG.PlatformMaterial,
		endShippingModel,
		true
	)
	
	-- Set floor as PrimaryPart
	endShippingModel.PrimaryPart = floor
	
	-- Back wall (opposite entrance)
	createPartAtOffset(
		"BackWall",
		Vector3.new(platformSize.X, wallHeight, wallThickness),
		Vector3.new(0, platformSize.Y/2 + wallHeight/2, -halfZ - wallThickness/2),
		CONFIG.ShippingCenterWallColor,
		Enum.Material.Concrete,
		endShippingModel
	)
	
	-- Left wall
	createPartAtOffset(
		"LeftWall",
		Vector3.new(wallThickness, wallHeight, platformSize.Z),
		Vector3.new(-halfX - wallThickness/2, platformSize.Y/2 + wallHeight/2, 0),
		CONFIG.ShippingCenterWallColor,
		Enum.Material.Concrete,
		endShippingModel
	)
	
	-- Right wall
	createPartAtOffset(
		"RightWall",
		Vector3.new(wallThickness, wallHeight, platformSize.Z),
		Vector3.new(halfX + wallThickness/2, platformSize.Y/2 + wallHeight/2, 0),
		CONFIG.ShippingCenterWallColor,
		Enum.Material.Concrete,
		endShippingModel
	)
	
	-- ROOF with skylights
	local roofThickness = 2
	createPartAtOffset(
		"ReceivingRoof",
		Vector3.new(platformSize.X + wallThickness * 2, roofThickness, platformSize.Z + wallThickness * 2),
		Vector3.new(0, platformSize.Y/2 + wallHeight + roofThickness/2, 0),
		CONFIG.ShippingCenterRoofColor,
		Enum.Material.Metal,
		endShippingModel
	)
	
	-- Skylights
	for i = 1, 3 do
		local skylightLocalX = -halfX + (i / 4) * platformSize.X
		local skylight = createPartAtOffset(
			"Skylight_" .. i,
			Vector3.new(15, roofThickness + 0.1, platformSize.Z * 0.4),
			Vector3.new(skylightLocalX, platformSize.Y/2 + wallHeight + roofThickness/2, 0),
			Color3.fromRGB(200, 220, 255),
			Enum.Material.Glass,
			endShippingModel,
			false
		)
		skylight.Transparency = 0.6
	end
	
	-- Loading dock hazard stripes (at entrance - front/+Z local)
	local dockEdgeWidth = 5
	createPartAtOffset(
		"LoadingDockStripe",
		Vector3.new(platformSize.X, 0.5, dockEdgeWidth),
		Vector3.new(0, platformSize.Y/2 + 0.25, halfZ - dockEdgeWidth/2),
		Color3.fromRGB(255, 200, 0),
		Enum.Material.SmoothPlastic,
		endShippingModel,
		false
	)
	
	-- Industrial hanging warehouse lights
	local lightRows = 2
	local lightsPerRow = 3
	
	for row = 1, lightRows do
		for col = 1, lightsPerRow do
			local lightLocalX = -halfX + (col / (lightsPerRow + 1)) * platformSize.X
			local lightLocalZ = -halfZ + (row / (lightRows + 1)) * platformSize.Z
			local lightLocalY = platformSize.Y/2 + wallHeight - 3
			
			-- Light fixture
			createPartAtOffset(
				"LightFixture_" .. row .. "_" .. col,
				Vector3.new(4, 2, 4),
				Vector3.new(lightLocalX, lightLocalY, lightLocalZ),
				Color3.fromRGB(50, 50, 55),
				Enum.Material.Metal,
				endShippingModel,
				false
			)
			
			-- Light bulb
			local bulb = createPartAtOffset(
				"LightBulb_" .. row .. "_" .. col,
				Vector3.new(3, 3, 3),
				Vector3.new(lightLocalX, lightLocalY - 1.5, lightLocalZ),
				Color3.fromRGB(255, 240, 200),
				Enum.Material.Neon,
				endShippingModel,
				false
			)
			bulb.Shape = Enum.PartType.Ball
			
			local pointLight = Instance.new("PointLight")
			pointLight.Color = Color3.fromRGB(255, 245, 220)
			pointLight.Brightness = 1.02
			pointLight.Range = 60
			pointLight.Parent = bulb
		end
	end
	
	-- Receiving Center sign (on back wall)
	local signPart = createPartAtOffset(
		"ReceivingCenterSign",
		Vector3.new(50, 6, 1),
		Vector3.new(0, platformSize.Y/2 + wallHeight - 5, -halfZ - wallThickness - 1),
		Color3.fromRGB(20, 100, 60),
		Enum.Material.SmoothPlastic,
		endShippingModel,
		true
	)
	
	local signGui = Instance.new("SurfaceGui")
	signGui.Face = Enum.NormalId.Back
	signGui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	signGui.PixelsPerStud = 30
	signGui.Parent = signPart
	
	local signText = Instance.new("TextLabel")
	signText.Size = UDim2.new(1, 0, 1, 0)
	signText.BackgroundTransparency = 1
	signText.Text = "📦 RECEIVING CENTER 📦"
	signText.TextColor3 = Color3.fromRGB(255, 255, 255)
	signText.TextScaled = true
	signText.Font = Enum.Font.GothamBold
	signText.Parent = signGui
	
	-- Safety rails on closed sides (back, left, right - not front/entrance)
	local safetyColor = Color3.fromRGB(255, 200, 0)
	
	-- Transform local corners to world space for rails
	local function localToWorld(localPos)
		local worldOffset = rotationOnly:VectorToWorldSpace(localPos)
		return roomCenter + worldOffset
	end
	
	-- Back rail
	createSafetyRail(
		"EndShipping_BackRail",
		localToWorld(Vector3.new(-halfX, platformSize.Y/2, -halfZ)),
		localToWorld(Vector3.new(halfX, platformSize.Y/2, -halfZ)),
		0,
		safetyColor,
		endShippingModel
	)
	
	-- Left rail
	createSafetyRail(
		"EndShipping_LeftRail",
		localToWorld(Vector3.new(-halfX, platformSize.Y/2, -halfZ)),
		localToWorld(Vector3.new(-halfX, platformSize.Y/2, halfZ)),
		0,
		safetyColor,
		endShippingModel
	)
	
	-- Right rail
	createSafetyRail(
		"EndShipping_RightRail",
		localToWorld(Vector3.new(halfX, platformSize.Y/2, -halfZ)),
		localToWorld(Vector3.new(halfX, platformSize.Y/2, halfZ)),
		0,
		safetyColor,
		endShippingModel
	)
	
	-- ═══════════════════════════════════════════════════════════════════════
	-- POLISHED PACKAGE COLLECTION TERMINAL
	-- ═══════════════════════════════════════════════════════════════════════
	
	local binSize = Vector3.new(24, 3, 24)
	local binCenterOffset = Vector3.new(0, platformSize.Y/2, -halfZ/2)
	
	-- Elevated platform base with industrial look
	local platformBase = createPartAtOffset(
		"CollectionPlatformBase",
		Vector3.new(binSize.X + 8, 1, binSize.Z + 8),
		binCenterOffset + Vector3.new(0, 0.5, 0),
		Color3.fromRGB(45, 45, 50),
		Enum.Material.DiamondPlate,
		endShippingModel,
		true
	)
	
	-- Inner recessed area (the collection pit)
	local recessedPit = createPartAtOffset(
		"CollectionPit",
		Vector3.new(binSize.X, 0.8, binSize.Z),
		binCenterOffset + Vector3.new(0, 0.6, 0),
		Color3.fromRGB(25, 25, 30),
		Enum.Material.Metal,
		endShippingModel,
		true
	)
	
	-- Glowing floor grid pattern
	local gridSpacing = 6
	for gx = -1, 1 do
		for gz = -1, 1 do
			local gridPart = createPartAtOffset(
				"GridLight_" .. gx .. "_" .. gz,
				Vector3.new(4, 0.15, 4),
				binCenterOffset + Vector3.new(gx * gridSpacing, 1.05, gz * gridSpacing),
				Color3.fromRGB(0, 200, 150),  -- Teal glow
				Enum.Material.Neon,
				endShippingModel,
				false
			)
			gridPart.Transparency = 0.4
		end
	end
	
	-- Central collection point (glowing circle)
	local centralGlow = createPartAtOffset(
		"CentralGlow",
		Vector3.new(8, 0.2, 8),
		binCenterOffset + Vector3.new(0, 1.1, 0),
		Color3.fromRGB(0, 255, 200),  -- Bright teal
		Enum.Material.Neon,
		endShippingModel,
		false
	)
	centralGlow.Shape = Enum.PartType.Cylinder
	centralGlow.CFrame = centralGlow.CFrame * CFrame.Angles(0, 0, math.rad(90))
	centralGlow.Transparency = 0.3
	
	-- Holographic ring above collection point
	local holoRing = createPartAtOffset(
		"HoloRing",
		Vector3.new(16, 0.3, 16),
		binCenterOffset + Vector3.new(0, 4, 0),
		Color3.fromRGB(0, 220, 180),
		Enum.Material.Neon,
		endShippingModel,
		false
	)
	holoRing.Shape = Enum.PartType.Cylinder
	holoRing.CFrame = holoRing.CFrame * CFrame.Angles(0, 0, math.rad(90))
	holoRing.Transparency = 0.6
	
	-- Inner holographic ring
	local holoRingInner = createPartAtOffset(
		"HoloRingInner",
		Vector3.new(10, 0.4, 10),
		binCenterOffset + Vector3.new(0, 4, 0),
		Color3.fromRGB(0, 255, 220),
		Enum.Material.Neon,
		endShippingModel,
		false
	)
	holoRingInner.Shape = Enum.PartType.Cylinder
	holoRingInner.CFrame = holoRingInner.CFrame * CFrame.Angles(0, 0, math.rad(90))
	holoRingInner.Transparency = 0.5
	
	-- Corner scanner pillars
	local pillarPositions = {
		Vector3.new(-binSize.X/2 - 2, 0, -binSize.Z/2 - 2),
		Vector3.new(binSize.X/2 + 2, 0, -binSize.Z/2 - 2),
		Vector3.new(-binSize.X/2 - 2, 0, binSize.Z/2 + 2),
		Vector3.new(binSize.X/2 + 2, 0, binSize.Z/2 + 2),
	}
	
	for i, pillarOffset in ipairs(pillarPositions) do
		-- Main pillar body
		local pillar = createPartAtOffset(
			"ScannerPillar_" .. i,
			Vector3.new(1.5, 8, 1.5),
			binCenterOffset + Vector3.new(pillarOffset.X, 4, pillarOffset.Z),
			Color3.fromRGB(40, 40, 45),
			Enum.Material.Metal,
			endShippingModel,
			true
		)
		
		-- Pillar accent strip
		local accentStrip = createPartAtOffset(
			"PillarAccent_" .. i,
			Vector3.new(0.3, 6, 0.3),
			binCenterOffset + Vector3.new(pillarOffset.X * 0.9, 4, pillarOffset.Z * 0.9),
			Color3.fromRGB(0, 200, 160),
			Enum.Material.Neon,
			endShippingModel,
			false
		)
		accentStrip.Transparency = 0.2
		
		-- Scanner head on top
		local scannerHead = createPartAtOffset(
			"ScannerHead_" .. i,
			Vector3.new(2.5, 1.5, 2.5),
			binCenterOffset + Vector3.new(pillarOffset.X, 8.5, pillarOffset.Z),
			Color3.fromRGB(30, 30, 35),
			Enum.Material.Metal,
			endShippingModel,
			true
		)
		
		-- Scanner lens (points toward center)
		local lensDir = -Vector3.new(pillarOffset.X, -2, pillarOffset.Z).Unit
		local lens = createPartAtOffset(
			"ScannerLens_" .. i,
			Vector3.new(1, 1, 1),
			binCenterOffset + Vector3.new(pillarOffset.X * 0.85, 8.5, pillarOffset.Z * 0.85),
			Color3.fromRGB(0, 255, 200),
			Enum.Material.Neon,
			endShippingModel,
			false
		)
		lens.Shape = Enum.PartType.Ball
		lens.Transparency = 0.3
		
		-- Scanner spotlight
		local spotlight = Instance.new("SpotLight")
		spotlight.Color = Color3.fromRGB(0, 255, 200)
		spotlight.Brightness = 2
		spotlight.Range = 25
		spotlight.Angle = 35
		spotlight.Face = Enum.NormalId.Bottom
		spotlight.Parent = scannerHead
	end
	
	-- Counter display panel (floating)
	local counterPanel = createPartAtOffset(
		"CounterPanel",
		Vector3.new(18, 6, 0.5),
		binCenterOffset + Vector3.new(0, 12, -binSize.Z/2 - 6),
		Color3.fromRGB(20, 25, 30),
		Enum.Material.SmoothPlastic,
		endShippingModel,
		false
	)
	
	-- Counter panel glow edge
	local panelGlow = createPartAtOffset(
		"PanelGlow",
		Vector3.new(18.5, 6.5, 0.3),
		binCenterOffset + Vector3.new(0, 12, -binSize.Z/2 - 6.2),
		Color3.fromRGB(0, 180, 150),
		Enum.Material.Neon,
		endShippingModel,
		false
	)
	panelGlow.Transparency = 0.5
	
	-- Counter display GUI
	local counterGui = Instance.new("SurfaceGui")
	counterGui.Name = "CounterGui"
	counterGui.Face = Enum.NormalId.Front
	counterGui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	counterGui.PixelsPerStud = 50
	counterGui.Parent = counterPanel
	
	local counterFrame = Instance.new("Frame")
	counterFrame.Size = UDim2.new(1, 0, 1, 0)
	counterFrame.BackgroundTransparency = 1
	counterFrame.Parent = counterGui
	
	-- Title text
	local titleLabel = Instance.new("TextLabel")
	titleLabel.Name = "Title"
	titleLabel.Size = UDim2.new(1, 0, 0.3, 0)
	titleLabel.Position = UDim2.new(0, 0, 0, 0)
	titleLabel.BackgroundTransparency = 1
	titleLabel.Text = "📦 DELIVERY TERMINAL"
	titleLabel.TextColor3 = Color3.fromRGB(0, 220, 180)
	titleLabel.TextScaled = true
	titleLabel.Font = Enum.Font.GothamBold
	titleLabel.Parent = counterFrame
	
	-- Instruction text
	local instructionLabel = Instance.new("TextLabel")
	instructionLabel.Name = "Instruction"
	instructionLabel.Size = UDim2.new(1, 0, 0.25, 0)
	instructionLabel.Position = UDim2.new(0, 0, 0.3, 0)
	instructionLabel.BackgroundTransparency = 1
	instructionLabel.Text = "Press [E] to deposit packages"
	instructionLabel.TextColor3 = Color3.fromRGB(180, 180, 190)
	instructionLabel.TextScaled = true
	instructionLabel.Font = Enum.Font.Gotham
	instructionLabel.Parent = counterFrame
	
	-- Status text (will be updated during collection)
	local statusLabel = Instance.new("TextLabel")
	statusLabel.Name = "Status"
	statusLabel.Size = UDim2.new(1, 0, 0.35, 0)
	statusLabel.Position = UDim2.new(0, 0, 0.6, 0)
	statusLabel.BackgroundTransparency = 1
	statusLabel.Text = "✓ READY"
	statusLabel.TextColor3 = Color3.fromRGB(0, 255, 150)
	statusLabel.TextScaled = true
	statusLabel.Font = Enum.Font.GothamBold
	statusLabel.Parent = counterFrame
	
	-- Also show on back
	local counterGui2 = counterGui:Clone()
	counterGui2.Face = Enum.NormalId.Back
	counterGui2.Parent = counterPanel
	
	-- Store reference to status label for updates
	endShippingModel:SetAttribute("HasStatusDisplay", true)
	
	-- Arrow indicators pointing down to collection zone
	for side = 1, 4 do
		local angle = (side - 1) * math.pi / 2
		local arrowOffset = Vector3.new(math.cos(angle) * 18, 3, math.sin(angle) * 18)
		
		local arrow = createPartAtOffset(
			"Arrow_" .. side,
			Vector3.new(3, 0.3, 5),
			binCenterOffset + arrowOffset,
			Color3.fromRGB(0, 200, 150),
			Enum.Material.Neon,
			endShippingModel,
			false
		)
		arrow.Transparency = 0.4
		-- Rotate arrow to point toward center
		local lookAt = binCenterOffset + Vector3.new(0, 3, 0)
		local arrowPos = binCenterOffset + arrowOffset
		arrow.CFrame = CFrame.lookAt(arrow.Position, arrow.Position - arrowOffset) * CFrame.Angles(math.rad(-45), 0, 0)
	end
	
	-- Create invisible collection zone (trigger area)
	local collectionZone = createPartAtOffset(
		"PackageCollectionZone",
		Vector3.new(binSize.X, 12, binSize.Z),
		binCenterOffset + Vector3.new(0, 6, 0),
		Color3.fromRGB(100, 50, 150),
		Enum.Material.SmoothPlastic,
		endShippingModel,
		false
	)
	collectionZone.Transparency = 1
	collectionZone.CanQuery = true
	collectionZone.CanTouch = true
	
	-- Store references
	endShippingModel:SetAttribute("HasCollectionZone", true)
	collectionZone:SetAttribute("IsCollectionZone", true)
	
	-- Store panel references for status updates during collection
	collectionZone:SetAttribute("CounterPanelName", "CounterPanel")
	collectionZone:SetAttribute("CentralGlowName", "CentralGlow")
	
	print("[HubService] End Shipping Center with polished Delivery Terminal created, facing track from:", entrancePos)
	
	return {
		model = endShippingModel,
		floor = floor,
		floorTopY = floorTopY,
		collectionZone = collectionZone,
	}
end

-- Create enhanced platform decorations (edge trim, lights, center marking, underglow)
-- platformPos: center position of platform
-- platformSize: Vector3 (X, Y, Z) or number (square platform)
-- accentColor: Color3 for glowing elements
-- options: { hasEdgeTrim, hasCornerLights, hasUnderglow, hasCenterMarking, hasCheckerboard, platformIndex }
local function decoratePlatform(platformPos, platformSize, accentColor, options, parent)
	options = options or {}
	
	-- Normalize size to Vector3
	local sizeX, sizeY, sizeZ
	if typeof(platformSize) == "number" then
		sizeX, sizeY, sizeZ = platformSize, CONFIG.MiddlePlatformHeight, platformSize
	else
		sizeX, sizeY, sizeZ = platformSize.X, platformSize.Y, platformSize.Z
	end
	
	local topY = platformPos.Y + sizeY / 2
	local halfX = sizeX / 2
	local halfZ = sizeZ / 2
	local decorFolder = Instance.new("Folder")
	decorFolder.Name = "PlatformDecor_" .. (options.platformIndex or "0")
	decorFolder.Parent = parent
	
	-- Edge trim (glowing neon border)
	if options.hasEdgeTrim then
		local trimHeight = 0.8
		local trimWidth = 2
		
		-- Create trim on all four edges
		local edges = {
			{name = "FrontTrim", size = Vector3.new(sizeX + trimWidth * 2, trimHeight, trimWidth), 
			 pos = Vector3.new(platformPos.X, topY + trimHeight/2, platformPos.Z + halfZ + trimWidth/2)},
			{name = "BackTrim", size = Vector3.new(sizeX + trimWidth * 2, trimHeight, trimWidth),
			 pos = Vector3.new(platformPos.X, topY + trimHeight/2, platformPos.Z - halfZ - trimWidth/2)},
			{name = "LeftTrim", size = Vector3.new(trimWidth, trimHeight, sizeZ),
			 pos = Vector3.new(platformPos.X - halfX - trimWidth/2, topY + trimHeight/2, platformPos.Z)},
			{name = "RightTrim", size = Vector3.new(trimWidth, trimHeight, sizeZ),
			 pos = Vector3.new(platformPos.X + halfX + trimWidth/2, topY + trimHeight/2, platformPos.Z)},
		}
		
		for _, edge in ipairs(edges) do
			local trim = Instance.new("Part")
			trim.Name = edge.name
			trim.Size = edge.size
			trim.Position = edge.pos
			trim.Color = accentColor
			trim.Material = Enum.Material.Neon
			trim.Anchored = true
			trim.CanCollide = false
			trim.Parent = decorFolder
		end
	end
	
	-- Corner lights (glowing orbs on poles)
	if options.hasCornerLights then
		local lightHeight = 8
		local lightRadius = 1.5
		local cornerOffset = 0.85  -- How far inside from corners
		
		local corners = {
			Vector3.new(-halfX * cornerOffset, 0, -halfZ * cornerOffset),
			Vector3.new(halfX * cornerOffset, 0, -halfZ * cornerOffset),
			Vector3.new(-halfX * cornerOffset, 0, halfZ * cornerOffset),
			Vector3.new(halfX * cornerOffset, 0, halfZ * cornerOffset),
		}
		
		for i, offset in ipairs(corners) do
			-- Light pole
			local pole = Instance.new("Part")
			pole.Name = "LightPole_" .. i
			pole.Shape = Enum.PartType.Cylinder
			pole.Size = Vector3.new(lightHeight, 1, 1)
			pole.Position = platformPos + offset + Vector3.new(0, topY - platformPos.Y + lightHeight/2, 0)
			pole.Color = Color3.fromRGB(60, 65, 75)
			pole.Material = Enum.Material.Metal
			pole.Anchored = true
			pole.CanCollide = false
			pole.CFrame = CFrame.new(pole.Position) * CFrame.Angles(0, 0, math.pi/2)
			pole.Parent = decorFolder
			
			-- Light orb
			local orb = Instance.new("Part")
			orb.Name = "LightOrb_" .. i
			orb.Shape = Enum.PartType.Ball
			orb.Size = Vector3.new(lightRadius * 2, lightRadius * 2, lightRadius * 2)
			orb.Position = pole.Position + Vector3.new(0, lightHeight/2 + lightRadius, 0)
			orb.Color = accentColor
			orb.Material = Enum.Material.Neon
			orb.Anchored = true
			orb.CanCollide = false
			orb.Parent = decorFolder
			
			-- Point light
			local light = Instance.new("PointLight")
			light.Color = accentColor
			light.Brightness = 1.5
			light.Range = 25
			light.Parent = orb
		end
	end
	
	-- Center marking (glowing platform number or design)
	if options.hasCenterMarking then
		-- Cross pattern
		local markingSize = math.min(sizeX, sizeZ) * 0.3
		local markingThickness = 0.2
		
		local crossH = Instance.new("Part")
		crossH.Name = "CenterCrossH"
		crossH.Size = Vector3.new(markingSize, markingThickness, markingSize * 0.15)
		crossH.Position = Vector3.new(platformPos.X, topY + markingThickness/2, platformPos.Z)
		crossH.Color = accentColor
		crossH.Material = Enum.Material.Neon
		crossH.Transparency = 0.2
		crossH.Anchored = true
		crossH.CanCollide = false
		crossH.Parent = decorFolder
		
		local crossV = Instance.new("Part")
		crossV.Name = "CenterCrossV"
		crossV.Size = Vector3.new(markingSize * 0.15, markingThickness, markingSize)
		crossV.Position = Vector3.new(platformPos.X, topY + markingThickness/2, platformPos.Z)
		crossV.Color = accentColor
		crossV.Material = Enum.Material.Neon
		crossV.Transparency = 0.2
		crossV.Anchored = true
		crossV.CanCollide = false
		crossV.Parent = decorFolder
		
		-- Outer ring
		local ringSize = markingSize * 0.8
		local ringParts = 8
		for i = 1, ringParts do
			local angle = (i / ringParts) * math.pi * 2
			local ringPart = Instance.new("Part")
			ringPart.Name = "CenterRing_" .. i
			ringPart.Size = Vector3.new(ringSize * 0.15, markingThickness, ringSize * 0.4)
			ringPart.Position = Vector3.new(
				platformPos.X + math.cos(angle) * ringSize * 0.5,
				topY + markingThickness/2,
				platformPos.Z + math.sin(angle) * ringSize * 0.5
			)
			ringPart.Color = accentColor
			ringPart.Material = Enum.Material.Neon
			ringPart.Transparency = 0.4
			ringPart.Anchored = true
			ringPart.CanCollide = false
			ringPart.CFrame = CFrame.new(ringPart.Position) * CFrame.Angles(0, angle + math.pi/2, 0)
			ringPart.Parent = decorFolder
		end
	end
	
	-- Underglow (glowing plate underneath)
	if options.hasUnderglow then
		local glow = Instance.new("Part")
		glow.Name = "Underglow"
		glow.Size = Vector3.new(sizeX - 8, 1.5, sizeZ - 8)
		glow.Position = Vector3.new(platformPos.X, platformPos.Y - sizeY/2 - 0.75, platformPos.Z)
		glow.Color = accentColor
		glow.Material = Enum.Material.Neon
		glow.Transparency = 0.6
		glow.Anchored = true
		glow.CanCollide = false
		glow.Parent = decorFolder
	end
	
	-- Checkerboard pattern (for finish line)
	if options.hasCheckerboard then
		local tileSize = 15
		local tilesX = math.floor(sizeX / tileSize)
		local tilesZ = math.floor(sizeZ / tileSize)
		local startX = platformPos.X - (tilesX * tileSize) / 2 + tileSize / 2
		local startZ = platformPos.Z - (tilesZ * tileSize) / 2 + tileSize / 2
		
		for tx = 0, tilesX - 1 do
			for tz = 0, tilesZ - 1 do
				local isWhite = (tx + tz) % 2 == 0
				local tile = Instance.new("Part")
				tile.Name = string.format("CheckerTile_%d_%d", tx, tz)
				tile.Size = Vector3.new(tileSize - 0.5, 0.15, tileSize - 0.5)
				tile.Position = Vector3.new(startX + tx * tileSize, topY + 0.1, startZ + tz * tileSize)
				tile.Color = isWhite and Color3.fromRGB(240, 240, 240) or Color3.fromRGB(30, 30, 30)
				tile.Material = Enum.Material.SmoothPlastic
				tile.Anchored = true
				tile.CanCollide = false
				tile.Parent = decorFolder
			end
		end
	end
	
	-- Victory arch (for finish line)
	if options.hasVictoryArch then
		local archHeight = 25
		local archWidth = sizeX * 0.6
		local archThickness = 3
		
		-- Left pillar
		local leftPillar = Instance.new("Part")
		leftPillar.Name = "VictoryArch_LeftPillar"
		leftPillar.Size = Vector3.new(archThickness, archHeight, archThickness)
		leftPillar.Position = Vector3.new(platformPos.X - archWidth/2, topY + archHeight/2, platformPos.Z)
		leftPillar.Color = accentColor
		leftPillar.Material = Enum.Material.Metal
		leftPillar.Anchored = true
		leftPillar.CanCollide = false
		leftPillar.Parent = decorFolder
		
		-- Right pillar
		local rightPillar = leftPillar:Clone()
		rightPillar.Name = "VictoryArch_RightPillar"
		rightPillar.Position = Vector3.new(platformPos.X + archWidth/2, topY + archHeight/2, platformPos.Z)
		rightPillar.Parent = decorFolder
		
		-- Top bar
		local topBar = Instance.new("Part")
		topBar.Name = "VictoryArch_TopBar"
		topBar.Size = Vector3.new(archWidth + archThickness, archThickness, archThickness)
		topBar.Position = Vector3.new(platformPos.X, topY + archHeight, platformPos.Z)
		topBar.Color = accentColor
		topBar.Material = Enum.Material.Neon
		topBar.Anchored = true
		topBar.CanCollide = false
		topBar.Parent = decorFolder
		
		-- "FINISH" text represented by glowing banner
		local banner = Instance.new("Part")
		banner.Name = "VictoryArch_Banner"
		banner.Size = Vector3.new(archWidth * 0.8, 6, 0.5)
		banner.Position = Vector3.new(platformPos.X, topY + archHeight - 8, platformPos.Z)
		banner.Color = accentColor
		banner.Material = Enum.Material.Neon
		banner.Transparency = 0.3
		banner.Anchored = true
		banner.CanCollide = false
		banner.Parent = decorFolder
	end
	
	return decorFolder
end

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         TRACK GEOMETRY TRACKING                             ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

-- Store track geometry for collision detection
local trackGeometry = {}  -- Module-level storage

local function clearTrackGeometry()
	trackGeometry = {}
end

-- Add a box to the track geometry (for platforms)
local function addTrackBox(centerX, centerZ, halfWidth, halfDepth)
	table.insert(trackGeometry, {
		type = "box",
		centerX = centerX,
		centerZ = centerZ,
		halfWidth = halfWidth + CONFIG.TrackCollisionBuffer,
		halfDepth = halfDepth + CONFIG.TrackCollisionBuffer,
	})
end

-- Add a line segment to the track geometry (for slides)
local function addTrackSegment(startX, startZ, endX, endZ, width)
	table.insert(trackGeometry, {
		type = "segment",
		startX = startX,
		startZ = startZ,
		endX = endX,
		endZ = endZ,
		halfWidth = width / 2 + CONFIG.TrackCollisionBuffer,
	})
end

-- Check if a building position (with size) would collide with track geometry
local function wouldCollideWithTrack(buildingX, buildingZ, buildingHalfWidth, buildingHalfDepth)
	for _, geo in ipairs(trackGeometry) do
		if geo.type == "box" then
			-- Box vs Box collision (AABB)
			local dx = math.abs(buildingX - geo.centerX)
			local dz = math.abs(buildingZ - geo.centerZ)
			local overlapX = (buildingHalfWidth + geo.halfWidth) - dx
			local overlapZ = (buildingHalfDepth + geo.halfDepth) - dz
			
			if overlapX > 0 and overlapZ > 0 then
				return true  -- Collision!
			end
			
		elseif geo.type == "segment" then
			-- Point to line segment distance check
			local segDirX = geo.endX - geo.startX
			local segDirZ = geo.endZ - geo.startZ
			local segLength = math.sqrt(segDirX * segDirX + segDirZ * segDirZ)
			
			if segLength > 0 then
				-- Normalize segment direction
				segDirX = segDirX / segLength
				segDirZ = segDirZ / segLength
				
				-- Vector from segment start to building
				local toPointX = buildingX - geo.startX
				local toPointZ = buildingZ - geo.startZ
				
				-- Project onto segment
				local projection = toPointX * segDirX + toPointZ * segDirZ
				projection = math.clamp(projection, 0, segLength)
				
				-- Closest point on segment
				local closestX = geo.startX + segDirX * projection
				local closestZ = geo.startZ + segDirZ * projection
				
				-- Distance from building center to closest point
				local distX = buildingX - closestX
				local distZ = buildingZ - closestZ
				local distance = math.sqrt(distX * distX + distZ * distZ)
				
				-- Check if within collision range
				local collisionRadius = math.max(buildingHalfWidth, buildingHalfDepth) + geo.halfWidth
				if distance < collisionRadius then
					return true  -- Collision!
				end
			end
		end
	end
	
	return false  -- No collision
end

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         SKY CITY BUILDING GENERATOR                         ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

-- Create a massive skyscraper that extends from the base up
local function createSkyscraper(xPos, zPos, topY, scaleMultiplier, parent)
	scaleMultiplier = scaleMultiplier or 1
	
	-- Random building dimensions (scaled)
	local baseWidth = math.random(CONFIG.BuildingWidthRange[1], CONFIG.BuildingWidthRange[2])
	local width = baseWidth * scaleMultiplier
	local depth = math.random(CONFIG.BuildingWidthRange[1], CONFIG.BuildingWidthRange[2]) * scaleMultiplier
	
	-- Building extends from CONFIG.BuildingBaseY up to topY (or higher)
	local extraHeight = math.random(0, 200) * scaleMultiplier  -- Some buildings poke above track level
	local buildingTopY = topY + extraHeight
	local height = buildingTopY - CONFIG.BuildingBaseY
	
	-- Random style
	local color = CONFIG.BuildingColors[math.random(1, #CONFIG.BuildingColors)]
	local material = CONFIG.BuildingMaterials[math.random(1, #CONFIG.BuildingMaterials)]
	
	-- Create building model
	local buildingModel = Instance.new("Model")
	buildingModel.Name = "Skyscraper"
	
	-- Main tower (extends from base to top)
	local tower = Instance.new("Part")
	tower.Name = "Tower"
	tower.Size = Vector3.new(width, height, depth)
	tower.Position = Vector3.new(xPos, CONFIG.BuildingBaseY + height / 2, zPos)
	tower.Color = color
	tower.Material = material
	tower.Anchored = true
	tower.CanCollide = false
	tower.CastShadow = true
	tower.Parent = buildingModel
	
	-- Add window strips (glowing horizontal bands)
	if math.random() < CONFIG.BuildingWindowChance then
		local windowSpacing = CONFIG.BuildingWindowSpacing * scaleMultiplier
		local windowRows = math.floor(height / windowSpacing)
		
		-- Limit windows on very tall buildings for performance
		local maxWindows = 30
		local windowStep = math.max(1, math.floor(windowRows / maxWindows))
		
		for row = windowStep, windowRows - 1, windowStep do
			local windowY = CONFIG.BuildingBaseY + row * windowSpacing
			local windowHeight = 4 * scaleMultiplier
			
			-- Front/back windows
			for _, zOffset in ipairs({depth/2 + 1, -depth/2 - 1}) do
				local window = Instance.new("Part")
				window.Name = "Window"
				window.Size = Vector3.new(width * 0.85, windowHeight, 2)
				window.Position = Vector3.new(xPos, windowY, zPos + zOffset)
				window.Color = CONFIG.BuildingWindowColor
				window.Material = Enum.Material.Neon
				window.Anchored = true
				window.CanCollide = false
				window.Transparency = 0.2
				window.Parent = buildingModel
			end
			
			-- Left/right windows
			for _, xOffset in ipairs({width/2 + 1, -width/2 - 1}) do
				local window = Instance.new("Part")
				window.Name = "Window"
				window.Size = Vector3.new(2, windowHeight, depth * 0.85)
				window.Position = Vector3.new(xPos + xOffset, windowY, zPos)
				window.Color = CONFIG.BuildingWindowColor
				window.Material = Enum.Material.Neon
				window.Anchored = true
				window.CanCollide = false
				window.Transparency = 0.2
				window.Parent = buildingModel
			end
		end
	end
	
	-- Rooftop structure
	local roofWidth = width * 0.4
	local roofHeight = math.random(20, 60) * scaleMultiplier
	local roof = Instance.new("Part")
	roof.Name = "Roof"
	roof.Size = Vector3.new(roofWidth, roofHeight, roofWidth)
	roof.Position = Vector3.new(xPos, buildingTopY + roofHeight / 2, zPos)
	roof.Color = color:Lerp(Color3.new(0, 0, 0), 0.3)
	roof.Material = material
	roof.Anchored = true
	roof.CanCollide = false
	roof.Parent = buildingModel
	
	-- Antenna/spire on tall buildings
	if math.random() < 0.5 then
		local antennaHeight = math.random(30, 100) * scaleMultiplier
		local antenna = Instance.new("Part")
		antenna.Name = "Antenna"
		antenna.Size = Vector3.new(4 * scaleMultiplier, antennaHeight, 4 * scaleMultiplier)
		antenna.Position = Vector3.new(xPos, buildingTopY + roofHeight + antennaHeight / 2, zPos)
		antenna.Color = Color3.fromRGB(80, 80, 90)
		antenna.Material = Enum.Material.Metal
		antenna.Anchored = true
		antenna.CanCollide = false
		antenna.Parent = buildingModel
		
		-- Warning light at top
		local light = Instance.new("Part")
		light.Name = "WarningLight"
		light.Size = Vector3.new(6, 6, 6) * scaleMultiplier
		light.Shape = Enum.PartType.Ball
		light.Position = antenna.Position + Vector3.new(0, antennaHeight / 2 + 3, 0)
		light.Color = Color3.fromRGB(255, 60, 60)
		light.Material = Enum.Material.Neon
		light.Anchored = true
		light.CanCollide = false
		light.Parent = buildingModel
	end
	
	buildingModel.Parent = parent
	return buildingModel
end

-- Generate sky city buildings along a slide path
local function generateBuildingsAlongPath(startPos, endPos, trackY, direction, parent)
	if not CONFIG.BuildingsEnabled then return end
	
	-- Get perpendicular direction for offsetting buildings to the sides
	local perpendicular
	if direction == "z+" or direction == "z-" then
		perpendicular = Vector3.new(1, 0, 0)
	else
		perpendicular = Vector3.new(0, 0, 1)
	end
	
	-- Main buildings
	local numBuildings = math.random(CONFIG.BuildingsPerSlide[1], CONFIG.BuildingsPerSlide[2])
	for i = 1, numBuildings do
		local t = math.random() * 100 / 100
		local pathPos = startPos:Lerp(endPos, t)
		
		local distance = math.random(CONFIG.BuildingDistanceFromTrack[1], CONFIG.BuildingDistanceFromTrack[2])
		local side = math.random() < 0.5 and 1 or -1
		local offset = perpendicular * distance * side
		
		createSkyscraper(
			pathPos.X + offset.X,
			pathPos.Z + offset.Z,
			trackY + math.random(-50, 150),
			1,
			parent
		)
	end
	
	-- Background buildings (farther, larger)
	if CONFIG.BackgroundBuildingsEnabled then
		local numBackground = math.random(CONFIG.BackgroundBuildingsPerSlide[1], CONFIG.BackgroundBuildingsPerSlide[2])
		for i = 1, numBackground do
			local t = math.random() * 100 / 100
			local pathPos = startPos:Lerp(endPos, t)
			
			local side = math.random() < 0.5 and 1 or -1
			local distance = math.random(CONFIG.BackgroundBuildingDistance[1], CONFIG.BackgroundBuildingDistance[2])
			local offset = perpendicular * distance * side
			
			local scale = CONFIG.BackgroundBuildingScale[1] + math.random() * (CONFIG.BackgroundBuildingScale[2] - CONFIG.BackgroundBuildingScale[1])
			
			createSkyscraper(
				pathPos.X + offset.X,
				pathPos.Z + offset.Z,
				trackY + math.random(-100, 300),
				scale,
				parent
			)
		end
	end
end

-- Remove buildings that intersect with track or each other
local function removeCollidingBuildings(hubFolder)
	local buildingsFolder = hubFolder:FindFirstChild("Buildings")
	if not buildingsFolder then
		-- Create buildings folder and move all skyscrapers into it
		buildingsFolder = Instance.new("Folder")
		buildingsFolder.Name = "Buildings"
		buildingsFolder.Parent = hubFolder
		
		for _, child in ipairs(hubFolder:GetChildren()) do
			if child:IsA("Model") and child.Name == "Skyscraper" then
				child.Parent = buildingsFolder
			end
		end
	end
	
	local buildings = buildingsFolder:GetChildren()
	local toRemove = {}
	
	-- Check each building against track geometry and other buildings
	for i, building in ipairs(buildings) do
		local tower = building:FindFirstChild("Tower")
		if tower then
			local pos = tower.Position
			local halfWidth = tower.Size.X / 2
			local halfDepth = tower.Size.Z / 2
			
			-- Check against track
			if wouldCollideWithTrack(pos.X, pos.Z, halfWidth, halfDepth) then
				toRemove[building] = true
			else
				-- Check against other buildings (only check buildings with higher index to avoid double-checking)
				for j = i + 1, #buildings do
					local otherBuilding = buildings[j]
					if not toRemove[otherBuilding] then
						local otherTower = otherBuilding:FindFirstChild("Tower")
						if otherTower then
							local otherPos = otherTower.Position
							local otherHalfWidth = otherTower.Size.X / 2
							local otherHalfDepth = otherTower.Size.Z / 2
							
							-- AABB collision check
							local dx = math.abs(pos.X - otherPos.X)
							local dz = math.abs(pos.Z - otherPos.Z)
							local overlapX = (halfWidth + otherHalfWidth) - dx
							local overlapZ = (halfDepth + otherHalfDepth) - dz
							
							if overlapX > 0 and overlapZ > 0 then
								-- Collision! Remove the smaller building
								if tower.Size.X * tower.Size.Z < otherTower.Size.X * otherTower.Size.Z then
									toRemove[building] = true
								else
									toRemove[otherBuilding] = true
								end
							end
						end
					end
				end
			end
		end
	end
	
	-- Remove colliding buildings
	local removedCount = 0
	for building, _ in pairs(toRemove) do
		building:Destroy()
		removedCount = removedCount + 1
	end
	
	local remainingCount = #buildingsFolder:GetChildren()
	print(string.format("[HubService] Removed %d colliding buildings, %d remaining", removedCount, remainingCount))
end

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         BLOCKADE GENERATOR                                  ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

-- Create a single blockade obstacle
local function createBlockade(position, size, rotation, slideColor, parent)
	local blockade = Instance.new("Model")
	blockade.Name = "Blockade"
	
	-- Main blockade part
	local mainPart = Instance.new("Part")
	mainPart.Name = "BlockadeMain"
	mainPart.Size = size
	mainPart.CFrame = CFrame.new(position) * rotation
	mainPart.Color = CONFIG.BlockadeColors[math.random(1, #CONFIG.BlockadeColors)]
	mainPart.Material = CONFIG.BlockadeMaterial
	mainPart.Anchored = true
	mainPart.Parent = blockade
	
	-- Add hazard stripes if enabled
	if CONFIG.BlockadeHazardStripes then
		local stripeTexture = Instance.new("Texture")
		stripeTexture.Name = "HazardStripes"
		stripeTexture.Texture = "rbxassetid://6372755229"  -- Hazard stripes texture
		stripeTexture.Face = Enum.NormalId.Front
		stripeTexture.StudsPerTileU = 4
		stripeTexture.StudsPerTileV = 4
		stripeTexture.Parent = mainPart
		
		local stripeTexture2 = stripeTexture:Clone()
		stripeTexture2.Face = Enum.NormalId.Back
		stripeTexture2.Parent = mainPart
	end
	
	-- Add warning light on top
	local light = Instance.new("Part")
	light.Name = "WarningLight"
	light.Shape = Enum.PartType.Ball
	light.Size = Vector3.new(4, 4, 4)
	light.Position = position + Vector3.new(0, size.Y / 2 + 2, 0)
	light.Color = Color3.fromRGB(255, 200, 0)
	light.Material = Enum.Material.Neon
	light.Anchored = true
	light.CanCollide = false
	light.Parent = blockade
	
	-- Add a base/support
	local base = Instance.new("Part")
	base.Name = "Base"
	base.Size = Vector3.new(size.X + 4, 3, size.Z + 4)
	base.CFrame = CFrame.new(position - Vector3.new(0, size.Y / 2 - 1, 0)) * rotation
	base.Color = Color3.fromRGB(50, 50, 55)
	base.Material = Enum.Material.Concrete
	base.Anchored = true
	base.Parent = blockade
	
	blockade.Parent = parent
	return blockade
end

-- Generate blockades along a slide
-- Returns the blockade positions so rails can avoid them (optional)
local function generateBlockades(params)
	if not CONFIG.BlockadesEnabled then return {} end
	
	local startPos = params.startPos
	local startY = params.startY
	local direction = params.direction
	local length = params.length
	local dropRate = params.dropRate
	local width = params.width
	local slideColor = params.color
	local parent = params.parent
	local getHeightFunc = params.getHeight  -- Function to get Y at distance
	local getWidthFunc = params.getWidth    -- Function to get width at distance
	
	-- Direction vectors
	local forwardVec, rightVec
	if direction == "z+" then
		forwardVec = Vector3.new(0, 0, 1)
		rightVec = Vector3.new(1, 0, 0)
	elseif direction == "z-" then
		forwardVec = Vector3.new(0, 0, -1)
		rightVec = Vector3.new(-1, 0, 0)
	elseif direction == "x+" then
		forwardVec = Vector3.new(1, 0, 0)
		rightVec = Vector3.new(0, 0, -1)
	elseif direction == "x-" then
		forwardVec = Vector3.new(-1, 0, 0)
		rightVec = Vector3.new(0, 0, 1)
	end
	
	-- Rotation to face along the slide
	local rotation = CFrame.Angles(0, math.atan2(forwardVec.X, forwardVec.Z), 0)
	
	-- Determine number of blockades
	local numBlockades = math.random(CONFIG.BlockadesPerSlide[1], CONFIG.BlockadesPerSlide[2])
	
	-- Generate random positions along the slide (with minimum spacing)
	local positions = {}
	local usableLength = length - CONFIG.BlockadeEdgeBuffer * 2  -- Avoid edges
	local attempts = 0
	local maxAttempts = 50
	
	while #positions < numBlockades and attempts < maxAttempts do
		attempts = attempts + 1
		
		-- Random distance along slide (avoiding edges)
		local distance = CONFIG.BlockadeEdgeBuffer + math.random() * usableLength
		
		-- Check spacing from existing blockades
		local tooClose = false
		for _, existingDist in ipairs(positions) do
			if math.abs(distance - existingDist) < CONFIG.BlockadeMinSpacing then
				tooClose = true
				break
			end
		end
		
		if not tooClose then
			table.insert(positions, distance)
		end
	end
	
	-- Sort positions by distance
	table.sort(positions)
	
	-- Get master blockades collection (or create local folder if not available)
	local blockadeFolder = HubService._collections and HubService._collections.Blockades
	if not blockadeFolder then
		blockadeFolder = Instance.new("Folder")
		blockadeFolder.Name = "Blockades"
		blockadeFolder.Parent = parent
	end
	
	for _, distance in ipairs(positions) do
		-- Get Y position using the slide's height function
		local y = getHeightFunc(distance) + CONFIG.SlideThickness / 2
		
		-- Get current width at this position
		local currentWidth = getWidthFunc(distance)
		
		-- Random blockade dimensions
		local blockadeHeight = math.random(CONFIG.BlockadeHeight[1], CONFIG.BlockadeHeight[2])
		local blockadeWidth = math.random(CONFIG.BlockadeWidth[1], math.min(CONFIG.BlockadeWidth[2], currentWidth - 20))
		blockadeWidth = math.max(blockadeWidth, CONFIG.BlockadeWidth[1])  -- Ensure minimum
		
		-- Random horizontal offset (can be left, center, or right of slide)
		local maxOffset = (currentWidth - blockadeWidth) / 2 - 5
		local horizontalOffset = math.random(-maxOffset, maxOffset)
		
		-- Calculate position
		local basePos = Vector3.new(startPos.X, 0, startPos.Z) + forwardVec * distance
		local pos = Vector3.new(
			basePos.X + rightVec.X * horizontalOffset,
			y + blockadeHeight / 2,
			basePos.Z + rightVec.Z * horizontalOffset
		)
		
		-- Create the blockade
		createBlockade(
			pos,
			Vector3.new(blockadeWidth, blockadeHeight, CONFIG.BlockadeThickness),
			rotation,
			slideColor,
			blockadeFolder
		)
	end
	
	print(string.format("[HubService] Generated %d blockades for slide", #positions))
	return positions
end

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         CRYSTAL GENERATOR                                   ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

-- Create particle burst effect when crystal is collected (using prefab)
local function createCrystalBurstEffect(position, color, collisionDirection)
	print(string.format("[HubService] Crystal collected at (%.1f, %.1f, %.1f) - spawning particles!", position.X, position.Y, position.Z))
	
	-- Get the ParticleAttachment prefab from ReplicatedStorage
	local prefabFolder = ReplicatedStorage:FindFirstChild("Prefabs")
	if not prefabFolder then
		warn("[HubService] Prefabs folder not found in ReplicatedStorage!")
		return
	end
	
	local particlePrefab = prefabFolder:FindFirstChild("ParticleAttachment")
	if not particlePrefab then
		warn("[HubService] ParticleAttachment prefab not found in Prefabs folder!")
		return
	end
	
	-- Create a temporary part to hold the attachment
	local effectPart = Instance.new("Part")
	effectPart.Name = "CrystalEffect"
	effectPart.Size = Vector3.new(0.5, 0.5, 0.5)
	effectPart.Position = position
	effectPart.Transparency = 1
	effectPart.Anchored = true
	effectPart.CanCollide = false
	effectPart.CanQuery = false
	effectPart.CanTouch = false
	effectPart.Parent = Workspace
	
	-- Clone the particle attachment prefab
	local attachment = particlePrefab:Clone()
	attachment.Parent = effectPart
	
	-- Orient attachment to face the collision direction
	attachment.CFrame = CFrame.lookAt(Vector3.zero, collisionDirection)
	
	-- Update particle colors to match the crystal
	for _, child in ipairs(attachment:GetDescendants()) do
		if child:IsA("ParticleEmitter") then
			-- Update color to crystal color
			local originalColor = child.Color
			if originalColor then
				child.Color = ColorSequence.new({
					ColorSequenceKeypoint.new(0, color),
					ColorSequenceKeypoint.new(0.5, Color3.new(1, 1, 1)),
					ColorSequenceKeypoint.new(1, color),
				})
			end
			
			-- Emit particles
			local emitCount = child:GetAttribute("EmitCount") or 25
			child:Emit(emitCount)
		end
	end
	
	-- Clean up after particles finish
	local cleanupTime = 5  -- Default cleanup time
	task.delay(cleanupTime, function()
		effectPart:Destroy()
	end)
end

-- Check if a part belongs to a player character
local function isPlayerCharacter(part)
	local character = part:FindFirstAncestorOfClass("Model")
	if character then
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			return true, character
		end
	end
	return false, nil
end

-- Create a single crystal
local function createCrystal(position, size, color, parent)
	local crystal = Instance.new("Part")
	crystal.Name = "Crystal"
	crystal.Shape = Enum.PartType.Ball
	crystal.Size = Vector3.new(size, size * 1.5, size)
	crystal.Position = position
	crystal.Color = color
	crystal.Material = CONFIG.CrystalMaterial
	crystal.Transparency = CONFIG.CrystalTransparency
	crystal.Anchored = true
	crystal.CanCollide = true   -- Need CanCollide for Touched to work reliably
	crystal.CanQuery = true
	crystal.CanTouch = true     -- Explicitly enable touch events
	
	-- Add a mesh to make it look like a crystal
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Scale = Vector3.new(0.6, 1.2, 0.6)
	mesh.Parent = crystal
	
	-- Random rotation for variety
	crystal.CFrame = CFrame.new(position) * CFrame.Angles(
		math.rad(math.random(-15, 15)),
		math.rad(math.random(0, 360)),
		math.rad(math.random(-15, 15))
	)
	
	-- Add a point light for glow effect
	local light = Instance.new("PointLight")
	light.Color = color
	light.Brightness = 0.5
	light.Range = size * 3
	light.Parent = crystal
	
	-- Track if already collected (prevent double collection)
	local collected = false
	
	-- Touch detection for collection
	crystal.Touched:Connect(function(otherPart)
		if collected then return end
		
		local isValid, model = isPlayerCharacter(otherPart)
		if isValid and model then
			collected = true
			
			-- Find the root part for position and velocity
			local rootPart = model:FindFirstChild("RootPart") or model:FindFirstChild("HumanoidRootPart")
			local collisionDir = Vector3.new(1, 0.5, 0)  -- Default direction
			local effectPosition = crystal.Position  -- Fallback to crystal position
			
			if rootPart then
				-- Use player position for the effect
				effectPosition = rootPart.Position
				
				-- Direction based on player's velocity (where they're going)
				local velocity = rootPart.AssemblyLinearVelocity
				
				if velocity.Magnitude > 1 then
					-- Particles scatter in the direction of movement
					collisionDir = velocity.Unit
				else
					-- If not moving, scatter upward and outward from crystal
					collisionDir = (rootPart.Position - crystal.Position).Unit
				end
				
				-- Add some upward bias for a satisfying arc
				collisionDir = (collisionDir + Vector3.new(0, 0.5, 0)).Unit
			end
			
			-- Store crystal color before destroying
			local crystalColor = crystal.Color
			
			-- Create burst effect at the player's position
			task.spawn(function()
				createCrystalBurstEffect(effectPosition, crystalColor, collisionDir)
			end)
			
			-- Destroy the crystal
			crystal:Destroy()
		end
	end)
	
	crystal.Parent = parent
	return crystal
end

-- Create a cluster of crystals
local function createCrystalCluster(centerPosition, baseSize, color, parent)
	local clusterFolder = Instance.new("Model")
	clusterFolder.Name = "CrystalCluster"
	
	local numCrystals = math.random(CONFIG.CrystalClusterSize[1], CONFIG.CrystalClusterSize[2])
	
	for i = 1, numCrystals do
		local offsetX = math.random(-baseSize, baseSize)
		local offsetZ = math.random(-baseSize, baseSize)
		local offsetY = math.random(0, baseSize / 2)
		
		local crystalSize = baseSize * (0.5 + math.random() * 0.8)
		local crystalPos = centerPosition + Vector3.new(offsetX, offsetY, offsetZ)
		
		-- Slightly vary the color for each crystal in cluster
		local hue, sat, val = color:ToHSV()
		local variedColor = Color3.fromHSV(
			(hue + math.random(-5, 5) / 100) % 1,
			math.clamp(sat + math.random(-10, 10) / 100, 0.3, 1),
			math.clamp(val + math.random(-10, 10) / 100, 0.5, 1)
		)
		
		createCrystal(crystalPos, crystalSize, variedColor, clusterFolder)
	end
	
	clusterFolder.Parent = parent
	return clusterFolder
end

-- Generate crystals scattered along a slide
local function generateCrystals(params)
	if not CONFIG.CrystalsEnabled then return end
	
	local startPos = params.startPos
	local startY = params.startY
	local direction = params.direction
	local length = params.length
	local width = params.width
	local parent = params.parent
	local getHeightFunc = params.getHeight
	local getWidthFunc = params.getWidth
	
	-- Direction vectors
	local forwardVec, rightVec
	if direction == "z+" then
		forwardVec = Vector3.new(0, 0, 1)
		rightVec = Vector3.new(1, 0, 0)
	elseif direction == "z-" then
		forwardVec = Vector3.new(0, 0, -1)
		rightVec = Vector3.new(-1, 0, 0)
	elseif direction == "x+" then
		forwardVec = Vector3.new(1, 0, 0)
		rightVec = Vector3.new(0, 0, -1)
	elseif direction == "x-" then
		forwardVec = Vector3.new(-1, 0, 0)
		rightVec = Vector3.new(0, 0, 1)
	end
	
	-- Get master crystals collection (or create local folder if not available)
	local crystalFolder = HubService._collections and HubService._collections.Crystals
	if not crystalFolder then
		crystalFolder = Instance.new("Folder")
		crystalFolder.Name = "Crystals"
		crystalFolder.Parent = parent
	end
	
	-- ═══════════════════════════════════════════════════════════════
	-- PATTERN-BASED CRYSTAL GENERATION
	-- ═══════════════════════════════════════════════════════════════
	
	local crystalsCreated = 0
	local spacing = CONFIG.CrystalSpacing
	local numRows = math.floor((length - 40) / spacing)  -- Leave buffer at start/end
	local pattern = CONFIG.CrystalPattern
	local jitter = CONFIG.CrystalJitter
	
	-- Helper to create a crystal at calculated position
	local function placeCrystal(distance, laneOffset)
		local y = getHeightFunc(distance) + CONFIG.SlideThickness / 2 + CONFIG.CrystalHeight
		local currentWidth = getWidthFunc(distance)
		local maxOffset = (currentWidth / 2) - 8
		
		-- Clamp lane offset to available width
		local horizontalOffset = math.clamp(laneOffset, -maxOffset, maxOffset)
		
		-- Add small random jitter for natural look
		horizontalOffset = horizontalOffset + math.random(-jitter, jitter)
		local distanceJitter = math.random(-jitter/2, jitter/2)
		
		local basePos = Vector3.new(startPos.X, 0, startPos.Z) + forwardVec * (distance + distanceJitter)
		local pos = Vector3.new(
			basePos.X + rightVec.X * horizontalOffset,
			y,
			basePos.Z + rightVec.Z * horizontalOffset
		)
		
		local size = math.random(CONFIG.CrystalSize[1] * 10, CONFIG.CrystalSize[2] * 10) / 10
		local color = CONFIG.CrystalColors[math.random(1, #CONFIG.CrystalColors)]
		
		if math.random() < CONFIG.CrystalClusterChance then
			createCrystalCluster(pos, size, color, crystalFolder)
			crystalsCreated = crystalsCreated + math.random(CONFIG.CrystalClusterSize[1], CONFIG.CrystalClusterSize[2])
		else
			createCrystal(pos, size, color, crystalFolder)
			crystalsCreated = crystalsCreated + 1
		end
	end
	
	-- ═══════════════════════════════════════════════════════════════
	-- ZIGZAG PATTERN - Alternates left/right each row
	-- ═══════════════════════════════════════════════════════════════
	if pattern == "zigzag" then
		local zigzagWidth = CONFIG.CrystalZigzagWidth
		for i = 0, numRows do
			local distance = 20 + (i * spacing)
			local currentWidth = getWidthFunc(distance)
			local maxOffset = (currentWidth / 2) * zigzagWidth
			
			-- Alternate between left and right
			local side = (i % 2 == 0) and -1 or 1
			local laneOffset = side * maxOffset
			
			placeCrystal(distance, laneOffset)
		end
		
	-- ═══════════════════════════════════════════════════════════════
	-- WAVE PATTERN - Smooth sine wave across the slide
	-- ═══════════════════════════════════════════════════════════════
	elseif pattern == "wave" then
		local amplitude = CONFIG.CrystalWaveAmplitude
		local frequency = CONFIG.CrystalWaveFrequency
		for i = 0, numRows do
			local distance = 20 + (i * spacing)
			local currentWidth = getWidthFunc(distance)
			local maxOffset = (currentWidth / 2) * amplitude
			
			-- Sine wave pattern
			local waveOffset = math.sin(distance * frequency) * maxOffset
			
			placeCrystal(distance, waveOffset)
		end
		
	-- ═══════════════════════════════════════════════════════════════
	-- LANES PATTERN - Multiple parallel lanes
	-- ═══════════════════════════════════════════════════════════════
	elseif pattern == "lanes" then
		local numLanes = CONFIG.CrystalLanes
		local laneSpacing = spacing * 1.5  -- More space between rows
		local laneRows = math.floor((length - 40) / laneSpacing)
		
		for i = 0, laneRows do
			local distance = 20 + (i * laneSpacing)
			local currentWidth = getWidthFunc(distance)
			local laneWidth = (currentWidth - 20) / numLanes
			
			-- Place crystal in each lane (with some randomness about which lanes get crystals)
			for lane = 1, numLanes do
				if math.random() > 0.3 then  -- 70% chance each lane gets a crystal
					local laneCenter = -currentWidth/2 + 10 + (lane - 0.5) * laneWidth
					placeCrystal(distance, laneCenter)
				end
			end
		end
		
	-- ═══════════════════════════════════════════════════════════════
	-- GRID PATTERN - Evenly spaced grid with row offset
	-- ═══════════════════════════════════════════════════════════════
	elseif pattern == "grid" then
		local numLanes = 3
		for i = 0, numRows do
			local distance = 20 + (i * spacing)
			local currentWidth = getWidthFunc(distance)
			local laneWidth = (currentWidth - 16) / numLanes
			
			-- Offset every other row by half a lane
			local rowOffset = 0
			if CONFIG.CrystalRowOffset and (i % 2 == 1) then
				rowOffset = laneWidth / 2
			end
			
			for lane = 1, numLanes do
				local laneCenter = -currentWidth/2 + 8 + (lane - 0.5) * laneWidth + rowOffset
				-- Skip if offset pushes us off the edge
				if math.abs(laneCenter) < (currentWidth/2 - 8) then
					placeCrystal(distance, laneCenter)
				end
			end
		end
		
	-- ═══════════════════════════════════════════════════════════════
	-- RANDOM PATTERN - Original random distribution
	-- ═══════════════════════════════════════════════════════════════
	else  -- "random" or fallback
		local numCrystals = math.random(20, 35)
		for i = 1, numCrystals do
			local distance = math.random(20, length - 20)
			local currentWidth = getWidthFunc(distance)
			local maxOffset = (currentWidth / 2) - 10
			local horizontalOffset = math.random(-maxOffset * 100, maxOffset * 100) / 100
			
			placeCrystal(distance, horizontalOffset)
		end
	end
	
	print(string.format("[HubService] Generated %d crystals (%s pattern) for slide", crystalsCreated, pattern))
end

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         KUDOS GATE GENERATOR                               ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

-- Helper: Get player from a part that touched something
local function getPlayerFromPart(part)
	local character = part:FindFirstAncestorOfClass("Model")
	if character then
		local player = Players:GetPlayerFromCharacter(character)
		if player then
			return player, character
		end
	end
	return nil, nil
end

-- Create a single kudos gate (enhanced visual design)
local function createKudosGate(position, rotation, gateIndex, kudosReward, color, parent)
	local gate = Instance.new("Model")
	gate.Name = string.format("KudosGate_%d", gateIndex)
	
	local halfWidth = CONFIG.GateWidth / 2
	local pillarRadius = CONFIG.GatePillarWidth / 2
	local gateHeight = CONFIG.GateHeight
	
	-- ═══════════════════════════════════════════════════════════════
	-- LEFT PILLAR (cylindrical with decorative elements)
	-- ═══════════════════════════════════════════════════════════════
	local leftPillarPos = position + rotation:VectorToWorldSpace(Vector3.new(-halfWidth, 0, 0))
	
	-- Main pillar cylinder
	local leftPillar = Instance.new("Part")
	leftPillar.Name = "LeftPillar"
	leftPillar.Shape = Enum.PartType.Cylinder
	leftPillar.Size = Vector3.new(gateHeight, CONFIG.GatePillarWidth, CONFIG.GatePillarWidth)
	leftPillar.CFrame = CFrame.new(leftPillarPos + Vector3.new(0, gateHeight/2, 0)) * CFrame.Angles(0, 0, math.pi/2)
	leftPillar.Color = color
	leftPillar.Material = Enum.Material.Metal
	leftPillar.Anchored = true
	leftPillar.CanCollide = false
	leftPillar.Parent = gate
	
	-- Left pillar base
	local leftBase = Instance.new("Part")
	leftBase.Name = "LeftBase"
	leftBase.Shape = Enum.PartType.Cylinder
	leftBase.Size = Vector3.new(2, CONFIG.GatePillarWidth * 1.5, CONFIG.GatePillarWidth * 1.5)
	leftBase.CFrame = CFrame.new(leftPillarPos + Vector3.new(0, 1, 0)) * CFrame.Angles(0, 0, math.pi/2)
	leftBase.Color = Color3.fromRGB(60, 60, 70)
	leftBase.Material = Enum.Material.Metal
	leftBase.Anchored = true
	leftBase.CanCollide = false
	leftBase.Parent = gate
	
	-- Left pillar top orb
	local leftOrb = Instance.new("Part")
	leftOrb.Name = "LeftOrb"
	leftOrb.Shape = Enum.PartType.Ball
	leftOrb.Size = Vector3.new(CONFIG.GatePillarWidth * 1.2, CONFIG.GatePillarWidth * 1.2, CONFIG.GatePillarWidth * 1.2)
	leftOrb.Position = leftPillarPos + Vector3.new(0, gateHeight + CONFIG.GatePillarWidth * 0.5, 0)
	leftOrb.Color = color
	leftOrb.Material = Enum.Material.Neon
	leftOrb.Anchored = true
	leftOrb.CanCollide = false
	leftOrb.Parent = gate
	
	-- Left point light
	local leftLight = Instance.new("PointLight")
	leftLight.Color = color
	leftLight.Brightness = 3
	leftLight.Range = 20
	leftLight.Parent = leftOrb
	
	-- ═══════════════════════════════════════════════════════════════
	-- RIGHT PILLAR (mirror of left)
	-- ═══════════════════════════════════════════════════════════════
	local rightPillarPos = position + rotation:VectorToWorldSpace(Vector3.new(halfWidth, 0, 0))
	
	local rightPillar = leftPillar:Clone()
	rightPillar.Name = "RightPillar"
	rightPillar.CFrame = CFrame.new(rightPillarPos + Vector3.new(0, gateHeight/2, 0)) * CFrame.Angles(0, 0, math.pi/2)
	rightPillar.Parent = gate
	
	local rightBase = leftBase:Clone()
	rightBase.Name = "RightBase"
	rightBase.CFrame = CFrame.new(rightPillarPos + Vector3.new(0, 1, 0)) * CFrame.Angles(0, 0, math.pi/2)
	rightBase.Parent = gate
	
	local rightOrb = leftOrb:Clone()
	rightOrb.Name = "RightOrb"
	rightOrb.Position = rightPillarPos + Vector3.new(0, gateHeight + CONFIG.GatePillarWidth * 0.5, 0)
	rightOrb.Parent = gate
	
	-- ═══════════════════════════════════════════════════════════════
	-- TOP ARCH (curved beam connecting pillars)
	-- ═══════════════════════════════════════════════════════════════
	local archSegments = 8
	local archWidth = CONFIG.GateWidth
	
	for i = 0, archSegments do
		local t = i / archSegments
		local angle = t * math.pi
		local x = math.cos(angle) * (archWidth / 2)
		local y = math.sin(angle) * 4 + gateHeight  -- 4 stud arch height
		
		local archPart = Instance.new("Part")
		archPart.Name = "Arch_" .. i
		archPart.Shape = Enum.PartType.Ball
		archPart.Size = Vector3.new(CONFIG.GatePillarWidth * 0.8, CONFIG.GatePillarWidth * 0.8, CONFIG.GatePillarWidth * 0.8)
		archPart.CFrame = CFrame.new(position + rotation:VectorToWorldSpace(Vector3.new(x, y, 0)))
		archPart.Color = color
		archPart.Material = Enum.Material.Neon
		archPart.Transparency = 0.2
		archPart.Anchored = true
		archPart.CanCollide = false
		archPart.Parent = gate
	end
	
	-- ═══════════════════════════════════════════════════════════════
	-- PORTAL RING (glowing ring in the center)
	-- ═══════════════════════════════════════════════════════════════
	local ringSegments = 16
	local ringRadius = math.min(halfWidth - 2, gateHeight / 2 - 2)
	local ringCenter = position + Vector3.new(0, gateHeight / 2 + 2, 0)
	
	for i = 1, ringSegments do
		local angle = (i / ringSegments) * math.pi * 2
		local nextAngle = ((i + 1) / ringSegments) * math.pi * 2
		
		local ringPart = Instance.new("Part")
		ringPart.Name = "Ring_" .. i
		ringPart.Shape = Enum.PartType.Cylinder
		ringPart.Size = Vector3.new(0.8, 2, 2)
		
		local x = math.cos(angle) * ringRadius
		local y = math.sin(angle) * ringRadius
		local partPos = ringCenter + rotation:VectorToWorldSpace(Vector3.new(x, y, 0))
		
		-- Orient cylinder tangent to the ring
		local tangentAngle = angle + math.pi / 2
		ringPart.CFrame = CFrame.new(partPos) * rotation * CFrame.Angles(0, tangentAngle, math.pi/2)
		ringPart.Color = CONFIG.GateGlowColor
		ringPart.Material = Enum.Material.Neon
		ringPart.Transparency = 0.3
		ringPart.Anchored = true
		ringPart.CanCollide = false
		ringPart.Parent = gate
	end
	
	-- Center glow (semi-transparent fill)
	local centerGlow = Instance.new("Part")
	centerGlow.Name = "CenterGlow"
	centerGlow.Shape = Enum.PartType.Cylinder
	centerGlow.Size = Vector3.new(1, ringRadius * 2 - 2, ringRadius * 2 - 2)
	centerGlow.CFrame = CFrame.new(ringCenter) * rotation * CFrame.Angles(0, math.pi/2, 0)
	centerGlow.Color = CONFIG.GateGlowColor
	centerGlow.Material = Enum.Material.Neon
	centerGlow.Transparency = 0.85
	centerGlow.Anchored = true
	centerGlow.CanCollide = false
	centerGlow.Parent = gate
	
	-- Store reference for animation
	gate:SetAttribute("CenterGlowName", "CenterGlow")
	
	-- ═══════════════════════════════════════════════════════════════
	-- TRIGGER ZONE
	-- ═══════════════════════════════════════════════════════════════
	local trigger = Instance.new("Part")
	trigger.Name = "GateTrigger"
	trigger.Size = Vector3.new(CONFIG.GateWidth, gateHeight, CONFIG.GatePillarWidth * 3)
	trigger.CFrame = CFrame.new(position + Vector3.new(0, gateHeight/2, 0)) * rotation
	trigger.Transparency = 1
	trigger.Anchored = true
	trigger.CanCollide = false
	trigger.CanQuery = true
	trigger.CanTouch = true
	trigger.Parent = gate
	
	-- ═══════════════════════════════════════════════════════════════
	-- KUDOS INDICATOR (floating above)
	-- ═══════════════════════════════════════════════════════════════
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "KudosIndicator"
	billboard.Size = UDim2.new(0, 120, 0, 50)
	billboard.StudsOffset = Vector3.new(0, gateHeight + 8, 0)
	billboard.Adornee = centerGlow
	billboard.AlwaysOnTop = false
	billboard.Parent = gate
	
	local kudosFrame = Instance.new("Frame")
	kudosFrame.Name = "KudosFrame"
	kudosFrame.Size = UDim2.new(1, 0, 1, 0)
	kudosFrame.BackgroundColor3 = Color3.fromRGB(20, 20, 30)
	kudosFrame.BackgroundTransparency = 0.4
	kudosFrame.BorderSizePixel = 0
	kudosFrame.Parent = billboard
	
	local kudosCorner = Instance.new("UICorner")
	kudosCorner.CornerRadius = UDim.new(0, 10)
	kudosCorner.Parent = kudosFrame
	
	local kudosStroke = Instance.new("UIStroke")
	kudosStroke.Color = color
	kudosStroke.Thickness = 2
	kudosStroke.Parent = kudosFrame
	
	local kudosLabel = Instance.new("TextLabel")
	kudosLabel.Name = "KudosLabel"
	kudosLabel.Size = UDim2.new(1, 0, 1, 0)
	kudosLabel.BackgroundTransparency = 1
	kudosLabel.Text = string.format("+%d ⭐", kudosReward)
	kudosLabel.TextColor3 = CONFIG.GateGlowColor
	kudosLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
	kudosLabel.TextStrokeTransparency = 0.3
	kudosLabel.Font = Enum.Font.GothamBold
	kudosLabel.TextScaled = true
	kudosLabel.Parent = kudosFrame
	
	-- ═══════════════════════════════════════════════════════════════
	-- ATTRIBUTES & COLLECTION TRACKING
	-- ═══════════════════════════════════════════════════════════════
	gate:SetAttribute("KudosReward", kudosReward)
	gate:SetAttribute("GateIndex", gateIndex)
	gate:SetAttribute("GateColor", color:ToHex())
	gate:SetAttribute("Collected", false)
	
	local collectedPlayers = {}
	
	-- Touch detection
	trigger.Touched:Connect(function(otherPart)
		local player, model = getPlayerFromPart(otherPart)
		if not player then return end
		
		-- Check if this player already collected this gate
		if collectedPlayers[player.UserId] then return end
		collectedPlayers[player.UserId] = true
		
		-- Award kudos
		HubService:AwardKudos(player, kudosReward)
		
		-- Mark gate as collected for this player (client can read this)
		gate:SetAttribute("LastCollectedBy", player.UserId)
		gate:SetAttribute("LastCollectedAt", tick())
		
		-- Fire remote event to notify client
		local gateCollectedEvent = ReplicatedStorage:FindFirstChild("GateCollectedEvent")
		if gateCollectedEvent then
			gateCollectedEvent:FireClient(player, gate, kudosReward)
		end
		
		-- Server-side visual feedback (visible to all)
		task.spawn(function()
			-- Flash all neon parts white
			local originalColors = {}
			for _, part in ipairs(gate:GetDescendants()) do
				if part:IsA("BasePart") and part.Material == Enum.Material.Neon then
					originalColors[part] = part.Color
					part.Color = Color3.new(1, 1, 1)
				end
			end
			
			-- Brighten center
			if centerGlow then
				centerGlow.Transparency = 0.5
			end
			
			task.wait(0.15)
			
			-- Restore colors
			for part, originalColor in pairs(originalColors) do
				if part and part.Parent then
					part.Color = originalColor
				end
			end
			
			if centerGlow and centerGlow.Parent then
				centerGlow.Transparency = 0.85
			end
		end)
		
		print(string.format("[HubService] Player %s collected gate %d for %d kudos!", 
			player.Name, gateIndex, kudosReward))
	end)
	
	gate.Parent = parent
	return gate
end

-- Generate kudos gates along a slide
local function generateGates(params)
	if not CONFIG.GatesEnabled then return end
	
	local startPos = params.startPos
	local startY = params.startY
	local direction = params.direction
	local length = params.length
	local parent = params.parent
	local getHeightFunc = params.getHeight
	local getWidthFunc = params.getWidth
	local slideIndex = params.slideIndex or 1
	
	-- Direction vectors for rotation
	local rotation
	if direction == "z+" then
		rotation = CFrame.Angles(0, 0, 0)
	elseif direction == "z-" then
		rotation = CFrame.Angles(0, math.pi, 0)
	elseif direction == "x+" then
		rotation = CFrame.Angles(0, -math.pi/2, 0)
	elseif direction == "x-" then
		rotation = CFrame.Angles(0, math.pi/2, 0)
	end
	
	local forwardVec
	if direction == "z+" then
		forwardVec = Vector3.new(0, 0, 1)
	elseif direction == "z-" then
		forwardVec = Vector3.new(0, 0, -1)
	elseif direction == "x+" then
		forwardVec = Vector3.new(1, 0, 0)
	elseif direction == "x-" then
		forwardVec = Vector3.new(-1, 0, 0)
	end
	
	-- Get master gates collection
	local gatesFolder = HubService._collections and HubService._collections.Gates
	if not gatesFolder then
		gatesFolder = Instance.new("Folder")
		gatesFolder.Name = "Gates"
		gatesFolder.Parent = parent
	end
	
	-- Determine number of gates for this slide
	local numGates = math.random(CONFIG.GatesPerSlide[1], CONFIG.GatesPerSlide[2])
	
	-- Generate evenly distributed gate positions with some randomness
	local positions = {}
	local segmentLength = length / (numGates + 1)
	
	for i = 1, numGates do
		local baseDistance = i * segmentLength
		local jitter = math.random(-20, 20)
		local distance = math.clamp(baseDistance + jitter, 40, length - 40)
		
		-- Ensure minimum spacing from previous gate
		if #positions > 0 then
			local lastPos = positions[#positions]
			if distance - lastPos < CONFIG.GateMinSpacing then
				distance = lastPos + CONFIG.GateMinSpacing
			end
		end
		
		if distance < length - 40 then
			table.insert(positions, distance)
		end
	end
	
	-- Create gates at calculated positions
	local gateIndex = (slideIndex - 1) * 10  -- Unique index per slide
	
	for i, distance in ipairs(positions) do
		gateIndex = gateIndex + 1
		
		-- Get Y position at this distance
		local y = getHeightFunc(distance) + CONFIG.SlideThickness / 2
		
		-- Calculate position
		local gatePos = Vector3.new(startPos.X, y, startPos.Z) + forwardVec * distance
		
		-- Random kudos reward
		local kudosReward = math.random(CONFIG.GateKudosReward[1], CONFIG.GateKudosReward[2])
		
		-- Pick color (rarer colors = higher rewards)
		local colorIndex = 1
		if kudosReward > 12 then
			colorIndex = 4  -- Pink (epic)
		elseif kudosReward > 10 then
			colorIndex = 3  -- Purple (rare)
		elseif kudosReward > 7 then
			colorIndex = 2  -- Cyan (uncommon)
		end
		local color = CONFIG.GateColors[colorIndex]
		
		createKudosGate(gatePos, rotation, gateIndex, kudosReward, color, gatesFolder)
	end
	
	print(string.format("[HubService] Generated %d kudos gates for slide %d", #positions, slideIndex))
end

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                    SPLINE-BASED TRACK GENERATOR                            ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

-- Generate control points for the track spline
local function generateTrackControlPoints(startPos, startHeight)
	local points = {}
	
	-- Use provided start position or default
	local platformEdgeZ = startPos and startPos.Z or (CONFIG.StartPlatformPosition.Z + CONFIG.StartPlatformSize.Z / 2)
	local platformCenterX = startPos and startPos.X or CONFIG.StartPlatformPosition.X
	
	-- IMPORTANT: Control points define segment CENTER positions
	-- Offset down by half thickness so segment TOP surfaces are at intended height
	local thicknessOffset = CONFIG.SlideThickness / 2
	local currentHeight = (startHeight or startPos and startPos.Y or CONFIG.TrackStartHeight) - thicknessOffset
	
	-- Point 0: At the platform edge (where track connects)
	-- This Y is where the segment CENTER will be, so segment TOP is at platform surface
	local currentPos = Vector3.new(platformCenterX, currentHeight, platformEdgeZ)
	table.insert(points, currentPos)
	
	-- Point 1: Initial straight section (no turn, slight drop)
	-- This ensures smooth connection to platform
	local initialDrop = 8  -- Gentle initial drop
	currentHeight = currentHeight - initialDrop
	currentPos = currentPos + Vector3.new(0, -initialDrop, CONFIG.TrackInitialStraightLength)
	table.insert(points, currentPos)
	
	-- Point 2: Continue straight with more drop (builds up speed before turns)
	currentHeight = currentHeight - 15
	currentPos = currentPos + Vector3.new(0, -15, CONFIG.TrackInitialDropDistance - CONFIG.TrackInitialStraightLength)
	table.insert(points, currentPos)
	
	local currentAngle = 0  -- Heading in radians (0 = +Z direction)
	local totalDistance = CONFIG.TrackInitialStraightLength + CONFIG.TrackInitialDropDistance
	local targetTurnRate = 0  -- Smooth turn rate target
	local currentTurnRate = 0  -- Actual turn rate (smoothly follows target)
	
	-- Generate remaining points with smooth curves and more turns
	for i = 4, CONFIG.TrackNumControlPoints do
		-- Vary section length slightly for natural feel
		local sectionLength = CONFIG.TrackMinSectionLength + 
			math.random() * (CONFIG.TrackMaxSectionLength - CONFIG.TrackMinSectionLength)
		
		-- Calculate turn intensity based on distance from start (gradual introduction)
		local turnIntensity = math.min(1.0, (totalDistance - CONFIG.TrackInitialDropDistance) / 150)
		
		-- Use smooth turns - change direction every 2 control points for snake-like curves
		if i % 2 == 0 then  -- Very frequent direction changes = more snake-like!
			local maxTurn = math.rad(CONFIG.TrackMaxTurnAngle) * turnIntensity
			targetTurnRate = (math.random() - 0.5) * 2 * maxTurn * 0.7  -- Stronger turn rate
		end
		
		-- Smoothly interpolate current turn rate toward target (gradual changes)
		currentTurnRate = currentTurnRate + (targetTurnRate - currentTurnRate) * 0.35  -- Faster response
		currentAngle = currentAngle + currentTurnRate
		
		-- Clamp total angle to prevent extreme turns, with smooth return to center
		if math.abs(currentAngle) > math.rad(90) then
			targetTurnRate = -math.sign(currentAngle) * math.rad(5)  -- Gently steer back
		end
		currentAngle = math.clamp(currentAngle, math.rad(-100), math.rad(100))
		
		-- Smooth height changes
		local heightChange
		if currentHeight <= CONFIG.TrackMinHeight + 50 then
			heightChange = math.random(CONFIG.TrackRisePerSection[1], CONFIG.TrackRisePerSection[2])
		elseif currentHeight >= CONFIG.TrackMaxHeight - 20 then
			heightChange = -math.random(CONFIG.TrackDropPerSection[1], CONFIG.TrackDropPerSection[2])
		elseif math.random() < CONFIG.TrackDropChance then
			heightChange = -math.random(CONFIG.TrackDropPerSection[1], CONFIG.TrackDropPerSection[2])
		else
			heightChange = math.random(CONFIG.TrackRisePerSection[1], CONFIG.TrackRisePerSection[2])
		end
		
		currentHeight = math.clamp(currentHeight + heightChange, CONFIG.TrackMinHeight, CONFIG.TrackMaxHeight)
		
		-- Calculate next position (X = sin, Z = cos for proper heading)
		local dx = math.sin(currentAngle) * sectionLength
		local dz = math.cos(currentAngle) * sectionLength
		currentPos = currentPos + Vector3.new(dx, 0, dz)
		currentPos = Vector3.new(currentPos.X, currentHeight, currentPos.Z)
		
		table.insert(points, currentPos)
		totalDistance = totalDistance + sectionLength
	end
	
	print(string.format("[HubService] Generated %d control points, total distance: %.1f studs", #points, totalDistance))
	return points
end

-- Create a track segment split into 3 parts across the width for smoother curves
local function createTrackSegment(startPos, endPos, width, color, bankAngle, parent)
	local direction = endPos - startPos
	local length = direction.Magnitude
	if length < 0.1 then return nil end
	
	local midPoint = (startPos + endPos) / 2
	local overlapLength = length * 1.15  -- 15% overlap for seamless connection
	
	-- Calculate base orientation vectors
	local forward = direction.Unit
	local worldUp = Vector3.new(0, 1, 0)
	local right = forward:Cross(worldUp)
	if right.Magnitude < 0.1 then
		right = Vector3.new(1, 0, 0)
	end
	right = right.Unit
	
	local numLanes = 3  -- Split width into 3 lanes
	local laneWidth = width / numLanes
	local segments = {}
	
	-- Create base CFrame at midpoint looking along direction
	local baseCF = CFrame.lookAt(midPoint, midPoint + forward, worldUp)
	
	-- Apply banking rotation (supports full 360° for loops and twists)
	if bankAngle ~= 0 then
		baseCF = baseCF * CFrame.Angles(0, 0, math.rad(bankAngle))
	end
	
	for lane = 0, numLanes - 1 do
		-- Calculate offset from center: -1, 0, +1 for lanes 0, 1, 2
		local laneOffset = (lane - (numLanes - 1) / 2) * laneWidth
		
		-- Offset in local space (X is right after banking is applied)
		local laneCenter = baseCF.Position + baseCF.RightVector * laneOffset
		
		local segment = Instance.new("Part")
		segment.Name = "TrackSegment"
		segment.Size = Vector3.new(laneWidth * 1.02, CONFIG.SlideThickness, overlapLength)
		segment.Color = color
		segment.Material = CONFIG.SlideMaterial
		segment.Anchored = true
		segment.CanCollide = true
		
		-- Use the banked orientation but at the lane position
		segment.CFrame = CFrame.new(laneCenter) * baseCF.Rotation
		segment.Parent = parent
		table.insert(segments, segment)
	end
	
	return segments
end

-- Create industrial safety rails along a portion of the spline
local function createSplineRails(spline, tStart, tEnd, width, color, parent)
	local railsFolder = parent
	local numSpikes = math.ceil((tEnd - tStart) * spline.Length / CONFIG.RailSegmentLength)
	numSpikes = math.max(numSpikes, 2)
	
	for i = 0, numSpikes do
		local t = tStart + (i / numSpikes) * (tEnd - tStart)
		local pos = spline:CalculatePositionRelativeToLength(math.clamp(t, 0, 1))
		local tangent = spline:CalculateDerivativeRelativeToLength(math.clamp(t, 0, 1))
		
		if tangent.Magnitude > 0.1 then
			local forward = tangent.Unit
			local right = forward:Cross(Vector3.new(0, 1, 0))
			if right.Magnitude < 0.1 then
				right = Vector3.new(1, 0, 0)
			end
			right = right.Unit
			
			local spikeOffset = width / 2 - CONFIG.RailThickness / 4  -- Slightly inward from edge
			local baseY = pos.Y + CONFIG.SlideThickness / 2
			
			local leftBasePos = Vector3.new(pos.X, baseY, pos.Z) - right * spikeOffset
			local rightBasePos = Vector3.new(pos.X, baseY, pos.Z) + right * spikeOffset
			
			-- Create LEFT spike (pointing up and outward)
			local leftSpike = Instance.new("WedgePart")
			leftSpike.Name = "LeftSpike_" .. i
			leftSpike.Size = Vector3.new(CONFIG.RailThickness, CONFIG.RailHeight, CONFIG.RailThickness * 1.5)
			leftSpike.Color = color
			leftSpike.Material = CONFIG.RailMaterial
			leftSpike.Anchored = true
			leftSpike.CanCollide = true
			-- Orient spike: point outward and up, aligned with track direction
			local leftCF = CFrame.lookAt(leftBasePos, leftBasePos + forward)
			leftSpike.CFrame = leftCF * CFrame.new(0, CONFIG.RailHeight / 2, 0) * CFrame.Angles(0, math.pi, 0)
			leftSpike.Parent = railsFolder
			
			-- Create RIGHT spike (pointing up and outward, mirrored)
			local rightSpike = Instance.new("WedgePart")
			rightSpike.Name = "RightSpike_" .. i
			rightSpike.Size = Vector3.new(CONFIG.RailThickness, CONFIG.RailHeight, CONFIG.RailThickness * 1.5)
			rightSpike.Color = color
			rightSpike.Material = CONFIG.RailMaterial
			rightSpike.Anchored = true
			rightSpike.CanCollide = true
			-- Orient spike: point outward and up, aligned with track direction (mirrored)
			local rightCF = CFrame.lookAt(rightBasePos, rightBasePos + forward)
			rightSpike.CFrame = rightCF * CFrame.new(0, CONFIG.RailHeight / 2, 0)
			rightSpike.Parent = railsFolder
		end
	end
end

-- Generate loop-de-loop points (vertical circle in the direction of travel)
local function generateLoopPoints(startPos, direction, radius, numSegments)
	local points = {}
	
	-- Get the horizontal forward direction
	local forward = Vector3.new(direction.X, 0, direction.Z)
	if forward.Magnitude < 0.1 then
		forward = Vector3.new(0, 0, 1)
	end
	forward = forward.Unit
	
	-- Loop is a vertical circle - we rotate in the plane defined by forward and up
	-- The loop center is at startPos + up * radius (so bottom of loop is at startPos)
	local loopCenter = startPos + Vector3.new(0, radius, 0)
	
	for i = 0, numSegments do
		local angle = (i / numSegments) * math.pi * 2  -- Full circle, starting from bottom
		-- Start at bottom (-90°), go up front, over top, down back, back to bottom
		local adjustedAngle = angle - math.pi / 2
		
		-- Position on the circle (in the vertical plane along forward direction)
		local y = math.sin(adjustedAngle) * radius
		local forwardOffset = math.cos(adjustedAngle) * radius
		
		local pos = loopCenter + forward * forwardOffset + Vector3.new(0, y, 0)
		
		-- The track surface should face "outward" from the loop center
		-- Bank angle makes the track surface perpendicular to the radius
		local bankAngle = math.deg(adjustedAngle + math.pi / 2)
		
		table.insert(points, {
			position = pos,
			direction = forward,
			bankAngle = bankAngle,
		})
	end
	
	return points
end

-- Generate twist/barrel roll points (360° rotation while moving forward)
local function generateTwistPoints(startPos, direction, length, numSegments)
	local points = {}
	
	local forward = direction.Unit
	
	for i = 0, numSegments do
		local t = i / numSegments
		local pos = startPos + forward * (t * length)
		local bankAngle = t * 360  -- Full 360° rotation
		
		table.insert(points, {
			position = pos,
			direction = forward,
			bankAngle = bankAngle,
		})
	end
	
	return points
end

-- Generate the entire spline-based track
-- Catmull-Rom interpolation between 4 points
local function catmullRomInterpolate(p0, p1, p2, p3, t)
	local t2 = t * t
	local t3 = t2 * t
	
	return 0.5 * (
		(2 * p1) +
		(-p0 + p2) * t +
		(2 * p0 - 5 * p1 + 4 * p2 - p3) * t2 +
		(-p0 + 3 * p1 - 3 * p2 + p3) * t3
	)
end

-- Generate smooth path from control points using Catmull-Rom interpolation
local function generateSmoothPath(controlPoints, subdivisions)
	local path = {}
	
	-- Need at least 4 points for Catmull-Rom
	if #controlPoints < 4 then
		return controlPoints
	end
	
	-- Create phantom points at the start and end for full interpolation
	-- Phantom start: extrapolate backward from first two points
	local phantomStart = controlPoints[1] - (controlPoints[2] - controlPoints[1])
	-- Phantom end: extrapolate forward from last two points
	local phantomEnd = controlPoints[#controlPoints] + (controlPoints[#controlPoints] - controlPoints[#controlPoints - 1])
	
	-- Build extended control points array with phantoms
	local extendedPoints = {phantomStart}
	for _, p in ipairs(controlPoints) do
		table.insert(extendedPoints, p)
	end
	table.insert(extendedPoints, phantomEnd)
	
	-- Now interpolate all segments (we have phantom points at both ends)
	-- extendedPoints: [phantom, p1, p2, ..., pN, phantom]
	-- We want to interpolate from p1 to pN
	for i = 2, #extendedPoints - 2 do
		local p0 = extendedPoints[i - 1]
		local p1 = extendedPoints[i]
		local p2 = extendedPoints[i + 1]
		local p3 = extendedPoints[i + 2]
		
		-- Subdivide this segment
		for j = 0, subdivisions - 1 do
			local t = j / subdivisions
			local pos = catmullRomInterpolate(p0, p1, p2, p3, t)
			table.insert(path, pos)
		end
	end
	
	-- Add the final actual control point
	table.insert(path, controlPoints[#controlPoints])
	
	return path
end

local function generateSplineTrack(startPos, parent)
	print("[HubService] Generating spline-based track...")
	print(string.format("[HubService] Start position: (%.1f, %.1f, %.1f)", startPos.X, startPos.Y, startPos.Z))
	
	-- Generate control points starting from the platform edge
	local controlPoints = generateTrackControlPoints(startPos, startPos.Y)
	print(string.format("[HubService] Generated %d control points", #controlPoints))
	
	-- Need at least 4 points
	if #controlPoints < 4 then
		warn("[HubService] Not enough control points!")
		return nil
	end
	
	-- Create track folder
	local trackFolder = Instance.new("Folder")
	trackFolder.Name = "SplineTrack"
	trackFolder.Parent = parent
	
	-- Generate smooth path with more subdivisions for smoother curves
	local subdivisionsPerSegment = 25  -- More points = smoother curves
	local smoothPath = generateSmoothPath(controlPoints, subdivisionsPerSegment)
	print(string.format("[HubService] Generated smooth path with %d points", #smoothPath))
	
	-- Track state for banking calculation
	local prevTangent = nil
	local currentBankAngle = 0
	local segmentCount = 0
	
	-- Use consistent color for seamless appearance
	local trackColor = CONFIG.SlideColor
	
	-- ═══════════════════════════════════════════════════════════════════════
	-- CREATE RAMP CONNECTOR (bridges platform to track - NO OVERLAP)
	-- ═══════════════════════════════════════════════════════════════════════
	-- Ramp starts exactly at platform front edge and extends forward to track
	-- NO overlap with platform - clean separation
	local rampLength = 25  -- Total ramp length
	
	-- Track segment centers are offset down by half thickness
	local platformTopY = startPos.Y  -- Platform TOP surface
	local trackCenterY = platformTopY - CONFIG.SlideThickness / 2  -- Where track segment centers are
	
	-- Direction from platform into track (horizontal)
	local connectorDir = Vector3.new(0, 0, 1)  -- +Z direction
	if #smoothPath >= 2 then
		local dir = (smoothPath[2] - smoothPath[1])
		connectorDir = Vector3.new(dir.X, 0, dir.Z)
		if connectorDir.Magnitude > 0.1 then
			connectorDir = connectorDir.Unit
		else
			connectorDir = Vector3.new(0, 0, 1)
		end
	end
	
	-- Ramp starts at platform edge (startPos.Z) and extends forward
	-- Ramp center is at startPos.Z + rampLength/2
	local rampCenterZ = startPos.Z + rampLength / 2
	local rampCenterPos = Vector3.new(startPos.X, trackCenterY, rampCenterZ)
	
	-- Create the ramp segments (3 lanes)
	local numLanes = 3
	local laneWidth = CONFIG.SlideWidth / numLanes
	local baseCF = CFrame.lookAt(rampCenterPos, rampCenterPos + connectorDir)
	
	for lane = 0, numLanes - 1 do
		local laneOffset = (lane - (numLanes - 1) / 2) * laneWidth
		local laneCenter = rampCenterPos + baseCF.RightVector * laneOffset
		
		local ramp = Instance.new("Part")
		ramp.Name = "TrackRamp_" .. lane
		ramp.Size = Vector3.new(laneWidth * 1.02, CONFIG.SlideThickness, rampLength)
		ramp.Color = trackColor
		ramp.Material = CONFIG.SlideMaterial
		ramp.Anchored = true
		ramp.CanCollide = true
		ramp.CFrame = CFrame.new(laneCenter) * baseCF.Rotation
		ramp.Parent = trackFolder
	end
	print("[HubService] Created platform-to-track ramp connector (no overlap)")
	local twistColor = Color3.fromRGB(100, 200, 255)  -- Cyan for twists
	
	-- Calculate total path length first
	local totalPathLength = 0
	for idx = 1, #smoothPath - 1 do
		totalPathLength = totalPathLength + (smoothPath[idx + 1] - smoothPath[idx]).Magnitude
	end
	
	-- Decide if we have a twist (ONE per track maximum)
	local hasTwist = CONFIG.TwistsEnabled and math.random() < CONFIG.TwistChance
	local twistStartDistance = 0
	local twistEndDistance = 0
	
	if hasTwist then
		-- Place twist between 35-55% of the track
		twistStartDistance = totalPathLength * (0.35 + math.random() * 0.2)
		twistEndDistance = twistStartDistance + CONFIG.TwistLength
		print(string.format("[HubService] TWIST from distance %.0f to %.0f (%.0f%% of track)", 
			twistStartDistance, twistEndDistance, (twistStartDistance/totalPathLength)*100))
	end
	
	-- Create track segments
	local distanceTraveled = 0
	
	for i = 1, #smoothPath - 1 do
		local segStart = smoothPath[i]
		local segEnd = smoothPath[i + 1]
		local direction = (segEnd - segStart)
		local segLength = direction.Magnitude
		
		if segLength > 0.1 then
			local tangent = direction.Unit
			
			-- Calculate normal banking for turns
			if prevTangent and CONFIG.TrackBankingEnabled then
				local turnRate = prevTangent:Cross(tangent).Y
				local targetBank = math.clamp(turnRate * 80, -CONFIG.TrackMaxBankAngle, CONFIG.TrackMaxBankAngle)
				currentBankAngle = currentBankAngle + (targetBank - currentBankAngle) * CONFIG.TrackBankSmoothing
			end
			prevTangent = tangent
			
			-- Check if we're in the twist section
			local inTwist = hasTwist and distanceTraveled >= twistStartDistance and distanceTraveled < twistEndDistance
			local bankAngle = currentBankAngle
			local color = trackColor
			
			if inTwist then
				-- Calculate twist rotation - go to max and back (smooth wave)
				local twistProgress = (distanceTraveled - twistStartDistance) / CONFIG.TwistLength
				-- Use sine wave: 0° -> max -> 0° (smooth in and out)
				local twistRotation = math.sin(twistProgress * math.pi) * CONFIG.TwistMaxRotation
				bankAngle = currentBankAngle + twistRotation
				color = twistColor
			end
			
			createTrackSegment(segStart, segEnd, CONFIG.SlideWidth, color, bankAngle, trackFolder)
			segmentCount = segmentCount + 1
			distanceTraveled = distanceTraveled + segLength
		end
	end
	
	print(string.format("[HubService] Created %d track segments", segmentCount))
	
	-- Calculate total path length for placing objects
	local totalPathLength = 0
	for i = 1, #smoothPath - 1 do
		totalPathLength = totalPathLength + (smoothPath[i + 1] - smoothPath[i]).Magnitude
	end
	print(string.format("[HubService] Total path length: %.1f studs", totalPathLength))
	
	-- Helper function to get position and direction at a distance along the path
	local function getPositionAtDistance(distance)
		local traveled = 0
		for i = 1, #smoothPath - 1 do
			local segmentLength = (smoothPath[i + 1] - smoothPath[i]).Magnitude
			if traveled + segmentLength >= distance then
				local t = (distance - traveled) / segmentLength
				local pos = smoothPath[i]:Lerp(smoothPath[i + 1], t)
				local dir = (smoothPath[i + 1] - smoothPath[i]).Unit
				return pos, dir
			end
			traveled = traveled + segmentLength
		end
		-- Return end of path
		return smoothPath[#smoothPath], (smoothPath[#smoothPath] - smoothPath[#smoothPath - 1]).Unit
	end
	
	-- Create safety rails along the track (Industrial style) + smooth invisible colliders
	print("[HubService] Creating industrial safety rails with smooth colliders...")
	local railsFolder = HubService._collections and HubService._collections.Rails or trackFolder
	local spikeIndex = 0
	
	-- Calculate spike spacing based on config
	local spikeSpacing = math.ceil(#smoothPath / (totalPathLength / CONFIG.RailSegmentLength))
	spikeSpacing = math.max(spikeSpacing, 2)  -- At least every 2 points
	
	-- Track positions for smooth colliders
	local prevLeftPos, prevRightPos = nil, nil
	
	for i = 1, #smoothPath - 1, spikeSpacing do
		local pos = smoothPath[i]
		local nextPos = smoothPath[math.min(i + 1, #smoothPath)]
		local dir = (nextPos - pos)
		if dir.Magnitude > 0.1 then
			dir = dir.Unit
			local right = dir:Cross(Vector3.new(0, 1, 0))
			if right.Magnitude < 0.1 then right = Vector3.new(1, 0, 0) end
			right = right.Unit
			
			local railOffset = CONFIG.SlideWidth / 2 - CONFIG.RailThickness / 4  -- Slightly inward
			local railBaseY = pos.Y + CONFIG.SlideThickness / 2
			local leftBasePos = Vector3.new(pos.X, railBaseY, pos.Z) - right * railOffset
			local rightBasePos = Vector3.new(pos.X, railBaseY, pos.Z) + right * railOffset
			
			-- Create rails based on RailShape config
			if CONFIG.RailShape == "Bar" then
				-- INDUSTRIAL SAFETY BARS (rectangular posts)
				local barLength = CONFIG.RailThickness * 2
				
				-- LEFT BAR (visual only - no collision)
				local leftBar = Instance.new("Part")
				leftBar.Name = "LeftBar_" .. spikeIndex
				leftBar.Size = Vector3.new(CONFIG.RailThickness, CONFIG.RailHeight, barLength)
				leftBar.Color = CONFIG.RailColor
				leftBar.Material = CONFIG.RailMaterial
				leftBar.Anchored = true
				leftBar.CanCollide = false
				local leftCF = CFrame.lookAt(leftBasePos, leftBasePos + dir)
				leftBar.CFrame = leftCF * CFrame.new(0, CONFIG.RailHeight / 2, 0)
				leftBar.Parent = railsFolder
				
				-- RIGHT BAR (visual only - no collision)
				local rightBar = Instance.new("Part")
				rightBar.Name = "RightBar_" .. spikeIndex
				rightBar.Size = Vector3.new(CONFIG.RailThickness, CONFIG.RailHeight, barLength)
				rightBar.Color = CONFIG.RailColor
				rightBar.Material = CONFIG.RailMaterial
				rightBar.Anchored = true
				rightBar.CanCollide = false
				local rightCF = CFrame.lookAt(rightBasePos, rightBasePos + dir)
				rightBar.CFrame = rightCF * CFrame.new(0, CONFIG.RailHeight / 2, 0)
				rightBar.Parent = railsFolder
				
				-- Add black/dark stripes for hazard look (every other bar)
				if spikeIndex % 2 == 0 then
					-- Dark stripe on left
					local leftStripe = Instance.new("Part")
					leftStripe.Name = "LeftStripe_" .. spikeIndex
					leftStripe.Size = Vector3.new(CONFIG.RailThickness + 0.1, CONFIG.RailHeight * 0.3, barLength + 0.1)
					leftStripe.Color = Color3.fromRGB(30, 30, 35)
					leftStripe.Material = Enum.Material.SmoothPlastic
					leftStripe.Anchored = true
					leftStripe.CanCollide = false
					leftStripe.CFrame = leftCF * CFrame.new(0, CONFIG.RailHeight * 0.35, 0)
					leftStripe.Parent = railsFolder
					
					-- Dark stripe on right
					local rightStripe = Instance.new("Part")
					rightStripe.Name = "RightStripe_" .. spikeIndex
					rightStripe.Size = Vector3.new(CONFIG.RailThickness + 0.1, CONFIG.RailHeight * 0.3, barLength + 0.1)
					rightStripe.Color = Color3.fromRGB(30, 30, 35)
					rightStripe.Material = Enum.Material.SmoothPlastic
					rightStripe.Anchored = true
					rightStripe.CanCollide = false
					rightStripe.CFrame = rightCF * CFrame.new(0, CONFIG.RailHeight * 0.35, 0)
					rightStripe.Parent = railsFolder
				end
			else
				-- SPIKES (wedge parts - original style)
				local leftSpike = Instance.new("WedgePart")
				leftSpike.Name = "LeftSpike_" .. spikeIndex
				leftSpike.Size = Vector3.new(CONFIG.RailThickness, CONFIG.RailHeight, CONFIG.RailThickness * 1.5)
				leftSpike.Color = CONFIG.RailColor
				leftSpike.Material = CONFIG.RailMaterial
				leftSpike.Anchored = true
				leftSpike.CanCollide = false
				local leftCF = CFrame.lookAt(leftBasePos, leftBasePos + dir)
				leftSpike.CFrame = leftCF * CFrame.new(0, CONFIG.RailHeight / 2, 0) * CFrame.Angles(0, math.pi, 0)
				leftSpike.Parent = railsFolder
				
				local rightSpike = Instance.new("WedgePart")
				rightSpike.Name = "RightSpike_" .. spikeIndex
				rightSpike.Size = Vector3.new(CONFIG.RailThickness, CONFIG.RailHeight, CONFIG.RailThickness * 1.5)
				rightSpike.Color = CONFIG.RailColor
				rightSpike.Material = CONFIG.RailMaterial
				rightSpike.Anchored = true
				rightSpike.CanCollide = false
				local rightCF = CFrame.lookAt(rightBasePos, rightBasePos + dir)
				rightSpike.CFrame = rightCF * CFrame.new(0, CONFIG.RailHeight / 2, 0)
				rightSpike.Parent = railsFolder
			end
			
			-- SMOOTH COLLIDERS (invisible walls for collision)
			local colliderY = railBaseY + CONFIG.RailHeight / 2
			local leftColliderPos = Vector3.new(pos.X, colliderY, pos.Z) - right * railOffset
			local rightColliderPos = Vector3.new(pos.X, colliderY, pos.Z) + right * railOffset
			
			if prevLeftPos then
				-- Left smooth collider segment
				local leftDir = (leftColliderPos - prevLeftPos)
				local leftLen = leftDir.Magnitude
				if leftLen > 0.5 then
					local leftMid = (prevLeftPos + leftColliderPos) / 2
					local leftCollider = Instance.new("Part")
					leftCollider.Name = "LeftCollider_" .. spikeIndex
					leftCollider.Size = Vector3.new(CONFIG.RailThickness, CONFIG.RailHeight, leftLen + 0.5)
					leftCollider.Transparency = 0.9  -- Nearly invisible
					leftCollider.Anchored = true
					leftCollider.CanCollide = true
					leftCollider.CFrame = CFrame.lookAt(leftMid, leftMid + leftDir.Unit)
					leftCollider.Parent = railsFolder
				end
				
				-- Right smooth collider segment
				local rightDir = (rightColliderPos - prevRightPos)
				local rightLen = rightDir.Magnitude
				if rightLen > 0.5 then
					local rightMid = (prevRightPos + rightColliderPos) / 2
					local rightCollider = Instance.new("Part")
					rightCollider.Name = "RightCollider_" .. spikeIndex
					rightCollider.Size = Vector3.new(CONFIG.RailThickness, CONFIG.RailHeight, rightLen + 0.5)
					rightCollider.Transparency = 0.9  -- Nearly invisible
					rightCollider.Anchored = true
					rightCollider.CanCollide = true
					rightCollider.CFrame = CFrame.lookAt(rightMid, rightMid + rightDir.Unit)
					rightCollider.Parent = railsFolder
				end
			end
			
			prevLeftPos = leftColliderPos
			prevRightPos = rightColliderPos
			spikeIndex = spikeIndex + 1
		end
	end
	print(string.format("[HubService] Created %d safety rails + smooth colliders on each side", spikeIndex))
	
	-- Create light spires along the track for visibility
	if CONFIG.RailSpiresEnabled then
		print("[HubService] Creating warning spires with blinking lights...")
		local spireIndex = 0
		local spireFolder = Instance.new("Folder")
		spireFolder.Name = "WarningSpires"
		spireFolder.Parent = trackFolder
		
		local blinkingLights = {}  -- Track lights for blinking animation
		
		for i = 1, #smoothPath - 1, math.max(1, math.floor(CONFIG.RailSpireSpacing / (totalPathLength / #smoothPath))) do
			local pos = smoothPath[i]
			local nextPos = smoothPath[math.min(i + 1, #smoothPath)]
			local dir = (nextPos - pos)
			
			if dir.Magnitude > 0.1 then
				dir = dir.Unit
				local right = dir:Cross(Vector3.new(0, 1, 0))
				if right.Magnitude < 0.1 then right = Vector3.new(1, 0, 0) end
				right = right.Unit
				
				local railOffset = CONFIG.SlideWidth / 2
				local railBaseY = pos.Y + CONFIG.SlideThickness / 2
				
				-- Create spire on left side
				local leftBasePos = Vector3.new(pos.X, railBaseY, pos.Z) - right * railOffset
				
				-- Spire pole
				local leftPole = Instance.new("Part")
				leftPole.Name = "LeftSpire_" .. spireIndex
				leftPole.Size = Vector3.new(CONFIG.RailSpireThickness, CONFIG.RailSpireHeight, CONFIG.RailSpireThickness)
				leftPole.Color = CONFIG.RailSpireColor
				leftPole.Material = Enum.Material.Metal
				leftPole.Anchored = true
				leftPole.CanCollide = false
				leftPole.CastShadow = false
				leftPole.Position = leftBasePos + Vector3.new(0, CONFIG.RailSpireHeight / 2, 0)
				leftPole.Parent = spireFolder
				
				-- Light orb on top
				local leftLight = Instance.new("Part")
				leftLight.Name = "LeftLight_" .. spireIndex
				leftLight.Shape = Enum.PartType.Ball
				leftLight.Size = Vector3.new(CONFIG.RailSpireLightSize, CONFIG.RailSpireLightSize, CONFIG.RailSpireLightSize)
				leftLight.Color = CONFIG.RailSpireLightColor
				leftLight.Material = Enum.Material.Neon
				leftLight.Anchored = true
				leftLight.CanCollide = false
				leftLight.CastShadow = false
				leftLight.Position = leftBasePos + Vector3.new(0, CONFIG.RailSpireHeight + CONFIG.RailSpireLightSize / 2, 0)
				leftLight.Parent = spireFolder
				
				-- Point light
				local leftPointLight = Instance.new("PointLight")
				leftPointLight.Color = CONFIG.RailSpireLightColor
				leftPointLight.Range = CONFIG.RailSpireLightRange
				leftPointLight.Brightness = CONFIG.RailSpireLightBrightness
				leftPointLight.Parent = leftLight
				
				table.insert(blinkingLights, { light = leftPointLight, orb = leftLight })
				
				-- Create spire on right side
				local rightBasePos = Vector3.new(pos.X, railBaseY, pos.Z) + right * railOffset
				
				-- Spire pole
				local rightPole = Instance.new("Part")
				rightPole.Name = "RightSpire_" .. spireIndex
				rightPole.Size = Vector3.new(CONFIG.RailSpireThickness, CONFIG.RailSpireHeight, CONFIG.RailSpireThickness)
				rightPole.Color = CONFIG.RailSpireColor
				rightPole.Material = Enum.Material.Metal
				rightPole.Anchored = true
				rightPole.CanCollide = false
				rightPole.CastShadow = false
				rightPole.Position = rightBasePos + Vector3.new(0, CONFIG.RailSpireHeight / 2, 0)
				rightPole.Parent = spireFolder
				
				-- Light orb on top
				local rightLight = Instance.new("Part")
				rightLight.Name = "RightLight_" .. spireIndex
				rightLight.Shape = Enum.PartType.Ball
				rightLight.Size = Vector3.new(CONFIG.RailSpireLightSize, CONFIG.RailSpireLightSize, CONFIG.RailSpireLightSize)
				rightLight.Color = CONFIG.RailSpireLightColor
				rightLight.Material = Enum.Material.Neon
				rightLight.Anchored = true
				rightLight.CanCollide = false
				rightLight.CastShadow = false
				rightLight.Position = rightBasePos + Vector3.new(0, CONFIG.RailSpireHeight + CONFIG.RailSpireLightSize / 2, 0)
				rightLight.Parent = spireFolder
				
				-- Point light
				local rightPointLight = Instance.new("PointLight")
				rightPointLight.Color = CONFIG.RailSpireLightColor
				rightPointLight.Range = CONFIG.RailSpireLightRange
				rightPointLight.Brightness = CONFIG.RailSpireLightBrightness
				rightPointLight.Parent = rightLight
				
				table.insert(blinkingLights, { light = rightPointLight, orb = rightLight })
				
				spireIndex = spireIndex + 1
			end
		end
		
		print(string.format("[HubService] Created %d warning spires with lights", spireIndex))
		
		-- Start blinking animation for all lights
		task.spawn(function()
			local blinkInterval = 1 / CONFIG.RailSpireBlinkSpeed
			local isOn = true
			
			while spireFolder and spireFolder.Parent do
				task.wait(blinkInterval / 2)
				isOn = not isOn
				
				for _, lightData in ipairs(blinkingLights) do
					if lightData.light and lightData.light.Parent then
						lightData.light.Enabled = isOn
					end
					if lightData.orb and lightData.orb.Parent then
						lightData.orb.Transparency = isOn and 0 or 0.7
					end
				end
			end
		end)
	end
	
	-- Create crystals along the track
	if CONFIG.CrystalsEnabled then
		print("[HubService] Placing crystals...")
		local crystalFolder = HubService._collections and HubService._collections.Crystals or trackFolder
		local numCrystals = math.floor(totalPathLength / CONFIG.CrystalSpacing)
		
		for i = 1, numCrystals do
			local distance = (i / numCrystals) * totalPathLength * 0.95 + totalPathLength * 0.02
			local pos, dir = getPositionAtDistance(distance)
			
			if dir.Magnitude > 0.1 then
				local right = dir:Cross(Vector3.new(0, 1, 0))
				if right.Magnitude < 0.1 then right = Vector3.new(1, 0, 0) end
				right = right.Unit
				
				-- Pattern-based positioning
				local laneOffset = 0
				if CONFIG.CrystalPattern == "zigzag" then
					laneOffset = ((i % 2) == 0 and 1 or -1) * CONFIG.SlideWidth * 0.3
				elseif CONFIG.CrystalPattern == "wave" then
					laneOffset = math.sin(i * 0.5) * CONFIG.SlideWidth * 0.35
				else
					laneOffset = (math.random() - 0.5) * CONFIG.SlideWidth * 0.6
				end
				
				local crystalPos = pos + right * laneOffset + Vector3.new(0, CONFIG.SlideThickness / 2 + CONFIG.CrystalHeight, 0)
				local size = math.random(CONFIG.CrystalSize[1] * 10, CONFIG.CrystalSize[2] * 10) / 10
				local color = CONFIG.CrystalColors[math.random(1, #CONFIG.CrystalColors)]
				
				createCrystal(crystalPos, size, color, crystalFolder)
			end
		end
	end
	
	-- Create gates along the track
	if CONFIG.GatesEnabled then
		print("[HubService] Placing gates...")
		local gatesFolder = HubService._collections and HubService._collections.Gates or trackFolder
		local numGates = math.floor(totalPathLength / 150)
		
		for i = 1, numGates do
			local distance = ((i + 0.5) / (numGates + 1)) * totalPathLength
			local pos, dir = getPositionAtDistance(distance)
			
			if dir.Magnitude > 0.1 then
				local rotation = CFrame.lookAt(Vector3.zero, dir)
				local gatePos = pos + Vector3.new(0, CONFIG.SlideThickness / 2, 0)
				local kudosReward = math.random(CONFIG.GateKudosReward[1], CONFIG.GateKudosReward[2])
				
				local colorIndex = 1
				if kudosReward > 12 then colorIndex = 4
				elseif kudosReward > 10 then colorIndex = 3
				elseif kudosReward > 7 then colorIndex = 2 end
				local color = CONFIG.GateColors[colorIndex]
				
				createKudosGate(gatePos, rotation, i, kudosReward, color, gatesFolder)
			end
		end
	end
	
	-- Get end position for the finish platform
	local endPos = smoothPath[#smoothPath]
	local endTangent = (smoothPath[#smoothPath] - smoothPath[#smoothPath - 1]).Unit
	
	print(string.format("[HubService] Spline track complete! %d segments created", segmentCount))
	
	return {
		path = smoothPath,
		folder = trackFolder,
		endPos = endPos,
		endTangent = endTangent,
		totalLength = totalPathLength,
	}
end

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         WAVY SLIDE GENERATOR                               ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

-- Generate a wavy slide from a start position in a given direction
-- direction: "z+" (forward), "z-" (backward), "x+" (right), "x-" (left)
-- dropRate: positive = downhill, negative = uphill
local function generateWavySlide(params)
	local startPos = params.startPos           -- Vector3: starting position (edge of platform)
	local startY = params.startY               -- number: Y height at start
	local direction = params.direction or "z+" -- string: which way the slide goes
	local length = params.length               -- number: total length of slide
	local dropRate = params.dropRate or CONFIG.DownhillDropRate  -- slope steepness
	local width = params.width or CONFIG.SlideWidth
	local color = params.color or CONFIG.SlideColor
	local parent = params.parent
	local name = params.name or "WavySlide"
	local slideIndex = params.slideIndex or 1  -- For gate generation
	
	-- Create folder for this slide
	local slideFolder = Instance.new("Folder")
	slideFolder.Name = name
	slideFolder.Parent = parent
	
	-- Calculate wave offset at start so slide begins at exact platform height
	local initialWaveOffset = 0
	for _, wave in ipairs(CONFIG.SlideWaves) do
		initialWaveOffset = initialWaveOffset + math.sin(wave.Phase) * wave.Amplitude
	end
	
	-- Height function based on distance traveled
	-- Returns the CENTER Y of the slide segment (offset down by half thickness so TOP is flush with platform)
	-- dropRate: positive = goes down, negative = goes up
	local thicknessOffset = CONFIG.SlideThickness / 2
	local function getHeight(distance)
		local height = startY - (distance * dropRate)  -- Use passed dropRate
		for _, wave in ipairs(CONFIG.SlideWaves) do
			height = height + math.sin(distance * wave.Frequency + wave.Phase) * wave.Amplitude
		end
		-- Offset down so the TOP surface is at the calculated height
		return height - initialWaveOffset - thicknessOffset
	end
	
	-- Generate narrow zones for this slide
	local narrowZones = {}
	if CONFIG.NarrowZoneEnabled and math.random() < CONFIG.NarrowZoneChance then
		local numZones = math.random(CONFIG.NarrowZonesPerSlide[1], CONFIG.NarrowZonesPerSlide[2])
		local zoneSpacing = length / (numZones + 1)
		
		-- Generate initial zone centers
		local zoneCenters = {}
		for z = 1, numZones do
			local zoneCenter = zoneSpacing * z + math.random(-50, 50)
			zoneCenter = math.clamp(zoneCenter, CONFIG.NarrowZoneTransitionLength + 50, length - CONFIG.NarrowZoneTransitionLength - 50)
			table.insert(zoneCenters, zoneCenter)
		end
		
		-- Sort by position
		table.sort(zoneCenters)
		
		-- Create zones, merging overlapping ones
		local i = 1
		while i <= #zoneCenters do
			local startCenter = zoneCenters[i]
			local endCenter = startCenter
			
			-- Check for subsequent zones that should merge (if they overlap or are close)
			while i < #zoneCenters do
				local nextCenter = zoneCenters[i + 1]
				local currentZoneEnd = endCenter + CONFIG.NarrowZoneDuration / 2 + CONFIG.NarrowZoneTransitionLength
				local nextZoneStart = nextCenter - CONFIG.NarrowZoneDuration / 2 - CONFIG.NarrowZoneTransitionLength
				
				-- If zones overlap or are within transition distance, merge them
				if nextZoneStart <= currentZoneEnd + 20 then  -- 20 stud buffer for smooth connection
					endCenter = nextCenter
					i = i + 1
				else
					break
				end
			end
			
			-- Create the (possibly merged) zone
			table.insert(narrowZones, {
				start = startCenter - CONFIG.NarrowZoneDuration / 2 - CONFIG.NarrowZoneTransitionLength,
				narrowStart = startCenter - CONFIG.NarrowZoneDuration / 2,
				narrowEnd = endCenter + CONFIG.NarrowZoneDuration / 2,
				finish = endCenter + CONFIG.NarrowZoneDuration / 2 + CONFIG.NarrowZoneTransitionLength,
			})
			
			i = i + 1
		end
	end
	
	-- Width function based on distance (handles narrow zones with smooth transitions)
	local function getWidth(distance)
		local currentWidth = width
		local narrowAmount = width - CONFIG.NarrowZoneMinWidth
		
		for _, zone in ipairs(narrowZones) do
			if distance >= zone.start and distance <= zone.finish then
				if distance < zone.narrowStart then
					-- Transitioning into narrow
					local t = (distance - zone.start) / CONFIG.NarrowZoneTransitionLength
					t = math.clamp(t, 0, 1)
					t = t * t * (3 - 2 * t)  -- Smoothstep
					currentWidth = width - narrowAmount * t
				elseif distance > zone.narrowEnd then
					-- Transitioning out of narrow
					local t = (distance - zone.narrowEnd) / CONFIG.NarrowZoneTransitionLength
					t = math.clamp(t, 0, 1)
					t = t * t * (3 - 2 * t)  -- Smoothstep
					currentWidth = CONFIG.NarrowZoneMinWidth + narrowAmount * t
				else
					-- In the narrow section
					currentWidth = CONFIG.NarrowZoneMinWidth
				end
				break
			end
		end
		
		return currentWidth
	end
	
	-- Direction vector (horizontal movement direction)
	local forwardVec
	if direction == "z+" then
		forwardVec = Vector3.new(0, 0, 1)
	elseif direction == "z-" then
		forwardVec = Vector3.new(0, 0, -1)
	elseif direction == "x+" then
		forwardVec = Vector3.new(1, 0, 0)
	elseif direction == "x-" then
		forwardVec = Vector3.new(-1, 0, 0)
	end
	
	-- Get right vector (perpendicular to forward)
	local rightVec
	if direction == "z+" then
		rightVec = Vector3.new(1, 0, 0)
	elseif direction == "z-" then
		rightVec = Vector3.new(-1, 0, 0)
	elseif direction == "x+" then
		rightVec = Vector3.new(0, 0, -1)
	elseif direction == "x-" then
		rightVec = Vector3.new(0, 0, 1)
	end
	
	-- Generate segments
	local segmentLength = CONFIG.SlideSegmentLength
	local numSegments = math.ceil(length / segmentLength)
	local endPos = startPos
	local endY = startY
	
	-- Rail segment length (longer segments for performance)
	local railSegmentLength = CONFIG.RailSegmentLength
	local numRailSegments = math.ceil(length / railSegmentLength)
	
	for i = 0, numSegments - 1 do
		local d1 = i * segmentLength
		local d2 = (i + 1) * segmentLength
		local dMid = (d1 + d2) / 2
		
		local y1 = getHeight(d1)
		local y2 = getHeight(d2)
		local yMid = (y1 + y2) / 2
		
		-- Get width at this position (may vary due to narrow zones)
		local segmentWidth = getWidth(dMid)
		
		-- Position along the direction (3D points)
		local pos1 = Vector3.new(startPos.X, y1, startPos.Z) + forwardVec * d1
		local pos2 = Vector3.new(startPos.X, y2, startPos.Z) + forwardVec * d2
		local posMid = Vector3.new(startPos.X, yMid, startPos.Z) + forwardVec * dMid
		
		-- Calculate actual segment length (accounting for height change)
		local actualLength = (pos2 - pos1).Magnitude
		
		-- Create segment
		local segment = Instance.new("Part")
		segment.Name = "Segment_" .. i
		segment.Size = Vector3.new(segmentWidth, CONFIG.SlideThickness, actualLength + 0.5)
		segment.Color = color
		segment.Material = CONFIG.SlideMaterial
		segment.Anchored = true
		
		-- Use CFrame.lookAt to properly orient the segment along the slope
		-- The segment's front (-Z in part space) should face from pos1 to pos2
		local lookDir = (pos2 - pos1).Unit
		local segmentCFrame = CFrame.lookAt(posMid, posMid + lookDir)
		
		-- Rotate 180° around Y so the part's +Z faces the travel direction
		segment.CFrame = segmentCFrame * CFrame.Angles(0, math.pi, 0)
		segment.Parent = slideFolder
		
		-- Track end position (XZ only, Y from height function)
		endPos = startPos + forwardVec * d2
		endY = y2
	end
	
	-- Generate Snake Way style SPIKES (visual) + smooth colliders along edges
	-- Get master rails collection for Powers system
	local railsCollection = HubService._collections and HubService._collections.Rails
	
	-- Helper to create a spike at a position (visual only)
	local function createSpike(pos, side, index, lookDir)
		local spike = Instance.new("WedgePart")
		spike.Name = string.format("%sSpike_%d", side, index)
		spike.Size = Vector3.new(CONFIG.RailThickness, CONFIG.RailHeight, CONFIG.RailThickness * 1.5)
		spike.Color = CONFIG.RailColor
		spike.Material = CONFIG.RailMaterial
		spike.Anchored = true
		spike.CanCollide = false  -- Visual only!
		
		-- Orient spike pointing up, facing along the path direction
		local basePos = pos - Vector3.new(0, CONFIG.RailHeight / 2, 0)  -- Move base to bottom
		local cf = CFrame.lookAt(basePos, basePos + lookDir)
		
		-- Left spikes point one way, right spikes point the other
		if side == "Left" then
			spike.CFrame = cf * CFrame.new(0, CONFIG.RailHeight / 2, 0) * CFrame.Angles(0, math.pi, 0)
		else
			spike.CFrame = cf * CFrame.new(0, CONFIG.RailHeight / 2, 0)
		end
		
		spike.Parent = railsCollection or slideFolder
		return spike
	end
	
	-- Track previous positions for smooth colliders
	local prevLeftPos, prevRightPos = nil, nil
	
	-- Generate spikes and smooth colliders at intervals
	for i = 0, numRailSegments do
		local d = math.min(i * railSegmentLength, length)
		
		local y = getHeight(d) + thicknessOffset
		local railWidth = getWidth(d)
		local railOffset = railWidth / 2 - CONFIG.RailThickness / 4  -- Slightly inward
		
		-- Current positions (at base of spikes)
		local basePos = Vector3.new(startPos.X, y, startPos.Z) + forwardVec * d
		local leftPos = basePos - rightVec * railOffset
		local rightPos = basePos + rightVec * railOffset
		
		-- Create visual spikes
		createSpike(leftPos, "Left", i, forwardVec)
		createSpike(rightPos, "Right", i, forwardVec)
		
		-- Create smooth invisible colliders
		local colliderY = y + CONFIG.RailHeight / 2
		local leftColliderPos = Vector3.new(leftPos.X, colliderY, leftPos.Z)
		local rightColliderPos = Vector3.new(rightPos.X, colliderY, rightPos.Z)
		
		if prevLeftPos then
			-- Left smooth collider segment
			local leftDir = (leftColliderPos - prevLeftPos)
			local leftLen = leftDir.Magnitude
			if leftLen > 0.5 then
				local leftMid = (prevLeftPos + leftColliderPos) / 2
				local leftCollider = Instance.new("Part")
				leftCollider.Name = string.format("LeftCollider_%d", i)
				leftCollider.Size = Vector3.new(CONFIG.RailThickness, CONFIG.RailHeight, leftLen + 0.5)
				leftCollider.Transparency = 0.7  -- Semi-transparent
				leftCollider.Anchored = true
				leftCollider.CanCollide = true
				leftCollider.CFrame = CFrame.lookAt(leftMid, leftMid + leftDir.Unit)
				leftCollider.Parent = railsCollection or slideFolder
			end
			
			-- Right smooth collider segment
			local rightDir = (rightColliderPos - prevRightPos)
			local rightLen = rightDir.Magnitude
			if rightLen > 0.5 then
				local rightMid = (prevRightPos + rightColliderPos) / 2
				local rightCollider = Instance.new("Part")
				rightCollider.Name = string.format("RightCollider_%d", i)
				rightCollider.Size = Vector3.new(CONFIG.RailThickness, CONFIG.RailHeight, rightLen + 0.5)
				rightCollider.Transparency = 0.7  -- Semi-transparent
				rightCollider.Anchored = true
				rightCollider.CanCollide = true
				rightCollider.CFrame = CFrame.lookAt(rightMid, rightMid + rightDir.Unit)
				rightCollider.Parent = railsCollection or slideFolder
			end
		end
		
		prevLeftPos = leftColliderPos
		prevRightPos = rightColliderPos
	end
	
	print(string.format("[HubService] Generated %d segments + %d rail segments for %s", numSegments, numRailSegments * 2, name))
	
	-- Generate blockades on this slide
	generateBlockades({
		startPos = startPos,
		startY = startY,
		direction = direction,
		length = length,
		dropRate = dropRate,
		width = width,
		color = color,
		parent = slideFolder,
		getHeight = getHeight,
		getWidth = getWidth,
	})
	
	-- Generate crystals scattered on this slide
	generateCrystals({
		startPos = startPos,
		startY = startY,
		direction = direction,
		length = length,
		width = width,
		parent = slideFolder,
		getHeight = getHeight,
		getWidth = getWidth,
	})
	
	-- Generate kudos gates on this slide
	generateGates({
		startPos = startPos,
		startY = startY,
		direction = direction,
		length = length,
		parent = slideFolder,
		getHeight = getHeight,
		getWidth = getWidth,
		slideIndex = slideIndex,
	})
	
	-- Register slide as a track segment for building collision avoidance
	addTrackSegment(
		startPos.X,
		startPos.Z,
		endPos.X,
		endPos.Z,
		width
	)
	
	-- Return the TOP surface Y (add back thickness offset) for platform placement
	return {
		endPos = endPos,
		endY = endY + thicknessOffset,  -- Return top surface height, not center
		folder = slideFolder
	}
end

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         HUB CREATION                                        ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

function HubService:CreateHub()
	-- Create hub folder
	if self._hubFolder then
		self._hubFolder:Destroy()
	end
	self._hubFolder = Instance.new("Folder")
	self._hubFolder.Name = "Hub"
	self._hubFolder.Parent = Workspace
	
	-- Create master collection folders for Powers system
	self._collections.Crystals = Instance.new("Folder")
	self._collections.Crystals.Name = "AllCrystals"
	self._collections.Crystals.Parent = self._hubFolder
	
	self._collections.Blockades = Instance.new("Folder")
	self._collections.Blockades.Name = "AllBlockades"
	self._collections.Blockades.Parent = self._hubFolder
	
	self._collections.Rails = Instance.new("Folder")
	self._collections.Rails.Name = "AllRails"
	self._collections.Rails.Parent = self._hubFolder
	
	self._collections.Gates = Instance.new("Folder")
	self._collections.Gates.Name = "AllGates"
	self._collections.Gates.Parent = self._hubFolder
	
	-- Clear track geometry for fresh collision detection
	clearTrackGeometry()
	
	-- ══════════════════════════════════════════════════════════════════════
	-- 1. SHIPPING CENTER (player spawn area with warehouse aesthetics)
	-- ══════════════════════════════════════════════════════════════════════
	local shippingCenterModel = Instance.new("Model")
	shippingCenterModel.Name = "ShippingCenter"
	shippingCenterModel.Parent = self._hubFolder
	
	-- Main platform base (concrete floor)
	local startPlatform = createPart(
		"WarehouseFloor",
		CONFIG.StartPlatformSize,
		CONFIG.StartPlatformPosition,
		CONFIG.PlatformColor,
		CONFIG.PlatformMaterial,
		shippingCenterModel
	)
	
	-- Set floor as PrimaryPart
	shippingCenterModel.PrimaryPart = startPlatform
	
	local startPlatformTopY = CONFIG.StartPlatformPosition.Y + CONFIG.StartPlatformSize.Y / 2
	local startPlatformFrontZ = CONFIG.StartPlatformPosition.Z + CONFIG.StartPlatformSize.Z / 2
	local halfX = CONFIG.StartPlatformSize.X / 2
	local halfZ = CONFIG.StartPlatformSize.Z / 2
	local wallHeight = CONFIG.ShippingCenterWallHeight
	local wallThickness = 3
	
	-- WAREHOUSE WALLS (back and sides - open front for loading)
	local backWall = Instance.new("Part")
	backWall.Name = "BackWall"
	backWall.Size = Vector3.new(CONFIG.StartPlatformSize.X, wallHeight, wallThickness)
	backWall.Position = Vector3.new(CONFIG.StartPlatformPosition.X, startPlatformTopY + wallHeight/2, CONFIG.StartPlatformPosition.Z - halfZ - wallThickness/2)
	backWall.Color = CONFIG.ShippingCenterWallColor
	backWall.Material = Enum.Material.Concrete
	backWall.Anchored = true
	backWall.Parent = shippingCenterModel
	
	local leftWall = Instance.new("Part")
	leftWall.Name = "LeftWall"
	leftWall.Size = Vector3.new(wallThickness, wallHeight, CONFIG.StartPlatformSize.Z)
	leftWall.Position = Vector3.new(CONFIG.StartPlatformPosition.X - halfX - wallThickness/2, startPlatformTopY + wallHeight/2, CONFIG.StartPlatformPosition.Z)
	leftWall.Color = CONFIG.ShippingCenterWallColor
	leftWall.Material = Enum.Material.Concrete
	leftWall.Anchored = true
	leftWall.Parent = shippingCenterModel
	
	local rightWall = Instance.new("Part")
	rightWall.Name = "RightWall"
	rightWall.Size = Vector3.new(wallThickness, wallHeight, CONFIG.StartPlatformSize.Z)
	rightWall.Position = Vector3.new(CONFIG.StartPlatformPosition.X + halfX + wallThickness/2, startPlatformTopY + wallHeight/2, CONFIG.StartPlatformPosition.Z)
	rightWall.Color = CONFIG.ShippingCenterWallColor
	rightWall.Material = Enum.Material.Concrete
	rightWall.Anchored = true
	rightWall.Parent = shippingCenterModel
	
	-- ROOF with skylights
	local roofThickness = 2
	local roof = Instance.new("Part")
	roof.Name = "WarehouseRoof"
	roof.Size = Vector3.new(CONFIG.StartPlatformSize.X + wallThickness * 2, roofThickness, CONFIG.StartPlatformSize.Z + wallThickness)
	roof.Position = Vector3.new(CONFIG.StartPlatformPosition.X, startPlatformTopY + wallHeight + roofThickness/2, CONFIG.StartPlatformPosition.Z - wallThickness/2)
	roof.Color = CONFIG.ShippingCenterRoofColor
	roof.Material = Enum.Material.Metal
	roof.Anchored = true
	roof.Parent = shippingCenterModel
	
	for i = 1, 3 do
		local skylightX = CONFIG.StartPlatformPosition.X - halfX + (i / 4) * CONFIG.StartPlatformSize.X
		local skylight = Instance.new("Part")
		skylight.Name = "Skylight_" .. i
		skylight.Size = Vector3.new(20, roofThickness + 0.1, CONFIG.StartPlatformSize.Z * 0.5)
		skylight.Position = Vector3.new(skylightX, roof.Position.Y, CONFIG.StartPlatformPosition.Z - 5)
		skylight.Color = Color3.fromRGB(200, 220, 255)
		skylight.Material = Enum.Material.Glass
		skylight.Transparency = 0.6
		skylight.Anchored = true
		skylight.CanCollide = false
		skylight.Parent = shippingCenterModel
	end
	
	-- Loading dock hazard stripes (front edge)
	if CONFIG.StartPlatformHasEdgeTrim then
		local dockEdgeWidth = 5
		local dockStripeBase = Instance.new("Part")
		dockStripeBase.Name = "LoadingDockStripe"
		dockStripeBase.Size = Vector3.new(CONFIG.StartPlatformSize.X, 0.5, dockEdgeWidth)
		dockStripeBase.Position = Vector3.new(CONFIG.StartPlatformPosition.X, startPlatformTopY + 0.25, startPlatformFrontZ - dockEdgeWidth/2)
		dockStripeBase.Color = CONFIG.StartPlatformAccentColor
		dockStripeBase.Material = Enum.Material.SmoothPlastic
		dockStripeBase.Anchored = true
		dockStripeBase.CanCollide = false
		dockStripeBase.Parent = shippingCenterModel
		
		local stripeCount = math.floor(CONFIG.StartPlatformSize.X / 8)
		for i = 0, stripeCount do
			local stripeX = CONFIG.StartPlatformPosition.X - halfX + (i * 8) + 2
			local blackStripe = Instance.new("Part")
			blackStripe.Name = "HazardStripe_" .. i
			blackStripe.Size = Vector3.new(4, 0.6, dockEdgeWidth - 0.5)
			blackStripe.Position = Vector3.new(stripeX, startPlatformTopY + 0.3, startPlatformFrontZ - dockEdgeWidth/2)
			blackStripe.Color = Color3.fromRGB(30, 30, 30)
			blackStripe.Material = Enum.Material.SmoothPlastic
			blackStripe.Anchored = true
			blackStripe.CanCollide = false
			blackStripe.CFrame = blackStripe.CFrame * CFrame.Angles(0, math.rad(45), 0)
			blackStripe.Parent = shippingCenterModel
		end
	end
	
	-- Warehouse lane markings (white dashed lines)
	if CONFIG.StartPlatformHasStripes then
		local laneCount = 4
		for i = 1, laneCount - 1 do
			local laneX = CONFIG.StartPlatformPosition.X - halfX + (i / laneCount) * CONFIG.StartPlatformSize.X
			local dashCount = math.floor((CONFIG.StartPlatformSize.Z - 20) / 12)
			
			for d = 0, dashCount do
				local dashZ = CONFIG.StartPlatformPosition.Z - halfZ + 10 + (d * 12)
				local dash = Instance.new("Part")
				dash.Name = "LaneDash_" .. i .. "_" .. d
				dash.Size = Vector3.new(1, 0.2, 6)
				dash.Position = Vector3.new(laneX, startPlatformTopY + 0.1, dashZ)
				dash.Color = Color3.fromRGB(255, 255, 255)
				dash.Material = Enum.Material.SmoothPlastic
				dash.Anchored = true
				dash.CanCollide = false
				dash.Parent = shippingCenterModel
			end
		end
		
		-- Package loading zones (numbered bays)
		local zoneWidth = 25
		local zoneDepth = 15
		local zoneColor = Color3.fromRGB(0, 150, 255)
		
		for i = 1, 3 do
			local zoneX = CONFIG.StartPlatformPosition.X - halfX + 25 + ((i - 1) * 45)
			local zoneZ = CONFIG.StartPlatformPosition.Z - halfZ + 18
			
			-- Zone outline
			local zoneOutline = Instance.new("Part")
			zoneOutline.Name = "LoadingZone_" .. i
			zoneOutline.Size = Vector3.new(zoneWidth, 0.3, zoneDepth)
			zoneOutline.Position = Vector3.new(zoneX, startPlatformTopY + 0.15, zoneZ)
			zoneOutline.Color = zoneColor
			zoneOutline.Material = Enum.Material.Neon
			zoneOutline.Transparency = 0.7
			zoneOutline.Anchored = true
			zoneOutline.CanCollide = false
			zoneOutline.Parent = shippingCenterModel
			
			-- Zone number label
			local zoneLabelPart = Instance.new("Part")
			zoneLabelPart.Name = "ZoneLabel_" .. i
			zoneLabelPart.Size = Vector3.new(8, 0.3, 8)
			zoneLabelPart.Position = Vector3.new(zoneX, startPlatformTopY + 0.2, zoneZ)
			zoneLabelPart.Color = zoneColor
			zoneLabelPart.Material = Enum.Material.Neon
			zoneLabelPart.Transparency = 0.5
			zoneLabelPart.Anchored = true
			zoneLabelPart.CanCollide = false
			zoneLabelPart.Parent = shippingCenterModel
			
			local surfaceGui = Instance.new("SurfaceGui")
			surfaceGui.Face = Enum.NormalId.Top
			surfaceGui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
			surfaceGui.PixelsPerStud = 20
			surfaceGui.Parent = zoneLabelPart
			
			local zoneText = Instance.new("TextLabel")
			zoneText.Size = UDim2.new(1, 0, 1, 0)
			zoneText.BackgroundTransparency = 1
			zoneText.Text = tostring(i)
			zoneText.TextColor3 = Color3.fromRGB(255, 255, 255)
			zoneText.TextScaled = true
			zoneText.Font = Enum.Font.GothamBold
			zoneText.Rotation = 180
			zoneText.Parent = surfaceGui
		end
	end
	
	-- Industrial hanging warehouse lights (BRIGHT)
	if CONFIG.StartPlatformHasLights then
		local lightRows = 3  -- More rows
		local lightsPerRow = 5  -- More lights per row
		
		for row = 1, lightRows do
			for col = 1, lightsPerRow do
				local lightX = CONFIG.StartPlatformPosition.X - halfX + (col / (lightsPerRow + 1)) * CONFIG.StartPlatformSize.X
				local lightZ = CONFIG.StartPlatformPosition.Z - halfZ + (row / (lightRows + 1)) * CONFIG.StartPlatformSize.Z
				local lightY = startPlatformTopY + wallHeight - 3
				
				-- Light fixture (industrial cone)
				local fixture = Instance.new("Part")
				fixture.Name = "LightFixture_" .. row .. "_" .. col
				fixture.Size = Vector3.new(4, 2, 4)
				fixture.Position = Vector3.new(lightX, lightY, lightZ)
				fixture.Color = Color3.fromRGB(50, 50, 55)
				fixture.Material = Enum.Material.Metal
				fixture.Anchored = true
				fixture.CanCollide = false
				fixture.Parent = shippingCenterModel
				
				-- Light bulb (bright warm glow)
				local bulb = Instance.new("Part")
				bulb.Name = "LightBulb_" .. row .. "_" .. col
				bulb.Shape = Enum.PartType.Ball
				bulb.Size = Vector3.new(3, 3, 3)  -- Bigger bulbs
				bulb.Position = Vector3.new(lightX, lightY - 1.5, lightZ)
				bulb.Color = Color3.fromRGB(255, 240, 200)  -- Bright warm white
				bulb.Material = Enum.Material.Neon
				bulb.Anchored = true
				bulb.CanCollide = false
				bulb.Parent = shippingCenterModel
				
				local pointLight = Instance.new("PointLight")
				pointLight.Color = Color3.fromRGB(255, 245, 220)  -- Warm white
				pointLight.Brightness = 1.02
				pointLight.Range = 60
				pointLight.Parent = bulb
			end
		end
	end
	
	-- Storage shelving units (back of warehouse)
	local shelfWidth = 20
	local shelfDepth = 8
	local shelfHeight = 15
	for i = 1, 3 do
		local shelfX = CONFIG.StartPlatformPosition.X - halfX + 25 + ((i - 1) * 40)
		local shelfZ = CONFIG.StartPlatformPosition.Z - halfZ + shelfDepth/2 + 5
		
		local shelfFrame = Instance.new("Part")
		shelfFrame.Name = "ShelfFrame_" .. i
		shelfFrame.Size = Vector3.new(shelfWidth, shelfHeight, shelfDepth)
		shelfFrame.Position = Vector3.new(shelfX, startPlatformTopY + shelfHeight/2, shelfZ)
		shelfFrame.Color = Color3.fromRGB(100, 80, 60)
		shelfFrame.Material = Enum.Material.Metal
		shelfFrame.Transparency = 0.3
		shelfFrame.Anchored = true
		shelfFrame.Parent = shippingCenterModel
		
		for level = 1, 3 do
			local levelY = startPlatformTopY + (level * 4)
			local shelfLevel = Instance.new("Part")
			shelfLevel.Name = "ShelfLevel_" .. i .. "_" .. level
			shelfLevel.Size = Vector3.new(shelfWidth - 2, 0.5, shelfDepth - 1)
			shelfLevel.Position = Vector3.new(shelfX, levelY, shelfZ)
			shelfLevel.Color = Color3.fromRGB(80, 65, 50)
			shelfLevel.Material = Enum.Material.Wood
			shelfLevel.Anchored = true
			shelfLevel.Parent = shippingCenterModel
		end
	end
	
	-- Shipping Center sign (on back wall)
	local signPart = Instance.new("Part")
	signPart.Name = "ShippingCenterSign"
	signPart.Size = Vector3.new(60, 8, 1)
	signPart.Position = Vector3.new(CONFIG.StartPlatformPosition.X, startPlatformTopY + wallHeight - 5, CONFIG.StartPlatformPosition.Z - halfZ - wallThickness - 1)
	signPart.Color = Color3.fromRGB(20, 60, 120)
	signPart.Material = Enum.Material.SmoothPlastic
	signPart.Anchored = true
	signPart.Parent = shippingCenterModel
	
	local signGui = Instance.new("SurfaceGui")
	signGui.Face = Enum.NormalId.Back
	signGui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	signGui.PixelsPerStud = 30
	signGui.Parent = signPart
	
	local signText = Instance.new("TextLabel")
	signText.Size = UDim2.new(1, 0, 1, 0)
	signText.BackgroundTransparency = 1
	signText.Text = "📦 SHIPPING CENTER 📦"
	signText.TextColor3 = Color3.fromRGB(255, 255, 255)
	signText.TextScaled = true
	signText.Font = Enum.Font.GothamBold
	signText.Parent = signGui
	
	-- Register start platform in track geometry
	addTrackBox(
		CONFIG.StartPlatformPosition.X,
		CONFIG.StartPlatformPosition.Z,
		CONFIG.StartPlatformSize.X / 2,
		CONFIG.StartPlatformSize.Z / 2
	)
	
	-- Safety rails (industrial yellow - NOT spikes, on sides without slides)
	local platformHalfX = CONFIG.StartPlatformSize.X / 2
	local platformHalfZ = CONFIG.StartPlatformSize.Z / 2
	local platformCenterX = CONFIG.StartPlatformPosition.X
	local platformCenterZ = CONFIG.StartPlatformPosition.Z
	local safetyColor = CONFIG.StartPlatformAccentColor  -- Yellow safety color
	
	-- Left rail (X-)
	createSafetyRail(
		"ShippingCenter_LeftRail",
		Vector3.new(platformCenterX - platformHalfX, startPlatformTopY, platformCenterZ - platformHalfZ),
		Vector3.new(platformCenterX - platformHalfX, startPlatformTopY, platformCenterZ + platformHalfZ),
		0,
		safetyColor,
		shippingCenterModel
	)
	
	-- Right rail (X+)
	createSafetyRail(
		"ShippingCenter_RightRail",
		Vector3.new(platformCenterX + platformHalfX, startPlatformTopY, platformCenterZ - platformHalfZ),
		Vector3.new(platformCenterX + platformHalfX, startPlatformTopY, platformCenterZ + platformHalfZ),
		0,
		safetyColor,
		shippingCenterModel
	)
	
	-- ══════════════════════════════════════════════════════════════════════
	-- START ZONE (wall at slide entrance - detects when players leave)
	-- ══════════════════════════════════════════════════════════════════════
	if CONFIG.StartZoneEnabled then
		local startZonePart = Instance.new("Part")
		startZonePart.Name = "StartZone"
		startZonePart.Size = CONFIG.StartZoneSize
		startZonePart.Position = Vector3.new(
			CONFIG.StartPlatformPosition.X,
			startPlatformTopY + CONFIG.StartZoneSize.Y / 2,
			startPlatformFrontZ + CONFIG.StartZoneSize.Z / 2  -- At the edge where slide starts
		)
		startZonePart.Color = CONFIG.StartZoneColor
		startZonePart.Transparency = CONFIG.StartZoneTransparency
		startZonePart.Material = Enum.Material.ForceField
		startZonePart.Anchored = true
		startZonePart.CanCollide = false  -- Players can pass through
		startZonePart.Parent = self._hubFolder
		
		-- Create Zone+ zone from the part
		self._startZone = Zone.new(startZonePart)
		
		-- When player exits the zone, start their race timer
		self._startZone.playerExited:Connect(function(player)
			print(string.format("[HubService] Player '%s' exited the start zone - starting timer!", player.Name))
			self:StartPlayerTimer(player)
		end)
		
		-- When player enters the zone, stop their timer (they came back)
		self._startZone.playerEntered:Connect(function(player)
			print(string.format("[HubService] Player '%s' entered the start zone", player.Name))
			-- Optionally stop timer if they return to start
			-- self:StopPlayerTimer(player)
		end)
		
		print("[HubService] Start zone created at slide entrance")
	end
	
	-- ══════════════════════════════════════════════════════════════════════
	-- 2. GENERATE ALL SLIDES AND PLATFORMS (with random directions)
	-- ══════════════════════════════════════════════════════════════════════
	
	-- Track current position and height for chaining slides
	local currentTopY = startPlatformTopY
	local currentPos = Vector3.new(CONFIG.StartPlatformPosition.X, 0, startPlatformFrontZ)
	local lastSlideResult = nil
	local currentDirection = CONFIG.FirstSlideDirection
	
	-- All possible directions
	local allDirections = {"z+", "z-", "x+", "x-"}
	
	-- Get the opposite direction (can't go backwards)
	local function getOppositeDirection(dir)
		if dir == "z+" then return "z-" end
		if dir == "z-" then return "z+" end
		if dir == "x+" then return "x-" end
		if dir == "x-" then return "x+" end
		return nil
	end
	
	-- Get available directions (excludes the direction we came from)
	local function getAvailableDirections(incomingDir)
		local opposite = getOppositeDirection(incomingDir)
		local available = {}
		for _, dir in ipairs(allDirections) do
			if dir ~= opposite then
				table.insert(available, dir)
			end
		end
		return available
	end
	
	-- Helper to get edge position based on direction
	local function getEdgeOffset(direction, platformSize)
		if direction == "z+" then
			return Vector3.new(0, 0, platformSize / 2)
		elseif direction == "z-" then
			return Vector3.new(0, 0, -platformSize / 2)
		elseif direction == "x+" then
			return Vector3.new(platformSize / 2, 0, 0)
		elseif direction == "x-" then
			return Vector3.new(-platformSize / 2, 0, 0)
		end
		return Vector3.zero
	end
	
	-- Helper to get platform center offset from slide end
	local function getPlatformOffset(direction, platformSize)
		if direction == "z+" then
			return Vector3.new(0, 0, platformSize / 2)
		elseif direction == "z-" then
			return Vector3.new(0, 0, -platformSize / 2)
		elseif direction == "x+" then
			return Vector3.new(platformSize / 2, 0, 0)
		elseif direction == "x-" then
			return Vector3.new(-platformSize / 2, 0, 0)
		end
		return Vector3.zero
	end
	
	-- ══════════════════════════════════════════════════════════════════════
	-- TRACK GENERATION (SPLINE or SEGMENT-BASED)
	-- ══════════════════════════════════════════════════════════════════════
	
	local splineTrackResult = nil
	
	if CONFIG.UseSplineTrack then
		-- Use the new spline-based track generation
		print("[HubService] Using SPLINE-based track generation")
		
		local startPos = Vector3.new(
			CONFIG.StartPlatformPosition.X,
			startPlatformTopY,
			startPlatformFrontZ
		)
		
		splineTrackResult = generateSplineTrack(startPos, self._hubFolder)
		
		if splineTrackResult then
			-- Create end shipping center (Receiving Center) at the end of the spline
			local endPos = splineTrackResult.endPos
			local endTangent = splineTrackResult.endTangent
			
			-- Position entrance at track end, flush with the path
			local entrancePos = endPos - Vector3.new(0, CONFIG.SlideThickness / 2, 0)
			local endPlatformSize = CONFIG.FinalLandingSize
			
			-- Create the receiving center rotated to face the incoming track
			local endCenterResult = createEndShippingCenter(entrancePos, endTangent, endPlatformSize, self._hubFolder)
			
			-- Setup package collection detection
			if endCenterResult and endCenterResult.collectionZone then
				self:SetupPackageCollection(endCenterResult.collectionZone)
			end
			
			print(string.format("[HubService] Spline track complete! Total length: %.0f studs", splineTrackResult.totalLength))
		else
			warn("[HubService] Spline track generation failed! Falling back to segment-based...")
		end
	end
	
	-- Skip segment-based generation if spline track was successful
	if not CONFIG.UseSplineTrack or not splineTrackResult then
	
	-- Generate slides with random directions (OLD SEGMENT-BASED SYSTEM)
	for i = 1, CONFIG.NumSlides do
		-- Pick random length and color
		local slideLength = math.random(CONFIG.SlideLengthMin, CONFIG.SlideLengthMax)
		local slideColor = CONFIG.SlideColors[(i - 1) % #CONFIG.SlideColors + 1]
		
		-- Decide slope direction based on current height
		local dropRate
		local slideType
		
		if currentTopY <= CONFIG.MinHeight + CONFIG.HeightWarningBuffer then
			-- Too low! Must go up
			dropRate = CONFIG.UphillDropRate
			slideType = "UP"
		elseif currentTopY >= CONFIG.MaxHeight - CONFIG.HeightWarningBuffer then
			-- Too high! Must go down
			dropRate = CONFIG.DownhillDropRate
			slideType = "DOWN"
		else
			-- Safe zone - randomly pick up or down (weighted toward down for fun)
			if math.random() < 0.3 then  -- 30% chance to go up
				dropRate = CONFIG.UphillDropRate
				slideType = "UP"
			else
				dropRate = CONFIG.DownhillDropRate
				slideType = "DOWN"
			end
		end
		
		-- Generate slide
		local slideResult = generateWavySlide({
			startPos = currentPos,
			startY = currentTopY,
			direction = currentDirection,
			length = slideLength,
			dropRate = dropRate,
			width = CONFIG.MiddlePlatformSize,
			color = slideColor,
			parent = self._hubFolder,
			name = string.format("Slide%d_%s_%s", i, currentDirection, slideType),
			slideIndex = i,  -- For gate generation
		})
		
		lastSlideResult = slideResult
		
		-- Generate floating buildings along this slide
		generateBuildingsAlongPath(
			currentPos, 
			slideResult.endPos, 
			(currentTopY + slideResult.endY) / 2,  -- Average height
			currentDirection, 
			self._hubFolder
		)
		
		-- Generate cloud formations along this slide
		generateCloudsAlongPath(
			currentPos,
			slideResult.endPos,
			(currentTopY + slideResult.endY) / 2,
			currentDirection,
			self._hubFolder
		)
		
		print(string.format("[HubService] Slide %d: %s %s, %d studs, Y: %.0f -> %.0f", 
			i, slideType, currentDirection, slideLength, currentTopY, slideResult.endY))
		
		-- Create intermediate platform (except after last slide)
		if i < CONFIG.NumSlides then
			local platformColor = CONFIG.PlatformColors[(i - 1) % #CONFIG.PlatformColors + 1]
			local platformOffset = getPlatformOffset(currentDirection, CONFIG.MiddlePlatformSize)
			
			local platformPos = Vector3.new(
				slideResult.endPos.X + platformOffset.X,
				slideResult.endY - CONFIG.MiddlePlatformHeight / 2,
				slideResult.endPos.Z + platformOffset.Z
			)
			
		-- Create base platform
		createPart(
			string.format("Platform%d", i),
			Vector3.new(CONFIG.MiddlePlatformSize, CONFIG.MiddlePlatformHeight, CONFIG.MiddlePlatformSize),
			platformPos,
			CONFIG.MiddlePlatformColor,  -- Use consistent dark base color
			CONFIG.PlatformMaterial,
			self._hubFolder
		)
		
		-- Add platform decorations with cycling accent colors
		local accentColor = CONFIG.MiddlePlatformAccentColors[(i - 1) % #CONFIG.MiddlePlatformAccentColors + 1]
		decoratePlatform(platformPos, CONFIG.MiddlePlatformSize, accentColor, {
			hasEdgeTrim = CONFIG.MiddlePlatformHasEdgeTrim,
			hasCornerLights = CONFIG.MiddlePlatformHasCornerLights,
			hasUnderglow = CONFIG.MiddlePlatformHasUnderglow,
			hasCenterMarking = CONFIG.MiddlePlatformHasCenterMarking,
			platformIndex = i,
		}, self._hubFolder)
		
		-- Register intermediate platform in track geometry
		addTrackBox(
			platformPos.X,
			platformPos.Z,
			CONFIG.MiddlePlatformSize / 2,
			CONFIG.MiddlePlatformSize / 2
		)
		
		-- Pick random direction for next slide (excluding where we came from)
		local availableDirections = getAvailableDirections(currentDirection)
		local nextDirection = availableDirections[math.random(1, #availableDirections)]
		
		-- Add rails to platform sides that don't have slides
		local incomingDir = currentDirection  -- Where we came from
		local outgoingDir = nextDirection     -- Where we're going
		local platformTopY = platformPos.Y + CONFIG.MiddlePlatformHeight / 2
		local halfSize = CONFIG.MiddlePlatformSize / 2
		
		-- Check each side and add tubular rail if not connected to a slide
		local sides = {
			{dir = "z+", offset = Vector3.new(0, 0, halfSize)},
			{dir = "z-", offset = Vector3.new(0, 0, -halfSize)},
			{dir = "x+", offset = Vector3.new(halfSize, 0, 0)},
			{dir = "x-", offset = Vector3.new(-halfSize, 0, 0)},
		}
		
		for _, side in ipairs(sides) do
			-- Actually, we want rails on sides that DON'T have slides
			-- Incoming slide comes FROM the opposite direction, outgoing goes TO the direction
			local hasIncoming = (getOppositeDirection(side.dir) == incomingDir)
			local hasOutgoing = (side.dir == outgoingDir)
			
			if not hasIncoming and not hasOutgoing then
				-- Calculate start and end points for tubular rail
				local railStartPos, railEndPos
				if side.dir == "z+" or side.dir == "z-" then
					-- Rail runs along X axis
					railStartPos = Vector3.new(platformPos.X - halfSize, platformTopY, platformPos.Z + side.offset.Z)
					railEndPos = Vector3.new(platformPos.X + halfSize, platformTopY, platformPos.Z + side.offset.Z)
				else
					-- Rail runs along Z axis
					railStartPos = Vector3.new(platformPos.X + side.offset.X, platformTopY, platformPos.Z - halfSize)
					railEndPos = Vector3.new(platformPos.X + side.offset.X, platformTopY, platformPos.Z + halfSize)
				end
				
				createTubularPlatformRail(
					string.format("PlatformRail_%d_%s", i, side.dir),
					railStartPos,
					railEndPos,
					0,
					self._hubFolder
				)
			end
		end
			
			local edgeOffset = getEdgeOffset(nextDirection, CONFIG.MiddlePlatformSize)
			
			currentTopY = platformPos.Y + CONFIG.MiddlePlatformHeight / 2
			currentPos = Vector3.new(
				platformPos.X + edgeOffset.X,
				0,
				platformPos.Z + edgeOffset.Z
			)
			
			-- Update direction for next iteration
			currentDirection = nextDirection
			
			print(string.format("[HubService] Platform %d at (%.0f, %.0f, %.0f) -> next: %s", 
				i, platformPos.X, platformPos.Y, platformPos.Z, nextDirection))
		end
	end
	
	print(string.format("[HubService] Generated %d slides!", CONFIG.NumSlides))
	
	-- ══════════════════════════════════════════════════════════════════════
	-- 3. FINAL LANDING AREA
	-- ══════════════════════════════════════════════════════════════════════
	local landingOffset = getPlatformOffset(currentDirection, CONFIG.FinalLandingSize.X)
	
	local finalLandingPos = Vector3.new(
		lastSlideResult.endPos.X + landingOffset.X,
		lastSlideResult.endY - CONFIG.FinalLandingSize.Y / 2,
		lastSlideResult.endPos.Z + landingOffset.Z
	)
	
	createPart(
		"FinalLanding",
		CONFIG.FinalLandingSize,
		finalLandingPos,
		CONFIG.FinalLandingColor,
		Enum.Material.SmoothPlastic,
		self._hubFolder
	)
	
	-- Add finish line decorations (checkerboard, victory arch)
	decoratePlatform(finalLandingPos, CONFIG.FinalLandingSize, CONFIG.FinalLandingAccentColor, {
		hasEdgeTrim = true,
		hasCornerLights = true,
		hasUnderglow = true,
		hasCheckerboard = CONFIG.FinalLandingHasCheckerboard,
		hasVictoryArch = CONFIG.FinalLandingHasVictoryArch,
		platformIndex = "Final",
	}, self._hubFolder)
	
	-- Final landing rails (smooth tubular - on sides without the incoming slide)
	local landingTopY = finalLandingPos.Y + CONFIG.FinalLandingSize.Y / 2
	local landingHalfX = CONFIG.FinalLandingSize.X / 2
	local landingHalfZ = CONFIG.FinalLandingSize.Z / 2
	local incomingFromDir = getOppositeDirection(currentDirection)  -- Where the slide comes from
	
	-- Add smooth tubular rails on sides that don't have the incoming slide
	if incomingFromDir ~= "z-" then
		createTubularPlatformRail("FinalLanding_BackRail",
			Vector3.new(finalLandingPos.X - landingHalfX, landingTopY, finalLandingPos.Z - landingHalfZ),
			Vector3.new(finalLandingPos.X + landingHalfX, landingTopY, finalLandingPos.Z - landingHalfZ),
			0, self._hubFolder)
	end
	if incomingFromDir ~= "z+" then
		createTubularPlatformRail("FinalLanding_FrontRail",
			Vector3.new(finalLandingPos.X - landingHalfX, landingTopY, finalLandingPos.Z + landingHalfZ),
			Vector3.new(finalLandingPos.X + landingHalfX, landingTopY, finalLandingPos.Z + landingHalfZ),
			0, self._hubFolder)
	end
	if incomingFromDir ~= "x-" then
		createTubularPlatformRail("FinalLanding_LeftRail",
			Vector3.new(finalLandingPos.X - landingHalfX, landingTopY, finalLandingPos.Z - landingHalfZ),
			Vector3.new(finalLandingPos.X - landingHalfX, landingTopY, finalLandingPos.Z + landingHalfZ),
			0, self._hubFolder)
	end
	if incomingFromDir ~= "x+" then
		createTubularPlatformRail("FinalLanding_RightRail",
			Vector3.new(finalLandingPos.X + landingHalfX, landingTopY, finalLandingPos.Z - landingHalfZ),
			Vector3.new(finalLandingPos.X + landingHalfX, landingTopY, finalLandingPos.Z + landingHalfZ),
			0, self._hubFolder)
	end
	
	end  -- End of segment-based track generation conditional
	
	-- ══════════════════════════════════════════════════════════════════════
	-- SPAWN LOCATION
	-- ══════════════════════════════════════════════════════════════════════
	local spawnPos = CONFIG.StartPlatformPosition + CONFIG.SpawnOffset + Vector3.new(0, CONFIG.StartPlatformSize.Y/2 + 3, 0)
	
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "HubSpawn"
	spawn.Size = Vector3.new(12, 1, 12)
	spawn.Position = spawnPos
	spawn.Anchored = true
	spawn.CanCollide = false
	spawn.Transparency = 0.5
	spawn.Color = Color3.fromRGB(100, 200, 255)
	spawn.Material = Enum.Material.Neon
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Parent = self._hubFolder
	
	self._spawnLocation = spawn
	
	print(string.format("[HubService] Hub created! %d slides with random directions", CONFIG.NumSlides))
	
	return self._hubFolder
end

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         PLAYER TIMER FUNCTIONS                              ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

-- Class token for race timer replicas (created once)
local RaceTimerClassToken = ReplicaService.NewClassToken("RaceTimerReplica")

function HubService:StartPlayerTimer(player)
	-- Don't start if already running
	if self._playerTimers[player] then
		print(string.format("[HubService] Timer already running for %s", player.Name))
		return
	end
	
	local startTime = tick()
	
	-- Create a replica for this player's timer
	local replica = ReplicaService.NewReplica({
		ClassToken = RaceTimerClassToken,
		Data = {
			ElapsedTime = 0,
			IsRunning = true,
			StartTime = startTime,
		},
		Replication = { [player] = true },  -- Only replicate to this player
	})
	
	-- Create a timer that ticks every 0.1 seconds to update the replica
	local timer = Timer.new(0.1)
	timer.Tick:Connect(function()
		local elapsed = tick() - startTime
		replica:SetValue({"ElapsedTime"}, elapsed)
	end)
	timer:Start()
	
	-- Store timer data
	self._playerTimers[player] = {
		timer = timer,
		replica = replica,
		startTime = startTime,
	}
	
	print(string.format("[HubService] Started race timer for %s", player.Name))
end

function HubService:StopPlayerTimer(player)
	local timerData = self._playerTimers[player]
	if not timerData then
		return nil
	end
	
	-- Stop the timer
	timerData.timer:Stop()
	timerData.timer:Destroy()
	
	-- Get final time
	local finalTime = tick() - timerData.startTime
	
	-- Update replica one last time
	timerData.replica:SetValue({"ElapsedTime"}, finalTime)
	timerData.replica:SetValue({"IsRunning"}, false)
	
	-- Destroy replica after a short delay so client can see final time
	task.delay(5, function()
		if timerData.replica then
			timerData.replica:Destroy()
		end
	end)
	
	-- Clear from table
	self._playerTimers[player] = nil
	
	print(string.format("[HubService] Stopped race timer for %s - Final time: %.2f seconds", player.Name, finalTime))
	
	return finalTime
end

function HubService:GetPlayerTime(player)
	local timerData = self._playerTimers[player]
	if not timerData then
		return nil
	end
	return tick() - timerData.startTime
end

-- Clean up timers when players leave
local function onPlayerRemoving(player)
	local hubService = Knit.GetService("HubService")
	if hubService._playerTimers[player] then
		hubService:StopPlayerTimer(player)
	end
end

Players.PlayerRemoving:Connect(onPlayerRemoving)

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         PACKAGE CHUTE SYSTEM (Ceiling Drop)                 ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

function HubService:CreatePackageChute(ceilingY, dropPosition)
	if not CONFIG.PackageChuteEnabled then return nil end
	
	local chuteFolder = Instance.new("Folder")
	chuteFolder.Name = "PackageChute"
	chuteFolder.Parent = self._hubFolder
	
	local chuteRadius = CONFIG.ChuteWidth / 2
	local pipeLength = 10  -- Shorter chute pipe
	
	-- Main cylindrical chute pipe coming down from ceiling
	local chutePipe = Instance.new("Part")
	chutePipe.Name = "ChutePipe"
	chutePipe.Shape = Enum.PartType.Cylinder
	chutePipe.Size = Vector3.new(pipeLength, chuteRadius * 2, chuteRadius * 2)
	chutePipe.Position = Vector3.new(dropPosition.X, ceilingY - pipeLength/2, dropPosition.Z)
	chutePipe.CFrame = chutePipe.CFrame * CFrame.Angles(0, 0, math.rad(90))
	chutePipe.Color = CONFIG.ChuteColor
	chutePipe.Material = Enum.Material.Metal
	chutePipe.Anchored = true
	chutePipe.CanCollide = false  -- Packages fall through
	chutePipe.Parent = chuteFolder
	
	-- Inner darker pipe (for depth effect)
	local innerPipe = Instance.new("Part")
	innerPipe.Name = "InnerPipe"
	innerPipe.Shape = Enum.PartType.Cylinder
	innerPipe.Size = Vector3.new(pipeLength + 1, (chuteRadius - 1) * 2, (chuteRadius - 1) * 2)
	innerPipe.Position = Vector3.new(dropPosition.X, ceilingY - pipeLength/2, dropPosition.Z)
	innerPipe.CFrame = innerPipe.CFrame * CFrame.Angles(0, 0, math.rad(90))
	innerPipe.Color = Color3.fromRGB(30, 30, 35)  -- Dark interior
	innerPipe.Material = Enum.Material.Metal
	innerPipe.Anchored = true
	innerPipe.CanCollide = false  -- Packages fall through
	innerPipe.Parent = chuteFolder
	
	-- Ceiling mount (flange where pipe meets ceiling)
	local flange = Instance.new("Part")
	flange.Name = "ChuteFlange"
	flange.Shape = Enum.PartType.Cylinder
	flange.Size = Vector3.new(3, chuteRadius * 2.5, chuteRadius * 2.5)
	flange.Position = Vector3.new(dropPosition.X, ceilingY - 1.5, dropPosition.Z)
	flange.CFrame = flange.CFrame * CFrame.Angles(0, 0, math.rad(90))
	flange.Color = Color3.fromRGB(50, 55, 60)
	flange.Material = Enum.Material.Metal
	flange.Anchored = true
	flange.CanCollide = false  -- Packages fall through
	flange.Parent = chuteFolder
	
	-- Bottom rim (thicker ring at exit)
	local bottomRim = Instance.new("Part")
	bottomRim.Name = "BottomRim"
	bottomRim.Shape = Enum.PartType.Cylinder
	bottomRim.Size = Vector3.new(2, chuteRadius * 2.2, chuteRadius * 2.2)
	bottomRim.Position = Vector3.new(dropPosition.X, ceilingY - pipeLength - 1, dropPosition.Z)
	bottomRim.CFrame = bottomRim.CFrame * CFrame.Angles(0, 0, math.rad(90))
	bottomRim.Color = Color3.fromRGB(50, 55, 60)
	bottomRim.Material = Enum.Material.Metal
	bottomRim.Anchored = true
	bottomRim.CanCollide = false  -- Packages fall through
	bottomRim.Parent = chuteFolder
	
	-- Spawn point (inside chute near top)
	local spawnPoint = Vector3.new(dropPosition.X, ceilingY - 3, dropPosition.Z)
	
	-- Status sign hanging from ceiling at the front of the room
	local signHeight = 12
	local signY = ceilingY - 8  -- Hang from ceiling
	local signZ = dropPosition.Z + 35  -- Forward toward entrance
	
	local signPart = Instance.new("Part")
	signPart.Name = "ChuteStatusSign"
	signPart.Size = Vector3.new(20, signHeight, 0.5)
	signPart.Position = Vector3.new(dropPosition.X, signY, signZ)
	signPart.Color = Color3.fromRGB(30, 35, 40)
	signPart.Material = Enum.Material.SmoothPlastic
	signPart.Anchored = true
	signPart.CanCollide = false
	signPart.Parent = chuteFolder
	
	-- Glow frame around sign
	local glowFrame = Instance.new("Part")
	glowFrame.Name = "SignGlow"
	glowFrame.Size = Vector3.new(20.5, signHeight + 0.5, 0.3)
	glowFrame.Position = signPart.Position - Vector3.new(0, 0, 0.2)
	glowFrame.Color = Color3.fromRGB(0, 180, 150)
	glowFrame.Material = Enum.Material.Neon
	glowFrame.Transparency = 0.5
	glowFrame.Anchored = true
	glowFrame.CanCollide = false
	glowFrame.Parent = chuteFolder
	
	-- Hanging cables/chains from ceiling
	local cableWidth = 0.5
	local cableHeight = ceilingY - signY - signHeight/2
	
	-- Left cable
	local leftCable = Instance.new("Part")
	leftCable.Name = "LeftCable"
	leftCable.Size = Vector3.new(cableWidth, cableHeight, cableWidth)
	leftCable.Position = Vector3.new(dropPosition.X - 8, ceilingY - cableHeight/2, signZ)
	leftCable.Color = Color3.fromRGB(50, 55, 60)
	leftCable.Material = Enum.Material.Metal
	leftCable.Anchored = true
	leftCable.CanCollide = false
	leftCable.Parent = chuteFolder
	
	-- Right cable
	local rightCable = Instance.new("Part")
	rightCable.Name = "RightCable"
	rightCable.Size = Vector3.new(cableWidth, cableHeight, cableWidth)
	rightCable.Position = Vector3.new(dropPosition.X + 8, ceilingY - cableHeight/2, signZ)
	rightCable.Color = Color3.fromRGB(50, 55, 60)
	rightCable.Material = Enum.Material.Metal
	rightCable.Anchored = true
	rightCable.CanCollide = false
	rightCable.Parent = chuteFolder
	
	-- Ceiling mount bar
	local mountBar = Instance.new("Part")
	mountBar.Name = "MountBar"
	mountBar.Size = Vector3.new(18, 1, 1)
	mountBar.Position = Vector3.new(dropPosition.X, ceilingY - 0.5, signZ)
	mountBar.Color = Color3.fromRGB(40, 45, 50)
	mountBar.Material = Enum.Material.Metal
	mountBar.Anchored = true
	mountBar.CanCollide = false
	mountBar.Parent = chuteFolder
	
	-- Create SurfaceGui for the sign (back face - facing into the room)
	local signGui = Instance.new("SurfaceGui")
	signGui.Name = "StatusGui"
	signGui.Face = Enum.NormalId.Back
	signGui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	signGui.PixelsPerStud = 50
	signGui.Parent = signPart
	
	local mainFrame = Instance.new("Frame")
	mainFrame.Name = "MainFrame"
	mainFrame.Size = UDim2.new(1, 0, 1, 0)
	mainFrame.BackgroundTransparency = 1
	mainFrame.Parent = signGui
	
	-- Title
	local titleLabel = Instance.new("TextLabel")
	titleLabel.Name = "Title"
	titleLabel.Size = UDim2.new(1, 0, 0.15, 0)
	titleLabel.Position = UDim2.new(0, 0, 0.02, 0)
	titleLabel.BackgroundTransparency = 1
	titleLabel.Text = "📦 PACKAGE STATUS"
	titleLabel.TextColor3 = Color3.fromRGB(0, 220, 180)
	titleLabel.TextScaled = true
	titleLabel.Font = Enum.Font.GothamBold
	titleLabel.Parent = mainFrame
	
	-- Active packages count
	local activeLabel = Instance.new("TextLabel")
	activeLabel.Name = "ActiveCount"
	activeLabel.Size = UDim2.new(1, 0, 0.2, 0)
	activeLabel.Position = UDim2.new(0, 0, 0.2, 0)
	activeLabel.BackgroundTransparency = 1
	activeLabel.Text = "Available: 0"
	activeLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	activeLabel.TextScaled = true
	activeLabel.Font = Enum.Font.GothamBold
	activeLabel.Parent = mainFrame
	
	-- Total spawned
	local spawnedLabel = Instance.new("TextLabel")
	spawnedLabel.Name = "SpawnedCount"
	spawnedLabel.Size = UDim2.new(1, 0, 0.15, 0)
	spawnedLabel.Position = UDim2.new(0, 0, 0.42, 0)
	spawnedLabel.BackgroundTransparency = 1
	spawnedLabel.Text = "Spawned: 0"
	spawnedLabel.TextColor3 = Color3.fromRGB(180, 180, 190)
	spawnedLabel.TextScaled = true
	spawnedLabel.Font = Enum.Font.Gotham
	spawnedLabel.Parent = mainFrame
	
	-- Total collected
	local collectedLabel = Instance.new("TextLabel")
	collectedLabel.Name = "CollectedCount"
	collectedLabel.Size = UDim2.new(1, 0, 0.15, 0)
	collectedLabel.Position = UDim2.new(0, 0, 0.58, 0)
	collectedLabel.BackgroundTransparency = 1
	collectedLabel.Text = "Delivered: 0"
	collectedLabel.TextColor3 = Color3.fromRGB(100, 255, 150)
	collectedLabel.TextScaled = true
	collectedLabel.Font = Enum.Font.Gotham
	collectedLabel.Parent = mainFrame
	
	-- Status message
	local statusLabel = Instance.new("TextLabel")
	statusLabel.Name = "Status"
	statusLabel.Size = UDim2.new(1, 0, 0.18, 0)
	statusLabel.Position = UDim2.new(0, 0, 0.78, 0)
	statusLabel.BackgroundTransparency = 1
	statusLabel.Text = "⏳ Initializing..."
	statusLabel.TextColor3 = Color3.fromRGB(255, 220, 100)
	statusLabel.TextScaled = true
	statusLabel.Font = Enum.Font.GothamBold
	statusLabel.Parent = mainFrame
	
	-- Also create sign on front side (for people outside looking in)
	local signGui2 = signGui:Clone()
	signGui2.Face = Enum.NormalId.Front
	signGui2.Parent = signPart
	
	-- Store reference to sign for updates
	self._chuteStatusSign = signPart
	
	return {
		folder = chuteFolder,
		spawnPoint = spawnPoint,
		dropPosition = dropPosition,
		statusSign = signPart,
	}
end

function HubService:SpawnPackageFromChute(chuteData)
	if not chuteData then return nil end
	
	local CollectionService = game:GetService("CollectionService")
	
	-- Random size like PackagePlatformService
	local sizeX = 2 + math.random() * 2  -- 2-4
	local sizeY = 2 + math.random() * 2  -- 2-4
	local sizeZ = 2 + math.random() * 2  -- 2-4
	
	-- Create model like PackagePlatformService
	local packageModel = Instance.new("Model")
	packageModel.Name = "Package_" .. math.random(1000, 9999)
	
	-- Create the main package part
	local packagePart = Instance.new("Part")
	packagePart.Name = "PackagePart"
	packagePart.Shape = Enum.PartType.Block
	packagePart.Size = Vector3.new(sizeX, sizeY, sizeZ)
	
	-- Random position offset
	local spawnPos = chuteData.spawnPoint + Vector3.new(
		(math.random() - 0.5) * 2,  -- Small random X offset
		0,
		(math.random() - 0.5) * 2   -- Small random Z offset
	)
	
	-- Random rotation so packages don't stack neatly
	local randomRotX = math.rad(math.random(-45, 45))
	local randomRotY = math.rad(math.random(0, 360))
	local randomRotZ = math.rad(math.random(-45, 45))
	packagePart.CFrame = CFrame.new(spawnPos) * CFrame.Angles(randomRotX, randomRotY, randomRotZ)
	
	packagePart.Color = CONFIG.PackageColors[math.random(1, #CONFIG.PackageColors)]
	packagePart.Material = Enum.Material.SmoothPlastic
	packagePart.Anchored = false
	packagePart.CanCollide = true
	packagePart.Parent = packageModel
	
	-- Set as primary part
	packageModel.PrimaryPart = packagePart
	
	-- Assign random kudos value to package (done early so prompt can use it)
	local kudosValue = math.random(CONFIG.PackageKudosMin, CONFIG.PackageKudosMax)
	packageModel:SetAttribute("KudosValue", kudosValue)
	
	-- Add ProximityPrompt for pickup
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "PickupPrompt"
	prompt.ActionText = "Pick Up"
	prompt.ObjectText = "Package (⭐" .. kudosValue .. ")"
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 8
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.RequiresLineOfSight = false
	prompt.Parent = packagePart
	
	-- Add tag so PackagePlatformService can handle pickup
	CollectionService:AddTag(packageModel, "spawnedPackage")
	
	-- Add tape stripe on top
	local tape = Instance.new("Part")
	tape.Name = "Tape"
	tape.Size = Vector3.new(sizeX * 0.7, 0.1, 1.5)
	tape.Color = Color3.fromRGB(200, 180, 140)
	tape.Material = Enum.Material.SmoothPlastic
	tape.Anchored = false
	tape.CanCollide = false
	tape.Position = packagePart.Position + Vector3.new(0, sizeY / 2 + 0.05, 0)
	tape.Parent = packageModel
	
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = packagePart
	weld.Part1 = tape
	weld.Parent = tape
	
	-- Create BillboardGui to display kudos value
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "KudosBillboard"
	billboard.Size = UDim2.new(0, 80, 0, 40)
	billboard.StudsOffset = Vector3.new(0, sizeY / 2 + 2, 0)  -- Float above package
	billboard.AlwaysOnTop = false
	billboard.MaxDistance = 50
	billboard.Parent = packagePart
	
	-- Background frame
	local bgFrame = Instance.new("Frame")
	bgFrame.Name = "Background"
	bgFrame.Size = UDim2.new(1, 0, 1, 0)
	bgFrame.BackgroundColor3 = Color3.fromRGB(30, 30, 40)
	bgFrame.BackgroundTransparency = 0.3
	bgFrame.BorderSizePixel = 0
	bgFrame.Parent = billboard
	
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.2, 0)
	corner.Parent = bgFrame
	
	-- Kudos icon/text
	local kudosLabel = Instance.new("TextLabel")
	kudosLabel.Name = "KudosLabel"
	kudosLabel.Size = UDim2.new(1, 0, 1, 0)
	kudosLabel.BackgroundTransparency = 1
	kudosLabel.Text = "⭐ " .. kudosValue
	kudosLabel.TextColor3 = Color3.fromRGB(255, 215, 0)  -- Gold color
	kudosLabel.TextScaled = true
	kudosLabel.Font = Enum.Font.GothamBold
	kudosLabel.Parent = bgFrame
	
	-- Add stroke for visibility
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(0, 0, 0)
	stroke.Thickness = 2
	stroke.Parent = kudosLabel
	
	-- Parent model to SpawnedPackages folder
	local packagesFolder = Workspace:FindFirstChild("SpawnedPackages")
	if not packagesFolder then
		packagesFolder = Instance.new("Folder")
		packagesFolder.Name = "SpawnedPackages"
		packagesFolder.Parent = Workspace
	end
	packageModel.Parent = packagesFolder
	
	-- Mark as chute package
	packageModel:SetAttribute("ChutePackage", true)
	
	-- Anchor package once it has settled (velocity near zero)
	task.spawn(function()
		local settleThreshold = 0.5  -- Velocity magnitude threshold
		local settleTime = 0.5  -- Time (seconds) velocity must be low
		local lowVelocityStart = nil
		
		while packageModel and packageModel.Parent and packagePart and packagePart.Parent do
			task.wait(0.1)
			
			-- Don't anchor if being held by player
			local heldBy = packageModel:GetAttribute("HeldByPlayer")
			if heldBy then
				lowVelocityStart = nil
				break  -- Stop monitoring if picked up
			end
			
			-- Check velocity
			local velocity = packagePart.AssemblyLinearVelocity
			if velocity.Magnitude < settleThreshold then
				if not lowVelocityStart then
					lowVelocityStart = tick()
				elseif tick() - lowVelocityStart >= settleTime then
					-- Package has settled - anchor it
					packagePart.Anchored = true
					-- Also anchor tape if it exists
					local tapePart = packageModel:FindFirstChild("Tape")
					if tapePart then
						tapePart.Anchored = true
					end
					break
				end
			else
				-- Reset timer if moving again
				lowVelocityStart = nil
			end
		end
	end)
	
	return packageModel
end

-- Update the chute status sign display
function HubService:UpdateChuteStatusSign()
	if not self._chuteStatusSign then return end
	
	local gui = self._chuteStatusSign:FindFirstChild("StatusGui")
	if not gui then return end
	
	local mainFrame = gui:FindFirstChild("MainFrame")
	if not mainFrame then return end
	
	local activeCount = #self._packageStats.activePackages
	local spawnedCount = self._packageStats.totalSpawned
	local collectedCount = self._packageStats.totalCollected
	
	-- Update labels
	local activeLabel = mainFrame:FindFirstChild("ActiveCount")
	if activeLabel then
		activeLabel.Text = string.format("Available: %d", activeCount)
		-- Color based on count
		if activeCount == 0 then
			activeLabel.TextColor3 = Color3.fromRGB(255, 100, 100)
		elseif activeCount < 10 then
			activeLabel.TextColor3 = Color3.fromRGB(255, 200, 100)
		else
			activeLabel.TextColor3 = Color3.fromRGB(100, 255, 150)
		end
	end
	
	local spawnedLabel = mainFrame:FindFirstChild("SpawnedCount")
	if spawnedLabel then
		spawnedLabel.Text = string.format("Total Spawned: %d", spawnedCount)
	end
	
	local collectedLabel = mainFrame:FindFirstChild("CollectedCount")
	if collectedLabel then
		collectedLabel.Text = string.format("Delivered: %d ⭐", collectedCount)
	end
	
	local statusLabel = mainFrame:FindFirstChild("Status")
	if statusLabel then
		if activeCount < CONFIG.PackageTargetActive then
			statusLabel.Text = "📦 SPAWNING..."
			statusLabel.TextColor3 = Color3.fromRGB(100, 200, 255)
		else
			statusLabel.Text = "✓ READY"
			statusLabel.TextColor3 = Color3.fromRGB(0, 255, 150)
		end
	end
	
	-- Also update the second GUI (front side)
	for _, child in ipairs(self._chuteStatusSign:GetChildren()) do
		if child:IsA("SurfaceGui") and child.Face == Enum.NormalId.Front then
			local frame2 = child:FindFirstChild("MainFrame")
			if frame2 then
				local al2 = frame2:FindFirstChild("ActiveCount")
				if al2 and activeLabel then al2.Text = activeLabel.Text; al2.TextColor3 = activeLabel.TextColor3 end
				local sl2 = frame2:FindFirstChild("SpawnedCount")
				if sl2 and spawnedLabel then sl2.Text = spawnedLabel.Text end
				local cl2 = frame2:FindFirstChild("CollectedCount")
				if cl2 and collectedLabel then cl2.Text = collectedLabel.Text end
				local st2 = frame2:FindFirstChild("Status")
				if st2 and statusLabel then st2.Text = statusLabel.Text; st2.TextColor3 = statusLabel.TextColor3 end
			end
		end
	end
end

-- Track when a package is collected/delivered
function HubService:OnPackageCollected(packageModel)
	-- Remove from active list
	for i, pkg in ipairs(self._packageStats.activePackages) do
		if pkg == packageModel then
			table.remove(self._packageStats.activePackages, i)
			break
		end
	end
	
	self._packageStats.totalCollected = self._packageStats.totalCollected + 1
	self:UpdateChuteStatusSign()
end

function HubService:StartPackageChute()
	if not CONFIG.PackageChuteEnabled then return end
	
	-- Find the warehouse floor inside the ShippingCenter model
	local shippingCenter = self._hubFolder:FindFirstChild("ShippingCenter")
	if not shippingCenter then
		warn("[HubService] No ShippingCenter model found for package chute")
		return
	end
	
	local warehouseFloor = shippingCenter:FindFirstChild("WarehouseFloor")
	if not warehouseFloor then
		warn("[HubService] No warehouse floor found for package chute")
		return
	end
	
	local platformPos = warehouseFloor.Position
	local platformSize = warehouseFloor.Size
	local platformTopY = platformPos.Y + platformSize.Y / 2
	local ceilingY = platformTopY + CONFIG.ShippingCenterWallHeight
	
	-- Drop position is center of the room, on the floor
	local dropPosition = Vector3.new(platformPos.X, platformTopY, platformPos.Z)
	
	-- Create the chute
	local chuteData = self:CreatePackageChute(ceilingY, dropPosition)
	
	if not chuteData then
		warn("[HubService] Failed to create package chute")
		return
	end
	
	self._chuteData = chuteData
	
	-- Reset package stats
	self._packageStats = {
		totalSpawned = 0,
		totalCollected = 0,
		activePackages = {},
	}
	
	print("[HubService] Package chute created!")
	self:UpdateChuteStatusSign()
	
	-- Spawn initial batch of packages
	task.spawn(function()
		print(string.format("[HubService] Spawning initial %d packages...", CONFIG.PackageInitialSpawn))
		
		for i = 1, CONFIG.PackageInitialSpawn do
			if not self._chuteData then break end
			
			local pkg = self:SpawnPackageFromChute(chuteData)
			if pkg then
				table.insert(self._packageStats.activePackages, pkg)
				self._packageStats.totalSpawned = self._packageStats.totalSpawned + 1
				self:UpdateChuteStatusSign()
			end
			
			task.wait(0.3)  -- Quick burst spawn for initial batch
		end
		
		print(string.format("[HubService] Initial spawn complete: %d packages", #self._packageStats.activePackages))
		self:UpdateChuteStatusSign()
	end)
	
	-- Spawn replacement packages when some are collected
	task.spawn(function()
		task.wait(CONFIG.PackageInitialSpawn * 0.3 + 1)  -- Wait for initial spawn
		
		while self._chuteData do
			-- Clean up any destroyed packages from tracking
			for i = #self._packageStats.activePackages, 1, -1 do
				local pkg = self._packageStats.activePackages[i]
				if not pkg or not pkg.Parent then
					table.remove(self._packageStats.activePackages, i)
				end
			end
			
			local activeCount = #self._packageStats.activePackages
			local needsMore = activeCount < CONFIG.PackageTargetActive
			
			-- Spawn more if we need them (no max limit)
			if needsMore then
				local pkg = self:SpawnPackageFromChute(chuteData)
				if pkg then
					table.insert(self._packageStats.activePackages, pkg)
					self._packageStats.totalSpawned = self._packageStats.totalSpawned + 1
					self:UpdateChuteStatusSign()
				end
			end
			
			self:UpdateChuteStatusSign()
			task.wait(CONFIG.PackageSpawnInterval)
		end
	end)
	
	print("[HubService] Package chute system started!")
end

function HubService:StopPackageChute()
	self._chuteData = nil
	
	-- Clean up chute folder
	local chuteFolder = self._hubFolder:FindFirstChild("PackageChute")
	if chuteFolder then
		chuteFolder:Destroy()
	end
	
	print("[HubService] Package chute stopped")
end

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         PUBLIC API                                          ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

function HubService:GetSpawnLocation()
	return self._spawnLocation
end

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         KUDOS SYSTEM                                        ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

-- Award kudos to a player
function HubService:AwardKudos(player, amount, worldPosition)
	if not player or amount <= 0 then return end
	
	-- Initialize kudos for player if not exists
	if not self._playerKudos[player] then
		self._playerKudos[player] = 0
	end
	
	-- Add kudos
	self._playerKudos[player] = self._playerKudos[player] + amount
	
	-- Update replica if exists
	local replica = self._kudosReplicas[player]
	if replica then
		replica:SetValue("Kudos", self._playerKudos[player])
		replica:SetValue("LastAward", amount)
		replica:SetValue("LastAwardTime", tick())
	end
	
	-- Fire client signal for flying kudos effect
	self.Client.KudosEarned:Fire(player, amount, worldPosition)
	
	print(string.format("[HubService] Awarded %d kudos to %s (total: %d)", 
		amount, player.Name, self._playerKudos[player]))
end

-- Get player's total kudos
function HubService:GetPlayerKudos(player)
	return self._playerKudos[player] or 0
end

-- Spend kudos (deduct from player's total) - returns true if successful
function HubService:SpendKudos(player, amount)
	if not player or amount <= 0 then return false end
	
	local currentKudos = self._playerKudos[player] or 0
	
	-- Check if player has enough kudos
	if currentKudos < amount then
		return false
	end
	
	-- Deduct kudos
	self._playerKudos[player] = currentKudos - amount
	
	-- Update replica if exists
	local replica = self._kudosReplicas[player]
	if replica then
		replica:SetValue("Kudos", self._playerKudos[player])
	end
	
	print(string.format("[HubService] %s spent %d kudos (remaining: %d)", 
		player.Name, amount, self._playerKudos[player]))
	
	return true
end

-- Setup kudos tracking for a player (called when player joins)
function HubService:SetupPlayerKudos(player)
	-- Initialize kudos (players start with 50)
	local startingKudos = 50
	self._playerKudos[player] = startingKudos
	
	-- Create a replica for this player's kudos (ReplicaService already required at top of file)
	local replica = ReplicaService.NewReplica({
		ClassToken = ReplicaService.NewClassToken("PlayerKudos_" .. player.UserId),
		Data = {
			Kudos = startingKudos,
			LastAward = 0,
			LastAwardTime = 0,
		},
		Replication = player,  -- Only replicate to this player
	})
	
	self._kudosReplicas[player] = replica
	print(string.format("[HubService] Kudos replica created for %s (starting with %d kudos)", player.Name, startingKudos))
end

-- Cleanup kudos when player leaves
function HubService:CleanupPlayerKudos(player)
	-- Destroy replica
	local replica = self._kudosReplicas[player]
	if replica then
		replica:Destroy()
		self._kudosReplicas[player] = nil
	end
	
	-- Clean up kudos data
	self._playerKudos[player] = nil
	
	print(string.format("[HubService] Kudos cleaned up for %s", player.Name))
end

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                   PACKAGE COLLECTION SYSTEM                                 ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

function HubService:SetupPackageCollection(collectionZone)
	if not collectionZone then return end
	print("[HubService] Setting up package collection zone...")
	
	local collectedPackages = {}
	local CollectionService = game:GetService("CollectionService")
	local TweenService = game:GetService("TweenService")
	
	local collectionEvent = Instance.new("RemoteEvent")
	collectionEvent.Name = "PackageCollectedEvent"
	collectionEvent.Parent = ReplicatedStorage
	
	-- Get reference to PackagePlatformService for dropping packages
	local Knit = require(game:GetService("ReplicatedStorage").Packages.Knit)
	local PackagePlatformService = nil
	task.spawn(function()
		PackagePlatformService = Knit.GetService("PackagePlatformService")
	end)
	
	-- Find status display elements in the end shipping model
	local endShippingModel = collectionZone.Parent
	local counterPanel = endShippingModel:FindFirstChild("CounterPanel")
	local centralGlow = endShippingModel:FindFirstChild("CentralGlow")
	local holoRing = endShippingModel:FindFirstChild("HoloRing")
	local holoRingInner = endShippingModel:FindFirstChild("HoloRingInner")
	
	-- Helper to update status display
	local function updateStatusDisplay(status, color)
		if not counterPanel then return end
		
		for _, gui in ipairs(counterPanel:GetChildren()) do
			if gui:IsA("SurfaceGui") then
				local frame = gui:FindFirstChildWhichIsA("Frame")
				if frame then
					local statusLabel = frame:FindFirstChild("Status")
					if statusLabel then
						statusLabel.Text = status
						statusLabel.TextColor3 = color or Color3.fromRGB(0, 255, 150)
					end
				end
			end
		end
	end
	
	-- Helper to pulse the central glow
	local function pulseGlow()
		if centralGlow then
			local originalTransparency = centralGlow.Transparency
			TweenService:Create(centralGlow, TweenInfo.new(0.15, Enum.EasingStyle.Quad), {
				Transparency = 0,
			}):Play()
			task.wait(0.15)
			TweenService:Create(centralGlow, TweenInfo.new(0.3, Enum.EasingStyle.Quad), {
				Transparency = originalTransparency,
			}):Play()
		end
	end
	
	local function collectPackage(packageModel, player)
		if collectedPackages[packageModel] then return end
		collectedPackages[packageModel] = true
		
		local kudosValue = packageModel:GetAttribute("KudosValue") or 10
		if player then
			self:AwardKudos(player, kudosValue)
			collectionEvent:FireClient(player, {kudosAwarded = kudosValue})
		end
		
		-- Track collection for spawn replacement
		self:OnPackageCollected(packageModel)
		
		task.spawn(function()
			local packagePart = packageModel.PrimaryPart or packageModel:FindFirstChildWhichIsA("BasePart")
			if packagePart then
				local targetPos = collectionZone.Position - Vector3.new(0, 3, 0)
				packageModel:SetAttribute("HeldByPlayer", nil)
				for _, part in ipairs(packageModel:GetDescendants()) do
					if part:IsA("BasePart") then
						part.Anchored = true
						part.CanCollide = false
						TweenService:Create(part, TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.In), {
							Position = targetPos, Transparency = 1, Size = part.Size * 0.1,
						}):Play()
					end
				end
				task.wait(0.6)
			end
			packageModel:Destroy()
			pulseGlow()
		end)
	end
	
	-- Create deposit prompt
	local depositPrompt = Instance.new("ProximityPrompt")
	depositPrompt.Name = "DepositPrompt"
	depositPrompt.ActionText = "Deliver"
	depositPrompt.ObjectText = "📦 Delivery Terminal"
	depositPrompt.HoldDuration = 0.5
	depositPrompt.MaxActivationDistance = 15
	depositPrompt.RequiresLineOfSight = false
	depositPrompt.KeyboardKeyCode = Enum.KeyCode.E
	depositPrompt.Parent = collectionZone
	
	-- Track depositing state
	local depositingPlayers = {}
	
	-- Cleanup function for when player leaves or dies during collection
	local function cleanupDeposit(player)
		if depositingPlayers[player.UserId] then
			depositingPlayers[player.UserId] = nil
			depositPrompt.Enabled = true
			print("[HubService] Deposit cleanup for " .. player.Name)
		end
	end
	
	-- Listen for player leaving
	Players.PlayerRemoving:Connect(cleanupDeposit)
	
	-- Listen for character dying during collection
	for _, player in ipairs(Players:GetPlayers()) do
		player.CharacterAdded:Connect(function()
			cleanupDeposit(player)
		end)
	end
	Players.PlayerAdded:Connect(function(player)
		player.CharacterAdded:Connect(function()
			cleanupDeposit(player)
		end)
	end)
	
	-- Helper to freeze/unfreeze player movement
	local function setPlayerFrozen(player, frozen)
		local character = player.Character
		if not character then return end
		
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		local rootPart = character:FindFirstChild("HumanoidRootPart")
		
		if frozen then
			-- Freeze the player
			if humanoid then
				humanoid.WalkSpeed = 0
				humanoid.JumpPower = 0
				humanoid.JumpHeight = 0
			end
			if rootPart then
				rootPart.Anchored = true
			end
		else
			-- Unfreeze the player
			if humanoid then
				humanoid.WalkSpeed = 16  -- Default walk speed
				humanoid.JumpPower = 50  -- Default jump power
				humanoid.JumpHeight = 7.2  -- Default jump height
			end
			if rootPart then
				rootPart.Anchored = false
			end
		end
		
		-- Notify client about freeze state
		collectionEvent:FireClient(player, {
			frozen = frozen,
		})
	end
	
	depositPrompt.Triggered:Connect(function(player)
		if not PackagePlatformService then
			warn("[HubService] PackagePlatformService not available yet!")
			return
		end
		
		if depositingPlayers[player.UserId] then
			return
		end
		
		local playerStack = PackagePlatformService:GetHeldPackages(player)
		if not playerStack or #playerStack == 0 then
			updateStatusDisplay("⚠ NO PACKAGES", Color3.fromRGB(255, 200, 100))
			task.delay(1.5, function()
				updateStatusDisplay("✓ READY", Color3.fromRGB(0, 255, 150))
			end)
			return
		end
		
		depositingPlayers[player.UserId] = true
		
		-- Disable prompt and freeze player during collection
		depositPrompt.Enabled = false
		setPlayerFrozen(player, true)
		
		local packageCount = #playerStack
		print(string.format("[HubService] Player %s depositing %d packages", player.Name, packageCount))
		
		-- Update status to processing
		updateStatusDisplay("⏳ SCANNING...", Color3.fromRGB(255, 220, 100))
		
		-- Spin up the holo rings
		if holoRing then
			task.spawn(function()
				while depositingPlayers[player.UserId] do
					holoRing.CFrame = holoRing.CFrame * CFrame.Angles(0, math.rad(2), 0)
					if holoRingInner then
						holoRingInner.CFrame = holoRingInner.CFrame * CFrame.Angles(0, math.rad(-3), 0)
					end
					task.wait()
				end
			end)
		end
		
		task.spawn(function()
			local baseKudos = 0        -- Sum of package values
			local totalKudos = 0       -- Final amount with bonuses
			local processedCount = 0
			local flatBonus = 0        -- Flat bonus per package
			local stackBonus = 0       -- Percentage-based stack bonus
			
			-- Initial scan delay
			task.wait(0.5)
			
			while true do
				local currentStack = PackagePlatformService:GetHeldPackages(player)
				if not currentStack or #currentStack == 0 then
					break
				end
				
				local topPackage = currentStack[#currentStack]
				if not topPackage then break end
				
				local kudosValue = topPackage:GetAttribute("KudosValue") or 10
				collectedPackages[topPackage] = true
				
				-- Update status with progress
				processedCount = processedCount + 1
				updateStatusDisplay(
					string.format("📦 %d/%d  +⭐%d", processedCount, packageCount, kudosValue),
					Color3.fromRGB(0, 220, 180)
				)
				
				PackagePlatformService:DropTopPackage(player)
				
				local packagePart = topPackage.PrimaryPart or topPackage:FindFirstChildWhichIsA("BasePart")
				if packagePart then
					local startPos = packagePart.Position
					local scanPos = collectionZone.Position + Vector3.new(0, 2, 0)
					local targetPos = collectionZone.Position - Vector3.new(0, 1, 0)
					
					-- Anchor all parts
					for _, part in ipairs(topPackage:GetDescendants()) do
						if part:IsA("BasePart") then
							part.Anchored = true
							part.CanCollide = false
						end
					end
					
					-- Phase 1: Float to scan position (above terminal)
					TweenService:Create(packagePart, TweenInfo.new(0.4, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {
						Position = scanPos,
					}):Play()
					
					local tape = topPackage:FindFirstChild("Tape")
					if tape then
						TweenService:Create(tape, TweenInfo.new(0.4, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {
							Position = scanPos,
						}):Play()
					end
					
					task.wait(0.4)
					
					-- Phase 2: Brief hover (scanning)
					task.wait(0.2)
					
					-- Phase 3: Drop into terminal with shrink
					for _, part in ipairs(topPackage:GetDescendants()) do
						if part:IsA("BasePart") then
							TweenService:Create(part, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.In), {
								Position = targetPos,
								Size = part.Size * 0.15,
								Transparency = 0.8,
							}):Play()
						end
					end
					
					task.wait(0.35)
					
					-- Pulse effect
					pulseGlow()
				end
				
				-- Add base kudos value (from package)
				baseKudos = baseKudos + kudosValue
				
				-- Add flat delivery bonus per package
				flatBonus = flatBonus + CONFIG.DeliveryBonusPerPackage
				
				-- Award the package value + flat bonus immediately
				local immediateAward = kudosValue + CONFIG.DeliveryBonusPerPackage
				self:AwardKudos(player, immediateAward, collectionZone.Position + Vector3.new(0, 3, 0))
				
				collectionEvent:FireClient(player, {
					kudosAwarded = immediateAward,
					totalKudos = baseKudos + flatBonus,
					processedCount = processedCount,
					totalCount = packageCount,
					isComplete = false,
				})
				
				-- Track collection for spawn replacement
				self:OnPackageCollected(topPackage)
				
				topPackage:Destroy()
				
				-- Small delay between packages
				task.wait(0.15)
			end
			
			-- Calculate stack bonus based on total packages delivered
			local stackBonusPercent = 0
			for _, threshold in ipairs(CONFIG.StackBonusThresholds) do
				if processedCount >= threshold.minStack then
					stackBonusPercent = threshold.bonusPercent
				end
			end
			
			-- Calculate and award stack bonus
			if stackBonusPercent > 0 then
				stackBonus = math.floor(baseKudos * stackBonusPercent / 100)
				if stackBonus > 0 then
					self:AwardKudos(player, stackBonus, collectionZone.Position + Vector3.new(0, 5, 0))
				end
			end
			
			-- Calculate final total
			totalKudos = baseKudos + flatBonus + stackBonus
			
			-- Complete!
			depositingPlayers[player.UserId] = nil
			
			-- Unfreeze player and re-enable prompt
			setPlayerFrozen(player, false)
			depositPrompt.Enabled = true
			
			-- Show completion status with breakdown
			local bonusText = ""
			if stackBonusPercent > 0 then
				bonusText = string.format(" (+%d%% BONUS!)", stackBonusPercent)
			end
			updateStatusDisplay(
				string.format("✓ +⭐%d%s", totalKudos, bonusText),
				Color3.fromRGB(100, 255, 150)
			)
			
			-- Fire final completion event
			collectionEvent:FireClient(player, {
				kudosAwarded = stackBonus,
				totalKudos = totalKudos,
				processedCount = processedCount,
				totalCount = packageCount,
				isComplete = true,
				stackBonusPercent = stackBonusPercent,
				stackBonus = stackBonus,
				flatBonus = flatBonus,
				baseKudos = baseKudos,
			})
			
			-- Reset to ready after delay
			task.delay(2, function()
				updateStatusDisplay("✓ READY", Color3.fromRGB(0, 255, 150))
			end)
			
			print(string.format("[HubService] Player %s delivered %d packages: Base=%d + Flat=%d + Stack=%d (%d%%) = %d total kudos", 
				player.Name, processedCount, baseKudos, flatBonus, stackBonus, stackBonusPercent, totalKudos))
		end)
	end)
	
	-- Also handle packages that physically touch the zone (dropped packages)
	collectionZone.Touched:Connect(function(hit)
		local packageModel = hit:FindFirstAncestorOfClass("Model")
		if not packageModel or not CollectionService:HasTag(packageModel, "spawnedPackage") then return end
		if collectedPackages[packageModel] then return end
		
		-- Only collect if NOT held by a player (loose packages)
		local holderId = packageModel:GetAttribute("HeldByPlayer")
		if holderId then return end  -- Skip held packages - use deposit prompt instead
		
		collectPackage(packageModel, nil)
	end)
	
	print("[HubService] Package collection zone setup complete!")
end

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         KNIT LIFECYCLE                                      ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

function HubService:KnitInit()
	print("[HubService] Initializing...")
	
	-- Create RemoteEvent for gate collection feedback
	local gateCollectedEvent = Instance.new("RemoteEvent")
	gateCollectedEvent.Name = "GateCollectedEvent"
	gateCollectedEvent.Parent = ReplicatedStorage
	
	-- Setup kudos for players that join
	Players.PlayerAdded:Connect(function(player)
		self:SetupPlayerKudos(player)
	end)
	
	-- Cleanup when players leave
	Players.PlayerRemoving:Connect(function(player)
		self:CleanupPlayerKudos(player)
	end)
	
	-- Setup for any players already in game
	for _, player in ipairs(Players:GetPlayers()) do
		self:SetupPlayerKudos(player)
	end
end

function HubService:KnitStart()
	print("[HubService] Started")
	
	-- Remove baseplate
	local baseplate = Workspace:FindFirstChild("Baseplate")
	if baseplate then
		baseplate:Destroy()
		print("[HubService] Baseplate removed")
	end
	
	-- Create the hub
	task.spawn(function()
		task.wait(0.5)
		
		self:CreateHub()
		
		
		-- Remove any buildings that collide with track or each other
		removeCollidingBuildings(self._hubFolder)
		
		-- Start package chute system (drops packages from ceiling)
		self:StartPackageChute()
		
		print("[HubService] Hub ready!")
	end)
end

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         CLIENT API                                          ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

-- Get current crystal particle settings
function HubService.Client:GetCrystalParticleSettings(player)
	return CONFIG.CrystalParticles
end

-- Update crystal particle settings (from Iris GUI)
function HubService.Client:UpdateCrystalParticleSettings(player, settings)
	-- Validate and apply settings
	if settings.BurstSize then
		CONFIG.CrystalParticles.BurstSize = math.clamp(settings.BurstSize, 1, 20)
	end
	if settings.BurstLifetimeMin then
		CONFIG.CrystalParticles.BurstLifetimeMin = math.clamp(settings.BurstLifetimeMin, 0.1, 10)
	end
	if settings.BurstLifetimeMax then
		CONFIG.CrystalParticles.BurstLifetimeMax = math.clamp(settings.BurstLifetimeMax, 0.1, 10)
	end
	if settings.BurstSpeed then
		CONFIG.CrystalParticles.BurstSpeed = math.clamp(settings.BurstSpeed, 5, 200)
	end
	if settings.BurstCount then
		CONFIG.CrystalParticles.BurstCount = math.clamp(math.floor(settings.BurstCount), 1, 100)
	end
	if settings.BurstGravity then
		CONFIG.CrystalParticles.BurstGravity = math.clamp(settings.BurstGravity, -100, 100)
	end
	if settings.BurstDrag then
		CONFIG.CrystalParticles.BurstDrag = math.clamp(settings.BurstDrag, 0, 10)
	end
	if settings.GlowSize then
		CONFIG.CrystalParticles.GlowSize = math.clamp(settings.GlowSize, 1, 30)
	end
	if settings.GlowLifetimeMin then
		CONFIG.CrystalParticles.GlowLifetimeMin = math.clamp(settings.GlowLifetimeMin, 0.1, 10)
	end
	if settings.GlowLifetimeMax then
		CONFIG.CrystalParticles.GlowLifetimeMax = math.clamp(settings.GlowLifetimeMax, 0.1, 10)
	end
	if settings.GlowSpeed then
		CONFIG.CrystalParticles.GlowSpeed = math.clamp(settings.GlowSpeed, 5, 100)
	end
	if settings.GlowCount then
		CONFIG.CrystalParticles.GlowCount = math.clamp(math.floor(settings.GlowCount), 1, 50)
	end
	
	print(string.format("[HubService] %s updated crystal particle settings", player.Name))
	return true
end

-- Get player's current kudos
function HubService.Client:GetKudos(player)
	return HubService:GetPlayerKudos(player)
end

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                    POWERS API (Collection Toggling)                         ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

-- Toggle visibility of a collection for all players
function HubService:ToggleCollection(collectionName, visible)
	local folder = self._collections[collectionName]
	if not folder then
		warn("[HubService] Unknown collection:", collectionName)
		return false
	end
	
	-- Toggle visibility of all descendants
	for _, descendant in ipairs(folder:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.Transparency = visible and (descendant:GetAttribute("OriginalTransparency") or 0) or 1
			descendant.CanCollide = visible
		elseif descendant:IsA("ParticleEmitter") or descendant:IsA("PointLight") then
			descendant.Enabled = visible
		end
	end
	
	print(string.format("[HubService] Collection '%s' visibility set to: %s", collectionName, tostring(visible)))
	return true
end

-- Store original transparency when hiding
function HubService:HideCollection(collectionName, duration)
	local folder = self._collections[collectionName]
	if not folder then return false end
	
	-- Store original transparency values
	for _, descendant in ipairs(folder:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant:SetAttribute("OriginalTransparency", descendant.Transparency)
		end
	end
	
	-- Hide
	self:ToggleCollection(collectionName, false)
	
	-- Auto-restore after duration
	if duration and duration > 0 then
		task.delay(duration, function()
			self:ToggleCollection(collectionName, true)
			print(string.format("[HubService] Collection '%s' restored after %.1fs", collectionName, duration))
		end)
	end
	
	return true
end

-- Get available collections
function HubService.Client:GetCollections(player)
	local collections = {}
	for name, folder in pairs(HubService._collections) do
		if folder then
			local count = 0
			for _, _ in ipairs(folder:GetDescendants()) do
				count = count + 1
			end
			collections[name] = {
				name = name,
				itemCount = count,
			}
		end
	end
	return collections
end

-- Client can request to hide a collection (would be triggered by Developer Product)
function HubService.Client:RequestHideCollection(player, collectionName, duration)
	-- This would normally validate a Developer Product purchase
	-- For now, just execute the hide
	print(string.format("[HubService] %s requested to hide '%s' for %ds", player.Name, collectionName, duration))
	return HubService:HideCollection(collectionName, duration)
end

return HubService

