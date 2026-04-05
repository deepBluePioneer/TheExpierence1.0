local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Packages = ReplicatedStorage.Packages
local CustomPackages = ReplicatedStorage:WaitForChild("CustomPackages")
local Knit = require(Packages.Knit)
local Trove = require(Packages.Trove)
local ZoneRoot = CustomPackages:WaitForChild("ZoneRoot")
local Zone = require(ZoneRoot:WaitForChild("Zone"))

local PLANET_TAG = "planet"
local HUB_PLANET_TAG = "planetHub"
local TOOL_TAG = "tool"
local GRAVITY_ZONE_MULTIPLIER = 1.8
local ZONE_TRANSPARENCY = 0.85
local ZONE_COLOR = Color3.fromRGB(100, 150, 255)
local HUB_ZONE_COLOR = Color3.fromRGB(100, 255, 150)

local ReplicaService = require(CustomPackages.Replica.ReplicaService)

local ITEM_COSTS = {
	Harvester = 1,
}

local HARVESTER_TAG = "harvester"
local HARVESTER_POLL_INTERVAL = 0.4
local HARVESTER_ARRIVE_DIST = 12
local HARVESTER_MINE_DURATION = 3
local HARVESTER_SEARCH_RADIUS = 500
local HARVESTER_BEAM_COLOR = ColorSequence.new(Color3.fromRGB(255, 200, 50), Color3.fromRGB(255, 100, 20))

local GraviBowPlayerService = Knit.CreateService({
	Name = "GraviBowPlayerService",
	Client = {
		ArrowHit = Knit.CreateSignal(),
		ArrowFired = Knit.CreateSignal(),
		HomingArrowFired = Knit.CreateSignal(),
		ActivePlanetChanged = Knit.CreateSignal(),
		ToolPickedUp = Knit.CreateSignal(),
		CrystalMined = Knit.CreateSignal(),
		PurchaseItem = Knit.CreateSignal(),
		ItemPurchased = Knit.CreateSignal(),
		DropHarvester = Knit.CreateSignal(),
		HarvesterTarget = Knit.CreateSignal(),
		HarvesterMining = Knit.CreateSignal(),
	},

	_playerTroves = {},
	_planets = {},
	_hubPlanets = {},
	_playerActivePlanets = {},
	_playerInventory = {},
	_zoneFolder = nil,
	_oreClassToken = nil,
	_oreReplicas = {},
	_playerHarvesters = {},
	_claimedCrystals = {},
})

function GraviBowPlayerService:KnitInit()
	self._trove = Trove.new()
end

function GraviBowPlayerService:KnitStart()
	Workspace.Gravity = 0

	local baseplate = Workspace:FindFirstChild("Baseplate")
	if baseplate then
		baseplate:Destroy()
	end

	self:_setupLighting()
	self:_setupPlanetZones()
	self:_setupHubPlanetZones()
	self:_setupToolPickups()
	self:_initOreReplica()

	self._matchService = Knit.GetService("GraviBowMatchService")

	self._trove:Add(Players.PlayerAdded:Connect(function(player)
		self:_onPlayerAdded(player)
	end), "Disconnect")

	self._trove:Add(Players.PlayerRemoving:Connect(function(player)
		self:_onPlayerRemoving(player)
	end), "Disconnect")

	self.Client.ArrowHit:Connect(function(shooter, victimPlayer)
		self:_onArrowHit(shooter, victimPlayer)
	end)

	self.Client.ArrowFired:Connect(function(shooter, spawnPos, aimDir, speed, accel)
		for _, player in ipairs(Players:GetPlayers()) do
			if player ~= shooter then
				self.Client.ArrowFired:Fire(player, shooter, spawnPos, aimDir, speed, accel)
			end
		end
	end)

	self.Client.HomingArrowFired:Connect(function(shooter, spawnPos, upDir, targetPositions)
		for _, player in ipairs(Players:GetPlayers()) do
			if player ~= shooter then
				self.Client.HomingArrowFired:Fire(player, shooter, spawnPos, upDir, targetPositions)
			end
		end
	end)

	self.Client.CrystalMined:Connect(function(player)
		self:_onCrystalMined(player)
	end)

	self.Client.PurchaseItem:Connect(function(player, itemName)
		self:_onPurchaseItem(player, itemName)
	end)

	self.Client.DropHarvester:Connect(function(player, harvester, dropPos, lookDir)
		self:_onDropHarvester(player, harvester, dropPos, lookDir)
	end)

	for _, player in ipairs(Players:GetPlayers()) do
		self:_onPlayerAdded(player)
	end
end

function GraviBowPlayerService:_onArrowHit(shooter, victimPlayer)
	if not victimPlayer or not victimPlayer:IsA("Player") then return end
	if victimPlayer == shooter then return end

	if self._matchService and self._matchService:GetPhase() ~= "GAME_ACTIVE" then
		return
	end

	local character = victimPlayer.Character
	if not character then return end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then return end

	if self._matchService then
		self._matchService:RecordHit(shooter)
	end

	humanoid.Health = 0

	if self._matchService then
		self._matchService:RecordKill(shooter, victimPlayer)
	end
end

function GraviBowPlayerService:_onPlayerAdded(player)
	self:_createOreReplica(player)

	local function onCharacterAdded(character)
		self:_setupCharacter(player, character)
	end

	local charConn = player.CharacterAdded:Connect(onCharacterAdded)

	if not self._playerTroves[player] then
		self._playerTroves[player] = Trove.new()
	end
	self._playerTroves[player]:Add(charConn, "Disconnect")

	if player.Character then
		onCharacterAdded(player.Character)
	end
