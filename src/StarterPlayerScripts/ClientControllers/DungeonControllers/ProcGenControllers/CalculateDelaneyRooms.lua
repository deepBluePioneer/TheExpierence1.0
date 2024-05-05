-- DelaunayTriangulationModule.lua

-- Assuming Delaunay and ProcGen_Controller are accessible or require-able if they are custom modules
local Delaunay = require(script.Parent.delaunay)  -- Adjust the path as needed
local Point  = Delaunay.Point 

local CalculateDelaneyRooms = {}


-- Function to retrieve the coordinates of all points in all triangles
function CalculateDelaneyRooms:getTrianglePoints(triangles)
    local trianglePoints = {}
    for i, triangle in ipairs(triangles) do
        -- Each entry in trianglePoints will be a table with the points of one triangle
        local points = {
            {x = triangle.p1.x, y = triangle.p1.y},
            {x = triangle.p2.x, y = triangle.p2.y},
            {x = triangle.p3.x, y = triangle.p3.y}
        }
        table.insert(trianglePoints, points)
    end
    return trianglePoints
end


function CalculateDelaneyRooms:triangulateRooms(createdRooms)
    local points = {}

    -- Collecting points from room positions
    for i, room in ipairs(createdRooms) do
        points[i] = Point(room.Position.X, room.Position.Z)
    end

    -- Triangulate points using Delaunay algorithm
    local triangles = Delaunay.triangulate(unpack(points))
    local extractedPoints = CalculateDelaneyRooms:getTrianglePoints(triangles)

    -- Store the points of each triangle
    local trianglesData = {}

    for i, triangle in ipairs(extractedPoints) do
        local pointsTable = {}
        for j, point in ipairs(triangle) do
            table.insert(pointsTable, {x = point.x, y = point.y})
        end
        trianglesData[i] = pointsTable
    end

    -- Create rays for each edge of each triangle
    for i, triangle in ipairs(trianglesData) do
        for j = 1, #triangle do
            local nextIndex = (j % #triangle) + 1
            local startPoint = triangle[j]
            local endPoint = triangle[nextIndex]

            -- Creating Vector3 objects for each point
            local startVector = Vector3.new(startPoint.x, 12, startPoint.y)
            local endVector = Vector3.new(endPoint.x, 12, endPoint.y)

            -- Optional: Gizmo usage to visualize the rays (if Gizmo is a part of the environment)
            -- Gizmo.PushProperty("Color3", Color3.new(0.631372, 0.988235, 0.639215))
            -- Gizmo.Ray:Create(startVector, endVector)
        end
    end

    return trianglesData
end

function CalculateDelaneyRooms:createPointsAndEdges(trianglesData)
    local points = {}
    local edges = {}
    local pointIndex = {}  -- Maps a point to its index

    -- Assign an index to each unique point
    local index = 1
    for _, triangle in ipairs(trianglesData) do
        for _, point in ipairs(triangle) do
            local key = tostring(point.x) .. "," .. tostring(point.y)
            if not pointIndex[key] then
                pointIndex[key] = index
                points[index] = {point.x, point.y}
                index = index + 1
            end
        end
    end

    -- Create edges by referring to point indices, adjusting the format
    for _, triangle in ipairs(trianglesData) do
        for j = 1, #triangle do
            local nextIndex = (j % #triangle) + 1
            local p1 = triangle[j]
            local p2 = triangle[nextIndex]
            local idx1 = pointIndex[tostring(p1.x) .. "," .. tostring(p1.y)]
            local idx2 = pointIndex[tostring(p2.x) .. "," .. tostring(p2.y)]
            table.insert(edges, {points[idx1][1], points[idx1][2], points[idx2][1], points[idx2][2]})
        end
    end

    return points, edges
end

return CalculateDelaneyRooms
