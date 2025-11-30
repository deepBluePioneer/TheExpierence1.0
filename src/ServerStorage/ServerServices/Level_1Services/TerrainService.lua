local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local Knit = require(Packages.Knit)

local TerrainService = Knit.CreateService {
	Name = "TerrainService",
	Client = {},
}

-- === CONFIG ===
local CONFIG = {
	-- Terrain generation settings
	TerrainEnabled = true,  -- Set to false if using procedural part mountains instead
	
	-- Area settings (based on baseplate)
	UseBaseplate = true,
	DefaultSize = Vector3.new(512, 100, 512),
	
	-- Perlin noise settings for terrain generation
	NoiseScale = 0.02,        -- Larger = smoother terrain
	NoiseAmplitude = 25,      -- Maximum height variation
	NoiseOctaves = 4,         -- Detail layers
	NoisePersistence = 0.5,   -- How much each octave contributes
	
	-- Height settings
	BaseHeight = 0,           -- Base terrain height
	WaterLevel = -5,          -- Water level (negative = below base)
	
	-- Materials
	DefaultMaterial = Enum.Material.Grass,
	SlopeMaterial = Enum.Material.Rock,
	PeakMaterial = Enum.Material.Snow,
	WaterMaterial = Enum.Material.Water,
	
	-- Thresholds
	SlopeThreshold = 0.6,     -- Steepness for rock
	PeakHeight = 20,          -- Height for snow
	
	-- Resolution (4 is standard, lower = more detail but slower)
	Resolution = 4,
}

local Terrain = Workspace.Terrain

-- === HELPER FUNCTIONS ===

local function getBaseplateInfo()
	local baseplate = Workspace:FindFirstChild("Baseplate")
	if baseplate and baseplate:IsA("BasePart") then
		return {
			position = baseplate.Position,
			size = baseplate.Size,
			topY = baseplate.Position.Y + baseplate.Size.Y / 2,
		}
	end
	return nil
end

-- Multi-octave Perlin noise for more natural terrain
local function fractalNoise(x, z, octaves, persistence, scale)
	local total = 0
	local frequency = scale
	local amplitude = 1
	local maxValue = 0
	
	for i = 1, octaves do
		total = total + math.noise(x * frequency, z * frequency) * amplitude
		maxValue = maxValue + amplitude
		amplitude = amplitude * persistence
		frequency = frequency * 2
	end
	
	return total / maxValue
end

-- Get height at a specific X, Z position
local function getHeightAt(x, z, seed)
	seed = seed or 0
	local noise = fractalNoise(
		x + seed,
		z + seed,
		CONFIG.NoiseOctaves,
		CONFIG.NoisePersistence,
		CONFIG.NoiseScale
	)
	return CONFIG.BaseHeight + noise * CONFIG.NoiseAmplitude
end

-- Determine material based on height and slope
local function getMaterialAt(height, slope)
	if height > CONFIG.PeakHeight then
		return CONFIG.PeakMaterial
	elseif slope > CONFIG.SlopeThreshold then
		return CONFIG.SlopeMaterial
	else
		return CONFIG.DefaultMaterial
	end
end

-- === TERRAIN OPERATIONS ===

function TerrainService:ClearTerrain()
	print("[TerrainService] Clearing all terrain...")
	Terrain:Clear()
	print("[TerrainService] Terrain cleared")
end

function TerrainService:ClearRegion(position, size)
	local region = Region3.new(
		position - size / 2,
		position + size / 2
	)
	Terrain:FillRegion(region, CONFIG.Resolution, Enum.Material.Air)
	print("[TerrainService] Cleared region at", position, "size", size)
end

function TerrainService:FillBlock(position, size, material)
	material = material or CONFIG.DefaultMaterial
	Terrain:FillBlock(CFrame.new(position), size, material)
end

function TerrainService:FillBall(center, radius, material)
	material = material or CONFIG.DefaultMaterial
	Terrain:FillBall(center, radius, material)
end

function TerrainService:FillCylinder(cframe, height, radius, material)
	material = material or CONFIG.DefaultMaterial
	Terrain:FillCylinder(cframe, height, radius, material)
end

