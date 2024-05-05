local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CustomPackages = ReplicatedStorage.CustomPackages
local Packages = ReplicatedStorage.Packages
local Gizmo = require(Packages.imgizmo)

local GridManager = {}


local Propertys = {
    DrawTriangles = false,
    AlwaysOnTop = false,
    Positions = {
        BoxPosition = Vector3.new(0, 0, 0) -- Define a starting position for the first box
    },
    Sizes = {
        BoxSize = Vector3.new(2, 2, 2) -- Define the size for each box
    },
    MatrixDimensions = {Rows = 3, Columns = 3, Layers = 3}, -- Define the dimensions of the matrix for 3D
    Spacing = 3 -- Define spacing between the boxes
}

function GridManager:createGrid()
    -- Size of each box
    local boxSize = Vector3.new(12, 12, 12)  -- Each box is 12x12x12 units

    -- Grid dimensions
    local gridSize = 40  -- Create a 30x30 grid of boxes
    local spacing = 12   -- Spacing between boxes

    -- Calculate the total size of the grid
    local totalWidth = gridSize * spacing

    -- Calculate the starting position to center the grid around the origin (assuming baseplate at origin)
    local startX = -totalWidth / 2 + spacing / 2
    local startZ = -totalWidth / 2 + spacing / 2

    -- Initialize a table to store each cell's data
    local gridCells = {}

    -- Loop through to create the grid, adjusting positions to center the grid
    for i = 0, gridSize - 1 do
        gridCells[i] = {}  -- Initialize a new row in the gridCells table
        for j = 0, gridSize - 1 do
            -- Calculate the position for each box, offset to center the grid
            local boxPosition = Vector3.new(startX + i * spacing, 0, startZ + j * spacing)
            local cframe = CFrame.new(boxPosition)
            local position = boxPosition

            -- Set color properties for the gizmo
            Gizmo.PushProperty("Color3", Color3.new(1, 1, 1))
            Gizmo.PushProperty("AlwaysOnTop", Propertys.AlwaysOnTop)
            Gizmo.PushProperty("Transparency", .25)
            -- Create each box at the calculated position
           -- Gizmo.Box:Create(cframe, boxSize, Propertys.DrawTriangles)

            -- Store the cell in the grid table
            gridCells[i][j] = {
                CFrame = cframe,
                Position = boxPosition,
                Size = boxSize,
                Color = Color3.new(0.184314, 0.184314, 1),
                Taken = false,
                isWall = false
            }
        end
    end

    -- Optionally return or use the gridCells table elsewhere
    return gridCells
end

return GridManager