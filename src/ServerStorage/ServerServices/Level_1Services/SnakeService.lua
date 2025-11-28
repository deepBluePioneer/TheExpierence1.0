local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local Knit = require(Packages.Knit)

local SnakeService = Knit.CreateService {
	Name = "SnakeService",
	Client = {},
	snakes = {},
}

-- === CONFIG ===
local SNAKE_CONFIG = {
	-- Spawning
	SnakeCount = 1,
	
	-- Body structure (no head, just long body)
	SegmentCount = 150,          -- MUCH longer snake
	HeadEnabled = false,         -- No head
	BodyStartSize = 4,           -- Size at front
	BodyEndSize = 0.8,           -- Size at tail (tapers)
	SegmentSpacing = 2,          -- Distance between segment centers
	
	-- Colors
	BodyColors = {
		Color3.fromRGB(60, 80, 50),    -- Dark green
		Color3.fromRGB(70, 90, 55),    -- Green
		Color3.fromRGB(50, 70, 45),    -- Darker green
	},
	BellyColor = Color3.fromRGB(180, 170, 140),  -- Pale belly
	
	-- Movement (slow, forward-focused, organic)
	MoveSpeed = 4,               -- Slow crawl
	SlitherFrequency = 0.4,      -- Slow wave movement
	SlitherAmplitude = 1.5,      -- Minimal side-to-side
	SlitherWaveLength = 0.08,    -- Tighter waves for longer body
	SlitherVariation = 0.5,      -- Random variation in amplitude
	
	-- Front segment bobbing
	HeadBobAmount = 0.1,
	HeadBobSpeed = 0.8,
	
	-- Following delay (creates the trailing effect)
	FollowSmoothing = 0.15,      -- How quickly segments catch up
	HistoryLength = 500,         -- Larger history for longer snake
	HistorySpacing = 2,          -- Tighter spacing for smoother following
	
	-- AI Behavior
	WanderEnabled = true,
	TurnSpeed = 1.5,             -- How fast it turns
	DirectionChangeTime = 3,     -- Seconds between direction changes
	
	-- Ground height
	GroundOffset = 1.5,          -- How high above ground
}

local FOLDER_NAME = "Snakes"

-- === HELPERS ===

local function getSnakeFolder()
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

local function lerp(a, b, t)
	return a + (b - a) * t
end

local function lerpVector(a, b, t)
	return a:Lerp(b, t)
end

-- === SEGMENT CREATION ===

