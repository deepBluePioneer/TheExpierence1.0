--[[
	ReservedZoneService
	Manages different types of zones: Building zones, Radiation zones, and AudioLog zones
	
	AudioLog zones: 10 individual 1x1 cell zones randomly placed on the grid,
	each containing an AudioLog spawned on the surface within the zone.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local CustomPackages = ReplicatedStorage:WaitForChild("CustomPackages")
local Knit = require(Packages.Knit)

-- Zone+ Module
local ZoneRoot = CustomPackages:WaitForChild("ZoneRoot")
local Zone = require(ZoneRoot:WaitForChild("Zone"))

local ReservedZoneService = Knit.CreateService {
	Name = "ReservedZoneService",
	Client = {},
	_gridService = nil,
	_cubeTerrainService = nil,
	_zones = {},  -- Track all zones by type: { [zoneType] = { cells = {}, zoneCube = Part, zone = Zone } }
	_autoStart = false,  -- Set to false to let WorldInitService control initialization
	_isInitialized = false,
}

-- === ZONE TYPE DEFINITIONS ===
local ZONE_TYPES = {
	Building = {
		name = "Building",
		cellTransparency = 1.0,  -- Fully transparent cells
		zoneCubeTransparency = 0.7,
		zoneCubeColor = Color3.fromRGB(255, 255, 0),  -- Yellow
		flattenTerrain = true,
	},
	Radiation = {
		name = "Radiation",
		cellTransparency = 1.0,  -- Fully transparent cells
		zoneCubeTransparency = 0.7,
		zoneCubeColor = Color3.fromRGB(128, 0, 128),  -- Purple
		flattenTerrain = false,
	},
	AudioLog = {
		name = "AudioLog",
		cellTransparency = 1.0,  -- Fully transparent cells
		zoneCubeTransparency = 0.85,
		zoneCubeColor = Color3.fromRGB(50, 150, 255),  -- Blue
		flattenTerrain = false,
		spawnAudioLog = true,  -- Special flag to spawn audio log in zone
	},
	HumanEnemy = {
		name = "HumanEnemy",
		cellTransparency = 1.0,  -- Fully transparent cells
		zoneCubeTransparency = 0.8,
		zoneCubeColor = Color3.fromRGB(255, 80, 80),  -- Red
		flattenTerrain = false,
		spawnEnemies = true,  -- Special flag to spawn enemies in zone
		enemyCount = 5,
	},
}

local CollectionService = game:GetService("CollectionService")

-- === CONFIG ===
local ZONE_CONFIG = {
	BuildingZoneSizeX = 2,      -- Width of building zone (cells) - at center of grid
	BuildingZoneSizeZ = 2,      -- Depth of building zone (cells) - at center of grid
	RadiationZoneSizeX = 2,     -- Width of radiation zone (cells)
	RadiationZoneSizeZ = 2,     -- Depth of radiation zone (cells)
	AudioLogZoneCount = 5,      -- Fallback count (will use AudioLogService.LogCount if available)
	AudioLogZoneSizeX = 1,      -- Width of each audio log zone (cells)
	AudioLogZoneSizeZ = 1,      -- Depth of each audio log zone (cells)
	HumanEnemyZoneSizeX = 3,    -- Width of human enemy zone (cells)
	HumanEnemyZoneSizeZ = 3,    -- Depth of human enemy zone (cells)
	HumanEnemyCount = 5,        -- Number of enemies to spawn in zone
	OwnerId = "ReservedZoneService",
}

-- Tag for zone cubes (used for raycast exclusion)
local ZONE_CUBE_TAG = "reservedZoneCube"

-- === TERRAIN FLATTENING ===

-- Flatten terrain under a zone using its zone cube bounds
local function flattenTerrainUnderZone(self, zoneCube, zoneType)
	if not ZONE_TYPES[zoneType] or not ZONE_TYPES[zoneType].flattenTerrain then
		return  -- Don't flatten if zone type doesn't require it
	end
	
	if not zoneCube then
		warn("[ReservedZoneService] No zone cube provided for flattening")
		return
	end
	
	local CubeTerrainService = self._cubeTerrainService
	if not CubeTerrainService then
		warn("[ReservedZoneService] CubeTerrainService not found, cannot flatten terrain")
		return
	end
	
	-- Get the flat height from GridService topY (the ground level)
	local flatHeight = self._gridService and self._gridService:GetTopY() or 0
	
	--[[print(string.format("[ReservedZoneService] Flattening terrain cubes within %s zone", zoneType))]]
	
	-- Flatten terrain cubes within the zone bounds
	CubeTerrainService:FlattenAreaInZone(zoneCube, flatHeight)
	
	--("[ReservedZoneService] Terrain cubes flattened under " .. zoneType .. " zone")
end

-- Create a zone for a specific zone type
local function createZone(self, zoneType, cells, sizeX, sizeZ)
	if not self._gridService then
		return
	end
	
	if not ZONE_TYPES[zoneType] then
		warn(string.format("[ReservedZoneService] Invalid zone type: %s", tostring(zoneType)))
		return
	end
	
	if not cells or #cells == 0 then
		warn(string.format("[ReservedZoneService] No cells provided for %s zone", zoneType))
		return
	end
	
	local zoneTypeData = ZONE_TYPES[zoneType]
	
	-- Clear any existing zone of this type
	if self._zones[zoneType] then
		local existingZone = self._zones[zoneType]
		if existingZone.zone and existingZone.zone.Destroy then
			existingZone.zone:Destroy()
		end
		if existingZone.zoneCube then
			existingZone.zoneCube:Destroy()
		end
	end
	
	-- Calculate the center position and size
	local cellSize = self._gridService:GetCellSize()
	
	-- Calculate center position and boundaries from the cells
	local minX, maxX = math.huge, -math.huge
	local minZ, maxZ = math.huge, -math.huge
	
	for _, cell in ipairs(cells) do
		local worldPos = self._gridService:GridToWorld(cell.x, cell.z)
		minX = math.min(minX, worldPos.X)
		maxX = math.max(maxX, worldPos.X)
		minZ = math.min(minZ, worldPos.Z)
		maxZ = math.max(maxZ, worldPos.Z)
	end
	
	-- Calculate total size to cover all cells
	local totalSizeX = (maxX - minX) + cellSize
	local totalSizeZ = (maxZ - minZ) + cellSize
	
	-- Center position
	local centerX = (minX + maxX) / 2
	local centerZ = (minZ + maxZ) / 2
	-- Match grid cube height: grid cubes are positioned at topY + cellSize/2
	local centerY = self._gridService._gridData.topY + (cellSize / 2)
	
	-- Create a cube part covering the entire area
	local cube = Instance.new("Part")
	cube.Name = string.format("%sZoneCube", zoneType)
	cube.Size = Vector3.new(totalSizeX, cellSize, totalSizeZ)
	cube.Position = Vector3.new(centerX, centerY, centerZ)
	cube.Transparency = zoneTypeData.zoneCubeTransparency
	cube.Color = zoneTypeData.zoneCubeColor
	cube.CanCollide = false
	cube.Anchored = true
	cube.CastShadow = false
	CollectionService:AddTag(cube, ZONE_CUBE_TAG)  -- Tag for raycast exclusion
	cube.Parent = workspace
	
	-- Create Zone+ zone on the cube
	local success, zoneInstance = pcall(function()
		return Zone.new(cube)
	end)
	
	if not success then
		warn(string.format("[ReservedZoneService] Failed to create %s zone: %s", zoneType, tostring(zoneInstance)))
		return
	end
	
	-- Event handlers for the zone
	zoneInstance.playerEntered:Connect(function(player)
		local character = player.Character
		local position = character and character:FindFirstChild("HumanoidRootPart") and 
			character.HumanoidRootPart.Position or Vector3.zero
		
		--[[print(string.format(
			"[ReservedZoneService] >>> Player '%s' (UserId: %d) ENTERED %s zone at position (%.1f, %.1f, %.1f)",
			player.Name, player.UserId, zoneType, position.X, position.Y, position.Z
		))]]
	end)
	
	zoneInstance.playerExited:Connect(function(player)
		local character = player.Character
		local position = character and character:FindFirstChild("HumanoidRootPart") and 
			character.HumanoidRootPart.Position or Vector3.zero
		
		--[[print(string.format(
			"[ReservedZoneService] <<< Player '%s' (UserId: %d) EXITED %s zone at position (%.1f, %.1f, %.1f)",
			player.Name, player.UserId, zoneType, position.X, position.Y, position.Z
		))]]
	end)
	
	-- Store zone data
	self._zones[zoneType] = {
		cells = cells,
		zoneCube = cube,
		zone = zoneInstance,
	}
	
	--[[print(string.format("[ReservedZoneService] ✓ Created %s zone (%.1f x %.1f x %.1f studs) covering %d cells", 
		zoneType, totalSizeX, cellSize, totalSizeZ, #cells))]]
end

-- Helper function to create a zone of a specific type
local function createZoneOfType(self, zoneType, sizeX, sizeZ, LoadingService, reportProgress)
	if not ZONE_TYPES[zoneType] then
		warn(string.format("[ReservedZoneService] Invalid zone type: %s", tostring(zoneType)))
		return
	end
	
	-- Get grid dimensions
	local gridWidth, gridDepth = self._gridService:GetGridDimensions()
	
	if not gridWidth or not gridDepth then
		warn("[ReservedZoneService] Could not get grid dimensions")
		return
	end
	
	-- Find a valid block of cells
	local startX, startZ = nil, nil
	local attempts = 0
	local maxAttempts = 100
	
	-- Valid starting positions for the block
	local maxStartX = gridWidth - sizeX + 1
	local maxStartZ = gridDepth - sizeZ + 1
	
	while attempts < maxAttempts do
		attempts += 1
		
		-- Random starting cell for the block
		local testX = math.random(1, maxStartX)
		local testZ = math.random(1, maxStartZ)
		
		-- Check if all cells in the block are available
		local allCellsValid = true
		for dx = 0, sizeX - 1 do
			for dz = 0, sizeZ - 1 do
				local checkX = testX + dx
				local checkZ = testZ + dz
				
				-- Check if cell is valid and not occupied
				if not self._gridService:IsValidCell(checkX, checkZ) or 
				   self._gridService:IsCellOccupied(checkX, checkZ) then
					allCellsValid = false
					break
				end
			end
			if not allCellsValid then break end
		end
		
		if allCellsValid then
			startX = testX
			startZ = testZ
			break
		end
	end
	
	if not startX or not startZ then
		warn(string.format("[ReservedZoneService] Could not find valid %dx%d block for %s zone after %d attempts", 
			sizeX, sizeZ, zoneType, maxAttempts))
		return
	end
	
	--[[print(string.format("[ReservedZoneService] Selected %dx%d block starting at (%d,%d) for %s zone", 
		sizeX, sizeZ, startX, startZ, zoneType))]]
	
	local zoneTypeData = ZONE_TYPES[zoneType]
	local cells = {}
	local cellPositions = {}  -- Store cell positions for terrain flattening
	local totalCells = sizeX * sizeZ
	local cellIndex = 0
	
	-- Reserve all cells in the block
	for dx = 0, sizeX - 1 do
		for dz = 0, sizeZ - 1 do
			local cellX = startX + dx
			local cellZ = startZ + dz
			cellIndex += 1
			
			-- Mark cell as occupied
			if self._gridService.SetCellOccupied then
				self._gridService:SetCellOccupied(cellX, cellZ, ZONE_CONFIG.OwnerId)
			end
			
			-- Get the cell data and modify the cube
			local cellData = self._gridService:GetCell(cellX, cellZ)
			if cellData and cellData.cube then
				cellData.cube.Transparency = zoneTypeData.cellTransparency
				-- Color doesn't matter when fully transparent, but set it anyway
				--[[print(string.format("[ReservedZoneService] Reserved cell (%d,%d) for %s zone", 
					cellX, cellZ, zoneType))]]
			else
				warn(string.format("[ReservedZoneService] Could not find cube for cell (%d,%d)", cellX, cellZ))
			end
			
			-- Store cell position for terrain flattening (if needed)
			local cellPos = self._gridService:GridToWorld(cellX, cellZ)
			table.insert(cellPositions, cellPos)
			
			-- Store reserved cell
			table.insert(cells, {x = cellX, z = cellZ})
			
			if reportProgress then
				local progress = 10 + (cellIndex / totalCells) * 60
				reportProgress(string.format("Reserving %s zone (%d/%d)...", zoneType, cellIndex, totalCells), progress)
			end
		end
	end
	
	-- Wait a moment for GridService zones to be fully initialized
	task.wait(0.5)
	
	-- Create the zone
	if reportProgress then
		reportProgress(string.format("Creating %s zone...", zoneType), 75)
	end
	createZone(self, zoneType, cells, sizeX, sizeZ)
	
	-- Flatten terrain if needed using the zone cube bounds
	if zoneTypeData.flattenTerrain then
		if reportProgress then
			reportProgress(string.format("Flattening terrain for %s zone...", zoneType), 85)
		end
		-- Get the zone cube that was just created
		local zoneData = self._zones[zoneType]
		if zoneData and zoneData.zoneCube then
			flattenTerrainUnderZone(self, zoneData.zoneCube, zoneType)
		end
	end
	
	if reportProgress then
		reportProgress(string.format("%s zone created", zoneType), 100)
	end
end

-- Helper function to spawn enemies within a zone area
local function spawnEnemiesInZone(self, centerPosition, zoneSizeX, zoneSizeZ, enemyCount)
	-- Get HumanEnemyService
	local HumanEnemyService = nil
	pcall(function()
		HumanEnemyService = Knit.GetService("HumanEnemyService")
	end)
	
	if not HumanEnemyService then
		warn("[ReservedZoneService] HumanEnemyService not found, cannot spawn enemies")
		return nil
	end
	
	-- Calculate spawn radius based on zone size (use smaller dimension)
	local cellSize = self._gridService:GetCellSize()
	local zoneWidth = zoneSizeX * cellSize
	local zoneDepth = zoneSizeZ * cellSize
	local spawnRadius = math.min(zoneWidth, zoneDepth) / 2 - 2  -- Slightly inside zone edges
	
	-- Call HumanEnemyService to spawn enemies at this location
	local enemies = HumanEnemyService:SpawnEnemiesAt(centerPosition, spawnRadius, enemyCount)
	
	--[[print(string.format("[ReservedZoneService] Spawned %d enemies in HumanEnemy zone at (%.1f, %.1f, %.1f)", 
		enemyCount, centerPosition.X, centerPosition.Y, centerPosition.Z))]]
	
	return enemies
end

-- Helper function to spawn an audio log within a zone using Zone+ getRandomPoint()
-- Uses getRandomPoint() for random XZ within zone, then places on terrain surface
local function spawnAudioLogInZone(self, zoneInstance, zoneCube, zoneIndex)
	-- Get AudioLogService
	local AudioLogService = nil
	pcall(function()
		AudioLogService = Knit.GetService("AudioLogService")
	end)
	
	if not AudioLogService then
		warn("[ReservedZoneService] AudioLogService not found, cannot spawn audio log")
		return nil
	end
	
	-- Use Zone+ getRandomPoint() to get a random position within the zone
	local randomPoint = zoneInstance:getRandomPoint()
	if not randomPoint then
		warn("[ReservedZoneService] Could not get random point from zone")
		return nil
	end
	
	-- Get the terrain surface height at this random XZ position using CubeTerrainService
	local terrainY = self._gridService._gridData.topY  -- Default fallback
	
	if self._cubeTerrainService then
		local surfaceHeight = self._cubeTerrainService:GetSurfaceHeightAt(randomPoint.X, randomPoint.Z)
		if surfaceHeight and surfaceHeight > 0 then
			terrainY = surfaceHeight
		else
			-- Fallback to grid-based height calculation
			terrainY = self._cubeTerrainService:GetHeightAtPosition(Vector3.new(randomPoint.X, 0, randomPoint.Z))
		end
	end
	
	-- Spawn position: random XZ from zone, Y from terrain surface + small offset
	local spawnPosition = Vector3.new(randomPoint.X, terrainY + 0.5, randomPoint.Z)
	
	--[[print(string.format("[ReservedZoneService] Spawning audio log %d at random zone XZ (%.1f, %.1f) on terrain Y=%.1f", 
		zoneIndex, randomPoint.X, randomPoint.Z, terrainY))]]
	
	-- Spawn the audio log
	local audioLog = AudioLogService:SpawnAudioLogAt(spawnPosition)
	if audioLog and audioLog.model and audioLog.body then
		audioLog.model.Name = "AudioLog_Zone_" .. zoneIndex
		audioLog.entryIndex = zoneIndex
		
		-- Keep it anchored so it stays on the terrain
		audioLog.body.Anchored = true
		
		--[[print(string.format("[ReservedZoneService] Audio log %d placed and anchored at (%.1f, %.1f, %.1f)", 
			zoneIndex, spawnPosition.X, spawnPosition.Y, spawnPosition.Z))]]
	end
	
	return audioLog
end

-- Create a single zone for AudioLog type (1x1 cell)
-- Zone is tall to encompass terrain height variations, audio log spawns on terrain within zone XZ bounds
local function createSingleAudioLogZone(self, cellX, cellZ, zoneIndex)
	if not self._gridService then return nil end
	
	local zoneTypeData = ZONE_TYPES.AudioLog
	local cellSize = self._gridService:GetCellSize()
	local worldPos = self._gridService:GridToWorld(cellX, cellZ)
	
	-- Mark cell as occupied
	if self._gridService.SetCellOccupied then
		self._gridService:SetCellOccupied(cellX, cellZ, ZONE_CONFIG.OwnerId .. "_AudioLog_" .. zoneIndex)
	end
	
	-- Get the cell data and modify the cube
	local cellData = self._gridService:GetCell(cellX, cellZ)
	if cellData and cellData.cube then
		cellData.cube.Transparency = zoneTypeData.cellTransparency
	end
	
	-- Make zone cube tall enough to encompass terrain height variations
	-- Terrain height can vary from MinHeightOffset (-4) to MaxHeightOffset (+6) relative to topY
	-- So we make the zone extend from below the lowest terrain to above the highest
	local topY = self._gridService._gridData.topY
	local zoneHeight = cellSize + 20  -- Extra height to encompass terrain variations (-10 to +10)
	local centerY = topY + (zoneHeight / 2) - 5  -- Center it so it extends below and above grid level
	
	local cube = Instance.new("Part")
	cube.Name = string.format("AudioLogZoneCube_%d", zoneIndex)
	cube.Size = Vector3.new(cellSize, zoneHeight, cellSize)
	cube.Position = Vector3.new(worldPos.X, centerY, worldPos.Z)
	cube.Transparency = zoneTypeData.zoneCubeTransparency
	cube.Color = zoneTypeData.zoneCubeColor
	cube.CanCollide = false
	cube.Anchored = true
	cube.CastShadow = false
	CollectionService:AddTag(cube, ZONE_CUBE_TAG)  -- Tag for raycast exclusion
	cube.Parent = workspace
	
	--[[print(string.format("[ReservedZoneService] AudioLog zone %d cube at (%.1f, %.1f, %.1f) size (%.1f, %.1f, %.1f)", 
		zoneIndex, worldPos.X, centerY, worldPos.Z, cellSize, zoneHeight, cellSize))]]
	
	-- Create Zone+ zone on the cube
	local success, zoneInstance = pcall(function()
		return Zone.new(cube)
	end)
	
	if not success then
		warn(string.format("[ReservedZoneService] Failed to create AudioLog zone %d: %s", zoneIndex, tostring(zoneInstance)))
		cube:Destroy()
		return nil
	end
	
	-- Event handlers for the zone
	zoneInstance.playerEntered:Connect(function(player)
		local character = player.Character
		local position = character and character:FindFirstChild("HumanoidRootPart") and 
			character.HumanoidRootPart.Position or Vector3.zero
		
		--[[print(string.format(
			"[ReservedZoneService] >>> Player '%s' ENTERED AudioLog zone %d at (%.1f, %.1f, %.1f)",
			player.Name, zoneIndex, position.X, position.Y, position.Z
		))]]
	end)
	
	zoneInstance.playerExited:Connect(function(player)
		local character = player.Character
		local position = character and character:FindFirstChild("HumanoidRootPart") and 
			character.HumanoidRootPart.Position or Vector3.zero
		
		--[[print(string.format(
			"[ReservedZoneService] <<< Player '%s' EXITED AudioLog zone %d at (%.1f, %.1f, %.1f)",
			player.Name, zoneIndex, position.X, position.Y, position.Z
		))]]
	end)
	
	-- Spawn audio log at random position within the zone, let it fall to terrain
	-- Uses Zone+ getRandomPoint() to pick a random XZ position within zone bounds
	local audioLog = spawnAudioLogInZone(self, zoneInstance, cube, zoneIndex)
	
	return {
		cell = {x = cellX, z = cellZ},
		zoneCube = cube,
		zone = zoneInstance,
		audioLog = audioLog,
		zoneIndex = zoneIndex,
	}
end

-- Create multiple independent zones of AudioLog type
local function createMultipleAudioLogZones(self, count, LoadingService, reportProgress)
	if not self._gridService then
		warn("[ReservedZoneService] GridService not available for AudioLog zones")
		return
	end
	
	local gridWidth, gridDepth = self._gridService:GetGridDimensions()
	if not gridWidth or not gridDepth then
		warn("[ReservedZoneService] Could not get grid dimensions")
		return
	end
	
	-- Initialize AudioLog zones storage
	self._zones.AudioLog = {
		cells = {},
		zones = {},
		isMultiZone = true,
	}
	
	-- Build list of cells already reserved by Building/Radiation zones
	local reservedCells = {}
	for zoneType, zoneData in pairs(self._zones) do
		if zoneType ~= "AudioLog" and zoneData.cells then
			for _, cell in ipairs(zoneData.cells) do
				reservedCells[cell.x .. "," .. cell.z] = true
			end
		end
	end
	
	-- Build list of all unreserved cells
	local availableCells = {}
	for x = 1, gridWidth do
		for z = 1, gridDepth do
			if not reservedCells[x .. "," .. z] then
				table.insert(availableCells, {x = x, z = z})
			end
		end
	end
	
	-- Shuffle for random distribution
	for i = #availableCells, 2, -1 do
		local j = math.random(1, i)
		availableCells[i], availableCells[j] = availableCells[j], availableCells[i]
	end
	
	-- Create the zones
	local zonesToCreate = math.min(count, #availableCells)
	
	for i = 1, zonesToCreate do
		local cell = availableCells[i]
		
		if reportProgress then
			reportProgress(string.format("Creating AudioLog zone %d/%d...", i, zonesToCreate), (i / zonesToCreate) * 100)
		end
		
		local zoneData = createSingleAudioLogZone(self, cell.x, cell.z, i)
		
		if zoneData then
			table.insert(self._zones.AudioLog.cells, zoneData.cell)
			table.insert(self._zones.AudioLog.zones, zoneData)
			--[[print(string.format("[ReservedZoneService] ✓ AudioLog zone %d at cell (%d, %d)", i, cell.x, cell.z))]]
		end
		
		task.wait(0.1)
	end
	
	--[[print(string.format("[ReservedZoneService] ✓ Created %d AudioLog zones", zonesToCreate))]]
end

-- Create Building zone at the CENTER of the grid
local function createBuildingZoneAtCenter(self, sizeX, sizeZ, LoadingService, reportProgress)
	if not self._gridService then
		warn("[ReservedZoneService] GridService not available for Building zone")
		return
	end
	
	local zoneType = "Building"
	local zoneTypeData = ZONE_TYPES[zoneType]
	
	-- Get grid dimensions
	local gridWidth, gridDepth = self._gridService:GetGridDimensions()
	if not gridWidth or not gridDepth then
		warn("[ReservedZoneService] Could not get grid dimensions")
		return
	end
	
	-- Calculate center of grid
	local centerGridX = math.floor(gridWidth / 2)
	local centerGridZ = math.floor(gridDepth / 2)
	
	-- Calculate starting position so zone is centered
	local startX = centerGridX - math.floor(sizeX / 2)
	local startZ = centerGridZ - math.floor(sizeZ / 2)
	
	-- Ensure start positions are valid (at least 1)
	startX = math.max(1, startX)
	startZ = math.max(1, startZ)
	
	--[[print(string.format("[ReservedZoneService] Creating Building zone at CENTER: grid center (%d, %d), start (%d, %d), size %dx%d", 
		centerGridX, centerGridZ, startX, startZ, sizeX, sizeZ))]]
	
	local cells = {}
	local cellPositions = {}
	local totalCells = sizeX * sizeZ
	local cellIndex = 0
	
	-- Reserve all cells in the block at center
	for dx = 0, sizeX - 1 do
		for dz = 0, sizeZ - 1 do
			local cellX = startX + dx
			local cellZ = startZ + dz
			cellIndex += 1
			
			-- Mark cell as occupied
			if self._gridService.SetCellOccupied then
				self._gridService:SetCellOccupied(cellX, cellZ, ZONE_CONFIG.OwnerId)
			end
			
			-- Get the cell data and modify the cube
			local cellData = self._gridService:GetCell(cellX, cellZ)
			if cellData and cellData.cube then
				cellData.cube.Transparency = zoneTypeData.cellTransparency
				--[[print(string.format("[ReservedZoneService] Reserved center cell (%d,%d) for Building zone", cellX, cellZ))]]
			end
			
			-- Store cell position for terrain flattening
			local cellPos = self._gridService:GridToWorld(cellX, cellZ)
			table.insert(cellPositions, cellPos)
			
			-- Store reserved cell
			table.insert(cells, {x = cellX, z = cellZ})
			
			if reportProgress then
				local progress = 10 + (cellIndex / totalCells) * 60
				reportProgress(string.format("Reserving Building zone at center (%d/%d)...", cellIndex, totalCells), progress)
			end
		end
	end
	
	task.wait(0.5)
	
	-- Create the zone
	if reportProgress then
		reportProgress("Creating Building zone at center...", 75)
	end
	createZone(self, zoneType, cells, sizeX, sizeZ)
	
	-- Flatten terrain under the Building zone using the zone cube bounds
	if zoneTypeData.flattenTerrain then
		if reportProgress then
			reportProgress("Flattening terrain under Building zone...", 85)
		end
		-- Get the zone cube that was just created
		local buildingZone = self._zones.Building
		if buildingZone and buildingZone.zoneCube then
			flattenTerrainUnderZone(self, buildingZone.zoneCube, zoneType)
		end
	end
	
	if reportProgress then
		reportProgress("Building zone created at center", 100)
	end
	
	--[[print(string.format("[ReservedZoneService] ✓ Building zone created at CENTER of grid (%d, %d)", centerGridX, centerGridZ))]]
end

-- Main function to create all zones
local function proceedWithReservation(self, LoadingService, reportProgress)
	-- Create building zone at CENTER of grid (15% of progress)
	createBuildingZoneAtCenter(self, ZONE_CONFIG.BuildingZoneSizeX, ZONE_CONFIG.BuildingZoneSizeZ, 
		LoadingService, function(msg, progress)
			if reportProgress then
				reportProgress(msg, progress * 0.15)
			end
		end)
	
	-- Create radiation zone (15% of progress)
	createZoneOfType(self, "Radiation", ZONE_CONFIG.RadiationZoneSizeX, ZONE_CONFIG.RadiationZoneSizeZ, 
		LoadingService, function(msg, progress)
			if reportProgress then
				reportProgress(msg, 15 + progress * 0.15)
			end
		end)
	
	-- Create human enemy zone (20% of progress)
	createZoneOfType(self, "HumanEnemy", ZONE_CONFIG.HumanEnemyZoneSizeX, ZONE_CONFIG.HumanEnemyZoneSizeZ, 
		LoadingService, function(msg, progress)
			if reportProgress then
				reportProgress(msg, 30 + progress * 0.2)
			end
		end)
	
	-- Spawn enemies in the HumanEnemy zone
	local humanEnemyZone = self._zones.HumanEnemy
	if humanEnemyZone and humanEnemyZone.zoneCube then
		local centerPos = humanEnemyZone.zoneCube.Position
		spawnEnemiesInZone(self, centerPos, ZONE_CONFIG.HumanEnemyZoneSizeX, ZONE_CONFIG.HumanEnemyZoneSizeZ, ZONE_CONFIG.HumanEnemyCount)
	end
	
	-- Create audio log zones (50% of progress)
	-- Get the audio log count from AudioLogService to ensure zone count matches
	local audioLogCount = ZONE_CONFIG.AudioLogZoneCount  -- Default fallback
	local AudioLogService = nil
	pcall(function()
		AudioLogService = Knit.GetService("AudioLogService")
	end)
	if AudioLogService and AudioLogService.GetLogCount then
		audioLogCount = AudioLogService:GetLogCount()
		--[[print(string.format("[ReservedZoneService] Using AudioLogService LogCount: %d", audioLogCount))]]
	end
	
	createMultipleAudioLogZones(self, audioLogCount, LoadingService, function(msg, progress)
		if reportProgress then
			reportProgress(msg, 50 + progress * 0.5)
		end
	end)
	
	-- Cleanup grid cells and map UI now that reserved zones are created
	-- This deletes grid cube parts and map replica but keeps:
	-- - Reserved zone cubes (Building, Radiation, AudioLog, HumanEnemy zones)
	-- - Terrain cubes
	if self._gridService and self._gridService.CleanupGridCellsAndMap then
		--("[ReservedZoneService] Cleaning up grid cells and map UI...")
		self._gridService:CleanupGridCellsAndMap()
	end
	
	-- Mark step complete
	if LoadingService then
		LoadingService:MarkStepComplete("ReservedZoneService")
	end
	
	--("[ReservedZoneService] All zones created, grid cells cleaned up")
end

-- === KNIT LIFECYCLE ===

function ReservedZoneService:KnitInit()
	--("[ReservedZoneService] Initializing...")
	
	-- Get GridService reference
	pcall(function()
		self._gridService = Knit.GetService("GridService")
	end)

	-- Get CubeTerrainService reference
	pcall(function()
		self._cubeTerrainService = Knit.GetService("CubeTerrainService")
	end)
end

function ReservedZoneService:KnitStart()
	-- Only auto-initialize if _autoStart is true (legacy mode)
	-- WorldInitService will call InitializeZones() instead
	if self._autoStart then
		-- Get LoadingService for progress updates
		local LoadingService = nil
		pcall(function()
			LoadingService = Knit.GetService("LoadingService")
		end)
		
		local function reportProgress(message, progress)
			if LoadingService then
				LoadingService:UpdateStatus("ReservedZoneService", message, progress or 0)
			end
		end
		
		if not self._gridService then
			warn("[ReservedZoneService] GridService not found!")
			return
		end
		
		-- Wait for CubeTerrainService to complete before flattening
		if LoadingService then
			--("[ReservedZoneService] Waiting for CubeTerrainService to complete...")
			LoadingService:OnStepComplete("CubeTerrainService", function()
				--("[ReservedZoneService] CubeTerrainService complete, proceeding with reservation...")
				proceedWithReservation(self, LoadingService, reportProgress)
			end)
		else
			-- Fallback if LoadingService not available
			task.wait(2)  -- Give terrain time to generate
			proceedWithReservation(self, LoadingService, reportProgress)
		end
	else
		--("[ReservedZoneService] Waiting for WorldInitService to initialize zones...")
	end
end

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║               WORLDINITSERVICE INTEGRATION                                 ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

-- Initialize zones (called by WorldInitService)
function ReservedZoneService:InitializeZones()
	if self._isInitialized then
		--("[ReservedZoneService] Already initialized, skipping...")
		return true
	end
	
	--("[ReservedZoneService] Initializing zones (called by WorldInitService)...")
	
	-- Get LoadingService for progress updates
	local LoadingService = nil
	pcall(function()
		LoadingService = Knit.GetService("LoadingService")
	end)
	
	local function reportProgress(message, progress)
		if LoadingService then
			LoadingService:UpdateStatus("ReservedZoneService", message, progress or 0)
		end
	end
	
	if not self._gridService then
		warn("[ReservedZoneService] GridService not found!")
		return false
	end
	
	-- Proceed with reservation (no waiting for terrain since WorldInitService handles order)
	proceedWithReservation(self, LoadingService, reportProgress)
	
	self._isInitialized = true
	--("[ReservedZoneService] Zone initialization complete")
	return true
end

-- === PUBLIC API ===

function ReservedZoneService:GetZones()
	return self._zones
end

function ReservedZoneService:GetZone(zoneType)
	return self._zones[zoneType]
end

function ReservedZoneService:GetZoneCells(zoneType)
	local zoneData = self._zones[zoneType]
	return zoneData and zoneData.cells or {}
end

function ReservedZoneService:IsCellInZone(x, z, zoneType)
	local cells = self:GetZoneCells(zoneType)
	for _, cell in ipairs(cells) do
		if cell.x == x and cell.z == z then
			return true
		end
	end
	return false
end

function ReservedZoneService:IsCellReserved(x, z)
	-- Check if cell is in any zone
	for zoneType, _ in pairs(self._zones) do
		if self:IsCellInZone(x, z, zoneType) then
			return true
		end
	end
	return false
end

function ReservedZoneService:ClearZone(zoneType)
	local zoneData = self._zones[zoneType]
	if not zoneData then
		return
	end
	
	-- Handle multi-zone types (like AudioLog)
	if zoneData.isMultiZone and zoneData.zones then
		for _, individualZone in ipairs(zoneData.zones) do
			-- Destroy zone
			if individualZone.zone and individualZone.zone.Destroy then
				individualZone.zone:Destroy()
			end
			
			-- Destroy zone cube
			if individualZone.zoneCube then
				individualZone.zoneCube:Destroy()
			end
			
			-- Destroy audio log if present
			if individualZone.audioLog and individualZone.audioLog.model then
				individualZone.audioLog.model:Destroy()
			end
			
			-- Clear cell occupancy
			if individualZone.cell and self._gridService and self._gridService.ClearCellOccupancy then
				self._gridService:ClearCellOccupancy(individualZone.cell.x, individualZone.cell.z)
				
				-- Reset cube transparency and color (checkerboard pattern)
				local cellData = self._gridService:GetCell(individualZone.cell.x, individualZone.cell.z)
				if cellData and cellData.cube then
					cellData.cube.Transparency = 0
					if (individualZone.cell.x + individualZone.cell.z) % 2 == 0 then
						cellData.cube.Color = Color3.fromRGB(66, 135, 245)  -- Blue
					else
						cellData.cube.Color = Color3.fromRGB(245, 166, 66)  -- Orange
					end
				end
			end
		end
	else
		-- Handle single zone types (Building, Radiation)
		-- Destroy zone
		if zoneData.zone and zoneData.zone.Destroy then
			zoneData.zone:Destroy()
		end
		
		-- Destroy zone cube
		if zoneData.zoneCube then
			zoneData.zoneCube:Destroy()
		end
		
		-- Clear cell occupancy and reset transparency
		for _, cell in ipairs(zoneData.cells) do
			if self._gridService and self._gridService.ClearCellOccupancy then
				self._gridService:ClearCellOccupancy(cell.x, cell.z)
			end
			
			-- Reset cube transparency and color (checkerboard pattern)
			local cellData = self._gridService:GetCell(cell.x, cell.z)
			if cellData and cellData.cube then
				cellData.cube.Transparency = 0
				-- Reset to original checkerboard color
				if (cell.x + cell.z) % 2 == 0 then
					cellData.cube.Color = Color3.fromRGB(66, 135, 245)  -- Blue
				else
					cellData.cube.Color = Color3.fromRGB(245, 166, 66)  -- Orange
				end
			end
		end
	end
	
	self._zones[zoneType] = nil
	--[[print(string.format("[ReservedZoneService] Cleared %s zone", zoneType))]]
end

function ReservedZoneService:ClearAllZones()
	for zoneType, _ in pairs(self._zones) do
		self:ClearZone(zoneType)
	end
	--("[ReservedZoneService] Cleared all zones")
end

-- === AUDIOLOG ZONE SPECIFIC API ===

-- Get all AudioLog zone data
function ReservedZoneService:GetAudioLogZones()
	local audioLogData = self._zones.AudioLog
	if audioLogData and audioLogData.isMultiZone then
		return audioLogData.zones or {}
	end
	return {}
end

-- Get a specific AudioLog zone by index
function ReservedZoneService:GetAudioLogZone(index)
	local zones = self:GetAudioLogZones()
	return zones[index]
end

-- Get the count of AudioLog zones
function ReservedZoneService:GetAudioLogZoneCount()
	return #self:GetAudioLogZones()
end

-- Check if a position is within any AudioLog zone
function ReservedZoneService:IsInAnyAudioLogZone(position)
	local zones = self:GetAudioLogZones()
	for _, zoneData in ipairs(zones) do
		if zoneData.zone and zoneData.zone.findPoint then
			local isInside = zoneData.zone:findPoint(position)
			if isInside then
				return true, zoneData.zoneIndex
			end
		end
	end
	return false, nil
end

-- Get all AudioLog models from zones
function ReservedZoneService:GetAllAudioLogsFromZones()
	local audioLogs = {}
	local zones = self:GetAudioLogZones()
	for _, zoneData in ipairs(zones) do
		if zoneData.audioLog then
			table.insert(audioLogs, zoneData.audioLog)
		end
	end
	return audioLogs
end

return ReservedZoneService
