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

-- Cursor state (local player)
local cursorX = Value(1)
local cursorY = Value(1)

-- Opponent cursor state (replicated)
local oppCursorX = Value(1)
local oppCursorY = Value(1)

-- Current time for countdown/timer display
local currentTime = Value(workspace:GetServerTimeNow())

-- Previous board states for detecting clears
local prevMyBoard = nil
local prevOppBoard = nil

-- Clear effect containers (will hold Frame references for effects)
local myBoardClearContainer = nil
local oppBoardClearContainer = nil

-- Clear effect animation settings
local CLEAR_FLASH_DURATION = 0.15 -- Duration of white flash
local CLEAR_FADE_DURATION = 0.25 -- Duration of fade out after flash

-- Keyboard input
local keyboard

-- Replica reference
local playerReplica

-- UI reference
local screenGui

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                              UI CONSTANTS                                   ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

local CELL_SIZE = 40
local BOARD_GAP = 20
local BOARD_PADDING = 10

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
	Detects cleared tiles by comparing old and new board states.
	Returns a list of cleared tile positions and their colors.
	@param oldBoard Previous board snapshot
	@param newBoard New board snapshot
	@return Array of { x, y, colorId }
]]
local function detectClearedTiles(oldBoard, newBoard)
	local cleared = {}
	
	if not oldBoard or not oldBoard.cells then
		return cleared
	end
	if not newBoard or not newBoard.cells then
		return cleared
	end
	
	local w = oldBoard.w
	local h = oldBoard.h
	
	-- Count ALL tiles of each color across the ENTIRE board (not per-column)
	-- A tile was cleared only if the TOTAL count of that color decreased
	
	-- Count colors in old board (entire board)
	local oldColorCounts = {}
	local oldColorPositions = {} -- Track all positions for each color
	
	for y = 1, h do
		for x = 1, w do
			local oldIndex = (y - 1) * w + x
			local oldTile = oldBoard.cells[oldIndex]
			if oldTile and oldTile > 0 then
				oldColorCounts[oldTile] = (oldColorCounts[oldTile] or 0) + 1
				if not oldColorPositions[oldTile] then
					oldColorPositions[oldTile] = {}
				end
				table.insert(oldColorPositions[oldTile], { x = x, y = y })
			end
		end
	end
	
	-- Count colors in new board (entire board)
	local newColorCounts = {}
	for y = 1, h do
		for x = 1, w do
			local newIndex = (y - 1) * w + x
			local newTile = newBoard.cells[newIndex]
			if newTile and newTile > 0 then
				newColorCounts[newTile] = (newColorCounts[newTile] or 0) + 1
			end
		end
	end
	
	-- Find colors where total count decreased - those were cleared
	for colorId, oldCount in pairs(oldColorCounts) do
		local newCount = newColorCounts[colorId] or 0
		local clearedCount = oldCount - newCount
		
		if clearedCount > 0 then
			-- Find which positions of this color are now empty in the new board
			local positions = oldColorPositions[colorId]
			local effectsAdded = 0
			
			for _, pos in ipairs(positions) do
				if effectsAdded >= clearedCount then
					break
				end
				
				-- Check if this position is now empty or has a different color
				local newIndex = (pos.y - 1) * w + pos.x
				local newTile = newBoard.cells[newIndex]
				if not newTile or newTile == 0 or newTile ~= colorId then
					table.insert(cleared, { x = pos.x, y = pos.y, colorId = colorId })
					effectsAdded = effectsAdded + 1
				end
			end
		end
	end
	
	return cleared
end

--[[
	Creates a clear effect (flash + fade) at the specified position.
	@param container The Frame to parent the effect to
	@param x Column position
	@param y Row position
	@param colorId The tile color ID
]]
local function createClearEffect(container, x, y, colorId)
	if not container then return end
	
	local tileColor = Config.TILE_COLORS[colorId] or COLORS.ACCENT
	
	-- Calculate position (same as cell position calculation)
	local posX = (x - 1) * CELL_SIZE + 1
	local posY = (Config.BOARD_HEIGHT - y) * CELL_SIZE + 1
	
	-- Create the effect frame (shows tile in position immediately)
	local effectFrame = Instance.new("Frame")
	effectFrame.Name = "ClearEffect"
	effectFrame.Size = UDim2.new(0, CELL_SIZE - 2, 0, CELL_SIZE - 2)
	effectFrame.Position = UDim2.new(0, posX, 0, posY)
	effectFrame.BackgroundColor3 = tileColor
	effectFrame.BorderSizePixel = 0
	effectFrame.ZIndex = 5
	effectFrame.Parent = container
	
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 4)
	corner.Parent = effectFrame
	
	-- White flash overlay (starts visible for immediate flash)
	local flashOverlay = Instance.new("Frame")
	flashOverlay.Name = "Flash"
	flashOverlay.Size = UDim2.new(1, 0, 1, 0)
	flashOverlay.BackgroundColor3 = Color3.new(1, 1, 1)
	flashOverlay.BackgroundTransparency = 0.5 -- Start semi-visible
	flashOverlay.BorderSizePixel = 0
	flashOverlay.ZIndex = 6
	flashOverlay.Parent = effectFrame
	
	local flashCorner = Instance.new("UICorner")
	flashCorner.CornerRadius = UDim.new(0, 4)
	flashCorner.Parent = flashOverlay
	
	-- Animate: flash white, then fade out (server already delayed the clear event)
	task.spawn(function()
		local TweenService = game:GetService("TweenService")
		
		-- Flash IN phase: white overlay appears
		local flashInTween = TweenService:Create(
			flashOverlay,
			TweenInfo.new(CLEAR_FLASH_DURATION * 0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ BackgroundTransparency = 0 }
		)
		flashInTween:Play()
		flashInTween.Completed:Wait()
		
		-- Flash OUT phase: white overlay fades
		local flashOutTween = TweenService:Create(
			flashOverlay,
			TweenInfo.new(CLEAR_FLASH_DURATION * 0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ BackgroundTransparency = 1 }
		)
		flashOutTween:Play()
		flashOutTween.Completed:Wait()
		
		-- Fade phase: fade out the colored tile
		local fadeTween = TweenService:Create(
			effectFrame,
			TweenInfo.new(CLEAR_FADE_DURATION, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ BackgroundTransparency = 1 }
		)
		fadeTween:Play()
		fadeTween.Completed:Wait()
		
		-- Clean up
		effectFrame:Destroy()
	end)
