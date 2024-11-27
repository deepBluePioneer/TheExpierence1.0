local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CustomPackages = ReplicatedStorage.CustomPackages
local Packages = ReplicatedStorage.Packages
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Knit = require(Packages.Knit)
local ZoneRoot = CustomPackages.ZoneRoot
local Zone = require(ZoneRoot.Zone)

local TreeService = Knit.CreateService {
    Name = "TreeService",
    Client = {},
}

-- Table to store cloned prefabs for cleanup
local clonedPrefabs = {}
-- Table to store zones
local zones = {}
-- Flag to track regeneration state
local regenerated = false

-- Function to clean up old prefabs
local function cleanupPrefabs()
    for _, prefab in ipairs(clonedPrefabs) do
        if prefab and prefab.Parent then
            prefab:Destroy()
        end
    end
    clonedPrefabs = {}
end

-- Function to regenerate prefab placement within zones
local function regeneratePrefabs(prefabsFolder)
    cleanupPrefabs()

    for _, zone in ipairs(zones) do
        local zonePart = zone.zonePart

        for _, prefab in ipairs(prefabsFolder:GetChildren()) do
            if prefab:IsA("Model") then
                local clone = prefab:Clone()

                -- Use Zone:getRandomPoint() to get a random position within the zone
                local randomPosition, touchingZoneParts = zone.zone:getRandomPoint()
                if randomPosition then
                    -- Use PivotTo to set the model's position
                    clone:PivotTo(CFrame.new(randomPosition))

                    -- Parent the clone to the workspace
                    clone.Parent = workspace
                    table.insert(clonedPrefabs, clone)
                    --print(prefab.Name .. " placed at " .. tostring(randomPosition))
                else
                    warn("Failed to get a random point within the zone for " .. prefab.Name)
                end
            end
        end
    end
end

-- Function to check if a player is looking away from all zones
local function isPlayerLookingAway(player)
    local character = player.Character
    if not character then return false end

    local humanoidRoot = character:FindFirstChild("HumanoidRootPart")
    if not humanoidRoot then return false end

    local lookVector = humanoidRoot.CFrame.LookVector

    for _, zone in ipairs(zones) do
        local directionToZone = (zone.zonePart.Position - humanoidRoot.Position).Unit
        local dotProduct = lookVector:Dot(directionToZone)

        -- If looking toward any zone, return false
        if dotProduct > 0 then
            return false
        end
    end

    -- If no zones are being looked at, return true
    return true
end

function TreeService:KnitStart()
   
    -- Get the Prefabs folder
    local prefabsFolder = ReplicatedStorage:WaitForChild("Prefabs")

    -- Get the TreeBushes folder from the Prefabs folder
    local treeBushesFolder = prefabsFolder:WaitForChild("TreesBushes")

    if not treeBushesFolder then
        warn("Prefabs folder not found in ReplicatedStorage!")
        return
    end

    -- Get all parts tagged with "treeZone" using CollectionService
    local treeZones = CollectionService:GetTagged("treeZone")

    -- Create zones and store them for later checks
    for _, treePart in ipairs(treeZones) do
        local zone = Zone.new(treePart)
        table.insert(zones, { zone = zone, zonePart = treePart })

        -- Connect playerEntered and playerExited events for this zone
        zone.playerEntered:Connect(function(player)
            print(player.Name .. " entered a tree zone.")
        end)

        zone.playerExited:Connect(function(player)
            print(player.Name .. " exited a tree zone.")
        end)
    end

    -- Initial prefab generation
    regeneratePrefabs(treeBushesFolder)

    -- Check player look direction periodically
    RunService.Heartbeat:Connect(function()
        for _, player in ipairs(Players:GetPlayers()) do
            if isPlayerLookingAway(player) then
                if not regenerated then
                    print(player.Name .. " is looking away from all zones. Regenerating prefabs.")
                    regeneratePrefabs(treeBushesFolder)
                    regenerated = true -- Set flag to prevent further regeneration
                end
            else
                if regenerated then
                    print(player.Name .. " is looking back toward a zone.")
                    regenerated = false -- Reset flag when looking back
                end
            end
        end
    end)
end

function TreeService:KnitInit()
    -- Add service initialization logic here
end

return TreeService
