local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local Knit = require(Packages.Knit)

local MonolithEntityService = Knit.CreateService {
	Name = "MonolithEntityService",
	Client = {},
	Entity = nil,
	BlinkingParts = {},
	PulsingParts = {},
	ConsoleLights = {},
	ConsoleLens = nil,
	IsAlive = true,
}

-- === CONFIG ===
local CONFIG = {
	-- Position (center of map, slightly offset)
	SpawnOffset = Vector3.new(0, 0, 50),
	
	-- Core body dimensions
	BodyHeight = 80,
	BodyWidth = 25,
	BodyDepth = 20,
	
	-- Colors (dark organic with accent glows)
	BodyColor = Color3.fromRGB(25, 22, 30),           -- Deep void
	OrganicColor = Color3.fromRGB(35, 30, 40),        -- Dark purple organic
	VeinColor = Color3.fromRGB(45, 40, 50),           -- Vein highlights
	EyeColor = Color3.fromRGB(120, 90, 100),          -- Muted eye glow
	EyeGlowColor = Color3.fromRGB(180, 120, 140),     -- Eye when "awake"
	PulseColor = Color3.fromRGB(80, 60, 90),          -- Pulse nodes
	
	-- Face configuration
	FaceHeight = 0.7, -- Position on body (70% up)
	EyeCount = 3,     -- Number of eyes
	EyeSize = 4,
	
	-- Tentacle/appendage config
	TentacleCount = 8,
	TentacleSegments = 6,
	TentacleLength = 40,
	TentacleWidth = 3,
	
	-- Spine/rib protrusions
	SpineCount = 12,
	SpineLength = 8,
	
	-- Animation
	BlinkInterval = { Min = 2, Max = 8 },     -- Seconds between blinks
	BlinkDuration = 0.15,                      -- How long eye stays closed
	PulseSpeed = 2,                            -- Pulse cycle in seconds
	BreathingSpeed = 4,                        -- Body "breathing" cycle
	
	-- Spiraling platforms (platformer path to the top)
	Platforms = {
		Count = 30,                    -- More platforms = easier jumps
		StartHeight = 6,               -- Starting height above ground
		SpiralRadius = 16,             -- Distance from center (slightly closer)
		SpiralRotations = 3,           -- More rotations for gradual climb
		
		-- Platform dimensions
		Width = 9,
		Depth = 7,
		Height = 2,
		
		-- Colors
		PlatformColor = Color3.fromRGB(40, 35, 45),
		EdgeColor = Color3.fromRGB(60, 50, 70),
		GlowColor = Color3.fromRGB(80, 60, 100),
	},
	
	-- Console (HAL-like interface at TOP)
	Console = {
		Width = 14,
		Height = 6,
		Depth = 10,
		
		-- Colors
		FrameColor = Color3.fromRGB(20, 18, 25),
		ScreenColor = Color3.fromRGB(8, 8, 12),
		
		-- Central eye/lens (HAL style)
		LensColor = Color3.fromRGB(180, 50, 50),        -- Red HAL eye
		LensGlowColor = Color3.fromRGB(255, 80, 80),
		LensSize = 4,
		
		-- Indicator lights
		LightColors = {
			Color3.fromRGB(80, 200, 80),   -- Green
			Color3.fromRGB(200, 180, 60),  -- Yellow/Amber
			Color3.fromRGB(60, 150, 200),  -- Cyan
			Color3.fromRGB(200, 80, 80),   -- Red
			Color3.fromRGB(150, 100, 200), -- Purple
		},
		LightRows = 2,
		LightsPerRow = 10,
		LightSize = 0.5,
		
		-- Blinking patterns
		BlinkSpeed = { Min = 0.1, Max = 0.8 },
	},
}

local FOLDER_NAME = "MonolithEntity"

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

local function getEntityFolder()
	local folder = Workspace:FindFirstChild(FOLDER_NAME)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = FOLDER_NAME
		folder.Parent = Workspace
	end
	return folder
end

local function getSpawnPosition()
	local baseplate = Workspace:FindFirstChild("Baseplate")
	if baseplate then
		return baseplate.Position + Vector3.new(0, baseplate.Size.Y / 2, 0) + CONFIG.SpawnOffset
	end
	return Vector3.new(0, 0, 0) + CONFIG.SpawnOffset
end

-- === ENTITY CREATION ===

function MonolithEntityService:CreateCore(model, basePos)
	-- Main body - tall monolithic structure
	local body = Instance.new("Part")
	body.Name = "Core"
	body.Size = Vector3.new(CONFIG.BodyWidth, CONFIG.BodyHeight, CONFIG.BodyDepth)
	body.Position = basePos + Vector3.new(0, CONFIG.BodyHeight / 2, 0)
	body.Color = CONFIG.BodyColor
	body.Material = Enum.Material.Slate
	body.Anchored = true
	body.CanCollide = true
	body.Parent = model
	model.PrimaryPart = body
	
	-- Organic texture layers (overlapping parts for depth)
	for i = 1, 5 do
		local layer = Instance.new("Part")
		layer.Name = "OrganicLayer" .. i
		local scaleX = 1 - (i * 0.08) + randomRange(-0.05, 0.05)
		local scaleZ = 1 - (i * 0.06) + randomRange(-0.05, 0.05)
		layer.Size = Vector3.new(
			CONFIG.BodyWidth * scaleX,
			CONFIG.BodyHeight * randomRange(0.3, 0.5),
			CONFIG.BodyDepth * scaleZ
		)
		layer.Position = basePos + Vector3.new(
			randomRange(-2, 2),
			CONFIG.BodyHeight * randomRange(0.2, 0.8),
			randomRange(-2, 2)
		)
		layer.Color = varyColor(CONFIG.OrganicColor, 10)
		layer.Material = Enum.Material.Slate
		layer.Anchored = true
		layer.CanCollide = true
		layer.Parent = model
	end
	
	-- Base mound (organic growth at bottom)
	local baseWidth = CONFIG.BodyWidth * 2
	local baseMound = Instance.new("Part")
	baseMound.Name = "BaseMound"
	baseMound.Shape = Enum.PartType.Ball
	baseMound.Size = Vector3.new(baseWidth, baseWidth * 0.4, baseWidth)
	baseMound.Position = basePos + Vector3.new(0, baseWidth * 0.1, 0)
	baseMound.Color = varyColor(CONFIG.OrganicColor, 8)
	baseMound.Material = Enum.Material.Slate
	baseMound.Anchored = true
	baseMound.CanCollide = true
	baseMound.Parent = model
	
	return body
