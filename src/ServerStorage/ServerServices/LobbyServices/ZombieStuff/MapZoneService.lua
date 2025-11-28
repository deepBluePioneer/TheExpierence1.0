local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Packages = ReplicatedStorage.Packages
local Knit = require(Packages.Knit)
local CustomPackages = ReplicatedStorage:WaitForChild("CustomPackages")
local CollectionService = game:GetService("CollectionService")

local ZoneRoot = CustomPackages:WaitForChild("ZoneRoot")
local Zone = require(ZoneRoot:WaitForChild("Zone"))
local Workspace = game:GetService("Workspace")

local MapZoneService = Knit.CreateService {
    Name = "MapZoneService",
    Client = {},
}

-- =========================
-- CONFIG
-- =========================
local CELL_SIZE = Vector3.new(20, 20, 20)
local GRID_WIDTH = 20
local GRID_HEIGHT = 20
local LEVEL_OFFSET = 0
local RANDOM_FILL = 0.45
local SMOOTH_STEPS = 5
local BIRTH_LIMIT = 4
local DEATH_LIMIT = 3
local CLEANUP_FOLDER_NAME = "Level_1"
local FLOOR_FOLDER_NAME = "Level_1Floor"
local MAX_PARTS_PER_STEP = 500
local FIXED_SEED = nil

-- =========================
-- Helpers
-- =========================

local function getBaseplate()
    return Workspace:FindFirstChild("Baseplate")
end

local function getFolder(name: string)
    local folder = Workspace:FindFirstChild(name)
    if not folder then
        folder = Instance.new("Folder")
        folder.Name = name
        folder.Parent = Workspace
    end
    return folder
end

local function clearDungeon()
    getFolder(CLEANUP_FOLDER_NAME):ClearAllChildren()
    getFolder(FLOOR_FOLDER_NAME):ClearAllChildren()
    getFolder("Level_1Zones"):ClearAllChildren()
end

local function makeRng()
    if FIXED_SEED then
        return Random.new(FIXED_SEED)
    else
        return Random.new(os.time() % 1000000)
    end
end

local function newGrid(width, height, rng, fillChance)
    local grid = table.create(height)
    for z = 1, height do
        local row = table.create(width)
        for x = 1, width do
            local isBorder = (x == 1 or x == width or z == 1 or z == height)
            row[x] = isBorder or (rng:NextNumber() < fillChance)
        end
        grid[z] = row
    end
    return grid
end

local function inBounds(x, z, width, height)
    return x >= 1 and x <= width and z >= 1 and z <= height
end

local function countWallNeighbors(grid, x, z, width, height)
    local count = 0
    for dz = -1, 1 do
        for dx = -1, 1 do
            if not (dx == 0 and dz == 0) then
                local nx, nz = x + dx, z + dz
                if inBounds(nx, nz, width, height) then
                    if grid[nz][nx] then count += 1 end
                else
                    count += 1
                end
            end
        end
    end
    return count
end

local function stepCA(grid, width, height)
    local newGrid = table.create(height)
    for z = 1, height do
        local newRow = table.create(width)
        for x = 1, width do
            local neighbors = countWallNeighbors(grid, x, z, width, height)
            if grid[z][x] then
                newRow[x] = (neighbors >= DEATH_LIMIT)
            else
                newRow[x] = (neighbors > BIRTH_LIMIT)
            end
        end
        newGrid[z] = newRow
    end
    return newGrid
end

local function buildDungeon(grid, width, height)
    clearDungeon()

    local wallsFolder = getFolder(CLEANUP_FOLDER_NAME)
    local floorFolder = getFolder(FLOOR_FOLDER_NAME)
    local zoneFolder = getFolder("Level_1Zones")
    local baseplate = getBaseplate()

    local basePos = baseplate and baseplate.Position or Vector3.new(0, 0, 0)
    local baseTopY = baseplate and (basePos.Y + (baseplate.Size.Y * 0.5)) or 0
    local originY = baseTopY + LEVEL_OFFSET

    if baseplate then
        baseplate:Destroy()
    end

    local built = 0
    local placedFloors = 0

    for z = 1, height do
        for x = 1, width do
            local offsetX = (x - (width / 2 + 0.5)) * CELL_SIZE.X
            local offsetZ = (z - (height / 2 + 0.5)) * CELL_SIZE.Z

            -- Only place floor if this tile is NOT a wall
            if not grid[z][x] then
                local floorPart = Instance.new("Part")
                floorPart.Size = CELL_SIZE
                floorPart.Anchored = true
                floorPart.Material = Enum.Material.Concrete
                floorPart.Color = Color3.fromRGB(100, 100, 100)
                floorPart.Name = string.format("Floor_%d_%d", x, z)
                floorPart.CFrame = CFrame.new(
                    basePos.X + offsetX,
                    originY - (CELL_SIZE.Y * 0.5),
                    basePos.Z + offsetZ
                )
                floorPart.Parent = floorFolder
                CollectionService:AddTag(floorPart, "FloorTile")

                placedFloors += 1
                if placedFloors % MAX_PARTS_PER_STEP == 0 then task.wait() end

                -- Transparent zone part on top
                local zonePart = Instance.new("Part")
                zonePart.Size = CELL_SIZE
                zonePart.Anchored = true
                zonePart.CanCollide = false
                zonePart.Transparency = 1
                zonePart.Name = string.format("Zone_%d_%d", x, z)
                zonePart.CFrame = floorPart.CFrame + Vector3.new(0, CELL_SIZE.Y, 0)
                zonePart.Parent = zoneFolder

                local zone = Zone.new(zonePart)
                zone.playerEntered:Connect(function(player)
                    print(player.Name, "entered zone", zonePart.Name)
                end)
                zone.playerExited:Connect(function(player)
                    print(player.Name, "exited zone", zonePart.Name)
                end)
            end
        end
    end

    -- Walls (processed separately)
    for z = 1, height do
        for x = 1, width do
            if grid[z][x] then
                local offsetX = (x - (width / 2 + 0.5)) * CELL_SIZE.X
                local offsetZ = (z - (height / 2 + 0.5)) * CELL_SIZE.Z

                local part = Instance.new("Part")
                part.Size = CELL_SIZE
                part.Anchored = true
                part.Material = Enum.Material.Slate
                part.Color = Color3.fromRGB(50, 50, 50)
                part.Name = string.format("Wall_%d_%d", x, z)
                part.CFrame = CFrame.new(
                    basePos.X + offsetX,
                    originY + (CELL_SIZE.Y * 0.5),
                    basePos.Z + offsetZ
                )
                part.Parent = wallsFolder

                built += 1
                if built % MAX_PARTS_PER_STEP == 0 then
                    task.wait()
                end
            end
        end
    end

    return built, placedFloors
end

local function generateDungeon()
    local rng = makeRng()
    local grid = newGrid(GRID_WIDTH, GRID_HEIGHT, rng, RANDOM_FILL)
    for _ = 1, SMOOTH_STEPS do
        grid = stepCA(grid, GRID_WIDTH, GRID_HEIGHT)
        task.wait()
    end
    local walls, floors = buildDungeon(grid, GRID_WIDTH, GRID_HEIGHT)
    warn(("[MapZoneService] Level built with %d wall cubes and %d floor cubes."):format(walls, floors))
end

-- =========================
-- Knit lifecycle
-- =========================

function MapZoneService:KnitStart()
    generateDungeon()
end

function MapZoneService:KnitInit()
end

return MapZoneService
