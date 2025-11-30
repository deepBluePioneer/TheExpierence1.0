local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local Lighting = game:GetService("Lighting")
local TweenService = game:GetService("TweenService")
local CollectionService = game:GetService("CollectionService")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local Knit = require(Packages.Knit)
local PartCache = require(Packages.partcache)

local Player = Players.LocalPlayer
local Camera = Workspace.CurrentCamera

local RainController = Knit.CreateController {
	Name = "RainController",
	rainCache = nil,
	splashCache = nil,
	activeDrops = {},
	isRaining = false,        -- Start with no rain (will enable at night)
	lightningEnabled = false, -- Start with no lightning (will enable at night)
	_weatherService = nil,    -- Reference to WeatherService
}

-- === CONFIG ===
local RAIN_CONFIG = {
	-- Rain spawn area (relative to camera)
	SpawnWidth = 80,        -- Width of rain spawn box
	SpawnDepth = 80,        -- Depth of rain spawn box
	SpawnHeight = 60,       -- Height above player to spawn
	
	-- Rain properties
	MaxDrops = 400,         -- Maximum active raindrops
	SpawnRate = 80,         -- Drops per second (more rain)
	FallSpeed = 85,         -- Studs per second
	DropLength = 2.5,       -- Length of raindrop (longer = more visible)
	DropWidth = 0.15,       -- Width of raindrop (thicker = more visible)
	
	-- Splash properties
	MaxSplashes = 200,
	SplashDuration = 0.4,
	SplashSize = 1.2,           -- Larger splashes
	SplashTransparency = 0.2,   -- Starting transparency (more visible)
	
	-- Visual
	RainColor = Color3.fromRGB(220, 235, 255),   -- Brighter white-blue
	RainTransparency = 0.15,                      -- Less transparent (more visible)
	SplashColor = Color3.fromRGB(255, 255, 255), -- Bright white splashes
}

-- === LIGHTNING CONFIG ===
local LIGHTNING_CONFIG = {
	MinInterval = 5,          -- Minimum seconds between lightning
	MaxInterval = 15,         -- Maximum seconds between lightning
	
	-- Lightning bolt appearance
	BoltSpawnHeight = 250,    -- Height above player to spawn
	BoltSpawnRadius = 120,    -- How far from player bolts can spawn
	
	-- Fractal/Random Walk settings
	MainSegments = 12,        -- Segments in main bolt
	SegmentLength = 18,       -- Length of each segment
	MainWidth = 1.0,          -- Main bolt thickness
	JitterAmount = 0.5,       -- How much the bolt zigzags (0-1)
	
	-- Branching
	BranchChance = 0.35,      -- Chance to branch at each segment
	BranchAngleMin = 20,      -- Min angle of branch (degrees)
	BranchAngleMax = 50,      -- Max angle of branch (degrees)
	BranchLengthRatio = 0.6,  -- Branch length relative to remaining main
	BranchWidthRatio = 0.5,   -- Branch width relative to parent
	MaxBranchDepth = 2,       -- How many levels of sub-branches
	
	-- Animation timing
	SegmentRevealTime = 0.015, -- Time between each segment appearing
	LingerTime = 0.8,         -- Time all segments stay visible (even longer!)
	FadeOutTime = 0.25,       -- Time to fade out
	
	-- Visual
	BoltColor = Color3.fromRGB(230, 240, 255),
	GlowColor = Color3.fromRGB(200, 220, 255),
	
	-- Lighting flash (synced with bolt)
	LightingFlashEnabled = true,
	FlashBrightness = 50,      -- Peak brightness during flash (even more intense!)
	FlashAmbient = Color3.fromRGB(255, 255, 255),  -- Pure white ambient
	FlashFadeTime = 0.6,       -- Longer fade to match linger
}

-- === RAINDROP TEMPLATE ===

local function createRainTemplate()
	local drop = Instance.new("Part")
	drop.Name = "RainDrop"
	drop.Size = Vector3.new(RAIN_CONFIG.DropWidth, RAIN_CONFIG.DropLength, RAIN_CONFIG.DropWidth)
	drop.Material = Enum.Material.Glass
	drop.Color = RAIN_CONFIG.RainColor
	drop.Transparency = RAIN_CONFIG.RainTransparency
	drop.CanCollide = false
	drop.Anchored = true
	drop.CastShadow = false
	drop.CanQuery = false
	drop.CanTouch = false
	return drop
