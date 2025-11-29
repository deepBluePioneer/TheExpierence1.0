local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Lighting = game:GetService("Lighting")
local CollectionService = game:GetService("CollectionService")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local CustomPackages = ReplicatedStorage:WaitForChild("CustomPackages")
local Knit = require(Packages.Knit)
local Fusion = require(CustomPackages:WaitForChild("FusionRoot"):WaitForChild("Fusion"))
local Input = require(Packages.Input)
local Mouse = Input.Mouse
local Keyboard = Input.Keyboard
local Gizmo = require(Packages.imgizmo)

-- Tags for detection
local ENTITY_TAG = "entity"
local GRID_CUBE_TAG = "gridCube"
local PHOTO_TARGET_TAG = "PhotoTarget"

-- Fusion imports
local New = Fusion.New
local Children = Fusion.Children
local Value = Fusion.Value
local Computed = Fusion.Computed
local Spring = Fusion.Spring

local CameraEffectController = Knit.CreateController {
	Name = "CameraEffectController",
}

-- === CONFIG ===
local CAMERA_CONFIG = {
	-- Overall effect
	EffectEnabled = true,
	
	-- Mouse/Cursor
	HideCursor = true,
	LockCursor = true,
	
	-- Camera Controls (mouse look only, movement follows character)
	ControlsEnabled = true,
	MouseSensitivity = 0.3,  -- Mouse look sensitivity
	SmoothingFactor = 0.15,  -- Camera smoothing (0-1, lower = smoother)
	MinZoom = 1.0,           -- Minimum zoom level
	MaxZoom = 4.0,           -- Maximum zoom level
	ZoomSpeed = 0.5,         -- Zoom scroll speed
	
	-- Vignette
	VignetteEnabled = true,
	VignetteIntensity = 0.7,
	
	-- Recording indicator
	RecIndicatorEnabled = true,
	RecBlinkSpeed = 1,  -- Blinks per second
	
	-- Timestamp
	TimestampEnabled = true,
	TimestampFormat = "CAM-01  %m/%d/%Y  %H:%M:%S",
	
	-- Focus brackets
	FocusBracketsEnabled = true,
	BracketSize = 80,
	BracketThickness = 3,
	
	-- Scan lines
	ScanLinesEnabled = true,
	ScanLineOpacity = 0.08,
	ScanLineSpacing = 4,
	
	-- Film grain
	FilmGrainEnabled = true,
	FilmGrainOpacity = 0.05,
	
	-- Battery indicator
	BatteryEnabled = true,
	BatteryLevel = 87,  -- Percentage
	
	-- Audio levels
	AudioLevelsEnabled = true,
	
	-- Memory card
	MemoryCardEnabled = true,
	MemoryUsed = 64,  -- GB
	MemoryTotal = 128, -- GB
	
	-- Aperture/ISO
	CameraSettingsEnabled = true,
	Aperture = "f/2.8",
	ISO = "3200",
	ShutterSpeed = "1/60",
	FocalLength = "24mm",
	
	-- Focus distance
	
	-- Crosshair style
	CrosshairEnabled = true,
	
	-- Film border
	FilmBorderEnabled = true,
	
	-- Zoom indicator
	ZoomEnabled = true,
	ZoomLevel = 1.0,
	
	-- Colors (Normal Mode)
	OverlayColor = Color3.fromRGB(255, 255, 255),
	RecColor = Color3.fromRGB(255, 50, 50),
	WarningColor = Color3.fromRGB(255, 200, 50),
	AccentColor = Color3.fromRGB(0, 200, 255),
	
	-- Night Vision Colors
	NightVisionOverlayColor = Color3.fromRGB(100, 255, 100),
	NightVisionTint = Color3.fromRGB(0, 255, 0),
	NightVisionAccent = Color3.fromRGB(150, 255, 150),
	
	-- Night Vision Toggle Key
	NightVisionKey = Enum.KeyCode.N,
	
	-- Raycast settings
	RaycastMaxDistance = 2000,   -- Max raycast distance for entity detection
	
	-- Debug Gizmos
	DebugGizmosEnabled = true,
	DebugLineColor = Color3.fromRGB(0, 255, 0),      -- Green for valid hit
	DebugLineMissColor = Color3.fromRGB(255, 0, 0), -- Red for miss
	DebugLineNoTagColor = Color3.fromRGB(255, 255, 0), -- Yellow for hit without tag
	DebugHitPointSize = 0.5,
	DebugLineDuration = 2,       -- How long debug visuals stay visible (seconds)
}

-- === STATE ===
local isEffectVisible = Value(true)
local currentTime = Value(os.date(CAMERA_CONFIG.TimestampFormat))
local recBlinkState = Value(true)
local batteryLevel = Value(CAMERA_CONFIG.BatteryLevel)
local audioLevelL = Value(0.6)
local audioLevelR = Value(0.5)
local zoomLevel = Value(CAMERA_CONFIG.ZoomLevel)
local memoryUsed = Value(CAMERA_CONFIG.MemoryUsed)
local isNightVisionEnabled = Value(false)

-- Target object info (from raycast)
local targetObjectName = Value("---")
local targetObjectClass = Value("---")
local targetObjectDistance = Value(0)

-- Photo target detection state
local isLookingAtPhotoTarget = Value(false)
local currentTargetInstance = nil  -- Track which specific target we're looking at

-- Gaze progress (0 to 1, fills up while looking at target)
local gazeProgress = Value(0)
local GAZE_FILL_TIME = 2.0  -- Seconds to fill the bar completely

-- Crosshair animation values (for smooth transitions)
local crosshairScale = Value(1)

-- Spring-animated scale
local crosshairScaleSpring = Spring(crosshairScale, 25, 0.8)

-- === INPUT INSTANCES ===
local mouse = Mouse.new()
local keyboard = Keyboard.new()

-- === CAMERA CONTROL STATE ===
local cameraControlState = {
	yaw = 0,           -- Horizontal rotation (radians)
	pitch = 0,         -- Vertical rotation (radians)
	targetYaw = 0,
	targetPitch = 0,
	currentZoom = 1.0,
	targetZoom = 1.0,
}

-- === CURSOR CONTROL ===

local function lockAndHideCursor()
	if CAMERA_CONFIG.HideCursor then
		UserInputService.MouseIconEnabled = false
	end
	if CAMERA_CONFIG.LockCursor then
		mouse:LockCenter()
	end
end

local function unlockAndShowCursor()
	UserInputService.MouseIconEnabled = true
	mouse:Unlock()
end

-- === UI COMPONENTS ===

local function createVignette(parent)
	return New "ImageLabel" {
		Name = "Vignette",
		Size = UDim2.new(1, 0, 1, 0),
		Position = UDim2.new(0, 0, 0, 0),
		BackgroundTransparency = 1,
		Image = "rbxassetid://1749611830",
		ImageColor3 = Color3.fromRGB(0, 0, 0),
		ImageTransparency = 1 - CAMERA_CONFIG.VignetteIntensity,
		Parent = parent,
	}
end

local function createNightVisionOverlay(parent)
	return New "Frame" {
		Name = "NightVisionOverlay",
		Size = UDim2.new(1, 0, 1, 0),
		Position = UDim2.new(0, 0, 0, 0),
		BackgroundColor3 = CAMERA_CONFIG.NightVisionTint,
		BackgroundTransparency = Computed(function()
			return isNightVisionEnabled:get() and 0.85 or 1
		end),
		BorderSizePixel = 0,
		Parent = parent,
	}
end