-- Generate procedural terrain using Perlin noise
function TerrainService:GenerateTerrain(options)
	options = options or {}
	
	local startTime = tick()
	print("[TerrainService] Generating terrain...")
	
	-- Get LoadingService for progress reporting
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
	
	-- Get area to generate
	local centerX = options.centerX or 0
	local centerZ = options.centerZ or 0
	local width = options.width or CONFIG.DefaultSize.X
	local depth = options.depth or CONFIG.DefaultSize.Z
	local seed = options.seed or math.random(1, 10000)
	
	-- Use baseplate if configured
	if CONFIG.UseBaseplate then
		local baseplateInfo = getBaseplateInfo()
		if baseplateInfo then
			centerX = baseplateInfo.position.X
			centerZ = baseplateInfo.position.Z
			width = baseplateInfo.size.X
			depth = baseplateInfo.size.Z
			CONFIG.BaseHeight = baseplateInfo.topY
		end
	end
	
	local resolution = options.resolution or CONFIG.Resolution
	local halfWidth = width / 2
	local halfDepth = depth / 2
	
	-- Generate terrain in chunks for better performance
	local chunkSize = 64
	local totalChunks = math.ceil(width / chunkSize) * math.ceil(depth / chunkSize)
	local chunksProcessed = 0
	
	reportProgress(5, 100, "Generating terrain chunks")
	
	for chunkX = centerX - halfWidth, centerX + halfWidth - chunkSize, chunkSize do
		for chunkZ = centerZ - halfDepth, centerZ + halfDepth - chunkSize, chunkSize do
			-- Calculate region for this chunk
			local minX = chunkX
			local maxX = math.min(chunkX + chunkSize, centerX + halfWidth)
			local minZ = chunkZ
			local maxZ = math.min(chunkZ + chunkSize, centerZ + halfDepth)
			
			-- Sample heights in this chunk
			local maxHeight = CONFIG.BaseHeight
			local minHeight = CONFIG.BaseHeight
			
			for x = minX, maxX, resolution do
				for z = minZ, maxZ, resolution do
					local height = getHeightAt(x, z, seed)
					maxHeight = math.max(maxHeight, height)
					minHeight = math.min(minHeight, height)
				end
			end
			
			-- Create region
			local regionMin = Vector3.new(minX, minHeight - 10, minZ)
			local regionMax = Vector3.new(maxX, maxHeight + 5, maxZ)
			local region = Region3.new(regionMin, regionMax):ExpandToGrid(resolution)
			
			-- Read current voxels
			local materials, occupancies = Terrain:ReadVoxels(region, resolution)
			local regionSize = materials.Size
			
			-- Modify voxels
			for ix = 1, regionSize.X do
				for iz = 1, regionSize.Z do
					local worldX = regionMin.X + (ix - 1) * resolution
					local worldZ = regionMin.Z + (iz - 1) * resolution
					local targetHeight = getHeightAt(worldX, worldZ, seed)
					
					for iy = 1, regionSize.Y do
						local worldY = regionMin.Y + (iy - 1) * resolution
						
						if worldY < targetHeight then
							-- Calculate slope (approximate)
							local heightNorth = getHeightAt(worldX, worldZ + resolution, seed)
							local heightSouth = getHeightAt(worldX, worldZ - resolution, seed)
							local heightEast = getHeightAt(worldX + resolution, worldZ, seed)
							local heightWest = getHeightAt(worldX - resolution, worldZ, seed)
							local slope = math.max(
								math.abs(heightNorth - heightSouth),
								math.abs(heightEast - heightWest)
							) / (resolution * 2)
							
							materials[ix][iy][iz] = getMaterialAt(targetHeight, slope)
							occupancies[ix][iy][iz] = 1
						elseif worldY < CONFIG.WaterLevel then
							materials[ix][iy][iz] = CONFIG.WaterMaterial
							occupancies[ix][iy][iz] = 1
						else
							materials[ix][iy][iz] = Enum.Material.Air
							occupancies[ix][iy][iz] = 0
						end
					end
				end
			end
			
			-- Write voxels back
			Terrain:WriteVoxels(region, resolution, materials, occupancies)
			
			chunksProcessed = chunksProcessed + 1
			
			-- Report progress
			local progress = 5 + (chunksProcessed / totalChunks) * 85
			reportProgress(math.floor(progress), 100, string.format("Generating terrain (%d/%d chunks)", chunksProcessed, totalChunks))
			
			-- Yield periodically to prevent lag
			if chunksProcessed % 4 == 0 then
				task.wait()
			end
		end
	end
	
	reportProgress(90, 100, "Smoothing terrain")
	
	-- Smooth the terrain for more natural look
	if options.smooth ~= false then
		self:SmoothTerrain(centerX, centerZ, width, depth)
	end
	
	reportProgress(100, 100, "Terrain complete")
	
	local elapsed = tick() - startTime
	print(string.format("[TerrainService] Generated terrain in %.2fs (%d chunks)", elapsed, chunksProcessed))
end

-- Smooth terrain in a region
function TerrainService:SmoothTerrain(centerX, centerZ, width, depth)
	centerX = centerX or 0
	centerZ = centerZ or 0
	width = width or CONFIG.DefaultSize.X
	depth = depth or CONFIG.DefaultSize.Z
	
	local region = Region3.new(
		Vector3.new(centerX - width/2, CONFIG.BaseHeight - 50, centerZ - depth/2),
		Vector3.new(centerX + width/2, CONFIG.BaseHeight + CONFIG.NoiseAmplitude + 20, centerZ + depth/2)
	)
	
	-- SmoothRegion may not be available in all contexts, wrap in pcall
	local success, err = pcall(function()
		Terrain:SmoothRegion(region, CONFIG.Resolution)
	end)
	
	if success then
		print("[TerrainService] Smoothed terrain region")
	else
		warn("[TerrainService] SmoothRegion not available:", err)
	end
