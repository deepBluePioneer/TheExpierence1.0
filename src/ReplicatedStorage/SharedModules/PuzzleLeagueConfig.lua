--[[
	PuzzleLeagueConfig
	
	Shared configuration constants for the Puzzle League game.
]]

local PuzzleLeagueConfig = {
	-- Board dimensions
	BOARD_WIDTH = 6,
	BOARD_HEIGHT = 12,
	
	-- Tile types (0 = empty, 1-5 = colors)
	EMPTY_TILE = 0,
	NUM_COLORS = 5,
	
	-- Match requirements
	MIN_MATCH_LENGTH = 3,
	
	-- Rising board
	RISE_SPEED = 0.05, -- riseOffset per second (baseline)
	
	-- Gravity animation
	GRAVITY_FALL_SPEED = 8, -- cells per second for falling animation
	
	-- Clear effect timing (server waits for client effects before gravity)
	CLEAR_EFFECT_WHITE_DURATION = 0.5, -- All tiles stay white for this duration
	CLEAR_EFFECT_FLASH_DURATION = 0.15, -- Flash fade out animation
	CLEAR_EFFECT_BUFFER = 0.1,         -- Extra buffer time
	
	-- Swap resolution
	SWAP_RESOLVE_DELAY = 0.25, -- Time after swap before match detection
	
	-- Countdown
	COUNTDOWN_SECONDS = 3,
	
	-- Game phases
	PHASE = {
		MENU = "Menu",
		QUEUE = "Queue",
		COUNTDOWN = "Countdown",
		IN_MATCH = "InMatch",
		RESULT = "Result",
	},
	
	-- Replica class name
	REPLICA_CLASS = "PuzzleLeaguePlayer",
	
	-- UI Colors (mapped from tile IDs client-side)
	TILE_COLORS = {
		[1] = Color3.fromRGB(255, 82, 82),   -- Red
		[2] = Color3.fromRGB(76, 175, 80),   -- Green
		[3] = Color3.fromRGB(33, 150, 243),  -- Blue
		[4] = Color3.fromRGB(255, 235, 59),  -- Yellow
		[5] = Color3.fromRGB(156, 39, 176),  -- Purple
	},
}

return PuzzleLeagueConfig

