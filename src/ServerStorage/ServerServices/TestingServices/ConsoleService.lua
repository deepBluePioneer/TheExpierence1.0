--[[
	ConsoleService
	
	Creates a futuristic control console with an interactive button
	in the center of the Building zone (flattened terrain area).
	
	The console features:
	- Industrial metal base platform
	- Angled control panel with holographic accents
	- Large interactive button with glow effects
	- Ambient lighting and detail parts
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local TweenService = game:GetService("TweenService")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local Knit = require(Packages.Knit)

local ConsoleService = Knit.CreateService {
	Name = "ConsoleService",
	Client = {
		ButtonPressed = Knit.CreateSignal(),  -- Signal for client notification
	},
	
	-- State
	_consoleModel = nil,
	_shipModel = nil,
	_button = nil,
	_spawnLocations = {},
	_wallSegments = {},  -- Store all wall segments for cascade animation
	_isInitialized = false,
	_buttonCooldown = false,
	_wallsDeployed = false,  -- Track if walls are currently deployed
	_animating = false,  -- Prevent overlapping animations
	
	-- Service references
	_reservedZoneService = nil,
	_gridService = nil,
}

-- === CONFIG ===
local CONFIG = {
	-- Console dimensions
	BaseSizeX = 6,
	BaseSizeY = 0.5,
	BaseSizeZ = 4,
	
	PanelSizeX = 5,
	PanelSizeY = 0.3,
	PanelSizeZ = 3,
	PanelAngle = 25,  -- Degrees tilt toward player
	
	ButtonRadius = 0.8,
	ButtonHeight = 0.4,
	
	-- Heights
	PedestalHeight = 2.5,
	
	-- Colors
	BaseColor = Color3.fromRGB(35, 35, 40),           -- Dark gunmetal
	PanelColor = Color3.fromRGB(25, 28, 35),          -- Dark charcoal
	AccentColor = Color3.fromRGB(0, 200, 255),        -- Cyan accent
	ButtonColor = Color3.fromRGB(255, 60, 60),        -- Red button
	ButtonGlowColor = Color3.fromRGB(255, 100, 100),  -- Button glow
	TrimColor = Color3.fromRGB(180, 140, 60),         -- Bronze/gold trim
	
	-- Materials
	BaseMaterial = Enum.Material.DiamondPlate,
	PanelMaterial = Enum.Material.SmoothPlastic,
	ButtonMaterial = Enum.Material.Neon,
	TrimMaterial = Enum.Material.Metal,
	
	-- Button behavior
	ButtonCooldownSeconds = 1.5,
	
	-- Spawn locations
	SpawnDistanceFromCenter = 8,  -- How far from center to place spawns
	SpawnLocationSize = Vector3.new(6, 1, 6),
	SpawnLocationColor = Color3.fromRGB(50, 50, 55),
	SpawnLocationMaterial = Enum.Material.SmoothPlastic,
	SpawnDecalTransparency = 0.3,
	
	-- Ship structure
	ShipWallThickness = 1.5,
	ShipWallHeight = 12,
	ShipCeilingThickness = 1,
	ShipPadding = 2,  -- Inward padding - walls placed inside the flattened zone
	
	-- Wall segments for cascade animation
	WallSegmentCount = 6,  -- Number of horizontal segments per wall
	WallSegmentGap = 0.1,  -- Small gap between segments
	CascadeDelayPerSegment = 0.4,  -- Delay between each segment animating
	CascadeAnimDuration = 0.8,  -- Duration of each segment's animation
	
	-- Ship colors
	ShipHullColor = Color3.fromRGB(45, 48, 55),          -- Dark steel gray
	ShipPanelColor = Color3.fromRGB(35, 38, 45),         -- Darker panel
	ShipFrameColor = Color3.fromRGB(60, 65, 75),         -- Lighter frame
	ShipAccentColor = Color3.fromRGB(0, 180, 220),       -- Cyan glow
	ShipWarningColor = Color3.fromRGB(255, 160, 0),      -- Orange warning
	ShipWindowColor = Color3.fromRGB(80, 150, 200),      -- Blue tinted glass
	
	-- Ship materials
	ShipHullMaterial = Enum.Material.Metal,
	ShipPanelMaterial = Enum.Material.DiamondPlate,
	ShipFrameMaterial = Enum.Material.Metal,
	ShipWindowMaterial = Enum.Material.Glass,
}

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         CONSOLE CREATION                                    ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

-- Create the base platform of the console
local function createBasePlatform(parent, position)
	-- Main base
	local base = Instance.new("Part")
	base.Name = "ConsoleBase"
	base.Size = Vector3.new(CONFIG.BaseSizeX, CONFIG.BaseSizeY, CONFIG.BaseSizeZ)
	base.Position = position + Vector3.new(0, CONFIG.BaseSizeY / 2, 0)
	base.Color = CONFIG.BaseColor
	base.Material = CONFIG.BaseMaterial
	base.Anchored = true
	base.CanCollide = true
	base.Parent = parent
	
	-- Base trim ring
	local trimRing = Instance.new("Part")
	trimRing.Name = "BaseTrim"
	trimRing.Size = Vector3.new(CONFIG.BaseSizeX + 0.2, 0.1, CONFIG.BaseSizeZ + 0.2)
	trimRing.Position = position + Vector3.new(0, 0.05, 0)
	trimRing.Color = CONFIG.TrimColor
	trimRing.Material = CONFIG.TrimMaterial
	trimRing.Anchored = true
	trimRing.CanCollide = false
	trimRing.Parent = parent
	
	return base
end

-- Create the pedestal/column
local function createPedestal(parent, basePosition)
	local pedestalHeight = CONFIG.PedestalHeight
	local pedestalWidth = 1.2
	
	-- Main pedestal column
	local pedestal = Instance.new("Part")
	pedestal.Name = "Pedestal"
	pedestal.Size = Vector3.new(pedestalWidth, pedestalHeight, pedestalWidth)
	pedestal.Position = basePosition + Vector3.new(0, CONFIG.BaseSizeY + pedestalHeight / 2, 0)
	pedestal.Color = CONFIG.BaseColor
	pedestal.Material = Enum.Material.Metal
	pedestal.Anchored = true
	pedestal.CanCollide = true
	pedestal.Parent = parent
	
	-- Accent light strips on pedestal (4 corners)
	local lightStripHeight = pedestalHeight * 0.8
	local lightStripWidth = 0.08
	local offsets = {
		Vector3.new(pedestalWidth/2 + 0.01, 0, pedestalWidth/2 - 0.1),
		Vector3.new(-pedestalWidth/2 - 0.01, 0, pedestalWidth/2 - 0.1),
		Vector3.new(pedestalWidth/2 + 0.01, 0, -pedestalWidth/2 + 0.1),
		Vector3.new(-pedestalWidth/2 - 0.01, 0, -pedestalWidth/2 + 0.1),
	}
	
	for i, offset in ipairs(offsets) do
		local lightStrip = Instance.new("Part")
		lightStrip.Name = "AccentLight_" .. i
		lightStrip.Size = Vector3.new(lightStripWidth, lightStripHeight, lightStripWidth)
		lightStrip.Position = pedestal.Position + offset
		lightStrip.Color = CONFIG.AccentColor
		lightStrip.Material = Enum.Material.Neon
		lightStrip.Anchored = true
		lightStrip.CanCollide = false
		lightStrip.Parent = parent
	end
	
	-- Top of pedestal decorative ring
	local topRing = Instance.new("Part")
	topRing.Name = "PedestalTopRing"
	topRing.Size = Vector3.new(pedestalWidth + 0.4, 0.15, pedestalWidth + 0.4)
	topRing.Position = basePosition + Vector3.new(0, CONFIG.BaseSizeY + pedestalHeight, 0)
	topRing.Color = CONFIG.TrimColor
	topRing.Material = CONFIG.TrimMaterial
	topRing.Anchored = true
	topRing.CanCollide = false
	topRing.Parent = parent
	
	return pedestal
end

-- Create the angled control panel
local function createControlPanel(parent, basePosition)
	local panelY = basePosition.Y + CONFIG.BaseSizeY + CONFIG.PedestalHeight + 0.2
	
	-- Main panel (angled)
	local panel = Instance.new("Part")
	panel.Name = "ControlPanel"
	panel.Size = Vector3.new(CONFIG.PanelSizeX, CONFIG.PanelSizeY, CONFIG.PanelSizeZ)
	panel.Color = CONFIG.PanelColor
	panel.Material = CONFIG.PanelMaterial
	panel.Anchored = true
	panel.CanCollide = true
	
	-- Position and rotate panel
	local panelCenterY = panelY + (CONFIG.PanelSizeZ / 2) * math.sin(math.rad(CONFIG.PanelAngle))
	local panelCenterZ = basePosition.Z - 0.3
	panel.CFrame = CFrame.new(basePosition.X, panelCenterY, panelCenterZ) 
		* CFrame.Angles(math.rad(-CONFIG.PanelAngle), 0, 0)
	panel.Parent = parent
	
	-- Panel border/frame
	local borderThickness = 0.12
	local borders = {
		{name = "BorderTop", size = Vector3.new(CONFIG.PanelSizeX + borderThickness*2, borderThickness, borderThickness), 
		 offset = Vector3.new(0, 0, -CONFIG.PanelSizeZ/2 - borderThickness/2)},
		{name = "BorderBottom", size = Vector3.new(CONFIG.PanelSizeX + borderThickness*2, borderThickness, borderThickness), 
		 offset = Vector3.new(0, 0, CONFIG.PanelSizeZ/2 + borderThickness/2)},
		{name = "BorderLeft", size = Vector3.new(borderThickness, borderThickness, CONFIG.PanelSizeZ), 
		 offset = Vector3.new(-CONFIG.PanelSizeX/2 - borderThickness/2, 0, 0)},
		{name = "BorderRight", size = Vector3.new(borderThickness, borderThickness, CONFIG.PanelSizeZ), 
		 offset = Vector3.new(CONFIG.PanelSizeX/2 + borderThickness/2, 0, 0)},
	}
	
	for _, borderData in ipairs(borders) do
		local border = Instance.new("Part")
		border.Name = borderData.name
		border.Size = borderData.size
		border.Color = CONFIG.TrimColor
		border.Material = CONFIG.TrimMaterial
		border.Anchored = true
		border.CanCollide = false
		border.CFrame = panel.CFrame * CFrame.new(borderData.offset)
		border.Parent = parent
	end
	
	-- Decorative screen/display area (left side of panel)
	local screen = Instance.new("Part")
	screen.Name = "DisplayScreen"
	screen.Size = Vector3.new(1.8, 0.05, 1.5)
	screen.Color = Color3.fromRGB(20, 40, 50)
	screen.Material = Enum.Material.Glass
	screen.Transparency = 0.3
	screen.Anchored = true
	screen.CanCollide = false
	screen.CFrame = panel.CFrame * CFrame.new(-1.2, CONFIG.PanelSizeY/2 + 0.03, 0)
	screen.Parent = parent
	
	-- Screen glow
	local screenGlow = Instance.new("Part")
	screenGlow.Name = "ScreenGlow"
	screenGlow.Size = Vector3.new(1.6, 0.02, 1.3)
	screenGlow.Color = CONFIG.AccentColor
	screenGlow.Material = Enum.Material.Neon
	screenGlow.Transparency = 0.5
	screenGlow.Anchored = true
	screenGlow.CanCollide = false
	screenGlow.CFrame = panel.CFrame * CFrame.new(-1.2, CONFIG.PanelSizeY/2 + 0.06, 0)
	screenGlow.Parent = parent
	
	-- Small indicator lights on panel
	local indicatorPositions = {
		{offset = Vector3.new(1.5, CONFIG.PanelSizeY/2 + 0.05, -0.8), color = Color3.fromRGB(0, 255, 100)},
		{offset = Vector3.new(1.5, CONFIG.PanelSizeY/2 + 0.05, -0.4), color = Color3.fromRGB(255, 200, 0)},
		{offset = Vector3.new(1.5, CONFIG.PanelSizeY/2 + 0.05, 0), color = CONFIG.AccentColor},
	}
	
	for i, indicator in ipairs(indicatorPositions) do
		local light = Instance.new("Part")
		light.Name = "Indicator_" .. i
		light.Shape = Enum.PartType.Ball
		light.Size = Vector3.new(0.15, 0.15, 0.15)
		light.Color = indicator.color
		light.Material = Enum.Material.Neon
		light.Anchored = true
		light.CanCollide = false
		light.CFrame = panel.CFrame * CFrame.new(indicator.offset)
		light.Parent = parent
	end
	
	return panel
end

-- Create the main interactive button
local function createButton(parent, panel)
	-- Button housing/base
	local buttonHousing = Instance.new("Part")
	buttonHousing.Name = "ButtonHousing"
	buttonHousing.Shape = Enum.PartType.Cylinder
	buttonHousing.Size = Vector3.new(0.3, CONFIG.ButtonRadius * 2.4, CONFIG.ButtonRadius * 2.4)
	buttonHousing.Color = CONFIG.BaseColor
	buttonHousing.Material = Enum.Material.Metal
	buttonHousing.Anchored = true
	buttonHousing.CanCollide = false
	-- Position on right side of panel
	buttonHousing.CFrame = panel.CFrame 
		* CFrame.new(1.2, CONFIG.PanelSizeY/2 + 0.15, 0.5) 
		* CFrame.Angles(0, 0, math.rad(90))
	buttonHousing.Parent = parent
	
	-- The actual button (pressable)
	local button = Instance.new("Part")
	button.Name = "InteractiveButton"
	button.Shape = Enum.PartType.Cylinder
	button.Size = Vector3.new(CONFIG.ButtonHeight, CONFIG.ButtonRadius * 2, CONFIG.ButtonRadius * 2)
	button.Color = CONFIG.ButtonColor
	button.Material = CONFIG.ButtonMaterial
	button.Anchored = true
	button.CanCollide = false
	button.CFrame = panel.CFrame 
		* CFrame.new(1.2, CONFIG.PanelSizeY/2 + 0.15 + CONFIG.ButtonHeight/2 + 0.15, 0.5) 
		* CFrame.Angles(0, 0, math.rad(90))
	button.Parent = parent
	
	-- Add ClickDetector for interaction
	local clickDetector = Instance.new("ClickDetector")
	clickDetector.Name = "ButtonClickDetector"
	clickDetector.MaxActivationDistance = 10
	clickDetector.CursorIcon = "rbxasset://textures/Cursors/KeyboardMouse/ArrowFarCursor.png"
	clickDetector.Parent = button
	
	-- Button glow ring
	local glowRing = Instance.new("Part")
	glowRing.Name = "ButtonGlowRing"
	glowRing.Shape = Enum.PartType.Cylinder
	glowRing.Size = Vector3.new(0.08, CONFIG.ButtonRadius * 2.6, CONFIG.ButtonRadius * 2.6)
	glowRing.Color = CONFIG.ButtonGlowColor
	glowRing.Material = Enum.Material.Neon
	glowRing.Transparency = 0.3
	glowRing.Anchored = true
	glowRing.CanCollide = false
	glowRing.CFrame = buttonHousing.CFrame
	glowRing.Parent = parent
	
	-- Pulsing light effect
	local pointLight = Instance.new("PointLight")
	pointLight.Name = "ButtonLight"
	pointLight.Color = CONFIG.ButtonColor
	pointLight.Brightness = 2
	pointLight.Range = 8
	pointLight.Shadows = false
	pointLight.Parent = button
	
	return button, clickDetector
end

-- Create corner posts/supports for the base
local function createCornerPosts(parent, basePosition)
	local postHeight = 1.5
	local postSize = 0.25
	local baseHalfX = CONFIG.BaseSizeX / 2 - postSize / 2 - 0.2
	local baseHalfZ = CONFIG.BaseSizeZ / 2 - postSize / 2 - 0.2
	
	local corners = {
		Vector3.new(baseHalfX, 0, baseHalfZ),
		Vector3.new(-baseHalfX, 0, baseHalfZ),
		Vector3.new(baseHalfX, 0, -baseHalfZ),
		Vector3.new(-baseHalfX, 0, -baseHalfZ),
	}
	
	for i, corner in ipairs(corners) do
		-- Post
		local post = Instance.new("Part")
		post.Name = "CornerPost_" .. i
		post.Size = Vector3.new(postSize, postHeight, postSize)
		post.Position = basePosition + corner + Vector3.new(0, CONFIG.BaseSizeY + postHeight/2, 0)
		post.Color = CONFIG.BaseColor
		post.Material = Enum.Material.Metal
		post.Anchored = true
		post.CanCollide = false
		post.Parent = parent
		
		-- Post top light
		local topLight = Instance.new("Part")
		topLight.Name = "PostLight_" .. i
		topLight.Shape = Enum.PartType.Ball
		topLight.Size = Vector3.new(0.2, 0.2, 0.2)
		topLight.Position = post.Position + Vector3.new(0, postHeight/2 + 0.1, 0)
		topLight.Color = CONFIG.AccentColor
		topLight.Material = Enum.Material.Neon
		topLight.Anchored = true
		topLight.CanCollide = false
		topLight.Parent = parent
	end
end

-- Create 4 spawn locations around the console
local function createSpawnLocations(self, centerPosition)
	local spawnLocations = {}
	local distance = CONFIG.SpawnDistanceFromCenter
	
	-- 4 spawn positions: front, back, left, right of the console
	local spawnPositions = {
		{offset = Vector3.new(0, 0, -distance), rotation = 0, name = "SpawnFront"},      -- Front (facing console)
		{offset = Vector3.new(0, 0, distance), rotation = 180, name = "SpawnBack"},      -- Back (facing console)
		{offset = Vector3.new(-distance, 0, 0), rotation = 90, name = "SpawnLeft"},      -- Left (facing console)
		{offset = Vector3.new(distance, 0, 0), rotation = -90, name = "SpawnRight"},     -- Right (facing console)
	}
	
	for i, spawnData in ipairs(spawnPositions) do
		local spawnPos = centerPosition + spawnData.offset
		
		-- Create SpawnLocation
		local spawn = Instance.new("SpawnLocation")
		spawn.Name = spawnData.name
		spawn.Size = CONFIG.SpawnLocationSize
		spawn.Color = CONFIG.SpawnLocationColor
		spawn.Material = CONFIG.SpawnLocationMaterial
		spawn.Anchored = true
		spawn.CanCollide = true
		spawn.Neutral = true  -- Allow all teams to spawn here
		spawn.AllowTeamChangeOnTouch = false
		spawn.Duration = 0  -- No spawn protection duration
		
		-- Position spawn on the ground, rotated to face console
		spawn.CFrame = CFrame.new(spawnPos.X, spawnPos.Y + CONFIG.SpawnLocationSize.Y / 2, spawnPos.Z) 
			* CFrame.Angles(0, math.rad(spawnData.rotation), 0)
		
		-- Add a subtle accent border around spawn
		local borderThickness = 0.15
		local borderHeight = 0.1
		local borders = {
			{size = Vector3.new(CONFIG.SpawnLocationSize.X + borderThickness * 2, borderHeight, borderThickness), 
			 offset = Vector3.new(0, CONFIG.SpawnLocationSize.Y / 2, -CONFIG.SpawnLocationSize.Z / 2 - borderThickness / 2)},
			{size = Vector3.new(CONFIG.SpawnLocationSize.X + borderThickness * 2, borderHeight, borderThickness), 
			 offset = Vector3.new(0, CONFIG.SpawnLocationSize.Y / 2, CONFIG.SpawnLocationSize.Z / 2 + borderThickness / 2)},
			{size = Vector3.new(borderThickness, borderHeight, CONFIG.SpawnLocationSize.Z), 
			 offset = Vector3.new(-CONFIG.SpawnLocationSize.X / 2 - borderThickness / 2, CONFIG.SpawnLocationSize.Y / 2, 0)},
			{size = Vector3.new(borderThickness, borderHeight, CONFIG.SpawnLocationSize.Z), 
			 offset = Vector3.new(CONFIG.SpawnLocationSize.X / 2 + borderThickness / 2, CONFIG.SpawnLocationSize.Y / 2, 0)},
		}
		
		for j, borderData in ipairs(borders) do
			local border = Instance.new("Part")
			border.Name = "SpawnBorder_" .. j
			border.Size = borderData.size
			border.Color = CONFIG.AccentColor
			border.Material = Enum.Material.Neon
			border.Transparency = 0.5
			border.Anchored = true
			border.CanCollide = false
			border.CFrame = spawn.CFrame * CFrame.new(borderData.offset)
			border.Parent = spawn
		end
		
		-- Add corner accent lights
		local cornerOffset = CONFIG.SpawnLocationSize.X / 2 - 0.3
		local cornerPositions = {
			Vector3.new(cornerOffset, CONFIG.SpawnLocationSize.Y / 2 + 0.1, cornerOffset),
			Vector3.new(-cornerOffset, CONFIG.SpawnLocationSize.Y / 2 + 0.1, cornerOffset),
			Vector3.new(cornerOffset, CONFIG.SpawnLocationSize.Y / 2 + 0.1, -cornerOffset),
			Vector3.new(-cornerOffset, CONFIG.SpawnLocationSize.Y / 2 + 0.1, -cornerOffset),
		}
		
		for j, cornerPos in ipairs(cornerPositions) do
			local light = Instance.new("Part")
			light.Name = "SpawnLight_" .. j
			light.Shape = Enum.PartType.Ball
			light.Size = Vector3.new(0.25, 0.25, 0.25)
			light.Color = CONFIG.AccentColor
			light.Material = Enum.Material.Neon
			light.Anchored = true
			light.CanCollide = false
			light.CFrame = spawn.CFrame * CFrame.new(cornerPos)
			light.Parent = spawn
		end
		
		spawn.Parent = Workspace
		table.insert(spawnLocations, spawn)
	end
	
	self._spawnLocations = spawnLocations
	print(string.format("[ConsoleService] Created %d spawn locations around console", #spawnLocations))
	
	return spawnLocations
end

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                      TRANSPORT SHIP STRUCTURE                               ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

-- Create a segmented wall with multiple horizontal panels for cascade animation
-- Returns array of segments ordered from top to bottom
local function createSegmentedWall(parent, basePosition, totalSize, rotation, wallIndex)
	local segments = {}
	local segmentCount = CONFIG.WallSegmentCount
	local gap = CONFIG.WallSegmentGap
	
	-- Calculate segment height (accounting for gaps)
	local totalGapHeight = gap * (segmentCount - 1)
	local segmentHeight = (totalSize.Y - totalGapHeight) / segmentCount
	
	-- Create segments from top to bottom
	for i = 1, segmentCount do
		-- Calculate Y position for this segment (top to bottom)
		local segmentIndex = i - 1
		local yOffset = totalSize.Y / 2 - segmentHeight / 2 - segmentIndex * (segmentHeight + gap)
		
		local segment = Instance.new("Part")
		segment.Name = string.format("WallSegment_%d_%d", wallIndex, i)
		segment.Size = Vector3.new(totalSize.X, segmentHeight, totalSize.Z)
		
		-- Position at the deployed location
		local deployedCFrame = CFrame.new(basePosition + Vector3.new(0, yOffset, 0)) 
			* CFrame.Angles(0, math.rad(rotation), 0)
		segment.CFrame = deployedCFrame
		
		segment.Color = CONFIG.ShipHullColor
		segment.Material = CONFIG.ShipHullMaterial
		segment.Anchored = true
		segment.CanCollide = true
		segment.Parent = parent
		
		-- Store segment data
		table.insert(segments, {
			part = segment,
			deployedCFrame = deployedCFrame,
			-- Hidden position is above the ceiling
			hiddenCFrame = CFrame.new(basePosition + Vector3.new(0, totalSize.Y + 5 + (segmentCount - i) * (segmentHeight + gap), 0)) 
				* CFrame.Angles(0, math.rad(rotation), 0),
			segmentIndex = i,
			wallIndex = wallIndex,
		})
	end
	
	return segments
end

-- Legacy single wall segment (for non-animated parts)
local function createWallSegment(parent, position, size, rotation)
	local wall = Instance.new("Part")
	wall.Name = "ShipWall"
	wall.Size = size
	wall.CFrame = CFrame.new(position) * CFrame.Angles(0, math.rad(rotation), 0)
	wall.Color = CONFIG.ShipHullColor
	wall.Material = CONFIG.ShipHullMaterial
	wall.Anchored = true
	wall.CanCollide = true
	wall.Parent = parent
	
	return wall
end

-- Create interior wall panels with details
local function createWallPaneling(parent, wallCFrame, wallSize, isLongWall)
	local panelHeight = wallSize.Y * 0.6
	local panelWidth = isLongWall and wallSize.X * 0.25 or wallSize.X * 0.4
	local panelDepth = 0.1
	local panelCount = isLongWall and 3 or 2
	
	local spacing = wallSize.X / (panelCount + 1)
	
	for i = 1, panelCount do
		local offsetX = -wallSize.X/2 + spacing * i
		
		-- Panel background
		local panel = Instance.new("Part")
		panel.Name = "WallPanel_" .. i
		panel.Size = Vector3.new(panelWidth, panelHeight, panelDepth)
		panel.CFrame = wallCFrame * CFrame.new(offsetX, 0, -wallSize.Z/2 - panelDepth/2)
		panel.Color = CONFIG.ShipPanelColor
		panel.Material = CONFIG.ShipPanelMaterial
		panel.Anchored = true
		panel.CanCollide = false
		panel.Parent = parent
		
		-- Panel frame
		local frameThickness = 0.08
		local frames = {
			{size = Vector3.new(panelWidth + frameThickness*2, frameThickness, frameThickness), 
			 offset = Vector3.new(0, panelHeight/2, 0)},
			{size = Vector3.new(panelWidth + frameThickness*2, frameThickness, frameThickness), 
			 offset = Vector3.new(0, -panelHeight/2, 0)},
			{size = Vector3.new(frameThickness, panelHeight, frameThickness), 
			 offset = Vector3.new(-panelWidth/2, 0, 0)},
			{size = Vector3.new(frameThickness, panelHeight, frameThickness), 
			 offset = Vector3.new(panelWidth/2, 0, 0)},
		}
		
		for j, frameData in ipairs(frames) do
			local frame = Instance.new("Part")
			frame.Name = "PanelFrame_" .. j
			frame.Size = frameData.size
			frame.CFrame = panel.CFrame * CFrame.new(frameData.offset)
			frame.Color = CONFIG.ShipFrameColor
			frame.Material = CONFIG.ShipFrameMaterial
			frame.Anchored = true
			frame.CanCollide = false
			frame.Parent = parent
		end
		
		-- Accent light strip at bottom of panel
		local accentLight = Instance.new("Part")
		accentLight.Name = "PanelAccent_" .. i
		accentLight.Size = Vector3.new(panelWidth * 0.8, 0.1, 0.05)
		accentLight.CFrame = panel.CFrame * CFrame.new(0, -panelHeight/2 + 0.3, -0.05)
		accentLight.Color = CONFIG.ShipAccentColor
		accentLight.Material = Enum.Material.Neon
		accentLight.Anchored = true
		accentLight.CanCollide = false
		accentLight.Parent = parent
	end
end

-- Create structural corner pillars
local function createCornerPillar(parent, position, height)
	local pillarSize = 0.8
	
	-- Main pillar
	local pillar = Instance.new("Part")
	pillar.Name = "CornerPillar"
	pillar.Size = Vector3.new(pillarSize, height, pillarSize)
	pillar.Position = position + Vector3.new(0, height/2, 0)
	pillar.Color = CONFIG.ShipFrameColor
	pillar.Material = CONFIG.ShipFrameMaterial
	pillar.Anchored = true
	pillar.CanCollide = true
	pillar.Parent = parent
	
	-- Accent light strip on pillar
	local lightStrip = Instance.new("Part")
	lightStrip.Name = "PillarLight"
	lightStrip.Size = Vector3.new(0.1, height * 0.85, 0.1)
	lightStrip.Position = pillar.Position
	lightStrip.Color = CONFIG.ShipAccentColor
	lightStrip.Material = Enum.Material.Neon
	lightStrip.Anchored = true
	lightStrip.CanCollide = false
	lightStrip.Parent = parent
	
	-- Top cap
	local cap = Instance.new("Part")
	cap.Name = "PillarCap"
	cap.Size = Vector3.new(pillarSize + 0.2, 0.2, pillarSize + 0.2)
	cap.Position = position + Vector3.new(0, height, 0)
	cap.Color = CONFIG.ShipFrameColor
	cap.Material = CONFIG.ShipFrameMaterial
	cap.Anchored = true
	cap.CanCollide = false
	cap.Parent = parent
	
	return pillar
end

-- Create ceiling with lighting fixtures
local function createCeiling(parent, centerPos, sizeX, sizeZ, floorY)
	local ceilingY = floorY + CONFIG.ShipWallHeight
	
	-- Main ceiling
	local ceiling = Instance.new("Part")
	ceiling.Name = "ShipCeiling"
	ceiling.Size = Vector3.new(sizeX, CONFIG.ShipCeilingThickness, sizeZ)
	ceiling.Position = Vector3.new(centerPos.X, ceilingY + CONFIG.ShipCeilingThickness/2, centerPos.Z)
	ceiling.Color = CONFIG.ShipHullColor
	ceiling.Material = CONFIG.ShipHullMaterial
	ceiling.Anchored = true
	ceiling.CanCollide = true
	ceiling.Parent = parent
	
	-- Ceiling beams (cross pattern)
	local beamThickness = 0.4
	local beamDepth = 0.6
	
	-- Main cross beams
	local beam1 = Instance.new("Part")
	beam1.Name = "CeilingBeam_X"
	beam1.Size = Vector3.new(sizeX - 2, beamDepth, beamThickness)
	beam1.Position = Vector3.new(centerPos.X, ceilingY - beamDepth/2, centerPos.Z)
	beam1.Color = CONFIG.ShipFrameColor
	beam1.Material = CONFIG.ShipFrameMaterial
	beam1.Anchored = true
	beam1.CanCollide = false
	beam1.Parent = parent
	
	local beam2 = Instance.new("Part")
	beam2.Name = "CeilingBeam_Z"
	beam2.Size = Vector3.new(beamThickness, beamDepth, sizeZ - 2)
	beam2.Position = Vector3.new(centerPos.X, ceilingY - beamDepth/2, centerPos.Z)
	beam2.Color = CONFIG.ShipFrameColor
	beam2.Material = CONFIG.ShipFrameMaterial
	beam2.Anchored = true
	beam2.CanCollide = false
	beam2.Parent = parent
	
	-- Ceiling light fixtures (4 quadrants)
	local lightOffsetX = sizeX / 4
	local lightOffsetZ = sizeZ / 4
	local lightPositions = {
		Vector3.new(lightOffsetX, 0, lightOffsetZ),
		Vector3.new(-lightOffsetX, 0, lightOffsetZ),
		Vector3.new(lightOffsetX, 0, -lightOffsetZ),
		Vector3.new(-lightOffsetX, 0, -lightOffsetZ),
	}
	
	for i, offset in ipairs(lightPositions) do
		-- Light housing
		local housing = Instance.new("Part")
		housing.Name = "LightHousing_" .. i
		housing.Size = Vector3.new(3, 0.3, 3)
		housing.Position = Vector3.new(centerPos.X + offset.X, ceilingY - 0.15, centerPos.Z + offset.Z)
		housing.Color = CONFIG.ShipFrameColor
		housing.Material = CONFIG.ShipFrameMaterial
		housing.Anchored = true
		housing.CanCollide = false
		housing.Parent = parent
		
		-- Light panel
		local lightPanel = Instance.new("Part")
		lightPanel.Name = "LightPanel_" .. i
		lightPanel.Size = Vector3.new(2.5, 0.1, 2.5)
		lightPanel.Position = Vector3.new(centerPos.X + offset.X, ceilingY - 0.35, centerPos.Z + offset.Z)
		lightPanel.Color = Color3.fromRGB(255, 250, 240)
		lightPanel.Material = Enum.Material.Neon
		lightPanel.Transparency = 0.2
		lightPanel.Anchored = true
		lightPanel.CanCollide = false
		lightPanel.Parent = parent
		
		-- Point light
		local pointLight = Instance.new("PointLight")
		pointLight.Color = Color3.fromRGB(255, 250, 240)
		pointLight.Brightness = 1.5
		pointLight.Range = 20
		pointLight.Shadows = true
		pointLight.Parent = lightPanel
	end
	
	return ceiling
end

-- Create viewport windows on walls
local function createViewport(parent, wallCFrame, wallSize, side)
	local windowWidth = wallSize.X * 0.3
	local windowHeight = wallSize.Y * 0.35
	local windowDepth = CONFIG.ShipWallThickness + 0.1
	
	-- Window frame (cut-out effect)
	local frame = Instance.new("Part")
	frame.Name = "ViewportFrame_" .. side
	frame.Size = Vector3.new(windowWidth + 0.3, windowHeight + 0.3, windowDepth)
	frame.CFrame = wallCFrame * CFrame.new(0, wallSize.Y * 0.15, 0)
	frame.Color = CONFIG.ShipFrameColor
	frame.Material = CONFIG.ShipFrameMaterial
	frame.Anchored = true
	frame.CanCollide = false
	frame.Parent = parent
	
	-- Glass pane
	local glass = Instance.new("Part")
	glass.Name = "ViewportGlass_" .. side
	glass.Size = Vector3.new(windowWidth, windowHeight, 0.1)
	glass.CFrame = wallCFrame * CFrame.new(0, wallSize.Y * 0.15, 0)
	glass.Color = CONFIG.ShipWindowColor
	glass.Material = CONFIG.ShipWindowMaterial
	glass.Transparency = 0.6
	glass.Anchored = true
	glass.CanCollide = false
	glass.Parent = parent
	
	-- Window accent lights (top and bottom)
	local topLight = Instance.new("Part")
	topLight.Name = "ViewportLightTop_" .. side
	topLight.Size = Vector3.new(windowWidth, 0.08, 0.15)
	topLight.CFrame = wallCFrame * CFrame.new(0, wallSize.Y * 0.15 + windowHeight/2 + 0.1, -wallSize.Z/2 - 0.1)
	topLight.Color = CONFIG.ShipAccentColor
	topLight.Material = Enum.Material.Neon
	topLight.Anchored = true
	topLight.CanCollide = false
	topLight.Parent = parent
	
	local bottomLight = Instance.new("Part")
	bottomLight.Name = "ViewportLightBottom_" .. side
	bottomLight.Size = Vector3.new(windowWidth, 0.08, 0.15)
	bottomLight.CFrame = wallCFrame * CFrame.new(0, wallSize.Y * 0.15 - windowHeight/2 - 0.1, -wallSize.Z/2 - 0.1)
	bottomLight.Color = CONFIG.ShipAccentColor
	bottomLight.Material = Enum.Material.Neon
	bottomLight.Anchored = true
	bottomLight.CanCollide = false
	bottomLight.Parent = parent
end

-- Create warning stripes near floor
local function createWarningStripes(parent, wallCFrame, wallSize)
	local stripeHeight = 0.3
	local stripeY = -wallSize.Y/2 + stripeHeight/2 + 0.5
	
	local stripe = Instance.new("Part")
	stripe.Name = "WarningStripe"
	stripe.Size = Vector3.new(wallSize.X - 0.5, stripeHeight, 0.05)
	stripe.CFrame = wallCFrame * CFrame.new(0, stripeY, -wallSize.Z/2 - 0.03)
	stripe.Color = CONFIG.ShipWarningColor
	stripe.Material = Enum.Material.Neon
	stripe.Transparency = 0.3
	stripe.Anchored = true
	stripe.CanCollide = false
	stripe.Parent = parent
end

-- Create floor trim/baseboards
local function createFloorTrim(parent, centerPos, sizeX, sizeZ, floorY)
	local trimHeight = 0.4
	local trimDepth = 0.15
	
	local trims = {
		{pos = Vector3.new(centerPos.X, floorY + trimHeight/2, centerPos.Z - sizeZ/2 + trimDepth/2), 
		 size = Vector3.new(sizeX, trimHeight, trimDepth)},
		{pos = Vector3.new(centerPos.X, floorY + trimHeight/2, centerPos.Z + sizeZ/2 - trimDepth/2), 
		 size = Vector3.new(sizeX, trimHeight, trimDepth)},
		{pos = Vector3.new(centerPos.X - sizeX/2 + trimDepth/2, floorY + trimHeight/2, centerPos.Z), 
		 size = Vector3.new(trimDepth, trimHeight, sizeZ - trimDepth*2)},
		{pos = Vector3.new(centerPos.X + sizeX/2 - trimDepth/2, floorY + trimHeight/2, centerPos.Z), 
		 size = Vector3.new(trimDepth, trimHeight, sizeZ - trimDepth*2)},
	}
	
	for i, trimData in ipairs(trims) do
		local trim = Instance.new("Part")
		trim.Name = "FloorTrim_" .. i
		trim.Size = trimData.size
		trim.Position = trimData.pos
		trim.Color = CONFIG.ShipFrameColor
		trim.Material = CONFIG.ShipFrameMaterial
		trim.Anchored = true
		trim.CanCollide = false
		trim.Parent = parent
		
		-- Accent light on trim
		local accentSize = Vector3.new(trimData.size.X * 0.95, 0.08, 0.05)
		if trimData.size.X < trimData.size.Z then
			accentSize = Vector3.new(0.05, 0.08, trimData.size.Z * 0.95)
		end
		
		local accent = Instance.new("Part")
		accent.Name = "TrimAccent_" .. i
		accent.Size = accentSize
		accent.Position = trimData.pos + Vector3.new(0, trimHeight/2 - 0.05, 0)
		accent.Color = CONFIG.ShipAccentColor
		accent.Material = Enum.Material.Neon
		accent.Transparency = 0.5
		accent.Anchored = true
		accent.CanCollide = false
		accent.Parent = parent
	end
end

-- Assemble the complete transport ship structure
local function assembleShipStructure(self, centerPosition, zoneSizeX, zoneSizeZ)
	local shipModel = Instance.new("Model")
	shipModel.Name = "TransportShip"
	
	local floorY = centerPosition.Y
	local wallHeight = CONFIG.ShipWallHeight
	local wallThickness = CONFIG.ShipWallThickness
	local padding = CONFIG.ShipPadding
	
	-- Interior dimensions - walls placed inward from the flattened zone edges
	local interiorX = zoneSizeX - padding * 2
	local interiorZ = zoneSizeZ - padding * 2
	
	-- Exterior dimensions (including walls)
	local exteriorX = interiorX + wallThickness * 2
	local exteriorZ = interiorZ + wallThickness * 2
	
	local wallCenterY = floorY + wallHeight / 2
	
	-- Create 4 segmented walls for cascade animation
	local allWallSegments = {}
	local walls = {
		-- Front wall (negative Z)
		{pos = Vector3.new(centerPosition.X, wallCenterY, centerPosition.Z - interiorZ/2 - wallThickness/2),
		 size = Vector3.new(exteriorX, wallHeight, wallThickness), rot = 0, side = "Front", isLong = true, index = 1},
		-- Back wall (positive Z)
		{pos = Vector3.new(centerPosition.X, wallCenterY, centerPosition.Z + interiorZ/2 + wallThickness/2),
		 size = Vector3.new(exteriorX, wallHeight, wallThickness), rot = 180, side = "Back", isLong = true, index = 2},
		-- Left wall (negative X)
		{pos = Vector3.new(centerPosition.X - interiorX/2 - wallThickness/2, wallCenterY, centerPosition.Z),
		 size = Vector3.new(interiorZ, wallHeight, wallThickness), rot = 90, side = "Left", isLong = false, index = 3},
		-- Right wall (positive X)
		{pos = Vector3.new(centerPosition.X + interiorX/2 + wallThickness/2, wallCenterY, centerPosition.Z),
		 size = Vector3.new(interiorZ, wallHeight, wallThickness), rot = -90, side = "Right", isLong = false, index = 4},
	}
	
	for _, wallData in ipairs(walls) do
		-- Create segmented wall
		local segments = createSegmentedWall(shipModel, wallData.pos, wallData.size, wallData.rot, wallData.index)
		
		-- Store all segments
		for _, segment in ipairs(segments) do
			table.insert(allWallSegments, segment)
		end
	end
	
	-- Create corner pillars
	local cornerPositions = {
		Vector3.new(centerPosition.X - interiorX/2, floorY, centerPosition.Z - interiorZ/2),
		Vector3.new(centerPosition.X + interiorX/2, floorY, centerPosition.Z - interiorZ/2),
		Vector3.new(centerPosition.X - interiorX/2, floorY, centerPosition.Z + interiorZ/2),
		Vector3.new(centerPosition.X + interiorX/2, floorY, centerPosition.Z + interiorZ/2),
	}
	
	for _, cornerPos in ipairs(cornerPositions) do
		createCornerPillar(shipModel, cornerPos, wallHeight)
	end
	
	-- Create ceiling
	createCeiling(shipModel, centerPosition, exteriorX, exteriorZ, floorY)
	
	-- Create floor trim
	createFloorTrim(shipModel, centerPosition, interiorX, interiorZ, floorY)
	
	-- Set primary part and parent
	shipModel.Parent = Workspace
	
	self._shipModel = shipModel
	self._wallSegments = allWallSegments
	self._wallsDeployed = true  -- Walls start deployed
	
	print(string.format("[ConsoleService] Transport ship created (%.1f x %.1f interior) with %d wall segments", 
		interiorX, interiorZ, #allWallSegments))
	
	return shipModel, allWallSegments
end

-- Assemble the complete console
local function assembleConsole(self, centerPosition)
	-- Create model container
	local consoleModel = Instance.new("Model")
	consoleModel.Name = "ControlConsole"
	
	-- Build all components
	local base = createBasePlatform(consoleModel, centerPosition)
	local pedestal = createPedestal(consoleModel, centerPosition)
	local panel = createControlPanel(consoleModel, centerPosition)
	local button, clickDetector = createButton(consoleModel, panel)
	createCornerPosts(consoleModel, centerPosition)
	
	-- Set primary part
	consoleModel.PrimaryPart = base
	consoleModel.Parent = Workspace
	
	-- Store references
	self._consoleModel = consoleModel
	self._button = button
	
	-- Setup button interaction
	clickDetector.MouseClick:Connect(function(player)
		self:OnButtonPressed(player)
	end)
	
	-- Add hover effects
	clickDetector.MouseHoverEnter:Connect(function(player)
		self:OnButtonHoverEnter()
	end)
	
	clickDetector.MouseHoverLeave:Connect(function(player)
		self:OnButtonHoverLeave()
	end)
	
	return consoleModel
end

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         WALL CASCADE ANIMATION                              ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

-- Animate walls cascading down (deploying) - top segments first
function ConsoleService:CascadeWallsDown()
	if self._animating or self._wallsDeployed then
		return
	end
	
	self._animating = true
	print("[ConsoleService] Cascading walls DOWN (deploying)...")
	
	-- Sort segments by wall index, then by segment index (top to bottom)
	local sortedSegments = {}
	for _, seg in ipairs(self._wallSegments) do
		table.insert(sortedSegments, seg)
	end
	
	table.sort(sortedSegments, function(a, b)
		if a.wallIndex == b.wallIndex then
			return a.segmentIndex < b.segmentIndex  -- Top segments first
		end
		return a.wallIndex < b.wallIndex
	end)
	
	-- Animate each segment with cascade delay
	local tweenInfo = TweenInfo.new(
		CONFIG.CascadeAnimDuration,
		Enum.EasingStyle.Quad,
		Enum.EasingDirection.Out
	)
	
	-- Group by segment index for synchronized cascade across all walls
	local maxSegmentIndex = CONFIG.WallSegmentCount
	
	for segIdx = 1, maxSegmentIndex do
		-- Animate all walls' segment at this level simultaneously
		for _, seg in ipairs(sortedSegments) do
			if seg.segmentIndex == segIdx then
				local tween = TweenService:Create(seg.part, tweenInfo, {CFrame = seg.deployedCFrame})
				tween:Play()
				seg.part.CanCollide = true
			end
		end
		
		-- Wait before next row of segments
		if segIdx < maxSegmentIndex then
			task.wait(CONFIG.CascadeDelayPerSegment)
		end
	end
	
	-- Wait for last animation to complete
	task.wait(CONFIG.CascadeAnimDuration)
	
	self._wallsDeployed = true
	self._animating = false
	print("[ConsoleService] Walls deployed")
	
	-- Trigger world regeneration outside building zone after walls close
	task.spawn(function()
		task.wait(0.5)  -- Small delay after walls finish
		self:RegenerateWorldOutsideBuildingZone()
	end)
end

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║               WORLD REGENERATION (OUTSIDE BUILDING ZONE)                    ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

-- Regenerate everything outside the building zone
-- Called after walls cascade down (close in)
-- Preserves: Building zone, ship structure, console, spawn locations
-- Regenerates: Terrain, trees, formations, other zones, audio logs, photo targets, lighting/atmosphere
-- OPTIMIZED: Uses parallel processing and reduced yields for better performance
function ConsoleService:RegenerateWorldOutsideBuildingZone()
	print("[ConsoleService] ========== REGENERATING WORLD (OPTIMIZED) ==========")
	local startTime = tick()
	
	-- Get the building zone cube (to know what to preserve)
	local buildingZone = self._reservedZoneService and self._reservedZoneService:GetZone("Building")
	if not buildingZone or not buildingZone.zoneCube then
		warn("[ConsoleService] Cannot regenerate: Building zone not found")
		return false
	end
	
	local buildingZoneCube = buildingZone.zoneCube
	
	-- Get all required services (cache references)
	local CubeTerrainService = nil
	local TreeService = nil
	local FormationService = nil
	local ParticleService = nil
	local WorldInitService = nil
	local WeatherService = nil
	
	pcall(function() CubeTerrainService = Knit.GetService("CubeTerrainService") end)
	pcall(function() TreeService = Knit.GetService("TreeService") end)
	pcall(function() FormationService = Knit.GetService("FormationService") end)
	pcall(function() ParticleService = Knit.GetService("ParticleService") end)
	pcall(function() WorldInitService = Knit.GetService("WorldInitService") end)
	pcall(function() WeatherService = Knit.GetService("WeatherService") end)
	
	-- === PHASE 1: PARALLEL CLEAR (trees, formations, particles, zones - NOT terrain) ===
	print("[ConsoleService] Phase 1: Clearing vegetation & zones (parallel)...")
	local clearPhaseStart = tick()
	
	-- Run all clears in parallel using task.spawn (terrain is reshuffled, not cleared)
	local clearComplete = {trees = false, formations = false, particles = false, zones = false}
	
	task.spawn(function()
		if TreeService and TreeService.ClearTrees then
			TreeService:ClearTrees()
		end
		clearComplete.trees = true
	end)
	
	task.spawn(function()
		if FormationService and FormationService.ClearFormations then
			FormationService:ClearFormations()
		end
		clearComplete.formations = true
	end)
	
	task.spawn(function()
		if ParticleService and ParticleService.ClearParticles then
			ParticleService:ClearParticles()
		end
		clearComplete.particles = true
	end)
	
	task.spawn(function()
		if self._reservedZoneService then
			local zonesToClear = {"AudioLog", "PhotoTarget", "Radiation", "HumanEnemy"}
			for _, zoneType in ipairs(zonesToClear) do
				if self._reservedZoneService:GetZone(zoneType) then
					self._reservedZoneService:ClearZone(zoneType)
				end
			end
		end
		clearComplete.zones = true
	end)
	
	-- Wait for all clears to complete (with timeout)
	local clearTimeout = tick() + 5
	while not (clearComplete.trees and clearComplete.formations and clearComplete.particles and clearComplete.zones) do
		if tick() > clearTimeout then
			warn("[ConsoleService] Clear phase timed out!")
			break
		end
		task.wait()
	end
	
	print(string.format("[ConsoleService] Clear phase: %.2fs", tick() - clearPhaseStart))
	
	-- === PHASE 2: RESHUFFLE terrain (OPTIMIZED - just update heights, no recreate) ===
	print("[ConsoleService] Phase 2: Reshuffling terrain heights...")
	local terrainPhaseStart = tick()
	
	if CubeTerrainService and CubeTerrainService.ReshuffleTerrainOutsideZone and self._gridService then
		local gridData = self._gridService:GetGridData()
		if gridData then
			-- Set new random seed for different terrain
			local newSeed = math.random(1, 999999)
			CubeTerrainService:SetConfig("NoiseSeed", newSeed)
			
			-- OPTIMIZED: Just reshuffle existing cube heights (no destroy/create)
			CubeTerrainService:ReshuffleTerrainOutsideZone(buildingZoneCube, gridData.topY)
		end
	end
	
	print(string.format("[ConsoleService] Terrain phase: %.2fs", tick() - terrainPhaseStart))
	
	-- === PHASE 3: PARALLEL REGENERATION (trees, formations, particles) ===
	print("[ConsoleService] Phase 3: Regenerating vegetation & particles (parallel)...")
	local regenPhaseStart = tick()
	
	local regenComplete = {trees = false, formations = false, particles = false}
	local baseplateInfo = WorldInitService and WorldInitService:GetBaseplateInfo()
	
	-- Trees and formations in parallel
	task.spawn(function()
		if baseplateInfo and TreeService and TreeService.GenerateTreesWithBaseplates then
			TreeService:GenerateTreesWithBaseplates(baseplateInfo)
		end
		regenComplete.trees = true
	end)
	
	task.spawn(function()
		if baseplateInfo and FormationService and FormationService.GenerateFormationsWithBaseplates then
			FormationService:GenerateFormationsWithBaseplates(baseplateInfo)
		end
		regenComplete.formations = true
	end)
	
	task.spawn(function()
		if ParticleService and ParticleService.RegenerateParticles then
			ParticleService:RegenerateParticles()
		end
		regenComplete.particles = true
	end)
	
	-- Wait for all regeneration to complete (with timeout)
	local regenTimeout = tick() + 15
	while not (regenComplete.trees and regenComplete.formations and regenComplete.particles) do
		if tick() > regenTimeout then
			warn("[ConsoleService] Regeneration phase timed out!")
			break
		end
		task.wait()
	end
	
	print(string.format("[ConsoleService] Vegetation phase: %.2fs", tick() - regenPhaseStart))
	
	-- === PHASE 4: Apply new lighting (quick operation) ===
	print("[ConsoleService] Phase 4: Applying new atmosphere...")
	
	if WeatherService and WeatherService.RandomizeLighting then
		local profile = WeatherService:RandomizeLighting(2)  -- 2 second transition (faster)
		print(string.format("[ConsoleService] Atmosphere: %s (Rain: %s)", 
			profile.Name or "Unknown", tostring(profile.RainEnabled)))
	end
	
	local elapsed = tick() - startTime
	print(string.format("[ConsoleService] ========== REGENERATION COMPLETE (%.2fs) ==========", elapsed))
	
	return true
end

-- Animate walls cascading up (retracting) - bottom segments first
function ConsoleService:CascadeWallsUp()
	if self._animating or not self._wallsDeployed then
		return
	end
	
	self._animating = true
	print("[ConsoleService] Cascading walls UP (retracting)...")
	
	local tweenInfo = TweenInfo.new(
		CONFIG.CascadeAnimDuration,
		Enum.EasingStyle.Quad,
		Enum.EasingDirection.In
	)
	
	-- Animate from bottom to top (reverse order)
	local maxSegmentIndex = CONFIG.WallSegmentCount
	
	for segIdx = maxSegmentIndex, 1, -1 do
		-- Animate all walls' segment at this level simultaneously
		for _, seg in ipairs(self._wallSegments) do
			if seg.segmentIndex == segIdx then
				local tween = TweenService:Create(seg.part, tweenInfo, {CFrame = seg.hiddenCFrame})
				tween:Play()
				seg.part.CanCollide = false
			end
		end
		
		-- Wait before next row of segments
		if segIdx > 1 then
			task.wait(CONFIG.CascadeDelayPerSegment)
		end
	end
	
	-- Wait for last animation to complete
	task.wait(CONFIG.CascadeAnimDuration)
	
	self._wallsDeployed = false
	self._animating = false
	print("[ConsoleService] Walls retracted")
end

-- Toggle walls (cascade down if up, cascade up if down)
function ConsoleService:ToggleWalls()
	if self._animating then
		return
	end
	
	if self._wallsDeployed then
		self:CascadeWallsUp()
	else
		self:CascadeWallsDown()
	end
end

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         BUTTON INTERACTIONS                                 ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

-- Called when button is pressed
function ConsoleService:OnButtonPressed(player)
	if self._buttonCooldown then
		return
	end
	
	self._buttonCooldown = true
	
	print(string.format("[ConsoleService] Button pressed by player: %s", player.Name))
	
	-- Animate button press
	if self._button then
		local originalCFrame = self._button.CFrame
		local pressedCFrame = originalCFrame * CFrame.new(-0.1, 0, 0)  -- Push in slightly
		
		-- Press animation
		local pressInfo = TweenInfo.new(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		local pressTween = TweenService:Create(self._button, pressInfo, {CFrame = pressedCFrame})
		pressTween:Play()
		pressTween.Completed:Wait()
		
		-- Flash effect
		local originalColor = self._button.Color
		self._button.Color = Color3.fromRGB(255, 255, 255)
		task.wait(0.05)
		self._button.Color = originalColor
		
		-- Release animation
		local releaseInfo = TweenInfo.new(0.15, Enum.EasingStyle.Bounce, Enum.EasingDirection.Out)
		local releaseTween = TweenService:Create(self._button, releaseInfo, {CFrame = originalCFrame})
		releaseTween:Play()
	end
	
	-- Toggle wall cascade animation
	task.spawn(function()
		self:ToggleWalls()
	end)
	
	-- Fire signal to client
	self.Client.ButtonPressed:FireAll(player)
	
	-- Cooldown (longer to account for wall animation)
	local totalAnimTime = CONFIG.CascadeDelayPerSegment * CONFIG.WallSegmentCount + CONFIG.CascadeAnimDuration
	task.wait(math.max(CONFIG.ButtonCooldownSeconds, totalAnimTime + 0.5))
	self._buttonCooldown = false
end

-- Hover enter effect
function ConsoleService:OnButtonHoverEnter()
	if self._button then
		local glowInfo = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		local light = self._button:FindFirstChild("ButtonLight")
		if light then
			TweenService:Create(light, glowInfo, {Brightness = 4, Range = 12}):Play()
		end
	end
end

-- Hover leave effect
function ConsoleService:OnButtonHoverLeave()
	if self._button then
		local glowInfo = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		local light = self._button:FindFirstChild("ButtonLight")
		if light then
			TweenService:Create(light, glowInfo, {Brightness = 2, Range = 8}):Play()
		end
	end
end

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                     WORLDINITSERVICE INTEGRATION                            ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

-- Get the center of the Building zone (on the flattened terrain surface)
-- Returns: position, zoneSizeX, zoneSizeZ
function ConsoleService:GetBuildingZoneCenter()
	if not self._reservedZoneService then
		warn("[ConsoleService] ReservedZoneService not available")
		return nil, 0, 0
	end
	
	local buildingZone = self._reservedZoneService:GetZone("Building")
	if not buildingZone or not buildingZone.zoneCube then
		warn("[ConsoleService] Building zone not found")
		return nil, 0, 0
	end
	
	local zoneCube = buildingZone.zoneCube
	local centerX = zoneCube.Position.X
	local centerZ = zoneCube.Position.Z
	local zoneSizeX = zoneCube.Size.X
	local zoneSizeZ = zoneCube.Size.Z
	
	-- Get the flattened terrain surface height from CubeTerrainService
	local surfaceY = nil
	local CubeTerrainService = nil
	pcall(function()
		CubeTerrainService = Knit.GetService("CubeTerrainService")
	end)
	
	if CubeTerrainService then
		-- GetSurfaceHeightAt returns the TOP of the terrain cube at that position
		surfaceY = CubeTerrainService:GetSurfaceHeightAt(centerX, centerZ)
		print(string.format("[ConsoleService] Got surface height from CubeTerrainService: %.1f", surfaceY))
	end
	
	-- Fallback: calculate from grid data if CubeTerrainService didn't return valid height
	if not surfaceY or surfaceY <= 0 then
		if self._gridService then
			local gridData = self._gridService:GetGridData()
			if gridData then
				-- Flattened terrain surface = topY + CubeThickness (4 studs)
				surfaceY = gridData.topY + 4
				print(string.format("[ConsoleService] Using fallback surface height: %.1f", surfaceY))
			end
		end
	end
	
	-- Final fallback
	if not surfaceY then
		surfaceY = 4
	end
	
	return Vector3.new(centerX, surfaceY, centerZ), zoneSizeX, zoneSizeZ
end

-- Initialize console (called after zones are created)
function ConsoleService:InitializeConsole()
	if self._isInitialized then
		return true
	end
	
	print("[ConsoleService] Initializing console and transport ship...")
	
	local centerPosition, zoneSizeX, zoneSizeZ = self:GetBuildingZoneCenter()
	if not centerPosition then
		warn("[ConsoleService] Could not get Building zone center, using fallback position")
		centerPosition = Vector3.new(0, 0, 0)
		zoneSizeX = 16
		zoneSizeZ = 16
	end
	
	print(string.format("[ConsoleService] Building zone center: (%.1f, %.1f, %.1f), size: %.1f x %.1f", 
		centerPosition.X, centerPosition.Y, centerPosition.Z, zoneSizeX, zoneSizeZ))
	
	-- Create the transport ship structure first (walls, ceiling)
	assembleShipStructure(self, centerPosition, zoneSizeX, zoneSizeZ)
	
	-- Assemble the console in the center
	assembleConsole(self, centerPosition)
	
	-- Create spawn locations around the console (inside the ship)
	createSpawnLocations(self, centerPosition)
	
	self._isInitialized = true
	print("[ConsoleService] Transport ship, console, and spawn locations created successfully")
	
	return true
end

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                           KNIT LIFECYCLE                                    ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

function ConsoleService:KnitInit()
	print("[ConsoleService] Initializing...")
	
	-- Get service references
	pcall(function()
		self._reservedZoneService = Knit.GetService("ReservedZoneService")
	end)
	
	pcall(function()
		self._gridService = Knit.GetService("GridService")
	end)
end

function ConsoleService:KnitStart()
	print("[ConsoleService] Starting...")
	
	-- Wait for world initialization to complete, then create console
	task.spawn(function()
		-- Wait for WorldInitService to finish
		local WorldInitService = nil
		pcall(function()
			WorldInitService = Knit.GetService("WorldInitService")
		end)
		
		if WorldInitService then
			-- Wait until world init is complete
			while not WorldInitService:IsInitComplete() do
				task.wait(0.5)
			end
			
			-- Additional small delay to ensure Building zone is fully created
			task.wait(0.5)
		else
			-- Fallback: just wait a few seconds
			task.wait(5)
		end
		
		-- Now create the console
		self:InitializeConsole()
	end)
end

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                            PUBLIC API                                       ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

function ConsoleService:GetConsole()
	return self._consoleModel
end

function ConsoleService:GetShip()
	return self._shipModel
end

function ConsoleService:GetButton()
	return self._button
end

function ConsoleService:GetSpawnLocations()
	return self._spawnLocations
end

function ConsoleService:IsInitialized()
	return self._isInitialized
end

function ConsoleService:AreWallsDeployed()
	return self._wallsDeployed
end

function ConsoleService:IsAnimating()
	return self._animating
end

-- Manually trigger button press (for testing/scripting)
function ConsoleService:PressButton()
	if self._button and not self._buttonCooldown then
		self:OnButtonPressed({Name = "Server", UserId = 0})
	end
end

-- Manually deploy walls (cascade down)
function ConsoleService:DeployWalls()
	if not self._wallsDeployed and not self._animating then
		self:CascadeWallsDown()
	end
end

-- Manually retract walls (cascade up)
function ConsoleService:RetractWalls()
	if self._wallsDeployed and not self._animating then
		self:CascadeWallsUp()
	end
end

-- Manually trigger world regeneration outside building zone
-- Useful for testing or scripting purposes
function ConsoleService:RegenerateOutsideWorld()
	return self:RegenerateWorldOutsideBuildingZone()
end

-- Remove console, ship, and spawn locations
function ConsoleService:RemoveConsole()
	-- Remove ship structure (includes wall segments)
	if self._shipModel then
		self._shipModel:Destroy()
		self._shipModel = nil
		print("[ConsoleService] Transport ship removed")
	end
	
	-- Clear wall segments reference
	self._wallSegments = {}
	self._wallsDeployed = false
	self._animating = false
	
	-- Remove console
	if self._consoleModel then
		self._consoleModel:Destroy()
		self._consoleModel = nil
		self._button = nil
		print("[ConsoleService] Console removed")
	end
	
	-- Remove spawn locations
	for _, spawn in ipairs(self._spawnLocations) do
		if spawn then
			spawn:Destroy()
		end
	end
	self._spawnLocations = {}
	
	self._isInitialized = false
	print("[ConsoleService] All structures removed")
end

-- Recreate console
function ConsoleService:RecreateConsole()
	self:RemoveConsole()
	task.wait(0.1)
	self._isInitialized = false
	self:InitializeConsole()
end

return ConsoleService

