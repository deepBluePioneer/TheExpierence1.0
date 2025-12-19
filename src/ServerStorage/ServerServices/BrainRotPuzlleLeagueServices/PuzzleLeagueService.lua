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
-- Available background asset IDs
local BACKGROUND_ASSETS = {
	"rbxassetid://114775471895446",
	"rbxassetid://99750803009155",
}

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
			-- Clear batch system (server-driven)
			ClearBatchId = 0, -- Incremented on each resolve
			MyClearBatch = {}, -- Array of {x, y, colorId} for player's board clears
			OppClearBatch = {}, -- Array of {x, y, colorId} for opponent's board clears
			-- Background (same for both players in a match)
			BackgroundAssetId = "",
			-- Garbage system
			PendingGarbage = 0, -- Incoming garbage queued for this player
			ChainCount = 0, -- Current chain level (for display)
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
	
	-- Select random background (same for both players)
	local backgroundAssetId = BACKGROUND_ASSETS[math.random(1, #BACKGROUND_ASSETS)]
	
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
		-- Swap lock per board (prevents overlapping swaps)
		board1SwapLockedUntil = 0,
		board2SwapLockedUntil = 0,
		-- Clear batch ID (incremented each resolve)
		clearBatchId = 0,
		-- Background for this match
		backgroundAssetId = backgroundAssetId,
		-- Garbage system
		pendingGarbage1 = 0, -- Garbage queued to spawn on player 1's board
		pendingGarbage2 = 0, -- Garbage queued to spawn on player 2's board
		chainCount1 = 0, -- Current chain level for player 1
		chainCount2 = 0, -- Current chain level for player 2
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
		replica1:SetValue({"ClearBatchId"}, 0)
		replica1:SetValue({"MyClearBatch"}, {})
		replica1:SetValue({"OppClearBatch"}, {})
		replica1:SetValue({"BackgroundAssetId"}, backgroundAssetId)
		replica1:SetValue({"PendingGarbage"}, 0)
		replica1:SetValue({"ChainCount"}, 0)
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
		replica2:SetValue({"ClearBatchId"}, 0)
		replica2:SetValue({"MyClearBatch"}, {})
		replica2:SetValue({"OppClearBatch"}, {})
		replica2:SetValue({"BackgroundAssetId"}, backgroundAssetId)
		replica2:SetValue({"PendingGarbage"}, 0)
		replica2:SetValue({"ChainCount"}, 0)
	end
	
	print("[PuzzleLeagueService] Match", matchId, "created:", player1.Name, "vs", player2.Name)
	print("[PuzzleLeagueService]   Initial garbage state: pendingGarbage1=", match.pendingGarbage1, "pendingGarbage2=", match.pendingGarbage2)
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
	-- Prevent double-ending
	if match.phase == Config.PHASE.RESULT then
		print("[PuzzleLeagueService] WARNING: Attempted to end match", match.id, "that already ended")
		return
	end
	
	match.phase = Config.PHASE.RESULT
	match.winner = winner
	
	local winnerUserId = winner and winner.UserId or 0
	local winnerName = winner and winner.Name or "Nobody"
	
	print("[PuzzleLeagueService] Ending match", match.id, "- Winner:", winnerName, "UserId:", winnerUserId)
	
	-- Update player 1 replica
	local replica1 = getPlayerReplica(match.player1)
	if replica1 then
		print("[PuzzleLeagueService]   Setting Player1 replica: Phase=RESULT, WinnerUserId=", winnerUserId)
		replica1:SetValue({"Phase"}, Config.PHASE.RESULT)
		replica1:SetValue({"WinnerUserId"}, winnerUserId)
	else
		print("[PuzzleLeagueService]   WARNING: Player1 replica is nil!")
	end
	
	-- Update player 2 replica
	local replica2 = getPlayerReplica(match.player2)
	if replica2 then
		print("[PuzzleLeagueService]   Setting Player2 replica: Phase=RESULT, WinnerUserId=", winnerUserId)
		replica2:SetValue({"Phase"}, Config.PHASE.RESULT)
		replica2:SetValue({"WinnerUserId"}, winnerUserId)
	else
		print("[PuzzleLeagueService]   WARNING: Player2 replica is nil!")
	end
	
	-- Remove match from active matches after a delay
	task.delay(1, function()
		activeMatches[match.id] = nil
	end)
	
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

-- Delay between swap and resolve processing (so client sees swap complete first)
local SWAP_RESOLVE_DELAY = Config.SWAP_RESOLVE_DELAY

--[[
	Gets the swap lock time for a player's board.
	@param match The match data
	@param player The player
	@return swapLockedUntil time
]]
local function getSwapLock(match, player)
	if match.player1 == player then
		return match.board1SwapLockedUntil
	else
		return match.board2SwapLockedUntil
	end
end

--[[
	Sets the swap lock time for a player's board.
	@param match The match data
	@param player The player
	@param lockUntil The server time to lock until
]]
local function setSwapLock(match, player, lockUntil)
	if match.player1 == player then
		match.board1SwapLockedUntil = lockUntil
	else
		match.board2SwapLockedUntil = lockUntil
	end
end

--[[
	Orders cleared tiles starting from the trigger position (swap location).
	Tiles closest to trigger come first.
	@param clearedTiles Array of {x, y, colorId}
	@param triggerX The x position of the swap
	@param triggerY The y position of the swap
	@return Ordered array of cleared tiles
]]
local function orderClearedTilesFromTrigger(clearedTiles, triggerX, triggerY)
	-- Calculate distance from trigger for each tile
	local tilesWithDistance = {}
	for _, tile in ipairs(clearedTiles) do
		local distance = math.abs(tile.x - triggerX) + math.abs(tile.y - triggerY)
		table.insert(tilesWithDistance, {
			tile = tile,
			distance = distance,
		})
	end
	
	-- Sort by distance (closest to trigger first)
	table.sort(tilesWithDistance, function(a, b)
		return a.distance < b.distance
	end)
	
	-- Extract ordered tiles
	local ordered = {}
	for _, entry in ipairs(tilesWithDistance) do
		table.insert(ordered, entry.tile)
	end
	
	return ordered
end

--[[
	Emits clear batches to both players.
	@param match The match data
	@param clearingPlayer The player whose board had clears
	@param clearedTiles Array of {x, y, colorId}
	@param triggerX Optional x position of the swap that triggered the clear
	@param triggerY Optional y position of the swap that triggered the clear
]]
local function emitClearBatches(match, clearingPlayer, clearedTiles, triggerX, triggerY)
	print("[Server] emitClearBatches called")
	print("[Server]   clearingPlayer:", clearingPlayer.Name)
	print("[Server]   clearedTiles count:", #clearedTiles)
	print("[Server]   triggerX:", triggerX or "nil", "triggerY:", triggerY or "nil")
	
	if #clearedTiles == 0 then
		print("[Server]   No tiles to clear, returning")
		return
	end
	
	-- Log all cleared tiles before ordering
	print("[Server]   Cleared tiles (before ordering):")
	for i, tile in ipairs(clearedTiles) do
		print(string.format("[Server]     [%d] x=%d, y=%d, colorId=%d", i, tile.x, tile.y, tile.colorId))
	end
	
	-- Order tiles from trigger position if provided
	local orderedTiles = clearedTiles
	if triggerX and triggerY then
		orderedTiles = orderClearedTilesFromTrigger(clearedTiles, triggerX, triggerY)
		print("[Server]   Cleared tiles (after ordering from trigger):")
		for i, tile in ipairs(orderedTiles) do
			print(string.format("[Server]     [%d] x=%d, y=%d, colorId=%d", i, tile.x, tile.y, tile.colorId))
		end
	end
	
	-- Increment clear batch ID
	match.clearBatchId = match.clearBatchId + 1
	local batchId = match.clearBatchId
	print("[Server]   New batchId:", batchId)
	
	-- Get replicas
	local replica1 = getPlayerReplica(match.player1)
	local replica2 = getPlayerReplica(match.player2)
	
	-- IMPORTANT: Set batch DATA first, then batch ID last!
	-- Client listens to ClearBatchId changes and reads batch data.
	-- If we set ID first, client might read stale data.
	
	-- For player1: if clearing player is player1, it's "MyClearBatch", otherwise "OppClearBatch"
	if replica1 then
		-- Set batch data FIRST
		if clearingPlayer == match.player1 then
			replica1:SetValue({"MyClearBatch"}, orderedTiles)
			replica1:SetValue({"OppClearBatch"}, {})
		else
			replica1:SetValue({"MyClearBatch"}, {})
			replica1:SetValue({"OppClearBatch"}, orderedTiles)
		end
		-- Set batch ID LAST (this triggers client listener)
		replica1:SetValue({"ClearBatchId"}, batchId)
	end
	
	-- For player2: roles are reversed
	if replica2 then
		-- Set batch data FIRST
		if clearingPlayer == match.player2 then
			replica2:SetValue({"MyClearBatch"}, orderedTiles)
			replica2:SetValue({"OppClearBatch"}, {})
		else
			replica2:SetValue({"MyClearBatch"}, {})
			replica2:SetValue({"OppClearBatch"}, orderedTiles)
		end
		-- Set batch ID LAST (this triggers client listener)
		replica2:SetValue({"ClearBatchId"}, batchId)
	end
end

--[[
	Processes a swap action from a player.
	Two-phase: swap immediately, then resolve after delay.
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
	
	-- Check swap lock - reject if board is locked
	local currentTime = workspace:GetServerTimeNow()
	local swapLockedUntil = getSwapLock(match, player)
	if currentTime < swapLockedUntil then
		return false
	end
	
	-- Get player's board
	local board = getBoardForPlayer(match, player)
	
	print("[Server] processSwap: player=", player.Name, "x=", x, "y=", y)
	
	-- Log the tiles at swap positions BEFORE swap
	local leftTile = BoardLogic.GetCell(board, x, y)
	local rightTile = BoardLogic.GetCell(board, x + 1, y)
	print(string.format("[Server]   Before swap: (%d,%d)=%s, (%d,%d)=%s", 
		x, y, tostring(leftTile), x+1, y, tostring(rightTile)))
	
	-- Perform swap only (no match processing yet)
	local swapped = BoardLogic.Swap(board, x, y)
	if not swapped then
		print("[Server]   Swap FAILED")
		return false
	end
	
	-- Log after swap
	leftTile = BoardLogic.GetCell(board, x, y)
	rightTile = BoardLogic.GetCell(board, x + 1, y)
	print(string.format("[Server]   After swap: (%d,%d)=%s, (%d,%d)=%s", 
		x, y, tostring(leftTile), x+1, y, tostring(rightTile)))
	
	-- Set swap lock
	local lockUntil = currentTime + SWAP_RESOLVE_DELAY
	setSwapLock(match, player, lockUntil)
	
	-- Replicate the swap immediately (tiles move to new positions)
	print("[Server]   Replicating swap immediately...")
	replicateBoards(match)
	
	-- Store swap position for ordering clear effects later
	local swapX, swapY = x, y
	
	-- After delay, process matches and gravity (resolve phase)
	print(string.format("[Server]   Scheduling resolve in %.2f seconds...", SWAP_RESOLVE_DELAY))
	task.delay(SWAP_RESOLVE_DELAY, function()
		print("[Server] Resolve phase starting for swap at x=", swapX, "y=", swapY)
		
		-- Make sure match still exists and is still in progress
		if not activeMatches[matchId] then
			print("[Server]   Match no longer exists, aborting")
			return
		end
		if match.phase ~= Config.PHASE.IN_MATCH then
			print("[Server]   Match not in IN_MATCH phase, aborting")
			return
		end
		
		-- Determine which player this is and their opponent (used in processClearGravityCycle and garbage scheduling)
		local isPlayer1 = (player == match.player1)
		local opponent = isPlayer1 and match.player2 or match.player1
		
		-- Process with phased clear-then-gravity (handles chain reactions)
		local function processClearGravityCycle(triggerX, triggerY)
			local maxChains = 20 -- Safety limit for chain reactions
			local chainCount = 0
			local totalGarbageSent = 0
			
			while chainCount < maxChains do
				chainCount = chainCount + 1
				
				-- Step 1: Find and capture matches
				local matches = BoardLogic.FindMatches(board)
				local clearedTiles = BoardLogic.CaptureClearedTiles(board, matches)
				local cleared = BoardLogic.ClearMatches(board, matches)
				
				-- Step 2: If clears happened, process garbage and show effects
				if cleared > 0 then
					print("[Server]   Chain", chainCount, "- Cleared:", cleared, "tiles")
					
					-- Calculate garbage to send to opponent
					local garbageAmount = BoardLogic.CalculateGarbageSent(cleared, chainCount)
					totalGarbageSent = totalGarbageSent + garbageAmount
					
					if garbageAmount > 0 then
						print("[Server]   Sending", garbageAmount, "garbage (chain level:", chainCount, ")")
					end
					
					-- Update chain count display
					if isPlayer1 then
						match.chainCount1 = chainCount
					else
						match.chainCount2 = chainCount
					end
					local replica = getPlayerReplica(player)
					if replica then
						replica:SetValue({"ChainCount"}, chainCount)
					end
					
					-- Find and convert garbage adjacent to cleared tiles
					local adjacentGarbage = BoardLogic.FindAdjacentGarbage(board, matches)
					if next(adjacentGarbage) then
						local convertedTiles = BoardLogic.ConvertGarbage(board, adjacentGarbage)
						print("[Server]   Converted", #convertedTiles, "garbage tiles")
					end
					
					-- Replicate board with holes (BEFORE gravity)
					replicateBoards(match)
					
					-- Emit clear batch
					emitClearBatches(match, player, clearedTiles, triggerX, triggerY)
					-- Only use trigger position for first chain
					triggerX, triggerY = nil, nil
					
					-- Wait for client clear effects to finish (white + flash + buffer)
					local clearEffectTime = Config.CLEAR_EFFECT_WHITE_DURATION 
						+ Config.CLEAR_EFFECT_FLASH_DURATION 
						+ Config.CLEAR_EFFECT_BUFFER
					print(string.format("[Server]   Waiting %.2fs for clear effects...", clearEffectTime))
					task.wait(clearEffectTime)
				end
				
				-- Step 3: Apply gravity (ALWAYS, even if no clears)
				local anyFell = BoardLogic.ApplyGravity(board)
				
				-- Step 4: Replicate board with tiles in new positions
				if cleared > 0 or anyFell then
					print("[Server]   Gravity applied, anyFell:", anyFell)
					replicateBoards(match)
				end
				
				-- Step 5: If nothing happened this iteration, we're stable
				if cleared == 0 and not anyFell then
					print("[Server]   Board is stable")
					break
				end
				
				-- Loop will check for chain reactions (new matches from gravity)
			end
			
			-- After resolve cycle: reset chain count and queue garbage for opponent
			if isPlayer1 then
				match.chainCount1 = 0
				match.pendingGarbage2 = match.pendingGarbage2 + totalGarbageSent
			else
				match.chainCount2 = 0
				match.pendingGarbage1 = match.pendingGarbage1 + totalGarbageSent
			end
			
			-- Update opponent's pending garbage display
			local opponentReplica = getPlayerReplica(opponent)
			if opponentReplica and totalGarbageSent > 0 then
				local pendingGarbage = isPlayer1 and match.pendingGarbage2 or match.pendingGarbage1
				opponentReplica:SetValue({"PendingGarbage"}, pendingGarbage)
				print("[Server]   Opponent now has", pendingGarbage, "pending garbage")
			end
			
			-- Reset player's chain count display
			local playerReplica = getPlayerReplica(player)
			if playerReplica then
				playerReplica:SetValue({"ChainCount"}, 0)
			end
			
			return totalGarbageSent
		end
		
		print("[Server] Starting processClearGravityCycle for matchId:", matchId)
		local garbageSent = processClearGravityCycle(swapX, swapY)
		print("[Server] processClearGravityCycle returned garbageSent:", garbageSent)
		
		-- If garbage was sent, schedule it to drop on opponent's board after delay
		if garbageSent > 0 then
			local opponentBoard = isPlayer1 and match.board2 or match.board1
			local garbageTarget = isPlayer1 and "player2" or "player1"
			-- Capture the winner (the player who sent the garbage) for the callback
			local garbageSender = player
			local capturedMatchId = matchId
			
			print("[Server] Scheduling garbage drop for matchId:", capturedMatchId, "target:", garbageTarget, "amount:", garbageSent, "isPlayer1:", isPlayer1, "player:", player.Name, "match.player1:", match.player1.Name)
			
			-- Schedule garbage drop after delay
			task.delay(Config.GARBAGE_DROP_DELAY, function()
				-- Make sure match still exists
				local currentMatch = activeMatches[capturedMatchId]
				if not currentMatch then 
					print("[Server] Garbage callback: match", capturedMatchId, "no longer exists")
					return 
				end
				if currentMatch.phase ~= Config.PHASE.IN_MATCH then 
					print("[Server] Garbage callback: match", capturedMatchId, "phase is", currentMatch.phase, "not IN_MATCH")
					return 
				end
				
				-- Get current pending garbage
				local pending = garbageTarget == "player1" and currentMatch.pendingGarbage1 or currentMatch.pendingGarbage2
				if pending <= 0 then 
					print("[Server] Garbage callback: pending is 0 for", garbageTarget)
					return 
				end
				
				-- Calculate rows to drop (6 cells = 1 row)
				local garbageRows = math.ceil(pending / Config.BOARD_WIDTH)
				garbageRows = math.min(garbageRows, 4) -- Cap at 4 rows per drop
				
				print("[Server] Dropping", garbageRows, "garbage rows on", garbageTarget)
				
				-- Drop garbage from top
				local targetBoard = garbageTarget == "player1" and currentMatch.board1 or currentMatch.board2
				BoardLogic.DropGarbageFromTop(targetBoard, garbageRows)
				replicateBoards(currentMatch)
				
				-- Reduce pending garbage
				local used = garbageRows * Config.BOARD_WIDTH
				if garbageTarget == "player1" then
					currentMatch.pendingGarbage1 = math.max(0, currentMatch.pendingGarbage1 - used)
				else
					currentMatch.pendingGarbage2 = math.max(0, currentMatch.pendingGarbage2 - used)
				end
				
				-- Update opponent's pending garbage display
				local targetPlayer = garbageTarget == "player1" and currentMatch.player1 or currentMatch.player2
				local targetReplica = getPlayerReplica(targetPlayer)
				if targetReplica then
					local remaining = garbageTarget == "player1" and currentMatch.pendingGarbage1 or currentMatch.pendingGarbage2
					targetReplica:SetValue({"PendingGarbage"}, remaining)
				end
				
				-- Check for top-out on opponent (garbage sender wins)
				if BoardLogic.IsTopOut(targetBoard) then
					print("[Server] Top-out from garbage! Winner:", garbageSender.Name)
					endMatch(currentMatch, garbageSender)
				end
			end)
		end
		
		-- Check for top-out on current player
		if BoardLogic.IsTopOut(board) then
			local opponentPlayer = getOpponentForPlayer(match, player)
			endMatch(match, opponentPlayer)
		end
		
		print("[Server] Resolve phase complete")
	end)
	
	return true
end

--[[
	Updates the rising board for a match.
	@param match The match data
	@param dt Delta time
]]
--[[
	Process clears with phased gravity (spawns coroutine, doesn't block).
	Used for rising board clears where we don't want to block the main loop.
	@param match The match
	@param board The board
	@param player The player whose board this is
]]
local function processRisingBoardClears(match, board, player)
	-- Step 1: Find and clear matches (no gravity yet)
	local matches = BoardLogic.FindMatches(board)
	local clearedTiles = BoardLogic.CaptureClearedTiles(board, matches)
	local cleared = BoardLogic.ClearMatches(board, matches)
	
	if cleared == 0 then
		return -- No matches
	end
	
	print("[Server] Rising board caused", cleared, "clears")
	
	-- Step 2: Replicate board with holes (BEFORE gravity)
	replicateBoards(match)
	
	-- Step 3: Emit clear batch
	emitClearBatches(match, player, clearedTiles)
	
	-- Step 4: Spawn async task to wait then apply gravity
	task.spawn(function()
		local clearEffectTime = Config.CLEAR_EFFECT_WHITE_DURATION 
			+ Config.CLEAR_EFFECT_FLASH_DURATION 
			+ Config.CLEAR_EFFECT_BUFFER
		
		task.wait(clearEffectTime)
		
		-- Check match still exists
		if not activeMatches[match.matchId] then return end
		if match.phase ~= Config.PHASE.IN_MATCH then return end
		
		-- Apply gravity
		BoardLogic.ApplyGravity(board)
		replicateBoards(match)
		
		-- Check for chain reactions (recursively)
		processRisingBoardClears(match, board, player)
	end)
end

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
			
			-- Process any matches caused by the new row (async, won't block)
			processRisingBoardClears(match, board, player)
			
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

