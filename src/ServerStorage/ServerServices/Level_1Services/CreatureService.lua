local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local Knit = require(Packages.Knit)

local CreatureService = Knit.CreateService {
	Name = "CreatureService",
	Client = {},
	creatures = {},
}

-- === CONFIG ===
local CREATURE_CONFIG = {
	-- Spawning
	CreatureCount = 3,           -- Number of creatures
	SpawnSpread = 300,           -- How far apart to spawn creatures
	
	-- === PROCEDURAL VARIATION RANGES ===
	-- Each creature will have randomized stats within these ranges
	
	-- Height variation (how high body floats)
	BodyHeightMin = 120,
	BodyHeightMax = 220,
	
	-- Body size variation
	BodyWidthMin = 25,
	BodyWidthMax = 50,
	BodyLengthMin = 50,
	BodyLengthMax = 100,
	BodyDepthMin = 18,
	BodyDepthMax = 35,
	
	-- Body colors (will pick randomly and vary)
	BodyColors = {
		Color3.fromRGB(25, 25, 30),   -- Dark grey
		Color3.fromRGB(30, 25, 20),   -- Dark brown
		Color3.fromRGB(20, 25, 30),   -- Dark blue-grey
		Color3.fromRGB(35, 30, 25),   -- Muddy brown
		Color3.fromRGB(15, 20, 25),   -- Near black
	},
	BodyMaterial = Enum.Material.SmoothPlastic,
	
	-- Secondary body masses
	BodyMassCountMin = 2,
	BodyMassCountMax = 6,
	BodyMassSizeMin = 12,
	BodyMassSizeMax = 30,
	
	-- Leg variation
	LegCountMin = 4,             -- Minimum legs (must be even)
	LegCountMax = 8,             -- Maximum legs
	LegSegmentsMin = 6,
	LegSegmentsMax = 10,
	LegWidthMin = 3,
	LegWidthMax = 6,
	LegWidthTaper = 0.75,
	LegMaterial = Enum.Material.SmoothPlastic,
	
	-- Leg geometry
	LegSpreadAngle = 35,
	LegBendVariation = 12,
	LegRandomness = 8,
	JointBulge = 1.4,
	
	-- Head variation
	HeadEnabled = true,
	HeadSizeMin = 8,
	HeadSizeMax = 18,
	HeadLengthMin = 15,
	HeadLengthMax = 35,
	EyeCountMin = 2,
	EyeCountMax = 8,
	EyeSizeMin = 3,
	EyeSizeMax = 7,
	EyeColors = {
		Color3.fromRGB(180, 180, 160),  -- Pale
		Color3.fromRGB(200, 180, 150),  -- Yellowish
		Color3.fromRGB(160, 180, 180),  -- Blue-ish
		Color3.fromRGB(200, 160, 160),  -- Pinkish
		Color3.fromRGB(150, 200, 150),  -- Greenish
	},
	EyeGlow = true,
	
	-- Appendages variation
	AppendagesEnabled = true,
	AppendageCountMin = 4,
	AppendageCountMax = 12,
	AppendageLengthMin = 40,
	AppendageLengthMax = 80,
	AppendageSegmentsMin = 6,
	AppendageSegmentsMax = 14,
	AppendageWidthMin = 1.5,
	AppendageWidthMax = 3,
	
	-- PROCEDURAL WALKING
	WalkEnabled = true,
	WalkSpeedMin = 8,
	WalkSpeedMax = 16,
	StepDistanceMin = 30,
	StepDistanceMax = 50,
	StepHeightMin = 20,
	StepHeightMax = 35,
	StepDurationMin = 0.8,
	StepDurationMax = 1.3,
	StepOvershoot = 0.15,
	
	-- Body motion during walk
	BodyBobAmount = 6,
	BodySwayAmount = 4,
	BodyTiltAmount = 0.03,
	BodyLurchAmount = 3,
	
	-- Gait timing
	LegPhaseOffset = 0.15,
	StepCooldown = 0.3,
}