end

local SPECTATE_TIME = 3

function GraviBowPlayerService:_onPlayerDied(player)
	task.delay(SPECTATE_TIME, function()
		if not player.Parent then return end
		player:LoadCharacter()
	end)
end

function GraviBowPlayerService:_setupLighting()
	Lighting.ClockTime = 14
	Lighting.GeographicLatitude = 0
	Lighting.Brightness = 3
	Lighting.Ambient = Color3.fromRGB(40, 40, 50)
	Lighting.OutdoorAmbient = Color3.fromRGB(70, 70, 90)
	Lighting.ColorShift_Top = Color3.fromRGB(230, 220, 255)
	Lighting.ColorShift_Bottom = Color3.fromRGB(30, 30, 50)
	Lighting.EnvironmentDiffuseScale = 0.5
	Lighting.EnvironmentSpecularScale = 0.8
	Lighting.ExposureCompensation = 0.3
	Lighting.GlobalShadows = true
	Lighting.ShadowSoftness = 0.3

	for _, child in ipairs(Lighting:GetChildren()) do
		if child:IsA("Sky") or child:IsA("Atmosphere") or child:IsA("BloomEffect")
			or child:IsA("ColorCorrectionEffect") or child:IsA("SunRaysEffect") then
			child:Destroy()
		end
	end

	local sky = Instance.new("Sky")
	sky.SkyboxBk = "rbxassetid://1012890"
	sky.SkyboxDn = "rbxassetid://1012891"
	sky.SkyboxFt = "rbxassetid://1012887"
	sky.SkyboxLf = "rbxassetid://1012889"
	sky.SkyboxRt = "rbxassetid://1012888"
	sky.SkyboxUp = "rbxassetid://1014449"
	sky.StarCount = 5000
	sky.MoonAngularSize = 8
	sky.SunAngularSize = 15
	sky.CelestialBodiesShown = true
	sky.Parent = Lighting

	local atmosphere = Instance.new("Atmosphere")
	atmosphere.Density = 0.05
	atmosphere.Offset = 0
	atmosphere.Color = Color3.fromRGB(20, 20, 35)
	atmosphere.Decay = Color3.fromRGB(30, 30, 50)
	atmosphere.Glare = 0.2
	atmosphere.Haze = 0.5
	atmosphere.Parent = Lighting

	local bloom = Instance.new("BloomEffect")
	bloom.Intensity = 0.5
	bloom.Size = 30
	bloom.Threshold = 1.5
	bloom.Parent = Lighting

	local cc = Instance.new("ColorCorrectionEffect")
	cc.Brightness = 0.05
	cc.Contrast = 0.15
	cc.Saturation = 0.1
	cc.TintColor = Color3.fromRGB(245, 240, 255)
	cc.Parent = Lighting

	local sunRays = Instance.new("SunRaysEffect")
	sunRays.Intensity = 0.15
	sunRays.Spread = 0.8
	sunRays.Parent = Lighting

end

function GraviBowPlayerService:_onPlayerRemoving(player)
	local trove = self._playerTroves[player]
	if trove then
		trove:Clean()
		self._playerTroves[player] = nil
	end
	self._playerActivePlanets[player] = nil
	self._playerInventory[player] = nil
	self:_destroyOreReplica(player)
end

function GraviBowPlayerService:_setupCharacter(player, character)
	local humanoid = character:WaitForChild("Humanoid", 10)
	local hrp = character:WaitForChild("HumanoidRootPart", 10)
	if not humanoid or not hrp then return end

	self:_stripDefaultScripts(character)
	self:_muteCharacterSounds(character)

	for _, state in ipairs(Enum.HumanoidStateType:GetEnumItems()) do
		if state ~= Enum.HumanoidStateType.None then
			pcall(function()
				humanoid:SetStateEnabled(state, false)
			end)
		end
	end
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Physics, true)
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Dead, true)

	humanoid.AutoRotate = false
	humanoid.PlatformStand = true
	humanoid.WalkSpeed = 0
	humanoid.JumpPower = 0
	humanoid.JumpHeight = 0

	humanoid.Died:Once(function()
		self:_onPlayerDied(player)
	end)

	local rootJoint = hrp:FindFirstChild("RootJoint")
		or hrp:FindFirstChildOfClass("Motor6D")
	if rootJoint then
		rootJoint.Enabled = true
	end

	self:_setPartFriction(character)

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
		centerAttachment.Position = Vector3.new(0, 0, 0)
		centerAttachment.Parent = hrp
	end

	local vectorForce = Instance.new("VectorForce")
	vectorForce.Name = "GravityForce"
	vectorForce.Attachment0 = attachment
	vectorForce.RelativeTo = Enum.ActuatorRelativeTo.World
	vectorForce.ApplyAtCenterOfMass = true
	vectorForce.Force = Vector3.zero
	vectorForce.Parent = hrp

	self:_setupLeftHandGrip(character)

	local hubPlanet = self:GetHubPlanet()
	if not hubPlanet then
		for _ = 1, 120 do
			task.wait(0.25)
			hubPlanet = self:GetHubPlanet()
			if hubPlanet then break end
		end
	end
	if hubPlanet then
		self:_dropPlayerOnPlanet(player, hubPlanet)
	else
		warn("[GraviBowPlayerService] Hub planet never registered; cannot teleport", player.Name)
	end
end

