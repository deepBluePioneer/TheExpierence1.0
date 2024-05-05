local CellPopulator = {}

function CellPopulator.createWalls(Cframe, parent, cellProperties)
    -- Define the size of the cell
    local cellSize = Vector3.new(12, 12, 12) -- This represents the dimensions of the cell

    -- Create parts for the walls based on perimeter properties
    local walls = {}
    local thickness = 1 -- Thickness of the walls
    local wallHeight = 24

    -- Adjust wall placement for North and South
    if cellProperties.Perimeter_North then
        local northWall = Instance.new("Part")
        northWall.Size = Vector3.new(cellSize.X, wallHeight, thickness)
        northWall.Position = Cframe.Position + Vector3.new(0, 0, -(cellSize.Z/2 - thickness/2))  -- Moved to South
        northWall.Anchored = true
        northWall.Parent = parent
        northWall.CanCollide = false
        northWall.Name = "NorthWall"
        northWall.Material = Enum.Material.Concrete
        northWall.Color = Color3.new(1, 1, 1) -- Grey color
        cellProperties.Perimeter_WallPart = northWall

        table.insert(walls, northWall)
    end

    if cellProperties.Perimeter_South then
        local southWall = Instance.new("Part")
        southWall.Size = Vector3.new(cellSize.X, wallHeight, thickness)
        southWall.Position = Cframe.Position + Vector3.new(0, 0, cellSize.Z/2 - thickness/2)  -- Moved to North
        southWall.Anchored = true
        southWall.Parent = parent
        southWall.Name = "SouthWall"
        southWall.Material = Enum.Material.Concrete
        southWall.Color = Color3.new(1, 1, 1)
        cellProperties.Perimeter_WallPart = southWall

        table.insert(walls, southWall)
    end

    -- East and West remain unchanged
    if cellProperties.Perimeter_East then
        local eastWall = Instance.new("Part")
        eastWall.Size = Vector3.new(thickness, wallHeight, cellSize.Z)
        eastWall.Position = Cframe.Position + Vector3.new(cellSize.X/2 - thickness/2, 0, 0)
        eastWall.Anchored = true
        eastWall.Parent = parent
        eastWall.Name = "EastWall"
        eastWall.Material = Enum.Material.Concrete
        eastWall.Color = Color3.new(1, 1, 1)
        cellProperties.Perimeter_WallPart = eastWall

        table.insert(walls, eastWall)
    end

    if cellProperties.Perimeter_West then
        local westWall = Instance.new("Part")
        westWall.Size = Vector3.new(thickness, wallHeight, cellSize.Z)
        westWall.Position = Cframe.Position + Vector3.new(-(cellSize.X/2 - thickness/2), 0, 0)
        westWall.Anchored = true
        westWall.Parent = parent
        westWall.Name = "WestWall"
        westWall.Material = Enum.Material.Concrete
        westWall.Color = Color3.new(1, 1, 1)
        cellProperties.Perimeter_WallPart = westWall

        table.insert(walls, westWall)
    end

    return walls
end

