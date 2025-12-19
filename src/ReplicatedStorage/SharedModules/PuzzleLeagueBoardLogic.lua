--[[
	PuzzleLeagueBoardLogic
	
	Server-authoritative board simulation logic for Puzzle League.
	Contains pure functions for board operations.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SharedModules = ReplicatedStorage:WaitForChild("Source"):WaitForChild("SharedModules")
local Config = require(SharedModules.PuzzleLeagueConfig)

local PuzzleLeagueBoardLogic = {}

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                              BOARD CREATION                                 ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

--[[
	Creates a new empty board.
	@return Board snapshot table
]]
function PuzzleLeagueBoardLogic.CreateEmptyBoard()
	local cells = {}
	for i = 1, Config.BOARD_WIDTH * Config.BOARD_HEIGHT do
		cells[i] = Config.EMPTY_TILE
	end
	
	return {
		w = Config.BOARD_WIDTH,
		h = Config.BOARD_HEIGHT,
		cells = cells,
		rise = 0,
	}
end

--[[
	Creates a new board with initial tiles in the bottom half.
	@return Board snapshot table
]]
function PuzzleLeagueBoardLogic.CreateInitialBoard()
	local board = PuzzleLeagueBoardLogic.CreateEmptyBoard()
	
	-- Fill bottom 6 rows with random tiles (avoiding immediate matches)
	local initialRows = 6
	for y = 1, initialRows do
		for x = 1, Config.BOARD_WIDTH do
			local color = PuzzleLeagueBoardLogic.GetRandomColorAvoidingMatch(board, x, y)
			PuzzleLeagueBoardLogic.SetCell(board, x, y, color)
		end
	end
	
	return board
end

--[[
	Gets a random color that won't create an immediate match.
	@param board The board table
	@param x Column position
	@param y Row position
	@return Color ID
]]
function PuzzleLeagueBoardLogic.GetRandomColorAvoidingMatch(board, x, y)
	local attempts = 0
	local maxAttempts = 20
	
	while attempts < maxAttempts do
		local color = math.random(1, Config.NUM_COLORS)
		
		-- Check horizontal (left 2 tiles)
		local leftMatch = true
		if x >= 3 then
			local left1 = PuzzleLeagueBoardLogic.GetCell(board, x - 1, y)
			local left2 = PuzzleLeagueBoardLogic.GetCell(board, x - 2, y)
			if left1 ~= color or left2 ~= color then
				leftMatch = false
			end
		else
			leftMatch = false
		end
		
		-- Check vertical (below 2 tiles)
		local downMatch = true
		if y >= 3 then
			local down1 = PuzzleLeagueBoardLogic.GetCell(board, x, y - 1)
			local down2 = PuzzleLeagueBoardLogic.GetCell(board, x, y - 2)
			if down1 ~= color or down2 ~= color then
				downMatch = false
			end
		else
			downMatch = false
		end
		
		if not leftMatch and not downMatch then
			return color
		end
		
		attempts = attempts + 1
	end
	
	-- Fallback to random if we can't avoid a match
	return math.random(1, Config.NUM_COLORS)
end

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                              CELL OPERATIONS                                ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

--[[
	Gets the cell value at (x, y).
	@param board The board table
	@param x Column (1-indexed)
	@param y Row (1-indexed, 1 = bottom)
	@return Tile ID or nil if out of bounds
]]
function PuzzleLeagueBoardLogic.GetCell(board, x, y)
	if x < 1 or x > board.w or y < 1 or y > board.h then
		return nil
	end
	local index = (y - 1) * board.w + x
	return board.cells[index]
end

--[[
	Sets the cell value at (x, y).
	@param board The board table
	@param x Column (1-indexed)
	@param y Row (1-indexed, 1 = bottom)
	@param value Tile ID to set
]]
function PuzzleLeagueBoardLogic.SetCell(board, x, y, value)
	if x < 1 or x > board.w or y < 1 or y > board.h then
		return
	end
	local index = (y - 1) * board.w + x
	board.cells[index] = value
end

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                              SWAP OPERATION                                 ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

--[[
	Swaps tiles at (x, y) and (x+1, y).
	@param board The board table
	@param x Column of left tile
	@param y Row
	@return true if swap was valid, false otherwise
]]
function PuzzleLeagueBoardLogic.Swap(board, x, y)
	-- Validate bounds: x must be in [1, w-1], y in [1, h]
	if x < 1 or x >= board.w or y < 1 or y > board.h then
		return false
	end
	
	local left = PuzzleLeagueBoardLogic.GetCell(board, x, y)
	local right = PuzzleLeagueBoardLogic.GetCell(board, x + 1, y)
	
	-- Allow swapping even with empty tiles
	PuzzleLeagueBoardLogic.SetCell(board, x, y, right)
	PuzzleLeagueBoardLogic.SetCell(board, x + 1, y, left)
	
	return true
end

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                              MATCH DETECTION                                ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

--[[
	Finds all matching tiles (3+ in a row/column).
	@param board The board table
	@return Set of cell indices to clear { [index] = true }
]]
function PuzzleLeagueBoardLogic.FindMatches(board)
	local matches = {}
	
	-- Check horizontal matches (garbage tiles don't match)
	for y = 1, board.h do
		local runStart = 1
		local runColor = PuzzleLeagueBoardLogic.GetCell(board, 1, y)
		
		for x = 2, board.w + 1 do
			local cell = PuzzleLeagueBoardLogic.GetCell(board, x, y)
			
			-- Garbage tiles break runs and don't match
			local isValidColor = runColor ~= Config.EMPTY_TILE and runColor ~= Config.GARBAGE_TILE
			
			if cell == runColor and isValidColor then
				-- Continue the run
			else
				-- End of run, check if it's a match
				local runLength = x - runStart
				if runLength >= Config.MIN_MATCH_LENGTH and isValidColor then
					for i = runStart, x - 1 do
						local index = (y - 1) * board.w + i
						matches[index] = true
					end
				end
				runStart = x
				runColor = cell
			end
		end
	end
	
	-- Check vertical matches (garbage tiles don't match)
	for x = 1, board.w do
		local runStart = 1
		local runColor = PuzzleLeagueBoardLogic.GetCell(board, x, 1)
		
		for y = 2, board.h + 1 do
			local cell = PuzzleLeagueBoardLogic.GetCell(board, x, y)
			
			-- Garbage tiles break runs and don't match
			local isValidColor = runColor ~= Config.EMPTY_TILE and runColor ~= Config.GARBAGE_TILE
			
			if cell == runColor and isValidColor then
				-- Continue the run
			else
				-- End of run, check if it's a match
				local runLength = y - runStart
				if runLength >= Config.MIN_MATCH_LENGTH and isValidColor then
					for i = runStart, y - 1 do
						local index = (i - 1) * board.w + x
						matches[index] = true
					end
				end
				runStart = y
				runColor = cell
			end
		end
	end
	
	return matches
end

--[[
	Clears matched tiles from the board.
	@param board The board table
	@param matches Set of indices to clear
	@return Number of tiles cleared
]]
function PuzzleLeagueBoardLogic.ClearMatches(board, matches)
	local count = 0
	for index in pairs(matches) do
		board.cells[index] = Config.EMPTY_TILE
		count = count + 1
	end
	return count
end

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                              GRAVITY                                        ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

--[[
	Applies gravity to make tiles fall down.
	@param board The board table
	@return true if any tiles fell, false otherwise
]]
function PuzzleLeagueBoardLogic.ApplyGravity(board)
	local anyFell = false
	
	for x = 1, board.w do
		-- Find the lowest empty cell and pull tiles down
		local writeY = 1
		
		for y = 1, board.h do
			local cell = PuzzleLeagueBoardLogic.GetCell(board, x, y)
			
			if cell ~= Config.EMPTY_TILE then
				if writeY ~= y then
					PuzzleLeagueBoardLogic.SetCell(board, x, writeY, cell)
					PuzzleLeagueBoardLogic.SetCell(board, x, y, Config.EMPTY_TILE)
					anyFell = true
				end
				writeY = writeY + 1
			end
		end
	end
	
	return anyFell
end

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         MATCH + GRAVITY LOOP                                ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

--[[
	Captures cleared tile positions BEFORE clearing them.
	@param board The board table
	@param matches Set of indices to clear { [index] = true }
	@return Array of { x, y, colorId }
]]
function PuzzleLeagueBoardLogic.CaptureClearedTiles(board, matches)
	local clearedTiles = {}
	print("[BoardLogic] CaptureClearedTiles called")
	
	local matchCount = 0
	for _ in pairs(matches) do matchCount = matchCount + 1 end
	print("[BoardLogic]   Match indices count:", matchCount)
	
	for index in pairs(matches) do
		local colorId = board.cells[index]
		if colorId and colorId ~= Config.EMPTY_TILE then
			-- Convert index to x,y coordinates
			local y = math.floor((index - 1) / board.w) + 1
			local x = ((index - 1) % board.w) + 1
			table.insert(clearedTiles, { x = x, y = y, colorId = colorId })
			print(string.format("[BoardLogic]   Captured: index=%d -> x=%d, y=%d, colorId=%d", index, x, y, colorId))
		end
	end
	
	print("[BoardLogic]   Total captured:", #clearedTiles)
	return clearedTiles
end

--[[
	Processes all matches and gravity until the board is stable.
	Tiles snap instantly to new positions (no animation).
	@param board The board table
	@return totalCleared (number), clearedTiles (array of {x, y, colorId})
]]
function PuzzleLeagueBoardLogic.ProcessUntilStable(board)
	local totalCleared = 0
	local allClearedTiles = {}
	local maxIterations = 100 -- Safety limit
	local iterations = 0
	
	repeat
		iterations = iterations + 1
		
		-- Find matches
		local matches = PuzzleLeagueBoardLogic.FindMatches(board)
		
		-- Capture cleared tiles BEFORE clearing
		local capturedTiles = PuzzleLeagueBoardLogic.CaptureClearedTiles(board, matches)
		for _, tile in ipairs(capturedTiles) do
			table.insert(allClearedTiles, tile)
		end
		
		-- Clear matches
		local cleared = PuzzleLeagueBoardLogic.ClearMatches(board, matches)
		totalCleared = totalCleared + cleared
		
		-- Apply gravity (tiles snap instantly, column-only)
		local anyFell = PuzzleLeagueBoardLogic.ApplyGravity(board)
		
		-- Continue if we cleared anything or tiles fell
		if cleared == 0 and not anyFell then
			break
		end
	until iterations >= maxIterations
	
	return totalCleared, allClearedTiles
end

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                              RISING BOARD                                   ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

--[[
	Generates a new random row of tiles.
	Avoids horizontal matches within the row AND vertical matches with
	the current bottom row (which will be pushed up when this row is added).
	@param board The board table
	@return Array of tile IDs for the new row
]]
function PuzzleLeagueBoardLogic.GenerateNewRow(board)
	local row = {}
	
	for x = 1, board.w do
		local attempts = 0
		local maxAttempts = 20
		local color = math.random(1, Config.NUM_COLORS)
		
		while attempts < maxAttempts do
			local hasMatch = false
			
			-- Check horizontal match with previous 2 tiles in this new row
			if x >= 3 then
				if row[x - 1] == color and row[x - 2] == color then
					hasMatch = true
				end
			end
			
			-- Check vertical match with tile above (current y=1 and y=2, which will become y=2 and y=3)
			-- After push, this new tile will be at y=1, current y=1 will be at y=2, current y=2 will be at y=3
			-- So we need to avoid: newTile == current[y=1] == current[y=2]
			if not hasMatch then
				local above1 = PuzzleLeagueBoardLogic.GetCell(board, x, 1) -- Will be at y=2
				local above2 = PuzzleLeagueBoardLogic.GetCell(board, x, 2) -- Will be at y=3
				if above1 and above2 and color == above1 and color == above2 then
					hasMatch = true
				end
			end
			
			-- Also avoid matching just the tile directly above to reduce chain reaction on rise
			-- This makes the game more strategic (player must set up matches)
			if not hasMatch then
				local above1 = PuzzleLeagueBoardLogic.GetCell(board, x, 1)
				if above1 and color == above1 then
					-- Only reject if we have other options (soft constraint)
					if attempts < maxAttempts / 2 then
						hasMatch = true
					end
				end
			end
			
			if not hasMatch then
				break
			end
			
			color = math.random(1, Config.NUM_COLORS)
			attempts = attempts + 1
		end
		
		row[x] = color
	end
	
	return row
end

--[[
	Pushes the board up by one row and adds a new bottom row.
	@param board The board table
	@param newRow Array of tile IDs for the new bottom row
]]
function PuzzleLeagueBoardLogic.PushBoardUp(board, newRow)
	-- Shift all existing rows up by one
	for y = board.h, 2, -1 do
		for x = 1, board.w do
			local below = PuzzleLeagueBoardLogic.GetCell(board, x, y - 1)
			PuzzleLeagueBoardLogic.SetCell(board, x, y, below)
		end
	end
	
	-- Insert new row at the bottom
	for x = 1, board.w do
		PuzzleLeagueBoardLogic.SetCell(board, x, 1, newRow[x])
	end
end

--[[
	Checks if the player has topped out (any tile in top row).
	@param board The board table
	@return true if topped out, false otherwise
]]
function PuzzleLeagueBoardLogic.IsTopOut(board)
	for x = 1, board.w do
		local cell = PuzzleLeagueBoardLogic.GetCell(board, x, board.h)
		if cell ~= Config.EMPTY_TILE then
			return true
		end
	end
	return false
end

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                              SNAPSHOT                                       ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

--[[
	Creates a deep copy snapshot of the board (primitive data only).
	@param board The board table
	@return New board table (safe for replication)
]]
function PuzzleLeagueBoardLogic.CreateSnapshot(board)
	local cellsCopy = {}
	for i, v in ipairs(board.cells) do
		cellsCopy[i] = v
	end
	
	return {
		w = board.w,
		h = board.h,
		cells = cellsCopy,
		rise = board.rise,
	}
end

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                              GARBAGE SYSTEM                                 ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

--[[
	Finds all garbage tiles adjacent to matched/cleared tiles.
	@param board The board table
	@param clearedIndices Set of indices that were cleared { [index] = true }
	@return Set of garbage tile indices to convert { [index] = true }
]]
function PuzzleLeagueBoardLogic.FindAdjacentGarbage(board, clearedIndices)
	local adjacentGarbage = {}
	
	for index in pairs(clearedIndices) do
		local y = math.floor((index - 1) / board.w) + 1
		local x = ((index - 1) % board.w) + 1
		
		-- Check all 4 adjacent cells
		local neighbors = {
			{ x = x - 1, y = y }, -- Left
			{ x = x + 1, y = y }, -- Right
			{ x = x, y = y - 1 }, -- Below
			{ x = x, y = y + 1 }, -- Above
		}
		
		for _, neighbor in ipairs(neighbors) do
			local cell = PuzzleLeagueBoardLogic.GetCell(board, neighbor.x, neighbor.y)
			if cell == Config.GARBAGE_TILE then
				local neighborIndex = (neighbor.y - 1) * board.w + neighbor.x
				adjacentGarbage[neighborIndex] = true
			end
		end
	end
	
	return adjacentGarbage
end

--[[
	Converts garbage tiles to random colored tiles.
	@param board The board table
	@param garbageIndices Set of garbage indices to convert { [index] = true }
	@return Array of converted tiles { {x, y, colorId}, ... }
]]
function PuzzleLeagueBoardLogic.ConvertGarbage(board, garbageIndices)
	local convertedTiles = {}
	
	for index in pairs(garbageIndices) do
		local y = math.floor((index - 1) / board.w) + 1
		local x = ((index - 1) % board.w) + 1
		
		-- Convert to a random color
		local newColor = math.random(1, Config.NUM_COLORS)
		board.cells[index] = newColor
		
		table.insert(convertedTiles, { x = x, y = y, colorId = newColor })
	end
	
	return convertedTiles
end

--[[
	Calculates how much garbage to send based on tiles cleared and chain level.
	ANY match sends garbage! More tiles and chains = more garbage.
	@param tilesCleared Number of tiles cleared in this clear
	@param chainLevel Current chain level (1 = no chain, 2+ = chain)
	@return Number of garbage cells to send
]]
function PuzzleLeagueBoardLogic.CalculateGarbageSent(tilesCleared, chainLevel)
	-- Base: any match sends garbage
	-- 3 tiles = 1, 4 tiles = 2, 5 tiles = 3, etc.
	local baseGarbage = Config.GARBAGE_PER_MATCH + math.max(0, tilesCleared - 3) * Config.GARBAGE_PER_EXTRA_TILE
	
	-- Chain multiplier: chain level multiplies garbage
	-- Chain 1 = x1, Chain 2 = x2, Chain 3 = x3, etc.
	local chainMultiplier = chainLevel
	if chainLevel > 1 then
		chainMultiplier = chainLevel * Config.GARBAGE_CHAIN_MULTIPLIER / 2
	end
	
	local totalGarbage = math.floor(baseGarbage * chainMultiplier)
	
	return totalGarbage
end

--[[
	Drops garbage bar from the top of the board.
	Garbage falls and lands on top of existing tiles.
	@param board The board table
	@param garbageRows Number of rows of garbage to drop
	@return true if successful, false if would cause immediate top-out
]]
function PuzzleLeagueBoardLogic.DropGarbageFromTop(board, garbageRows)
	if garbageRows <= 0 then
		return true
	end
	
	-- Cap garbage rows
	garbageRows = math.min(garbageRows, 6)
	
	-- Find the highest occupied row in each column
	local columnHeights = {}
	for x = 1, board.w do
		columnHeights[x] = 0
		for y = board.h, 1, -1 do
			local cell = PuzzleLeagueBoardLogic.GetCell(board, x, y)
			if cell ~= Config.EMPTY_TILE then
				columnHeights[x] = y
				break
			end
		end
	end
	
	-- Find the overall highest point (garbage lands on top of all columns)
	local highestPoint = 0
	for x = 1, board.w do
		highestPoint = math.max(highestPoint, columnHeights[x])
	end
	
	-- Check if garbage would exceed board height
	local garbageBottomY = highestPoint + 1
	local garbageTopY = highestPoint + garbageRows
	
	if garbageTopY > board.h then
		-- Would top out - place as much as we can
		garbageRows = board.h - highestPoint
		if garbageRows <= 0 then
			return false -- Board is already full
		end
		garbageBottomY = highestPoint + 1
		garbageTopY = board.h
	end
	
	-- Place garbage rows (full width bar)
	for y = garbageBottomY, garbageTopY do
		for x = 1, board.w do
			PuzzleLeagueBoardLogic.SetCell(board, x, y, Config.GARBAGE_TILE)
		end
	end
	
	return not PuzzleLeagueBoardLogic.IsTopOut(board)
end

--[[
	Legacy function - spawns garbage at bottom pushing tiles up.
	@deprecated Use DropGarbageFromTop instead
]]
function PuzzleLeagueBoardLogic.SpawnGarbage(board, garbageRows)
	return PuzzleLeagueBoardLogic.DropGarbageFromTop(board, garbageRows)
end

--[[
	Counts garbage tiles on the board.
	@param board The board table
	@return Number of garbage tiles
]]
function PuzzleLeagueBoardLogic.CountGarbage(board)
	local count = 0
	for _, cell in ipairs(board.cells) do
		if cell == Config.GARBAGE_TILE then
			count = count + 1
		end
	end
	return count
end

--[[
	Checks if a cell is a garbage tile.
	@param board The board table
	@param x Column position
	@param y Row position
	@return true if garbage, false otherwise
]]
function PuzzleLeagueBoardLogic.IsGarbage(board, x, y)
	return PuzzleLeagueBoardLogic.GetCell(board, x, y) == Config.GARBAGE_TILE
end

return PuzzleLeagueBoardLogic