function GraviBowPlayerService:_setupLeftHandGrip(character)
	local leftHand = character:FindFirstChild("LeftHand", true)
	local rightHand = character:FindFirstChild("RightHand", true)
	if not leftHand or not rightHand then return end

	local function isBowTool(tool)
		return tool:IsA("Tool") and tool.Name:lower() == "bow"
	end

	local function attachTool(tool)
		if not isBowTool(tool) then return end

		local handle = tool:FindFirstChild("Handle")
		if not handle then return end

		task.defer(function()
			local rg = rightHand:FindFirstChild("RightGrip")
			if rg then rg:Destroy() end

			local existing = leftHand:FindFirstChild("LeftGrip")
			if existing then existing:Destroy() end

			handle.Anchored = false
			handle.CanCollide = false
			handle.Massless = true

			local weld = Instance.new("Weld")
			weld.Name = "LeftGrip"
			weld.Part0 = leftHand
			weld.Part1 = handle
			weld.C0 = CFrame.Angles(0, math.rad(90), math.rad(-90)) * CFrame.Angles(0, 0, math.rad(20))
			weld.C1 = tool.Grip
			weld.Parent = leftHand
		end)
	end

	local function detachTool(tool)
		if not isBowTool(tool) then return end
		local grip = leftHand:FindFirstChild("LeftGrip")
		if grip then grip:Destroy() end
	end

	for _, child in ipairs(character:GetChildren()) do
		attachTool(child)
	end

	character.ChildAdded:Connect(attachTool)
	character.ChildRemoved:Connect(detachTool)
end

