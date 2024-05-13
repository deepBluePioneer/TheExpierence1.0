local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Packages = ReplicatedStorage.Packages
local Gizmo = require(Packages.imgizmo)
local Knit = require(Packages.Knit)

local mst = require(script.Parent.mst)
local ProcGen_Controller = Knit.CreateController { Name = "ProcGen_Controller" }
local RoomSizeConfig =require(script.Parent.RoomSizeConfig)
local CalculateDelaneyRooms = require(script.Parent.CalculateDelaneyRooms)
local GridManager = require(script.Parent.GridManager)
local MapManager = require(script.Parent.MapManager)
local PathfindingManager = require(script.Parent.PathfindingManager)


local CellPopulator =  require(script.Parent.CellPopulator)
local GlobalGridCells



function ProcGen_Controller:isAreaAvailable(gridCells, startX, startY, roomWidth, roomHeight, buffer)
    buffer = buffer or 1 -- Default buffer of 1 cell around the room if not specified
    local endX = startX + roomWidth + buffer - 1
    local endY = startY + roomHeight + buffer - 1

    -- Check bounds to ensure the room with buffer fits within the grid
    if endX > #gridCells or endY > #gridCells[1] then
        return false
    end

    -- Check each cell within the enlarged area
    for i = startX - buffer, endX do
        for j = startY - buffer, endY do
            if i >= 1 and j >= 1 and i <= #gridCells and j <= #gridCells[1] then -- Ensure indices are within grid bounds
                if gridCells[i][j].Taken then
                    return false -- Return false if any part of the area (including buffer) is already taken
                end
            end
        end
    end
    return true
end
function ProcGen_Controller:createRoomFromGrid(gridCells, startX, startY, roomWidth, roomHeight, roomIndex)
    -- Calculate the total size of the room
    local roomSize = Vector3.new(roomWidth * 12, 12, roomHeight * 12) -- Each box is 12x12x12 units, height remains 12

    -- Calculate the CFrame position for the room's center
    local baseCFrame = gridCells[startX][startY].CFrame
    local xOffset = (roomWidth - 1) * 12 / 2  -- Offset to center the part within the room area horizontally
    local zOffset = (roomHeight - 1) * 12 / 2 -- Offset to center the part within the room area vertically
    local roomCFrame = baseCFrame * CFrame.new(xOffset, roomSize.Y / 2, zOffset) -- Adjusting CFrame to the center of the room

    -- Create a part at the calculated position and size
    local roomPart = Instance.new("Part")
    roomPart.Name = "Room_"..tostring(roomIndex)
    roomPart.Size = roomSize
    roomPart.Transparency = 1
    roomPart.CFrame = roomCFrame
    roomPart.Anchored = true
    roomPart.CanCollide = false

   -- roomPart.Color = Color3.new(math.random(), math.random(), math.random()) -- Assign a random color
    roomPart.Color = Color3.new(0, 0, 0) -- Assign a random color
    roomPart.Parent = workspace  -- Assuming the workspace is the desired parent

     -- Mark cells as taken and collect the subset for the room
     local roomCells = {}
     for i = startX, startX + roomWidth - 1 do
         roomCells[i - startX + 1] = {}
         for j = startY, startY + roomHeight - 1 do
             --gridCells[i][j].Taken = true
             roomCells[i - startX + 1][j - startY + 1] = gridCells[i][j]
         end
     end

    -- Create a model to contain all parts of the room
    local roomModel = Instance.new("Model")
    roomModel.Name = "RoomModel_"..tostring(roomIndex)
    roomModel.Parent = workspace
    roomPart.Parent = roomModel



    return roomPart
end

function ProcGen_Controller:createPositionToRoomIdMap(createdRooms)
    local positionToRoomId = {}
    for i, room in ipairs(createdRooms) do
        -- Ensure to capture position correctly; watch out for potential casing or typo like 'pos.z'
        local pos = room.Position
        local key = string.format("%d,%d", math.floor(pos.X), math.floor(pos.Z))  -- Corrected to 'pos.Z' assuming 'Z' is capitalized
        positionToRoomId[key] = {index = i, room = room}  -- Store both index and room object
    end
    return positionToRoomId
end




