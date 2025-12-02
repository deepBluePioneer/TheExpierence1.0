local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local Knit = require(Packages.Knit)

local TerrainService = Knit.CreateService {
	Name = "TerrainService",
	Client = {},
	_baseplates = nil,
	_baseplateInfo = nil,
	_baseplatePositions = {},
	_biomeCache = {},  -- Cache biome lookups for performance
	_climateData = nil,  -- Store generated climate data
	_autoStart = false,  -- Set to false to let WorldInitService control initialization
}

-- === CONFIG ===
local CONFIG = {
	-- Terrain generation settings
	TerrainEnabled = true,
	
	-- Area settings
	UseBaseplate = true,
	DefaultSize = Vector3.new(128, 100, 128),
	
	-- Baseplate grid settings
	CreateBaseplateGrid = true,
	BaseplateGridSize = 3,
	BaseplateSize = Vector3.new(128, 1, 128),
	BaseplateThickness = 1,
	RemoveBaseplatesAfterGen = true,
	
	-- Height settings
	BaseHeight = 0,
	WaterLevel = -50,
	DisableWater = true,
	
	-- Resolution
	Resolution = 4,
	
	-- Smoothing
	SmoothingPasses = 3,
	
	-- Hole Prevention
	MinTerrainThickness = 8,      -- Minimum terrain depth below surface
	ChunkOverlap = 4,             -- Overlap between chunks to prevent seams
	FillGapsEnabled = true,       -- Enable gap filling pass
	BaseFloorEnabled = true,      -- Add a solid floor layer to prevent holes
	BaseFloorDepth = 15,          -- Depth below BaseHeight for floor
	
	-- Additional features
	AddHills = true,
	HillCount = 15,
	HillMinRadius = 20,
	HillMaxRadius = 50,
	HillMinHeight = 10,
	HillMaxHeight = 30,
	
	AddCaves = true,
	CaveCount = 8,
	CaveMinRadius = 15,
	CaveMaxRadius = 35,
	CaveMinDepth = 20,
	CaveMaxDepth = 40,
}

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         CLIMATE-BASED BIOME SYSTEM                         ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

--[[
    NEW BIOME SELECTION SYSTEM
    
    Instead of random biome assignment, we use a climate model:
    
    1. TEMPERATURE (0-1): Controlled by noise + latitude gradient
       - 0 = Freezing (poles/mountains)
       - 1 = Hot (equator/lowlands)
    
    2. MOISTURE (0-1): Controlled by separate noise
       - 0 = Dry (desert/badlands)
       - 1 = Wet (jungle/swamp)
    
    3. ELEVATION: Modifies temperature (higher = colder)
    
    4. VORONOI CELLS: Add organic region boundaries
    
    This creates coherent biome distribution like real-world climate zones!
]]

local CLIMATE_CONFIG = {
	-- Noise settings for climate maps
	TemperatureNoiseScale = 0.002,   -- Large scale for broad climate zones
	TemperatureNoiseOctaves = 3,
	TemperatureNoisePersistence = 0.5,
	
	MoistureNoiseScale = 0.003,      -- Slightly different scale for variety
	MoistureNoiseOctaves = 3,
	MoistureNoisePersistence = 0.5,
	
	-- Elevation influence on temperature (higher = colder)
	ElevationTemperatureInfluence = 0.02,  -- Per stud of elevation
	
	-- Voronoi settings for organic regions
	VoronoiEnabled = true,
	VoronoiCellCount = 25,           -- Number of biome "seed points"
	VoronoiInfluence = 0.3,          -- How much Voronoi affects final biome (0-1)
	
	-- Latitude gradient (optional - makes north colder, south warmer)
	LatitudeGradientEnabled = false,
	LatitudeGradientStrength = 0.3,
}

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                           BIOME DEFINITIONS                                ║
-- ╠════════════════════════════════════════════════════════════════════════════╣
-- ║  Each biome has climate ranges (temperature, moisture) that determine      ║
-- ║  where it can appear. Biomes are selected based on best climate match.     ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

