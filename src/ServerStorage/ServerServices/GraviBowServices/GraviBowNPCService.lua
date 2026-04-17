local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Packages = ReplicatedStorage.Packages
local Knit = require(Packages.Knit)
local Trove = require(Packages.Trove)

local NPC_COUNT = 6
local DROP_HEIGHT = 50

local DEFAULT_SCRIPTS = {
	"Animate", "Health", "ChatScript", "BubbleChat", "ChatServiceRunner",
}

local GraviBowNPCService = Knit.CreateService({
	Name = "GraviBowNPCService",
	Client = {},

	_trove = nil,
	_npcFolder = nil,
	_npcs = {},
	_ownerPlayer = nil,
})

function GraviBowNPCService:KnitInit()
	self._trove = Trove.new()
end

function GraviBowNPCService:KnitStart()
	do return end -- bots disabled

	self._terrainService = Knit.GetService("GraviBowTerrainService")

	local planet = self._terrainService:GetSharedPlanet()
	if not planet then
		planet = self._terrainService:CreateSharedPlanet()
	end
	if not planet then
		warn("[GraviBowNPCService] No shared planet; NPCs not spawned")
		return
	end

	self._npcFolder = Instance.new("Folder")
	self._npcFolder.Name = "GraviNPCs"
	self._npcFolder.Parent = Workspace

	for i = 1, NPC_COUNT do
		self:_spawnNPC(i, planet)
	end
	print("[GraviBowNPCService] Spawned", NPC_COUNT, "NPCs on planet surface")

	self._trove:Add(Players.PlayerAdded:Connect(function(player)
		self:_tryAssignOwnership(player)
	end), "Disconnect")

	for _, player in ipairs(Players:GetPlayers()) do
		self:_tryAssignOwnership(player)
	end

	self._trove:Add(Players.PlayerRemoving:Connect(function(player)
		if self._ownerPlayer == player then
			self._ownerPlayer = nil
			for _, p in ipairs(Players:GetPlayers()) do
				if p ~= player then
					self:_tryAssignOwnership(p)
					break
				end
			end
		end
	end), "Disconnect")
end

function GraviBowNPCService:_tryAssignOwnership(player)
	if self._ownerPlayer then return end
	self._ownerPlayer = player

	task.defer(function()
		for _, npc in ipairs(self._npcs) do
			local hrp = npc:FindFirstChild("HumanoidRootPart")
			if hrp then
				pcall(function()
					hrp:SetNetworkOwner(player)
				end)
			end
		end
		print("[GraviBowNPCService] Network ownership assigned to", player.Name)
	end)
end

function GraviBowNPCService:_randomTangent(radial)
	local rand = Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5)
	local t = rand - radial * rand:Dot(radial)
	if t.Magnitude < 0.01 then
		t = radial:Cross(Vector3.new(0, 1, 0))
	end
	return t.Unit
end

function GraviBowNPCService:_surfaceSpawnPosition(center, radialOut, planet)
	local noiseAmp = planet.noiseAmplitude or 20
	local rayStartDist = planet.radius + noiseAmp + 100
	local origin = center + radialOut * rayStartDist
	local dir = (center - origin).Unit * (rayStartDist + 250)

	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	local exclude = {}
	if self._npcFolder then table.insert(exclude, self._npcFolder) end
	local gzFolder = Workspace:FindFirstChild("GravityZones")
	if gzFolder then table.insert(exclude, gzFolder) end
	local tpFolder = Workspace:FindFirstChild("TerrainPlanets")
	if tpFolder then table.insert(exclude, tpFolder) end
	local snakes = Workspace:FindFirstChild("SnakeBodies")
	if snakes then table.insert(exclude, snakes) end
	rayParams.FilterDescendantsInstances = exclude

	local result = Workspace:Raycast(origin, dir, rayParams)
	if result then
		return result.Position + result.Normal * 4
	end
	return center + radialOut * (planet.radius + DROP_HEIGHT)
end

