local PathfindingManager = {}
local luastar =  require(script.Parent.astar)


local CellPopulator =  require(script.Parent.CellPopulator)
local UpdatedGridCells


local function Debug_CreatePathPart(x, y, gridCells, color)
    
    local cell = gridCells[x][y]
    local part = Instance.new("Part")
    part.Size = cell.Size
    part.Position = cell.CFrame.Position + Vector3.new(0, part.Size.Y / 2, 0)
    part.Anchored = true
    part.CanCollide = false
    part.Transparency = 1
    part.Color = color
    part.Material = Enum.Material.Plastic
    part.Parent = workspace
    gridCells[x][y].Taken = true

    return part, gridCells
end
    

    -- Helper function to find the closest cells between two sets of cells
local function findClosestCells(cellsA, cellsB)
    local minDistance = math.huge
    local closestPair = {a = nil, b = nil}

    for _, cellA in ipairs(cellsA) do
        for _, cellB in ipairs(cellsB) do
            local distance = (cellA.x - cellB.x)^2 + (cellA.y - cellB.y)^2
            if distance < minDistance then
                minDistance = distance
                closestPair.a = cellA
                closestPair.b = cellB
            end
        end
    end
    return closestPair.a, closestPair.b
end

local function SetPathCorridorProperties(prevNode, currentNode, nextNode, gridCells)

    
    local dx1 = currentNode.x - prevNode.x
    local dy1 = currentNode.y - prevNode.y
    local dx2 = nextNode.x - currentNode.x
    local dy2 = nextNode.y - currentNode.y

    local x = currentNode.x
    local y = currentNode.y

    -- Determine corridor types based on movement
     if dx1 == 0 and dx2 == 0 then
        gridCells[x][y].VerticalCorridor = true
    elseif dy1 == 0 and dy2 == 0 then
        gridCells[x][y].HorizontalCorridor = true
    end

    return gridCells

end

--[[
gridCells[i][j].innerCell = false

one of these would be true
gridCells[x][y].VerticalCorridor 
gridCells[x][y].HorizontalCorridor 
gridCells[x][y].Perimeter_North 
gridCells[x][y].Perimeter_East 
gridCells[x][y].Perimeter_West 
gridCells[x][y].Perimeter_South 



]]

local function SetPathCornerProperties(prevNode, currentNode, nextNode, gridCells)
    local dx1 = currentNode.x - prevNode.x
    local dy1 = currentNode.y - prevNode.y
    local dx2 = nextNode.x - currentNode.x
    local dy2 = nextNode.y - currentNode.y

    local x = currentNode.x
    local y = currentNode.y
    local color = nil

    -- Determine direction and set appropriate corner properties
    if dx1 == 0 then  -- Initially moving vertically (North or South)
        if dy1 > 0 then  -- Moving South
            if dx2 > 0 then
                gridCells[x][y].SouthLeftTurn = true
            elseif dx2 < 0 then
                gridCells[x][y].SouthRightTurn = true
            end
        elseif dy1 < 0 then  -- Moving North
            if dx2 > 0 then
                gridCells[x][y].NorthRightTurn = true
            elseif dx2 < 0 then
                gridCells[x][y].NorthLeftTurn = true
            end
        end
    elseif dy1 == 0 then  -- Initially moving horizontally (East or West)
        if dx1 > 0 then  -- Moving East
            if dy2 > 0 then
                gridCells[x][y].SouthLeftTurn = true
            elseif dy2 < 0 then
                gridCells[x][y].NorthRightTurn = true
            end
        elseif dx1 < 0 then  -- Moving West
            if dy2 > 0 then
                gridCells[x][y].SouthRightTurn = true
                color = Color3.new(0.5, 0.5, 0)  -- Olive for right turn
            elseif dy2 < 0 then
                gridCells[x][y].NorthLeftTurn = true
            end
        end
    end

    return gridCells, color -- Return the updated gridCells and the determined corner color
end