local BIOMES = {
	-- === COLD BIOMES (Temperature 0.0 - 0.3) ===
	Tundra = {
		name = "Tundra",
		-- Climate ranges
		temperatureMin = 0.0,
		temperatureMax = 0.2,
		moistureMin = 0.0,
		moistureMax = 0.5,
		priority = 1,  -- Higher priority for specific conditions
		
		-- Terrain generation
		noiseScale = 0.005,
		noiseAmplitude = 8,
		noiseOctaves = 2,
		noisePersistence = 0.25,
		baseHeight = 2,
		
		-- Materials
		defaultMaterial = Enum.Material.Snow,
		slopeMaterial = Enum.Material.Snow,
		peakMaterial = Enum.Material.Snow,
		slopeThreshold = 0.7,
		peakHeight = 0,
		rockMinHeight = 999,
	},
	
	SnowyMountain = {
		name = "SnowyMountain",
		temperatureMin = 0.0,
		temperatureMax = 0.25,
		moistureMin = 0.3,
		moistureMax = 1.0,
		priority = 2,
		
		noiseScale = 0.006,
		noiseAmplitude = 25,
		noiseOctaves = 3,
		noisePersistence = 0.4,
		baseHeight = 15,
		
		defaultMaterial = Enum.Material.Snow,
		slopeMaterial = Enum.Material.Rock,
		peakMaterial = Enum.Material.Snow,
		slopeThreshold = 0.4,
		peakHeight = 30,
		rockMinHeight = 5,
	},
	
	-- === COOL BIOMES (Temperature 0.2 - 0.5) ===
	Taiga = {
		name = "Taiga",
		temperatureMin = 0.15,
		temperatureMax = 0.4,
		moistureMin = 0.4,
		moistureMax = 1.0,
		priority = 1,
		
		noiseScale = 0.005,
		noiseAmplitude = 12,
		noiseOctaves = 2,
		noisePersistence = 0.35,
		baseHeight = 3,
		
		defaultMaterial = Enum.Material.Grass,
		slopeMaterial = Enum.Material.Rock,
		peakMaterial = Enum.Material.Snow,
		slopeThreshold = 0.55,
		peakHeight = 25,
		rockMinHeight = 12,
	},
	
	Mountain = {
		name = "Mountain",
		temperatureMin = 0.2,
		temperatureMax = 0.5,
		moistureMin = 0.0,
		moistureMax = 0.6,
		priority = 2,
		
		noiseScale = 0.006,
		noiseAmplitude = 22,
		noiseOctaves = 3,
		noisePersistence = 0.38,
		baseHeight = 10,
		
		defaultMaterial = Enum.Material.Rock,
		slopeMaterial = Enum.Material.Rock,
		peakMaterial = Enum.Material.Snow,
		slopeThreshold = 0.4,
		peakHeight = 35,
		rockMinHeight = 0,
	},
	
	-- === TEMPERATE BIOMES (Temperature 0.4 - 0.7) ===
	Forest = {
		name = "Forest",
		temperatureMin = 0.35,
		temperatureMax = 0.65,
		moistureMin = 0.5,
		moistureMax = 1.0,
		priority = 1,
		
		noiseScale = 0.005,
		noiseAmplitude = 10,
		noiseOctaves = 2,
		noisePersistence = 0.3,
		baseHeight = 2,
		
		defaultMaterial = Enum.Material.Grass,
		slopeMaterial = Enum.Material.Rock,
		peakMaterial = Enum.Material.Grass,
		slopeThreshold = 0.55,
		peakHeight = 999,
		rockMinHeight = 14,
	},
	
	Plains = {
		name = "Plains",
		temperatureMin = 0.4,
		temperatureMax = 0.7,
		moistureMin = 0.3,
		moistureMax = 0.6,
		priority = 1,
		
		noiseScale = 0.004,
		noiseAmplitude = 5,
		noiseOctaves = 2,
		noisePersistence = 0.25,
		baseHeight = 1,
		
		defaultMaterial = Enum.Material.Grass,
		slopeMaterial = Enum.Material.Grass,
		peakMaterial = Enum.Material.Grass,
		slopeThreshold = 0.85,
		peakHeight = 999,
		rockMinHeight = 999,
	},
	
	Grassland = {
		name = "Grassland",
		temperatureMin = 0.35,
		temperatureMax = 0.65,
		moistureMin = 0.2,
		moistureMax = 0.5,
		priority = 1,
		
		noiseScale = 0.004,
		noiseAmplitude = 8,
		noiseOctaves = 2,
		noisePersistence = 0.3,
		baseHeight = 2,
		
		defaultMaterial = Enum.Material.Grass,
		slopeMaterial = Enum.Material.Grass,
		peakMaterial = Enum.Material.Grass,
		slopeThreshold = 0.75,
		peakHeight = 999,
		rockMinHeight = 999,
	},
	
	Hills = {
		name = "Hills",
		temperatureMin = 0.3,
		temperatureMax = 0.6,
		moistureMin = 0.3,
		moistureMax = 0.7,
		priority = 1,
		
		noiseScale = 0.005,
		noiseAmplitude = 14,
		noiseOctaves = 2,
		noisePersistence = 0.32,
		baseHeight = 4,
		
		defaultMaterial = Enum.Material.Grass,
		slopeMaterial = Enum.Material.Rock,
		peakMaterial = Enum.Material.Grass,
		slopeThreshold = 0.6,
		peakHeight = 999,
		rockMinHeight = 12,
	},
	
	-- === WARM/DRY BIOMES (Temperature 0.6 - 0.85) ===
	Savanna = {
		name = "Savanna",
		temperatureMin = 0.55,
		temperatureMax = 0.8,
		moistureMin = 0.15,
		moistureMax = 0.45,
		priority = 1,
		
		noiseScale = 0.004,
		noiseAmplitude = 6,
		noiseOctaves = 2,
		noisePersistence = 0.28,
		baseHeight = 1,
		
		defaultMaterial = Enum.Material.Sand,
		slopeMaterial = Enum.Material.Sand,
		peakMaterial = Enum.Material.Sand,
		slopeThreshold = 0.8,
		peakHeight = 999,
		rockMinHeight = 999,
	},
	
	Rocky = {
		name = "Rocky",
		temperatureMin = 0.4,
		temperatureMax = 0.7,
		moistureMin = 0.0,
		moistureMax = 0.3,
		priority = 1,
		
		noiseScale = 0.006,
		noiseAmplitude = 14,
		noiseOctaves = 2,
		noisePersistence = 0.3,
		baseHeight = 4,
		
		defaultMaterial = Enum.Material.Rock,
		slopeMaterial = Enum.Material.Rock,
		peakMaterial = Enum.Material.Rock,
		slopeThreshold = 0.45,
		peakHeight = 999,
		rockMinHeight = 0,
	},
	
	Badlands = {
		name = "Badlands",
		temperatureMin = 0.5,
		temperatureMax = 0.85,
		moistureMin = 0.0,
		moistureMax = 0.25,
		priority = 2,
		
		noiseScale = 0.007,
		noiseAmplitude = 16,
		noiseOctaves = 3,
		noisePersistence = 0.35,
		baseHeight = 3,
		
		defaultMaterial = Enum.Material.Sandstone,
		slopeMaterial = Enum.Material.Rock,
		peakMaterial = Enum.Material.Sandstone,
		slopeThreshold = 0.45,
		peakHeight = 999,
		rockMinHeight = 8,
	},
	
	-- === HOT BIOMES (Temperature 0.7 - 1.0) ===
	Desert = {
		name = "Desert",
		temperatureMin = 0.7,
		temperatureMax = 1.0,
		moistureMin = 0.0,
		moistureMax = 0.2,
		priority = 2,
		
		noiseScale = 0.003,
		noiseAmplitude = 8,
		noiseOctaves = 2,
		noisePersistence = 0.25,
		baseHeight = 0,
		
		defaultMaterial = Enum.Material.Sand,
		slopeMaterial = Enum.Material.Sand,
		peakMaterial = Enum.Material.Sand,
		slopeThreshold = 0.9,
		peakHeight = 999,
		rockMinHeight = 999,
	},
	
	Jungle = {
		name = "Jungle",
		temperatureMin = 0.7,
		temperatureMax = 1.0,
		moistureMin = 0.6,
		moistureMax = 1.0,
		priority = 2,
		
		noiseScale = 0.005,
		noiseAmplitude = 12,
		noiseOctaves = 2,
		noisePersistence = 0.3,
		baseHeight = 2,
		
		defaultMaterial = Enum.Material.Grass,
		slopeMaterial = Enum.Material.Grass,
		peakMaterial = Enum.Material.Grass,
		slopeThreshold = 0.7,
		peakHeight = 999,
		rockMinHeight = 999,
	},
	
	Swamp = {
		name = "Swamp",
		temperatureMin = 0.55,
		temperatureMax = 0.85,
		moistureMin = 0.75,
		moistureMax = 1.0,
		priority = 2,
		
		noiseScale = 0.004,
		noiseAmplitude = 4,
		noiseOctaves = 2,
		noisePersistence = 0.2,
		baseHeight = -1,
		
		defaultMaterial = Enum.Material.Mud,
		slopeMaterial = Enum.Material.Mud,
		peakMaterial = Enum.Material.Grass,
		slopeThreshold = 0.9,
		peakHeight = 5,
		rockMinHeight = 999,
	},
	
	-- === VOLCANIC (Special - high temperature, any moisture) ===
	Volcanic = {
		name = "Volcanic",
		temperatureMin = 0.85,
		temperatureMax = 1.0,
		moistureMin = 0.0,
		moistureMax = 0.4,
		priority = 3,  -- High priority when conditions match
		
		noiseScale = 0.007,
		noiseAmplitude = 20,
		noiseOctaves = 3,
		noisePersistence = 0.38,
		baseHeight = 6,
		
		defaultMaterial = Enum.Material.Basalt,
		slopeMaterial = Enum.Material.Basalt,
		peakMaterial = Enum.Material.CrackedLava,
		slopeThreshold = 0.45,
		peakHeight = 25,
		rockMinHeight = 0,
	},
}

-- Build a list for iteration
local BIOME_LIST = {}
for name, biome in pairs(BIOMES) do
	biome.name = name
	table.insert(BIOME_LIST, biome)
end

-- Sort by priority (higher priority checked first)
table.sort(BIOME_LIST, function(a, b)
	return (a.priority or 0) > (b.priority or 0)
end)

local Terrain = Workspace.Terrain

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                            NOISE FUNCTIONS                                 ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

local function fractalNoise(x, z, octaves, persistence, scale, seed)
	seed = seed or 0
	local total = 0
	local frequency = scale
	local amplitude = 1
	local maxValue = 0
	
	for _ = 1, octaves do
		total += math.noise(x * frequency + seed, z * frequency + seed) * amplitude
		maxValue += amplitude
		amplitude *= persistence
		frequency *= 2
	end
	
	return total / maxValue
end

-- Normalize noise from [-1, 1] to [0, 1]
local function normalizedNoise(x, z, octaves, persistence, scale, seed)
	local n = fractalNoise(x, z, octaves, persistence, scale, seed)
	return math.clamp((n + 1) / 2, 0, 1)
end

-- Voronoi noise for organic cell boundaries
local function voronoiNoise(x, z, cellSize, seed)
	local cellX = math.floor(x / cellSize)
	local cellZ = math.floor(z / cellSize)
	
	local minDist = math.huge
	local secondMinDist = math.huge
	local closestCellX, closestCellZ = cellX, cellZ
	
	-- Check 3x3 neighborhood
	for dx = -1, 1 do
		for dz = -1, 1 do
			local ncx = cellX + dx
			local ncz = cellZ + dz
			
			-- Deterministic random point within cell
			math.randomseed(ncx * 73856093 + ncz * 19349663 + seed)
			local px = (ncx + math.random()) * cellSize
			local pz = (ncz + math.random()) * cellSize
			
			local dist = math.sqrt((x - px)^2 + (z - pz)^2)
			
			if dist < minDist then
				secondMinDist = minDist
				minDist = dist
				closestCellX = ncx
				closestCellZ = ncz
			elseif dist < secondMinDist then
				secondMinDist = dist
			end
		end
	end
	
	-- Return cell ID and edge distance (for blending)
	local cellId = closestCellX * 1000 + closestCellZ
	local edgeFactor = minDist / (minDist + secondMinDist)  -- 0 at center, 0.5 at edge
	
	return cellId, edgeFactor, closestCellX, closestCellZ