local function createSegment(index, totalSegments, parent)
	local config = SNAKE_CONFIG
	
	-- Calculate size (tapers from head to tail)
	local t = index / totalSegments
	local size = lerp(config.BodyStartSize, config.BodyEndSize, t)
	
	-- Pick color with slight variation
	local baseColor = config.BodyColors[math.random(1, #config.BodyColors)]
	local colorVariation = 0.1
	local color = Color3.new(
		math.clamp(baseColor.R + (math.random() - 0.5) * colorVariation, 0, 1),
		math.clamp(baseColor.G + (math.random() - 0.5) * colorVariation, 0, 1),
		math.clamp(baseColor.B + (math.random() - 0.5) * colorVariation, 0, 1)
	)
	
	local segment = Instance.new("Part")
	segment.Name = "Segment_" .. index
	segment.Shape = Enum.PartType.Ball
	segment.Size = Vector3.new(size, size * 0.8, size * 1.2)  -- Slightly oval
	segment.Color = color
	segment.Material = Enum.Material.SmoothPlastic
	segment.Anchored = true
	segment.CanCollide = false
	segment.Parent = parent
	
	return segment
end

local function createHead(parent)
	local config = SNAKE_CONFIG
	
	-- Head (slightly triangular/pointed)
	local head = Instance.new("Part")
	head.Name = "Head"
	head.Size = Vector3.new(config.HeadSize, config.HeadSize * 0.7, config.HeadSize * 1.4)
	head.Color = config.BodyColors[1]
	head.Material = Enum.Material.SmoothPlastic
	head.Anchored = true
	head.CanCollide = false
	head.Parent = parent
	
	-- Make it more head-shaped
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Scale = Vector3.new(1, 0.7, 1.3)
	mesh.Parent = head
	
	-- Eyes
	local eyes = {}
	for i = 1, 2 do
		local side = (i == 1) and 1 or -1
		
		local eye = Instance.new("Part")
		eye.Name = "Eye"
		eye.Shape = Enum.PartType.Ball
		eye.Size = Vector3.new(0.8, 0.8, 0.8)
		eye.Color = config.EyeColor
		eye.Material = Enum.Material.Neon
		eye.Anchored = true
		eye.CanCollide = false
		eye.Parent = parent
		
		-- Pupil
		local pupil = Instance.new("Part")
		pupil.Name = "Pupil"
		pupil.Shape = Enum.PartType.Ball
		pupil.Size = Vector3.new(0.4, 0.5, 0.3)
		pupil.Color = Color3.fromRGB(20, 20, 20)
		pupil.Material = Enum.Material.SmoothPlastic
		pupil.Anchored = true
		pupil.CanCollide = false
		pupil.Parent = parent
		
		table.insert(eyes, {eye = eye, pupil = pupil, side = side})
	end
	
	-- Tongue (forked)
	local tongue = Instance.new("Part")
	tongue.Name = "Tongue"
	tongue.Size = Vector3.new(0.15, 0.1, 2)
	tongue.Color = Color3.fromRGB(200, 80, 100)
	tongue.Material = Enum.Material.SmoothPlastic
	tongue.Anchored = true
	tongue.CanCollide = false
	tongue.Transparency = 0
	tongue.Parent = parent
	
	return head, eyes, tongue
end

-- === SNAKE CREATION ===

local function createSnake(startPosition, groundY, folder)
	local config = SNAKE_CONFIG
	
	local model = Instance.new("Model")
	model.Name = "Snake_" .. math.random(1000, 9999)
	model.Parent = folder
	
	-- Optionally create head (or use first segment as lead)
	local head, eyes, tongue = nil, nil, nil
	if config.HeadEnabled ~= false then
		head, eyes, tongue = createHead(model)
		head.Position = startPosition
	end
	
	-- Create body segments
	local segments = {}
	for i = 1, config.SegmentCount do
		local segment = createSegment(i, config.SegmentCount, model)
		-- Start all segments at start position (they'll spread out)
		segment.Position = startPosition - Vector3.new(0, 0, i * config.SegmentSpacing)
		table.insert(segments, segment)
	end
	
	-- Set primary part (head if exists, otherwise first segment)
	model.PrimaryPart = head or segments[1]
	
	-- Position history for smooth following
	local positionHistory = {}
	for i = 1, config.HistoryLength do
		table.insert(positionHistory, startPosition)
	end
	
	return {
		model = model,
		head = head,
		eyes = eyes,
		tongue = tongue,
		segments = segments,
		positionHistory = positionHistory,
		historyIndex = 1,
		
		-- Movement state
		position = startPosition,
		groundY = groundY,
		facing = Vector3.new(0, 0, 1),
		targetFacing = Vector3.new(0, 0, 1),
		
		-- Animation state
		slitherPhase = 0,
		tonguePhase = 0,
		tongueOut = false,
		
		-- AI state
		directionTimer = 0,
		wanderAngle = math.random() * math.pi * 2,
	}
end

-- === SNAKE MOVEMENT ===

local function updateSnake(snake, deltaTime)
	local config = SNAKE_CONFIG
	
	-- Check if snake still exists (use head if available, otherwise first segment)
	local leadPart = snake.head or (snake.segments[1])
	if not leadPart or not leadPart.Parent then return end
	
	-- === AI: Wander behavior ===
	if config.WanderEnabled then
		snake.directionTimer = snake.directionTimer - deltaTime
		if snake.directionTimer <= 0 then
			-- Pick new random direction
			snake.wanderAngle = snake.wanderAngle + (math.random() - 0.5) * math.pi * 0.8
			snake.directionTimer = config.DirectionChangeTime * (0.5 + math.random())
		end
		
		snake.targetFacing = Vector3.new(
			math.cos(snake.wanderAngle),
			0,
			math.sin(snake.wanderAngle)
		).Unit
	end
	
	-- Smoothly turn toward target direction
	snake.facing = snake.facing:Lerp(snake.targetFacing, deltaTime * config.TurnSpeed)
	if snake.facing.Magnitude > 0.1 then
		snake.facing = snake.facing.Unit
	end
	
	-- === Slithering motion (organic, non-uniform) ===
	snake.slitherPhase = snake.slitherPhase + deltaTime * config.SlitherFrequency * math.pi * 2
	
	-- Initialize variation phase if not set
	if not snake.variationPhase then
		snake.variationPhase = math.random() * math.pi * 2
		snake.variationSpeed = 0.3 + math.random() * 0.4
	end
	snake.variationPhase = snake.variationPhase + deltaTime * snake.variationSpeed
	
	-- Non-uniform slither: combine multiple waves for organic feel
	local primaryWave = math.sin(snake.slitherPhase)
	local secondaryWave = math.sin(snake.slitherPhase * 0.7 + 1.3) * 0.3  -- Offset secondary wave
	local variation = math.sin(snake.variationPhase) * (config.SlitherVariation or 0.5)
	
	-- Amplitude varies over time
	local currentAmplitude = config.SlitherAmplitude * (1 + variation)
	local slitherOffset = (primaryWave + secondaryWave) * currentAmplitude
	
	local perpendicular = Vector3.new(-snake.facing.Z, 0, snake.facing.X)
	
	-- Move forward with slight speed variation
	local speedVariation = 1 + math.sin(snake.variationPhase * 1.7) * 0.15
	local moveAmount = config.MoveSpeed * deltaTime * speedVariation
	snake.position = snake.position + snake.facing * moveAmount
	
	-- Subtle head bob
	local headBob = math.sin(snake.slitherPhase * 1.5 + snake.variationPhase) * config.HeadBobAmount
	
	-- Final head position with minimal slither
	local headPos = snake.position + perpendicular * slitherOffset + Vector3.new(0, config.GroundOffset + headBob, 0)
	
	-- Store position in history (circular buffer)
	snake.positionHistory[snake.historyIndex] = headPos
	snake.historyIndex = (snake.historyIndex % config.HistoryLength) + 1
	
	-- === Update head (if exists) ===
	if snake.head then
		-- CFrame.lookAt points -Z toward target, so we look backward and rotate 180
		-- This makes the elongated +Z part of the head face the movement direction
		local headLookTarget = headPos + snake.facing * 10
		snake.head.CFrame = CFrame.lookAt(headPos, headLookTarget) * CFrame.Angles(0, math.pi, 0)
		
		-- === Update eyes ===
		if snake.eyes then
			for _, eyeData in ipairs(snake.eyes) do
				local eyeOffset = Vector3.new(
					eyeData.side * config.HeadSize * 0.35,
					config.HeadSize * 0.15,
					-config.HeadSize * 0.5
				)
				local eyeWorldPos = snake.head.CFrame:PointToWorldSpace(eyeOffset)
				eyeData.eye.Position = eyeWorldPos
				
				local pupilOffset = eyeOffset + Vector3.new(0, 0, -0.25)
				local pupilWorldPos = snake.head.CFrame:PointToWorldSpace(pupilOffset)
				eyeData.pupil.Position = pupilWorldPos
			end
		end
		
		-- === Update tongue ===
		if snake.tongue then
			snake.tonguePhase = snake.tonguePhase + deltaTime
			if snake.tonguePhase > 2 then
				snake.tongueOut = not snake.tongueOut
				snake.tonguePhase = 0
			end
			
			local tongueExtend = snake.tongueOut and math.sin(snake.tonguePhase * 15) * 0.5 + 0.5 or 0
			local tongueOffset = Vector3.new(0, -0.1, -(config.HeadSize * 0.7 + tongueExtend * 1.5))
			local tongueWorldPos = snake.head.CFrame:PointToWorldSpace(tongueOffset)
			snake.tongue.CFrame = CFrame.lookAt(tongueWorldPos, tongueWorldPos + snake.facing)
			snake.tongue.Size = Vector3.new(0.15, 0.1, 1 + tongueExtend * 1.5)
			snake.tongue.Transparency = snake.tongueOut and 0 or 1
		end
	end
	
	-- === Update body segments (follow the head with delay) ===
	for i, segment in ipairs(snake.segments) do
		-- Calculate which history position this segment should be at
		local historyOffset = i * config.HistorySpacing
		local historyIdx = (snake.historyIndex - historyOffset - 1) % config.HistoryLength + 1
		
		-- Get the target position from history
		local targetPos = snake.positionHistory[historyIdx]
		
		-- Minimal body slither - mostly follows the head's path
		-- Only add very subtle wave that diminishes quickly
		local segmentPhase = snake.slitherPhase - i * config.SlitherWaveLength
		local segmentVariation = math.sin(segmentPhase + snake.variationPhase * 0.5)
		
		-- Rapidly diminish amplitude for body (most motion is from following head)
		local taperFactor = math.max(0, 1 - (i / config.SegmentCount) * 1.5)
		taperFactor = taperFactor * taperFactor  -- Quadratic falloff
		local segmentSlither = segmentVariation * config.SlitherAmplitude * taperFactor * 0.3
		
		-- Get direction for this segment (toward previous segment)
		local prevPos
		if i == 1 then
			prevPos = headPos
		else
			prevPos = snake.segments[i - 1].Position
		end
		
		local towardPrev = (prevPos - segment.Position)
		local segmentFacing = towardPrev.Magnitude > 0.1 and towardPrev.Unit or snake.facing
		local segmentPerp = Vector3.new(-segmentFacing.Z, 0, segmentFacing.X)
		
		-- Apply minimal slither offset - body mostly just follows
		local slitherPos = targetPos + segmentPerp * segmentSlither
		
		-- Smoothly move segment (tighter following)
		local smoothing = config.FollowSmoothing * 1.5
		segment.Position = segment.Position:Lerp(slitherPos, smoothing)
		
		-- Orient segment to face toward the head (forward direction)
		local lookDir = (prevPos - segment.Position)
		if lookDir.Magnitude > 0.1 then
			-- Rotate 180 so the elongated part faces forward
			segment.CFrame = CFrame.lookAt(segment.Position, segment.Position + lookDir) * CFrame.Angles(0, math.pi, 0)
		end
	end
end

-- === GENERATION ===

local function generateSnakes(self)
	local folder = getSnakeFolder()
	folder:ClearAllChildren()
	
	local baseplateInfo = getBaseplateInfo()
	if not baseplateInfo then
		warn("[SnakeService] No Baseplate found!")
		return
	end
	
	local groundY = baseplateInfo.topY
	
	for i = 1, SNAKE_CONFIG.SnakeCount do
		local angle = math.random() * math.pi * 2
		local radius = math.random() * 50
		
		local x = baseplateInfo.position.X + math.cos(angle) * radius
		local z = baseplateInfo.position.Z + math.sin(angle) * radius
		local y = groundY + SNAKE_CONFIG.GroundOffset
		
		local snake = createSnake(Vector3.new(x, y, z), groundY, folder)
		table.insert(self.snakes, snake)
		
		print(string.format("[SnakeService] Spawned snake %d with %d segments", i, SNAKE_CONFIG.SegmentCount))
	end
	
	-- Animation loop
	RunService.Heartbeat:Connect(function(deltaTime)
		for _, snake in ipairs(self.snakes) do
			updateSnake(snake, deltaTime)
		end
	end)
end

-- === KNIT LIFECYCLE ===

function SnakeService:KnitInit()
	-- Nothing
end

function SnakeService:KnitStart()
	task.delay(2, function()
		generateSnakes(self)
	end)
end

-- === PUBLIC METHODS ===

function SnakeService:SpawnSnake(position)
	local baseplateInfo = getBaseplateInfo()
	local groundY = baseplateInfo and baseplateInfo.topY or 0
	
	local folder = getSnakeFolder()
	local snake = createSnake(position, groundY, folder)
	table.insert(self.snakes, snake)
	
	return snake
end

function SnakeService:ClearSnakes()
	self.snakes = {}
	local folder = Workspace:FindFirstChild(FOLDER_NAME)
	if folder then
		folder:ClearAllChildren()
	end
end

function SnakeService:SetSnakeTarget(snake, targetPosition)
	if snake then
		local toTarget = (targetPosition - snake.position)
		toTarget = Vector3.new(toTarget.X, 0, toTarget.Z)
		if toTarget.Magnitude > 0.1 then
			snake.targetFacing = toTarget.Unit
		end
	end
end

return SnakeService

