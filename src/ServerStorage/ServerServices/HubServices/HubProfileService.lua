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
local Analytics = require(ReplicatedStorage.Source.Analytics)

local PROFILE_STORE_NAME = "PlayerProfile_v1"

local HubProfileService = Knit.CreateService {
	Name = "HubProfileService",
	Client = {},

	_profileStore = nil,
	_profiles = {},
	_replicas = {},
	_troves = {},

	PlayerProfileLoaded = Signal.new(),
	PlayerProfileReleased = Signal.new(),
	PlayerLeveledUp = Signal.new(),
}

local PlayerProfileClassToken = ReplicaService.NewClassToken("PlayerProfile")

-- Schema migration: bring old profiles up to current version
local function migrateProfile(data)
	local version = data.schemaVersion or 0
	while version < ProfileConfig.CURRENT_VERSION do
		local migrator = ProfileConfig.Migrations[version]
		if migrator then
			local ok, err = pcall(migrator, data)
			if not ok then
				warn("[HubProfileService] Migration from v" .. version .. " failed: " .. tostring(err))
				return false
			end
			version = data.schemaVersion
		else
			data.schemaVersion = ProfileConfig.CURRENT_VERSION
			version = ProfileConfig.CURRENT_VERSION
		end
	end
	return true
end

function HubProfileService:KnitInit()
	self._profileStore = ProfileService.GetProfileStore(PROFILE_STORE_NAME, ProfileConfig.DEFAULT_PROFILE)
end

function HubProfileService:KnitStart()
	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(function()
			self:_loadProfile(player)
		end)
	end

	Players.PlayerAdded:Connect(function(player)
		Analytics.HubJoined(player)
		Analytics.Funnel.OnboardingJoined(player)
		self:_loadProfile(player)
	end)

	Players.PlayerRemoving:Connect(function(player)
		Analytics.Funnel.ClearPlayer(player)
		self:_releaseProfile(player)
	end)
end

function HubProfileService:_loadProfile(player)
	local profile = self._profileStore:LoadProfileAsync("Player_" .. player.UserId)
	if not profile then
		player:Kick("Unable to load your data. Please rejoin.")
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

	if not migrateProfile(profile.Data) then
		player:Kick("Data migration failed. Please rejoin or contact support.")
		profile:Release()
		return
	end

	local trove = Trove.new()
	self._profiles[player] = profile
	self._troves[player] = trove

	local replica = ReplicaService.NewReplica({
		ClassToken = PlayerProfileClassToken,
		Tags = { Player = player },
		Data = {
			currency = profile.Data.currency,
			xp = profile.Data.xp,
			level = profile.Data.level,
			ownedMachines = profile.Data.ownedMachines,
			selectedMachineId = profile.Data.selectedMachineId,
			ownedTrails = profile.Data.ownedTrails,
			equippedTrailId = profile.Data.equippedTrailId,
			ownedTitles = profile.Data.ownedTitles,
			equippedTitleId = profile.Data.equippedTitleId,
			hudDensity = profile.Data.hudDensity,
		},
		Replication = { [player] = true },
	})

	self._replicas[player] = replica
	Analytics.Funnel.OnboardingProfileLoaded(player)
	trove:Add(function()
		replica:Destroy()
	end)

	print("[HubProfileService] Profile loaded for " .. player.Name)
	self.PlayerProfileLoaded:Fire(player, profile)
end

function HubProfileService:_onProfileReleased(player)
	local trove = self._troves[player]
	if trove then
		trove:Destroy()
	end

	self._profiles[player] = nil
	self._replicas[player] = nil
	self._troves[player] = nil

	self.PlayerProfileReleased:Fire(player)

	if player:IsDescendantOf(Players) then
		player:Kick("Your profile session has ended.")
	end
end

function HubProfileService:_releaseProfile(player)
	local profile = self._profiles[player]
	if profile then
		profile:Release()
	end
end

----------------------------------------------------------------
-- Public APIs
----------------------------------------------------------------

function HubProfileService:GetProfile(player)
	return self._profiles[player]
end

function HubProfileService:GetProfileData(player)
	local profile = self._profiles[player]
	return profile and profile.Data or nil
end

function HubProfileService:GetReplica(player)
	return self._replicas[player]
end

function HubProfileService:GetCurrency(player)
	local data = self:GetProfileData(player)
	return data and data.currency or 0
end

function HubProfileService:CanAfford(player, cost)
	return self:GetCurrency(player) >= cost
end

function HubProfileService:AddCurrency(player, amount)
	local data = self:GetProfileData(player)
	if not data then return end

	data.currency = data.currency + amount
	local replica = self._replicas[player]
	if replica then
		replica:SetValue({ "currency" }, data.currency)
	end
end

function HubProfileService:ApplyPurchase(player, cost)
	local data = self:GetProfileData(player)
	if not data then return false, "No profile" end
	if data.currency < cost then return false, "Not enough currency" end

	data.currency = data.currency - cost
	local replica = self._replicas[player]
	if replica then
		replica:SetValue({ "currency" }, data.currency)
	end
	return true
end

function HubProfileService:AddXP(player, amount)
	local data = self:GetProfileData(player)
	if not data then return end

	data.xp = data.xp + amount

	local oldLevel = data.level
	local newLevel = oldLevel
	while ProfileConfig.xpForLevel(newLevel + 1) <= data.xp do
		newLevel = newLevel + 1
	end

	data.level = newLevel

	local replica = self._replicas[player]
	if replica then
		replica:SetValue({ "xp" }, data.xp)
		replica:SetValue({ "level" }, data.level)
	end

	if newLevel > oldLevel then
		print("[HubProfileService] " .. player.Name .. " leveled up to " .. newLevel)
		self.PlayerLeveledUp:Fire(player, newLevel, oldLevel)
	end
end

function HubProfileService:GetLevel(player)
	local data = self:GetProfileData(player)
	return data and data.level or 1
end

function HubProfileService:SetSelectedMachine(player, machineId)
	local data = self:GetProfileData(player)
	if not data then return false, "No profile" end

	data.selectedMachineId = machineId
	local replica = self._replicas[player]
	if replica then
		replica:SetValue({ "selectedMachineId" }, machineId)
	end
	return true
end

function HubProfileService:GetOwnedMachines(player)
	local data = self:GetProfileData(player)
	return data and data.ownedMachines or {}
end

function HubProfileService:UnlockMachine(player, machineId)
	local data = self:GetProfileData(player)
	if not data then return false, "No profile" end

	if table.find(data.ownedMachines, machineId) then
		return false, "Already owned"
	end

	table.insert(data.ownedMachines, machineId)
	local replica = self._replicas[player]
	if replica then
		replica:SetValue({ "ownedMachines" }, data.ownedMachines)
	end

	if not data.selectedMachineId or data.selectedMachineId == "" then
		self:SetSelectedMachine(player, machineId)
	end

	return true
end

----------------------------------------------------------------
-- BindToClose: save all profiles on shutdown
----------------------------------------------------------------

function HubProfileService:SaveAllProfiles()
	for player, profile in pairs(self._profiles) do
		if profile then
			profile:Release()
		end
	end
end

game:BindToClose(function()
	HubProfileService:SaveAllProfiles()
end)

----------------------------------------------------------------
-- Client-exposed methods
----------------------------------------------------------------

function HubProfileService.Client:GetCurrency(player)
	return HubProfileService:GetCurrency(player)
end

function HubProfileService.Client:GetLevel(player)
	return HubProfileService:GetLevel(player)
end

return HubProfileService
