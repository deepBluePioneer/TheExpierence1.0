local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CustomPackages = ReplicatedStorage.CustomPackages
local Packages = ReplicatedStorage.Packages
local Knit = require(Packages.Knit)

local TreeController = Knit.CreateController { Name = "TreeController" }
-- Zone Modules
local ZoneRoot = CustomPackages.ZoneRoot
local Zone = require(ZoneRoot.Zone)

function TreeController:KnitStart()
    -- Get all parts tagged with "treeZone" using CollectionService
    local treeZones = CollectionService:GetTagged("treeZone")

    -- Loop through all tagged parts and create a Zone for each
    for _, treePart in ipairs(treeZones) do
        -- Create a zone for the tagged part
        local zone = Zone.new(treePart)

        -- Connect playerEntered and playerExited events for this zone
        zone.playerEntered:Connect(function(player)
            print(player.Name .. " entered a tree zone.")
            -- Add custom logic for when a player enters the tree zone
        end)

        zone.playerExited:Connect(function(player)
            print(player.Name .. " exited a tree zone.")
            -- Add custom logic for when a player exits the tree zone
        end)
    end
end

function TreeController:KnitInit()
    -- Add controller initialization logic here
end

return TreeController
