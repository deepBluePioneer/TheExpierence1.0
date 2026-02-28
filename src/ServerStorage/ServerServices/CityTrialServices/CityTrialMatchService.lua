local Players = game:GetService("Players")
local TeleportService = game:GetService("TeleportService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Packages = ReplicatedStorage.Packages
local Knit = require(Packages.Knit)
local Signal = require(Packages.Signal)
local Trove = require(Packages.Trove)
local Timer = require(Packages.timer)

local CustomPackages = ReplicatedStorage.CustomPackages
local ReplicaService = require(CustomPackages.Replica.ReplicaService)

local GameConfig = require(ReplicatedStorage.Source.GameConfig)
local TeleportConfig = require(ReplicatedStorage.Source.TeleportConfig)
local Analytics = require(ReplicatedStorage.Source.Analytics)

local PHASE_LOBBY = "LOBBY"
local PHASE_COUNTDOWN = "COUNTDOWN"
local PHASE_IN_PROGRESS = "IN_PROGRESS"
local PHASE_ENDED = "ENDED"
local PHASE_RESULTS = "RESULTS"

local CityTrialMatchService = Knit.CreateService {
	Name = "CityTrialMatchService",
	Client = {},

	_phase = PHASE_LOBBY,
	_trove = nil,
	_matchReplica = nil,

	_joinedPlayers = {},
	_readyPlayers = {},
	_expectedPlayerCount = 0,

	_joinGraceTimer = nil,
	_readyGraceTimer = nil,
	_countdownTimer = nil,
	_matchTimer = nil,
	_resultsTimer = nil,

	_matchStartTime = 0,
	_matchEndTime = 0,

	PhaseChanged = Signal.new(),
	MatchStarted = Signal.new(),
	MatchEnded = Signal.new(),
}

local MatchReplicaClassToken = ReplicaService.NewClassToken("MatchState")

function CityTrialMatchService:KnitInit()
	self._trove = Trove.new()
end

function CityTrialMatchService:KnitStart()
	self:_initMatch()

	self._trove:Add(Players.PlayerRemoving:Connect(function(player)
		self:_onPlayerRemoving(player)
	end), "Disconnect")
end

function CityTrialMatchService:_initMatch()
	local teleportData = self:_readTeleportData()

	self._expectedPlayerCount = teleportData.expectedCount or GameConfig.maxPlayers

	self._matchReplica = ReplicaService.NewReplica({
		ClassToken = MatchReplicaClassToken,
		Tags = {},
		Data = {
			phase = PHASE_LOBBY,
			matchTimeRemaining = GameConfig.matchDurationSeconds,
			countdownRemaining = 0,
			resultsTimeRemaining = 0,
			playerCount = 0,
			readyCount = 0,
		},
		Replication = "All",
	})

	self._trove:Add(function()
		if self._matchReplica then
			self._matchReplica:Destroy()
			self._matchReplica = nil
		end
	end)

	self:_setPhase(PHASE_LOBBY)
	self:_startJoinGraceTimer()

	print("[CityTrialMatchService] Match initialized, waiting for players (expected: " .. self._expectedPlayerCount .. ")")
end

function CityTrialMatchService:_readTeleportData()
	local data = {
		expectedCount = GameConfig.maxPlayers,
		seed = 0,
		teleporterId = nil,
	}

	for _, player in ipairs(Players:GetPlayers()) do
		local joinData = player:GetJoinData()
		local teleportData = joinData and joinData.TeleportData
		if teleportData and type(teleportData) == "table" then
			data.expectedCount = teleportData.expectedCount or data.expectedCount
			data.seed = teleportData.seed or data.seed
			data.teleporterId = teleportData.teleporterId or data.teleporterId
			break
		end
	end

	return data
end

----------------------------------------------------------------
-- Phase management
----------------------------------------------------------------

function CityTrialMatchService:_setPhase(phase)
	local oldPhase = self._phase
	self._phase = phase

	if self._matchReplica then
		self._matchReplica:SetValue({ "phase" }, phase)
	end

	print("[CityTrialMatchService] Phase: " .. oldPhase .. " -> " .. phase)
	self.PhaseChanged:Fire(phase, oldPhase)
end

function CityTrialMatchService:GetPhase()
	return self._phase
end

----------------------------------------------------------------
-- Join and ready tracking
----------------------------------------------------------------

function CityTrialMatchService:ReportPlayerJoined(player)
	if self._joinedPlayers[player] then return end
	self._joinedPlayers[player] = true

	local count = self:_getJoinedCount()
	if self._matchReplica then
		self._matchReplica:SetValue({ "playerCount" }, count)
	end

	print("[CityTrialMatchService] Player joined: " .. player.Name .. " (" .. count .. "/" .. self._expectedPlayerCount .. ")")

	if self._phase == PHASE_LOBBY then
		if count >= self._expectedPlayerCount then
			self:_stopJoinGraceTimer()
			self:_startReadyGraceTimer()
		end
	end
end

function CityTrialMatchService:ReportPlayerReady(player)
	if self._readyPlayers[player] then return end
	if not self._joinedPlayers[player] then return end

	self._readyPlayers[player] = true

	local readyCount = self:_getReadyCount()
	local joinedCount = self:_getJoinedCount()

	if self._matchReplica then
		self._matchReplica:SetValue({ "readyCount" }, readyCount)
	end

	print("[CityTrialMatchService] Player ready: " .. player.Name .. " (" .. readyCount .. "/" .. joinedCount .. ")")

	if self._phase == PHASE_LOBBY and readyCount >= joinedCount and joinedCount >= 1 then
		self:_stopJoinGraceTimer()
		self:_stopReadyGraceTimer()
		self:_beginStartCountdown()
	end
end

function CityTrialMatchService:_onPlayerRemoving(player)
	self._joinedPlayers[player] = nil
	self._readyPlayers[player] = nil

	local count = self:_getJoinedCount()
	if self._matchReplica then
		self._matchReplica:SetValue({ "playerCount" }, count)
		self._matchReplica:SetValue({ "readyCount" }, self:_getReadyCount())
	end

	print("[CityTrialMatchService] Player left: " .. player.Name .. " (" .. count .. " remaining)")

	if count == 0 and self._phase ~= PHASE_RESULTS then
		print("[CityTrialMatchService] All players left, cleaning up")
		self:_cleanup()
		return
	end

	if self._phase == PHASE_COUNTDOWN and count < 1 then
		self:_cancelCountdown("All players left")
	end
end

function CityTrialMatchService:_getJoinedCount()
	local count = 0
	for player, _ in pairs(self._joinedPlayers) do
		if player:IsDescendantOf(Players) then
			count = count + 1
		end
	end
	return count
end

function CityTrialMatchService:_getReadyCount()
	local count = 0
	for player, _ in pairs(self._readyPlayers) do
		if player:IsDescendantOf(Players) then
			count = count + 1
		end
	end
	return count
end

----------------------------------------------------------------
-- Join grace timer
----------------------------------------------------------------

function CityTrialMatchService:_startJoinGraceTimer()
	self:_stopJoinGraceTimer()

	local elapsed = 0
	local timer = Timer.new(1)
	timer.Tick:Connect(function()
		elapsed = elapsed + 1
		if elapsed >= GameConfig.joinGraceSeconds then
			timer:Stop()
			timer:Destroy()
			self._joinGraceTimer = nil
			self:_onJoinGraceExpired()
		end
	end)
	timer:Start()
	self._joinGraceTimer = timer

	print("[CityTrialMatchService] Join grace timer started (" .. GameConfig.joinGraceSeconds .. "s)")
end

function CityTrialMatchService:_stopJoinGraceTimer()
	if self._joinGraceTimer then
		self._joinGraceTimer:Stop()
		self._joinGraceTimer:Destroy()
		self._joinGraceTimer = nil
	end
end

function CityTrialMatchService:_onJoinGraceExpired()
	print("[CityTrialMatchService] Join grace timer expired")
	local joinedCount = self:_getJoinedCount()

	if joinedCount < 1 then
		print("[CityTrialMatchService] No players joined, cancelling match")
		self:_teleportAllToHub("No players arrived")
		return
	end

	self:_startReadyGraceTimer()
end

----------------------------------------------------------------
-- Ready grace timer
----------------------------------------------------------------

function CityTrialMatchService:_startReadyGraceTimer()
	self:_stopReadyGraceTimer()

	local readyCount = self:_getReadyCount()
	local joinedCount = self:_getJoinedCount()

	if readyCount >= joinedCount and joinedCount >= 1 then
		self:_beginStartCountdown()
		return
	end

	local elapsed = 0
	local timer = Timer.new(1)
	timer.Tick:Connect(function()
		elapsed = elapsed + 1
		if elapsed >= GameConfig.readyGraceSeconds then
			timer:Stop()
			timer:Destroy()
			self._readyGraceTimer = nil
			self:_onReadyGraceExpired()
		end
	end)
	timer:Start()
	self._readyGraceTimer = timer

	print("[CityTrialMatchService] Ready grace timer started (" .. GameConfig.readyGraceSeconds .. "s)")
end

function CityTrialMatchService:_stopReadyGraceTimer()
	if self._readyGraceTimer then
		self._readyGraceTimer:Stop()
		self._readyGraceTimer:Destroy()
		self._readyGraceTimer = nil
	end
end

function CityTrialMatchService:_onReadyGraceExpired()
	print("[CityTrialMatchService] Ready grace timer expired")
	local joinedCount = self:_getJoinedCount()

	if joinedCount >= 1 then
		self:_beginStartCountdown()
	else
		self:_teleportAllToHub("Not enough players")
	end
end

----------------------------------------------------------------
-- Start countdown
----------------------------------------------------------------

function CityTrialMatchService:_beginStartCountdown()
	if self._phase ~= PHASE_LOBBY then return end

	self:_stopJoinGraceTimer()
	self:_stopReadyGraceTimer()

	self:_setPhase(PHASE_COUNTDOWN)

	local remaining = GameConfig.startCountdownSeconds
	if self._matchReplica then
		self._matchReplica:SetValue({ "countdownRemaining" }, remaining)
	end

	print("[CityTrialMatchService] Start countdown: " .. remaining .. "s")

	local timer = Timer.new(1)
	timer.Tick:Connect(function()
		remaining = remaining - 1
		if self._matchReplica then
			self._matchReplica:SetValue({ "countdownRemaining" }, math.max(0, remaining))
		end

		if remaining <= 0 then
			timer:Stop()
			timer:Destroy()
			self._countdownTimer = nil
			self:_startMatch()
		end
	end)
	timer:Start()
	self._countdownTimer = timer
end

function CityTrialMatchService:_cancelCountdown(reason)
	if self._countdownTimer then
		self._countdownTimer:Stop()
		self._countdownTimer:Destroy()
		self._countdownTimer = nil
	end

	warn("[CityTrialMatchService] Countdown cancelled: " .. (reason or "unknown"))
	self:_setPhase(PHASE_LOBBY)
end

----------------------------------------------------------------
-- Match in progress
----------------------------------------------------------------

function CityTrialMatchService:_startMatch()
	self:_setPhase(PHASE_IN_PROGRESS)
	self._matchStartTime = os.clock()

	local remaining = GameConfig.matchDurationSeconds
	if self._matchReplica then
		self._matchReplica:SetValue({ "matchTimeRemaining" }, remaining)
	end

	print("[CityTrialMatchService] Match started! Duration: " .. remaining .. "s")
	self.MatchStarted:Fire()

	local CityTrialPlayerService = Knit.GetService("CityTrialPlayerService")
	for _, player in ipairs(CityTrialPlayerService:GetAllLoadedPlayers()) do
		Analytics.Funnel.MatchStarted(player)
	end

	local timer = Timer.new(1)
	timer.Tick:Connect(function()
		remaining = remaining - 1
		if self._matchReplica then
			self._matchReplica:SetValue({ "matchTimeRemaining" }, math.max(0, remaining))
		end

		if remaining <= 0 then
			timer:Stop()
			timer:Destroy()
			self._matchTimer = nil
			self:_endMatch()
		end
	end)
	timer:Start()
	self._matchTimer = timer
end

----------------------------------------------------------------
-- End of match
----------------------------------------------------------------

function CityTrialMatchService:_endMatch()
	if self._phase ~= PHASE_IN_PROGRESS then return end

	self._matchEndTime = os.clock()
	self:_setPhase(PHASE_ENDED)

	print("[CityTrialMatchService] Match ended, computing results...")
	self.MatchEnded:Fire()

	self:_computeAndSaveResults()

	task.delay(0.5, function()
		self:_beginResultsCountdown()
	end)
end

function CityTrialMatchService:_computeAndSaveResults()
	local CityTrialPlayerService = Knit.GetService("CityTrialPlayerService")

	for _, player in ipairs(CityTrialPlayerService:GetAllLoadedPlayers()) do
		local session = CityTrialPlayerService:GetSessionData(player)
		local profileData = CityTrialPlayerService:GetProfileData(player)
		if not session or not profileData then continue end

		local rewards = GameConfig.rewards
		local totalPatches = session.totalPatchesCollected or 0
		local deaths = session.deaths or 0
		local events = session.eventsSurvived or 0
		local matchDuration = self._matchEndTime - (session.joinTime or self._matchStartTime)
		local survivalFraction = math.clamp(matchDuration / GameConfig.matchDurationSeconds, 0, 1)

		local earnedCurrency = rewards.baseCurrency
			+ (totalPatches * rewards.patchCurrencyMultiplier)
			+ math.floor(survivalFraction * rewards.survivalCurrencyMax)
			+ (events * rewards.eventCurrency)

		local earnedXP = rewards.baseXP
			+ (totalPatches * rewards.patchXPMultiplier)
			+ math.floor(survivalFraction * rewards.survivalXPMax)
			+ (events * rewards.eventXP)

		local deathPenalty = math.floor(deaths * rewards.deathPenaltyPercent * earnedCurrency)
		earnedCurrency = math.max(0, earnedCurrency - deathPenalty)

		local deathXPPenalty = math.floor(deaths * rewards.deathPenaltyPercent * earnedXP)
		earnedXP = math.max(0, earnedXP - deathXPPenalty)

		profileData.currency = (profileData.currency or 0) + earnedCurrency
		profileData.xp = (profileData.xp or 0) + earnedXP

		local oldLevel = profileData.level or 1
		local ProfileConfig = require(ReplicatedStorage.Source.ProfileConfig)
		while ProfileConfig.xpForLevel(oldLevel + 1) <= profileData.xp do
			oldLevel = oldLevel + 1
		end
		profileData.level = oldLevel

		session.earnedCurrency = earnedCurrency
		session.earnedXP = earnedXP
		session.finalLevel = oldLevel

		Analytics.MatchCompleted(player, matchDuration, totalPatches, deaths)
		Analytics.RewardsEarned(player, earnedCurrency, earnedXP)
		Analytics.Funnel.MatchCompleted(player)
		Analytics.Funnel.MatchRewardsEarned(player)

		local replica = CityTrialPlayerService:GetReplica(player)
		if replica then
			replica:SetValue({ "earnedCurrency" }, earnedCurrency)
			replica:SetValue({ "earnedXP" }, earnedXP)
			replica:SetValue({ "totalPatches" }, totalPatches)
			replica:SetValue({ "deaths" }, deaths)
		end

		print("[CityTrialMatchService] " .. player.Name .. " earned " .. earnedCurrency .. " currency, " .. earnedXP .. " XP")
	end
end

----------------------------------------------------------------
-- Results countdown
----------------------------------------------------------------

function CityTrialMatchService:_beginResultsCountdown()
	self:_setPhase(PHASE_RESULTS)

	local remaining = GameConfig.resultsDurationSeconds
	if self._matchReplica then
		self._matchReplica:SetValue({ "resultsTimeRemaining" }, remaining)
	end

	print("[CityTrialMatchService] Results screen: " .. remaining .. "s")

	local timer = Timer.new(1)
	timer.Tick:Connect(function()
		remaining = remaining - 1
		if self._matchReplica then
			self._matchReplica:SetValue({ "resultsTimeRemaining" }, math.max(0, remaining))
		end

		if remaining <= 0 then
			timer:Stop()
			timer:Destroy()
			self._resultsTimer = nil
			self:_teleportAllToHub()
		end
	end)
	timer:Start()
	self._resultsTimer = timer
end

----------------------------------------------------------------
-- Teleport back to hub
----------------------------------------------------------------

function CityTrialMatchService:_teleportAllToHub(reason)
	local activePlayers = {}
	for _, player in ipairs(Players:GetPlayers()) do
		table.insert(activePlayers, player)
	end

	if #activePlayers == 0 then
		print("[CityTrialMatchService] No players to teleport back")
		self:_cleanup()
		return
	end

	local teleportData = {
		returnedFromCityTrial = true,
		reason = reason,
	}

	local teleportOptions = Instance.new("TeleportOptions")
	teleportOptions:SetTeleportData(teleportData)

	print("[CityTrialMatchService] Teleporting " .. #activePlayers .. " players back to hub")

	for _, player in ipairs(activePlayers) do
		Analytics.Funnel.MatchReturnedToHub(player)
	end

	local ok, err = pcall(function()
		TeleportService:TeleportAsync(TeleportConfig.hubPlaceId, activePlayers, teleportOptions)
	end)

	if not ok then
		warn("[CityTrialMatchService] Teleport to hub failed: " .. tostring(err))
		task.delay(3, function()
			local retryOk, retryErr = pcall(function()
				TeleportService:TeleportAsync(TeleportConfig.hubPlaceId, Players:GetPlayers(), teleportOptions)
			end)
			if not retryOk then
				warn("[CityTrialMatchService] Retry teleport failed: " .. tostring(retryErr))
			end
		end)
	end

	task.delay(5, function()
		self:_cleanup()
	end)
end

----------------------------------------------------------------
-- Cleanup
----------------------------------------------------------------

function CityTrialMatchService:_cleanup()
	self:_stopJoinGraceTimer()
	self:_stopReadyGraceTimer()

	if self._countdownTimer then
		self._countdownTimer:Stop()
		self._countdownTimer:Destroy()
		self._countdownTimer = nil
	end

	if self._matchTimer then
		self._matchTimer:Stop()
		self._matchTimer:Destroy()
		self._matchTimer = nil
	end

	if self._resultsTimer then
		self._resultsTimer:Stop()
		self._resultsTimer:Destroy()
		self._resultsTimer = nil
	end

	self._joinedPlayers = {}
	self._readyPlayers = {}

	print("[CityTrialMatchService] Match cleaned up")
end

----------------------------------------------------------------
-- BindToClose
----------------------------------------------------------------

game:BindToClose(function()
	print("[CityTrialMatchService] Server shutting down, saving profiles...")

	local CityTrialPlayerService = Knit.GetService("CityTrialPlayerService")

	if CityTrialMatchService._phase == PHASE_IN_PROGRESS then
		CityTrialMatchService:_computeAndSaveResults()
	end

	CityTrialPlayerService:SaveAllProfiles()

	CityTrialMatchService:_cleanup()
end)

----------------------------------------------------------------
-- Client-exposed methods
----------------------------------------------------------------

function CityTrialMatchService.Client:GetPhase(player)
	return CityTrialMatchService:GetPhase()
end

function CityTrialMatchService.Client:GetMatchState(player)
	if not CityTrialMatchService._matchReplica then return nil end
	return CityTrialMatchService._matchReplica.Data
end

return CityTrialMatchService
