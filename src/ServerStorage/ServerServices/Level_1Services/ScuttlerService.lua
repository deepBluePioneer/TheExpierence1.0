local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local Knit = require(Packages.Knit)

local ScuttlerService = Knit.CreateService {
	Name = "ScuttlerService",
	Client = {},
	scuttlers = {},
}

-- === CONFIG ===
local SCUTTLER_CONFIG = {
	-- Spawning (more of them!)
	ScuttlerCount = 15,
	SpawnRadius = 60,
	
	-- Body (tiny, Flood-like)
	BodyWidthMin = 0.6,
	BodyWidthMax = 1.0,
	BodyLengthMin = 0.8,
	BodyLengthMax = 1.4,
	BodyHeightMin = 0.4,
	BodyHeightMax = 0.7,
	BodyColors = {
		Color3.fromRGB(120, 100, 70),   -- Tan/flesh
		Color3.fromRGB(100, 90, 60),    -- Darker tan
		Color3.fromRGB(90, 80, 70),     -- Grey-brown
		Color3.fromRGB(110, 95, 65),    -- Pale flesh
		Color3.fromRGB(80, 70, 60),     -- Dark
	},
	
	-- Legs (tiny, fast, spindly)
	LegCount = 6,                -- 6 legs like an insect
	LegSegments = 2,             -- Fewer segments (tiny creature)
	LegWidthMin = 0.08,
	LegWidthMax = 0.12,
	LegWidthTaper = 0.7,
	LegMaterial = Enum.Material.SmoothPlastic,
	JointBulge = 1.2,
	
	-- Eyes (small, beady)
	EyeCount = 2,
	EyeSizeMin = 0.1,
	EyeSizeMax = 0.2,
	EyeColor = Color3.fromRGB(200, 255, 100),  -- Sickly yellow-green glow
	
	-- Movement (slower, creepy)
	MoveSpeed = 12,              -- Slower chase
	ChaseRange = 60,             -- Start chasing when player is this close
	LoseRange = 100,             -- Stop chasing when player is this far
	WanderSpeed = 6,             -- Slow wandering
	TurnSpeed = 8,               -- Moderate turning
	
	-- Step animation
	StepDistance = 1.0,
	StepHeight = 0.4,
	StepDuration = 0.06,         -- Moderate step speed
	
	-- Body motion
	BodyBobAmount = 0.1,
	BodyBobSpeed = 15,           -- Moderate bobbing
	
	-- Behavior
	AggroDelay = 0.3,
	IdleTime = 1.5,
	
	-- === ERRATIC MOVEMENT ===
	ErraticEnabled = true,
	WeaveAmount = 0.8,           -- How much they weave side to side
	WeaveSpeed = 3,              -- How fast they weave
	DirectionChangeInterval = 0.5, -- How often they slightly change direction
	DirectionChangeAmount = 45,  -- Max degrees to veer off course
	SurgeChance = 0.02,          -- Chance per frame to surge forward
	SurgeSpeedMultiplier = 2.0,  -- Speed multiplier during surge
	SurgeDuration = 0.3,         -- How long a surge lasts
	PauseChance = 0.01,          -- Chance to briefly pause
	PauseDuration = 0.2,         -- How long to pause
	
	-- === FLOCKING BEHAVIOR ===
	FlockingEnabled = true,
	SeparationWeight = 4.0,      -- STRONG separation (no overlapping!)
	AlignmentWeight = 0.6,       -- Moderate alignment
	CohesionWeight = 0.4,        -- Weak cohesion (don't bunch up too much)
	ChaseWeight = 2.0,           -- Chase player
	
	FlockRadius = 12,            -- How far to look for neighbors
	SeparationRadius = 4,        -- Larger minimum distance from neighbors
	MaxFlockSpeed = 15,          -- Slower max speed
}

local FOLDER_NAME = "Scuttlers"

-- === HELPERS ===

local function randomRange(min, max)
	return min + math.random() * (max - min)
end

local function varyColor(baseColor, variation)
	local r = math.clamp(baseColor.R * 255 + (math.random() - 0.5) * variation * 2, 0, 255)
	local g = math.clamp(baseColor.G * 255 + (math.random() - 0.5) * variation * 2, 0, 255)
	local b = math.clamp(baseColor.B * 255 + (math.random() - 0.5) * variation * 2, 0, 255)
	return Color3.fromRGB(r, g, b)
end

local function getScuttlerFolder()
	local folder = Workspace:FindFirstChild(FOLDER_NAME)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = FOLDER_NAME
		folder.Parent = Workspace
	end
	return folder
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

local function getNearestPlayer(position, maxRange)
	local nearest = nil
	local nearestDist = maxRange
	
	for _, player in ipairs(Players:GetPlayers()) do
		local character = player.Character
		if character then
			local hrp = character:FindFirstChild("HumanoidRootPart")
			if hrp then
				local dist = (hrp.Position - position).Magnitude
				if dist < nearestDist then
					nearest = player
					nearestDist = dist
				end
			end
		end
	end
	
	return nearest, nearestDist
end

-- === PART CREATION ===

local function createSegment(startPos, endPos, width, color, parent)
	local segment = Instance.new("Part")
	segment.Name = "LegSegment"
	
	local direction = endPos - startPos
	local length = direction.Magnitude
	
	segment.Size = Vector3.new(width, width, math.max(length, 0.1))
	segment.CFrame = CFrame.lookAt(startPos, endPos) * CFrame.new(0, 0, -length/2)
	segment.Color = color
	segment.Material = SCUTTLER_CONFIG.LegMaterial
	segment.Anchored = true
	segment.CanCollide = false
	segment.Parent = parent
	
	return segment
end

local function createJoint(position, size, color, parent)
	local joint = Instance.new("Part")
	joint.Name = "Joint"
	joint.Shape = Enum.PartType.Ball
	joint.Size = Vector3.new(size, size, size)
	joint.Position = position
	joint.Color = color
	joint.Material = SCUTTLER_CONFIG.LegMaterial
	joint.Anchored = true
	joint.CanCollide = false
	joint.Parent = parent
	
	return joint
end

-- === IK SOLVER ===

local function solveLegIK(hipPos, footPos, segmentCount, totalLength, bendDir)
	local points = {}
	local toFoot = footPos - hipPos
	local distance = math.min(toFoot.Magnitude, totalLength * 0.95)
	local adjustedFoot = hipPos + toFoot.Unit * distance
	
	-- Simple 2-bone IK approximation
	local slack = 1 - (distance / totalLength)
	local bendAmount = slack * totalLength * 0.4
	
	local segmentLength = totalLength / segmentCount
	
	for i = 0, segmentCount do
		local t = i / segmentCount
		local basePos = hipPos:Lerp(adjustedFoot, t)
		
		-- Parabolic bend
		local bendCurve = 4 * t * (1 - t)
		local bendOffset = bendDir * bendAmount * bendCurve
		
		points[i + 1] = basePos + bendOffset
	end
	
	-- Simple FABRIK pass
	for iter = 1, 3 do
		points[segmentCount + 1] = adjustedFoot
		for i = segmentCount, 1, -1 do
			local dir = (points[i] - points[i + 1])
			dir = dir.Magnitude > 0.01 and dir.Unit or Vector3.yAxis
			points[i] = points[i + 1] + dir * segmentLength
		end
		
		points[1] = hipPos
		for i = 1, segmentCount do
			local dir = (points[i + 1] - points[i])
			dir = dir.Magnitude > 0.01 and dir.Unit or -Vector3.yAxis
			points[i + 1] = points[i] + dir * segmentLength
		end
	end
	
	return points
end

-- === LEG CREATION ===

local function createLeg(hipPos, footPos, legIndex, side, stats, parent, legData)
	local config = SCUTTLER_CONFIG
	
	local totalLength = stats.BodyHeight * 2.5
	local bendDir = Vector3.new(side, 0.5, 0).Unit
	local points = solveLegIK(hipPos, footPos, config.LegSegments, totalLength, bendDir)
	
	local segments = {}
	local joints = {}
	local width = stats.LegWidth
	
	for i = 1, config.LegSegments do
		local startPos = points[i]
		local endPos = points[i + 1]
		
		local jointSize = width * config.JointBulge
		local joint = createJoint(startPos, jointSize, stats.LegColor, parent)
		table.insert(joints, joint)
		
		local segment = createSegment(startPos, endPos, width, stats.LegColor, parent)
		table.insert(segments, segment)
		
		width = math.max(width * config.LegWidthTaper, 0.1)
	end
	
	-- Foot
	local foot = createJoint(footPos, width * config.JointBulge, stats.LegColor, parent)
	table.insert(joints, foot)
	
	legData.segments = segments
	legData.joints = joints
	legData.totalLength = totalLength
	legData.bendDir = bendDir
end

local function updateLeg(legData, hipPos, footPos)
	local config = SCUTTLER_CONFIG
	local points = solveLegIK(hipPos, footPos, config.LegSegments, legData.totalLength, legData.bendDir)
	
	-- Update joints
	for i, joint in ipairs(legData.joints) do
		if i <= #points then
			joint.Position = joint.Position:Lerp(points[i], 0.5)
		end
	end
	
	-- Update segments
	for i, segment in ipairs(legData.segments) do
		local startJoint = legData.joints[i]
		local endJoint = legData.joints[i + 1]
		
		if startJoint and endJoint then
			local startPos = startJoint.Position
			local endPos = endJoint.Position
			local dir = endPos - startPos
			local length = dir.Magnitude
			
			if length > 0.05 then
				segment.Size = Vector3.new(segment.Size.X, segment.Size.Y, length)
				segment.CFrame = CFrame.lookAt(startPos, endPos) * CFrame.new(0, 0, -length/2)
			end
		end
	end
end

-- === SCUTTLER CREATION ===

local function generateStats()
	local config = SCUTTLER_CONFIG
	local bodyColor = config.BodyColors[math.random(1, #config.BodyColors)]
	
	return {
		BodyWidth = randomRange(config.BodyWidthMin, config.BodyWidthMax),
		BodyLength = randomRange(config.BodyLengthMin, config.BodyLengthMax),
		BodyHeight = randomRange(config.BodyHeightMin, config.BodyHeightMax),
		BodyColor = bodyColor,
		LegColor = Color3.new(bodyColor.R * 0.7, bodyColor.G * 0.7, bodyColor.B * 0.7),
		LegWidth = randomRange(config.LegWidthMin, config.LegWidthMax),
		EyeSize = randomRange(config.EyeSizeMin, config.EyeSizeMax),
		MoveSpeed = config.MoveSpeed * (0.8 + math.random() * 0.4),
	}
end

local function createScuttler(position, groundY, folder)
	local config = SCUTTLER_CONFIG
	local stats = generateStats()
	
	local model = Instance.new("Model")
	model.Name = "Scuttler_" .. math.random(1000, 9999)
	model.Parent = folder
	
	-- Body
	local body = Instance.new("Part")
	body.Name = "Body"
	body.Size = Vector3.new(stats.BodyWidth, stats.BodyHeight, stats.BodyLength)
	body.Position = position
	body.Color = stats.BodyColor
	body.Material = Enum.Material.SmoothPlastic
	body.Anchored = true
	body.CanCollide = false
	body.Parent = model
	
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = body
	
	-- Eyes
	local eyeParts = {}
	for i = 1, config.EyeCount do
		local side = (i % 2 == 0) and 1 or -1
		local row = math.floor((i - 1) / 2)
		
		local eyePos = position + Vector3.new(
			side * stats.BodyWidth * 0.3,
			stats.BodyHeight * 0.2,
			stats.BodyLength * 0.4 - row * stats.EyeSize * 1.5
		)
		
		local eye = Instance.new("Part")
		eye.Name = "Eye"
		eye.Shape = Enum.PartType.Ball
		eye.Size = Vector3.new(stats.EyeSize, stats.EyeSize, stats.EyeSize)
		eye.Position = eyePos
		eye.Color = config.EyeColor
		eye.Material = Enum.Material.Neon
		eye.Anchored = true
		eye.CanCollide = false
		eye.Parent = model
		
		table.insert(eyeParts, eye)
	end
	
	-- Legs
	local legs = {}
	local legsPerSide = config.LegCount / 2
	
	for i = 1, config.LegCount do
		local side = (i <= legsPerSide) and 1 or -1
		local legIndexOnSide = ((i - 1) % legsPerSide) + 1
		
		local zOffset = ((legIndexOnSide - 1) / math.max(legsPerSide - 1, 1) - 0.5) * stats.BodyLength * 0.8
		local xOffset = side * stats.BodyWidth * 0.4
		
		local hipOffset = Vector3.new(xOffset, -stats.BodyHeight * 0.2, zOffset)
		local hipPos = position + hipOffset
		
		-- Foot position spread outward
		local spreadDist = stats.BodyHeight * 1.5
		local footX = position.X + side * (stats.BodyWidth * 0.5 + spreadDist)
		local footZ = position.Z + zOffset * 1.2
		local footPos = Vector3.new(footX, groundY, footZ)
		
		local legData = {
			index = i,
			side = side,
			hipOffset = hipOffset,
			footPos = footPos,
			targetFootPos = footPos,
			restFootOffset = Vector3.new(side * spreadDist, 0, zOffset * 1.2),
			isStepping = false,
			stepProgress = 0,
			stepStartPos = footPos,
			gaitGroup = (i % 2),
		}
		
		createLeg(hipPos, footPos, i, side, stats, model, legData)
		table.insert(legs, legData)
	end
	
	model.PrimaryPart = body
	
	return {
		model = model,
		body = body,
		eyeParts = eyeParts,
		legs = legs,
		position = position,
		groundY = groundY,
		facing = Vector3.new(0, 0, 1),
		stats = stats,
		-- AI state
		state = "idle",
		targetPlayer = nil,
		idleTimer = 0,
		wanderDir = Vector3.new(math.random() - 0.5, 0, math.random() - 0.5).Unit,
		-- Erratic behavior state
		weavePhase = math.random() * math.pi * 2,  -- Random starting phase
		currentVeerAngle = 0,                       -- Current direction offset
		veerTimer = 0,                              -- Time until next direction change
		isSurging = false,
		surgeTimer = 0,
		isPaused = false,
		pauseTimer = 0,
	}
end

-- === MOVEMENT & AI ===

local function easeInOutQuad(t)
	return t < 0.5 and 2 * t * t or 1 - (-2 * t + 2)^2 / 2
end

-- Flocking behavior calculations
local function calculateFlocking(scuttler, allScuttlers)
	local config = SCUTTLER_CONFIG
	
	local separation = Vector3.zero
	local alignment = Vector3.zero
	local cohesion = Vector3.zero
	local neighborCount = 0
	local separationCount = 0
	
	for _, other in ipairs(allScuttlers) do
		if other ~= scuttler and other.body and other.body.Parent then
			local toOther = other.position - scuttler.position
			local distance = toOther.Magnitude
			
			if distance < config.FlockRadius and distance > 0.1 then
				neighborCount = neighborCount + 1
				
				-- Alignment: average heading
				if other.facing.Magnitude > 0.1 then
					alignment = alignment + other.facing
				end
				
				-- Cohesion: center of mass
				cohesion = cohesion + other.position
				
				-- Separation: avoid crowding
				if distance < config.SeparationRadius then
					local awayDir = -toOther.Unit
					local strength = 1 - (distance / config.SeparationRadius)
					separation = separation + awayDir * strength
					separationCount = separationCount + 1
				end
			end
		end
	end
	
	-- Normalize and weight the vectors
	if neighborCount > 0 then
		-- Alignment: steer toward average heading
		alignment = alignment / neighborCount
		if alignment.Magnitude > 0.1 then
			alignment = alignment.Unit * config.AlignmentWeight
		end
		
		-- Cohesion: steer toward center of neighbors
		cohesion = cohesion / neighborCount
		local toCenter = cohesion - scuttler.position
		toCenter = Vector3.new(toCenter.X, 0, toCenter.Z)
		if toCenter.Magnitude > 0.1 then
			cohesion = toCenter.Unit * config.CohesionWeight
		else
			cohesion = Vector3.zero
		end
	end
	
	if separationCount > 0 then
		separation = separation / separationCount
		if separation.Magnitude > 0.1 then
			separation = separation.Unit * config.SeparationWeight
		end
	end
	
	return separation, alignment, cohesion
end

local function updateScuttler(scuttler, deltaTime, allScuttlers)
	local config = SCUTTLER_CONFIG
	local stats = scuttler.stats
	
	if not scuttler.body or not scuttler.body.Parent then return end
	
	-- Find nearest player
	local nearestPlayer, distance = getNearestPlayer(scuttler.position, config.LoseRange)
	
	-- AI State machine
	if scuttler.state == "idle" then
		scuttler.idleTimer = scuttler.idleTimer + deltaTime
		if scuttler.idleTimer > config.IdleTime then
			scuttler.state = "wander"
			scuttler.wanderDir = Vector3.new(math.random() - 0.5, 0, math.random() - 0.5).Unit
			scuttler.idleTimer = 0
		end
		
		if nearestPlayer and distance < config.ChaseRange then
			scuttler.state = "chase"
			scuttler.targetPlayer = nearestPlayer
		end
		
	elseif scuttler.state == "wander" then
		scuttler.idleTimer = scuttler.idleTimer + deltaTime
		if scuttler.idleTimer > 3 then
			scuttler.state = "idle"
			scuttler.idleTimer = 0
		end
		
		if nearestPlayer and distance < config.ChaseRange then
			scuttler.state = "chase"
			scuttler.targetPlayer = nearestPlayer
		end
		
	elseif scuttler.state == "chase" then
		if not nearestPlayer or distance > config.LoseRange then
			scuttler.state = "idle"
			scuttler.targetPlayer = nil
			scuttler.idleTimer = 0
		else
			scuttler.targetPlayer = nearestPlayer
		end
	end
	
	-- Calculate flocking behavior
	local separation, alignment, cohesion = Vector3.zero, Vector3.zero, Vector3.zero
	if config.FlockingEnabled and allScuttlers then
		separation, alignment, cohesion = calculateFlocking(scuttler, allScuttlers)
	end
	
	-- Movement based on state
	local moveDir = Vector3.zero
	local lookDir = scuttler.facing
	local moveSpeed = 0
	local chaseDir = Vector3.zero
	
	if scuttler.state == "idle" then
		-- Look at nearest player even when idle
		if nearestPlayer then
			local character = nearestPlayer.Character
			if character then
				local hrp = character:FindFirstChild("HumanoidRootPart")
				if hrp then
					local toPlayer = (hrp.Position - scuttler.position)
					toPlayer = Vector3.new(toPlayer.X, 0, toPlayer.Z)
					if toPlayer.Magnitude > 0.1 then
						lookDir = toPlayer.Unit
					end
				end
			end
		end
		-- Still apply flocking when idle (drift with the group)
		moveDir = separation + alignment * 0.5 + cohesion * 0.5
		moveSpeed = config.WanderSpeed * 0.5
		
	elseif scuttler.state == "wander" then
		-- Combine wander direction with flocking
		local wanderForce = scuttler.wanderDir
		moveDir = wanderForce + separation + alignment + cohesion
		lookDir = moveDir.Magnitude > 0.1 and moveDir.Unit or scuttler.wanderDir
		moveSpeed = config.WanderSpeed
		
	elseif scuttler.state == "chase" and scuttler.targetPlayer then
		local character = scuttler.targetPlayer.Character
		if character then
			local hrp = character:FindFirstChild("HumanoidRootPart")
			if hrp then
				local toPlayer = (hrp.Position - scuttler.position)
				toPlayer = Vector3.new(toPlayer.X, 0, toPlayer.Z)
				if toPlayer.Magnitude > 0.1 then
					chaseDir = toPlayer.Unit
				end
			end
		end
		
		-- === ERRATIC CHASE BEHAVIOR ===
		if config.ErraticEnabled then
			-- Update veer timer and angle
			scuttler.veerTimer = scuttler.veerTimer - deltaTime
			if scuttler.veerTimer <= 0 then
				-- Pick a new random veer angle
				scuttler.currentVeerAngle = (math.random() - 0.5) * 2 * math.rad(config.DirectionChangeAmount)
				scuttler.veerTimer = config.DirectionChangeInterval * (0.5 + math.random())
			end
			
			-- Apply veer angle to chase direction
			if chaseDir.Magnitude > 0.1 then
				local veerRotation = CFrame.Angles(0, scuttler.currentVeerAngle, 0)
				chaseDir = veerRotation:VectorToWorldSpace(chaseDir)
			end
			
			-- Add sine wave weaving
			scuttler.weavePhase = scuttler.weavePhase + deltaTime * config.WeaveSpeed
			local weaveOffset = math.sin(scuttler.weavePhase) * config.WeaveAmount
			if chaseDir.Magnitude > 0.1 then
				-- Get perpendicular direction for weaving
				local perpendicular = Vector3.new(-chaseDir.Z, 0, chaseDir.X)
				chaseDir = (chaseDir + perpendicular * weaveOffset).Unit
			end
			
			-- Random surge (burst of speed)
			if not scuttler.isSurging and not scuttler.isPaused and math.random() < config.SurgeChance then
				scuttler.isSurging = true
				scuttler.surgeTimer = config.SurgeDuration
			end
			
			-- Random pause (brief hesitation)
			if not scuttler.isPaused and not scuttler.isSurging and math.random() < config.PauseChance then
				scuttler.isPaused = true
				scuttler.pauseTimer = config.PauseDuration
			end
			
			-- Update surge/pause timers
			if scuttler.isSurging then
				scuttler.surgeTimer = scuttler.surgeTimer - deltaTime
				if scuttler.surgeTimer <= 0 then
					scuttler.isSurging = false
				end
			end
			
			if scuttler.isPaused then
				scuttler.pauseTimer = scuttler.pauseTimer - deltaTime
				if scuttler.pauseTimer <= 0 then
					scuttler.isPaused = false
				end
			end
		end
		
		-- Combine chase with STRONG separation (no overlapping!)
		moveDir = chaseDir * config.ChaseWeight + separation * 3.0 + alignment * 0.2
		lookDir = chaseDir.Magnitude > 0.1 and chaseDir.Unit or scuttler.facing
		
		-- Apply speed modifiers
		if scuttler.isPaused then
			moveSpeed = 0
		elseif scuttler.isSurging then
			moveSpeed = stats.MoveSpeed * config.SurgeSpeedMultiplier
		else
			moveSpeed = stats.MoveSpeed
		end
	end
	
	-- Normalize movement direction
	if moveDir.Magnitude > 0.1 then
		moveDir = moveDir.Unit
	end
	
	-- Always smoothly turn to look at target (look more toward actual player, not veered direction)
	if lookDir.Magnitude > 0.1 then
		local targetFacing = lookDir.Unit
		scuttler.facing = scuttler.facing:Lerp(targetFacing, deltaTime * config.TurnSpeed)
		if scuttler.facing.Magnitude > 0.1 then
			scuttler.facing = scuttler.facing.Unit
		end
	end
	
	-- Apply movement
	if moveDir.Magnitude > 0.1 and moveSpeed > 0 then
		local moveAmount = moveSpeed * deltaTime
		scuttler.position = scuttler.position + moveDir * moveAmount
	end
	
	-- Body bob
	local bobPhase = tick() * config.BodyBobSpeed
	local bobOffset = math.sin(bobPhase) * config.BodyBobAmount
	
	-- Update body
	local bodyPos = scuttler.position + Vector3.new(0, stats.BodyHeight / 2 + bobOffset, 0)
	
	-- Create body CFrame with rotation toward facing direction
	local bodyCFrame
	if scuttler.facing.Magnitude > 0.1 then
		bodyCFrame = CFrame.lookAt(bodyPos, bodyPos + scuttler.facing)
	else
		bodyCFrame = CFrame.new(bodyPos)
	end
	
	scuttler.body.CFrame = bodyCFrame
	
	-- Update eyes - position them relative to rotated body
	local config = SCUTTLER_CONFIG
	for i, eye in ipairs(scuttler.eyeParts) do
		local side = (i % 2 == 0) and 1 or -1
		local row = math.floor((i - 1) / 2)
		
		-- Local eye offset (relative to body)
		local localEyeOffset = Vector3.new(
			side * stats.BodyWidth * 0.3,
			stats.BodyHeight * 0.2,
			stats.BodyLength * 0.4 - row * stats.EyeSize * 1.5
		)
		
		-- Transform to world space using body rotation
		local worldEyePos = bodyCFrame:PointToWorldSpace(localEyeOffset)
		eye.Position = worldEyePos
	end
	
	-- Update legs
	for _, leg in ipairs(scuttler.legs) do
		local hipPos = scuttler.position + Vector3.new(0, stats.BodyHeight / 2, 0) + leg.hipOffset
		
		-- Rotate hip offset based on facing
		if scuttler.facing.Magnitude > 0.1 then
			local facingCF = CFrame.lookAt(Vector3.zero, scuttler.facing)
			hipPos = scuttler.position + Vector3.new(0, stats.BodyHeight / 2, 0) + facingCF:VectorToWorldSpace(leg.hipOffset)
		end
		
		-- Ideal foot position
		local idealFootOffset = leg.restFootOffset
		if scuttler.facing.Magnitude > 0.1 then
			local facingCF = CFrame.lookAt(Vector3.zero, scuttler.facing)
			idealFootOffset = facingCF:VectorToWorldSpace(leg.restFootOffset)
		end
		
		local idealFootPos = Vector3.new(
			scuttler.position.X + idealFootOffset.X,
			scuttler.groundY,
			scuttler.position.Z + idealFootOffset.Z
		)
		
		-- Check if needs to step
		local distFromIdeal = (leg.footPos - idealFootPos).Magnitude
		
		if not leg.isStepping and distFromIdeal > config.StepDistance then
			leg.isStepping = true
			leg.stepProgress = 0
			leg.stepStartPos = leg.footPos
			leg.targetFootPos = idealFootPos + scuttler.facing * config.StepDistance * 0.3
			leg.targetFootPos = Vector3.new(leg.targetFootPos.X, scuttler.groundY, leg.targetFootPos.Z)
		end
		
		if leg.isStepping then
			leg.stepProgress = leg.stepProgress + deltaTime / config.StepDuration
			
			if leg.stepProgress >= 1 then
				leg.stepProgress = 1
				leg.isStepping = false
				leg.footPos = leg.targetFootPos
			else
				local t = easeInOutQuad(leg.stepProgress)
				local groundPos = leg.stepStartPos:Lerp(leg.targetFootPos, t)
				local arcHeight = math.sin(leg.stepProgress * math.pi) * config.StepHeight
				leg.footPos = groundPos + Vector3.new(0, arcHeight, 0)
			end
		end
		
		updateLeg(leg, hipPos, leg.footPos)
	end
end

-- === GENERATION ===

local function generateScuttlers(self)
	local folder = getScuttlerFolder()
	folder:ClearAllChildren()
	
	local baseplateInfo = getBaseplateInfo()
	if not baseplateInfo then
		warn("[ScuttlerService] No Baseplate found!")
		return
	end
	
	local groundY = baseplateInfo.topY
	
	for i = 1, SCUTTLER_CONFIG.ScuttlerCount do
		local angle = math.random() * math.pi * 2
		local radius = math.random() * SCUTTLER_CONFIG.SpawnRadius
		
		local x = baseplateInfo.position.X + math.cos(angle) * radius
		local z = baseplateInfo.position.Z + math.sin(angle) * radius
		local y = groundY + 2
		
		local scuttler = createScuttler(Vector3.new(x, y, z), groundY, folder)
		table.insert(self.scuttlers, scuttler)
		
		print(string.format("[ScuttlerService] Spawned scuttler %d at (%.0f, %.0f)", i, x, z))
	end
	
	print(string.format("[ScuttlerService] Spawned %d scuttlers", #self.scuttlers))
	
	-- Start animation loop
	RunService.Heartbeat:Connect(function(deltaTime)
		for _, scuttler in ipairs(self.scuttlers) do
			updateScuttler(scuttler, deltaTime, self.scuttlers)
		end
	end)
end

-- === KNIT LIFECYCLE ===

function ScuttlerService:KnitInit()
	-- Nothing
end

function ScuttlerService:KnitStart()
	task.delay(3, function()
		--generateScuttlers(self)
	end)
end

-- === PUBLIC METHODS ===

function ScuttlerService:SpawnScuttler(position)
	local baseplateInfo = getBaseplateInfo()
	local groundY = baseplateInfo and baseplateInfo.topY or 0
	
	local folder = getScuttlerFolder()
	local scuttler = createScuttler(position, groundY, folder)
	table.insert(self.scuttlers, scuttler)
	
	return scuttler
end

function ScuttlerService:ClearScuttlers()
	self.scuttlers = {}
	local folder = Workspace:FindFirstChild(FOLDER_NAME)
	if folder then
		folder:ClearAllChildren()
	end
end

return ScuttlerService

