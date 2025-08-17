-- Services/IslandGridService.lua
-- Builds a grid of islands, connects them with bridges, adds a thin "waypoint zone" plate on each bridge,
-- and generates a voxel layer of waypoint parts on top. Then registers both:
--  - waypoint voxels -> WaypointService (tag "waypointPart")
--  - bridge plates   -> NPC_SpawnZoneService (tag "waypointZone")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Packages          = ReplicatedStorage:WaitForChild("Packages")
local Knit              = require(Packages.Knit)
local CollectionService = game:GetService("CollectionService")

-- ZonePlus
local CustomPackages    = ReplicatedStorage:WaitForChild("CustomPackages")
local ZoneRoot          = CustomPackages:WaitForChild("ZoneRoot")
local Zone              = require(ZoneRoot:WaitForChild("Zone"))

local Prefabs           = ReplicatedStorage:WaitForChild("Prefabs")
local waypointTag       = "waypointZone" -- tagged on bridge-top plates
local waypointVoxelTag  = "waypointPart" -- tagged on each voxel in the grid

local IslandGridService = Knit.CreateService {
    Name = "IslandGridService",
    Client = {},
}

-- ====== CONFIG ======
local GRID_ROWS = 2
local GRID_COLS = 2
local GRID_SPACING = Vector3.new(150, 0, 150)
local START_CFRAME = CFrame.new(0, 0, 0)

local BRIDGE_THICKNESS = Vector3.new(10, 5, 15)
local BRIDGE_LENGTH = 53.487
local BRIDGE_Y = 61.342

-- Grid visual settings
local GRID_PART_SIZE = Vector3.new(1, 1, 1)
local GRID_GAP = 5
local GRID_COLOR = Color3.fromRGB(255, 170, 0)
local GRID_MATERIAL = Enum.Material.Plastic
local GRID_CAN_COLLIDE = false

-- Waypoint zone plate on TOP of each bridge
local WAYPOINT_PLATE_THICKNESS = 1
local WAYPOINT_PLATE_TRANSPARENCY = 0.6
local WAYPOINT_PLATE_COLOR = Color3.fromRGB(0, 170, 255)
local WAYPOINT_PLATE_MATERIAL = Enum.Material.SmoothPlastic

IslandGridService._waypointZones = {}

-- ====== HELPERS ======
local function getIslandPrefab()
    local island = Prefabs:FindFirstChild("island") or Prefabs:FindFirstChild("Island")
    assert(island and island:IsA("Model"), "Island prefab Model not found in Prefabs.")
    return island
end

local function ensurePrimaryPart(m: Model)
    if m.PrimaryPart and m.PrimaryPart:IsA("BasePart") then
        return m.PrimaryPart
    end
    local candidate = m:FindFirstChild("Primary") or m:FindFirstChild("PrimaryPart")
    if candidate and candidate:IsA("BasePart") then
        m.PrimaryPart = candidate
        return candidate
    end
    for _, d in ipairs(m:GetDescendants()) do
        if d:IsA("BasePart") then
            m.PrimaryPart = d
            return d
        end
    end
    error("Island model has no BasePart to set as PrimaryPart.")
end

local function placeModelAt(model: Model, cf: CFrame)
    ensurePrimaryPart(model)
    model:PivotTo(cf)
end

-- Create the main bridge between two parts and also a thin "waypoint zone" plate on top, tagged.
local function createBridgeAndWaypointZoneBetween(partA: BasePart, partB: BasePart, parent: Instance)
    local midpoint = (partA.Position + partB.Position) / 2
    midpoint = Vector3.new(midpoint.X, BRIDGE_Y, midpoint.Z)
    local lookAt = CFrame.lookAt(midpoint, Vector3.new(partB.Position.X, BRIDGE_Y, partB.Position.Z))
    local yawAligned = lookAt * CFrame.Angles(0, math.pi/2, 0) -- keep prior 90° rotation

    -- Main bridge
    local bridge = Instance.new("Part")
    bridge.Anchored = true
    bridge.Size = Vector3.new(BRIDGE_LENGTH, BRIDGE_THICKNESS.Y, BRIDGE_THICKNESS.Z)
    bridge.CFrame = yawAligned
    bridge.Color = Color3.fromRGB(125, 125, 125)
    bridge.Material = Enum.Material.WoodPlanks
    bridge.Name = "Bridge"
    bridge.Parent = parent

    -- Waypoint zone plate on top
    local plate = Instance.new("Part")
    plate.Anchored = true
    plate.Name = "BridgeWaypointZone"
    plate.Material = WAYPOINT_PLATE_MATERIAL
    plate.Color = WAYPOINT_PLATE_COLOR
    plate.Transparency = WAYPOINT_PLATE_TRANSPARENCY
    plate.CanCollide = false
    plate.Size = Vector3.new(bridge.Size.X, WAYPOINT_PLATE_THICKNESS, bridge.Size.Z)
    local yOffset = (bridge.Size.Y * 0.5) + (plate.Size.Y * 0.5)
    plate.CFrame = bridge.CFrame * CFrame.new(0, yOffset, 0)
    plate.Parent = parent

    -- Tag the top plate (used as ZonePlus spawn zone)
    CollectionService:AddTag(plate, waypointTag)

    return bridge, plate
