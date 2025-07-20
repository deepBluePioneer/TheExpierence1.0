-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CustomPackages = ReplicatedStorage:WaitForChild("CustomPackages")
local Packages = ReplicatedStorage:WaitForChild("Packages")
local Knit = require(Packages.Knit)
local CollectionService = game:GetService("CollectionService")
local PhysicsService = game:GetService("PhysicsService")

local Players = game:GetService("Players")

-- Replica Modules
local Replica = CustomPackages.Replica
local ReplicaService = require(Replica.ReplicaService)

local PlayerAddedController = CustomPackages.PlayerAddedController
local PlayerAddedFunctions = PlayerAddedController.PlayerAddedFunctions

local ParticleRoot = CustomPackages:WaitForChild("Particles")
local ParticleSystem = require(ParticleRoot:WaitForChild("ParticlePackage"))

-- ZonePlus (for spawn area only)
local ZoneRoot = CustomPackages:WaitForChild("ZoneRoot")
local Zone = require(ZoneRoot:WaitForChild("Zone"))

local objectSpawnerZones = "objectSpawnerZone"

-- Image IDs
local offenseID = 98406035373604
local speedBoostID = 123435038795023
local topSpeedID = 124394366919392

local patchImageIDs = {
	offenseID,
	speedBoostID,
	topSpeedID
}

-- Service
local patchZoneService = Knit.CreateService {
	Name = "patchZoneService",
	Client = {},
}

-- Collision Group Setup
function patchZoneService:SetupCollisionGroups()
	local function ensureGroup(name)
		pcall(function()
			PhysicsService:RegisterCollisionGroup(name)
		end)
	end

	ensureGroup("Patch")
	ensureGroup("Machine")
	ensureGroup("Player") -- ✅ added

	PhysicsService:CollisionGroupSetCollidable("Patch", "Machine", false)
	PhysicsService:CollisionGroupSetCollidable("Patch", "Player", false) -- ✅ added
	PhysicsService:CollisionGroupSetCollidable("Patch", "Default", true)
end

-- Auto-assign "Machine" group to RootParts
function patchZoneService:AssignMachineCollisionGroups()
	for _, machine in ipairs(CollectionService:GetTagged("machine")) do
		local root = machine:FindFirstChild("RootPart")
		if root then
			root.CollisionGroup = "Machine"
		end
	end
end

-- Assign "Player" collision group to all character parts
function patchZoneService:HandleCharacterAdded(Player, Character)
	local humanoid = Character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.WalkSpeed = 45
	end

	for _, part in ipairs(Character:GetDescendants()) do
		if part:IsA("BasePart") then
			part.CollisionGroup = "Player"
		end
	end
end

function patchZoneService:ParticlesManager()
	local part = Instance.new("Part")
	part.Name = "ParticleAnchor"
	part.Anchored = true
	part.CanCollide = false
	part.Size = Vector3.new(.5, .5, .5)
	part.Position = Vector3.new(0, 5, 0)
	part.Transparency = 0
	part.Parent = workspace

	local MeshID = "rbxassetid://110892923"
	local TextureID = "rbxassetid://110892681"

	local particleEmitter = ParticleSystem.new(part, MeshID, TextureID)

	particleEmitter.Rate = 50
	particleEmitter.Color = ColorSequence.new(Color3.new(1, 0, 0), Color3.new(1, 1, 0))
	particleEmitter.Size = NumberSequence.new(0.5, 2)
	particleEmitter.Speed = 5
	particleEmitter.SpreadAngle = Vector2.new(20, 20)
	particleEmitter.RotSpeed = {
		X = NumberRange.new(-180, 180),
		Y = NumberRange.new(-180, 180),
		Z = NumberRange.new(-180, 180),
	}
	particleEmitter.Lifetime = NumberRange.new(1, 2)
	particleEmitter.Acceleration = Vector3.new(0, -1, 0)
	particleEmitter.EmissionDirection = "Top"
	particleEmitter.ShapeInOut = "Outward"
	particleEmitter.ShapeStyle = "Volume"
	particleEmitter.Enabled = true

	return particleEmitter
