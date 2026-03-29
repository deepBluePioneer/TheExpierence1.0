local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local MACHINE_SPAWN_POSITION = Vector3.new(0, 5, 0)
-- FillBlock CFrame position is the region center; top surface Y = center.Y + size.Y/2
local LOBBY_ORIGIN = Vector3.new(0, 50, -200)
local LOBBY_PLATFORM_SIZE = Vector3.new(200, 4, 200)
local LOBBY_SURFACE_Y = LOBBY_ORIGIN.Y + LOBBY_PLATFORM_SIZE.Y / 2
local LOBBY_MACHINE_SPACING = 20
local LOBBY_MACHINE_CLEARANCE = 0.15

local Packages = ReplicatedStorage.Packages
local Knit = require(Packages.Knit)
local Signal = require(Packages.Signal)
local Trove = require(Packages.Trove)
local TableUtil = require(Packages.TableUtil)

local CustomPackages = ReplicatedStorage.CustomPackages
local ProfileService = require(CustomPackages.ProfileService.ProfileService)

local STORE_NAME = "LakelandCareerDay_v2"
local PROFILE_KEY = "LakelandArcade"
local LEADERBOARD_STORE_NAME = "LakelandLeaderboard_v2"
local MAX_LEADERBOARD = 10

local DEFAULT_DATA = {
	profiles = {},
}

local LakelandDataService = Knit.CreateService({
	Name = "LakelandDataService",
	Client = {},

	_trove = nil,
	_profileStore = nil,
	_profile = nil,
	_leaderboardStore = nil,
	_leaderboardCache = {},
	_leaderboardCacheTime = 0,

	DataLoaded = Signal.new(),
	LeaderboardUpdated = Signal.new(),
})

local LEADERBOARD_CACHE_TTL = 10

function LakelandDataService:KnitInit()
	self._trove = Trove.new()
	self._profileStore = ProfileService.GetProfileStore(STORE_NAME, DEFAULT_DATA)
	self._leaderboardStore = DataStoreService:GetOrderedDataStore(LEADERBOARD_STORE_NAME)

	Players.CharacterAutoLoads = false
end

function LakelandDataService:KnitStart()
	self:CreateLobbyPlatform()
	self:SpawnLobbyMachines()

	self._trove:Add(Players.PlayerAdded:Connect(function(player)
		player:LoadCharacter()
	end), "Disconnect")

	for _, player in ipairs(Players:GetPlayers()) do
		if not player.Character then
			player:LoadCharacter()
		end
	end

	self:_loadProfile()

	self._trove:Add(Players.PlayerRemoving:Connect(function(_player)
		if #Players:GetPlayers() <= 1 and self._profile then
			self._profile:Release()
		end
	end), "Disconnect")
end

