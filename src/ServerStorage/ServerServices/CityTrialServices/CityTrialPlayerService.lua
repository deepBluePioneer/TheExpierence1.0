local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Packages = ReplicatedStorage.Packages
local Knit = require(Packages.Knit)
local Signal = require(Packages.Signal)
local Trove = require(Packages.Trove)

local CustomPackages = ReplicatedStorage.CustomPackages
local ProfileService = require(CustomPackages.ProfileService.ProfileService)
local ReplicaService = require(CustomPackages.Replica.ReplicaService)

local ProfileConfig = require(ReplicatedStorage.Source.ProfileConfig)
local MachinesConfig = require(ReplicatedStorage.Source.MachinesConfig)
local Analytics = require(ReplicatedStorage.Source.Analytics)

local PROFILE_STORE_NAME = "PlayerProfile_v1"

local CityTrialPlayerService = Knit.CreateService {
	Name = "CityTrialPlayerService",
	Client = {
		ReportReady = Knit.CreateSignal(),
	},

	_profileStore = nil,
	_profiles = {},
	_replicas = {},
	_troves = {},
	_sessionData = {},
	_readyPlayers = {},

	PlayerLoaded = Signal.new(),
	PlayerReady = Signal.new(),
	PlayerLeft = Signal.new(),
}

local PlayerProfileClassToken = ReplicaService.NewClassToken("CTPlayerProfile")

function CityTrialPlayerService:KnitInit()
	self._profileStore = ProfileService.GetProfileStore(PROFILE_STORE_NAME, ProfileConfig.DEFAULT_PROFILE)
end

function CityTrialPlayerService:KnitStart()
	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(function()
			self:_loadPlayer(player)
		end)
	end

	Players.PlayerAdded:Connect(function(player)
		Analytics.Funnel.MatchTeleportedIn(player)
		self:_loadPlayer(player)
	end)

	Players.PlayerRemoving:Connect(function(player)
		Analytics.Funnel.ClearPlayer(player)
		self:_releasePlayer(player)
	end)

	self.Client.ReportReady:Connect(function(player)
		self:SetPlayerReady(player)
	end)
end

function CityTrialPlayerService:_loadPlayer(player)
	local profile = self._profileStore:LoadProfileAsync("Player_" .. player.UserId)
	if not profile then
		warn("[CityTrialPlayerService] Failed to load profile for " .. player.Name)
		return
	end

	profile:AddUserId(player.UserId)
	profile:Reconcile()

	profile:ListenToRelease(function()
		self:_onProfileReleased(player)
	end)

	if not player:IsDescendantOf(Players) then
		profile:Release()
		return
	end

	local trove = Trove.new()
	self._profiles[player] = profile
	self._troves[player] = trove

	local selectedMachineId = profile.Data.selectedMachineId or MachinesConfig.defaultMachineId
	local machineConfig = MachinesConfig.machines[selectedMachineId]

	self._sessionData[player] = {
		machineId = selectedMachineId,
		patchCounts = {},
		totalPatchesCollected = 0,
		deaths = 0,
		damageTaken = 0,
		distanceTraveled = 0,
		eventsSurvived = 0,
		joinTime = os.clock(),
	}

	local replica = ReplicaService.NewReplica({
		ClassToken = PlayerProfileClassToken,
		Tags = { Player = player },
		Data = {
			machineId = selectedMachineId,
			machineName = machineConfig and machineConfig.displayName or selectedMachineId,
			health = machineConfig and machineConfig.baseStats.maxHealth or 80,
			maxHealth = machineConfig and machineConfig.baseStats.maxHealth or 80,
			boostCharge = 0,
			patchCounts = {},
			invulnerable = false,
			alive = true,
		},
		Replication = "All",
	})

	self._replicas[player] = replica
	trove:Add(function()
		replica:Destroy()
	end)

	print("[CityTrialPlayerService] Player loaded: " .. player.Name .. " | Machine: " .. selectedMachineId)
	self.PlayerLoaded:Fire(player)

	local matchService = Knit.GetService("CityTrialMatchService")
	matchService:ReportPlayerJoined(player)
end

function CityTrialPlayerService:_onProfileReleased(player)
	local trove = self._troves[player]
	if trove then
		trove:Destroy()
	end

	self._profiles[player] = nil
	self._replicas[player] = nil
	self._troves[player] = nil
	self._sessionData[player] = nil
	self._readyPlayers[player] = nil
end

function CityTrialPlayerService:_releasePlayer(player)
	self.PlayerLeft:Fire(player)

	local profile = self._profiles[player]
	if profile then
		profile:Release()
	end
end

function CityTrialPlayerService:SetPlayerReady(player)
	if self._readyPlayers[player] then return end
	if not self._profiles[player] then return end

	self._readyPlayers[player] = true
	print("[CityTrialPlayerService] Player ready: " .. player.Name)
	self.PlayerReady:Fire(player)

	local matchService = Knit.GetService("CityTrialMatchService")
	matchService:ReportPlayerReady(player)
end

function CityTrialPlayerService:IsPlayerReady(player)
	return self._readyPlayers[player] == true
end

function CityTrialPlayerService:GetProfile(player)
	return self._profiles[player]
end

function CityTrialPlayerService:GetProfileData(player)
	local profile = self._profiles[player]
	return profile and profile.Data or nil
end

function CityTrialPlayerService:GetReplica(player)
	return self._replicas[player]
end

function CityTrialPlayerService:GetSessionData(player)
	return self._sessionData[player]
end

function CityTrialPlayerService:GetAllLoadedPlayers()
	local players = {}
	for player, _ in pairs(self._profiles) do
		if player:IsDescendantOf(Players) then
			table.insert(players, player)
		end
	end
	return players
end

function CityTrialPlayerService:SaveAllProfiles()
	for player, profile in pairs(self._profiles) do
		if profile then
			profile:Release()
		end
	end
end

return CityTrialPlayerService