function GraviBowPlayerService:_setupPlanetZones()
	self._zoneFolder = Instance.new("Folder")
	self._zoneFolder.Name = "GravityZones"
	self._zoneFolder.Parent = Workspace

	local tagged = CollectionService:GetTagged(PLANET_TAG)
	print("[GraviBowPlayerService] Found", #tagged, "instances with tag '" .. PLANET_TAG .. "'")
	for i, instance in ipairs(tagged) do
		print("[GraviBowPlayerService]  ", i, instance:GetFullName(), "IsA:", instance.ClassName)
		self:_registerPlanet(instance)
	end

	CollectionService:GetInstanceAddedSignal(PLANET_TAG):Connect(function(instance)
		print("[GraviBowPlayerService] Tag added to:", instance:GetFullName())
		self:_registerPlanet(instance)
	end)

	CollectionService:GetInstanceRemovedSignal(PLANET_TAG):Connect(function(instance)
		self:_unregisterPlanet(instance)
	end)
end

function GraviBowPlayerService:_getPlanetPart(model)
	if model:IsA("BasePart") then
		return model
	end
	if model:IsA("Model") and model.PrimaryPart then
		return model.PrimaryPart
	end
	return model:FindFirstChildWhichIsA("BasePart", true)
end

function GraviBowPlayerService:_registerPlanet(model)
	if self._planets[model] then return end

	local part = self:_getPlanetPart(model)
	if not part then
		print("[GraviBowPlayerService] No BasePart yet for", model:GetFullName(), "- waiting...")
		task.spawn(function()
			while model.Parent and not self:_getPlanetPart(model) do
				local desc = model.DescendantAdded:Wait()
				if desc:IsA("BasePart") then
					break
				end
			end
			if model.Parent and not self._planets[model] then
				print("[GraviBowPlayerService] BasePart found for", model:GetFullName(), "- retrying registration")
				self:_registerPlanet(model)
			end
		end)
		return
	end

	local center = part.Position
	local radius = math.max(part.Size.X, part.Size.Y, part.Size.Z) / 2
	print("[GraviBowPlayerService] Registered planet:", model.Name, "center:", center, "radius:", radius)
	local zoneRadius = radius * GRAVITY_ZONE_MULTIPLIER
	local zoneDiameter = zoneRadius * 2

	local zonePart = Instance.new("Part")
	zonePart.Name = model.Name .. "_GravityZone"
	zonePart.Shape = Enum.PartType.Ball
	zonePart.Size = Vector3.new(zoneDiameter, zoneDiameter, zoneDiameter)
	zonePart.Position = center
	zonePart.Anchored = true
	zonePart.CanCollide = false
	zonePart.CanQuery = true
	zonePart.CanTouch = true
	zonePart.Transparency = ZONE_TRANSPARENCY
	zonePart.Color = ZONE_COLOR
	zonePart.Material = Enum.Material.ForceField
	zonePart.Parent = self._zoneFolder

	local zone = Zone.new(zonePart)

	local planetData = {
		model = model,
		center = center,
		radius = radius,
		zonePart = zonePart,
		zone = zone,
	}

	self._planets[model] = planetData

	zone.playerEntered:Connect(function(player)
		print("[GraviBowPlayerService] Player", player.Name, "entered zone:", model.Name)
		self._playerActivePlanets[player] = planetData
		self.Client.ActivePlanetChanged:Fire(player, model)
	end)

	zone.playerExited:Connect(function(player)
		print("[GraviBowPlayerService] Player", player.Name, "exited zone:", model.Name)
		if self._playerActivePlanets[player] == planetData then
			self._playerActivePlanets[player] = nil
			self.Client.ActivePlanetChanged:Fire(player, nil)
		end
	end)
end

function GraviBowPlayerService:_unregisterPlanet(model)
	local planetData = self._planets[model]
	if not planetData then return end

	for player, activePlanet in pairs(self._playerActivePlanets) do
		if activePlanet == planetData then
			self._playerActivePlanets[player] = nil
			self.Client.ActivePlanetChanged:Fire(player, nil)
		end
	end

	if planetData.zone then
		planetData.zone:destroy()
	end
	if planetData.zonePart then
		planetData.zonePart:Destroy()
	end

	self._planets[model] = nil
end

function GraviBowPlayerService:_setupHubPlanetZones()
	local tagged = CollectionService:GetTagged(HUB_PLANET_TAG)
	print("[GraviBowPlayerService] Found", #tagged, "instances with tag '" .. HUB_PLANET_TAG .. "'")
	for i, instance in ipairs(tagged) do
		print("[GraviBowPlayerService]  ", i, instance:GetFullName(), "IsA:", instance.ClassName)
		self:_registerHubPlanet(instance)
	end

	CollectionService:GetInstanceAddedSignal(HUB_PLANET_TAG):Connect(function(instance)
		print("[GraviBowPlayerService] Hub tag added to:", instance:GetFullName())
		self:_registerHubPlanet(instance)
	end)
end

function GraviBowPlayerService:_registerHubPlanet(model)
	if self._hubPlanets[model] then return end

	local part = self:_getPlanetPart(model)
	if not part then
		task.spawn(function()
			while model.Parent and not self:_getPlanetPart(model) do
				local desc = model.DescendantAdded:Wait()
				if desc:IsA("BasePart") then break end
			end
			if model.Parent and not self._hubPlanets[model] then
				self:_registerHubPlanet(model)
			end
		end)
		return
	end

	local center = part.Position
	local radius = math.max(part.Size.X, part.Size.Y, part.Size.Z) / 2
	print("[GraviBowPlayerService] Registered hub planet:", model.Name, "center:", center, "radius:", radius)

	local zoneRadius = radius * GRAVITY_ZONE_MULTIPLIER
	local zoneDiameter = zoneRadius * 2

	local zonePart = Instance.new("Part")
	zonePart.Name = model.Name .. "_HubGravityZone"
	zonePart.Shape = Enum.PartType.Ball
	zonePart.Size = Vector3.new(zoneDiameter, zoneDiameter, zoneDiameter)
	zonePart.Position = center
	zonePart.Anchored = true
	zonePart.CanCollide = false
	zonePart.CanQuery = true
	zonePart.CanTouch = true
	zonePart.Transparency = ZONE_TRANSPARENCY
	zonePart.Color = HUB_ZONE_COLOR
	zonePart.Material = Enum.Material.ForceField
	zonePart.Parent = self._zoneFolder

	local zone = Zone.new(zonePart)

	local planetData = {
		model = model,
		center = center,
		radius = radius,
		zonePart = zonePart,
		zone = zone,
	}

	self._hubPlanets[model] = planetData

	zone.playerEntered:Connect(function(player)
		print("[GraviBowPlayerService] Player", player.Name, "entered hub zone:", model.Name)
		self._playerActivePlanets[player] = planetData
		self.Client.ActivePlanetChanged:Fire(player, model)
	end)

	zone.playerExited:Connect(function(player)
		print("[GraviBowPlayerService] Player", player.Name, "exited hub zone:", model.Name)
		if self._playerActivePlanets[player] == planetData then
			self._playerActivePlanets[player] = nil
			self.Client.ActivePlanetChanged:Fire(player, nil)
		end
	end)
end

function GraviBowPlayerService:GetHubPlanet()
	local _, data = next(self._hubPlanets)
	return data
end

function GraviBowPlayerService:GetGamePlanets()
	local list = {}
	for _, data in pairs(self._planets) do
		table.insert(list, data)
	end
	return list
end

function GraviBowPlayerService:SetBowEnabled(_player, _enabled)
	-- Legacy no-op; tool availability is now managed by the pickup/inventory system
end

function GraviBowPlayerService:_setupToolPickups()
	local function setupPrompt(tool)
		if not tool:IsA("Tool") then return end

		local handle = tool:WaitForChild("Handle", 5)
		if not handle then
			warn("[GraviBowPlayerService] Tool", tool.Name, "has no Handle, skipping prompt")
			return
		end

		handle.CanTouch = false

		local toolName = tool.Name:lower()

		local prompt = Instance.new("ProximityPrompt")
		prompt.ActionText = "Pick Up"
		prompt.ObjectText = tool.Name
		prompt.KeyboardKeyCode = Enum.KeyCode.E
		prompt.HoldDuration = 0.3
		prompt.MaxActivationDistance = 12
		prompt.RequiresLineOfSight = false
		prompt.Parent = handle

		prompt.Triggered:Connect(function(player)
			if not self._playerInventory[player] then
				self._playerInventory[player] = {}
			end

			for _, existing in ipairs(self._playerInventory[player]) do
				if existing == toolName then
					return
				end
			end

			local backpack = player:FindFirstChild("Backpack")
			if not backpack then return end

			local clone = tool:Clone()
			for _, desc in ipairs(clone:GetDescendants()) do
				if desc:IsA("ProximityPrompt") then
					desc:Destroy()
				end
			end
			clone.Parent = backpack

			table.insert(self._playerInventory[player], toolName)
			self.Client.ToolPickedUp:Fire(player, toolName)

			tool:Destroy()

			for _, otherTool in ipairs(CollectionService:GetTagged(TOOL_TAG)) do
				if otherTool:IsA("Tool") and otherTool.Name:lower() == toolName then
					local otherHandle = otherTool:FindFirstChild("Handle")
					if otherHandle then
						local otherPrompt = otherHandle:FindFirstChildOfClass("ProximityPrompt")
						if otherPrompt then
							otherPrompt.Enabled = false
						end
					end
				end
			end

			print("[GraviBowPlayerService] Player", player.Name, "picked up:", toolName)
		end)
	end

	for _, instance in ipairs(CollectionService:GetTagged(TOOL_TAG)) do
		setupPrompt(instance)
	end

	CollectionService:GetInstanceAddedSignal(TOOL_TAG):Connect(function(instance)
		setupPrompt(instance)
	end)
end

function GraviBowPlayerService:GetPlayerInventory(player)
	return self._playerInventory[player] or {}
end

local DROP_HEIGHT = 50

function GraviBowPlayerService:_dropPlayerOnPlanet(player, planetData)
	local character = player.Character
	if not character then return end
	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not hrp then return end

	local center = planetData.center
	local radius = planetData.radius

	local angle = math.random() * math.pi * 2
	local phi = math.acos(2 * math.random() - 1)
	local upDir = Vector3.new(
		math.sin(phi) * math.cos(angle),
		math.cos(phi),
		math.sin(phi) * math.sin(angle)
	).Unit

	local spawnPos = center + upDir * (radius + DROP_HEIGHT)

	local lookDir = upDir:Cross(Vector3.new(0, 0, 1))
	if lookDir.Magnitude < 0.01 then
		lookDir = upDir:Cross(Vector3.new(1, 0, 0))
	end
	lookDir = lookDir.Unit

	hrp.CFrame = CFrame.lookAt(spawnPos, spawnPos + lookDir, upDir)
	hrp.AssemblyLinearVelocity = Vector3.zero
	hrp.AssemblyAngularVelocity = Vector3.zero

	self.Client.ActivePlanetChanged:Fire(player, planetData.model)
end

function GraviBowPlayerService:TeleportPlayerToPlanet(player, planetData)
	local character = player.Character
	if not character then return end
	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not hrp then return end

	local center = planetData.center
	local radius = planetData.radius

	local angle = math.random() * math.pi * 2
	local phi = math.acos(2 * math.random() - 1)
	local upDir = Vector3.new(
		math.sin(phi) * math.cos(angle),
		math.cos(phi),
		math.sin(phi) * math.sin(angle)
	).Unit

	local rayOrigin = center + upDir * (radius + 60)
	local rayDirection = -upDir * 120

	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	local filterInstances = { character }
	local gzFolder = Workspace:FindFirstChild("GravityZones")
	if gzFolder then table.insert(filterInstances, gzFolder) end
	local tpFolder = Workspace:FindFirstChild("TerrainPlanets")
	if tpFolder then table.insert(filterInstances, tpFolder) end
	rayParams.FilterDescendantsInstances = filterInstances

	local result = Workspace:Raycast(rayOrigin, rayDirection, rayParams)

	local surfacePos
	if result then
		surfacePos = result.Position + upDir * 5
	else
		surfacePos = center + upDir * (radius + 10)
	end

	local lookDir = upDir:Cross(Vector3.new(0, 0, 1))
	if lookDir.Magnitude < 0.01 then
		lookDir = upDir:Cross(Vector3.new(1, 0, 0))
	end
	lookDir = lookDir.Unit

	hrp.CFrame = CFrame.lookAt(surfacePos, surfacePos + lookDir, upDir)
	hrp.AssemblyLinearVelocity = Vector3.zero
	hrp.AssemblyAngularVelocity = Vector3.zero

	self.Client.ActivePlanetChanged:Fire(player, planetData.model)
end

function GraviBowPlayerService:TeleportPlayerToHub(player)
	local hubPlanet = self:GetHubPlanet()
	if not hubPlanet then
		warn("[GraviBowPlayerService] No hub planet found for teleport")
		return
	end
	self:_dropPlayerOnPlanet(player, hubPlanet)
end

function GraviBowPlayerService:_setPartFriction(character)
	for _, part in ipairs(character:GetDescendants()) do
		if part:IsA("BasePart") then
			part.CustomPhysicalProperties = PhysicalProperties.new(
				0.7, -- density
				0,   -- friction
				0,   -- elasticity
				100, -- frictionWeight (high to override other contacts)
				0    -- elasticityWeight
			)
		end
	end
end

function GraviBowPlayerService:_muteCharacterSounds(character)
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
				if desc.Parent then
					desc:Destroy()
				end
			end)
		end
	end)
