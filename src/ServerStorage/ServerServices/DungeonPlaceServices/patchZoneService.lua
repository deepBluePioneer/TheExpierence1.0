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
	-- Get all tagged containers
	local zoneTagged = CollectionService:GetTagged(objectSpawnerZones)
	if #zoneTagged == 0 then
		warn("No tagged zone containers found for:", objectSpawnerZones)
		return
	end

	-- Extract all BaseParts from tagged containers
	local zoneParts = {}
	for _, container in ipairs(zoneTagged) do
		for _, part in ipairs(container:GetDescendants()) do
			if part:IsA("BasePart") then
				table.insert(zoneParts, part)
			end
		end
	end

	if #zoneParts == 0 then
		warn("No BaseParts found inside tagged containers")
		return
	end

	-- Create the Zone
	self.zone = Zone.new(zoneParts)

	-- Get a random point inside the zone
	local position, touchingParts = self.zone:getRandomPoint()
	if not position then
		warn("Could not get valid position in zone")
		return
	end

	-- Create the unanchored part
	local part = Instance.new("Part")
	part.Size = Vector3.new(15, 15, 15)
	part.Anchored = false
	part.CanCollide = true
	part.Position = position + Vector3.new(0, 5, 0) -- slightly above surface
	part.Name = "PatchObject"
	part.Parent = workspace
   -- part.MaterialVariant = "UVGrid"
	-- Track the part so we can get itemEntered/itemExited events
	self.zone:trackItem(part)

	-- Optional: log when the part enters or exits the zone
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
