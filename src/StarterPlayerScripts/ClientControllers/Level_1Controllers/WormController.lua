--[[
	WormController (TWEEN-BASED)
	Giant worm using TweenService for smooth movement
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local Knit = require(Packages.Knit)

local WormController = Knit.CreateController {
	Name = "WormController",
	_worms = {},
}

-- === CONFIGURATION ===
local WORM_CONFIG = {
	-- Worm body
	SegmentCount = 25,
	SegmentLength = 6,
	SegmentRadius = 4,
	HeadRadius = 6,
	TailTaper = 0.3,
	
	-- Colors
	BodyColor = Color3.fromRGB(120, 80, 60),
	HeadColor = Color3.fromRGB(90, 60, 40),
	
	-- Movement
	MoveSpeed = 60,              -- Studs per second
	
	-- Path generation
	TargetRadius = 200,
	MinTargetDistance = 80,
	MaxTargetDistance = 180,
	ArcHeight = 60,
	ArcHeightVariation = 15,
	GroundDepth = -50,
	
	-- Spawning
	SpawnRadius = 150,
	
	-- Dirt mound effect
	DirtMound = {
		Enabled = true,
		RingRadius = 10,          -- Radius of the donut ring
		ChunkCount = 12,          -- Number of dirt chunks in the ring
		ChunkSizeMin = 2,         -- Minimum chunk size
		ChunkSizeMax = 4,         -- Maximum chunk size
		ChunkHeightMin = 1,       -- Min height off ground
		ChunkHeightMax = 3,       -- Max height off ground
		SprayVelocity = 15,       -- How fast chunks fly outward
		LifeTime = 4,             -- How long mounds last (seconds)
		FadeTime = 1.5,           -- Fade out duration
		Color = Color3.fromRGB(90, 70, 50),  -- Dirt color
		ColorVariation = 0.15,    -- Color randomness
	},
}

-- Cache raycast params
local raycastParams = RaycastParams.new()
raycastParams.FilterType = Enum.RaycastFilterType.Exclude
raycastParams.FilterDescendantsInstances = {}

-- === HELPER FUNCTIONS ===

local function getGroundHeight(x, z)
	local excludeList = {}
	
	local wormsFolder = Workspace:FindFirstChild("Worms")
	if wormsFolder then
		table.insert(excludeList, wormsFolder)
	end
	
	-- Exclude debug visualization
	local debugFolder = Workspace:FindFirstChild("ExclusionZoneDebug")
	if debugFolder then
		table.insert(excludeList, debugFolder)
	end
	
	raycastParams.FilterDescendantsInstances = excludeList
	
	local result = Workspace:Raycast(
		Vector3.new(x, 500, z),
		Vector3.new(0, -1000, 0),
		raycastParams
	)
	
	return result and result.Position.Y or 0
end

local function getRandomTerrainSpot(fromX, fromZ)
	local baseplate = Workspace:FindFirstChild("Baseplate")
	local maxRadius = baseplate and math.min(WORM_CONFIG.TargetRadius, baseplate.Size.X / 2 - 20) or WORM_CONFIG.TargetRadius
	
	local angle = math.random() * math.pi * 2
	local distance = WORM_CONFIG.MinTargetDistance + math.random() * (WORM_CONFIG.MaxTargetDistance - WORM_CONFIG.MinTargetDistance)
	
	local targetX = math.clamp(fromX + math.cos(angle) * distance, -maxRadius, maxRadius)
	local targetZ = math.clamp(fromZ + math.sin(angle) * distance, -maxRadius, maxRadius)
	
	return Vector3.new(targetX, getGroundHeight(targetX, targetZ) + WORM_CONFIG.GroundDepth, targetZ)
end

-- === DIRT MOUND EFFECTS ===

local dirtMoundsFolder = nil

local function getDirtFolder()
	if not dirtMoundsFolder or not dirtMoundsFolder.Parent then
		dirtMoundsFolder = Workspace:FindFirstChild("WormDirt") or Instance.new("Folder", Workspace)
		dirtMoundsFolder.Name = "WormDirt"
	end
	return dirtMoundsFolder
end

local function createDirtMound(position, direction, isEmerging)
	if not WORM_CONFIG.DirtMound.Enabled then return end
	
	local config = WORM_CONFIG.DirtMound
	local folder = getDirtFolder()
	
	-- Get ground height at this position
	local groundY = getGroundHeight(position.X, position.Z)
	local groundPos = Vector3.new(position.X, groundY, position.Z)
	
	-- Create dirt chunks in a ring
	local chunks = {}
	for i = 1, config.ChunkCount do
		local angle = (i / config.ChunkCount) * math.pi * 2
		local randomOffset = (math.random() - 0.5) * 0.5  -- Slight randomness
		angle = angle + randomOffset
		
		-- Position in ring
		local ringRadius = config.RingRadius + (math.random() - 0.5) * 3
		local offsetX = math.cos(angle) * ringRadius
		local offsetZ = math.sin(angle) * ringRadius
		
		-- Create chunk
		local chunk = Instance.new("Part")
		chunk.Name = "DirtChunk"
		
		-- Random size
		local size = config.ChunkSizeMin + math.random() * (config.ChunkSizeMax - config.ChunkSizeMin)
		chunk.Size = Vector3.new(
			size * (0.8 + math.random() * 0.4),
			size * (0.5 + math.random() * 0.5),
			size * (0.8 + math.random() * 0.4)
		)
		
		-- Color with variation
		local variation = config.ColorVariation
		local r = math.clamp(config.Color.R + (math.random() - 0.5) * variation, 0, 1)
		local g = math.clamp(config.Color.G + (math.random() - 0.5) * variation, 0, 1)
		local b = math.clamp(config.Color.B + (math.random() - 0.5) * variation, 0, 1)
		chunk.Color = Color3.new(r, g, b)
		
		chunk.Material = Enum.Material.Sand
		chunk.Anchored = true
		chunk.CanCollide = false
		chunk.CastShadow = false
		
		-- Start position (at ground level)
		local startHeight = config.ChunkHeightMin + math.random() * (config.ChunkHeightMax - config.ChunkHeightMin)
		local chunkPos = groundPos + Vector3.new(offsetX, startHeight, offsetZ)
		
		-- Random rotation
		chunk.CFrame = CFrame.new(chunkPos) * CFrame.Angles(
			math.random() * math.pi,
			math.random() * math.pi,
			math.random() * math.pi
		)
		
		chunk.Parent = folder
		table.insert(chunks, chunk)
	end
	
	-- Animate chunks flying outward and settling
	task.spawn(function()
		local sprayTime = 0.3
		local settleTime = 0.5
		
		-- Spray outward animation
		for _, chunk in ipairs(chunks) do
			local startPos = chunk.Position
			local outwardDir = (Vector3.new(startPos.X, groundY, startPos.Z) - groundPos).Unit
			local targetPos = startPos + outwardDir * config.SprayVelocity * 0.3 + Vector3.new(0, math.random() * 2, 0)
			
			local sprayTween = TweenService:Create(chunk, TweenInfo.new(sprayTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				Position = targetPos
			})
			sprayTween:Play()
		end
		
		task.wait(sprayTime)
		
		-- Settle down animation
		for _, chunk in ipairs(chunks) do
			local settlePos = Vector3.new(chunk.Position.X, groundY + chunk.Size.Y / 2, chunk.Position.Z)
			local settleTween = TweenService:Create(chunk, TweenInfo.new(settleTime, Enum.EasingStyle.Bounce, Enum.EasingDirection.Out), {
				Position = settlePos
			})
			settleTween:Play()
		end
		
		-- Wait then fade out
		task.wait(config.LifeTime - config.FadeTime)
		
		-- Fade out
		for _, chunk in ipairs(chunks) do
			local fadeTween = TweenService:Create(chunk, TweenInfo.new(config.FadeTime, Enum.EasingStyle.Linear), {
				Transparency = 1
			})
			fadeTween:Play()
		end
		
		task.wait(config.FadeTime + 0.1)
		
		-- Cleanup
		for _, chunk in ipairs(chunks) do
			chunk:Destroy()
		end
	end)
end

-- Build path with arcs above and below ground
local function buildArcPath(fromPos, toPos)
	local dx = toPos.X - fromPos.X
	local dz = toPos.Z - fromPos.Z
	local deepDepth = WORM_CONFIG.GroundDepth * 1.5
	local arcHeight = WORM_CONFIG.ArcHeight + (math.random() - 0.5) * WORM_CONFIG.ArcHeightVariation * 2
	
	local points = {}
	
	points[1] = fromPos
	
	-- Underground arc (25% along)
	local p1x = fromPos.X + dx * 0.25
	local p1z = fromPos.Z + dz * 0.25
	points[2] = Vector3.new(p1x, getGroundHeight(p1x, p1z) + deepDepth, p1z)
	
	-- Above ground peak (50% along)
	local p2x = fromPos.X + dx * 0.50
	local p2z = fromPos.Z + dz * 0.50
	points[3] = Vector3.new(p2x, getGroundHeight(p2x, p2z) + arcHeight, p2z)
	
	-- Underground arc (75% along)
	local p3x = fromPos.X + dx * 0.75
	local p3z = fromPos.Z + dz * 0.75
	points[4] = Vector3.new(p3x, getGroundHeight(p3x, p3z) + deepDepth, p3z)
	
	points[5] = toPos
	
	return points
end

-- === WORM CREATION ===

local function createWorm(name)
	local folder = Workspace:FindFirstChild("Worms") or Instance.new("Folder", Workspace)
	folder.Name = "Worms"
	
	local wormModel = Instance.new("Model")
	wormModel.Name = name or "SandWorm"
	wormModel.Parent = folder
	
	local segments = {}
	
	-- Create a hidden part for head position (tweened)
	local headTracker = Instance.new("Part")
	headTracker.Name = "HeadTracker"
	headTracker.Size = Vector3.new(1, 1, 1)
	headTracker.Transparency = 1
	headTracker.Anchored = true
	headTracker.CanCollide = false
	headTracker.Parent = wormModel
	
	for i = 1, WORM_CONFIG.SegmentCount do
		local segment = Instance.new("Part")
		segment.Name = "Segment_" .. i
		segment.Shape = Enum.PartType.Cylinder
		
		local taperFactor = 1
		if i == 1 then
			taperFactor = WORM_CONFIG.HeadRadius / WORM_CONFIG.SegmentRadius
		elseif i > WORM_CONFIG.SegmentCount * 0.6 then
			local tailProgress = (i - WORM_CONFIG.SegmentCount * 0.6) / (WORM_CONFIG.SegmentCount * 0.4)
			taperFactor = 1 - (1 - WORM_CONFIG.TailTaper) * tailProgress
		end
		
		local radius = WORM_CONFIG.SegmentRadius * taperFactor
		segment.Size = Vector3.new(WORM_CONFIG.SegmentLength, radius * 2, radius * 2)
		segment.Color = i == 1 and WORM_CONFIG.HeadColor or WORM_CONFIG.BodyColor
		segment.Material = Enum.Material.Sand
		segment.Anchored = true
		segment.CanCollide = false
		segment.CastShadow = false
		segment.Parent = wormModel
		
		segments[i] = segment
	end
	
	wormModel.PrimaryPart = segments[1]
	
	return {
		model = wormModel,
		segments = segments,
		headTracker = headTracker,
		positions = {},
		pathPoints = nil,
		nextPathPoints = nil,
		currentPointIndex = 1,
		currentTween = nil,
		active = true,
		-- Surface crossing detection
		lastHeadY = nil,
		lastGroundY = nil,
		wasUnderground = true,
	}
end

-- === TWEEN-BASED MOVEMENT ===

local function tweenToNextPoint(wormData)
	if not wormData.active then return end
	if not wormData.pathPoints then return end
	
	local targetPoint = wormData.pathPoints[wormData.currentPointIndex]
	if not targetPoint then return end
	
	local currentPos = wormData.headTracker.Position
	local distance = (targetPoint - currentPos).Magnitude
	
	-- Skip very close points without delay
	while distance < 1 and wormData.currentPointIndex < #wormData.pathPoints do
		wormData.currentPointIndex = wormData.currentPointIndex + 1
		targetPoint = wormData.pathPoints[wormData.currentPointIndex]
		if targetPoint then
			distance = (targetPoint - currentPos).Magnitude
		end
	end
	
	if not targetPoint then return end
	
	-- Calculate duration - pure speed-based
	local duration = distance / WORM_CONFIG.MoveSpeed
	
	-- Cancel existing tween
	if wormData.currentTween then
		wormData.currentTween:Cancel()
	end
	
	-- Create tween
	local tweenInfo = TweenInfo.new(
		duration,
		Enum.EasingStyle.Linear,
		Enum.EasingDirection.Out
	)
	
	local tween = TweenService:Create(wormData.headTracker, tweenInfo, {
		Position = targetPoint
	})
	
	wormData.currentTween = tween
	
	-- Pre-generate next path when halfway
	if wormData.currentPointIndex >= 3 and not wormData.nextPathPoints then
		task.spawn(function()
			local startPos = wormData.pathPoints[#wormData.pathPoints]
			local endPos = getRandomTerrainSpot(startPos.X, startPos.Z)
			wormData.nextPathPoints = buildArcPath(startPos, endPos)
		end)
	end
	
	-- When tween completes, move to next point
	tween.Completed:Once(function()
		if not wormData.active then return end
		
		wormData.currentPointIndex = wormData.currentPointIndex + 1
		
		-- Switch paths if needed
		if wormData.currentPointIndex > #wormData.pathPoints then
			if wormData.nextPathPoints then
				wormData.pathPoints = wormData.nextPathPoints
				wormData.nextPathPoints = nil
			else
				local startPos = wormData.pathPoints[#wormData.pathPoints]
				local endPos = getRandomTerrainSpot(startPos.X, startPos.Z)
				wormData.pathPoints = buildArcPath(startPos, endPos)
			end
			wormData.currentPointIndex = 1
		end
		
		-- Use task.defer to break recursion chain
		task.defer(function()
			if wormData.active then
				tweenToNextPoint(wormData)
			end
		end)
	end)
	
	tween:Play()
end

local function updateWormBody(wormData)
	if not wormData.active then return end
	
	local positions = wormData.positions
	local segments = wormData.segments
	local segmentSpacing = WORM_CONFIG.SegmentLength * 0.85
	
	-- Head follows tracker
	local headPos = wormData.headTracker.Position
	positions[1] = headPos
	
	-- Detect surface crossing for dirt mound effect
	local groundY = getGroundHeight(headPos.X, headPos.Z)
	local isUnderground = headPos.Y < groundY
	
	-- Check if we crossed the surface
	if wormData.lastHeadY ~= nil then
		local wasUnder = wormData.wasUnderground
		
		if wasUnder and not isUnderground then
			-- Emerging from ground - create dirt mound!
			local direction = (headPos - Vector3.new(headPos.X, wormData.lastHeadY, headPos.Z)).Unit
			createDirtMound(Vector3.new(headPos.X, groundY, headPos.Z), direction, true)
		elseif not wasUnder and isUnderground then
			-- Diving into ground - create dirt mound!
			local direction = (headPos - Vector3.new(headPos.X, wormData.lastHeadY, headPos.Z)).Unit
			createDirtMound(Vector3.new(headPos.X, groundY, headPos.Z), direction, false)
		end
	end
	
	wormData.lastHeadY = headPos.Y
	wormData.lastGroundY = groundY
	wormData.wasUnderground = isUnderground
	
	-- RIGID FOLLOWING: Each segment is ALWAYS exactly segmentSpacing behind the one ahead
	for i = 2, #segments do
		local leader = positions[i - 1]
		local current = positions[i] or leader
		
		local toLeader = leader - current
		local dist = toLeader.Magnitude
		
		if dist > 0.001 then
			-- Always place segment at fixed distance behind leader
			local dir = toLeader / dist
			positions[i] = leader - dir * segmentSpacing
		else
			-- If somehow overlapping, offset slightly
			positions[i] = leader - Vector3.new(segmentSpacing, 0, 0)
		end
	end
	
	-- Apply to parts - position is rigid, rotation follows direction
	for i, segment in ipairs(segments) do
		local pos = positions[i]
		if pos then
			local leader = positions[i - 1]
			if leader then
				local dir = leader - pos
				if dir.Magnitude > 0.1 then
					-- Set CFrame directly with correct rotation
					local lookCF = CFrame.lookAt(pos, pos + dir.Unit)
					segment.CFrame = lookCF * CFrame.Angles(0, math.rad(90), 0)
				else
					segment.Position = pos
				end
			else
				segment.Position = pos
			end
		end
	end
end

-- === PUBLIC API ===

function WormController:SpawnWorm(x, z, name)
	x = x or math.random(-WORM_CONFIG.SpawnRadius, WORM_CONFIG.SpawnRadius)
	z = z or math.random(-WORM_CONFIG.SpawnRadius, WORM_CONFIG.SpawnRadius)
	
	local groundY = getGroundHeight(x, z)
	local startPos = Vector3.new(x, groundY + WORM_CONFIG.GroundDepth, z)
	
	local wormData = createWorm(name)
	wormData.headTracker.Position = startPos
	
	-- Initialize all segment positions
	for i = 1, #wormData.segments do
		wormData.positions[i] = startPos
	end
	
	-- Generate initial path
	local endPos = getRandomTerrainSpot(startPos.X, startPos.Z)
	wormData.pathPoints = buildArcPath(startPos, endPos)
	wormData.currentPointIndex = 1
	
	table.insert(self._worms, wormData)
	print(string.format("[WormController] Spawned '%s' at (%.0f, %.0f)", name or "SandWorm", x, z))
	
	-- Start movement
	tweenToNextPoint(wormData)
	
	return wormData
end

function WormController:RemoveWorm(wormData)
	for i, w in ipairs(self._worms) do
		if w == wormData then
			w.active = false
			if w.currentTween then
				w.currentTween:Cancel()
			end
			if w.model then w.model:Destroy() end
			table.remove(self._worms, i)
			break
		end
	end
end

function WormController:SetSpeed(speed)
	WORM_CONFIG.MoveSpeed = speed
end

-- === KNIT LIFECYCLE ===

function WormController:KnitInit()
	print("[WormController] Initializing (tween-based)...")
end

function WormController:KnitStart()
	-- Update body segments every frame
	RunService.Heartbeat:Connect(function()
		for _, wormData in ipairs(self._worms) do
			updateWormBody(wormData)
		end
	end)
	
	print("[WormController] Started")
	
	task.delay(5, function()
		local baseplate = Workspace:FindFirstChild("Baseplate")
		local cx = baseplate and baseplate.Position.X or 0
		local cz = baseplate and baseplate.Position.Z or 0
		self:SpawnWorm(cx + (math.random() - 0.5) * 100, cz + (math.random() - 0.5) * 100, "SandWorm_1")
	end)
end

return WormController