end

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                        CLIMATE MAP GENERATION                              ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

local function generateTemperature(x, z, centerX, centerZ, worldWidth, worldDepth, seed)
	-- Base temperature from noise
	local temp = normalizedNoise(
		x, z,
		CLIMATE_CONFIG.TemperatureNoiseOctaves,
		CLIMATE_CONFIG.TemperatureNoisePersistence,
		CLIMATE_CONFIG.TemperatureNoiseScale,
		seed
	)
	
	-- Optional latitude gradient (north = cold, south = warm)
	if CLIMATE_CONFIG.LatitudeGradientEnabled then
		local normalizedZ = (z - centerZ) / worldDepth + 0.5  -- 0 to 1
		local latitudeEffect = normalizedZ * CLIMATE_CONFIG.LatitudeGradientStrength
		temp = math.clamp(temp + latitudeEffect - CLIMATE_CONFIG.LatitudeGradientStrength / 2, 0, 1)
	end
	
	return temp
end

local function generateMoisture(x, z, seed)
	return normalizedNoise(
		x, z,
		CLIMATE_CONFIG.MoistureNoiseOctaves,
		CLIMATE_CONFIG.MoistureNoisePersistence,
		CLIMATE_CONFIG.MoistureNoiseScale,
		seed + 5000  -- Different seed offset for variety
	)
end

local function applyElevationToTemperature(baseTemp, elevation, baseHeight)
	-- Higher elevation = colder
	local elevationAboveBase = math.max(0, elevation - baseHeight)
	local tempReduction = elevationAboveBase * CLIMATE_CONFIG.ElevationTemperatureInfluence
	return math.clamp(baseTemp - tempReduction, 0, 1)
end

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                          BIOME SELECTION                                   ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

local function getBiomeScore(biome, temperature, moisture)
	-- Check if within range
	if temperature < biome.temperatureMin or temperature > biome.temperatureMax then
		return -1
	end
	if moisture < biome.moistureMin or moisture > biome.moistureMax then
		return -1
	end
	
	-- Calculate how well this point matches the biome's ideal range
	local tempCenter = (biome.temperatureMin + biome.temperatureMax) / 2
	local moistCenter = (biome.moistureMin + biome.moistureMax) / 2
	
	local tempDist = math.abs(temperature - tempCenter)
	local moistDist = math.abs(moisture - moistCenter)
	
	-- Lower distance = better match = higher score
	local score = 1 - (tempDist + moistDist) / 2
	
	-- Priority bonus
	score = score + (biome.priority or 0) * 0.1
	
	return score
end

local function selectBiome(temperature, moisture)
	local bestBiome = BIOMES.Plains  -- Default fallback
	local bestScore = -1
	
	for _, biome in ipairs(BIOME_LIST) do
		local score = getBiomeScore(biome, temperature, moisture)
		if score > bestScore then
			bestScore = score
			bestBiome = biome
		end
	end
	
	return bestBiome
end

-- Get biome with Voronoi influence for organic boundaries
local function getBiomeAtPosition(x, z, centerX, centerZ, worldWidth, worldDepth, seed, elevation)
	-- Generate climate values
	local temperature = generateTemperature(x, z, centerX, centerZ, worldWidth, worldDepth, seed)
	local moisture = generateMoisture(x, z, seed)
	
	-- Apply elevation to temperature
	if elevation then
		temperature = applyElevationToTemperature(temperature, elevation, CONFIG.BaseHeight)
	end
	
	-- Get base biome from climate
	local baseBiome = selectBiome(temperature, moisture)
	
	-- Apply Voronoi for organic region boundaries (optional)
	if CLIMATE_CONFIG.VoronoiEnabled then
		local cellSize = math.max(worldWidth, worldDepth) / math.sqrt(CLIMATE_CONFIG.VoronoiCellCount)
		local cellId, edgeFactor, cellX, cellZ = voronoiNoise(x, z, cellSize, seed + 10000)
		
		-- Near cell boundaries, potentially blend with neighbor
		if edgeFactor > 0.35 then
			-- Get neighboring cell's climate (use cell center)
			local neighborX = (cellX + 0.5) * cellSize
			local neighborZ = (cellZ + 0.5) * cellSize
			
			-- Add some variation based on cell ID
			math.randomseed(cellId)
			local cellTempOffset = (math.random() - 0.5) * 0.2
			local cellMoistOffset = (math.random() - 0.5) * 0.2
			
			local blendedTemp = math.clamp(temperature + cellTempOffset * CLIMATE_CONFIG.VoronoiInfluence, 0, 1)
			local blendedMoist = math.clamp(moisture + cellMoistOffset * CLIMATE_CONFIG.VoronoiInfluence, 0, 1)
			
			baseBiome = selectBiome(blendedTemp, blendedMoist)
		end
	end
	
	return baseBiome, temperature, moisture
end

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                        TERRAIN HEIGHT GENERATION                           ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

local function getHeightAt(x, z, seed, biome)
	biome = biome or BIOMES.Plains
	
	local noise = fractalNoise(
		x + seed, z + seed,
		biome.noiseOctaves or 2,
		biome.noisePersistence or 0.3,
		biome.noiseScale or 0.005,
		0
	)
	
	local height = (biome.baseHeight or CONFIG.BaseHeight) + noise * (biome.noiseAmplitude or 10)
	
	-- Add subtle detail noise
	height = height + math.noise((x + seed * 2) * 0.02, (z + seed * 2) * 0.02) * 0.8
	
	return height
end

local function getMaterialAt(height, slope, biome)
	local peakHeight = biome.peakHeight or 999
	local slopeThreshold = biome.slopeThreshold or 0.6
	local rockMinHeight = biome.rockMinHeight or 999
	
	if height > peakHeight then
		return biome.peakMaterial or Enum.Material.Snow
	end
	
	if height >= rockMinHeight and slope > slopeThreshold then
		return biome.slopeMaterial or Enum.Material.Rock
	end
	
	return biome.defaultMaterial or Enum.Material.Grass
end

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                    BIOME BLENDING FOR SMOOTH TRANSITIONS                   ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

local BIOME_NUMERIC_KEYS = {
	"noiseScale", "noiseAmplitude", "noiseOctaves", "noisePersistence",
	"baseHeight", "slopeThreshold", "peakHeight", "rockMinHeight"
}

local function blendBiomeConfigs(biomeA, biomeB, t)
	-- t = 0 means 100% biomeA, t = 1 means 100% biomeB
	local blended = {}
	
	for _, key in ipairs(BIOME_NUMERIC_KEYS) do
		local a = biomeA[key] or 0
		local b = biomeB[key] or 0
		blended[key] = a + (b - a) * t
	end
	
	blended.noiseOctaves = math.max(1, math.floor(blended.noiseOctaves + 0.5))
	
	-- Use dominant biome's materials
	local dominant = t < 0.5 and biomeA or biomeB
	blended.defaultMaterial = dominant.defaultMaterial
	blended.slopeMaterial = dominant.slopeMaterial
	blended.peakMaterial = dominant.peakMaterial
	blended.name = string.format("Blend(%s->%s)", biomeA.name or "?", biomeB.name or "?")
	
	return blended
end