function GraviBowNPCService:_spawnNPC(index, planet)
	local center = planet.center

	local angle = math.random() * math.pi * 2
	local phi = math.acos(2 * math.random() - 1)
	local radial = Vector3.new(
		math.sin(phi) * math.cos(angle),
		math.cos(phi),
		math.sin(phi) * math.sin(angle)
	).Unit

	local spawnPos = self:_surfaceSpawnPosition(center, radial, planet)
	local character = self:_buildCharacter(index)
	if not character then return end

	local hrp = character:FindFirstChild("HumanoidRootPart")
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not hrp or not humanoid then
		warn("[GraviBowNPCService] Rig prefab missing HumanoidRootPart or Humanoid")
		character:Destroy()
		return
	end

	self:_stripDefaultScripts(character)
	self:_muteCharacterSounds(character)

	for _, state in ipairs(Enum.HumanoidStateType:GetEnumItems()) do
		if state ~= Enum.HumanoidStateType.None then
			pcall(function() humanoid:SetStateEnabled(state, false) end)
		end
	end
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Physics, true)
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Dead, true)

	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.Viewer
	humanoid.DisplayName = "Villager"
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	humanoid.MaxHealth = 100
	humanoid.Health = 100
	humanoid.AutoRotate = false
	humanoid.PlatformStand = true
	humanoid.WalkSpeed = 0
	humanoid.JumpPower = 0
	humanoid.JumpHeight = 0

	local rootJoint = hrp:FindFirstChild("RootJoint")
		or hrp:FindFirstChildOfClass("Motor6D")
	if rootJoint then
		rootJoint.Enabled = true
	end

	self:_setPartFriction(character)

	local lookDir = self:_randomTangent(radial)
	hrp.CFrame = CFrame.lookAt(spawnPos, spawnPos + lookDir, radial)
	hrp.AssemblyLinearVelocity = Vector3.zero
	hrp.AssemblyAngularVelocity = Vector3.zero

	local attachment = hrp:FindFirstChild("GravityAttachment")
	if not attachment then
		attachment = Instance.new("Attachment")
		attachment.Name = "GravityAttachment"
		attachment.Parent = hrp
	end

	local centerAttachment = hrp:FindFirstChild("CenterAttachment")
	if not centerAttachment then
		centerAttachment = Instance.new("Attachment")
		centerAttachment.Name = "CenterAttachment"
		centerAttachment.Position = Vector3.zero
		centerAttachment.Parent = hrp
	end

	local vectorForce = Instance.new("VectorForce")
	vectorForce.Name = "GravityForce"
	vectorForce.Attachment0 = attachment
	vectorForce.RelativeTo = Enum.ActuatorRelativeTo.World
	vectorForce.ApplyAtCenterOfMass = true
	vectorForce.Force = Vector3.zero
	vectorForce.Parent = hrp

	character.Parent = self._npcFolder
	table.insert(self._npcs, character)
end

function GraviBowNPCService:_buildCharacter(index)
	local prefabs = ReplicatedStorage:FindFirstChild("prefabs") or ReplicatedStorage:FindFirstChild("Prefabs")
	if not prefabs then
		warn("[GraviBowNPCService] No prefabs folder in ReplicatedStorage")
		return nil
	end

	local rigPrefab = prefabs:FindFirstChild("Rig")
	if not rigPrefab then
		warn("[GraviBowNPCService] No 'Rig' model found in prefabs folder")
		return nil
	end

	local character = rigPrefab:Clone()
	character.Name = "GraviNPC_" .. index
	return character
end

function GraviBowNPCService:_setPartFriction(character)
	for _, part in ipairs(character:GetDescendants()) do
		if part:IsA("BasePart") then
			part.CustomPhysicalProperties = PhysicalProperties.new(0.7, 0, 0, 100, 0)
		end
	end
end

function GraviBowNPCService:_stripDefaultScripts(character)
	for _, scriptName in ipairs(DEFAULT_SCRIPTS) do
		local child = character:FindFirstChild(scriptName)
		if child then child:Destroy() end
	end

	for _, desc in ipairs(character:GetDescendants()) do
		if desc:IsA("LocalScript") or desc:IsA("Script") then
			local dominated = false
			for _, s in ipairs(DEFAULT_SCRIPTS) do
				if desc.Name == s then dominated = true; break end
			end
			if not dominated and desc.Parent == character then
				desc:Destroy()
			end
		end
	end
end

function GraviBowNPCService:_muteCharacterSounds(character)
	local function removeSounds(parent)
		for _, child in ipairs(parent:GetDescendants()) do
			if child:IsA("Sound") then
				child.Volume = 0
				child:Stop()
				child:Destroy()
			end
		end
	end

	removeSounds(character)

	character.DescendantAdded:Connect(function(desc)
		if desc:IsA("Sound") then
			desc.Volume = 0
			desc:Stop()
			task.defer(function()
				if desc.Parent then desc:Destroy() end
			end)
		end
	end)
end

function GraviBowNPCService:GetNPCFolder()
	return self._npcFolder
end

return GraviBowNPCService