end

function MonolithEntityService:CreateFace(model, basePos)
	local faceY = basePos.Y + CONFIG.BodyHeight * CONFIG.FaceHeight
	local faceZ = basePos.Z + CONFIG.BodyDepth / 2 + 2
	
	-- Face plate (slightly protruding area)
	local facePlate = Instance.new("Part")
	facePlate.Name = "FacePlate"
	facePlate.Size = Vector3.new(CONFIG.BodyWidth * 0.8, CONFIG.BodyHeight * 0.25, 5)
	facePlate.Position = Vector3.new(basePos.X, faceY, faceZ)
	facePlate.Color = varyColor(CONFIG.OrganicColor, 5)
	facePlate.Material = Enum.Material.Slate
	facePlate.Anchored = true
	facePlate.CanCollide = true
	facePlate.Parent = model
	
	-- Eyes
	local eyeSpacing = CONFIG.BodyWidth * 0.25
	local eyePositions = {}
	
	if CONFIG.EyeCount == 1 then
		table.insert(eyePositions, Vector3.new(0, 0, 0))
	elseif CONFIG.EyeCount == 2 then
		table.insert(eyePositions, Vector3.new(-eyeSpacing, 0, 0))
		table.insert(eyePositions, Vector3.new(eyeSpacing, 0, 0))
	elseif CONFIG.EyeCount == 3 then
		table.insert(eyePositions, Vector3.new(0, eyeSpacing * 0.5, 0)) -- Top center
		table.insert(eyePositions, Vector3.new(-eyeSpacing, -eyeSpacing * 0.3, 0))
		table.insert(eyePositions, Vector3.new(eyeSpacing, -eyeSpacing * 0.3, 0))
	else
		for i = 1, CONFIG.EyeCount do
			local angle = (i - 1) * (math.pi * 2 / CONFIG.EyeCount)
			table.insert(eyePositions, Vector3.new(
				math.cos(angle) * eyeSpacing,
				math.sin(angle) * eyeSpacing * 0.5,
				0
			))
		end
	end
	
	for i, offset in ipairs(eyePositions) do
		-- Eye socket (dark recess)
		local socket = Instance.new("Part")
		socket.Name = "EyeSocket" .. i
		socket.Shape = Enum.PartType.Ball
		socket.Size = Vector3.new(CONFIG.EyeSize * 1.8, CONFIG.EyeSize * 1.5, CONFIG.EyeSize)
		socket.Position = Vector3.new(basePos.X + offset.X, faceY + offset.Y, faceZ + 2)
		socket.Color = Color3.fromRGB(10, 8, 12)
		socket.Material = Enum.Material.Slate
		socket.Anchored = true
		socket.CanCollide = true
		socket.Parent = model
		
		-- Eye (the blinking part)
		local eye = Instance.new("Part")
		eye.Name = "Eye" .. i
		eye.Shape = Enum.PartType.Ball
		eye.Size = Vector3.new(CONFIG.EyeSize, CONFIG.EyeSize * 0.8, CONFIG.EyeSize * 0.5)
		eye.Position = Vector3.new(basePos.X + offset.X, faceY + offset.Y, faceZ + 3)
		eye.Color = CONFIG.EyeColor
		eye.Material = Enum.Material.Slate
		eye.Anchored = true
		eye.CanCollide = true
		eye.Parent = model
		
		-- Eye light
		local eyeLight = Instance.new("PointLight")
		eyeLight.Name = "EyeLight"
		eyeLight.Color = CONFIG.EyeGlowColor
		eyeLight.Brightness = 0.5
		eyeLight.Range = 15
		eyeLight.Parent = eye
		
		-- Add to blinking parts
		table.insert(self.BlinkingParts, {
			eye = eye,
			light = eyeLight,
			socket = socket,
			originalColor = CONFIG.EyeColor,
			glowColor = CONFIG.EyeGlowColor,
			closedColor = Color3.fromRGB(20, 15, 25),
			nextBlink = tick() + randomRange(CONFIG.BlinkInterval.Min, CONFIG.BlinkInterval.Max),
		})
	end
	
	-- Mouth/Slit (ominous vertical slit below eyes)
	local mouth = Instance.new("Part")
	mouth.Name = "Mouth"
	mouth.Size = Vector3.new(2, CONFIG.BodyHeight * 0.1, 3)
	mouth.Position = Vector3.new(basePos.X, faceY - eyeSpacing * 1.2, faceZ + 1)
	mouth.Color = Color3.fromRGB(8, 5, 10)
	mouth.Material = Enum.Material.Slate
	mouth.Anchored = true
	mouth.CanCollide = true
	mouth.Parent = model
end

