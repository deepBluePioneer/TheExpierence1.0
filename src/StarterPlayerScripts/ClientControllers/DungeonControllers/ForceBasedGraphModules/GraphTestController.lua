local Players = game:GetService("Players")
local player = game:GetService("Players").LocalPlayer 
local RunService = game:GetService("RunService")


local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CustomPackages = ReplicatedStorage.CustomPackages
local Packages = ReplicatedStorage.Packages
local GraphLibrary = require(CustomPackages.GraphModules.Graphoon.Graph)
local g = require(CustomPackages.GraphModules.graph).create(8, true); -- directed weighted graph
local rope = require(CustomPackages.GraphModules.RopeSwing.Rope)

local dijkstra = require(CustomPackages.GraphModules.Dijkstra)

local Knit = require(Packages.Knit)

local GraphTestController = Knit.CreateController { Name = "GraphTestController" }
local CanvasDraw = require(CustomPackages.GraphModules.CanvasDraw)

function GraphTestController:KnitStart()
    -- Add controller startup logic here
end

local function initGraph()
    local playergui = player:FindFirstChild("PlayerGui") 
    local ScreenGui = playergui:WaitForChild("_ScreenGui")

    --UI Elements
    local btn_node = ReplicatedStorage.btn_node
    local txt_weight = ReplicatedStorage.txt_weight

    local graph = GraphLibrary.new()
    local width = 1920
    local height = 1080
    local x = .5
    local y = .5

    local XPos = width * x
    local YPos = height * y


    -- Node initialization with positions adjusted to minimize edge crossings
   --[[ graph:addNode("0", "0", 1920 * 0.3, 1080 * 0.5, false)
    graph:addNode("1", "1", 1920 * 0.4, 1080 * 0.4, false)
    graph:addNode("2", "2", 1920 * 0.4, 1080 * 0.6, false)
    graph:addNode("3", "3", 1920 * 0.5, 1080 * 0.3, false)
    graph:addNode("4", "4", 1920 * 0.5, 1080 * 0.7, false)
    graph:addNode("5", "5", 1920 * 0.6, 1080 * 0.4, false)
    graph:addNode("6", "6", 1920 * 0.6, 1080 * 0.6, false)
    graph:addNode("7", "7", 1920 * 0.7, 1080 * 0.5, false)

    --
    -- Edge connections designed to be planar
    graph:connectIDs("0", "1")
    graph:connectIDs("0", "2")
    graph:connectIDs("1", "3")
    graph:connectIDs("1", "5")
    graph:connectIDs("2", "4")
    graph:connectIDs("2", "6")
    graph:connectIDs("3", "5")
    graph:connectIDs("4", "6")
    graph:connectIDs("5", "7")
    graph:connectIDs("6", "7")

    -- Edge weights (optional randomization omitted for simplicity)
    g:addEdge(0, 1, 1)
    g:addEdge(0, 2, 2)
    g:addEdge(1, 3, 3)
    g:addEdge(1, 5, 4)
    g:addEdge(2, 4, 5)
    g:addEdge(2, 6, 6)
    g:addEdge(3, 5, 7)
    g:addEdge(4, 6, 8)
    g:addEdge(5, 7, 9)
    g:addEdge(6, 7, 10)--]]

    

   -- Assume `graph` is an object that we can call `addNode` and `addEdge` on
