local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Packages = ReplicatedStorage.Packages
local Knit = require(Packages.Knit)
local Trove = require(Packages.Trove)

local LocalPlayer = Players.LocalPlayer

local PLANET_TAG = "planet"

local GraviBowEnvironmentController = Knit.CreateController({
	Name = "GraviBowEnvironmentController",

	_trove = nil,
	_characterTrove = nil,
	_planetVisuals = {},
})

function GraviBowEnvironmentController:KnitInit()
	self._trove = Trove.new()
end

function GraviBowEnvironmentController:KnitStart()
	for _, instance in ipairs(CollectionService:GetTagged(PLANET_TAG)) do
		self:_setupPlanetVisuals(instance)
	end

	self._trove:Add(CollectionService:GetInstanceAddedSignal(PLANET_TAG):Connect(function(instance)
		self:_setupPlanetVisuals(instance)
	end), "Disconnect")

	self._trove:Add(CollectionService:GetInstanceRemovedSignal(PLANET_TAG):Connect(function(instance)
		self:_removePlanetVisuals(instance)
	end), "Disconnect")

	self._trove:Add(LocalPlayer.CharacterAdded:Connect(function(character)
		self:_onCharacterAdded(character)
	end), "Disconnect")

	if LocalPlayer.Character then
		self:_onCharacterAdded(LocalPlayer.Character)
	end
end

function GraviBowEnvironmentController:_getPlanetPart(model)
	if model:IsA("BasePart") then
		return model
	end
	if model:IsA("Model") and model.PrimaryPart then
		return model.PrimaryPart
	end
	return model:FindFirstChildWhichIsA("BasePart", true)
end

function GraviBowEnvironmentController:_setupPlanetVisuals(model)
	if self._planetVisuals[model] then return end

	local part = self:_getPlanetPart(model)
	if not part then
		task.spawn(function()
			while model.Parent and not self:_getPlanetPart(model) do
				local desc = model.DescendantAdded:Wait()
				if desc:IsA("BasePart") then break end
			end
			if model.Parent and not self._planetVisuals[model] then
				self:_setupPlanetVisuals(model)
			end
		end)
		return
	end

	self._planetVisuals[model] = {
		parts = {},
		planetPart = part,
	}
end

function GraviBowEnvironmentController:_removePlanetVisuals(model)
	local visuals = self._planetVisuals[model]
	if not visuals then return end

	for _, p in ipairs(visuals.parts) do
		if p and p.Parent then
			p:Destroy()
		end
	end

	self._planetVisuals[model] = nil
end

function GraviBowEnvironmentController:_onCharacterAdded(character)
	if self._characterTrove then
		self._characterTrove:Clean()
	end
	self._characterTrove = self._trove:Extend()

	character:WaitForChild("HumanoidRootPart", 10)
end

return GraviBowEnvironmentController