end

-- === SPLASH TEMPLATE ===

local function createSplashTemplate()
	local splash = Instance.new("Part")
	splash.Name = "Splash"
	splash.Shape = Enum.PartType.Cylinder
	splash.Size = Vector3.new(0.05, RAIN_CONFIG.SplashSize, RAIN_CONFIG.SplashSize)
	splash.Material = Enum.Material.Glass
	splash.Color = RAIN_CONFIG.SplashColor
	splash.Transparency = 0.5
	splash.CanCollide = false
	splash.Anchored = true
	splash.CastShadow = false
	splash.CanQuery = false
	splash.CanTouch = false
	return splash
end

-- === RAIN FOLDER ===

local function getRainFolder()
	local folder = Workspace:FindFirstChild("RainEffects")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "RainEffects"
		folder.Parent = Workspace
	end
	return folder
end

-- === SPAWN RAINDROP ===

local function getRandomSpawnPosition()
	local camPos = Camera.CFrame.Position
	local offsetX = (math.random() - 0.5) * RAIN_CONFIG.SpawnWidth
	local offsetZ = (math.random() - 0.5) * RAIN_CONFIG.SpawnDepth
	
	return Vector3.new(
		camPos.X + offsetX,
		camPos.Y + RAIN_CONFIG.SpawnHeight,
		camPos.Z + offsetZ
	)
end

local function spawnRaindrop(self)
	if #self.activeDrops >= RAIN_CONFIG.MaxDrops then
		return
	end
	
	local drop = self.rainCache:GetPart()
	if not drop then return end
	
	local spawnPos = getRandomSpawnPosition()
	
	-- Raycast down to find ground
	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	
	-- Exclude rain effects, player, grid cells, and particle groups from raycast
	local gridFolder = Workspace:FindFirstChild("GridCubes")
	local excludeList = {getRainFolder(), Player.Character}
	if gridFolder then
		table.insert(excludeList, gridFolder)
	end
	
	-- Exclude all particle group anchors
	local particleGroups = CollectionService:GetTagged("particleGroup")
	for _, part in ipairs(particleGroups) do
		table.insert(excludeList, part)
	end
	
	-- Exclude debug visualization
	local debugFolder = Workspace:FindFirstChild("ExclusionZoneDebug")
	if debugFolder then
		table.insert(excludeList, debugFolder)
	end
	
	rayParams.FilterDescendantsInstances = excludeList
	
	local rayResult = Workspace:Raycast(spawnPos, Vector3.new(0, -200, 0), rayParams)
	local groundY = rayResult and rayResult.Position.Y or (spawnPos.Y - 100)
	local groundNormal = rayResult and rayResult.Normal or Vector3.yAxis
	local hitInstance = rayResult and rayResult.Instance or nil
	
	-- Position the drop
	drop.CFrame = CFrame.new(spawnPos)
	
	-- Store drop data
	table.insert(self.activeDrops, {
		part = drop,
		position = spawnPos,
		groundY = groundY,
		groundNormal = groundNormal,
		hitInstance = hitInstance,
		velocity = RAIN_CONFIG.FallSpeed,
	})
end

-- === SPLASH EFFECT ===

local function createSplash(self, position, normal)
	local splash = self.splashCache:GetPart()
	if not splash then return end
	
	-- Orient splash to surface normal (cylinder lies flat)
	local cf = CFrame.new(position, position + normal)
	cf = cf * CFrame.Angles(0, 0, math.rad(90))
	splash.CFrame = cf
	splash.Color = RAIN_CONFIG.SplashColor
	
	-- Start size (bigger initial size)
	local startSize = RAIN_CONFIG.SplashSize * 0.4
	splash.Size = Vector3.new(0.1, startSize, startSize)
	splash.Transparency = RAIN_CONFIG.SplashTransparency
	
	-- Animate splash (expand and fade)
	task.spawn(function()
		local startTime = tick()
		local duration = RAIN_CONFIG.SplashDuration
		local startTransparency = RAIN_CONFIG.SplashTransparency
		
		while tick() - startTime < duration do
			local progress = (tick() - startTime) / duration
			-- Expand quickly at first, then slow down
			local easeProgress = 1 - (1 - progress) ^ 2
			local size = RAIN_CONFIG.SplashSize * (0.4 + easeProgress * 0.6)
			splash.Size = Vector3.new(0.1, size, size)
			-- Fade out gradually
			splash.Transparency = startTransparency + (1 - startTransparency) * progress
			task.wait()
		end
		
		self.splashCache:ReturnPart(splash)
	end)
