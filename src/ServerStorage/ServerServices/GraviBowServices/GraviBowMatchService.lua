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
local HUB_COUNTDOWN_TIME = 60
local GAME_TIME = 300
local RESULTS_TIME = 10

local PHASES = {
	HUB_WAITING = "HUB_WAITING",
	HUB_COUNTDOWN = "HUB_COUNTDOWN",
	TELEPORTING = "TELEPORTING",
	GAME_ACTIVE = "GAME_ACTIVE",
	GAME_OVER = "GAME_OVER",
	RESULTS = "RESULTS",
}

local GraviBowMatchService = Knit.CreateService({
	Name = "GraviBowMatchService",
	Client = {},

	PhaseChanged = Signal.new(),

	_phase = PHASES.HUB_WAITING,
	_matchReplica = nil,
	_timer = nil,
	_timeRemaining = 0,
})

function GraviBowMatchService:KnitInit() end

function GraviBowMatchService:KnitStart()
	self:_initReplica()

	self._playerService = Knit.GetService("GraviBowPlayerService")

	Players.PlayerAdded:Connect(function(player)
		self:_onPlayerCountChanged(player, true)
	end)

	Players.PlayerRemoving:Connect(function(player)
		self:_removePlayerScore(player)
		self:_onPlayerCountChanged(player, false)
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
			phase = PHASES.HUB_WAITING,
			timeRemaining = 0,
			scores = {},
		},
		Replication = "All",
	})
end

function GraviBowMatchService:GetPhase()
	return self._phase
end

function GraviBowMatchService:RecordKill(killer, victim)
	if self._phase ~= PHASES.GAME_ACTIVE then return end

	local killerKey = tostring(killer.UserId)
	local victimKey = tostring(victim.UserId)

	local scores = self._matchReplica.Data.scores

	if scores[killerKey] then
		self._matchReplica:SetValue({"scores", killerKey, "kills"}, scores[killerKey].kills + 1)
	end
	if scores[victimKey] then
		self._matchReplica:SetValue({"scores", victimKey, "deaths"}, scores[victimKey].deaths + 1)
	end
end

function GraviBowMatchService:RecordHit(shooter)
	if self._phase ~= PHASES.GAME_ACTIVE then return end

	local key = tostring(shooter.UserId)
	local scores = self._matchReplica.Data.scores

	if scores[key] then
		self._matchReplica:SetValue({"scores", key, "hits"}, scores[key].hits + 1)
	end
end

function GraviBowMatchService:_addPlayerScore(player)
	local key = tostring(player.UserId)
	self._matchReplica:SetValue({"scores", key}, {
		name = player.Name,
		kills = 0,
		deaths = 0,
		hits = 0,
	})
end

function GraviBowMatchService:_removePlayerScore(player)
	local key = tostring(player.UserId)
	self._matchReplica:SetValue({"scores", key}, nil)
end

function GraviBowMatchService:_resetAllScores()
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

function GraviBowMatchService:_onPlayerCountChanged(player, joined)
	if joined then
		self:_addPlayerScore(player)
	end
	task.defer(function()
		self:_checkPlayerCount()
	end)
end

function GraviBowMatchService:_isGameInSession()
	return self._phase == PHASES.TELEPORTING
		or self._phase == PHASES.GAME_ACTIVE
		or self._phase == PHASES.GAME_OVER
		or self._phase == PHASES.RESULTS
end

function GraviBowMatchService:_checkPlayerCount()
	return
end

function GraviBowMatchService:_startHubCountdown()
	self:_setPhase(PHASES.HUB_COUNTDOWN)
	self:_setTimeRemaining(HUB_COUNTDOWN_TIME)

	self:_stopTimer()
	self._timer = Timer.new(1)
	self._timer.Tick:Connect(function()
		self._timeRemaining -= 1
		self:_setTimeRemaining(self._timeRemaining)

		if self._timeRemaining <= 0 then
			self:_stopTimer()
			self:_startTeleporting()
		end
	end)
	self._timer:Start()
end

function GraviBowMatchService:_startTeleporting()
	self:_setPhase(PHASES.TELEPORTING)
	self:_setTimeRemaining(0)

	self:_resetAllScores()

	local gamePlanets = self._playerService:GetGamePlanets()
	local players = Players:GetPlayers()

	if #gamePlanets > 0 and #players > 0 then
		for i, player in ipairs(players) do
			local planetIndex = ((i - 1) % #gamePlanets) + 1
			local planet = gamePlanets[planetIndex]
			self._playerService:TeleportPlayerToPlanet(player, planet)
		end
	end

	task.delay(1, function()
		self:_startGameActive()
	end)
end

function GraviBowMatchService:_startGameActive()
	self:_setPhase(PHASES.GAME_ACTIVE)
	self:_setTimeRemaining(GAME_TIME)

	self:_stopTimer()
	self._timer = Timer.new(1)
	self._timer.Tick:Connect(function()
		self._timeRemaining -= 1
		self:_setTimeRemaining(self._timeRemaining)

		if self._timeRemaining <= 0 then
			self:_stopTimer()
			self:_startGameOver()
		end
	end)
	self._timer:Start()
end

function GraviBowMatchService:_startGameOver()
	self:_setPhase(PHASES.GAME_OVER)
	self:_setTimeRemaining(0)

	task.delay(1, function()
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
			self:_returnToHub()
		end
	end)
	self._timer:Start()
end

function GraviBowMatchService:_returnToHub()
	for _, player in ipairs(Players:GetPlayers()) do
		self._playerService:TeleportPlayerToHub(player)
	end

	self:_setPhase(PHASES.HUB_WAITING)
	self:_setTimeRemaining(0)

	task.defer(function()
		self:_checkPlayerCount()
	end)
end

return GraviBowMatchService