function MonolithEntityService:CreateTentacles(model, basePos)
	for i = 1, CONFIG.TentacleCount do
		local angle = (i - 1) * (math.pi * 2 / CONFIG.TentacleCount) + randomRange(-0.3, 0.3)
		local startHeight = CONFIG.BodyHeight * randomRange(0.1, 0.4)
		local startX = basePos.X + math.cos(angle) * (CONFIG.BodyWidth / 2 + 2)
		local startZ = basePos.Z + math.sin(angle) * (CONFIG.BodyDepth / 2 + 2)
		local startPos = Vector3.new(startX, basePos.Y + startHeight, startZ)
		
		local segmentLength = CONFIG.TentacleLength / CONFIG.TentacleSegments
		local currentPos = startPos
		local currentDir = Vector3.new(math.cos(angle), -0.3, math.sin(angle)).Unit
		local currentWidth = CONFIG.TentacleWidth
		
		for j = 1, CONFIG.TentacleSegments do
			-- Add organic curve
			local curve = (j / CONFIG.TentacleSegments) * math.pi * 0.5
			local droop = math.sin(curve) * 0.5
			currentDir = Vector3.new(
				currentDir.X + randomRange(-0.1, 0.1),
				-0.2 - droop,
				currentDir.Z + randomRange(-0.1, 0.1)
			).Unit
			
			local nextPos = currentPos + currentDir * segmentLength
			local midPos = currentPos + (nextPos - currentPos) / 2
			
			local segment = Instance.new("Part")
			segment.Name = "Tentacle" .. i .. "_Seg" .. j
			segment.Shape = Enum.PartType.Cylinder
			segment.Size = Vector3.new(segmentLength, currentWidth, currentWidth)
			segment.CFrame = CFrame.lookAt(midPos, nextPos) * CFrame.Angles(0, math.rad(90), 0)
			segment.Color = varyColor(CONFIG.OrganicColor, 12)
			segment.Material = Enum.Material.Slate
			segment.Anchored = true
			segment.CanCollide = true
			segment.Parent = model
			
			-- Add bulge/node at joints
			if j % 2 == 0 then
				local node = Instance.new("Part")
				node.Name = "TentacleNode" .. i .. "_" .. j
				node.Shape = Enum.PartType.Ball
				node.Size = Vector3.new(currentWidth * 1.5, currentWidth * 1.3, currentWidth * 1.5)
				node.Position = currentPos
				node.Color = varyColor(CONFIG.VeinColor, 8)
				node.Material = Enum.Material.Slate
				node.Anchored = true
				node.CanCollide = true
				node.Parent = model
			end
			
			currentPos = nextPos
			currentWidth = currentWidth * 0.85
		end
		
		-- Tentacle tip (slightly glowing)
		local tip = Instance.new("Part")
		tip.Name = "TentacleTip" .. i
		tip.Shape = Enum.PartType.Ball
		tip.Size = Vector3.new(currentWidth * 2, currentWidth * 2.5, currentWidth * 2)
		tip.Position = currentPos
		tip.Color = CONFIG.PulseColor
		tip.Material = Enum.Material.Slate
		tip.Anchored = true
		tip.CanCollide = true
		tip.Parent = model
		
		local tipLight = Instance.new("PointLight")
		tipLight.Name = "TipLight"
		tipLight.Color = CONFIG.PulseColor
		tipLight.Brightness = 0.3
		tipLight.Range = 8
		tipLight.Parent = tip
		
		table.insert(self.PulsingParts, {
			part = tip,
			light = tipLight,
			baseColor = CONFIG.PulseColor,
			baseBrightness = 0.3,
			phase = math.random() * math.pi * 2,
		})
	end
end

function MonolithEntityService:CreateSpines(model, basePos)
	for i = 1, CONFIG.SpineCount do
		local heightFraction = (i - 1) / (CONFIG.SpineCount - 1)
		local spineY = basePos.Y + CONFIG.BodyHeight * (0.2 + heightFraction * 0.6)
		
		-- Spines on both sides
		for side = -1, 1, 2 do
			local spineX = basePos.X + side * (CONFIG.BodyWidth / 2 + CONFIG.SpineLength * 0.3)
			local spineAngle = side * randomRange(30, 50)
			
			local spine = Instance.new("Part")
			spine.Name = "Spine" .. i .. "_" .. (side == 1 and "R" or "L")
			spine.Size = Vector3.new(CONFIG.SpineLength, 2, 2)
			spine.Position = Vector3.new(spineX, spineY, basePos.Z)
			spine.CFrame = spine.CFrame * CFrame.Angles(0, 0, math.rad(spineAngle))
			spine.Color = varyColor(CONFIG.VeinColor, 10)
			spine.Material = Enum.Material.Slate
			spine.Anchored = true
			spine.CanCollide = true
			spine.Parent = model
		end
	end
	
	-- Back spines (larger, more prominent)
	for i = 1, 6 do
		local spineY = basePos.Y + CONFIG.BodyHeight * (0.3 + (i - 1) * 0.1)
		local spineZ = basePos.Z - CONFIG.BodyDepth / 2 - CONFIG.SpineLength * 0.4
		
		local spine = Instance.new("Part")
		spine.Name = "BackSpine" .. i
		spine.Size = Vector3.new(3, CONFIG.SpineLength * 1.5, 3)
		spine.Position = Vector3.new(basePos.X + randomRange(-3, 3), spineY, spineZ)
		spine.CFrame = spine.CFrame * CFrame.Angles(math.rad(randomRange(-20, -40)), 0, math.rad(randomRange(-10, 10)))
		spine.Color = varyColor(CONFIG.VeinColor, 8)
		spine.Material = Enum.Material.Slate
		spine.Anchored = true
		spine.CanCollide = true
		spine.Parent = model
	end
end

function MonolithEntityService:CreatePulseNodes(model, basePos)
	-- Scattered pulse nodes on the body
	local nodeCount = 15
	
	for i = 1, nodeCount do
		local nodeX = basePos.X + randomRange(-CONFIG.BodyWidth * 0.4, CONFIG.BodyWidth * 0.4)
		local nodeY = basePos.Y + CONFIG.BodyHeight * randomRange(0.1, 0.9)
		local nodeZ = basePos.Z + randomRange(-CONFIG.BodyDepth * 0.3, CONFIG.BodyDepth * 0.5)
		
		local node = Instance.new("Part")
		node.Name = "PulseNode" .. i
		node.Shape = Enum.PartType.Ball
		node.Size = Vector3.new(3, 3, 3)
		node.Position = Vector3.new(nodeX, nodeY, nodeZ)
		node.Color = CONFIG.PulseColor
		node.Material = Enum.Material.Slate
		node.Anchored = true
		node.CanCollide = true
		node.Parent = model
		
		local nodeLight = Instance.new("PointLight")
		nodeLight.Name = "NodeLight"
		nodeLight.Color = CONFIG.PulseColor
		nodeLight.Brightness = 0.2
		nodeLight.Range = 6
		nodeLight.Parent = node
		
		table.insert(self.PulsingParts, {
			part = node,
			light = nodeLight,
			baseColor = CONFIG.PulseColor,
			baseBrightness = 0.2,
			phase = math.random() * math.pi * 2,
		})
	end
