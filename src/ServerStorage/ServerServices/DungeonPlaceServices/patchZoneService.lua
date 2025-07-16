-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CustomPackages = ReplicatedStorage:WaitForChild("CustomPackages")
local Packages = ReplicatedStorage:WaitForChild("Packages")
local Knit = require(Packages.Knit)
local CollectionService = game:GetService("CollectionService")

-- Modules
local ZoneRoot = CustomPackages:WaitForChild("ZoneRoot")
local Zone = require(ZoneRoot:WaitForChild("Zone"))

local objectSpawnerZones = "objectSpawnerZone"

-- Service
local patchZoneService = Knit.CreateService {
	Name = "patchZoneService",
	Client = {},
}

-- Character Handling
function patchZoneService:HandleCharacterAdded(Player, Character)
	local humanoid = Character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.WalkSpeed = 45
	end
end

-- Spawn Patch and Create Its Zone
function patchZoneService:spawnPatch(position)
	local part = Instance.new("Part")
	part.Size = Vector3.new(10, 10, 0.001)
	part.Anchored = false
	part.CanCollide = true
	part.Transparency = 1
	part.Position = position + Vector3.new(0, 10, 0)
	part.Name = "PatchObject"
	part.Parent = workspace

	CollectionService:AddTag(part, "powerupPatch")

	for _, face in { Enum.NormalId.Front, Enum.NormalId.Back } do
		local decal = Instance.new("Decal")
		decal.Face = face
		decal.Texture = "rbxassetid://112425153579607"
		decal.Parent = part
	end

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

	-- Track item in global zone
	self.zone:trackItem(part)

	-- Create zone for this patch
	local patchZone = Zone.new({ part })

	-- Track existing machines
	for _, machine in ipairs(CollectionService:GetTagged("machine")) do
		local root = machine:FindFirstChild("RootPart")
		if root then
			patchZone:trackItem(root)
		end
	end

	-- Detect machine RootParts entering/exiting patch zone
	patchZone.itemEntered:Connect(function(item)
		local machine = item.Parent
		if machine and CollectionService:HasTag(machine, "machine") then
			print(machine.Name, "entered patch zone:", part.Name)
		end
	end)

	patchZone.itemExited:Connect(function(item)
		local machine = item.Parent
		if machine and CollectionService:HasTag(machine, "machine") then
			print(machine.Name, "exited patch zone:", part.Name)
		end
	end)

	-- Detect physical collisions with machine RootParts
	local touching = {}

	part.Touched:Connect(function(hit)
		local machine = hit.Parent
		if machine and CollectionService:HasTag(machine, "machine") and hit.Name == "RootPart" then
			if not touching[machine] then
				touching[machine] = true
				print(machine.Name, "collided with patch:", part.Name)
			end
		end
	end)

	part.TouchEnded:Connect(function(hit)
		local machine = hit.Parent
		if machine and CollectionService:HasTag(machine, "machine") and hit.Name == "RootPart" then
			if touching[machine] then
				touching[machine] = nil
				print(machine.Name, "ended collision with patch:", part.Name)
			end
		end
	end)

	return part
end

-- KnitStart
function patchZoneService:KnitStart()
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

	task.wait(5)

	local position, _ = self.zone:getRandomPoint()
	if not position then
		warn("No valid position found for patch spawn")
		return
	end

	self:spawnPatch(position)
end

function patchZoneService:KnitInit() end

return patchZoneService
