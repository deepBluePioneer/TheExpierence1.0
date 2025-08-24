-- MainHelpFunc.lua

local Tile = require(script.Parent.Tile)

local MainHelpFunc = {}

-- Returns a list of adjacent grid positions to (row, col)
function MainHelpFunc.getAdjacentPos(row, col)
	return {
		{ row - 1, col },
		{ row + 1, col },
		{ row, col - 1 },
		{ row, col + 1 }
	}
end
-- Prim's algorithm for MST between rooms
function MainHelpFunc.prims(roomList)
	assert(#roomList > 0, "Room list must contain at least one room")

	local visited = {}
	local root = roomList[1]
	local lastLeaf = root
	table.insert(visited, root)

	while #visited < #roomList do
		local shortestDist = math.huge
		local closestA, closestB = nil, nil

		for _, roomA in ipairs(visited) do
			for _, roomB in ipairs(roomList) do
				if not table.find(visited, roomB) then
					local dist = roomA:distanceTo(roomB)
					if dist < shortestDist then
						shortestDist = dist
						closestA = roomA
						closestB = roomB
					end
				end
			end
		end

		if closestA and closestB then
			closestA:addNeighbour(closestB)
			closestB:addNeighbour(closestA)
			table.insert(visited, closestB)
			lastLeaf = closestB
		end
	end

	return root, lastLeaf
end


-- Places player near root room center
function MainHelpFunc.initPlayer(level)
	local c = level:getRoot().center
	local adj = MainHelpFunc.getAdjacentPos(c[1], c[2])
	local i = 1
	local endr, endc

	repeat
		endr, endc = adj[i][1], adj[i][2]
		i += 1
	until level:getTile(endr, endc).class == Tile.FLOOR

	level:getTile(endr, endc).class = Tile.PLAYER
end

-- Places boss near end room center
function MainHelpFunc.initBoss(level)
	local c = level:getEnd().center
	local adj = MainHelpFunc.getAdjacentPos(c[1], c[2])
	local i = 1
	local endr, endc

	repeat
		endr, endc = adj[i][1], adj[i][2]
		i += 1
	until level:getTile(endr, endc).class == Tile.FLOOR

	level:getTile(endr, endc).class = Tile.BOSS
end
-- Calculates Euclidean distance between 2 points
function MainHelpFunc.getDist(start, goal)
	return math.sqrt(
		math.pow(math.abs(goal[1] - start[1]), 2) +
		math.pow(math.abs(goal[2] - start[2]), 2)
	)
end

-- Finds the next tile toward the goal, avoiding diagonals
function MainHelpFunc.findNext(start, goal)
	if start[1] == goal[1] and start[2] == goal[2] then
		return goal
	end

	local row, col = start[1], start[2]
	local adj = MainHelpFunc.getAdjacentPos(row, col)
	local dist = MainHelpFunc.getDist(start, goal)

	local nextPos = start -- fallback (prevent infinite loop)

	for i = 1, #adj do
		local adjT = adj[i]
		if MainHelpFunc.getDist(adjT, goal) < dist and i % 2 == 0 then -- avoid diagonals
			nextPos = adjT
			dist = MainHelpFunc.getDist(nextPos, goal)
		end
	end

	-- Prevent infinite loop if no better position was found
	if nextPos[1] == start[1] and nextPos[2] == start[2] then
		local fallback = adj[2] or adj[1] -- just return anything adjacent
		return fallback
	end

	return nextPos
end


function MainHelpFunc.withinBounds(r, c, height, width)
	return r > 0 and r < height and c > 0 and c < width
end

function MainHelpFunc.getRandNeighbour(row, col, notDiag)
	if notDiag then
		local d = (math.random() > 0.5) and 1 or -1
		if math.random() > 0.5 then
			return row + d, col
		else
			return row, col + d
		end
	else
		local dir = { math.random(-1, 1), math.random(-1, 1) }
		return row + dir[1], col + dir[2]
	end
end


return MainHelpFunc