end

function MonolithEntityService:CreateVeins(model, basePos)
	-- Surface veins (dark lines running up the body)
	local veinCount = 8
	
	for i = 1, veinCount do
		local angle = (i - 1) * (math.pi * 2 / veinCount)
		local veinX = basePos.X + math.cos(angle) * (CONFIG.BodyWidth * 0.45)
		local veinZ = basePos.Z + math.sin(angle) * (CONFIG.BodyDepth * 0.45)
		
		-- Vein runs vertically with some wobble
		local segments = 8
		local segmentHeight = CONFIG.BodyHeight * 0.7 / segments
		local currentX = veinX
		local currentZ = veinZ
		
		for j = 1, segments do
			local veinY = basePos.Y + CONFIG.BodyHeight * 0.15 + (j - 1) * segmentHeight
			
			local vein = Instance.new("Part")
			vein.Name = "Vein" .. i .. "_" .. j
			vein.Size = Vector3.new(1.5, segmentHeight + 1, 1.5)
			vein.Position = Vector3.new(currentX, veinY + segmentHeight / 2, currentZ)
			vein.Color = CONFIG.VeinColor
			vein.Material = Enum.Material.Slate
			vein.Anchored = true
			vein.CanCollide = true
			vein.Parent = model
			
			-- Wobble for next segment
			currentX = currentX + randomRange(-0.5, 0.5)
			currentZ = currentZ + randomRange(-0.5, 0.5)
		end
	end
end

