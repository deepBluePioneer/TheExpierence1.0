local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local TweenService = game:GetService("TweenService")
local CollectionService = game:GetService("CollectionService")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local Knit = require(Packages.Knit)

local AudioLogService = Knit.CreateService {
	Name = "AudioLogService",
	Client = {
		AudioLogTriggered = Knit.CreateSignal(),  -- Fires when player triggers an audio log
	},
	audioLogs = {},
	onTriggeredCallback = nil,
	isAudioLogPlaying = false,  -- Track if any audio log is currently playing
}

-- === COLLECTION SERVICE TAG ===
local AUDIO_LOG_TAG = "audioLog"

-- === CONFIG ===
local AUDIOLOG_CONFIG = {
	-- Spawning
	LogCount = 5,
	SpawnRadius = 80,
	
	-- === PROCEDURAL VARIATION RANGES ===
	
	-- Body dimensions
	BodyWidthMin = 3.0,
	BodyWidthMax = 4.0,
	BodyHeightMin = 0.7,
	BodyHeightMax = 1.0,
	BodyDepthMin = 2.0,
	BodyDepthMax = 2.5,
	
	-- Color palettes for body
	BodyColors = {
		Color3.fromRGB(60, 55, 50),    -- Dark grey/brown
		Color3.fromRGB(50, 50, 55),    -- Dark blue-grey
		Color3.fromRGB(70, 60, 50),    -- Brown
		Color3.fromRGB(45, 45, 50),    -- Charcoal
		Color3.fromRGB(80, 70, 60),    -- Tan/beige dark
	},
	
	AccentColors = {
		Color3.fromRGB(180, 170, 150), -- Beige/cream
		Color3.fromRGB(200, 190, 170), -- Light cream
		Color3.fromRGB(160, 160, 165), -- Silver
		Color3.fromRGB(170, 160, 140), -- Tan
		Color3.fromRGB(150, 145, 140), -- Grey
	},
	
	-- Button colors
	RecordButtonColor = Color3.fromRGB(200, 50, 50),
	ButtonColor = Color3.fromRGB(160, 160, 165),
	
	-- Tape colors
	TapeColors = {
		Color3.fromRGB(50, 35, 25),    -- Brown tape
		Color3.fromRGB(30, 30, 35),    -- Dark grey tape
		Color3.fromRGB(60, 40, 30),    -- Reddish brown
		Color3.fromRGB(40, 40, 45),    -- Dark blue-grey
	},
	
	-- Recording light colors
	LightColors = {
		Color3.fromRGB(255, 50, 50),   -- Red
		Color3.fromRGB(50, 255, 50),   -- Green
		Color3.fromRGB(255, 200, 50),  -- Yellow/amber
	},
	
	-- Materials
	BodyMaterial = Enum.Material.SmoothPlastic,
	MetalMaterial = Enum.Material.Metal,
	
	-- Interaction
	InteractionEnabled = true,
	GlowWhenNearby = true,
	GlowRange = 15,
	
	-- Proximity Prompt
	PromptEnabled = true,
	PromptActionText = "Play",
	PromptObjectText = "Audio Log",
	PromptKeyboardKey = Enum.KeyCode.E,
	PromptGamepadKey = Enum.KeyCode.ButtonX,
	PromptHoldDuration = 0,
	PromptMaxDistance = 8,
	PromptRequiresLineOfSight = false,
	
	-- Animation
	LightBlinkEnabled = true,
	LightBlinkSpeed = 1.5,
	ReelSpinEnabled = false,  -- Disabled: conflicts with physics (welded parts)
	ReelSpinSpeed = 0.5,
}

local FOLDER_NAME = "AudioLogs"

-- === HELPERS ===

local function getAudioLogFolder()
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

