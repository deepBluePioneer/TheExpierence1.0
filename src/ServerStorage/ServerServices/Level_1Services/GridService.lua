local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local CollectionService = game:GetService("CollectionService")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local CustomPackages = ReplicatedStorage:WaitForChild("CustomPackages")
local Knit = require(Packages.Knit)
local Timer = require(Packages.timer)
local Signal = require(Packages.Signal)

-- Zone+ Module
local ZoneRoot = CustomPackages:WaitForChild("ZoneRoot")
local Zone = require(ZoneRoot:WaitForChild("Zone"))

-- Replica Module
local Replica = CustomPackages:WaitForChild("Replica")
local ReplicaService = require(Replica.ReplicaService)

local GridService = Knit.CreateService {
	Name = "GridService",
	Client = {},
	zones = {},  -- Store all zone instances
	timerReplica = nil,
	mapReplica = nil,  -- For player positions on map
	timer = nil,
	
	-- Grid data structure
	_gridData = {
		width = 20,
		depth = 20,
		cellSize = 8,
		centerX = 0,
		centerZ = 0,
		topY = 0,
		cells = {},        -- { ["x_z"] = { cube = Part, occupied = false, owner = nil } }
		occupiedCells = {}, -- { ["x_z"] = ownerId }
	},
	
	-- Exclusion zones (areas where objects should not spawn)
	_exclusionZones = {}, -- { [id] = { position = Vector3, radius = number, height = number, owner = string } }
	
	-- Signal fired when exclusion zones change (added or removed)
	ExclusionZoneChanged = nil,  -- Signal() - fires when zones are added/removed
	
	-- State tracking for orchestrated initialization
	_isGridReady = false,
	_baseplateInfo = nil,
	_autoStart = false,  -- Set to false to let WorldInitService control initialization
}

-- === CONFIG ===
local TARGET_CELLS_PER_SIDE = 20  -- Target number of cells per side (will adjust to fit)
local GRID_FOLDER_NAME = "GridCubes"
local BATCH_SIZE = 50              -- Create this many parts before yielding
local GRID_CUBE_TAG = "gridCube"   -- Tag for each grid cube

-- Timer Config
local TIMER_DURATION = 60  -- Timer duration in seconds

-- Grid dimensions (calculated from baseplate)
local GRID_WIDTH = 20      -- Will be recalculated
local GRID_DEPTH = 20      -- Will be recalculated
local CUBE_SIZE = 8        -- Will be recalculated to fit baseplate exactly
local BASEPLATE_CENTER = Vector3.zero
local BASEPLATE_TOP_Y = 0

-- Calculate grid from provided dimensions (no physical baseplate needed)
local function calculateGridFromDimensions(gridData, width, depth, centerPos, topY)
	width = width or 128
	depth = depth or 128
	centerPos = centerPos or Vector3.zero
	topY = topY or 0
	
	BASEPLATE_CENTER = Vector3.new(centerPos.X, centerPos.Y, centerPos.Z)
	BASEPLATE_TOP_Y = topY
	
	-- Calculate cell size to exactly fit the area
	local minSide = math.min(width, depth)
	CUBE_SIZE = math.floor(minSide / TARGET_CELLS_PER_SIDE)
	CUBE_SIZE = math.max(CUBE_SIZE, 4)  -- Minimum cell size of 4
	
	-- Calculate grid dimensions to exactly fill area
	GRID_WIDTH = math.floor(width / CUBE_SIZE)
	GRID_DEPTH = math.floor(depth / CUBE_SIZE)
	
	-- Recalculate cell size to perfectly fit (no gaps at edges)
	local cellSizeX = width / GRID_WIDTH
	local cellSizeZ = depth / GRID_DEPTH
	CUBE_SIZE = math.min(cellSizeX, cellSizeZ)  -- Use uniform size
	
	-- Update gridData structure
	if gridData then
		gridData.width = GRID_WIDTH
		gridData.depth = GRID_DEPTH
		gridData.cellSize = CUBE_SIZE
		gridData.centerX = BASEPLATE_CENTER.X
		gridData.centerZ = BASEPLATE_CENTER.Z
		gridData.topY = BASEPLATE_TOP_Y
	end
	
	print(string.format("[GridService] Grid area: %.0fx%.0f | Grid: %dx%d | Cell size: %.1f", 
		width, depth, GRID_WIDTH, GRID_DEPTH, CUBE_SIZE))
	
	return GRID_WIDTH, GRID_DEPTH
