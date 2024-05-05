local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MaterialService = game:GetService("MaterialService")

local CustomPackages = ReplicatedStorage.CustomPackages
local Packages = ReplicatedStorage.Packages
local Gizmo = require(Packages.imgizmo)
local Knit = require(Packages.Knit)

local mst = require(script.Parent.mst)

local ProcGen_Controller = Knit.CreateController { Name = "ProcGen_Controller" }
local RoomSizeConfig =require(script.Parent.RoomSizeConfig)
local CalculateDelaneyRooms = require(script.Parent.CalculateDelaneyRooms)
local GridManager = require(script.Parent.GridManager)
local MapManager = require(script.Parent.MapManager)
local MSTManager = require(script.Parent.MSTManager)
local PathfindingManager = require(script.Parent.PathfindingManager)

local PrefabsFolder = ReplicatedStorage:WaitForChild("Prefabs")
local floorTilesFolder = PrefabsFolder:WaitForChild("FloorTiles")
local WallTilesFolder = PrefabsFolder:WaitForChild("WallTiles")

local DecorationsFolder = PrefabsFolder:WaitForChild("Decorations").DecoModels

local FloorModule = require(script.Parent.FloorModule)
local CeillingModule = require(script.Parent.CeillingModule)
local DecoratorModule = require(script.Parent.DecoratorModule)
local WallModule = require(script.Parent.WallModule)





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
             gridCells[i][j].Taken = true
             roomCells[i - startX + 1][j - startY + 1] = gridCells[i][j]
         end
     end

    -- Create a model to contain all parts of the room
    local roomModel = Instance.new("Model")
    roomModel.Name = "RoomModel_"..tostring(roomIndex)
    roomModel.Parent = workspace
    roomPart.Parent = roomModel

    -- Initialize FloorModule with the room's specific grid cell subset
    local floor = FloorModule.new(roomModel, floorTilesFolder, roomCells)
    floor:generateFloor(roomWidth, roomHeight)

     --local ceilling = CeillingModule.new(roomModel, floorTilesFolder, roomCells)
     --ceilling:generateCeilling(roomWidth, roomHeight)

    local wall = WallModule.new(roomModel, WallTilesFolder)
    wall:generateWalls(floor, 1)
    
    --local deco = DecoratorModule.new(roomModel, DecorationsFolder, roomCells)
    --deco:generateDecorations(roomWidth, roomHeight)

    return roomPart
