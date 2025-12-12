--[[
	HubService
	
	Creates a hub area where players spawn on a platform.
	Machines are lined up on the edge, ready to ride down a slide/ramp.
	Tracks race time for each player using Replica.
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

local HubService = Knit.CreateService {
	Name = "HubService",
	Client = {},
	
	-- References
	_hubFolder = nil,
	_spawnLocation = nil,
	_machines = {},
	_startZone = nil,
	
	-- Player timers: { [player] = { timer = Timer, replica = Replica, startTime = number } }
	_playerTimers = {},
	
	-- Track geometry for building collision avoidance
	-- Each entry: { center = Vector3, halfSize = Vector3 } (axis-aligned bounding box)
	_trackGeometry = {},
}

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         CONFIGURATION                                       ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

local CONFIG = {
	-- Start platform (where players spawn)
	StartPlatformSize = Vector3.new(100, 5, 60),
	StartPlatformPosition = Vector3.new(0, 50, 0),
	PlatformColor = Color3.fromRGB(80, 80, 90),
	PlatformMaterial = Enum.Material.Concrete,
	
	-- Machine spawn area
	MachineEdgeOffset = 25,
	MachineSpacing = 15,
	MachineHeight = 3,
	MachineFacingAngle = 0,
	
	-- Intermediate platform (square, at end of first slide)
	MiddlePlatformSize = 120,                    -- Square size (same width/depth)
	MiddlePlatformHeight = 5,
	MiddlePlatformColor = Color3.fromRGB(90, 85, 100),
	
	-- Wavy Slide settings
	SlideWidth = 120,
	SlideColor = Color3.fromRGB(60, 180, 120),
	SlideMaterial = Enum.Material.Grass,
	SlideSegmentLength = 6,                      -- Smaller = smoother curves
	SlideThickness = 4,
	
	-- Narrow zones (width variation)
	NarrowZoneEnabled = true,                    -- Enable width variation
	NarrowZoneChance = 0.4,                      -- 40% chance a slide has narrow zones
	NarrowZoneMinWidth = 60,                     -- Minimum width at narrowest point
	NarrowZoneTransitionLength = 80,             -- How long it takes to narrow/widen
	NarrowZoneDuration = 100,                    -- How long the narrow section lasts
	NarrowZonesPerSlide = {1, 3},                -- Min/max narrow zones per slide
	
	-- Guide Rails
	RailHeight = 8,                              -- How tall the rails are
	RailThickness = 3,                           -- How thick the rails are
	RailColor = Color3.fromRGB(70, 70, 80),      -- Dark metal color
	RailMaterial = Enum.Material.Metal,
	RailSegmentLength = 12,                      -- Shorter segments to follow width changes
	
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
	
	-- Slide colors (picked randomly or in order)
	SlideColors = {
		Color3.fromRGB(60, 180, 120),    -- Green meadow
		Color3.fromRGB(180, 140, 80),    -- Sandy desert
		Color3.fromRGB(100, 160, 200),   -- Icy blue
		Color3.fromRGB(160, 100, 180),   -- Purple twilight
		Color3.fromRGB(200, 80, 80),     -- Red canyon
		Color3.fromRGB(80, 200, 150),    -- Teal lagoon
		Color3.fromRGB(200, 180, 100),   -- Golden
		Color3.fromRGB(150, 100, 80),    -- Rust
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
	
	-- Final landing
	FinalLandingSize = Vector3.new(150, 3, 150),
	FinalLandingColor = Color3.fromRGB(100, 90, 80),
	
	-- Spawn location
	SpawnOffset = Vector3.new(0, 3, -20),
	
	-- Prefabs
	MachinePrefabPath = {"Prefabs", "Machines"},
	
	-- Start Zone (wall at slide entrance)
	StartZoneSize = Vector3.new(120, 20, 5),     -- Wide wall at slide edge
	StartZoneColor = Color3.fromRGB(100, 200, 255),
	StartZoneTransparency = 0.7,
	
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

local function getMachinePrefabs()
	local current = ReplicatedStorage
	for _, pathPart in ipairs(CONFIG.MachinePrefabPath) do
		current = current:FindFirstChild(pathPart)
		if not current then return {} end
	end
	
	local prefabs = {}
	for _, child in ipairs(current:GetChildren()) do
		if child:IsA("Model") then
			table.insert(prefabs, child)
		end
	end
	table.sort(prefabs, function(a, b) return a.Name < b.Name end)
	return prefabs
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
	
	-- Generate guide rails along edges (follow the width variation)
	
	for i = 0, numRailSegments - 1 do
		local d1 = i * railSegmentLength
		local d2 = math.min((i + 1) * railSegmentLength, length)
		local dMid = (d1 + d2) / 2
		
		local y1 = getHeight(d1) + thicknessOffset  -- Top of slide surface
		local y2 = getHeight(d2) + thicknessOffset
		local yMid = (y1 + y2) / 2 + CONFIG.RailHeight / 2  -- Center of rail
		
		-- Get width at this position for rail offset
		local railWidth = getWidth(dMid)
		local railOffset = railWidth / 2 + CONFIG.RailThickness / 2
		
		local actualRailLength = math.sqrt((d2 - d1)^2 + (y1 - y2)^2)
		
		-- Calculate look direction for rails (follows slope)
		local lookDir = forwardVec + Vector3.new(0, (y2 - y1) / math.max(d2 - d1, 0.1), 0)
		if lookDir.Magnitude > 0 then
			lookDir = lookDir.Unit
		else
			lookDir = forwardVec
		end
		
		-- Base position along the slide centerline
		local basePos = Vector3.new(startPos.X, yMid, startPos.Z) + forwardVec * dMid
		
		-- Left rail (offset perpendicular to travel direction)
		local leftPos = basePos - rightVec * railOffset
		local leftRail = Instance.new("Part")
		leftRail.Name = "LeftRail_" .. i
		leftRail.Size = Vector3.new(CONFIG.RailThickness, CONFIG.RailHeight, actualRailLength + 0.5)
		leftRail.Color = CONFIG.RailColor
		leftRail.Material = CONFIG.RailMaterial
		leftRail.Anchored = true
		leftRail.CFrame = CFrame.lookAt(leftPos, leftPos + lookDir) * CFrame.Angles(0, math.pi, 0)
		leftRail.Parent = slideFolder
		
		-- Right rail (offset perpendicular to travel direction)
		local rightPos = basePos + rightVec * railOffset
		local rightRail = Instance.new("Part")
		rightRail.Name = "RightRail_" .. i
		rightRail.Size = Vector3.new(CONFIG.RailThickness, CONFIG.RailHeight, actualRailLength + 0.5)
		rightRail.Color = CONFIG.RailColor
		rightRail.Material = CONFIG.RailMaterial
		rightRail.Anchored = true
		rightRail.CFrame = CFrame.lookAt(rightPos, rightPos + lookDir) * CFrame.Angles(0, math.pi, 0)
		rightRail.Parent = slideFolder
	end
	
	print(string.format("[HubService] Generated %d segments + %d rail segments for %s", numSegments, numRailSegments * 2, name))
	
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
	
	-- Clear track geometry for fresh collision detection
	clearTrackGeometry()
	
	-- ══════════════════════════════════════════════════════════════════════
	-- 1. START PLATFORM (where players spawn and machines wait)
	-- ══════════════════════════════════════════════════════════════════════
	local startPlatform = createPart(
		"StartPlatform",
		CONFIG.StartPlatformSize,
		CONFIG.StartPlatformPosition,
		CONFIG.PlatformColor,
		CONFIG.PlatformMaterial,
		self._hubFolder
	)
	
	local startPlatformTopY = CONFIG.StartPlatformPosition.Y + CONFIG.StartPlatformSize.Y / 2
	local startPlatformFrontZ = CONFIG.StartPlatformPosition.Z + CONFIG.StartPlatformSize.Z / 2
	
	-- Register start platform in track geometry
	addTrackBox(
		CONFIG.StartPlatformPosition.X,
		CONFIG.StartPlatformPosition.Z,
		CONFIG.StartPlatformSize.X / 2,
		CONFIG.StartPlatformSize.Z / 2
	)
	
	-- Start platform rails (on sides without slides - back, left, right)
	local startRailY = startPlatformTopY + CONFIG.RailHeight / 2
	
	-- Back rail
	createPart(
		"StartPlatform_BackRail",
		Vector3.new(CONFIG.StartPlatformSize.X, CONFIG.RailHeight, CONFIG.RailThickness),
		Vector3.new(CONFIG.StartPlatformPosition.X, startRailY, CONFIG.StartPlatformPosition.Z - CONFIG.StartPlatformSize.Z/2),
		CONFIG.RailColor,
		CONFIG.RailMaterial,
		self._hubFolder
	)
	
	-- Left rail
	createPart(
		"StartPlatform_LeftRail",
		Vector3.new(CONFIG.RailThickness, CONFIG.RailHeight, CONFIG.StartPlatformSize.Z),
		Vector3.new(CONFIG.StartPlatformPosition.X - CONFIG.StartPlatformSize.X/2, startRailY, CONFIG.StartPlatformPosition.Z),
		CONFIG.RailColor,
		CONFIG.RailMaterial,
		self._hubFolder
	)
	
	-- Right rail
	createPart(
		"StartPlatform_RightRail",
		Vector3.new(CONFIG.RailThickness, CONFIG.RailHeight, CONFIG.StartPlatformSize.Z),
		Vector3.new(CONFIG.StartPlatformPosition.X + CONFIG.StartPlatformSize.X/2, startRailY, CONFIG.StartPlatformPosition.Z),
		CONFIG.RailColor,
		CONFIG.RailMaterial,
		self._hubFolder
	)
	
	-- ══════════════════════════════════════════════════════════════════════
	-- START ZONE (wall at slide entrance - detects when players leave)
	-- ══════════════════════════════════════════════════════════════════════
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
	
	-- Generate slides with random directions
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
			name = string.format("Slide%d_%s_%s", i, currentDirection, slideType)
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
			
		createPart(
			string.format("Platform%d", i),
			Vector3.new(CONFIG.MiddlePlatformSize, CONFIG.MiddlePlatformHeight, CONFIG.MiddlePlatformSize),
			platformPos,
			platformColor,
			CONFIG.PlatformMaterial,
			self._hubFolder
		)
		
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
		
		-- Check each side and add rail if not connected to a slide
		-- Rail Size is (thickness, height, length) - length runs along local Z axis
		-- So for z+/z- edges (front/back), we need to rotate 90° so rail runs along X
		-- For x+/x- edges (left/right), no rotation needed - rail runs along Z
		local sides = {
			{dir = "z+", offset = Vector3.new(0, 0, halfSize), length = CONFIG.MiddlePlatformSize, rotation = math.pi/2},
			{dir = "z-", offset = Vector3.new(0, 0, -halfSize), length = CONFIG.MiddlePlatformSize, rotation = math.pi/2},
			{dir = "x+", offset = Vector3.new(halfSize, 0, 0), length = CONFIG.MiddlePlatformSize, rotation = 0},
			{dir = "x-", offset = Vector3.new(-halfSize, 0, 0), length = CONFIG.MiddlePlatformSize, rotation = 0},
		}
		
		for _, side in ipairs(sides) do
			-- Add rail if this side is not connected to incoming or outgoing slide
			local isConnected = (side.dir == incomingDir) or (side.dir == getOppositeDirection(incomingDir))
				or (side.dir == outgoingDir) or (side.dir == getOppositeDirection(outgoingDir))
			
			-- Actually, we want rails on sides that DON'T have slides
			-- Incoming slide comes FROM the opposite direction, outgoing goes TO the direction
			local hasIncoming = (getOppositeDirection(side.dir) == incomingDir)
			local hasOutgoing = (side.dir == outgoingDir)
			
			if not hasIncoming and not hasOutgoing then
				local railPos = platformPos + side.offset + Vector3.new(0, CONFIG.MiddlePlatformHeight/2 + CONFIG.RailHeight/2, 0)
				local rail = Instance.new("Part")
				rail.Name = string.format("PlatformRail_%d_%s", i, side.dir)
				rail.Size = Vector3.new(CONFIG.RailThickness, CONFIG.RailHeight, side.length)
				rail.Color = CONFIG.RailColor
				rail.Material = CONFIG.RailMaterial
				rail.Anchored = true
				rail.CFrame = CFrame.new(railPos) * CFrame.Angles(0, side.rotation, 0)
				rail.Parent = self._hubFolder
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
		Enum.Material.Slate,
		self._hubFolder
	)
	
	-- Final landing rails (on sides without the incoming slide)
	local landingTopY = finalLandingPos.Y + CONFIG.FinalLandingSize.Y / 2 + CONFIG.RailHeight / 2
	local landingHalfX = CONFIG.FinalLandingSize.X / 2
	local landingHalfZ = CONFIG.FinalLandingSize.Z / 2
	local incomingFromDir = getOppositeDirection(currentDirection)  -- Where the slide comes from
	
	-- Add rails on sides that don't have the incoming slide
	if incomingFromDir ~= "z-" then
		createPart("FinalLanding_BackRail", 
			Vector3.new(CONFIG.FinalLandingSize.X, CONFIG.RailHeight, CONFIG.RailThickness),
			finalLandingPos + Vector3.new(0, CONFIG.FinalLandingSize.Y/2 + CONFIG.RailHeight/2, -landingHalfZ),
			CONFIG.RailColor, CONFIG.RailMaterial, self._hubFolder)
	end
	if incomingFromDir ~= "z+" then
		createPart("FinalLanding_FrontRail",
			Vector3.new(CONFIG.FinalLandingSize.X, CONFIG.RailHeight, CONFIG.RailThickness),
			finalLandingPos + Vector3.new(0, CONFIG.FinalLandingSize.Y/2 + CONFIG.RailHeight/2, landingHalfZ),
			CONFIG.RailColor, CONFIG.RailMaterial, self._hubFolder)
	end
	if incomingFromDir ~= "x-" then
		createPart("FinalLanding_LeftRail",
			Vector3.new(CONFIG.RailThickness, CONFIG.RailHeight, CONFIG.FinalLandingSize.Z),
			finalLandingPos + Vector3.new(-landingHalfX, CONFIG.FinalLandingSize.Y/2 + CONFIG.RailHeight/2, 0),
			CONFIG.RailColor, CONFIG.RailMaterial, self._hubFolder)
	end
	if incomingFromDir ~= "x+" then
		createPart("FinalLanding_RightRail",
			Vector3.new(CONFIG.RailThickness, CONFIG.RailHeight, CONFIG.FinalLandingSize.Z),
			finalLandingPos + Vector3.new(landingHalfX, CONFIG.FinalLandingSize.Y/2 + CONFIG.RailHeight/2, 0),
			CONFIG.RailColor, CONFIG.RailMaterial, self._hubFolder)
	end
	
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
-- ║                         MACHINE SPAWNING                                    ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

function HubService:SpawnMachinesOnEdge()
	print("[HubService] SpawnMachinesOnEdge called")
	
	-- Clear existing machines
	for _, machine in ipairs(self._machines) do
		if machine and machine.Parent then
			machine:Destroy()
		end
	end
	self._machines = {}
	
	local prefabs = getMachinePrefabs()
	print("[HubService] Found", #prefabs, "machine prefabs")
	
	if #prefabs == 0 then
		warn("[HubService] No machine prefabs found at path:", table.concat(CONFIG.MachinePrefabPath, "."))
		return {}
	end
	
	-- Calculate positions along the edge (facing Slide 1)
	local totalWidth = (#prefabs - 1) * CONFIG.MachineSpacing
	local startX = CONFIG.StartPlatformPosition.X - totalWidth / 2
	local edgeZ = CONFIG.StartPlatformPosition.Z + CONFIG.MachineEdgeOffset
	local machineY = CONFIG.StartPlatformPosition.Y + CONFIG.StartPlatformSize.Y/2 + CONFIG.MachineHeight
	
	-- Create machines folder
	local machinesFolder = self._hubFolder:FindFirstChild("Machines")
	if not machinesFolder then
		machinesFolder = Instance.new("Folder")
		machinesFolder.Name = "Machines"
		machinesFolder.Parent = self._hubFolder
	end
	
	-- Spawn each machine
	for i, prefab in ipairs(prefabs) do
		local xPos = startX + (i - 1) * CONFIG.MachineSpacing
		local position = Vector3.new(xPos, machineY, edgeZ)
		
		local clone = prefab:Clone()
		clone.Name = prefab.Name
		
		-- Position facing down the slide (positive Z)
		local cframe = CFrame.new(position) * CFrame.Angles(0, math.rad(CONFIG.MachineFacingAngle), 0)
		clone:PivotTo(cframe)
		
		clone.Parent = machinesFolder
		table.insert(self._machines, clone)
		
		print(string.format("[HubService] Spawned %s at edge position %d", clone.Name, i))
	end
	
	print(string.format("[HubService] Spawned %d machines on the edge", #self._machines))
	
	return self._machines
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
-- ║                         PUBLIC API                                          ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

function HubService:GetMachines()
	return self._machines
end

function HubService:GetSpawnLocation()
	return self._spawnLocation
end

function HubService:RespawnMachines()
	return self:SpawnMachinesOnEdge()
end

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         KNIT LIFECYCLE                                      ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

function HubService:KnitInit()
	print("[HubService] Initializing...")
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
		
		self:SpawnMachinesOnEdge()
		
		print("[HubService] Hub ready! Players spawn behind machines, ride down the slide!")
	end)
end

return HubService

