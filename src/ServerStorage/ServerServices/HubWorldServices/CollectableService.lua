local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local CollectionService = game:GetService("CollectionService")

local Knit = require(ReplicatedStorage.Packages.Knit)
local ZoneRoot = ReplicatedStorage.CustomPackages.ZoneRoot
local Zone = require(ZoneRoot.Zone)

local CollectableService = Knit.CreateService {
    Name = "CollectableService",
    Client = {},
}

local clonedGoldParts = {}

-- Cleanup function to remove previously scattered gold parts
local function cleanupGoldParts()
    for _, goldPart in ipairs(clonedGoldParts) do
        if goldPart and goldPart.Parent then
            goldPart:Destroy()
        end
    end
    table.clear(clonedGoldParts)
end

-- Function to add a ProximityPrompt to each part in a model
local function addProximityPromptsToModel(model)
    for _, child in ipairs(model:GetDescendants()) do
        if child:IsA("BasePart") then
            local prompt = Instance.new("ProximityPrompt")
            prompt.ActionText = "Collect"
            prompt.ObjectText = model.Name -- Show the model's name
            prompt.RequiresLineOfSight = true
            prompt.MaxActivationDistance = 10 -- Adjust the activation distance as needed

            -- Connect a triggered event to handle the collection logic
            prompt.Triggered:Connect(function(player)
                print(player.Name .. " collected " .. model.Name)
                model:Destroy() -- Remove the gold model upon collection
            end)

            prompt.Parent = child
        end
    end
end

function CollectableService:ScatterGold()
    -- Clean up existing gold parts
    cleanupGoldParts()

    -- Locate the prefabs folder
    local goldPrefabsFolder = ReplicatedStorage:FindFirstChild("Prefabs") and ReplicatedStorage.Prefabs:FindFirstChild("Items")
    if not goldPrefabsFolder then
        warn("Gold prefabs folder not found in ReplicatedStorage -> Prefabs -> Items")
        return
    end

    -- Get all zones tagged as "treeZone"
    local treeZones = CollectionService:GetTagged("treeZone")
    local goldPrefabs = goldPrefabsFolder:GetChildren()

    for _, zonePart in ipairs(treeZones) do
        -- Create a Zone object for the current zone part
        local zone = Zone.new(zonePart)

        for _, prefab in ipairs(goldPrefabs) do
            if prefab:IsA("Model") then
                local clone = prefab:Clone()

                -- Use Zone:getRandomPoint() to determine a random position within the zone
                local randomPosition, touchingZoneParts = zone:getRandomPoint()
                if randomPosition then
                    -- Use PivotTo to set the model's position
                    clone:PivotTo(CFrame.new(randomPosition))

                    -- Add ProximityPrompt to the gold model
                    addProximityPromptsToModel(clone)

                    -- Parent the clone to the workspace
                    clone.Parent = Workspace
                    table.insert(clonedGoldParts, clone)

                    -- Debug information
                   -- print(prefab.Name .. " placed at " .. tostring(randomPosition))
                else
                    warn("Failed to get a random point within the zone for " .. prefab.Name)
                end
            end
        end
    end
end

function CollectableService:KnitStart()
    -- Scatter gold when the service starts
    self:ScatterGold()
end

function CollectableService:KnitInit()
    -- Add service initialization logic here if needed
end

return CollectableService
