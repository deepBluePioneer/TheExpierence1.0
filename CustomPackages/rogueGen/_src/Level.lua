-- LevelModule.lua

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CustomPackages = ReplicatedStorage:WaitForChild("CustomPackages")
local _src = CustomPackages:WaitForChild("rogueGen"):WaitForChild("_src")

local FuncModule = require(_src:WaitForChild("MainHelpFunc")) -- assumed renamed
local Tile = require(_src:WaitForChild("Tile"))
local Room = require(_src:WaitForChild("Room"))

local Level = {}
Level.__index = Level

-- Constants
Level.MIN_ROOM_SIZE = 3
Level.veinSpawnRate = 0.02
Level.soilSpawnRate = 0.05

-- Constructor
function Level.new(height: number, width: number)
	if height < 10 or width < 10 then
		error("Level must have height>=10, width>=10")
	end

	local self = setmetatable({}, Level)

	self.height = height
	self.width = width
	self.matrix = {}
	self.rooms = {}
	self.entrances = {}
	self.staircases = {}
	self.rootRoom = nil
	self.endRoom = nil

	self.maxRoomSize = math.ceil(math.min(height, width) / 10) + 5
	self.maxRooms = math.ceil(math.max(height, width) / Level.MIN_ROOM_SIZE)
	self.scatteringFactor = math.ceil(math.max(height, width) / self.maxRoomSize)

	return self
end

-- === Generation ===

function Level:generateLevel()
	self:initMap()
	self:generateRooms()
	local root = self:getRoomTree()
	self:buildCorridors(root)
	-- self:addCycles(5)
	self:addStaircases()
	self:addDoors()
end

function Level:initMap()
	for i = -1, self.height + 1 do
		self.matrix[i] = {}
		for j = 0, self.width + 1 do
			self.matrix[i][j] = Tile.new(Tile.EMPTY)
		end
	end

	self:addWalls(0, 0, self.height + 1, self.width + 1)
end

function Level:printLevel()
	for i = 0, self.height + 1 do
		local row = "  "
		for j = 0, self.width + 1 do
			row = row .. self.matrix[i][j].class .. Tile.EMPTY
		end
		print(row)
	end
end

-- === Room logic ===

function Level:generateRooms()
	for _ = 1, self.maxRooms do
		self:generateRoom()
	end
end

function Level:generateRoom()
	local startRow = math.random(1, self.height - self.maxRoomSize)
	local startCol = math.random(1, self.width - self.maxRoomSize)

	local height = math.random(Level.MIN_ROOM_SIZE, self.maxRoomSize)
	local width = math.random(Level.MIN_ROOM_SIZE, self.maxRoomSize)

	for i = startRow - 1, startRow + height + 1 do
		for j = startCol - 1, startCol + width + 1 do
			if self:isRoom(i, j) then
				return -- discard if overlapping
			end
		end
	end

	self:buildRoom(startRow, startCol, startRow + height, startCol + width)
end

function Level:buildRoom(startR, startC, endR, endC)
	local id = #self.rooms + 1
	local room = Room.new(id)
	local centerR = endR - math.floor((endR - startR) / 2)
	local centerC = endC - math.floor((endC - startC) / 2)
	room:setCenter(centerR, centerC)
	table.insert(self.rooms, room)

	for i = startR, endR do
		for j = startC, endC do
			local tile = self:getTile(i, j)
			tile.roomId, tile.class = id, Tile.FLOOR
		end
	end

	self:addWalls(startR - 1, startC - 1, endR + 1, endC + 1)
end

-- === Corridor Logic ===

function Level:getRoomTree()
	if #self.rooms < 1 then error("Can't generate room tree, no rooms exist") end
	local root, lastLeaf = FuncModule.prims(table.clone(self.rooms))
	self.rootRoom = root
	self.endRoom = lastLeaf
	return root
end

function Level:buildCorridors(root)
	for _, neigh in ipairs(root.neighbours) do
		self:buildCorridor(root, neigh)
		self:buildCorridors(neigh)
	end
end

function Level:buildCorridor(from, to)
	local start, goal = from.center, to.center
	local nextTile = FuncModule.findNext(start, goal)

	local maxSteps = 500
	local steps = 0

	while self:getTile(nextTile[1], nextTile[2]).roomId ~= to.id do
		if steps > maxSteps then
			warn(`[buildCorridor] Max steps exceeded: from Room {from.id} to Room {to.id}`)
			break
		end

		local row, col = nextTile[1], nextTile[2]
		self:buildTile(row, col)

		if math.random() < self.scatteringFactor * 0.05 then
			self:buildRandomTiles(row, col)
		end

		nextTile = FuncModule.findNext(nextTile, goal)
		steps += 1
	end

	table.insert(self.entrances, nextTile)
