local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local Knit = require(Packages.Knit)

local RoomService = Knit.CreateService {
	Name = "RoomService",
	Client = {},
	_rooms = {},          -- Store room data: { [roomId] = { cells = {}, model = Model, ... } }
	_roomIdCounter = 0,
	_gridService = nil,   -- Reference to GridService
}

-- === CONFIG ===
local ROOM_CONFIG = {
	-- Default room size
	DefaultWidth = 2,         -- Room width in grid cells
	DefaultDepth = 2,         -- Room depth in grid cells
	
	-- Room generation settings
	WallHeight = .5,           -- Height of walls in grid units (multiplied by cell size)
	WallThickness = 0.5,      -- Wall thickness in studs
	FloorThickness = 0.5,     -- Floor thickness in studs
	RoofThickness = 0.5,      -- Roof/ceiling thickness in studs
	
	-- Materials
	WallMaterial = Enum.Material.Concrete,
	FloorMaterial = Enum.Material.Concrete,
	RoofMaterial = Enum.Material.Concrete,
	
	-- Colors
	WallColor = Color3.fromRGB(180, 180, 180),
	FloorColor = Color3.fromRGB(120, 120, 120),
	RoofColor = Color3.fromRGB(100, 100, 100),
	
	-- Door settings
	DoorWidth = 0.6,          -- Door width as fraction of cell size
	DoorHeight = 0.8,         -- Door height as fraction of wall height
}

local ROOM_FOLDER_NAME = "Rooms"

-- === HELPERS ===

local function getRoomFolder()
	local folder = Workspace:FindFirstChild(ROOM_FOLDER_NAME)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = ROOM_FOLDER_NAME
		folder.Parent = Workspace
	end
	return folder
end

local function getCellKey(x, z)
	return string.format("%d_%d", x, z)
end

-- === ROOM PART CREATION ===

local function createFloor(self, roomModel, minX, minZ, maxX, maxZ, heightLevel)
	local gridData = self._gridService:GetGridData()
	local cellSize = gridData.cellSize
	
	local widthCells = maxX - minX + 1
	local depthCells = maxZ - minZ + 1
	
	local centerX = (minX + maxX) / 2
	local centerZ = (minZ + maxZ) / 2
	local centerPos = self._gridService:GridToWorld(centerX, centerZ, heightLevel)
	
	local floor = Instance.new("Part")
	floor.Name = "Floor"
	floor.Size = Vector3.new(
		widthCells * cellSize,
		ROOM_CONFIG.FloorThickness,
		depthCells * cellSize
	)
	floor.Position = centerPos + Vector3.new(0, ROOM_CONFIG.FloorThickness / 2, 0)
	floor.Anchored = true
	floor.CanCollide = true
	floor.Material = ROOM_CONFIG.FloorMaterial
	floor.Color = ROOM_CONFIG.FloorColor
	floor.Parent = roomModel
	
	return floor
end

local function createRoof(self, roomModel, minX, minZ, maxX, maxZ, heightLevel)
	local gridData = self._gridService:GetGridData()
	local cellSize = gridData.cellSize
	
	local widthCells = maxX - minX + 1
	local depthCells = maxZ - minZ + 1
	
	local centerX = (minX + maxX) / 2
	local centerZ = (minZ + maxZ) / 2
	local centerPos = self._gridService:GridToWorld(centerX, centerZ, heightLevel)
	
	local wallHeightStuds = ROOM_CONFIG.WallHeight * cellSize
	
	local roof = Instance.new("Part")
	roof.Name = "Roof"
	roof.Size = Vector3.new(
		widthCells * cellSize,
		ROOM_CONFIG.RoofThickness,
		depthCells * cellSize
	)
	roof.Position = centerPos + Vector3.new(0, wallHeightStuds - ROOM_CONFIG.RoofThickness / 2, 0)
	roof.Anchored = true
	roof.CanCollide = true
	roof.Material = ROOM_CONFIG.RoofMaterial
	roof.Color = ROOM_CONFIG.RoofColor
	roof.Parent = roomModel
	
	return roof
end

