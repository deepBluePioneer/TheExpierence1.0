local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local Terrain = workspace:WaitForChild("Terrain")
local Packages = ReplicatedStorage.Packages
local CustomPackages = ReplicatedStorage.CustomPackages

-- Zone Modules
local ZoneRoot = CustomPackages.ZoneRoot
local Zone = require(ZoneRoot.Zone)

local Knit = require(Packages.Knit)

local GlacierService = Knit.CreateService { Name = "GlacierService" }

-- Function to apply a force to push the glacier away from the item
local function applyPushForce(glacier, item)
    if glacier and item then
        local direction = (glacier.Position - item.Position).Unit
        local forceMagnitude = 10 -- Adjust this value as needed
        local force = direction * forceMagnitude
        glacier.AssemblyLinearVelocity = force
    end
end

function GlacierService:KnitStart()
    local glaciers = CollectionService:GetTagged("glacier") -- Fetch glaciers each frame in case new ones are added

    -- Create a zone for each glacier and track it
    for _, glacier in pairs(glaciers) do
        glacier:SetNetworkOwner(nil)

        if glacier:IsA("BasePart") then
            local zone = Zone.new(glacier)

            zone.itemEntered:Connect(function(item)
                print(("%s entered the zone of %s!"):format(item.Name, glacier.Name))
                applyPushForce(glacier, item) -- Apply force to push the glacier away from the item
            end)

            zone.itemExited:Connect(function(item)
                print(("%s exited the zone of %s!"):format(item.Name, glacier.Name))
            end)

            -- Example: Track an additional item if needed
            zone:trackItem(workspace.boat_1.PrimaryPart)
        end
    end
end

function GlacierService:KnitInit()
    -- Add any initialization logic here
end

return GlacierService