local function randomChoice(tbl)
	return tbl[math.random(1, #tbl)]
end

local function varyColor(baseColor, variation)
	local r = math.clamp(baseColor.R * 255 + (math.random() - 0.5) * variation * 2, 0, 255)
	local g = math.clamp(baseColor.G * 255 + (math.random() - 0.5) * variation * 2, 0, 255)
	local b = math.clamp(baseColor.B * 255 + (math.random() - 0.5) * variation * 2, 0, 255)
	return Color3.fromRGB(r, g, b)
end

local function getBaseplateInfo()
	-- First try to get info from WorldInitService (preferred)
	local WorldInitService = nil
	pcall(function()
		WorldInitService = Knit.GetService("WorldInitService")
	end)
	
	if WorldInitService then
		local info = WorldInitService:GetBaseplateInfo()
		if info then
			return {
				position = info.position,
				size = info.size,
				topY = info.topY,
			}
		end
	end
	
	-- Fallback: Try GridService for grid dimensions
	local GridService = nil
	pcall(function()
		GridService = Knit.GetService("GridService")
	end)
	
	if GridService then
		local gridData = GridService:GetGridData()
		if gridData and gridData.cellSize > 0 then
			local totalWidth = gridData.width * gridData.cellSize
			local totalDepth = gridData.depth * gridData.cellSize
			return {
				position = Vector3.new(gridData.centerX, gridData.topY, gridData.centerZ),
				size = Vector3.new(totalWidth, 1, totalDepth),
				topY = gridData.topY,
			}
		end
	end
	
	-- Legacy fallback: look for physical Baseplate
	local baseplate = Workspace:FindFirstChild("Baseplate")
	if baseplate and baseplate:IsA("BasePart") then
		return {
			position = baseplate.Position,
			size = baseplate.Size,
			topY = baseplate.Position.Y + baseplate.Size.Y / 2,
		}
	end
	
	-- Default fallback (3x3 grid of 128x128 baseplates)
	----("[AudioLogService] Using default baseplate dimensions (384x384)")
	return {
		position = Vector3.new(0, 0, 0),
		size = Vector3.new(384, 1, 384),
		topY = 0,
	}
end

-- Fixed stats for all audio logs (identical appearance)
local function generateAudioLogStats()
	local config = AUDIOLOG_CONFIG
	
	return {
		-- Fixed dimensions
		BodyWidth = 3.5,
		BodyHeight = 0.8,
		BodyDepth = 2.2,
		
		-- Fixed colors
		BodyColor = Color3.fromRGB(60, 55, 50),       -- Dark grey/brown
		AccentColor = Color3.fromRGB(180, 170, 150),  -- Beige/cream
		TapeColor = Color3.fromRGB(50, 35, 25),       -- Brown tape
		LightColor = Color3.fromRGB(255, 50, 50),     -- Red light
		
		-- Fixed features (all enabled)
		HasHandle = true,
		HasSpeaker = true,
		HasVolumeKnob = true,
		HasLabel = true,
		ButtonCount = 5,
		
		-- Fixed tape state
		LeftReelTape = 0.8,
		RightReelTape = 0.4,
		
		-- No wear
		WearFactor = 0,
	}
end

-- === PART CREATION ===

local function createPart(name, size, cframe, color, material, parent)
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = cframe
	part.Color = color
	part.Material = material
	part.Anchored = true
	part.CanCollide = true
	part.Parent = parent
	return part
end

local function createCylinder(name, diameter, length, cframe, color, material, parent)
	local cyl = Instance.new("Part")
	cyl.Name = name
	cyl.Shape = Enum.PartType.Cylinder
	cyl.Size = Vector3.new(length, diameter, diameter)
	cyl.CFrame = cframe
	cyl.Color = color
	cyl.Material = material
	cyl.Anchored = true
	cyl.CanCollide = false
	cyl.Parent = parent
	return cyl
end

-- === AUDIO LOG ASSEMBLY ===

local function createAudioLog(position, folder, stats)
	local config = AUDIOLOG_CONFIG
	
	stats = stats or generateAudioLogStats()
	
	local logModel = Instance.new("Model")
	logModel.Name = "AudioLog_" .. math.random(1000, 9999)
	logModel.Parent = folder
	
	local allParts = {}
	local bodyColor = varyColor(stats.BodyColor, 10 + stats.WearFactor * 20)
	local accentColor = varyColor(stats.AccentColor, 10)
	local silverColor = Color3.fromRGB(160, 160, 165)
	local windowColor = Color3.fromRGB(80, 90, 100)
	
	local bodyWidth = stats.BodyWidth
	local bodyHeight = stats.BodyHeight
	local bodyDepth = stats.BodyDepth
	
	-- === MAIN BODY ===
	local body = createPart(
		"Body",
		Vector3.new(bodyWidth, bodyHeight, bodyDepth),
		CFrame.new(position),
		bodyColor,
		config.BodyMaterial,
		logModel
	)
	table.insert(allParts, body)
	
	-- Body top accent
	local topAccent = createPart(
		"BodyTop",
		Vector3.new(bodyWidth - 0.1, 0.05, bodyDepth - 0.1),
		CFrame.new(position + Vector3.new(0, bodyHeight/2 + 0.025, 0)),
		accentColor,
		config.BodyMaterial,
		logModel
	)
	table.insert(allParts, topAccent)
	
	-- === CASSETTE WINDOW ===
	local windowWidth = bodyWidth * 0.6
	local windowHeight = 0.15
	local windowDepth = bodyDepth * 0.6
	local windowPos = position + Vector3.new(0, bodyHeight/2 + 0.02, -bodyDepth * 0.12)
	
	-- Window frame
	local frame = createPart(
		"WindowFrame",
		Vector3.new(windowWidth + 0.15, windowHeight + 0.1, windowDepth + 0.15),
		CFrame.new(windowPos),
		silverColor,
		config.MetalMaterial,
		logModel
	)
	table.insert(allParts, frame)
	
	-- Window (transparent)
	local window = createPart(
		"Window",
		Vector3.new(windowWidth, windowHeight, windowDepth),
		CFrame.new(windowPos + Vector3.new(0, 0.02, 0)),
		windowColor,
		Enum.Material.Glass,
		logModel
	)
	window.Transparency = 0.5
	table.insert(allParts, window)
	
	-- === TAPE REELS ===
	local reelRadius = math.min(windowWidth, windowDepth) * 0.18
	local reelSpacing = windowWidth * 0.25
	local reels = {}
	
	for i, side in ipairs({-1, 1}) do
		local reelX = side * reelSpacing
		local reelPos = windowPos + Vector3.new(reelX, -0.05, 0)
		local tapeAmount = i == 1 and stats.LeftReelTape or stats.RightReelTape
		
		-- Reel hub
		local hub = createCylinder(
			"ReelHub_" .. side,
			reelRadius * 2, 0.12,
			CFrame.new(reelPos) * CFrame.Angles(0, 0, math.rad(90)),
			Color3.fromRGB(30, 25, 20),
			config.BodyMaterial,
			logModel
		)
		table.insert(allParts, hub)
		table.insert(reels, hub)
		
		-- Reel center (silver)
		local center = createCylinder(
			"ReelCenter_" .. side,
			reelRadius * 0.6, 0.14,
			CFrame.new(reelPos) * CFrame.Angles(0, 0, math.rad(90)),
			silverColor,
			config.MetalMaterial,
			logModel
		)
		table.insert(allParts, center)
		
		-- Tape wound on reel
		local tape = createCylinder(
			"Tape_" .. side,
			reelRadius * 2 * tapeAmount, 0.1,
			CFrame.new(reelPos) * CFrame.Angles(0, 0, math.rad(90)),
			stats.TapeColor,
			config.BodyMaterial,
			logModel
		)
		table.insert(allParts, tape)
	end
	
	-- Tape strip between reels
	local tapeStrip = createPart(
		"TapeStrip",
		Vector3.new(reelSpacing * 2 - reelRadius, 0.02, 0.08),
		CFrame.new(windowPos + Vector3.new(0, -0.05, reelRadius * 0.8)),
		stats.TapeColor,
		config.BodyMaterial,
		logModel
	)
	table.insert(allParts, tapeStrip)
	
	-- === CONTROL BUTTONS ===
	local buttonY = position.Y + bodyHeight/2 + 0.05
	local buttonZ = position.Z + bodyDepth * 0.32
	local buttonSpacing = bodyWidth / (stats.ButtonCount + 2)
	local buttonSize = bodyWidth * 0.06
	
	for i = 1, stats.ButtonCount do
		local btnX = position.X + (i - (stats.ButtonCount + 1) / 2) * buttonSpacing
		local isRecord = i == math.ceil(stats.ButtonCount / 2)
		local btnColor = isRecord and config.RecordButtonColor or config.ButtonColor
		
		local btn = createPart(
			"Button_" .. i,
			Vector3.new(buttonSize, 0.12, buttonSize),
			CFrame.new(btnX, buttonY, buttonZ),
			btnColor,
			config.BodyMaterial,
			logModel
		)
		table.insert(allParts, btn)
	end
	
	-- === SPEAKER GRILLE ===
	if stats.HasSpeaker then
		local grilleWidth = bodyWidth * 0.25
		local grilleHeight = bodyDepth * 0.25
		local grillePos = position + Vector3.new(bodyWidth/2 - grilleWidth/2 - 0.15, 0, bodyDepth * 0.15)
		
		-- Grille backing
		local grilleBacking = createPart(
			"GrilleBacking",
			Vector3.new(grilleWidth, bodyHeight * 0.7, grilleHeight),
			CFrame.new(grillePos),
			Color3.fromRGB(40, 35, 30),
			Enum.Material.Fabric,
			logModel
		)
		table.insert(allParts, grilleBacking)
		
		-- Grille lines
		for i = 1, 4 do
			local slotY = grillePos.Y + (i - 2.5) * (bodyHeight * 0.15)
			local slot = createPart(
				"GrilleSlot_" .. i,
				Vector3.new(grilleWidth - 0.08, 0.025, 0.02),
				CFrame.new(grillePos.X, slotY, grillePos.Z + grilleHeight/2),
				silverColor,
				config.MetalMaterial,
				logModel
			)
			table.insert(allParts, slot)
		end
	end
	
	-- === VOLUME KNOB ===
	if stats.HasVolumeKnob then
		local knobPos = position + Vector3.new(-bodyWidth/2 + bodyWidth * 0.12, bodyHeight/2 + 0.1, bodyDepth * 0.2)
		
		local knob = createCylinder(
			"VolumeKnob",
			bodyWidth * 0.08, 0.15,
			CFrame.new(knobPos) * CFrame.Angles(math.rad(90), 0, 0),
			silverColor,
			config.MetalMaterial,
			logModel
		)
		table.insert(allParts, knob)
		
		-- Knob indicator
		local indicator = createPart(
			"KnobIndicator",
			Vector3.new(0.02, 0.16, bodyWidth * 0.035),
			CFrame.new(knobPos + Vector3.new(0, 0.01, bodyWidth * 0.02)),
			Color3.fromRGB(20, 20, 20),
			config.BodyMaterial,
			logModel
		)
		table.insert(allParts, indicator)
	end
	
	-- === CARRY HANDLE ===
	if stats.HasHandle then
		local handleWidth = bodyWidth * 0.35
		local handleHeight = bodyHeight * 0.5
		local handleThickness = 0.1
		
		for _, side in ipairs({-1, 1}) do
			local post = createPart(
				"HandlePost_" .. side,
				Vector3.new(handleThickness, handleHeight, handleThickness),
				CFrame.new(position + Vector3.new(side * handleWidth/2, bodyHeight/2 + handleHeight/2, -bodyDepth/2 + 0.15)),
				bodyColor,
				config.BodyMaterial,
				logModel
			)
			table.insert(allParts, post)
		end
		
		local handleBar = createPart(
			"HandleBar",
			Vector3.new(handleWidth, handleThickness, handleThickness),
			CFrame.new(position + Vector3.new(0, bodyHeight/2 + handleHeight, -bodyDepth/2 + 0.15)),
			bodyColor,
			config.BodyMaterial,
			logModel
		)
		table.insert(allParts, handleBar)
	end
	
	-- === LABEL/STICKER ===
	if stats.HasLabel then
		local label = createPart(
			"Label",
			Vector3.new(bodyWidth * 0.35, 0.02, bodyDepth * 0.2),
			CFrame.new(position + Vector3.new(-bodyWidth * 0.15, bodyHeight/2 + 0.01, -bodyDepth * 0.32)),
			Color3.fromRGB(240, 235, 220),
			config.BodyMaterial,
			logModel
		)
		table.insert(allParts, label)
	end
	
	-- === RECORDING INDICATOR LIGHT ===
	local indicatorLight = createPart(
		"RecordingLight",
		Vector3.new(0.1, 0.08, 0.1),
		CFrame.new(position + Vector3.new(0, bodyHeight/2 + 0.04, bodyDepth * 0.38)),
		stats.LightColor,
		Enum.Material.Neon,
		logModel
	)
	table.insert(allParts, indicatorLight)
	
	-- Point light
	local light = Instance.new("PointLight")
	light.Name = "IndicatorGlow"
	light.Color = stats.LightColor
	light.Brightness = 0.3
	light.Range = 2
	light.Parent = indicatorLight
	
	logModel.PrimaryPart = body
	
	-- === ADD COLLECTION SERVICE TAG ===
	CollectionService:AddTag(logModel, AUDIO_LOG_TAG)
	
	-- === ADD PROXIMITY PROMPT ===
	local proximityPrompt = nil
	if config.PromptEnabled then
		proximityPrompt = Instance.new("ProximityPrompt")
		proximityPrompt.Name = "AudioLogPrompt"
		proximityPrompt.ActionText = config.PromptActionText
		proximityPrompt.ObjectText = config.PromptObjectText
		proximityPrompt.KeyboardKeyCode = config.PromptKeyboardKey
		proximityPrompt.GamepadKeyCode = config.PromptGamepadKey
		proximityPrompt.HoldDuration = config.PromptHoldDuration
		proximityPrompt.MaxActivationDistance = config.PromptMaxDistance
		proximityPrompt.RequiresLineOfSight = config.PromptRequiresLineOfSight
		proximityPrompt.Parent = body
	end
	
	-- === PHYSICS SETUP - WELD ALL PARTS TO BODY ===
	-- Weld all parts to the body so they fall as a unit
	for _, part in ipairs(allParts) do
		if part ~= body and part:IsA("BasePart") then
			local weld = Instance.new("WeldConstraint")
			weld.Name = "AudioLogWeld"
			weld.Part0 = body
			weld.Part1 = part
			weld.Parent = body
			
			-- Unanchor the welded part
			part.Anchored = false
			part.CanCollide = false  -- Only body needs collision
		end
	end
	
	-- Also weld the reels
	for _, reel in ipairs(reels) do
		if reel:IsA("BasePart") then
			local weld = Instance.new("WeldConstraint")
			weld.Name = "ReelWeld"
			weld.Part0 = body
			weld.Part1 = reel
			weld.Parent = body
			reel.Anchored = false
			reel.CanCollide = false
		end
	end
	
	-- Unanchor the body so it falls with gravity
	body.Anchored = false
	body.CanCollide = true
	
	-- Set mass/density for realistic falling
	if body:IsA("BasePart") then
		body.CustomPhysicalProperties = PhysicalProperties.new(
			2,    -- Density (heavier than default)
			0.3,  -- Friction
			0.1,  -- Elasticity (low bounce)
			1,    -- FrictionWeight
			1     -- ElasticityWeight
		)
	end
	
	return {
		model = logModel,
		parts = allParts,
		body = body,
		reels = reels,
		light = indicatorLight,
		pointLight = light,
		proximityPrompt = proximityPrompt,
		position = position,
		stats = stats,
	}
end

-- === ANIMATION ===

local function animateAudioLogs(self)
	local config = AUDIOLOG_CONFIG
	local startTime = tick()
	
	game:GetService("RunService").Heartbeat:Connect(function()
		local elapsed = tick() - startTime
		
		for _, audioLog in ipairs(self.audioLogs) do
			-- Blink recording light
			if config.LightBlinkEnabled and audioLog.pointLight then
				local blink = (math.sin(elapsed * config.LightBlinkSpeed * math.pi * 2) + 1) / 2
				audioLog.pointLight.Brightness = 0.1 + blink * 0.4
			end
			
			-- Spin reels (subtle)
			if config.ReelSpinEnabled and audioLog.reels then
				for _, reel in ipairs(audioLog.reels) do
					if reel and reel.Parent then
						local currentCF = reel.CFrame
						reel.CFrame = currentCF * CFrame.Angles(config.ReelSpinSpeed * 0.016, 0, 0)
					end
				end
			end
		end
	end)
end

-- === GENERATION ===

-- === TERRAIN HEIGHT LOOKUP (via CubeTerrainService - no raycasting) ===

-- Cache for CubeTerrainService reference
local _cubeTerrainService = nil

local function getCubeTerrainService()
	if not _cubeTerrainService then
		pcall(function()
			_cubeTerrainService = Knit.GetService("CubeTerrainService")
		end)
	end
	return _cubeTerrainService
end

-- Get terrain surface height at position (uses CubeTerrainService direct lookup)
local function getGroundHeight(x, z, fallbackY)
	local terrainService = getCubeTerrainService()
	if terrainService then
		local height = terrainService:GetSurfaceHeightAt(x, z)
		if height and height > 0 then
			return height
		end
	end
	return fallbackY or 0
end

local function generateAudioLogs(self)
	local startTime = tick()
	local config = AUDIOLOG_CONFIG
	
	-- Get LoadingService
	local LoadingService = nil
	pcall(function()
		LoadingService = Knit.GetService("LoadingService")
	end)
	
	if LoadingService then
		LoadingService:UpdateStatus("AudioLogService", "Placing audio logs...", 0)
	end
	
	local folder = getAudioLogFolder()
	folder:ClearAllChildren()
	
	local baseplateInfo = getBaseplateInfo()
	if not baseplateInfo then
		warn("[AudioLogService] No Baseplate found!")
		return
	end
	
	local fallbackY = baseplateInfo.topY
	
	for i = 1, config.LogCount do
		local stats = generateAudioLogStats()
		
		-- Random position within spawn radius
		local angle = math.random() * math.pi * 2
		local distance = math.random() * config.SpawnRadius
		
		local x = baseplateInfo.position.X + math.cos(angle) * distance
		local z = baseplateInfo.position.Z + math.sin(angle) * distance
		
		-- Raycast to find actual ground height (terrain or baseplate)
		local groundY = getGroundHeight(x, z, fallbackY)
		-- Spawn above ground and let physics drop it down
		local y = groundY + stats.BodyHeight / 2 + 3  -- Spawn 3 studs above ground, will fall into place
		
		local position = Vector3.new(x, y, z)
		local audioLog = createAudioLog(position, folder, stats)
		
		-- Assign this audio log a specific entry index (1, 2, 3, etc.)
		audioLog.entryIndex = i
		audioLog.model.Name = "AudioLog_" .. i
		
		-- Random rotation
		local rotation = math.random() * math.pi * 2
		if audioLog.model.PrimaryPart then
			audioLog.model:SetPrimaryPartCFrame(
				audioLog.model.PrimaryPart.CFrame * CFrame.Angles(0, rotation, 0)
			)
		end
		
		table.insert(self.audioLogs, audioLog)
		
		-- Report progress
		if LoadingService then
			LoadingService:ReportProgress("AudioLogService", i, config.LogCount, "Placing audio logs")
		end
		
		--[[print(string.format(
			"[AudioLogService] Audio Log %d (Entry #%d): Position=(%.0f, %.0f, %.0f)",
			i, audioLog.entryIndex, position.X, position.Y, position.Z
		))]]
		
		task.wait(0.1)
	end
	
	local elapsed = tick() - startTime
	--[[print(string.format("[AudioLogService] Generated %d audio logs in %.2fs", config.LogCount, elapsed))]]
	
	-- Mark step complete
	if LoadingService then
		LoadingService:MarkStepComplete("AudioLogService")
	end
	
	-- -- all tagged audio logs
	local taggedLogs = CollectionService:GetTagged(AUDIO_LOG_TAG)
	--[[print(string.format("[AudioLogService] Found %d instances with '%s' tag:", #taggedLogs, AUDIO_LOG_TAG))]]
	for _, taggedInstance in ipairs(taggedLogs) do
		--[[print("  - " .. taggedInstance.Name)]]
	end
	
	-- Connect proximity prompt events
	local connectedCount = 0
	for _, audioLog in ipairs(self.audioLogs) do
		if audioLog.proximityPrompt then
			connectedCount = connectedCount + 1
			--("[AudioLogService] Connecting prompt for:", audioLog.model.Name)
			
			audioLog.proximityPrompt.Triggered:Connect(function(player)
				--("[AudioLogService] Prompt triggered by:", player.Name, "for:", audioLog.model.Name)
				
				-- Don't allow if an audio log is already playing
				if self:IsAudioLogPlaying() then
					--("[AudioLogService] Blocked - audio log already playing")
					return
				end
				self:OnAudioLogTriggered(audioLog, player)
			end)
		else
			warn("[AudioLogService] No proximity prompt for:", audioLog.model and audioLog.model.Name or "unknown")
		end
	end
	--("[AudioLogService] Connected", connectedCount, "proximity prompts")
	
	-- Start animations
	animateAudioLogs(self)
end

-- === KNIT LIFECYCLE ===

function AudioLogService:KnitInit()
	-- Nothing to init
end

function AudioLogService:KnitStart()
	-- Audio logs are now spawned by ReservedZoneService within audio log zones
	-- This service only provides the SpawnAudioLogAt() method and manages audio log state
	-- We do NOT auto-generate audio logs here anymore
	--("[AudioLogService] Started - audio logs will be spawned by ReservedZoneService within zones")
	
	-- Mark step complete for LoadingService so it doesn't wait for us
	local LoadingService = nil
	pcall(function()
		LoadingService = Knit.GetService("LoadingService")
	end)
	
	if LoadingService then
		LoadingService:MarkStepComplete("AudioLogService")
		--("[AudioLogService] Marked step complete")
	end
end

-- === PUBLIC METHODS ===

function AudioLogService:RegenerateAudioLogs()
	self.audioLogs = {}
	generateAudioLogs(self)
end

function AudioLogService:ClearAudioLogs()
	self.audioLogs = {}
	local folder = Workspace:FindFirstChild(FOLDER_NAME)
	if folder then
		folder:ClearAllChildren()
	end
end

function AudioLogService:SetLogCount(count)
	AUDIOLOG_CONFIG.LogCount = math.clamp(count, 1, 20)
end

function AudioLogService:GetLogCount()
	return AUDIOLOG_CONFIG.LogCount
end

function AudioLogService:SpawnAudioLogAt(position)
	local folder = getAudioLogFolder()
	local stats = generateAudioLogStats()
	local audioLog = createAudioLog(position, folder, stats)
	
	-- Connect proximity prompt if it exists
	if audioLog.proximityPrompt then
		audioLog.proximityPrompt.Triggered:Connect(function(player)
			-- Don't allow if an audio log is already playing
			if self:IsAudioLogPlaying() then
				return
			end
			self:OnAudioLogTriggered(audioLog, player)
		end)
	end
	
	table.insert(self.audioLogs, audioLog)
	return audioLog
end

-- === PROXIMITY PROMPT HANDLING ===

-- Called when a player triggers an audio log's proximity prompt
function AudioLogService:OnAudioLogTriggered(audioLog, player)
	local entryIndex = audioLog.entryIndex or 1
	--[[print(string.format("[AudioLogService] %s triggered audio log: %s (Entry #%d)", player.Name, audioLog.model.Name, entryIndex))]]
	
	-- Disable ALL prompts while playing
	self.isAudioLogPlaying = true
	self:DisableAllPrompts()
	--[[print("[AudioLogService] Prompts disabled, isAudioLogPlaying =", self.isAudioLogPlaying)]]
	
	-- Fire custom callback if set
	if self.onTriggeredCallback then
		self.onTriggeredCallback(audioLog, player)
	end
	
	-- Fire client event ONLY to the player who triggered it, with the entry index
	if self.Client and self.Client.AudioLogTriggered then
		--[[print("[AudioLogService] Firing AudioLogTriggered signal to", player.Name, "with entryIndex", entryIndex)]]
		self.Client.AudioLogTriggered:Fire(player, entryIndex)
	else
		warn("[AudioLogService] Cannot fire signal - self.Client or AudioLogTriggered is nil")
	end
end

-- Check if any audio log is currently playing
function AudioLogService:IsAudioLogPlaying()
	return self.isAudioLogPlaying == true
end

-- Client calls this when done viewing
function AudioLogService.Client:NotifyDialogClosed(player)
	self.Server.isAudioLogPlaying = false
	self.Server:EnableAllPrompts()
	--[[print(string.format("[AudioLogService] %s finished viewing audio log - prompts re-enabled", player.Name))]]
end

-- Set a custom callback for when audio logs are triggered
function AudioLogService:SetOnTriggeredCallback(callback)
	self.onTriggeredCallback = callback
end

-- Disable/enable proximity prompt for a specific audio log
function AudioLogService:SetPromptEnabled(audioLog, enabled)
	if audioLog and audioLog.proximityPrompt then
		audioLog.proximityPrompt.Enabled = enabled
	end
end

-- Disable all proximity prompts
function AudioLogService:DisableAllPrompts()
	for _, audioLog in ipairs(self.audioLogs) do
		if audioLog.proximityPrompt then
			audioLog.proximityPrompt.Enabled = false
		end
	end
end

-- Enable all proximity prompts
function AudioLogService:EnableAllPrompts()
	for _, audioLog in ipairs(self.audioLogs) do
		if audioLog.proximityPrompt then
			audioLog.proximityPrompt.Enabled = true
		end
	end
end

function AudioLogService:GetNearestAudioLog(position)
	local nearest = nil
	local nearestDist = math.huge
	
	for _, audioLog in ipairs(self.audioLogs) do
		if audioLog.model and audioLog.model.PrimaryPart then
			local dist = (audioLog.model.PrimaryPart.Position - position).Magnitude
			if dist < nearestDist then
				nearestDist = dist
				nearest = audioLog
			end
		end
	end
	
	return nearest, nearestDist
end

-- === COLLECTION SERVICE METHODS ===

-- Get the tag name
function AudioLogService:GetTag()
	return AUDIO_LOG_TAG
end

-- Get all audio log models by tag
function AudioLogService:GetAllTagged()
	return CollectionService:GetTagged(AUDIO_LOG_TAG)
end

-- Check if an instance is an audio log
function AudioLogService:IsAudioLog(instance)
	return CollectionService:HasTag(instance, AUDIO_LOG_TAG)
end

-- Get the audio log model from any of its parts
function AudioLogService:GetAudioLogFromPart(part)
	if not part then return nil end
	
	-- Check if this is the model itself
	if CollectionService:HasTag(part, AUDIO_LOG_TAG) then
		return part
	end
	
	-- Walk up the hierarchy to find the tagged model
	local current = part.Parent
	while current do
		if CollectionService:HasTag(current, AUDIO_LOG_TAG) then
			return current
		end
		current = current.Parent
	end
	
	return nil
end

-- Listen for when audio logs are added (returns connection)
function AudioLogService:OnAudioLogAdded(callback)
	return CollectionService:GetInstanceAddedSignal(AUDIO_LOG_TAG):Connect(callback)
end

-- Listen for when audio logs are removed (returns connection)
function AudioLogService:OnAudioLogRemoved(callback)
	return CollectionService:GetInstanceRemovedSignal(AUDIO_LOG_TAG):Connect(callback)
end

return AudioLogService

