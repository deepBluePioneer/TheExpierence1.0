local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CustomPackages = ReplicatedStorage:WaitForChild("CustomPackages")
local Packages = ReplicatedStorage:WaitForChild("Packages")
local Knit = require(Packages.Knit)

local Prefabs = ReplicatedStorage:WaitForChild("Prefabs")

local IslandGridService = Knit.CreateService {
    Name = "IslandGridService",
    Client = {},
}

-- ====== CONFIG ======
local GRID_ROWS = 5
local GRID_COLS = 5
local GRID_SPACING = Vector3.new(150, 0, 150)
local START_CFRAME = CFrame.new(0, 0, 0)

local BRIDGE_THICKNESS = Vector3.new(10, 5, 10) -- default thickness of bridge parts

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

local function createBridgeBetween(partA: BasePart, partB: BasePart, parent: Instance)
    local midpoint = (partA.Position + partB.Position) / 2
    midpoint = Vector3.new(midpoint.X, 61.342, midpoint.Z) -- fixed height

    local bridge = Instance.new("Part")
    bridge.Anchored = true
    bridge.Size = Vector3.new(53.487, BRIDGE_THICKNESS.Y, BRIDGE_THICKNESS.Z) -- fixed length
    bridge.CFrame = CFrame.lookAt(midpoint, Vector3.new(partB.Position.X, 61.342, partB.Position.Z))
                      * CFrame.Angles(0, math.pi/2, 0)
    bridge.Color = Color3.fromRGB(125, 125, 125)
    bridge.Material = Enum.Material.WoodPlanks
    bridge.Name = "Bridge"
    bridge.Parent = parent
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

    -- Create bridges
    for r = 0, rows - 1 do
        for c = 0, cols - 1 do
            local currentIsland = islands[r][c]
            local currentPrimary = ensurePrimaryPart(currentIsland)

            -- Bridge to the right neighbor
            if c < cols - 1 then
                local rightIsland = islands[r][c + 1]
                local rightPrimary = ensurePrimaryPart(rightIsland)
                createBridgeBetween(currentPrimary, rightPrimary, container)
            end

            -- Bridge to the bottom neighbor
            if r < rows - 1 then
                local bottomIsland = islands[r + 1][c]
                local bottomPrimary = ensurePrimaryPart(bottomIsland)
                createBridgeBetween(currentPrimary, bottomPrimary, container)
            end
        end
    end

    return container
end

-- ====== Knit lifecycle ======
function IslandGridService:KnitInit()
end

function IslandGridService:KnitStart()
    self:SpawnIslandGrid(GRID_ROWS, GRID_COLS, GRID_SPACING, START_CFRAME, workspace)
end

return IslandGridService