-- Wall directions: "north" (+Z), "south" (-Z), "east" (+X), "west" (-X)
local function createWallSegment(self, roomModel, startX, startZ, endX, endZ, direction, heightLevel, hasDoor)
	local gridData = self._gridService:GetGridData()
	local cellSize = gridData.cellSize
	local wallHeightStuds = ROOM_CONFIG.WallHeight * cellSize
	local basePos = self._gridService:GridToWorld((startX + endX) / 2, (startZ + endZ) / 2, heightLevel)
	
	local lengthCells
	local wallSize
	local wallOffset
	
	if direction == "north" or direction == "south" then
		-- Wall runs along X axis
		lengthCells = math.abs(endX - startX) + 1
		local zOffset = direction == "north" and cellSize / 2 or -cellSize / 2
		
		if hasDoor then
			-- Create wall with door opening (two wall segments)
			local doorWidthStuds = cellSize * ROOM_CONFIG.DoorWidth
			local doorHeightStuds = wallHeightStuds * ROOM_CONFIG.DoorHeight
			local wallLengthStuds = lengthCells * cellSize
			local sideWallLength = (wallLengthStuds - doorWidthStuds) / 2
			
			-- Left wall segment
			local leftWall = Instance.new("Part")
			leftWall.Name = "Wall_" .. direction .. "_left"
			leftWall.Size = Vector3.new(sideWallLength, wallHeightStuds, ROOM_CONFIG.WallThickness)
			leftWall.Position = basePos + Vector3.new(-wallLengthStuds/2 + sideWallLength/2, wallHeightStuds/2, zOffset)
			leftWall.Anchored = true
			leftWall.CanCollide = true
			leftWall.Material = ROOM_CONFIG.WallMaterial
			leftWall.Color = ROOM_CONFIG.WallColor
			leftWall.Parent = roomModel
			
			-- Right wall segment
			local rightWall = Instance.new("Part")
			rightWall.Name = "Wall_" .. direction .. "_right"
			rightWall.Size = Vector3.new(sideWallLength, wallHeightStuds, ROOM_CONFIG.WallThickness)
			rightWall.Position = basePos + Vector3.new(wallLengthStuds/2 - sideWallLength/2, wallHeightStuds/2, zOffset)
			rightWall.Anchored = true
			rightWall.CanCollide = true
			rightWall.Material = ROOM_CONFIG.WallMaterial
			rightWall.Color = ROOM_CONFIG.WallColor
			rightWall.Parent = roomModel
			
			-- Top segment above door
			local topWall = Instance.new("Part")
			topWall.Name = "Wall_" .. direction .. "_top"
			topWall.Size = Vector3.new(doorWidthStuds, wallHeightStuds - doorHeightStuds, ROOM_CONFIG.WallThickness)
			topWall.Position = basePos + Vector3.new(0, doorHeightStuds + (wallHeightStuds - doorHeightStuds)/2, zOffset)
			topWall.Anchored = true
			topWall.CanCollide = true
			topWall.Material = ROOM_CONFIG.WallMaterial
			topWall.Color = ROOM_CONFIG.WallColor
			topWall.Parent = roomModel
			
			return
		end
		
		wallSize = Vector3.new(lengthCells * cellSize, wallHeightStuds, ROOM_CONFIG.WallThickness)
		wallOffset = Vector3.new(0, wallHeightStuds / 2, zOffset)
	else
		-- Wall runs along Z axis (east/west)
		lengthCells = math.abs(endZ - startZ) + 1
		local xOffset = direction == "east" and cellSize / 2 or -cellSize / 2
		
		if hasDoor then
			local doorWidthStuds = cellSize * ROOM_CONFIG.DoorWidth
			local doorHeightStuds = wallHeightStuds * ROOM_CONFIG.DoorHeight
			local wallLengthStuds = lengthCells * cellSize
			local sideWallLength = (wallLengthStuds - doorWidthStuds) / 2
			
			-- Front wall segment
			local frontWall = Instance.new("Part")
			frontWall.Name = "Wall_" .. direction .. "_front"
			frontWall.Size = Vector3.new(ROOM_CONFIG.WallThickness, wallHeightStuds, sideWallLength)
			frontWall.Position = basePos + Vector3.new(xOffset, wallHeightStuds/2, -wallLengthStuds/2 + sideWallLength/2)
			frontWall.Anchored = true
			frontWall.CanCollide = true
			frontWall.Material = ROOM_CONFIG.WallMaterial
			frontWall.Color = ROOM_CONFIG.WallColor
			frontWall.Parent = roomModel
			
			-- Back wall segment
			local backWall = Instance.new("Part")
			backWall.Name = "Wall_" .. direction .. "_back"
			backWall.Size = Vector3.new(ROOM_CONFIG.WallThickness, wallHeightStuds, sideWallLength)
			backWall.Position = basePos + Vector3.new(xOffset, wallHeightStuds/2, wallLengthStuds/2 - sideWallLength/2)
			backWall.Anchored = true
			backWall.CanCollide = true
			backWall.Material = ROOM_CONFIG.WallMaterial
			backWall.Color = ROOM_CONFIG.WallColor
			backWall.Parent = roomModel
			
			-- Top segment above door
			local topWall = Instance.new("Part")
			topWall.Name = "Wall_" .. direction .. "_top"
			topWall.Size = Vector3.new(ROOM_CONFIG.WallThickness, wallHeightStuds - doorHeightStuds, doorWidthStuds)
			topWall.Position = basePos + Vector3.new(xOffset, doorHeightStuds + (wallHeightStuds - doorHeightStuds)/2, 0)
			topWall.Anchored = true
			topWall.CanCollide = true
			topWall.Material = ROOM_CONFIG.WallMaterial
			topWall.Color = ROOM_CONFIG.WallColor
			topWall.Parent = roomModel
			
			return
		end
		
		wallSize = Vector3.new(ROOM_CONFIG.WallThickness, wallHeightStuds, lengthCells * cellSize)
		wallOffset = Vector3.new(xOffset, wallHeightStuds / 2, 0)
	end
	
	local wall = Instance.new("Part")
	wall.Name = "Wall_" .. direction
	wall.Size = wallSize
	wall.Position = basePos + wallOffset
	wall.Anchored = true
	wall.CanCollide = true
	wall.Material = ROOM_CONFIG.WallMaterial
	wall.Color = ROOM_CONFIG.WallColor
	wall.Parent = roomModel
	
	return wall
