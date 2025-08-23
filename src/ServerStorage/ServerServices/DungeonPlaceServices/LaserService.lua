-- Services/LaserService.lua
-- Picks a random perimeter cell and scales a 20x20x20 "laser" Part across the grid over time.

local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local Workspace           = game:GetService("Workspace")
local CollectionService   = game:GetService("CollectionService")
local RunService          = game:GetService("RunService")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local Knit     = require(Packages.Knit)

local LaserService = Knit.CreateService {
    Name   = "LaserService",
    Client = {},
}

-- === CONFIG (must match GridService) ===
local TILE_TAG       = "gridTile"        -- tiles named "Tile_i_j"
local PERIMETER_TAG  = "perimeterCube"   -- cubes named "Cube_i_j"
local LASER_TAG      = "laserCube"
local CUBE_SIZE      = 20
local LASER_COLOR    = Color3.fromRGB(255, 60, 60)
local LASER_FOLDER   = "LaserObjects"

-- Animation
local DEFAULT_DURATION = 3.0  -- seconds to grow across the grid

-- Internal
LaserService._animConn = nil

-- Utility
local function pickRandom(list)
    local n = #list
    if n == 0 then return nil end
    local rng = Random.new()
    return list[rng:NextInteger(1, n)]
end

-- Read grid dimensions & cell sizes from tiles
local function getGridInfo()
    local tiles = CollectionService:GetTagged(TILE_TAG)
    if #tiles == 0 then return nil end

    local maxI, maxJ = 0, 0
    local sampleTile = nil

    for _, t in ipairs(tiles) do
        local iStr, jStr = tostring(t.Name):match("^Tile_(%d+)_(%d+)$")
        if iStr and jStr then
            local i, j = tonumber(iStr), tonumber(jStr)
            if i and j then
                if i > maxI then maxI = i end
                if j > maxJ then maxJ = j end
                sampleTile = sampleTile or t
            end
        end
    end

    if not sampleTile or maxI == 0 or maxJ == 0 then return nil end

    local cellX = sampleTile.Size.X
    local cellZ = sampleTile.Size.Z
    return {
        maxI = maxI,
        maxJ = maxJ,
        cellX = cellX,
        cellZ = cellZ,
        spanX = maxI * cellX, -- total grid width along X axis
        spanZ = maxJ * cellZ, -- total grid depth along Z axis
    }
end

-- Parse i,j indices from a perimeter cube name ("Cube_i_j" or "Cube_i_j_*")
local function parsePerimeterIndices(part)
    local iStr, jStr = tostring(part.Name):match("^Cube_(%d+)_(%d+)")
    if iStr and jStr then
        return tonumber(iStr), tonumber(jStr)
    end
    -- fall back to attributes if present (used when we spawn a new laser cube)
    local ai, aj = part:GetAttribute("ix"), part:GetAttribute("iz")
    if typeof(ai) == "number" and typeof(aj) == "number" then
        return ai, aj
    end
    return nil, nil
end

-- Create (or reuse) the perimeter cube for the laser and annotate it
function LaserService:PlaceOnRandomPerimeterCell(useExisting: boolean?)
    local perim = CollectionService:GetTagged(PERIMETER_TAG)
    if #perim == 0 then
        warn("[LaserService] No perimeter cubes found. Run grid build first.")
        return nil
    end

    local chosen = pickRandom(perim)
    if not chosen or not chosen.Parent then return nil end

    local i, j = parsePerimeterIndices(chosen)
    if not i or not j then
        warn("[LaserService] Could not parse indices from perimeter cube name: " .. chosen.Name)
        return nil
    end

    local reuse = (useExisting ~= false) -- default true
    if reuse then
        chosen.Color = LASER_COLOR
        chosen.Material = Enum.Material.SmoothPlastic
        chosen.Name = string.format("Cube_%d_%d_Laser", i, j)
        chosen:SetAttribute("ix", i)
        chosen:SetAttribute("iz", j)
        CollectionService:AddTag(chosen, LASER_TAG)
        return chosen
    else
        -- Spawn a NEW laser cube centered at the same spot/orientation
        local folder = Workspace:FindFirstChild(LASER_FOLDER) or Instance.new("Folder")
        folder.Name = LASER_FOLDER
        folder.Parent = Workspace

        local laser = Instance.new("Part")
        laser.Name = "LaserCube"
        laser.Size = Vector3.new(CUBE_SIZE, CUBE_SIZE, CUBE_SIZE)
        laser.Anchored = true
        laser.Material = Enum.Material.SmoothPlastic
        laser.Color = LASER_COLOR
        laser.CFrame = chosen.CFrame
        laser.Parent = folder
        laser:SetAttribute("ix", i)
        laser:SetAttribute("iz", j)
        CollectionService:AddTag(laser, LASER_TAG)
        return laser
    end
