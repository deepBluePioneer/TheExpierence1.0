local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Packages = ReplicatedStorage.Packages
local Knit = require(Packages.Knit)
local Signal = require(Packages.Signal)
local Trove = require(Packages.Trove)
local Timer = require(Packages.timer)

local CustomPackages = ReplicatedStorage.CustomPackages
local ReplicaService = require(CustomPackages.Replica.ReplicaService)

local MachinesConfig = require(ReplicatedStorage.Source.MachinesConfig)
local MachinePhysicsConfig = require(ReplicatedStorage.Source.MachinePhysicsConfig)
local GameConfig = require(ReplicatedStorage.Source.GameConfig)
local PatchesConfig = require(ReplicatedStorage.Source.PatchesConfig)

local MACHINES_FOLDER_NAME = "CityTrialMachines"
local SPAWN_TAG = "MachineSpawnPoint"

local CityTrialMachineService = Knit.CreateService({
	Name = "CityTrialMachineService",
	Client = {},

	_trove = nil,
	_machineData = {},
	_spawnSlots = {},
	_nextSlotIndex = 1,
	_machinesFolder = nil,

	_ownershipTimer = nil,

	MachineSpawned = Signal.new(),
	MachineDestroyed = Signal.new(),
	MachineStateChanged = Signal.new(),
})

local MachineReplicaClassToken = ReplicaService.NewClassToken("MachineState")

----------------------------------------------------------------
-- Lifecycle
----------------------------------------------------------------

function CityTrialMachineService:KnitInit()
	self._trove = Trove.new()
end

function CityTrialMachineService:KnitStart()
	self:_initMachinesFolder()
	self:_collectSpawnSlots()

	local matchService = Knit.GetService("CityTrialMatchService")
	local playerService = Knit.GetService("CityTrialPlayerService")

	matchService.PhaseChanged:Connect(function(phase)
		if phase == "COUNTDOWN" then
			self:_spawnAllMachines()
		elseif phase == "IN_PROGRESS" then
			self:_unlockAllMachines()
		elseif phase == "ENDED" then
			self:_freezeAllMachines()
		elseif phase == "RESULTS" then
			-- Machines stay frozen during results
		end
	end)

	matchService.MatchEnded:Connect(function()
		task.delay(GameConfig.resultsDurationSeconds + 2, function()
			self:_destroyAllMachines()
		end)
	end)

	playerService.PlayerLeft:Connect(function(player)
		self:_destroyMachine(player)
	end)

	self:_startOwnershipMaintenance()
end

----------------------------------------------------------------
-- Machines folder and spawn slots
----------------------------------------------------------------

function CityTrialMachineService:_initMachinesFolder()
	self._machinesFolder = Workspace:FindFirstChild(MACHINES_FOLDER_NAME)
	if not self._machinesFolder then
		self._machinesFolder = Instance.new("Folder")
		self._machinesFolder.Name = MACHINES_FOLDER_NAME
		self._machinesFolder.Parent = Workspace
	end
end