end

-- === LIGHTNING BOLT EFFECT ===

local lightningFolder = nil

local function getLightningFolder()
	if lightningFolder and lightningFolder.Parent then
		return lightningFolder
	end
	lightningFolder = Instance.new("Folder")
	lightningFolder.Name = "LightningBolts"
	lightningFolder.Parent = Workspace
	return lightningFolder
end

local function createBoltSegment(startPos, endPos, width, color)
	local segment = Instance.new("Part")
	segment.Name = "BoltSegment"
	segment.Anchored = true
	segment.CanCollide = false
	segment.CastShadow = false
	segment.CanQuery = false
	segment.CanTouch = false
	segment.Material = Enum.Material.Neon
	segment.Color = color
	segment.Transparency = 1  -- Start invisible
	
	local distance = (endPos - startPos).Magnitude
	local midPoint = (startPos + endPos) / 2
	
	segment.Size = Vector3.new(width, width, distance)
	segment.CFrame = CFrame.lookAt(midPoint, endPos)
	
	return segment
end

-- Recursive fractal bolt generation
local function generateBoltPath(startPos, direction, numSegments, segmentLength, width, depth, allSegments, folder)
	local currentPos = startPos
	local currentDir = direction.Unit
	
	for i = 1, numSegments do
		-- Random walk: add jitter to direction
		local jitter = LIGHTNING_CONFIG.JitterAmount
		local randomAngle = math.rad((math.random() - 0.5) * 60 * jitter)
		local randomTilt = math.rad((math.random() - 0.5) * 30 * jitter)
		
		-- Rotate direction randomly but keep mostly going down
		local rightVec = currentDir:Cross(Vector3.yAxis)
		if rightVec.Magnitude < 0.01 then
			rightVec = Vector3.xAxis
		end
		rightVec = rightVec.Unit
		local upVec = rightVec:Cross(currentDir).Unit
		
		-- Apply rotation
		local newDir = (currentDir + rightVec * math.sin(randomAngle) * 0.5 + upVec * math.sin(randomTilt) * 0.3).Unit
		
		-- Calculate end position
		local actualLength = segmentLength * (0.8 + math.random() * 0.4)
		local endPos = currentPos + newDir * actualLength
		
		-- Create segment data (not the part yet)
		local segmentData = {
			startPos = currentPos,
			endPos = endPos,
			width = width,
			depth = depth,
			part = nil,
		}
		table.insert(allSegments, segmentData)
		
		-- Maybe create a branch (fractal recursion)
		local canBranch = depth < LIGHTNING_CONFIG.MaxBranchDepth
		local remainingSegments = numSegments - i
		
		if canBranch and remainingSegments > 1 and math.random() < LIGHTNING_CONFIG.BranchChance then
			-- Calculate branch direction (angled off to the side)
			local branchAngle = math.rad(
				LIGHTNING_CONFIG.BranchAngleMin + 
				math.random() * (LIGHTNING_CONFIG.BranchAngleMax - LIGHTNING_CONFIG.BranchAngleMin)
			)
			
			-- Random side
			local side = (math.random() > 0.5) and 1 or -1
			local branchDir = (newDir + rightVec * math.sin(branchAngle) * side + Vector3.new(0, -0.3, 0)).Unit
			
			-- Branch has fewer segments and is thinner
			local branchSegments = math.max(2, math.floor(remainingSegments * LIGHTNING_CONFIG.BranchLengthRatio))
			local branchWidth = width * LIGHTNING_CONFIG.BranchWidthRatio
			local branchLength = segmentLength * 0.8
			
			-- Recursively generate branch
			generateBoltPath(endPos, branchDir, branchSegments, branchLength, branchWidth, depth + 1, allSegments, folder)
		end
		
		currentPos = endPos
		currentDir = newDir
	end
end

-- Store original lighting values
local originalLighting = {
	Brightness = nil,
	Ambient = nil,
	OutdoorAmbient = nil,
}

