local Wall = {}
Wall.__index = Wall



function Wall.new(modelParent, tilesFolder, unitCubeModel)
    local self = setmetatable({}, Wall)
    self.modelParent = modelParent
    self.tilesFolder = tilesFolder
    self.unitCubeModel = unitCubeModel
    return self
end


function Wall:createWallModel()
    local wallTiles = self.tilesFolder:GetChildren()
    
    for _, tile in ipairs(wallTiles) do
        -- Create a new model to hold the wall tile
        local wallModel = Instance.new("Model")
        wallModel.Name = "WallModel_" .. tile.Name
        wallModel.Parent = self.tilesFolder  -- Parenting the model to the same folder for organization

        -- Set the tile as a child of the model
        tile.Parent = wallModel

        -- Create a primary part for the model
        local primaryPart = Instance.new("Part")
        primaryPart.Name = "PrimaryPart"
        primaryPart.Size = Vector3.new(tile.Size.X, 1, tile.Size.Z)  -- Assuming the primary part matches the tile width and depth
        primaryPart.Anchored = true
        primaryPart.CanCollide = false  -- Set to false if you do not want it to interfere physically
        primaryPart.Color = Color3.new(1, 0, 0)  -- Color it red for visibility (optional)
        primaryPart.Position = Vector3.new(tile.Position.X, tile.Position.Y - tile.Size.Y / 2 - 0.5, tile.Position.Z)  -- Position it at the bottom edge of the tile

        -- Set the primary part of the model
        primaryPart.Parent = wallModel
        wallModel.PrimaryPart = primaryPart
    end
end