-- Get blended biome config with smooth transitions between regions
local function getBlendedBiomeConfig(x, z, centerX, centerZ, worldWidth, worldDepth, seed)
	-- Sample biomes at corners of a small area around this point
	local sampleRadius = 16  -- Sample area size
	
	local samples = {}
	local weights = {}
	local totalWeight = 0
	
	-- Sample at 4 corners
	local offsets = {
		{-sampleRadius, -sampleRadius},
		{sampleRadius, -sampleRadius},
		{-sampleRadius, sampleRadius},
		{sampleRadius, sampleRadius},
	}
	
	for i, offset in ipairs(offsets) do
		local sx = x + offset[1]
		local sz = z + offset[2]
		local biome = getBiomeAtPosition(sx, sz, centerX, centerZ, worldWidth, worldDepth, seed, nil)
		
		-- Weight by inverse distance (center point gets highest influence from all corners)
		local dist = math.sqrt(offset[1]^2 + offset[2]^2)
		local weight = 1 / (dist + 1)
		
		samples[i] = biome
		weights[i] = weight
		totalWeight = totalWeight + weight
	end
	
	-- If all samples are the same biome, just return it
	local allSame = true
	for i = 2, #samples do
		if samples[i].name ~= samples[1].name then
			allSame = false
			break
		end
	end
	
	if allSame then
		return samples[1]
	end
	
	-- Blend numeric values
	local blended = {}
	for _, key in ipairs(BIOME_NUMERIC_KEYS) do
		local value = 0
		for i, biome in ipairs(samples) do
			value = value + (biome[key] or 0) * (weights[i] / totalWeight)
		end
		blended[key] = value
	end
	
	blended.noiseOctaves = math.max(1, math.floor(blended.noiseOctaves + 0.5))
	
	-- Use the dominant biome's materials
	local dominantBiome = samples[1]
	local dominantWeight = weights[1]
	for i = 2, #samples do
		if weights[i] > dominantWeight then
			dominantWeight = weights[i]
			dominantBiome = samples[i]
		end
	end
	
	blended.defaultMaterial = dominantBiome.defaultMaterial
	blended.slopeMaterial = dominantBiome.slopeMaterial
	blended.peakMaterial = dominantBiome.peakMaterial
	blended.name = "Blended"
	
	return blended
end

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         BASEPLATE HELPERS                                  ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

local function getBaseplateInfo()
	-- First try to get info from WorldInitService (preferred)
	local WorldInitService = nil
	pcall(function()
		WorldInitService = Knit.GetService("WorldInitService")
	end)
	
	if WorldInitService then
		local info = WorldInitService:GetBaseplateInfo()
		if info then
			return {
				position = info.position,
				size = info.size,
				topY = info.topY,
			}
		end
	end
	
	-- Fallback: Try GridService for grid dimensions
	local GridService = nil
	pcall(function()
		GridService = Knit.GetService("GridService")
	end)
	
	if GridService then
		local gridData = GridService:GetGridData()
		if gridData and gridData.cellSize > 0 then
			local totalWidth = gridData.width * gridData.cellSize
			local totalDepth = gridData.depth * gridData.cellSize
			return {
				position = Vector3.new(gridData.centerX, gridData.topY, gridData.centerZ),
				size = Vector3.new(totalWidth, 1, totalDepth),
				topY = gridData.topY,
			}
		end
	end
	
	-- Legacy fallback: look for physical Baseplate
	local baseplate = Workspace:FindFirstChild("Baseplate")
	if baseplate and baseplate:IsA("BasePart") then
		return {
			position = baseplate.Position,
			size = baseplate.Size,
			topY = baseplate.Position.Y + baseplate.Size.Y / 2,
		}
	end
	
	-- Default fallback (3x3 grid of 128x128 baseplates = 384x384)
	return {
		position = Vector3.new(0, 0, 0),
		size = Vector3.new(384, 1, 384),
		topY = 0,
	}
end

local function createBaseplateGrid(centerX, centerZ)
	local baseplates = {}
	local gridSize = CONFIG.BaseplateGridSize
	local baseplateSize = CONFIG.BaseplateSize
	local spacing = baseplateSize.X
	
	local totalWidth = gridSize * spacing
	local totalDepth = gridSize * spacing
	local startX = centerX - (totalWidth / 2) + (spacing / 2)
	local startZ = centerZ - (totalDepth / 2) + (spacing / 2)
	
	local baseplateFolder = Workspace:FindFirstChild("TerrainBaseplates")
	if not baseplateFolder then
		baseplateFolder = Instance.new("Folder")
		baseplateFolder.Name = "TerrainBaseplates"
		baseplateFolder.Parent = Workspace
	end
	
	for x = 1, gridSize do
		baseplates[x] = {}
		for z = 1, gridSize do
			local positionX = startX + (x - 1) * spacing
			local positionZ = startZ + (z - 1) * spacing
			local positionY = CONFIG.BaseHeight + (baseplateSize.Y / 2)
			
			local baseplate = Instance.new("Part")
			baseplate.Name = string.format("Baseplate_%d_%d", x, z)
			baseplate.Size = baseplateSize
			baseplate.Position = Vector3.new(positionX, positionY, positionZ)
			baseplate.Anchored = true
			baseplate.CanCollide = false
			baseplate.Transparency = 0.5
			baseplate.BrickColor = BrickColor.new("Bright green")
			baseplate.Material = Enum.Material.Plastic
			baseplate.Parent = baseplateFolder
			
			baseplates[x][z] = baseplate
		end
	end
	
	print(string.format("[TerrainService] Created %dx%d baseplate grid", gridSize, gridSize))
	return baseplates, baseplateFolder
end

local function getBaseplateGridInfo(baseplates)
	if not baseplates or #baseplates == 0 then
		return nil
	end
	
	local gridSize = CONFIG.BaseplateGridSize
	local baseplateSize = CONFIG.BaseplateSize
	
	local firstBaseplate = baseplates[1][1]
	local lastBaseplate = baseplates[gridSize][gridSize]
	if not firstBaseplate or not lastBaseplate then
		return nil
	end
	
	local spacing = baseplateSize.X
	local totalWidth = gridSize * spacing
	local totalDepth = gridSize * spacing
	
	local centerX = (firstBaseplate.Position.X + lastBaseplate.Position.X) / 2
	local centerZ = (firstBaseplate.Position.Z + lastBaseplate.Position.Z) / 2
	local topY = firstBaseplate.Position.Y + (baseplateSize.Y / 2)
	
	return {
		position = Vector3.new(centerX, topY, centerZ),
		size = Vector3.new(totalWidth, baseplateSize.Y, totalDepth),
		topY = topY,
		baseplates = baseplates,
	}
end

local function removeBaseplateGrid(baseplateFolder)
	if baseplateFolder then
		baseplateFolder:Destroy()
		print("[TerrainService] Removed baseplate grid")
	end
end

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                       TERRAIN OPERATIONS                                   ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

function TerrainService:ClearTerrain()
	print("[TerrainService] Clearing all terrain...")
	Terrain:Clear()
	self._biomeCache = {}
	print("[TerrainService] Terrain cleared")
end

function TerrainService:ClearRegion(position, size)
	local region = Region3.new(
		position - size / 2,
		position + size / 2
	):ExpandToGrid(CONFIG.Resolution)
	Terrain:FillRegion(region, CONFIG.Resolution, Enum.Material.Air)
end

function TerrainService:FillBlock(position, size, material)
	material = material or Enum.Material.Grass
	Terrain:FillBlock(CFrame.new(position), size, material)
end

function TerrainService:FillBall(center, radius, material)
	material = material or Enum.Material.Grass
	Terrain:FillBall(center, radius, material)
end

function TerrainService:FillCylinder(cframe, height, radius, material)
	material = material or Enum.Material.Grass
	Terrain:FillCylinder(cframe, height, radius, material)
end

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                    MAIN TERRAIN GENERATION                                 ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

