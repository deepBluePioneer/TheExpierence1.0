local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CustomPackages = ReplicatedStorage:WaitForChild("CustomPackages")
local Packages = ReplicatedStorage:WaitForChild("Packages")
local Knit = require(Packages.Knit)
local CollectionService = game:GetService("CollectionService")

local ZoneRoot = CustomPackages:WaitForChild("ZoneRoot")
local Zone = require(ZoneRoot:WaitForChild("Zone"))

local objectSpawnerZones = "objectSpawnerZone"

local patchZoneService = Knit.CreateService {
	Name = "patchZoneService",
	Client = {},
}

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

	local position, touchingParts = self.zone:getRandomPoint()
	if not position then
		warn("Could not get valid position in zone")
		return
	end

	task.wait(5)
	local part = Instance.new("Part")
	part.Size = Vector3.new(10, 10, 0.001)
	part.Anchored = false
	part.CanCollide = true
	part.Transparency = 1
	part.Position = position + Vector3.new(0, 10, 0)
	part.Name = "PatchObject"
	part.Parent = workspace

	-- Add tag
	CollectionService:AddTag(part, "powerupPatch")


	-- Add decals
	for _, face in { Enum.NormalId.Front, Enum.NormalId.Back } do
		local decal = Instance.new("Decal")
		decal.Face = face
		decal.Texture = "rbxassetid://112425153579607"
		decal.Parent = part
	end

	-- Add attachment (shared by AlignOrientation + VectorForce)
	local attachment = Instance.new("Attachment")
	attachment.Parent = part

	-- Keep upright
	local align = Instance.new("AlignOrientation")
	align.Attachment0 = attachment
	align.Mode = Enum.OrientationAlignmentMode.OneAttachment
	align.RigidityEnabled = true
	align.Responsiveness = 200
	align.AlignType = Enum.AlignType.Parallel
	align.PrimaryAxisOnly = false
	align.Parent = part

	-- Apply upward force to cancel most gravity, leaving a slow fall
	local gravity = workspace.Gravity -- usually 196.2
	local mass = part:GetMass()
	local netDownwardForce = -1250 -- adjust this for desired fall speed

	local vectorForce = Instance.new("VectorForce")
	vectorForce.Attachment0 = attachment
	vectorForce.Force = Vector3.new(0, -(mass * gravity - math.abs(netDownwardForce)), 0)
	vectorForce.RelativeTo = Enum.ActuatorRelativeTo.World
	vectorForce.ApplyAtCenterOfMass = true
	vectorForce.Parent = part

	self.zone:trackItem(part)

	self.zone.itemEntered:Connect(function(item)
		print("Item entered zone:", item.Name)
	end)

	self.zone.itemExited:Connect(function(item)
		print("Item exited zone:", item.Name)
	end)
end

function patchZoneService:KnitInit()
	-- Service initialization logic here if needed
end

return patchZoneService
