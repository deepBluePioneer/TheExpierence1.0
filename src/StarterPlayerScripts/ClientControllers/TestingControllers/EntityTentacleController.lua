--[[
	EntityTentacleController (CLIENT-SIDE)
	Finds entities with "entity" tag and adds procedurally animated tentacles to their heads
	Uses pure CFrame animation - no physics constraints
]]

local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")

local Packages = game:GetService("ReplicatedStorage"):WaitForChild("Packages")
local Knit = require(Packages.Knit)

local EntityTentacleController = Knit.CreateController {
	Name = "EntityTentacleController",
	_processedEntities = {},  -- Track entities we've already processed
	_entityData = {},  -- Store tentacle data for each entity
	_streamingCullingController = nil, -- Reference to culling controller
}

-- === CONFIG ===
local TENTACLE_CONFIG = {
	EntityTag = "entity",           -- Tag to find entities
	TentacleCount = 12,             -- Number of tentacles
	TentacleSegments = 8,           -- Segments per tentacle
	TentacleBaseWidth = 0.8,        -- Width at base
	TentacleTipWidth = 0.2,         -- Width at tip
	TentacleLength = 6,             -- Total tentacle length
	TentacleColor = Color3.fromRGB(25, 10, 40),     -- Dark alien purple base
	TentacleTipColor = Color3.fromRGB(80, 255, 180), -- Bioluminescent cyan-green tips
	TentacleMaterial = Enum.Material.SmoothPlastic,
	-- Animation settings
	WiggleSpeed = 2.0,              -- How fast tentacles wiggle
	WiggleAmplitude = 0.3,          -- How much they wiggle (radians)
	WaveSpeed = 3.0,                -- Speed of wave propagation down tentacle
	IdleSwaySpeed = 0.5,            -- Slow idle swaying
	IdleSwayAmplitude = 0.1,        -- Idle sway amount
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

-- Create a tentacle segment (anchored for procedural animation)
local function createTentacleSegment(index, totalSegments, baseWidth, tipWidth, segmentLength, parent)
	local t = index / totalSegments
	local width = lerp(baseWidth, tipWidth, t)
	
	local segment = Instance.new("Part")
	segment.Name = "TentacleSegment_" .. index
	segment.Size = Vector3.new(width, segmentLength, width)
	segment.Anchored = true  -- Anchored for procedural CFrame animation
	segment.CanCollide = false
	segment.CanQuery = false
	segment.CanTouch = false
	segment.CastShadow = true
	segment.Color = lerpColor(TENTACLE_CONFIG.TentacleColor, TENTACLE_CONFIG.TentacleTipColor, t)
	segment.Material = TENTACLE_CONFIG.TentacleMaterial
	segment.Parent = parent
	
	-- Cylinder mesh for rounded tentacle look
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Cylinder
	mesh.Parent = segment
	
	return segment
end

-- Create tentacles for an entity
local function createTentacles(tentacleFolder, head)
	local tentacles = {}
	local segmentLength = TENTACLE_CONFIG.TentacleLength / TENTACLE_CONFIG.TentacleSegments
	
	for i = 1, TENTACLE_CONFIG.TentacleCount do
		-- Get direction for this tentacle (fibonacci sphere distribution)
		local dir = fibonacciSphere(i - 1, TENTACLE_CONFIG.TentacleCount)
		
		local tentacle = {
			segments = {},
			direction = dir,
			index = i,
			phaseOffset = i * (math.pi * 2 / TENTACLE_CONFIG.TentacleCount),
		}
		
		-- Create segments
		for segIndex = 1, TENTACLE_CONFIG.TentacleSegments do
			local segment = createTentacleSegment(
				segIndex,
				TENTACLE_CONFIG.TentacleSegments,
				TENTACLE_CONFIG.TentacleBaseWidth,
				TENTACLE_CONFIG.TentacleTipWidth,
				segmentLength,
				tentacleFolder
			)
			table.insert(tentacle.segments, segment)
		end
		
		table.insert(tentacles, tentacle)
	end
	
	return tentacles
end

-- Find the Head MeshPart of a humanoid model
local function findHead(model)
	-- Look for Head MeshPart (recursive search)
	local head = model:FindFirstChild("Head", true)
	if head and (head:IsA("MeshPart") or head:IsA("BasePart")) then
		return head
	end
	
	return nil
end

-- Process an entity: create tentacles on head
local function processEntity(self, entity: Model)
	task.wait(5)
	
	-- Skip if already processed
	if self._processedEntities[entity] then
		return
	end
	
	-- Make sure it's a humanoid character
	local humanoid = entity:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		warn("[EntityTentacleController] Entity has no Humanoid:", entity.Name)
		return
	end
	
	-- Find the head
	local head = findHead(entity)
	if not head then
		warn("[EntityTentacleController] Entity has no Head:", entity.Name)
		-- Watch for head being added later
		entity.DescendantAdded:Connect(function(d)
			if d:IsA("BasePart") and d.Name == "Head" and not self._processedEntities[entity] then
				print("[EntityTentacleController] Head added later, processing:", entity.Name)
				processEntity(self, entity)
			end
		end)
		return
	end
	
	-- Mark as processed
	self._processedEntities[entity] = true
	
	print("[EntityTentacleController] Adding tentacles to:", entity.Name, "on head:", head.Name)
	
	-- Create a folder to hold tentacle segments
	local tentacleFolder = Instance.new("Folder")
	tentacleFolder.Name = "Tentacles_" .. entity.Name
	tentacleFolder.Parent = entity
	
	-- Create tentacles
	local tentacles = createTentacles(tentacleFolder, head)
	
	-- Store entity data for animation updates
	local entityData = {
		model = entity,
		head = head,
		tentacles = tentacles,
		tentacleFolder = tentacleFolder,
	}
	
	self._entityData[entity] = entityData
	
	-- Register tentacle folder with streaming culling controller for fog-aligned culling
	if self._streamingCullingController and tentacleFolder then
		self._streamingCullingController:RegisterEntity(tentacleFolder, "entityTentacles")
		CollectionService:AddTag(tentacleFolder, "clientEntity")  -- For auto-tracking
	end
	
	-- Cleanup when entity is removed
	entity.AncestryChanged:Connect(function(_, parent)
		if not parent then
			self._processedEntities[entity] = nil
			self._entityData[entity] = nil
		end
	end)
	
	print("[EntityTentacleController] Successfully added", #tentacles, "tentacles to", entity.Name)
end

-- Update tentacle animation procedurally (pure CFrame manipulation)
local function updateTentacleAnimation(entityData, currentTime)
	local head = entityData.head
	if not head or not head.Parent then
		return
	end
	
	local headPos = head.Position
	local headCF = head.CFrame
	local headSize = head.Size
	local headRadius = math.max(headSize.X, headSize.Z, headSize.Y) / 2
	
	local segmentLength = TENTACLE_CONFIG.TentacleLength / TENTACLE_CONFIG.TentacleSegments
	
	for _, tentacle in ipairs(entityData.tentacles) do
		local baseDir = tentacle.direction
		local phaseOffset = tentacle.phaseOffset
		
		-- Transform base direction by head rotation (tentacles follow head orientation)
		local rotatedBaseDir = headCF:VectorToWorldSpace(baseDir)
		
		-- Starting position at head surface
		local currentPos = headPos + rotatedBaseDir * headRadius
		local currentDir = rotatedBaseDir
		
		for i, segment in ipairs(tentacle.segments) do
			if not segment or not segment.Parent then continue end
			
			local t = i / #tentacle.segments
			
			-- Calculate wiggle for this segment
			local wavePhase = currentTime * TENTACLE_CONFIG.WaveSpeed - t * math.pi * 2
			local wigglePhase = currentTime * TENTACLE_CONFIG.WiggleSpeed + phaseOffset
			
			-- Wiggle increases towards tip
			local wiggleAmount = TENTACLE_CONFIG.WiggleAmplitude * t * t
			local idleAmount = TENTACLE_CONFIG.IdleSwayAmplitude
			
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
			local idleX = math.sin(currentTime * TENTACLE_CONFIG.IdleSwaySpeed + phaseOffset) * idleAmount
			local idleZ = math.cos(currentTime * TENTACLE_CONFIG.IdleSwaySpeed * 0.8 + phaseOffset * 1.5) * idleAmount
			
			-- Combine rotations
			local totalRotX = wiggleX + idleX
			local totalRotZ = wiggleZ + idleZ
			
			-- Apply rotation to direction
			local rotatedDir = CFrame.fromAxisAngle(right, totalRotX) * CFrame.fromAxisAngle(up, totalRotZ) * CFrame.new(currentDir)
			currentDir = rotatedDir.Position.Unit
			
			-- Add slight gravity influence (tentacles droop slightly)
			local gravityInfluence = t * 0.1 * math.max(0, -baseDir.Y + 0.5)
			currentDir = (currentDir + Vector3.new(0, -gravityInfluence, 0)).Unit
			
			-- Calculate segment center position
			local segmentCenter = currentPos + currentDir * (segmentLength / 2)
			
			-- Create CFrame: position at center, oriented along current direction
			-- Cylinder mesh is oriented along X axis, so we need to rotate 90 degrees
			local lookCF = CFrame.lookAt(segmentCenter, segmentCenter + currentDir)
			local finalCF = lookCF * CFrame.Angles(0, 0, math.rad(90))
			
			-- Set segment CFrame directly (procedural animation)
			segment.CFrame = finalCF
			
			-- Move to next segment position (tip of current segment)
			currentPos = currentPos + currentDir * segmentLength
		end
	end
end

-- === KNIT LIFECYCLE ===

function EntityTentacleController:KnitInit()
	warn("[EntityTentacleController] Initializing...")
	
	-- Get reference to streaming culling controller
	task.spawn(function()
		local success, controller = pcall(function()
			return Knit.GetController("StreamingCullingController")
		end)
		if success and controller then
			self._streamingCullingController = controller
			print("[EntityTentacleController] Connected to StreamingCullingController for fog-based culling")
		end
	end)
end

function EntityTentacleController:KnitStart()
	-- Wait a bit for entities to be spawned and tagged
	task.wait(10)
	
	-- Process existing entities with the tag
	local entities = CollectionService:GetTagged(TENTACLE_CONFIG.EntityTag)
	warn(string.format("[EntityTentacleController] Found %d entities with tag '%s'", #entities, TENTACLE_CONFIG.EntityTag))
	
	for _, entity in ipairs(entities) do
		if entity and entity:IsA("Model") and entity.Parent then
			task.spawn(function()
				processEntity(self, entity)
			end)
		end
	end
	
	-- Listen for new entities being added with the tag
	CollectionService:GetInstanceAddedSignal(TENTACLE_CONFIG.EntityTag):Connect(function(entity)
		if entity:IsA("Model") then
			task.spawn(function()
				processEntity(self, entity)
			end)
		end
	end)
	
	-- Animation loop - runs every frame
	local startTime = tick()
	RunService.Heartbeat:Connect(function()
		local currentTime = tick() - startTime
		
		for _, entityData in pairs(self._entityData) do
			updateTentacleAnimation(entityData, currentTime)
		end
	end)
	
	print("[EntityTentacleController] Started!")
end

return EntityTentacleController
