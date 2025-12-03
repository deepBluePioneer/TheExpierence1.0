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
	BuildingZoneSizeX = 2,      -- Width of building zone (cells)
	BuildingZoneSizeZ = 2,      -- Depth of building zone (cells)
	RadiationZoneSizeX = 2,     -- Width of radiation zone (cells)
	RadiationZoneSizeZ = 2,     -- Depth of radiation zone (cells)
	AudioLogZoneCount = 10,     -- Number of audio log zones to create
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

-- Flatten terrain under the reserved area using CubeTerrainService
local function flattenTerrainUnderReservedArea(self, cellPositions, zoneType)
	if not ZONE_TYPES[zoneType] or not ZONE_TYPES[zoneType].flattenTerrain then
		return  -- Don't flatten if zone type doesn't require it
	end
	if not cellPositions or #cellPositions == 0 then
		return
	end
	
	local CubeTerrainService = self._cubeTerrainService
	if not CubeTerrainService then
		warn("[ReservedZoneService] CubeTerrainService not found, cannot flatten terrain")
		return
	end
	
	if not self._gridService then
		warn("[ReservedZoneService] GridService not available, cannot calculate area size")
		return
	end
	
	-- Calculate the center cell position
	local totalX, totalZ = 0, 0
	local minGridX, maxGridX = math.huge, -math.huge
	local minGridZ, maxGridZ = math.huge, -math.huge
	
	for _, pos in ipairs(cellPositions) do
		-- Convert world position to grid position
		local gridX, gridZ = self._gridService:WorldToGrid(pos)
		minGridX = math.min(minGridX, gridX)
		maxGridX = math.max(maxGridX, gridX)
		minGridZ = math.min(minGridZ, gridZ)
		maxGridZ = math.max(maxGridZ, gridZ)
		totalX = totalX + gridX
		totalZ = totalZ + gridZ
	end
	
	-- Calculate center grid position
	local centerGridX = math.floor((minGridX + maxGridX) / 2)
	local centerGridZ = math.floor((minGridZ + maxGridZ) / 2)
	local radiusX = math.ceil((maxGridX - minGridX) / 2) + 1
	local radiusZ = math.ceil((maxGridZ - minGridZ) / 2) + 1
	local radius = math.max(radiusX, radiusZ)
	
	-- Get the flat height from GridService topY (the ground level)
	local flatHeight = self._gridService:GetTopY()
	
	print(string.format(
		"[ReservedZoneService] Flattening terrain at grid (%d, %d) radius %d", 
		centerGridX, centerGridZ, radius
	))
	
	-- Flatten the terrain via CubeTerrainService
	CubeTerrainService:FlattenArea(centerGridX, centerGridZ, radius, flatHeight)
	
	print("[ReservedZoneService] Terrain cubes flattened under Building zone")
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
		
		print(string.format(
			"[ReservedZoneService] >>> Player '%s' (UserId: %d) ENTERED %s zone at position (%.1f, %.1f, %.1f)",
			player.Name, player.UserId, zoneType, position.X, position.Y, position.Z
		))
	end)
	
	zoneInstance.playerExited:Connect(function(player)
		local character = player.Character
		local position = character and character:FindFirstChild("HumanoidRootPart") and 
			character.HumanoidRootPart.Position or Vector3.zero
		
		print(string.format(
			"[ReservedZoneService] <<< Player '%s' (UserId: %d) EXITED %s zone at position (%.1f, %.1f, %.1f)",
			player.Name, player.UserId, zoneType, position.X, position.Y, position.Z
		))
	end)
	
	-- Store zone data
	self._zones[zoneType] = {
		cells = cells,
		zoneCube = cube,
		zone = zoneInstance,
	}
	
	print(string.format("[ReservedZoneService] ✓ Created %s zone (%.1f x %.1f x %.1f studs) covering %d cells", 
		zoneType, totalSizeX, cellSize, totalSizeZ, #cells))
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
	
	print(string.format("[ReservedZoneService] Selected %dx%d block starting at (%d,%d) for %s zone", 
		sizeX, sizeZ, startX, startZ, zoneType))
	
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
				print(string.format("[ReservedZoneService] Reserved cell (%d,%d) for %s zone", 
					cellX, cellZ, zoneType))
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
	
	-- Flatten terrain if needed
	if zoneTypeData.flattenTerrain then
		if reportProgress then
			reportProgress(string.format("Flattening terrain for %s zone...", zoneType), 85)
		end
		flattenTerrainUnderReservedArea(self, cellPositions, zoneType)
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
	
	print(string.format("[ReservedZoneService] Spawned %d enemies in HumanEnemy zone at (%.1f, %.1f, %.1f)", 
		enemyCount, centerPosition.X, centerPosition.Y, centerPosition.Z))
	
	return enemies
end

-- Helper function to spawn an audio log at a specific world position
local function spawnAudioLogInZone(self, worldPosition, zoneIndex)
	-- Get AudioLogService
	local AudioLogService = nil
	pcall(function()
		AudioLogService = Knit.GetService("AudioLogService")
	end)
	
	if not AudioLogService then
		warn("[ReservedZoneService] AudioLogService not found, cannot spawn audio log")
		return nil
	end
	
	-- Raycast to find ground height at this position
	local Terrain = Workspace.Terrain
	local rayOrigin = Vector3.new(worldPosition.X, 500, worldPosition.Z)
	local rayDirection = Vector3.new(0, -1000, 0)
	
	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	
	-- Build exclude list for accurate ground detection
	local excludeList = {}
	local audioLogFolder = Workspace:FindFirstChild("AudioLogs")
	if audioLogFolder then table.insert(excludeList, audioLogFolder) end
	local treesFolder = Workspace:FindFirstChild("Trees")
	if treesFolder then table.insert(excludeList, treesFolder) end
	local formationsFolder = Workspace:FindFirstChild("AlienFormations")
	if formationsFolder then table.insert(excludeList, formationsFolder) end
	
	-- Exclude grid cubes by tag
	local gridCubes = CollectionService:GetTagged("gridCube")
	for _, cube in ipairs(gridCubes) do
		table.insert(excludeList, cube)
	end
	
	-- Exclude reserved zone cubes by tag
	local zoneCubes = CollectionService:GetTagged(ZONE_CUBE_TAG)
	for _, cube in ipairs(zoneCubes) do
		table.insert(excludeList, cube)
	end
	
	rayParams.FilterDescendantsInstances = excludeList
	rayParams.IgnoreWater = true
	
	local rayResult = Workspace:Raycast(rayOrigin, rayDirection, rayParams)
	local groundY = rayResult and rayResult.Position.Y or (self._gridService:GetTopY() or 0)
	
	-- Spawn position slightly above ground (AudioLogService will handle physics drop)
	local spawnPosition = Vector3.new(worldPosition.X, groundY + 3, worldPosition.Z)
	
	-- Spawn the audio log
	local audioLog = AudioLogService:SpawnAudioLogAt(spawnPosition)
	if audioLog and audioLog.model then
		audioLog.model.Name = "AudioLog_Zone_" .. zoneIndex
		audioLog.entryIndex = zoneIndex
		print(string.format("[ReservedZoneService] Spawned audio log %d at (%.1f, %.1f, %.1f)", 
			zoneIndex, spawnPosition.X, spawnPosition.Y, spawnPosition.Z))
	end
	
	return audioLog
end

-- Create a single zone for AudioLog type (1x1 cell)
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
	
	-- Create zone cube
	local centerY = self._gridService._gridData.topY + (cellSize / 2)
	local cube = Instance.new("Part")
	cube.Name = string.format("AudioLogZoneCube_%d", zoneIndex)
	cube.Size = Vector3.new(cellSize, cellSize, cellSize)
	cube.Position = Vector3.new(worldPos.X, centerY, worldPos.Z)
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
		warn(string.format("[ReservedZoneService] Failed to create AudioLog zone %d: %s", zoneIndex, tostring(zoneInstance)))
		cube:Destroy()
		return nil
	end
	
	-- Event handlers for the zone
	zoneInstance.playerEntered:Connect(function(player)
		local character = player.Character
		local position = character and character:FindFirstChild("HumanoidRootPart") and 
			character.HumanoidRootPart.Position or Vector3.zero
		
		print(string.format(
			"[ReservedZoneService] >>> Player '%s' ENTERED AudioLog zone %d at (%.1f, %.1f, %.1f)",
			player.Name, zoneIndex, position.X, position.Y, position.Z
		))
	end)
	
	zoneInstance.playerExited:Connect(function(player)
		local character = player.Character
		local position = character and character:FindFirstChild("HumanoidRootPart") and 
			character.HumanoidRootPart.Position or Vector3.zero
		
		print(string.format(
			"[ReservedZoneService] <<< Player '%s' EXITED AudioLog zone %d at (%.1f, %.1f, %.1f)",
			player.Name, zoneIndex, position.X, position.Y, position.Z
		))
	end)
	
	-- Spawn audio log inside the zone
	local audioLog = spawnAudioLogInZone(self, worldPos, zoneIndex)
	
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
			print(string.format("[ReservedZoneService] ✓ AudioLog zone %d at cell (%d, %d)", i, cell.x, cell.z))
		end
		
		task.wait(0.1)
	end
	
	print(string.format("[ReservedZoneService] ✓ Created %d AudioLog zones", zonesToCreate))
end

-- Main function to create all zones
local function proceedWithReservation(self, LoadingService, reportProgress)
	-- Create building zone (15% of progress)
	createZoneOfType(self, "Building", ZONE_CONFIG.BuildingZoneSizeX, ZONE_CONFIG.BuildingZoneSizeZ, 
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
	createMultipleAudioLogZones(self, ZONE_CONFIG.AudioLogZoneCount, LoadingService, function(msg, progress)
		if reportProgress then
			reportProgress(msg, 50 + progress * 0.5)
		end
	end)
	
	-- Mark step complete
	if LoadingService then
		LoadingService:MarkStepComplete("ReservedZoneService")
	end
	
	print("[ReservedZoneService] All zones created")
end

-- === KNIT LIFECYCLE ===

function ReservedZoneService:KnitInit()
	print("[ReservedZoneService] Initializing...")
	
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
			print("[ReservedZoneService] Waiting for CubeTerrainService to complete...")
			LoadingService:OnStepComplete("CubeTerrainService", function()
				print("[ReservedZoneService] CubeTerrainService complete, proceeding with reservation...")
				proceedWithReservation(self, LoadingService, reportProgress)
			end)
		else
			-- Fallback if LoadingService not available
			task.wait(2)  -- Give terrain time to generate
			proceedWithReservation(self, LoadingService, reportProgress)
		end
	else
		print("[ReservedZoneService] Waiting for WorldInitService to initialize zones...")
	end
end

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║               WORLDINITSERVICE INTEGRATION                                 ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

-- Initialize zones (called by WorldInitService)
function ReservedZoneService:InitializeZones()
	if self._isInitialized then
		print("[ReservedZoneService] Already initialized, skipping...")
		return true
	end
	
	print("[ReservedZoneService] Initializing zones (called by WorldInitService)...")
	
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
	print("[ReservedZoneService] Zone initialization complete")
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
	print(string.format("[ReservedZoneService] Cleared %s zone", zoneType))
end

function ReservedZoneService:ClearAllZones()
	for zoneType, _ in pairs(self._zones) do
		self:ClearZone(zoneType)
	end
	print("[ReservedZoneService] Cleared all zones")
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