end

local DEFAULT_SCRIPTS = {
	"Animate",
	"Health",
	"ChatScript",
	"BubbleChat",
	"ChatServiceRunner",
}

function GraviBowPlayerService:_stripDefaultScripts(character)
	for _, scriptName in ipairs(DEFAULT_SCRIPTS) do
		local child = character:FindFirstChild(scriptName)
		if child then
			child:Destroy()
		end
	end

	for _, desc in ipairs(character:GetDescendants()) do
		if desc:IsA("LocalScript") or desc:IsA("Script") then
			local name = desc.Name
			local dominated = false
			for _, s in ipairs(DEFAULT_SCRIPTS) do
				if name == s then dominated = true; break end
			end
			if not dominated and desc.Parent == character then
				desc:Destroy()
			end
		end
	end
end

function GraviBowPlayerService:_initOreReplica()
	self._oreClassToken = ReplicaService.NewClassToken("GraviBowOreState")
	self._oreReplicas = {}
end

function GraviBowPlayerService:_createOreReplica(player)
	if self._oreReplicas[player] then return end
	local replica = ReplicaService.NewReplica({
		ClassToken = self._oreClassToken,
		Data = { ore = 0 },
		Replication = { [player] = true },
	})
	self._oreReplicas[player] = replica
end

function GraviBowPlayerService:_destroyOreReplica(player)
	local replica = self._oreReplicas[player]
	if replica then
		replica:Destroy()
		self._oreReplicas[player] = nil
	end