end

-- === ROOM GENERATION ===

local function createRectangularRoom(self, startX, startZ, width, depth, options)
	options = options or {}
	local heightLevel = options.heightLevel or 0
	local doors = options.doors or {}  -- { north = true, south = false, east = true, west = false }
	local hasFloor = options.hasFloor ~= false
	local hasRoof = options.hasRoof ~= false
	local roomName = options.name or "Room"
	
	local endX = startX + width - 1
	local endZ = startZ + depth - 1
	
	-- Validate bounds
	if not self._gridService:IsValidCell(startX, startZ) or not self._gridService:IsValidCell(endX, endZ) then
		warn("[RoomService] Room extends outside grid bounds")
		return nil
	end
	
	-- Check for cell conflicts
	local cellsToOccupy = {}
	for x = startX, endX do
		for z = startZ, endZ do
			if self._gridService:IsCellOccupied(x, z) then
				local owner = self._gridService:GetCellOwner(x, z)
				warn(string.format("[RoomService] Cell (%d,%d) is already occupied by %s", x, z, tostring(owner)))
				return nil
			end
			table.insert(cellsToOccupy, { x = x, z = z, key = getCellKey(x, z) })
		end
	end
	
	-- Generate room ID
	self._roomIdCounter += 1
	local roomId = "room_" .. self._roomIdCounter
	
	-- Create room model
	local roomModel = Instance.new("Model")
	roomModel.Name = roomName .. "_" .. roomId
	
	-- Create floor
	if hasFloor then
		createFloor(self, roomModel, startX, startZ, endX, endZ, heightLevel)
	end
	
	-- Create roof
	if hasRoof then
		createRoof(self, roomModel, startX, startZ, endX, endZ, heightLevel)
	end
	
	-- Create walls
	-- North wall (+Z)
	createWallSegment(self, roomModel, startX, endZ, endX, endZ, "north", heightLevel, doors.north)
	-- South wall (-Z)
	createWallSegment(self, roomModel, startX, startZ, endX, startZ, "south", heightLevel, doors.south)
	-- East wall (+X)
	createWallSegment(self, roomModel, endX, startZ, endX, endZ, "east", heightLevel, doors.east)
	-- West wall (-X)
	createWallSegment(self, roomModel, startX, startZ, startX, endZ, "west", heightLevel, doors.west)
	
	-- Parent to folder
	roomModel.Parent = getRoomFolder()
	
	-- Mark cells as occupied in GridService
	for _, cellInfo in ipairs(cellsToOccupy) do
		self._gridService:SetCellOccupied(cellInfo.x, cellInfo.z, roomId)
	end
	
	-- Store room data
	self._rooms[roomId] = {
		id = roomId,
		model = roomModel,
		cells = cellsToOccupy,
		startX = startX,
		startZ = startZ,
		width = width,
		depth = depth,
		heightLevel = heightLevel,
		doors = doors,
	}
	
	print(string.format("[RoomService] Created room '%s' at (%d,%d) size %dx%d", roomId, startX, startZ, width, depth))
	
	return roomId
