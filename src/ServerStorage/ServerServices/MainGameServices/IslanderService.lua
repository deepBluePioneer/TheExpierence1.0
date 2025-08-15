-- Services/WalkService.lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local CollectionService = game:GetService("CollectionService")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local Knit = require(Packages.Knit)

local CustomPackages = ReplicatedStorage:WaitForChild("CustomPackages")
local ZoneRoot = CustomPackages:WaitForChild("ZoneRoot")
local Zone = require(ZoneRoot:WaitForChild("Zone"))

local walkerSpawnZoneTag = "walkerSpawnZone"

local WalkService = Knit.CreateService {
    Name = "WalkService",
    Client = {},
}

-- ====== Config ======
local MODEL_NAME = "mayor_walking_1"
local NUM_SPAWNS = 10

-- Batch to reduce frame hitch
local BATCH_SIZE = 5
local BATCH_DELAY = 0.03

-- ====== Helpers ======

local function findTemplateModel() --: Model?
    local direct = ReplicatedStorage:FindFirstChild(MODEL_NAME)
    if direct and direct:IsA("Model") then return direct end
    for _, inst in ipairs(ReplicatedStorage:GetDescendants()) do
        if inst:IsA("Model") and inst.Name == MODEL_NAME then
            return inst
        end
    end
    return nil
end



-- Build zones from Parts only (fast path)
local function buildSpawnZones() --: { any }
    local zones = {}
    for _, inst in ipairs(CollectionService:GetTagged(walkerSpawnZoneTag)) do
        if inst:IsA("BasePart") then
            -- Use the part's CFrame/Size to make a lightweight region zone
            local cf, size = inst.CFrame, inst.Size
            local ok, z = pcall(function() return Zone.fromRegion(cf, size) end)
            if ok and z then
                z.autoUpdate = false -- static spawn volumes
                table.insert(zones, z)
            end
        else
            -- Ignore models/folders; you said zones are parts
        end
    end
    return zones
end

-- Exactly use the zone point; no offsets, no yaw
local function cframeFromZone(zone)
    local point = select(1, zone:getRandomPoint())
    if typeof(point) ~= "Vector3" then return nil end
    return CFrame.new(point)
end

local function spawnOne(template: Model, cf: CFrame, index: number)
    local clone = template:Clone()
    clone.Name = ("%s_%02d"):format(MODEL_NAME, index)
    clone.Parent = Workspace
    clone:PivotTo(cf)

    return clone
end

-- ====== Knit lifecycle ======
function WalkService:KnitStart()
    math.randomseed(os.time())

    local template = findTemplateModel()

    local zones = buildSpawnZones()

    -- Round-robin across zones, in batches
    local zoneIndex = 1
    local spawned = 0
    while spawned < NUM_SPAWNS do
        local toMake = math.min(BATCH_SIZE, NUM_SPAWNS - spawned)
        for _ = 1, toMake do
            local zone = zones[zoneIndex]
            zoneIndex = (zoneIndex % #zones) + 1

            local cf = cframeFromZone(zone)
            if cf then
                spawned += 1
                spawnOne(template, cf, spawned)
            else
                warn("[WalkService] Failed to get spawn CFrame from zone; skipping one spawn.")
                spawned += 1
            end
        end
        if spawned < NUM_SPAWNS then
            task.wait(BATCH_DELAY)
        end
    end
end

function WalkService:KnitInit()
    -- init if needed
end

return WalkService
