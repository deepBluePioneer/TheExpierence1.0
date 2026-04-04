local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Packages = ReplicatedStorage.Packages
local Knit = require(Packages.Knit)
local Trove = require(Packages.Trove)
local Signal = require(Packages.Signal)

local LocalPlayer = Players.LocalPlayer

local PLANET_TAG = "planet"
local HUB_PLANET_TAG = "planetHub"
local GRAVITY_FORCE = 40
local GRAVITY_DIR_SMOOTH_RAD_PER_SEC = 4.2
local HUB_ZONE_MULTIPLIER = 1.8
local HUB_BARRIER_PUSH_FORCE = 120

local function smoothUnitToward(current, target, dt, maxRadPerSec)
	local c = current.Unit
	local t = target.Unit
	local dot = math.clamp(c:Dot(t), -1, 1)
	local omega = math.acos(dot)
	if omega < 1e-5 then
		return t
	end
	local step = math.min(omega, math.max(maxRadPerSec * dt, 0))
	local sinO = math.sin(omega)
	if sinO < 1e-5 then
		return t
	end
	return (c * math.sin(omega - step) + t * math.sin(step)) / sinO
end

local GraviBowGravityController = Knit.CreateController({
	Name = "GraviBowGravityController",

	GravityDirection = Vector3.new(0, -1, 0),
	GravityChanged = Signal.new(),

	_trove = nil,
	_characterTrove = nil,
	_planets = {},
	_hubPlanets = {},
	_activePlanet = nil,
	_cachedMass = 0,
	_planetRegistered = Signal.new(),
	_smoothedGravityDir = nil,
})

function GraviBowGravityController:KnitInit()
	self._trove = Trove.new()
end

function GraviBowGravityController:KnitStart()
	self._playerService = Knit.GetService("GraviBowPlayerService")
	self._matchController = Knit.GetController("GraviBowMatchController")

	for _, instance in ipairs(CollectionService:GetTagged(PLANET_TAG)) do
		self:_registerPlanet(instance)
	end

	self._trove:Add(CollectionService:GetInstanceAddedSignal(PLANET_TAG):Connect(function(instance)
		self:_registerPlanet(instance)
	end), "Disconnect")

	self._trove:Add(CollectionService:GetInstanceRemovedSignal(PLANET_TAG):Connect(function(instance)
		self:_unregisterPlanet(instance)
	end), "Disconnect")

	for _, instance in ipairs(CollectionService:GetTagged(HUB_PLANET_TAG)) do
		self:_registerHubPlanet(instance)
	end

	self._trove:Add(CollectionService:GetInstanceAddedSignal(HUB_PLANET_TAG):Connect(function(instance)
		self:_registerHubPlanet(instance)
	end), "Disconnect")

	self._playerService.ActivePlanetChanged:Connect(function(planetModel)
		if planetModel then
			local planetData = self._planets[planetModel]
			if not planetData then
				for _ = 1, 20 do
					task.wait(0.25)
					planetData = self._planets[planetModel]
					if planetData then break end
				end
			end
			if planetData then
				print("[GraviBowGravityController] Server set active planet:", planetModel.Name)
				self._activePlanet = planetData
			else
				warn("[GraviBowGravityController] Could not find planet data for:", planetModel:GetFullName())
			end
		else
			print("[GraviBowGravityController] Server cleared active planet, using nearest")
			self._activePlanet = self:_findNearestPlanet()
		end
	end)

	self._trove:Add(LocalPlayer.CharacterAdded:Connect(function(character)
		self:_onCharacterAdded(character)
	end), "Disconnect")

	if LocalPlayer.Character then
		self:_onCharacterAdded(LocalPlayer.Character)
	end
end

function GraviBowGravityController:GetSphereCenter()
	local planet = self._activePlanet or self:_findNearestPlanet()
	if planet then
		return planet.center
	end
	return Vector3.zero
end