end

-- Create Zone + top-layer 2D grid with gaps (voxels are tagged "waypointPart")
local function createZoneAndGridFromPart(zonePart: BasePart, gridsFolder: Folder, _zonesFolder: Folder)
    local zone = Zone.new(zonePart)
    zone.name = zonePart.Name .. "_Zone"
    IslandGridService._waypointZones[zonePart] = zone

    local cf = zonePart.CFrame
    local size = zonePart.Size
    local half = size * 0.5
    local yLocal = half.Y - (GRID_PART_SIZE.Y * 0.5)

    local padX = GRID_PART_SIZE.X * 0.5
    local padZ = GRID_PART_SIZE.Z * 0.5
    local minX, maxX = -half.X + padX, half.X - padX
    local minZ, maxZ = -half.Z + padZ, half.Z - padZ

    local STEP_X = GRID_PART_SIZE.X + GRID_GAP
    local STEP_Z = GRID_PART_SIZE.Z + GRID_GAP

    for lx = minX, maxX, STEP_X do
        for lz = minZ, maxZ, STEP_Z do
            local worldCFrame = cf * CFrame.new(lx, yLocal, lz)
            local p = Instance.new("Part")
            p.Size = GRID_PART_SIZE
            p.Anchored = true
            p.CanCollide = GRID_CAN_COLLIDE
            p.Color = GRID_COLOR
            p.Transparency = 0.5
            p.Material = GRID_MATERIAL
            p.CFrame = worldCFrame
            p.Name = "WaypointVoxel2D"
            p.Parent = gridsFolder

            CollectionService:AddTag(p, waypointVoxelTag)
        end
    end
end

-- ====== API ======
function IslandGridService:SpawnIslandGrid(rows: number, cols: number, spacing: Vector3, startCf: CFrame, parent: Instance?)
    rows = math.max(1, rows or GRID_ROWS)
    cols = math.max(1, cols or GRID_COLS)
    spacing = spacing or GRID_SPACING
    startCf = startCf or START_CFRAME
    parent = parent or workspace

    local islandPrefab = getIslandPrefab()
    local container = Instance.new("Folder")
    container.Name = "IslandGrid"
    container.Parent = parent

    local islands = {}
    local bridgesFolder = Instance.new("Folder"); bridgesFolder.Name = "Bridges";        bridgesFolder.Parent = container
    local zonesFolder   = Instance.new("Folder"); zonesFolder.Name   = "WaypointZones";   zonesFolder.Parent   = container
    local gridsFolder   = Instance.new("Folder"); gridsFolder.Name   = "WaypointGrids";   gridsFolder.Parent   = container

    -- Spawn islands
    for r = 0, rows - 1 do
        islands[r] = {}
        for c = 0, cols - 1 do
            local island = islandPrefab:Clone()
            island.Name = string.format("Island_r%d_c%d", r + 1, c + 1)
            island.Parent = container

            local offset = Vector3.new(c * spacing.X, 0, r * spacing.Z)
            local cf = startCf + offset
            placeModelAt(island, cf)

            islands[r][c] = island
        end
    end

    -- Bridges + waypoint plates
    for r = 0, rows - 1 do
        for c = 0, cols - 1 do
            local currentIsland = islands[r][c]
            local currentPrimary = ensurePrimaryPart(currentIsland)

            if c < cols - 1 then
                local rightIsland = islands[r][c + 1]
                local rightPrimary = ensurePrimaryPart(rightIsland)
                createBridgeAndWaypointZoneBetween(currentPrimary, rightPrimary, bridgesFolder)
            end
            if r < rows - 1 then
                local bottomIsland = islands[r + 1][c]
                local bottomPrimary = ensurePrimaryPart(bottomIsland)
                createBridgeAndWaypointZoneBetween(currentPrimary, bottomPrimary, bridgesFolder)
            end
        end
    end

    -- Build voxel grids only for tagged plates (includes the bridge plates)
    for _, inst in ipairs(container:GetDescendants()) do
        if inst:IsA("BasePart") and CollectionService:HasTag(inst, waypointTag) then
            createZoneAndGridFromPart(inst, gridsFolder, zonesFolder)
        end
    end

 

    return container
end

-- ====== Knit lifecycle ======
function IslandGridService:KnitInit() end
function IslandGridService:KnitStart()
    self:SpawnIslandGrid(GRID_ROWS, GRID_COLS, GRID_SPACING, START_CFRAME, workspace)
end

return IslandGridService