end

function GraviBowPlayerService:_onCrystalMined(player)
	local replica = self._oreReplicas[player]
	if not replica then return end
	local current = replica.Data.ore or 0
	replica:SetValue({"ore"}, current + 1)
end

function GraviBowPlayerService:GetPlayerOre(player)
	local replica = self._oreReplicas[player]
	return replica and replica.Data.ore or 0
end

function GraviBowPlayerService:_onPurchaseItem(player, itemName)
	if type(itemName) ~= "string" then return end

	local cost = ITEM_COSTS[itemName]
	if not cost then
		warn("[GraviBowPlayerService] Unknown item:", itemName)
		return
	end

	local currentOre = self:GetPlayerOre(player)
	if currentOre < cost then
		warn("[GraviBowPlayerService] Not enough ore for", itemName, "- has", currentOre, "needs", cost)
		return
	end

	local replica = self._oreReplicas[player]
	if not replica then return end
	replica:SetValue({"ore"}, currentOre - cost)

	if itemName == "Harvester" then
		local harvester = self:_spawnHarvester(player)
		if harvester then
			self.Client.ItemPurchased:Fire(player, itemName, harvester)
			print("[GraviBowPlayerService] Player", player.Name, "purchased Harvester - ore left:", currentOre - cost)
			return
		end
	end

	self.Client.ItemPurchased:Fire(player, itemName, nil)
	print("[GraviBowPlayerService] Player", player.Name, "purchased", itemName, "- ore left:", currentOre - cost)
end

function GraviBowPlayerService:_findHarvesterPrefab()
	local prefabsFolder = ReplicatedStorage:FindFirstChild("prefabs")
	if not prefabsFolder then return nil end

	for _, child in ipairs(prefabsFolder:GetDescendants()) do
		if CollectionService:HasTag(child, HARVESTER_TAG) then
			return child
		end
	end
	for _, child in ipairs(prefabsFolder:GetChildren()) do
		if child.Name:lower() == "harvester" then
			return child
		end
	end
	return nil
end

function GraviBowPlayerService:_spawnHarvester(player)
	local prefab = self:_findHarvesterPrefab()
	if not prefab then
		warn("[GraviBowPlayerService] Could not find harvester prefab")
		return nil
	end

	local clone = prefab:Clone()

	local parts = {}
	if clone:IsA("BasePart") then table.insert(parts, clone) end
	for _, desc in ipairs(clone:GetDescendants()) do
		if desc:IsA("BasePart") then table.insert(parts, desc) end
	end
	for _, part in ipairs(parts) do
		part.Anchored = true
		part.CanCollide = false
		part.CanTouch = false
		part.CanQuery = false
	end

	local character = player.Character
	if character then
		local hrp = character:FindFirstChild("HumanoidRootPart")
		if hrp then
			local spawnPos = hrp.CFrame:PointToWorldSpace(Vector3.new(0, 0, -8))
			if clone:IsA("Model") then
				clone:PivotTo(CFrame.new(spawnPos))
			else
				clone.CFrame = CFrame.new(spawnPos)
			end
		end
	end

	clone.Parent = Workspace

	for _, part in ipairs(parts) do
		pcall(function()
			part:SetNetworkOwner(player)
		end)
	end

	self._playerHarvesters[player] = clone
	return clone
end

function GraviBowPlayerService:_onDropHarvester(player, harvester, dropPos, lookDir)
	if not harvester or not harvester.Parent then return end
	if self._playerHarvesters[player] ~= harvester then return end
	if typeof(dropPos) ~= "Vector3" then return end
	if typeof(lookDir) ~= "Vector3" then return end

	local rootPart
	if harvester:IsA("Model") then
		rootPart = harvester.PrimaryPart or harvester:FindFirstChildWhichIsA("BasePart")
	elseif harvester:IsA("BasePart") then
		rootPart = harvester
	end
	if not rootPart then return end

	local planetCenter = self:_getNearestPlanetCenter(dropPos)
	local upDir = (dropPos - planetCenter)
	upDir = upDir.Magnitude > 0.01 and upDir.Unit or Vector3.new(0, 1, 0)

	local projLook = lookDir - upDir * lookDir:Dot(upDir)
	if projLook.Magnitude < 0.01 then
		projLook = upDir:Cross(Vector3.new(0, 0, 1))
		if projLook.Magnitude < 0.01 then
			projLook = upDir:Cross(Vector3.new(1, 0, 0))
		end
	end
	projLook = projLook.Unit

	local orientedCF = CFrame.lookAt(dropPos, dropPos + projLook, upDir)
	if harvester:IsA("Model") then
		harvester:PivotTo(orientedCF)
	else
		rootPart.CFrame = orientedCF
	end

	local parts = {}
	if harvester:IsA("BasePart") then table.insert(parts, harvester) end
	for _, desc in ipairs(harvester:GetDescendants()) do
		if desc:IsA("BasePart") then table.insert(parts, desc) end
	end
	for _, part in ipairs(parts) do
		part.Anchored = false
		part.CanCollide = true
		part.CanTouch = true
		part.CanQuery = true
		part.CustomPhysicalProperties = PhysicalProperties.new(
			0.7,  -- density
			0.05, -- friction
			0.2,  -- elasticity
			1,    -- frictionWeight
			1     -- elasticityWeight
		)
	end

	task.defer(function()
		for _, part in ipairs(parts) do
			pcall(function() part:SetNetworkOwner(player) end)
		end
	end)

	self:_startHarvesterBehavior(harvester, rootPart, player)
	print("[GraviBowPlayerService] Harvester dropped by", player.Name)