end

-- Compute beam axis (X or Z), inward direction, target length, and anchor point.
local function computeBeam(chosen: BasePart, grid)
    local i, j = parsePerimeterIndices(chosen)
    assert(i and j, "Laser cube missing indices")

    -- Local axes from the chosen cube
    local right = chosen.CFrame.RightVector
    local up    = chosen.CFrame.UpVector
    local look  = chosen.CFrame.LookVector

    local beamDir, axis, targetLen

    if i == 1 then
        beamDir  =  right         -- inward from min-X edge
        axis     = "X"
        targetLen= grid.spanX
    elseif i == grid.maxI then
        beamDir  = -right         -- inward from max-X edge
        axis     = "X"
        targetLen= grid.spanX
    elseif j == 1 then
        beamDir  =  look          -- inward from min-Z edge
        axis     = "Z"
        targetLen= grid.spanZ
    elseif j == grid.maxJ then
        beamDir  = -look          -- inward from max-Z edge
        axis     = "Z"
        targetLen= grid.spanZ
    else
        -- Not actually on perimeter; default to Z inward
        beamDir  = look
        axis     = "Z"
        targetLen= grid.spanZ
    end

    -- Anchor the inward face so the beam grows into the grid
    local anchor = chosen.Position + beamDir * (CUBE_SIZE / 2)

    return {
        axis      = axis,
        beamDir   = beamDir,
        anchor    = anchor,
        right     = right,
        up        = up,
        look      = look,
        targetLen = targetLen,
    }
end

-- Animate scaling the laser across the grid over time, keeping the start face fixed on the perimeter.
function LaserService:AnimateAcrossGrid(laserPart: BasePart, durationSeconds: number?)
    if not (laserPart and laserPart.Parent) then return end

    local grid = getGridInfo()
    if not grid then
        warn("[LaserService] No grid tiles found to compute grid size.")
        return
    end

    local beam = computeBeam(laserPart, grid)
    local duration = math.max(0.01, tonumber(durationSeconds) or DEFAULT_DURATION)

    -- Cancel any prior animation
    if self._animConn then
        self._animConn:Disconnect()
        self._animConn = nil
    end

    local t0 = os.clock()
    local startLen = CUBE_SIZE
    local endLen   = beam.targetLen

    self._animConn = RunService.Heartbeat:Connect(function()
        if not (laserPart and laserPart.Parent) then
            self._animConn:Disconnect()
            self._animConn = nil
            return
        end

        local t   = os.clock()
        local a   = math.clamp((t - t0) / duration, 0, 1)
        local Len = startLen + (endLen - startLen) * a

        -- Keep the perimeter face fixed at 'anchor' and move center forward by Len/2
        local center = beam.anchor + beam.beamDir * (Len / 2)

        -- Update size (X or Z), keep thickness and height at CUBE_SIZE
        if beam.axis == "X" then
            laserPart.Size = Vector3.new(Len, CUBE_SIZE, CUBE_SIZE)
        else -- "Z"
            laserPart.Size = Vector3.new(CUBE_SIZE, CUBE_SIZE, Len)
        end

        -- Keep orientation consistent with the original cube
        laserPart.CFrame = CFrame.fromMatrix(center, beam.right, beam.up, beam.look)

        if a >= 1 then
            self._animConn:Disconnect()
            self._animConn = nil
        end
    end)
end

-- Convenience: do both steps (pick/create the laser cube, then animate)
function LaserService:LaunchRandomLaser(durationSeconds: number?, useExisting: boolean?)
    local laser = self:PlaceOnRandomPerimeterCell(useExisting)
    if laser then
        self:AnimateAcrossGrid(laser, durationSeconds)
    end
    return laser
end

function LaserService:KnitInit() end
function LaserService:KnitStart() end

return LaserService