function GraviBowGravityController:GetNearestPlanetCenter(position)
	local planet = self:_findNearestPlanet(position)
	if planet then
		return planet.center
	end
	return self:GetSphereCenter()
end

function GraviBowGravityController:GetSphereRadius()
	local planet = self._activePlanet or self:_findNearestPlanet()
	if planet then
		return planet.radius
	end
	return 100
end

function GraviBowGravityController:GetSmoothedGravityDirection()
	return self._smoothedGravityDir or self.GravityDirection
end

function GraviBowGravityController:_getPlanetPart(model)
	if model:IsA("BasePart") then
		return model
	end
	if model:IsA("Model") and model.PrimaryPart then
		return model.PrimaryPart
	end
	return model:FindFirstChildWhichIsA("BasePart", true)
end

function GraviBowGravityController:_getPlanetCenter(model)
	local part = self:_getPlanetPart(model)
	if part then
		return part.Position
	end
	return nil
end

function GraviBowGravityController:_getPlanetRadius(model)
	local part = self:_getPlanetPart(model)
	if part then
		return math.max(part.Size.X, part.Size.Y, part.Size.Z) / 2
	end
	return 100
end

function GraviBowGravityController:_registerPlanet(model)
	if self._planets[model] then return end

	local center = self:_getPlanetCenter(model)
	if not center then
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

	local radius = self:_getPlanetRadius(model)

	local planetData = {
		model = model,
		center = center,
		radius = radius,
	}

	self._planets[model] = planetData
	self._planetRegistered:Fire(planetData)
end

function GraviBowGravityController:_unregisterPlanet(model)
	local planetData = self._planets[model]
	if not planetData then return end

	if self._activePlanet == planetData then
		self._activePlanet = nil
	end

	self._planets[model] = nil

	if not self._activePlanet then
		self._activePlanet = self:_findNearestPlanet()
	end
end

function GraviBowGravityController:_registerHubPlanet(model)
	if self._hubPlanets[model] then return end

	local center = self:_getPlanetCenter(model)
	if not center then
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

	local radius = self:_getPlanetRadius(model)
	local planetData = {
		model = model,
		center = center,
		radius = radius,
	}
	self._hubPlanets[model] = planetData
	self._planets[model] = planetData
	self._planetRegistered:Fire(planetData)
end

function GraviBowGravityController:_getHubPlanet()
	local _, data = next(self._hubPlanets)
	return data
end

function GraviBowGravityController:GetHubPlanet()
	return self:_getHubPlanet()
end

function GraviBowGravityController:GetHubZoneMultiplier()
	return HUB_ZONE_MULTIPLIER
end

function GraviBowGravityController:_findNearestPlanet(position)
	if not position then
		local character = LocalPlayer.Character
		if character then
			local hrp = character:FindFirstChild("HumanoidRootPart")
			if hrp then
				position = hrp.Position
			end
		end
	end
	if not position then return nil end

	local nearest = nil
	local nearestDist = math.huge

	for _, planetData in pairs(self._planets) do
		local dist = (planetData.center - position).Magnitude
		if dist < nearestDist then
			nearestDist = dist
			nearest = planetData
		end
	end

	return nearest
end

function GraviBowGravityController:_updatePlanetCenters()
	for _, planetData in pairs(self._planets) do
		local newCenter = self:_getPlanetCenter(planetData.model)
		if newCenter then
			planetData.center = newCenter
		end
	end
end