end

function GraviBowPlayerService:_getNearestPlanetCenter(pos)
	local bestDist = math.huge
	local bestCenter = Vector3.zero

	for _, data in pairs(self._planets) do
		local dist = (data.center - pos).Magnitude
		if dist < bestDist then
			bestDist = dist
			bestCenter = data.center
		end
	end
	for _, data in pairs(self._hubPlanets) do
		local dist = (data.center - pos).Magnitude
		if dist < bestDist then
			bestDist = dist
			bestCenter = data.center
		end
	end

	return bestCenter
end

function GraviBowPlayerService:_findNearestCrystal(pos)
	local crystalFolder = Workspace:FindFirstChild("CrystalPatches")
	if not crystalFolder then return nil, math.huge end

	local planetCenter = self:_getNearestPlanetCenter(pos)
	local planetDist = (pos - planetCenter).Magnitude

	local bestDist = HARVESTER_SEARCH_RADIUS
	local bestCrystal = nil

	for _, child in ipairs(crystalFolder:GetChildren()) do
		local crystalPos
		if child:IsA("Model") and child.PrimaryPart then
			crystalPos = child.PrimaryPart.Position
		elseif child:IsA("BasePart") then
			crystalPos = child.Position
		end
		if crystalPos and not self._claimedCrystals[child] then
			local crystalPlanetDist = (crystalPos - planetCenter).Magnitude
			if math.abs(crystalPlanetDist - planetDist) < planetDist * 0.5 then
				local dist = (crystalPos - pos).Magnitude
				if dist < bestDist then
					bestDist = dist
					bestCrystal = child
				end
			end
		end
	end

	return bestCrystal, bestDist
end

function GraviBowPlayerService:_getCrystalPosition(crystal)
	if crystal:IsA("Model") and crystal.PrimaryPart then
		return crystal.PrimaryPart.Position
	elseif crystal:IsA("BasePart") then
		return crystal.Position
	end
	return nil
end

function GraviBowPlayerService:_setCrystalTransparency(crystalModel, progress)
	local t = math.clamp(progress, 0, 1)
	if crystalModel:IsA("BasePart") then
		crystalModel.Transparency = t
	else
		local primary = crystalModel:IsA("Model") and crystalModel.PrimaryPart or nil
		for _, desc in ipairs(crystalModel:GetDescendants()) do
			if desc:IsA("BasePart") and desc ~= primary and desc.Name ~= "harvestPoint" then
				desc.Transparency = t
			end
		end
	end
end

function GraviBowPlayerService:_destroyCrystalWithEffect(crystal)
	if not crystal or not crystal.Parent then return end

	local pos
	if crystal:IsA("Model") and crystal.PrimaryPart then
		pos = crystal.PrimaryPart.Position
	elseif crystal:IsA("BasePart") then
		pos = crystal.Position
	else
		crystal:Destroy()
		return
	end

	local burstPart = Instance.new("Part")
	burstPart.Size = Vector3.new(0.5, 0.5, 0.5)
	burstPart.Transparency = 1
	burstPart.Anchored = true
	burstPart.CanCollide = false
	burstPart.CanQuery = false
	burstPart.CanTouch = false
	burstPart.Position = pos
	burstPart.Parent = Workspace

	local burst = Instance.new("ParticleEmitter")
	burst.Color = ColorSequence.new(Color3.fromRGB(255, 220, 80), Color3.fromRGB(255, 100, 20))
	burst.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.5),
		NumberSequenceKeypoint.new(0.5, 0.2),
		NumberSequenceKeypoint.new(1, 0),
	})
	burst.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.5, 0.4),
		NumberSequenceKeypoint.new(1, 1),
	})
	burst.Lifetime = NumberRange.new(0.4, 0.8)
	burst.Speed = NumberRange.new(5, 15)
	burst.SpreadAngle = Vector2.new(180, 180)
	burst.LightEmission = 1
	burst.LightInfluence = 0
	burst.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	burst.Parent = burstPart

	burst:Emit(30)
	burst.Enabled = false

	task.delay(1, function()
		burstPart:Destroy()
	end)

	crystal:Destroy()
end

function GraviBowPlayerService:_startHarvesterBehavior(obj, rootPart, ownerPlayer)
	local groundRayParams = RaycastParams.new()
	groundRayParams.FilterType = Enum.RaycastFilterType.Exclude
	local groundFilterList = { obj }
	local gzFolder = Workspace:FindFirstChild("GravityZones")
	if gzFolder then table.insert(groundFilterList, gzFolder) end
	local tpFolder = Workspace:FindFirstChild("TerrainPlanets")
	if tpFolder then table.insert(groundFilterList, tpFolder) end
	local cpFolder = Workspace:FindFirstChild("CrystalPatches")
	if cpFolder then table.insert(groundFilterList, cpFolder) end
	groundRayParams.FilterDescendantsInstances = groundFilterList

	self.Client.HarvesterTarget:Fire(ownerPlayer, obj, nil)

	task.spawn(function()
		self:_harvesterBehaviorLoop(obj, rootPart, ownerPlayer, groundRayParams)
	end)
end