local function storeLightingValues()
	originalLighting.Brightness = Lighting.Brightness
	originalLighting.Ambient = Lighting.Ambient
	originalLighting.OutdoorAmbient = Lighting.OutdoorAmbient
end

local function flashLighting()
	if not LIGHTNING_CONFIG.LightingFlashEnabled then return end
	
	-- Store current values if not stored
	if not originalLighting.Brightness then
		storeLightingValues()
	end
	
	-- Flash ON
	Lighting.Brightness = LIGHTNING_CONFIG.FlashBrightness
	Lighting.Ambient = LIGHTNING_CONFIG.FlashAmbient
	Lighting.OutdoorAmbient = LIGHTNING_CONFIG.FlashAmbient
	
	-- Fade back to original
	task.spawn(function()
		local fadeSteps = 10
		local fadeStepTime = LIGHTNING_CONFIG.FlashFadeTime / fadeSteps
		
		for step = 1, fadeSteps do
			local progress = step / fadeSteps
			-- Lerp back to original
			Lighting.Brightness = LIGHTNING_CONFIG.FlashBrightness + (originalLighting.Brightness - LIGHTNING_CONFIG.FlashBrightness) * progress
			Lighting.Ambient = originalLighting.Ambient:Lerp(LIGHTNING_CONFIG.FlashAmbient, 1 - progress)
			Lighting.OutdoorAmbient = originalLighting.OutdoorAmbient:Lerp(LIGHTNING_CONFIG.FlashAmbient, 1 - progress)
			task.wait(fadeStepTime)
		end
		
		-- Ensure we're back to original
		Lighting.Brightness = originalLighting.Brightness
		Lighting.Ambient = originalLighting.Ambient
		Lighting.OutdoorAmbient = originalLighting.OutdoorAmbient
	end)
end

local function animateLightningBolt(allSegments, folder)
	-- Create all parts
	for _, segData in ipairs(allSegments) do
		local part = createBoltSegment(
			segData.startPos,
			segData.endPos,
			segData.width,
			LIGHTNING_CONFIG.BoltColor
		)
		part.Parent = folder
		segData.part = part
	end
	
	-- Animate: reveal segments one by one (top to bottom)
	task.spawn(function()
		-- Flash lighting when bolt starts
		flashLighting()
		
		for i, segData in ipairs(allSegments) do
			if segData.part then
				segData.part.Transparency = 0
			end
			task.wait(LIGHTNING_CONFIG.SegmentRevealTime)
		end
		
		-- All segments visible - linger
		task.wait(LIGHTNING_CONFIG.LingerTime)
		
		-- Fade out all at once
		local fadeSteps = 8
		local fadeStepTime = LIGHTNING_CONFIG.FadeOutTime / fadeSteps
		
		for step = 1, fadeSteps do
			local transparency = step / fadeSteps
			for _, segData in ipairs(allSegments) do
				if segData.part then
					segData.part.Transparency = transparency
				end
			end
			task.wait(fadeStepTime)
		end
		
		-- Cleanup
		for _, segData in ipairs(allSegments) do
			if segData.part then
				segData.part:Destroy()
			end
		end
	end)
end

local function getBaseplateHeight()
	local baseplate = Workspace:FindFirstChild("Baseplate")
	if baseplate and baseplate:IsA("BasePart") then
		return baseplate.Position.Y + (baseplate.Size.Y / 2)
	end
	return 0
end

