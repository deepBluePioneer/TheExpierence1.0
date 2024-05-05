local PathfindingManager = {}
local luastar =  require(script.Parent.astar)

local function createWalls_Corridor(part, pathDirection)
    local wallWidth = 1
    local wallHeight = 12
    local wallLength = 12
    local walls = {}
    local offsets = {
        horizontal = {Vector3.new(0, 0, wallWidth/2 + part.Size.Z/2), Vector3.new(0, 0, -wallWidth/2 - part.Size.Z/2)},
        vertical = {Vector3.new(wallWidth/2 + part.Size.X/2, 0, 0), Vector3.new(-wallWidth/2 - part.Size.X/2, 0, 0)}
    }

    for i, offset in ipairs(offsets[pathDirection]) do
        local wall = Instance.new("Part")
        wall.Size = Vector3.new(pathDirection == "vertical" and wallWidth or wallLength, wallHeight, pathDirection == "vertical" and wallLength or wallWidth)
        wall.Position = part.Position + offset
        wall.Anchored = true
        wall.CanCollide = false
        wall.Color = Color3.new(1, 1, 1) -- Grey walls
        wall.Material = Enum.Material.WoodPlanks
        wall.Parent = workspace
        table.insert(walls, wall)
    end

    return walls
end




local function createPathPart(x, y, gridCells, color)
    
    --The transparent part
    local cell = gridCells[x][y]
    local part = Instance.new("Part")
    part.Size = cell.Size
    part.Position = cell.CFrame.Position + Vector3.new(0, part.Size.Y / 2, 0)
    part.Anchored = true
    part.CanCollide = false
    part.Transparency = 0
    part.Color = color
    part.Material = Enum.Material.Plastic
    part.Parent = workspace
    gridCells[x][y].Taken = true

    return part
end
    
local function createSolidPathPart(path, gridCells, color)
    if #path == 0 then return nil end  -- If there's no path, do nothing

    local scaleMultiplier = 1.05
    -- Determine the bounds of the path
    local minX, maxX, minY, maxY = math.huge, -math.huge, math.huge, -math.huge
    for _, node in ipairs(path) do
        minX = math.min(minX, node.x)
        maxX = math.max(maxX, node.x)
        minY = math.min(minY, node.y)
        maxY = math.max(maxY, node.y)
    end

    -- Calculate the size and position of the path part
    local width = (maxX - minX + 1) * gridCells[1][1].Size.X *scaleMultiplier
    local height = (maxY - minY + 1) * gridCells[1][1].Size.Z *scaleMultiplier
    local startPosition = gridCells[minX][minY].CFrame.Position
    local endPosition = gridCells[maxX][maxY].CFrame.Position
    local centerX = (startPosition.X + endPosition.X) / 2
    local centerY = (startPosition.Y + endPosition.Y) / 2
    local centerZ = (startPosition.Z + endPosition.Z) / 2

    -- Create the part
    local pathPart = Instance.new("Part")
    pathPart.Size = Vector3.new(width, gridCells[1][1].Size.Y, height)
    pathPart.Position = Vector3.new(centerX, centerY + gridCells[1][1].Size.Y / 2, centerZ)
    pathPart.Anchored = true
    pathPart.CanCollide = false
    pathPart.Transparency = 0
    pathPart.Color = color
    pathPart.Material = Enum.Material.Plastic
    pathPart.Parent = workspace

    -- Mark grid cells as taken
    for x = minX, maxX do
        for y = minY, maxY do
            gridCells[x][y].Taken = true
        end
    end

    return pathPart
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




function PathfindingManager:luastarInit(gridCells, adjacentFreeCells, tree, positionToRoomId)
    -- Define colors for different types of turns
    local pathColor = Color3.new(1, 1, 1)  -- White for regular path points
    local upToRightColor = Color3.new(1, 0, 0)  -- Red
    local rightToDownColor = Color3.new(0, 1, 0)  -- Green
    local downToLeftColor = Color3.new(0, 0, 1)  -- Blue
    local leftToUpColor = Color3.new(1, 1, 0)  -- Yellow
    local upToLeftColor = Color3.new(1, 0, 1)  -- Magenta
    local leftToDownColor = Color3.new(0.5, 0.5, 0)  -- Olive
    local downToRightColor = Color3.new(0.5, 0, 0.5)  -- Purple
    local rightToUpColor = Color3.new(0, 0.5, 0.5)  -- Teal

    -- Helper function to determine direction
    local function getDirection(node1, node2)
        if node1.x == node2.x then
            return "vertical"
        elseif node1.y == node2.y then
            return "horizontal"
        else
            return "diagonal"  -- Consider handling diagonals if your grid allows
        end
    end

    -- Function to check if a position is open
    local function positionIsOpenFunc(x, y)
        if x < 1 or y < 1 or x > #gridCells or y > #gridCells[1] then
            return false
        end
        return not gridCells[x][y].Taken
    end


    -- Determine corner type based on adjacent cells
    local function getCornerType(prevNode, currentNode, nextNode)
        local dx1 = currentNode.x - prevNode.x
        local dy1 = currentNode.y - prevNode.y
        local dx2 = nextNode.x - currentNode.x
        local dy2 = nextNode.y - currentNode.y

        if dy1 == 0 and dx2 == 0 then
            if dx1 > 0 and dy2 > 0 then
                return rightToDownColor
            elseif dx1 > 0 and dy2 < 0 then
                return rightToUpColor
            elseif dx1 < 0 and dy2 > 0 then
                return leftToDownColor
            elseif dx1 < 0 and dy2 < 0 then
                return leftToUpColor
            end
        elseif dx1 == 0 and dy2 == 0 then
            if dy1 > 0 and dx2 > 0 then
                return downToRightColor
            elseif dy1 > 0 and dx2 < 0 then
                return downToLeftColor
            elseif dy1 < 0 and dx2 > 0 then
                return upToRightColor
            elseif dy1 < 0 and dx2 < 0 then
                return upToLeftColor
            end
        end
        return nil  -- Default to no color if no specific corner detected
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

        local PerimeterTileModelTable = startRoomData.room.Parent.PerimeterTiles:GetChildren()
        local WallModelString = "WallModel"


        if #startCells > 0 and #endCells > 0 then
            local startCell, goalCell = findClosestCells(startCells, endCells)

          --  warn(startCell)

            if startCell and goalCell then
                local start = {x = startCell.x, y = startCell.y}
                local goal = {x = goalCell.x, y = goalCell.y}

                local path = luastar:find(#gridCells, #gridCells[1], start, goal, positionIsOpenFunc, true, true)

            
                if path then
                    for index = 1, #path - 1 do
                        local prevNode = path[index - 1] or path[1]
                        local currentNode = path[index]
                        local nextNode = path[index + 1]

                        local currentDirection = getDirection(currentNode, nextNode)
                        local cornerType = getCornerType(prevNode, currentNode, nextNode)
                        local partColor = pathColor  -- Default to path color

                        if cornerType then
                            partColor = cornerType  -- Use specific corner color
                        end

                        local part = createPathPart(currentNode.x, currentNode.y, gridCells, partColor)
                        table.insert(paths, part)

                     
                        

                    end

                    -- Handle the last node
                    local lastNode = path[#path]
                    local part = createPathPart(lastNode.x, lastNode.y, gridCells, pathColor)
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

    return paths, gridCells
end






-- Additional helper functions need to be defined such as `createPathPart` and `createCornerPart`.



return PathfindingManager