-- Function to generate random nodes
    function generateRandomNodes(count)
        local nodes = {}
        local width = 1920
        local height = 1080
        for i = 1, count do
            local x = math.random() * width * 0.3 + width * 0.3  -- Keep nodes somewhat centralized
            local y = math.random() * height * 0.3 + height * 0.3
            table.insert(nodes, {id = tostring(i - 1), x = x, y = y})
        end
        return nodes
    end

    -- Initialize a random number of nodes, e.g., between 5 and 15
    local nodeCount = math.random(5, 10)
    local nodes = generateRandomNodes(nodeCount)

    -- Add nodes to the graph
    for _, node in pairs(nodes) do
        graph:addNode(node.id, node.id, node.x, node.y, false)
    end

    -- Helper function to check if two line segments intersect
    function linesIntersect(p1, p2, p3, p4)
        local function ccw(A, B, C)
            return (C.y - A.y) * (B.x - A.x) > (B.y - A.y) * (C.x - A.x)
        end

        return ccw(p1, p3, p4) ~= ccw(p2, p3, p4) and ccw(p1, p2, p3) ~= ccw(p1, p2, p4)
    end

    -- Add edges while ensuring the graph remains planar
    local edges = {}
    function addPlanarEdge(node1, node2)
        local canAdd = true
        for _, edge in pairs(edges) do
            if linesIntersect(nodes[tonumber(edge.from) + 1], nodes[tonumber(edge.to) + 1], node1, node2) then
                canAdd = false
                break
            end
        end

        if canAdd then
            edges[#edges + 1] = {from = node1.id, to = node2.id}
            graph:connectIDs(node1.id, node2.id)
            g:addEdge(tonumber(node1.id), tonumber(node2.id), math.random(1, 10))
        end
    end

    -- Randomly try to add edges, with a lower connection probability for more nodes
    math.randomseed(os.time())
    for i = 1, #nodes do
        for j = i + 1, #nodes do
            if math.random() > 0.1 then  -- Adjust probability based on node density
                addPlanarEdge(nodes[i], nodes[j])
            end
        end
    end




    local btn_nodeCloneForceTable = {}
    local ropes = {}
    local txt_weights = {}
    
    --local Canvas = CanvasDraw.new(ScreenGui.BG, Vector2.new(150, 100))


    graph:draw( 

	function( node )

		local x, y = node:getPosition()


		local btn_nodeCloneForce = btn_node:Clone()
		btn_nodeCloneForce.Position = UDim2.fromOffset(x, y)
		btn_nodeCloneForce.Parent = ScreenGui
		btn_nodeCloneForce.Name = node.getID()
		btn_nodeCloneForce.BackgroundColor3 = Color3.new(1, 0.858824, 0.0666667)
		btn_nodeCloneForce.ZIndex = 2
		btn_nodeCloneForce.Size = UDim2.new(0, 45, 0, 45)
		btn_nodeCloneForce.AnchorPoint = Vector2.new(.5, .5)
		btn_nodeCloneForce.Text = node.getID()
		table.insert(btn_nodeCloneForceTable, btn_nodeCloneForce)
	
		
	end,


	function( edge )
		
		
		local ox, oy = edge.origin:getPosition()
		
		local tx, ty = edge.target:getPosition()
		local point1 = Vector2.new(ox,oy)
		local point2 = Vector2.new(tx,ty)
		
		local newrope = rope(ox, oy, tx, ty, ScreenGui.BG, 5)
		newrope.Name = tostring(edge.id)
		table.insert(ropes, newrope)
		
		local txt_weightClone = txt_weight:Clone()
		txt_weightClone.Position = UDim2.fromOffset(x, y)
		txt_weightClone.Parent = ScreenGui
		txt_weightClone.Name = tostring(edge.id)
		txt_weightClone.Text = "w"
		table.insert(txt_weights, txt_weightClone)

	end

)


    local function UpdateRopeRotationAndScale(l, originx, originy, endpointx, endpointy)
        local origin = {
            x = originx,
            y = originy
        }

        local endpoint = {
            x = endpointx,
            y = endpointy
        }

        local adj = (Vector2.new(endpoint.x, origin.y) - Vector2.new(origin.x, origin.y)).magnitude
        local opp = (Vector2.new(endpoint.x, origin.y) - Vector2.new(endpoint.x, endpoint.y)).magnitude
        local hyp = math.sqrt(adj^2 + opp^2)

        local theta = math.deg(math.acos(adj/hyp))

        local line = l

        local pos = line.AbsolutePosition
        local size = line.AbsoluteSize

        if (endpoint.x == origin.x and endpoint.y > origin.y) or (endpoint.x == origin.x and endpoint.y <= origin.y) then
            theta = 90 -- y axis
        elseif (endpoint.x < origin.x and endpoint.y == origin.y) or (endpoint.x >= origin.x and endpoint.y == origin.y) then
            theta = 0 -- x axis
        elseif endpoint.x >= origin.x and endpoint.y <= origin.y then
            theta = -theta-- quad 1
        elseif endpoint.x <= origin.x and endpoint.y <= origin.y then
            theta = theta + 180 -- quad 2
        elseif endpoint.x <= origin.x and endpoint.y >= origin.y then
            theta = -theta -- quad 3		
        elseif endpoint.x >= origin.x and endpoint.y >= origin.x then
            theta = math.abs(theta) -- quad 4
        end

        local mid = Vector2.new((origin.x + endpoint.x)/2, (origin.y + endpoint.y)/2)

        line.Position = UDim2.fromOffset(mid.x, mid.y)
        line.Rotation = theta
        line.Size = UDim2.new(0, hyp, 0, 1)

    end

    local function UpdateTextlabelRotation(l, originx, originy, endpointx, endpointy)
        local origin = {
            x = originx,
            y = originy
        }

        local endpoint = {
            x = endpointx,
            y = endpointy
        }

        local adj = (Vector2.new(endpoint.x, origin.y) - Vector2.new(origin.x, origin.y)).magnitude
        local opp = (Vector2.new(endpoint.x, origin.y) - Vector2.new(endpoint.x, endpoint.y)).magnitude
        local hyp = math.sqrt(adj^2 + opp^2)

        local theta = math.deg(math.acos(adj/hyp))

        local line = l

        local pos = line.AbsolutePosition
        local size = line.AbsoluteSize

        if (endpoint.x == origin.x and endpoint.y > origin.y) or (endpoint.x == origin.x and endpoint.y <= origin.y) then
            theta = 90 -- y axis
        elseif (endpoint.x < origin.x and endpoint.y == origin.y) or (endpoint.x >= origin.x and endpoint.y == origin.y) then
            theta = 0 -- x axis
        elseif endpoint.x >= origin.x and endpoint.y <= origin.y then
            theta = -theta-- quad 1
        elseif endpoint.x <= origin.x and endpoint.y <= origin.y then
            theta = theta + 180 -- quad 2
        elseif endpoint.x <= origin.x and endpoint.y >= origin.y then
            theta = -theta -- quad 3		
        elseif endpoint.x >= origin.x and endpoint.y >= origin.x then
            theta = math.abs(theta) -- quad 4
        end

        local mid = Vector2.new((origin.x + endpoint.x)/2, (origin.y + endpoint.y)/2)

        line.Position = UDim2.fromOffset(mid.x, mid.y)
        line.Rotation = theta
        line.Size = UDim2.new(0, hyp, 0, 1)

    end

    local function onStep(_currentTime, deltaTime)
        
        
        graph:update( deltaTime,
            
            function( node )

                local x, y = node:getPosition()
                
                for i, button in ipairs(btn_nodeCloneForceTable) do
                    
                    if button.Name == node:getID() then
                        
                        --local NodeUi = ScreenGui:WaitForChild(node:getID())
                        local point1 = Vector2.new(x,y)

                        if node.isAnchor() == false then
                            --setAbsolutePosition(button ,point1)
                            button.Position =  UDim2.new(0, x, 0, y)


                        end
                        
                    end
                    
                end
                
                
            end,
            function( edge )
                local ox, oy = edge.origin:getPosition()
                local tx, ty = edge.target:getPosition()

                local StartPoint = Vector2.new(ox,oy)
                local EndPoint = Vector2.new(tx,ty)
            
                for i,rope in ipairs(ropes) do
                    
                    --print(rope.Name)
                    if tostring(edge.id) == rope.Name then
                        UpdateRopeRotationAndScale(rope, ox, oy, tx, ty)					
                    end
                
            
                end
                for i,textLabel in ipairs(txt_weights) do

                    --print(rope.Name)
                    if tostring(edge.id) == textLabel.Name then
                        UpdateTextlabelRotation(textLabel, ox, oy, tx, ty)					
                    end


                end
                
            end
            
        )
        
        

    end

    RunService.Stepped:Connect(onStep)

    local source = 0
    dijkstra:run(g, source) -- 0 is the id of the source node in the path search
    for k = 0,g:vertexCount()-1 do
        local v = g:vertexAt(k)
        if v ~= source and dijkstra:hasPathTo(v) then
            print('path from 0 to ' .. v .. ' ( cost: '  .. dijkstra:getPathLength(v) .. ' )')
            local path = dijkstra:getPathTo(v)
            for i = 0,path:size()-1 do
                print('# from ' .. path:get(i):from() .. ' to ' .. path:get(i):to() .. ' ( distance: ' .. path:get(i).weight .. ' )')
            end
        end
    end
        

end


function GraphTestController:KnitInit()

end

return GraphTestController