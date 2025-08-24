-- DungeonModule.lua

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CustomPackages = ReplicatedStorage:WaitForChild("CustomPackages")
local LevelModule = require(CustomPackages.rogueGen._src.Level)

local Dungeon = {}
Dungeon.__index = Dungeon

-- Constructor
function Dungeon.new(nrOfLevels: number, height: number, width: number)
	local self = setmetatable({}, Dungeon)
	self.nrOfLevels = nrOfLevels
	self.height = height
	self.width = width
	self.levels = {}
	return self
end

-- Generates levels in the dungeon
function Dungeon:generateDungeon(advanced: boolean?, maxRooms: number?, maxRoomSize: number?, scatteringFactor: number?)
	for i = 1, self.nrOfLevels do
		local newLevel = LevelModule.new(self.height, self.width)

		if advanced then
			newLevel:setMaxRooms(maxRooms or 10)
			newLevel:setMaxRoomSize(maxRoomSize or 6)
			newLevel:setScatteringFactor(scatteringFactor or 20)
		end

		newLevel:generateLevel()
		self.levels[i] = newLevel
	end
end

-- Prints all levels of the dungeon
function Dungeon:printDungeon()
	for i = 1, #self.levels do
		local header = "L E V E L  " .. i
		local spacing = ""
		for _ = 1, math.floor((self.width + 2) / 2 - (#header) / 2) do
			spacing = spacing .. " "
		end
		print(spacing .. header .. spacing)
		self.levels[i]:printLevel()
		print()
	end
end

return Dungeon