function TerrainService:GenerateTerrain(options)
	options = options or {}
	
	local startTime = tick()
	print("[TerrainService] Generating terrain with CLIMATE-BASED biome system...")
	
	-- Get LoadingService for progress updates
	local LoadingService = nil
	pcall(function()
		LoadingService = Knit.GetService("LoadingService")
	end)
	
	local function reportProgress(current, total, message)
		if LoadingService then
			LoadingService:ReportProgress("TerrainService", current, total, message or "Generating terrain")
		end
	end
	
	reportProgress(0, 100, "Preparing terrain generation")
	
	local centerX = options.centerX or 0
	local centerZ = options.centerZ or 0
	local width = options.width or CONFIG.DefaultSize.X
	local depth = options.depth or CONFIG.DefaultSize.Z
	local seed = options.seed or math.random(1, 10000)
	
	print(string.format("[TerrainService] Using seed: %d", seed))
	
	local baseplates
	local baseplateFolder
	local baseplateInfo
	
	if CONFIG.CreateBaseplateGrid then
		reportProgress(1, 100, "Creating baseplate grid...")
		baseplates, baseplateFolder = createBaseplateGrid(centerX, centerZ)
		baseplateInfo = getBaseplateGridInfo(baseplates)
		
		self._baseplates = baseplates
		self._baseplateInfo = baseplateInfo
		
		if baseplateInfo then
			centerX = baseplateInfo.position.X
			centerZ = baseplateInfo.position.Z
			width = baseplateInfo.size.X
			depth = baseplateInfo.size.Z
			CONFIG.BaseHeight = baseplateInfo.topY
		end
	elseif CONFIG.UseBaseplate then
		baseplateInfo = getBaseplateInfo()
		if baseplateInfo then
			centerX = baseplateInfo.position.X
			centerZ = baseplateInfo.position.Z
			width = baseplateInfo.size.X
			depth = baseplateInfo.size.Z
			CONFIG.BaseHeight = baseplateInfo.topY
		end
	end
	
	print(string.format("[TerrainService] Terrain area: %.0f x %.0f centered at (%.0f, %.0f)", 
		width, depth, centerX, centerZ))
	
	-- Generate climate preview
	reportProgress(3, 100, "Generating climate map...")
	
	local biomeDistribution = {}
	local sampleStep = 32
	for sx = centerX - width/2, centerX + width/2, sampleStep do
		for sz = centerZ - depth/2, centerZ + depth/2, sampleStep do
			local biome = getBiomeAtPosition(sx, sz, centerX, centerZ, width, depth, seed, nil)
			biomeDistribution[biome.name] = (biomeDistribution[biome.name] or 0) + 1
		end
	end
	
	print("[TerrainService] Biome distribution preview:")
	for biomeName, count in pairs(biomeDistribution) do
		print(string.format("  %s: %d samples", biomeName, count))
	end
	
	local resolution = options.resolution or CONFIG.Resolution
	local halfWidth = width / 2
	local halfDepth = depth / 2
	
	local chunkSize = 64
	local totalChunks = math.ceil(width / chunkSize) * math.ceil(depth / chunkSize)
	local chunksProcessed = 0
	
	reportProgress(5, 100, "Generating terrain chunks")
	
	-- Create base floor FIRST to guarantee no holes at bottom
	if CONFIG.BaseFloorEnabled then
		reportProgress(4, 100, "Creating solid base layer...")
		self:CreateBaseFloor(centerX, centerZ, width, depth)
	end
	
	-- Main terrain generation loop with overlap to prevent seams
	local chunkOverlap = CONFIG.ChunkOverlap or 4
	for chunkX = centerX - halfWidth, centerX + halfWidth - chunkSize, chunkSize do
		for chunkZ = centerZ - halfDepth, centerZ + halfDepth - chunkSize, chunkSize do
			-- Add overlap to prevent seams between chunks
			local minX = chunkX - chunkOverlap
			local maxX = math.min(chunkX + chunkSize + chunkOverlap, centerX + halfWidth + chunkOverlap)
			local minZ = chunkZ - chunkOverlap
			local maxZ = math.min(chunkZ + chunkSize + chunkOverlap, centerZ + halfDepth + chunkOverlap)
			
			-- Sample biome at chunk center for coarse estimation
			local chunkCenterX = (minX + maxX) / 2
			local chunkCenterZ = (minZ + maxZ) / 2
			local biome = getBlendedBiomeConfig(chunkCenterX, chunkCenterZ, centerX, centerZ, width, depth, seed)
			
			-- Calculate height range for this chunk
			local baseHeight = biome.baseHeight or CONFIG.BaseHeight
			local maxHeight = baseHeight
			local minHeight = baseHeight
			
			for x = minX, maxX, resolution do
				for z = minZ, maxZ, resolution do
					local positionBiome = getBlendedBiomeConfig(x, z, centerX, centerZ, width, depth, seed)
					local height = getHeightAt(x, z, seed, positionBiome)
					maxHeight = math.max(maxHeight, height)
					minHeight = math.min(minHeight, height)
				end
			end
			
			local regionMin = Vector3.new(minX, minHeight - 10, minZ)
			local regionMax = Vector3.new(maxX, maxHeight + 5, maxZ)
			local region = Region3.new(regionMin, regionMax):ExpandToGrid(resolution)
			
			local materials, occupancies = Terrain:ReadVoxels(region, resolution)
			local regionSize = materials.Size
			
			for ix = 1, regionSize.X do
				for iz = 1, regionSize.Z do
					local worldX = regionMin.X + (ix - 1) * resolution
					local worldZ = regionMin.Z + (iz - 1) * resolution
					
					local positionBiome = getBlendedBiomeConfig(worldX, worldZ, centerX, centerZ, width, depth, seed)
					local targetHeight = getHeightAt(worldX, worldZ, seed, positionBiome)
					
					-- Calculate slope once for this column
					local heightNorth = getHeightAt(worldX, worldZ + resolution, seed, positionBiome)
					local heightSouth = getHeightAt(worldX, worldZ - resolution, seed, positionBiome)
					local heightEast = getHeightAt(worldX + resolution, worldZ, seed, positionBiome)
					local heightWest = getHeightAt(worldX - resolution, worldZ, seed, positionBiome)
					local slope = math.max(
						math.abs(heightNorth - heightSouth),
						math.abs(heightEast - heightWest)
					) / (resolution * 2)
					
					-- Minimum terrain floor
					local minTerrainY = CONFIG.BaseHeight - CONFIG.MinTerrainThickness
					
					for iy = 1, regionSize.Y do
						local worldY = regionMin.Y + (iy - 1) * resolution
						
						-- Fill if below surface OR below minimum terrain floor (prevents holes)
						if worldY < targetHeight or worldY < minTerrainY then
							materials[ix][iy][iz] = getMaterialAt(targetHeight, slope, positionBiome)
							occupancies[ix][iy][iz] = 1  -- Full occupancy, no partial fills
						else
							materials[ix][iy][iz] = Enum.Material.Air
							occupancies[ix][iy][iz] = 0
						end
					end
				end
			end
			
			Terrain:WriteVoxels(region, resolution, materials, occupancies)
			
			chunksProcessed += 1
			
			local progress = 5 + (chunksProcessed / totalChunks) * 80
			local biomeName = biome and biome.name or "Default"
			reportProgress(math.floor(progress), 100, string.format("Generating terrain (%d/%d) - %s", chunksProcessed, totalChunks, biomeName))
			
			if chunksProcessed % 4 == 0 then
				task.wait()
			end
		end
	end
	
	-- Smoothing passes
	reportProgress(85, 100, "Smoothing terrain")
	
	if options.smooth ~= false then
		for pass = 1, CONFIG.SmoothingPasses do
			reportProgress(85 + (pass - 1) * 3, 100, string.format("Smoothing terrain (pass %d/%d)", pass, CONFIG.SmoothingPasses))
			self:SmoothTerrain(centerX, centerZ, width, depth)
			if pass < CONFIG.SmoothingPasses then
				task.wait(0.1)
			end
		end
	end
	
	-- Add hills
	if CONFIG.AddHills then
		reportProgress(92, 100, "Adding hills...")
		self:AddRandomHills(centerX, centerZ, width, depth, seed)
	end
	
	-- Add caves (with safety limits to prevent surface holes)
	if CONFIG.AddCaves then
		reportProgress(93, 100, "Adding caves...")
		self:AddRandomCaves(centerX, centerZ, width, depth, seed)
	end
	
	-- Repair any holes created by caves or chunk boundaries
	if CONFIG.FillGapsEnabled then
		reportProgress(95, 100, "Repairing terrain holes...")
		self:RepairTerrainHoles(centerX, centerZ, width, depth)
	end
	
	-- Seal terrain edges to prevent falling into void
	reportProgress(96, 100, "Sealing terrain edges...")
	self:SealTerrainEdges(centerX, centerZ, width, depth)
	
	-- Final smoothing
	if CONFIG.AddHills or CONFIG.AddCaves then
		reportProgress(97, 100, "Final smoothing...")
		self:SmoothTerrain(centerX, centerZ, width, depth)
	end
	
	-- One more hole check after smoothing (smoothing can sometimes create gaps)
	if CONFIG.FillGapsEnabled then
		reportProgress(98, 100, "Final hole verification...")
		self:RepairTerrainHoles(centerX, centerZ, width, depth)
	end
	
	-- Store baseplate positions
	if baseplates then
		self._baseplatePositions = {}
		local gridSize = CONFIG.BaseplateGridSize
		for x = 1, gridSize do
			for z = 1, gridSize do
				local baseplate = baseplates[x][z]
				if baseplate then
					table.insert(self._baseplatePositions, {
						position = baseplate.Position,
						size = baseplate.Size,
						centerX = baseplate.Position.X,
						centerZ = baseplate.Position.Z,
						centerY = baseplate.Position.Y,
						halfWidth = baseplate.Size.X / 2,
						halfDepth = baseplate.Size.Z / 2,
					})
				end
			end
		end
	end
	
	-- Remove baseplates
	if CONFIG.RemoveBaseplatesAfterGen then
		reportProgress(98, 100, "Removing baseplates...")
		if baseplateFolder then
			removeBaseplateGrid(baseplateFolder)
		end
		local existingBaseplate = Workspace:FindFirstChild("Baseplate")
		if existingBaseplate and existingBaseplate:IsA("BasePart") then
			existingBaseplate:Destroy()
		end
	end
	
	reportProgress(100, 100, "Terrain complete")
	
	local elapsed = tick() - startTime
	print(string.format("[TerrainService] Generated terrain in %.2fs (%d chunks)", elapsed, chunksProcessed))
