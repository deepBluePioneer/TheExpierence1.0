--[[
	HubService
	
	Creates a hub area where players spawn on a platform.
	Machines are lined up on the edge, ready to ride down a slide/ramp.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local Knit = require(Packages.Knit)

local HubService = Knit.CreateService {
	Name = "HubService",
	Client = {},
	
	-- References
	_hubFolder = nil,
	_spawnLocation = nil,
	_machines = {},
}

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         CONFIGURATION                                       ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

local CONFIG = {
	-- Hub platform
	PlatformSize = Vector3.new(100, 5, 60),     -- Width, Height, Depth
	PlatformPosition = Vector3.new(0, 50, 0),   -- Elevated platform
	PlatformColor = Color3.fromRGB(80, 80, 90),
	PlatformMaterial = Enum.Material.Concrete,
	
	-- Machine spawn area (edge of platform facing the slide)
	MachineEdgeOffset = 25,                      -- How far from center toward the slide edge
	MachineSpacing = 15,                         -- Space between machines
	MachineHeight = 3,                           -- Height above platform
	MachineFacingAngle = 0,                      -- Facing down the slide (degrees)
	
	-- Wavy Slide
	SlideLength = 500,                           -- How long the slide is (Z direction)
	SlideWidth = 120,                            -- Wide enough for all machines
	SlideBaseDropRate = 0.15,                    -- Base downward slope (height drop per stud)
	SlideColor = Color3.fromRGB(60, 180, 120),   -- Green grass-like
	SlideMaterial = Enum.Material.Grass,
	
	-- Wave parameters for the slide
	SlideWaves = {
		{ Frequency = 0.02, Amplitude = 15, Phase = 0 },      -- Main rolling hills
		{ Frequency = 0.05, Amplitude = 8, Phase = 1.2 },     -- Medium bumps
		{ Frequency = 0.01, Amplitude = 20, Phase = 0.5 },    -- Long gradual waves
	},
	SlideSegmentLength = 8,                      -- Length of each slide segment (smaller = smoother)
	SlideThickness = 4,                          -- Thickness of slide parts
	
	-- Landing area at bottom
	LandingSize = Vector3.new(150, 3, 100),
	LandingColor = Color3.fromRGB(100, 90, 80),
	
	-- Spawn location
	SpawnOffset = Vector3.new(0, 3, -20),        -- Behind the machines
	
	-- Prefabs
	MachinePrefabPath = {"Prefabs", "Machines"},
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
	
	local platformY = CONFIG.PlatformPosition.Y
	
	-- ══════════════════════════════════════════════════════════════════════
	-- MAIN PLATFORM (where players spawn and machines wait)
	-- ══════════════════════════════════════════════════════════════════════
	local platform = createPart(
		"Platform",
		CONFIG.PlatformSize,
		CONFIG.PlatformPosition,
		CONFIG.PlatformColor,
		CONFIG.PlatformMaterial,
		self._hubFolder
	)
	
	-- Add visual detail - back edge trim (where players spawn)
	local backEdgeTrim = createPart(
		"BackEdgeTrim",
		Vector3.new(CONFIG.PlatformSize.X + 4, 2, 4),
		CONFIG.PlatformPosition + Vector3.new(0, CONFIG.PlatformSize.Y/2 + 1, -CONFIG.PlatformSize.Z/2 - 2),
		Color3.fromRGB(60, 60, 70),
		Enum.Material.Metal,
		self._hubFolder
	)
	
	-- ══════════════════════════════════════════════════════════════════════
	-- WAVY SLIDE (procedurally generated rolling hills)
	-- ══════════════════════════════════════════════════════════════════════
	
	-- The slide starts at the platform's front edge
	local platformTopY = platformY + CONFIG.PlatformSize.Y / 2
	local platformFrontZ = CONFIG.PlatformPosition.Z + CONFIG.PlatformSize.Z / 2
	
	-- Calculate the wave offset at Z=0 so we can subtract it (ensures slide starts at platform height)
	local initialWaveOffset = 0
	for _, wave in ipairs(CONFIG.SlideWaves) do
		initialWaveOffset = initialWaveOffset + math.sin(wave.Phase) * wave.Amplitude
	end
	
	-- Height calculation function (combines multiple sine waves)
	local function getSlideHeight(z)
		local relativeZ = z - platformFrontZ  -- Distance from platform
		
		-- Base downward slope starting exactly at platform top
		local height = platformTopY - (relativeZ * CONFIG.SlideBaseDropRate)
		
		-- Add wave contributions (subtract initial offset so it starts at platform height)
		for _, wave in ipairs(CONFIG.SlideWaves) do
			height = height + math.sin(relativeZ * wave.Frequency + wave.Phase) * wave.Amplitude
		end
		
		-- Remove the initial wave offset so first point is exactly at platformTopY
		height = height - initialWaveOffset
		
		return height
	end
	
	-- Create slide folder
	local slideFolder = Instance.new("Folder")
	slideFolder.Name = "WavySlide"
	slideFolder.Parent = self._hubFolder
	
	-- Generate slide segments
	local segmentLength = CONFIG.SlideSegmentLength
	local numSegments = math.ceil(CONFIG.SlideLength / segmentLength)
	local slideEndY = platformTopY
	local slideEndZ = platformFrontZ
	
	for i = 0, numSegments - 1 do
		local z1 = platformFrontZ + i * segmentLength
		local z2 = platformFrontZ + (i + 1) * segmentLength
		local zMid = (z1 + z2) / 2
		
		local y1 = getSlideHeight(z1)
		local y2 = getSlideHeight(z2)
		local yMid = (y1 + y2) / 2
		
		-- Calculate segment angle
		local segmentAngle = math.atan2(y1 - y2, segmentLength)
		local segmentActualLength = math.sqrt(segmentLength^2 + (y1 - y2)^2)
		
		-- Create segment part
		local segment = Instance.new("Part")
		segment.Name = "Segment_" .. i
		segment.Size = Vector3.new(CONFIG.SlideWidth, CONFIG.SlideThickness, segmentActualLength + 0.5) -- Slight overlap
		segment.Color = CONFIG.SlideColor
		segment.Material = CONFIG.SlideMaterial
		segment.Anchored = true
		
		-- Position and rotate segment
		segment.CFrame = CFrame.new(CONFIG.PlatformPosition.X, yMid, zMid)
			* CFrame.Angles(segmentAngle, 0, 0)
		segment.Parent = slideFolder
		
		-- Track the end position
		slideEndY = y2
		slideEndZ = z2
	end
	
	print(string.format("[HubService] Generated %d wavy slide segments", numSegments))
	
	-- Side rails (simplified - just end posts for now)
	local railHeight = 10
	local railOffset = CONFIG.SlideWidth/2 + 2
	
	-- Start rails
	local leftStartRail = createPart(
		"LeftStartRail",
		Vector3.new(4, railHeight, 4),
		Vector3.new(CONFIG.PlatformPosition.X - railOffset, platformTopY + railHeight/2, platformFrontZ),
		Color3.fromRGB(70, 70, 80),
		Enum.Material.Metal,
		self._hubFolder
	)
	
	local rightStartRail = createPart(
		"RightStartRail",
		Vector3.new(4, railHeight, 4),
		Vector3.new(CONFIG.PlatformPosition.X + railOffset, platformTopY + railHeight/2, platformFrontZ),
		Color3.fromRGB(70, 70, 80),
		Enum.Material.Metal,
		self._hubFolder
	)
	
	-- ══════════════════════════════════════════════════════════════════════
	-- LANDING AREA (at the bottom of the slide)
	-- ══════════════════════════════════════════════════════════════════════
	local landing = createPart(
		"Landing",
		CONFIG.LandingSize,
		Vector3.new(CONFIG.PlatformPosition.X, slideEndY - CONFIG.LandingSize.Y/2, slideEndZ + CONFIG.LandingSize.Z/2),
		CONFIG.LandingColor,
		Enum.Material.Slate,
		self._hubFolder
	)
	
	-- ══════════════════════════════════════════════════════════════════════
	-- SPAWN LOCATION
	-- ══════════════════════════════════════════════════════════════════════
	local spawnPos = CONFIG.PlatformPosition + CONFIG.SpawnOffset + Vector3.new(0, CONFIG.PlatformSize.Y/2 + 3, 0)
	
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
	
	print(string.format("[HubService] Hub created! Platform at Y=%.0f, Slide length=%.0f studs", platformY, CONFIG.SlideLength))
	
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
	
	-- Calculate positions along the edge
	local totalWidth = (#prefabs - 1) * CONFIG.MachineSpacing
	local startX = CONFIG.PlatformPosition.X - totalWidth / 2
	local edgeZ = CONFIG.PlatformPosition.Z + CONFIG.MachineEdgeOffset
	local machineY = CONFIG.PlatformPosition.Y + CONFIG.PlatformSize.Y/2 + CONFIG.MachineHeight
	
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
		self:SpawnMachinesOnEdge()
		
		print("[HubService] Hub ready! Players spawn behind machines, ride down the slide!")
	end)
end

return HubService

