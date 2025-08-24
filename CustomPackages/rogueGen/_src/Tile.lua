-- TileModule.lua

local Tile = {}
Tile.__index = Tile

-- Tile types
Tile.EMPTY        = " "
Tile.FLOOR        = "."
Tile.WALL         = "#"
Tile.A_STAIRCASE  = "<"
Tile.D_STAIRCASE  = ">"
Tile.SOIL         = "%"
Tile.VEIN         = "*"
Tile.C_DOOR       = "+"
Tile.O_DOOR       = "'"

-- Special debug/marker tiles
Tile.PLAYER       = "@"
Tile.BOSS         = "B"

-- Constructor
function Tile.new(classSymbol: string)
	local self = setmetatable({}, Tile)
	self.class = classSymbol
	self.roomId = 0
	return self
end

-- Helper: Is this tile considered a wall (for generation logic)?
function Tile:isWall()
	return (
		self.class == Tile.WALL or
		self.class == Tile.SOIL or
		self.class == Tile.VEIN
	)
end

return Tile