local function createFilmBorder(parent, animatedTransparency)
	-- Using scale values (based on 1920x1080 reference)
	local borderThicknessScale = 0.083  -- 90/1080
	local cornerSizeX = 0.021           -- 40/1920
	local cornerSizeY = 0.037           -- 40/1080
	local marginX = 0.182               -- 350/1920
	local lineThicknessX = 0.0016       -- 3/1920
	local lineThicknessY = 0.003        -- 3/1080
	local cornerOffsetY = 0.028         -- 30/1080
	
	return New "Frame" {
		Name = "FilmBorder",
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundTransparency = 1,
		Parent = parent,
		
		[Children] = {
			-- Top border
			New "Frame" {
				Size = UDim2.new(1, 0, borderThicknessScale, 0),
				Position = UDim2.new(0, 0, 0, 0),
				BackgroundColor3 = Color3.fromRGB(0, 0, 0),
				BackgroundTransparency = 0.3,
				BorderSizePixel = 0,
			},
			-- Bottom border
			New "Frame" {
				Size = UDim2.new(1, 0, borderThicknessScale, 0),
				Position = UDim2.new(0, 0, 1 - borderThicknessScale, 0),
				BackgroundColor3 = Color3.fromRGB(0, 0, 0),
				BackgroundTransparency = 0.3,
				BorderSizePixel = 0,
			},
			-- Corner brackets (top-left)
			New "Frame" {
				Size = UDim2.new(cornerSizeX, 0, lineThicknessY, 0),
				Position = UDim2.new(marginX, 0, borderThicknessScale + cornerOffsetY, 0),
				BackgroundColor3 = CAMERA_CONFIG.OverlayColor,
				BackgroundTransparency = animatedTransparency,
				BorderSizePixel = 0,
			},
			New "Frame" {
				Size = UDim2.new(lineThicknessX, 0, cornerSizeY, 0),
				Position = UDim2.new(marginX, 0, borderThicknessScale + cornerOffsetY, 0),
				BackgroundColor3 = CAMERA_CONFIG.OverlayColor,
				BackgroundTransparency = animatedTransparency,
				BorderSizePixel = 0,
			},
			-- Corner brackets (top-right)
			New "Frame" {
				Size = UDim2.new(cornerSizeX, 0, lineThicknessY, 0),
				Position = UDim2.new(1 - marginX - cornerSizeX, 0, borderThicknessScale + cornerOffsetY, 0),
				BackgroundColor3 = CAMERA_CONFIG.OverlayColor,
				BackgroundTransparency = animatedTransparency,
				BorderSizePixel = 0,
			},
			New "Frame" {
				Size = UDim2.new(lineThicknessX, 0, cornerSizeY, 0),
				Position = UDim2.new(1 - marginX - lineThicknessX, 0, borderThicknessScale + cornerOffsetY, 0),
				BackgroundColor3 = CAMERA_CONFIG.OverlayColor,
				BackgroundTransparency = animatedTransparency,
				BorderSizePixel = 0,
			},
			-- Corner brackets (bottom-left)
			New "Frame" {
				Size = UDim2.new(cornerSizeX, 0, lineThicknessY, 0),
				Position = UDim2.new(marginX, 0, 1 - borderThicknessScale - cornerOffsetY - lineThicknessY, 0),
				BackgroundColor3 = CAMERA_CONFIG.OverlayColor,
				BackgroundTransparency = animatedTransparency,
				BorderSizePixel = 0,
			},
			New "Frame" {
				Size = UDim2.new(lineThicknessX, 0, cornerSizeY, 0),
				Position = UDim2.new(marginX, 0, 1 - borderThicknessScale - cornerOffsetY - cornerSizeY, 0),
				BackgroundColor3 = CAMERA_CONFIG.OverlayColor,
				BackgroundTransparency = animatedTransparency,
				BorderSizePixel = 0,
			},
			-- Corner brackets (bottom-right)
			New "Frame" {
				Size = UDim2.new(cornerSizeX, 0, lineThicknessY, 0),
				Position = UDim2.new(1 - marginX - cornerSizeX, 0, 1 - borderThicknessScale - cornerOffsetY - lineThicknessY, 0),
				BackgroundColor3 = CAMERA_CONFIG.OverlayColor,
				BackgroundTransparency = animatedTransparency,
				BorderSizePixel = 0,
			},
			New "Frame" {
				Size = UDim2.new(lineThicknessX, 0, cornerSizeY, 0),
				Position = UDim2.new(1 - marginX - lineThicknessX, 0, 1 - borderThicknessScale - cornerOffsetY - cornerSizeY, 0),
				BackgroundColor3 = CAMERA_CONFIG.OverlayColor,
				BackgroundTransparency = animatedTransparency,
				BorderSizePixel = 0,
			},
		},
	}
end

local function createCrosshair(parent, animatedTransparency)
	-- Scale values (based on 1920x1080 reference)
	local crossSizeX = 0.017    -- 32/1920
	local crossSizeY = 0.03     -- 32/1080
	local gapSizeX = 0.006      -- 12/1920
	local gapSizeY = 0.011      -- 12/1080
	local thicknessX = 0.0016   -- 3/1920
	local thicknessY = 0.003    -- 3/1080
	
	-- Crosshair color (changes based on target state)
	local crosshairColor = Computed(function()
		if isLookingAtPhotoTarget:get() then
			return Color3.fromRGB(0, 255, 0)  -- Green when targeting
		else
			return Color3.fromRGB(255, 255, 255)  -- White normally
		end
	end)
	
	-- Animated crosshair size multiplier
	local sizeMultiplier = Computed(function()
		return crosshairScaleSpring:get()
	end)
	
	return New "Frame" {
		Name = "Crosshair",
		Size = Computed(function()
			local scale = sizeMultiplier:get()
			return UDim2.new(0.052 * scale, 0, 0.093 * scale, 0)
		end),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		Parent = parent,
		
		[Children] = {
			-- Center dot (circle, grows when targeting)
			New "Frame" {
				Size = Computed(function()
					local scale = sizeMultiplier:get()
					local baseSize = isLookingAtPhotoTarget:get() and 0.1 or 0.06
					return UDim2.new(baseSize * scale, 0, baseSize * scale, 0)
				end),
				Position = UDim2.new(0.5, 0, 0.5, 0),
				AnchorPoint = Vector2.new(0.5, 0.5),
				BackgroundColor3 = crosshairColor,
				BackgroundTransparency = animatedTransparency,
				BorderSizePixel = 0,
				[Children] = {
					New "UICorner" { 
						CornerRadius = UDim.new(1, 0),  -- Always circle
					},
				},
			},
			-- Top line
			New "Frame" {
				Size = Computed(function()
					local scale = sizeMultiplier:get()
					return UDim2.new(thicknessX * scale, 0, crossSizeY * scale, 0)
				end),
				Position = Computed(function()
					local scale = sizeMultiplier:get()
					return UDim2.new(0.5, 0, 0.5 - (gapSizeY + crossSizeY) * scale, 0)
				end),
				AnchorPoint = Vector2.new(0.5, 0),
				BackgroundColor3 = crosshairColor,
				BackgroundTransparency = animatedTransparency,
				BorderSizePixel = 0,
			},
			-- Bottom line
			New "Frame" {
				Size = Computed(function()
					local scale = sizeMultiplier:get()
					return UDim2.new(thicknessX * scale, 0, crossSizeY * scale, 0)
				end),
				Position = Computed(function()
					local scale = sizeMultiplier:get()
					return UDim2.new(0.5, 0, 0.5 + gapSizeY * scale, 0)
				end),
				AnchorPoint = Vector2.new(0.5, 0),
				BackgroundColor3 = crosshairColor,
				BackgroundTransparency = animatedTransparency,
				BorderSizePixel = 0,
			},
			-- Left line
			New "Frame" {
				Size = Computed(function()
					local scale = sizeMultiplier:get()
					return UDim2.new(crossSizeX * scale, 0, thicknessY * scale, 0)
				end),
				Position = Computed(function()
					local scale = sizeMultiplier:get()
					return UDim2.new(0.5 - (gapSizeX + crossSizeX) * scale, 0, 0.5, 0)
				end),
				AnchorPoint = Vector2.new(0, 0.5),
				BackgroundColor3 = crosshairColor,
				BackgroundTransparency = animatedTransparency,
				BorderSizePixel = 0,
			},
			-- Right line
			New "Frame" {
				Size = Computed(function()
					local scale = sizeMultiplier:get()
					return UDim2.new(crossSizeX * scale, 0, thicknessY * scale, 0)
				end),
				Position = Computed(function()
					local scale = sizeMultiplier:get()
					return UDim2.new(0.5 + gapSizeX * scale, 0, 0.5, 0)
				end),
				AnchorPoint = Vector2.new(0, 0.5),
				BackgroundColor3 = crosshairColor,
				BackgroundTransparency = animatedTransparency,
				BorderSizePixel = 0,
			},
			-- Corner brackets (more prominent when targeting)
			New "Frame" {
				Size = Computed(function()
					local scale = sizeMultiplier:get()
					local width = isLookingAtPhotoTarget:get() and 0.15 or 0.08
					return UDim2.new(width * scale, 0, 0.01 * scale, 0)
				end),
				Position = UDim2.new(0.5 - 0.35, 0, 0.5 - 0.35, 0),
				AnchorPoint = Vector2.new(0.5, 0.5),
				Rotation = 45,
				BackgroundColor3 = crosshairColor,
				BackgroundTransparency = Computed(function() return 0.3 + animatedTransparency:get() * 0.3 end),
				BorderSizePixel = 0,
			},
			New "Frame" {
				Size = Computed(function()
					local scale = sizeMultiplier:get()
					local width = isLookingAtPhotoTarget:get() and 0.15 or 0.08
					return UDim2.new(width * scale, 0, 0.01 * scale, 0)
				end),
				Position = UDim2.new(0.5 + 0.35, 0, 0.5 - 0.35, 0),
				AnchorPoint = Vector2.new(0.5, 0.5),
				Rotation = -45,
				BackgroundColor3 = crosshairColor,
				BackgroundTransparency = Computed(function() return 0.3 + animatedTransparency:get() * 0.3 end),
				BorderSizePixel = 0,
			},
			New "Frame" {
				Size = Computed(function()
					local scale = sizeMultiplier:get()
					local width = isLookingAtPhotoTarget:get() and 0.15 or 0.08
					return UDim2.new(width * scale, 0, 0.01 * scale, 0)
				end),
				Position = UDim2.new(0.5 - 0.35, 0, 0.5 + 0.35, 0),
				AnchorPoint = Vector2.new(0.5, 0.5),
				Rotation = -45,
				BackgroundColor3 = crosshairColor,
				BackgroundTransparency = Computed(function() return 0.3 + animatedTransparency:get() * 0.3 end),
				BorderSizePixel = 0,
			},
			New "Frame" {
				Size = Computed(function()
					local scale = sizeMultiplier:get()
					local width = isLookingAtPhotoTarget:get() and 0.15 or 0.08
					return UDim2.new(width * scale, 0, 0.01 * scale, 0)
				end),
				Position = UDim2.new(0.5 + 0.35, 0, 0.5 + 0.35, 0),
				AnchorPoint = Vector2.new(0.5, 0.5),
				Rotation = 45,
				BackgroundColor3 = crosshairColor,
				BackgroundTransparency = Computed(function() return 0.3 + animatedTransparency:get() * 0.3 end),
				BorderSizePixel = 0,
			},
			-- "PHOTO" indicator when targeting
			New "TextLabel" {
				Size = UDim2.new(1, 0, 0.15, 0),
				Position = UDim2.new(0.5, 0, 1.1, 0),
				AnchorPoint = Vector2.new(0.5, 0),
				BackgroundTransparency = 1,
				Font = Enum.Font.RobotoMono,
				TextScaled = true,
				TextColor3 = crosshairColor,
				TextTransparency = Computed(function()
					return isLookingAtPhotoTarget:get() and animatedTransparency:get() or 1
				end),
				Text = "◉ PHOTO TARGET",
			},
		},
	}
