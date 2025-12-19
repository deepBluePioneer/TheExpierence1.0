--[[
	PuzzleLeagueService
	
	Server-authoritative service for Panel de Pon / Puzzle League gameplay.
	Handles matchmaking, game simulation, and state replication.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local Knit = require(Packages.Knit)

local CustomPackages = ReplicatedStorage:WaitForChild("CustomPackages")
local ReplicaService = require(CustomPackages.Replica.ReplicaService)

local SharedModules = ReplicatedStorage:WaitForChild("Source"):WaitForChild("SharedModules")
local Config = require(SharedModules.PuzzleLeagueConfig)
local BoardLogic = require(SharedModules.PuzzleLeagueBoardLogic)

local PuzzleLeagueService = Knit.CreateService({
	Name = "PuzzleLeagueService",
	Client = {
		-- Client-callable methods defined below
	},
})

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                              STATE                                          ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

-- Replica class token
local PlayerReplicaToken = ReplicaService.NewClassToken(Config.REPLICA_CLASS)

-- Player replicas: { [Player] = Replica }
local playerReplicas = {}

-- Matchmaking queue: { Player, ... }
local matchQueue = {}

-- Active matches: { [matchId] = MatchData }
local activeMatches = {}

-- Match ID counter
local nextMatchId = 1

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         REPLICA MANAGEMENT                                  ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

--[[
	Creates a player replica with initial state.
	@param player The player to create replica for
	@return Replica
]]
local function createPlayerReplica(player)
	local replica = ReplicaService.NewReplica({
		ClassToken = PlayerReplicaToken,
		Tags = { Player = player },
		Data = {
			Phase = Config.PHASE.MENU,
			MatchId = 0,
			MyBoard = nil,
			OppBoard = nil,
			OpponentUserId = 0,
			WinnerUserId = 0,
			CountdownEndsAt = 0,
			CountdownSeconds = Config.COUNTDOWN_SECONDS,
			MatchStartedAt = 0, -- Game timer start time
			MyCursor = { x = 1, y = 1 }, -- Player's own cursor
			OppCursor = { x = 1, y = 1 }, -- Opponent's cursor (replicated)
		},
		Replication = player,
	})
	
	playerReplicas[player] = replica
	return replica
end

--[[
	Gets the replica for a player.
	@param player The player
	@return Replica or nil
]]
local function getPlayerReplica(player)
	return playerReplicas[player]
end

--[[
	Destroys a player's replica.
	@param player The player
]]
local function destroyPlayerReplica(player)
	local replica = playerReplicas[player]
	if replica then
		replica:Destroy()
		playerReplicas[player] = nil
	end
end

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         MATCHMAKING                                         ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

--[[
	Removes a player from the match queue.
	@param player The player to remove
]]
local function removeFromQueue(player)
	for i, queuedPlayer in ipairs(matchQueue) do
		if queuedPlayer == player then
			table.remove(matchQueue, i)
			break
		end
	end
end

--[[
	Adds a player to the match queue.
	@param player The player to add
]]
local function addToQueue(player)
	-- Remove if already in queue
	removeFromQueue(player)
	
	-- Add to queue
	table.insert(matchQueue, player)
	
	-- Update replica phase
	local replica = getPlayerReplica(player)
	if replica then
		replica:SetValue({"Phase"}, Config.PHASE.QUEUE)
	end
	
	print("[PuzzleLeagueService] Player", player.Name, "joined queue. Queue size:", #matchQueue)
end

--[[
	Attempts to create matches from queued players.
]]
local function processMatchQueue()
	while #matchQueue >= 2 do
		local player1 = table.remove(matchQueue, 1)
		local player2 = table.remove(matchQueue, 1)
		
		-- Verify both players are still connected
		if player1.Parent and player2.Parent then
			createMatch(player1, player2)
		elseif player1.Parent then
			table.insert(matchQueue, 1, player1)
			break
		elseif player2.Parent then
			table.insert(matchQueue, 1, player2)
			break
		end
	end
end

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         MATCH MANAGEMENT                                    ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

--[[
	Creates a new match between two players.
	@param player1 First player
	@param player2 Second player
]]
function createMatch(player1, player2)
	local matchId = nextMatchId
	nextMatchId = nextMatchId + 1
	
	-- Create initial boards
	local board1 = BoardLogic.CreateInitialBoard()
	local board2 = BoardLogic.CreateInitialBoard()
	
	-- Calculate countdown end time
	local countdownEndsAt = workspace:GetServerTimeNow() + Config.COUNTDOWN_SECONDS
	
	-- Create match data
	local match = {
		id = matchId,
		player1 = player1,
		player2 = player2,
		board1 = board1,
		board2 = board2,
		phase = Config.PHASE.COUNTDOWN,
		countdownEndsAt = countdownEndsAt,
		matchStartedAt = 0, -- Set when match actually starts
		winner = nil,
		cursor1 = { x = math.floor(Config.BOARD_WIDTH / 2), y = 1 },
		cursor2 = { x = math.floor(Config.BOARD_WIDTH / 2), y = 1 },
	}
	
	activeMatches[matchId] = match
	
	-- Update player 1 replica
	local replica1 = getPlayerReplica(player1)
	if replica1 then
		replica1:SetValue({"Phase"}, Config.PHASE.COUNTDOWN)
		replica1:SetValue({"MatchId"}, matchId)
		replica1:SetValue({"OpponentUserId"}, player2.UserId)
		replica1:SetValue({"CountdownEndsAt"}, countdownEndsAt)
		replica1:SetValue({"CountdownSeconds"}, Config.COUNTDOWN_SECONDS)
		replica1:SetValue({"MyBoard"}, BoardLogic.CreateSnapshot(board1))
		replica1:SetValue({"OppBoard"}, BoardLogic.CreateSnapshot(board2))
		replica1:SetValue({"WinnerUserId"}, 0)
		replica1:SetValue({"MatchStartedAt"}, 0)
		replica1:SetValue({"MyCursor"}, { x = match.cursor1.x, y = match.cursor1.y })
		replica1:SetValue({"OppCursor"}, { x = match.cursor2.x, y = match.cursor2.y })
	end
	
	-- Update player 2 replica
	local replica2 = getPlayerReplica(player2)
	if replica2 then
		replica2:SetValue({"Phase"}, Config.PHASE.COUNTDOWN)
		replica2:SetValue({"MatchId"}, matchId)
		replica2:SetValue({"OpponentUserId"}, player1.UserId)
		replica2:SetValue({"CountdownEndsAt"}, countdownEndsAt)
		replica2:SetValue({"CountdownSeconds"}, Config.COUNTDOWN_SECONDS)
		replica2:SetValue({"MyBoard"}, BoardLogic.CreateSnapshot(board2))
		replica2:SetValue({"OppBoard"}, BoardLogic.CreateSnapshot(board1))
		replica2:SetValue({"WinnerUserId"}, 0)
		replica2:SetValue({"MatchStartedAt"}, 0)
		replica2:SetValue({"MyCursor"}, { x = match.cursor2.x, y = match.cursor2.y })
		replica2:SetValue({"OppCursor"}, { x = match.cursor1.x, y = match.cursor1.y })
	end
	
	print("[PuzzleLeagueService] Match", matchId, "created:", player1.Name, "vs", player2.Name)
end

--[[
	Gets the match data for a player.
	@param player The player
	@return MatchData or nil
]]
local function getMatchForPlayer(player)
	for _, match in pairs(activeMatches) do
		if match.player1 == player or match.player2 == player then
			return match
		end
	end
	return nil
end

--[[
	Gets the board for a specific player in a match.
	@param match The match data
	@param player The player
	@return Board table
]]
local function getBoardForPlayer(match, player)
	if match.player1 == player then
		return match.board1
	else
		return match.board2
	end
end

--[[
	Gets the opponent for a specific player in a match.
	@param match The match data
	@param player The player
	@return Opponent player
]]
local function getOpponentForPlayer(match, player)
	if match.player1 == player then
		return match.player2
	else
		return match.player1
	end
end

--[[
	Updates replicated board state for both players.
	@param match The match data
]]
local function replicateBoards(match)
	local replica1 = getPlayerReplica(match.player1)
	local replica2 = getPlayerReplica(match.player2)
	
	local snapshot1 = BoardLogic.CreateSnapshot(match.board1)
	local snapshot2 = BoardLogic.CreateSnapshot(match.board2)
	
	if replica1 then
		replica1:SetValue({"MyBoard"}, snapshot1)
		replica1:SetValue({"OppBoard"}, snapshot2)
	end
	
	if replica2 then
		replica2:SetValue({"MyBoard"}, snapshot2)
		replica2:SetValue({"OppBoard"}, snapshot1)
	end
end

--[[
	Ends a match with a winner.
	@param match The match data
	@param winner The winning player (or nil for draw)
]]
local function endMatch(match, winner)
	match.phase = Config.PHASE.RESULT
	match.winner = winner
	
	local winnerUserId = winner and winner.UserId or 0
	
	-- Update player 1 replica
	local replica1 = getPlayerReplica(match.player1)
	if replica1 then
		replica1:SetValue({"Phase"}, Config.PHASE.RESULT)
		replica1:SetValue({"WinnerUserId"}, winnerUserId)
	end
	
	-- Update player 2 replica
	local replica2 = getPlayerReplica(match.player2)
	if replica2 then
		replica2:SetValue({"Phase"}, Config.PHASE.RESULT)
		replica2:SetValue({"WinnerUserId"}, winnerUserId)
	end
	
	-- Remove match from active matches after a delay
	task.delay(1, function()
		activeMatches[match.id] = nil
	end)
	
	local winnerName = winner and winner.Name or "Nobody"
	print("[PuzzleLeagueService] Match", match.id, "ended. Winner:", winnerName)
end

--[[
	Handles a player disconnecting from a match.
	@param player The disconnecting player
]]
local function handlePlayerDisconnect(player)
	local match = getMatchForPlayer(player)
	if match and match.phase ~= Config.PHASE.RESULT then
		local opponent = getOpponentForPlayer(match, player)
		endMatch(match, opponent)
	end
end

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         GAME SIMULATION                                     ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

-- Delay between swap and clear processing (so client sees swap complete first)
local SWAP_TO_CLEAR_DELAY = 0.30

--[[
	Processes a swap action from a player.
	Sends swap update first, then processes clears after a delay.
	@param player The player
	@param matchId The match ID
	@param x Column position
	@param y Row position
	@return true if swap was processed, false otherwise
]]
local function processSwap(player, matchId, x, y)
	local match = activeMatches[matchId]
	if not match then
		return false
	end
	
	-- Verify player is in this match
	if match.player1 ~= player and match.player2 ~= player then
		return false
	end
	
	-- Only allow swaps during InMatch phase
	if match.phase ~= Config.PHASE.IN_MATCH then
		return false
	end
	
	-- Get player's board
	local board = getBoardForPlayer(match, player)
	
	-- Perform swap only (no match processing yet)
	local swapped = BoardLogic.Swap(board, x, y)
	if not swapped then
		return false
	end
	
	-- Replicate the swap immediately (tiles move to new positions)
	replicateBoards(match)
	
	-- After a short delay, process matches and gravity
	task.delay(SWAP_TO_CLEAR_DELAY, function()
		-- Make sure match still exists
		if not activeMatches[matchId] then
			return
		end
		
		-- Process matches and gravity
		local cleared = BoardLogic.ProcessUntilStable(board)
		
		-- Only replicate if something was cleared
		if cleared > 0 then
			replicateBoards(match)
		end
		
		-- Check for top-out
		if BoardLogic.IsTopOut(board) then
			local opponent = getOpponentForPlayer(match, player)
			endMatch(match, opponent)
		end
	end)
	
	return true
end

--[[
	Updates the rising board for a match.
	@param match The match data
	@param dt Delta time
]]
local function updateRisingBoard(match, dt)
	-- Update both boards
	for _, boardData in ipairs({{match.board1, match.player1}, {match.board2, match.player2}}) do
		local board = boardData[1]
		local player = boardData[2]
		
		-- Increase rise offset
		board.rise = board.rise + Config.RISE_SPEED * dt
		
		-- When rise >= 1, push board up
		while board.rise >= 1 do
			board.rise = board.rise - 1
			
			-- Generate and push new row
			local newRow = BoardLogic.GenerateNewRow(board)
			BoardLogic.PushBoardUp(board, newRow)
			
			-- Process any matches caused by the new row
			BoardLogic.ProcessUntilStable(board)
			
			-- Check for top-out
			if BoardLogic.IsTopOut(board) then
				local opponent = getOpponentForPlayer(match, player)
				endMatch(match, opponent)
				return
			end
		end
	end
end

--[[
	Main simulation loop for all active matches.
	@param dt Delta time
]]
local function updateMatches(dt)
	local currentTime = workspace:GetServerTimeNow()
	
	for matchId, match in pairs(activeMatches) do
		-- Handle countdown -> InMatch transition
		if match.phase == Config.PHASE.COUNTDOWN then
			if currentTime >= match.countdownEndsAt then
				match.phase = Config.PHASE.IN_MATCH
				match.matchStartedAt = currentTime
				
				-- Update replicas
				local replica1 = getPlayerReplica(match.player1)
				local replica2 = getPlayerReplica(match.player2)
				
				if replica1 then
					replica1:SetValue({"Phase"}, Config.PHASE.IN_MATCH)
					replica1:SetValue({"MatchStartedAt"}, currentTime)
				end
				if replica2 then
					replica2:SetValue({"Phase"}, Config.PHASE.IN_MATCH)
					replica2:SetValue({"MatchStartedAt"}, currentTime)
				end
				
				print("[PuzzleLeagueService] Match", matchId, "started!")
			end
		end
		
		-- Update rising board during InMatch
		if match.phase == Config.PHASE.IN_MATCH then
			updateRisingBoard(match, dt)
			
			-- Replicate boards periodically (rise offset changes)
			replicateBoards(match)
		end
	end
end

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         CLIENT API                                          ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

--[[
	Client calls this to join the matchmaking queue.
	@param player The calling player
]]
function PuzzleLeagueService.Client:JoinQueue(player)
	local replica = getPlayerReplica(player)
	if not replica then
		return
	end
	
	-- Only allow joining queue from Menu or Result phase
	local currentPhase = replica.Data.Phase
	if currentPhase ~= Config.PHASE.MENU and currentPhase ~= Config.PHASE.RESULT then
		return
	end
	
	-- If in a match (Result phase), clean up first
	if currentPhase == Config.PHASE.RESULT then
		-- Reset state
		replica:SetValue({"MatchId"}, 0)
		replica:SetValue({"MyBoard"}, nil)
		replica:SetValue({"OppBoard"}, nil)
		replica:SetValue({"OpponentUserId"}, 0)
		replica:SetValue({"WinnerUserId"}, 0)
	end
	
	addToQueue(player)
	processMatchQueue()
end

--[[
	Client calls this to send a swap action.
	@param player The calling player
	@param matchId The match ID
	@param x Column position
	@param y Row position
]]
function PuzzleLeagueService.Client:SendSwap(player, matchId, x, y)
	-- Validate parameters
	if type(matchId) ~= "number" or type(x) ~= "number" or type(y) ~= "number" then
		return
	end
	
	processSwap(player, matchId, x, y)
end

--[[
	Client calls this to update cursor position.
	@param player The calling player
	@param matchId The match ID
	@param x Cursor X position
	@param y Cursor Y position
]]
function PuzzleLeagueService.Client:SendCursorUpdate(player, matchId, x, y)
	-- Validate parameters
	if type(matchId) ~= "number" or type(x) ~= "number" or type(y) ~= "number" then
		return
	end
	
	local match = activeMatches[matchId]
	if not match then
		return
	end
	
	-- Verify player is in this match
	if match.player1 ~= player and match.player2 ~= player then
		return
	end
	
	-- Only allow cursor updates during Countdown or InMatch
	if match.phase ~= Config.PHASE.COUNTDOWN and match.phase ~= Config.PHASE.IN_MATCH then
		return
	end
	
	-- Clamp cursor values
	x = math.clamp(x, 1, Config.BOARD_WIDTH - 1)
	y = math.clamp(y, 1, Config.BOARD_HEIGHT)
	
	-- Update cursor and replicate to opponent
	if match.player1 == player then
		match.cursor1.x = x
		match.cursor1.y = y
		
		-- Update own replica
		local replica1 = getPlayerReplica(match.player1)
		if replica1 then
			replica1:SetValue({"MyCursor"}, { x = x, y = y })
		end
		
		-- Update opponent's replica (as OppCursor)
		local replica2 = getPlayerReplica(match.player2)
		if replica2 then
			replica2:SetValue({"OppCursor"}, { x = x, y = y })
		end
	else
		match.cursor2.x = x
		match.cursor2.y = y
		
		-- Update own replica
		local replica2 = getPlayerReplica(match.player2)
		if replica2 then
			replica2:SetValue({"MyCursor"}, { x = x, y = y })
		end
		
		-- Update opponent's replica (as OppCursor)
		local replica1 = getPlayerReplica(match.player1)
		if replica1 then
			replica1:SetValue({"OppCursor"}, { x = x, y = y })
		end
	end
end

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         KNIT LIFECYCLE                                      ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

function PuzzleLeagueService:KnitInit()
	print("[PuzzleLeagueService] Initializing...")
end

function PuzzleLeagueService:KnitStart()
	print("[PuzzleLeagueService] Starting...")
	
	-- Handle player joining
	Players.PlayerAdded:Connect(function(player)
		createPlayerReplica(player)
		print("[PuzzleLeagueService] Created replica for", player.Name)
	end)
	
	-- Handle player leaving
	Players.PlayerRemoving:Connect(function(player)
		-- Remove from queue
		removeFromQueue(player)
		
		-- Handle disconnect from match
		handlePlayerDisconnect(player)
		
		-- Destroy replica
		destroyPlayerReplica(player)
		
		print("[PuzzleLeagueService] Cleaned up", player.Name)
	end)
	
	-- Create replicas for existing players
	for _, player in ipairs(Players:GetPlayers()) do
		createPlayerReplica(player)
	end
	
	-- Main simulation loop
	RunService.Heartbeat:Connect(function(dt)
		updateMatches(dt)
	end)
	
	print("[PuzzleLeagueService] Ready")
end

return PuzzleLeagueService

