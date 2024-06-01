local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CustomPackages = ReplicatedStorage.CustomPackages
local Packages = ReplicatedStorage.Packages
local CollectionService = game:GetService("CollectionService")
local Knit = require(Packages.Knit)
-- Zone Modules
local ZoneRoot = CustomPackages.ZoneRoot
local Zone = require(ZoneRoot.Zone)

local PatchesModule = require(ReplicatedStorage.Source.PatchesModule)

local zoneName = "itemZone"

local ItemService = Knit.CreateService {
    Name = "ItemService",
    Client = {

        ApplyPatchToPlayer = Knit.CreateSignal(), -- Create a client-side signal


    },
}

function ItemService:KnitStart()
    
    -- Get zone parts from CollectionService using the tag zoneName
    local zoneParts = CollectionService:GetTagged(zoneName)
    if #zoneParts == 0 then
        warn("No parts found with the tag:", zoneName)
        return
    end

    -- Define the zone using the tagged parts
    self.zone = Zone.new(zoneParts)

    -- Create a random amount of parts in the zone
    self:CreateRandomPatchesInZone()
end

function ItemService:KnitInit()
    -- Add service initialization logic here
end




-- Function to create a random amount of parts in the zone
function ItemService:CreateRandomPatchesInZone()
    if not self.zone then
        warn("Zone is not defined!")
        return
    end

    -- Determine a random number of parts to create
    local numParts = math.random(5, 15) -- Change the range as needed

    for i = 1, numParts do
        self:CreateRandomPatchInZone()
    end
end

-- Function to create a part at a random location within the zone
function ItemService:CreateRandomPatchInZone()
    -- Generate a random point within the zone
    local randomPosition, touchingZoneParts = self.zone:getRandomPoint()
    if randomPosition then
        local newPart = Instance.new("Part")
        newPart.Size = Vector3.new(4, 1, 4)
        newPart.Anchored = true
        newPart.Position = randomPosition
        newPart.Parent = workspace
    else
        warn("Could not generate a random position within the zone!")
    end
end

function ItemService:ApplyPatchToPlayer(player, patchName, currentVehicleModel)
    -- Your logic to apply the patch to the player's vehicle
     --print(patchName)
    self.applyPatchToVehicle(currentVehicleModel, patchName)

end

function ItemService.Client:ApplyPatchToPlayer(player, patchName, currentVehicleModel)
    self.Server:ApplyPatchToPlayer(player, patchName, currentVehicleModel)
end

return ItemService