end

function patchZoneService:spawnPatch(position)
	local part = Instance.new("Part")
	part.Size = Vector3.new(7, 7, 7)
	part.Anchored = false
	part.CanCollide = true
	part.Transparency = 1
	part.Position = position + Vector3.new(0, 10, 0)
	part.Name = "PatchObject"
	part.CollisionGroup = "Patch"
	part.Parent = workspace

	CollectionService:AddTag(part, "powerupPatch")

	local billboardGui = Instance.new("BillboardGui")
	billboardGui.Name = "PatchBillboard"
	billboardGui.Size = UDim2.new(11, 0, 11, 0)
	billboardGui.StudsOffset = Vector3.new(0, 0, 0)
	billboardGui.AlwaysOnTop = false
	billboardGui.Adornee = part
	billboardGui.MaxDistance = math.huge
	billboardGui.LightInfluence = 0
	billboardGui.Parent = part

	local imageLabel = Instance.new("ImageLabel")
	imageLabel.Name = "PatchImage"
	imageLabel.AnchorPoint = Vector2.new(0.5, 0.6)
	imageLabel.Position = UDim2.new(0.5, 0, 0.5, 0)
	imageLabel.Size = UDim2.new(1, 0, 1, 0)
	imageLabel.BackgroundTransparency = 1
	imageLabel.Image = "rbxassetid://" .. tostring(patchImageIDs[math.random(1, #patchImageIDs)])
	imageLabel.Parent = billboardGui

	local attachment = Instance.new("Attachment")
	attachment.Parent = part

	local align = Instance.new("AlignOrientation")
	align.Name = "PatchLookAlign"
	align.Attachment0 = attachment
	align.Mode = Enum.OrientationAlignmentMode.OneAttachment
	align.AlignType = Enum.AlignType.Parallel
	align.RigidityEnabled = true
	align.Responsiveness = 100
	align.PrimaryAxisOnly = false
	align.Parent = part

	local gravity = workspace.Gravity
	local mass = part:GetMass()
	local netDownwardForce = -1250

	local vectorForce = Instance.new("VectorForce")
	vectorForce.Attachment0 = attachment
	vectorForce.Force = Vector3.new(0, -(mass * gravity - math.abs(netDownwardForce)), 0)
	vectorForce.RelativeTo = Enum.ActuatorRelativeTo.World
	vectorForce.ApplyAtCenterOfMass = true
	vectorForce.Parent = part

	local touching = {}

	part.Touched:Connect(function(hit)
		local model = hit:FindFirstAncestorOfClass("Model")
		if model and hit.Name == "RootPart" and CollectionService:HasTag(model, "machine") then
			if not touching[model] then
				touching[model] = true
				print(model.Name, "touched patch:", part.Name)

				self:ParticlesManager()
				part:Destroy()
			end
		end
	end)

	part.TouchEnded:Connect(function(hit)
		local model = hit:FindFirstAncestorOfClass("Model")
		if model and touching[model] then
			touching[model] = nil
		end
	end)

	return part
end

function patchZoneService:KnitStart()
	self:SetupCollisionGroups()
	self:AssignMachineCollisionGroups()

	local zoneTagged = CollectionService:GetTagged(objectSpawnerZones)
	local zoneParts = {}

	for _, container in ipairs(zoneTagged) do
		for _, part in ipairs(container:GetDescendants()) do
			if part:IsA("BasePart") then
				table.insert(zoneParts, part)
			end
		end
	end

	self.zone = Zone.new(zoneParts)

	task.spawn(function()
		while true do
			local spawnCount = 10
			for i = 1, spawnCount do
				local position = self.zone:getRandomPoint()
				if position then
					self:spawnPatch(position)
				else
					warn("No valid position found for patch spawn")
				end
				task.wait(0.5)
			end
			task.wait(5)
		end
	end)

	require(PlayerAddedFunctions)(
		function(player) end,
		function(player) end,
		function(player, character)
			self:HandleCharacterAdded(player, character)
		end
	)
end

function patchZoneService:KnitInit() end

return patchZoneService