end

-- Legacy function - kept for backward compatibility but now uses default values
local function calculateGridFromBaseplate(gridData)
	-- Check if we already have baseplateInfo from WorldInitService
	-- If not, use default dimensions
	local defaultWidth = 384  -- 3x128 baseplate grid
	local defaultDepth = 384
	local defaultCenter = Vector3.zero
	local defaultTopY = 0
	
	-- Try to find a physical baseplate as fallback (legacy support)
	local baseplate = Workspace:FindFirstChild("Baseplate")
	if baseplate and baseplate:IsA("BasePart") then
		print("[GridService] Found physical baseplate, using its dimensions")
		local baseplateSize = baseplate.Size
		return calculateGridFromDimensions(
			gridData,
			baseplateSize.X,
			baseplateSize.Z,
			baseplate.Position,
			baseplate.Position.Y + (baseplateSize.Y / 2)
		)
	else
		print("[GridService] No physical baseplate found, using defaults (will be updated by WorldInitService)")
		return calculateGridFromDimensions(gridData, defaultWidth, defaultDepth, defaultCenter, defaultTopY)
	end
end

-- === HELPERS ===

local function getGridFolder()
	local folder = Workspace:FindFirstChild(GRID_FOLDER_NAME)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = GRID_FOLDER_NAME
		folder.Parent = Workspace
	end
	return folder
end

local function clearGrid()
	local folder = Workspace:FindFirstChild(GRID_FOLDER_NAME)
	if folder then
		folder:ClearAllChildren()
	end
end

-- Pre-create a template part for cloning (faster than Instance.new each time)
local cubeTemplate = Instance.new("Part")
cubeTemplate.Name = "CubeTemplate"
cubeTemplate.Anchored = true
cubeTemplate.CanCollide = false
cubeTemplate.CastShadow = false
cubeTemplate.Transparency = 1  -- Fully transparent
cubeTemplate.Material = Enum.Material.SmoothPlastic

local function getCellKey(x, z)
	return string.format("%d_%d", x, z)
end

local function createCubeFast(x, z, folder, gridData)
	local cube = cubeTemplate:Clone()
	cube.Name = string.format("Cube_%d_%d", x, z)
	cube.Size = Vector3.new(CUBE_SIZE, CUBE_SIZE, CUBE_SIZE)
	
	-- Calculate position centered on baseplate
	local offsetX = (x - (GRID_WIDTH + 1) / 2) * CUBE_SIZE
	local offsetZ = (z - (GRID_DEPTH + 1) / 2) * CUBE_SIZE
	local cubeY = BASEPLATE_TOP_Y + (CUBE_SIZE / 2)
	
	cube.Position = Vector3.new(
		BASEPLATE_CENTER.X + offsetX,
		cubeY,
		BASEPLATE_CENTER.Z + offsetZ
	)
	
	-- Color based on position (checkerboard pattern)
	if (x + z) % 2 == 0 then
		cube.Color = Color3.fromRGB(66, 135, 245)  -- Blue
	else
		cube.Color = Color3.fromRGB(245, 166, 66)  -- Orange
	end
	
	-- Add tag for identification
	CollectionService:AddTag(cube, GRID_CUBE_TAG)
	
	cube.Parent = folder
	
	-- Store cell data in grid structure
	if gridData then
		local key = getCellKey(x, z)
		gridData.cells[key] = {
			cube = cube,
			x = x,
			z = z,
			occupied = false,
			owner = nil,
		}
	end
	
	return cube
end