end

--[[
	Spawns clear effects for all cleared tiles.
	@param clearedTiles Array of { x, y, colorId }
	@param container The Frame to parent effects to
]]
local function spawnClearEffects(clearedTiles, container)
	-- Spawn effects immediately (they handle their own delay internally)
	for _, tile in ipairs(clearedTiles) do
		createClearEffect(container, tile.x, tile.y, tile.colorId)
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
	return New "Frame" {
		Name = "Cell_" .. x .. "_" .. y,
		Size = UDim2.new(0, CELL_SIZE - 2, 0, CELL_SIZE - 2),
		Position = UDim2.new(0, (x - 1) * CELL_SIZE + 1, 0, (Config.BOARD_HEIGHT - y) * CELL_SIZE + 1),
		BackgroundColor3 = Computed(function()
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
			
			-- Player cursor highlight (on own board)
			isMyBoard and New "Frame" {
				Name = "CursorHighlight",
				Size = UDim2.new(1, 4, 1, 4),
				Position = UDim2.new(0.5, 0, 0.5, 0),
				AnchorPoint = Vector2.new(0.5, 0.5),
				BackgroundTransparency = 1,
				Visible = Computed(function()
					local cx = cursorX:get()
					local cy = cursorY:get()
					return (x == cx or x == cx + 1) and y == cy
				end),
				
				[Children] = {
					New "UICorner" { CornerRadius = UDim.new(0, 6) },
					New "UIStroke" {
						Color = COLORS.CURSOR,
						Thickness = 3,
					},
				},
			} or nil,
			
			-- Opponent cursor highlight (on opponent board)
			showOppCursor and New "Frame" {
				Name = "OppCursorHighlight",
				Size = UDim2.new(1, 4, 1, 4),
				Position = UDim2.new(0.5, 0, 0.5, 0),
				AnchorPoint = Vector2.new(0.5, 0.5),
				BackgroundTransparency = 1,
				Visible = Computed(function()
					local cx = oppCursorX:get()
					local cy = oppCursorY:get()
					return (x == cx or x == cx + 1) and y == cy
				end),
				
				[Children] = {
					New "UICorner" { CornerRadius = UDim.new(0, 6) },
					New "UIStroke" {
						Color = COLORS.OPP_CURSOR,
						Thickness = 3,
					},
				},
			} or nil,
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
	
	-- Create clear effects container (stored for spawning effects later)
	local clearEffectsContainer = New "Frame" {
		Name = "ClearEffects",
		Size = UDim2.new(0, Config.BOARD_WIDTH * CELL_SIZE, 0, Config.BOARD_HEIGHT * CELL_SIZE),
		Position = UDim2.new(0, BOARD_PADDING, 0, 30 + BOARD_PADDING),
		BackgroundTransparency = 1,
		ZIndex = 3,
	}
	
	-- Store reference to the clear effects container
	if isMyBoard then
		myBoardClearContainer = clearEffectsContainer
	else
		oppBoardClearContainer = clearEffectsContainer
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
			
			-- Clear effects container (above board)
			clearEffectsContainer,
			
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
			
			-- Board container with rise offset
			New "Frame" {
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
			},
			
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
		end)
		
		replica:ListenToChange({"MyBoard"}, function(newValue)
			-- Detect cleared tiles and spawn effects BEFORE updating state
			local clearedTiles = detectClearedTiles(prevMyBoard, newValue)
			if #clearedTiles > 0 then
				spawnClearEffects(clearedTiles, myBoardClearContainer)
			end
			
			prevMyBoard = newValue
			myBoard:set(newValue)
		end)
		
		replica:ListenToChange({"OppBoard"}, function(newValue)
			-- Detect cleared tiles and spawn effects BEFORE updating state
			local clearedTiles = detectClearedTiles(prevOppBoard, newValue)
			if #clearedTiles > 0 then
				spawnClearEffects(clearedTiles, oppBoardClearContainer)
			end
			
			prevOppBoard = newValue
			oppBoard:set(newValue)
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