function Wall:generateWalls(floor, wallHeight)

    local models = floor.models
    local innerTiles = models.FloorTiles
    local perimeterTiles = models.PerimeterTiles

    local Corners = perimeterTiles.Corners
    local northeastCorner = Corners.Northeast
    local northwestCorner = Corners.Northwest
    local southeastCorner = Corners.Southeast
    local southwestCorner = Corners.Southwest

    local eastPerimeter = perimeterTiles.East
    local northPerimeter = perimeterTiles.North
    local southPerimeter = perimeterTiles.South
    local westPerimeter = perimeterTiles.West

    local wallTiles = self.tilesFolder:GetChildren()

    local perimeterExtraPartString = "PerimeterExtraPart"
    local CornerExtraPartString = "CornerExtraPart"


    -- A table to store all parts that match the name condition
    local PerimeterExtraParts = {}
    local CornerExtraParts = {}

     -- Function to search through each model's children for parts with the specified string in their name
     local function GetPerimeterExtraParts(modelsTable, direction)
        for _, model in ipairs(modelsTable) do
            for _, part in ipairs(model:GetChildren()) do
                if string.find(part.Name, perimeterExtraPartString) then
                    table.insert(PerimeterExtraParts, {part = part, direction = direction})
                   -- print("Found matching part:", part.Name, "Direction:", direction)
                end
            end
        end
    end

    local function GetCornerExtraParts(modelsTable, direction)
        for _, model in ipairs(modelsTable) do
            for _, part in ipairs(model:GetChildren()) do
                if string.find(part.Name, CornerExtraPartString) then
                    --warn(part)
                    table.insert(CornerExtraParts, {part = part, direction = direction})
                    --print("Found matching part:", part.Name, "Direction:", direction)
                end
            end
        end
    end


        -- Applying the search function to each group of models with directional context
    GetPerimeterExtraParts(northeastCorner, "Northeast")
    GetPerimeterExtraParts(northwestCorner, "Northwest")
    GetPerimeterExtraParts(southeastCorner, "Southeast")
    GetPerimeterExtraParts(southwestCorner, "Southwest")

    GetPerimeterExtraParts(eastPerimeter, "East")
    GetPerimeterExtraParts(northPerimeter, "North")
    GetPerimeterExtraParts(southPerimeter, "South")
    GetPerimeterExtraParts(westPerimeter, "West")


    GetCornerExtraParts(northeastCorner, "Northeast")
    GetCornerExtraParts(northwestCorner, "Northwest")
    GetCornerExtraParts(southeastCorner, "Southeast")
    GetCornerExtraParts(southwestCorner, "Southwest")
    -- Randomly select a wall tile to clone for placement
    if #wallTiles > 0 then
        local randomIndex = math.random(#wallTiles)
        local selectedWallTile = wallTiles[randomIndex]

        -- Create a wall at the location of each matching part with consideration of direction
        for _, entry in ipairs(PerimeterExtraParts) do
            local part = entry.part
            local direction = entry.direction


            for level = 1, wallHeight do
                
                local newWall = selectedWallTile:Clone()

                local heightOffset = (level - 1) * wallHeight  -- Calculate height offset for each level
                --newWall:PivotTo(part.CFrame * CFrame.new(0, heightOffset + wallHeight / 2, 0))  -- Adjust vertical position by half the wall height to center it

                --newWall:PivotTo(part.CFrame)  -- Set initial position
                newWall.Parent = part.Parent  -- Assuming the part's parent is where you want the wall to be
    
                -- Adjust orientation based on direction
                local rotationCFrame
                if direction == "North" then
                    rotationCFrame = CFrame.Angles(0, math.rad(180), 0)  -- Rotate 180 degrees
                elseif direction == "East" then
                    rotationCFrame = CFrame.Angles(0, math.rad(90), 0)   -- Rotate 90 degrees
                elseif direction == "South" then
                    rotationCFrame = CFrame.Angles(0, math.rad(0), 0)    -- No rotation needed
                elseif direction == "West" then
                    rotationCFrame = CFrame.Angles(0, math.rad(-90), 0)  -- Rotate -90 degrees
                elseif direction == "Northeast" then
                    rotationCFrame = CFrame.Angles(0, math.rad(90), 0)  -- Rotate -90 degrees
                elseif direction == "Northwest" then
                    rotationCFrame = CFrame.Angles(0, math.rad(-90), 0)  -- Rotate -90 degrees
                elseif direction == "Southeast" then
                    rotationCFrame = CFrame.Angles(0, math.rad(90), 0)  -- Rotate -90 degrees
                elseif direction == "Southwest" then
                    rotationCFrame = CFrame.Angles(0, math.rad(-90), 0)  -- Rotate -90 degrees
                else
                    rotationCFrame = CFrame.new()  -- Default no rotation
                end
    
                newWall:SetPrimaryPartCFrame(part.CFrame * CFrame.new(0, heightOffset * 2.5, 0) * rotationCFrame)
                newWall.Parent = part.Parent  -- Assuming the part's parent is where you want the wall to be

                -- Apply the rotation to the newWall
                --newWall:SetPrimaryPartCFrame(part.CFrame * rotationCFrame)
                
                -- print("Wall created at:", newWall.Position, "Direction:", direction)
            end

         
        end

        for _, entry in ipairs(CornerExtraParts) do
            local part = entry.part
            local direction = entry.direction


            for level = 1, wallHeight do
                
                local newWall = selectedWallTile:Clone()

                local heightOffset = (level - 1) * wallHeight  -- Calculate height offset for each level
                newWall.Parent = part.Parent  -- Assuming the part's parent is where you want the wall to be
    
                -- Adjust orientation based on direction
                local rotationCFrame
                
                 if direction == "Northeast" then
                    rotationCFrame = CFrame.Angles(0, math.rad(180), 0)  -- Rotate -90 degrees NW SW
                elseif direction == "Northwest" then
                    rotationCFrame = CFrame.Angles(0, math.rad(180), 0)  -- Rotate -90 degrees
                elseif direction == "Southeast" then
                    rotationCFrame = CFrame.Angles(0, math.rad(0), 0)  -- Rotate -90 degrees
                elseif direction == "Southwest" then
                    rotationCFrame = CFrame.Angles(0, math.rad(0), 0)  -- Rotate -90 degrees
                else
                    rotationCFrame = CFrame.new()  -- Default no rotation
                end
    
                newWall:SetPrimaryPartCFrame(part.CFrame * CFrame.new(0, heightOffset * 2.5, 0) * rotationCFrame)
                newWall.Parent = part.Parent  -- Assuming the part's parent is where you want the wall to be

               
            end

         
        end
    else
        print("No wall tiles available in the folder.")
    end

end


return Wall

--Rotate the North newWall by 180

