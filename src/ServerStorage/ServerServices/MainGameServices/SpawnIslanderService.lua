-- Services/WalkService.lua (IslanderService spawning at random waypoint voxels)
local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local Workspace           = game:GetService("Workspace")
local CollectionService   = game:GetService("CollectionService")

local Packages            = ReplicatedStorage:WaitForChild("Packages")
local Knit                = require(Packages.Knit)

local SpawnIslanderService = Knit.CreateService {
    Name = "IslanderService",
    Client = {},
}

-- ====== Config ======
local MODEL_NAME            = "mayor_walking_1"
local NUM_SPAWNS            = 20

-- Lifespan (seconds) for each spawned NPC (random in [MIN, MAX])
local LIFESPAN_MIN          = 25
local LIFESPAN_MAX          = 55
local DESTROY_ON_DEATH      = true

-- Batch to reduce frame hitch
local BATCH_SIZE            = 5
local BATCH_DELAY           = 0.03

-- Optional: also tag the spawned NPCs
local ADD_WALKER_TAG        = true
local WALKER_TAG            = "islanderWalker"

-- Waypoint voxels tag (produced by WaypointService producers)
local WAYPOINT_PART_TAG     = "waypointPart"

-- Optional: scope spawns to a specific container (e.g., IslandGrid)
-- local WAYPOINT_ANCESTOR  = workspace:FindFirstChild("IslandGrid") -- if you want to scope
local WAYPOINT_ANCESTOR     = nil

-- NEW: spawn tweaks
local SPAWN_Y_OFFSET        = 2.0   -- studs above the waypoint voxel
local RANDOM_YAW            = true  -- randomize facing around +Y

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
    if not template then
        warn(("[IslanderService] Template model '%s' not found"):format(MODEL_NAME))
        return
    end

    local WaypointService    = Knit.GetService("WaypointService")
    local NpcLifespanService = Knit.GetService("NpcLifespanService")

    local spawned = 0
    while spawned < NUM_SPAWNS do
        local toMake = math.min(BATCH_SIZE, NUM_SPAWNS - spawned)

        for _ = 1, toMake do
            -- Random waypoint from the indexed voxels
            local wpCf = WaypointService:GetRandomCFrame(WAYPOINT_PART_TAG)
            spawned += 1

            if wpCf then
                -- Build a spawn CFrame slightly above the waypoint with random yaw
                local pos = wpCf.Position + Vector3.new(0, SPAWN_Y_OFFSET, 0)
                local yaw = RANDOM_YAW and (math.random() * math.pi * 2) or 0
                local spawnCf = CFrame.new(pos) * CFrame.Angles(0, yaw, 0)

                local clone = spawnOne(template, spawnCf, spawned)

                -- Timed ragdoll + (optional) impulse at ragdoll moment
                NpcLifespanService:Add(clone, {
                    min = LIFESPAN_MIN,
                    max = LIFESPAN_MAX,
                    destroyOnDeath = DESTROY_ON_DEATH,

                    -- Uncomment to add a kick when ragdoll happens:
                     impulseSpeed = math.random(20, 50),    -- small forward
                    impulseUp    = math.random(500, 750),  -- strong upward
                    -- OR a fixed impulse:
                    -- impulse      = Vector3.new(0, 700, 0),
                })
            else
                warn("[IslanderService] No waypoint voxels available (tag: " .. WAYPOINT_PART_TAG .. "); skipping spawn.")
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

    -- Ensure the waypoint index is active (safe even if already registered elsewhere)
    local WaypointService = Knit.GetService("WaypointService")
    WaypointService:RegisterIndex(WAYPOINT_PART_TAG, {
        requireAnchored = true,
        filterAncestor  = WAYPOINT_ANCESTOR, -- keep nil to use all voxels in the game
    })

    -- Give IslandGrid / producer generation a moment if they run at the same time
    task.wait(2)
    self:SpawnNPC()
end

function SpawnIslanderService:KnitInit() end

return SpawnIslanderService