local function attachZone(cube, x, z, zonesTable, mapReplica)
	local zone = Zone.new(cube)
	
	zone.playerEntered:Connect(function(player)
		cube.Color = Color3.fromRGB(0, 255, 0)  -- Turn green when player enters
		
		-- Update player position in map replica
		local userId = tostring(player.UserId)
		mapReplica:SetValue({"PlayerPositions", userId}, {
			X = x,
			Z = z,
			Name = player.Name,
		})
		
		-- Mark cell as explored (fog of war)
		local cellKey = string.format("%d_%d", x, z)
		if not mapReplica.Data.ExploredCells[cellKey] then
			mapReplica:SetValue({"ExploredCells", cellKey}, true)
			
			-- Also reveal adjacent cells (3x3 vision radius)
			for dx = -1, 1 do
				for dz = -1, 1 do
					local adjX, adjZ = x + dx, z + dz
					if adjX >= 1 and adjX <= GRID_WIDTH and adjZ >= 1 and adjZ <= GRID_DEPTH then
						local adjKey = string.format("%d_%d", adjX, adjZ)
						if not mapReplica.Data.ExploredCells[adjKey] then
							mapReplica:SetValue({"ExploredCells", adjKey}, true)
						end
					end
				end
			end
		end
	end)
	
	zone.playerExited:Connect(function(player)
		-- Restore original color
		if (x + z) % 2 == 0 then
			cube.Color = Color3.fromRGB(66, 135, 245)  -- Blue
		else
			cube.Color = Color3.fromRGB(245, 166, 66)  -- Orange
		end
	end)
	
	zonesTable[cube.Name] = zone
end

