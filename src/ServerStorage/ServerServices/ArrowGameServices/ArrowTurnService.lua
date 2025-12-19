--[[
	ArrowTurnService
	
	Manages turn-based gameplay using a State Machine pattern.
	- Each match has its own turn state
	- Players alternate taking one shot per turn
	- Tracks hits and determines winners
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local Knit = require(Packages.Knit)
local Signal = require(Packages.Signal)

local ArrowTurnService = Knit.CreateService({
	Name = "ArrowTurnService",
	Client = {
		TurnChanged = Knit.CreateSignal(),       -- (activePlayer, turnNumber)
		YourTurn = Knit.CreateSignal(),          -- (turnNumber)
		OpponentTurn = Knit.CreateSignal(),      -- (opponent, turnNumber)
		TurnResult = Knit.CreateSignal(),        -- (shooter, didHit, target)
		MatchEnded = Knit.CreateSignal(),        -- (winner, loser)
		StateChanged = Knit.CreateSignal(),      -- (newState, matchId)
	},
	
	-- Server-side signals
	OnTurnStart = Signal.new(),       -- (matchId, player)
	OnTurnEnd = Signal.new(),         -- (matchId, player, didHit)
	OnMatchEnd = Signal.new(),        -- (matchId, winner, loser)
})

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                              GAME STATES                                    ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

local GameState = {
	WAITING = "Waiting",              -- Waiting for match to start
	PLAYER_1_TURN = "Player1Turn",    -- Player 1 is aiming/shooting
	PROJECTILE_FLYING = "ProjectileFlying",  -- Arrow in the air
	PLAYER_2_TURN = "Player2Turn",    -- Player 2 is aiming/shooting
	MATCH_ENDED = "MatchEnded",       -- Match is over
}

-- State transitions
local Transitions = {
	[GameState.WAITING] = GameState.PLAYER_1_TURN,
	[GameState.PLAYER_1_TURN] = GameState.PROJECTILE_FLYING,
	[GameState.PROJECTILE_FLYING] = nil,  -- Determined by logic (either PLAYER_2_TURN or MATCH_ENDED)
	[GameState.PLAYER_2_TURN] = GameState.PROJECTILE_FLYING,
}

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                              CONFIGURATION                                  ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

local CONFIG = {
	TurnTimeLimit = 15,       -- Seconds per turn (0 = unlimited)
	MaxTurnsPerMatch = 10,    -- Max turns before draw
	HitsToWin = 1,            -- Hits needed to win
}

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                              STATE                                          ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

-- Match states: matchId -> { state, player1, player2, currentPlayer, turnNumber, etc. }
local matchStates = {}

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         STATE MACHINE                                       ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

function ArrowTurnService:GetMatchState(matchId: string)
	return matchStates[matchId]
end

function ArrowTurnService:SetState(matchId: string, newState: string)
	local match = matchStates[matchId]
	if not match then return end
	
	local oldState = match.state
	match.state = newState
	
	print(string.format("[ArrowTurnService] Match %s: %s -> %s", matchId, oldState, newState))
	
	-- Notify clients
	self.Client.StateChanged:FireAll(newState, matchId)
	
	-- Handle state entry logic
	self:OnStateEnter(matchId, newState)
end

function ArrowTurnService:OnStateEnter(matchId: string, state: string)
	local match = matchStates[matchId]
	if not match then return end
	
	if state == GameState.PLAYER_1_TURN then
		self:StartPlayerTurn(matchId, match.player1)
		
	elseif state == GameState.PLAYER_2_TURN then
		self:StartPlayerTurn(matchId, match.player2)
		
	elseif state == GameState.PROJECTILE_FLYING then
		-- Wait for projectile hit event
		print(string.format("[ArrowTurnService] Match %s: Waiting for projectile hit...", matchId))
		
	elseif state == GameState.MATCH_ENDED then
		self:HandleMatchEnd(matchId)
	end
end

function ArrowTurnService:StartPlayerTurn(matchId: string, player: Player)
	local match = matchStates[matchId]
	if not match then return end
	
	match.currentPlayer = player
	match.turnNumber = match.turnNumber + 1
	match.turnStartTime = os.clock()
	match.hasFired = false
	
	local opponent = player == match.player1 and match.player2 or match.player1
	
	print(string.format("[ArrowTurnService] Match %s: %s's turn (Turn %d)", 
		matchId, player.Name, match.turnNumber))
	
	-- Fire signals
	self.OnTurnStart:Fire(matchId, player)
	self.Client.TurnChanged:FireAll(player, match.turnNumber)
	self.Client.YourTurn:Fire(player, match.turnNumber)
	self.Client.OpponentTurn:Fire(opponent, player, match.turnNumber)
	
	-- Start turn timer if enabled
	if CONFIG.TurnTimeLimit > 0 then
		task.spawn(function()
			task.wait(CONFIG.TurnTimeLimit)
			-- Check if turn is still active (player hasn't fired)
			if match.state == GameState.PLAYER_1_TURN or match.state == GameState.PLAYER_2_TURN then
				if match.currentPlayer == player and not match.hasFired then
					print(string.format("[ArrowTurnService] %s ran out of time!", player.Name))
					self:OnPlayerFired(matchId, player)  -- Force end turn (miss)
				end
			end
		end)
	end
end

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         MATCH MANAGEMENT                                    ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

function ArrowTurnService:InitializeMatch(player1: Player, player2: Player, matchId: string)
	local matchState = {
		id = matchId,
		state = GameState.WAITING,
		player1 = player1,
		player2 = player2,
		currentPlayer = nil,
		turnNumber = 0,
		player1Hits = 0,
		player2Hits = 0,
		turnStartTime = 0,
		hasFired = false,
	}
	
	matchStates[matchId] = matchState
	
	print(string.format("[ArrowTurnService] ✓ Match initialized: %s vs %s (ID: %s)", 
		player1.Name, player2.Name, matchId))
	
	-- Start the match after a brief delay
	task.delay(2, function()
		self:SetState(matchId, GameState.PLAYER_1_TURN)
	end)
	
	return matchState
end

function ArrowTurnService:OnPlayerFired(matchId: string, player: Player)
	local match = matchStates[matchId]
	if not match then return end
	
	-- Verify it's this player's turn
	if match.currentPlayer ~= player then
		warn(string.format("[ArrowTurnService] %s tried to fire but it's not their turn!", player.Name))
		return false
	end
	
	-- Mark that player has fired
	match.hasFired = true
	
	-- Transition to projectile flying state
	self:SetState(matchId, GameState.PROJECTILE_FLYING)
	
	return true
end

function ArrowTurnService:OnProjectileHit(matchId: string, shooter: Player, hitPlayer: Player?, hitPart: BasePart?)
	local match = matchStates[matchId]
	if not match then return end
	
	local didHit = hitPlayer ~= nil and hitPlayer ~= shooter
	local target = didHit and hitPlayer or nil
	
	print(string.format("[ArrowTurnService] Match %s: %s %s", 
		matchId, shooter.Name, didHit and "HIT " .. hitPlayer.Name or "MISSED"))
	
	-- Update hit counts
	if didHit then
		if shooter == match.player1 then
			match.player1Hits = match.player1Hits + 1
		else
			match.player2Hits = match.player2Hits + 1
		end
	end
	
	-- Fire turn result
	self.OnTurnEnd:Fire(matchId, shooter, didHit)
	self.Client.TurnResult:FireAll(shooter, didHit, target)
	
	-- Check for win condition
	if match.player1Hits >= CONFIG.HitsToWin then
		match.winner = match.player1
		self:SetState(matchId, GameState.MATCH_ENDED)
		return
	elseif match.player2Hits >= CONFIG.HitsToWin then
		match.winner = match.player2
		self:SetState(matchId, GameState.MATCH_ENDED)
		return
	end
	
	-- Check for max turns (draw)
	if match.turnNumber >= CONFIG.MaxTurnsPerMatch then
		match.winner = nil  -- Draw
		self:SetState(matchId, GameState.MATCH_ENDED)
		return
	end
	
	-- Switch to other player's turn
	if match.currentPlayer == match.player1 then
		self:SetState(matchId, GameState.PLAYER_2_TURN)
	else
		self:SetState(matchId, GameState.PLAYER_1_TURN)
	end
end

function ArrowTurnService:HandleMatchEnd(matchId: string)
	local match = matchStates[matchId]
	if not match then return end
	
	local winner = match.winner
	local loser = winner == match.player1 and match.player2 or match.player1
	
	if winner then
		print(string.format("[ArrowTurnService] ✓ Match %s ended! Winner: %s", matchId, winner.Name))
	else
		print(string.format("[ArrowTurnService] Match %s ended in a DRAW!", matchId))
	end
	
	-- Fire signals
	self.OnMatchEnd:Fire(matchId, winner, loser)
	self.Client.MatchEnded:FireAll(winner, loser)
	
	-- Clean up match state after delay
	task.delay(5, function()
		matchStates[matchId] = nil
	end)
end

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         PUBLIC API                                          ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

function ArrowTurnService:IsPlayersTurn(player: Player): boolean
	-- Find player's match
	for matchId, match in pairs(matchStates) do
		if match.player1 == player or match.player2 == player then
			return match.currentPlayer == player and 
				   (match.state == GameState.PLAYER_1_TURN or match.state == GameState.PLAYER_2_TURN)
		end
	end
	return false
end

function ArrowTurnService:GetPlayerMatchId(player: Player): string?
	for matchId, match in pairs(matchStates) do
		if match.player1 == player or match.player2 == player then
			return matchId
		end
	end
	return nil
end

function ArrowTurnService:GetCurrentTurnPlayer(matchId: string): Player?
	local match = matchStates[matchId]
	if match then
		return match.currentPlayer
	end
	return nil
end

function ArrowTurnService:GetConfig()
	return CONFIG
end

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         CLIENT METHODS                                      ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

function ArrowTurnService.Client:IsMyTurn(player)
	return ArrowTurnService:IsPlayersTurn(player)
end

function ArrowTurnService.Client:NotifyFired(player)
	local matchId = ArrowTurnService:GetPlayerMatchId(player)
	if matchId then
		return ArrowTurnService:OnPlayerFired(matchId, player)
	end
	return false
end

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         KNIT LIFECYCLE                                      ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

function ArrowTurnService:KnitInit()
	print("[ArrowTurnService] Initializing...")
end

function ArrowTurnService:KnitStart()
	print("[ArrowTurnService] Starting...")
	
	-- Connect to matchmaking service
	local ArrowMatchmakingService = Knit.GetService("ArrowMatchmakingService")
	if ArrowMatchmakingService then
		ArrowMatchmakingService.MatchStarted:Connect(function(player1, player2, matchId)
			self:InitializeMatch(player1, player2, matchId)
		end)
	end
	
	-- Connect to projectile service for hit detection
	local ArrowProjectileService = Knit.GetService("ArrowProjectileService")
	if ArrowProjectileService then
		ArrowProjectileService.OnHit:Connect(function(firingPlayer, hitPlayer, hitPart, hitPosition, power)
			local matchId = self:GetPlayerMatchId(firingPlayer)
			if matchId then
				self:OnProjectileHit(matchId, firingPlayer, hitPlayer, hitPart)
			end
		end)
	end
	
	print("[ArrowTurnService] Ready")
end

return ArrowTurnService

