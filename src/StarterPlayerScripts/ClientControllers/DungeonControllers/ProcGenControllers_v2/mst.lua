local mst = {}

-- Helper function to check if a point exists in a list of vertices
local function doesExist(vertices, point)
    for _, v in ipairs(vertices) do
        if v == point then
            return true
        end
    end
    return false
end

-- Distance calculation using Vector2 (for 2D space)
local function dist(x1, y1, x2, y2)
    return (Vector2.new(x1, y1) - Vector2.new(x2, y2)).magnitude
end

-- Function to check if an edge is the same as an existing edge
local function same(x1, y1, x2, y2, edges)
    local p1, p2 = Vector2.new(x1, y1), Vector2.new(x2, y2)
    for _, edge in ipairs(edges) do
        local e1, e2 = Vector2.new(edge[1], edge[2]), Vector2.new(edge[3], edge[4])
        if (p1 == e1 and p2 == e2) or (p1 == e2 and p2 == e1) then
            return true
        end
    end
    return false
end

-- MST calculation function
function mst.tree(points, edges)
    local vertices = {points[1]}
    local tree = {}
    while #vertices ~= #points do
        local ln = 10000
        local temp1 = nil
        local temp2 = nil
        for i, vertex in ipairs(vertices) do
            for _, point in ipairs(points) do
                if not doesExist(vertices, point) then
                    local distance = dist(point[1], point[2], vertex[1], vertex[2])
                    if distance < ln and same(point[1], point[2], vertex[1], vertex[2], edges) then
                        ln = distance
                        temp1 = point
                        temp2 = vertex
                    end
                end
            end
        end
        if temp1 and temp2 then
            table.insert(vertices, temp1)
            table.insert(tree, {temp1[1], temp1[2], temp2[1], temp2[2]})
        end
    end
    return tree
end

return mst
