--[[
	EntityTentacleController (CLIENT-SIDE)
	Finds entities with "entity" tag and adds animated tentacles to their heads
]]

local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")

local Packages = game:GetService("ReplicatedStorage"):WaitForChild("Packages")
local Knit = require(Packages.Knit)

local EntityTentacleController = Knit.CreateController {
	Name = "EntityTentacleController",
	_processedEntities = {},  -- Track entities we've already processed
	_entityData = {},  -- Store tentacle data for each entity
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
	IdleSwaySpeed = 0.5,             -- Slow idle swaying
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

-- Get attachment point for tentacles (use PrimaryPart or first BasePart)
local function getAttachmentPoint(model)
	if model.PrimaryPart and model.PrimaryPart:IsA("BasePart") then
		return model.PrimaryPart
	end
	
	-- Find first BasePart
	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") then
			return part
		end
	end
	
	return nil
end

-- Create a tentacle segment
local function createTentacleSegment(index, totalSegments, baseWidth, tipWidth, segmentLength, parent)
	local t = index / totalSegments
	local width = lerp(baseWidth, tipWidth, t)
	
	local segment = Instance.new("Part")
	segment.Name = "TentacleSegment_" .. index
	segment.Size = Vector3.new(width, segmentLength, width)
	segment.Anchored = false  -- Unanchored to attach to head
	segment.CanCollide = false
	segment.Massless = true  -- Don't add weight
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
local function createTentacles(entityModel, attachmentPart)
	local tentacles = {}
	local segmentLength = TENTACLE_CONFIG.TentacleLength / TENTACLE_CONFIG.TentacleSegments
	
	-- Get attachment part size for attachment point
	local partSize = attachmentPart.Size
	local partRadius = math.max(partSize.X, partSize.Z, partSize.Y) / 2
	
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
				entityModel
			)
			table.insert(tentacle.segments, segment)
		end
		
		table.insert(tentacles, tentacle)
	end
	
	return tentacles
end

-- Get or create attachment at specific position
local function getOrCreateAttachment(part, attachmentName, worldPosition)
	local attachment = part:FindFirstChild(attachmentName)
	if not attachment then
		attachment = Instance.new("Attachment")
		attachment.Name = attachmentName
		attachment.Parent = part
		
		-- Position attachment based on name or world position
		if worldPosition then
			-- Convert world position to local space
			attachment.WorldPosition = worldPosition
		elseif attachmentName == "BaseAttachment" then
			-- At the base (center of part, offset by half length)
			attachment.Position = Vector3.new(0, -part.Size.Y / 2, 0)
		elseif attachmentName == "TipAttachment" then
			-- At the tip (center of part, offset by half length)
			attachment.Position = Vector3.new(0, part.Size.Y / 2, 0)
		elseif attachmentName == "OrientationAttachment" then
			-- At center for orientation
			attachment.Position = Vector3.new(0, 0, 0)
		end
	end
	return attachment
end

