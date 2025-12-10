--[[
	WavyTerrainService
	
	Generates Tiny Wings-style rolling hill terrain using procedural sine waves.
	Creates smooth, colorful hills that the player can slide down and launch off.
	
	Features:
	- Procedural sine wave terrain generation
	- Multiple overlapping frequencies for natural-looking hills
	- Uses Roblox's native Smooth Terrain for buttery-smooth surfaces
	- Chunk-based generation for infinite terrain
	- Terrain coloring via MaterialColors
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local Knit = require(Packages.Knit)

-- Get the Terrain object
local Terrain = Workspace:WaitForChild("Terrain")

local WavyTerrainService = Knit.CreateService {
	Name = "WavyTerrainService",
	Client = {},
	
	-- State
	_isTerrainGenerated = false,
}

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         CONFIGURATION                                       ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

local CONFIG = {
	-- Terrain dimensions
	TerrainWidth = 80,              -- Width in Z-axis (studs) - how wide the track is
	TerrainLength = 2000,           -- Total length of terrain in X-axis (studs)
	TerrainStart = -200,            -- Where terrain starts on X-axis
	StepSize = 4,                   -- How often to sample height (smaller = smoother but slower)
	BaseHeight = 50,                -- Base Y position of terrain (elevated so we can have valleys)
	
	-- Wave parameters for hill generation
	-- Multiple sine waves are combined for natural-looking terrain
	Waves = {
		-- Primary hills (large rolling hills) - the main "Tiny Wings" feel
		{ Frequency = 0.012, Amplitude = 40, Phase = 0 },
		-- Secondary hills (medium variation)
		{ Frequency = 0.028, Amplitude = 20, Phase = 1.5 },
		-- Tertiary detail (gentle bumps)
		{ Frequency = 0.06, Amplitude = 10, Phase = 3.2 },
		-- Micro detail (very subtle)
		{ Frequency = 0.12, Amplitude = 4, Phase = 0.7 },
	},
	
	-- Terrain depth (how far below the surface to fill)
	TerrainDepth = 60,
	
	-- Terrain material
	Material = Enum.Material.Grass,
	
	-- Seed for reproducible terrain
	Seed = 12345,
}

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         HEIGHT CALCULATION                                  ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

-- Calculate terrain height at a given X position using combined sine waves
local function calculateHeight(x)
	local height = CONFIG.BaseHeight
	
	for _, wave in ipairs(CONFIG.Waves) do
		-- Add each sine wave contribution
		-- Using seed to offset phase for variety
		local phase = wave.Phase + (CONFIG.Seed * 0.001)
		height = height + math.sin(x * wave.Frequency + phase) * wave.Amplitude
	end
	
	return height
end

-- Calculate the slope (derivative) at a given X position
local function calculateSlope(x)
	local slope = 0
	
	for _, wave in ipairs(CONFIG.Waves) do
		local phase = wave.Phase + (CONFIG.Seed * 0.001)
		-- Derivative of sin(ax + b) is a*cos(ax + b)
		slope = slope + math.cos(x * wave.Frequency + phase) * wave.Amplitude * wave.Frequency
	end
	
	return slope
end

-- Get the angle of the terrain at a given X position (in radians)
local function calculateAngle(x)
	local slope = calculateSlope(x)
	return math.atan(slope)
end

-- Smoothed height calculation using cubic interpolation
local function calculateSmoothHeight(x, z)
	-- Add very subtle Z variation for a more natural look (optional)
	local zVariation = math.sin(z * 0.02 + CONFIG.Seed * 0.1) * 2
	return calculateHeight(x) + zVariation
end

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         TERRAIN GENERATION                                  ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

-- Generate terrain using FillRegion slices (no gaps guaranteed)
-- Generate terrain using FillRegion slices (no gaps)
-- Generate terrain in ONE continuous Region3 (no slice seams)
local function generateEntireTerrain()
	local resolution = 4 -- Terrain voxel resolution

	-- Helper to snap to terrain grid
	local function snapToGrid(v)
		return math.floor(v / resolution + 0.5) * resolution
	end

	-- Snap bounds to grid
	local startX = snapToGrid(CONFIG.TerrainStart)
	local endX = snapToGrid(CONFIG.TerrainStart + CONFIG.TerrainLength)
	local halfWidth = snapToGrid(CONFIG.TerrainWidth / 2)

	local minX = math.min(startX, endX)
	local maxX = math.max(startX, endX)
	local minZ = -halfWidth
	local maxZ = halfWidth

	-- First pass: find min and max height for the whole terrain
	local globalMinHeight = math.huge
	local globalMaxHeight = -math.huge

	for x = minX, maxX, CONFIG.StepSize do
		for z = minZ, maxZ, CONFIG.StepSize do
			local h = calculateSmoothHeight(x, z)
			if h > globalMaxHeight then
				globalMaxHeight = h
			end
			if h < globalMinHeight then
				globalMinHeight = h
			end
		end
	end

	-- Vertical bounds - go well below the lowest point to ensure no gaps
	local minY = globalMinHeight - CONFIG.TerrainDepth  -- Solid ground below lowest trough
	local maxY = globalMaxHeight + 4

	print(string.format(
		"[WavyTerrainService] Generating terrain region X[%.0f, %.0f] Z[%.0f, %.0f] Y[%.0f, %.0f]",
		minX, maxX, minZ, maxZ, minY, maxY
	))

	-- Build Region3 and snap it to voxel grid
	local corner1 = Vector3.new(minX, minY, minZ)
	local corner2 = Vector3.new(maxX, maxY, maxZ)
	local region = Region3.new(corner1, corner2):ExpandToGrid(resolution)

	local regionSize = region.Size
	local sizeX = math.floor(regionSize.X / resolution + 0.5)
	local sizeY = math.floor(regionSize.Y / resolution + 0.5)
	local sizeZ = math.floor(regionSize.Z / resolution + 0.5)

	local regionCorner = region.CFrame.Position - regionSize / 2

	print(string.format(
		"[WavyTerrainService] Voxel grid size: %d x %d x %d (resolution=%d)",
		sizeX, sizeY, sizeZ, resolution
	))

	-- Allocate voxel arrays
	local materials = table.create(sizeX)
	local occupancy = table.create(sizeX)

	for xi = 1, sizeX do
		materials[xi] = table.create(sizeY)
		occupancy[xi] = table.create(sizeY)

		for yi = 1, sizeY do
			materials[xi][yi] = table.create(sizeZ)
			occupancy[xi][yi] = table.create(sizeZ)

			for zi = 1, sizeZ do
				materials[xi][yi][zi] = Enum.Material.Air
				occupancy[xi][yi][zi] = 0
			end
		end
	end

	-- Fill arrays based on height
	local material = CONFIG.Material

	for xi = 1, sizeX do
		local worldX = regionCorner.X + (xi - 0.5) * resolution

		for zi = 1, sizeZ do
			local worldZ = regionCorner.Z + (zi - 0.5) * resolution
			local surfaceHeight = calculateSmoothHeight(worldX, worldZ)

			for yi = 1, sizeY do
				local worldY = regionCorner.Y + (yi - 0.5) * resolution

				if worldY <= surfaceHeight then
					materials[xi][yi][zi] = material

					local distFromSurface = surfaceHeight - worldY
					if distFromSurface < resolution then
						occupancy[xi][yi][zi] = math.clamp(distFromSurface / resolution, 0.2, 1)
					else
						occupancy[xi][yi][zi] = 1
					end
				end
			end
		end

		-- Optional: progress log
		if xi % 25 == 0 then
			local progress = xi / sizeX * 100
			print(string.format("[WavyTerrainService] Progress: %.0f%%", progress))
			task.wait()
		end
	end

	-- Single write: no seams possible inside this region
	local startTime = tick()
	Terrain:WriteVoxels(region, resolution, materials, occupancy)
	local elapsed = tick() - startTime

	print(string.format("[WavyTerrainService] Terrain complete in %.2fs", elapsed))

	return 1 -- "1 region" created
end



-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         SPAWN LOCATION                                      ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

-- Create a spawn location at the beginning of the terrain
local function createSpawnLocation(spawnX)
	spawnX = spawnX or 0
	
	-- Calculate the terrain height at the spawn position
	local spawnHeight = calculateSmoothHeight(spawnX, 0)
	
	-- Position spawn slightly above the terrain surface
	local spawnY = spawnHeight + 5
	
	-- Check if spawn already exists
	local existingSpawn = Workspace:FindFirstChild("TinyWingsSpawn")
	if existingSpawn then
		existingSpawn:Destroy()
	end
	
	-- Create the SpawnLocation
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "TinyWingsSpawn"
	spawn.Anchored = true
	spawn.CanCollide = false
	spawn.Size = Vector3.new(12, 1, 12)
	spawn.Position = Vector3.new(spawnX, spawnY, 0)
	spawn.Material = Enum.Material.SmoothPlastic
	spawn.Color = Color3.fromRGB(255, 255, 100) -- Bright yellow
	spawn.Transparency = 0.5
	spawn.Neutral = true -- All teams can spawn here
	spawn.Duration = 0 -- No spawn protection delay
	spawn.Parent = Workspace
	
	-- Add a visual indicator (optional beam of light effect)
	local attachment = Instance.new("Attachment")
	attachment.Parent = spawn
	
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 255, 150)
	light.Brightness = 2
	light.Range = 20
	light.Parent = spawn
	
	print(string.format("[WavyTerrainService] Spawn created at X=%.0f, Y=%.1f", spawnX, spawnY))
	
	return spawn
end

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         KNIT LIFECYCLE                                      ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

function WavyTerrainService:KnitInit()
	print("[WavyTerrainService] Initializing...")
	
	-- Set terrain material color for a nice look
	-- Grass will have a vibrant green color
	Terrain:SetMaterialColor(Enum.Material.Grass, Color3.fromRGB(120, 200, 80))
end

function WavyTerrainService:KnitStart()
	print("[WavyTerrainService] Started")
	
	-- Generate the entire terrain as one continuous piece
	task.spawn(function()
		task.wait(1) -- Small delay to let other services initialize
		self:GenerateTerrain()
		
		-- Create spawn location at the start of the terrain
		createSpawnLocation(0)
		
		-- Remove the baseplate since we have terrain now
		local baseplate = Workspace:FindFirstChild("Baseplate")
		if baseplate then
			baseplate:Destroy()
			print("[WavyTerrainService] Baseplate removed")
		end
	end)
end

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         PUBLIC API                                          ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

-- Generate the entire terrain as one continuous piece
function WavyTerrainService:GenerateTerrain()
	if self._isTerrainGenerated then
		print("[WavyTerrainService] Terrain already generated!")
		return 0
	end
	
	local columnsCreated = generateEntireTerrain()
	self._isTerrainGenerated = true
	
	return columnsCreated
end

-- Clear all terrain
function WavyTerrainService:ClearTerrain()
	-- Clear the entire terrain
	Terrain:Clear()
	
	-- Remove spawn location
	local existingSpawn = Workspace:FindFirstChild("TinyWingsSpawn")
	if existingSpawn then
		existingSpawn:Destroy()
	end
	
	self._isTerrainGenerated = false
	
	print("[WavyTerrainService] Terrain cleared")
end

-- Create or move spawn location
function WavyTerrainService:CreateSpawn(x)
	return createSpawnLocation(x or 0)
end

-- Get spawn location
function WavyTerrainService:GetSpawnLocation()
	return Workspace:FindFirstChild("TinyWingsSpawn")
end

-- Clear terrain in a specific region
function WavyTerrainService:ClearRegion(minPos, maxPos)
	local resolution = 4 -- Roblox terrain default resolution
	local region = Region3.new(minPos, maxPos):ExpandToGrid(resolution)
	Terrain:FillRegion(region, resolution, Enum.Material.Air)
end

-- Get terrain height at X position
function WavyTerrainService:GetHeightAtX(x)
	return calculateHeight(x)
end

-- Get terrain height at X, Z position (includes Z variation)
function WavyTerrainService:GetHeightAt(x, z)
	return calculateSmoothHeight(x, z or 0)
end

-- Get terrain slope at X position (returns angle in radians)
function WavyTerrainService:GetSlopeAtX(x)
	return calculateAngle(x)
end

-- Get terrain surface position at X
function WavyTerrainService:GetSurfacePositionAtX(x, z)
	z = z or 0
	local y = calculateSmoothHeight(x, z)
	return Vector3.new(x, y, z)
end

-- Check if terrain is generated
function WavyTerrainService:IsTerrainGenerated()
	return self._isTerrainGenerated
end

-- Get configuration
function WavyTerrainService:GetConfig()
	return CONFIG
end

-- Update configuration
function WavyTerrainService:SetConfig(key, value)
	if CONFIG[key] ~= nil then
		CONFIG[key] = value
		print("[WavyTerrainService] Config updated:", key, "=", tostring(value))
		return true
	end
	warn("[WavyTerrainService] Unknown config key:", key)
	return false
end

-- Update wave parameters
function WavyTerrainService:SetWaves(waves)
	CONFIG.Waves = waves
	print("[WavyTerrainService] Waves updated")
end

-- Regenerate terrain with new seed
function WavyTerrainService:RegenerateWithSeed(newSeed)
	CONFIG.Seed = newSeed or math.random(1, 999999)
	self:ClearTerrain()
	print("[WavyTerrainService] Regenerating with seed:", CONFIG.Seed)
	return self:GenerateTerrain()
end

-- Get terrain bounds
function WavyTerrainService:GetTerrainBounds()
	return {
		StartX = CONFIG.TerrainStart,
		EndX = CONFIG.TerrainStart + CONFIG.TerrainLength,
		Width = CONFIG.TerrainWidth,
	}
end

-- Set terrain material color (for Tiny Wings-style color changes)
function WavyTerrainService:SetTerrainColor(color)
	Terrain:SetMaterialColor(CONFIG.Material, color)
end

-- Cycle through color palettes based on X position
function WavyTerrainService:UpdateColorForPosition(x)
	local palettes = {
		Color3.fromRGB(255, 140, 90),   -- Coral orange (Sunrise)
		Color3.fromRGB(120, 200, 80),   -- Lime green (Meadow)
		Color3.fromRGB(80, 180, 220),   -- Sky blue (Ocean)
		Color3.fromRGB(180, 100, 200),  -- Orchid (Sunset)
		Color3.fromRGB(240, 200, 100),  -- Golden yellow (Desert)
	}
	
	local paletteDistance = 500
	local paletteIndex = math.floor(x / paletteDistance) % #palettes + 1
	local nextIndex = (paletteIndex % #palettes) + 1
	
	-- Smooth blend between palettes
	local blend = (x % paletteDistance) / paletteDistance
	blend = blend * blend * (3 - 2 * blend) -- Smoothstep
	
	local color = palettes[paletteIndex]:Lerp(palettes[nextIndex], blend)
	self:SetTerrainColor(color)
end

-- Client exposure for height queries (useful for physics)
function WavyTerrainService.Client:GetHeightAtX(player, x)
	return self.Server:GetHeightAtX(x)
end

function WavyTerrainService.Client:GetHeightAt(player, x, z)
	return self.Server:GetHeightAt(x, z)
end

function WavyTerrainService.Client:GetSlopeAtX(player, x)
	return self.Server:GetSlopeAtX(x)
end

function WavyTerrainService.Client:GetSurfacePositionAtX(player, x, z)
	return self.Server:GetSurfacePositionAtX(x, z)
end

return WavyTerrainService
