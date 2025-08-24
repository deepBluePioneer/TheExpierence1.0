-- Services/GridService.lua
-- Generates a centered tile grid on top of Baseplate and places 20x20x20 cubes at random cells with no overlap.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CustomPackages = ReplicatedStorage.CustomPackages
local Packages = ReplicatedStorage.Packages
local Knit = require(Packages.Knit)
local ZoneRoot = CustomPackages:WaitForChild("ZoneRoot")
local Zone = require(ZoneRoot:WaitForChild("Zone"))
local CollectionService = game:GetService("CollectionService")
local Workspace = game:GetService("Workspace")

local GridService = Knit.CreateService {
    Name = "GridService",
    Client = {},
}

-- ====== CONFIG ======
local GRID_SIZE_X = 100           -- number of columns
local GRID_SIZE_Z = 100           -- number of rows
local CELL_SIZE   = 20            -- tile XZ size (20x20)
local TILE_THICK  = 1             -- tile thickness (Y)

local TILE_TAG    = "gridTile"    -- tag tiles for clearing/querying
local CUBE_TAG    = "perimeterCube"
local RANDOM_CUBE_TAG   = "randomGridCube"  -- ⬅️ give random cubes their own tag

local CUBE_SIZE   = 20            -- 20x20x20 cubes

-- Random cube placement config
local RANDOM_CUBE_COUNT = 600     -- change how many random cubes to place
local RANDOM_CUBE_TAG   = RANDOM_CUBE_TAG -- set to "randomGridCube" if you want a separate tag

-- ====== INTERNAL HELPERS ======
local function cellKey(ix: number, iz: number)
    return string.format("%d,%d", ix, iz)
end

-- Computes grid frame (axes + origin) aligned to Baseplate, handling rotation/tilt.
local function computeGridFrame(baseplate: BasePart)
    local cf = baseplate.CFrame
    local xAxis = cf.RightVector
    local zAxis = cf.LookVector
    local upAxis = cf.UpVector

    local spanX = GRID_SIZE_X * CELL_SIZE
    local spanZ = GRID_SIZE_Z * CELL_SIZE

    -- Center position *on top* of the Baseplate (accounting for tile thickness)
    local topCenter = baseplate.Position + upAxis * (baseplate.Size.Y/2 + TILE_THICK/2)

    -- Origin so grid is centered; first shift back by half-span, then forward by half a cell for tile centers
    local originOffset =
        (-xAxis * (spanX/2)) + (-zAxis * (spanZ/2)) +
        ( xAxis * (CELL_SIZE/2)) + ( zAxis * (CELL_SIZE/2))

    local origin = topCenter + originOffset
    return xAxis, zAxis, upAxis, origin
end

-- ====== LIFECYCLE ======
function GridService:KnitInit() end

function init()
     local baseplate = Workspace:FindFirstChild("Baseplate")
    if not baseplate then
        warn("Baseplate not found!")
        return
    end

    -- Build the grid (tiles + perimeter cubes)
    self:GenerateGridOnBaseplate(baseplate)

    -- Optionally place non-overlapping random cubes
    if RANDOM_CUBE_COUNT and RANDOM_CUBE_COUNT > 0 then
        self:PlaceRandomCubes(RANDOM_CUBE_COUNT)
    end

    -- Pick a random perimeter cell and animate a laser from it across the grid
    local LaserService = Knit.GetService("LaserService")
    -- durationSeconds = 3.0, useExisting = true (reuse the chosen perimeter cube)
    task.wait(4)
    LaserService:LaunchRandomLaser(5.0, true)

    -- If you prefer spawning a NEW cube instead of reusing:
    -- LaserService:LaunchRandomLaser(3.0, false)
end

function GridService:KnitStart()
   
end


-- ====== PUBLIC / MAIN ======

-- Clears previously generated tiles & cubes (by tag)
function GridService:ClearGrid()
    for _, inst in ipairs(CollectionService:GetTagged(TILE_TAG)) do
        if inst and inst.Parent then inst:Destroy() end
    end
    for _, inst in ipairs(CollectionService:GetTagged(CUBE_TAG)) do
        if inst and inst.Parent then inst:Destroy() end
    end
    -- If you chose a separate tag for random cubes, also clear those:
    if RANDOM_CUBE_TAG ~= CUBE_TAG then
        for _, inst in ipairs(CollectionService:GetTagged(RANDOM_CUBE_TAG)) do
            if inst and inst.Parent then inst:Destroy() end
        end
    end
end

