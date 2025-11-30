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
	TreeCount = 200,
	MinSpacing = 18,
	EdgePadding = 12,
	
	-- Trunk colors (dark, organic, alien bark)
	TrunkHeightMin = 25,
	TrunkHeightMax = 60,
	TrunkWidthMin = 2,
	TrunkWidthMax = 5,
	TrunkColors = {
		Color3.fromRGB(35, 25, 30),    -- Dark charcoal
		Color3.fromRGB(25, 30, 35),    -- Deep slate
		Color3.fromRGB(40, 30, 25),    -- Dark umber
		Color3.fromRGB(30, 25, 40),    -- Midnight purple
		Color3.fromRGB(20, 28, 32),    -- Abyssal teal
	},
	TrunkMaterial = Enum.Material.Slate,
	
	-- Branches
	BranchCount = { Min = 4, Max = 9 },
	BranchLengthRatio = { Min = 0.25, Max = 0.55 },
	BranchAngle = { Min = 15, Max = 75 },
	BranchHeightStart = 0.3,
	SubBranchChance = 0.6, -- Chance for branches to have sub-branches
	
	-- Muted bioluminescent colors (subtle, eerie glow)
	CanopyColors = {
		Color3.fromRGB(60, 120, 100),   -- Muted teal
		Color3.fromRGB(90, 70, 110),    -- Dusty purple
		Color3.fromRGB(70, 100, 80),    -- Moss green
		Color3.fromRGB(100, 85, 70),    -- Amber brown
		Color3.fromRGB(65, 85, 105),    -- Steel blue
		Color3.fromRGB(85, 75, 95),     -- Twilight violet
	},
	CanopyMaterial = Enum.Material.Grass,
	CanopySizeMin = 5,
	CanopySizeMax = 12,
	
	-- Accent glow (sparse, subtle highlights)
	AccentColors = {
		Color3.fromRGB(100, 180, 160),  -- Soft cyan
		Color3.fromRGB(140, 100, 160),  -- Soft purple
		Color3.fromRGB(90, 140, 100),   -- Soft green
		Color3.fromRGB(160, 140, 100),  -- Soft amber
	},
	AccentGlowBrightness = 0.4, -- Dim glow
	AccentGlowRange = 8,
	
	-- Membrane/webbing colors (organic tissue)
	MembraneColors = {
		Color3.fromRGB(50, 60, 55),     -- Dark membrane
		Color3.fromRGB(55, 50, 60),     -- Purple membrane
		Color3.fromRGB(45, 55, 50),     -- Green membrane
	},
	
	-- Alien tree type weights
	TreeTypes = {
		{ name = "Ancient", weight = 25 },      -- Gnarled with many sub-branches
		{ name = "Fungal", weight = 20 },       -- Organic fungal growth
		{ name = "Ossified", weight = 15 },     -- Bone-like crystalline
		{ name = "Veined", weight = 25 },       -- Web of interconnected branches
		{ name = "Spire", weight = 15 },        -- Tall twisted spire
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

local function pickTrunkColor()
	return TREE_CONFIG.TrunkColors[math.random(1, #TREE_CONFIG.TrunkColors)]
end

local function pickCanopyColor()
	return TREE_CONFIG.CanopyColors[math.random(1, #TREE_CONFIG.CanopyColors)]
end

local function pickAccentColor()
	return TREE_CONFIG.AccentColors[math.random(1, #TREE_CONFIG.AccentColors)]
end

local function pickMembraneColor()
	return TREE_CONFIG.MembraneColors[math.random(1, #TREE_CONFIG.MembraneColors)]
end

local function lerpColor(c1, c2, t)
	return Color3.new(
		c1.R + (c2.R - c1.R) * t,
		c1.G + (c2.G - c1.G) * t,
		c1.B + (c2.B - c1.B) * t
	)
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

local function pickTreeType()
	local totalWeight = 0
	for _, treeType in ipairs(TREE_CONFIG.TreeTypes) do
		totalWeight = totalWeight + treeType.weight
	end
	
	local roll = math.random() * totalWeight
	local cumulative = 0
	for _, treeType in ipairs(TREE_CONFIG.TreeTypes) do
		cumulative = cumulative + treeType.weight
		if roll <= cumulative then
			return treeType.name
		end
	end
	return "Standard"
end

-- === COMPLEX ALIEN TREE CREATION ===

local function createSegmentedTrunk(position, height, width, color, parent, segments, wobbleAmount)
	segments = segments or math.random(4, 7)
	wobbleAmount = wobbleAmount or 2
	local segmentHeight = height / segments
	local currentPos = position
	local twist = math.random() * math.pi * 2
	local firstPart = nil
	local topPos = position
	
	for i = 1, segments do
		twist = twist + randomRange(0.2, 0.5)
		local wobbleX = math.sin(twist) * wobbleAmount * (i / segments)
		local wobbleZ = math.cos(twist * 1.3) * wobbleAmount * (i / segments)
		local nextPos = currentPos + Vector3.new(wobbleX, segmentHeight, wobbleZ)
		
		local dir = (nextPos - currentPos)
		local len = dir.Magnitude
		local segWidth = width * (1 - (i - 1) * 0.08)
		
		local segment = Instance.new("Part")
		segment.Name = "TrunkSeg"
		segment.Shape = Enum.PartType.Cylinder
		segment.Size = Vector3.new(len, segWidth, segWidth)
		segment.CFrame = CFrame.lookAt(currentPos + dir/2, nextPos) * CFrame.Angles(0, math.rad(90), 0)
		segment.Color = varyColor(color, 8)
		segment.Material = TREE_CONFIG.TrunkMaterial
		segment.Anchored = true
		segment.CanCollide = i == 1
		segment.Parent = parent
		
		if i == 1 then firstPart = segment end
		currentPos = nextPos
		topPos = nextPos
	end
	
	return firstPart, topPos
end

local function createBranch(startPos, direction, length, width, color, parent)
	local branch = Instance.new("Part")
	branch.Name = "Branch"
	branch.Shape = Enum.PartType.Cylinder
	branch.Size = Vector3.new(length, width, width)
	
	local endPos = startPos + direction * length
	local midPoint = startPos + direction * (length / 2)
	
	local cf = CFrame.lookAt(midPoint, endPos)
	branch.CFrame = cf * CFrame.Angles(0, math.rad(90), 0)
	branch.Color = color
	branch.Material = TREE_CONFIG.TrunkMaterial
	branch.Anchored = true
	branch.CanCollide = false
	branch.Parent = parent
	
	return branch, endPos
end

local function createCurvedBranch(startPos, baseDirection, length, width, color, parent, curveAmount)
	curveAmount = curveAmount or 0.3
	local segments = 3
	local segLen = length / segments
	local curPos = startPos
	local endPos = startPos
	local currentDir = baseDirection
	
	for i = 1, segments do
		-- Add curve
		local pitchAdjust = (math.random() - 0.5) * curveAmount
		local yawAdjust = (math.random() - 0.5) * curveAmount * 0.5
		currentDir = (CFrame.lookAt(Vector3.zero, currentDir) * CFrame.Angles(pitchAdjust, yawAdjust, 0)).LookVector
		
		local nextPos = curPos + currentDir * segLen
		local segWidth = width * (1 - (i - 1) * 0.2)
		
		local seg = Instance.new("Part")
		seg.Name = "BranchSeg"
		seg.Shape = Enum.PartType.Cylinder
		seg.Size = Vector3.new(segLen, segWidth, segWidth)
		seg.CFrame = CFrame.lookAt(curPos + (nextPos - curPos)/2, nextPos) * CFrame.Angles(0, math.rad(90), 0)
		seg.Color = varyColor(color, 5)
		seg.Material = TREE_CONFIG.TrunkMaterial
		seg.Anchored = true
		seg.CanCollide = false
		seg.Parent = parent
		
		curPos = nextPos
		endPos = nextPos
	end
	
	return endPos
end

local function createSubtleGlow(position, size, color, parent)
	local orb = Instance.new("Part")
	orb.Name = "GlowNode"
	orb.Shape = Enum.PartType.Ball
	orb.Size = Vector3.new(size, size * 0.8, size)
	orb.Position = position
	orb.Color = color
	orb.Material = Enum.Material.SmoothPlastic
	orb.Anchored = true
	orb.CanCollide = false
	orb.Transparency = 0.2
	orb.Parent = parent
	
	-- Subtle inner light
	local light = Instance.new("PointLight")
	light.Color = color
	light.Brightness = TREE_CONFIG.AccentGlowBrightness
	light.Range = TREE_CONFIG.AccentGlowRange
	light.Parent = orb
	
	return orb
end

local function createCanopyCluster(position, size, color, parent, clusterCount)
	clusterCount = clusterCount or math.random(3, 6)
	
	for i = 1, clusterCount do
		local offset = Vector3.new(
			randomRange(-size * 0.4, size * 0.4),
			randomRange(-size * 0.2, size * 0.3),
			randomRange(-size * 0.4, size * 0.4)
		)
		local clusterSize = size * randomRange(0.5, 1)
		
		local canopy = Instance.new("Part")
		canopy.Name = "Canopy"
		canopy.Shape = Enum.PartType.Ball
		canopy.Size = Vector3.new(clusterSize, clusterSize * 0.6, clusterSize)
		canopy.Position = position + offset
		canopy.Color = varyColor(color, 15)
		canopy.Material = TREE_CONFIG.CanopyMaterial
		canopy.Anchored = true
		canopy.CanCollide = false
		canopy.Parent = parent
	end
end

local function createMembrane(pos1, pos2, width, color, parent)
	local membrane = Instance.new("Part")
	membrane.Name = "Membrane"
	local dir = pos2 - pos1
	local len = dir.Magnitude
	membrane.Size = Vector3.new(len, width, 0.3)
	membrane.CFrame = CFrame.lookAt(pos1 + dir/2, pos2)
	membrane.Color = color
	membrane.Material = Enum.Material.SmoothPlastic
	membrane.Transparency = 0.4
	membrane.Anchored = true
	membrane.CanCollide = false
	membrane.Parent = parent
	return membrane
end

-- ANCIENT TREE: Gnarled with many twisted sub-branches
local function createAncientTree(position, folder)
	local model = Instance.new("Model")
	model.Name = "AncientTree"
	
	local trunkHeight = randomRange(TREE_CONFIG.TrunkHeightMin, TREE_CONFIG.TrunkHeightMax)
	local trunkWidth = randomRange(TREE_CONFIG.TrunkWidthMin * 1.2, TREE_CONFIG.TrunkWidthMax * 1.3)
	local trunkColor = pickTrunkColor()
	local canopyColor = pickCanopyColor()
	local accentColor = pickAccentColor()
	
	-- Twisted segmented trunk
	local trunk, topPos = createSegmentedTrunk(position, trunkHeight, trunkWidth, trunkColor, model, 6, 3)
	model.PrimaryPart = trunk
	
	-- Many branches with sub-branches
	local branchCount = math.random(TREE_CONFIG.BranchCount.Min, TREE_CONFIG.BranchCount.Max)
	local branchEndpoints = {}
	
	for i = 1, branchCount do
		local branchY = position.Y + trunkHeight * randomRange(TREE_CONFIG.BranchHeightStart, 0.95)
		local branchYaw = (i - 1) * (360 / branchCount) + randomRange(-25, 25)
		local branchAngle = randomRange(TREE_CONFIG.BranchAngle.Min, TREE_CONFIG.BranchAngle.Max)
		local branchLength = trunkHeight * randomRange(TREE_CONFIG.BranchLengthRatio.Min, TREE_CONFIG.BranchLengthRatio.Max)
		local branchWidth = trunkWidth * 0.4
		
		local direction = (CFrame.Angles(0, math.rad(branchYaw), 0) * CFrame.Angles(math.rad(branchAngle), 0, 0)).LookVector
		local branchStart = Vector3.new(position.X, branchY, position.Z)
		
		local branchEnd = createCurvedBranch(branchStart, direction, branchLength, branchWidth, trunkColor, model, 0.4)
		table.insert(branchEndpoints, branchEnd)
		
		-- Sub-branches
		if math.random() < TREE_CONFIG.SubBranchChance then
			local subCount = math.random(1, 3)
			for j = 1, subCount do
				local subStart = branchStart + direction * (branchLength * randomRange(0.3, 0.7))
				local subYaw = branchYaw + randomRange(-60, 60)
				local subAngle = branchAngle + randomRange(-30, 30)
				local subLength = branchLength * randomRange(0.3, 0.5)
				local subDir = (CFrame.Angles(0, math.rad(subYaw), 0) * CFrame.Angles(math.rad(subAngle), 0, 0)).LookVector
				
				local subEnd = createCurvedBranch(subStart, subDir, subLength, branchWidth * 0.5, trunkColor, model, 0.5)
				table.insert(branchEndpoints, subEnd)
			end
		end
	end
	
	-- Canopy clusters at branch endpoints
	for _, endPos in ipairs(branchEndpoints) do
		createCanopyCluster(endPos, randomRange(TREE_CONFIG.CanopySizeMin, TREE_CONFIG.CanopySizeMax), canopyColor, model)
	end
	
	-- Main canopy at top
	createCanopyCluster(topPos + Vector3.new(0, 3, 0), TREE_CONFIG.CanopySizeMax * 1.2, canopyColor, model, 5)
	
	-- Sparse accent glows
	if math.random() < 0.6 then
		local glowPos = branchEndpoints[math.random(1, #branchEndpoints)]
		createSubtleGlow(glowPos + Vector3.new(0, 2, 0), 2, accentColor, model)
	end
	
	model.Parent = folder
	return model
end

-- FUNGAL TREE: Organic fungal growth with shelf-like structures
local function createFungalTree(position, folder)
	local model = Instance.new("Model")
	model.Name = "FungalTree"
	
	local trunkHeight = randomRange(TREE_CONFIG.TrunkHeightMin * 0.8, TREE_CONFIG.TrunkHeightMax * 0.9)
	local trunkWidth = randomRange(TREE_CONFIG.TrunkWidthMax, TREE_CONFIG.TrunkWidthMax * 1.5)
	local trunkColor = pickTrunkColor()
	local fungusColor = pickCanopyColor()
	local membraneColor = pickMembraneColor()
	
	-- Thick organic trunk
	local trunk, topPos = createSegmentedTrunk(position, trunkHeight, trunkWidth, trunkColor, model, 4, 1.5)
	model.PrimaryPart = trunk
	
	-- Shelf fungi (flat disc-like growths)
	local shelfCount = math.random(5, 10)
	for i = 1, shelfCount do
		local shelfY = position.Y + trunkHeight * randomRange(0.2, 0.85)
		local shelfYaw = math.random() * 360
		local shelfDist = trunkWidth * 0.6
		local shelfSize = randomRange(4, 9)
		
		local shelfX = position.X + math.cos(math.rad(shelfYaw)) * shelfDist
		local shelfZ = position.Z + math.sin(math.rad(shelfYaw)) * shelfDist
		
		local shelf = Instance.new("Part")
		shelf.Name = "FungalShelf"
		shelf.Shape = Enum.PartType.Cylinder
		shelf.Size = Vector3.new(1.5, shelfSize, shelfSize)
		shelf.CFrame = CFrame.new(Vector3.new(shelfX, shelfY, shelfZ)) 
			* CFrame.Angles(0, math.rad(shelfYaw), math.rad(90 + randomRange(-20, 10)))
		shelf.Color = varyColor(fungusColor, 20)
		shelf.Material = Enum.Material.SmoothPlastic
		shelf.Anchored = true
		shelf.CanCollide = false
		shelf.Parent = model
	end
	
	-- Main cap at top
	local capSize = trunkWidth * randomRange(2.5, 4)
	local cap = Instance.new("Part")
	cap.Name = "FungalCap"
	cap.Shape = Enum.PartType.Ball
	cap.Size = Vector3.new(capSize, capSize * 0.35, capSize)
	cap.Position = topPos + Vector3.new(0, capSize * 0.1, 0)
	cap.Color = fungusColor
	cap.Material = Enum.Material.SmoothPlastic
	cap.Anchored = true
	cap.CanCollide = false
	cap.Parent = model
	
	-- Underside texture (gills)
	local gills = Instance.new("Part")
	gills.Name = "Gills"
	gills.Shape = Enum.PartType.Cylinder
	gills.Size = Vector3.new(1, capSize * 0.7, capSize * 0.7)
	gills.CFrame = CFrame.new(topPos - Vector3.new(0, 0.5, 0)) * CFrame.Angles(0, 0, math.rad(90))
	gills.Color = varyColor(trunkColor, 10)
	gills.Material = TREE_CONFIG.TrunkMaterial
	gills.Anchored = true
	gills.CanCollide = false
	gills.Parent = model
	
	-- Subtle glow spots
	local glowCount = math.random(2, 4)
	for i = 1, glowCount do
		local glowPos = position + Vector3.new(
			randomRange(-capSize/3, capSize/3),
			trunkHeight * randomRange(0.3, 0.7),
			randomRange(-capSize/3, capSize/3)
		)
		createSubtleGlow(glowPos, randomRange(1.5, 3), pickAccentColor(), model)
	end
	
	model.Parent = folder
	return model
end

-- OSSIFIED TREE: Bone-like crystalline structure
local function createOssifiedTree(position, folder)
	local model = Instance.new("Model")
	model.Name = "OssifiedTree"
	
	local height = randomRange(TREE_CONFIG.TrunkHeightMin, TREE_CONFIG.TrunkHeightMax * 1.2)
	local baseWidth = randomRange(TREE_CONFIG.TrunkWidthMin, TREE_CONFIG.TrunkWidthMax)
	local boneColor = Color3.fromRGB(60, 55, 50) -- Pale bone color
	local darkColor = pickTrunkColor()
	local accentColor = pickAccentColor()
	
	-- Main spine
	local trunk, topPos = createSegmentedTrunk(position, height, baseWidth, boneColor, model, 5, 1)
	model.PrimaryPart = trunk
	
	-- Rib-like branches
	local ribCount = math.random(6, 10)
	local ribEndpoints = {}
	
	for i = 1, ribCount do
		local ribY = position.Y + height * randomRange(0.25, 0.85)
		local ribYaw = (i - 1) * (360 / ribCount) + randomRange(-20, 20)
		local ribLength = height * randomRange(0.2, 0.4)
		local ribAngle = randomRange(50, 80) -- More horizontal
		
		local direction = (CFrame.Angles(0, math.rad(ribYaw), 0) * CFrame.Angles(math.rad(ribAngle), 0, 0)).LookVector
		local ribStart = Vector3.new(position.X, ribY, position.Z)
		
		local _, ribEnd = createBranch(ribStart, direction, ribLength, baseWidth * 0.35, varyColor(boneColor, 10), model)
		table.insert(ribEndpoints, ribEnd)
		
		-- Curved tip
		local tipDir = direction + Vector3.new(0, -0.3, 0)
		local tipEnd = createCurvedBranch(ribEnd, tipDir.Unit, ribLength * 0.3, baseWidth * 0.2, boneColor, model, 0.6)
		table.insert(ribEndpoints, tipEnd)
	end
	
	-- Skull-like top structure
	local skullSize = baseWidth * 3
	local skull = Instance.new("Part")
	skull.Name = "Skull"
	skull.Shape = Enum.PartType.Ball
	skull.Size = Vector3.new(skullSize, skullSize * 0.8, skullSize * 0.9)
	skull.Position = topPos + Vector3.new(0, skullSize * 0.3, 0)
	skull.Color = boneColor
	skull.Material = Enum.Material.SmoothPlastic
	skull.Anchored = true
	skull.CanCollide = false
	skull.Parent = model
	
	-- Dark base growth
	local base = Instance.new("Part")
	base.Name = "Base"
	base.Size = Vector3.new(baseWidth * 2.5, 2, baseWidth * 2.5)
	base.Position = position + Vector3.new(0, 1, 0)
	base.Color = darkColor
	base.Material = Enum.Material.Slate
	base.Anchored = true
	base.CanCollide = true
	base.Parent = model
	
	-- Eerie glow in "eye" sockets
	createSubtleGlow(topPos + Vector3.new(skullSize * 0.2, skullSize * 0.4, skullSize * 0.3), 1.5, accentColor, model)
	createSubtleGlow(topPos + Vector3.new(-skullSize * 0.2, skullSize * 0.4, skullSize * 0.3), 1.5, accentColor, model)
	
	model.Parent = folder
	return model
end

-- VEINED TREE: Web of interconnected branches with membrane
local function createVeinedTree(position, folder)
	local model = Instance.new("Model")
	model.Name = "VeinedTree"
	
	local trunkHeight = randomRange(TREE_CONFIG.TrunkHeightMin, TREE_CONFIG.TrunkHeightMax)
	local trunkWidth = randomRange(TREE_CONFIG.TrunkWidthMin, TREE_CONFIG.TrunkWidthMax)
	local trunkColor = pickTrunkColor()
	local canopyColor = pickCanopyColor()
	local membraneColor = pickMembraneColor()
	
	-- Central trunk
	local trunk, topPos = createSegmentedTrunk(position, trunkHeight, trunkWidth, trunkColor, model, 5, 2)
	model.PrimaryPart = trunk
	
	-- Complex branching network
	local branchCount = math.random(5, 8)
	local branchEndpoints = {}
	local branchMidpoints = {}
	
	for i = 1, branchCount do
		local branchY = position.Y + trunkHeight * randomRange(0.35, 0.9)
		local branchYaw = (i - 1) * (360 / branchCount) + randomRange(-20, 20)
		local branchAngle = randomRange(25, 60)
		local branchLength = trunkHeight * randomRange(0.3, 0.5)
		local branchWidth = trunkWidth * 0.35
		
		local direction = (CFrame.Angles(0, math.rad(branchYaw), 0) * CFrame.Angles(math.rad(branchAngle), 0, 0)).LookVector
		local branchStart = Vector3.new(position.X, branchY, position.Z)
		local midPoint = branchStart + direction * (branchLength * 0.5)
		
		local branchEnd = createCurvedBranch(branchStart, direction, branchLength, branchWidth, trunkColor, model, 0.3)
		table.insert(branchEndpoints, branchEnd)
		table.insert(branchMidpoints, midPoint)
		
		-- Sub-branches that connect
		local subEnd = createCurvedBranch(
			midPoint, 
			(direction + Vector3.new(0, 0.3, 0)).Unit, 
			branchLength * 0.4, 
			branchWidth * 0.5, 
			trunkColor, 
			model, 
			0.4
		)
		table.insert(branchEndpoints, subEnd)
	end
	
	-- Create membrane connections between some branches
	for i = 1, #branchEndpoints - 1 do
		if math.random() < 0.4 then
			local j = i + 1
			if j <= #branchEndpoints then
				local dist = (branchEndpoints[i] - branchEndpoints[j]).Magnitude
				if dist < trunkHeight * 0.5 then
					createMembrane(branchEndpoints[i], branchEndpoints[j], randomRange(2, 4), membraneColor, model)
				end
			end
		end
	end
	
	-- Canopy at endpoints
	for _, endPos in ipairs(branchEndpoints) do
		if math.random() < 0.7 then
			createCanopyCluster(endPos, randomRange(TREE_CONFIG.CanopySizeMin * 0.8, TREE_CONFIG.CanopySizeMax * 0.9), canopyColor, model, 2)
		end
	end
	
	-- Central canopy
	createCanopyCluster(topPos + Vector3.new(0, 2, 0), TREE_CONFIG.CanopySizeMax, canopyColor, model, 4)
	
	-- Sparse glows at intersections
	if math.random() < 0.5 then
		local glowPos = branchMidpoints[math.random(1, #branchMidpoints)]
		createSubtleGlow(glowPos, 2.5, pickAccentColor(), model)
	end
	
	model.Parent = folder
	return model
end

-- SPIRE TREE: Tall twisted spire with minimal branches
local function createSpireTree(position, folder)
	local model = Instance.new("Model")
	model.Name = "SpireTree"
	
	local height = randomRange(TREE_CONFIG.TrunkHeightMax, TREE_CONFIG.TrunkHeightMax * 1.5)
	local baseWidth = randomRange(TREE_CONFIG.TrunkWidthMin, TREE_CONFIG.TrunkWidthMax * 0.8)
	local trunkColor = pickTrunkColor()
	local canopyColor = pickCanopyColor()
	local accentColor = pickAccentColor()
	
	-- Tall twisted spire trunk
	local trunk, topPos = createSegmentedTrunk(position, height, baseWidth, trunkColor, model, 8, 4)
	model.PrimaryPart = trunk
	
	-- Sparse, drooping branches
	local branchCount = math.random(3, 5)
	local branchEndpoints = {}
	
	for i = 1, branchCount do
		local branchY = position.Y + height * randomRange(0.5, 0.85)
		local branchYaw = (i - 1) * (360 / branchCount) + randomRange(-30, 30)
		local branchAngle = randomRange(60, 85) -- Very horizontal/drooping
		local branchLength = height * randomRange(0.15, 0.3)
		
		local direction = (CFrame.Angles(0, math.rad(branchYaw), 0) * CFrame.Angles(math.rad(branchAngle), 0, 0)).LookVector
		local branchStart = Vector3.new(position.X, branchY, position.Z)
		
		-- Drooping curved branch
		local branchEnd = createCurvedBranch(branchStart, direction, branchLength, baseWidth * 0.3, trunkColor, model, 0.6)
		table.insert(branchEndpoints, branchEnd)
	end
	
	-- Small canopy clusters at tips
	for _, endPos in ipairs(branchEndpoints) do
		createCanopyCluster(endPos, randomRange(TREE_CONFIG.CanopySizeMin * 0.7, TREE_CONFIG.CanopySizeMax * 0.8), canopyColor, model, 2)
	end
	
	-- Crown at top
	createCanopyCluster(topPos + Vector3.new(0, 2, 0), TREE_CONFIG.CanopySizeMin, canopyColor, model, 3)
	
	-- Single accent glow at peak
	createSubtleGlow(topPos + Vector3.new(0, 4, 0), 3, accentColor, model)
	
	model.Parent = folder
	return model
end

local function createTree(position, folder)
	local treeType = pickTreeType()
	
	if treeType == "Ancient" then
		return createAncientTree(position, folder)
	elseif treeType == "Fungal" then
		return createFungalTree(position, folder)
	elseif treeType == "Ossified" then
		return createOssifiedTree(position, folder)
	elseif treeType == "Veined" then
		return createVeinedTree(position, folder)
	elseif treeType == "Spire" then
		return createSpireTree(position, folder)
	else
		return createAncientTree(position, folder)
	end
end

-- === PLACEMENT ===

-- Check if position is valid using GridService for exclusion zones
local function isValidPosition(newPos, existingPositions, minSpacing)
	-- Check GridService exclusion zones first
	local GridService = nil
	pcall(function()
		GridService = Knit.GetService("GridService")
	end)
	
	if GridService then
		local excluded = GridService:IsPositionExcluded(newPos)
		if excluded then
			return false
		end
	end
	
	-- Check spacing from other trees
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
	local maxAttempts = count * 20
	
	local halfX = baseplateInfo.size.X / 2 - TREE_CONFIG.EdgePadding
	local halfZ = baseplateInfo.size.Z / 2 - TREE_CONFIG.EdgePadding
	
	while #positions < count and attempts < maxAttempts do
		attempts += 1
		
		local x = baseplateInfo.position.X + (math.random() - 0.5) * halfX * 2
		local z = baseplateInfo.position.Z + (math.random() - 0.5) * halfZ * 2
		local newPos = Vector3.new(x, baseplateInfo.topY, z)
		
		if isValidPosition(newPos, positions, TREE_CONFIG.MinSpacing) then
			table.insert(positions, newPos)
		end
	end
	
	return positions
end

local function generateTrees(self)
	local startTime = tick()
	
	local LoadingService = nil
	pcall(function()
		LoadingService = Knit.GetService("LoadingService")
	end)
	
	local function reportProgress(current, total, message)
		if LoadingService then
			LoadingService:ReportProgress("TreeService", current, total, message or "Growing trees")
		end
	end
	
	reportProgress(0, 100, "Preparing forest")
	
	clearTrees()
	local folder = getTreeFolder()
	
	local baseplateInfo = getBaseplateInfo()
	if not baseplateInfo then
		warn("[TreeService] No Baseplate found!")
		return
	end
	
	reportProgress(5, 100, "Finding tree positions")
	
	local positions = generateTreePositions(baseplateInfo, TREE_CONFIG.TreeCount)
	
	reportProgress(15, 100, "Growing trees")
	
	local totalTrees = #positions
	local batchSize = 15 -- Create more trees per batch for better performance
	
	for i, pos in ipairs(positions) do
		local tree = createTree(pos, folder)
		table.insert(self.trees, tree)
		
		if i % batchSize == 0 then
			local treeProgress = 15 + (i / totalTrees) * 80
			reportProgress(math.floor(treeProgress), 100, string.format("Growing trees (%d/%d)", i, totalTrees))
			task.wait()
		end
	end
	
	local elapsed = tick() - startTime
	print(string.format("[TreeService] Generated %d trees in %.2fs", #positions, elapsed))
	
	reportProgress(100, 100, "Forest complete")
	
	if LoadingService then
		LoadingService:MarkStepComplete("TreeService")
	end
end

-- === KNIT LIFECYCLE ===

function TreeService:KnitInit()
	print("[TreeService] Initializing...")
end

function TreeService:KnitStart()
	print("[TreeService] Starting...")
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
