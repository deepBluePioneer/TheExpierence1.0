local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local Knit = require(Packages.Knit)

local TreeService = Knit.CreateService {
	Name = "TreeService",
	Client = {},
	trees = {},
}

-- === CONFIG ===
local TREE_CONFIG = {
	-- Spawning
	TreeCount = 200,             -- Number of trees to spawn
	MinSpacing = 18,             -- Minimum distance between trees
	EdgePadding = 12,            -- Keep trees away from baseplate edges
	
	-- Trunk variations (taller!)
	TrunkHeightMin = 20,
	TrunkHeightMax = 40,
	TrunkWidthMin = 2.5,
	TrunkWidthMax = 5,
	TrunkColor = Color3.fromRGB(101, 67, 33),
	TrunkColorVariation = 25,
	TrunkMaterial = Enum.Material.Wood,
	
	-- Leaves/Canopy variations (larger!)
	CanopyWidthMin = 18,
	CanopyWidthMax = 30,
	CanopyHeightMin = 12,
	CanopyHeightMax = 22,
	CanopyColors = {
		Color3.fromRGB(34, 85, 34),   -- Dark green
		Color3.fromRGB(50, 120, 50),  -- Medium green
		Color3.fromRGB(60, 100, 40),  -- Olive green
		Color3.fromRGB(30, 70, 30),   -- Forest green
		Color3.fromRGB(45, 90, 35),   -- Deep forest
	},
	CanopyMaterial = Enum.Material.Grass,
	
	-- L-System settings
	LSystemIterations = 3,       -- How many times to apply rules
	BranchAngle = 25,            -- Angle for branching (degrees)
	BranchLengthRatio = 0.7,     -- Each branch is 70% of parent
	BranchWidthRatio = 0.6,      -- Each branch is 60% width of parent
	MinBranchLength = 2,         -- Stop branching below this
	
	-- Tree types (all L-system variants)
	TreeTypes = {"LSystem", "LSystemPine", "LSystemOak", "LSystemWillow", "LSystemAncient"},
}

-- === L-SYSTEM DEFINITIONS ===
local LSYSTEM_RULES = {
	-- Standard branching tree (more winding with ~)
	LSystem = {
		axiom = "FFFA",
		rules = {
			A = "~F~F[+~FA][-~FA][>~FA][<~FA]",  -- ~ = random wobble
			F = "F~F",  -- Trunk winds
		},
		angle = 22,
		iterations = 3,
		wobble = 15,  -- Degrees of random wobble
	},
	
	-- Pine/Conifer style (tall with many small branches)
	LSystemPine = {
		axiom = "FFFFA",
		rules = {
			A = "~F[+~A][>+~A][<+~A][-~A]~FA",  -- Many branches at each level
			F = "~F",
		},
		angle = 30,
		iterations = 4,
		wobble = 10,
	},
	
	-- Oak/Spreading style (very branchy and winding)
	LSystemOak = {
		axiom = "FFA",
		rules = {
			A = "~F~F[++~A][--~A][>~A][<~A]~F[+~A][-~A]A",  -- Lots of branches
			F = "~F~",  -- Extra winding trunk
		},
		angle = 25,
		iterations = 3,
		wobble = 20,
	},
	
	-- Willow style (drooping branches)
	LSystemWillow = {
		axiom = "FFFFA",
		rules = {
			A = "~F~F[--~A][--~>A][--~<A]~F[+~A]A",  -- Branches droop down
			F = "~F",
		},
		angle = 35,
		iterations = 4,
		wobble = 12,
	},
	
	-- Ancient/Gnarled tree
	LSystemAncient = {
		axiom = "FFA",
		rules = {
			A = "~~F~~[+++~A][---~A][>>~A][<<~A]~~F[+~A][-~A][>~A][<~A]",
			F = "~~F~~",  -- Very winding
		},
		angle = 28,
		iterations = 3,
		wobble = 25,  -- Very wobbly
	},
}

local FOLDER_NAME = "ProceduralTrees"

-- === HELPERS ===