function LakelandDataService:_loadProfile()
	local profile = self._profileStore:LoadProfileAsync(PROFILE_KEY)
	if not profile then
		warn("[LakelandDataService] Failed to load arcade profile")
		return
	end

	profile:AddUserId(0)
	profile:Reconcile()

	profile:ListenToRelease(function()
		self._profile = nil
		print("[LakelandDataService] Profile released")
	end)

	self._profile = profile
	self._trove:Add(function()
		if self._profile then
			self._profile:Release()
			self._profile = nil
		end
	end)

	self.DataLoaded:Fire()
	print("[LakelandDataService] Loaded: " .. #self:_getData().profiles .. " profiles")
end

function LakelandDataService:_getData()
	if self._profile then
		return self._profile.Data
	end
	return DEFAULT_DATA
end

----------------------------------------------------------------
-- Client-callable methods
----------------------------------------------------------------

function LakelandDataService.Client:LoadCharacter(player)
	player:LoadCharacter()
end

function LakelandDataService.Client:DestroyCharacter(player)
	if player.Character then
		player.Character:Destroy()
	end
end

function LakelandDataService.Client:SpawnMachine(_player)
	return self.Server:SpawnMachine()
end

function LakelandDataService.Client:DestroyMachine(_player)
	self.Server:DestroyMachine()
end

function LakelandDataService.Client:SeatPlayerInMachine(player)
	self.Server:SeatPlayerInMachine(player)
end

function LakelandDataService.Client:UnseatPlayer(player)
	self.Server:UnseatPlayer(player)
end

function LakelandDataService.Client:CreateLobbyPlatform(_player)
	self.Server:CreateLobbyPlatform()
end

function LakelandDataService.Client:SpawnLobbyMachines(_player)
	return self.Server:SpawnLobbyMachines()
end

function LakelandDataService.Client:DestroyLobbyMachines(_player)
	self.Server:DestroyLobbyMachines()
end

function LakelandDataService.Client:SpawnSpecificMachine(_player, templateName)
	return self.Server:SpawnSpecificMachine(templateName)
end

function LakelandDataService.Client:GetProfiles(_player)
	return self.Server:GetProfiles()
end

function LakelandDataService.Client:GetLeaderboard(_player)
	return self.Server:GetLeaderboard()
end

function LakelandDataService.Client:RegisterProfile(_player, name)
	return self.Server:RegisterProfile(name)
end

function LakelandDataService.Client:SubmitScore(_player, name, score)
	return self.Server:SubmitScore(name, score)
end

----------------------------------------------------------------
-- Machine spawning (server-only)
----------------------------------------------------------------

function LakelandDataService:SpawnMachine()
	self:DestroyMachine()

	local machinesFolder = ReplicatedStorage:FindFirstChild("Machines")
	if not machinesFolder then
		warn("[LakelandDataService] No Machines folder in ReplicatedStorage")
		return ""
	end

	local templates = machinesFolder:GetChildren()
	if #templates == 0 then
		warn("[LakelandDataService] No machines found in ReplicatedStorage.Machines")
		return ""
	end

	local template = templates[math.random(1, #templates)]
	local machine = template:Clone()
	machine.Name = "ActiveMachine"

	for _, descendant in ipairs(machine:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
		end
	end

	if machine.PrimaryPart then
		machine:PivotTo(CFrame.new(MACHINE_SPAWN_POSITION))
	end

	machine.Parent = Workspace
	print("[LakelandDataService] Spawned machine: " .. template.Name)
	return template.Name
end

function LakelandDataService:DestroyMachine()
	local existing = Workspace:FindFirstChild("ActiveMachine")
	if existing then
		existing:Destroy()
	end
end

function LakelandDataService:CreateLobbyPlatform()
	local terrain = Workspace.Terrain
	terrain:FillBlock(
		CFrame.new(LOBBY_ORIGIN),
		LOBBY_PLATFORM_SIZE,
		Enum.Material.Grass
	)
	print("[LakelandDataService] Created lobby platform at " .. tostring(LOBBY_ORIGIN) .. " surfaceY=" .. LOBBY_SURFACE_Y)
end

local function snapModelBottomToSurfaceY(model, surfaceY)
	if not model.PrimaryPart then return end
	local cf, size = model:GetBoundingBox()
	local bottomY = cf.Position.Y - size.Y * 0.5
	local delta = surfaceY + LOBBY_MACHINE_CLEARANCE - bottomY
	if math.abs(delta) > 0.001 then
		model:TranslateBy(Vector3.new(0, delta, 0))
	end
end

function LakelandDataService:SpawnLobbyMachines()
	self:DestroyLobbyMachines()

	local machinesFolder = ReplicatedStorage:FindFirstChild("Machines")
	if not machinesFolder then
		warn("[LakelandDataService] No Machines folder in ReplicatedStorage")
		return {}
	end

	local templates = machinesFolder:GetChildren()
	if #templates == 0 then
		warn("[LakelandDataService] No machines found in ReplicatedStorage.Machines")
		return {}
	end

	local lobbyFolder = Instance.new("Folder")
	lobbyFolder.Name = "LobbyMachines"
	lobbyFolder.Parent = Workspace

	local totalWidth = (#templates - 1) * LOBBY_MACHINE_SPACING
	local startX = -totalWidth / 2

	local names = {}
	for i, template in ipairs(templates) do
		local machine = template:Clone()
		machine.Name = "LobbyMachine_" .. template.Name
		machine:SetAttribute("TemplateName", template.Name)

		for _, desc in ipairs(machine:GetDescendants()) do
			if desc:IsA("BasePart") then
				desc.Anchored = true
				desc.CanCollide = true
			end
			if desc:IsA("Seat") or desc:IsA("VehicleSeat") then
				desc.Disabled = false
			end
		end

		local x = startX + (i - 1) * LOBBY_MACHINE_SPACING
		-- Rough place (Y arbitrary); snap so model AABB bottom sits on terrain top.
		local pos = Vector3.new(LOBBY_ORIGIN.X + x, LOBBY_SURFACE_Y + 8, LOBBY_ORIGIN.Z)
		machine.Parent = lobbyFolder
		if machine.PrimaryPart then
			machine:PivotTo(CFrame.new(pos) * CFrame.Angles(0, math.rad(180), 0))
			snapModelBottomToSurfaceY(machine, LOBBY_SURFACE_Y)
		end

		table.insert(names, template.Name)
	end

	print("[LakelandDataService] Spawned " .. #names .. " lobby machines")
	return names
end

function LakelandDataService:DestroyLobbyMachines()
	local existing = Workspace:FindFirstChild("LobbyMachines")
	if existing then
		existing:Destroy()
	end
end

function LakelandDataService:SpawnSpecificMachine(templateName)
	self:DestroyMachine()

	local machinesFolder = ReplicatedStorage:FindFirstChild("Machines")
	if not machinesFolder then return "" end

	local template = machinesFolder:FindFirstChild(templateName)
	if not template then
		warn("[LakelandDataService] Template not found: " .. tostring(templateName))
		return ""
	end

	local machine = template:Clone()
	machine.Name = "ActiveMachine"

	for _, desc in ipairs(machine:GetDescendants()) do
		if desc:IsA("BasePart") then
			desc.Anchored = true
		end
	end

	if machine.PrimaryPart then
		machine:PivotTo(CFrame.new(MACHINE_SPAWN_POSITION))
	end

	machine.Parent = Workspace
	print("[LakelandDataService] Spawned specific machine: " .. templateName)
	return templateName
end

----------------------------------------------------------------
-- Player seating (server-only)
----------------------------------------------------------------

function LakelandDataService:SeatPlayerInMachine(player)
	local character = player.Character
	if not character then return end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then return end

	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if not rootPart then return end

	local machine = Workspace:FindFirstChild("ActiveMachine")
	if not machine then
		warn("[LakelandDataService] No ActiveMachine found in Workspace")
		return
	end

	local folder = machine:FindFirstChild("Folder")
	if not folder then return end

	local seat = folder:FindFirstChildOfClass("Seat") or folder:FindFirstChildOfClass("VehicleSeat")
	if not seat then return end

	rootPart.CFrame = seat.CFrame + Vector3.new(0, 3, 0)
	task.wait()
	seat:Sit(humanoid)

	humanoid.JumpHeight = 0
	humanoid.JumpPower = 0

	print("[LakelandDataService] Seated player: " .. player.Name)
end

function LakelandDataService:UnseatPlayer(player)
	local character = player.Character
	if not character then return end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then return end

	humanoid.Sit = false
	humanoid.Jump = true
	humanoid.JumpHeight = 7.2
	humanoid.JumpPower = 50
end

----------------------------------------------------------------
-- Profiles (ProfileService)
----------------------------------------------------------------

function LakelandDataService:GetProfiles()
	return TableUtil.Copy(self:_getData().profiles)
end

function LakelandDataService:RegisterProfile(name)
	if type(name) ~= "string" or #name == 0 or #name > 20 then
		return false
	end

	local data = self:_getData()

	for _, profile in data.profiles do
		if profile.name == name then
			return true
		end
	end

	table.insert(data.profiles, {
		name = name,
		gamesPlayed = 0,
		bestScore = 0,
	})

	return true
end

function LakelandDataService:GetProfileByName(name)
	for _, profile in self:_getData().profiles do
		if profile.name == name then
			return TableUtil.Copy(profile)
		end
	end
	return nil
end

----------------------------------------------------------------
-- Leaderboard (OrderedDataStore)
----------------------------------------------------------------

function LakelandDataService:SubmitScore(name, score)
	if type(name) ~= "string" or #name == 0 then return end
	if type(score) ~= "number" or score < 0 then return end

	local intScore = math.floor(score)
	if intScore <= 0 then return end

	local data = self:_getData()
	for _, profile in data.profiles do
		if profile.name == name then
			profile.gamesPlayed = (profile.gamesPlayed or 0) + 1
			if intScore > (profile.bestScore or 0) then
				profile.bestScore = intScore
			end
			break
		end
	end

	local ok, err = pcall(function()
		self._leaderboardStore:UpdateAsync(name, function(oldValue)
			oldValue = oldValue or 0
			if intScore > oldValue then
				return intScore
			end
			return nil
		end)
	end)

	if not ok then
		warn("[LakelandDataService] Failed to write leaderboard: " .. tostring(err))
	else
		print("[LakelandDataService] Leaderboard updated: " .. name .. " = " .. intScore)
	end

	self._leaderboardCacheTime = 0
	self.LeaderboardUpdated:Fire()
end

function LakelandDataService:GetLeaderboard()
	local now = os.clock()
	if now - self._leaderboardCacheTime < LEADERBOARD_CACHE_TTL and #self._leaderboardCache > 0 then
		return self._leaderboardCache
	end

	local entries = {}

	local ok, err = pcall(function()
		local pages = self._leaderboardStore:GetSortedAsync(false, MAX_LEADERBOARD)
		local page = pages:GetCurrentPage()
		for rank, entry in ipairs(page) do
			table.insert(entries, {
				rank = rank,
				name = entry.key,
				score = entry.value,
			})
		end
	end)

	if not ok then
		warn("[LakelandDataService] Failed to read leaderboard: " .. tostring(err))
		return self._leaderboardCache
	end

	self._leaderboardCache = entries
	self._leaderboardCacheTime = now
	print("[LakelandDataService] Fetched " .. #entries .. " leaderboard entries from OrderedDataStore")
	return entries
end

return LakelandDataService