-- Generate a centered grid that sits on top of (and aligns with) the Baseplate.
function GridService:GenerateGridOnBaseplate(baseplate: BasePart)
    self:ClearGrid()

    local gridFolder = Workspace:FindFirstChild("GridTiles") or Instance.new("Folder")
    gridFolder.Name = "GridTiles"
    gridFolder.Parent = Workspace

    local cubesFolder = Workspace:FindFirstChild("PerimeterCubes") or Instance.new("Folder")
    cubesFolder.Name = "PerimeterCubes"
    cubesFolder.Parent = Workspace

    local xAxis, zAxis, upAxis, origin = computeGridFrame(baseplate)

    for ix = 0, GRID_SIZE_X - 1 do
        for iz = 0, GRID_SIZE_Z - 1 do
            local tilePos = origin + (xAxis * (ix * CELL_SIZE)) + (zAxis * (iz * CELL_SIZE))

            -- === Tile ===
            local tile = Instance.new("Part")
            tile.Size = Vector3.new(CELL_SIZE, TILE_THICK, CELL_SIZE)
            tile.Anchored = true
            tile.Material = Enum.Material.SmoothPlastic
            tile.Color = Color3.fromRGB(120, 200, 255)
            tile.Name = string.format("Tile_%d_%d", ix + 1, iz + 1)
            tile.CFrame = CFrame.fromMatrix(tilePos, xAxis, upAxis, zAxis)
            tile.Parent = gridFolder
            CollectionService:AddTag(tile, TILE_TAG)

            -- === Perimeter cube (20x20x20) ===
            local isPerimeter = (ix == 0) or (ix == GRID_SIZE_X - 1) or (iz == 0) or (iz == GRID_SIZE_Z - 1)
            if isPerimeter then
                local cubeCenter = tilePos + upAxis * ((TILE_THICK / 2) + (CUBE_SIZE / 2))
                local cube = Instance.new("Part")
                cube.Size = Vector3.new(CUBE_SIZE, CUBE_SIZE, CUBE_SIZE)
                cube.Anchored = true
                cube.Material = Enum.Material.SmoothPlastic
                cube.Color = Color3.fromRGB(255, 180, 80)
                cube.Name = string.format("Cube_%d_%d", ix + 1, iz + 1)
                cube.CFrame = CFrame.fromMatrix(cubeCenter, xAxis, upAxis, zAxis)
                cube.Parent = cubesFolder
                CollectionService:AddTag(cube, CUBE_TAG)
            end
        end
    end
end

-- Place N random 20x20x20 cubes on free cells with no overlap (avoids perimeter cubes and previous placements)
function GridService:PlaceRandomCubes(count: number)
    local baseplate = Workspace:FindFirstChild("Baseplate")
    if not baseplate then
        warn("Baseplate not found; cannot place random cubes.")
        return
    end

    local xAxis, zAxis, upAxis, origin = computeGridFrame(baseplate)

    -- Build occupied set from existing cubes (perimeter and any prior placements)
    local occupied: { [string]: boolean } = {}
    for _, cube in ipairs(CollectionService:GetTagged(CUBE_TAG)) do
        -- Expecting names like "Cube_12_34"
        local ixStr, izStr = tostring(cube.Name):match("^Cube_(%d+)_(%d+)$")
        if ixStr and izStr then
            local ix0 = tonumber(ixStr) - 1
            local iz0 = tonumber(izStr) - 1
            if ix0 and iz0 then
                occupied[cellKey(ix0, iz0)] = true
            end
        end
    end
    if RANDOM_CUBE_TAG ~= CUBE_TAG then
        for _, cube in ipairs(CollectionService:GetTagged(RANDOM_CUBE_TAG)) do
            local ixStr, izStr = tostring(cube.Name):match("^Cube_(%d+)_(%d+)$")
            if ixStr and izStr then
                local ix0 = tonumber(ixStr) - 1
                local iz0 = tonumber(izStr) - 1
                if ix0 and iz0 then
                    occupied[cellKey(ix0, iz0)] = true
                end
            end
        end
    end

    -- Build list of available cells (no overlap)
    local available = table.create(GRID_SIZE_X * GRID_SIZE_Z)
    for ix = 0, GRID_SIZE_X - 1 do
        for iz = 0, GRID_SIZE_Z - 1 do
            local key = cellKey(ix, iz)
            if not occupied[key] then
                table.insert(available, { ix = ix, iz = iz })
            end
        end
    end

    if #available == 0 then
        warn("No free cells available to place random cubes.")
        return
    end

    -- Clamp count to available cells
    local toPlace = math.clamp(count, 0, #available)
    if toPlace < count then
        warn(("Requested %d cubes, but only %d free cells were available."):format(count, toPlace))
    end

    -- Shuffle available cells (Fisher–Yates)
    local rng = Random.new() -- seedless; set Random.new(SEED) if you want determinism
    for i = #available, 2, -1 do
        local j = rng:NextInteger(1, i)
        available[i], available[j] = available[j], available[i]
    end

    -- Reuse the perimeter folder for all cubes (or make your own folder if you prefer)
    local cubesFolder = Workspace:FindFirstChild("PerimeterCubes") or Instance.new("Folder")
    cubesFolder.Name = "PerimeterCubes"
    cubesFolder.Parent = Workspace

    for n = 1, toPlace do
        local ix = available[n].ix
        local iz = available[n].iz

        local tilePos = origin + (xAxis * (ix * CELL_SIZE)) + (zAxis * (iz * CELL_SIZE))
        local cubeCenter = tilePos + upAxis * ((TILE_THICK / 2) + (CUBE_SIZE / 2))

        local cube = Instance.new("Part")
        cube.Size = Vector3.new(CUBE_SIZE, CUBE_SIZE, CUBE_SIZE) -- 20x20x20
        cube.Anchored = true
        cube.Material = Enum.Material.SmoothPlastic
        cube.Color = Color3.fromRGB(180, 255, 120)
        cube.Name = string.format("Cube_%d_%d", ix + 1, iz + 1) -- keep consistent naming
        cube.CFrame = CFrame.fromMatrix(cubeCenter, xAxis, upAxis, zAxis)
        cube.Parent = cubesFolder
        CollectionService:AddTag(cube, RANDOM_CUBE_TAG)

        occupied[cellKey(ix, iz)] = true
    end
end

return GridService
