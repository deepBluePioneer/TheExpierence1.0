--[[
	CubeTerrainService
	
	Generates terrain using cube parts with randomized heights.
	Uses Perlin-like noise for smooth, natural terrain variation.
	
	Each cube represents a terrain cell with:
	- Slight height offset for organic ground feel
	- Color variation based on height
	- Configurable noise parameters
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local CollectionService = game:GetService("CollectionService")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local Knit = require(Packages.Knit)

local CubeTerrainService = Knit.CreateService {
	Name = "CubeTerrainService",
	Client = {},
	
	-- Service references
	_gridService = nil,
	
	-- State
	_isTerrainGenerated = false,
	_terrainCubes = {},  -- { ["x_z"] = cube }
	_heightMap = {},     -- { ["x_z"] = heightOffset }
}

-- === FOLDERS ===
local TERRAIN_FOLDER_NAME = "TerrainCubes"
local TERRAIN_CUBE_TAG = "terrainCube"

-- === TERRAIN CONFIG ===
local CONFIG = {
	-- Height variation settings
	HeightVariationEnabled = true,
	MinHeightOffset = -4,          -- Minimum height offset (studs)
	MaxHeightOffset = 6,           -- Maximum height offset (studs)
	
	-- Perlin noise settings for smooth height variation
	NoiseEnabled = true,
	NoiseScale = 0.15,             -- Lower = smoother, larger hills; Higher = more chaotic
	NoiseAmplitude = 5.0,          -- How much the noise affects height
	NoiseSeed = 12345,             -- Seed for reproducible terrain
	
	-- Secondary noise layer for detail
	DetailNoiseEnabled = true,
	DetailNoiseScale = 0.4,        -- Higher frequency for small bumps
	DetailNoiseAmplitude = 1.5,    -- Amplitude for detail bumps
	
	-- === SUBDIVISION SETTINGS ===
	SubdivisionEnabled = true,     -- Enable cell subdivision for more detailed terrain
	MinSubdivisions = 2,           -- Minimum subdivisions per cell (2 = 2x2 = 4 sub-cubes)
	MaxSubdivisions = 4,           -- Maximum subdivisions per cell (4 = 4x4 = 16 sub-cubes)
	SubdivisionRandomness = true,  -- Randomize subdivision count per cell
	SubHeightVariation = 1.5,      -- Additional height variation within subdivided cells
	
	-- Cube appearance
	CubeThickness = 4,             -- Height/thickness of each terrain cube
	
	-- Material
	Material = Enum.Material.Ground,
	
	-- Color palette for terrain (will blend based on height/noise)
	BaseColor = Color3.fromRGB(85, 107, 47),      -- Olive drab (base ground)
	LowColor = Color3.fromRGB(107, 84, 40),       -- Darker brown (lower areas)
	HighColor = Color3.fromRGB(124, 160, 72),     -- Lighter green (higher areas)
	ColorVariation = 0.15,                         -- Random color variation (0-1)
}

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         NOISE GENERATION                                   ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

-- Simple hash function for pseudo-random but deterministic values (for color variation)
local function hash2D(x, z, seed)
	-- Use math.noise for deterministic pseudo-random
	return (math.noise(x * 0.1 + seed, z * 0.1) + 1) / 2
end

-- Multi-octave noise using Roblox's built-in math.noise (returns -0.5 to 0.5)
local function fractalNoise2D(x, z, scale, octaves, persistence, seed)
	local total = 0
	local amplitude = 1
	local maxValue = 0
	local frequency = scale
	
	-- Use seed to offset the noise sampling position
	local seedOffsetX = seed * 0.1
	local seedOffsetZ = seed * 0.17
	
	for _ = 1, octaves do
		-- math.noise returns -0.5 to 0.5, we convert to 0 to 1
		local noiseValue = math.noise(
			x * frequency + seedOffsetX, 
			z * frequency + seedOffsetZ
		) + 0.5
		
		total = total + noiseValue * amplitude
		maxValue = maxValue + amplitude
		amplitude = amplitude * persistence
		frequency = frequency * 2
	end
	
	return total / maxValue  -- Returns 0 to 1
end

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         HEIGHT CALCULATION                                 ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

-- Calculate terrain height offset for a given grid position
local function calculateTerrainHeight(x, z)
	if not CONFIG.HeightVariationEnabled then
		return 0
	end
	
	local heightOffset = 0
	
	if CONFIG.NoiseEnabled then
		-- Primary noise layer (large features)
		local primaryNoise = fractalNoise2D(
			x, z,
			CONFIG.NoiseScale,
			3,  -- octaves
			0.5,  -- persistence
			CONFIG.NoiseSeed
		)
		heightOffset = heightOffset + (primaryNoise - 0.5) * 2 * CONFIG.NoiseAmplitude
		
		-- Detail noise layer (small bumps)
		if CONFIG.DetailNoiseEnabled then
			local detailNoise = fractalNoise2D(
				x, z,
				CONFIG.DetailNoiseScale,
				2,  -- octaves
				0.5,  -- persistence
				CONFIG.NoiseSeed + 1000
			)
			heightOffset = heightOffset + (detailNoise - 0.5) * 2 * CONFIG.DetailNoiseAmplitude
		end
	else
		-- Simple random offset (less smooth)
		local randomOffset = hash2D(x, z, CONFIG.NoiseSeed)
		heightOffset = CONFIG.MinHeightOffset + 
			randomOffset * (CONFIG.MaxHeightOffset - CONFIG.MinHeightOffset)
	end
	
	-- Clamp to min/max
	heightOffset = math.clamp(heightOffset, CONFIG.MinHeightOffset, CONFIG.MaxHeightOffset)
	
	return heightOffset
end

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         COLOR CALCULATION                                  ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

-- Calculate terrain color based on height and position
local function calculateTerrainColor(x, z, heightOffset)
	-- Normalize height to 0-1 range
	local heightRange = CONFIG.MaxHeightOffset - CONFIG.MinHeightOffset
	local normalizedHeight = (heightOffset - CONFIG.MinHeightOffset) / heightRange
	
	-- Blend between low, base, and high colors based on height
	local color
	if normalizedHeight < 0.5 then
		-- Blend from low to base
		local t = normalizedHeight * 2
		color = CONFIG.LowColor:Lerp(CONFIG.BaseColor, t)
	else
		-- Blend from base to high
		local t = (normalizedHeight - 0.5) * 2
		color = CONFIG.BaseColor:Lerp(CONFIG.HighColor, t)
	end
	
	-- Add random color variation
	if CONFIG.ColorVariation > 0 then
		local variation = (hash2D(x * 7, z * 13, CONFIG.NoiseSeed + 500) - 0.5) * 2
		variation = variation * CONFIG.ColorVariation
		
		local r = math.clamp(color.R + variation * 0.1, 0, 1)
		local g = math.clamp(color.G + variation * 0.1, 0, 1)
		local b = math.clamp(color.B + variation * 0.05, 0, 1)
		color = Color3.new(r, g, b)
	end
	
	return color
end

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         CUBE CREATION                                      ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

-- Template for terrain cubes
local terrainCubeTemplate = Instance.new("Part")
terrainCubeTemplate.Name = "TerrainCubeTemplate"
terrainCubeTemplate.Anchored = true
terrainCubeTemplate.CanCollide = true
terrainCubeTemplate.CastShadow = true
terrainCubeTemplate.Transparency = 0
terrainCubeTemplate.Material = CONFIG.Material

-- Get or create terrain folder
local function getTerrainFolder()
	local folder = Workspace:FindFirstChild(TERRAIN_FOLDER_NAME)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = TERRAIN_FOLDER_NAME
		folder.Parent = Workspace
	end
	return folder
end

-- Clear all terrain cubes
local function clearTerrainCubes(self)
	local folder = Workspace:FindFirstChild(TERRAIN_FOLDER_NAME)
	if folder then
		folder:ClearAllChildren()
	end
	self._terrainCubes = {}
	self._heightMap = {}
	self._isTerrainGenerated = false
end

-- Get cell key from coordinates
local function getCellKey(x, z)
	return string.format("%d_%d", x, z)
end

-- Get subdivision key for sub-cubes
local function getSubCellKey(gridX, gridZ, subX, subZ)
	return string.format("%d_%d_%d_%d", gridX, gridZ, subX, subZ)
end

-- Deterministic random based on position (for consistent subdivision counts)
local function getSubdivisionCount(gridX, gridZ)
	if not CONFIG.SubdivisionRandomness then
		return CONFIG.MaxSubdivisions
	end
	
	-- Use noise to get consistent random subdivision count per cell
	local noiseVal = math.noise(gridX * 0.5 + CONFIG.NoiseSeed * 0.01, gridZ * 0.5)
	local normalized = (noiseVal + 0.5)  -- 0 to 1
	local range = CONFIG.MaxSubdivisions - CONFIG.MinSubdivisions
	return math.floor(CONFIG.MinSubdivisions + normalized * range + 0.5)
end

-- Create a single sub-cube at a specific world position
local function createSubCube(self, worldX, worldZ, subCubeSize, baseY, folder, gridX, gridZ, subX, subZ)
	-- Calculate height using the actual world position for more detail
	-- Use higher frequency noise for sub-cubes
	local noiseX = worldX * CONFIG.NoiseScale * 2  -- Higher frequency for sub-cubes
	local noiseZ = worldZ * CONFIG.NoiseScale * 2
	
	-- Base height from the grid position
	local baseHeight = calculateTerrainHeight(gridX, gridZ)
	
	-- Additional micro-variation for this sub-cube
	local microNoise = math.noise(
		worldX * 0.3 + CONFIG.NoiseSeed * 0.1, 
		worldZ * 0.3
	)
	local subHeightOffset = microNoise * CONFIG.SubHeightVariation
	
	local heightOffset = baseHeight + subHeightOffset
	heightOffset = math.clamp(heightOffset, CONFIG.MinHeightOffset, CONFIG.MaxHeightOffset)
	
	-- Create the cube
	local cube = terrainCubeTemplate:Clone()
	cube.Name = string.format("Terrain_%d_%d_%d_%d", gridX, gridZ, subX, subZ)
	cube.Size = Vector3.new(subCubeSize, CONFIG.CubeThickness, subCubeSize)
	
	local cubeY = baseY + (CONFIG.CubeThickness / 2) + heightOffset
	
	cube.Position = Vector3.new(worldX, cubeY, worldZ)
	
	-- Apply terrain color based on height
	cube.Color = calculateTerrainColor(worldX, worldZ, heightOffset)
	
	-- Add tag
	CollectionService:AddTag(cube, TERRAIN_CUBE_TAG)
	
	cube.Parent = folder
	
	-- Store reference
	local key = getSubCellKey(gridX, gridZ, subX, subZ)
	self._terrainCubes[key] = cube
	self._heightMap[key] = heightOffset
	
	return cube, heightOffset
end

-- Create terrain cubes for a single grid cell (with subdivisions)
local function createTerrainCell(self, gridX, gridZ, cellSize, baseY, centerX, centerZ, gridWidth, gridDepth, folder)
	local cubesCreated = 0
	
	-- Calculate the world position of this cell's corner
	local cellOffsetX = (gridX - (gridWidth + 1) / 2) * cellSize
	local cellOffsetZ = (gridZ - (gridDepth + 1) / 2) * cellSize
	local cellWorldX = centerX + cellOffsetX - (cellSize / 2)
	local cellWorldZ = centerZ + cellOffsetZ - (cellSize / 2)
	
	if CONFIG.SubdivisionEnabled then
		-- Get subdivision count for this cell
		local subdivisions = getSubdivisionCount(gridX, gridZ)
		local subCubeSize = cellSize / subdivisions
		
		-- Create sub-cubes
		for subX = 1, subdivisions do
			for subZ = 1, subdivisions do
				local worldX = cellWorldX + (subX - 0.5) * subCubeSize
				local worldZ = cellWorldZ + (subZ - 0.5) * subCubeSize
				
				createSubCube(self, worldX, worldZ, subCubeSize, baseY, folder, gridX, gridZ, subX, subZ)
				cubesCreated += 1
			end
		end
	else
		-- No subdivision - create single cube (original behavior)
		local worldX = cellWorldX + (cellSize / 2)
		local worldZ = cellWorldZ + (cellSize / 2)
		
		local heightOffset = calculateTerrainHeight(gridX, gridZ)
		
		local cube = terrainCubeTemplate:Clone()
		cube.Name = string.format("Terrain_%d_%d", gridX, gridZ)
		cube.Size = Vector3.new(cellSize, CONFIG.CubeThickness, cellSize)
		
		local cubeY = baseY + (CONFIG.CubeThickness / 2) + heightOffset
		cube.Position = Vector3.new(worldX, cubeY, worldZ)
		cube.Color = calculateTerrainColor(gridX, gridZ, heightOffset)
		
		CollectionService:AddTag(cube, TERRAIN_CUBE_TAG)
		cube.Parent = folder
		
		local key = getCellKey(gridX, gridZ)
		self._terrainCubes[key] = cube
		self._heightMap[key] = heightOffset
		cubesCreated = 1
	end
	
	return cubesCreated
end

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         KNIT LIFECYCLE                                     ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

function CubeTerrainService:KnitInit()
	print("[CubeTerrainService] Initializing...")
end

function CubeTerrainService:KnitStart()
	-- Get GridService reference
	pcall(function()
		self._gridService = Knit.GetService("GridService")
	end)
	
	print("[CubeTerrainService] Started - waiting for terrain generation request")
end

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         PUBLIC API                                         ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

-- Generate terrain cubes for the entire grid
function CubeTerrainService:GenerateTerrain(gridWidth, gridDepth, cubeSize, centerX, centerZ, baseY)
	local startTime = tick()
	
	local subdivisionInfo = ""
	if CONFIG.SubdivisionEnabled then
		subdivisionInfo = string.format(" (subdivided %d-%d per cell)", CONFIG.MinSubdivisions, CONFIG.MaxSubdivisions)
	end
	print(string.format("[CubeTerrainService] Generating %dx%d terrain cells%s...", gridWidth, gridDepth, subdivisionInfo))
	
	-- Clear existing terrain
	clearTerrainCubes(self)
	
	local folder = getTerrainFolder()
	local totalCells = gridWidth * gridDepth
	local totalCubesCreated = 0
	local cellsProcessed = 0
	local batchSize = 10  -- Lower batch size since each cell creates multiple cubes
	local batchCount = 0
	
	-- Create terrain cubes for each grid cell
	for x = 1, gridWidth do
		for z = 1, gridDepth do
			local cubesCreated = createTerrainCell(self, x, z, cubeSize, baseY, centerX, centerZ, gridWidth, gridDepth, folder)
			
			totalCubesCreated += cubesCreated
			cellsProcessed += 1
			batchCount += 1
			
			-- Yield periodically to prevent lag
			if batchCount >= batchSize then
				batchCount = 0
				task.wait()
			end
		end
	end
	
	self._isTerrainGenerated = true
	
	local elapsed = tick() - startTime
	local avgSubdivisions = totalCubesCreated / totalCells
	print(string.format("[CubeTerrainService] Generated %d terrain cubes from %d cells (avg %.1f cubes/cell) in %.2fs", 
		totalCubesCreated, totalCells, avgSubdivisions, elapsed))
	print(string.format("[CubeTerrainService] Height range: %.1f to %.1f studs", 
		CONFIG.MinHeightOffset, CONFIG.MaxHeightOffset))
	
	return totalCubesCreated
end

-- Generate terrain using GridService data
function CubeTerrainService:GenerateTerrainFromGrid()
	if not self._gridService then
		pcall(function()
			self._gridService = Knit.GetService("GridService")
		end)
	end
	
	if not self._gridService then
		warn("[CubeTerrainService] GridService not available!")
		return 0
	end
	
	local gridData = self._gridService:GetGridData()
	return self:GenerateTerrain(
		gridData.width,
		gridData.depth,
		gridData.cellSize,
		gridData.centerX,
		gridData.centerZ,
		gridData.topY
	)
end

-- Clear all terrain
function CubeTerrainService:ClearTerrain()
	clearTerrainCubes(self)
	print("[CubeTerrainService] Terrain cleared")
end

-- Check if terrain is generated
function CubeTerrainService:IsTerrainGenerated()
	return self._isTerrainGenerated
end

-- Get height offset at grid position
function CubeTerrainService:GetHeightAtCell(x, z)
	local key = getCellKey(x, z)
	if self._heightMap[key] then
		return self._heightMap[key]
	end
	-- Calculate on-demand if not cached
	return calculateTerrainHeight(x, z)
end

-- Get terrain height at world position (grid-based, fast but approximate)
function CubeTerrainService:GetHeightAtPosition(worldPos)
	if not self._gridService then
		pcall(function()
			self._gridService = Knit.GetService("GridService")
		end)
	end
	
	if self._gridService then
		local gridX, gridZ = self._gridService:WorldToGrid(worldPos)
		local gridData = self._gridService:GetGridData()
		return gridData.topY + self:GetHeightAtCell(gridX, gridZ)
	end
	
	return 0
end

-- Find terrain cube at world position (direct lookup, no raycast)
function CubeTerrainService:GetCubeAtWorldPosition(worldX, worldZ)
	if not self._gridService then
		pcall(function()
			self._gridService = Knit.GetService("GridService")
		end)
	end
	
	if not self._gridService then
		return nil
	end
	
	-- Convert world position to grid coordinates
	local gridX, gridZ = self._gridService:WorldToGrid(Vector3.new(worldX, 0, worldZ))
	
	if not gridX or not gridZ then
		return nil
	end
	
	-- First try direct lookup (works for non-subdivided terrain)
	local key = getCellKey(gridX, gridZ)
	local cube = self._terrainCubes[key]
	
	if cube then
		return cube
	end
	
	-- For subdivided terrain, find the closest cube by checking all cubes
	-- that might overlap this position
	local closestCube = nil
	local closestDistance = math.huge
	
	for cubeKey, terrainCube in pairs(self._terrainCubes) do
		local cubePos = terrainCube.Position
		local cubeSize = terrainCube.Size
		
		-- Check if world position is within cube's XZ bounds
		local halfX = cubeSize.X / 2
		local halfZ = cubeSize.Z / 2
		
		if worldX >= (cubePos.X - halfX) and worldX <= (cubePos.X + halfX) and
		   worldZ >= (cubePos.Z - halfZ) and worldZ <= (cubePos.Z + halfZ) then
			-- Position is inside this cube's XZ bounds - return it
			return terrainCube
		end
		
		-- Track closest cube as fallback
		local dist = math.sqrt((worldX - cubePos.X)^2 + (worldZ - cubePos.Z)^2)
		if dist < closestDistance then
			closestDistance = dist
			closestCube = terrainCube
		end
	end
	
	return closestCube
end

-- Get terrain surface height at world position (NO raycast - direct cube lookup)
function CubeTerrainService:GetSurfaceHeightAt(worldX, worldZ)
	local cube = self:GetCubeAtWorldPosition(worldX, worldZ)
	
	if cube then
		-- Return top surface Y of the cube
		return cube.Position.Y + (cube.Size.Y / 2)
	end
	
	-- Fallback to grid-based height
	return self:GetHeightAtPosition(Vector3.new(worldX, 0, worldZ))
end

-- Get terrain surface position (Vector3) at world X, Z coordinates
function CubeTerrainService:GetSurfacePositionAt(worldX, worldZ)
	local surfaceY = self:GetSurfaceHeightAt(worldX, worldZ)
	return Vector3.new(worldX, surfaceY, worldZ)
end

-- Get terrain thickness at world position
function CubeTerrainService:GetTerrainThicknessAt(worldX, worldZ)
	local cube = self:GetCubeAtWorldPosition(worldX, worldZ)
	if cube then
		return cube.Size.Y
	end
	return CONFIG.CubeThickness
end

-- Get terrain cube at grid position
function CubeTerrainService:GetCubeAt(x, z)
	local key = getCellKey(x, z)
	return self._terrainCubes[key]
end

-- Get all terrain cubes
function CubeTerrainService:GetAllCubes()
	local cubes = {}
	for _, cube in pairs(self._terrainCubes) do
		table.insert(cubes, cube)
	end
	return cubes
end

-- Get terrain folder
function CubeTerrainService:GetTerrainFolder()
	return Workspace:FindFirstChild(TERRAIN_FOLDER_NAME)
end

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         CONFIGURATION                                      ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

-- Get current configuration
function CubeTerrainService:GetConfig()
	return CONFIG
end

-- Set configuration value
function CubeTerrainService:SetConfig(key, value)
	if CONFIG[key] ~= nil then
		CONFIG[key] = value
		print("[CubeTerrainService] Config updated:", key, "=", tostring(value))
		return true
	end
	warn("[CubeTerrainService] Unknown config key:", key)
	return false
end

-- Set multiple configuration values
function CubeTerrainService:SetConfigs(configTable)
	for key, value in pairs(configTable) do
		self:SetConfig(key, value)
	end
end

-- Regenerate with new seed
function CubeTerrainService:RegenerateWithSeed(newSeed)
	CONFIG.NoiseSeed = newSeed or math.random(1, 999999)
	print("[CubeTerrainService] Regenerating with seed:", CONFIG.NoiseSeed)
	return self:GenerateTerrainFromGrid()
end

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         TERRAIN MODIFICATION                               ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

-- Flatten terrain in an area (for buildings, etc.)
function CubeTerrainService:FlattenArea(centerX, centerZ, radiusCells, targetHeight)
	if not self._gridService then
		pcall(function()
			self._gridService = Knit.GetService("GridService")
		end)
	end
	
	local gridData = self._gridService and self._gridService:GetGridData() or nil
	targetHeight = targetHeight or (gridData and gridData.topY or 0)
	
	local flattenedCount = 0
	
	for dx = -radiusCells, radiusCells do
		for dz = -radiusCells, radiusCells do
			local gridX = centerX + dx
			local gridZ = centerZ + dz
			
			-- Check if within circular radius
			local dist = math.sqrt(dx * dx + dz * dz)
			if dist <= radiusCells then
				local cube = self:GetCubeAt(gridX, gridZ)
				if cube then
					-- Move cube to flat height
					local currentPos = cube.Position
					cube.Position = Vector3.new(
						currentPos.X,
						targetHeight + (CONFIG.CubeThickness / 2),
						currentPos.Z
					)
					
					-- Update height map
					local key = getCellKey(gridX, gridZ)
					self._heightMap[key] = 0
					
					flattenedCount += 1
				end
			end
		end
	end
	
	print(string.format("[CubeTerrainService] Flattened %d cubes around (%d, %d)", 
		flattenedCount, centerX, centerZ))
	return flattenedCount
end

-- Set height for a specific cell
function CubeTerrainService:SetCellHeight(x, z, heightOffset)
	local cube = self:GetCubeAt(x, z)
	if not cube then return false end
	
	if not self._gridService then
		pcall(function()
			self._gridService = Knit.GetService("GridService")
		end)
	end
	
	local gridData = self._gridService and self._gridService:GetGridData() or nil
	local baseY = gridData and gridData.topY or 0
	
	-- Update cube position
	local currentPos = cube.Position
	cube.Position = Vector3.new(
		currentPos.X,
		baseY + (CONFIG.CubeThickness / 2) + heightOffset,
		currentPos.Z
	)
	
	-- Update color based on new height
	cube.Color = calculateTerrainColor(x, z, heightOffset)
	
	-- Update height map
	local key = getCellKey(x, z)
	self._heightMap[key] = heightOffset
	
	return true
end

-- Raise/lower terrain in an area
function CubeTerrainService:ModifyAreaHeight(centerX, centerZ, radiusCells, heightDelta, smooth)
	smooth = smooth ~= false  -- Default to true
	local modifiedCount = 0
	
	for dx = -radiusCells, radiusCells do
		for dz = -radiusCells, radiusCells do
			local gridX = centerX + dx
			local gridZ = centerZ + dz
			
			local dist = math.sqrt(dx * dx + dz * dz)
			if dist <= radiusCells then
				local key = getCellKey(gridX, gridZ)
				local currentHeight = self._heightMap[key] or 0
				
				-- Apply smoothing falloff at edges
				local factor = 1
				if smooth then
					factor = 1 - (dist / radiusCells)
					factor = factor * factor  -- Quadratic falloff
				end
				
				local newHeight = currentHeight + (heightDelta * factor)
				newHeight = math.clamp(newHeight, CONFIG.MinHeightOffset, CONFIG.MaxHeightOffset)
				
				if self:SetCellHeight(gridX, gridZ, newHeight) then
					modifiedCount += 1
				end
			end
		end
	end
	
	return modifiedCount
end

return CubeTerrainService