end

-- Create a hill at a specific location
function TerrainService:CreateHill(position, radius, height, material)
	material = material or CONFIG.DefaultMaterial
	height = height or 15
	radius = radius or 20
	
	print("[TerrainService] Creating hill at", position)
	
	-- Create layered spheres for a more natural hill shape
	local layers = 10
	for i = 1, layers do
		local layerRatio = i / layers
		local layerRadius = radius * (1 - layerRatio * 0.7)
		local layerHeight = height * layerRatio
		local layerPos = position + Vector3.new(0, layerHeight - height/2, 0)
		
		Terrain:FillBall(layerPos, layerRadius, material)
	end
end

-- Create a crater/hole
function TerrainService:CreateCrater(position, radius, depth)
	depth = depth or radius * 0.5
	
	print("[TerrainService] Creating crater at", position)
	
	-- Carve out a bowl shape
	local layers = 8
	for i = 1, layers do
		local layerRatio = i / layers
		local layerRadius = radius * (1 - layerRatio * 0.5)
		local layerDepth = depth * layerRatio
		local layerPos = position - Vector3.new(0, layerDepth, 0)
		
		Terrain:FillBall(layerPos, layerRadius, Enum.Material.Air)
	end
end

-- Create a flat area (for buildings, spawn areas, etc.)
function TerrainService:CreateFlatArea(position, size, height)
	height = height or CONFIG.BaseHeight
	
	print("[TerrainService] Creating flat area at", position)
	
	-- Clear above
	local clearRegion = Region3.new(
		Vector3.new(position.X - size.X/2, height, position.Z - size.Z/2),
		Vector3.new(position.X + size.X/2, height + 50, position.Z + size.Z/2)
	)
	Terrain:FillRegion(clearRegion, CONFIG.Resolution, Enum.Material.Air)
	
	-- Fill below with ground
	local fillRegion = Region3.new(
		Vector3.new(position.X - size.X/2, height - 10, position.Z - size.Z/2),
		Vector3.new(position.X + size.X/2, height, position.Z + size.Z/2)
	)
	Terrain:FillRegion(fillRegion, CONFIG.Resolution, CONFIG.DefaultMaterial)
end

-- Paint terrain material in a region
function TerrainService:PaintRegion(position, size, material)
	local region = Region3.new(
		position - size / 2,
		position + size / 2
	)
	
	-- Replace all solid materials with the new material
	for _, oldMaterial in ipairs(Enum.Material:GetEnumItems()) do
		if oldMaterial ~= Enum.Material.Air and oldMaterial ~= Enum.Material.Water then
			pcall(function()
				Terrain:ReplaceMaterial(region, CONFIG.Resolution, oldMaterial, material)
			end)
		end
	end
	
	print("[TerrainService] Painted region with", material.Name)
end

-- === KNIT LIFECYCLE ===

function TerrainService:KnitInit()
	print("[TerrainService] Initializing...")
end

function TerrainService:KnitStart()
	print("[TerrainService] Starting...")
	
	-- Get LoadingService
	local LoadingService = nil
	pcall(function()
		LoadingService = Knit.GetService("LoadingService")
	end)
	
	-- Optionally auto-generate terrain on start
	if CONFIG.TerrainEnabled then
		if LoadingService then
			LoadingService:UpdateStatus("TerrainService", "Generating terrain...", 0)
		end
		
		-- Wrap in pcall to ensure MarkStepComplete is called even if there's an error
		local success, err = pcall(function()
			self:GenerateTerrain()
		end)
		
		if not success then
			warn("[TerrainService] Terrain generation failed:", err)
		end
		
		-- Always mark complete even if generation failed
		if LoadingService then
			LoadingService:MarkStepComplete("TerrainService")
		end
	else
		-- Mark complete immediately if terrain generation is disabled
		print("[TerrainService] Terrain generation disabled, skipping...")
		if LoadingService then
			LoadingService:MarkStepComplete("TerrainService")
		end
	end
end

-- === PUBLIC API ===

function TerrainService:GetConfig()
	return CONFIG
end

function TerrainService:SetConfig(key, value)
	if CONFIG[key] ~= nil then
		CONFIG[key] = value
		print("[TerrainService] Config updated:", key, "=", value)
	end
end

function TerrainService:RegenerateTerrain(options)
	self:ClearTerrain()
	task.wait(0.1)
	self:GenerateTerrain(options)
end

return TerrainService

