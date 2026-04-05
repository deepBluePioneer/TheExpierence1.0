local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Packages = ReplicatedStorage.Packages
local Knit = require(Packages.Knit)

local HARVESTER_TAG = "harvester"
local HARVESTER_POLL_INTERVAL = 0.4
local HARVESTER_ARRIVE_DIST = 12
local HARVESTER_MINE_DURATION = 3
local HARVESTER_SEARCH_RADIUS = 500
local HARVESTER_BEAM_COLOR = ColorSequence.new(Color3.fromRGB(255, 200, 50), Color3.fromRGB(255, 100, 20))

local GraviBowHarvesterService = Knit.CreateService({
	Name = "GraviBowHarvesterService",
	Client = {
		DropHarvester = Knit.CreateSignal(),
		HarvesterTarget = Knit.CreateSignal(),
		HarvesterMining = Knit.CreateSignal(),
		HarvesterReady = Knit.CreateSignal(),
	},

	_playerHarvesters = {},
	_claimedCrystals = {},
	_readyEvents = {},
})

function GraviBowHarvesterService:KnitInit()
end

function GraviBowHarvesterService:KnitStart()
	self._playerService = Knit.GetService("GraviBowPlayerService")
	self._oreService = Knit.GetService("GraviBowOreService")

	self.Client.DropHarvester:Connect(function(player, harvester, dropPos, lookDir)
		self:_onDropHarvester(player, harvester, dropPos, lookDir)
	end)

	self.Client.HarvesterReady:Connect(function(player, harvesterObj)
		local key = tostring(player.UserId) .. "_" .. tostring(harvesterObj)
		local event = self._readyEvents[key]
		if event then
			event:Fire()
		end
	end)
end

function GraviBowHarvesterService:_waitForClientReady(player, harvesterObj, timeout)
	timeout = timeout or 3
	local key = tostring(player.UserId) .. "_" .. tostring(harvesterObj)
	local event = Instance.new("BindableEvent")
	self._readyEvents[key] = event

	local done = false
	task.delay(timeout, function()
		if not done then
			done = true
			event:Fire()
		end
	end)

	event.Event:Wait()
	done = true
	event:Destroy()
	self._readyEvents[key] = nil
end

function GraviBowHarvesterService:SpawnHarvester(player)
	return self:_spawnHarvester(player)
end

function GraviBowHarvesterService:_findHarvesterPrefab()
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

function GraviBowHarvesterService:_spawnHarvester(player)
	local prefab = self:_findHarvesterPrefab()
	if not prefab then
		warn("[GraviBowHarvesterService] Could not find harvester prefab")
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

function GraviBowHarvesterService:_onDropHarvester(player, harvester, dropPos, lookDir)
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
	print("[GraviBowHarvesterService] Harvester dropped by", player.Name)
end

function GraviBowHarvesterService:_getNearestPlanetCenter(pos)
	local bestDist = math.huge
	local bestCenter = Vector3.zero

	for _, data in pairs(self._playerService:GetGamePlanets()) do
		local dist = (data.center - pos).Magnitude
		if dist < bestDist then
			bestDist = dist
			bestCenter = data.center
		end
	end
	local hubData = self._playerService:GetHubPlanet()
	if hubData then
		local dist = (hubData.center - pos).Magnitude
		if dist < bestDist then
			bestDist = dist
			bestCenter = hubData.center
		end
	end

	return bestCenter
end

function GraviBowHarvesterService:_findNearestCrystal(pos)
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

function GraviBowHarvesterService:_getCrystalPosition(crystal)
	if crystal:IsA("Model") and crystal.PrimaryPart then
		return crystal.PrimaryPart.Position
	elseif crystal:IsA("BasePart") then
		return crystal.Position
	end
	return nil
end

function GraviBowHarvesterService:_setCrystalTransparency(crystalModel, progress)
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

function GraviBowHarvesterService:_destroyCrystalWithEffect(crystal)
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

function GraviBowHarvesterService:_startHarvesterBehavior(obj, rootPart, ownerPlayer)
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

function GraviBowHarvesterService:_harvesterBehaviorLoop(obj, rootPart, ownerPlayer, groundRayParams)
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
		self:_waitForClientReady(ownerPlayer, obj)

		if not crystal or not crystal.Parent then
			self._claimedCrystals[crystal] = nil
			continue
		end

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
			self._oreService:OnCrystalMined(ownerPlayer)
			self:_destroyCrystalWithEffect(crystal)
		end

		self._claimedCrystals[crystal] = nil
		task.wait(0.5)
	end

	self.Client.HarvesterTarget:Fire(ownerPlayer, obj, nil)
	cleanBeam()
end

return GraviBowHarvesterService