end
function ProcGen_Controller:createMultipleRooms(gridCells, rooms)
    local createdRooms = {}
    local roomPositions = {}  -- Store positions and dimensions for later adjacency checks
    local roomIndex = 1  -- Initialize room index counter

    -- First, try to place all rooms
    for _, room in ipairs(rooms) do
        local placed = false
        for attempt = 1, 100 do -- Try up to 100 different positions for each room
            local startX = math.random(1, #gridCells - room.width + 1)
            local startY = math.random(1, #gridCells[1] - room.height + 1)
            local roomBuffer = 2
            if self:isAreaAvailable(gridCells, startX, startY, room.width, room.height, roomBuffer) then
                local roomPart = self:createRoomFromGrid(gridCells, startX, startY, room.width, room.height, roomIndex)
                table.insert(createdRooms, roomPart)
                table.insert(roomPositions, {part = roomPart, x = startX, y = startY, width = room.width, height = room.height, index = roomIndex})
                
               

                placed = true
                break
            end
        end
        if not placed then
            print("Failed to place a room of size " .. room.width .. "x" .. room.height)
        else
            roomIndex = roomIndex + 1  -- Increment the index only upon successful placement
        end
    end

    -- After all rooms are placed, calculate adjacent free cells for each room
    local adjacentFreeCells = {}

    for _, roomInfo in ipairs(roomPositions) do
        local freeCells = self:getAdjacentFreeCells(gridCells, roomInfo.x, roomInfo.y, roomInfo.width, roomInfo.height)
        table.insert(adjacentFreeCells, {room = roomInfo.part, cells = freeCells})

         -- Calculate perimeter cells
         --local freeCells = self:getPerimeterCells(gridCells, roomInfo.x, roomInfo.y, roomInfo.width, roomInfo.height)
        -- table.insert(adjacentFreeCells, {room = roomInfo.part, cells = freeCells})

    end

    return createdRooms, adjacentFreeCells, roomPositions
end
function ProcGen_Controller:getAdjacentFreeCells(gridCells, startX, startY, width, height)
    local freeCells = {}
    -- Define corner positions to exclude
    local corners = {
        {x = startX - 1, y = startY - 1},
        {x = startX - 1, y = startY + height},
        {x = startX + width, y = startY - 1},
        {x = startX + width, y = startY + height}
    }

    -- Function to check if a cell is a corner
    local function isCorner(x, y)
        for _, corner in ipairs(corners) do
            if x == corner.x and y == corner.y then
                return true
            end
        end
        return false
    end

    -- Check cells around the perimeter of the room, excluding corners
    for x = startX - 1, startX + width do
        for y = startY - 1, startY + height do
            -- Exclude corners
            if not isCorner(x, y) then
                if (x == startX - 1 or x == startX + width or y == startY - 1 or y == startY + height) and
                   (x >= 1 and y >= 1 and x <= #gridCells and y <= #gridCells[1]) then
                    if not gridCells[x][y].Taken then
                        table.insert(freeCells, {x = x, y = y})
                    end
                end
            end
        end
    end
    return freeCells
end



function ProcGen_Controller:getPerimeterCells(gridCells, startX, startY, width, height)
    local freeCells = {}
    -- Define the second layer inner perimeter to check
    local innerStartX = startX + 1
    local innerEndX = startX + width - 2
    local innerStartY = startY + 1
    local innerEndY = startY + height - 2

    -- Check the second layer inner perimeter of the room
    for x = innerStartX, innerEndX do
        if x >= 1 and x <= #gridCells then
            -- Check the second row from the original top and bottom, ensuring it is within the grid and room dimensions
            if startY > 2 then  -- Two cells inside from the top row
                table.insert(freeCells, {x = x, y = startY - 2})
            end
            if startY + height - 1 < #gridCells[x] then  -- Two cells inside from the bottom row
                table.insert(freeCells, {x = x, y = startY + height - 1})
            end
        end
    end

    for y = innerStartY, innerEndY do
        if y >= 1 and y <= #gridCells[1] then
            -- Check the second column from the original left and right, ensuring it is within the grid and room dimensions
            if startX > 2 then  -- Two cells inside from the left column
                table.insert(freeCells, {x = startX - 2, y = y})
            end
            if startX + width - 1 < #gridCells and not gridCells[startX + width - 1][y] then  -- Two cells inside from the right column
                table.insert(freeCells, {x = startX + width - 1, y = y})
            end
        end
    end

    return freeCells
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

function ProcGen_Controller:KnitStart()

    Gizmo.Init()
   
    local gridCells = GridManager:createGrid()
  
    local createdRooms, adjacentFreeCells = ProcGen_Controller:createMultipleRooms(gridCells, RoomSizeConfig.rooms)
    warn(adjacentFreeCells)
   
    local trianglesData = CalculateDelaneyRooms:triangulateRooms(createdRooms)

    local points, edges = CalculateDelaneyRooms:createPointsAndEdges(trianglesData)

    local tree = mst.tree(points,edges)

   
    MSTManager:DrawMST(tree)

    local positionToRoomId = ProcGen_Controller:createPositionToRoomIdMap(createdRooms)
    MSTManager:printTreeWithRoomIds(tree, positionToRoomId)
    
    local paths, gridCells = PathfindingManager:luastarInit(gridCells ,adjacentFreeCells,tree,positionToRoomId)
    
    --ProcGen_Controller:CreateUI(gridCells)
    MapManager:CreateUIAscii(gridCells)

end










function ProcGen_Controller:KnitInit()

    

    -- Add controller initialization logic here
end

return ProcGen_Controller