function GraviBowGravityController:_onCharacterAdded(character)
	if self._characterTrove then
		self._characterTrove:Clean()
	end
	self._characterTrove = self._trove:Extend()

	local hrp = character:WaitForChild("HumanoidRootPart", 10)
	if not hrp then return end

	local vectorForce = hrp:WaitForChild("GravityForce", 10)
	if not vectorForce then
		warn("[GraviBowGravityController] Missing GravityForce on HumanoidRootPart")
		return
	end

	self._cachedMass = 0
	for _, part in ipairs(character:GetDescendants()) do
		if part:IsA("BasePart") then
			self._cachedMass += part:GetMass()
		end
	end

	if not self._activePlanet then
		local hubPlanet = self:_getHubPlanet()
		if hubPlanet then
			self._activePlanet = hubPlanet
		else
			local nearest = self:_findNearestPlanet(hrp.Position)
			if nearest then
				self._activePlanet = nearest
			else
				local registered = self._planetRegistered:Wait()
				if registered then
					self._activePlanet = registered
				end
			end
		end
	end

	self._smoothedGravityDir = nil

	self._characterTrove:Add(RunService.Stepped:Connect(function(_, dt)
		self:_updateGravity(hrp, vectorForce, dt)
	end), "Disconnect")
end

function GraviBowGravityController:_teleportToSurface(hrp)
	local planet = self:_getHubPlanet()
	if not planet then
		planet = self._activePlanet or self:_findNearestPlanet(hrp.Position)
	end
	if not planet then
		local anyPlanet = next(self._planets)
		if anyPlanet then
			planet = self._planets[anyPlanet]
		end
	end
	if not planet then
		planet = self._planetRegistered:Wait()
	end
	if not planet then
		return
	end

	self._activePlanet = planet

	local center = planet.center
	local radius = planet.radius

	local upDir = (hrp.Position - center)
	if upDir.Magnitude < 0.01 then
		upDir = Vector3.new(0, 1, 0)
	end
	upDir = upDir.Unit

	local surfacePos = center + upDir * (radius + 5)
	local lookDir = upDir:Cross(Vector3.new(0, 0, 1))
	if lookDir.Magnitude < 0.01 then
		lookDir = upDir:Cross(Vector3.new(1, 0, 0))
	end
	lookDir = lookDir.Unit

	local spawnCF = CFrame.lookAt(surfacePos, surfacePos + lookDir, upDir)
	hrp.CFrame = spawnCF
	hrp.AssemblyLinearVelocity = Vector3.zero
	hrp.AssemblyAngularVelocity = Vector3.zero
end

function GraviBowGravityController:_updateGravity(hrp, vectorForce, dt)
	self:_updatePlanetCenters()

	local planet = self._activePlanet or self:_findNearestPlanet(hrp.Position)

	if not planet then return end

	local playerPos = hrp.Position
	local toCenter = planet.center - playerPos
	if toCenter.Magnitude < 0.001 then return end

	local gravityDir = toCenter.Unit
	self.GravityDirection = gravityDir

	if not self._smoothedGravityDir then
		self._smoothedGravityDir = gravityDir
	else
		self._smoothedGravityDir = smoothUnitToward(self._smoothedGravityDir, gravityDir, dt, GRAVITY_DIR_SMOOTH_RAD_PER_SEC)
	end

	self.GravityChanged:Fire(gravityDir)

	local totalForce = gravityDir * GRAVITY_FORCE * self._cachedMass

	local phase = self._matchController and self._matchController.Phase
	if phase == "HUB_WAITING" or phase == "HUB_COUNTDOWN" then
		local hubPlanet = self:_getHubPlanet()
		if hubPlanet then
			local hubCenter = hubPlanet.center
			local zoneRadius = hubPlanet.radius * HUB_ZONE_MULTIPLIER
			local offset = playerPos - hubCenter
			local dist = offset.Magnitude
			if dist > zoneRadius * 0.85 then
				local pushDir = (hubCenter - playerPos).Unit
				local overshoot = math.clamp((dist - zoneRadius * 0.85) / (zoneRadius * 0.15), 0, 1)
				totalForce = totalForce + pushDir * HUB_BARRIER_PUSH_FORCE * overshoot * self._cachedMass

				if dist > zoneRadius then
					hrp.AssemblyLinearVelocity = hrp.AssemblyLinearVelocity * 0.5
				end
			end
		end
	end

	vectorForce.Force = totalForce
end

return GraviBowGravityController