-- Attach tentacles to attachment part using constraints
local function attachTentaclesToPart(tentacles, attachmentPart, entityData)
	for _, tentacle in ipairs(tentacles) do
		if #tentacle.segments > 0 then
			local baseDir = tentacle.direction
			
			-- Calculate attachment point on part surface
			local partSize = attachmentPart.Size
			local partRadius = math.max(partSize.X, partSize.Z, partSize.Y) / 2
			local partCF = attachmentPart.CFrame
			local rotatedBaseDir = partCF:VectorToWorldSpace(baseDir)
			local attachmentWorldPos = attachmentPart.Position + rotatedBaseDir * partRadius
			
			-- First segment: use BallSocketConstraint to attachment part with AlignPosition for animation
			local firstSegment = tentacle.segments[1]
			if firstSegment and attachmentPart then
				
				-- BallSocketConstraint for flexible attachment
				local ballSocket = Instance.new("BallSocketConstraint")
				ballSocket.Attachment0 = getOrCreateAttachment(attachmentPart, "TentacleAttachment_" .. tentacle.index, attachmentWorldPos)
				ballSocket.Attachment1 = getOrCreateAttachment(firstSegment, "BaseAttachment")
				ballSocket.LimitsEnabled = true
				ballSocket.UpperAngle = 45
				ballSocket.Parent = firstSegment
				
				-- AlignPosition for animation control
				local alignPos = Instance.new("AlignPosition")
				alignPos.Attachment0 = ballSocket.Attachment0
				alignPos.Attachment1 = ballSocket.Attachment1
				alignPos.MaxForce = 10000
				alignPos.MaxVelocity = 50
				alignPos.Responsiveness = 50
				alignPos.Parent = firstSegment
				
				-- Store for animation updates
				tentacle.baseAlignPosition = alignPos
				tentacle.attachmentPart = attachmentPart
				tentacle.attachmentPoint = ballSocket.Attachment0
			end
			
			-- Subsequent segments: BallSocketConstraint to previous segment
			for i = 2, #tentacle.segments do
				local prevSegment = tentacle.segments[i - 1]
				local currSegment = tentacle.segments[i]
				if prevSegment and currSegment then
					-- BallSocketConstraint
					local ballSocket = Instance.new("BallSocketConstraint")
					ballSocket.Attachment0 = getOrCreateAttachment(prevSegment, "TipAttachment")
					ballSocket.Attachment1 = getOrCreateAttachment(currSegment, "BaseAttachment")
					ballSocket.LimitsEnabled = true
					ballSocket.UpperAngle = 30
					ballSocket.Parent = currSegment
					
					-- AlignPosition for animation
					local alignPos = Instance.new("AlignPosition")
					alignPos.Attachment0 = ballSocket.Attachment0
					alignPos.Attachment1 = ballSocket.Attachment1
					alignPos.MaxForce = 10000
					alignPos.MaxVelocity = 50
					alignPos.Responsiveness = 50
					alignPos.Parent = currSegment
					
					-- Store for animation updates
					if not tentacle.segmentAlignPositions then
						tentacle.segmentAlignPositions = {}
					end
					tentacle.segmentAlignPositions[i] = alignPos
				end
			end
		end
	end
end

-- Process an entity: create tentacles
local function processEntity(self, entity: Model)
	-- Make sure it's a humanoid character
	local humanoid = entity:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end

	print("Coloring entity:", entity.Name)

	-- Helper to color a single part
	local function colorPart(part: BasePart)
		part.BrickColor = BrickColor.new("Bright yellow")

		-- Optional: strip decals/textures so the color shows
		for _, child in ipairs(part:GetChildren()) do
			if child:IsA("Decal") or child:IsA("Texture") then
				child:Destroy()
			end
		end
	end

	-- 1) Color any parts that already exist
	local foundAny = false
	for _, d in ipairs(entity:GetDescendants()) do
		if d:IsA("BasePart") then
			foundAny = true
			colorPart(d)
		end
	end

	if not foundAny then
		print("No BaseParts yet on", entity.Name, "- will watch for new ones.")
	end

	-- 2) Also color parts that get added later (when the rig actually spawns)
	entity.DescendantAdded:Connect(function(d)
		if d:IsA("BasePart") then
			print("New part added to", entity.Name, "->", d.Name, "(", d.ClassName, ")")
			colorPart(d)
		end
	end)
end