function MonolithEntityService:CreatePlatforms(model, basePos)
	local cfg = CONFIG.Platforms
	
	local totalHeight = CONFIG.BodyHeight - cfg.StartHeight
	local anglePerPlatform = (cfg.SpiralRotations * math.pi * 2) / cfg.Count
	local heightPerPlatform = totalHeight / cfg.Count
	
	for i = 1, cfg.Count do
		local angle = (i - 1) * anglePerPlatform
		local height = basePos.Y + cfg.StartHeight + (i - 1) * heightPerPlatform
		
		local platformX = basePos.X + math.cos(angle) * cfg.SpiralRadius
		local platformZ = basePos.Z + math.sin(angle) * cfg.SpiralRadius
		
		-- Main platform
		local platform = Instance.new("Part")
		platform.Name = "Platform" .. i
		platform.Size = Vector3.new(cfg.Width, cfg.Height, cfg.Depth)
		platform.Position = Vector3.new(platformX, height, platformZ)
		-- Rotate to face center
		platform.CFrame = CFrame.new(platform.Position) * CFrame.Angles(0, angle + math.pi/2, 0)
		platform.Color = varyColor(cfg.PlatformColor, 10)
		platform.Material = Enum.Material.Slate
		platform.Anchored = true
		platform.CanCollide = true
		platform.Parent = model
		
		-- === EDGE STRIP LIGHTS ===
		-- Front edge strip
		local frontEdge = Instance.new("Part")
		frontEdge.Name = "PlatformFrontEdge" .. i
		frontEdge.Size = Vector3.new(cfg.Width, 0.4, 0.4)
		frontEdge.CFrame = platform.CFrame * CFrame.new(0, cfg.Height/2 + 0.2, cfg.Depth/2 - 0.2)
		frontEdge.Color = cfg.GlowColor
		frontEdge.Material = Enum.Material.Neon
		frontEdge.Transparency = 0.2
		frontEdge.Anchored = true
		frontEdge.CanCollide = false
		frontEdge.Parent = model
		
		-- Back edge strip
		local backEdge = Instance.new("Part")
		backEdge.Name = "PlatformBackEdge" .. i
		backEdge.Size = Vector3.new(cfg.Width, 0.4, 0.4)
		backEdge.CFrame = platform.CFrame * CFrame.new(0, cfg.Height/2 + 0.2, -cfg.Depth/2 + 0.2)
		backEdge.Color = cfg.GlowColor
		backEdge.Material = Enum.Material.Neon
		backEdge.Transparency = 0.2
		backEdge.Anchored = true
		backEdge.CanCollide = false
		backEdge.Parent = model
		
		-- Side edge strips (neon)
		for side = -1, 1, 2 do
			local sideEdge = Instance.new("Part")
			sideEdge.Name = "PlatformSideEdge" .. i .. (side == 1 and "R" or "L")
			sideEdge.Size = Vector3.new(0.4, 0.4, cfg.Depth)
			sideEdge.CFrame = platform.CFrame * CFrame.new(side * (cfg.Width/2 - 0.2), cfg.Height/2 + 0.2, 0)
			sideEdge.Color = cfg.GlowColor
			sideEdge.Material = Enum.Material.Neon
			sideEdge.Transparency = 0.2
			sideEdge.Anchored = true
			sideEdge.CanCollide = false
			sideEdge.Parent = model
		end
		
		-- === FRONT CORNER FLOOR LIGHTS (uplights at front corners) ===
		local frontCorners = {
			{x = cfg.Width/2 - 0.8, z = cfg.Depth/2 - 0.8},
			{x = -cfg.Width/2 + 0.8, z = cfg.Depth/2 - 0.8},
		}
		
		for j, corner in ipairs(frontCorners) do
			-- Floor light fixture
			local floorLight = Instance.new("Part")
			floorLight.Name = "FloorLight" .. i .. "_" .. j
			floorLight.Shape = Enum.PartType.Cylinder
			floorLight.Size = Vector3.new(0.3, 1.2, 1.2)
			floorLight.CFrame = platform.CFrame * CFrame.new(corner.x, cfg.Height/2 + 0.2, corner.z)
			floorLight.Color = cfg.GlowColor
			floorLight.Material = Enum.Material.Neon
			floorLight.Transparency = 0.1
			floorLight.Anchored = true
			floorLight.CanCollide = false
			floorLight.Parent = model
			
			-- Uplight spotlight (bright!)
			local uplightMount = Instance.new("Part")
			uplightMount.Name = "UplightMount" .. i .. "_" .. j
			uplightMount.Size = Vector3.new(0.3, 0.3, 0.3)
			uplightMount.CFrame = platform.CFrame * CFrame.new(corner.x, cfg.Height/2 + 0.5, corner.z) * CFrame.Angles(math.rad(-90), 0, 0)
			uplightMount.Transparency = 1
			uplightMount.Anchored = true
			uplightMount.CanCollide = false
			uplightMount.Parent = model
			
			local uplight = Instance.new("SpotLight")
			uplight.Brightness = 6
			uplight.Range = 25
			uplight.Angle = 70
			uplight.Color = cfg.GlowColor
			uplight.Face = Enum.NormalId.Front
			uplight.Shadows = true
			uplight.Parent = uplightMount
		end
		
		-- Support strut connecting to body
		local strutEndX = basePos.X + math.cos(angle) * (CONFIG.BodyWidth / 2 + 1)
		local strutEndZ = basePos.Z + math.sin(angle) * (CONFIG.BodyDepth / 2 + 1)
		local strutStart = Vector3.new(platformX, height - cfg.Height/2, platformZ)
		local strutEnd = Vector3.new(strutEndX, height - cfg.Height/2, strutEndZ)
		local strutDir = (strutEnd - strutStart)
		local strutLen = strutDir.Magnitude
		
		local strut = Instance.new("Part")
		strut.Name = "Strut" .. i
		strut.Shape = Enum.PartType.Cylinder
		strut.Size = Vector3.new(strutLen, 1.5, 1.5)
		strut.CFrame = CFrame.lookAt(strutStart + strutDir/2, strutEnd) * CFrame.Angles(0, math.rad(90), 0)
		strut.Color = CONFIG.VeinColor
		strut.Material = Enum.Material.Slate
		strut.Anchored = true
		strut.CanCollide = true
		strut.Parent = model
		
		-- Strut light (illuminates connection)
		local strutLight = Instance.new("PointLight")
		strutLight.Color = cfg.GlowColor
		strutLight.Brightness = 0.3
		strutLight.Range = 5
		strutLight.Parent = strut
	end
	
	-- Final platform at the top (larger, for the console)
	local topAngle = cfg.Count * anglePerPlatform
	local topHeight = basePos.Y + CONFIG.BodyHeight + 5
	local topX = basePos.X + math.cos(topAngle) * (cfg.SpiralRadius * 0.8)
	local topZ = basePos.Z + math.sin(topAngle) * (cfg.SpiralRadius * 0.8)
	
	local topWidth = CONFIG.Console.Width + 8
	local topDepth = CONFIG.Console.Depth + 6
	
	local topPlatform = Instance.new("Part")
	topPlatform.Name = "TopPlatform"
	topPlatform.Size = Vector3.new(topWidth, 3, topDepth)
	topPlatform.Position = Vector3.new(topX, topHeight, topZ)
	topPlatform.CFrame = CFrame.new(topPlatform.Position) * CFrame.Angles(0, topAngle + math.pi/2, 0)
	topPlatform.Color = cfg.PlatformColor
	topPlatform.Material = Enum.Material.Slate
	topPlatform.Anchored = true
	topPlatform.CanCollide = true
	topPlatform.Parent = model
	
	-- === TOP PLATFORM FLOOR UPLIGHTS ===
	local topCorners = {
		{x = topWidth/2 - 2, z = topDepth/2 - 2},
		{x = -topWidth/2 + 2, z = topDepth/2 - 2},
		{x = topWidth/2 - 2, z = -topDepth/2 + 2},
		{x = -topWidth/2 + 2, z = -topDepth/2 + 2},
	}
	
	-- Floor uplights at the corners
	for j, corner in ipairs(topCorners) do
		local floorLight = Instance.new("Part")
		floorLight.Name = "TopFloorLight" .. j
		floorLight.Shape = Enum.PartType.Cylinder
		floorLight.Size = Vector3.new(0.5, 2, 2)
		floorLight.CFrame = topPlatform.CFrame * CFrame.new(corner.x * 0.5, 1.5 + 0.3, corner.z * 0.5)
		floorLight.Color = Color3.fromRGB(100, 200, 150)
		floorLight.Material = Enum.Material.Neon
		floorLight.Transparency = 0.1
		floorLight.Anchored = true
		floorLight.CanCollide = false
		floorLight.Parent = model
		
		local upMount = Instance.new("Part")
		upMount.Name = "TopUpMount" .. j
		upMount.Size = Vector3.new(0.3, 0.3, 0.3)
		upMount.CFrame = topPlatform.CFrame * CFrame.new(corner.x * 0.5, 1.5 + 0.5, corner.z * 0.5) * CFrame.Angles(math.rad(-90), 0, 0)
		upMount.Transparency = 1
		upMount.Anchored = true
		upMount.CanCollide = false
		upMount.Parent = model
		
		local upSpot = Instance.new("SpotLight")
		upSpot.Brightness = 8
		upSpot.Range = 30
		upSpot.Angle = 80
		upSpot.Color = Color3.fromRGB(100, 200, 150)
		upSpot.Face = Enum.NormalId.Front
		upSpot.Shadows = true
		upSpot.Parent = upMount
	end
	
	-- Neon edge strips for top platform
	local topEdges = {
		{pos = CFrame.new(0, 1.5 + 0.3, topDepth/2 - 0.3), size = Vector3.new(topWidth, 0.5, 0.5)},
		{pos = CFrame.new(0, 1.5 + 0.3, -topDepth/2 + 0.3), size = Vector3.new(topWidth, 0.5, 0.5)},
		{pos = CFrame.new(topWidth/2 - 0.3, 1.5 + 0.3, 0), size = Vector3.new(0.5, 0.5, topDepth)},
		{pos = CFrame.new(-topWidth/2 + 0.3, 1.5 + 0.3, 0), size = Vector3.new(0.5, 0.5, topDepth)},
	}
	
	for j, edgeData in ipairs(topEdges) do
		local topEdge = Instance.new("Part")
		topEdge.Name = "TopPlatformEdge" .. j
		topEdge.Size = edgeData.size
		topEdge.CFrame = topPlatform.CFrame * edgeData.pos
		topEdge.Color = Color3.fromRGB(100, 200, 150)
		topEdge.Material = Enum.Material.Neon
		topEdge.Transparency = 0.2
		topEdge.Anchored = true
		topEdge.CanCollide = false
		topEdge.Parent = model
	end
	
	print("[MonolithEntityService] Created", cfg.Count, "spiral platforms")
	
	-- Return top platform info for console placement
	return {
		position = topPlatform.Position,
		cframe = topPlatform.CFrame,
		height = topHeight,
	}
