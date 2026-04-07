local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Packages = ReplicatedStorage.Packages
local CustomPackages = ReplicatedStorage:WaitForChild("CustomPackages")
local Knit = require(Packages.Knit)
local Signal = require(Packages.Signal)
local Timer = require(Packages.timer)
local Replica = CustomPackages.Replica
local ReplicaService = require(Replica.ReplicaService)

local MIN_PLAYERS = 1
local COUNTDOWN_TIME = 5
local ROUND_TIME = 120
local SNAKE_SPAWN_DELAY = 2
local RESULTS_TIME = 10

local PHASES = {
	WAITING = "WAITING",
	COUNTDOWN = "COUNTDOWN",
	SNAKE_SPAWNING = "SNAKE_SPAWNING",
	ROUND_ACTIVE = "ROUND_ACTIVE",
	ROUND_OVER = "ROUND_OVER",
	RESULTS = "RESULTS",
}

local GraviBowMatchService = Knit.CreateService({
	Name = "GraviBowMatchService",
	Client = {},

	PhaseChanged = Signal.new(),

	_phase = PHASES.WAITING,
	_matchReplica = nil,
	_timer = nil,
	_timeRemaining = 0,
	_snakePlayers = {},
	_killDebounce = {},
})

function GraviBowMatchService:KnitInit() end

function GraviBowMatchService:KnitStart()
	self:_initReplica()

	self._playerService = Knit.GetService("GraviBowPlayerService")
	self._snakeService = Knit.GetService("GraviBowSnakeService")

	Players.PlayerAdded:Connect(function(player)
		self:_addPlayerScore(player)
		self:_checkPlayerCount()
	end)

	Players.PlayerRemoving:Connect(function(player)
		self:_removePlayerScore(player)
		self._snakePlayers[player] = nil
		self._killDebounce[player] = nil
		task.defer(function()
			self:_checkPlayerCount()
		end)
	end)

	for _, player in ipairs(Players:GetPlayers()) do
		self:_addPlayerScore(player)
	end

	self:_checkPlayerCount()
end

function GraviBowMatchService:_initReplica()
	self._matchReplica = ReplicaService.NewReplica({
		ClassToken = ReplicaService.NewClassToken("GraviBowMatchState"),
		Data = {
			phase = PHASES.WAITING,
			timeRemaining = 0,
			scores = {},
			snakePlayers = {},
			firstSnakeId = 0,
		},
		Replication = "All",
	})
end

function GraviBowMatchService:GetPhase()
	return self._phase
end

function GraviBowMatchService:IsSnakePlayer(player)
	return self._snakePlayers[player] == true
end

function GraviBowMatchService:IsRoundActive()
	return self._phase == PHASES.ROUND_ACTIVE
end

function GraviBowMatchService:ConvertToSnake(player)
	if self._phase ~= PHASES.ROUND_ACTIVE then return end
	if self._snakePlayers[player] then return end

	if self._killDebounce[player] then return end
	self._killDebounce[player] = true

	self._snakePlayers[player] = true
	local key = tostring(player.UserId)
	self._matchReplica:SetValue({"snakePlayers", key}, true)

	local scores = self._matchReplica.Data.scores
	if scores[key] then
		self._matchReplica:SetValue({"scores", key, "deaths"}, (scores[key].deaths or 0) + 1)
	end

	local character = player.Character
	if character then
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if humanoid and humanoid.Health > 0 then
			humanoid.Health = 0
		end
	end

	print("[GraviBowMatchService]", player.Name, "converted to snake")

	task.delay(0.5, function()
		self._killDebounce[player] = nil
	end)

	if self:_allPlayersAreSnakes() then
		self:_stopTimer()
		self:_startRoundOver()
	end
end

function GraviBowMatchService:EnsureSnakeOnDeath(player)
	-- Any in-round phase (not lobby): deaths must flip the victim to snake so the next
	-- LoadCharacter respawn runs BuildSnakeForPlayer. ROUND_ACTIVE-only missed COUNTDOWN / SNAKE_SPAWNING.
	if self._phase == PHASES.WAITING then return end
	if self._snakePlayers[player] then return end

	self._snakePlayers[player] = true
	local key = tostring(player.UserId)
	self._matchReplica:SetValue({"snakePlayers", key}, true)

	local scores = self._matchReplica.Data.scores
	if scores[key] then
		self._matchReplica:SetValue({"scores", key, "deaths"}, (scores[key].deaths or 0) + 1)
	end

	if self:_allPlayersAreSnakes() then
		self:_stopTimer()
		self:_startRoundOver()
	end
end

function GraviBowMatchService:_allPlayersAreSnakes()
	for _, player in ipairs(Players:GetPlayers()) do
		if not self._snakePlayers[player] then
			return false
		end
	end
	return true
end

function GraviBowMatchService:_addPlayerScore(player)
	local key = tostring(player.UserId)
	self._matchReplica:SetValue({"scores", key}, {
		name = player.Name,
		kills = 0,
		deaths = 0,
		survived = false,
	})
end