local function spawnLightningBolt(self)
	if not self.lightningEnabled then return end
	
	local folder = getLightningFolder()
	
	-- Get camera info
	local camCF = Camera.CFrame
	local camPos = camCF.Position
	local camLook = camCF.LookVector
	local camRight = camCF.RightVector
	
	-- Get horizon height (baseplate level + small offset for horizon effect)
	local baseHeight = getBaseplateHeight()
	local horizonHeight = baseHeight + 30 + math.random() * 40  -- 30-70 studs above baseplate
	
	-- Spawn lightning further away for horizon effect
	local forwardDistance = LIGHTNING_CONFIG.BoltSpawnRadius * (1.5 + math.random() * 1.0)
	
	-- Much wider horizontal spread - can appear far to the sides
	local horizontalSpread = forwardDistance * 1.8  -- Wide spread
	local rightOffset = (math.random() - 0.5) * horizontalSpread
	
	-- Bias toward the edges (less centered)
	if math.abs(rightOffset) < horizontalSpread * 0.2 then
		rightOffset = rightOffset + (math.random() > 0.5 and 1 or -1) * horizontalSpread * 0.3
	end
	
	-- Flatten the look vector to get horizontal direction
	local flatLook = Vector3.new(camLook.X, 0, camLook.Z).Unit
	local flatRight = Vector3.new(camRight.X, 0, camRight.Z).Unit
	
	-- Calculate spawn position on the horizon
	local horizonPoint = camPos + flatLook * forwardDistance + flatRight * rightOffset
	local startPos = Vector3.new(
		horizonPoint.X,
		horizonHeight + LIGHTNING_CONFIG.MainSegments * LIGHTNING_CONFIG.SegmentLength * 0.7,  -- Start above where bolt will end
		horizonPoint.Z
	)
	
	-- Direction is mostly downward
	local direction = Vector3.new(
		(math.random() - 0.5) * 0.2,
		-1,
		(math.random() - 0.5) * 0.2
	).Unit
	
	-- Generate the full bolt path (fractal random walk)
	local allSegments = {}
	generateBoltPath(
		startPos,
		direction,
		LIGHTNING_CONFIG.MainSegments,
		LIGHTNING_CONFIG.SegmentLength,
		LIGHTNING_CONFIG.MainWidth,
		0,  -- depth starts at 0
		allSegments,
		folder
	)
	
	-- Animate the bolt
	animateLightningBolt(allSegments, folder)
end

local function initLightning(self)
	getLightningFolder()
	
	-- Store original lighting values after a short delay
	-- (to let WeatherController set up first)
	task.delay(2, function()
		storeLightingValues()
	end)
end

local function startLightningLoop(self)
	print("[RainController] Lightning loop STARTED")
	task.spawn(function()
		while true do
			-- Random interval between lightning strikes
			local interval = math.random(
				LIGHTNING_CONFIG.MinInterval * 10,
				LIGHTNING_CONFIG.MaxInterval * 10
			) / 10
			
			task.wait(interval)
			
			if self.isRaining and self.lightningEnabled then
				print("[RainController] LIGHTNING STRIKE!")
				spawnLightningBolt(self)
			else
				-- Log every 10 seconds why lightning isn't firing
				if math.random() < 0.1 then
					print(string.format("[RainController] Lightning check - isRaining: %s, lightningEnabled: %s", 
						tostring(self.isRaining), tostring(self.lightningEnabled)))
				end
			end
		end
	end)
end

-- === UPDATE LOOP ===

local function updateRain(self, deltaTime)
	local toRemove = {}
	
	for i, dropData in ipairs(self.activeDrops) do
		-- Move drop down
		dropData.position = dropData.position - Vector3.new(0, dropData.velocity * deltaTime, 0)
		dropData.part.CFrame = CFrame.new(dropData.position)
		
		-- Check if hit ground
		if dropData.position.Y <= dropData.groundY then
			-- Create splash if hit something
			if dropData.hitInstance then
				createSplash(self, Vector3.new(dropData.position.X, dropData.groundY, dropData.position.Z), dropData.groundNormal)
			end
			
			-- Mark for removal
			table.insert(toRemove, i)
		end
	end
	
	-- Remove and return drops to cache (iterate backwards)
	for i = #toRemove, 1, -1 do
		local index = toRemove[i]
		local dropData = self.activeDrops[index]
		self.rainCache:ReturnPart(dropData.part)
		table.remove(self.activeDrops, index)
	end
end

-- === SPAWN LOOP ===

local function startSpawnLoop(self)
	local spawnInterval = 1 / RAIN_CONFIG.SpawnRate
	local accumulator = 0
	local logTimer = 0
	local dropsSpawned = 0
	
	print("[RainController] Rain spawn loop STARTED")
	
	RunService.RenderStepped:Connect(function(deltaTime)
		logTimer = logTimer + deltaTime
		
		-- Log status every 5 seconds
		if logTimer >= 5 then
			print(string.format("[RainController] Rain status - isRaining: %s, drops spawned: %d", 
				tostring(self.isRaining), dropsSpawned))
			logTimer = 0
			dropsSpawned = 0
		end
		
		if not self.isRaining then return end
		
		-- Spawn new drops
		accumulator = accumulator + deltaTime
		while accumulator >= spawnInterval do
			spawnRaindrop(self)
			dropsSpawned = dropsSpawned + 1
			accumulator = accumulator - spawnInterval
		end
		
		-- Update existing drops
		updateRain(self, deltaTime)
	end)
