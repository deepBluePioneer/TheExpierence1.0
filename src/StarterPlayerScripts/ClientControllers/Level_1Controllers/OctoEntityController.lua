--[[
	OctoEntityController (CLIENT-SIDE)
	Creates spherical entities with animated tentacles - eldritch horror style
	Runs entirely on the client for smooth animations and reduced server load
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local Knit = require(Packages.Knit)
local Gizmo = require(Packages.imgizmo)

local OctoEntityController = Knit.CreateController {
	Name = "OctoEntityController",
	_entities = {}, -- Track all spawned octo entities
	_entityFolder = nil, -- Container for all octo entities
}

-- === CONFIGURATION ===
local OCTO_CONFIG = {
	-- Body settings
	BodyRadius = 3,
	BodyColor = Color3.fromRGB(20, 8, 35),  -- Deep alien purple-black
	BodyMaterial = Enum.Material.SmoothPlastic,
	
	-- Physics settings
	PhysicsEnabled = true,        -- Enable physics on the body
	BodyMass = 10,                -- Mass of the body (affects how easily it's pushed)
	BodyFriction = 0.3,           -- Friction when rolling
	BodyElasticity = 0.5,         -- Bounciness
	BodyDensity = 0.5,            -- Density (affects mass calculation)
	
	-- Target bounding box (invisible hitbox for targeting)
	TargetBoxSize = Vector3.new(20, 20, 20),  -- Size of the target hitbox
	TargetBoxVisible = false,                  -- Set true to debug
	
	-- Tentacle settings
	TentacleCount = 80,           -- Number of tentacles (dense coverage)
	TentacleSegments = 12,        -- Segments per tentacle
	TentacleBaseWidth = 1.8,      -- Width at base (THICC)
	TentacleTipWidth = 0.5,       -- Width at tip
	TentacleLength = 10,          -- Total tentacle length (long reach)
	TentacleColor = Color3.fromRGB(25, 10, 40),     -- Dark alien purple base
	TentacleTipColor = Color3.fromRGB(80, 255, 180), -- Bioluminescent cyan-green tips
	TentacleMaterial = Enum.Material.SmoothPlastic,
	
	-- Animation settings
	WiggleSpeed = 2.0,            -- How fast tentacles wiggle
	WiggleAmplitude = 0.4,        -- How much they wiggle (radians)
	WaveSpeed = 3.0,              -- Speed of wave propagation down tentacle
	IdleSwaySpeed = 0.5,          -- Slow idle swaying
	IdleSwayAmplitude = 0.15,     -- Idle sway amount
	
	-- Spawn settings
	SpawnHeight = 10,             -- Height above ground to spawn
	
	-- Chase behavior
	ChaseEnabled = true,          -- Enable chasing the player
	ChaseForce = 10,              -- Force applied towards player (slow)
	ChaseTorque = 2,              -- Torque for rolling towards player (minimal spin)
	MaxChaseSpeed = 8,            -- Maximum velocity when chasing (slow crawl)
	ChaseMinDistance = 8,         -- Stop applying force when this close
	AngularDamping = 0.9,         -- How quickly rotation slows down (0-1)
	
	-- Vision / Obstacle Avoidance
	-- Single sphere detection around the core - finds all nearby obstacles
	VisionEnabled = true,         -- Enable obstacle detection
	VisionRadius = 15,            -- Detection radius around the core
	AvoidanceForce = 20,          -- Lateral force to push away from obstacles
	AvoidanceFalloff = 1.5,       -- How quickly avoidance weakens with distance
	
	-- Debug visualization
	DebugVisionEnabled = true,    -- Show detection sphere and obstacles
	DebugSphereColor = Color3.fromRGB(50, 255, 50),   -- Green detection sphere
	DebugHitColor = Color3.fromRGB(255, 50, 50),      -- Red for detected obstacles
	DebugForceColor = Color3.fromRGB(255, 255, 0),    -- Yellow for avoidance force direction
	DebugPlayerColor = Color3.fromRGB(0, 150, 255),   -- Blue line to player
}

-- === HELPER FUNCTIONS ===

local function lerp(a, b, t)
	return a + (b - a) * t
end

local function lerpColor(c1, c2, t)
	return Color3.new(
		lerp(c1.R, c2.R, t),
		lerp(c1.G, c2.G, t),
		lerp(c1.B, c2.B, t)
	)
end

-- Distribute points evenly on a sphere using fibonacci spiral
local function fibonacciSphere(index, total)
	local phi = math.pi * (3 - math.sqrt(5)) -- golden angle
	local y = 1 - (index / (total - 1)) * 2  -- y goes from 1 to -1
	local radius = math.sqrt(1 - y * y)
	local theta = phi * index
	
	return Vector3.new(
		math.cos(theta) * radius,
		y,
		math.sin(theta) * radius
	).Unit
end

-- === VISION / OBSTACLE AVOIDANCE ===
-- Single sphere detection around the core
-- Finds all obstacles within radius and pushes away from them

local gizmoInitialized = false

local function initGizmo()
	if not gizmoInitialized then
		Gizmo.Init()
		gizmoInitialized = true
	end
end

local function drawVisionSphere(position, color, radius)
	if not OCTO_CONFIG.DebugVisionEnabled then return end
	initGizmo()
	Gizmo.SetStyle(color, 0.5, true)
	Gizmo.Sphere:Draw(CFrame.new(position), radius, 12, 360)
end

local function drawVisionRay(startPos, endPos, color)
	if not OCTO_CONFIG.DebugVisionEnabled then return end
	initGizmo()
	Gizmo.SetStyle(color, 0, true)
	Gizmo.Ray:Draw(startPos, endPos)  -- start & end positions
end

local function drawHitPoint(position, color)
	if not OCTO_CONFIG.DebugVisionEnabled then return end
	initGizmo()
	Gizmo.SetStyle(color, 0, true)
	Gizmo.Sphere:Draw(CFrame.new(position), 0.5, 6, 360)
end

local function performVisionDetection(entityData, playerDirection)
	if not OCTO_CONFIG.VisionEnabled then return Vector3.zero end
	
	local body = entityData.body
	if not body or not body.Parent then return Vector3.zero end
	
	local bodyPos = body.Position
	local visionRadius = OCTO_CONFIG.VisionRadius
	
	-- Build exclusion set for filtering
	local excludeSet = {}
	
	-- Exclude octo parts
	if entityData.model then excludeSet[entityData.model] = true end
	if entityData.body then excludeSet[entityData.body] = true end
	if entityData.targetBox then excludeSet[entityData.targetBox] = true end
	
	-- Exclude tentacle segments
	for _, tentacle in ipairs(entityData.tentacles) do
		for _, segment in ipairs(tentacle.segments) do
			if segment then excludeSet[segment] = true end
		end
	end
	
	-- Exclude player
	local player = Players.LocalPlayer
	if player and player.Character then
		excludeSet[player.Character] = true
		for _, part in ipairs(player.Character:GetDescendants()) do
			if part:IsA("BasePart") then
				excludeSet[part] = true
			end
		end
	end
	
	-- Exclude grid cubes
	for _, cube in ipairs(CollectionService:GetTagged("gridCube")) do
		excludeSet[cube] = true
	end
	
	-- Create overlap params
	local overlapParams = OverlapParams.new()
	overlapParams.FilterType = Enum.RaycastFilterType.Exclude
	overlapParams.FilterDescendantsInstances = {entityData.model, player and player.Character}
	
	-- Single sphere detection - find all parts within radius
	local partsInSphere = workspace:GetPartBoundsInRadius(bodyPos, visionRadius, overlapParams)
	
	-- Debug: draw detection sphere
	drawVisionSphere(bodyPos, OCTO_CONFIG.DebugSphereColor, visionRadius)
	
	-- Accumulate avoidance force from all detected obstacles
	local totalAvoidance = Vector3.zero
	
	for _, part in ipairs(partsInSphere) do
		-- Skip excluded parts
		if excludeSet[part] then continue end
		if excludeSet[part.Parent] then continue end
		
		-- Skip non-collidable parts
		if not part.CanCollide then continue end
		
		-- Calculate direction and distance to obstacle
		local obstaclePos = part.Position
		local toObstacle = obstaclePos - bodyPos
		local distance = toObstacle.Magnitude
		
		if distance < 0.1 then continue end
		
		-- Normalize distance (0 = at center, 1 = at edge of vision)
		local normalizedDistance = distance / visionRadius
		
		-- Stronger avoidance when closer (inverse falloff)
		local avoidanceStrength = (1 - normalizedDistance) ^ OCTO_CONFIG.AvoidanceFalloff
		
		-- Push AWAY from obstacle (lateral only)
		local pushAwayDir = -toObstacle.Unit
		local lateralPush = Vector3.new(pushAwayDir.X, 0, pushAwayDir.Z)
		
		if lateralPush.Magnitude > 0.1 then
			lateralPush = lateralPush.Unit
			totalAvoidance = totalAvoidance + lateralPush * avoidanceStrength * OCTO_CONFIG.AvoidanceForce
			
			-- Debug: just show dot at obstacle position (no line)
			drawHitPoint(obstaclePos, OCTO_CONFIG.DebugHitColor)
		end
	end
	
	
	-- Debug: draw line showing the direction of the total avoidance force (yellow)
	if totalAvoidance.Magnitude > 0.01 then
		local forceDir = totalAvoidance.Unit
		local forceLength = 25  -- Fixed long length so it's always visible
		drawVisionRay(bodyPos, bodyPos + forceDir * forceLength, OCTO_CONFIG.DebugForceColor)
	end
	
	return totalAvoidance
end

-- === ENTITY CREATION ===

local function createBody(position, parent)
	local body = Instance.new("Part")
	body.Name = "OctoBody"
	body.Shape = Enum.PartType.Ball
	body.Size = Vector3.new(OCTO_CONFIG.BodyRadius * 2, OCTO_CONFIG.BodyRadius * 2, OCTO_CONFIG.BodyRadius * 2)
	body.CFrame = CFrame.new(position)
	body.CastShadow = true
	body.Color = OCTO_CONFIG.BodyColor
	body.Material = OCTO_CONFIG.BodyMaterial
	
	-- Physics settings
	if OCTO_CONFIG.PhysicsEnabled then
		body.Anchored = false
		body.CanCollide = true
		body.CanQuery = false  -- Body is not the target
		body.CanTouch = true
		
		-- Custom physical properties for rolling ball
		local physProps = PhysicalProperties.new(
			OCTO_CONFIG.BodyDensity,      -- Density
			OCTO_CONFIG.BodyFriction,     -- Friction
			OCTO_CONFIG.BodyElasticity,   -- Elasticity
			1,                             -- FrictionWeight
			1                              -- ElasticityWeight
		)
		body.CustomPhysicalProperties = physProps
	else
		body.Anchored = true
		body.CanCollide = false
		body.CanQuery = false
		body.CanTouch = false
	end
	
	body.Parent = parent
	
	-- Add eerie bioluminescent glow
	local pointLight = Instance.new("PointLight")
	pointLight.Color = Color3.fromRGB(80, 255, 180)  -- Alien cyan-green glow
	pointLight.Brightness = 1.2
	pointLight.Range = 12
	pointLight.Parent = body
	
	-- Tag body as entity (but NOT PhotoTarget - that's the bounding box)
	CollectionService:AddTag(body, "entity")
	
	return body
end

local function createTargetBoundingBox(position, parent, body)
	local boundingBox = Instance.new("Part")
	boundingBox.Name = "OctoTargetBox"
	boundingBox.Size = OCTO_CONFIG.TargetBoxSize
	boundingBox.CFrame = CFrame.new(position)
	boundingBox.Anchored = false  -- Will be welded to body
	boundingBox.CanCollide = false
	boundingBox.CanQuery = true  -- This IS the target
	boundingBox.CanTouch = false
	boundingBox.CastShadow = false
	boundingBox.Massless = true  -- Don't add mass to physics
	boundingBox.Transparency = OCTO_CONFIG.TargetBoxVisible and 0.8 or 1
	boundingBox.Color = Color3.fromRGB(0, 255, 100)
	boundingBox.Material = Enum.Material.ForceField
	boundingBox.Parent = parent
	
	-- Weld to body so it follows physics
	if body then
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = body
		weld.Part1 = boundingBox
		weld.Parent = boundingBox
	end
	
	-- Tag for targeting system
	CollectionService:AddTag(boundingBox, "entity")
	CollectionService:AddTag(boundingBox, "PhotoTarget")
	
	return boundingBox
end

local function createTentacleSegment(index, totalSegments, baseWidth, tipWidth, segmentLength, parent)
	local t = index / totalSegments
	local width = lerp(baseWidth, tipWidth, t)
	
	local segment = Instance.new("Part")
	segment.Name = "TentacleSegment_" .. index
	segment.Size = Vector3.new(width, segmentLength, width)
	segment.Anchored = true
	segment.CanCollide = false
	segment.CanQuery = false
	segment.CanTouch = false
	segment.CastShadow = true
	segment.Color = lerpColor(OCTO_CONFIG.TentacleColor, OCTO_CONFIG.TentacleTipColor, t)
	segment.Material = OCTO_CONFIG.TentacleMaterial
	segment.Parent = parent
	
	-- Cylinder mesh for rounded tentacle look
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Cylinder
	mesh.Parent = segment
	
	return segment
end

local function createTentacle(entityModel, direction, tentacleIndex)
	local tentacle = {
		segments = {},
		direction = direction,
		index = tentacleIndex,
		phaseOffset = tentacleIndex * (math.pi * 2 / OCTO_CONFIG.TentacleCount),
	}
	
	local segmentLength = OCTO_CONFIG.TentacleLength / OCTO_CONFIG.TentacleSegments
	
	for i = 1, OCTO_CONFIG.TentacleSegments do
		local segment = createTentacleSegment(
			i, 
			OCTO_CONFIG.TentacleSegments,
			OCTO_CONFIG.TentacleBaseWidth,
			OCTO_CONFIG.TentacleTipWidth,
			segmentLength,
			entityModel
		)
		table.insert(tentacle.segments, segment)
	end
	
	return tentacle
end

local function createOctoEntity(self, position)
	-- Create model container
	local entity = Instance.new("Model")
	entity.Name = "OctoEntity_" .. tostring(#self._entities + 1)
	
	-- Calculate spawn position with spawn height
	local spawnPos = position + Vector3.new(0, OCTO_CONFIG.SpawnHeight, 0)
	
	-- Create body first
	local body = createBody(spawnPos, entity)
	entity.PrimaryPart = body
	
	-- Create larger bounding box for targeting (welded to body)
	local targetBox = createTargetBoundingBox(spawnPos, entity, body)
	
	-- Create tentacles distributed evenly around the entire sphere
	local tentacles = {}
	for i = 1, OCTO_CONFIG.TentacleCount do
		-- Get direction for this tentacle (fibonacci sphere distribution - full coverage)
		local dir = fibonacciSphere(i - 1, OCTO_CONFIG.TentacleCount)
		
		local tentacle = createTentacle(entity, dir, i)
		table.insert(tentacles, tentacle)
	end
	
	-- Parent to entity folder (client-side)
	entity.Parent = self._entityFolder
	
	return {
		model = entity,
		body = body,
		targetBox = targetBox,
		tentacles = tentacles,
		spawnPosition = position,
		spawnTime = tick(),
		physicsEnabled = OCTO_CONFIG.PhysicsEnabled,
	}
end

-- === ANIMATION ===

local function updateTentacleAnimation(entityData, deltaTime, currentTime)
	local body = entityData.body
	if not body or not body.Parent then return end
	
	local bodyPos = body.Position
	local bodyCF = body.CFrame
	local bodyRadius = OCTO_CONFIG.BodyRadius
	
	for _, tentacle in ipairs(entityData.tentacles) do
		local baseDir = tentacle.direction
		local phaseOffset = tentacle.phaseOffset
		local segmentLength = OCTO_CONFIG.TentacleLength / OCTO_CONFIG.TentacleSegments
		
		-- Transform base direction by body rotation
		local rotatedBaseDir = bodyCF:VectorToWorldSpace(baseDir)
		
		-- Starting position at sphere surface
		local currentPos = bodyPos + rotatedBaseDir * bodyRadius
		local currentDir = rotatedBaseDir
		
		for i, segment in ipairs(tentacle.segments) do
			if not segment or not segment.Parent then continue end
			
			local t = i / #tentacle.segments
			
			-- Calculate wiggle for this segment
			local wavePhase = currentTime * OCTO_CONFIG.WaveSpeed - t * math.pi * 2
			local wigglePhase = currentTime * OCTO_CONFIG.WiggleSpeed + phaseOffset
			
			-- Wiggle increases towards tip
			local wiggleAmount = OCTO_CONFIG.WiggleAmplitude * t * t
			local idleAmount = OCTO_CONFIG.IdleSwayAmplitude
			
			-- Create rotation axes perpendicular to current direction
			local right = currentDir:Cross(Vector3.new(0, 1, 0))
			if right.Magnitude < 0.1 then
				right = currentDir:Cross(Vector3.new(1, 0, 0))
			end
			right = right.Unit
			local up = right:Cross(currentDir).Unit
			
			-- Apply wiggle rotation
			local wiggleX = math.sin(wavePhase + wigglePhase) * wiggleAmount
			local wiggleZ = math.cos(wavePhase * 0.7 + wigglePhase * 1.3) * wiggleAmount * 0.7
			
			-- Add slow idle sway
			local idleX = math.sin(currentTime * OCTO_CONFIG.IdleSwaySpeed + phaseOffset) * idleAmount
			local idleZ = math.cos(currentTime * OCTO_CONFIG.IdleSwaySpeed * 0.8 + phaseOffset * 1.5) * idleAmount
			
			-- Combine rotations
			local totalRotX = wiggleX + idleX
			local totalRotZ = wiggleZ + idleZ
			
			-- Apply rotation to direction
			local rotatedDir = CFrame.fromAxisAngle(right, totalRotX) * CFrame.fromAxisAngle(up, totalRotZ) * CFrame.new(currentDir)
			currentDir = rotatedDir.Position.Unit
			
			-- Add slight gravity influence (less for upward-pointing tentacles)
			local gravityInfluence = t * 0.15 * math.max(0, -baseDir.Y + 0.5)
			currentDir = (currentDir + Vector3.new(0, -gravityInfluence, 0)).Unit
			
			-- Position segment
			local segmentCenter = currentPos + currentDir * (segmentLength / 2)
			
			-- Orient segment along direction (cylinder mesh is oriented along X axis)
			local lookCF = CFrame.lookAt(segmentCenter, segmentCenter + currentDir)
			-- Rotate 90 degrees to align cylinder
			segment.CFrame = lookCF * CFrame.Angles(0, 0, math.rad(90))
			
			-- Move to next segment position
			currentPos = currentPos + currentDir * segmentLength
		end
	end
end

local function updateChaseForces(entityData, deltaTime)
	if not entityData.physicsEnabled then return end
	
	local body = entityData.body
	if not body or not body.Parent then return end
	
	-- Clear gizmos from previous frame
	if OCTO_CONFIG.DebugVisionEnabled and gizmoInitialized then
		Gizmo.ScheduleCleaning()
	end
	
	-- Apply angular damping to slow down spinning
	local angularVel = body.AssemblyAngularVelocity
	local dampingFactor = 1 - (OCTO_CONFIG.AngularDamping * deltaTime * 5)
	body.AssemblyAngularVelocity = angularVel * dampingFactor
	
	-- Get player position
	local player = Players.LocalPlayer
	local character = player.Character
	if not character then return end
	
	local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")
	if not humanoidRootPart then return end
	
	local bodyPos = body.Position
	local playerPos = humanoidRootPart.Position
	
	-- Debug: draw line from body to player (blue) - using ACTUAL positions from chase logic
	if OCTO_CONFIG.DebugVisionEnabled then
		initGizmo()
		Gizmo.SetStyle(OCTO_CONFIG.DebugPlayerColor, 0, true)
		Gizmo.Ray:Draw(bodyPos, playerPos)  -- start & end positions
		-- Draw spheres at both positions
		Gizmo.SetStyle(Color3.fromRGB(255, 255, 255), 0, true)
		Gizmo.Sphere:Draw(CFrame.new(bodyPos), 0.5, 6, 360)  -- White = octo
		Gizmo.SetStyle(OCTO_CONFIG.DebugPlayerColor, 0, true)
		Gizmo.Sphere:Draw(CFrame.new(playerPos), 0.5, 6, 360)  -- Blue = player
	end
	
	-- Calculate direction to player (horizontal only for rolling)
	local directionToPlayer = (playerPos - bodyPos)
	local horizontalDirection = Vector3.new(directionToPlayer.X, 0, directionToPlayer.Z)
	local distance = horizontalDirection.Magnitude
	local direction = horizontalDirection.Magnitude > 0.1 and horizontalDirection.Unit or Vector3.new(1, 0, 0)
	
	-- === VISION & OBSTACLE AVOIDANCE ===
	local avoidanceForce = performVisionDetection(entityData, direction)
	
	-- Apply avoidance force (always active if vision is enabled)
	if avoidanceForce.Magnitude > 0.1 then
		-- Horizontal avoidance only
		local horizontalAvoidance = Vector3.new(avoidanceForce.X, 0, avoidanceForce.Z)
		body:ApplyImpulse(horizontalAvoidance * deltaTime * 60)
	end
	
	-- Skip chase forces if disabled or too close
	if not OCTO_CONFIG.ChaseEnabled then return end
	if distance < OCTO_CONFIG.ChaseMinDistance then return end
	
	-- Check current speed
	local currentVelocity = body.AssemblyLinearVelocity
	local horizontalSpeed = Vector3.new(currentVelocity.X, 0, currentVelocity.Z).Magnitude
	
	-- Only apply chase force if below max speed
	if horizontalSpeed < OCTO_CONFIG.MaxChaseSpeed then
		-- Combine chase direction with avoidance (avoidance has priority when strong)
		local avoidanceMagnitude = avoidanceForce.Magnitude
		local chaseWeight = math.max(0, 1 - avoidanceMagnitude / OCTO_CONFIG.AvoidanceForce)
		
		-- Blend between pure chase and avoidance-influenced chase
		local finalDirection = (direction * chaseWeight + avoidanceForce.Unit * (1 - chaseWeight))
		if finalDirection.Magnitude > 0.1 then
			finalDirection = Vector3.new(finalDirection.X, 0, finalDirection.Z).Unit
		else
			finalDirection = direction
		end
		
		-- Apply chase force
		local force = finalDirection * OCTO_CONFIG.ChaseForce
		body:ApplyImpulse(force * deltaTime * 60)
	end
	
	-- Apply gentle torque to make it roll (perpendicular to movement direction)
	local torqueAxis = Vector3.new(direction.Z, 0, -direction.X)
	local torque = torqueAxis * OCTO_CONFIG.ChaseTorque
	body:ApplyAngularImpulse(torque * deltaTime * 60)
end

local function updateEntityAnimation(entityData, deltaTime, currentTime)
	local body = entityData.body
	
	if not body or not body.Parent then return end
	
	-- Apply chase forces to roll towards player
	updateChaseForces(entityData, deltaTime)
	
	-- Update tentacles (they follow body.CFrame automatically)
	updateTentacleAnimation(entityData, deltaTime, currentTime)
end

-- === CONTROLLER METHODS ===

function OctoEntityController:SpawnOcto(position)
	local entityData = createOctoEntity(self, position)
	table.insert(self._entities, entityData)
	print(string.format("[OctoEntityController] Spawned OctoEntity at %.1f, %.1f, %.1f", position.X, position.Y, position.Z))
	return entityData
end

function OctoEntityController:DespawnOcto(entityData)
	if entityData and entityData.model then
		entityData.model:Destroy()
		
		-- Remove from tracking
		for i, data in ipairs(self._entities) do
			if data == entityData then
				table.remove(self._entities, i)
				break
			end
		end
		
		print("[OctoEntityController] Despawned OctoEntity")
	end
end

function OctoEntityController:DespawnAll()
	for _, entityData in ipairs(self._entities) do
		if entityData.model then
			entityData.model:Destroy()
		end
	end
	self._entities = {}
	print("[OctoEntityController] Despawned all OctoEntities")
end

function OctoEntityController:GetAllEntities()
	return self._entities
end

function OctoEntityController:SetConfig(key, value)
	if OCTO_CONFIG[key] ~= nil then
		OCTO_CONFIG[key] = value
		print(string.format("[OctoEntityController] Config %s set to %s", key, tostring(value)))
		return true
	end
	return false
end

function OctoEntityController:GetConfig(key)
	return OCTO_CONFIG[key]
end

function OctoEntityController:ApplyImpulse(entityData, impulse)
	if entityData and entityData.body and entityData.physicsEnabled then
		entityData.body:ApplyImpulse(impulse)
	end
end

function OctoEntityController:ApplyForce(entityData, force, position)
	if entityData and entityData.body and entityData.physicsEnabled then
		if position then
			entityData.body:ApplyImpulseAtPosition(force, position)
		else
			entityData.body:ApplyImpulse(force)
		end
	end
end

function OctoEntityController:SetVelocity(entityData, velocity)
	if entityData and entityData.body and entityData.physicsEnabled then
		entityData.body.AssemblyLinearVelocity = velocity
	end
end

function OctoEntityController:GetVelocity(entityData)
	if entityData and entityData.body then
		return entityData.body.AssemblyLinearVelocity
	end
	return Vector3.zero
end

function OctoEntityController:EnableChase()
	OCTO_CONFIG.ChaseEnabled = true
end

function OctoEntityController:DisableChase()
	OCTO_CONFIG.ChaseEnabled = false
end

function OctoEntityController:SetChaseForce(force)
	OCTO_CONFIG.ChaseForce = force
end

function OctoEntityController:SetChaseTorque(torque)
	OCTO_CONFIG.ChaseTorque = torque
end

function OctoEntityController:SetMaxChaseSpeed(speed)
	OCTO_CONFIG.MaxChaseSpeed = speed
end

-- Vision control
function OctoEntityController:EnableVision()
	OCTO_CONFIG.VisionEnabled = true
end

function OctoEntityController:DisableVision()
	OCTO_CONFIG.VisionEnabled = false
end

function OctoEntityController:EnableDebugVision()
	OCTO_CONFIG.DebugVisionEnabled = true
end

function OctoEntityController:DisableDebugVision()
	OCTO_CONFIG.DebugVisionEnabled = false
end

function OctoEntityController:SetVisionDistance(distance)
	OCTO_CONFIG.VisionDistance = distance
end

function OctoEntityController:SetAvoidanceForce(force)
	OCTO_CONFIG.AvoidanceForce = force
end

-- === KNIT LIFECYCLE ===

function OctoEntityController:KnitInit()
	-- Create folder to hold all octo entities (client-side)
	self._entityFolder = Instance.new("Folder")
	self._entityFolder.Name = "OctoEntities"
	self._entityFolder.Parent = workspace
end

function OctoEntityController:KnitStart()
	-- Use RenderStepped for smoother client-side animations
	RunService.RenderStepped:Connect(function(deltaTime)
		local currentTime = tick()
		for _, entityData in ipairs(self._entities) do
			updateEntityAnimation(entityData, deltaTime, currentTime)
		end
	end)
	
	print("[OctoEntityController] Started (CLIENT-SIDE) - ready to spawn eldritch horrors!")
	
	-- TEST: Spawn at player's position (remove this in production)
	task.delay(3, function()
		local player = Players.LocalPlayer
		local character = player.Character or player.CharacterAdded:Wait()
		local humanoidRootPart = character:WaitForChild("HumanoidRootPart")
		
		-- Spawn slightly in front of player
		local spawnPos = humanoidRootPart.Position + humanoidRootPart.CFrame.LookVector * 15
		self:SpawnOcto(spawnPos)
	end)
end

return OctoEntityController