end

-- Gaze progress bar - shows when looking at a PhotoTarget
local function createGazeProgressBar(parent, animatedTransparency)
	-- Scale values (based on 1920x1080 reference)
	local barWidth = 0.15   -- 288/1920
	local barHeight = 0.008 -- 8/1080
	
	-- Smooth spring animation for progress
	local progressSpring = Spring(gazeProgress, 30, 0.7)
	
	return New "Frame" {
		Name = "GazeProgressBar",
		Size = UDim2.new(barWidth, 0, barHeight, 0),
		Position = UDim2.new(0.5, 0, 0.75, 0),  -- Bottom middle of screen
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = Color3.fromRGB(30, 30, 30),
		BackgroundTransparency = Computed(function()
			-- Hide when not looking at target (progress is 0)
			local progress = gazeProgress:get()
			if progress <= 0 then
				return 1
			end
			return 0.5 + animatedTransparency:get() * 0.3
		end),
		BorderSizePixel = 0,
		Parent = parent,
		
		[Children] = {
			-- Corner rounding
			New "UICorner" {
				CornerRadius = UDim.new(0.5, 0),
			},
			
			-- Border/stroke
			New "UIStroke" {
				Color = Computed(function()
					if isNightVisionEnabled:get() then
						return CAMERA_CONFIG.NightVisionOverlayColor
					end
					return Color3.fromRGB(0, 255, 0)  -- Green border
				end),
				Thickness = 1,
				Transparency = Computed(function()
					local progress = gazeProgress:get()
					if progress <= 0 then
						return 1
					end
					return animatedTransparency:get()
				end),
			},
			
			-- Progress fill
			New "Frame" {
				Name = "Fill",
				Size = Computed(function()
					local progress = progressSpring:get()
					return UDim2.new(math.clamp(progress, 0, 1), 0, 1, 0)
				end),
				Position = UDim2.new(0, 0, 0, 0),
				BackgroundColor3 = Computed(function()
					local progress = gazeProgress:get()
					-- Transition from green to bright cyan as it fills
					if progress >= 1 then
						return Color3.fromRGB(0, 255, 200)  -- Bright cyan when full
					end
					return Color3.fromRGB(0, 255, 0)  -- Green while filling
				end),
				BackgroundTransparency = Computed(function()
					local progress = gazeProgress:get()
					if progress <= 0 then
						return 1
					end
					return animatedTransparency:get() * 0.3
				end),
				BorderSizePixel = 0,
				
				[Children] = {
					New "UICorner" {
						CornerRadius = UDim.new(0.5, 0),
					},
				},
			},
			
			-- Label text
			New "TextLabel" {
				Name = "Label",
				Size = UDim2.new(1, 0, 3, 0),
				Position = UDim2.new(0.5, 0, -4, 0),
				AnchorPoint = Vector2.new(0.5, 0),
				BackgroundTransparency = 1,
				Font = Enum.Font.RobotoMono,
				TextScaled = true,
				TextColor3 = Computed(function()
					if isNightVisionEnabled:get() then
						return CAMERA_CONFIG.NightVisionOverlayColor
					end
					return Color3.fromRGB(0, 255, 0)
				end),
				TextTransparency = Computed(function()
					local progress = gazeProgress:get()
					if progress <= 0 then
						return 1
					end
					return animatedTransparency:get()
				end),
				Text = Computed(function()
					local progress = gazeProgress:get()
					if progress >= 1 then
						return "◉ CAPTURED"
					end
					return string.format("CAPTURING... %d%%", math.floor(progress * 100))
				end),
			},
		},
	}
end