function CellPopulator.createCorners(Cframe, parent, cellProperties)
    local cellSize = Vector3.new(12, 12, 12)  -- Represents the dimensions of the cell
    local thickness = 1  -- Wall thickness
    local wallHeight = 24  -- Wall height

    local walls = {}

    -- Corner Northwest: North and West walls
    if cellProperties.Corner_Northwest then
        local northWall = Instance.new("Part")
        northWall.Size = Vector3.new(cellSize.X, wallHeight, thickness)
        northWall.Position = Cframe.Position + Vector3.new(0, 0, -(cellSize.Z/2 - thickness/2))
        northWall.Anchored = true
        northWall.Parent = parent
        northWall.Name = "NorthWestNorthWall"
        northWall.Material = Enum.Material.Concrete
        northWall.Color = Color3.fromRGB(98, 242, 255)  -- White
        table.insert(walls, northWall)

        local westWall = Instance.new("Part")
        westWall.Size = Vector3.new(thickness, wallHeight, cellSize.Z)
        westWall.Position = Cframe.Position + Vector3.new(-(cellSize.X/2 - thickness/2), 0, 0)
        westWall.Anchored = true
        westWall.Parent = parent
        westWall.Name = "NorthWestWestWall"
        westWall.Material = Enum.Material.Concrete
        westWall.Color = Color3.fromRGB(98, 242, 255)
        table.insert(walls, westWall)
    end

    -- Corner Northeast: North and East walls
    if cellProperties.Corner_Northeast then
        local northWall = Instance.new("Part")
        northWall.Size = Vector3.new(cellSize.X, wallHeight, thickness)
        northWall.Position = Cframe.Position + Vector3.new(0, 0, -(cellSize.Z/2 - thickness/2))
        northWall.Anchored = true
        northWall.Parent = parent
        northWall.Name = "NorthEastNorthWall"
        northWall.Material = Enum.Material.Concrete
        northWall.Color = Color3.fromRGB(98, 242, 255)
        table.insert(walls, northWall)

        local eastWall = Instance.new("Part")
        eastWall.Size = Vector3.new(thickness, wallHeight, cellSize.Z)
        eastWall.Position = Cframe.Position + Vector3.new(cellSize.X/2 - thickness/2, 0, 0)
        eastWall.Anchored = true
        eastWall.Parent = parent
        eastWall.Name = "NorthEastEastWall"
        eastWall.Material = Enum.Material.Concrete
        eastWall.Color = Color3.fromRGB(98, 242, 255)
        table.insert(walls, eastWall)
    end

    -- Corner Southwest: South and West walls
    if cellProperties.Corner_Southwest then
        local southWall = Instance.new("Part")
        southWall.Size = Vector3.new(cellSize.X, wallHeight, thickness)
        southWall.Position = Cframe.Position + Vector3.new(0, 0, cellSize.Z/2 - thickness/2)
        southWall.Anchored = true
        southWall.Parent = parent
        southWall.Name = "SouthWestSouthWall"
        southWall.Material = Enum.Material.Concrete
        southWall.Color = Color3.fromRGB(98, 242, 255)
        table.insert(walls, southWall)

        local westWall = Instance.new("Part")
        westWall.Size = Vector3.new(thickness, wallHeight, cellSize.Z)
        westWall.Position = Cframe.Position + Vector3.new(-(cellSize.X/2 - thickness/2), 0, 0)
        westWall.Anchored = true
        westWall.Parent = parent
        westWall.Name = "SouthWestWestWall"
        westWall.Material = Enum.Material.Concrete
        westWall.Color =Color3.fromRGB(98, 242, 255)
        table.insert(walls, westWall)
    end

    -- Corner Southeast: South and East walls
    if cellProperties.Corner_Southeast then
        local southWall = Instance.new("Part")
        southWall.Size = Vector3.new(cellSize.X, wallHeight, thickness)
        southWall.Position = Cframe.Position + Vector3.new(0, 0, cellSize.Z/2 - thickness/2)
        southWall.Anchored = true
        southWall.Parent = parent
        southWall.Name = "SouthEastSouthWall"
        southWall.Material = Enum.Material.Concrete
        southWall.Color = Color3.fromRGB(98, 242, 255)
        table.insert(walls, southWall)

        local eastWall = Instance.new("Part")
        eastWall.Size = Vector3.new(thickness, wallHeight, cellSize.Z)
        eastWall.Position = Cframe.Position + Vector3.new(cellSize.X/2 - thickness/2, 0, 0)
        eastWall.Anchored = true
        eastWall.Parent = parent
        eastWall.Name = "SouthEastEastWall"
        eastWall.Material = Enum.Material.Concrete
        eastWall.Color = Color3.fromRGB(98, 242, 255)
        table.insert(walls, eastWall)
    end

    return walls
end