function GraviBowPlayerService:_harvesterBehaviorLoop(obj, rootPart, ownerPlayer, groundRayParams)
	local beamInstances = {}

	local function cleanBeam()
		for _, inst in ipairs(beamInstances) do
			if inst and inst.Parent then
				inst:Destroy()
			end
		end
		beamInstances = {}
	end

	local function createBeam(fromPart, toCrystal)
		cleanBeam()

		local targetPart
		if toCrystal:IsA("Model") then
			targetPart = toCrystal:FindFirstChild("harvestPoint")
				or toCrystal.PrimaryPart
		end
		if not targetPart and toCrystal:IsA("BasePart") then
			targetPart = toCrystal
		end
		if not targetPart then return end

		local a0 = Instance.new("Attachment")
		a0.Name = "BeamStart"
		a0.Parent = fromPart
		table.insert(beamInstances, a0)

		local a1 = Instance.new("Attachment")
		a1.Name = "BeamEnd"
		local halfSize = targetPart.Size * 0.5
		a1.Position = Vector3.new(
			(math.random() - 0.5) * halfSize.X,
			(math.random() - 0.5) * halfSize.Y,
			(math.random() - 0.5) * halfSize.Z
		)
		a1.Parent = targetPart
		table.insert(beamInstances, a1)

		local beam = Instance.new("Beam")
		beam.Name = "MineBeam"
		beam.Attachment0 = a0
		beam.Attachment1 = a1
		beam.Color = HARVESTER_BEAM_COLOR
		beam.Width0 = 0.3
		beam.Width1 = 0.15
		beam.LightEmission = 0.8
		beam.LightInfluence = 0.2
		beam.FaceCamera = true
		beam.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(0.8, 0.3),
			NumberSequenceKeypoint.new(1, 0.6),
		})
		beam.Parent = fromPart
		table.insert(beamInstances, beam)

		local emitter = Instance.new("ParticleEmitter")
		emitter.Name = "HarvesterMineParticles"
		emitter.Color = ColorSequence.new(Color3.fromRGB(255, 200, 50), Color3.fromRGB(255, 120, 20))
		emitter.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.25),
			NumberSequenceKeypoint.new(0.5, 0.12),
			NumberSequenceKeypoint.new(1, 0),
		})
		emitter.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(0.7, 0.3),
			NumberSequenceKeypoint.new(1, 1),
		})
		emitter.Lifetime = NumberRange.new(0.3, 0.5)
		emitter.Rate = 40
		emitter.Speed = NumberRange.new(1, 3)
		emitter.SpreadAngle = Vector2.new(30, 30)
		emitter.LightEmission = 0.8
		emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		emitter.Parent = targetPart
		table.insert(beamInstances, emitter)
	end

	print("[Harvester] Behavior loop started, waiting 1s to settle")
	task.wait(1)

	while rootPart and rootPart.Parent do
		local pos = rootPart.Position

		local crystal, dist = self:_findNearestCrystal(pos)

		if not crystal or not crystal.Parent then
			self.Client.HarvesterTarget:Fire(ownerPlayer, obj, nil)
			task.wait(1)
			continue
		end

		self._claimedCrystals[crystal] = true

		local targetPos = self:_getCrystalPosition(crystal)
		if not targetPos then
			self._claimedCrystals[crystal] = nil
			task.wait(0.5)
			continue
		end

		print("[Harvester] Targeting crystal, dist:", string.format("%.1f", dist), "target:", targetPos)
		self.Client.HarvesterTarget:Fire(ownerPlayer, obj, targetPos)

		while crystal and crystal.Parent and rootPart and rootPart.Parent do
			targetPos = self:_getCrystalPosition(crystal)
			if not targetPos then break end

			local harvPos = rootPart.Position
			local flatDist = (targetPos - harvPos).Magnitude

			if flatDist <= HARVESTER_ARRIVE_DIST then
				print("[Harvester] Arrived at crystal, dist:", string.format("%.1f", flatDist))
				self.Client.HarvesterTarget:Fire(ownerPlayer, obj, nil)
				break
			end

			self.Client.HarvesterTarget:Fire(ownerPlayer, obj, targetPos)
			task.wait(HARVESTER_POLL_INTERVAL)
		end

		if not crystal or not crystal.Parent then
			self._claimedCrystals[crystal] = nil
			continue
		end
		if not rootPart or not rootPart.Parent then
			self._claimedCrystals[crystal] = nil
			break
		end

		self.Client.HarvesterTarget:Fire(ownerPlayer, obj, nil)

		createBeam(rootPart, crystal)
		for _, p in ipairs(Players:GetPlayers()) do
			self.Client.HarvesterMining:Fire(p, obj, true)
		end

		local elapsed = 0
		while elapsed < HARVESTER_MINE_DURATION and crystal and crystal.Parent and rootPart and rootPart.Parent do
			elapsed = elapsed + task.wait()
			local progress = math.clamp(elapsed / HARVESTER_MINE_DURATION, 0, 1)
			self:_setCrystalTransparency(crystal, progress)
		end

		for _, p in ipairs(Players:GetPlayers()) do
			self.Client.HarvesterMining:Fire(p, obj, false)
		end
		cleanBeam()

		if crystal and crystal.Parent then
			self:_onCrystalMined(ownerPlayer)
			self:_destroyCrystalWithEffect(crystal)
		end

		self._claimedCrystals[crystal] = nil
		task.wait(0.5)
	end

	self.Client.HarvesterTarget:Fire(ownerPlayer, obj, nil)
	cleanBeam()
end

return GraviBowPlayerService