end

function TerrainService:SmoothTerrain(centerX, centerZ, width, depth)
	local paddingY = 50
	
	local region = Region3.new(
		Vector3.new(centerX - width/2, CONFIG.BaseHeight - paddingY, centerZ - depth/2),
		Vector3.new(centerX + width/2, CONFIG.BaseHeight + paddingY, centerZ + depth/2)
	):ExpandToGrid(CONFIG.Resolution)
	
	pcall(function()
		Terrain:SmoothRegion(region, CONFIG.Resolution)
	end)
end

function TerrainService:CreateHill(position, radius, height, material)
	material = material or Enum.Material.Grass
	height = height or 15
	radius = radius or 20
	
	local layers = 10
	for i = 1, layers do
		local layerRatio = i / layers
		local layerRadius = radius * (1 - layerRatio * 0.7)
		local layerHeight = height * layerRatio
		local layerPos = position + Vector3.new(0, layerHeight - height/2, 0)
		
		Terrain:FillBall(layerPos, layerRadius, material)
	end
end

function TerrainService:CreateCave(entrancePosition, radius, depth, entranceRadius)
	radius = radius or 25
	depth = depth or 30
	entranceRadius = entranceRadius or radius * 0.6
	
	local rayOrigin = Vector3.new(entrancePosition.X, entrancePosition.Y + 100, entrancePosition.Z)
	local rayDirection = Vector3.new(0, -200, 0)
	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	raycastParams.FilterDescendantsInstances = {}
	
	local raycastResult = Workspace:Raycast(rayOrigin, rayDirection, raycastParams)
	local surfaceY = raycastResult and raycastResult.Position.Y or entrancePosition.Y
	
	-- SAFETY: Don't create caves too close to surface to prevent holes
	local minSurfaceBuffer = CONFIG.MinTerrainThickness + 5  -- Keep caves below this depth
	local safeStartY = surfaceY - minSurfaceBuffer
	
	-- SAFETY: Limit cave depth to not go below base floor
	local minY = CONFIG.BaseHeight - CONFIG.BaseFloorDepth + radius
	local maxCaveDepth = math.max(10, safeStartY - minY)
	depth = math.min(depth, maxCaveDepth)
	
	-- Only create cave if there's enough depth
	if depth < 15 then
		return  -- Not enough space for a cave
	end
	
	-- Create entrance - START BELOW SURFACE BUFFER
	local entranceDepth = depth * 0.3
	for i = 1, 5 do
		local layerRatio = i / 5
		local layerRadius = entranceRadius * (1 - layerRatio * 0.3)
		local layerDepth = entranceDepth * layerRatio
		local layerPos = Vector3.new(entrancePosition.X, safeStartY - layerDepth, entrancePosition.Z)
		
		-- Safety check: don't carve too close to surface
		if layerPos.Y < surfaceY - minSurfaceBuffer then
			Terrain:FillBall(layerPos, layerRadius, Enum.Material.Air)
		end
	end
	
	-- Create main chamber - UNDERGROUND ONLY
	local caveCenter = Vector3.new(entrancePosition.X, safeStartY - depth * 0.5, entrancePosition.Z)
	
	-- Safety: ensure chamber doesn't breach surface
	if caveCenter.Y + radius > surfaceY - minSurfaceBuffer then
		caveCenter = Vector3.new(caveCenter.X, surfaceY - minSurfaceBuffer - radius, caveCenter.Z)
	end
	
	for i = 1, 10 do
		local layerRatio = i / 10
		local layerRadius = radius * (1 - layerRatio * 0.4)
		local layerHeight = depth * 0.4 * layerRatio
		local layerPos = Vector3.new(entrancePosition.X, caveCenter.Y + layerHeight - depth * 0.2, entrancePosition.Z)
		
		-- Safety check: only carve if safely underground
		if layerPos.Y + layerRadius < surfaceY - minSurfaceBuffer then
			Terrain:FillBall(layerPos, layerRadius, Enum.Material.Air)
		end
	end
	
	-- Create connecting tunnel - STAY UNDERGROUND
	for i = 1, 8 do
		local t = i / 8
		local tunnelY = safeStartY - (entranceDepth + (depth * 0.5 - entranceDepth) * t)
		local tunnelRadius = entranceRadius * 0.6
		local tunnelPos = Vector3.new(entrancePosition.X, tunnelY, entrancePosition.Z)
		
		-- Safety check
		if tunnelPos.Y + tunnelRadius < surfaceY - minSurfaceBuffer then
			Terrain:FillBall(tunnelPos, tunnelRadius, Enum.Material.Air)
		end
	end
end

function TerrainService:AddRandomHills(centerX, centerZ, width, depth, seed)
	math.randomseed(seed)
	
	for i = 1, CONFIG.HillCount do
		local x = centerX + (math.random() - 0.5) * width * 0.9
		local z = centerZ + (math.random() - 0.5) * depth * 0.9
		
		local rayOrigin = Vector3.new(x, CONFIG.BaseHeight + 100, z)
		local rayDirection = Vector3.new(0, -200, 0)
		local raycastParams = RaycastParams.new()
		raycastParams.FilterType = Enum.RaycastFilterType.Exclude
		raycastParams.FilterDescendantsInstances = {}
		
		local raycastResult = Workspace:Raycast(rayOrigin, rayDirection, raycastParams)
		local surfaceY = raycastResult and raycastResult.Position.Y or CONFIG.BaseHeight
		
		local radius = math.random(CONFIG.HillMinRadius, CONFIG.HillMaxRadius)
		local height = math.random(CONFIG.HillMinHeight, CONFIG.HillMaxHeight)
		local hillPos = Vector3.new(x, surfaceY, z)
		
		local material = surfaceY > CONFIG.BaseHeight + 15 and Enum.Material.Rock or Enum.Material.Grass
		
		self:CreateHill(hillPos, radius, height, material)
		
		if i % 3 == 0 then
			task.wait()
		end
	end
	
	math.randomseed(tick())
end

function TerrainService:AddRandomCaves(centerX, centerZ, width, depth, seed)
	math.randomseed(seed + 1000)
	
	for i = 1, CONFIG.CaveCount do
		local x = centerX + (math.random() - 0.5) * width * 0.9
		local z = centerZ + (math.random() - 0.5) * depth * 0.9
		
		local rayOrigin = Vector3.new(x, CONFIG.BaseHeight + 100, z)
		local rayDirection = Vector3.new(0, -200, 0)
		local raycastParams = RaycastParams.new()
		raycastParams.FilterType = Enum.RaycastFilterType.Exclude
		raycastParams.FilterDescendantsInstances = {}
		
		local raycastResult = Workspace:Raycast(rayOrigin, rayDirection, raycastParams)
		local surfaceY = raycastResult and raycastResult.Position.Y or CONFIG.BaseHeight
		
		local radius = math.random(CONFIG.CaveMinRadius, CONFIG.CaveMaxRadius)
		local caveDepth = math.random(CONFIG.CaveMinDepth, CONFIG.CaveMaxDepth)
		local entranceRadius = radius * 0.6
		local cavePos = Vector3.new(x, surfaceY, z)
		
		self:CreateCave(cavePos, radius, caveDepth, entranceRadius)
		
		if i % 2 == 0 then
			task.wait()
		end
	end
	
	math.randomseed(tick())