local function getTreeFolder()
	local folder = Workspace:FindFirstChild(FOLDER_NAME)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = FOLDER_NAME
		folder.Parent = Workspace
	end
	return folder
end

local function clearTrees()
	local folder = Workspace:FindFirstChild(FOLDER_NAME)
	if folder then
		folder:ClearAllChildren()
	end
end

local function randomRange(min, max)
	return min + math.random() * (max - min)
end

local function varyColor(baseColor, variation)
	local r = math.clamp(baseColor.R * 255 + (math.random() - 0.5) * variation * 2, 0, 255)
	local g = math.clamp(baseColor.G * 255 + (math.random() - 0.5) * variation * 2, 0, 255)
	local b = math.clamp(baseColor.B * 255 + (math.random() - 0.5) * variation * 2, 0, 255)
	return Color3.fromRGB(r, g, b)
end

local function getBaseplateInfo()
	local baseplate = Workspace:FindFirstChild("Baseplate")
	if baseplate and baseplate:IsA("BasePart") then
		return {
			position = baseplate.Position,
			size = baseplate.Size,
			topY = baseplate.Position.Y + baseplate.Size.Y / 2,
		}
	end
	return nil
end

-- === L-SYSTEM PROCESSING ===

local function applyLSystemRules(axiom, rules, iterations)
	local current = axiom
	
	for i = 1, iterations do
		local next = ""
		for char in current:gmatch(".") do
			if rules[char] then
				next = next .. rules[char]
			else
				next = next .. char
			end
		end
		current = next
	end
	
	return current
end

-- === TREE CREATION ===

local function createBranch(startPos, endPos, width, color, material, folder)
	local branch = Instance.new("Part")
	branch.Name = "Branch"
	
	local direction = endPos - startPos
	local length = direction.Magnitude
	local midPoint = startPos + direction / 2
	
	branch.Size = Vector3.new(width, width, length)
	branch.CFrame = CFrame.lookAt(midPoint, endPos) * CFrame.Angles(math.rad(90), 0, 0)
	branch.CFrame = CFrame.lookAt(startPos, endPos) * CFrame.new(0, 0, -length/2)
	branch.Color = color
	branch.Material = material
	branch.Anchored = true
	branch.CanCollide = false
	branch.Parent = folder
	
	return branch
end