end

function MonolithEntityService:CreateConsole(model, basePos, topPlatformInfo)
	local cfg = CONFIG.Console
	
	-- Console position (on top of the final platform)
	local consolePos = topPlatformInfo.position + Vector3.new(0, 1.5 + cfg.Height / 2, 0)
	local consoleCFrame = topPlatformInfo.cframe * CFrame.new(0, 1.5 + cfg.Height / 2, 0)
	
	-- Main console housing
	local housing = Instance.new("Part")
	housing.Name = "ConsoleHousing"
	housing.Size = Vector3.new(cfg.Width + 2, cfg.Height + 2, cfg.Depth + 2)
	housing.CFrame = consoleCFrame
	housing.Color = cfg.FrameColor
	housing.Material = Enum.Material.Slate
	housing.Anchored = true
	housing.CanCollide = true
	housing.Parent = model
	
	-- Screen/display area (front panel)
	local screen = Instance.new("Part")
	screen.Name = "ConsoleScreen"
	screen.Size = Vector3.new(cfg.Width, cfg.Height, 0.5)
	screen.CFrame = consoleCFrame * CFrame.new(0, 0, cfg.Depth / 2 + 0.75)
	screen.Color = cfg.ScreenColor
	screen.Material = Enum.Material.Slate
	screen.Anchored = true
	screen.CanCollide = true
	screen.Parent = model
	
	-- Central HAL-style lens/eye
	local lensSocket = Instance.new("Part")
	lensSocket.Name = "LensSocket"
	lensSocket.Shape = Enum.PartType.Cylinder
	lensSocket.Size = Vector3.new(1, cfg.LensSize + 2, cfg.LensSize + 2)
	lensSocket.CFrame = consoleCFrame * CFrame.new(0, 0, cfg.Depth / 2 + 1) * CFrame.Angles(0, 0, math.rad(90))
	lensSocket.Color = Color3.fromRGB(15, 12, 18)
	lensSocket.Material = Enum.Material.Slate
	lensSocket.Anchored = true
	lensSocket.CanCollide = true
	lensSocket.Parent = model
	
	local lens = Instance.new("Part")
	lens.Name = "ConsoleLens"
	lens.Shape = Enum.PartType.Ball
	lens.Size = Vector3.new(cfg.LensSize, cfg.LensSize, cfg.LensSize * 0.6)
	lens.CFrame = consoleCFrame * CFrame.new(0, 0, cfg.Depth / 2 + 1.5)
	lens.Color = cfg.LensColor
	lens.Material = Enum.Material.Slate
	lens.Anchored = true
	lens.CanCollide = true
	lens.Parent = model
	
	local lensLight = Instance.new("PointLight")
	lensLight.Name = "LensLight"
	lensLight.Color = cfg.LensGlowColor
	lensLight.Brightness = 1
	lensLight.Range = 20
	lensLight.Parent = lens
	
	self.ConsoleLens = {
		part = lens,
		light = lensLight,
		baseColor = cfg.LensColor,
		glowColor = cfg.LensGlowColor,
	}
	
	-- Indicator light grid (blinking computer lights)
	local lightSpacingX = (cfg.Width - 2) / (cfg.LightsPerRow - 1)
	local lightSpacingY = cfg.LightRows > 1 and (cfg.Height * 0.4) / (cfg.LightRows - 1) or 0
	
	for row = 0, cfg.LightRows - 1 do
		for col = 0, cfg.LightsPerRow - 1 do
			local localX = -(cfg.Width - 2) / 2 + col * lightSpacingX
			local localY = cfg.Height * 0.25 + row * lightSpacingY
			local localZ = cfg.Depth / 2 + 1
			
			local indicator = Instance.new("Part")
			indicator.Name = "Indicator_" .. row .. "_" .. col
			indicator.Shape = Enum.PartType.Ball
			indicator.Size = Vector3.new(cfg.LightSize, cfg.LightSize, cfg.LightSize * 0.5)
			indicator.CFrame = consoleCFrame * CFrame.new(localX, localY, localZ)
			indicator.Color = cfg.LightColors[math.random(1, #cfg.LightColors)]
			indicator.Material = Enum.Material.Slate
			indicator.Anchored = true
			indicator.CanCollide = false
			indicator.Parent = model
			
			local indicatorLight = Instance.new("PointLight")
			indicatorLight.Name = "IndicatorLight"
			indicatorLight.Color = indicator.Color
			indicatorLight.Brightness = 0.3
			indicatorLight.Range = 2
			indicatorLight.Parent = indicator
			
			table.insert(self.ConsoleLights, {
				part = indicator,
				light = indicatorLight,
				baseColor = indicator.Color,
				isOn = math.random() > 0.5,
				nextToggle = tick() + randomRange(cfg.BlinkSpeed.Min, cfg.BlinkSpeed.Max),
			})
		end
	end
	
	-- Side panels with lights
	for side = -1, 1, 2 do
		local sidePanel = Instance.new("Part")
		sidePanel.Name = "SidePanel" .. (side == 1 and "R" or "L")
		sidePanel.Size = Vector3.new(2, cfg.Height, cfg.Depth)
		sidePanel.CFrame = consoleCFrame * CFrame.new(side * (cfg.Width / 2 + 1.5), 0, 0)
		sidePanel.Color = varyColor(cfg.FrameColor, 5)
		sidePanel.Material = Enum.Material.Slate
		sidePanel.Anchored = true
		sidePanel.CanCollide = true
		sidePanel.Parent = model
		
		-- Side lights
		for i = 1, 3 do
			local sideLight = Instance.new("Part")
			sideLight.Name = "SideLight" .. i
			sideLight.Shape = Enum.PartType.Ball
			sideLight.Size = Vector3.new(0.8, 0.8, 0.8)
			sideLight.CFrame = sidePanel.CFrame * CFrame.new(side * 0.8, cfg.Height * 0.3 - (i - 1) * 1.5, cfg.Depth / 2)
			sideLight.Color = cfg.LightColors[math.random(1, #cfg.LightColors)]
			sideLight.Material = Enum.Material.Slate
			sideLight.Anchored = true
			sideLight.CanCollide = false
			sideLight.Parent = model
			
			local sideLightGlow = Instance.new("PointLight")
			sideLightGlow.Color = sideLight.Color
			sideLightGlow.Brightness = 0.2
			sideLightGlow.Range = 2
			sideLightGlow.Parent = sideLight
			
			table.insert(self.ConsoleLights, {
				part = sideLight,
				light = sideLightGlow,
				baseColor = sideLight.Color,
				isOn = math.random() > 0.5,
				nextToggle = tick() + randomRange(cfg.BlinkSpeed.Min, cfg.BlinkSpeed.Max),
			})
		end
	end
	
	print("[MonolithEntityService] Console created at top with", #self.ConsoleLights, "indicator lights")
end

function MonolithEntityService:CreateEntity()
	local folder = getEntityFolder()
	
	-- Clear existing
	for _, child in ipairs(folder:GetChildren()) do
		child:Destroy()
	end
	self.BlinkingParts = {}
	self.PulsingParts = {}
	self.ConsoleLights = {}
	self.ConsoleLens = nil
	
	local model = Instance.new("Model")
	model.Name = "MonolithBeing"
	
	local basePos = getSpawnPosition()
	
	-- Build the entity body
	self:CreateCore(model, basePos)
	self:CreateFace(model, basePos)
	self:CreateTentacles(model, basePos)
	-- self:CreateSpines(model, basePos)  -- Removed
	self:CreatePulseNodes(model, basePos)
	self:CreateVeins(model, basePos)
	
	-- Build spiral platforms (platformer path to the top)
	local topPlatformInfo = self:CreatePlatforms(model, basePos)
	
	-- Build console at the top of the platforms
	self:CreateConsole(model, basePos, topPlatformInfo)
	
	model.Parent = folder
	self.Entity = model
	
	print("[MonolithEntityService] Created Monolith Entity with spiral platforms at", basePos)
	return model
end

-- === COLLISION CLEARING ===
function MonolithEntityService:ClearCollidingObjects()
	if not self.Entity then return end
	
	local basePos = getSpawnPosition()
	
	-- Define the clear zone around the monolith (generous radius)
	local clearRadius = CONFIG.Platforms.SpiralRadius + 25  -- Large padding for safety
	local clearHeight = CONFIG.BodyHeight + 50  -- Full height + top platform area
	
	-- Names of folders to exclude (monolith's own folder)
	local excludeFolders = {
		["MonolithEntity"] = true,
		["Baseplate"] = true,
		["Terrain"] = true,
		["Camera"] = true,
		["SpawnLocation"] = true,
	}
	
	-- Folders to specifically check for collisions
	local foldersToCheck = {
		workspace:FindFirstChild("Trees"),
		workspace:FindFirstChild("AlienFormations"),
		workspace:FindFirstChild("Mountains"),
		workspace:FindFirstChild("Formations"),
		workspace:FindFirstChild("Environment"),
	}
	
	local removedCount = 0
	
	-- Helper function to check if object should be removed
	local function shouldRemoveObject(obj)
		if not obj or not obj.Parent then return false end
		
		-- Skip if it's part of the monolith
		if obj:IsDescendantOf(self.Entity) then return false end
		local folder = obj:FindFirstAncestorWhichIsA("Folder")
		if folder and folder.Name == "MonolithEntity" then return false end
		
		local objPos
		if obj:IsA("Model") then
			local part = obj.PrimaryPart or obj:FindFirstChildWhichIsA("BasePart")
			if part then objPos = part.Position end
		elseif obj:IsA("BasePart") then
			-- Skip terrain and baseplate
			if obj.Name == "Baseplate" or obj.Name == "Terrain" then return false end
			objPos = obj.Position
		end
		
		if objPos then
			local horizontalDist = math.sqrt((objPos.X - basePos.X)^2 + (objPos.Z - basePos.Z)^2)
			local verticalDist = objPos.Y - basePos.Y
			
			if horizontalDist < clearRadius and verticalDist < clearHeight and verticalDist > -10 then
				return true
			end
		end
		
		return false
	end
	
	-- Check specific folders
	for _, folder in ipairs(foldersToCheck) do
		if folder then
			for _, obj in ipairs(folder:GetChildren()) do
				if shouldRemoveObject(obj) then
					obj:Destroy()
					removedCount = removedCount + 1
				end
			end
		end
	end
	
	-- Check tagged objects
	local CollectionService = game:GetService("CollectionService")
	local tagsToCheck = {"Tree", "AlienTree", "Formation", "Mountain", "Structure", "Obstacle"}
	
	for _, tag in ipairs(tagsToCheck) do
		for _, obj in ipairs(CollectionService:GetTagged(tag)) do
			if shouldRemoveObject(obj) then
				obj:Destroy()
				removedCount = removedCount + 1
			end
		end
	end
	
	-- Also scan all workspace children for any stray objects
	for _, child in ipairs(workspace:GetChildren()) do
		if not excludeFolders[child.Name] and child ~= self.Entity then
			if child:IsA("Model") or child:IsA("BasePart") then
				if shouldRemoveObject(child) then
					child:Destroy()
					removedCount = removedCount + 1
				end
			end
		end
	end
	
	print("[MonolithEntityService] Cleared", removedCount, "objects within radius", clearRadius, "of monolith")
end

-- === ANIMATION ===

function MonolithEntityService:StartAnimations()
	-- Eye blinking
	RunService.Heartbeat:Connect(function()
		if not self.IsAlive then return end
		
		local currentTime = tick()
		
		for _, eyeData in ipairs(self.BlinkingParts) do
			if currentTime >= eyeData.nextBlink then
				-- Blink: close eye
				eyeData.eye.Color = eyeData.closedColor
				eyeData.light.Brightness = 0
				
				-- Schedule eye open
				task.delay(CONFIG.BlinkDuration, function()
					if self.IsAlive and eyeData.eye and eyeData.eye.Parent then
						eyeData.eye.Color = eyeData.originalColor
						eyeData.light.Brightness = 0.5
					end
				end)
				
				-- Schedule next blink
				eyeData.nextBlink = currentTime + randomRange(CONFIG.BlinkInterval.Min, CONFIG.BlinkInterval.Max)
			end
		end
	end)
	
	-- Pulse nodes animation
	RunService.Heartbeat:Connect(function(dt)
		if not self.IsAlive then return end
		
		local time = tick()
		
		for _, pulseData in ipairs(self.PulsingParts) do
			local wave = math.sin((time / CONFIG.PulseSpeed) * math.pi * 2 + pulseData.phase)
			local intensity = 0.5 + wave * 0.5 -- 0 to 1
			
			-- Pulse brightness
			if pulseData.light and pulseData.light.Parent then
				pulseData.light.Brightness = pulseData.baseBrightness * (0.5 + intensity)
			end
		end
	end)
	
	-- Console indicator light blinking (random computer-like pattern)
	RunService.Heartbeat:Connect(function()
		if not self.IsAlive then return end
		
		local currentTime = tick()
		local cfg = CONFIG.Console
		
		for _, lightData in ipairs(self.ConsoleLights) do
			if currentTime >= lightData.nextToggle then
				-- Toggle light state
				lightData.isOn = not lightData.isOn
				
				if lightData.part and lightData.part.Parent then
					if lightData.isOn then
						lightData.part.Color = lightData.baseColor
						if lightData.light then
							lightData.light.Brightness = 0.3
						end
					else
						-- Dim when off
						lightData.part.Color = Color3.fromRGB(
							lightData.baseColor.R * 255 * 0.2,
							lightData.baseColor.G * 255 * 0.2,
							lightData.baseColor.B * 255 * 0.2
						)
						if lightData.light then
							lightData.light.Brightness = 0.05
						end
					end
				end
				
				-- Schedule next toggle
				lightData.nextToggle = currentTime + randomRange(cfg.BlinkSpeed.Min, cfg.BlinkSpeed.Max)
			end
		end
	end)
	
	-- Console lens slow pulse (HAL breathing effect)
	RunService.Heartbeat:Connect(function()
		if not self.IsAlive then return end
		if not self.ConsoleLens then return end
		
		local time = tick()
		local wave = math.sin(time * 0.5) * 0.5 + 0.5 -- Slow 0-1 pulse
		
		if self.ConsoleLens.light and self.ConsoleLens.light.Parent then
			self.ConsoleLens.light.Brightness = 0.5 + wave * 0.5
			self.ConsoleLens.light.Range = 10 + wave * 5
		end
	end)
	
	print("[MonolithEntityService] Animations started")
end

-- === KNIT LIFECYCLE ===

function MonolithEntityService:KnitInit()
	print("[MonolithEntityService] Initializing...")
	
	-- Register exclusion zone with GridService EARLY (before trees spawn)
	-- This prevents trees from spawning near the monolith in the first place
	task.spawn(function()
		local GridService = Knit.GetService("GridService")
		if GridService then
			local basePos = getSpawnPosition()
			local exclusionRadius = CONFIG.Platforms.SpiralRadius + 30  -- Large exclusion zone
			local exclusionHeight = CONFIG.BodyHeight + 60
			
			GridService:RegisterExclusionZone(
				"Monolith",
				basePos,
				exclusionRadius,
				exclusionHeight,
				"MonolithEntityService"
			)
			print("[MonolithEntityService] Registered exclusion zone with GridService - radius:", exclusionRadius)
		else
			warn("[MonolithEntityService] Could not get GridService to register exclusion zone")
		end
	end)
end

function MonolithEntityService:KnitStart()
	print("[MonolithEntityService] Starting...")
	
	-- Get LoadingService
	local LoadingService = nil
	pcall(function()
		LoadingService = Knit.GetService("LoadingService")
	end)
	
	if LoadingService then
		LoadingService:UpdateStatus("MonolithEntityService", "Awakening the Monolith...", 0)
	end
	
	-- Wait for other services to set up terrain, trees, formations, etc.
	task.wait(3)
	
	self:CreateEntity()
	
	-- Clear any objects that somehow spawned in the exclusion zone
	task.wait(0.5)
	self:ClearCollidingObjects()
	
	-- Clear again after a delay in case anything spawned late
	task.delay(2, function()
		self:ClearCollidingObjects()
	end)
	
	self:StartAnimations()
	
	-- Mark step complete
	if LoadingService then
		LoadingService:MarkStepComplete("MonolithEntityService")
	end
	
	print("[MonolithEntityService] Monolith Entity is alive")
end

-- === PUBLIC METHODS ===

function MonolithEntityService:GetEntity()
	return self.Entity
end

function MonolithEntityService:SetAlive(alive)
	self.IsAlive = alive
end

function MonolithEntityService:Regenerate()
	self:CreateEntity()
end

return MonolithEntityService