end

-- === PUBLIC METHODS ===

function RainController:StartRain()
	self.isRaining = true
	print("[RainController] Rain started")
end

function RainController:StopRain()
	self.isRaining = false
	
	-- Return all active drops
	for _, dropData in ipairs(self.activeDrops) do
		self.rainCache:ReturnPart(dropData.part)
	end
	self.activeDrops = {}
	
	print("[RainController] Rain stopped")
end

function RainController:SetIntensity(dropsPerSecond)
	RAIN_CONFIG.SpawnRate = math.clamp(dropsPerSecond, 1, 200)
	print("[RainController] Intensity set to", dropsPerSecond)
end

function RainController:EnableLightning()
	self.lightningEnabled = true
	print("[RainController] Lightning enabled")
end

function RainController:DisableLightning()
	self.lightningEnabled = false
	print("[RainController] Lightning disabled")
end

function RainController:TriggerLightning()
	spawnLightningBolt(self)
end

-- === KNIT LIFECYCLE ===

function RainController:KnitInit()
	local folder = getRainFolder()
	
	-- Create part caches
	local rainTemplate = createRainTemplate()
	local splashTemplate = createSplashTemplate()
	
	self.rainCache = PartCache.new(rainTemplate, RAIN_CONFIG.MaxDrops, folder)
	self.splashCache = PartCache.new(splashTemplate, RAIN_CONFIG.MaxSplashes, folder)
	
	print("[RainController] PartCache initialized with", RAIN_CONFIG.MaxDrops, "drops")
end

function RainController:SetRainEnabled(enabled)
	local wasRaining = self.isRaining
	self.isRaining = enabled
	print(string.format("[RainController] *** RAIN %s *** (was: %s, now: %s)", 
		enabled and "ENABLED" or "DISABLED",
		tostring(wasRaining),
		tostring(enabled)))
	
	-- Clean up rain drops when rain stops
	if not enabled and wasRaining then
		print("[RainController] Cleaning up rain drops...")
		for _, dropData in ipairs(self.activeDrops) do
			if self.rainCache then
				self.rainCache:ReturnPart(dropData.part)
			end
		end
		self.activeDrops = {}
		print(string.format("[RainController] Cleaned up all rain drops"))
	end
end

function RainController:SetLightningEnabled(enabled)
	local wasEnabled = self.lightningEnabled
	self.lightningEnabled = enabled
	print(string.format("[RainController] *** LIGHTNING %s *** (was: %s, now: %s)", 
		enabled and "ENABLED" or "DISABLED",
		tostring(wasEnabled),
		tostring(enabled)))
end

function RainController:KnitStart()
	-- Wait for character
	if not Player.Character then
		Player.CharacterAdded:Wait()
	end
	
	-- Initialize systems (but don't enable yet)
	startSpawnLoop(self)
	initLightning(self)
	startLightningLoop(self)
	
	-- Get WeatherService
	print("[RainController] Getting WeatherService...")
	self._weatherService = Knit.GetService("WeatherService")
	print("[RainController] WeatherService obtained!")
	
	-- Get initial IsNight state from server
	print("[RainController] Requesting initial IsNight state...")
	local isNight = self._weatherService:GetIsNight()
	print(string.format("[RainController] Initial IsNight from server: %s", tostring(isNight)))
	
	self:SetRainEnabled(isNight)
	self:SetLightningEnabled(isNight)
	
	-- Listen for IsNight changes via signal
	print("[RainController] Connecting to IsNightChanged signal...")
	self._weatherService.IsNightChanged:Connect(function(newIsNight)
		print(string.format("[RainController] *** IsNightChanged SIGNAL RECEIVED: %s ***", tostring(newIsNight)))
		self:SetRainEnabled(newIsNight)
		self:SetLightningEnabled(newIsNight)
	end)
	
	print("[RainController] Rain and lightning system initialized")
end

return RainController