local function createWall(model, position, size, color)
    local wall = Instance.new("Part")
    wall.Size = size
    wall.Position = position
    wall.Anchored = true
    wall.BrickColor = BrickColor.new(color)
    wall.Parent = model
    return wall
end

function CellPopulator.createCornerPathPieces(Cframe, parent, cellProperties)
    local corners = {}
    local ReplicatedStorage = game:GetService("ReplicatedStorage")
    local PrefabsFolder = ReplicatedStorage:WaitForChild("Prefabs")
    local PathPiecesFolder = PrefabsFolder:WaitForChild("PathPieces")

    -- Helper function to clone and position corner pieces
    local function placeCorner(modelName, positionOffset, rotationDegrees)
        local modelTemplate = PathPiecesFolder:WaitForChild(modelName)
        local modelClone = modelTemplate:Clone()
        modelClone:SetPrimaryPartCFrame(Cframe * CFrame.new(positionOffset) * CFrame.Angles(0, math.rad(rotationDegrees), 0))
        modelClone.Parent = parent
        table.insert(corners, modelClone)
    end

    -- Define the offsets and rotations for each corner type
    -- Assuming each model needs to be centered, with no specific offsets from the center
    local cornerDefinitions = {
        {property = "NorthRightTurn", modelName = "NorthRightTurn", offset = Vector3.new(0, 6, 0), rotation = 0},
        {property = "NorthLeftTurn", modelName = "NorthLeftTurn", offset = Vector3.new(0, 6, 0), rotation = 0},
        {property = "SouthRightTurn", modelName = "SouthRightTurn", offset = Vector3.new(0, 6, 0), rotation = 180},
        {property = "SouthLeftTurn", modelName = "SouthLeftTurn", offset = Vector3.new(0, 6, 0), rotation = 180},
       
    }

    -- Iterate through each corner definition and place the model if the corresponding property is true
    for _, corner in ipairs(cornerDefinitions) do
        if cellProperties[corner.property] then
            placeCorner(corner.modelName, corner.offset, corner.rotation)
        end
    end

    return corners
end

function CellPopulator.createCorridorPathPieces(Cframe, parent, cellProperties)
    local corridors = {}
    local ReplicatedStorage = game:GetService("ReplicatedStorage")
    local PrefabsFolder = ReplicatedStorage:WaitForChild("Prefabs")
    local PathPiecesFolder = PrefabsFolder:WaitForChild("PathPieces")

    -- Helper function to clone and position corridor pieces
    local function placeCorridor(modelName, positionOffset, rotationDegrees)
        local modelTemplate = PathPiecesFolder:WaitForChild(modelName)
        local modelClone = modelTemplate:Clone()
        modelClone:SetPrimaryPartCFrame(Cframe * CFrame.new(positionOffset) * CFrame.Angles(0, math.rad(rotationDegrees), 0))
        modelClone.Parent = parent
        table.insert(corridors, modelClone)
        cellProperties.Corridor_WallPart = modelClone
    end

    -- Corridor definitions for horizontal and vertical types
    local corridorDefinitions = {
        HorizontalCorridor = {modelName = "Horizontal Corridor", offset = Vector3.new(0, 6, 0), rotation = 0},
        VerticalCorridor = {modelName = "Vertical Corridor", offset = Vector3.new(0, 6, 0), rotation = 0}
    }

    -- Check for horizontal and vertical corridor properties and place models accordingly
    if cellProperties.HorizontalCorridor then
        placeCorridor(corridorDefinitions.HorizontalCorridor.modelName,
                      corridorDefinitions.HorizontalCorridor.offset,
                      corridorDefinitions.HorizontalCorridor.rotation)
    end

    if cellProperties.VerticalCorridor then
        placeCorridor(corridorDefinitions.VerticalCorridor.modelName,
                      corridorDefinitions.VerticalCorridor.offset,
                      corridorDefinitions.VerticalCorridor.rotation)
    end

    return corridors
end




return CellPopulator