end


-- === KNIT LIFECYCLE ===

function RoomService:KnitInit()
	print("[RoomService] Initializing...")
end

function RoomService:KnitStart()
	-- Get LoadingService for progress updates
	local LoadingService = nil
	pcall(function()
		LoadingService = Knit.GetService("LoadingService")
	end)
	
	local function reportProgress(message)
		if LoadingService then
			LoadingService:UpdateStatus("RoomService", message, 0)
		end
	end
	
	reportProgress("Waiting for grid...")
	
	-- Get reference to GridService
	self._gridService = Knit.GetService("GridService")
	
	-- Wait for grid to be ready
	task.wait(1)
	
	local gridData = self._gridService:GetGridData()
	print(string.format("[RoomService] Connected to GridService - Grid: %dx%d, Cell size: %.1f", 
		gridData.width, gridData.depth, gridData.cellSize))
	
	reportProgress("Building rooms...")
	
	-- Create a test room (4x4 cells, 2 cells high)
	self:CreateRoom(5, 5, ROOM_CONFIG.DefaultWidth, ROOM_CONFIG.DefaultDepth, {
		name = "TestRoom",
		doors = { south = true },
	})
	
	reportProgress("Rooms complete")
	
	-- Mark step complete
	if LoadingService then
		LoadingService:MarkStepComplete("RoomService")
	end
end

-- === PUBLIC API ===

function RoomService:CreateRoom(startX, startZ, width, depth, options)
	return createRectangularRoom(self, startX, startZ, width, depth, options)
end

function RoomService:DestroyRoom(roomId)
	local roomData = self._rooms[roomId]
	if not roomData then
		warn("[RoomService] Room not found: " .. roomId)
		return false
	end
	
	-- Free up cells in GridService
	for _, cellInfo in ipairs(roomData.cells) do
		self._gridService:ClearCellOccupancy(cellInfo.x, cellInfo.z)
	end
	
	-- Destroy model
	if roomData.model then
		roomData.model:Destroy()
	end
	
	self._rooms[roomId] = nil
	print("[RoomService] Destroyed room: " .. roomId)
	return true
end

function RoomService:ClearAllRooms()
	for roomId, _ in pairs(self._rooms) do
		self:DestroyRoom(roomId)
	end
	self._rooms = {}
	self._roomIdCounter = 0
	print("[RoomService] All rooms cleared")
end

function RoomService:GetRoomData(roomId)
	return self._rooms[roomId]
end

function RoomService:GetAllRooms()
	return self._rooms
end

function RoomService:GetRoomAtCell(x, z)
	local owner = self._gridService:GetCellOwner(x, z)
	if owner then
		return self._rooms[owner]
	end
	return nil
end

return RoomService
