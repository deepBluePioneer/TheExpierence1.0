--[[
	ArrowMatchmakingService
	
	Handles pairing players together for 1v1 arrow duels.
	- Players on the platform at timer start get queued for matchmaking
	- Players are paired when the timer ends
	- Paired players are moved to opposite ends of the baseplate
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local Knit = require(Packages.Knit)
local Signal = require(Packages.Signal)

local ArrowMatchmakingService = Knit.CreateService({
	Name = "ArrowMatchmakingService",
	Client = {
		MatchFound = Knit.CreateSignal(),        -- (opponent, yourSide)
		WaitingForMatch = Knit.CreateSignal(),   -- ()
		NoMatchFound = Knit.CreateSignal(),      -- ()
	},
	
	-- Server-side signals
	PlayersMatched = Signal.new(),    -- (player1, player2)
	MatchStarted = Signal.new(),      -- (player1, player2, matchId)
})

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                              CONFIGURATION                                  ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

local CONFIG = {
	-- Arena settings
	ArenaLength = 200,            -- Total length of arena (X axis)
	ArenaWidth = 30,              -- Width of arena (Z axis)
	ArenaHeight = 3,              -- Thickness of arena platform
	ArenaBaseY = 10,              -- Y position of first arena
	ArenaSpacingY = 50,           -- Vertical spacing between arenas
	
	-- Arena appearance
	ArenaColor = Color3.fromRGB(255, 200, 80),      -- Yellow/gold
	ArenaMaterial = Enum.Material.SmoothPlastic,
	ArenaBorderColor = Color3.fromRGB(40, 40, 40),  -- Dark border
	ArenaBorderThickness = 2,
	
	-- Player platform settings (small squares on each end)
	PlayerPlatformSize = Vector3.new(15, 1, 15),
	PlayerPlatformOffset = 20,    -- Distance from arena edge
	Platform1Color = Color3.fromRGB(80, 150, 255),   -- Blue (left)
	Platform2Color = Color3.fromRGB(255, 80, 80),    -- Red (right)
}

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                              STATE                                          ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

-- Matchmaking queue
local waitingPlayers = {}  -- Players waiting for a match

-- Active matches: matchId -> { player1, player2, platform1, platform2 }
local activeMatches = {}
local matchCounter = 0

-- Player -> matchId lookup
local playerMatches = {}

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         MATCHMAKING LOGIC                                   ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

function ArrowMatchmakingService:AddToQueue(player: Player)
	-- Don't add if already in queue or in a match
	if table.find(waitingPlayers, player) then
		print("[ArrowMatchmaking] " .. player.Name .. " already in queue")
		return false
	end
	
	if playerMatches[player] then
		print("[ArrowMatchmaking] " .. player.Name .. " already in a match")
		return false
	end
	
	table.insert(waitingPlayers, player)
	print("[ArrowMatchmaking] " .. player.Name .. " added to queue. Queue size: " .. #waitingPlayers)
	
	self.Client.WaitingForMatch:Fire(player)
	
	return true
end

function ArrowMatchmakingService:RemoveFromQueue(player: Player)
	local index = table.find(waitingPlayers, player)
	if index then
		table.remove(waitingPlayers, index)
		print("[ArrowMatchmaking] " .. player.Name .. " removed from queue")
		return true
	end
	return false
end

function ArrowMatchmakingService:CreateMatch(player1: Player, player2: Player)
	matchCounter = matchCounter + 1
	local matchId = "Match_" .. matchCounter
	
	-- Create match data
	local matchData = {
		id = matchId,
		matchNumber = matchCounter,
		player1 = player1,
		player2 = player2,
		arena = nil,
		leftPlatform = nil,
		rightPlatform = nil,
		arenaY = nil,
		winner = nil,
	}
	
	activeMatches[matchId] = matchData
	playerMatches[player1] = matchId
	playerMatches[player2] = matchId
	
	print(string.format("[ArrowMatchmaking] ✓ Match created: %s vs %s (ID: %s)", 
		player1.Name, player2.Name, matchId))
	
	-- Fire signals
	self.PlayersMatched:Fire(player1, player2)
	self.Client.MatchFound:Fire(player1, player2, "left")   -- Player1 is on left
	self.Client.MatchFound:Fire(player2, player1, "right")  -- Player2 is on right
	
	return matchData
end

function ArrowMatchmakingService:PairAllWaitingPlayers()
	print("[ArrowMatchmaking] Pairing waiting players... Queue size: " .. #waitingPlayers)
	
	local pairedCount = 0
	local unpairedPlayers = {}
	
	-- Pair players in order
	while #waitingPlayers >= 2 do
		local player1 = table.remove(waitingPlayers, 1)
		local player2 = table.remove(waitingPlayers, 1)
		
		-- Verify both players are still valid
		if player1 and player2 and player1.Parent and player2.Parent then
			local matchData = self:CreateMatch(player1, player2)
			self:SetupDuelPlatforms(matchData)
			pairedCount = pairedCount + 1
		else
			-- Put valid player back in queue
			if player1 and player1.Parent then
				table.insert(unpairedPlayers, player1)
			end
			if player2 and player2.Parent then
				table.insert(unpairedPlayers, player2)
			end
		end
	end
	
	-- Handle remaining unpaired players
	for _, player in ipairs(waitingPlayers) do
		table.insert(unpairedPlayers, player)
	end
	waitingPlayers = {}
	
	-- Notify unpaired players
	for _, player in ipairs(unpairedPlayers) do
		print("[ArrowMatchmaking] " .. player.Name .. " has no opponent")
		self.Client.NoMatchFound:Fire(player)
	end
	
	print(string.format("[ArrowMatchmaking] Pairing complete. %d matches created, %d players unpaired", 
		pairedCount, #unpairedPlayers))
	
	return pairedCount
end

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         ARENA CREATION                                      ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

function ArrowMatchmakingService:CreateArena(matchIndex: number)
	local model = Instance.new("Model")
	model.Name = "Arena_" .. matchIndex
	
	-- Calculate arena Y position (stack arenas vertically)
	local arenaY = CONFIG.ArenaBaseY + (matchIndex - 1) * CONFIG.ArenaSpacingY
	local arenaCenter = Vector3.new(0, arenaY, 0)
	
	-- Main arena platform (long horizontal bar)
	local arenaPlatform = Instance.new("Part")
	arenaPlatform.Name = "ArenaPlatform"
	arenaPlatform.Size = Vector3.new(CONFIG.ArenaLength, CONFIG.ArenaHeight, CONFIG.ArenaWidth)
	arenaPlatform.Position = arenaCenter
	arenaPlatform.Anchored = true
	arenaPlatform.CanCollide = true
	arenaPlatform.Material = CONFIG.ArenaMaterial
	arenaPlatform.Color = CONFIG.ArenaColor
	arenaPlatform.Parent = model
	
	-- Add border/outline effect
	local outline = Instance.new("SelectionBox")
	outline.Adornee = arenaPlatform
	outline.Color3 = CONFIG.ArenaBorderColor
	outline.LineThickness = CONFIG.ArenaBorderThickness
	outline.Parent = arenaPlatform
	
	-- Left player platform (blue square)
	local leftPlatformX = -CONFIG.ArenaLength / 2 + CONFIG.PlayerPlatformOffset
	local leftPlatform = Instance.new("Part")
	leftPlatform.Name = "LeftPlayerPlatform"
	leftPlatform.Size = CONFIG.PlayerPlatformSize
	leftPlatform.Position = Vector3.new(leftPlatformX, arenaY + CONFIG.ArenaHeight / 2 + CONFIG.PlayerPlatformSize.Y / 2, 0)
	leftPlatform.Anchored = true
	leftPlatform.CanCollide = true
	leftPlatform.Material = Enum.Material.Neon
	leftPlatform.Color = CONFIG.Platform1Color
	leftPlatform.Transparency = 0.2
	leftPlatform.Parent = model
	
	-- Left platform glow
	local leftLight = Instance.new("PointLight")
	leftLight.Color = CONFIG.Platform1Color
	leftLight.Brightness = 2
	leftLight.Range = 15
	leftLight.Parent = leftPlatform
	
	-- Right player platform (red square)
	local rightPlatformX = CONFIG.ArenaLength / 2 - CONFIG.PlayerPlatformOffset
	local rightPlatform = Instance.new("Part")
	rightPlatform.Name = "RightPlayerPlatform"
	rightPlatform.Size = CONFIG.PlayerPlatformSize
	rightPlatform.Position = Vector3.new(rightPlatformX, arenaY + CONFIG.ArenaHeight / 2 + CONFIG.PlayerPlatformSize.Y / 2, 0)
	rightPlatform.Anchored = true
	rightPlatform.CanCollide = true
	rightPlatform.Material = Enum.Material.Neon
	rightPlatform.Color = CONFIG.Platform2Color
	rightPlatform.Transparency = 0.2
	rightPlatform.Parent = model
	
	-- Right platform glow
	local rightLight = Instance.new("PointLight")
	rightLight.Color = CONFIG.Platform2Color
	rightLight.Brightness = 2
	rightLight.Range = 15
	rightLight.Parent = rightPlatform
	
	model.PrimaryPart = arenaPlatform
	
	-- Parent to workspace
	local folder = workspace:FindFirstChild("Arenas")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "Arenas"
		folder.Parent = workspace
	end
	model.Parent = folder
	
	print(string.format("[ArrowMatchmaking] ✓ Created Arena %d at Y: %.0f", matchIndex, arenaY))
	
	return model, leftPlatform, rightPlatform, arenaY
end

function ArrowMatchmakingService:SetupDuelPlatforms(matchData)
	-- Create a new arena for this match
	local arena, leftPlatform, rightPlatform, arenaY = self:CreateArena(matchCounter)
	
	matchData.arena = arena
	matchData.leftPlatform = leftPlatform
	matchData.rightPlatform = rightPlatform
	matchData.arenaY = arenaY
	
	-- Teleport players to their platforms
	self:TeleportPlayerToPlatform(matchData.player1, leftPlatform, "left")
	self:TeleportPlayerToPlatform(matchData.player2, rightPlatform, "right")
	
	-- Notify turn service that match is ready
	self.MatchStarted:Fire(matchData.player1, matchData.player2, matchData.id)
	
	print(string.format("[ArrowMatchmaking] ✓ Arena created for %s vs %s", 
		matchData.player1.Name, matchData.player2.Name))
end

function ArrowMatchmakingService:TeleportPlayerToPlatform(player: Player, platform: BasePart, side: string)
	local character = player.Character
	if not character then return end
	
	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if not rootPart then return end
	
	-- Position player on top of their platform
	local platformTop = platform.Position + Vector3.new(0, CONFIG.PlayerPlatformSize.Y / 2 + 3, 0)
	
	-- Face the opponent (left faces right +X, right faces left -X)
	local facingAngle = side == "left" and 0 or math.rad(180)
	rootPart.CFrame = CFrame.new(platformTop) * CFrame.Angles(0, facingAngle, 0)
	
	print(string.format("[ArrowMatchmaking] Teleported %s to %s platform", player.Name, side))
end

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         MATCH MANAGEMENT                                    ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

function ArrowMatchmakingService:GetPlayerMatch(player: Player)
	local matchId = playerMatches[player]
	if matchId then
		return activeMatches[matchId]
	end
	return nil
end

function ArrowMatchmakingService:GetOpponent(player: Player)
	local match = self:GetPlayerMatch(player)
	if match then
		if match.player1 == player then
			return match.player2
		else
			return match.player1
		end
	end
	return nil
end

function ArrowMatchmakingService:EndMatch(matchId: string, winner: Player?)
	local matchData = activeMatches[matchId]
	if not matchData then return end
	
	matchData.winner = winner
	
	-- Clean up arena after a delay (let players see the result)
	task.delay(5, function()
		if matchData.arena then
			matchData.arena:Destroy()
		end
	end)
	
	-- Remove player references
	playerMatches[matchData.player1] = nil
	playerMatches[matchData.player2] = nil
	
	-- Remove match
	activeMatches[matchId] = nil
	
	print(string.format("[ArrowMatchmaking] Match %s ended. Winner: %s", 
		matchId, winner and winner.Name or "None"))
end

function ArrowMatchmakingService:GetConfig()
	return CONFIG
end

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         KNIT LIFECYCLE                                      ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

function ArrowMatchmakingService:KnitInit()
	print("[ArrowMatchmakingService] Initializing...")
	
	-- Clean up when players leave
	Players.PlayerRemoving:Connect(function(player)
		self:RemoveFromQueue(player)
		
		-- End any active match
		local matchId = playerMatches[player]
		if matchId then
			local match = activeMatches[matchId]
			local opponent = self:GetOpponent(player)
			self:EndMatch(matchId, opponent)  -- Opponent wins by default
		end
	end)
end

function ArrowMatchmakingService:KnitStart()
	print("[ArrowMatchmakingService] Starting...")
	
	-- Connect to timer service - when timer ends, pair all waiting players
	local ArrowTimerService = Knit.GetService("ArrowTimerService")
	if ArrowTimerService then
		ArrowTimerService.TimerEndedServer:Connect(function()
			print("[ArrowMatchmaking] Timer ended - pairing players!")
			self:PairAllWaitingPlayers()
		end)
	end
	
	-- Add players to queue when they join the main platform area
	-- For now, auto-add all players when they spawn
	Players.PlayerAdded:Connect(function(player)
		player.CharacterAdded:Connect(function()
			task.wait(2)  -- Wait for character to fully load
			self:AddToQueue(player)
		end)
	end)
	
	-- Add existing players
	for _, player in ipairs(Players:GetPlayers()) do
		if player.Character then
			self:AddToQueue(player)
		end
	end
	
	print("[ArrowMatchmakingService] Ready")
end

return ArrowMatchmakingService

