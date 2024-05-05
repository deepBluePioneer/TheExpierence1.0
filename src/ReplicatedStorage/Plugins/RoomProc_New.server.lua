local ChangeHistoryService = game:GetService("ChangeHistoryService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local toolbar = plugin:CreateToolbar("Room Tools")
-- Add a toolbar button named "Generate Room"
local generateRoomButton = toolbar:CreateButton("Generate Room", "Generate a room structure", "rbxassetid://1234567890")
generateRoomButton.ClickableWhenViewportHidden = true

local PrefabsFolder = ReplicatedStorage:WaitForChild("Prefabs")
local floorTilesFolder = PrefabsFolder:WaitForChild("FloorTiles")
local wallTilesFolder = PrefabsFolder:WaitForChild("WallTiles")
local DecorationsFolder = PrefabsFolder:WaitForChild("Decorations")
local Torches =  DecorationsFolder.Torch:GetChildren()
local SingleTileMiscItemsFolder =  DecorationsFolder:WaitForChild("SingleTileMiscItems")

local northColor = BrickColor.new("Bright blue") -- North
local southColor = BrickColor.new("Bright red") -- South
local eastColor = BrickColor.new("Lime green") -- East
local westColor = BrickColor.new("Bright yellow") -- West

local gridSize = 4

local function resizeAndPositionWall(wallClone, tileSize, position)
    -- Resize the wall to match the floor tile size
    wallClone.Size = Vector3.new(tileSize, wallClone.Size.Y, wallClone.Size.Z) -- Adjust the wall size
    wallClone.Position = position
end
local function addHighlightToModel(model, color)
    local highlight = Instance.new("Highlight", model)
    highlight.FillColor = color
    highlight.FillTransparency = 0.80  -- Example transparency, adjust as needed
    highlight.OutlineColor = Color3.new(0, 0, 0)  -- Example outline color, adjust as needed
    highlight.OutlineTransparency = 0.5  -- Example outline transparency, adjust as needed
    --highlight.DepthMode = Enum.HighlightDepthMode.Occluded  -- Set highlight to be visible only when occluded

end
local function rotateWall(wallClone, rotationDegrees)
    wallClone.Orientation = wallClone.Orientation + Vector3.new(0, rotationDegrees, 0)
end
local function rotateWallModel(model)
    -- Iterate through all children of the model
    for _, child in ipairs(model:GetChildren()) do
        -- Check if the child is a Part
        if child:IsA("MeshPart") then
            -- Rotate the part by 180 degrees around the Y-axis
            child.CFrame = child.CFrame * CFrame.Angles(0, math.rad(180), 0)
        elseif child:IsA("Model") then
            -- Recursively rotate child models
            rotateWallModel(child)
        end
    end
end
local function rotateCeilingModel(model)
    -- Iterate through all children of the model
    for _, child in ipairs(model:GetChildren()) do
        -- Check if the child is a Part
        if child:IsA("MeshPart") then
            -- Rotate the part by 180 degrees around the Y-axis
            child.CFrame = child.CFrame * CFrame.Angles(0, 0, math.rad(180))
        elseif child:IsA("Model") then
            -- Recursively rotate child models
            rotateWallModel(child)
        end
    end
end
local function generateWalls(gridWidth, gridLength, wallTileSample, tileSize, parentModel)
    local northWallsModel = Instance.new("Model", parentModel)
    northWallsModel.Name = "NorthWalls"
    local southWallsModel = Instance.new("Model", parentModel)
    southWallsModel.Name = "SouthWalls"
    local eastWallsModel = Instance.new("Model", parentModel)
    eastWallsModel.Name = "EastWalls"
    local westWallsModel = Instance.new("Model", parentModel)
    westWallsModel.Name = "WestWalls"

    -- Highlight models for visibility
    --addHighlightToModel(northWallsModel, Color3.fromRGB(0, 162, 255))
    ---addHighlightToModel(southWallsModel, Color3.fromRGB(255, 0, 0))
    --addHighlightToModel(eastWallsModel, Color3.fromRGB(0, 255, 0))
    --addHighlightToModel(westWallsModel, Color3.fromRGB(255, 255, 0))

    local skippedLocations = {}  -- Improved structure for clarity on wall sides

    local middleX = math.ceil(gridWidth / 2)
    local middleZ = math.ceil(gridLength / 2)

    -- Process x-axis walls
    for x = 1, gridWidth do
        local wallCloneBottom = wallTileSample:Clone()
        local wallCloneTop = wallTileSample:Clone()
        resizeAndPositionWall(wallCloneBottom, tileSize, Vector3.new((x - 1) * tileSize + tileSize / 2, wallTileSample.Size.Y / 2, -wallTileSample.Size.Z / 2))
        resizeAndPositionWall(wallCloneTop, tileSize, Vector3.new((x - 1) * tileSize + tileSize / 2, wallTileSample.Size.Y / 2, gridLength * tileSize + wallTileSample.Size.Z / 2))
        wallCloneBottom.Parent = southWallsModel
        wallCloneTop.Parent = northWallsModel
        if x == middleX then
            -- Structure skippedLocations to include side information
            table.insert(skippedLocations, {wall = wallCloneTop, side = "North"})
            table.insert(skippedLocations, {wall = wallCloneBottom, side = "South"})
        end
    end

    -- Process z-axis walls
    for z = 1, gridLength do
        local wallCloneLeft = wallTileSample:Clone()
        local wallCloneRight = wallTileSample:Clone()
        resizeAndPositionWall(wallCloneLeft, tileSize, Vector3.new(-wallTileSample.Size.Z / 2, wallTileSample.Size.Y / 2, (z - 1) * tileSize + tileSize / 2))
        resizeAndPositionWall(wallCloneRight, tileSize, Vector3.new(gridWidth * tileSize + wallTileSample.Size.Z / 2, wallTileSample.Size.Y / 2, (z - 1) * tileSize + tileSize / 2))
        rotateWall(wallCloneLeft, 90)
        rotateWall(wallCloneRight, 90)
        wallCloneLeft.Parent = westWallsModel
        wallCloneRight.Parent = eastWallsModel
        if z == middleZ then
            -- Include side information in skippedLocations
            table.insert(skippedLocations, {wall = wallCloneLeft, side = "West"})
            table.insert(skippedLocations, {wall = wallCloneRight, side = "East"})
        end
    end

    -- Rotate specific walls for proper orientation
    rotateWallModel(southWallsModel)
    rotateWallModel(westWallsModel)

    return northWallsModel, southWallsModel, eastWallsModel, westWallsModel, skippedLocations
end


local function placeMultipleRandomRubbleOnTiles(FloorTilesModel, numTiles)
    local rand = Random.new()  -- Create a new Random object for generating random numbers
    local RubbleFolder = SingleTileMiscItemsFolder.Rubble:GetChildren()

    -- Collect all inner tiles from the FloorTilesModel
    local innerTiles = FloorTilesModel.Inner_FloorModel:GetChildren()

    if #innerTiles == 0 or #RubbleFolder == 0 then
        warn("No inner tiles or rubble items available.")
        return
    end

    -- Select a few random tiles, not more than the number of available tiles
    numTiles = math.min(numTiles, #innerTiles)
    local selectedTiles = {}
    for i = 1, numTiles do
        local tileIndex = rand:NextInteger(1, #innerTiles)
        table.insert(selectedTiles, innerTiles[tileIndex])
        table.remove(innerTiles, tileIndex)  -- Remove to avoid re-selection
    end

    -- Place one rubble item on each selected tile
    for _, tile in ipairs(selectedTiles) do
        if #RubbleFolder == 0 then break end  -- Check if there are enough rubble items left
        local rubbleIndex = rand:NextInteger(1, #RubbleFolder)
        local selectedRubble = RubbleFolder[rubbleIndex]:Clone()

        -- Randomize rotation around the Y-axis
        local randomYRotation = CFrame.Angles(0, math.rad(rand:NextInteger(0, 360)), 0)
        local newPivot = tile.CFrame * CFrame.new(0, tile.Size.Y / 2 + selectedRubble.Size.Y / 2, 0) * randomYRotation

        -- Check if selectedRubble is a part and use PivotTo
        if selectedRubble:IsA("Part") then
            selectedRubble:PivotTo(newPivot)
        else
            -- For models or other types, set the CFrame directly
            selectedRubble.CFrame = newPivot
        end
        
        selectedRubble.Parent = FloorTilesModel.Inner_FloorModel
    end
end




local function placeTorchesOnPerimeter(FloorTilesModel, torchHeight, numberOfTorches)
    local torch = Torches[1]  -- Assuming Torches is a predefined table with Model references
    local rand = Random.new()  -- Create a new Random object for generating random numbers

    -- Retrieve North and South tiles
    local northTiles = FloorTilesModel.NorthPerimeterFloors:GetChildren()
    local southTiles = FloorTilesModel.SouthPerimeterFloors:GetChildren()
    local combinedTiles = {}

    -- Combine North and South tiles into one list
    for i = 1, #northTiles do
        table.insert(combinedTiles, northTiles[i])
    end
    for i = 1, #southTiles do
        table.insert(combinedTiles, southTiles[i])
    end

    -- Define rotations for North and South facing tiles
    local northRotation = CFrame.Angles(0, math.rad(180), 0)  -- North facing South
    local southRotation = CFrame.Angles(0, math.rad(0), 0)    -- South facing North

    -- Check if there are enough tiles
    if #combinedTiles < numberOfTorches then
        warn("Not enough tiles available or number of torches requested exceeds available tiles.")
        return {}
    end

    -- Shuffle and select a subset of tiles
    for i = 1, numberOfTorches do
        local index = rand:NextInteger(i, #combinedTiles)
        combinedTiles[i], combinedTiles[index] = combinedTiles[index], combinedTiles[i]  -- Swap to shuffle
    end

    local removedTiles = {}  -- To store tiles that have torches placed on them

    -- Place torches on the selected tiles with the correct orientation
    for i = 1, numberOfTorches do
        local tile = combinedTiles[i]
        local torchClone = torch:Clone()
        local rotation = tile.Parent == FloorTilesModel.NorthPerimeterFloors and northRotation or southRotation
        local zOffset = (tile.Parent == FloorTilesModel.SouthPerimeterFloors) and 12 or 0  -- Adjust Z offset for South tiles
        torchClone:PivotTo(tile.CFrame * CFrame.new(0, torchHeight + tile.Size.Y * 0.5, (-tile.Size.Z / 2) + zOffset) * rotation)
        torchClone.Parent = tile.Parent  -- Parent the torch to the same model as the tile

        -- Add to removedTiles list
        table.insert(removedTiles, tile)
    end

    return removedTiles  -- Return the tiles from which torches were placed
end













local function generateFloor(gridWidth, gridLength, tileSample, tileSize, parentModel)
    -- Root floor model
    local FloorTilesModel = Instance.new("Model", parentModel)
    FloorTilesModel.Name = "FloorTilesModel"
    
    -- Model for inner floor tiles
    local Inner_FloorModel = Instance.new("Model", FloorTilesModel)
    Inner_FloorModel.Name = "Inner_FloorModel"

    -- Models for each direction of perimeter floor tiles
    local NorthModel = Instance.new("Model", FloorTilesModel)
    NorthModel.Name = "NorthPerimeterFloors"

    local SouthModel = Instance.new("Model", FloorTilesModel)
    SouthModel.Name = "SouthPerimeterFloors"

    local EastModel = Instance.new("Model", FloorTilesModel)
    EastModel.Name = "EastPerimeterFloors"

    local WestModel = Instance.new("Model", FloorTilesModel)
    WestModel.Name = "WestPerimeterFloors"

    local tilesTable = {}  -- Initialize a table to hold references to all tile clones

    -- Generate the floor and store each tile clone in the table
    for x = 1, gridWidth do
        tilesTable[x] = {}  -- Create a new row in the table for each column of tiles
        for z = 1, gridLength do
            local tileClone = tileSample:Clone()
            tileClone.Position = Vector3.new((x - 1) * tileSize + tileSize / 2, 0, (z - 1) * tileSize + tileSize / 2)

            -- Determine the appropriate model for each tile based on its position
            if x == 1 then
                tileClone.Parent = WestModel
            elseif x == gridWidth then
                tileClone.Parent = EastModel
            elseif z == 1 then
                tileClone.Parent = NorthModel
            elseif z == gridLength then
                tileClone.Parent = SouthModel
            else
                tileClone.Parent = Inner_FloorModel
            end

            tilesTable[x][z] = tileClone  -- Store the clone in the table
        end
    end
        
    placeTorchesOnPerimeter(FloorTilesModel, 0, 4)
   -- local innerTiles = FloorTilesModel.Inner_FloorModel:GetChildren()

    --print(removedTiles)
    placeMultipleRandomRubbleOnTiles(FloorTilesModel, 15)  -- Place rubble on 5 tiles, up to 3 pieces of rubble per tile

    
    return tilesTable, FloorTilesModel
end






local function generateCeiling(gridWidth, gridLength, tileSample, tileSize, wallHeight, parentModel)
    local ceilingModel = Instance.new("Model", parentModel)
    ceilingModel.Name = "Ceiling"

    local ceilingTilesTable = {}

    -- The Y position of the ceiling is now dynamically set based on wall height
    for x = 1, gridWidth do
        ceilingTilesTable[x] = {}
        for z = 1, gridLength do
            local tileClone = tileSample:Clone()
            tileClone.Position = Vector3.new((x - 1) * tileSize + tileSize / 2, wallHeight, (z - 1) * tileSize + tileSize / 2)
            tileClone.Parent = ceilingModel
            ceilingTilesTable[x][z] = tileClone
        end
    end

    rotateCeilingModel(ceilingModel)

    return ceilingTilesTable, ceilingModel
end



local function determinePerimeterStatus(row, col, numRows, numCols)
    local isPerimeter = false
    local perimeterStatus = ""
    
    -- Check for North Perimeter
    if row == 1 then
        perimeterStatus = perimeterStatus .. "North-Perimeter "
        isPerimeter = true
    end
    
    -- Check for South Perimeter
    if row == numRows then
        perimeterStatus = perimeterStatus .. "South-Perimeter "
        isPerimeter = true
    end
    
    -- Check for West Perimeter
    if col == 1 then
        perimeterStatus = perimeterStatus .. "West-Perimeter "
        isPerimeter = true
    end
    
    -- Check for East Perimeter
    if col == numCols then
        perimeterStatus = perimeterStatus .. "East-Perimeter "
        isPerimeter = true
    end

    -- Trim the last space for cleaner status output
    perimeterStatus = perimeterStatus:match("^%s*(.-)%s*$")

    -- Determine if it's a corner by checking the count of perimeter descriptions
    local isCorner = false
    local _, count = perimeterStatus:gsub("%-", "")
    if count > 1 then
        isCorner = true
    end

    -- Determine if it is on the perimeter but not a corner
    local isStrictPerimeter = isPerimeter and not isCorner

    return isPerimeter, perimeterStatus, isCorner, isStrictPerimeter
end



local function generateGrid()
    local gridWidth = 9
    local gridLength = 9

    local roomModel = Instance.new("Model", workspace)
    roomModel.Name = "GeneratedRoom"

    if #floorTilesFolder:GetChildren() == 0 or #wallTilesFolder:GetChildren() == 0 then
        error("Tiles not found in Prefabs folder.")
    end

    local tileSample = floorTilesFolder:GetChildren()[1]
    local wallTileSample = wallTilesFolder:GetChildren()[1]
    local tileSize = tileSample.Size.X
    local wallHeight = wallTileSample.Size.Y

    local tilesTable = generateFloor(gridWidth, gridLength, tileSample, tileSize, roomModel)
    local northWalls, southWalls, eastWalls, westWalls, skippedWallLocations = generateWalls(gridWidth, gridLength, wallTileSample, tileSize, roomModel)
    local ceilingTilesTable, ceilingModel = generateCeiling(gridWidth, gridLength, tileSample, tileSize, wallHeight, roomModel)

    if #tilesTable > 0 and #tilesTable[1] > 0 then
        roomModel.PrimaryPart = tilesTable[1][1]
    end

   

    return roomModel, tilesTable, {northWalls, southWalls, eastWalls, westWalls}, ceilingTilesTable, ceilingModel, skippedWallLocations
end
          
           
-- Blue North
-- Red South
-- Green East
-- Yellow West

         

local function generateRoomComplex(numRows, numCols)
    local complexModel = Instance.new("Model", workspace)
    complexModel.Name = "RoomComplex"

    local roomWidth = 9 * 12.5
    local roomDepth = 9 * 12.5
    local perimeterRooms = {}
    local perimeterStrictRooms = {}
    local perimeterCornerRooms = {}
    local innerRooms = {}

    for row = 1, numRows do
        for col = 1, numCols do
            local roomModel, _, wallModels, _, _, skippedWallLocations = generateGrid()
            roomModel.Parent = complexModel

            local xOffset = (col - 1) * roomWidth
            local zOffset = (row - 1) * roomDepth
            roomModel:SetPrimaryPartCFrame(CFrame.new(xOffset, 0, zOffset))

            local isPerimeter, perimeterStatus, isCorner, isStrictPerimeter = determinePerimeterStatus(row, col, numRows, numCols)
            -- Construct the name based on the room's perimeter status and if it's a corner
            local roomName = "Room " .. row .. "-" .. col
            if isPerimeter then
                roomName = roomName .. " (" .. perimeterStatus .. ")"
            end
            if isCorner then
                roomName = roomName .. " Corner"
                table.insert(perimeterCornerRooms, {
                    model = roomModel,
                    row = row,
                    col = col,
                    status = perimeterStatus,
                    skippedWalls = skippedWallLocations,
                    isCornerRoom = isCorner,
                    isStrictPerimeter = isStrictPerimeter
                })
            end

            if not isPerimeter and not isCorner then
                
                table.insert(innerRooms, {
                    model = roomModel,
                    row = row,
                    col = col,
                    status = perimeterStatus,
                    skippedWalls = skippedWallLocations,
                    isCornerRoom = isCorner,
                    isStrictPerimeter = isStrictPerimeter
                })

            end

            -- Rename the room model
            roomModel.Name = roomName

            -- Store perimeter room info
            if isPerimeter then
                table.insert(perimeterRooms, {
                    model = roomModel,
                    row = row,
                    col = col,
                    status = perimeterStatus,
                    skippedWalls = skippedWallLocations,
                    isCornerRoom = isCorner,
                    isStrictPerimeter = isStrictPerimeter
                })
            end

            if isStrictPerimeter then
                table.insert(perimeterStrictRooms, {
                    model = roomModel,
                    row = row,
                    col = col,
                    status = perimeterStatus,
                    skippedWalls = skippedWallLocations,
                    isCornerRoom = isCorner,
                    isStrictPerimeter = isStrictPerimeter
                })
            end

            -- Store room location data in each skipped wall location for later identification
            for _, wallInfo in ipairs(skippedWallLocations) do
                wallInfo.row = row
                wallInfo.col = col
            end

        
           local North_West_Corner = "North-Perimeter West-Perimeter"
           local North_East_Corner = "North-Perimeter East-Perimeter"
           local South_West_Corner = "South-Perimeter West-Perimeter"
           local South_East_Corner = "South-Perimeter East-Perimeter"
           
           for _, room in ipairs(perimeterCornerRooms) do            
           
               for _, wallInfo in ipairs(room.skippedWalls) do
                   local wall = wallInfo.wall
                   local side = wallInfo.side
           
                   -- Determine if this wall should be kept based on room side and wall side
                   local keepWall = false
                   
                   if room.status == North_West_Corner then  -- North-West Corner
                   keepWall = (side == "West" or side == "South")
                    elseif room.status == North_East_Corner then  -- North-East Corner
                        keepWall = (side == "East" or side == "South")
                    elseif room.status == South_West_Corner then  -- South-West Corner
                        keepWall = (side == "West" or side == "North")
                    elseif room.status == South_East_Corner then  -- South-East Corner
                        keepWall = (side == "East" or side == "North")
                    end
           
                   if not keepWall then
                       -- Keep this wall as it is on the perimeter side
                       --table.insert(wallsToKeep, wallInfo)
                       wall.Parent = nil  -- Make the wall fully transparent

                 
                   end
               end
           
            
           end


           
            -- Blue North
           -- Red South
           -- Green East
           -- Yellow West
           print("Listing Perimeter Walls:")
           for _, room in ipairs(perimeterStrictRooms) do            
                warn(room.status)

               for _, wallInfo in ipairs(room.skippedWalls) do
                   local wall = wallInfo.wall
                   local side = wallInfo.side
           
                   -- Determine if this wall should be kept based on room side and wall side
                   local keepWall = false
                   
                   if room.status == "North-Perimeter" then  -- North-West Corner
                        if side == "South" then
                            keepWall = true

                        end
                    elseif room.status == "East-Perimeter" then  -- North-East Corner
                        if side == "East" then
                            keepWall = true

                        end
                    elseif room.status == "South-Perimeter" then  -- South-West Corner
                        if side == "North" then
                            keepWall = true

                        end
                    elseif room.status == "West-Perimeter" then  -- South-East Corner
                        if side == "West" then
                            keepWall = true

                        end
                    end
           
                   if not keepWall then
                      
                       wall.Parent = nil

                 
                   end
               end
           
            
           end
           
           for _, room in ipairs(innerRooms) do            
           
                for _, wallInfo in ipairs(room.skippedWalls) do
                    local wall = wallInfo.wall
                    local side = wallInfo.side
            
                    wall.Parent = nil  -- Make the wall fully transparent
                end
        
         
        end
        
              
        end
    end


    return complexModel, perimeterRooms
end




local function onGenerateRoomButtonClicked()
    ChangeHistoryService:SetWaypoint("Before Generating Room Grid")
    print('Starting room generation')
   -- local generatedRoom = generateGrid() -- Generate the grid and walls

    local complex = generateRoomComplex(4, 4)  -- Create a 3x3 grid of rooms

    ChangeHistoryService:SetWaypoint("After Generating Room Grid")
end

generateRoomButton.Click:Connect(onGenerateRoomButtonClicked)
