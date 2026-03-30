local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local LakelandLobbyConfig = require(ReplicatedStorage.Source.LakelandLobbyConfig)

local MACHINE_SPAWN_POSITION = Vector3.new(0, 8, 0)
-- Lobby platform Part uses ORIGIN as center; top surface Y = getSurfaceY()
local LOBBY_ORIGIN = LakelandLobbyConfig.ORIGIN
local LOBBY_PLATFORM_SIZE = LakelandLobbyConfig.PLATFORM_SIZE
local LOBBY_SURFACE_Y = LakelandLobbyConfig.getSurfaceY()
local LOBBY_MACHINE_SPACING = LakelandLobbyConfig.MACHINE_SPACING
local LOBBY_MACHINE_CLEARANCE = LakelandLobbyConfig.MACHINE_CLEARANCE

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

function LakelandDataService.Client:DestroyLobbyPlatform(_player)
	self.Server:DestroyLobbyPlatform()
end

function LakelandDataService.Client:SpawnSpecificMachine(_player, templateName)
	return self.Server:SpawnSpecificMachine(templateName)
end

function LakelandDataService.Client:PlaceMachineOnTerrain(_player, groundY)
	self.Server:PlaceMachineOnTerrain(groundY)
end

function LakelandDataService.Client:SyncMachineTransform(_player, cf)
	return self.Server:SyncMachineTransform(cf)
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

	for _, descendant in ipairs(machine:GetDescendants()) do
		if descendant:IsA("WeldConstraint") then
			descendant.Enabled = false
			descendant.Enabled = true
		end
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
	-- Use a Part for the lobby so Workspace.Terrain is only used for biome/race volumes
	-- (avoids double grass slabs from client+server FillBlock and keeps one terrain “system”).
	local terrain = Workspace.Terrain
	local half = LOBBY_PLATFORM_SIZE * 0.5
	local minV = LOBBY_ORIGIN - half
	local maxV = LOBBY_ORIGIN + half
	local clearRes = 4
	terrain:FillRegion(Region3.new(minV, maxV):ExpandToGrid(clearRes), clearRes, Enum.Material.Air)

	local name = "LakelandLobbyPlatform"
	local existing = Workspace:FindFirstChild(name)
	if existing then
		existing:Destroy()
	end
	local floor = Instance.new("Part")
	floor.Name = name
	floor.Size = LOBBY_PLATFORM_SIZE
	floor.CFrame = CFrame.new(LOBBY_ORIGIN)
	floor.Anchored = true
	floor.CanCollide = true
	floor.Material = Enum.Material.Grass
	floor.CastShadow = true
	floor.Parent = Workspace
	print("[LakelandDataService] Created lobby platform (Part) at " .. tostring(LOBBY_ORIGIN) .. " surfaceY=" .. LOBBY_SURFACE_Y)
end

function LakelandDataService:DestroyLobbyPlatform()
	local existing = Workspace:FindFirstChild("LakelandLobbyPlatform")
	if existing then
		existing:Destroy()
	end

	local baseplate = Workspace:FindFirstChild("Baseplate")
	if baseplate then
		baseplate:Destroy()
	end
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

	for _, desc in ipairs(machine:GetDescendants()) do
		if desc:IsA("WeldConstraint") then
			desc.Enabled = false
			desc.Enabled = true
		end
	end

	machine.Parent = Workspace
	print("[LakelandDataService] Spawned specific machine: " .. templateName)
	return templateName
end

function LakelandDataService:SyncMachineTransform(cf)
	local machine = Workspace:FindFirstChild("ActiveMachine")
	if not machine or not machine.PrimaryPart then return true end
	machine:PivotTo(cf)
	for _, desc in ipairs(machine:GetDescendants()) do
		if desc:IsA("WeldConstraint") then
			desc.Enabled = false
			desc.Enabled = true
		end
	end
	return true
end

function LakelandDataService:PlaceMachineOnTerrain(groundY)
	local machine = Workspace:FindFirstChild("ActiveMachine")
	if not machine or not machine.PrimaryPart then return end
	local cf, size = machine:GetBoundingBox()
	local bottomY = cf.Position.Y - size.Y * 0.5
	local pivotCF = machine:GetPivot()
	local deltaY = groundY - bottomY
	machine:PivotTo(pivotCF + Vector3.new(0, deltaY, 0))
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

	local machine = Workspace:FindFirstChild("ActiveMachine")
	if machine then
		for _, desc in ipairs(machine:GetDescendants()) do
			if desc:IsA("BasePart") then
				desc.Anchored = true
			end
		end
		if machine.PrimaryPart then
			machine:PivotTo(machine:GetPivot())
		end
	end
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
