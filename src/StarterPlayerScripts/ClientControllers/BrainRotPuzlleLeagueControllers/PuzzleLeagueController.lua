--[[
	PuzzleLeagueController
	
	Client controller for Panel de Pon / Puzzle League gameplay.
	Handles UI (Fusion), input, and board rendering.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local Knit = require(Packages.Knit)
local Input = require(Packages.Input)

local CustomPackages = ReplicatedStorage:WaitForChild("CustomPackages")
local ReplicaController = require(CustomPackages.Replica.ReplicaController)
local Fusion = require(CustomPackages.FusionRoot.Fusion)

local SharedModules = ReplicatedStorage:WaitForChild("Source"):WaitForChild("SharedModules")
local Config = require(SharedModules.PuzzleLeagueConfig)

-- Fusion imports
local New = Fusion.New
local Children = Fusion.Children
local Value = Fusion.Value
local Computed = Fusion.Computed
local OnEvent = Fusion.OnEvent
local Spring = Fusion.Spring

local PuzzleLeagueController = Knit.CreateController({
	Name = "PuzzleLeagueController",
})

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                              STATE                                          ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

local player = Players.LocalPlayer
local PuzzleLeagueService

-- Fusion state values
local phase = Value(Config.PHASE.MENU)
local matchId = Value(0)
local myBoard = Value(nil)
local oppBoard = Value(nil)
local opponentUserId = Value(0)
local winnerUserId = Value(0)
local countdownEndsAt = Value(0)
local countdownSeconds = Value(Config.COUNTDOWN_SECONDS)
local matchStartedAt = Value(0)
local backgroundAssetId = Value("") -- Background image for the match

-- Cursor state (local player)
local cursorX = Value(1)
local cursorY = Value(1)

-- Opponent cursor state (replicated)
local oppCursorX = Value(1)
local oppCursorY = Value(1)

-- Current time for countdown/timer display
local currentTime = Value(workspace:GetServerTimeNow())

-- Clear batch tracking (server-driven)
local lastClearBatchId = 0

-- Clearing cells: tracks cells that are playing clear effects
-- Format: { ["board_x_y"] = { colorId = number, flashFrame = Frame } }
local clearingCells = {}

-- Fusion Value to trigger cell re-evaluation when clearing state changes
local clearingVersion = Value(0)

-- Clear effect animation settings
local CLEAR_WHITE_DURATION = 0.5 -- All matched tiles stay white for this duration
local CLEAR_FLASH_DURATION = 0.15 -- Flash in/out animation after white phase
local MAX_EFFECTS_PER_BATCH = 60 -- Cap effects to prevent performance issues

-- Keyboard input
local keyboard

-- Replica reference
local playerReplica

-- UI references
local screenGui
local myBoardContainer = nil  -- Direct reference to MyBoard's BoardContainer
local oppBoardContainer = nil -- Direct reference to OppBoard's BoardContainer
local myCellRefs = {}  -- { ["x_y"] = Frame } for my board cells
local oppCellRefs = {} -- { ["x_y"] = Frame } for opponent board cells

-- Animation tracking
local TweenService = game:GetService("TweenService")
local TILE_MOVE_DURATION = 0.15 -- Duration for tile movement animations
local GRAVITY_FALL_DURATION = 0.12 -- Duration per cell for gravity fall


-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                              UI CONSTANTS                                   ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

local CELL_SIZE = 55  -- Size of each tile (larger = bigger board)
local BOARD_GAP = 30  -- Gap between the two boards
local BOARD_PADDING = 15  -- Padding inside board panels

local COLORS = {
	BACKGROUND = Color3.fromRGB(18, 18, 24),
	PANEL = Color3.fromRGB(28, 28, 38),
	PANEL_BORDER = Color3.fromRGB(58, 58, 78),
	TEXT = Color3.fromRGB(240, 240, 250),
	TEXT_DIM = Color3.fromRGB(150, 150, 170),
	ACCENT = Color3.fromRGB(120, 200, 255),
	BUTTON = Color3.fromRGB(60, 140, 200),
	BUTTON_HOVER = Color3.fromRGB(80, 160, 220),
	CURSOR = Color3.fromRGB(255, 255, 100),
	OPP_CURSOR = Color3.fromRGB(255, 150, 100), -- Orange for opponent cursor
	EMPTY_CELL = Color3.fromRGB(40, 40, 50),
	WIN = Color3.fromRGB(100, 255, 150),
	LOSE = Color3.fromRGB(255, 100, 100),
	TIMER = Color3.fromRGB(255, 255, 255),
}

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         CLEAR EFFECT SYSTEM                                 ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

--[[
	Gets the key for a clearing cell.
	@param boardId "my" or "opp"
	@param x Column position
	@param y Row position
	@return String key
]]
local function getClearingKey(boardId, x, y)
	return boardId .. "_" .. x .. "_" .. y
end

--[[
	Checks if a cell is currently clearing.
	@param boardId "my" or "opp"
	@param x Column position
	@param y Row position
	@return colorId if clearing, nil otherwise
]]
local function getClearingColor(boardId, x, y)
	local key = getClearingKey(boardId, x, y)
	local data = clearingCells[key]
	return data and data.colorId or nil
end

--[[
	Processes a clear batch:
	1. ALL tiles turn white simultaneously
	2. Stay white for CLEAR_WHITE_DURATION
	3. Flash animation plays (fade out)
	4. Tiles disappear
	@param clearedTiles Array of { x, y, colorId }
	@param boardId "my" or "opp"
]]
local function processClearBatch(clearedTiles, boardId)
	local effectCount = math.min(#clearedTiles, MAX_EFFECTS_PER_BATCH)
	
	if effectCount == 0 then return end
	
	local cellRefs = boardId == "my" and myCellRefs or oppCellRefs
	local flashOverlays = {}
	
	-- Step 1: Mark ALL cells as clearing and create white overlays simultaneously
	for i = 1, effectCount do
		local tile = clearedTiles[i]
		local key = getClearingKey(boardId, tile.x, tile.y)
		clearingCells[key] = { colorId = tile.colorId }
		
		-- Get cell reference
		local cellKey = tile.x .. "_" .. tile.y
		local cell = cellRefs[cellKey]
		
		if cell then
			-- Create white overlay on the cell (starts fully visible)
			local flashOverlay = Instance.new("Frame")
			flashOverlay.Name = "ClearFlash"
			flashOverlay.Size = UDim2.new(1, 0, 1, 0)
			flashOverlay.BackgroundColor3 = Color3.new(1, 1, 1)
			flashOverlay.BackgroundTransparency = 0 -- Fully white immediately
			flashOverlay.BorderSizePixel = 0
			flashOverlay.ZIndex = 10
			flashOverlay.Parent = cell
			
			local flashCorner = Instance.new("UICorner")
			flashCorner.CornerRadius = UDim.new(0, 4)
			flashCorner.Parent = flashOverlay
			
			table.insert(flashOverlays, { overlay = flashOverlay, key = key })
		end
	end
	
	clearingVersion:set(clearingVersion:get() + 1) -- Trigger cell updates
	
	-- Step 2: Wait white duration, then flash, then clean up
	task.spawn(function()
		local TweenService = game:GetService("TweenService")
		
		-- Phase 1: Stay white for the duration
		task.wait(CLEAR_WHITE_DURATION)
		
		-- Phase 2: Flash animation - all fade out together
		local tweens = {}
		for _, data in ipairs(flashOverlays) do
			if data.overlay and data.overlay.Parent then
				local fadeTween = TweenService:Create(
					data.overlay,
					TweenInfo.new(CLEAR_FLASH_DURATION, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
					{ BackgroundTransparency = 1 }
				)
				fadeTween:Play()
				table.insert(tweens, fadeTween)
			end
		end
		
		-- Wait for flash animation to complete
		task.wait(CLEAR_FLASH_DURATION)
		
		-- Phase 3: Clean up all overlays and remove from clearing cells
		for _, data in ipairs(flashOverlays) do
			if data.overlay and data.overlay.Parent then
				data.overlay:Destroy()
			end
			if clearingCells[data.key] then
				clearingCells[data.key] = nil
			end
		end
		
		clearingVersion:set(clearingVersion:get() + 1) -- Trigger cell updates (now show empty)
	end)
end

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         TILE MOVEMENT ANIMATION                             ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

-- Animation overlay containers (created when boards are made)
local myAnimationLayer = nil
local oppAnimationLayer = nil

-- Cells currently being animated (to hide their color during animation)
-- Format: { ["boardId_x_y"] = true }
local animatingCells = {}

-- Fusion Value to trigger cell re-evaluation when animation state changes
local animatingVersion = Value(0)

--[[
	Checks if a cell is currently being animated (should show transparent).
	@param boardId "my" or "opp"
	@param x Column position
	@param y Row position
	@return true if animating, false otherwise
]]
local function isCellAnimating(boardId, x, y)
	local key = boardId .. "_" .. x .. "_" .. y
	return animatingCells[key] == true
end

--[[
	Creates a temporary animated tile that flies from source to destination.
	@param container The animation layer container
	@param fromX Source X position (column)
	@param fromY Source Y position (row)
	@param toX Target X position (column)
	@param toY Target Y position (row)
	@param colorId The tile color ID
	@param duration Animation duration
	@param boardId "my" or "opp" for tracking
]]
local function createFlyingTile(container, fromX, fromY, toX, toY, colorId, duration, boardId)
	if not container then return end
	
	local tileColor = Config.TILE_COLORS[colorId] or COLORS.EMPTY_CELL
	
	-- Calculate pixel positions
	local fromPosX = (fromX - 1) * CELL_SIZE + 1
	local fromPosY = (Config.BOARD_HEIGHT - fromY) * CELL_SIZE + 1
	local toPosX = (toX - 1) * CELL_SIZE + 1
	local toPosY = (Config.BOARD_HEIGHT - toY) * CELL_SIZE + 1
	
	-- Mark destination cell as animating (to hide its color)
	local destKey = boardId .. "_" .. toX .. "_" .. toY
	animatingCells[destKey] = true
	animatingVersion:set(animatingVersion:get() + 1)
	
	-- Create temporary tile frame
	local flyingTile = Instance.new("Frame")
	flyingTile.Name = "FlyingTile"
	flyingTile.Size = UDim2.new(0, CELL_SIZE - 2, 0, CELL_SIZE - 2)
	flyingTile.Position = UDim2.new(0, fromPosX, 0, fromPosY)
	flyingTile.BackgroundColor3 = tileColor
	flyingTile.BorderSizePixel = 0
	flyingTile.ZIndex = 5
	flyingTile.Parent = container
	
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 4)
	corner.Parent = flyingTile
	
	-- Animate to destination
	local tween = TweenService:Create(
		flyingTile,
		TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Position = UDim2.new(0, toPosX, 0, toPosY) }
	)
	
	tween:Play()
	
	-- Destroy when done and show destination cell
	tween.Completed:Connect(function()
		flyingTile:Destroy()
		animatingCells[destKey] = nil
		animatingVersion:set(animatingVersion:get() + 1)
	end)
end

--[[
	Creates a flying group of tiles that fall together as a vertical stack.
	@param container The animation layer container
	@param x Column position
	@param tiles Array of { fromY, toY, colorId } sorted by Y (bottom to top)
	@param fallDistance How many cells the group falls
	@param boardId "my" or "opp" for tracking
]]
local function createFallingGroup(container, x, tiles, fallDistance, boardId)
	if not container or #tiles == 0 then return end
	
	-- Calculate the bounding box for the group
	local minToY = tiles[1].toY
	local maxToY = tiles[#tiles].toY
	local groupHeight = (maxToY - minToY + 1) * CELL_SIZE
	
	-- Starting position (where tiles were)
	local fromPosX = (x - 1) * CELL_SIZE + 1
	local fromPosY = (Config.BOARD_HEIGHT - maxToY - fallDistance) * CELL_SIZE + 1
	
	-- Target position (where tiles go)
	local toPosY = (Config.BOARD_HEIGHT - maxToY) * CELL_SIZE + 1
	
	-- Mark all destination cells as animating
	for _, tile in ipairs(tiles) do
		local destKey = boardId .. "_" .. x .. "_" .. tile.toY
		animatingCells[destKey] = true
	end
	animatingVersion:set(animatingVersion:get() + 1)
	
	-- Create the group container
	local groupFrame = Instance.new("Frame")
	groupFrame.Name = "FallingGroup"
	groupFrame.Size = UDim2.new(0, CELL_SIZE - 2, 0, groupHeight - 2)
	groupFrame.Position = UDim2.new(0, fromPosX, 0, fromPosY)
	groupFrame.BackgroundTransparency = 1
	groupFrame.ZIndex = 5
	groupFrame.Parent = container
	
	-- Create individual tile visuals within the group
	for _, tile in ipairs(tiles) do
		local tileColor = Config.TILE_COLORS[tile.colorId] or COLORS.EMPTY_CELL
		local localY = (maxToY - tile.toY) * CELL_SIZE
		
		local tileFrame = Instance.new("Frame")
		tileFrame.Name = "Tile"
		tileFrame.Size = UDim2.new(0, CELL_SIZE - 2, 0, CELL_SIZE - 2)
		tileFrame.Position = UDim2.new(0, 0, 0, localY)
		tileFrame.BackgroundColor3 = tileColor
		tileFrame.BorderSizePixel = 0
		tileFrame.Parent = groupFrame
		
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 4)
		corner.Parent = tileFrame
	end
	
	-- Calculate duration based on fall distance
	local duration = math.min(fallDistance * GRAVITY_FALL_DURATION, 0.5)
	
	-- Animate the entire group
	local tween = TweenService:Create(
		groupFrame,
		TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
		{ Position = UDim2.new(0, fromPosX, 0, toPosY) }
	)
	
	tween:Play()
	
	-- Clean up when done
	tween.Completed:Connect(function()
		groupFrame:Destroy()
		for _, tile in ipairs(tiles) do
			local destKey = boardId .. "_" .. x .. "_" .. tile.toY
			animatingCells[destKey] = nil
		end
		animatingVersion:set(animatingVersion:get() + 1)
	end)
end

--[[
	Detects tile movements between old and new board states and animates them.
	Only animates:
	  - Horizontal swaps (same row)
	  - Gravity falls (vertical groups that fell together)
	Does NOT animate:
	  - Rising tiles (tiles that moved UP due to board push)
	  - New tiles appearing at bottom row from rising
	@param oldBoard Previous board data { w, h, cells, rise }
	@param newBoard New board data { w, h, cells, rise }
	@param animationLayer The animation overlay container
	@param isMyBoard Whether this is the player's board
]]
local function animateBoardChanges(oldBoard, newBoard, animationLayer, isMyBoard)
	if not newBoard or not newBoard.cells then return end
	if not oldBoard or not oldBoard.cells then return end -- First update, no animation
	if not animationLayer then return end
	
	local w = newBoard.w
	local h = newBoard.h
	local newCells = newBoard.cells
	local oldCells = oldBoard.cells
	local boardId = isMyBoard and "my" or "opp"
	
	-- Detect if this is a rising board update (rise value changed)
	local oldRise = oldBoard.rise or 0
	local newRise = newBoard.rise or 0
	local isRisingUpdate = (newRise < oldRise) or (newRise == 0 and oldRise > 0.9) -- Rise resets to 0 after push
	
	-- If board just rose, don't animate - tiles didn't fall, they were pushed up
	if isRisingUpdate then
		return
	end
	
	-- Track which tiles we've already handled
	local handled = {}
	
	-- First pass: detect horizontal swaps (individual tiles)
	for y = 1, h do
		for x = 1, w do
			local index = (y - 1) * w + x
			local newTile = newCells[index]
			local oldTile = oldCells[index]
			
			if not newTile or newTile == Config.EMPTY_TILE then continue end
			if newTile == oldTile then continue end
			
			-- Check horizontal swap (left/right neighbor had this tile)
			local sourceX = nil
			if x > 1 then
				local leftIndex = (y - 1) * w + (x - 1)
				if oldCells[leftIndex] == newTile and newCells[leftIndex] ~= newTile then
					sourceX = x - 1
				end
			end
			if not sourceX and x < w then
				local rightIndex = (y - 1) * w + (x + 1)
				if oldCells[rightIndex] == newTile and newCells[rightIndex] ~= newTile then
					sourceX = x + 1
				end
			end
			
			if sourceX then
				handled[index] = true
				createFlyingTile(animationLayer, sourceX, y, x, y, newTile, TILE_MOVE_DURATION, boardId)
			end
		end
	end
	
	-- Second pass: detect vertical falling groups per column
	for x = 1, w do
		-- Build a list of tiles that fell in this column
		local fallingTiles = {} -- { { fromY, toY, colorId }, ... }
		
		for y = 1, h do
			local index = (y - 1) * w + x
			if handled[index] then continue end
			
			local newTile = newCells[index]
			if not newTile or newTile == Config.EMPTY_TILE then continue end
			if newTile == oldCells[index] then continue end
			
			-- Find where this tile came from (above in same column)
			for checkY = y + 1, h do
				local checkIndex = (checkY - 1) * w + x
				if oldCells[checkIndex] == newTile then
					if newCells[checkIndex] ~= newTile then
						table.insert(fallingTiles, {
							fromY = checkY,
							toY = y,
							colorId = newTile,
							fallDistance = checkY - y
						})
						handled[index] = true
						break
					end
				end
			end
		end
		
		-- Group tiles by fall distance (tiles that fell the same amount should animate together)
		if #fallingTiles > 0 then
			-- Sort by toY to process from bottom up
			table.sort(fallingTiles, function(a, b) return a.toY < b.toY end)
			
			-- Group contiguous tiles with same fall distance
			local groups = {}
			local currentGroup = { fallingTiles[1] }
			local currentFallDist = fallingTiles[1].fallDistance
			
			for i = 2, #fallingTiles do
				local tile = fallingTiles[i]
				local prevTile = fallingTiles[i - 1]
				
				-- Check if this tile is contiguous with previous and has same fall distance
				if tile.toY == prevTile.toY + 1 and tile.fallDistance == currentFallDist then
					table.insert(currentGroup, tile)
				else
					-- Start a new group
					table.insert(groups, { tiles = currentGroup, fallDistance = currentFallDist })
					currentGroup = { tile }
					currentFallDist = tile.fallDistance
				end
			end
			-- Don't forget the last group
			table.insert(groups, { tiles = currentGroup, fallDistance = currentFallDist })
			
			-- Animate each group
			for _, group in ipairs(groups) do
				createFallingGroup(animationLayer, x, group.tiles, group.fallDistance, boardId)
			end
		end
	end
end


-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                              UI COMPONENTS                                  ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

--[[
	Creates a styled button component.
]]
local function createButton(props)
	local isHovered = Value(false)
	
	return New "TextButton" {
		Size = props.Size or UDim2.new(0, 200, 0, 50),
		Position = props.Position or UDim2.new(0.5, 0, 0.5, 0),
		AnchorPoint = props.AnchorPoint or Vector2.new(0.5, 0.5),
		BackgroundColor3 = Computed(function()
			return isHovered:get() and COLORS.BUTTON_HOVER or COLORS.BUTTON
		end),
		Text = props.Text or "Button",
		TextColor3 = COLORS.TEXT,
		TextSize = 20,
		Font = Enum.Font.GothamBold,
		
		[OnEvent "MouseEnter"] = function()
			isHovered:set(true)
		end,
		[OnEvent "MouseLeave"] = function()
			isHovered:set(false)
		end,
		[OnEvent "Activated"] = props.OnClick or function() end,
		
		[Children] = {
			New "UICorner" { CornerRadius = UDim.new(0, 8) },
			New "UIStroke" {
				Color = COLORS.ACCENT,
				Thickness = 2,
			},
		},
	}
end

--[[
	Creates a single cell frame for the board.
	@param x Column position
	@param y Row position  
	@param boardState Fusion Value containing board snapshot
	@param isMyBoard Whether this is the player's own board
	@param showOppCursor Whether to show opponent cursor (for opponent board view)
]]
local function createCell(x, y, boardState, isMyBoard, showOppCursor)
	local boardId = isMyBoard and "my" or "opp"
	
	return New "Frame" {
		Name = "Cell_" .. x .. "_" .. y,
		Size = UDim2.new(0, CELL_SIZE - 2, 0, CELL_SIZE - 2),
		Position = UDim2.new(0, (x - 1) * CELL_SIZE + 1, 0, (Config.BOARD_HEIGHT - y) * CELL_SIZE + 1),
		BackgroundColor3 = Computed(function()
			-- Read versions to trigger reactivity
			local _ = clearingVersion:get()
			local __ = animatingVersion:get()
			
			-- First check if this cell is being animated (flying tile in progress)
			if isCellAnimating(boardId, x, y) then
				return COLORS.EMPTY_CELL -- Hide during animation
			end
			
			-- Check if this cell is clearing (has pending clear effect)
			local clearingColorId = getClearingColor(boardId, x, y)
			if clearingColorId then
				return Config.TILE_COLORS[clearingColorId] or COLORS.EMPTY_CELL
			end
			
			-- Otherwise read from board state
			local board = boardState:get()
			if not board or not board.cells then
				return COLORS.EMPTY_CELL
			end
			
			local index = (y - 1) * board.w + x
			local tileId = board.cells[index]
			
			if tileId and tileId > 0 then
				return Config.TILE_COLORS[tileId] or COLORS.EMPTY_CELL
			end
			return COLORS.EMPTY_CELL
		end),
		BorderSizePixel = 0,
		
		[Children] = {
			New "UICorner" { CornerRadius = UDim.new(0, 4) },
		},
	}
end

--[[
	Creates a cursor overlay that spans 2 cells horizontally.
	@param cursorXValue Fusion Value for cursor X position
	@param cursorYValue Fusion Value for cursor Y position
	@param color Color3 for the cursor stroke
	@param boardState Fusion Value for board state (to get rise offset)
]]
local function createCursorOverlay(cursorXValue, cursorYValue, color, boardState)
	return New "Frame" {
		Name = "CursorOverlay",
		Size = UDim2.new(0, CELL_SIZE * 2 + 4, 0, CELL_SIZE + 4), -- Spans 2 cells + padding
		Position = Computed(function()
			local cx = cursorXValue:get()
			local cy = cursorYValue:get()
			local board = boardState:get()
			local riseOffset = board and board.rise or 0
			
			-- Calculate position: cursor spans cells at (cx, cy) and (cx+1, cy)
			local posX = BOARD_PADDING + (cx - 1) * CELL_SIZE - 2
			local posY = 30 + BOARD_PADDING + (Config.BOARD_HEIGHT - cy) * CELL_SIZE - riseOffset * CELL_SIZE - 2
			
			return UDim2.new(0, posX, 0, posY)
		end),
		BackgroundTransparency = 1,
		ZIndex = 20, -- On top of everything
		
		[Children] = {
			New "UICorner" { CornerRadius = UDim.new(0, 8) },
			New "UIStroke" {
				Color = color,
				Thickness = 4,
			},
		},
	}
end

--[[
	Creates a board grid component.
	@param boardState Fusion Value containing board snapshot
	@param isMyBoard Whether this is the player's own board
	@param title Title to display above board
	@param showOppCursor Whether to show opponent cursor on this board
]]
local function createBoard(boardState, isMyBoard, title, showOppCursor)
	local cells = {}
	
	for y = 1, Config.BOARD_HEIGHT do
		for x = 1, Config.BOARD_WIDTH do
			table.insert(cells, createCell(x, y, boardState, isMyBoard, showOppCursor))
		end
	end
	
	-- Create the board container first so we can store a reference to it
	local boardContainerFrame = New "Frame" {
		Name = "BoardContainer",
		Size = UDim2.new(0, Config.BOARD_WIDTH * CELL_SIZE, 0, Config.BOARD_HEIGHT * CELL_SIZE),
		Position = Computed(function()
			local board = boardState:get()
			local riseOffset = board and board.rise or 0
			return UDim2.new(0, BOARD_PADDING, 0, 30 + BOARD_PADDING - riseOffset * CELL_SIZE)
		end),
		BackgroundTransparency = 1,
		ClipsDescendants = true,
		
		[Children] = cells,
	}
	
	-- Create animation layer (for flying tiles during gravity/swaps)
	local animationLayerFrame = New "Frame" {
		Name = "AnimationLayer",
		Size = UDim2.new(0, Config.BOARD_WIDTH * CELL_SIZE, 0, Config.BOARD_HEIGHT * CELL_SIZE),
		Position = Computed(function()
			local board = boardState:get()
			local riseOffset = board and board.rise or 0
			return UDim2.new(0, BOARD_PADDING, 0, 30 + BOARD_PADDING - riseOffset * CELL_SIZE)
		end),
		BackgroundTransparency = 1,
		ClipsDescendants = true,
		ZIndex = 3, -- Above cells but below clear effects
	}
	
	-- Store reference for clear effects and build cell reference dictionary
	if isMyBoard then
		myBoardContainer = boardContainerFrame
		myAnimationLayer = animationLayerFrame
		myCellRefs = {}
		for y = 1, Config.BOARD_HEIGHT do
			for x = 1, Config.BOARD_WIDTH do
				local key = x .. "_" .. y
				myCellRefs[key] = cells[(y - 1) * Config.BOARD_WIDTH + x]
			end
		end
		print("[Client] Stored myBoardContainer reference with", Config.BOARD_WIDTH * Config.BOARD_HEIGHT, "cells")
	else
		oppBoardContainer = boardContainerFrame
		oppAnimationLayer = animationLayerFrame
		oppCellRefs = {}
		for y = 1, Config.BOARD_HEIGHT do
			for x = 1, Config.BOARD_WIDTH do
				local key = x .. "_" .. y
				oppCellRefs[key] = cells[(y - 1) * Config.BOARD_WIDTH + x]
			end
		end
		print("[Client] Stored oppBoardContainer reference with", Config.BOARD_WIDTH * Config.BOARD_HEIGHT, "cells")
	end
	
	return New "Frame" {
		Name = isMyBoard and "MyBoard" or "OppBoard",
		Size = UDim2.new(0, Config.BOARD_WIDTH * CELL_SIZE + BOARD_PADDING * 2, 0, Config.BOARD_HEIGHT * CELL_SIZE + BOARD_PADDING * 2 + 30),
		BackgroundColor3 = COLORS.PANEL,
		BorderSizePixel = 0,
		
		[Children] = {
			New "UICorner" { CornerRadius = UDim.new(0, 12) },
			New "UIStroke" {
				Color = COLORS.PANEL_BORDER,
				Thickness = 2,
			},
			
			-- Title label
			New "TextLabel" {
				Name = "Title",
				Size = UDim2.new(1, 0, 0, 30),
				Position = UDim2.new(0, 0, 0, 0),
				BackgroundTransparency = 1,
				Text = title,
				TextColor3 = COLORS.TEXT,
				TextSize = 16,
				Font = Enum.Font.GothamBold,
			},
			
			-- Board container with cells
			boardContainerFrame,
			
			-- Animation layer for flying tiles
			animationLayerFrame,
			
			-- Clip frame to hide rising content
			New "Frame" {
				Name = "ClipMask",
				Size = UDim2.new(1, 0, 0, 30),
				Position = UDim2.new(0, 0, 0, 0),
				BackgroundColor3 = COLORS.PANEL,
				BorderSizePixel = 0,
				ZIndex = 2,
				
				[Children] = {
					New "UICorner" { CornerRadius = UDim.new(0, 12) },
					New "TextLabel" {
						Size = UDim2.new(1, 0, 1, 0),
						BackgroundTransparency = 1,
						Text = title,
						TextColor3 = COLORS.TEXT,
						TextSize = 16,
						Font = Enum.Font.GothamBold,
					},
				},
			},
			
			-- Cursor overlay (player's cursor on own board, opponent's cursor on their board)
			isMyBoard and createCursorOverlay(cursorX, cursorY, Color3.new(1, 1, 1), boardState) or nil,
			showOppCursor and createCursorOverlay(oppCursorX, oppCursorY, Color3.fromRGB(255, 200, 150), boardState) or nil,
		},
	}
end

--[[
	Creates the Menu screen.
]]
local function createMenuScreen()
	return New "Frame" {
		Name = "MenuScreen",
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundColor3 = COLORS.BACKGROUND,
		Visible = Computed(function()
			return phase:get() == Config.PHASE.MENU
		end),
		
		[Children] = {
			-- Title
			New "TextLabel" {
				Size = UDim2.new(1, 0, 0, 80),
				Position = UDim2.new(0, 0, 0.3, 0),
				AnchorPoint = Vector2.new(0, 0.5),
				BackgroundTransparency = 1,
				Text = "PUZZLE LEAGUE",
				TextColor3 = COLORS.ACCENT,
				TextSize = 48,
				Font = Enum.Font.GothamBlack,
			},
			
			-- Subtitle
			New "TextLabel" {
				Size = UDim2.new(1, 0, 0, 30),
				Position = UDim2.new(0, 0, 0.38, 0),
				AnchorPoint = Vector2.new(0, 0.5),
				BackgroundTransparency = 1,
				Text = "Brain Rot Edition",
				TextColor3 = COLORS.TEXT_DIM,
				TextSize = 18,
				Font = Enum.Font.Gotham,
			},
			
			-- Play button
			createButton {
				Text = "PLAY",
				Position = UDim2.new(0.5, 0, 0.55, 0),
				Size = UDim2.new(0, 220, 0, 60),
				OnClick = function()
					if PuzzleLeagueService then
						PuzzleLeagueService:JoinQueue()
					end
				end,
			},
			
			-- Controls hint
			New "TextLabel" {
				Size = UDim2.new(1, 0, 0, 60),
				Position = UDim2.new(0, 0, 0.75, 0),
				AnchorPoint = Vector2.new(0, 0.5),
				BackgroundTransparency = 1,
				Text = "Controls: WASD to move cursor, SPACE to swap tiles",
				TextColor3 = COLORS.TEXT_DIM,
				TextSize = 14,
				Font = Enum.Font.Gotham,
			},
		},
	}
end

--[[
	Creates the Queue screen.
]]
local function createQueueScreen()
	return New "Frame" {
		Name = "QueueScreen",
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundColor3 = COLORS.BACKGROUND,
		Visible = Computed(function()
			return phase:get() == Config.PHASE.QUEUE
		end),
		
		[Children] = {
			-- Finding opponent text
			New "TextLabel" {
				Size = UDim2.new(1, 0, 0, 50),
				Position = UDim2.new(0.5, 0, 0.45, 0),
				AnchorPoint = Vector2.new(0.5, 0.5),
				BackgroundTransparency = 1,
				Text = "Finding opponent...",
				TextColor3 = COLORS.TEXT,
				TextSize = 32,
				Font = Enum.Font.GothamBold,
			},
			
			-- Loading dots animation (simple text)
			New "TextLabel" {
				Size = UDim2.new(1, 0, 0, 30),
				Position = UDim2.new(0.5, 0, 0.52, 0),
				AnchorPoint = Vector2.new(0.5, 0.5),
				BackgroundTransparency = 1,
				Text = "Please wait",
				TextColor3 = COLORS.TEXT_DIM,
				TextSize = 18,
				Font = Enum.Font.Gotham,
			},
		},
	}
end

--[[
	Formats elapsed time as MM:SS
]]
local function formatTime(seconds)
	local mins = math.floor(seconds / 60)
	local secs = math.floor(seconds % 60)
	return string.format("%02d:%02d", mins, secs)
end

--[[
	Creates the Game screen (Countdown + InMatch).
]]
local function createGameScreen()
	local boardWidth = Config.BOARD_WIDTH * CELL_SIZE + BOARD_PADDING * 2
	local timerWidth = 100
	local totalWidth = boardWidth * 2 + timerWidth
	
	return New "Frame" {
		Name = "GameScreen",
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundColor3 = COLORS.BACKGROUND,
		Visible = Computed(function()
			local p = phase:get()
			return p == Config.PHASE.COUNTDOWN or p == Config.PHASE.IN_MATCH
		end),
		
		[Children] = {
			-- Background image (server-selected, same for both players)
			New "ImageLabel" {
				Name = "Background",
				Size = UDim2.new(1, 0, 1, 0),
				Position = UDim2.new(0, 0, 0, 0),
				BackgroundTransparency = 1,
				Image = Computed(function()
					return backgroundAssetId:get()
				end),
				ImageTransparency = 0.3, -- Slightly transparent so it doesn't overpower
				ScaleType = Enum.ScaleType.Crop,
				ZIndex = 0,
			},
			
			-- VS Header
			New "TextLabel" {
				Size = UDim2.new(1, 0, 0, 40),
				Position = UDim2.new(0.5, 0, 0, 20),
				AnchorPoint = Vector2.new(0.5, 0),
				BackgroundTransparency = 1,
				Text = Computed(function()
					local oppId = opponentUserId:get()
					if oppId > 0 then
						local oppPlayer = Players:GetPlayerByUserId(oppId)
						local oppName = oppPlayer and oppPlayer.Name or ("Player " .. oppId)
						return "VS " .. oppName
					end
					return "VS ???"
				end),
				TextColor3 = COLORS.ACCENT,
				TextSize = 28,
				Font = Enum.Font.GothamBold,
			},
			
			-- Boards container
			New "Frame" {
				Name = "BoardsContainer",
				Size = UDim2.new(0, totalWidth, 0, Config.BOARD_HEIGHT * CELL_SIZE + BOARD_PADDING * 2 + 30),
				Position = UDim2.new(0.5, 0, 0.5, 20),
				AnchorPoint = Vector2.new(0.5, 0.5),
				BackgroundTransparency = 1,
				
				[Children] = {
					-- My board (left) - shows my cursor
					New "Frame" {
						Size = UDim2.new(0, boardWidth, 1, 0),
						Position = UDim2.new(0, 0, 0, 0),
						BackgroundTransparency = 1,
						
						[Children] = {
							createBoard(myBoard, true, "YOU", false),
						},
					},
					
					-- Timer display (center, between boards)
					New "Frame" {
						Name = "TimerContainer",
						Size = UDim2.new(0, timerWidth, 1, 0),
						Position = UDim2.new(0, boardWidth, 0, 0),
						BackgroundTransparency = 1,
						
						[Children] = {
							-- Timer label
							New "TextLabel" {
								Name = "TimerLabel",
								Size = UDim2.new(1, 0, 0, 30),
								Position = UDim2.new(0.5, 0, 0.5, -50),
								AnchorPoint = Vector2.new(0.5, 0.5),
								BackgroundTransparency = 1,
								Text = "TIME",
								TextColor3 = COLORS.TEXT_DIM,
								TextSize = 14,
								Font = Enum.Font.GothamBold,
							},
							
							-- Timer value
							New "TextLabel" {
								Name = "TimerValue",
								Size = UDim2.new(1, 0, 0, 50),
								Position = UDim2.new(0.5, 0, 0.5, -20),
								AnchorPoint = Vector2.new(0.5, 0.5),
								BackgroundTransparency = 1,
								Text = Computed(function()
									local startedAt = matchStartedAt:get()
									local now = currentTime:get()
									
									if startedAt <= 0 then
										return "00:00"
									end
									
									local elapsed = math.max(0, now - startedAt)
									return formatTime(elapsed)
								end),
								TextColor3 = COLORS.TIMER,
								TextSize = 32,
								Font = Enum.Font.GothamBlack,
							},
							
							-- VS divider
							New "Frame" {
								Name = "Divider",
								Size = UDim2.new(0, 2, 0, 100),
								Position = UDim2.new(0.5, 0, 0.5, 40),
								AnchorPoint = Vector2.new(0.5, 0.5),
								BackgroundColor3 = COLORS.PANEL_BORDER,
								BorderSizePixel = 0,
							},
						},
					},
					
					-- Opponent board (right) - shows opponent cursor
					New "Frame" {
						Size = UDim2.new(0, boardWidth, 1, 0),
						Position = UDim2.new(0, boardWidth + timerWidth, 0, 0),
						BackgroundTransparency = 1,
						
						[Children] = {
							createBoard(oppBoard, false, "OPPONENT", true),
						},
					},
				},
			},
			
			-- Countdown overlay
			New "Frame" {
				Name = "CountdownOverlay",
				Size = UDim2.new(1, 0, 1, 0),
				BackgroundColor3 = Color3.new(0, 0, 0),
				BackgroundTransparency = 0.5,
				Visible = Computed(function()
					return phase:get() == Config.PHASE.COUNTDOWN
				end),
				ZIndex = 10,
				
				[Children] = {
					New "TextLabel" {
						Size = UDim2.new(1, 0, 0, 150),
						Position = UDim2.new(0.5, 0, 0.5, 0),
						AnchorPoint = Vector2.new(0.5, 0.5),
						BackgroundTransparency = 1,
						Text = Computed(function()
							local endsAt = countdownEndsAt:get()
							local now = currentTime:get()
							local remaining = math.ceil(endsAt - now)
							
							if remaining <= 0 then
								return "GO!"
							end
							return tostring(remaining)
						end),
						TextColor3 = COLORS.ACCENT,
						TextSize = 120,
						Font = Enum.Font.GothamBlack,
						ZIndex = 11,
					},
				},
			},
		},
	}
end

--[[
	Creates the Result screen.
]]
local function createResultScreen()
	return New "Frame" {
		Name = "ResultScreen",
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundColor3 = COLORS.BACKGROUND,
		Visible = Computed(function()
			return phase:get() == Config.PHASE.RESULT
		end),
		
		[Children] = {
			-- Win/Lose text
			New "TextLabel" {
				Size = UDim2.new(1, 0, 0, 100),
				Position = UDim2.new(0.5, 0, 0.35, 0),
				AnchorPoint = Vector2.new(0.5, 0.5),
				BackgroundTransparency = 1,
				Text = Computed(function()
					local winner = winnerUserId:get()
					if winner == player.UserId then
						return "YOU WIN!"
					elseif winner > 0 then
						return "YOU LOSE"
					end
					return "DRAW"
				end),
				TextColor3 = Computed(function()
					local winner = winnerUserId:get()
					if winner == player.UserId then
						return COLORS.WIN
					elseif winner > 0 then
						return COLORS.LOSE
					end
					return COLORS.TEXT
				end),
				TextSize = 64,
				Font = Enum.Font.GothamBlack,
			},
			
			-- Play Again button
			createButton {
				Text = "PLAY AGAIN",
				Position = UDim2.new(0.5, 0, 0.55, 0),
				Size = UDim2.new(0, 220, 0, 60),
				OnClick = function()
					if PuzzleLeagueService then
						PuzzleLeagueService:JoinQueue()
					end
				end,
			},
		},
	}
end

--[[
	Creates the main UI.
]]
local function createUI()
	screenGui = New "ScreenGui" {
		Name = "PuzzleLeagueUI",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Parent = player:WaitForChild("PlayerGui"),
		
		[Children] = {
			createMenuScreen(),
			createQueueScreen(),
			createGameScreen(),
			createResultScreen(),
		},
	}
end

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                              INPUT HANDLING                                 ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

--[[
	Sends cursor position update to server.
]]
local function sendCursorUpdate()
	local currentMatchId = matchId:get()
	local cx = cursorX:get()
	local cy = cursorY:get()
	
	if PuzzleLeagueService and currentMatchId > 0 then
		PuzzleLeagueService:SendCursorUpdate(currentMatchId, cx, cy)
	end
end

--[[
	Handles keyboard input for cursor movement and swapping.
]]
local function setupInput()
	keyboard = Input.Keyboard.new()
	
	keyboard.KeyDown:Connect(function(keyCode)
		local currentPhase = phase:get()
		
		-- Cursor movement (always allowed during game)
		if currentPhase == Config.PHASE.COUNTDOWN or currentPhase == Config.PHASE.IN_MATCH then
			local cx = cursorX:get()
			local cy = cursorY:get()
			local moved = false
			
			if keyCode == Enum.KeyCode.W then
				cursorY:set(math.min(cy + 1, Config.BOARD_HEIGHT))
				moved = true
			elseif keyCode == Enum.KeyCode.S then
				cursorY:set(math.max(cy - 1, 1))
				moved = true
			elseif keyCode == Enum.KeyCode.A then
				cursorX:set(math.max(cx - 1, 1))
				moved = true
			elseif keyCode == Enum.KeyCode.D then
				cursorX:set(math.min(cx + 1, Config.BOARD_WIDTH - 1))
				moved = true
			end
			
			-- Send cursor update to server so opponent can see it
			if moved then
				sendCursorUpdate()
			end
		end
		
		-- Swap (only during InMatch)
		if currentPhase == Config.PHASE.IN_MATCH then
			if keyCode == Enum.KeyCode.Space then
				local currentMatchId = matchId:get()
				local cx = cursorX:get()
				local cy = cursorY:get()
				
				if PuzzleLeagueService and currentMatchId > 0 then
					PuzzleLeagueService:SendSwap(currentMatchId, cx, cy)
				end
			end
		end
	end)
end

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         REPLICA HANDLING                                    ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

--[[
	Sets up listening for replica updates.
]]
local function setupReplicaListener()
	ReplicaController.ReplicaOfClassCreated(Config.REPLICA_CLASS, function(replica)
		-- Check if this replica is for the local player
		if replica.Tags.Player ~= player then
			return
		end
		
		playerReplica = replica
		
		-- Initialize state from replica data
		local data = replica.Data
		phase:set(data.Phase)
		matchId:set(data.MatchId)
		myBoard:set(data.MyBoard)
		oppBoard:set(data.OppBoard)
		opponentUserId:set(data.OpponentUserId)
		winnerUserId:set(data.WinnerUserId)
		countdownEndsAt:set(data.CountdownEndsAt)
		countdownSeconds:set(data.CountdownSeconds)
		matchStartedAt:set(data.MatchStartedAt or 0)
		backgroundAssetId:set(data.BackgroundAssetId or "")
		
		-- Initialize cursor state
		if data.MyCursor then
			cursorX:set(data.MyCursor.x)
			cursorY:set(data.MyCursor.y)
		end
		if data.OppCursor then
			oppCursorX:set(data.OppCursor.x)
			oppCursorY:set(data.OppCursor.y)
		end
		
		-- Listen for changes
		replica:ListenToChange({"Phase"}, function(newValue)
			phase:set(newValue)
			
			-- Reset cursor when entering a match
			if newValue == Config.PHASE.COUNTDOWN then
				cursorX:set(math.floor(Config.BOARD_WIDTH / 2))
				cursorY:set(1)
			end
		end)
		
		replica:ListenToChange({"MatchId"}, function(newValue)
			matchId:set(newValue)
			-- Reset clear batch ID and animation state on new match
			lastClearBatchId = 0
			-- Clear animating cells tracking
			animatingCells = {}
			animatingVersion:set(animatingVersion:get() + 1)
			-- Clear any existing flying tiles
			if myAnimationLayer then
				for _, child in ipairs(myAnimationLayer:GetChildren()) do
					child:Destroy()
				end
			end
			if oppAnimationLayer then
				for _, child in ipairs(oppAnimationLayer:GetChildren()) do
					child:Destroy()
				end
			end
		end)
		
		replica:ListenToChange({"MyBoard"}, function(newValue)
			-- Animate tile movements before updating state
			local oldBoard = myBoard:get()
			
			if oldBoard and newValue then
				animateBoardChanges(oldBoard, newValue, myAnimationLayer, true)
			end
			
			-- Update reactive state
			myBoard:set(newValue)
		end)
		
		replica:ListenToChange({"OppBoard"}, function(newValue)
			-- Animate tile movements before updating state
			local oldBoard = oppBoard:get()
			
			if oldBoard and newValue then
				animateBoardChanges(oldBoard, newValue, oppAnimationLayer, false)
			end
			
			-- Update reactive state
			oppBoard:set(newValue)
		end)
		
		-- Listen for clear batches (server-driven)
		replica:ListenToChange({"ClearBatchId"}, function(newBatchId)
			print("[Client] ClearBatchId changed to", newBatchId, "last was", lastClearBatchId)
			if newBatchId > lastClearBatchId then
				lastClearBatchId = newBatchId
				
				-- Process MyClearBatch
				local myClearBatch = replica.Data.MyClearBatch
				print("[Client] MyClearBatch has", myClearBatch and #myClearBatch or 0, "tiles")
				if myClearBatch and #myClearBatch > 0 then
					for i, tile in ipairs(myClearBatch) do
						print(string.format("[Client]   [%d] x=%d y=%d colorId=%d", i, tile.x, tile.y, tile.colorId))
					end
					processClearBatch(myClearBatch, "my")
				end
				
				-- Process OppClearBatch
				local oppClearBatch = replica.Data.OppClearBatch
				print("[Client] OppClearBatch has", oppClearBatch and #oppClearBatch or 0, "tiles")
				if oppClearBatch and #oppClearBatch > 0 then
					processClearBatch(oppClearBatch, "opp")
				end
			end
		end)
		
		replica:ListenToChange({"OpponentUserId"}, function(newValue)
			opponentUserId:set(newValue)
		end)
		
		replica:ListenToChange({"WinnerUserId"}, function(newValue)
			winnerUserId:set(newValue)
		end)
		
		replica:ListenToChange({"CountdownEndsAt"}, function(newValue)
			countdownEndsAt:set(newValue)
		end)
		
		replica:ListenToChange({"CountdownSeconds"}, function(newValue)
			countdownSeconds:set(newValue)
		end)
		
		replica:ListenToChange({"MatchStartedAt"}, function(newValue)
			matchStartedAt:set(newValue)
		end)
		
		replica:ListenToChange({"MyCursor"}, function(newValue)
			if newValue then
				cursorX:set(newValue.x)
				cursorY:set(newValue.y)
			end
		end)
		
		replica:ListenToChange({"OppCursor"}, function(newValue)
			if newValue then
				oppCursorX:set(newValue.x)
				oppCursorY:set(newValue.y)
			end
		end)
		
		replica:ListenToChange({"BackgroundAssetId"}, function(newValue)
			backgroundAssetId:set(newValue or "")
		end)
		
		print("[PuzzleLeagueController] Connected to player replica")
	end)
	
	-- Request replica data from server
	ReplicaController.RequestData()
end

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         KNIT LIFECYCLE                                      ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

function PuzzleLeagueController:KnitInit()
	print("[PuzzleLeagueController] Initializing...")
end

function PuzzleLeagueController:KnitStart()
	print("[PuzzleLeagueController] Starting...")
	
	-- Get service reference
	PuzzleLeagueService = Knit.GetService("PuzzleLeagueService")
	
	-- Setup systems
	setupReplicaListener()
	setupInput()
	createUI()
	
	-- Update current time for countdown/timer display
	RunService.Heartbeat:Connect(function()
		currentTime:set(workspace:GetServerTimeNow())
	end)
	
	print("[PuzzleLeagueController] Ready")
end

return PuzzleLeagueController