-- Update tentacle animation using AlignPosition constraints
local function updateTentacleAnimation(entityData, deltaTime, currentTime)
	if not entityData.model or not entityData.model.Parent then
		return
	end
	
	local attachmentPart = entityData.attachmentPart
	if not attachmentPart or not attachmentPart.Parent then
		return
	end
	
	local partPos = attachmentPart.Position
	local partCF = attachmentPart.CFrame
	local partSize = attachmentPart.Size
	local partRadius = math.max(partSize.X, partSize.Z, partSize.Y) / 2
	
	for _, tentacle in ipairs(entityData.tentacles) do
		local baseDir = tentacle.direction
		local phaseOffset = tentacle.phaseOffset
		local segmentLength = TENTACLE_CONFIG.TentacleLength / TENTACLE_CONFIG.TentacleSegments
		
		-- Transform base direction by attachment part rotation
		local rotatedBaseDir = partCF:VectorToWorldSpace(baseDir)
		
		-- Starting position at attachment part surface
		local currentPos = partPos + rotatedBaseDir * partRadius
		local currentDir = rotatedBaseDir
		
		-- Update attachment point position (follows part movement)
		if tentacle.attachmentPoint then
			tentacle.attachmentPoint.WorldPosition = currentPos
		end
		
		-- Update first segment's AlignPosition target
		if tentacle.baseAlignPosition and tentacle.baseAlignPosition.Attachment0 then
			tentacle.baseAlignPosition.Attachment0.WorldPosition = currentPos
		end
		
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
			
			-- Add slight gravity influence
			local gravityInfluence = t * 0.1 * math.max(0, -baseDir.Y + 0.5)
			currentDir = (currentDir + Vector3.new(0, -gravityInfluence, 0)).Unit
			
			-- Calculate target position for this segment
			local segmentCenter = currentPos + currentDir * (segmentLength / 2)
			
			-- Update AlignPosition target for this segment
			if i > 1 and tentacle.segmentAlignPositions and tentacle.segmentAlignPositions[i] then
				local alignPos = tentacle.segmentAlignPositions[i]
				if alignPos.Attachment0 then
					alignPos.Attachment0.WorldPosition = segmentCenter
				end
			end
			
			-- Update orientation using AlignOrientation
			local lookCF = CFrame.lookAt(segmentCenter, segmentCenter + currentDir)
			local targetCFrame = lookCF * CFrame.Angles(0, 0, math.rad(90))
			
			-- Get or create AlignOrientation for this segment
			if not segment:FindFirstChild("AlignOrientation") then
				local alignOri = Instance.new("AlignOrientation")
				alignOri.Mode = Enum.OrientationAlignmentMode.OneAttachment
				alignOri.Attachment0 = getOrCreateAttachment(segment, "OrientationAttachment")
				alignOri.MaxTorque = 10000
				alignOri.MaxAngularVelocity = 50
				alignOri.Responsiveness = 50
				alignOri.Parent = segment
			end
			
			local alignOri = segment:FindFirstChild("AlignOrientation")
			if alignOri and alignOri.Attachment0 then
				alignOri.Attachment0.WorldCFrame = targetCFrame
			end
			
			-- Move to next segment position
			currentPos = currentPos + currentDir * segmentLength
		end
	end
end

-- === KNIT LIFECYCLE ===

function EntityTentacleController:KnitInit()
	warn("[EntityTentacleController] Initializing...")
end

function EntityTentacleController:KnitStart()
	-- Wait a bit for entities to be spawned and tagged
	task.wait(10)
	
	-- Process existing entities with the tag
	local entities = CollectionService:GetTagged(TENTACLE_CONFIG.EntityTag)
	warn(string.format("[EntityTentacleController] Found %d entities with tag '%s'", #entities, TENTACLE_CONFIG.EntityTag))
	
	for _, entity in ipairs(entities) do
		if entity and entity:IsA("Model") and entity.Parent then
			processEntity(self, entity)
		end
	end
	
	-- Listen for new entities being added with the tag
	CollectionService:GetInstanceAddedSignal(TENTACLE_CONFIG.EntityTag):Connect(function(entity)
		if entity:IsA("Model") then
			processEntity(self, entity)
		end
	end)
	
	-- Animation loop
	local startTime = tick()
	local lastTime = tick()
	RunService.Heartbeat:Connect(function()
		local currentTime = tick() - startTime
		local now = tick()
		local deltaTime = now - lastTime
		lastTime = now
		
		for _, entityData in pairs(self._entityData) do
			updateTentacleAnimation(entityData, deltaTime, currentTime)
		end
	end)
	
	print("[EntityTentacleController] Started!")
end

return EntityTentacleController

