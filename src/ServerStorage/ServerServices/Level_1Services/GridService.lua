local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local CollectionService = game:GetService("CollectionService")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local CustomPackages = ReplicatedStorage:WaitForChild("CustomPackages")
local Knit = require(Packages.Knit)
local Timer = require(Packages.timer)

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

local function calculateGridFromBaseplate()
	local baseplate = Workspace:FindFirstChild("Baseplate")
	if baseplate and baseplate:IsA("BasePart") then
		local baseplateSize = baseplate.Size
		BASEPLATE_CENTER = baseplate.Position
		BASEPLATE_TOP_Y = baseplate.Position.Y + (baseplateSize.Y / 2)
		
		-- Calculate cell size to exactly fit the baseplate
		local minSide = math.min(baseplateSize.X, baseplateSize.Z)
		CUBE_SIZE = math.floor(minSide / TARGET_CELLS_PER_SIDE)
		CUBE_SIZE = math.max(CUBE_SIZE, 4)  -- Minimum cell size of 4
		
		-- Calculate grid dimensions to exactly fill baseplate
		GRID_WIDTH = math.floor(baseplateSize.X / CUBE_SIZE)
		GRID_DEPTH = math.floor(baseplateSize.Z / CUBE_SIZE)
		
		-- Recalculate cell size to perfectly fit (no gaps at edges)
		local cellSizeX = baseplateSize.X / GRID_WIDTH
		local cellSizeZ = baseplateSize.Z / GRID_DEPTH
		CUBE_SIZE = math.min(cellSizeX, cellSizeZ)  -- Use uniform size
		
		print(string.format("[GridService] Baseplate: %.0fx%.0f | Grid: %dx%d | Cell size: %.1f", 
			baseplateSize.X, baseplateSize.Z, GRID_WIDTH, GRID_DEPTH, CUBE_SIZE))
	else
		warn("[GridService] No Baseplate found, using default grid size")
		CUBE_SIZE = 8
	end
	return GRID_WIDTH, GRID_DEPTH
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
cubeTemplate.Transparency = 1  -- Fully transparent
cubeTemplate.Material = Enum.Material.SmoothPlastic

local function createCubeFast(x, z, folder)
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
	
	-- Calculate grid size from baseplate
	calculateGridFromBaseplate()
	
	-- Update map replica with new grid dimensions
	if self.mapReplica then
		self.mapReplica:SetValue({"GridWidth"}, GRID_WIDTH)
		self.mapReplica:SetValue({"GridDepth"}, GRID_DEPTH)
	end
	
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
	
	for x = 1, GRID_WIDTH do
		for z = 1, GRID_DEPTH do
			local cube = createCubeFast(x, z, folder)
			table.insert(allCubes, {cube = cube, x = x, z = z})
			
			batchCount += 1
			if batchCount >= BATCH_SIZE then
				batchCount = 0
				task.wait()  -- Yield to prevent lag spikes
			end
		end
	end
	
	local partTime = tick()
	print(string.format("[GridService] Created %d parts in %.2fs", #allCubes, partTime - startTime))
	
	-- PHASE 2: Attach zones in batches (slower, do after parts visible)
	task.spawn(function()
		local zoneCount = 0
		for _, data in ipairs(allCubes) do
			attachZone(data.cube, data.x, data.z, self.zones, self.mapReplica)
			
			zoneCount += 1
			if zoneCount % BATCH_SIZE == 0 then
				task.wait()  -- Yield periodically
			end
		end
		
		local totalTime = tick()
		print(string.format("[GridService] Attached %d zones in %.2fs (total: %.2fs)", 
			zoneCount, totalTime - partTime, totalTime - startTime))
	end)
	
	print(string.format("[GridService] Generated %dx%d grid (%d cells, size %.1f each)", 
		GRID_WIDTH, GRID_DEPTH, #allCubes, CUBE_SIZE))
end

-- === TIMER FUNCTIONS ===

local function initReplica(self)
	-- Calculate grid size first so replica has correct values
	calculateGridFromBaseplate()
	
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
end

function GridService:KnitStart()
	generateGrid(self)
	startTimer(self)
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

return GridService