function GraviBowMatchService:_removePlayerScore(player)
	local key = tostring(player.UserId)
	self._matchReplica:SetValue({"scores", key}, nil)
	self._matchReplica:SetValue({"snakePlayers", key}, nil)
end

function GraviBowMatchService:_resetRound()
	self._snakePlayers = {}
	self._killDebounce = {}
	self._matchReplica:SetValue({"snakePlayers"}, {})
	self._matchReplica:SetValue({"firstSnakeId"}, 0)
	for _, player in ipairs(Players:GetPlayers()) do
		self:_addPlayerScore(player)
	end
end

function GraviBowMatchService:_setPhase(phase)
	self._phase = phase
	self._matchReplica:SetValue({"phase"}, phase)
	self.PhaseChanged:Fire(phase)
	print("[GraviBowMatchService] Phase:", phase)
end

function GraviBowMatchService:_setTimeRemaining(t)
	self._timeRemaining = t
	self._matchReplica:SetValue({"timeRemaining"}, t)
end

function GraviBowMatchService:_stopTimer()
	if self._timer then
		if self._timer:IsRunning() then
			self._timer:Stop()
		end
		self._timer:Destroy()
		self._timer = nil
	end
end

function GraviBowMatchService:_checkPlayerCount()
	if self._phase ~= PHASES.WAITING then return end

	local playerCount = #Players:GetPlayers()
	if playerCount >= MIN_PLAYERS then
		self:_startCountdown()
	end
end

function GraviBowMatchService:_startCountdown()
	self:_resetRound()
	self:_setPhase(PHASES.COUNTDOWN)
	self:_setTimeRemaining(COUNTDOWN_TIME)

	local players = Players:GetPlayers()
	if #players == 0 then
		self:_setPhase(PHASES.WAITING)
		return
	end

	local chosenSnake = players[math.random(1, #players)]
	self._snakePlayers[chosenSnake] = true
	local key = tostring(chosenSnake.UserId)
	self._matchReplica:SetValue({"snakePlayers", key}, true)
	self._matchReplica:SetValue({"firstSnakeId"}, chosenSnake.UserId)

	print("[GraviBowMatchService] First snake:", chosenSnake.Name)

	self:_stopTimer()
	self._timer = Timer.new(1)
	self._timer.Tick:Connect(function()
		self._timeRemaining -= 1
		self:_setTimeRemaining(self._timeRemaining)

		if self._timeRemaining <= 0 then
			self:_stopTimer()
			self:_startSnakeSpawning()
		end
	end)
	self._timer:Start()
end

function GraviBowMatchService:_startSnakeSpawning()
	self:_setPhase(PHASES.SNAKE_SPAWNING)
	self:_setTimeRemaining(0)

	for player, isSnake in pairs(self._snakePlayers) do
		if isSnake and player.Parent then
			self._snakeService:BuildSnakeForPlayer(player)
			self._playerService:HideAvatar(player)
		end
	end

	task.delay(SNAKE_SPAWN_DELAY, function()
		self:_startRoundActive()
	end)
end

function GraviBowMatchService:_startRoundActive()
	self:_setPhase(PHASES.ROUND_ACTIVE)
	self:_setTimeRemaining(ROUND_TIME)

	self:_stopTimer()
	self._timer = Timer.new(1)
	self._timer.Tick:Connect(function()
		self._timeRemaining -= 1
		self:_setTimeRemaining(self._timeRemaining)

		if self._timeRemaining <= 0 then
			self:_stopTimer()
			self:_startRoundOver()
		end
	end)
	self._timer:Start()
end

function GraviBowMatchService:_startRoundOver()
	self:_setPhase(PHASES.ROUND_OVER)
	self:_setTimeRemaining(0)

	for _, player in ipairs(Players:GetPlayers()) do
		if not self._snakePlayers[player] then
			local key = tostring(player.UserId)
			self._matchReplica:SetValue({"scores", key, "survived"}, true)
		end
	end

	task.delay(2, function()
		self:_startResults()
	end)
end

function GraviBowMatchService:_startResults()
	self:_setPhase(PHASES.RESULTS)
	self:_setTimeRemaining(RESULTS_TIME)

	self:_stopTimer()
	self._timer = Timer.new(1)
	self._timer.Tick:Connect(function()
		self._timeRemaining -= 1
		self:_setTimeRemaining(self._timeRemaining)

		if self._timeRemaining <= 0 then
			self:_stopTimer()
			self:_returnToWaiting()
		end
	end)
	self._timer:Start()
end

function GraviBowMatchService:_returnToWaiting()
	for player, _ in pairs(self._snakePlayers) do
		if player.Parent then
			self._snakeService:DestroySnakeForPlayer(player)
		end
	end

	self._snakePlayers = {}
	self._killDebounce = {}
	self._matchReplica:SetValue({"snakePlayers"}, {})
	self._matchReplica:SetValue({"firstSnakeId"}, 0)

	self:_setPhase(PHASES.WAITING)
	self:_setTimeRemaining(0)

	for _, player in ipairs(Players:GetPlayers()) do
		self._playerService:ShowAvatar(player)
	end

	task.defer(function()
		self:_checkPlayerCount()
	end)
end

return GraviBowMatchService