function ProcGen_Controller:createRoomCells(gridCells, preconfigured_rooms)
    local gridSizeX = #gridCells
    local gridSizeY = #gridCells[1]  -- Assuming the grid is rectangular
    local roomIndex = 0  -- Initialize room index counter

    local roomPartsTable = {}
    local perimeterCellsTable = {}

    local cornerCellsTable= {}

    local perimeterCellsList = {} -- List to store all perimeter cells for trying placements

  
    -- Iterate over each room in the preconfigured list
    for _, room in ipairs(preconfigured_rooms) do
        local roomWidth = room.width
        local roomHeight = room.height

        local isAvailable = false

        local attempt = 0
        local maxAttempts = 10  -- Adjust as needed
        
        -- Keep trying to place the room until it's successfully placed or max attempts reached
        while not isAvailable and attempt < maxAttempts do
            attempt = attempt + 1

            -- Find a random location for the room on the grid
          --  local startX = math.random(1, gridSizeX - roomWidth + 1)
           --local startY = math.random(1, gridSizeY - roomHeight + 1)

            local startX, startY
            local foundSpot = false

            -- Check if the selected location and its surroundings are available
            local isValidLocation = true

            local tempPerimeterCells = {}  -- Temporary table to store perimeter cells for this attempt
            local tempCornerCells = {}  -- Temporary table to store perimeter cells for this attempt

            local tempCellsInfo = {}  -- Temporary table to store perimeter cells for this attempt
            local tempCellsCornerInfo = {}  -- Temporary table to store perimeter cells for this attempt


            for i = startX - 1, startX + roomWidth do
                for j = startY - 1, startY + roomHeight do
                    if gridCells[i] and gridCells[i][j] and gridCells[i][j].Taken then
                        isValidLocation = false
                        break
                    end
                end
                if not isValidLocation then
                    break
                end
            end

            if isValidLocation then

                roomIndex += 1
                local roomPart = ProcGen_Controller:createRoomFromGrid(gridCells, startX, startY, roomWidth, roomHeight, roomIndex)
                table.insert(roomPartsTable, roomPart)
                isAvailable = true
                -- Mark cells as taken and create parts for the room
                for i = startX, startX + roomWidth - 1 do
                    for j = startY, startY + roomHeight - 1 do

                        gridCells[i][j].Taken = true
                        gridCells[i][j].innerCell = true
                        
                        gridCells[i][j].Size = Vector3.new(12, 12, 12)  -- Adjust size as needed

                        -- Create a part at the cell's location
                        local part = Instance.new("Part")
                        part.Size = gridCells[i][j].Size
                        part.Position = gridCells[i][j].Position
                        part.Anchored = true
                        part.CanCollide = false
                        part.Parent = workspace  -- Assuming workspace is the parent for the parts
                        part.Color = Color3.new(0.341176, 0.341176, 0.341176)  -- Set East perimeter color (Green)
                        part.Transparency = 1
                        -- Check if the cell is on the perimeter of the room
                        local isPerimeter = (i == startX or i == startX + roomWidth - 1 or j == startY or j == startY + roomHeight - 1)
                        if isPerimeter then
                            -- Set perimeter colors based on location
                            if i == startX then
                                gridCells[i][j].Perimeter_West = true
                                gridCells[i][j].innerCell = false
                                part.Color = Color3.new(1, 0, 0)  -- Red (West perimeter)
                                
                            elseif i == startX + roomWidth - 1 then
                                gridCells[i][j].Perimeter_East = true
                                gridCells[i][j].innerCell = false
                                part.Color = Color3.new(0, 1, 0)  -- Green (East perimeter)
                            elseif j == startY then
                                gridCells[i][j].Perimeter_North = true
                                gridCells[i][j].innerCell = false
                                part.Color = Color3.new(0, 0, 1)  -- Blue (North perimeter)
                            elseif j == startY + roomHeight - 1 then
                                gridCells[i][j].Perimeter_South = true
                                gridCells[i][j].innerCell = false
                                part.Color = Color3.new(1, 1, 0)  -- Yellow (South perimeter)
                            end

                            -- Check for corner cells
                            if (i == startX or i == startX + roomWidth - 1) and (j == startY or j == startY + roomHeight - 1) then
                                -- It's a corner, keep Taken as true and set corner colors
                                if i == startX and j == startY then
                                    part.Color = Color3.new(0.333333, 0.972549, 0.909803)  -- White (Northwest corner)
                                    gridCells[i][j].Corner_Northwest = true
                                    gridCells[i][j].innerCell = false
                                    gridCells[i][j].Taken = true


                                    table.insert(tempCellsCornerInfo, gridCells[i][j])
                                    table.insert(tempCornerCells, {x = i, y = j})
                                elseif i == startX and j == startY + roomHeight - 1 then
                                    part.Color = Color3.new(0, 1, 1)  -- Cyan (Southwest corner)
                                    gridCells[i][j].Corner_Southwest = true
                                    gridCells[i][j].innerCell = false
                                    gridCells[i][j].Taken = true

                                    table.insert(tempCellsCornerInfo, gridCells[i][j])
                                    table.insert(tempCornerCells, {x = i, y = j})
                                    

                                elseif i == startX + roomWidth - 1 and j == startY then
                                    part.Color = Color3.new(1, 0, 1)  -- Magenta (Northeast corner)
                                    gridCells[i][j].Corner_Northeast = true
                                    gridCells[i][j].innerCell = false
                                    gridCells[i][j].Taken = true

                                    table.insert(tempCellsCornerInfo, gridCells[i][j])
                                    table.insert(tempCornerCells, {x = i, y = j})

                                elseif i == startX + roomWidth - 1 and j == startY + roomHeight - 1 then
                                    part.Color = Color3.new(0.411764, 0.368627, 0.819607)  -- Black (Southeast corner)
                                    gridCells[i][j].Corner_Southeast = true
                                    gridCells[i][j].innerCell = false
                                    gridCells[i][j].Taken = true
                                  

                                    table.insert(tempCellsCornerInfo, gridCells[i][j])
                                    table.insert(tempCornerCells, {x = i, y = j})

                                end
                            else
                                -- Not a corner, so mark non-corner perimeter cells as not taken
                                gridCells[i][j].Taken = false
                                gridCells[i][j].innerCell = false
                                table.insert(tempCellsInfo, gridCells[i][j])
                                table.insert(tempPerimeterCells, {x = i, y = j})
                            end

                            
                        end


                    end
                end

                table.insert(perimeterCellsTable, {room = roomPart, cells = tempPerimeterCells, cellInfo = tempCellsInfo})
                table.insert(cornerCellsTable, {room = roomPart, cells = tempCornerCells, cellInfo = tempCellsCornerInfo})

            end
        end

        if not isAvailable then
            warn("Failed to find a valid location for room after "..maxAttempts.." attempts. Retrying...")
            -- You can add additional logic here for retrying, such as adjusting room dimensions or positions
        end
    end

    return roomPartsTable, perimeterCellsTable, cornerCellsTable, gridCells
