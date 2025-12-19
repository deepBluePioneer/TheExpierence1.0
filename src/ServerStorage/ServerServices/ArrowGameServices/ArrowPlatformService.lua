--[[
	ArrowPlatformService
	
	Creates and manages the Arrow Game platform with spawn locations
	and transparent boundaries to keep players contained.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local Knit = require(Packages.Knit)

local ArrowPlatformService = Knit.CreateService({
	Name = "ArrowPlatformService",
	Client = {
		PlatformReady = Knit.CreateSignal(),
	},
})

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                              CONFIGURATION                                  ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

local CONFIG = {
	-- Platform Settings
	PlatformSize = Vector3.new(120, 6, 120),
	PlatformHeight = 50,
	PlatformColor = Color3.fromRGB(20, 20, 30),
	PlatformMaterial = Enum.Material.Neon,
	
	-- Ring Pattern Colors
	RingColors = {
		Color3.fromRGB(255, 80, 120),   -- Pink
		Color3.fromRGB(80, 200, 255),   -- Cyan
		Color3.fromRGB(255, 200, 80),   -- Gold
		Color3.fromRGB(120, 255, 150),  -- Mint
		Color3.fromRGB(180, 100, 255),  -- Purple
	},
	RingSizes = {50, 40, 30, 20, 10},
	
	-- Boundary Settings
	BoundaryHeight = 25,
	BoundaryThickness = 1.5,
	BoundaryTransparency = 1,  -- Fully transparent (invisible)
	BoundaryColor = Color3.fromRGB(150, 220, 255),
	BoundaryMaterial = Enum.Material.Glass,
	BoundaryReflectance = 0,
	
	-- Spawn Settings
	SpawnSize = Vector3.new(8, 1, 8),
	SpawnTransparency = 0.2,
	SpawnMaterial = Enum.Material.Neon,
	SpawnOffsets = {
		{pos = Vector3.new(0, 0, 0), colorIndex = 0},       -- Center (white)
		{pos = Vector3.new(15, 0, 15), colorIndex = 1},     -- Pink
		{pos = Vector3.new(-15, 0, 15), colorIndex = 2},    -- Cyan
		{pos = Vector3.new(15, 0, -15), colorIndex = 3},    -- Gold
		{pos = Vector3.new(-15, 0, -15), colorIndex = 4},   -- Mint
	},
	
	-- Corner Pillar Settings
	PillarPositions = {
		Vector3.new(55, 0, 55),
		Vector3.new(-55, 0, 55),
		Vector3.new(55, 0, -55),
		Vector3.new(-55, 0, -55),
	},
	PillarSize = Vector3.new(4, 15, 4),
	OrbSize = Vector3.new(6, 6, 6),
	LightBrightness = 2,
	LightRange = 25,
}

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                              STATE                                          ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

local platformFolder = nil
local platform = nil
local boundaries = {}
local spawnLocations = {}
local decorations = {}

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         PLATFORM CREATION                                   ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

-- Create the main platform folder structure
function ArrowPlatformService:CreatePlatformFolder()
	-- Clean up existing platform if present
	local existing = Workspace:FindFirstChild("ArrowGamePlatform")
	if existing then
		existing:Destroy()
	end
	
	platformFolder = Instance.new("Folder")
	platformFolder.Name = "ArrowGamePlatform"
	platformFolder.Parent = Workspace
	
	return platformFolder
end

-- Create the main platform baseplate with decorations
function ArrowPlatformService:CreatePlatform()
	local platformPartsFolder = Instance.new("Folder")
	platformPartsFolder.Name = "PlatformParts"
	platformPartsFolder.Parent = platformFolder
	
	-- Base platform
	platform = Instance.new("Part")
	platform.Name = "BasePlatform"
	platform.Size = CONFIG.PlatformSize
	platform.Position = Vector3.new(0, CONFIG.PlatformHeight, 0)
	platform.Anchored = true
	platform.Material = CONFIG.PlatformMaterial
	platform.Color = CONFIG.PlatformColor
	platform.TopSurface = Enum.SurfaceType.Smooth
	platform.BottomSurface = Enum.SurfaceType.Smooth
	platform.Parent = platformPartsFolder
	
	-- Create colorful ring pattern
	for i, size in ipairs(CONFIG.RingSizes) do
		local ring = Instance.new("Part")
		ring.Name = "Ring_" .. i
		ring.Shape = Enum.PartType.Cylinder
		ring.Size = Vector3.new(1, size, size)
		ring.CFrame = CFrame.new(0, CONFIG.PlatformHeight + 3.5, 0) * CFrame.Angles(0, 0, math.rad(90))
		ring.Anchored = true
		ring.CanCollide = false
		ring.Material = Enum.Material.Neon
		ring.Color = CONFIG.RingColors[i]
		ring.Transparency = 0.3
		ring.Parent = platformPartsFolder
		table.insert(decorations, ring)
	end
	
	-- Corner pillars with glowing orbs
	for i, pos in ipairs(CONFIG.PillarPositions) do
		local pillar = Instance.new("Part")
		pillar.Name = "CornerPillar_" .. i
		pillar.Size = CONFIG.PillarSize
		pillar.Position = Vector3.new(pos.X, CONFIG.PlatformHeight + 10, pos.Z)
		pillar.Anchored = true
		pillar.Material = Enum.Material.Neon
		pillar.Color = CONFIG.RingColors[i]
		pillar.Parent = platformPartsFolder
		table.insert(decorations, pillar)
		
		-- Glowing orb on top
		local orb = Instance.new("Part")
		orb.Name = "Orb_" .. i
		orb.Shape = Enum.PartType.Ball
		orb.Size = CONFIG.OrbSize
		orb.Position = Vector3.new(pos.X, CONFIG.PlatformHeight + 20, pos.Z)
		orb.Anchored = true
		orb.CanCollide = false
		orb.Material = Enum.Material.Neon
		orb.Color = CONFIG.RingColors[i]
		orb.Parent = platformPartsFolder
		table.insert(decorations, orb)
		
		-- Add point light
		local light = Instance.new("PointLight")
		light.Color = CONFIG.RingColors[i]
		light.Brightness = CONFIG.LightBrightness
		light.Range = CONFIG.LightRange
		light.Parent = orb
	end
	
	-- Create support structure
	self:CreateSupportStructure(platformPartsFolder)
	
	print("[ArrowPlatform] ✓ Platform created at height:", CONFIG.PlatformHeight)
	return platform
end

-- Create support structure underneath the platform
function ArrowPlatformService:CreateSupportStructure(parentFolder)
	local supportsFolder = Instance.new("Folder")
	supportsFolder.Name = "Supports"
	supportsFolder.Parent = parentFolder
	
	-- Main central support column
	local mainSupport = Instance.new("Part")
	mainSupport.Name = "MainSupport"
	mainSupport.Size = Vector3.new(10, CONFIG.PlatformHeight - 3, 10)
	mainSupport.Position = Vector3.new(0, CONFIG.PlatformHeight / 2 - 1.5, 0)
	mainSupport.Anchored = true
	mainSupport.Material = Enum.Material.DiamondPlate
	mainSupport.Color = Color3.fromRGB(60, 60, 70)
	mainSupport.Parent = supportsFolder
	
	-- Diagonal support beams
	local beamAngles = {45, 135, 225, 315}
	for i, angle in ipairs(beamAngles) do
		local beam = Instance.new("Part")
		beam.Name = "SupportBeam_" .. i
		beam.Size = Vector3.new(3, 60, 3)
		local rad = math.rad(angle)
		local xOff = math.cos(rad) * 30
		local zOff = math.sin(rad) * 30
		beam.CFrame = CFrame.new(xOff / 2, CONFIG.PlatformHeight / 2, zOff / 2) * CFrame.Angles(math.rad(30) * math.cos(rad), 0, math.rad(30) * math.sin(rad))
		beam.Anchored = true
		beam.Material = Enum.Material.DiamondPlate
		beam.Color = Color3.fromRGB(50, 50, 60)
		beam.Parent = supportsFolder
	end
	
	-- Ground base
	local groundBase = Instance.new("Part")
	groundBase.Name = "GroundBase"
	groundBase.Size = Vector3.new(30, 3, 30)
	groundBase.Position = Vector3.new(0, 1.5, 0)
	groundBase.Anchored = true
	groundBase.Material = Enum.Material.Concrete
	groundBase.Color = Color3.fromRGB(80, 80, 90)
	groundBase.Parent = supportsFolder
end

-- Create spawn locations centered on the platform
function ArrowPlatformService:CreateSpawnLocations()
	local spawnsFolder = Instance.new("Folder")
	spawnsFolder.Name = "SpawnLocations"
	spawnsFolder.Parent = platformFolder
	
	local spawnY = CONFIG.PlatformHeight + CONFIG.PlatformSize.Y / 2 + 1
	
	for i, data in ipairs(CONFIG.SpawnOffsets) do
		local spawnColor = data.colorIndex == 0 and Color3.fromRGB(255, 255, 255) or CONFIG.RingColors[data.colorIndex]
		
		local spawn = Instance.new("SpawnLocation")
		spawn.Name = "Spawn_" .. i
		spawn.Size = CONFIG.SpawnSize
		spawn.Position = Vector3.new(data.pos.X, spawnY, data.pos.Z)
		spawn.Anchored = true
		spawn.Material = CONFIG.SpawnMaterial
		spawn.Color = spawnColor
		spawn.Transparency = CONFIG.SpawnTransparency
		spawn.Neutral = true
		spawn.Duration = 0
		spawn.Parent = spawnsFolder
		
		table.insert(spawnLocations, spawn)
		
		-- Decorative ring around spawn
		local spawnRing = Instance.new("Part")
		spawnRing.Name = "SpawnRing_" .. i
		spawnRing.Shape = Enum.PartType.Cylinder
		spawnRing.Size = Vector3.new(0.5, 12, 12)
		spawnRing.CFrame = CFrame.new(data.pos.X, CONFIG.PlatformHeight + 3.5, data.pos.Z) * CFrame.Angles(0, 0, math.rad(90))
		spawnRing.Anchored = true
		spawnRing.CanCollide = false
		spawnRing.Material = Enum.Material.Neon
		spawnRing.Color = spawnColor
		spawnRing.Transparency = 0.5
		spawnRing.Parent = spawnsFolder
		table.insert(decorations, spawnRing)
	end
	
	print("[ArrowPlatform] ✓ SpawnLocations created:", #spawnLocations)
	return spawnLocations
end

-- Create transparent boundary walls
function ArrowPlatformService:CreateBoundaries()
	local boundariesFolder = Instance.new("Folder")
	boundariesFolder.Name = "Boundaries"
	boundariesFolder.Parent = platformFolder
	
	local halfX = CONFIG.PlatformSize.X / 2
	local halfZ = CONFIG.PlatformSize.Z / 2
	local boundaryY = CONFIG.PlatformHeight + CONFIG.BoundaryHeight / 2 + 3
	
	local boundaryData = {
		{
			name = "North",
			size = Vector3.new(CONFIG.PlatformSize.X, CONFIG.BoundaryHeight, CONFIG.BoundaryThickness),
			position = Vector3.new(0, boundaryY, -halfZ),
		},
		{
			name = "South",
			size = Vector3.new(CONFIG.PlatformSize.X, CONFIG.BoundaryHeight, CONFIG.BoundaryThickness),
			position = Vector3.new(0, boundaryY, halfZ),
		},
		{
			name = "East",
			size = Vector3.new(CONFIG.BoundaryThickness, CONFIG.BoundaryHeight, CONFIG.PlatformSize.Z),
			position = Vector3.new(halfX, boundaryY, 0),
		},
		{
			name = "West",
			size = Vector3.new(CONFIG.BoundaryThickness, CONFIG.BoundaryHeight, CONFIG.PlatformSize.Z),
			position = Vector3.new(-halfX, boundaryY, 0),
		},
	}
	
	for _, data in ipairs(boundaryData) do
		local boundary = Instance.new("Part")
		boundary.Name = data.name .. "Boundary"
		boundary.Size = data.size
		boundary.Position = data.position
		boundary.Anchored = true
		boundary.CanCollide = true
		boundary.Transparency = CONFIG.BoundaryTransparency
		boundary.Material = CONFIG.BoundaryMaterial
		boundary.Color = CONFIG.BoundaryColor
		boundary.Reflectance = CONFIG.BoundaryReflectance
		boundary.CastShadow = false
		boundary.Parent = boundariesFolder
		
		table.insert(boundaries, boundary)
	end
	
	print("[ArrowPlatform] ✓ Boundaries created:", #boundaries)
	return boundaries
end

-- Build the entire platform setup
function ArrowPlatformService:BuildPlatform()
	print("[ArrowPlatform] Building platform...")
	
	self:CreatePlatformFolder()
	self:CreatePlatform()
	self:CreateSpawnLocations()
	self:CreateBoundaries()
	
	print("[ArrowPlatform] ✓ Platform build complete!")
	
	-- Notify clients
	self.Client.PlatformReady:FireAll()
	
	return platformFolder
end

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         PUBLIC API                                          ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

function ArrowPlatformService:GetPlatform()
	return platform
end

function ArrowPlatformService:GetPlatformFolder()
	return platformFolder
end

function ArrowPlatformService:GetBoundaries()
	return boundaries
end

function ArrowPlatformService:GetSpawnLocations()
	return spawnLocations
end

function ArrowPlatformService:GetConfig()
	return CONFIG
end

function ArrowPlatformService:UpdateConfig(key: string, value: any)
	if CONFIG[key] ~= nil then
		CONFIG[key] = value
		return true
	end
	return false
end

-- Rebuild the platform with current config
function ArrowPlatformService:RebuildPlatform()
	-- Clear existing references
	boundaries = {}
	spawnLocations = {}
	decorations = {}
	platform = nil
	
	return self:BuildPlatform()
end

-- Destroy the platform
function ArrowPlatformService:DestroyPlatform()
	if platformFolder then
		platformFolder:Destroy()
		platformFolder = nil
		platform = nil
		boundaries = {}
		spawnLocations = {}
		decorations = {}
		print("[ArrowPlatform] Platform destroyed")
		return true
	end
	return false
end

function ArrowPlatformService:GetDecorations()
	return decorations
end

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         CLIENT METHODS                                      ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

function ArrowPlatformService.Client:GetPlatformPosition(player)
	if platform then
		return platform.Position
	end
	return Vector3.new(0, CONFIG.PlatformHeight, 0)
end

function ArrowPlatformService.Client:GetPlatformSize(player)
	return CONFIG.PlatformSize
end

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         KNIT LIFECYCLE                                      ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

function ArrowPlatformService:KnitInit()
	print("[ArrowPlatformService] Initializing...")
end

function ArrowPlatformService:KnitStart()
	print("[ArrowPlatformService] Starting...")
	
	-- Build platform on startup
	task.spawn(function()
		task.wait(1) -- Wait for workspace to be ready
		self:BuildPlatform()
	end)
	
	print("[ArrowPlatformService] Ready")
end

return ArrowPlatformService