end

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                           KNIT LIFECYCLE                                   ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

function TerrainService:KnitInit()
	print("[TerrainService] Initializing with CLIMATE-BASED biome system...")
end

function TerrainService:KnitStart()
	print("[TerrainService] Starting...")
	
	-- Only auto-generate if _autoStart is true (legacy mode)
	-- WorldInitService will call GenerateTerrainWithBaseplates() instead
	if self._autoStart then
		local LoadingService = nil
		pcall(function()
			LoadingService = Knit.GetService("LoadingService")
		end)
		
		if CONFIG.TerrainEnabled then
			if LoadingService then
				LoadingService:UpdateStatus("TerrainService", "Generating terrain...", 0)
			end
			
			local success, err = pcall(function()
				self:GenerateTerrain()
			end)
			
			if not success then
				warn("[TerrainService] Terrain generation failed:", err)
			end
			
			if LoadingService then
				LoadingService:MarkStepComplete("TerrainService")
			end
		else
			print("[TerrainService] Terrain generation disabled, skipping...")
			if LoadingService then
				LoadingService:MarkStepComplete("TerrainService")
			end
		end
	else
		print("[TerrainService] Waiting for WorldInitService to generate terrain...")
	end
end

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║               WORLDINITSERVICE INTEGRATION                                 ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