-- Generate randomized stats for a single creature
local function generateCreatureStats()
	local config = CREATURE_CONFIG
	
	return {
		BodyHeight = randomRange(config.BodyHeightMin, config.BodyHeightMax),
		BodyWidth = randomRange(config.BodyWidthMin, config.BodyWidthMax),
		BodyLength = randomRange(config.BodyLengthMin, config.BodyLengthMax),
		BodyDepth = randomRange(config.BodyDepthMin, config.BodyDepthMax),
		BodyColor = config.BodyColors[math.random(1, #config.BodyColors)],
		BodyMassCount = math.random(config.BodyMassCountMin, config.BodyMassCountMax),
		BodyMassSize = randomRange(config.BodyMassSizeMin, config.BodyMassSizeMax),
		
		LegCount = math.random(config.LegCountMin / 2, config.LegCountMax / 2) * 2,  -- Ensure even
		LegSegments = math.random(config.LegSegmentsMin, config.LegSegmentsMax),
		LegWidth = randomRange(config.LegWidthMin, config.LegWidthMax),
		LegColor = nil,  -- Will be derived from body color
		
		HeadSize = randomRange(config.HeadSizeMin, config.HeadSizeMax),
		HeadLength = randomRange(config.HeadLengthMin, config.HeadLengthMax),
		EyeCount = math.random(config.EyeCountMin, config.EyeCountMax),
		EyeSize = randomRange(config.EyeSizeMin, config.EyeSizeMax),
		EyeColor = config.EyeColors[math.random(1, #config.EyeColors)],
		
		AppendageCount = math.random(config.AppendageCountMin, config.AppendageCountMax),
		AppendageLength = randomRange(config.AppendageLengthMin, config.AppendageLengthMax),
		AppendageSegments = math.random(config.AppendageSegmentsMin, config.AppendageSegmentsMax),
		AppendageWidth = randomRange(config.AppendageWidthMin, config.AppendageWidthMax),
		
		WalkSpeed = randomRange(config.WalkSpeedMin, config.WalkSpeedMax),
		StepDistance = randomRange(config.StepDistanceMin, config.StepDistanceMax),
		StepHeight = randomRange(config.StepHeightMin, config.StepHeightMax),
		StepDuration = randomRange(config.StepDurationMin, config.StepDurationMax),
	}
end

local FOLDER_NAME = "Creatures"

-- === HELPERS ===

local function getCreatureFolder()
	local folder = Workspace:FindFirstChild(FOLDER_NAME)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = FOLDER_NAME
		folder.Parent = Workspace
	end
	return folder
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

-- === PART CREATION ===

local function createSegment(startPos, endPos, width, color, material, parent)
	local segment = Instance.new("Part")
	segment.Name = "Segment"
	
	local direction = endPos - startPos
	local length = direction.Magnitude
	local midPoint = startPos + direction / 2
	
	segment.Size = Vector3.new(width, width, length)
	segment.CFrame = CFrame.lookAt(startPos, endPos) * CFrame.new(0, 0, -length/2)
	segment.Color = color
	segment.Material = material
	segment.Anchored = true
	segment.CanCollide = false
	segment.Parent = parent
	
	return segment
end

local function createJoint(position, size, color, material, parent)
	local joint = Instance.new("Part")
	joint.Name = "Joint"
	joint.Shape = Enum.PartType.Ball
	joint.Size = Vector3.new(size, size, size)
	joint.Position = position
	joint.Color = color
	joint.Material = material
	joint.Anchored = true
	joint.CanCollide = false
	joint.Parent = parent
	
	return joint
end

-- === PROCEDURAL LEG SYSTEM ===

-- Improved IK solver with stable joint positioning
local function solveLegIK(hipPos, footPos, segmentCount, totalLength, legSide)
	local points = {}
	
	local toFoot = footPos - hipPos
	local distance = toFoot.Magnitude
	local segmentLength = totalLength / segmentCount
	
	-- Clamp distance to prevent over-extension
	local clampedDistance = math.min(distance, totalLength * 0.95)
	local adjustedFootPos = hipPos + toFoot.Unit * clampedDistance
	
	-- Calculate a stable "outward" direction for the knee bend
	-- Use the leg's side (left/right) to determine bend direction
	local forward = Vector3.new(0, 0, 1)
	local outward = Vector3.new(legSide or 1, 0, 0)  -- Bend outward based on which side
	
	-- Calculate how much slack we have (determines bend amount)
	local slack = 1 - (clampedDistance / totalLength)
	local bendMagnitude = slack * totalLength * 0.4  -- More slack = more bend
	
	-- Generate points with a smooth parabolic curve
	for i = 0, segmentCount do
		local t = i / segmentCount
		
		-- Base position along straight line
		local basePos = hipPos:Lerp(adjustedFootPos, t)
		
		-- Parabolic bend curve (peaks at middle, zero at ends)
		-- Using smoothstep-like curve for smoother transitions at joints
		local bendCurve = 4 * t * (1 - t)  -- Parabola peaking at t=0.5
		
		-- Upper joints (near hip) should be more stable
		-- Apply less bend to first 2 segments
		local stabilityFactor = 1
		if i <= 2 then
			stabilityFactor = i / 2  -- Gradually increase bend from hip
		end
		
		local bendAmount = bendMagnitude * bendCurve * stabilityFactor
		
		-- Bend outward (away from body) and slightly backward
		local bendOffset = outward * bendAmount + Vector3.new(0, bendAmount * 0.2, -bendAmount * 0.1)
		
		points[i + 1] = basePos + bendOffset
	end
	
	-- FABRIK iterations with damping for stability
	local damping = 0.8  -- Prevents overshooting
	
	for iteration = 1, 8 do
		-- Backward pass (from foot to hip)
		points[segmentCount + 1] = adjustedFootPos
		for i = segmentCount, 1, -1 do
			local toParent = points[i] - points[i + 1]
			local dir = toParent.Magnitude > 0.001 and toParent.Unit or Vector3.yAxis
			local targetPos = points[i + 1] + dir * segmentLength
			points[i] = points[i]:Lerp(targetPos, damping)
		end
		
		-- Forward pass (from hip to foot)
		points[1] = hipPos
		for i = 1, segmentCount do
			local toChild = points[i + 1] - points[i]
			local dir = toChild.Magnitude > 0.001 and toChild.Unit or -Vector3.yAxis
			local targetPos = points[i] + dir * segmentLength
			points[i + 1] = points[i + 1]:Lerp(targetPos, damping)
		end
	end
	
	-- Final constraint: ensure hip and foot are exactly correct
	points[1] = hipPos
	points[segmentCount + 1] = adjustedFootPos
	
	return points
end

-- Create leg with stored references for animation
local function createLeg(hipPos, footPos, legIndex, legSide, parent, legData)
	local config = CREATURE_CONFIG
	
	local totalLength = config.BodyHeight * 1.2
	local points = solveLegIK(hipPos, footPos, config.LegSegments, totalLength, legSide)
	
	local segments = {}
	local joints = {}
	local currentWidth = config.LegWidth
	
	for i = 1, config.LegSegments do
		local startPos = points[i]
		local endPos = points[i + 1]
		
		-- Create joint
		local jointSize = currentWidth * config.JointBulge
		local joint = createJoint(startPos, jointSize, config.LegColor, config.LegMaterial, parent)
		table.insert(joints, joint)
		
		-- Create segment
		local segment = createSegment(startPos, endPos, currentWidth, config.LegColor, config.LegMaterial, parent)
		table.insert(segments, segment)
		
		currentWidth = math.max(currentWidth * config.LegWidthTaper, 1)
	end
	
	-- Foot joint
	local footJoint = createJoint(footPos, currentWidth * config.JointBulge * 1.5, config.LegColor, config.LegMaterial, parent)
	table.insert(joints, footJoint)
	
	-- Store leg data for animation
	legData.segments = segments
	legData.joints = joints
	legData.totalLength = totalLength
	legData.legSide = legSide  -- Store side for IK updates
	
	return segments, joints
end

-- Update leg visuals based on new hip and foot positions
local function updateLeg(legData, hipPos, footPos)
	local config = CREATURE_CONFIG
	local points = solveLegIK(hipPos, footPos, config.LegSegments, legData.totalLength, legData.legSide)
	
	-- Smoothly interpolate joint positions to prevent jitter
	local smoothing = 0.4  -- Lower = smoother but laggier
	
	-- Update joints with smoothing
	for i, joint in ipairs(legData.joints) do
		if i <= #points then
			local targetPos = points[i]
			-- Apply more smoothing to joints near hip (first few joints)
			local jointSmoothing = smoothing
			if i <= 3 then
				jointSmoothing = smoothing * 0.5  -- Extra smooth for hip area
			end
			joint.Position = joint.Position:Lerp(targetPos, jointSmoothing)
		end
	end
	
	-- Update segments based on smoothed joint positions
	for i, segment in ipairs(legData.segments) do
		local startJoint = legData.joints[i]
		local endJoint = legData.joints[i + 1]
		
		if startJoint and endJoint then
			local startPos = startJoint.Position
			local endPos = endJoint.Position
			local direction = endPos - startPos
			local length = direction.Magnitude
			
			if length > 0.1 then
				segment.Size = Vector3.new(segment.Size.X, segment.Size.Y, length)
				segment.CFrame = CFrame.lookAt(startPos, endPos) * CFrame.new(0, 0, -length/2)
			end
		end
	end
end

-- Create leg using creature-specific stats
local function createLegWithStats(hipPos, footPos, legIndex, legSide, stats, parent, legData)
	local config = CREATURE_CONFIG
	
	local totalLength = stats.BodyHeight * 1.2
	local points = solveLegIK(hipPos, footPos, stats.LegSegments, totalLength, legSide)
	
	local segments = {}
	local joints = {}
	local currentWidth = stats.LegWidth
	
	for i = 1, stats.LegSegments do
		local startPos = points[i]
		local endPos = points[i + 1]
		
		-- Create joint
		local jointSize = currentWidth * config.JointBulge
		local joint = createJoint(startPos, jointSize, stats.LegColor, config.LegMaterial, parent)
		table.insert(joints, joint)
		
		-- Create segment
		local segment = createSegment(startPos, endPos, currentWidth, stats.LegColor, config.LegMaterial, parent)
		table.insert(segments, segment)
		
		currentWidth = math.max(currentWidth * config.LegWidthTaper, 1)
	end
	
	-- Foot joint
	local footJoint = createJoint(footPos, currentWidth * config.JointBulge * 1.5, stats.LegColor, config.LegMaterial, parent)
	table.insert(joints, footJoint)
	
	-- Store leg data for animation
	legData.segments = segments
	legData.joints = joints
	legData.totalLength = totalLength
	legData.legSide = legSide
	legData.legSegments = stats.LegSegments  -- Store for IK updates
	
	return segments, joints
end

-- Update leg visuals using creature-specific segment count
local function updateLegWithStats(legData, hipPos, footPos)
	local segmentCount = legData.legSegments or CREATURE_CONFIG.LegSegments
	local points = solveLegIK(hipPos, footPos, segmentCount, legData.totalLength, legData.legSide)
	
	local smoothing = 0.4
	
	for i, joint in ipairs(legData.joints) do
		if i <= #points then
			local targetPos = points[i]
			local jointSmoothing = smoothing
			if i <= 3 then
				jointSmoothing = smoothing * 0.5
			end
			joint.Position = joint.Position:Lerp(targetPos, jointSmoothing)
		end
	end
	
	for i, segment in ipairs(legData.segments) do
		local startJoint = legData.joints[i]
		local endJoint = legData.joints[i + 1]
		
		if startJoint and endJoint then
			local startPos = startJoint.Position
			local endPos = endJoint.Position
			local direction = endPos - startPos
			local length = direction.Magnitude
			
			if length > 0.1 then
				segment.Size = Vector3.new(segment.Size.X, segment.Size.Y, length)
				segment.CFrame = CFrame.lookAt(startPos, endPos) * CFrame.new(0, 0, -length/2)
			end
		end
	end
end

-- === TRAILING APPENDAGE GENERATION ===

local function generateAppendageWithStats(startPos, stats, parent, allParts)
	local config = CREATURE_CONFIG
	local currentPos = startPos
	local currentDir = CFrame.new(Vector3.zero, Vector3.new(0, -1, 0))  -- Point down
	local width = stats.AppendageWidth
	
	for seg = 1, stats.AppendageSegments do
		local segLength = stats.AppendageLength / stats.AppendageSegments
		
		-- Gentle swaying motion
		local randomX = math.rad((math.random() - 0.5) * 20)
		local randomZ = math.rad((math.random() - 0.5) * 20)
		
		currentDir = currentDir * CFrame.Angles(randomX, 0, randomZ)
		
		local endPos = currentPos + currentDir.LookVector * segLength
		
		-- Create segment
		local segment = createSegment(currentPos, endPos, width, varyColor(stats.LegColor, 15), config.LegMaterial, parent)
		table.insert(allParts, segment)
		
		-- Occasional joint bulge
		if seg % 2 == 0 then
			local joint = createJoint(currentPos, width * 1.3, stats.LegColor, config.LegMaterial, parent)
			table.insert(allParts, joint)
		end
		
		currentPos = endPos
		width = math.max(width * 0.85, 0.5)
	end
end

local function generateAppendage(startPos, parent, allParts)
	local config = CREATURE_CONFIG
	local currentPos = startPos
	local currentDir = CFrame.new(Vector3.zero, Vector3.new(0, -1, 0))  -- Point down
	local width = config.AppendageWidthMax
	
	for seg = 1, config.AppendageSegmentsMax do
		local segLength = config.AppendageLengthMax / config.AppendageSegmentsMax
		
		-- Gentle swaying motion
		local randomX = math.rad((math.random() - 0.5) * 20)
		local randomZ = math.rad((math.random() - 0.5) * 20)
		
		currentDir = currentDir * CFrame.Angles(randomX, 0, randomZ)
		
		local endPos = currentPos + currentDir.LookVector * segLength
		
		-- Create segment
		local segment = createSegment(currentPos, endPos, width, varyColor(config.LegColor, 15), config.LegMaterial, parent)
		table.insert(allParts, segment)
		
		-- Occasional joint bulge
		if seg % 2 == 0 then
			local joint = createJoint(currentPos, width * 1.3, config.LegColor, config.LegMaterial, parent)
			table.insert(allParts, joint)
		end
		
		currentPos = endPos
		width = math.max(width * 0.85, 0.5)
	end
end

-- === BODY & HEAD (Leviathan style) ===

local function createBody(position, stats, parent, allParts)
	local config = CREATURE_CONFIG
	
	-- Main body (massive, elongated)
	local body = Instance.new("Part")
	body.Name = "Body"
	body.Size = Vector3.new(stats.BodyWidth, stats.BodyDepth, stats.BodyLength)
	body.Position = position
	body.Color = stats.BodyColor
	body.Material = config.BodyMaterial
	body.Anchored = true
	body.CanCollide = false
	body.Parent = parent
	
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = body
	
	table.insert(allParts, body)
	
	-- Add lumpy secondary masses for organic look
	for i = 1, stats.BodyMassCount do
		local massSize = stats.BodyMassSize * (0.6 + math.random() * 0.8)
		local xOffset = (math.random() - 0.5) * stats.BodyWidth * 0.6
		local yOffset = (math.random() - 0.5) * stats.BodyDepth * 0.4
		local zOffset = (math.random() - 0.5) * stats.BodyLength * 0.7
		
		local mass = Instance.new("Part")
		mass.Name = "BodyMass"
		mass.Shape = Enum.PartType.Ball
		mass.Size = Vector3.new(massSize, massSize * 0.7, massSize * 1.2)
		mass.Position = position + Vector3.new(xOffset, yOffset, zOffset)
		mass.Color = varyColor(stats.BodyColor, 10)
		mass.Material = config.BodyMaterial
		mass.Anchored = true
		mass.CanCollide = false
		mass.Parent = parent
		
		table.insert(allParts, mass)
	end
	
	return body
end

local function createHead(bodyPos, stats, parent, allParts)
	local config = CREATURE_CONFIG
	
	-- Head hangs down and forward from body
	local headPos = bodyPos + Vector3.new(0, -stats.BodyDepth * 0.3, stats.BodyLength * 0.5 + stats.HeadLength * 0.4)
	
	-- Elongated, alien head
	local head = Instance.new("Part")
	head.Name = "Head"
	head.Size = Vector3.new(stats.HeadSize, stats.HeadSize * 0.8, stats.HeadLength)
	head.Position = headPos
	head.Color = stats.BodyColor
	head.Material = config.BodyMaterial
	head.Anchored = true
	head.CanCollide = false
	head.Parent = parent
	
	local headMesh = Instance.new("SpecialMesh")
	headMesh.MeshType = Enum.MeshType.Sphere
	headMesh.Parent = head
	
	table.insert(allParts, head)
	
	-- Pale, unsettling eyes on sides of head
	for i = 1, stats.EyeCount do
		local side = (i % 2 == 0) and 1 or -1
		local zOffset = ((i - 1) / stats.EyeCount - 0.3) * stats.HeadLength * 0.4
		
		local eyePos = headPos + Vector3.new(
			side * stats.HeadSize * 0.45,
			stats.HeadSize * 0.1,
			zOffset
		)
		
		local eye = Instance.new("Part")
		eye.Name = "Eye"
		eye.Shape = Enum.PartType.Ball
		eye.Size = Vector3.new(stats.EyeSize, stats.EyeSize * 0.6, stats.EyeSize * 0.8)
		eye.Position = eyePos
		eye.Color = stats.EyeColor
		eye.Material = config.EyeGlow and Enum.Material.Neon or Enum.Material.SmoothPlastic
		eye.Anchored = true
		eye.CanCollide = false
		eye.Parent = parent
		
		table.insert(allParts, eye)
	end
	
	return head
end

-- === CREATURE ASSEMBLY ===

local function createCreature(position, groundY, folder, stats)
	local config = CREATURE_CONFIG
	
	-- Generate stats if not provided
	stats = stats or generateCreatureStats()
	
	-- Derive leg color from body color (slightly darker)
	stats.LegColor = Color3.new(
		stats.BodyColor.R * 0.8,
		stats.BodyColor.G * 0.8,
		stats.BodyColor.B * 0.8
	)
	
	local creatureModel = Instance.new("Model")
	creatureModel.Name = "Leviathan_" .. math.random(1000, 9999)
	creatureModel.Parent = folder
	
	local allParts = {}
	local legs = {}
	local bodyParts = {}  -- Track body parts that move with the body
	
	-- Create body (high above ground)
	local body = createBody(position, stats, creatureModel, allParts)
	table.insert(bodyParts, body)
	
	-- Track body masses for movement
	for _, part in ipairs(allParts) do
		if part.Name == "BodyMass" then
			table.insert(bodyParts, part)
		end
	end
	
	-- Create head
	local headParts = {}
	if config.HeadEnabled then
		createHead(position, stats, creatureModel, allParts)
		for _, part in ipairs(allParts) do
			if part.Name == "Head" or part.Name == "Eye" then
				table.insert(headParts, part)
			end
		end
	end
	
	-- Create legs that reach down to the ground
	local legsPerSide = stats.LegCount / 2
	
	for i = 1, stats.LegCount do
		local side = (i <= legsPerSide) and 1 or -1  -- Left or right
		local legIndexOnSide = ((i - 1) % legsPerSide) + 1
		
		-- Position along body where leg attaches (relative to body center)
		local zOffset = ((legIndexOnSide - 1) / math.max(legsPerSide - 1, 1) - 0.5) * stats.BodyLength * 0.7
		local xOffset = side * stats.BodyWidth * 0.45
		
		local hipOffset = Vector3.new(xOffset, -stats.BodyDepth * 0.3, zOffset)
		local hipPos = position + hipOffset
		
		-- Calculate initial foot position on ground
		local spreadDistance = stats.BodyHeight * 0.3
		local footX = position.X + side * (stats.BodyWidth * 0.5 + spreadDistance)
		local footZ = position.Z + zOffset * 1.3
		local footPos = Vector3.new(footX, groundY, footZ)
		
		-- Create leg data structure with phase offset for staggered stepping
		local legIndexInGroup = math.floor((i - 1) / 2)
		local phaseOffset = legIndexInGroup * config.LegPhaseOffset
		
		local legData = {
			index = i,
			side = side,
			hipOffset = hipOffset,
			footPos = footPos,
			targetFootPos = footPos,
			restFootOffset = Vector3.new(side * spreadDistance, 0, zOffset * 1.3),
			isStepping = false,
			stepProgress = 0,
			stepStartPos = footPos,
			gaitGroup = (i % 2),  -- Alternating gait groups (0 or 1)
			phaseOffset = phaseOffset,  -- Stagger within group
			lastStepTime = -10,  -- When this leg last stepped
			stepSpeed = 1 + (math.random() - 0.5) * 0.2,  -- Slight speed variation
		}
		
		-- Update createLeg to use stats for segments/width
		legData.totalLength = stats.BodyHeight * 1.2
		legData.legSide = side
		
		createLegWithStats(hipPos, footPos, i, side, stats, creatureModel, legData)
		table.insert(legs, legData)
	end
	
	-- Create trailing appendages
	if config.AppendagesEnabled then
		for i = 1, stats.AppendageCount do
			local angle = (i / stats.AppendageCount) * math.pi * 2
			local radius = stats.BodyWidth * 0.35
			local offset = Vector3.new(
				math.cos(angle) * radius,
				-stats.BodyDepth * 0.35,
				math.sin(angle) * radius * (stats.BodyLength / stats.BodyWidth) * 0.8
			)
			generateAppendageWithStats(position + offset, stats, creatureModel, allParts)
		end
	end
	
	creatureModel.PrimaryPart = body
	
	-- Store for animation (including creature-specific stats)
	return {
		model = creatureModel,
		parts = allParts,
		bodyParts = bodyParts,
		headParts = headParts,
		body = body,
		legs = legs,
		position = position,
		groundY = groundY,
		facing = Vector3.new(0, 0, 1),  -- Forward direction
		velocity = Vector3.zero,
		-- Body motion state
		bodySway = 0,
		bodyTilt = 0,
		bodyLurch = 0,
		-- Creature-specific stats for walk animation
		stats = stats,
	}
end

-- === PROCEDURAL WALKING ANIMATION ===

-- Easing functions for natural motion
local function easeInOutCubic(t)
	if t < 0.5 then
		return 4 * t * t * t
	else
		return 1 - (-2 * t + 2)^3 / 2
	end
end

local function easeOutBack(t)
	-- Slight overshoot then settle
	local c1 = 1.70158
	local c3 = c1 + 1
	return 1 + c3 * (t - 1)^3 + c1 * (t - 1)^2
end

local function easeOutElastic(t)
	if t == 0 or t == 1 then return t end
	return 2^(-10 * t) * math.sin((t * 10 - 0.75) * (2 * math.pi) / 3) + 1
end

local function updateCreatureWalk(creature, deltaTime)
	local config = CREATURE_CONFIG
	local stats = creature.stats or {}  -- Use creature-specific stats
	local currentTime = tick()
	
	if not creature.body or not creature.body.Parent then return end
	
	-- Move creature forward using creature-specific speed
	local moveDir = creature.facing
	local walkSpeed = stats.WalkSpeed or config.WalkSpeedMin
	local moveAmount = walkSpeed * deltaTime
	creature.position = creature.position + moveDir * moveAmount
	
	-- Count stepping legs and calculate weight distribution
	local steppingLegs = {[0] = {}, [1] = {}}
	local groundedLegs = {[0] = {}, [1] = {}}
	local totalSteppingWeight = Vector3.zero
	local steppingCount = 0
	
	for _, leg in ipairs(creature.legs) do
		if leg.isStepping then
			table.insert(steppingLegs[leg.gaitGroup], leg)
			totalSteppingWeight = totalSteppingWeight + Vector3.new(leg.side, 0, 0)
			steppingCount = steppingCount + 1
		else
			table.insert(groundedLegs[leg.gaitGroup], leg)
		end
	end
	
	-- Calculate body motion based on gait
	local walkPhase = currentTime * 1.5  -- Slow, deliberate pace
	
	-- Vertical bob - double frequency (bob on each step)
	local bobOffset = math.sin(walkPhase * 2) * config.BodyBobAmount
	
	-- Side sway - shifts toward grounded legs
	local swayTarget = 0
	if steppingCount > 0 then
		swayTarget = -totalSteppingWeight.X * config.BodySwayAmount  -- Lean away from stepping legs
	end
	creature.bodySway = creature.bodySway or 0
	creature.bodySway = creature.bodySway + (swayTarget - creature.bodySway) * deltaTime * 3
	
	-- Forward lurch - subtle forward motion with each step cycle
	local lurchOffset = math.sin(walkPhase) * config.BodyLurchAmount
	
	-- Body tilt based on which legs are stepping
	creature.bodyTilt = creature.bodyTilt or 0
	local tiltTarget = totalSteppingWeight.X * config.BodyTiltAmount
	creature.bodyTilt = creature.bodyTilt + (tiltTarget - creature.bodyTilt) * deltaTime * 2
	
	-- Compose final body position
	local bodyOffset3D = Vector3.new(
		creature.bodySway,
		bobOffset,
		lurchOffset
	)
	local bodyPos = creature.position + bodyOffset3D
	local bodyMovement = bodyPos - creature.body.Position
	
	-- Apply body position with rotation
	creature.body.CFrame = CFrame.new(bodyPos) * CFrame.Angles(0, 0, creature.bodyTilt)
	
	-- Move body masses with body
	for _, part in ipairs(creature.bodyParts) do
		if part ~= creature.body then
			part.Position = part.Position + bodyMovement
		end
	end
	
	-- Move head parts with body (slight lag for organic feel)
	for _, part in ipairs(creature.headParts) do
		part.Position = part.Position + bodyMovement * 0.95
	end
	
	-- Determine which gait group should step next
	local group0Stepping = #steppingLegs[0] > 0
	local group1Stepping = #steppingLegs[1] > 0
	
	-- Update each leg
	for _, leg in ipairs(creature.legs) do
		local hipPos = creature.position + leg.hipOffset + bodyOffset3D
		
		-- Calculate ideal foot position (where foot should rest relative to body)
		local idealFootPos = Vector3.new(
			creature.position.X + leg.restFootOffset.X,
			creature.groundY,
			creature.position.Z + leg.restFootOffset.Z
		)
		
		-- Check if foot needs to step
		local distanceFromIdeal = (leg.footPos - idealFootPos).Magnitude
		local timeSinceStep = currentTime - leg.lastStepTime
		local cooldownMet = timeSinceStep > config.StepCooldown
		
		-- Determine if this leg can step
		-- Alternating tripod gait: only step if other group is grounded
		local otherGroup = (leg.gaitGroup + 1) % 2
		local otherGroupGrounded = #steppingLegs[otherGroup] == 0
		
		-- Add phase offset delay for staggered stepping within group
		local phaseReady = timeSinceStep > (config.StepCooldown + leg.phaseOffset)
		
		-- Use creature-specific step distance
		local stepDistance = stats.StepDistance or config.StepDistanceMin
		
		local shouldStep = not leg.isStepping 
			and distanceFromIdeal > stepDistance 
			and cooldownMet 
			and phaseReady
			and (otherGroupGrounded or leg.gaitGroup == 0 and group0Stepping or leg.gaitGroup == 1 and group1Stepping)
		
		if shouldStep then
			-- Start stepping
			leg.isStepping = true
			leg.stepProgress = 0
			leg.stepStartPos = leg.footPos
			leg.lastStepTime = currentTime
			
			-- Target ahead of ideal position (anticipate movement)
			local stepAhead = moveDir * stepDistance * 0.4
			leg.targetFootPos = idealFootPos + stepAhead
			leg.targetFootPos = Vector3.new(leg.targetFootPos.X, creature.groundY, leg.targetFootPos.Z)
			
			table.insert(steppingLegs[leg.gaitGroup], leg)
		end
		
		if leg.isStepping then
			-- Use creature-specific step duration
			local stepDuration = stats.StepDuration or config.StepDurationMin
			local stepHeight = stats.StepHeight or config.StepHeightMin
			
			-- Animate step with variable speed
			local stepSpeed = leg.stepSpeed or 1
			leg.stepProgress = leg.stepProgress + (deltaTime / stepDuration) * stepSpeed
			
			if leg.stepProgress >= 1 then
				-- Step complete
				leg.stepProgress = 1
				leg.isStepping = false
				leg.footPos = leg.targetFootPos
			else
				-- Smooth step animation with overshoot
				local t = leg.stepProgress
				
				-- Horizontal motion: ease in-out cubic for smooth acceleration
				local horizontalT = easeInOutCubic(t)
				
				-- Add slight overshoot at the end
				if t > 0.7 then
					local overshootPhase = (t - 0.7) / 0.3
					horizontalT = horizontalT + math.sin(overshootPhase * math.pi) * config.StepOvershoot * (1 - overshootPhase)
				end
				
				local groundPos = leg.stepStartPos:Lerp(leg.targetFootPos, math.min(horizontalT, 1))
				
				-- Vertical arc: asymmetric - quick lift, slower descent
				local arcT = t
				local arcHeight
				if arcT < 0.4 then
					-- Quick lift phase
					arcHeight = math.sin((arcT / 0.4) * math.pi * 0.5) * stepHeight
				else
					-- Slower descent phase
					arcHeight = math.cos(((arcT - 0.4) / 0.6) * math.pi * 0.5) * stepHeight
				end
				
				leg.footPos = groundPos + Vector3.new(0, arcHeight, 0)
			end
		end
		
		-- Update leg IK using creature-specific segment count
		updateLegWithStats(leg, hipPos, leg.footPos)
	end
end

local function animateCreatures(self)
	local config = CREATURE_CONFIG
	if not config.WalkEnabled then return end
	
	local lastTime = tick()
	
	RunService.Heartbeat:Connect(function()
		local currentTime = tick()
		local deltaTime = currentTime - lastTime
		lastTime = currentTime
		
		for _, creature in ipairs(self.creatures) do
			updateCreatureWalk(creature, deltaTime)
		end
	end)
end

-- === GENERATION ===

local function generateCreatures(self)
	local startTime = tick()
	local config = CREATURE_CONFIG
	
	local folder = getCreatureFolder()
	folder:ClearAllChildren()
	
	local baseplateInfo = getBaseplateInfo()
	if not baseplateInfo then
		warn("[CreatureService] No Baseplate found!")
		return
	end
	
	local groundY = baseplateInfo.topY
	local creatureCount = config.CreatureCount
	
	-- Spawn positions spread across the baseplate
	local spawnAngles = {}
	for i = 1, creatureCount do
		-- Distribute creatures around the edges, facing inward
		local angle = (i - 1) / creatureCount * math.pi * 2 + math.random() * 0.5
		table.insert(spawnAngles, angle)
	end
	
	for i = 1, creatureCount do
		-- Generate unique stats for this creature
		local stats = generateCreatureStats()
		
		-- Calculate spawn position (spread around the baseplate)
		local angle = spawnAngles[i]
		local spawnRadius = math.min(baseplateInfo.size.X, baseplateInfo.size.Z) * 0.35
		
		local x = baseplateInfo.position.X + math.cos(angle) * spawnRadius
		local z = baseplateInfo.position.Z + math.sin(angle) * spawnRadius
		local y = groundY + stats.BodyHeight  -- Use creature's specific height
		
		local position = Vector3.new(x, y, z)
		local creature = createCreature(position, groundY, folder, stats)
		
		-- Face toward center (or random direction)
		local facingAngle = angle + math.pi + (math.random() - 0.5) * 0.5  -- Mostly toward center
		creature.facing = Vector3.new(math.cos(facingAngle), 0, math.sin(facingAngle)).Unit
		
		table.insert(self.creatures, creature)
		
		-- Log creature stats
		print(string.format(
			"[CreatureService] Creature %d: Height=%.0f, Legs=%d, WalkSpeed=%.1f",
			i, stats.BodyHeight, stats.LegCount, stats.WalkSpeed
		))
		
		task.wait(0.5)  -- Stagger spawning for dramatic effect
	end
	
	local elapsed = tick() - startTime
	print(string.format("[CreatureService] Generated %d unique leviathans in %.2fs", creatureCount, elapsed))
	
	-- Start procedural walking animation
	animateCreatures(self)
end

-- === KNIT LIFECYCLE ===

function CreatureService:KnitInit()
	-- Nothing to init
end

function CreatureService:KnitStart()
	-- Small delay to ensure other services are ready
	task.delay(2, function()
		generateCreatures(self)
	end)
end

-- === PUBLIC METHODS ===

function CreatureService:RegenerateCreatures()
	self.creatures = {}
	generateCreatures(self)
end

function CreatureService:ClearCreatures()
	self.creatures = {}
	local folder = Workspace:FindFirstChild(FOLDER_NAME)
	if folder then
		folder:ClearAllChildren()
	end
end

function CreatureService:SetCreatureCount(count)
	CREATURE_CONFIG.CreatureCount = math.clamp(count, 1, 10)
end

return CreatureService