end 


function ProcGen_Controller:KnitStart()


end

    
local function  Start()
    
    Gizmo.Init()
   
   -- local gridCells = GridManager:createGrid()

   -- local roomPartsTable , perimeterCellsTable, cornerCellsTable, gridCells=  ProcGen_Controller:createRoomCells(gridCells,  RoomSizeConfig.rooms )
   -- GlobalGridCells = gridCells


--[[

local trianglesData = CalculateDelaneyRooms:triangulateRooms(roomPartsTable)
local points, edges = CalculateDelaneyRooms:createPointsAndEdges(trianglesData)
local tree = mst.tree(points,edges)
--MSTManager:DrawMST(tree)

local positionToRoomId = ProcGen_Controller:createPositionToRoomIdMap(roomPartsTable)
--MSTManager:printTreeWithRoomIds(tree, positionToRoomId)

local paths, gridCells = PathfindingManager:luastarInit(GlobalGridCells ,perimeterCellsTable,tree,positionToRoomId)
GlobalGridCells = gridCells



]] 
--We ned to sanitize the floor taken cells
for i = 1, #GlobalGridCells do
    for j = 1, #GlobalGridCells[i] do
        local cell = GlobalGridCells[i][j]

         -- Resetting perimeter flags based on the presence of corner flags
        if cell.Corner_Northwest then
            if cell.Perimeter_North then
                cell.Perimeter_North = false
            end
            if cell.Perimeter_West then
                cell.Perimeter_West = false
            end
        end

        if cell.Corner_Northeast then
            if cell.Perimeter_North then
                cell.Perimeter_North = false
            end
            if cell.Perimeter_East then
                cell.Perimeter_East = false
            end
        end

        if cell.Corner_Southwest then
            if cell.Perimeter_South then
                cell.Perimeter_South = false
            end
            if cell.Perimeter_West then
                cell.Perimeter_West = false
            end
        end

        if cell.Corner_Southeast then
            if cell.Perimeter_South then
                cell.Perimeter_South = false
            end
            if cell.Perimeter_East then
                cell.Perimeter_East = false
            end
        end

        CellPopulator.createWalls(cell.CFrame, workspace, cell)
        CellPopulator.createCorners(cell.CFrame, workspace, cell)


       CellPopulator.createCornerPathPieces(cell.CFrame, workspace, cell)
        CellPopulator.createCorridorPathPieces(cell.CFrame, workspace, cell)
      -- cell.Taken = true

        if cell.Perimeter_East or cell.Perimeter_North or cell.Perimeter_South or cell.Perimeter_West then
        
            cell.Taken = true

            if cell.Corridor_WallPart then

                if cell.Perimeter_WallPart then

                    cell.Perimeter_WallPart.Parent = nil
                    cell.Perimeter_WallPart = nil 

                    cell.Corridor_WallPart.Parent = nil 
                    cell.Corridor_WallPart = nil 


                end

           
            end
            

        end

    end
end    
   
   -- MapManager:CreateUIAscii(GlobalGridCells)


end




function ProcGen_Controller:KnitInit()
--  Start()
    
end

return ProcGen_Controller