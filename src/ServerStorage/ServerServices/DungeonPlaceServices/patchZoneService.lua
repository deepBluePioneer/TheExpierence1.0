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
local firstPlayer = nil

-- Patch Types and IDs
local offenseID = 98406035373604
local speedBoostID = 123435038795023
local topSpeedID = 124394366919392

local patchTypes = {
	{ id = offenseID, name = "Offense" },
	{ id = speedBoostID, name = "SpeedBoost" },
	{ id = topSpeedID, name = "TopSpeed" },
}

-- Replica Setup
local playerReplicas = {}

-- Service
local patchZoneService = Knit.CreateService {
	Name = "patchZoneService",
	Client = {},
}

function patchZoneService:SetupCollisionGroups()
	local function ensureGroup(name)
		pcall(function()
			PhysicsService:RegisterCollisionGroup(name)
		end)
	end

	ensureGroup("Patch")
	ensureGroup("Machine")
	ensureGroup("Player")

	PhysicsService:CollisionGroupSetCollidable("Patch", "Machine", false)
	PhysicsService:CollisionGroupSetCollidable("Patch", "Player", false)
	PhysicsService:CollisionGroupSetCollidable("Patch", "Default", true)
end

function patchZoneService:AssignMachineCollisionGroups()
	for _, machine in ipairs(CollectionService:GetTagged("machine")) do
		local root = machine:FindFirstChild("RootPart")
		if root then
			root.CollisionGroup = "Machine"
		end

		if firstPlayer then
			machine:SetAttribute("OwnerUserId", firstPlayer.UserId)
		end
	end
end

function patchZoneService:InitReplicas(player)
	local replica = ReplicaService.NewReplica({
		ClassToken = ReplicaService.NewClassToken("PatchNotifier"),
		Data = {
			PatchType = nil,
		},
		Replication = player,
	})

	playerReplicas[player] = replica
end

function patchZoneService:HandleCharacterAdded(Player, Character)
	for _, part in ipairs(Character:GetDescendants()) do
		if part:IsA("BasePart") then
			part.CollisionGroup = "Player"
		end
	end

	if not firstPlayer then
		firstPlayer = Player
		warn(firstPlayer.UserId)
	end

	self:InitReplicas(Player)
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

	local emitter = ParticleSystem.new(part, "rbxassetid://110892923", "rbxassetid://110892681")
	emitter.Rate = 50
	emitter.Color = ColorSequence.new(Color3.new(1, 0, 0), Color3.new(1, 1, 0))
	emitter.Size = NumberSequence.new(0.5, 2)
	emitter.Speed = 5
	emitter.SpreadAngle = Vector2.new(20, 20)
	emitter.RotSpeed = {
		X = NumberRange.new(-180, 180),
		Y = NumberRange.new(-180, 180),
		Z = NumberRange.new(-180, 180),
	}
	emitter.Lifetime = NumberRange.new(1, 2)
	emitter.Acceleration = Vector3.new(0, -1, 0)
	emitter.EmissionDirection = "Top"
	emitter.ShapeInOut = "Outward"
	emitter.ShapeStyle = "Volume"
	emitter.Enabled = true

	return emitter
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

	-- Select patch type
	local selected = patchTypes[math.random(1, #patchTypes)]
	part:SetAttribute("PatchType", selected.name)
	imageLabel.Image = "rbxassetid://" .. tostring(selected.id)
	imageLabel.Parent = billboardGui

	local attachment = Instance.new("Attachment", part)

	local align = Instance.new("AlignOrientation")
	align.Attachment0 = attachment
	align.Mode = Enum.OrientationAlignmentMode.OneAttachment
	align.AlignType = Enum.AlignType.Parallel
	align.RigidityEnabled = true
	align.Responsiveness = 100
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

				local userId = model:GetAttribute("OwnerUserId")
				local player = userId and Players:GetPlayerByUserId(userId)

				if player and playerReplicas[player] then
					local patchType = part:GetAttribute("PatchType") or "Unknown"
					playerReplicas[player]:SetValue("PatchType", patchType)
					playerReplicas[player]:SetValue("PatchType", "") --Resest in case we collide with the same type
					--self:ParticlesManager()
					part:Destroy()
				else
					warn("No player or replica found for machine:", model.Name, "OwnerUserId:", userId)
				end
			end
		end
	end)

	part.TouchEnded:Connect(function(hit)
		local model = hit:FindFirstAncestorOfClass("Model")
		if model and touching[model] then
			touching[model] = nil
		end
	end)

	task.delay(10, function()
	if part and part.Parent then
		part:Destroy()
	end
end)

end

function patchZoneService:KnitStart()
	require(PlayerAddedFunctions)(
		function(_) end,
		function(_) end,
		function(player, character)
			self:HandleCharacterAdded(player, character)
		end
	)

	task.wait(4) -- ensure player has spawned
	self:SetupCollisionGroups()
	self:AssignMachineCollisionGroups()

	local zoneParts = {}
	for _, container in ipairs(CollectionService:GetTagged(objectSpawnerZones)) do
		for _, part in ipairs(container:GetDescendants()) do
			if part:IsA("BasePart") then
				table.insert(zoneParts, part)
			end
		end
	end
	self.zone = Zone.new(zoneParts)

	task.spawn(function()
		while true do
			for i = 1, 10 do
				local position = self.zone:getRandomPoint()
				if position then
					self:spawnPatch(position)
				end
				task.wait(0.5)
			end
		task.wait(5)
		end
	end)
end

function patchZoneService:KnitInit() end

return patchZoneService