end


function Level:buildTile(r, c)
	local adj = FuncModule.getAdjacentPos(r, c)
	self:getTile(r, c).class = Tile.FLOOR
	for _, pos in ipairs(adj) do
		local adjR, adjC = pos[1], pos[2]
		if self:getTile(adjR, adjC).class ~= Tile.FLOOR then
			self:placeWall(adjR, adjC)
		end
	end
end

-- === Decoration ===

function Level:addDoors(maxDoors)
	if #self.entrances == 0 or #self.rooms < 2 then return end
	maxDoors = maxDoors or #self.entrances

	for i = 1, maxDoors do
		local e = self.entrances[i]
		if self:isValidEntrance(e[1], e[2]) then
			local tile = self:getTile(e[1], e[2])
			tile.class = (math.random() > 0.5) and Tile.C_DOOR or Tile.O_DOOR
		end
	end
end

function Level:addStaircases(maxStaircases)
	maxStaircases = math.min(maxStaircases or #self.rooms, #self.rooms)
	local staircases = math.random(2, maxStaircases)

	while staircases > 0 do
		local room = self:getRandRoom()
		if not room.hasStaircase or #self.rooms == 1 then
			self:placeStaircase(room, staircases)
			staircases -= 1
		end
	end
end

function Level:addWalls(startR, startC, endR, endC)
	for j = startC, endC do
		self:placeWall(startR, j)
		self:placeWall(endR, j)
	end
	for i = startR, endR do
		self:placeWall(i, startC)
		self:placeWall(i, endC)
	end
end

function Level:placeWall(r, c)
	local tile = self:getTile(r, c)
	if math.random() <= Level.veinSpawnRate then
		tile.class = Tile.VEIN
	elseif math.random() <= Level.soilSpawnRate then
		tile.class = Tile.SOIL
		Level.soilSpawnRate = 0.6
	else
		tile.class = Tile.WALL
		Level.soilSpawnRate = 0.05
	end
end

function Level:placeStaircase(room, staircases)
	local steps = math.random(0, math.floor(self.maxRoomSize / 2))
	local nrow, ncol = unpack(room.center)

	while steps > 0 do
		local row, col = nrow, ncol
		repeat
			nrow, ncol = FuncModule.getRandNeighbour(row, col)
		until self:getTile(nrow, ncol).class == Tile.FLOOR
		steps -= 1
	end

	local finalTile = self:getTile(nrow, ncol)
	finalTile.class = (staircases % 2 == 0) and Tile.D_STAIRCASE or Tile.A_STAIRCASE
	room.hasStaircase = true
	table.insert(self.staircases, { nrow, ncol })
end

-- === Utility ===

function Level:getTile(r, c)
	return self.matrix[r][c]
end

function Level:isRoom(r, c)
	return self:getTile(r, c).roomId ~= 0
end

function Level:isValidEntrance(row, col)
	return (
		(self:getTile(row + 1, col):isWall() and self:getTile(row - 1, col):isWall()) or
		(self:getTile(row, col + 1):isWall() and self:getTile(row, col - 1):isWall())
	)
end

function Level:getRandRoom()
	return self.rooms[math.random(1, #self.rooms)]
end

function Level:getRoot()
	return self.rootRoom
end

function Level:getEnd()
	return self.endRoom
end

function Level:getStaircases()
	return self.staircases
end

function Level:setMaxRooms(m)
	self.maxRooms = m
end

function Level:setMaxRoomSize(m)
	if m > math.min(self.height, self.width) or m < 3 then
		error("MaxRoomSize must be between 3 and height/width - 3")
	end
	self.maxRoomSize = m
end

function Level:setScatteringFactor(f)
	self.scatteringFactor = f
end

function Level:getAdjacentTiles(r, c)
	local result = {}
	for _, pos in ipairs(FuncModule.getAdjacentPos(r, c)) do
		table.insert(result, self:getTile(pos[1], pos[2]))
	end
	return result
end

function Level:buildRandomTiles(r, c)
	for _ = 1, math.random(1, self.scatteringFactor) do
		local nr, nc = FuncModule.getRandNeighbour(r, c, true)
		if self:getTile(nr, nc).roomId == 0 and FuncModule.withinBounds(nr, nc, self.height, self.width) then
			self:buildTile(nr, nc)
			r, c = nr, nc
		end
	end
end

function Level:addCycles(maxCycles)
	for _ = 1, maxCycles do
		local from = self:getRandRoom()
		local to = self:getRandRoom()
		self:buildCorridor(from, to)
	end
end

return Level
