local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Packages = ReplicatedStorage.Packages
local Knit = require(Packages.Knit)
local Trove = require(Packages.Trove)

local ORBITER_TAG = "orbiter"
local PLANET_TAG = "planet"
local ORBIT_SPEED = 20
local ORBIT_TILT = 20
local ORBIT_PADDING = 500

local GraviBowOrbiterController = Knit.CreateController({
	Name = "GraviBowOrbiterController",
	_trove = nil,
	_orbiter = nil,
	_orbiterPart = nil,
	_planets = {},
	_angle = 0,
})

function GraviBowOrbiterController:KnitInit()
	self._trove = Trove.new()
end

function GraviBowOrbiterController:KnitStart()
	for _, instance in ipairs(CollectionService:GetTagged(PLANET_TAG)) do
		self:_registerPlanet(instance)
	end

	self._trove:Add(CollectionService:GetInstanceAddedSignal(PLANET_TAG):Connect(function(instance)
		self:_registerPlanet(instance)
	end), "Disconnect")

	local tagged = CollectionService:GetTagged(ORBITER_TAG)
	if #tagged > 0 then
		self:_setupOrbiter(tagged[1])
	else
		local conn
		conn = CollectionService:GetInstanceAddedSignal(ORBITER_TAG):Connect(function(instance)
			conn:Disconnect()
			self:_setupOrbiter(instance)
		end)
		self._trove:Add(conn, "Disconnect")
	end

	self._trove:Add(RunService.RenderStepped:Connect(function(dt)
		self:_update(dt)
	end), "Disconnect")
end

function GraviBowOrbiterController:_getPart(model)
	if model:IsA("BasePart") then
		return model
	end
	if model:IsA("Model") and model.PrimaryPart then
		return model.PrimaryPart
	end
	return model:FindFirstChildWhichIsA("BasePart", true)
end

function GraviBowOrbiterController:_registerPlanet(model)
	if self._planets[model] then return end

	local part = self:_getPart(model)
	if not part then
		task.spawn(function()
			while model.Parent and not self:_getPart(model) do
				local desc = model.DescendantAdded:Wait()
				if desc:IsA("BasePart") then break end
			end
			if model.Parent and not self._planets[model] then
				self:_registerPlanet(model)
			end
		end)
		return
	end

	self._planets[model] = part
end

function GraviBowOrbiterController:_setupOrbiter(model)
	local part = self:_getPart(model)
	if not part then
		task.spawn(function()
			while model.Parent and not self:_getPart(model) do
				local desc = model.DescendantAdded:Wait()
				if desc:IsA("BasePart") then break end
			end
			if model.Parent then
				self:_setupOrbiter(model)
			end
		end)
		return
	end

	self._orbiter = model
	self._orbiterPart = part
	self._angle = 0
end

function GraviBowOrbiterController:_computeBarycenterAndRadius()
	local sum = Vector3.zero
	local count = 0
	local maxDist = 0

	local positions = {}
	for _, part in pairs(self._planets) do
		if part and part.Parent then
			table.insert(positions, part.Position)
			sum = sum + part.Position
			count = count + 1
		end
	end

	if count == 0 then return nil, 0 end

	local barycenter = sum / count

	for _, pos in ipairs(positions) do
		local dist = (pos - barycenter).Magnitude
		if dist > maxDist then
			maxDist = dist
		end
	end

	return barycenter, maxDist + ORBIT_PADDING
end

function GraviBowOrbiterController:_update(dt)
	if not self._orbiterPart or not self._orbiterPart.Parent then return end

	local barycenter, orbitRadius = self:_computeBarycenterAndRadius()
	if not barycenter then return end

	self._angle = self._angle + math.rad(ORBIT_SPEED) * dt

	local tilt = math.rad(ORBIT_TILT)
	local x = math.cos(self._angle) * orbitRadius
	local z = math.sin(self._angle) * orbitRadius
	local y = math.sin(self._angle) * math.sin(tilt) * orbitRadius * 0.3

	local pos = barycenter + Vector3.new(x, y, z)

	if self._orbiter:IsA("Model") then
		local pivot = self._orbiter:GetPivot()
		self._orbiter:PivotTo(CFrame.new(pos) * (pivot - pivot.Position))
	else
		self._orbiterPart.Position = pos
	end
end

return GraviBowOrbiterController
