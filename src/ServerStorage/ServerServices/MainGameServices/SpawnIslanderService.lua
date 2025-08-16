-- Services/WalkService.lua (IslanderService integrated with SpawnZoneService)
local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local Workspace           = game:GetService("Workspace")
local CollectionService   = game:GetService("CollectionService")

local Packages            = ReplicatedStorage:WaitForChild("Packages")
local Knit                = require(Packages.Knit)

local walkerSpawnZoneTag  = "walkerSpawnZone"

local SpawnIslanderService = Knit.CreateService {
    Name = "IslanderService",
    Client = {},
}

-- ====== Config ======
local MODEL_NAME            = "mayor_walking_1"
local NUM_SPAWNS            = 5

-- Lifespan (seconds) for each spawned NPC (random in [MIN, MAX])
local LIFESPAN_MIN          = 25
local LIFESPAN_MAX          = 55
local DESTROY_ON_DEATH      = true

-- Batch to reduce frame hitch
local BATCH_SIZE            = 5
local BATCH_DELAY           = 0.03

-- Optional: also tag the spawned NPCs (works with your IslandWalker systems)
local ADD_WALKER_TAG        = true
local WALKER_TAG            = "islanderWalker"

-- ====== Helpers ======
local function findTemplateModel(): Model?
    local direct = ReplicatedStorage:FindFirstChild(MODEL_NAME)
    if direct and direct:IsA("Model") then return direct end
    for _, inst in ipairs(ReplicatedStorage:GetDescendants()) do
        if inst:IsA("Model") and inst.Name == MODEL_NAME then
            return inst
        end
    end
    return nil
end

local function spawnOne(template: Model, cf: CFrame, index: number)
    local clone = template:Clone()
    clone.Name = ("%s_%02d"):format(MODEL_NAME, index)
    clone.Parent = Workspace
    clone:PivotTo(cf)

    if ADD_WALKER_TAG then
        pcall(function() CollectionService:AddTag(clone, WALKER_TAG) end)
    end

    return clone
end

function SpawnIslanderService:SpawnNPC()
    local template = findTemplateModel()

    local SpawnZoneService = Knit.GetService("NPC_SpawnZoneService")
    local NpcLifespanService = Knit.GetService("NpcLifespanService")

    -- Round-robin across zones, in batches
    local spawned = 0
    while spawned < NUM_SPAWNS do
        local toMake = math.min(BATCH_SIZE, NUM_SPAWNS - spawned)

        for _ = 1, toMake do
            local cf = SpawnZoneService:NextZoneCFrame(walkerSpawnZoneTag)
            spawned += 1

            if cf then
                local clone = spawnOne(template, cf, spawned)

                -- Attach a random lifetime to this NPC
                NpcLifespanService:Add(clone, {
                    min = LIFESPAN_MIN,
                    max = LIFESPAN_MAX,
                    destroyOnDeath = DESTROY_ON_DEATH,
                    onDestroy = function(model, reason)
                        -- reason ∈ {"ragdoll_timeout","ragdoll_death","removed","manual"}
                        -- print(("NPC %s cleaned up (%s)"):format(model.Name, reason))
                    end,
                })
            else
                warn("[IslanderService] Failed to get spawn CFrame from zone; skipping one spawn.")
            end
        end

        if spawned < NUM_SPAWNS then
            task.wait(BATCH_DELAY)
        end
    end
end

-- ====== Knit lifecycle ======
function SpawnIslanderService:KnitStart()
    math.randomseed(os.time())

    -- Ensure the tag is registered with the zone service once.
    local SpawnZoneService = Knit.GetService("NPC_SpawnZoneService")
    SpawnZoneService:RegisterTag(walkerSpawnZoneTag, {
        autoUpdate = true,  -- rebuild zones when parts are added/removed
        randomYaw  = false, -- preserve your original "no yaw" behavior
    })

    task.wait(5)
    self:SpawnNPC()
end

function SpawnIslanderService:KnitInit() end

return SpawnIslanderService
