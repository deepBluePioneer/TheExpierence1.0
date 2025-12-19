--[[
	PuzzleLeagueTests
	
	Automated tests for the Puzzle League game logic.
	Uses Roblox TestService for test assertions.
	
	Run these tests by enabling TestService.AutoRuns in Studio
	or by calling TestService:Run()
]]

local TestService = game:GetService("TestService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Wait for modules to be available
local SharedModules = ReplicatedStorage:WaitForChild("Source"):WaitForChild("SharedModules")
local Config = require(SharedModules.PuzzleLeagueConfig)
local BoardLogic = require(SharedModules.PuzzleLeagueBoardLogic)

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                              TEST UTILITIES                                 ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

local testsPassed = 0
local testsFailed = 0

local function test(name, func)
	local success, err = pcall(func)
	if success then
		TestService:Check(true, name)
		testsPassed = testsPassed + 1
	else
		TestService:Check(false, name .. " - " .. tostring(err))
		testsFailed = testsFailed + 1
	end
end

local function assertEqual(actual, expected, message)
	if actual ~= expected then
		error(string.format("%s: expected %s, got %s", message or "Assertion failed", tostring(expected), tostring(actual)))
	end
end

local function assertTrue(condition, message)
	if not condition then
		error(message or "Expected true, got false")
	end
end

local function assertFalse(condition, message)
	if condition then
		error(message or "Expected false, got true")
	end
end

local function assertTableLength(tbl, expectedLength, message)
	local actualLength = #tbl
	if actualLength ~= expectedLength then
		error(string.format("%s: expected length %d, got %d", message or "Table length mismatch", expectedLength, actualLength))
	end
end

-- Create a test board with specific cell values
local function createTestBoard(cells, width, height)
	width = width or Config.BOARD_WIDTH
	height = height or Config.BOARD_HEIGHT
	
	local board = {
		w = width,
		h = height,
		cells = {},
		rise = 0,
	}
	
	-- Fill with empty tiles
	for i = 1, width * height do
		board.cells[i] = Config.EMPTY_TILE
	end
	
	-- Set specific cells if provided
	if cells then
		for _, cell in ipairs(cells) do
			local index = (cell.y - 1) * width + cell.x
			board.cells[index] = cell.color
		end
	end
	
	return board
end

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         BOARD CREATION TESTS                                ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

test("CreateEmptyBoard creates correct dimensions", function()
	local board = BoardLogic.CreateEmptyBoard()
	assertEqual(board.w, Config.BOARD_WIDTH, "Board width")
	assertEqual(board.h, Config.BOARD_HEIGHT, "Board height")
	assertEqual(#board.cells, Config.BOARD_WIDTH * Config.BOARD_HEIGHT, "Cell count")
	assertEqual(board.rise, 0, "Initial rise")
end)

test("CreateEmptyBoard fills with empty tiles", function()
	local board = BoardLogic.CreateEmptyBoard()
	for i, cell in ipairs(board.cells) do
		assertEqual(cell, Config.EMPTY_TILE, "Cell " .. i .. " should be empty")
	end
end)

test("CreateInitialBoard creates non-empty bottom half", function()
	local board = BoardLogic.CreateInitialBoard()
	local hasNonEmpty = false
	
	-- Check bottom 6 rows have some tiles
	for y = 1, 6 do
		for x = 1, board.w do
			local cell = BoardLogic.GetCell(board, x, y)
			if cell ~= Config.EMPTY_TILE then
				hasNonEmpty = true
				break
			end
		end
	end
	
	assertTrue(hasNonEmpty, "Bottom half should have tiles")
end)

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         CELL OPERATION TESTS                                ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

test("GetCell returns correct value", function()
	local board = createTestBoard({
		{ x = 1, y = 1, color = 1 },
		{ x = 3, y = 2, color = 2 },
	})
	
	assertEqual(BoardLogic.GetCell(board, 1, 1), 1, "Cell at (1,1)")
	assertEqual(BoardLogic.GetCell(board, 3, 2), 2, "Cell at (3,2)")
	assertEqual(BoardLogic.GetCell(board, 2, 1), Config.EMPTY_TILE, "Empty cell at (2,1)")
end)

test("GetCell returns nil for out of bounds", function()
	local board = BoardLogic.CreateEmptyBoard()
	assertEqual(BoardLogic.GetCell(board, 0, 1), nil, "x=0 out of bounds")
	assertEqual(BoardLogic.GetCell(board, 1, 0), nil, "y=0 out of bounds")
	assertEqual(BoardLogic.GetCell(board, board.w + 1, 1), nil, "x>width out of bounds")
	assertEqual(BoardLogic.GetCell(board, 1, board.h + 1), nil, "y>height out of bounds")
end)

test("SetCell updates correct position", function()
	local board = BoardLogic.CreateEmptyBoard()
	BoardLogic.SetCell(board, 2, 3, 5)
	assertEqual(BoardLogic.GetCell(board, 2, 3), 5, "Cell should be updated")
end)

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                              SWAP TESTS                                     ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

test("Swap exchanges two adjacent tiles", function()
	local board = createTestBoard({
		{ x = 1, y = 1, color = 1 },
		{ x = 2, y = 1, color = 2 },
	})
	
	local result = BoardLogic.Swap(board, 1, 1)
	assertTrue(result, "Swap should succeed")
	assertEqual(BoardLogic.GetCell(board, 1, 1), 2, "Left cell after swap")
	assertEqual(BoardLogic.GetCell(board, 2, 1), 1, "Right cell after swap")
end)

test("Swap with empty tile works", function()
	local board = createTestBoard({
		{ x = 1, y = 1, color = 1 },
		-- x=2,y=1 is empty
	})
	
	local result = BoardLogic.Swap(board, 1, 1)
	assertTrue(result, "Swap with empty should succeed")
	assertEqual(BoardLogic.GetCell(board, 1, 1), Config.EMPTY_TILE, "Left cell should be empty")
	assertEqual(BoardLogic.GetCell(board, 2, 1), 1, "Right cell should have tile")
end)

test("Swap at right edge fails", function()
	local board = BoardLogic.CreateEmptyBoard()
	local result = BoardLogic.Swap(board, board.w, 1)
	assertFalse(result, "Swap at right edge should fail")
end)

test("Swap out of bounds fails", function()
	local board = BoardLogic.CreateEmptyBoard()
	assertFalse(BoardLogic.Swap(board, 0, 1), "Swap at x=0 should fail")
	assertFalse(BoardLogic.Swap(board, 1, 0), "Swap at y=0 should fail")
	assertFalse(BoardLogic.Swap(board, 1, board.h + 1), "Swap at y>height should fail")
end)

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         MATCH DETECTION TESTS                               ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

test("FindMatches detects horizontal 3-match", function()
	local board = createTestBoard({
		{ x = 1, y = 1, color = 1 },
		{ x = 2, y = 1, color = 1 },
		{ x = 3, y = 1, color = 1 },
	})
	
	local matches = BoardLogic.FindMatches(board)
	local matchCount = 0
	for _ in pairs(matches) do matchCount = matchCount + 1 end
	assertEqual(matchCount, 3, "Should find 3 matching cells")
end)

test("FindMatches detects vertical 3-match", function()
	local board = createTestBoard({
		{ x = 1, y = 1, color = 2 },
		{ x = 1, y = 2, color = 2 },
		{ x = 1, y = 3, color = 2 },
	})
	
	local matches = BoardLogic.FindMatches(board)
	local matchCount = 0
	for _ in pairs(matches) do matchCount = matchCount + 1 end
	assertEqual(matchCount, 3, "Should find 3 matching cells")
end)

test("FindMatches ignores 2-in-a-row", function()
	local board = createTestBoard({
		{ x = 1, y = 1, color = 1 },
		{ x = 2, y = 1, color = 1 },
	})
	
	local matches = BoardLogic.FindMatches(board)
	local matchCount = 0
	for _ in pairs(matches) do matchCount = matchCount + 1 end
	assertEqual(matchCount, 0, "Should not match only 2")
end)

test("FindMatches detects 4-match", function()
	local board = createTestBoard({
		{ x = 1, y = 1, color = 3 },
		{ x = 2, y = 1, color = 3 },
		{ x = 3, y = 1, color = 3 },
		{ x = 4, y = 1, color = 3 },
	})
	
	local matches = BoardLogic.FindMatches(board)
	local matchCount = 0
	for _ in pairs(matches) do matchCount = matchCount + 1 end
	assertEqual(matchCount, 4, "Should find 4 matching cells")
end)

test("FindMatches ignores empty tiles", function()
	local board = createTestBoard({
		-- All empty, no matches
	})
	
	local matches = BoardLogic.FindMatches(board)
	local matchCount = 0
	for _ in pairs(matches) do matchCount = matchCount + 1 end
	assertEqual(matchCount, 0, "Empty board should have no matches")
end)

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         CLEAR CAPTURE TESTS                                 ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

test("CaptureClearedTiles returns correct positions and colors", function()
	local board = createTestBoard({
		{ x = 1, y = 1, color = 1 },
		{ x = 2, y = 1, color = 1 },
		{ x = 3, y = 1, color = 1 },
	})
	
	local matches = BoardLogic.FindMatches(board)
	local clearedTiles = BoardLogic.CaptureClearedTiles(board, matches)
	
	assertTableLength(clearedTiles, 3, "Should capture 3 tiles")
	
	-- Verify each captured tile has correct structure
	for _, tile in ipairs(clearedTiles) do
		assertTrue(tile.x ~= nil, "Tile should have x")
		assertTrue(tile.y ~= nil, "Tile should have y")
		assertTrue(tile.colorId ~= nil, "Tile should have colorId")
		assertEqual(tile.colorId, 1, "Captured color should be 1")
		assertEqual(tile.y, 1, "Captured y should be 1")
	end
end)

test("CaptureClearedTiles captures BEFORE clear", function()
	local board = createTestBoard({
		{ x = 1, y = 1, color = 2 },
		{ x = 1, y = 2, color = 2 },
		{ x = 1, y = 3, color = 2 },
	})
	
	local matches = BoardLogic.FindMatches(board)
	local clearedTiles = BoardLogic.CaptureClearedTiles(board, matches)
	
	-- Tiles should still be on board (not cleared yet)
	assertEqual(BoardLogic.GetCell(board, 1, 1), 2, "Tile should still exist")
	assertEqual(BoardLogic.GetCell(board, 1, 2), 2, "Tile should still exist")
	assertEqual(BoardLogic.GetCell(board, 1, 3), 2, "Tile should still exist")
	
	-- But we should have captured their positions
	assertTableLength(clearedTiles, 3, "Should have captured 3 positions")
end)

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                              GRAVITY TESTS                                  ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

test("ApplyGravity makes tiles fall straight down", function()
	local board = createTestBoard({
		{ x = 1, y = 3, color = 1 }, -- Should fall to y=1
	})
	
	local fell = BoardLogic.ApplyGravity(board)
	assertTrue(fell, "Tiles should have fallen")
	assertEqual(BoardLogic.GetCell(board, 1, 1), 1, "Tile should be at bottom")
	assertEqual(BoardLogic.GetCell(board, 1, 3), Config.EMPTY_TILE, "Original position should be empty")
end)

test("ApplyGravity preserves column", function()
	local board = createTestBoard({
		{ x = 3, y = 5, color = 2 }, -- Should fall to y=1 in column 3
	})
	
	BoardLogic.ApplyGravity(board)
	assertEqual(BoardLogic.GetCell(board, 3, 1), 2, "Tile should be in same column at bottom")
	assertEqual(BoardLogic.GetCell(board, 2, 1), Config.EMPTY_TILE, "Adjacent column should be empty")
	assertEqual(BoardLogic.GetCell(board, 4, 1), Config.EMPTY_TILE, "Adjacent column should be empty")
end)

test("ApplyGravity preserves relative order", function()
	local board = createTestBoard({
		{ x = 1, y = 2, color = 1 }, -- Should end up at y=1
		{ x = 1, y = 4, color = 2 }, -- Should end up at y=2
		{ x = 1, y = 6, color = 3 }, -- Should end up at y=3
	})
	
	BoardLogic.ApplyGravity(board)
	assertEqual(BoardLogic.GetCell(board, 1, 1), 1, "Bottom tile")
	assertEqual(BoardLogic.GetCell(board, 1, 2), 2, "Middle tile")
	assertEqual(BoardLogic.GetCell(board, 1, 3), 3, "Top tile")
end)

test("ApplyGravity does not move tiles sideways", function()
	local board = createTestBoard({
		{ x = 2, y = 1, color = 1 }, -- On ground in column 2
		{ x = 3, y = 3, color = 2 }, -- Floating in column 3
	})
	
	BoardLogic.ApplyGravity(board)
	
	-- Column 2 should be unchanged
	assertEqual(BoardLogic.GetCell(board, 2, 1), 1, "Column 2 tile unchanged")
	
	-- Column 3 tile should fall but stay in column 3
	assertEqual(BoardLogic.GetCell(board, 3, 1), 2, "Column 3 tile fell to bottom")
	assertEqual(BoardLogic.GetCell(board, 2, 2), Config.EMPTY_TILE, "No sideways movement")
end)

test("ApplyGravity returns false when no tiles fell", function()
	local board = createTestBoard({
		{ x = 1, y = 1, color = 1 }, -- Already at bottom
		{ x = 2, y = 1, color = 2 }, -- Already at bottom
	})
	
	local fell = BoardLogic.ApplyGravity(board)
	assertFalse(fell, "No tiles should fall")
end)

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                      PROCESS UNTIL STABLE TESTS                             ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

test("ProcessUntilStable clears matches and applies gravity", function()
	-- Create a scenario where clearing causes a chain
	local board = createTestBoard({
		{ x = 1, y = 1, color = 1 },
		{ x = 2, y = 1, color = 1 },
		{ x = 3, y = 1, color = 1 }, -- Match at bottom
		{ x = 1, y = 2, color = 2 }, -- Will fall after clear
	})
	
	local totalCleared, clearedTiles = BoardLogic.ProcessUntilStable(board)
	
	assertEqual(totalCleared, 3, "Should clear 3 tiles")
	assertTableLength(clearedTiles, 3, "Should return 3 cleared tile positions")
	
	-- Tile at (1,2) should have fallen to (1,1)
	assertEqual(BoardLogic.GetCell(board, 1, 1), 2, "Tile should have fallen")
end)

test("ProcessUntilStable returns clearedTiles with correct structure", function()
	local board = createTestBoard({
		{ x = 1, y = 1, color = 3 },
		{ x = 2, y = 1, color = 3 },
		{ x = 3, y = 1, color = 3 },
	})
	
	local totalCleared, clearedTiles = BoardLogic.ProcessUntilStable(board)
	
	assertEqual(totalCleared, 3, "Should clear 3 tiles")
	
	for _, tile in ipairs(clearedTiles) do
		assertTrue(type(tile.x) == "number", "x should be number")
		assertTrue(type(tile.y) == "number", "y should be number")
		assertTrue(type(tile.colorId) == "number", "colorId should be number")
		assertEqual(tile.colorId, 3, "colorId should be 3")
	end
end)

test("ProcessUntilStable handles chain reactions", function()
	-- Create a scenario where clearing triggers another match
	local board = createTestBoard({
		-- Bottom row: match
		{ x = 1, y = 1, color = 1 },
		{ x = 2, y = 1, color = 1 },
		{ x = 3, y = 1, color = 1 },
		-- Row above: will form match after falling
		{ x = 1, y = 2, color = 2 },
		{ x = 2, y = 2, color = 2 },
		{ x = 3, y = 2, color = 2 },
	})
	
	local totalCleared, clearedTiles = BoardLogic.ProcessUntilStable(board)
	
	-- Both matches should be cleared (3 + 3 = 6)
	assertEqual(totalCleared, 6, "Should clear 6 tiles total")
	assertTableLength(clearedTiles, 6, "Should return all 6 cleared positions")
end)

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         SNAPSHOT TESTS                                      ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

test("CreateSnapshot creates deep copy", function()
	local board = createTestBoard({
		{ x = 1, y = 1, color = 1 },
	})
	
	local snapshot = BoardLogic.CreateSnapshot(board)
	
	-- Modify original
	BoardLogic.SetCell(board, 1, 1, 5)
	
	-- Snapshot should be unchanged
	local snapshotCell = snapshot.cells[(1 - 1) * snapshot.w + 1]
	assertEqual(snapshotCell, 1, "Snapshot should be independent")
end)

test("CreateSnapshot contains only primitive data", function()
	local board = BoardLogic.CreateInitialBoard()
	local snapshot = BoardLogic.CreateSnapshot(board)
	
	-- Check all values are primitive (numbers)
	assertEqual(type(snapshot.w), "number", "w should be number")
	assertEqual(type(snapshot.h), "number", "h should be number")
	assertEqual(type(snapshot.rise), "number", "rise should be number")
	assertEqual(type(snapshot.cells), "table", "cells should be table")
	
	for i, cell in ipairs(snapshot.cells) do
		assertEqual(type(cell), "number", "Cell " .. i .. " should be number")
	end
end)

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         RISING BOARD TESTS                                  ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

test("PushBoardUp shifts tiles correctly", function()
	local board = createTestBoard({
		{ x = 1, y = 1, color = 1 },
		{ x = 2, y = 2, color = 2 },
	})
	
	local newRow = { 5, 5, 5, 5, 5, 5 } -- New bottom row
	BoardLogic.PushBoardUp(board, newRow)
	
	-- Original tiles should have moved up
	assertEqual(BoardLogic.GetCell(board, 1, 2), 1, "Tile should move from y=1 to y=2")
	assertEqual(BoardLogic.GetCell(board, 2, 3), 2, "Tile should move from y=2 to y=3")
	
	-- New row at bottom
	assertEqual(BoardLogic.GetCell(board, 1, 1), 5, "New row at bottom")
end)

test("IsTopOut detects tiles in top row", function()
	local board = createTestBoard({
		{ x = 1, y = Config.BOARD_HEIGHT, color = 1 }, -- Top row
	})
	
	assertTrue(BoardLogic.IsTopOut(board), "Should detect top-out")
end)

test("IsTopOut returns false for safe board", function()
	local board = createTestBoard({
		{ x = 1, y = Config.BOARD_HEIGHT - 1, color = 1 }, -- Below top row
	})
	
	assertFalse(BoardLogic.IsTopOut(board), "Should not detect top-out")
end)

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                      CLEAR EFFECT BUG TESTS                                 ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

test("ClearedTiles positions are accurate for horizontal match", function()
	local board = createTestBoard({
		{ x = 2, y = 3, color = 4 },
		{ x = 3, y = 3, color = 4 },
		{ x = 4, y = 3, color = 4 },
	})
	
	local matches = BoardLogic.FindMatches(board)
	local clearedTiles = BoardLogic.CaptureClearedTiles(board, matches)
	
	-- Verify exact positions
	local positions = {}
	for _, tile in ipairs(clearedTiles) do
		positions[tile.x .. "," .. tile.y] = tile.colorId
	end
	
	assertTrue(positions["2,3"] == 4, "Should have tile at (2,3)")
	assertTrue(positions["3,3"] == 4, "Should have tile at (3,3)")
	assertTrue(positions["4,3"] == 4, "Should have tile at (4,3)")
end)

test("ClearedTiles positions are accurate for vertical match", function()
	local board = createTestBoard({
		{ x = 5, y = 1, color = 2 },
		{ x = 5, y = 2, color = 2 },
		{ x = 5, y = 3, color = 2 },
	})
	
	local matches = BoardLogic.FindMatches(board)
	local clearedTiles = BoardLogic.CaptureClearedTiles(board, matches)
	
	-- Verify exact positions
	local positions = {}
	for _, tile in ipairs(clearedTiles) do
		positions[tile.x .. "," .. tile.y] = tile.colorId
	end
	
	assertTrue(positions["5,1"] == 2, "Should have tile at (5,1)")
	assertTrue(positions["5,2"] == 2, "Should have tile at (5,2)")
	assertTrue(positions["5,3"] == 2, "Should have tile at (5,3)")
end)

test("Swap into empty then match captures correct positions", function()
	-- Simulate: swap tile into empty space, gravity falls, creates match
	local board = createTestBoard({
		-- Column 1: will have tile swapped in
		{ x = 1, y = 1, color = 1 },
		{ x = 1, y = 2, color = 1 },
		-- Column 2: tile to swap
		{ x = 2, y = 3, color = 1 }, -- This will be swapped left
	})
	
	-- Swap (1,3) with (2,3) - moves tile from column 2 to column 1
	BoardLogic.Swap(board, 1, 3)
	
	-- Now column 1 has: y=1: 1, y=2: 1, y=3: 1 (match!)
	local totalCleared, clearedTiles = BoardLogic.ProcessUntilStable(board)
	
	assertEqual(totalCleared, 3, "Should clear 3 tiles")
	
	-- All cleared tiles should be in column 1
	for _, tile in ipairs(clearedTiles) do
		assertEqual(tile.x, 1, "Cleared tile should be in column 1")
		assertEqual(tile.colorId, 1, "Cleared tile color should be 1")
	end
end)

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                      COORDINATE CONVERSION TESTS                            ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

test("Index to coordinate conversion is correct", function()
	local board = BoardLogic.CreateEmptyBoard()
	local w = board.w
	
	-- Test several positions
	local testCases = {
		{ index = 1, expectedX = 1, expectedY = 1 },           -- Bottom-left corner
		{ index = w, expectedX = w, expectedY = 1 },           -- Bottom-right corner
		{ index = w + 1, expectedX = 1, expectedY = 2 },       -- Second row start
		{ index = w * 2, expectedX = w, expectedY = 2 },       -- Second row end
		{ index = w * 6 + 3, expectedX = 3, expectedY = 7 },   -- Middle of board
	}
	
	for _, tc in ipairs(testCases) do
		local index = tc.index
		local y = math.floor((index - 1) / w) + 1
		local x = ((index - 1) % w) + 1
		
		assertEqual(x, tc.expectedX, string.format("Index %d: x should be %d", index, tc.expectedX))
		assertEqual(y, tc.expectedY, string.format("Index %d: y should be %d", index, tc.expectedY))
		
		-- Verify round-trip: coordinate -> index -> coordinate
		local roundTripIndex = (y - 1) * w + x
		assertEqual(roundTripIndex, index, "Round-trip conversion should match")
	end
end)

test("CaptureClearedTiles coordinates match FindMatches indices", function()
	local board = createTestBoard({
		{ x = 3, y = 4, color = 2 },
		{ x = 4, y = 4, color = 2 },
		{ x = 5, y = 4, color = 2 },
	})
	
	local matches = BoardLogic.FindMatches(board)
	local clearedTiles = BoardLogic.CaptureClearedTiles(board, matches)
	
	-- Verify we have 3 cleared tiles
	assertTableLength(clearedTiles, 3, "Should capture 3 tiles")
	
	-- Verify each tile's coordinates match where we placed them
	local foundPositions = {}
	for _, tile in ipairs(clearedTiles) do
		foundPositions[tile.x .. "," .. tile.y] = true
		assertEqual(tile.y, 4, "All cleared tiles should be at y=4")
		assertTrue(tile.x >= 3 and tile.x <= 5, "x should be between 3 and 5")
		assertEqual(tile.colorId, 2, "colorId should be 2")
	end
	
	-- Verify we found all 3 specific positions
	assertTrue(foundPositions["3,4"], "Should have tile at (3,4)")
	assertTrue(foundPositions["4,4"], "Should have tile at (4,4)")
	assertTrue(foundPositions["5,4"], "Should have tile at (5,4)")
end)

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                              RUN TESTS                                      ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

TestService:Message("========================================")
TestService:Message("PuzzleLeague Tests Complete")
TestService:Message(string.format("Passed: %d, Failed: %d", testsPassed, testsFailed))
TestService:Message("========================================")

if testsFailed > 0 then
	TestService:Error(string.format("%d test(s) failed!", testsFailed))
else
	TestService:Message("All tests passed!")
end

TestService:Done()

