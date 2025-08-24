-- RoomModule.lua

local Room = {}
Room.__index = Room

-- Constructor
function Room.new(id: number)
	local self = setmetatable({}, Room)
	self.id = id
	self.neighbours = {}
	self.center = {}
	self.hasStaircase = false
	return self
end

-- Add a room to the neighbor list
function Room:addNeighbour(other)
	table.insert(self.neighbours, other)
end

-- Check if room has more than one neighbor
function Room:hasNeighbours()
	return #self.neighbours > 1
end

-- Set the center coordinate of the room
function Room:setCenter(r: number, c: number)
	self.center = { r, c }
end

-- Euclidean distance to another room
function Room:distanceTo(other)
	local dx = math.abs(self.center[1] - other.center[1])
	local dy = math.abs(self.center[2] - other.center[2])
	return math.sqrt(dx * dx + dy * dy)
end

return Room
