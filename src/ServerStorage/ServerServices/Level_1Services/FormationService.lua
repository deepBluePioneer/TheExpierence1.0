local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local Knit = require(Packages.Knit)

local FormationService = Knit.CreateService {
	Name = "FormationService",
	Client = {},
	formations = {},
	_autoStart = false,  -- Set to false to let WorldInitService control initialization
	_baseplateInfo = nil,
}

-- === CONFIG ===
local CONFIG = {
	-- Spawning
	FormationCount = 80,
	MinSpacing = 25,
	EdgePadding = 15,
	TreeAvoidDistance = 12, -- Avoid spawning too close to trees
	TerrainEmbedDepth = 3,  -- Base studs below terrain surface to embed formation
	TerrainEmbedMin = 2,    -- Minimum embed depth (guaranteed)
	TerrainEmbedMax = 5,    -- Maximum embed depth (prevents too deep on steep slopes)
	FootprintRadius = 8,    -- Radius to sample for ground height (larger for formations)
	
	-- Base colors (dark, alien palette)
	BaseColors = {
		Color3.fromRGB(30, 28, 35),    -- Dark void
		Color3.fromRGB(35, 30, 40),    -- Deep purple
		Color3.fromRGB(25, 32, 35),    -- Abyssal teal
		Color3.fromRGB(40, 35, 30),    -- Dark rust
		Color3.fromRGB(28, 28, 32),    -- Charcoal
	},
	
	-- Crystal/mineral colors (muted, alien)
	CrystalColors = {
		Color3.fromRGB(70, 90, 85),    -- Jade
		Color3.fromRGB(85, 70, 95),    -- Amethyst
		Color3.fromRGB(90, 85, 70),    -- Amber
		Color3.fromRGB(65, 80, 90),    -- Steel blue
		Color3.fromRGB(80, 75, 70),    -- Stone gray
	},
	
	-- Organic/membrane colors
	OrganicColors = {
		Color3.fromRGB(55, 50, 60),    -- Dark membrane
		Color3.fromRGB(50, 55, 52),    -- Moss
		Color3.fromRGB(60, 52, 55),    -- Flesh
		Color3.fromRGB(48, 55, 58),    -- Teal flesh
	},
	
	-- Subtle accent glow
	AccentColors = {
		Color3.fromRGB(100, 140, 130), -- Soft teal
		Color3.fromRGB(130, 100, 140), -- Soft purple
		Color3.fromRGB(140, 130, 100), -- Soft amber
		Color3.fromRGB(90, 120, 100),  -- Soft green
	},
	GlowBrightness = 0.3,
	GlowRange = 10,
	
	-- Formation type weights
	FormationTypes = {
		{ name = "CrystalCluster", weight = 20 },
		{ name = "OrganicSpire", weight = 15 },
		{ name = "Monolith", weight = 12 },
		{ name = "FungalColony", weight = 18 },
		{ name = "FossilFormation", weight = 10 },
		{ name = "FloatingRocks", weight = 8 },
		{ name = "PodCluster", weight = 12 },
		{ name = "AncientRuin", weight = 5 },
	},
}

local FOLDER_NAME = "AlienFormations"

-- === HELPERS ===

local function getFormationFolder()
	local folder = Workspace:FindFirstChild(FOLDER_NAME)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = FOLDER_NAME
		folder.Parent = Workspace
	end
	return folder
end

local function clearFormations()
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