-- Generate terrain using baseplate info from WorldInitService
function TerrainService:GenerateTerrainWithBaseplates(baseplateInfo)
	if not baseplateInfo then
		warn("[TerrainService] No baseplate info provided!")
		return false
	end
	
	print("[TerrainService] Generating terrain with baseplate info from WorldInitService...")
	
	-- Store baseplate info
	self._baseplateInfo = baseplateInfo
	
	-- Generate terrain using the provided baseplate dimensions
	local options = {
		centerX = baseplateInfo.position.X,
		centerZ = baseplateInfo.position.Z,
		width = baseplateInfo.size.X,
		depth = baseplateInfo.size.Z,
		seed = math.random(1, 10000),
	}
	
	-- Update CONFIG with baseplate info
	CONFIG.BaseHeight = baseplateInfo.topY
	CONFIG.CreateBaseplateGrid = false  -- Don't create baseplates, WorldInitService already did
	CONFIG.RemoveBaseplatesAfterGen = false  -- WorldInitService will remove them
	
	-- Store baseplate positions for other services
	if baseplateInfo.baseplates then
		self._baseplatePositions = {}
		local gridSize = baseplateInfo.gridSize or 3
		for x = 1, gridSize do
			for z = 1, gridSize do
				local baseplate = baseplateInfo.baseplates[x] and baseplateInfo.baseplates[x][z]
				if baseplate then
					table.insert(self._baseplatePositions, {
						position = baseplate.Position,
						size = baseplate.Size,
						centerX = baseplate.Position.X,
						centerZ = baseplate.Position.Z,
						centerY = baseplate.Position.Y,
						halfWidth = baseplate.Size.X / 2,
						halfDepth = baseplate.Size.Z / 2,
					})
				end
			end
		end
		print(string.format("[TerrainService] Stored %d baseplate positions", #self._baseplatePositions))
	end
	
	-- Generate terrain
	local success, err = pcall(function()
		self:GenerateTerrain(options)
	end)
	
	if not success then
		warn("[TerrainService] Terrain generation failed:", err)
		return false
	end
	
	print("[TerrainService] Terrain generation complete")
	return true
end

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                            PUBLIC API                                      ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

function TerrainService:GetConfig()
	return CONFIG
end

function TerrainService:GetClimateConfig()
	return CLIMATE_CONFIG
end

function TerrainService:SetConfig(key, value)
	if CONFIG[key] ~= nil then
		CONFIG[key] = value
		print("[TerrainService] Config updated:", key, "=", value)
	end
end

function TerrainService:SetClimateConfig(key, value)
	if CLIMATE_CONFIG[key] ~= nil then
		CLIMATE_CONFIG[key] = value
		print("[TerrainService] Climate config updated:", key, "=", value)
	end
end

function TerrainService:RegenerateTerrain(options)
	self:ClearTerrain()
	task.wait(0.1)
	self:GenerateTerrain(options)
end

function TerrainService:GetBiomes()
	return BIOMES
end

function TerrainService:GetBiome(biomeName)
	return BIOMES[biomeName]
end

function TerrainService:GetBiomeAt(worldX, worldZ)
	-- Requires baseplateInfo to be set
	if not self._baseplateInfo then
		return BIOMES.Plains
	end
	
	local centerX = self._baseplateInfo.position.X
	local centerZ = self._baseplateInfo.position.Z
	local width = self._baseplateInfo.size.X
	local depth = self._baseplateInfo.size.Z
	
	return getBiomeAtPosition(worldX, worldZ, centerX, centerZ, width, depth, 12345, nil)
end

function TerrainService:GetClimateAt(worldX, worldZ, seed)
	seed = seed or 12345
	
	local centerX = self._baseplateInfo and self._baseplateInfo.position.X or 0
	local centerZ = self._baseplateInfo and self._baseplateInfo.position.Z or 0
	local width = self._baseplateInfo and self._baseplateInfo.size.X or 384
	local depth = self._baseplateInfo and self._baseplateInfo.size.Z or 384
	
	local temperature = generateTemperature(worldX, worldZ, centerX, centerZ, width, depth, seed)
	local moisture = generateMoisture(worldX, worldZ, seed)
	
	return {
		temperature = temperature,
		moisture = moisture,
	}
end

function TerrainService:SetVoronoiEnabled(enabled)
	CLIMATE_CONFIG.VoronoiEnabled = enabled
	print("[TerrainService] Voronoi", enabled and "enabled" or "disabled")
end

function TerrainService:SetVoronoiCellCount(count)
	CLIMATE_CONFIG.VoronoiCellCount = count
	print("[TerrainService] Voronoi cell count set to", count)
end

function TerrainService:GetBaseplateGrid()
	return self._baseplates, self._baseplateInfo
end

function TerrainService:GetBaseplatePositions()
	if #self._baseplatePositions > 0 then
		return self._baseplatePositions
	end
	
	if not self._baseplates then
		return {}
	end
	
	local positions = {}
	local gridSize = CONFIG.BaseplateGridSize
	
	for x = 1, gridSize do
		for z = 1, gridSize do
			local baseplate = self._baseplates[x][z]
			if baseplate and baseplate.Parent then
				table.insert(positions, {
					position = baseplate.Position,
					size = baseplate.Size,
					centerX = baseplate.Position.X,
					centerZ = baseplate.Position.Z,
					centerY = baseplate.Position.Y,
					halfWidth = baseplate.Size.X / 2,
					halfDepth = baseplate.Size.Z / 2,
				})
			end
		end
	end
	
	return positions
end

-- Additional terrain manipulation methods
function TerrainService:PaintRegion(position, size, material)
	local region = Region3.new(
		position - size / 2,
		position + size / 2
	):ExpandToGrid(CONFIG.Resolution)
	
	for _, oldMaterial in ipairs(Enum.Material:GetEnumItems()) do
		if oldMaterial ~= Enum.Material.Air and oldMaterial ~= Enum.Material.Water then
			pcall(function()
				Terrain:ReplaceMaterial(region, CONFIG.Resolution, oldMaterial, material)
			end)
		end
	end
end

function TerrainService:ReplaceMaterialRegion(position, size, sourceMaterial, targetMaterial)
	local region = Region3.new(
		position - size / 2,
		position + size / 2
	):ExpandToGrid(CONFIG.Resolution)
	
	pcall(function()
		Terrain:ReplaceMaterial(region, CONFIG.Resolution, sourceMaterial, targetMaterial)
	end)
end

function TerrainService:CreateFlatArea(position, size, height)
	height = height or CONFIG.BaseHeight
	
	local clearRegion = Region3.new(
		Vector3.new(position.X - size.X/2, height, position.Z - size.Z/2),
		Vector3.new(position.X + size.X/2, height + 50, position.Z + size.Z/2)
	):ExpandToGrid(CONFIG.Resolution)
	Terrain:FillRegion(clearRegion, CONFIG.Resolution, Enum.Material.Air)
	
	local fillRegion = Region3.new(
		Vector3.new(position.X - size.X/2, height - 10, position.Z - size.Z/2),
		Vector3.new(position.X + size.X/2, height, position.Z + size.Z/2)
	):ExpandToGrid(CONFIG.Resolution)
	Terrain:FillRegion(fillRegion, CONFIG.Resolution, Enum.Material.Grass)
end

function TerrainService:CreateCrater(position, radius, depth)
	depth = depth or radius * 0.5
	
	for i = 1, 8 do
		local layerRatio = i / 8
		local layerRadius = radius * (1 - layerRatio * 0.5)
		local layerDepth = depth * layerRatio
		local layerPos = position - Vector3.new(0, layerDepth, 0)
		
		Terrain:FillBall(layerPos, layerRadius, Enum.Material.Air)
	end
end

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                       HOLE PREVENTION & REPAIR                             ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

-- Create a solid floor layer to guarantee no holes at the bottom
function TerrainService:CreateBaseFloor(centerX, centerZ, width, depth)
	if not CONFIG.BaseFloorEnabled then return end
	
	print("[TerrainService] Creating base floor layer to prevent holes...")
	
	local floorTop = CONFIG.BaseHeight - CONFIG.MinTerrainThickness
	local floorBottom = CONFIG.BaseHeight - CONFIG.BaseFloorDepth - CONFIG.MinTerrainThickness
	
	local region = Region3.new(
		Vector3.new(centerX - width/2 - 10, floorBottom, centerZ - depth/2 - 10),
		Vector3.new(centerX + width/2 + 10, floorTop, centerZ + depth/2 + 10)
	):ExpandToGrid(CONFIG.Resolution)
	
	-- Fill with rock as a solid base
	Terrain:FillRegion(region, CONFIG.Resolution, Enum.Material.Rock)
	
	print("[TerrainService] Base floor created")
end

-- Detect and fill holes in terrain by checking for air pockets below surface
function TerrainService:RepairTerrainHoles(centerX, centerZ, width, depth)
	if not CONFIG.FillGapsEnabled then return end
	
	print("[TerrainService] Scanning and repairing terrain holes...")
	
	local resolution = CONFIG.Resolution
	local holesFound = 0
	local holesFilled = 0
	
	-- Scan in a grid pattern
	local scanStep = resolution * 2  -- Check every 2 voxels
	
	for x = centerX - width/2, centerX + width/2, scanStep do
		for z = centerZ - depth/2, centerZ + depth/2, scanStep do
			-- Raycast down from above to find surface
			local rayOrigin = Vector3.new(x, CONFIG.BaseHeight + 100, z)
			local rayDirection = Vector3.new(0, -200, 0)
			
			local raycastParams = RaycastParams.new()
			raycastParams.FilterType = Enum.RaycastFilterType.Exclude
			raycastParams.FilterDescendantsInstances = {}
			
			local raycastResult = Workspace:Raycast(rayOrigin, rayDirection, raycastParams)
			
			if not raycastResult then
				-- No terrain hit at all - this is a hole!
				holesFound += 1
				
				-- Fill a small column of terrain at this position
				local fillHeight = CONFIG.BaseHeight + 5
				local fillDepth = CONFIG.MinTerrainThickness + 5
				local fillPos = Vector3.new(x, fillHeight - fillDepth/2, z)
				local fillSize = Vector3.new(scanStep + 2, fillDepth, scanStep + 2)
				
				Terrain:FillBlock(CFrame.new(fillPos), fillSize, Enum.Material.Grass)
				holesFilled += 1
			else
				-- Check if there's terrain continuity (no air pockets)
				local surfaceY = raycastResult.Position.Y
				local bottomY = CONFIG.BaseHeight - CONFIG.MinTerrainThickness
				
				-- Sample below surface to check for gaps
				local checkY = surfaceY - resolution * 2
				if checkY > bottomY then
					local checkRegion = Region3.new(
						Vector3.new(x - resolution, checkY - resolution, z - resolution),
						Vector3.new(x + resolution, checkY + resolution, z + resolution)
					):ExpandToGrid(resolution)
					
					local materials, _ = Terrain:ReadVoxels(checkRegion, resolution)
					local hasGap = false
					
					-- Check if center voxel is air when it shouldn't be
					local cx = math.ceil(materials.Size.X / 2)
					local cy = math.ceil(materials.Size.Y / 2)
					local cz = math.ceil(materials.Size.Z / 2)
					
					if materials[cx] and materials[cx][cy] and materials[cx][cy][cz] == Enum.Material.Air then
						hasGap = true
					end
					
					if hasGap then
						holesFound += 1
						-- Fill the gap
						local fillPos = Vector3.new(x, checkY, z)
						Terrain:FillBall(fillPos, resolution * 2, Enum.Material.Rock)
						holesFilled += 1
					end
				end
			end
		end
		
		-- Yield occasionally to prevent timeout
		task.wait()
	end
	
	print(string.format("[TerrainService] Hole repair complete: %d holes found, %d filled", holesFound, holesFilled))
end

-- Ensure terrain edges have proper fill (no cliff dropoffs to void)
function TerrainService:SealTerrainEdges(centerX, centerZ, width, depth)
	print("[TerrainService] Sealing terrain edges...")
	
	local edgeThickness = 20
	local edgeDepth = CONFIG.BaseFloorDepth + 10
	local edgeTop = CONFIG.BaseHeight + 30  -- Above max terrain height
	local edgeBottom = CONFIG.BaseHeight - edgeDepth
	
	-- North edge
	local northRegion = Region3.new(
		Vector3.new(centerX - width/2 - edgeThickness, edgeBottom, centerZ + depth/2),
		Vector3.new(centerX + width/2 + edgeThickness, edgeTop, centerZ + depth/2 + edgeThickness)
	):ExpandToGrid(CONFIG.Resolution)
	Terrain:FillRegion(northRegion, CONFIG.Resolution, Enum.Material.Rock)
	
	-- South edge
	local southRegion = Region3.new(
		Vector3.new(centerX - width/2 - edgeThickness, edgeBottom, centerZ - depth/2 - edgeThickness),
		Vector3.new(centerX + width/2 + edgeThickness, edgeTop, centerZ - depth/2)
	):ExpandToGrid(CONFIG.Resolution)
	Terrain:FillRegion(southRegion, CONFIG.Resolution, Enum.Material.Rock)
	
	-- East edge
	local eastRegion = Region3.new(
		Vector3.new(centerX + width/2, edgeBottom, centerZ - depth/2 - edgeThickness),
		Vector3.new(centerX + width/2 + edgeThickness, edgeTop, centerZ + depth/2 + edgeThickness)
	):ExpandToGrid(CONFIG.Resolution)
	Terrain:FillRegion(eastRegion, CONFIG.Resolution, Enum.Material.Rock)
	
	-- West edge
	local westRegion = Region3.new(
		Vector3.new(centerX - width/2 - edgeThickness, edgeBottom, centerZ - depth/2 - edgeThickness),
		Vector3.new(centerX - width/2, edgeTop, centerZ + depth/2 + edgeThickness)
	):ExpandToGrid(CONFIG.Resolution)
	Terrain:FillRegion(westRegion, CONFIG.Resolution, Enum.Material.Rock)
	
	print("[TerrainService] Terrain edges sealed")
end

-- Get ground height at position - ROBUST version with fallback
function TerrainService:GetGroundHeight(position)
	local x = position.X
	local z = position.Z
	
	-- Cast ray from high above down
	local rayOrigin = Vector3.new(x, CONFIG.BaseHeight + 200, z)
	local rayDirection = Vector3.new(0, -400, 0)
	
	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	local excludeList = {}
	
	-- Exclude non-terrain objects
	local folders = {"ProceduralTrees", "AlienFormations", "WorldBaseplates", "GridCubes", "RedZones", "SpawnedEnemies", "ReservedZones"}
	for _, folderName in ipairs(folders) do
		local folder = Workspace:FindFirstChild(folderName)
		if folder then
			table.insert(excludeList, folder)
		end
	end
	
	raycastParams.FilterDescendantsInstances = excludeList
	
	local raycastResult = Workspace:Raycast(rayOrigin, rayDirection, raycastParams)
	
	if raycastResult then
		return raycastResult.Position.Y
	else
		-- Fallback: use config base height
		return CONFIG.BaseHeight
	end
end

return TerrainService