function CityTrialMachineService:_collectSpawnSlots()
	self._spawnSlots = CollectionService:GetTagged(SPAWN_TAG)

	if #self._spawnSlots == 0 then
		warn("[CityTrialMachineService] No MachineSpawnPoint tags found, generating fallback circle")
		local count = GameConfig.maxPlayers
		for i = 1, count do
			local angle = (i / count) * math.pi * 2
			local pos = Vector3.new(math.cos(angle) * 80, 5, math.sin(angle) * 80)
			local part = Instance.new("Part")
			part.Name = "FallbackSpawn_" .. i
			part.Position = pos
			part.Anchored = true
			part.Transparency = 1
			part.CanCollide = false
			part.Parent = self._machinesFolder
			table.insert(self._spawnSlots, part)
		end
	end

	self._nextSlotIndex = 1
	print("[CityTrialMachineService] Found " .. #self._spawnSlots .. " spawn slots")
end

function CityTrialMachineService:_getNextSpawnSlot()
	local slot = self._spawnSlots[self._nextSlotIndex]
	self._nextSlotIndex = (self._nextSlotIndex % #self._spawnSlots) + 1
	return slot
end

----------------------------------------------------------------
-- Machine model builder
----------------------------------------------------------------

function CityTrialMachineService:_buildMachineModel(machineId, config)
	local model = Instance.new("Model")
	model.Name = config.displayName .. "_Machine"

	local bodySize = config.bodySize or Vector3.new(6, 2, 10)

	local rootPart = Instance.new("Part")
	rootPart.Name = "RootPart"
	rootPart.Size = bodySize
	rootPart.Anchored = true
	rootPart.CanCollide = true
	rootPart.Material = Enum.Material.SmoothPlastic
	rootPart.Color = config.bodyColor or Color3.fromRGB(100, 100, 200)
	rootPart.Parent = model
	model.PrimaryPart = rootPart

	local seat = Instance.new("VehicleSeat")
	seat.Name = "Seat"
	seat.Size = Vector3.new(2, 0.5, 2)
	seat.Transparency = 1
	seat.CanCollide = false
	seat.MaxSpeed = 0
	seat.Torque = 0
	seat.TurnSpeed = 0
	seat.HeadsUpDisplay = false
	seat.Disabled = false
	seat.Parent = rootPart

	local seatWeld = Instance.new("WeldConstraint")
	seatWeld.Part0 = rootPart
	seatWeld.Part1 = seat
	seatWeld.Parent = rootPart

	local rootAttachment = Instance.new("Attachment")
	rootAttachment.Name = "RootAttachment"
	rootAttachment.Parent = rootPart

	local linearVel = Instance.new("LinearVelocity")
	linearVel.Name = "DriveForce"
	linearVel.Attachment0 = rootAttachment
	linearVel.MaxForce = math.huge
	linearVel.VelocityConstraintMode = Enum.VelocityConstraintMode.Line
	linearVel.LineDirection = Vector3.new(0, 0, -1)
	linearVel.LineVelocity = 0
	linearVel.RelativeTo = Enum.ActuatorRelativeTo.World
	linearVel.Parent = rootPart

	local alignOri = Instance.new("AlignOrientation")
	alignOri.Name = "SteerAlign"
	alignOri.Attachment0 = rootAttachment
	alignOri.Mode = Enum.OrientationAlignmentMode.OneAttachment
	alignOri.MaxTorque = math.huge
	alignOri.Responsiveness = MachinePhysicsConfig.alignResponsiveness
	alignOri.CFrame = rootPart.CFrame
	alignOri.Parent = rootPart

	local groundSensor = Instance.new("ControllerPartSensor")
	groundSensor.Name = "GroundSensor"
	groundSensor.SensorMode = Enum.SensorMode.Floor
	groundSensor.SearchDistance = MachinePhysicsConfig.hoverHeight * MachinePhysicsConfig.groundRayLength
	groundSensor.Parent = rootPart

	return model, rootPart, seat
end

----------------------------------------------------------------
-- Spawn all machines (called on COUNTDOWN phase)
----------------------------------------------------------------

function CityTrialMachineService:_spawnAllMachines()
	local playerService = Knit.GetService("CityTrialPlayerService")
	local loadedPlayers = playerService:GetAllLoadedPlayers()

	print("[CityTrialMachineService] Spawning machines for " .. #loadedPlayers .. " players")

	for _, player in loadedPlayers do
		if not player:IsDescendantOf(Players) then continue end

		task.spawn(function()
			local ok, err = pcall(function()
				self:_spawnMachineForPlayer(player)
			end)
			if not ok then
				warn("[CityTrialMachineService] Failed to spawn machine for " .. player.Name .. ": " .. tostring(err))
			end
		end)
	end
end

function CityTrialMachineService:_spawnMachineForPlayer(player)
	if self._machineData[player] then return end
	if not player:IsDescendantOf(Players) then return end

	local playerService = Knit.GetService("CityTrialPlayerService")
	local sessionData = playerService:GetSessionData(player)
	if not sessionData then return end

	local machineId = sessionData.machineId or MachinesConfig.defaultMachineId
	local machineConfig = MachinesConfig.machines[machineId]
	if not machineConfig then
		machineConfig = MachinesConfig.machines[MachinesConfig.defaultMachineId]
		machineId = MachinesConfig.defaultMachineId
	end

	local slot = self:_getNextSpawnSlot()
	local spawnCFrame = slot.CFrame + Vector3.new(0, MachinePhysicsConfig.hoverHeight + 1, 0)

	local model, rootPart, seat = self:_buildMachineModel(machineId, machineConfig)
	model:PivotTo(spawnCFrame)
	model.Parent = self._machinesFolder

	CollectionService:AddTag(model, "CityTrialMachine")
	model:SetAttribute("OwnerUserId", player.UserId)

	player:LoadCharacter()

	local character = player.Character or player.CharacterAdded:Wait()
	if not player:IsDescendantOf(Players) then
		model:Destroy()
		return
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		humanoid = character:WaitForChild("Humanoid", 5)
	end
	if not humanoid or not player:IsDescendantOf(Players) then
		model:Destroy()
		return
	end

	seat:Sit(humanoid)

	humanoid.JumpHeight = 0
	humanoid.JumpPower = 0

	local trove = Trove.new()

	trove:Add(humanoid.Seated:Connect(function(active)
		if not active and self._machineData[player] then
			task.defer(function()
				if seat and seat.Parent and humanoid and humanoid.Parent then
					seat:Sit(humanoid)
				end
			end)
		end
	end), "Disconnect")

	trove:Add(humanoid.Died:Connect(function()
		if self._machineData[player] then
			self:_onMachineDeath(player)
		end
	end), "Disconnect")

	local baseStats = {}
	for k, v in machineConfig.baseStats do
		baseStats[k] = v
	end

	local replica = ReplicaService.NewReplica({
		ClassToken = MachineReplicaClassToken,
		Tags = { Player = player },
		Data = {
			machineId = machineId,
			state = "IDLE",
			health = baseStats.maxHealth,
			maxHealth = baseStats.maxHealth,
			boostCharge = 0,
			stats = baseStats,
			invulnerable = true,
		},
		Replication = "All",
	})

	trove:Add(function()
		replica:Destroy()
	end)

	self._machineData[player] = {
		model = model,
		rootPart = rootPart,
		seat = seat,
		humanoid = humanoid,
		replica = replica,
		trove = trove,
		stats = baseStats,
		machineId = machineId,
		machineConfig = machineConfig,
		spawnSlot = slot,
		respawnTimer = nil,
	}

	print("[CityTrialMachineService] Machine spawned for " .. player.Name .. " (" .. machineId .. ")")
	self.MachineSpawned:Fire(player, machineId)
end

----------------------------------------------------------------
-- Phase transitions
----------------------------------------------------------------

function CityTrialMachineService:_unlockAllMachines()
	for player, data in self._machineData do
		if not player:IsDescendantOf(Players) then continue end

		data.rootPart.Anchored = false

		pcall(function()
			data.rootPart:SetNetworkOwner(player)
		end)

		data.replica:SetValue({ "state" }, "DRIVING")
		data.replica:SetValue({ "invulnerable" }, false)
	end

	print("[CityTrialMachineService] All machines unlocked (DRIVING)")
end

function CityTrialMachineService:_freezeAllMachines()
	for player, data in self._machineData do
		if data.replica then
			data.replica:SetValue({ "state" }, "FROZEN")
		end
		if data.rootPart and data.rootPart.Parent then
			local driveForce = data.rootPart:FindFirstChild("DriveForce")
			if driveForce then
				driveForce.LineVelocity = 0
			end
		end
	end

	print("[CityTrialMachineService] All machines frozen (match ended)")
end

----------------------------------------------------------------
-- Death and respawn
----------------------------------------------------------------

function CityTrialMachineService:_onMachineDeath(player)
	local data = self._machineData[player]
	if not data then return end

	if data.humanoid and data.humanoid.Parent then
		data.humanoid.Health = data.humanoid.MaxHealth
	end

	data.replica:SetValue({ "state" }, "DEAD")
	data.replica:SetValue({ "health" }, 0)

	if data.rootPart and data.rootPart.Parent then
		local driveForce = data.rootPart:FindFirstChild("DriveForce")
		if driveForce then
			driveForce.LineVelocity = 0
		end
		data.rootPart.CanCollide = false
	end

	local playerService = Knit.GetService("CityTrialPlayerService")
	local sessionData = playerService:GetSessionData(player)
	if sessionData then
		sessionData.deaths = (sessionData.deaths or 0) + 1
	end

	local elapsed = 0
	local timer = Timer.new(1)
	timer.Tick:Connect(function()
		elapsed = elapsed + 1
		if elapsed >= MachinePhysicsConfig.respawnDelay then
			timer:Stop()
			timer:Destroy()
			data.respawnTimer = nil
			self:RespawnMachine(player)
		end
	end)
	timer:Start()
	data.respawnTimer = timer
end

function CityTrialMachineService:RespawnMachine(player)
	local data = self._machineData[player]
	if not data then return end
	if not player:IsDescendantOf(Players) then return end

	local matchService = Knit.GetService("CityTrialMatchService")
	local phase = matchService:GetPhase()
	if phase ~= "IN_PROGRESS" then return end

	local spawnSlot = self:_findSafeSpawnSlot(player)
	local spawnCFrame = spawnSlot.CFrame + Vector3.new(0, MachinePhysicsConfig.hoverHeight + 1, 0)

	data.rootPart.Anchored = true
	data.model:PivotTo(spawnCFrame)
	data.rootPart.AssemblyLinearVelocity = Vector3.zero
	data.rootPart.AssemblyAngularVelocity = Vector3.zero
	data.rootPart.CanCollide = true
	data.rootPart.Anchored = false

	pcall(function()
		data.rootPart:SetNetworkOwner(player)
	end)

	if not data.humanoid or not data.humanoid.Parent then
		player:LoadCharacter()
		local character = player.Character or player.CharacterAdded:Wait()
		if not player:IsDescendantOf(Players) then return end
		data.humanoid = character:FindFirstChildOfClass("Humanoid")
		if data.humanoid then
			data.humanoid.JumpHeight = 0
			data.humanoid.JumpPower = 0
			data.seat:Sit(data.humanoid)
		end
	else
		data.humanoid.Health = data.humanoid.MaxHealth
		if not data.seat.Occupant then
			data.seat:Sit(data.humanoid)
		end
	end

	local maxHealth = data.stats.maxHealth
	data.replica:SetValue({ "health" }, maxHealth)
	data.replica:SetValue({ "maxHealth" }, maxHealth)
	data.replica:SetValue({ "boostCharge" }, 0)
	data.replica:SetValue({ "state" }, "DRIVING")
	data.replica:SetValue({ "invulnerable" }, true)

	task.delay(MachinePhysicsConfig.respawnInvulnDuration, function()
		if data.replica and player:IsDescendantOf(Players) then
			data.replica:SetValue({ "invulnerable" }, false)
		end
	end)

	print("[CityTrialMachineService] " .. player.Name .. " respawned")
end

function CityTrialMachineService:_findSafeSpawnSlot(player)
	local bestSlot = self._spawnSlots[1]
	local bestDist = 0

	for _, slot in self._spawnSlots do
		local minPlayerDist = math.huge
		for otherPlayer, otherData in self._machineData do
			if otherPlayer == player then continue end
			if not otherData.rootPart or not otherData.rootPart.Parent then continue end
			local dist = (slot.Position - otherData.rootPart.Position).Magnitude
			if dist < minPlayerDist then
				minPlayerDist = dist
			end
		end
		if minPlayerDist > bestDist then
			bestDist = minPlayerDist
			bestSlot = slot
		end
	end

	return bestSlot
end

----------------------------------------------------------------
-- Damage / Heal API
----------------------------------------------------------------

function CityTrialMachineService:ApplyDamage(player, amount, _source)
	local data = self._machineData[player]
	if not data or not data.replica then return end

	local replicaData = data.replica.Data
	if replicaData.invulnerable then return end
	if replicaData.state == "DEAD" or replicaData.state == "IDLE" then return end

	local newHealth = math.max(0, replicaData.health - amount)
	data.replica:SetValue({ "health" }, newHealth)

	if newHealth <= 0 then
		self:_onMachineDeath(player)
	end
end

function CityTrialMachineService:ApplyHeal(player, amount)
	local data = self._machineData[player]
	if not data or not data.replica then return end

	local replicaData = data.replica.Data
	local newHealth = math.min(replicaData.maxHealth, replicaData.health + amount)
	data.replica:SetValue({ "health" }, newHealth)
end

function CityTrialMachineService:RecalculateStats(player, patchCounts)
	local data = self._machineData[player]
	if not data then return end

	local baseStats = {}
	for k, v in data.machineConfig.baseStats do
		baseStats[k] = v
	end

	for patchType, count in patchCounts do
		local patchConfig = PatchesConfig.patches[patchType]
		if patchConfig and patchConfig.statBoosts then
			for statName, boostPerPatch in patchConfig.statBoosts do
				if baseStats[statName] then
					baseStats[statName] = baseStats[statName] + (boostPerPatch * count)
				end
			end
		end
	end

	data.stats = baseStats

	if data.replica then
		data.replica:SetValue({ "stats" }, baseStats)
		data.replica:SetValue({ "maxHealth" }, baseStats.maxHealth)
	end
end

----------------------------------------------------------------
-- Queries
----------------------------------------------------------------

function CityTrialMachineService:GetMachineModel(player)
	local data = self._machineData[player]
	return data and data.model or nil
end

function CityTrialMachineService:GetMachineData(player)
	return self._machineData[player]
end

function CityTrialMachineService:GetMachineReplica(player)
	local data = self._machineData[player]
	return data and data.replica or nil
end

----------------------------------------------------------------
-- Cleanup
----------------------------------------------------------------

function CityTrialMachineService:_destroyMachine(player)
	local data = self._machineData[player]
	if not data then return end

	if data.respawnTimer then
		data.respawnTimer:Stop()
		data.respawnTimer:Destroy()
		data.respawnTimer = nil
	end

	if data.trove then
		data.trove:Destroy()
	end

	if data.model and data.model.Parent then
		data.model:Destroy()
	end

	self._machineData[player] = nil
	self.MachineDestroyed:Fire(player)
end

function CityTrialMachineService:_destroyAllMachines()
	for player, _ in self._machineData do
		self:_destroyMachine(player)
	end
	print("[CityTrialMachineService] All machines destroyed")
end

----------------------------------------------------------------
-- Network ownership maintenance
----------------------------------------------------------------

function CityTrialMachineService:_startOwnershipMaintenance()
	local timer = Timer.new(5)
	timer.Tick:Connect(function()
		for player, data in self._machineData do
			if not player:IsDescendantOf(Players) then continue end
			if not data.rootPart or not data.rootPart.Parent then continue end
			if data.rootPart.Anchored then continue end

			pcall(function()
				data.rootPart:SetNetworkOwner(player)
			end)
		end
	end)
	timer:Start()
	self._ownershipTimer = timer

	self._trove:Add(function()
		timer:Stop()
		timer:Destroy()
	end)
end

----------------------------------------------------------------
-- Collision handling
----------------------------------------------------------------

function CityTrialMachineService:SetupCollisionDetection(player)
	local data = self._machineData[player]
	if not data or not data.rootPart then return end

	local debounce = {}

	data.trove:Add(data.rootPart.Touched:Connect(function(otherPart)
		if not otherPart.Parent then return end

		local otherModel = otherPart:FindFirstAncestorOfClass("Model")
		if not otherModel then return end
		if not CollectionService:HasTag(otherModel, "CityTrialMachine") then return end

		local otherUserId = otherModel:GetAttribute("OwnerUserId")
		if not otherUserId then return end

		local debounceKey = math.min(player.UserId, otherUserId) .. "_" .. math.max(player.UserId, otherUserId)
		if debounce[debounceKey] then return end
		debounce[debounceKey] = true

		task.delay(0.5, function()
			debounce[debounceKey] = nil
		end)

		local relativeVelocity = (data.rootPart.AssemblyLinearVelocity - otherPart.AssemblyLinearVelocity).Magnitude
		if relativeVelocity < MachinePhysicsConfig.collisionStunThreshold then return end

		local damage = relativeVelocity * MachinePhysicsConfig.collisionDamageMultiplier
		self:ApplyDamage(player, damage, "collision")

		if data.replica and data.replica.Data.state ~= "DEAD" then
			data.replica:SetValue({ "state" }, "STUNNED")
			task.delay(MachinePhysicsConfig.collisionStunDuration, function()
				if data.replica and data.replica.Data.state == "STUNNED" then
					data.replica:SetValue({ "state" }, "DRIVING")
				end
			end)
		end
	end), "Disconnect")
end

----------------------------------------------------------------
-- Client methods
----------------------------------------------------------------

function CityTrialMachineService.Client:GetMachineState(player)
	local data = CityTrialMachineService._machineData[player]
	if not data or not data.replica then return nil end
	return data.replica.Data
end

return CityTrialMachineService
