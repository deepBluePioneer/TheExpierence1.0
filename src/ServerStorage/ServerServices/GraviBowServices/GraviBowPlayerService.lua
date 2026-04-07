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
local GRAVITY_ZONE_MULTIPLIER = 1.8
local ZONE_TRANSPARENCY = 0.85
local ZONE_COLOR = Color3.fromRGB(100, 150, 255)
local DROP_HEIGHT = 50

local GraviBowPlayerService = Knit.CreateService({
	Name = "GraviBowPlayerService",
	Client = {
		ArrowHit = Knit.CreateSignal(),
		ArrowFired = Knit.CreateSignal(),
		HomingArrowFired = Knit.CreateSignal(),
		ActivePlanetChanged = Knit.CreateSignal(),
	},

	_playerTroves = {},
	_planets = {},
	_playerActivePlanets = {},
	_sharedPlanet = nil,
	_zoneFolder = nil,
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

	self._matchService = Knit.GetService("GraviBowMatchService")
	self._oreService = Knit.GetService("GraviBowOreService")
	self._toolService = Knit.GetService("GraviBowToolService")
	self._terrainService = Knit.GetService("GraviBowTerrainService")

	self._sharedPlanet = self._terrainService:CreateSharedPlanet()
	if not self._sharedPlanet then
		warn("[GraviBowPlayerService] Failed to create shared planet!")
	end

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

	for _, player in ipairs(Players:GetPlayers()) do
		self:_onPlayerAdded(player)
	end
end

function GraviBowPlayerService:_onArrowHit(shooter, victimPlayer)
	if not victimPlayer or not victimPlayer:IsA("Player") then return end
	if victimPlayer == shooter then return end

	if self._matchService and self._matchService:GetPhase() ~= "ROUND_ACTIVE" then
		return
	end

	local character = victimPlayer.Character
	if not character then return end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then return end

	humanoid.Health = 0
end

function GraviBowPlayerService:_onPlayerAdded(player)
	player.DevTouchMovementMode = Enum.DevTouchMovementMode.Scriptable

	self._oreService:CreateOreReplica(player)

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

function GraviBowPlayerService:_onCharacterRespawned(player, character)
	self._matchService = self._matchService or Knit.GetService("GraviBowMatchService")
	local snakeService = Knit.GetService("GraviBowSnakeService")

	if self._matchService:IsSnakePlayer(player) then
		self:_hideAvatar(character)
		task.defer(function()
			if not character.Parent then return end
			snakeService:BuildSnakeForPlayer(player)
		end)
	end
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
	self._toolService:ClearPlayerInventory(player)
	self._oreService:DestroyOreReplica(player)
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

	self._matchService = self._matchService or Knit.GetService("GraviBowMatchService")
	if self._matchService:IsSnakePlayer(player) then
		self:_hideAvatar(character)
	end

	-- local highlight = Instance.new("Highlight")
	-- highlight.FillColor = Color3.fromRGB(255, 200, 50)
	-- highlight.FillTransparency = 0.5
	-- highlight.OutlineColor = Color3.fromRGB(255, 255, 255)
	-- highlight.OutlineTransparency = 0
	-- highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	-- highlight.Parent = character

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

	if self._sharedPlanet then
		self:_dropPlayerOnPlanet(player, {
			model = self._sharedPlanet.anchor,
			center = self._sharedPlanet.center,
			radius = self._sharedPlanet.radius,
		})
	else
		warn("[GraviBowPlayerService] No shared planet - cannot spawn")
	end

	self:_onCharacterRespawned(player, character)
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
	for _, instance in ipairs(tagged) do
		self:_registerPlanet(instance)
	end

	CollectionService:GetInstanceAddedSignal(PLANET_TAG):Connect(function(instance)
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
		task.spawn(function()
			while model.Parent and not self:_getPlanetPart(model) do
				local desc = model.DescendantAdded:Wait()
				if desc:IsA("BasePart") then
					break
				end
			end
			if model.Parent and not self._planets[model] then
				self:_registerPlanet(model)
			end
		end)
		return
	end

	local center = part.Position
	local radius = math.max(part.Size.X, part.Size.Y, part.Size.Z) / 2
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
		self._playerActivePlanets[player] = planetData
		self.Client.ActivePlanetChanged:Fire(player, model)
	end)

	zone.playerExited:Connect(function(player)
		if self._playerActivePlanets[player] == planetData then
			self._playerActivePlanets[player] = nil
			self.Client.ActivePlanetChanged:Fire(player, nil)
		end
	end)

	print("[GraviBowPlayerService] Registered planet:", model.Name, "center:", center, "radius:", radius)
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

function GraviBowPlayerService:TeleportPlayerToOwnPlanet(player)
	if not self._sharedPlanet then
		warn("[GraviBowPlayerService] No shared planet")
		return
	end
	self:_dropPlayerOnPlanet(player, {
		model = self._sharedPlanet.anchor,
		center = self._sharedPlanet.center,
		radius = self._sharedPlanet.radius,
	})
end

function GraviBowPlayerService:GetSharedPlanet()
	return self._sharedPlanet
end

function GraviBowPlayerService:GetGamePlanets()
	local list = {}
	for _, data in pairs(self._planets) do
		table.insert(list, data)
	end
	return list
end

function GraviBowPlayerService:HideAvatar(player)
	local character = player.Character
	if not character then return end
	self:_hideAvatar(character)
end

function GraviBowPlayerService:ShowAvatar(player)
	local character = player.Character
	if not character then return end
	self:_showAvatar(character)
end

function GraviBowPlayerService:_hideAvatar(character)
	character:SetAttribute("AvatarHidden", true)

	local function hideDescendant(desc)
		if desc:IsA("BasePart") then
			desc.Transparency = 1
		elseif desc:IsA("Decal") or desc:IsA("Texture") then
			desc.Transparency = 1
		end
	end

	for _, desc in ipairs(character:GetDescendants()) do
		hideDescendant(desc)
	end

	character.DescendantAdded:Connect(function(desc)
		if character:GetAttribute("AvatarHidden") then
			hideDescendant(desc)
		end
	end)
end

function GraviBowPlayerService:_showAvatar(character)
	character:SetAttribute("AvatarHidden", false)

	for _, desc in ipairs(character:GetDescendants()) do
		if desc:IsA("BasePart") then
			if desc.Name ~= "HumanoidRootPart" then
				desc.Transparency = 0
			end
		elseif desc:IsA("Decal") or desc:IsA("Texture") then
			desc.Transparency = 0
		end
	end
end

function GraviBowPlayerService:_setPartFriction(character)
	for _, part in ipairs(character:GetDescendants()) do
		if part:IsA("BasePart") then
			part.CustomPhysicalProperties = PhysicalProperties.new(
				0.7, -- density
				0,   -- friction
				0,   -- elasticity
				100, -- frictionWeight
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

return GraviBowPlayerService