local function createLeafCluster(position, size, folder)
	local leaf = Instance.new("Part")
	leaf.Name = "Leaves"
	leaf.Shape = Enum.PartType.Ball
	leaf.Size = Vector3.new(size, size * 0.8, size)
	leaf.Position = position
	leaf.Color = TREE_CONFIG.CanopyColors[math.random(1, #TREE_CONFIG.CanopyColors)]
	leaf.Material = TREE_CONFIG.CanopyMaterial
	leaf.Anchored = true
	leaf.CanCollide = false
	leaf.Parent = folder
	return leaf
end

local function generateLSystemTree(position, treeType, folder)
	local treeModel = Instance.new("Model")
	treeModel.Name = "LSystemTree"
	treeModel.Parent = folder
	
	-- Get L-system rules
	local lsystem = LSYSTEM_RULES[treeType] or LSYSTEM_RULES.LSystem
	local instructions = applyLSystemRules(lsystem.axiom, lsystem.rules, lsystem.iterations)
	
	-- Tree parameters
	local trunkLength = randomRange(TREE_CONFIG.TrunkHeightMin, TREE_CONFIG.TrunkHeightMax)
	local trunkWidth = randomRange(TREE_CONFIG.TrunkWidthMin, TREE_CONFIG.TrunkWidthMax)
	local baseAngle = lsystem.angle + (math.random() - 0.5) * 10  -- Add some variation
	local wobbleAmount = lsystem.wobble or 15  -- Degrees of random wobble
	local trunkColor = varyColor(TREE_CONFIG.TrunkColor, TREE_CONFIG.TrunkColorVariation)
	
	-- Turtle state
	local state = {
		position = position,
		direction = CFrame.new(Vector3.zero, Vector3.yAxis),  -- Point up
		length = trunkLength / 4,  -- Segment length (smaller for more segments)
		width = trunkWidth,
	}
	
	-- Stack for branching
	local stateStack = {}
	
	-- Track branch endpoints for leaves
	local leafPositions = {}
	local firstPart = nil
	
	-- Process L-system instructions
	local i = 1
	while i <= #instructions do
		local char = instructions:sub(i, i)
		local nextChar = instructions:sub(i + 1, i + 1)
		
		-- Check for double symbols (++, --, >>, <<)
		local doubleSymbol = false
		if (char == "+" or char == "-" or char == ">" or char == "<") and nextChar == char then
			doubleSymbol = true
		end
		
		if char == "F" or char == "A" then
			if char == "F" then
				-- Move forward and create branch
				local endPos = state.position + state.direction.LookVector * state.length
				local branch = createBranch(
					state.position, 
					endPos, 
					state.width,
					trunkColor,
					TREE_CONFIG.TrunkMaterial,
					treeModel
				)
				
				if not firstPart then
					firstPart = branch
				end
				
				state.position = endPos
				
				-- Track endpoints for leaves (only smaller branches)
				if state.width < trunkWidth * 0.4 then
					table.insert(leafPositions, {pos = endPos, size = state.width * 5})
				end
			end
			-- 'A' is just a placeholder for rules, doesn't draw
			
		elseif char == "~" then
			-- Wobble: random rotation for winding effect
			local wobbleX = (math.random() - 0.5) * 2 * math.rad(wobbleAmount)
			local wobbleY = (math.random() - 0.5) * 2 * math.rad(wobbleAmount)
			local wobbleZ = (math.random() - 0.5) * math.rad(wobbleAmount * 0.5)
			state.direction = state.direction * CFrame.Angles(wobbleX, wobbleY, wobbleZ)
			
		elseif char == "+" then
			-- Pitch up (rotate around X)
			local angle = doubleSymbol and baseAngle * 1.5 or baseAngle
			state.direction = state.direction * CFrame.Angles(math.rad(angle), 0, 0)
			if doubleSymbol then i = i + 1 end
			
		elseif char == "-" then
			-- Pitch down
			local angle = doubleSymbol and baseAngle * 1.5 or baseAngle
			state.direction = state.direction * CFrame.Angles(math.rad(-angle), 0, 0)
			if doubleSymbol then i = i + 1 end
			
		elseif char == ">" then
			-- Yaw right (rotate around Y)
			local angle = doubleSymbol and baseAngle * 1.5 or baseAngle
			state.direction = state.direction * CFrame.Angles(0, math.rad(angle), 0)
			if doubleSymbol then i = i + 1 end
			
		elseif char == "<" then
			-- Yaw left
			local angle = doubleSymbol and baseAngle * 1.5 or baseAngle
			state.direction = state.direction * CFrame.Angles(0, math.rad(-angle), 0)
			if doubleSymbol then i = i + 1 end
			
		elseif char == "[" then
			-- Push state (start branch)
			table.insert(stateStack, {
				position = state.position,
				direction = state.direction,
				length = state.length,
				width = state.width,
			})
			-- Reduce size for sub-branch
			state.length = state.length * TREE_CONFIG.BranchLengthRatio
			state.width = math.max(state.width * TREE_CONFIG.BranchWidthRatio, 0.3)
			-- Add random rotation for variety
			state.direction = state.direction * CFrame.Angles(
				(math.random() - 0.5) * 0.4,
				(math.random() - 0.5) * 0.6,
				0
			)
			
		elseif char == "]" then
			-- Pop state (end branch)
			if #stateStack > 0 then
				local savedState = table.remove(stateStack)
				state.position = savedState.position
				state.direction = savedState.direction
				state.length = savedState.length
				state.width = savedState.width
			end
		end
		
		i = i + 1
	end
	
	-- Add leaf clusters at branch endpoints
	local canopySize = randomRange(TREE_CONFIG.CanopyWidthMin, TREE_CONFIG.CanopyWidthMax)
	
	-- Add large canopy at top
	local topY = position.Y
	for _, leafData in ipairs(leafPositions) do
		if leafData.pos.Y > topY then
			topY = leafData.pos.Y
		end
	end
	
	-- Main canopy clusters
	local numClusters = math.random(5, 10)
	for i = 1, numClusters do
		local clusterPos
		if #leafPositions > 0 then
			-- Place near branch endpoints
			local leafData = leafPositions[math.random(1, #leafPositions)]
			clusterPos = leafData.pos + Vector3.new(
				(math.random() - 0.5) * canopySize * 0.3,
				math.random() * canopySize * 0.2,
				(math.random() - 0.5) * canopySize * 0.3
			)
		else
			-- Fallback: place at top
			clusterPos = position + Vector3.new(
				(math.random() - 0.5) * canopySize * 0.5,
				trunkLength + math.random() * canopySize * 0.3,
				(math.random() - 0.5) * canopySize * 0.5
			)
		end
		
		local clusterSize = canopySize * (0.4 + math.random() * 0.4)
		createLeafCluster(clusterPos, clusterSize, treeModel)
	end
	
	treeModel.PrimaryPart = firstPart
	return treeModel
end

local function createTree(position, folder)
	local treeType = TREE_CONFIG.TreeTypes[math.random(1, #TREE_CONFIG.TreeTypes)]
	return generateLSystemTree(position, treeType, folder)
end

-- === PLACEMENT ===

local function isValidPosition(newPos, existingPositions, minSpacing)
	for _, pos in ipairs(existingPositions) do
		local distance = (Vector3.new(newPos.X, 0, newPos.Z) - Vector3.new(pos.X, 0, pos.Z)).Magnitude
		if distance < minSpacing then
			return false
		end
	end
	return true
end

local function generateTreePositions(baseplateInfo, count)
	local positions = {}
	local attempts = 0
	local maxAttempts = count * 20  -- Prevent infinite loop
	
	local halfX = baseplateInfo.size.X / 2 - TREE_CONFIG.EdgePadding
	local halfZ = baseplateInfo.size.Z / 2 - TREE_CONFIG.EdgePadding
	
	while #positions < count and attempts < maxAttempts do
		attempts += 1
		
		-- Random position on baseplate
		local x = baseplateInfo.position.X + (math.random() - 0.5) * halfX * 2
		local z = baseplateInfo.position.Z + (math.random() - 0.5) * halfZ * 2
		local newPos = Vector3.new(x, baseplateInfo.topY, z)
		
		-- Check spacing
		if isValidPosition(newPos, positions, TREE_CONFIG.MinSpacing) then
			table.insert(positions, newPos)
		end
	end
	
	return positions
end

local function generateTrees(self)
	local startTime = tick()
	
	clearTrees()
	local folder = getTreeFolder()
	
	local baseplateInfo = getBaseplateInfo()
	if not baseplateInfo then
		warn("[TreeService] No Baseplate found!")
		return
	end
	
	-- Generate positions with spacing
	local positions = generateTreePositions(baseplateInfo, TREE_CONFIG.TreeCount)
	
	-- Create trees at positions
	for i, pos in ipairs(positions) do
		local tree = createTree(pos, folder)
		table.insert(self.trees, tree)
		
		-- Yield every 10 trees to prevent lag
		if i % 10 == 0 then
			task.wait()
		end
	end
	
	local elapsed = tick() - startTime
	print(string.format("[TreeService] Generated %d trees in %.2fs", #positions, elapsed))
end

-- === KNIT LIFECYCLE ===

function TreeService:KnitInit()
	-- Nothing to init
end

function TreeService:KnitStart()
	generateTrees(self)
end

-- === PUBLIC METHODS ===

function TreeService:RegenerateTrees()
	self.trees = {}
	generateTrees(self)
end

function TreeService:ClearTrees()
	self.trees = {}
	clearTrees()
end

function TreeService:SetTreeCount(count)
	TREE_CONFIG.TreeCount = math.clamp(count, 1, 500)
end

function TreeService:SetMinSpacing(spacing)
	TREE_CONFIG.MinSpacing = math.clamp(spacing, 5, 50)
end

return TreeService