-- Function to get the direction between two nodes
local function getDirection(fromNode, toNode)
    local dx = toNode.x - fromNode.x
    local dy = toNode.y - fromNode.y

    if dx == 0 and dy > 0 then
        return "North"
    elseif dx == 0 and dy < 0 then
        return "South"
    elseif dy == 0 and dx > 0 then
        return "East"
    elseif dy == 0 and dx < 0 then
        return "West"
    elseif dx > 0 and dy > 0 then
        return "Northeast"
    elseif dx > 0 and dy < 0 then
        return "Southeast"
    elseif dx < 0 and dy > 0 then
        return "Northwest"
    elseif dx < 0 and dy < 0 then
        return "Southwest"
    else
        return "None" -- No movement or invalid input
    end
end

-- Function to print the path directions on a single line
local function printPathDirectionsOnSingleLine(path)
    if #path < 2 then
        print("Path is too short to determine directions.")
        return
    end

    local directions = {}
    for index = 1, #path - 1 do
        local currentNode = path[index]
        local nextNode = path[index + 1]
        table.insert(directions, getDirection(currentNode, nextNode))
    end

    print("Path Directions: " .. table.concat(directions, ", "))
end



function PathfindingManager:luastarInit(gridCells, adjacentFreeCells, tree, positionToRoomId)
    -- Define colors for different types of turns
    local pathColor = Color3.new(0.321568, 0.549019, 0.972549)  -- White for regular path points
    

    -- Function to check if a position is open
    local function positionIsOpenFunc(x, y)
        if x < 1 or y < 1 or x > #gridCells or y > #gridCells[1] then
            return false
        end
        return not gridCells[x][y].Taken
    end


    local paths = {}


    for i, edge in ipairs(tree) do
       
        local startKey = string.format("%d,%d", edge[1], edge[2])
        local endKey = string.format("%d,%d", edge[3], edge[4])

        local startRoomData = positionToRoomId[startKey]
        local endRoomData = positionToRoomId[endKey]

        if not startRoomData or not endRoomData then
            print("Edge " .. i .. ": Invalid room data.")
            continue
        end

        local startCells = adjacentFreeCells[startRoomData.index].cells
        local endCells = adjacentFreeCells[endRoomData.index].cells


        if #startCells > 0 and #endCells > 0 then
            local startCell, goalCell = findClosestCells(startCells, endCells)

            if startCell and goalCell then
                local start = {x = startCell.x, y = startCell.y}
                local goal = {x = goalCell.x, y = goalCell.y}

                local path = luastar:find(#gridCells, #gridCells[1], start, goal, positionIsOpenFunc, true, true)

            
                if path then
                    printPathDirectionsOnSingleLine(path)  -- Call the function to print directions

                    for index = 1, #path do
                        local prevNode = path[index - 1] or path[index]
                        local currentNode = path[index]
                        local nextNode = path[index + 1] or currentNode  -- Use current node as nextNode if none

                        gridCells = SetPathCorridorProperties(prevNode, currentNode, nextNode, gridCells)
                        UpdatedGridCells = gridCells
                    end
                  
                  
                    for index = 1, #path - 1 do
                        local prevNode = path[index - 1] or path[1]
                        local currentNode = path[index]
                        local nextNode = path[index + 1]

                       -- local currentDirection = getDirection(currentNode, nextNode)
                        local gridCells= SetPathCornerProperties(prevNode, currentNode, nextNode, gridCells)
                        local partColor = pathColor  -- Default to path color
                        UpdatedGridCells = gridCells
                        

                        local part, gridCells = Debug_CreatePathPart(currentNode.x, currentNode.y, UpdatedGridCells, partColor)
                        UpdatedGridCells = gridCells

                        table.insert(paths, part)



                    end
                  

                    -- Handle the last node
                    local lastNode = path[#path]
                    local part, gridCells = Debug_CreatePathPart(lastNode.x, lastNode.y, UpdatedGridCells, pathColor)
                    UpdatedGridCells = gridCells

                    table.insert(paths, part)
                else
                    print("No path available from (" .. start.x .. ", " .. start.y .. ") to (" .. goal.x .. ", " .. goal.y .. ")")
                end
            else
                print("No available cells between rooms at edge " .. i)
            end
        else
            print("Insufficient free cells to establish path for rooms at edge " .. i)
        end
    end

    return paths, UpdatedGridCells
end






-- Additional helper functions need to be defined such as `createPathPart` and `createCornerPart`.



return PathfindingManager