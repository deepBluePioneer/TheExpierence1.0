local MSTManager = {}
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CustomPackages = ReplicatedStorage.CustomPackages
local Packages = ReplicatedStorage.Packages
local Gizmo = require(Packages.imgizmo)

 function MSTManager:DrawMST(tree)
    for i = 1, #tree do

        -- Extract coordinates from the tree structure
        local x1, y1, x2, y2 = tree[i][1], tree[i][2], tree[i][3], tree[i][4]
        -- Optionally draw a line between them if needed
        Gizmo.PushProperty("Color3", Color3.new(1, 1, 1)) -- Set color for drawing lines (optional)
        Gizmo.Ray:Create(Vector3.new(x1, 12, y1), Vector3.new(x2, 12, y2))
    end
end

function MSTManager:printTreeWithRoomIds(tree, positionToRoomId)
    for i, edge in ipairs(tree) do
        -- Generate keys for start and end positions
        local startKey = string.format("%d,%d", edge[1], edge[2])
        local endKey = string.format("%d,%d", edge[3], edge[4])

        -- Attempt to retrieve room data from the position map
        local startRoomData = positionToRoomId[startKey]
        local endRoomData = positionToRoomId[endKey]

        -- Check if room data was successfully retrieved
        if startRoomData and endRoomData then
            -- Extract additional room details, such as room name or other attributes
            local startRoomDetails = startRoomData.room.Name or "Unnamed Room"
            local endRoomDetails = endRoomData.room.Name or "Unnamed Room"

           print(string.format("Edge %d: Start Room ID %d (%s) -> End Room ID %d (%s)",
               i, startRoomData.index, startRoomDetails, endRoomData.index, endRoomDetails))
        else
            -- Detailed error reporting if keys are not found
            print(string.format("Edge %d: Missing room information for edges. Start Key: %s, End Key: %s",
                i, startKey, endKey))
            print("Available Keys in Mapping:")
            for k, v in pairs(positionToRoomId) do
                print(k, "-> Room ID", v.index, "Room Details:", v.room.Name or "Unnamed Room")
            end
        end
    end
end

return MSTManager