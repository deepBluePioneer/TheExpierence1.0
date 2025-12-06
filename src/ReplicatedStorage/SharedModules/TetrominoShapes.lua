--[[
	TetrominoShapes
	Shared module containing tetromino shape definitions
	Used by both server (TetrominoService) and client (CameraUIController)
]]

local TetrominoShapes = {}

-- The 7 classic tetromino shape names
TetrominoShapes.SHAPE_NAMES = {
	"I",  -- I-piece (straight line)
	"O",  -- O-piece (square)
	"T",  -- T-piece
	"S",  -- S-piece
	"Z",  -- Z-piece
	"J",  -- J-piece
	"L",  -- L-piece
}

-- Tetromino shape definitions (relative block positions from center)
-- Format: {x, z} where x is horizontal offset, z is vertical offset
TetrominoShapes.SHAPE_DEFINITIONS = {
	I = {{0, -1}, {0, 0}, {0, 1}, {0, 2}},  -- Vertical line
	O = {{0, 0}, {1, 0}, {0, 1}, {1, 1}},    -- Square
	T = {{-1, 0}, {0, 0}, {1, 0}, {0, 1}},   -- T shape
	S = {{-1, 1}, {0, 1}, {0, 0}, {1, 0}},   -- S shape
	Z = {{-1, 0}, {0, 0}, {0, 1}, {1, 1}},   -- Z shape
	J = {{-1, 0}, {0, 0}, {0, 1}, {0, 2}},   -- J shape
	L = {{1, 0}, {0, 0}, {0, 1}, {0, 2}},    -- L shape
}

-- Get a random tetromino shape name
function TetrominoShapes.GetRandomShape()
	return TetrominoShapes.SHAPE_NAMES[math.random(1, #TetrominoShapes.SHAPE_NAMES)]
end

-- Get the block positions for a shape
function TetrominoShapes.GetShapeBlocks(shapeName)
	if not shapeName then
		return nil
	end
	return TetrominoShapes.SHAPE_DEFINITIONS[shapeName:upper()]
end

-- Check if a shape name is valid
function TetrominoShapes.IsValidShape(shapeName)
	if not shapeName then
		return false
	end
	return TetrominoShapes.SHAPE_DEFINITIONS[shapeName:upper()] ~= nil
end

return TetrominoShapes