local function createAudioLevelMeter(parent, animatedTransparency, side, levelValue)
	-- Scale values (based on 1920x1080 reference)
	local meterHeightScale = 0.139   -- 150/1080
	local meterWidthScale = 0.006    -- 12/1920
	local segments = 12
	local segmentHeightScale = meterHeightScale / segments
	local xPosScale = side == "L" and 0.792 or 0.802  -- (1920-400)/1920, (1920-380)/1920
	
	local segmentFrames = {}
	for i = 1, segments do
		local segmentColor
		if i <= 8 then
			segmentColor = Color3.fromRGB(0, 255, 100)  -- Green
		elseif i <= 10 then
			segmentColor = Color3.fromRGB(255, 200, 0)  -- Yellow
		else
			segmentColor = Color3.fromRGB(255, 50, 50)  -- Red
		end
		
		table.insert(segmentFrames, New "Frame" {
			Size = UDim2.new(1, 0, (1/segments) - 0.01, 0),
			Position = UDim2.new(0, 0, 1 - (i / segments), 0),
			BackgroundColor3 = segmentColor,
			BackgroundTransparency = Computed(function()
				local level = levelValue:get()
				local threshold = i / segments
				if level >= threshold then
					return animatedTransparency:get()
				else
					return 0.8
				end
			end),
			BorderSizePixel = 0,
		})
	end
	
	return New "Frame" {
		Name = "AudioMeter_" .. side,
		Size = UDim2.new(meterWidthScale, 0, meterHeightScale, 0),
		Position = UDim2.new(xPosScale, 0, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		BackgroundTransparency = 1,
		Parent = parent,
		
		[Children] = {
			-- Background
			New "Frame" {
				Size = UDim2.new(1, 0, 1, 0),
				BackgroundColor3 = Color3.fromRGB(20, 20, 20),
				BackgroundTransparency = 0.5,
				BorderSizePixel = 0,
				ZIndex = 0,
			},
			-- Label
			New "TextLabel" {
				Size = UDim2.new(2, 0, 0.12, 0),
				Position = UDim2.new(0.5, 0, 1.05, 0),
				AnchorPoint = Vector2.new(0.5, 0),
				BackgroundTransparency = 1,
				Font = Enum.Font.RobotoMono,
				TextScaled = true,
				TextColor3 = CAMERA_CONFIG.OverlayColor,
				TextTransparency = animatedTransparency,
				Text = side,
			},
			-- Segments
			table.unpack(segmentFrames),
		},
	}
end

local function createRecIndicator(parent, animatedTransparency)
	return New "Frame" {
		Name = "RecIndicator",
		Size = UDim2.new(0.0625, 0, 0.037, 0),  -- 120/1920, 40/1080
		Position = UDim2.new(0.188, 0, 0.167, 0),  -- 360/1920, 180/1080
		BackgroundTransparency = 1,
		Parent = parent,
		
		[Children] = {
			-- REC dot
			New "Frame" {
				Name = "RecDot",
				Size = UDim2.new(0.5, 0, 0.5, 0),
				Position = UDim2.new(0, 0, 0.5, 0),
				AnchorPoint = Vector2.new(0, 0.5),
				BackgroundColor3 = CAMERA_CONFIG.RecColor,
				BackgroundTransparency = Computed(function()
					return recBlinkState:get() and animatedTransparency:get() or 1
				end),
				BorderSizePixel = 0,
				
				[Children] = {
					New "UICorner" {
						CornerRadius = UDim.new(1, 0),
					},
					New "UIAspectRatioConstraint" {
						AspectRatio = 1,
					},
				},
			},
			-- REC text
			New "TextLabel" {
				Name = "RecText",
				Size = UDim2.new(0.6, 0, 1, 0),
				Position = UDim2.new(0.25, 0, 0, 0),
				BackgroundTransparency = 1,
				Font = Enum.Font.RobotoMono,
				TextScaled = true,
				TextColor3 = CAMERA_CONFIG.RecColor,
				TextTransparency = Computed(function()
					return recBlinkState:get() and animatedTransparency:get() or 0.5
				end),
				TextXAlignment = Enum.TextXAlignment.Left,
				Text = "REC",
			},
		},
	}
end

local function createTimestamp(parent, animatedTransparency)
	return New "TextLabel" {
		Name = "Timestamp",
		Size = UDim2.new(0.182, 0, 0.032, 0),  -- 350/1920, 35/1080
		Position = UDim2.new(0.812, 0, 0.167, 0),  -- (1920-360)/1920, 180/1080
		AnchorPoint = Vector2.new(1, 0),
		BackgroundTransparency = 1,
		Font = Enum.Font.RobotoMono,
		TextScaled = true,
		TextColor3 = CAMERA_CONFIG.OverlayColor,
		TextTransparency = animatedTransparency,
		TextXAlignment = Enum.TextXAlignment.Right,
		Text = Computed(function()
			return currentTime:get()
		end),
		Parent = parent,
	}
end

local function createCameraSettings(parent, animatedTransparency)
	return New "Frame" {
		Name = "CameraSettings",
		Size = UDim2.new(0.13, 0, 0.102, 0),  -- 250/1920, 110/1080
		Position = UDim2.new(0.812, 0, 0.204, 0),  -- (1920-360)/1920, 220/1080
		AnchorPoint = Vector2.new(1, 0),
		BackgroundTransparency = 1,
		Parent = parent,
		
		[Children] = {
			New "TextLabel" {
				Size = UDim2.new(1, 0, 0.22, 0),
				Position = UDim2.new(0, 0, 0, 0),
				BackgroundTransparency = 1,
				Font = Enum.Font.RobotoMono,
				TextScaled = true,
				TextColor3 = CAMERA_CONFIG.OverlayColor,
				TextTransparency = animatedTransparency,
				TextXAlignment = Enum.TextXAlignment.Right,
				Text = CAMERA_CONFIG.Aperture .. "  ISO " .. CAMERA_CONFIG.ISO,
			},
			New "TextLabel" {
				Size = UDim2.new(1, 0, 0.22, 0),
				Position = UDim2.new(0, 0, 0.25, 0),
				BackgroundTransparency = 1,
				Font = Enum.Font.RobotoMono,
				TextScaled = true,
				TextColor3 = CAMERA_CONFIG.OverlayColor,
				TextTransparency = Computed(function() return 0.3 + animatedTransparency:get() * 0.7 end),
				TextXAlignment = Enum.TextXAlignment.Right,
				Text = CAMERA_CONFIG.ShutterSpeed .. "  " .. CAMERA_CONFIG.FocalLength,
			},
			-- White balance
			New "TextLabel" {
				Size = UDim2.new(1, 0, 0.2, 0),
				Position = UDim2.new(0, 0, 0.53, 0),
				BackgroundTransparency = 1,
				Font = Enum.Font.RobotoMono,
				TextScaled = true,
				TextColor3 = CAMERA_CONFIG.AccentColor,
				TextTransparency = animatedTransparency,
				TextXAlignment = Enum.TextXAlignment.Right,
				Text = "AWB  5600K",
			},
		},
	}
end

local function createZoomIndicator(parent, animatedTransparency)
	return New "Frame" {
		Name = "ZoomIndicator",
		Size = UDim2.new(0.094, 0, 0.037, 0),  -- 180/1920, 40/1080
		Position = UDim2.new(0.182, 0, 0.5, 0),  -- 350/1920
		AnchorPoint = Vector2.new(0, 0.5),
		BackgroundTransparency = 1,
		Parent = parent,
		
		[Children] = {
			-- Label
			New "TextLabel" {
				Size = UDim2.new(0.33, 0, 0.5, 0),
				Position = UDim2.new(0, 0, 0, 0),
				BackgroundTransparency = 1,
				Font = Enum.Font.RobotoMono,
				TextScaled = true,
				TextColor3 = CAMERA_CONFIG.OverlayColor,
				TextTransparency = Computed(function() return 0.4 + animatedTransparency:get() * 0.6 end),
				TextXAlignment = Enum.TextXAlignment.Left,
				Text = "ZOOM",
			},
			-- Bar background
			New "Frame" {
				Size = UDim2.new(1, 0, 0.15, 0),
				Position = UDim2.new(0, 0, 0.6, 0),
				BackgroundColor3 = Color3.fromRGB(60, 60, 60),
				BackgroundTransparency = 0.5,
				BorderSizePixel = 0,
				
				[Children] = {
					New "UICorner" { CornerRadius = UDim.new(0.5, 0) },
					-- Fill bar
					New "Frame" {
						Size = Computed(function()
							local zoom = math.clamp(zoomLevel:get(), 1, 4)
							return UDim2.new((zoom - 1) / 3, 0, 1, 0)
						end),
						BackgroundColor3 = CAMERA_CONFIG.AccentColor,
						BackgroundTransparency = animatedTransparency,
						BorderSizePixel = 0,
						[Children] = {
							New "UICorner" { CornerRadius = UDim.new(0.5, 0) },
						},
					},
				},
			},
			-- Zoom value
			New "TextLabel" {
				Size = UDim2.new(0.33, 0, 0.5, 0),
				Position = UDim2.new(1.1, 0, 0.5, 0),
				AnchorPoint = Vector2.new(0, 0.5),
				BackgroundTransparency = 1,
				Font = Enum.Font.RobotoMono,
				TextScaled = true,
				TextColor3 = CAMERA_CONFIG.OverlayColor,
				TextTransparency = animatedTransparency,
				TextXAlignment = Enum.TextXAlignment.Left,
				Text = Computed(function()
					return string.format("%.1fx", zoomLevel:get())
				end),
			},
		},
	}
end

local function createMemoryCard(parent, animatedTransparency)
	return New "Frame" {
		Name = "MemoryCard",
		Size = UDim2.new(0.078, 0, 0.051, 0),  -- 150/1920, 55/1080
		Position = UDim2.new(0.812, 0, 0.833, 0),  -- (1920-360)/1920, (1080-180)/1080
		AnchorPoint = Vector2.new(1, 1),
		BackgroundTransparency = 1,
		Parent = parent,
		
		[Children] = {
			-- SD card icon (simplified)
			New "Frame" {
				Size = UDim2.new(0.15, 0, 0.5, 0),
				Position = UDim2.new(0, 0, 0, 0),
				BackgroundColor3 = CAMERA_CONFIG.OverlayColor,
				BackgroundTransparency = animatedTransparency,
				BorderSizePixel = 0,
				[Children] = {
					New "UICorner" { CornerRadius = UDim.new(0.1, 0) },
					New "UIAspectRatioConstraint" { AspectRatio = 0.78 },
					-- Notch
					New "Frame" {
						Size = UDim2.new(0.35, 0, 0.28, 0),
						Position = UDim2.new(0.65, 0, 0, 0),
						BackgroundColor3 = Color3.fromRGB(30, 30, 30),
						BorderSizePixel = 0,
					},
				},
			},
			-- Memory text
			New "TextLabel" {
				Size = UDim2.new(0.8, 0, 0.44, 0),
				Position = UDim2.new(0.2, 0, 0, 0),
				BackgroundTransparency = 1,
				Font = Enum.Font.RobotoMono,
				TextScaled = true,
				TextColor3 = CAMERA_CONFIG.OverlayColor,
				TextTransparency = animatedTransparency,
				TextXAlignment = Enum.TextXAlignment.Left,
				Text = Computed(function()
					return string.format("%dGB/%dGB", memoryUsed:get(), CAMERA_CONFIG.MemoryTotal)
				end),
			},
			-- Remaining time
			New "TextLabel" {
				Size = UDim2.new(0.8, 0, 0.36, 0),
				Position = UDim2.new(0.2, 0, 0.47, 0),
				BackgroundTransparency = 1,
				Font = Enum.Font.RobotoMono,
				TextScaled = true,
				TextColor3 = CAMERA_CONFIG.OverlayColor,
				TextTransparency = Computed(function() return 0.4 + animatedTransparency:get() * 0.6 end),
				TextXAlignment = Enum.TextXAlignment.Left,
				Text = Computed(function()
					local remaining = CAMERA_CONFIG.MemoryTotal - memoryUsed:get()
					local minutes = math.floor(remaining * 2)  -- ~2 min per GB at high quality
					return string.format("%02d:%02d REM", math.floor(minutes / 60), minutes % 60)
				end),
			},
		},
	}
end

local function createBatteryIndicator(parent, animatedTransparency)
	return New "Frame" {
		Name = "BatteryIndicator",
		Size = UDim2.new(0.068, 0, 0.03, 0),  -- 130/1920, 32/1080
		Position = UDim2.new(0.812, 0, 0.778, 0),  -- (1920-360)/1920, (1080-240)/1080
		AnchorPoint = Vector2.new(1, 1),
		BackgroundTransparency = 1,
		Parent = parent,
		
		[Children] = {
			-- Battery outline
			New "Frame" {
				Name = "BatteryOutline",
				Size = UDim2.new(0.385, 0, 0.8, 0),
				Position = UDim2.new(0, 0, 0.5, 0),
				AnchorPoint = Vector2.new(0, 0.5),
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				
				[Children] = {
					New "UIStroke" {
						Color = CAMERA_CONFIG.OverlayColor,
						Thickness = 2,
						Transparency = animatedTransparency,
					},
					New "UICorner" {
						CornerRadius = UDim.new(0.1, 0),
					},
					-- Battery fill
					New "Frame" {
						Name = "BatteryFill",
						Size = Computed(function()
							return UDim2.new(batteryLevel:get() / 100 * 0.88, 0, 0.76, 0)
						end),
						Position = UDim2.new(0.06, 0, 0.12, 0),
						BackgroundColor3 = Computed(function()
							local level = batteryLevel:get()
							if level <= 20 then
								return CAMERA_CONFIG.RecColor
							elseif level <= 40 then
								return CAMERA_CONFIG.WarningColor
							else
								return CAMERA_CONFIG.OverlayColor
							end
						end),
						BackgroundTransparency = animatedTransparency,
						BorderSizePixel = 0,
						
						[Children] = {
							New "UICorner" {
								CornerRadius = UDim.new(0.1, 0),
							},
						},
					},
				},
			},
			-- Battery tip
			New "Frame" {
				Name = "BatteryTip",
				Size = UDim2.new(0.04, 0, 0.44, 0),
				Position = UDim2.new(0.41, 0, 0.5, 0),
				AnchorPoint = Vector2.new(0, 0.5),
				BackgroundColor3 = CAMERA_CONFIG.OverlayColor,
				BackgroundTransparency = animatedTransparency,
				BorderSizePixel = 0,
				
				[Children] = {
					New "UICorner" {
						CornerRadius = UDim.new(0.2, 0),
					},
				},
			},
			-- Percentage text
			New "TextLabel" {
				Name = "BatteryText",
				Size = UDim2.new(0.42, 0, 1, 0),
				Position = UDim2.new(0.5, 0, 0, 0),
				BackgroundTransparency = 1,
				Font = Enum.Font.RobotoMono,
				TextScaled = true,
				TextColor3 = CAMERA_CONFIG.OverlayColor,
				TextTransparency = animatedTransparency,
				TextXAlignment = Enum.TextXAlignment.Left,
				Text = Computed(function()
					return batteryLevel:get() .. "%"
				end),
			},
		},
	}
end

local function createScanLines(parent, animatedTransparency)
	local lines = {}
	local lineCount = math.floor(1 / (CAMERA_CONFIG.ScanLineSpacing / 1080))  -- Convert to scale-based count
	lineCount = math.min(lineCount, 200)
	
	for i = 1, lineCount do
		local yPosScale = (i - 1) / lineCount
		table.insert(lines, New "Frame" {
			Size = UDim2.new(1, 0, 0.001, 0),  -- Very thin line
			Position = UDim2.new(0, 0, yPosScale, 0),
			BackgroundColor3 = Color3.fromRGB(0, 0, 0),
			BackgroundTransparency = Computed(function()
				return 1 - CAMERA_CONFIG.ScanLineOpacity + animatedTransparency:get() * CAMERA_CONFIG.ScanLineOpacity
			end),
			BorderSizePixel = 0,
		})
	end
	
	return New "Frame" {
		Name = "ScanLines",
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundTransparency = 1,
		ClipsDescendants = true,
		Parent = parent,
		
		[Children] = lines,
	}
end

local function createFilmGrain(parent, animatedTransparency)
	return New "ImageLabel" {
		Name = "FilmGrain",
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundTransparency = 1,
		Image = "rbxassetid://2833078857",
		ImageTransparency = Computed(function()
			return 1 - CAMERA_CONFIG.FilmGrainOpacity + animatedTransparency:get() * CAMERA_CONFIG.FilmGrainOpacity
		end),
		ScaleType = Enum.ScaleType.Tile,
		TileSize = UDim2.new(0, 256, 0, 256),
		Parent = parent,
	}
end

local function createCameraInfo(parent, animatedTransparency)
	return New "Frame" {
		Name = "CameraInfo",
		Size = UDim2.new(0.146, 0, 0.185, 0),  -- 280/1920, 200/1080
		Position = UDim2.new(0.188, 0, 0.833, 0),  -- 360/1920, (1080-180)/1080
		AnchorPoint = Vector2.new(0, 1),
		BackgroundTransparency = 1,
		Parent = parent,
		
		[Children] = {
			-- Camera model
			New "TextLabel" {
				Size = UDim2.new(1, 0, 0.14, 0),
				Position = UDim2.new(0, 0, 0, 0),
				BackgroundTransparency = 1,
				Font = Enum.Font.RobotoMono,
				TextScaled = true,
				TextColor3 = CAMERA_CONFIG.OverlayColor,
				TextTransparency = animatedTransparency,
				TextXAlignment = Enum.TextXAlignment.Left,
				Text = "FACILITY CAM-01",
			},
			-- Resolution
			New "TextLabel" {
				Size = UDim2.new(1, 0, 0.12, 0),
				Position = UDim2.new(0, 0, 0.16, 0),
				BackgroundTransparency = 1,
				Font = Enum.Font.RobotoMono,
				TextScaled = true,
				TextColor3 = CAMERA_CONFIG.OverlayColor,
				TextTransparency = Computed(function()
					return 0.3 + animatedTransparency:get() * 0.7
				end),
				TextXAlignment = Enum.TextXAlignment.Left,
				Text = "1920x1080 30FPS",
			},
			-- Night vision indicator
			New "TextLabel" {
				Size = UDim2.new(1, 0, 0.12, 0),
				Position = UDim2.new(0, 0, 0.30, 0),
				BackgroundTransparency = 1,
				Font = Enum.Font.RobotoMono,
				TextScaled = true,
				TextColor3 = Computed(function()
					return isNightVisionEnabled:get() and Color3.fromRGB(100, 255, 100) or Color3.fromRGB(150, 150, 150)
				end),
				TextTransparency = animatedTransparency,
				TextXAlignment = Enum.TextXAlignment.Left,
				Text = Computed(function()
					return isNightVisionEnabled:get() and "◉ NIGHT VISION ON" or "○ NIGHT VISION OFF"
				end),
			},
			-- Stabilization
			New "TextLabel" {
				Size = UDim2.new(1, 0, 0.11, 0),
				Position = UDim2.new(0, 0, 0.44, 0),
				BackgroundTransparency = 1,
				Font = Enum.Font.RobotoMono,
				TextScaled = true,
				TextColor3 = CAMERA_CONFIG.AccentColor,
				TextTransparency = animatedTransparency,
				TextXAlignment = Enum.TextXAlignment.Left,
				Text = "⟳ OIS ACTIVE",
			},
			
			-- Divider
			New "Frame" {
				Size = UDim2.new(0.9, 0, 0.005, 0),
				Position = UDim2.new(0, 0, 0.59, 0),
				BackgroundColor3 = CAMERA_CONFIG.OverlayColor,
				BackgroundTransparency = Computed(function()
					return 0.6 + animatedTransparency:get() * 0.4
				end),
				BorderSizePixel = 0,
			},
			
			-- Target label
			New "TextLabel" {
				Size = UDim2.new(1, 0, 0.09, 0),
				Position = UDim2.new(0, 0, 0.625, 0),
				BackgroundTransparency = 1,
				Font = Enum.Font.RobotoMono,
				TextScaled = true,
				TextColor3 = CAMERA_CONFIG.OverlayColor,
				TextTransparency = Computed(function()
					return 0.4 + animatedTransparency:get() * 0.6
				end),
				TextXAlignment = Enum.TextXAlignment.Left,
				Text = "TARGET:",
			},
			
			-- Target object name
			New "TextLabel" {
				Size = UDim2.new(1, 0, 0.11, 0),
				Position = UDim2.new(0, 0, 0.715, 0),
				BackgroundTransparency = 1,
				Font = Enum.Font.RobotoMono,
				TextScaled = true,
				TextColor3 = CAMERA_CONFIG.AccentColor,
				TextTransparency = animatedTransparency,
				TextXAlignment = Enum.TextXAlignment.Left,
				Text = Computed(function()
					return targetObjectName:get()
				end),
			},
			
			-- Target object class and distance
			New "TextLabel" {
				Size = UDim2.new(1, 0, 0.09, 0),
				Position = UDim2.new(0, 0, 0.835, 0),
				BackgroundTransparency = 1,
				Font = Enum.Font.RobotoMono,
				TextScaled = true,
				TextColor3 = CAMERA_CONFIG.OverlayColor,
				TextTransparency = Computed(function()
					return 0.3 + animatedTransparency:get() * 0.7
				end),
				TextXAlignment = Enum.TextXAlignment.Left,
				Text = Computed(function()
					local dist = targetObjectDistance:get()
					local class = targetObjectClass:get()
					if dist > 0 then
						return string.format("[%s] %.1fm", class, dist)
					else
						return "[---]"
					end
				end),
			},
		},
	}
end

local function createCameraEffectUI(self)
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")
	
	-- Animated transparency for fade effects
	self.effectTransparency = Value(0)
	local animatedTransparency = Spring(self.effectTransparency, 20, 1)
	
	local screenGui = New "ScreenGui" {
		Name = "CameraEffectUI",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = 50,
		Parent = playerGui,
		
		[Children] = {
			-- Main container
			New "Frame" {
				Name = "CameraOverlay",
				Size = UDim2.new(1, 0, 1, 0),
				BackgroundTransparency = 1,
				Visible = Computed(function()
					return isEffectVisible:get()
				end),
				
				[Children] = {
					-- Night vision green tint overlay
					createNightVisionOverlay(nil),
					
					-- Film border with corner brackets
					CAMERA_CONFIG.FilmBorderEnabled and createFilmBorder(nil, animatedTransparency) or nil,
					
					-- Vignette effect
					CAMERA_CONFIG.VignetteEnabled and createVignette(nil) or nil,
					
					-- Scan lines
					CAMERA_CONFIG.ScanLinesEnabled and createScanLines(nil, animatedTransparency) or nil,
					
					-- Film grain
					CAMERA_CONFIG.FilmGrainEnabled and createFilmGrain(nil, animatedTransparency) or nil,
					
					-- Crosshair
					CAMERA_CONFIG.CrosshairEnabled and createCrosshair(nil, animatedTransparency) or nil,
					
					-- REC indicator
					CAMERA_CONFIG.RecIndicatorEnabled and createRecIndicator(nil, animatedTransparency) or nil,
					
					-- Timestamp
					CAMERA_CONFIG.TimestampEnabled and createTimestamp(nil, animatedTransparency) or nil,
					
					-- Camera settings (aperture, ISO, etc)
					CAMERA_CONFIG.CameraSettingsEnabled and createCameraSettings(nil, animatedTransparency) or nil,
					
					-- Zoom indicator
					CAMERA_CONFIG.ZoomEnabled and createZoomIndicator(nil, animatedTransparency) or nil,
					
					-- Audio level meters
					CAMERA_CONFIG.AudioLevelsEnabled and createAudioLevelMeter(nil, animatedTransparency, "L", audioLevelL) or nil,
					CAMERA_CONFIG.AudioLevelsEnabled and createAudioLevelMeter(nil, animatedTransparency, "R", audioLevelR) or nil,
					
					-- Memory card indicator
					CAMERA_CONFIG.MemoryCardEnabled and createMemoryCard(nil, animatedTransparency) or nil,
					
					-- Battery indicator
					CAMERA_CONFIG.BatteryEnabled and createBatteryIndicator(nil, animatedTransparency) or nil,
					
					-- Camera info
					createCameraInfo(nil, animatedTransparency),
					
					-- Gaze progress bar (shows when looking at PhotoTarget)
					createGazeProgressBar(nil, animatedTransparency),
				},
			},
		},
	}
	
	self.screenGui = screenGui
	return screenGui
end

local function performFocusRaycast()
	local camera = workspace.CurrentCamera
	if not camera then return nil end
	
	-- Raycast from center of screen
	local viewportSize = camera.ViewportSize
	local centerScreenPos = Vector2.new(viewportSize.X / 2, viewportSize.Y / 2)
	
	local unitRay = camera:ViewportPointToRay(centerScreenPos.X, centerScreenPos.Y)
	
	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	
	-- Build exclusion list
	local excludeList = {}
	
	-- Exclude local player's character
	local player = Players.LocalPlayer
	if player and player.Character then
		table.insert(excludeList, player.Character)
	end
	
	-- Exclude all grid cubes
	local gridCubes = CollectionService:GetTagged(GRID_CUBE_TAG)
	for _, cube in ipairs(gridCubes) do
		table.insert(excludeList, cube)
	end
	
	raycastParams.FilterDescendantsInstances = excludeList
	
	return workspace:Raycast(
		unitRay.Origin,
		unitRay.Direction * CAMERA_CONFIG.RaycastMaxDistance,
		raycastParams
	), unitRay
end

-- === DEBUG GIZMOS (using imgizmo) ===

local gizmoInitialized = false

local function initGizmo()
	if not gizmoInitialized then
		Gizmo.Init()
		gizmoInitialized = true
	end
end

local function drawDebugRay(startPos, endPos, color, duration)
	if not CAMERA_CONFIG.DebugGizmosEnabled then return end
	initGizmo()
	
	Gizmo.SetStyle(color, 0, true)  -- Color, Transparency, AlwaysOnTop
	
	-- Draw the ray for the specified duration
	Gizmo.AddDebrisInSeconds(duration or CAMERA_CONFIG.DebugLineDuration, function()
		Gizmo.Ray:Draw(startPos, endPos)
	end)
end

local function drawDebugSphere(position, color, radius, duration, label)
	if not CAMERA_CONFIG.DebugGizmosEnabled then return end
	initGizmo()
	
	Gizmo.SetStyle(color, 0.2, true)
	
	-- Draw sphere at hit point
	Gizmo.AddDebrisInSeconds(duration or CAMERA_CONFIG.DebugLineDuration, function()
		Gizmo.Sphere:Draw(CFrame.new(position), radius or CAMERA_CONFIG.DebugHitPointSize, 12, 360)
	end)
	
	-- Draw text label
	if label then
		Gizmo.SetStyle(color, 0, true)
		Gizmo.AddDebrisInSeconds(duration or CAMERA_CONFIG.DebugLineDuration, function()
			Gizmo.Text:Draw(position + Vector3.new(0, 1, 0), label, 16)
		end)
	end
end

local function drawDebugBox(position, size, color, duration)
	if not CAMERA_CONFIG.DebugGizmosEnabled then return end
	initGizmo()
	
	Gizmo.SetStyle(color, 0.3, true)
	
	Gizmo.AddDebrisInSeconds(duration or CAMERA_CONFIG.DebugLineDuration, function()
		Gizmo.Box:Draw(CFrame.new(position), size or Vector3.new(0.5, 0.5, 0.5), false)
	end)
end

local function drawDebugArrow(startPos, endPos, color, duration)
	if not CAMERA_CONFIG.DebugGizmosEnabled then return end
	initGizmo()
	
	Gizmo.SetStyle(color, 0, true)
	
	Gizmo.AddDebrisInSeconds(duration or CAMERA_CONFIG.DebugLineDuration, function()
		Gizmo.Arrow:Draw(startPos, endPos, 0.1, 0.3, 12)
	end)
end

local function hasEntityTag(instance)
	-- Check if the instance itself has the tag
	if CollectionService:HasTag(instance, ENTITY_TAG) then
		return true, instance
	end
	
	-- Check ancestors for the tag
	local current = instance.Parent
	while current and current ~= workspace do
		if CollectionService:HasTag(current, ENTITY_TAG) then
			return true, current
		end
		current = current.Parent
	end
	
	return false, nil
end

local function hasPhotoTargetTag(instance)
	-- Check if the instance itself has the PhotoTarget tag
	if CollectionService:HasTag(instance, PHOTO_TARGET_TAG) then
		return true, instance
	end
	
	-- Check ancestors for the tag
	local current = instance.Parent
	while current and current ~= workspace do
		if CollectionService:HasTag(current, PHOTO_TARGET_TAG) then
			return true, current
		end
		current = current.Parent
	end
	
	return false, nil
end

-- Update crosshair appearance based on what we're looking at
local function updateCrosshairState(isTargeting)
	if isTargeting then
		-- Photo target detected - larger
		crosshairScale:set(1.3)
	else
		-- Normal state - normal size
		crosshairScale:set(1)
	end
end

-- Continuous raycast to check what we're looking at
local function checkPhotoTargetInView(deltaTime)
	local camera = workspace.CurrentCamera
	if not camera then return end
	
	local viewportSize = camera.ViewportSize
	local centerScreenPos = Vector2.new(viewportSize.X / 2, viewportSize.Y / 2)
	local unitRay = camera:ViewportPointToRay(centerScreenPos.X, centerScreenPos.Y)
	
	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	
	local excludeList = {}
	local player = Players.LocalPlayer
	if player and player.Character then
		table.insert(excludeList, player.Character)
	end
	
	local gridCubes = CollectionService:GetTagged(GRID_CUBE_TAG)
	for _, cube in ipairs(gridCubes) do
		table.insert(excludeList, cube)
	end
	
	raycastParams.FilterDescendantsInstances = excludeList
	
	local raycastResult = workspace:Raycast(
		unitRay.Origin,
		unitRay.Direction * CAMERA_CONFIG.RaycastMaxDistance,
		raycastParams
	)
	
	local hitPhotoTarget = false
	local hitTargetInstance = nil
	if raycastResult then
		hitPhotoTarget, hitTargetInstance = hasPhotoTargetTag(raycastResult.Instance)
	end
	
	local wasLooking = isLookingAtPhotoTarget:get()
	local dt = deltaTime or 0.016
	
	if hitPhotoTarget then
		-- Check if we're looking at a different target than before
		if hitTargetInstance ~= currentTargetInstance then
			-- Reset progress when switching to a different target
			gazeProgress:set(0)
			currentTargetInstance = hitTargetInstance
		end
		
		-- Switch to targeting mode
		if not wasLooking then
			isLookingAtPhotoTarget:set(true)
			updateCrosshairState(true)
		end
		
		-- Increase gaze progress while looking at target
		local currentProgress = gazeProgress:get()
		local newProgress = math.min(1, currentProgress + (dt / GAZE_FILL_TIME))
		gazeProgress:set(newProgress)
	else
		-- Immediately switch off when not looking at target
		if wasLooking then
			isLookingAtPhotoTarget:set(false)
			updateCrosshairState(false)
			gazeProgress:set(0)
			currentTargetInstance = nil
		end
	end
end

local function lockFocusOnTarget()
	local raycastResult, unitRay = performFocusRaycast()
	
	local rayOrigin = unitRay.Origin
	local rayEnd = rayOrigin + unitRay.Direction * CAMERA_CONFIG.RaycastMaxDistance
	
	if raycastResult then
		local hitPart = raycastResult.Instance
		local hitPosition = raycastResult.Position
		
		-- Check if the hit object or its ancestors have the "entity" tag
		local hasTag, taggedEntity = hasEntityTag(hitPart)
		
		if hasTag then
			local entityDistance = (hitPosition - rayOrigin).Magnitude
			
			-- Update target object info using the tagged entity
			if taggedEntity then
				targetObjectName:set(taggedEntity.Name)
				targetObjectClass:set(taggedEntity.ClassName)
			else
				targetObjectName:set(hitPart.Name)
				targetObjectClass:set(hitPart.ClassName)
			end
			
			targetObjectDistance:set(math.floor(entityDistance * 10) / 10)
			
			-- Draw debug gizmos - GREEN for valid entity hit
			drawDebugArrow(rayOrigin, hitPosition, CAMERA_CONFIG.DebugLineColor, CAMERA_CONFIG.DebugLineDuration)
			drawDebugSphere(hitPosition, CAMERA_CONFIG.DebugLineColor, CAMERA_CONFIG.DebugHitPointSize, CAMERA_CONFIG.DebugLineDuration, "ENTITY")
			
			print(string.format("[CameraEffectController] Entity detected: %s (%.1fm)", 
				targetObjectName:get(), entityDistance))
		else
			-- Hit something but it doesn't have the entity tag
			targetObjectName:set("---")
			targetObjectClass:set("---")
			targetObjectDistance:set(0)
			
			-- Draw debug gizmos - YELLOW for hit without tag
			drawDebugArrow(rayOrigin, hitPosition, CAMERA_CONFIG.DebugLineNoTagColor, CAMERA_CONFIG.DebugLineDuration)
			drawDebugSphere(hitPosition, CAMERA_CONFIG.DebugLineNoTagColor, CAMERA_CONFIG.DebugHitPointSize, CAMERA_CONFIG.DebugLineDuration, "NO TAG")
			
			print(string.format("[CameraEffectController] Hit object '%s' does not have '%s' tag", hitPart.Name, ENTITY_TAG))
		end
	else
		-- No hit
		-- Draw debug gizmos - red line to max distance
		drawDebugRay(rayOrigin, rayEnd, CAMERA_CONFIG.DebugLineMissColor, CAMERA_CONFIG.DebugLineDuration)
		drawDebugBox(rayEnd, Vector3.new(0.5, 0.5, 0.5), CAMERA_CONFIG.DebugLineMissColor, CAMERA_CONFIG.DebugLineDuration)
		
		targetObjectName:set("---")
		targetObjectClass:set("---")
		targetObjectDistance:set(0)
		print("[CameraEffectController] No object hit by raycast")
	end
end

-- === CAMERA CONTROLS ===

local function initializeCameraControls(self)
	-- Mouse scroll for zoom (optional feature)
	mouse.Scrolled:Connect(function(scrollAmount)
		if not CAMERA_CONFIG.ControlsEnabled then return end
		cameraControlState.targetZoom = math.clamp(
			cameraControlState.targetZoom - scrollAmount * CAMERA_CONFIG.ZoomSpeed,
			CAMERA_CONFIG.MinZoom,
			CAMERA_CONFIG.MaxZoom
		)
	end)
	
	-- Left mouse click to detect and apply blur to target entity
	mouse.LeftDown:Connect(function()
		lockFocusOnTarget()
	end)
	
	-- Night vision toggle (N key by default)
	keyboard.KeyDown:Connect(function(keyCode)
		if keyCode == CAMERA_CONFIG.NightVisionKey then
			isNightVisionEnabled:set(not isNightVisionEnabled:get())
			print("[CameraEffectController] Night Vision:", isNightVisionEnabled:get() and "ON" or "OFF")
		end
	end)
end

local function updateCameraControls(self, deltaTime)
	if not CAMERA_CONFIG.ControlsEnabled then return end
	
	local camera = workspace.CurrentCamera
	
	-- === ZOOM (scroll wheel) ===
	local smoothing = 1 - math.pow(1 - CAMERA_CONFIG.SmoothingFactor, deltaTime * 60)
	cameraControlState.currentZoom = cameraControlState.currentZoom + 
		(cameraControlState.targetZoom - cameraControlState.currentZoom) * smoothing
	zoomLevel:set(cameraControlState.currentZoom)
	
	-- Apply zoom via FieldOfView (optional)
	local baseFOV = 70
	camera.FieldOfView = baseFOV / cameraControlState.currentZoom
end

-- === UPDATE LOOPS ===

local function startUpdateLoops(self)
	-- Update timestamp every second
	task.spawn(function()
		while true do
			currentTime:set(os.date(CAMERA_CONFIG.TimestampFormat))
			task.wait(1)
		end
	end)
	
	-- REC indicator blink
	task.spawn(function()
		while true do
			recBlinkState:set(not recBlinkState:get())
			task.wait(1 / CAMERA_CONFIG.RecBlinkSpeed)
		end
	end)
	
	-- Simulate audio levels (random fluctuation)
	task.spawn(function()
		while true do
			audioLevelL:set(math.clamp(audioLevelL:get() + (math.random() - 0.5) * 0.2, 0.1, 0.95))
			audioLevelR:set(math.clamp(audioLevelR:get() + (math.random() - 0.5) * 0.2, 0.1, 0.95))
			task.wait(0.05)
		end
	end)
	
	-- Slowly increase memory usage
	task.spawn(function()
		while true do
			task.wait(30)  -- Every 30 seconds
			local current = memoryUsed:get()
			if current < CAMERA_CONFIG.MemoryTotal - 1 then
				memoryUsed:set(current + 1)
			end
		end
	end)
	
	-- Slowly drain battery
	task.spawn(function()
		while true do
			task.wait(120)  -- Every 2 minutes
			local current = batteryLevel:get()
			if current > 5 then
				batteryLevel:set(current - 1)
			end
		end
	end)
	
	-- Continuously check if looking at photo target (for crosshair updates)
	task.spawn(function()
		local dt = 0.05
		while true do
			checkPhotoTargetInView(dt)
			task.wait(dt)  -- Check 20 times per second for responsive feel
		end
	end)
end

-- === KNIT LIFECYCLE ===

function CameraEffectController:KnitInit()
	self.screenGui = nil
	self.effectTransparency = nil
	self.mouse = mouse
	self.keyboard = keyboard
	self.cameraControlConnection = nil
end

function CameraEffectController:KnitStart()
	-- Create UI
	createCameraEffectUI(self)
	
	-- Start update loops
	startUpdateLoops(self)
	
	-- Hide mouse cursor
	UserInputService.MouseIconEnabled = false
	
	-- Initialize camera controls (zoom only, camera uses default Roblox behavior)
	if CAMERA_CONFIG.ControlsEnabled then
		initializeCameraControls(self)
		
		-- Start camera control update loop for zoom
		self.cameraControlConnection = RunService.RenderStepped:Connect(function(deltaTime)
			updateCameraControls(self, deltaTime)
		end)
	end
	
	print("[CameraEffectController] Initialized with camera effect GUI")
end

-- === PUBLIC METHODS ===

function CameraEffectController:Show()
	isEffectVisible:set(true)
	if self.effectTransparency then
		self.effectTransparency:set(0)
	end
end

function CameraEffectController:Hide()
	if self.effectTransparency then
		self.effectTransparency:set(1)
	end
	task.delay(0.3, function()
		isEffectVisible:set(false)
	end)
end

function CameraEffectController:Toggle()
	if isEffectVisible:get() then
		self:Hide()
	else
		self:Show()
	end
end

function CameraEffectController:IsVisible()
	return isEffectVisible:get()
end

function CameraEffectController:SetBatteryLevel(level)
	batteryLevel:set(math.clamp(level, 0, 100))
end

function CameraEffectController:SetZoomLevel(zoom)
	zoomLevel:set(math.clamp(zoom, 1, 4))
end

function CameraEffectController:SetMemoryUsed(gb)
	memoryUsed:set(math.clamp(gb, 0, CAMERA_CONFIG.MemoryTotal))
end

function CameraEffectController:IsCursorLocked()
	return self.cursorLocked
end

function CameraEffectController:LockCursor()
	lockAndHideCursor()
	self.cursorLocked = true
end

function CameraEffectController:UnlockCursor()
	unlockAndShowCursor()
	self.cursorLocked = false
end

function CameraEffectController:GetMouse()
	return self.mouse
end

function CameraEffectController:GetKeyboard()
	return self.keyboard
end

function CameraEffectController:EnableZoom()
	CAMERA_CONFIG.ControlsEnabled = true
end

function CameraEffectController:DisableZoom()
	CAMERA_CONFIG.ControlsEnabled = false
end

function CameraEffectController:HideCursor()
	UserInputService.MouseIconEnabled = false
end

function CameraEffectController:ShowCursor()
	UserInputService.MouseIconEnabled = true
end

-- Night Vision Controls
function CameraEffectController:ToggleNightVision()
	isNightVisionEnabled:set(not isNightVisionEnabled:get())
	return isNightVisionEnabled:get()
end

function CameraEffectController:EnableNightVision()
	isNightVisionEnabled:set(true)
end

function CameraEffectController:DisableNightVision()
	isNightVisionEnabled:set(false)
end

function CameraEffectController:IsNightVisionEnabled()
	return isNightVisionEnabled:get()
end

-- Debug Gizmo Controls
function CameraEffectController:EnableDebugGizmos()
	CAMERA_CONFIG.DebugGizmosEnabled = true
	print("[CameraEffectController] Debug gizmos ENABLED")
end

function CameraEffectController:DisableDebugGizmos()
	CAMERA_CONFIG.DebugGizmosEnabled = false
	-- Clear existing gizmos using imgizmo
	if gizmoInitialized then
		Gizmo.DoCleaning()
	end
	print("[CameraEffectController] Debug gizmos DISABLED")
end

function CameraEffectController:ToggleDebugGizmos()
	if CAMERA_CONFIG.DebugGizmosEnabled then
		self:DisableDebugGizmos()
	else
		self:EnableDebugGizmos()
	end
	return CAMERA_CONFIG.DebugGizmosEnabled
end

function CameraEffectController:AreDebugGizmosEnabled()
	return CAMERA_CONFIG.DebugGizmosEnabled
end

function CameraEffectController:ClearDebugGizmos()
	if gizmoInitialized then
		Gizmo.DoCleaning()
	end
end

return CameraEffectController