local function generateGrid(self)
	local startTime = tick()
	
	-- Get LoadingService for progress updates
	local LoadingService = nil
	pcall(function()
		LoadingService = Knit.GetService("LoadingService")
	end)
	
	local function reportProgress(message, current, total)
		if LoadingService then
			LoadingService:ReportProgress("GridService", current or 0, total or 1, message)
		end
	end
	
	reportProgress("Calculating grid dimensions", 0, 100)
	
	-- Only calculate from baseplate if we don't already have dimensions set
	-- (WorldInitService will set these via InitializeWithBaseplates)
	if GRID_WIDTH <= 0 or GRID_DEPTH <= 0 then
		calculateGridFromBaseplate(self._gridData)
	end
	
	-- Clear cell tracking
	self._gridData.cells = {}
	self._gridData.occupiedCells = {}
	
	-- Update map replica with new grid dimensions
	if self.mapReplica then
		self.mapReplica:SetValue({"GridWidth"}, GRID_WIDTH)
		self.mapReplica:SetValue({"GridDepth"}, GRID_DEPTH)
	end
	
	reportProgress("Clearing existing grid", 5, 100)
	
	-- Clear existing zones
	for _, zone in pairs(self.zones) do
		zone:Destroy()
	end
	self.zones = {}
	
	clearGrid()
	local folder = getGridFolder()
	
	-- PHASE 1: Batch create all parts first (fast)
	local allCubes = {}
	local batchCount = 0
	local totalCells = GRID_WIDTH * GRID_DEPTH
	local cellsCreated = 0
	
	reportProgress("Creating grid cells", 10, 100)
	
	for x = 1, GRID_WIDTH do
		for z = 1, GRID_DEPTH do
			local cube = createCubeFast(x, z, folder, self._gridData)
			table.insert(allCubes, {cube = cube, x = x, z = z})
			
			cellsCreated += 1
			batchCount += 1
			if batchCount >= BATCH_SIZE then
				batchCount = 0
				-- Report progress (10-60% range for cell creation)
				local cellProgress = 10 + (cellsCreated / totalCells) * 50
				reportProgress("Creating grid cells", math.floor(cellProgress), 100)
				task.wait()  -- Yield to prevent lag spikes
			end
		end
	end
	
	local partTime = tick()
	print(string.format("[GridService] Created %d parts in %.2fs", #allCubes, partTime - startTime))
	reportProgress("Grid cells created", 60, 100)
	
	-- PHASE 2: Attach zones in batches (slower, do after parts visible)
	reportProgress("Attaching zones", 65, 100)
	
	task.spawn(function()
		local zoneCount = 0
		local totalZones = #allCubes
		for _, data in ipairs(allCubes) do
			attachZone(data.cube, data.x, data.z, self.zones, self.mapReplica)
			
			zoneCount += 1
			if zoneCount % BATCH_SIZE == 0 then
				-- Report progress (65-95% range for zone attachment)
				local zoneProgress = 65 + (zoneCount / totalZones) * 30
				reportProgress("Attaching zones", math.floor(zoneProgress), 100)
				task.wait()  -- Yield periodically
			end
		end
		
		local totalTime = tick()
		print(string.format("[GridService] Attached %d zones in %.2fs (total: %.2fs)", 
			zoneCount, totalTime - partTime, totalTime - startTime))
		
		reportProgress("Grid complete", 100, 100)
		
		-- Mark GridService step as complete in LoadingService
		if LoadingService then
			LoadingService:MarkStepComplete("GridService")
		end
	end)
	
	print(string.format("[GridService] Generated %dx%d grid (%d cells, size %.1f each)", 
		GRID_WIDTH, GRID_DEPTH, #allCubes, CUBE_SIZE))
end

-- === TIMER FUNCTIONS ===

local function initReplica(self)
	-- Calculate grid size first so replica has correct values
	calculateGridFromBaseplate(self._gridData)
	
	self.timerReplica = ReplicaService.NewReplica({
		ClassToken = ReplicaService.NewClassToken("GridTimerReplica"),
		Data = {
			TimeRemaining = TIMER_DURATION,
			IsRunning = false,
		},
		Replication = "All",
	})
	
	-- Map replica to track player positions and explored cells (fog of war)
	self.mapReplica = ReplicaService.NewReplica({
		ClassToken = ReplicaService.NewClassToken("GridMapReplica"),
		Data = {
			PlayerPositions = {},
			ExploredCells = {},  -- Fog of war: { ["x_z"] = true, ... }
			GridWidth = GRID_WIDTH,
			GridDepth = GRID_DEPTH,
		},
		Replication = "All",
	})
end

local function startTimer(self)
	if self.timer and self.timer:IsRunning() then
		return -- Already running
	end
	
	self.timerReplica:SetValue({"TimeRemaining"}, TIMER_DURATION)
	self.timerReplica:SetValue({"IsRunning"}, true)
	
	self.timer = Timer.new(1) -- 1 second interval
	self.timer.Tick:Connect(function()
		local currentTime = self.timerReplica.Data.TimeRemaining
		if currentTime > 0 then
			self.timerReplica:SetValue({"TimeRemaining"}, currentTime - 1)
		else
			self:StopTimer()
			print("[GridService] Timer finished!")
		end
	end)
	
	self.timer:Start()
	print("[GridService] Timer started!")
end

local function stopTimer(self)
	if self.timer then
		self.timer:Stop()
		self.timer:Destroy()
		self.timer = nil
	end
	self.timerReplica:SetValue({"IsRunning"}, false)
end

-- === KNIT LIFECYCLE ===

function GridService:KnitInit()
	initReplica(self)
	
	-- Initialize exclusion zone changed signal
	self.ExclusionZoneChanged = Signal.new()
end

function GridService:KnitStart()
	-- Only auto-generate if _autoStart is true (legacy mode)
	-- WorldInitService will call InitializeWithBaseplates() instead
	if self._autoStart then
		generateGrid(self)
		startTimer(self)
	else
		print("[GridService] Waiting for WorldInitService to initialize grid...")
	end
end

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║               WORLDINITSERVICE INTEGRATION                                 ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

-- Initialize grid using baseplate info from WorldInitService
function GridService:InitializeWithBaseplates(baseplateInfo)
	if not baseplateInfo then
		warn("[GridService] No baseplate info provided!")
		return false
	end
	
	print("[GridService] Initializing with baseplate info from WorldInitService...")
	self._baseplateInfo = baseplateInfo
	self._isGridReady = false
	
	-- Update grid dimensions from baseplate info
	local totalWidth = baseplateInfo.size.X
	local totalDepth = baseplateInfo.size.Z
	
	-- Calculate cell size based on total area
	CUBE_SIZE = math.floor(math.min(totalWidth, totalDepth) / TARGET_CELLS_PER_SIDE)
	CUBE_SIZE = math.max(CUBE_SIZE, 4)  -- Minimum cell size of 4
	
	-- Calculate grid dimensions
	GRID_WIDTH = math.floor(totalWidth / CUBE_SIZE)
	GRID_DEPTH = math.floor(totalDepth / CUBE_SIZE)
	
	-- Recalculate cell size to perfectly fit
	local cellSizeX = totalWidth / GRID_WIDTH
	local cellSizeZ = totalDepth / GRID_DEPTH
	CUBE_SIZE = math.min(cellSizeX, cellSizeZ)
	
	-- Update baseplate center and top
	BASEPLATE_CENTER = Vector3.new(baseplateInfo.position.X, baseplateInfo.position.Y, baseplateInfo.position.Z)
	BASEPLATE_TOP_Y = baseplateInfo.topY
	
	-- Update gridData
	self._gridData.width = GRID_WIDTH
	self._gridData.depth = GRID_DEPTH
	self._gridData.cellSize = CUBE_SIZE
	self._gridData.centerX = BASEPLATE_CENTER.X
	self._gridData.centerZ = BASEPLATE_CENTER.Z
	self._gridData.topY = BASEPLATE_TOP_Y
	
	print(string.format("[GridService] Grid config: %dx%d cells, %.1f studs each, total area: %.0fx%.0f", 
		GRID_WIDTH, GRID_DEPTH, CUBE_SIZE, totalWidth, totalDepth))
	
	-- Update replicas
	if self.mapReplica then
		self.mapReplica:SetValue({"GridWidth"}, GRID_WIDTH)
		self.mapReplica:SetValue({"GridDepth"}, GRID_DEPTH)
	end
	
	-- Generate the grid
	self:GenerateGridNow()
	
	-- Start timer
	startTimer(self)
	
	return true
end

-- Generate grid immediately (called by InitializeWithBaseplates or manually)
function GridService:GenerateGridNow()
	local startTime = tick()
	print("[GridService] Generating grid...")
	
	-- Get LoadingService for progress updates
	local LoadingService = nil
	pcall(function()
		LoadingService = Knit.GetService("LoadingService")
	end)
	
	local function reportProgress(message, current, total)
		if LoadingService then
			LoadingService:ReportProgress("GridService", current or 0, total or 1, message)
		end
	end
	
	reportProgress("Preparing grid", 0, 100)
	
	-- Clear cell tracking
	self._gridData.cells = {}
	self._gridData.occupiedCells = {}
	
	-- Clear existing zones
	for _, zone in pairs(self.zones) do
		zone:Destroy()
	end
	self.zones = {}
	
	clearGrid()
	local folder = getGridFolder()
	
	-- Create all cubes
	local allCubes = {}
	local batchCount = 0
	local totalCells = GRID_WIDTH * GRID_DEPTH
	local cellsCreated = 0
	
	reportProgress("Creating grid cells", 10, 100)
	
	for x = 1, GRID_WIDTH do
		for z = 1, GRID_DEPTH do
			local cube = createCubeFast(x, z, folder, self._gridData)
			table.insert(allCubes, {cube = cube, x = x, z = z})
			
			cellsCreated += 1
			batchCount += 1
			if batchCount >= BATCH_SIZE then
				batchCount = 0
				local cellProgress = 10 + (cellsCreated / totalCells) * 50
				reportProgress("Creating grid cells", math.floor(cellProgress), 100)
				task.wait()
			end
		end
	end
	
	local partTime = tick()
	print(string.format("[GridService] Created %d parts in %.2fs", #allCubes, partTime - startTime))
	reportProgress("Grid cells created", 60, 100)
	
	-- Attach zones in background
	reportProgress("Attaching zones", 65, 100)
	
	task.spawn(function()
		local zoneCount = 0
		local totalZones = #allCubes
		for _, data in ipairs(allCubes) do
			attachZone(data.cube, data.x, data.z, self.zones, self.mapReplica)
			
			zoneCount += 1
			if zoneCount % BATCH_SIZE == 0 then
				local zoneProgress = 65 + (zoneCount / totalZones) * 30
				reportProgress("Attaching zones", math.floor(zoneProgress), 100)
				task.wait()
			end
		end
		
		local totalTime = tick()
		print(string.format("[GridService] Attached %d zones in %.2fs (total: %.2fs)", 
			zoneCount, totalTime - partTime, totalTime - startTime))
		
		reportProgress("Grid complete", 100, 100)
		self._isGridReady = true
	end)
	
	print(string.format("[GridService] Generated %dx%d grid (%d cells, size %.1f each)", 
		GRID_WIDTH, GRID_DEPTH, #allCubes, CUBE_SIZE))
end

-- Check if grid is ready (all zones attached)
function GridService:IsGridReady()
	return self._isGridReady
end

-- Get the baseplate info used for initialization
function GridService:GetBaseplateInfo()
	return self._baseplateInfo
end

-- === PUBLIC METHODS ===

function GridService:RegenerateGrid()
	generateGrid(self)
end

function GridService:ClearGrid()
	-- Destroy all zones
	for _, zone in pairs(self.zones) do
		zone:Destroy()
	end
	self.zones = {}
	
	clearGrid()
end

function GridService:StartTimer()
	startTimer(self)
end

function GridService:StopTimer()
	stopTimer(self)
end

function GridService:ResetTimer()
	stopTimer(self)
	self.timerReplica:SetValue({"TimeRemaining"}, TIMER_DURATION)
end

-- === GRID DATA ACCESS ===

function GridService:GetGridData()
	return self._gridData
end

function GridService:GetGridDimensions()
	return self._gridData.width, self._gridData.depth
end

function GridService:GetCellSize()
	return self._gridData.cellSize
end

function GridService:GetGridCenter()
	return Vector3.new(self._gridData.centerX, self._gridData.topY, self._gridData.centerZ)
end

function GridService:GetTopY()
	return self._gridData.topY
end

function GridService:GetCell(x, z)
	local key = getCellKey(x, z)
	return self._gridData.cells[key]
end

function GridService:GetCellByKey(key)
	return self._gridData.cells[key]
end

function GridService:IsValidCell(x, z)
	return x >= 1 and x <= self._gridData.width and z >= 1 and z <= self._gridData.depth
end

-- === CELL OCCUPANCY ===

function GridService:IsCellOccupied(x, z)
	local key = getCellKey(x, z)
	return self._gridData.occupiedCells[key] ~= nil
end

function GridService:GetCellOwner(x, z)
	local key = getCellKey(x, z)
	return self._gridData.occupiedCells[key]
end

function GridService:SetCellOccupied(x, z, ownerId)
	local key = getCellKey(x, z)
	if not self:IsValidCell(x, z) then
		warn(string.format("[GridService] Invalid cell position: %d, %d", x, z))
		return false
	end
	
	self._gridData.occupiedCells[key] = ownerId
	
	-- Also update cell data if it exists
	if self._gridData.cells[key] then
		self._gridData.cells[key].occupied = true
		self._gridData.cells[key].owner = ownerId
	end
	
	return true
end

function GridService:ClearCellOccupancy(x, z)
	local key = getCellKey(x, z)
	self._gridData.occupiedCells[key] = nil
	
	-- Also update cell data if it exists
	if self._gridData.cells[key] then
		self._gridData.cells[key].occupied = false
		self._gridData.cells[key].owner = nil
	end
end

function GridService:GetOccupiedCells()
	return self._gridData.occupiedCells
end

function GridService:ClearAllOccupancy()
	self._gridData.occupiedCells = {}
	for _, cellData in pairs(self._gridData.cells) do
		cellData.occupied = false
		cellData.owner = nil
	end
end

-- Convert grid position to world position
function GridService:GridToWorld(gridX, gridZ, heightLevel)
	heightLevel = heightLevel or 0
	local offsetX = (gridX - (self._gridData.width + 1) / 2) * self._gridData.cellSize
	local offsetZ = (gridZ - (self._gridData.depth + 1) / 2) * self._gridData.cellSize
	local worldY = self._gridData.topY + (heightLevel * self._gridData.cellSize)
	
	return Vector3.new(
		self._gridData.centerX + offsetX,
		worldY,
		self._gridData.centerZ + offsetZ
	)
end

-- Convert world position to grid position
function GridService:WorldToGrid(worldPos)
	local offsetX = worldPos.X - self._gridData.centerX
	local offsetZ = worldPos.Z - self._gridData.centerZ
	
	local gridX = math.floor(offsetX / self._gridData.cellSize + (self._gridData.width + 1) / 2 + 0.5)
	local gridZ = math.floor(offsetZ / self._gridData.cellSize + (self._gridData.depth + 1) / 2 + 0.5)
	
	return gridX, gridZ
end

-- === EXCLUSION ZONE MANAGEMENT ===

-- Register an exclusion zone where objects should not spawn
function GridService:RegisterExclusionZone(id, position, radius, height, owner)
	self._exclusionZones[id] = {
		position = position,
		radius = radius or 50,
		height = height or 100,
		owner = owner or "unknown",
	}
	print(string.format("[GridService] Registered exclusion zone '%s' at (%.1f, %.1f, %.1f) radius=%.1f owner=%s",
		id, position.X, position.Y, position.Z, radius or 50, owner or "unknown"))
	
	-- Fire signal to notify listeners
	if self.ExclusionZoneChanged then
		self.ExclusionZoneChanged:Fire()
	end
	
	return true
end

-- Remove an exclusion zone
function GridService:RemoveExclusionZone(id)
	if self._exclusionZones[id] then
		self._exclusionZones[id] = nil
		print("[GridService] Removed exclusion zone:", id)
		
		-- Fire signal to notify listeners
		if self.ExclusionZoneChanged then
			self.ExclusionZoneChanged:Fire()
		end
		
		return true
	end
	return false
end

-- Check if a position is inside any exclusion zone
function GridService:IsPositionExcluded(position)
	for id, zone in pairs(self._exclusionZones) do
		local dx = position.X - zone.position.X
		local dz = position.Z - zone.position.Z
		local horizontalDist = math.sqrt(dx * dx + dz * dz)
		
		if horizontalDist < zone.radius then
			local dy = position.Y - zone.position.Y
			if dy > -10 and dy < zone.height then
				return true, id
			end
		end
	end
	return false, nil
end

-- Get all exclusion zones
function GridService:GetExclusionZones()
	return self._exclusionZones
end

-- Get a specific exclusion zone
function GridService:GetExclusionZone(id)
	return self._exclusionZones[id]
end

-- Check if a position is valid for spawning (not excluded and optionally not too close to others)
function GridService:IsValidSpawnPosition(position, minSpacing, existingPositions)
	-- Check exclusion zones first
	local excluded, zoneId = self:IsPositionExcluded(position)
	if excluded then
		return false, "excluded by " .. (zoneId or "unknown")
	end
	
	-- Check spacing from existing positions if provided
	if existingPositions and minSpacing then
		for _, pos in ipairs(existingPositions) do
			local distance = (Vector3.new(position.X, 0, position.Z) - Vector3.new(pos.X, 0, pos.Z)).Magnitude
			if distance < minSpacing then
				return false, "too close to existing"
			end
		end
	end
	
	return true, nil
end

return GridService