local function pickColor(colorTable)
	return colorTable[math.random(1, #colorTable)]
end

local function pickFormationType()
	local totalWeight = 0
	for _, t in ipairs(CONFIG.FormationTypes) do
		totalWeight = totalWeight + t.weight
	end
	
	local roll = math.random() * totalWeight
	local cumulative = 0
	for _, t in ipairs(CONFIG.FormationTypes) do
		cumulative = cumulative + t.weight
		if roll <= cumulative then
			return t.name
		end
	end
	return "CrystalCluster"
end

local function getBaseplateInfo()
	-- First try to get info from WorldInitService (preferred)
	local WorldInitService = nil
	pcall(function()
		WorldInitService = Knit.GetService("WorldInitService")
	end)
	
	if WorldInitService then
		local info = WorldInitService:GetBaseplateInfo()
		if info then
			return {
				position = info.position,
				size = info.size,
				topY = info.topY,
			}
		end
	end
	
	-- Fallback: Try GridService for grid dimensions
	local GridService = nil
	pcall(function()
		GridService = Knit.GetService("GridService")
	end)
	
	if GridService then
		local gridData = GridService:GetGridData()
		if gridData and gridData.cellSize > 0 then
			local totalWidth = gridData.width * gridData.cellSize
			local totalDepth = gridData.depth * gridData.cellSize
			return {
				position = Vector3.new(gridData.centerX, gridData.topY, gridData.centerZ),
				size = Vector3.new(totalWidth, 1, totalDepth),
				topY = gridData.topY,
			}
		end
	end
	
	-- Legacy fallback: look for physical Baseplate
	local baseplate = Workspace:FindFirstChild("Baseplate")
	if baseplate and baseplate:IsA("BasePart") then
		return {
			position = baseplate.Position,
			size = baseplate.Size,
			topY = baseplate.Position.Y + baseplate.Size.Y / 2,
		}
	end
	
	-- Default fallback
	return {
		position = Vector3.new(0, 0, 0),
		size = Vector3.new(384, 1, 384),
		topY = 0,
	}
end

local function createSubtleGlow(position, size, color, parent)
	local orb = Instance.new("Part")
	orb.Name = "GlowCore"
	orb.Shape = Enum.PartType.Ball
	orb.Size = Vector3.new(size * 1.5, size * 1.5, size * 1.5)
	orb.Position = position
	orb.Color = color
	orb.Material = Enum.Material.Slate
	orb.Transparency = 0
	orb.Anchored = true
	orb.CanCollide = true
	orb.Parent = parent
	
	local light = Instance.new("PointLight")
	light.Color = color
	light.Brightness = CONFIG.GlowBrightness
	light.Range = CONFIG.GlowRange
	light.Parent = orb
	
	return orb
end

-- === FORMATION GENERATORS ===

-- CRYSTAL CLUSTER: Group of crystalline spires
local function createCrystalCluster(position, folder)
	local model = Instance.new("Model")
	model.Name = "CrystalCluster"
	
	local baseColor = pickColor(CONFIG.BaseColors)
	local crystalColor = pickColor(CONFIG.CrystalColors)
	local accentColor = pickColor(CONFIG.AccentColors)
	
	-- Base rock
	local baseSize = randomRange(6, 12)
	local base = Instance.new("Part")
	base.Name = "Base"
	base.Size = Vector3.new(baseSize, baseSize * 0.4, baseSize)
	base.Position = position + Vector3.new(0, baseSize * 0.15, 0)
	base.Color = baseColor
	base.Material = Enum.Material.Slate
	base.Anchored = true
	base.CanCollide = true
	base.Parent = model
	model.PrimaryPart = base
	
	-- Crystal spires (solid, collidable)
	local crystalCount = math.random(4, 8)
	for i = 1, crystalCount do
		local height = randomRange(8, 25)
		local width = randomRange(1.5, 4)
		local angle = (i - 1) * (360 / crystalCount) + randomRange(-30, 30)
		local dist = randomRange(0, baseSize * 0.35)
		local tilt = randomRange(5, 25)
		
		local crystal = Instance.new("Part")
		crystal.Name = "Crystal"
		crystal.Size = Vector3.new(width, height, width)
		
		local xOff = math.cos(math.rad(angle)) * dist
		local zOff = math.sin(math.rad(angle)) * dist
		crystal.Position = position + Vector3.new(xOff, height / 2 + baseSize * 0.2, zOff)
		
		-- Tilt outward
		crystal.CFrame = crystal.CFrame * CFrame.Angles(
			math.rad(tilt) * math.cos(math.rad(angle)),
			math.rad(randomRange(-15, 15)),
			math.rad(tilt) * math.sin(math.rad(angle))
		)
		
		crystal.Color = varyColor(crystalColor, 15)
		crystal.Material = Enum.Material.Slate
		crystal.Transparency = 0
		crystal.Anchored = true
		crystal.CanCollide = true
		crystal.Parent = model
	end
	
	-- Central glow
	if math.random() < 0.5 then
		local glowY = position.Y + baseSize * 0.3 + randomRange(3, 8)
		createSubtleGlow(Vector3.new(position.X, glowY, position.Z), 2, accentColor, model)
	end
	
	model.Parent = folder
	return model
end

-- ORGANIC SPIRE: Twisted organic tendril formation
local function createOrganicSpire(position, folder)
	local model = Instance.new("Model")
	model.Name = "OrganicSpire"
	
	local organicColor = pickColor(CONFIG.OrganicColors)
	local accentColor = pickColor(CONFIG.AccentColors)
	
	local height = randomRange(15, 35)
	local baseWidth = randomRange(3, 5)
	local segments = math.random(5, 8)
	local segmentHeight = height / segments
	
	local currentPos = position
	local twist = math.random() * math.pi * 2
	local firstPart = nil
	
	for i = 1, segments do
		twist = twist + randomRange(0.3, 0.6)
		local wobbleX = math.sin(twist) * 2 * (i / segments)
		local wobbleZ = math.cos(twist * 1.2) * 2 * (i / segments)
		local nextPos = currentPos + Vector3.new(wobbleX, segmentHeight, wobbleZ)
		
		local segWidth = baseWidth * (1 - (i - 1) * 0.1)
		local dir = nextPos - currentPos
		local len = dir.Magnitude
		
		local segment = Instance.new("Part")
		segment.Name = "Segment"
		segment.Shape = Enum.PartType.Cylinder
		segment.Size = Vector3.new(len, segWidth, segWidth)
		segment.CFrame = CFrame.lookAt(currentPos + dir/2, nextPos) * CFrame.Angles(0, math.rad(90), 0)
		segment.Color = varyColor(organicColor, 10)
		segment.Material = Enum.Material.Slate
		segment.Anchored = true
		segment.CanCollide = true
		segment.Parent = model
		
		if i == 1 then 
			firstPart = segment 
			model.PrimaryPart = segment
		end
		
		-- Bulges/nodes at intervals
		if i % 2 == 0 then
			local node = Instance.new("Part")
			node.Name = "Node"
			node.Shape = Enum.PartType.Ball
			node.Size = Vector3.new(segWidth * 1.5, segWidth * 1.3, segWidth * 1.5)
			node.Position = currentPos
			node.Color = varyColor(organicColor, 8)
			node.Material = Enum.Material.Slate
			node.Anchored = true
			node.CanCollide = true
			node.Parent = model
		end
		
		currentPos = nextPos
	end
	
	-- Tip (solid)
	local tip = Instance.new("Part")
	tip.Name = "Tip"
	tip.Shape = Enum.PartType.Ball
	tip.Size = Vector3.new(baseWidth * 1.2, baseWidth * 1.5, baseWidth * 1.2)
	tip.Position = currentPos
	tip.Color = accentColor
	tip.Material = Enum.Material.Slate
	tip.Transparency = 0
	tip.Anchored = true
	tip.CanCollide = true
	tip.Parent = model
	
	local tipLight = Instance.new("PointLight")
	tipLight.Color = accentColor
	tipLight.Brightness = CONFIG.GlowBrightness * 1.5
	tipLight.Range = CONFIG.GlowRange
	tipLight.Parent = tip
	
	model.Parent = folder
	return model
end

-- MONOLITH: Tall angular alien obelisk
local function createMonolith(position, folder)
	local model = Instance.new("Model")
	model.Name = "Monolith"
	
	local baseColor = pickColor(CONFIG.BaseColors)
	local accentColor = pickColor(CONFIG.AccentColors)
	
	local height = randomRange(25, 50)
	local width = randomRange(4, 8)
	local depth = randomRange(2, 4)
	
	-- Main slab
	local slab = Instance.new("Part")
	slab.Name = "Slab"
	slab.Size = Vector3.new(width, height, depth)
	slab.Position = position + Vector3.new(0, height / 2, 0)
	slab.Color = baseColor
	slab.Material = Enum.Material.Slate
	slab.Anchored = true
	slab.CanCollide = true
	slab.Parent = model
	model.PrimaryPart = slab
	
	-- Slight tilt
	slab.CFrame = slab.CFrame * CFrame.Angles(
		math.rad(randomRange(-5, 5)),
		math.rad(randomRange(0, 360)),
		math.rad(randomRange(-5, 5))
	)
	
	-- Carved grooves (darker inset lines)
	local grooveCount = math.random(3, 6)
	for i = 1, grooveCount do
		local grooveY = position.Y + height * (i / (grooveCount + 1))
		local groove = Instance.new("Part")
		groove.Name = "Groove"
		groove.Size = Vector3.new(width * 0.9, 0.5, depth + 0.2)
		groove.CFrame = slab.CFrame * CFrame.new(0, grooveY - position.Y - height/2, 0)
		groove.Color = Color3.fromRGB(15, 15, 20)
		groove.Material = Enum.Material.Slate
		groove.Anchored = true
		groove.CanCollide = true
		groove.Parent = model
	end
	
	-- Top symbol (solid)
	local symbol = Instance.new("Part")
	symbol.Name = "Symbol"
	symbol.Shape = Enum.PartType.Ball
	symbol.Size = Vector3.new(width * 0.5, width * 0.5, 1.5)
	symbol.CFrame = slab.CFrame * CFrame.new(0, height * 0.35, depth/2 + 0.5)
	symbol.Color = accentColor
	symbol.Material = Enum.Material.Slate
	symbol.Transparency = 0
	symbol.Anchored = true
	symbol.CanCollide = true
	symbol.Parent = model
	
	local symbolLight = Instance.new("PointLight")
	symbolLight.Color = accentColor
	symbolLight.Brightness = CONFIG.GlowBrightness
	symbolLight.Range = CONFIG.GlowRange * 0.8
	symbolLight.Parent = symbol
	
	model.Parent = folder
	return model
end

-- FUNGAL COLONY: Cluster of mushroom-like growths
local function createFungalColony(position, folder)
	local model = Instance.new("Model")
	model.Name = "FungalColony"
	
	local stalkColor = pickColor(CONFIG.OrganicColors)
	local capColor = pickColor(CONFIG.CrystalColors)
	
	local colonyRadius = randomRange(6, 12)
	local shroomCount = math.random(5, 12)
	local firstPart = nil
	
	for i = 1, shroomCount do
		local angle = math.random() * math.pi * 2
		local dist = math.random() * colonyRadius
		local xOff = math.cos(angle) * dist
		local zOff = math.sin(angle) * dist
		
		local stalkHeight = randomRange(3, 15)
		local stalkWidth = randomRange(0.8, 2.5)
		local capSize = stalkWidth * randomRange(2, 4)
		
		local shroomPos = position + Vector3.new(xOff, 0, zOff)
		
		-- Stalk
		local stalk = Instance.new("Part")
		stalk.Name = "Stalk"
		stalk.Shape = Enum.PartType.Cylinder
		stalk.Size = Vector3.new(stalkHeight, stalkWidth * 1.5, stalkWidth * 1.5)
		stalk.CFrame = CFrame.new(shroomPos + Vector3.new(0, stalkHeight/2, 0)) * CFrame.Angles(0, 0, math.rad(90))
		stalk.Color = varyColor(stalkColor, 12)
		stalk.Material = Enum.Material.Slate
		stalk.Anchored = true
		stalk.CanCollide = true
		stalk.Parent = model
		
		if i == 1 then 
			firstPart = stalk 
			model.PrimaryPart = stalk
		end
		
		-- Cap
		local cap = Instance.new("Part")
		cap.Name = "Cap"
		cap.Shape = Enum.PartType.Ball
		cap.Size = Vector3.new(capSize, capSize * 0.5, capSize)
		cap.Position = shroomPos + Vector3.new(0, stalkHeight + capSize * 0.15, 0)
		cap.Color = varyColor(capColor, 15)
		cap.Material = Enum.Material.Slate
		cap.Anchored = true
		cap.CanCollide = true
		cap.Parent = model
	end
	
	-- Ground cover (scattered small parts)
	local coverCount = math.random(8, 15)
	for i = 1, coverCount do
		local angle = math.random() * math.pi * 2
		local dist = math.random() * colonyRadius * 1.2
		local cover = Instance.new("Part")
		cover.Name = "Cover"
		cover.Size = Vector3.new(randomRange(2, 4), randomRange(1, 2), randomRange(2, 4))
		cover.Position = position + Vector3.new(math.cos(angle) * dist, 0.5, math.sin(angle) * dist)
		cover.Color = varyColor(stalkColor, 8)
		cover.Material = Enum.Material.Slate
		cover.Anchored = true
		cover.CanCollide = true
		cover.Parent = model
	end
	
	model.Parent = folder
	return model
end

-- FOSSIL FORMATION: Bone-like exposed formations
local function createFossilFormation(position, folder)
	local model = Instance.new("Model")
	model.Name = "FossilFormation"
	
	local boneColor = Color3.fromRGB(65, 60, 55)
	local baseColor = pickColor(CONFIG.BaseColors)
	
	-- Embedded rock base
	local baseSize = randomRange(8, 15)
	local base = Instance.new("Part")
	base.Name = "Base"
	base.Size = Vector3.new(baseSize, baseSize * 0.3, baseSize * 0.8)
	base.Position = position + Vector3.new(0, baseSize * 0.1, 0)
	base.Color = baseColor
	base.Material = Enum.Material.Slate
	base.Anchored = true
	base.CanCollide = true
	base.Parent = model
	model.PrimaryPart = base
	
	-- Rib cage structure
	local ribCount = math.random(5, 8)
	local spineLength = baseSize * 0.8
	
	-- Spine
	local spine = Instance.new("Part")
	spine.Name = "Spine"
	spine.Shape = Enum.PartType.Cylinder
	spine.Size = Vector3.new(spineLength, 2.5, 2.5)
	spine.CFrame = CFrame.new(position + Vector3.new(0, baseSize * 0.25, 0)) * CFrame.Angles(0, math.rad(90), math.rad(90))
	spine.Color = boneColor
	spine.Material = Enum.Material.Slate
	spine.Anchored = true
	spine.CanCollide = true
	spine.Parent = model
	
	-- Ribs
	for i = 1, ribCount do
		local ribX = -spineLength/2 + (i - 1) * (spineLength / (ribCount - 1))
		local ribHeight = randomRange(4, 10)
		local ribCurve = randomRange(3, 6)
		
		for side = -1, 1, 2 do
			local rib = Instance.new("Part")
			rib.Name = "Rib"
			rib.Shape = Enum.PartType.Cylinder
			rib.Size = Vector3.new(ribHeight, 1.2, 1.2)
			
			local ribPos = position + Vector3.new(ribX, baseSize * 0.25 + ribHeight/2, side * ribCurve/2)
			rib.CFrame = CFrame.new(ribPos) * CFrame.Angles(0, 0, math.rad(side * 30))
			rib.Color = varyColor(boneColor, 10)
			rib.Material = Enum.Material.Slate
			rib.Anchored = true
			rib.CanCollide = true
			rib.Parent = model
		end
	end
	
	-- Skull-like end piece
	local skull = Instance.new("Part")
	skull.Name = "Skull"
	skull.Size = Vector3.new(4, 3.5, 3)
	skull.Position = position + Vector3.new(spineLength/2 + 2, baseSize * 0.35, 0)
	skull.Color = boneColor
	skull.Material = Enum.Material.Slate
	skull.Anchored = true
	skull.CanCollide = true
	skull.Parent = model
	
	model.Parent = folder
	return model
end

-- FLOATING ROCKS: Hovering rock fragments
local function createFloatingRocks(position, folder)
	local model = Instance.new("Model")
	model.Name = "FloatingRocks"
	
	local rockColor = pickColor(CONFIG.BaseColors)
	local accentColor = pickColor(CONFIG.AccentColors)
	
	local rockCount = math.random(4, 8)
	local firstPart = nil
	
	for i = 1, rockCount do
		local size = randomRange(3, 7)
		local height = randomRange(5, 20)
		local angle = (i - 1) * (360 / rockCount) + randomRange(-30, 30)
		local dist = randomRange(2, 8)
		
		local rock = Instance.new("Part")
		rock.Name = "FloatingRock"
		rock.Size = Vector3.new(size, size * randomRange(0.6, 1.4), size * randomRange(0.8, 1.2))
		
		local xOff = math.cos(math.rad(angle)) * dist
		local zOff = math.sin(math.rad(angle)) * dist
		rock.Position = position + Vector3.new(xOff, height, zOff)
		
		rock.CFrame = rock.CFrame * CFrame.Angles(
			math.rad(randomRange(-30, 30)),
			math.rad(randomRange(0, 360)),
			math.rad(randomRange(-30, 30))
		)
		
		rock.Color = varyColor(rockColor, 12)
		rock.Material = Enum.Material.Slate
		rock.Anchored = true
		rock.CanCollide = true
		rock.Parent = model
		
		if i == 1 then 
			firstPart = rock 
			model.PrimaryPart = rock
		end
	end
	
	-- Central pillar on ground (solid)
	local glowBase = Instance.new("Part")
	glowBase.Name = "GlowBase"
	glowBase.Shape = Enum.PartType.Cylinder
	glowBase.Size = Vector3.new(2, 5, 5)
	glowBase.CFrame = CFrame.new(position + Vector3.new(0, 1, 0)) * CFrame.Angles(0, 0, math.rad(90))
	glowBase.Color = accentColor
	glowBase.Material = Enum.Material.Slate
	glowBase.Transparency = 0
	glowBase.Anchored = true
	glowBase.CanCollide = true
	glowBase.Parent = model
	
	local light = Instance.new("PointLight")
	light.Color = accentColor
	light.Brightness = CONFIG.GlowBrightness * 2
	light.Range = CONFIG.GlowRange * 1.5
	light.Parent = glowBase
	
	model.Parent = folder
	return model
end

-- POD CLUSTER: Organic egg-like pods
local function createPodCluster(position, folder)
	local model = Instance.new("Model")
	model.Name = "PodCluster"
	
	local podColor = pickColor(CONFIG.OrganicColors)
	local innerColor = pickColor(CONFIG.AccentColors)
	
	local clusterRadius = randomRange(5, 10)
	local podCount = math.random(4, 9)
	local firstPart = nil
	
	for i = 1, podCount do
		local angle = math.random() * math.pi * 2
		local dist = math.random() * clusterRadius
		local xOff = math.cos(angle) * dist
		local zOff = math.sin(angle) * dist
		
		local podHeight = randomRange(4, 10)
		local podWidth = podHeight * randomRange(0.6, 0.8)
		
		local pod = Instance.new("Part")
		pod.Name = "Pod"
		pod.Shape = Enum.PartType.Ball
		pod.Size = Vector3.new(podWidth, podHeight, podWidth)
		pod.Position = position + Vector3.new(xOff, podHeight * 0.4, zOff)
		pod.Color = varyColor(podColor, 10)
		pod.Material = Enum.Material.Slate
		pod.Anchored = true
		pod.CanCollide = true
		pod.Parent = model
		
		if i == 1 then 
			firstPart = pod 
			model.PrimaryPart = pod
		end
		
		-- Light source on some pods
		if math.random() < 0.4 then
			local podLight = Instance.new("PointLight")
			podLight.Color = innerColor
			podLight.Brightness = CONFIG.GlowBrightness
			podLight.Range = CONFIG.GlowRange * 0.6
			podLight.Parent = pod
		end
	end
	
	-- Ground base (solid platform)
	local web = Instance.new("Part")
	web.Name = "Base"
	web.Shape = Enum.PartType.Cylinder
	web.Size = Vector3.new(2, clusterRadius * 2, clusterRadius * 2)
	web.CFrame = CFrame.new(position + Vector3.new(0, 1, 0)) * CFrame.Angles(0, 0, math.rad(90))
	web.Color = varyColor(podColor, 5)
	web.Material = Enum.Material.Slate
	web.Transparency = 0
	web.Anchored = true
	web.CanCollide = true
	web.Parent = model
	
	model.Parent = folder
	return model
end

-- ANCIENT RUIN: Crumbling alien pillar/structure
local function createAncientRuin(position, folder)
	local model = Instance.new("Model")
	model.Name = "AncientRuin"
	
	local stoneColor = pickColor(CONFIG.BaseColors)
	local accentColor = pickColor(CONFIG.AccentColors)
	
	-- Base platform
	local platformSize = randomRange(12, 20)
	local platform = Instance.new("Part")
	platform.Name = "Platform"
	platform.Size = Vector3.new(platformSize, 2, platformSize)
	platform.Position = position + Vector3.new(0, 1, 0)
	platform.Color = stoneColor
	platform.Material = Enum.Material.Slate
	platform.Anchored = true
	platform.CanCollide = true
	platform.Parent = model
	model.PrimaryPart = platform
	
	-- Broken pillars
	local pillarCount = math.random(3, 6)
	for i = 1, pillarCount do
		local angle = (i - 1) * (360 / pillarCount) + randomRange(-20, 20)
		local dist = platformSize * 0.35
		local pillarHeight = randomRange(8, 25)
		local pillarWidth = randomRange(2, 4)
		
		local xOff = math.cos(math.rad(angle)) * dist
		local zOff = math.sin(math.rad(angle)) * dist
		
		local pillar = Instance.new("Part")
		pillar.Name = "Pillar"
		pillar.Shape = Enum.PartType.Cylinder
		pillar.Size = Vector3.new(pillarHeight, pillarWidth, pillarWidth)
		pillar.CFrame = CFrame.new(position + Vector3.new(xOff, 2 + pillarHeight/2, zOff)) * CFrame.Angles(0, 0, math.rad(90))
		
		-- Some pillars are broken/tilted
		if math.random() < 0.4 then
			pillar.CFrame = pillar.CFrame * CFrame.Angles(math.rad(randomRange(-20, 20)), 0, math.rad(randomRange(-15, 15)))
		end
		
		pillar.Color = varyColor(stoneColor, 10)
		pillar.Material = Enum.Material.Slate
		pillar.Anchored = true
		pillar.CanCollide = true
		pillar.Parent = model
	end
	
	-- Central altar/pedestal
	local altar = Instance.new("Part")
	altar.Name = "Altar"
	altar.Size = Vector3.new(4, 3, 4)
	altar.Position = position + Vector3.new(0, 3.5, 0)
	altar.Color = varyColor(stoneColor, 8)
	altar.Material = Enum.Material.Slate
	altar.Anchored = true
	altar.CanCollide = true
	altar.Parent = model
	
	-- Artifact on altar (solid)
	local artifact = Instance.new("Part")
	artifact.Name = "Artifact"
	artifact.Shape = Enum.PartType.Ball
	artifact.Size = Vector3.new(3, 4, 3)
	artifact.Position = position + Vector3.new(0, 6.5, 0)
	artifact.Color = accentColor
	artifact.Material = Enum.Material.Slate
	artifact.Transparency = 0
	artifact.Anchored = true
	artifact.CanCollide = true
	artifact.Parent = model
	
	local artifactLight = Instance.new("PointLight")
	artifactLight.Color = accentColor
	artifactLight.Brightness = CONFIG.GlowBrightness * 2
	artifactLight.Range = CONFIG.GlowRange * 2
	artifactLight.Parent = artifact
	
	-- Scattered debris (solid blocks)
	local debrisCount = math.random(5, 10)
	for i = 1, debrisCount do
		local debris = Instance.new("Part")
		debris.Name = "Debris"
		debris.Size = Vector3.new(randomRange(2, 4), randomRange(1, 3), randomRange(2, 4))
		debris.Position = position + Vector3.new(
			randomRange(-platformSize/2, platformSize/2),
			randomRange(1, 2),
			randomRange(-platformSize/2, platformSize/2)
		)
		debris.CFrame = debris.CFrame * CFrame.Angles(
			math.rad(randomRange(-30, 30)),
			math.rad(randomRange(0, 360)),
			math.rad(randomRange(-30, 30))
		)
		debris.Color = varyColor(stoneColor, 15)
		debris.Material = Enum.Material.Slate
		debris.Anchored = true
		debris.CanCollide = true
		debris.Parent = model
	end
	
	model.Parent = folder
	return model
end

local function createFormation(position, folder)
	local formationType = pickFormationType()
	
	if formationType == "CrystalCluster" then
		return createCrystalCluster(position, folder)
	elseif formationType == "OrganicSpire" then
		return createOrganicSpire(position, folder)
	elseif formationType == "Monolith" then
		return createMonolith(position, folder)
	elseif formationType == "FungalColony" then
		return createFungalColony(position, folder)
	elseif formationType == "FossilFormation" then
		return createFossilFormation(position, folder)
	elseif formationType == "FloatingRocks" then
		return createFloatingRocks(position, folder)
	elseif formationType == "PodCluster" then
		return createPodCluster(position, folder)
	elseif formationType == "AncientRuin" then
		return createAncientRuin(position, folder)
	else
		return createCrystalCluster(position, folder)
	end
end

-- === PLACEMENT ===

local function isValidPosition(newPos, existingPositions, minSpacing)
	-- Check GridService exclusion zones first
	local GridService = nil
	pcall(function()
		GridService = Knit.GetService("GridService")
	end)
	
	if GridService then
		-- Check exclusion zones
		local excluded = GridService:IsPositionExcluded(newPos)
		if excluded then
			return false
		end
		
		-- Check if position is in a Building zone (not Radiation zones)
		if GridService.WorldToGrid then
			local gridX, gridZ = GridService:WorldToGrid(newPos)
			if gridX and gridZ then
				-- Check ReservedZoneService for Building zones specifically
				local ReservedZoneService = nil
				pcall(function()
					ReservedZoneService = Knit.GetService("ReservedZoneService")
				end)
				
				if ReservedZoneService and ReservedZoneService.IsCellInZone then
					-- Block placement in Building zones, but allow in Radiation zones
					if ReservedZoneService:IsCellInZone(gridX, gridZ, "Building") then
						return false
					end
				else
					-- Fallback: check if cell is occupied (for backwards compatibility)
					if GridService.IsCellOccupied and GridService:IsCellOccupied(gridX, gridZ) then
						-- Only block if it's a Building zone (we can't tell, so be conservative)
						-- This is a fallback, so we'll block all occupied cells
						return false
					end
				end
			end
		end
	end
	
	-- Check spacing from other formations
	for _, pos in ipairs(existingPositions) do
		local distance = (Vector3.new(newPos.X, 0, newPos.Z) - Vector3.new(pos.X, 0, pos.Z)).Magnitude
		if distance < minSpacing then
			return false
		end
	end
	return true
end

local function getTreePositions()
	local treeFolder = Workspace:FindFirstChild("ProceduralTrees")
	local positions = {}
	
	if treeFolder then
		for _, tree in ipairs(treeFolder:GetChildren()) do
			if tree:IsA("Model") and tree.PrimaryPart then
				table.insert(positions, tree.PrimaryPart.Position)
			end
		end
	end
	
	return positions
end

-- Create raycast params (cached for performance)
local terrainRaycastParams = RaycastParams.new()
terrainRaycastParams.FilterType = Enum.RaycastFilterType.Exclude

local function updateTerrainRaycastFilter()
	local excludeList = {}
	
	-- Exclude non-terrain objects
	local treesFolder = Workspace:FindFirstChild("ProceduralTrees")
	if treesFolder then table.insert(excludeList, treesFolder) end
	
	local formationsFolder = Workspace:FindFirstChild("AlienFormations")
	if formationsFolder then table.insert(excludeList, formationsFolder) end
	
	local baseplatesFolder = Workspace:FindFirstChild("WorldBaseplates")
	if baseplatesFolder then table.insert(excludeList, baseplatesFolder) end
	
	local gridFolder = Workspace:FindFirstChild("GridCubes")
	if gridFolder then table.insert(excludeList, gridFolder) end
	
	local redZonesFolder = Workspace:FindFirstChild("RedZones")
	if redZonesFolder then table.insert(excludeList, redZonesFolder) end
	
	local spawnedEnemies = Workspace:FindFirstChild("SpawnedEnemies")
	if spawnedEnemies then table.insert(excludeList, spawnedEnemies) end
	
	terrainRaycastParams.FilterDescendantsInstances = excludeList
end

-- Single raycast to find terrain height
local function raycastTerrainHeight(x, z, fallbackY)
	local rayOrigin = Vector3.new(x, 500, z)
	local rayDirection = Vector3.new(0, -1000, 0)
	
	local raycastResult = Workspace:Raycast(rayOrigin, rayDirection, terrainRaycastParams)
	
	if raycastResult then
		return raycastResult.Position.Y
	else
		return fallbackY or 0
	end
end

-- ROBUST terrain height sampling: samples multiple points and returns the LOWEST
-- This ensures formations are never floating, even on slopes
local function getTerrainHeightRobust(x, z, fallbackY, footprintRadius)
	footprintRadius = footprintRadius or CONFIG.FootprintRadius or 8
	
	updateTerrainRaycastFilter()
	
	-- Sample center point
	local centerY = raycastTerrainHeight(x, z, fallbackY)
	local lowestY = centerY
	
	-- Sample 8 points around the footprint (like a compass rose)
	local sampleOffsets = {
		{1, 0},   -- East
		{-1, 0},  -- West
		{0, 1},   -- North
		{0, -1},  -- South
		{0.7, 0.7},   -- NE
		{-0.7, 0.7},  -- NW
		{0.7, -0.7},  -- SE
		{-0.7, -0.7}, -- SW
	}
	
	for _, offset in ipairs(sampleOffsets) do
		local sampleX = x + offset[1] * footprintRadius
		local sampleZ = z + offset[2] * footprintRadius
		local sampleY = raycastTerrainHeight(sampleX, sampleZ, fallbackY)
		
		if sampleY < lowestY then
			lowestY = sampleY
		end
	end
	
	return lowestY
end

-- Legacy single-point function (kept for compatibility)
local function getTerrainHeight(x, z, fallbackY)
	updateTerrainRaycastFilter()
	return raycastTerrainHeight(x, z, fallbackY)
end

local function generateFormationPositions(baseplateInfo, count)
	local positions = {}
	local treePositions = getTreePositions()
	local attempts = 0
	local maxAttempts = count * 30
	
	local halfX = baseplateInfo.size.X / 2 - CONFIG.EdgePadding
	local halfZ = baseplateInfo.size.Z / 2 - CONFIG.EdgePadding
	
	print(string.format("[FormationService] Generating %d formation positions in area %.0fx%.0f centered at (%.0f, %.0f)", 
		count, halfX * 2, halfZ * 2, baseplateInfo.position.X, baseplateInfo.position.Z))
	
	while #positions < count and attempts < maxAttempts do
		attempts += 1
		
		local x = baseplateInfo.position.X + (math.random() - 0.5) * halfX * 2
		local z = baseplateInfo.position.Z + (math.random() - 0.5) * halfZ * 2
		
		-- ROBUST: Sample terrain at multiple points around footprint and use LOWEST
		-- This prevents floating on slopes (formations are larger so use bigger footprint)
		local lowestTerrainY = getTerrainHeightRobust(x, z, baseplateInfo.topY, CONFIG.FootprintRadius)
		
		-- Calculate embed depth with variation for natural look
		local embedVariation = math.random() * (CONFIG.TerrainEmbedMax - CONFIG.TerrainEmbedMin)
		local embedDepth = CONFIG.TerrainEmbedMin + embedVariation
		
		-- Final Y position: lowest terrain point minus embed depth
		local finalY = lowestTerrainY - embedDepth
		local newPos = Vector3.new(x, finalY, z)
		
		-- Check spacing from other formations
		if isValidPosition(newPos, positions, CONFIG.MinSpacing) then
			-- Check spacing from trees
			if isValidPosition(newPos, treePositions, CONFIG.TreeAvoidDistance) then
				table.insert(positions, newPos)
			end
		end
	end
	
	print(string.format("[FormationService] Generated %d formation positions after %d attempts", #positions, attempts))
	return positions
end

-- Clean up formations that are too close to reserved cells
local function cleanupFormationsNearReservedCells(self)
	local ReservedZoneService = nil
	local GridService = nil
	
	pcall(function()
		ReservedZoneService = Knit.GetService("ReservedZoneService")
		GridService = Knit.GetService("GridService")
	end)
	
	if not ReservedZoneService or not GridService then
		return
	end
	
	-- Collect reserved cells only from Building zones (not Radiation zones)
	local allReservedCells = {}
	local zones = ReservedZoneService:GetZones()
	if zones then
		local buildingZone = zones["Building"]
		if buildingZone and buildingZone.cells then
			for _, cell in ipairs(buildingZone.cells) do
				table.insert(allReservedCells, cell)
			end
		end
	end
	
	if #allReservedCells == 0 then
		return
	end
	
	-- Calculate the center of the reserved area
	local cellPositions = {}
	for _, cell in ipairs(allReservedCells) do
		local cellPos = GridService:GridToWorld(cell.x, cell.z)
		table.insert(cellPositions, cellPos)
	end
	
	-- Get the center of the reserved area (average of all cell centers)
	local centerX, centerZ = 0, 0
	for _, pos in ipairs(cellPositions) do
		centerX = centerX + pos.X
		centerZ = centerZ + pos.Z
	end
	centerX = centerX / #cellPositions
	centerZ = centerZ / #cellPositions
	
	-- Calculate radius: distance from center to farthest corner of 2x2 block
	-- For a 2x2 block, the farthest corner is at distance: cellSize * sqrt(2)
	local cellSize = GridService:GetCellSize()
	local reservedRadius = cellSize * math.sqrt(2)  -- Distance to corner
	local bufferDistance = 5  -- Additional buffer distance in studs
	local totalRadius = reservedRadius + bufferDistance
	
	local removedCount = 0
	local formationsToKeep = {}
	
	for _, formation in ipairs(self.formations) do
		if formation and formation.Parent then
			local formationPos = formation:GetPivot().Position
			local distance = math.sqrt((formationPos.X - centerX)^2 + (formationPos.Z - centerZ)^2)
			
			if distance < totalRadius then
				-- Formation is too close to reserved area, remove it
				formation:Destroy()
				removedCount = removedCount + 1
			else
				table.insert(formationsToKeep, formation)
			end
		else
			-- Keep invalid formations in the list (they'll be cleaned up elsewhere)
			table.insert(formationsToKeep, formation)
		end
	end
	
	self.formations = formationsToKeep
	
	if removedCount > 0 then
		print(string.format("[FormationService] Removed %d formations within %.1f studs of reserved area", 
			removedCount, totalRadius))
	end
end

local function generateFormations(self)
	local startTime = tick()
	
	local LoadingService = nil
	pcall(function()
		LoadingService = Knit.GetService("LoadingService")
	end)
	
	local function reportProgress(current, total, message)
		if LoadingService then
			LoadingService:ReportProgress("FormationService", current, total, message or "Creating formations")
		end
	end
	
	reportProgress(0, 100, "Preparing terrain")
	
	clearFormations()
	local folder = getFormationFolder()
	
	local baseplateInfo = getBaseplateInfo()
	if not baseplateInfo then
		warn("[FormationService] No Baseplate found!")
		return
	end
	
	reportProgress(5, 100, "Finding placement positions")
	
	local positions = generateFormationPositions(baseplateInfo, CONFIG.FormationCount)
	
	reportProgress(15, 100, "Generating formations")
	
	local totalFormations = #positions
	local batchSize = 10
	
	for i, pos in ipairs(positions) do
		local formation = createFormation(pos, folder)
		table.insert(self.formations, formation)
		
		if i % batchSize == 0 then
			local progress = 15 + (i / totalFormations) * 80
			reportProgress(math.floor(progress), 100, string.format("Creating formations (%d/%d)", i, totalFormations))
			task.wait()
		end
	end
	
	local elapsed = tick() - startTime
	print(string.format("[FormationService] Generated %d formations in %.2fs", #positions, elapsed))
	
	-- Clean up formations near reserved cells
	cleanupFormationsNearReservedCells(self)
	
	reportProgress(100, 100, "Terrain complete")
	
	if LoadingService then
		LoadingService:MarkStepComplete("FormationService")
	end
end

-- === KNIT LIFECYCLE ===

function FormationService:KnitInit()
	print("[FormationService] Initializing...")
end

function FormationService:KnitStart()
	print("[FormationService] Starting...")
	
	-- Only auto-generate if _autoStart is true (legacy mode)
	-- WorldInitService will call GenerateFormationsWithBaseplates() instead
	if self._autoStart then
		-- Get LoadingService to wait for ReservedZoneService
		local LoadingService = nil
		pcall(function()
			LoadingService = Knit.GetService("LoadingService")
		end)
		
		if LoadingService then
			-- Wait for ReservedZoneService to complete before generating formations
			print("[FormationService] Waiting for ReservedZoneService to complete...")
			LoadingService:OnStepComplete("ReservedZoneService", function()
				print("[FormationService] ReservedZoneService complete, generating formations...")
				generateFormations(self)
			end)
		else
			-- Fallback if LoadingService not available
			warn("[FormationService] LoadingService not found, generating formations immediately")
			generateFormations(self)
		end
	else
		print("[FormationService] Waiting for WorldInitService to generate formations...")
	end
end

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║               WORLDINITSERVICE INTEGRATION                                 ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

-- Generate formations using baseplate info from WorldInitService
function FormationService:GenerateFormationsWithBaseplates(baseplateInfo)
	if not baseplateInfo then
		warn("[FormationService] No baseplate info provided!")
		return false
	end
	
	print("[FormationService] Generating formations with baseplate info from WorldInitService...")
	self._baseplateInfo = baseplateInfo
	
	-- Create a fake baseplate info structure compatible with generateFormationPositions
	local fakeBaseplateInfo = {
		position = baseplateInfo.position,
		size = baseplateInfo.size,
		topY = baseplateInfo.topY,
	}
	
	local startTime = tick()
	
	local LoadingService = nil
	pcall(function()
		LoadingService = Knit.GetService("LoadingService")
	end)
	
	local function reportProgress(current, total, message)
		if LoadingService then
			LoadingService:ReportProgress("FormationService", current, total, message or "Creating formations")
		end
	end
	
	reportProgress(0, 100, "Preparing terrain")
	
	clearFormations()
	local folder = getFormationFolder()
	
	reportProgress(5, 100, "Finding placement positions")
	
	local positions = generateFormationPositions(fakeBaseplateInfo, CONFIG.FormationCount)
	
	reportProgress(15, 100, "Generating formations")
	
	local totalFormations = #positions
	local batchSize = 10
	
	for i, pos in ipairs(positions) do
		local formation = createFormation(pos, folder)
		table.insert(self.formations, formation)
		
		if i % batchSize == 0 then
			local progress = 15 + (i / totalFormations) * 80
			reportProgress(math.floor(progress), 100, string.format("Creating formations (%d/%d)", i, totalFormations))
			task.wait()
		end
	end
	
	local elapsed = tick() - startTime
	print(string.format("[FormationService] Generated %d formations in %.2fs", #positions, elapsed))
	
	-- Clean up formations near reserved cells
	cleanupFormationsNearReservedCells(self)
	
	reportProgress(100, 100, "Terrain complete")
	
	print("[FormationService] Formation generation complete")
	return true
end

-- === PUBLIC METHODS ===

function FormationService:RegenerateFormations()
	self.formations = {}
	generateFormations(self)
end

function FormationService:ClearFormations()
	self.formations = {}
	clearFormations()
end

function FormationService:SetFormationCount(count)
	CONFIG.FormationCount = math.clamp(count, 1, 200)
end

return FormationService

