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

-- Entity tag for focus detection
local ENTITY_TAG = "entity"
local GRID_CUBE_TAG = "gridCube"

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
	FocusDistanceEnabled = true,
	
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
	
	-- Depth of Field
	DepthOfFieldEnabled = true,
	DOFInFocusRadius = 0,        -- How much area is in focus (studs) - 0 = very tight focus, more blur
	DOFNearIntensity = 0.5,      -- Blur intensity for near objects (0-1)
	DOFFarIntensity = 1,         -- Blur intensity for far objects (0-1) - MAX for entity blur
	DOFSmoothingSpeed = 12,      -- How fast focus adjusts
	DOFMaxDistance = 2000,       -- Max raycast distance
	DOFDefaultDistance = 100,    -- Default focus distance if nothing hit
	
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
local focusDistance = Value(2.5)
local zoomLevel = Value(CAMERA_CONFIG.ZoomLevel)
local memoryUsed = Value(CAMERA_CONFIG.MemoryUsed)
local isNightVisionEnabled = Value(false)

-- Target object info (from raycast)
local targetObjectName = Value("---")
local targetObjectClass = Value("---")
local targetObjectDistance = Value(0)
local isFocusLocked = Value(false)

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
	local borderThickness = 90
	local cornerSize = 40
	local margin = 350
	
	return New "Frame" {
		Name = "FilmBorder",
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundTransparency = 1,
		Parent = parent,
		
		[Children] = {
			-- Top border
			New "Frame" {
				Size = UDim2.new(1, 0, 0, borderThickness),
				Position = UDim2.new(0, 0, 0, 0),
				BackgroundColor3 = Color3.fromRGB(0, 0, 0),
				BackgroundTransparency = 0.3,
				BorderSizePixel = 0,
			},
			-- Bottom border
			New "Frame" {
				Size = UDim2.new(1, 0, 0, borderThickness),
				Position = UDim2.new(0, 0, 1, -borderThickness),
				BackgroundColor3 = Color3.fromRGB(0, 0, 0),
				BackgroundTransparency = 0.3,
				BorderSizePixel = 0,
			},
			-- Corner brackets (top-left)
			New "Frame" {
				Size = UDim2.new(0, cornerSize, 0, 3),
				Position = UDim2.new(0, margin, 0, borderThickness + 30),
				BackgroundColor3 = CAMERA_CONFIG.OverlayColor,
				BackgroundTransparency = animatedTransparency,
				BorderSizePixel = 0,
			},
			New "Frame" {
				Size = UDim2.new(0, 3, 0, cornerSize),
				Position = UDim2.new(0, margin, 0, borderThickness + 30),
				BackgroundColor3 = CAMERA_CONFIG.OverlayColor,
				BackgroundTransparency = animatedTransparency,
				BorderSizePixel = 0,
			},
			-- Corner brackets (top-right)
			New "Frame" {
				Size = UDim2.new(0, cornerSize, 0, 3),
				Position = UDim2.new(1, -margin - cornerSize, 0, borderThickness + 30),
				BackgroundColor3 = CAMERA_CONFIG.OverlayColor,
				BackgroundTransparency = animatedTransparency,
				BorderSizePixel = 0,
			},
			New "Frame" {
				Size = UDim2.new(0, 3, 0, cornerSize),
				Position = UDim2.new(1, -margin - 3, 0, borderThickness + 30),
				BackgroundColor3 = CAMERA_CONFIG.OverlayColor,
				BackgroundTransparency = animatedTransparency,
				BorderSizePixel = 0,
			},
			-- Corner brackets (bottom-left)
			New "Frame" {
				Size = UDim2.new(0, cornerSize, 0, 3),
				Position = UDim2.new(0, margin, 1, -borderThickness - 33),
				BackgroundColor3 = CAMERA_CONFIG.OverlayColor,
				BackgroundTransparency = animatedTransparency,
				BorderSizePixel = 0,
			},
			New "Frame" {
				Size = UDim2.new(0, 3, 0, cornerSize),
				Position = UDim2.new(0, margin, 1, -borderThickness - 30 - cornerSize),
				BackgroundColor3 = CAMERA_CONFIG.OverlayColor,
				BackgroundTransparency = animatedTransparency,
				BorderSizePixel = 0,
			},
			-- Corner brackets (bottom-right)
			New "Frame" {
				Size = UDim2.new(0, cornerSize, 0, 3),
				Position = UDim2.new(1, -margin - cornerSize, 1, -borderThickness - 33),
				BackgroundColor3 = CAMERA_CONFIG.OverlayColor,
				BackgroundTransparency = animatedTransparency,
				BorderSizePixel = 0,
			},
			New "Frame" {
				Size = UDim2.new(0, 3, 0, cornerSize),
				Position = UDim2.new(1, -margin - 3, 1, -borderThickness - 30 - cornerSize),
				BackgroundColor3 = CAMERA_CONFIG.OverlayColor,
				BackgroundTransparency = animatedTransparency,
				BorderSizePixel = 0,
			},
		},
	}
end

local function createCrosshair(parent, animatedTransparency)
	local crossSize = 32
	local gapSize = 12
	local thickness = 3
	
	return New "Frame" {
		Name = "Crosshair",
		Size = UDim2.new(0, 100, 0, 100),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		Parent = parent,
		
		[Children] = {
			-- Center dot
			New "Frame" {
				Size = UDim2.new(0, 6, 0, 6),
				Position = UDim2.new(0.5, 0, 0.5, 0),
				AnchorPoint = Vector2.new(0.5, 0.5),
				BackgroundColor3 = CAMERA_CONFIG.AccentColor,
				BackgroundTransparency = animatedTransparency,
				BorderSizePixel = 0,
				[Children] = {
					New "UICorner" { CornerRadius = UDim.new(1, 0) },
				},
			},
			-- Top line
			New "Frame" {
				Size = UDim2.new(0, thickness, 0, crossSize),
				Position = UDim2.new(0.5, 0, 0.5, -gapSize - crossSize),
				AnchorPoint = Vector2.new(0.5, 0),
				BackgroundColor3 = CAMERA_CONFIG.OverlayColor,
				BackgroundTransparency = animatedTransparency,
				BorderSizePixel = 0,
			},
			-- Bottom line
			New "Frame" {
				Size = UDim2.new(0, thickness, 0, crossSize),
				Position = UDim2.new(0.5, 0, 0.5, gapSize),
				AnchorPoint = Vector2.new(0.5, 0),
				BackgroundColor3 = CAMERA_CONFIG.OverlayColor,
				BackgroundTransparency = animatedTransparency,
				BorderSizePixel = 0,
			},
			-- Left line
			New "Frame" {
				Size = UDim2.new(0, crossSize, 0, thickness),
				Position = UDim2.new(0.5, -gapSize - crossSize, 0.5, 0),
				AnchorPoint = Vector2.new(0, 0.5),
				BackgroundColor3 = CAMERA_CONFIG.OverlayColor,
				BackgroundTransparency = animatedTransparency,
				BorderSizePixel = 0,
			},
			-- Right line
			New "Frame" {
				Size = UDim2.new(0, crossSize, 0, thickness),
				Position = UDim2.new(0.5, gapSize, 0.5, 0),
				AnchorPoint = Vector2.new(0, 0.5),
				BackgroundColor3 = CAMERA_CONFIG.OverlayColor,
				BackgroundTransparency = animatedTransparency,
				BorderSizePixel = 0,
			},
			-- Corner ticks (subtle)
			New "Frame" {
				Size = UDim2.new(0, 8, 0, 1),
				Position = UDim2.new(0.5, -35, 0.5, -35),
				AnchorPoint = Vector2.new(0.5, 0.5),
				Rotation = 45,
				BackgroundColor3 = CAMERA_CONFIG.OverlayColor,
				BackgroundTransparency = Computed(function() return 0.5 + animatedTransparency:get() * 0.5 end),
				BorderSizePixel = 0,
			},
			New "Frame" {
				Size = UDim2.new(0, 8, 0, 1),
				Position = UDim2.new(0.5, 35, 0.5, -35),
				AnchorPoint = Vector2.new(0.5, 0.5),
				Rotation = -45,
				BackgroundColor3 = CAMERA_CONFIG.OverlayColor,
				BackgroundTransparency = Computed(function() return 0.5 + animatedTransparency:get() * 0.5 end),
				BorderSizePixel = 0,
			},
			New "Frame" {
				Size = UDim2.new(0, 8, 0, 1),
				Position = UDim2.new(0.5, -35, 0.5, 35),
				AnchorPoint = Vector2.new(0.5, 0.5),
				Rotation = -45,
				BackgroundColor3 = CAMERA_CONFIG.OverlayColor,
				BackgroundTransparency = Computed(function() return 0.5 + animatedTransparency:get() * 0.5 end),
				BorderSizePixel = 0,
			},
			New "Frame" {
				Size = UDim2.new(0, 8, 0, 1),
				Position = UDim2.new(0.5, 35, 0.5, 35),
				AnchorPoint = Vector2.new(0.5, 0.5),
				Rotation = 45,
				BackgroundColor3 = CAMERA_CONFIG.OverlayColor,
				BackgroundTransparency = Computed(function() return 0.5 + animatedTransparency:get() * 0.5 end),
				BorderSizePixel = 0,
			},
		},
	}
end

local function createAudioLevelMeter(parent, animatedTransparency, side, levelValue)
	local meterHeight = 150
	local meterWidth = 12
	local segments = 12
	local segmentHeight = meterHeight / segments
	local xPos = side == "L" and UDim2.new(1, -400, 0.5, 0) or UDim2.new(1, -380, 0.5, 0)
	
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
			Size = UDim2.new(0, meterWidth, 0, segmentHeight - 2),
			Position = UDim2.new(0, 0, 1, -(i * segmentHeight)),
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
		Size = UDim2.new(0, meterWidth, 0, meterHeight),
		Position = xPos,
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
				Size = UDim2.new(0, 24, 0, 20),
				Position = UDim2.new(0.5, 0, 1, 8),
				AnchorPoint = Vector2.new(0.5, 0),
				BackgroundTransparency = 1,
				Font = Enum.Font.RobotoMono,
				TextSize = 16,
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
		Size = UDim2.new(0, 120, 0, 40),
		Position = UDim2.new(0, 360, 0, 180),
		BackgroundTransparency = 1,
		Parent = parent,
		
		[Children] = {
			-- REC dot
			New "Frame" {
				Name = "RecDot",
				Size = UDim2.new(0, 20, 0, 20),
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
				},
			},
			-- REC text
			New "TextLabel" {
				Name = "RecText",
				Size = UDim2.new(0, 70, 1, 0),
				Position = UDim2.new(0, 28, 0, 0),
				BackgroundTransparency = 1,
				Font = Enum.Font.RobotoMono,
				TextSize = 28,
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
		Size = UDim2.new(0, 350, 0, 35),
		Position = UDim2.new(1, -360, 0, 180),
		AnchorPoint = Vector2.new(1, 0),
		BackgroundTransparency = 1,
		Font = Enum.Font.RobotoMono,
		TextSize = 26,
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
		Size = UDim2.new(0, 250, 0, 110),
		Position = UDim2.new(1, -360, 0, 220),
		AnchorPoint = Vector2.new(1, 0),
		BackgroundTransparency = 1,
		Parent = parent,
		
		[Children] = {
			New "TextLabel" {
				Size = UDim2.new(1, 0, 0, 24),
				Position = UDim2.new(0, 0, 0, 0),
				BackgroundTransparency = 1,
				Font = Enum.Font.RobotoMono,
				TextSize = 20,
				TextColor3 = CAMERA_CONFIG.OverlayColor,
				TextTransparency = animatedTransparency,
				TextXAlignment = Enum.TextXAlignment.Right,
				Text = CAMERA_CONFIG.Aperture .. "  ISO " .. CAMERA_CONFIG.ISO,
			},
			New "TextLabel" {
				Size = UDim2.new(1, 0, 0, 24),
				Position = UDim2.new(0, 0, 0, 28),
				BackgroundTransparency = 1,
				Font = Enum.Font.RobotoMono,
				TextSize = 18,
				TextColor3 = CAMERA_CONFIG.OverlayColor,
				TextTransparency = Computed(function() return 0.3 + animatedTransparency:get() * 0.7 end),
				TextXAlignment = Enum.TextXAlignment.Right,
				Text = CAMERA_CONFIG.ShutterSpeed .. "  " .. CAMERA_CONFIG.FocalLength,
			},
			-- White balance
			New "TextLabel" {
				Size = UDim2.new(1, 0, 0, 22),
				Position = UDim2.new(0, 0, 0, 58),
				BackgroundTransparency = 1,
				Font = Enum.Font.RobotoMono,
				TextSize = 16,
				TextColor3 = CAMERA_CONFIG.AccentColor,
				TextTransparency = animatedTransparency,
				TextXAlignment = Enum.TextXAlignment.Right,
				Text = "AWB  5600K",
			},
		},
	}
end

local function createFocusDistance(parent, animatedTransparency)
	return New "Frame" {
		Name = "FocusDistance",
		Size = UDim2.new(0, 150, 0, 70),
		Position = UDim2.new(0.5, 0, 1, -240),
		AnchorPoint = Vector2.new(0.5, 1),
		BackgroundTransparency = 1,
		Parent = parent,
		
		[Children] = {
			New "TextLabel" {
				Size = UDim2.new(1, 0, 0, 20),
				Position = UDim2.new(0, 0, 0, 0),
				BackgroundTransparency = 1,
				Font = Enum.Font.RobotoMono,
				TextSize = 16,
				TextColor3 = Computed(function()
					return isFocusLocked:get() and Color3.fromRGB(100, 255, 100) or CAMERA_CONFIG.OverlayColor
				end),
				TextTransparency = Computed(function() return 0.4 + animatedTransparency:get() * 0.6 end),
				Text = Computed(function()
					return isFocusLocked:get() and "◉ FOCUS LOCKED" or "○ FOCUS"
				end),
			},
			New "TextLabel" {
				Size = UDim2.new(1, 0, 0, 30),
				Position = UDim2.new(0, 0, 0, 22),
				BackgroundTransparency = 1,
				Font = Enum.Font.RobotoMono,
				TextSize = 24,
				TextColor3 = CAMERA_CONFIG.AccentColor,
				TextTransparency = animatedTransparency,
				Text = Computed(function()
					return string.format("%.1fm", focusDistance:get())
				end),
			},
			-- Click hint
			New "TextLabel" {
				Size = UDim2.new(1, 0, 0, 16),
				Position = UDim2.new(0, 0, 0, 52),
				BackgroundTransparency = 1,
				Font = Enum.Font.RobotoMono,
				TextSize = 12,
				TextColor3 = CAMERA_CONFIG.OverlayColor,
				TextTransparency = Computed(function() return 0.5 + animatedTransparency:get() * 0.5 end),
				Text = "[LMB] to focus",
			},
		},
	}
end

local function createZoomIndicator(parent, animatedTransparency)
	local barWidth = 180
	
	return New "Frame" {
		Name = "ZoomIndicator",
		Size = UDim2.new(0, barWidth, 0, 40),
		Position = UDim2.new(0, 350, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		BackgroundTransparency = 1,
		Parent = parent,
		
		[Children] = {
			-- Label
			New "TextLabel" {
				Size = UDim2.new(0, 60, 0, 20),
				Position = UDim2.new(0, 0, 0, 0),
				BackgroundTransparency = 1,
				Font = Enum.Font.RobotoMono,
				TextSize = 16,
				TextColor3 = CAMERA_CONFIG.OverlayColor,
				TextTransparency = Computed(function() return 0.4 + animatedTransparency:get() * 0.6 end),
				TextXAlignment = Enum.TextXAlignment.Left,
				Text = "ZOOM",
			},
			-- Bar background
			New "Frame" {
				Size = UDim2.new(0, barWidth, 0, 6),
				Position = UDim2.new(0, 0, 0, 24),
				BackgroundColor3 = Color3.fromRGB(60, 60, 60),
				BackgroundTransparency = 0.5,
				BorderSizePixel = 0,
				
				[Children] = {
					New "UICorner" { CornerRadius = UDim.new(0, 3) },
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
							New "UICorner" { CornerRadius = UDim.new(0, 3) },
						},
					},
				},
			},
			-- Zoom value
			New "TextLabel" {
				Size = UDim2.new(0, 60, 0, 20),
				Position = UDim2.new(0, barWidth + 15, 0, 20),
				AnchorPoint = Vector2.new(0, 0.5),
				BackgroundTransparency = 1,
				Font = Enum.Font.RobotoMono,
				TextSize = 18,
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
		Size = UDim2.new(0, 150, 0, 55),
		Position = UDim2.new(1, -360, 1, -180),
		AnchorPoint = Vector2.new(1, 1),
		BackgroundTransparency = 1,
		Parent = parent,
		
		[Children] = {
			-- SD card icon (simplified)
			New "Frame" {
				Size = UDim2.new(0, 22, 0, 28),
				Position = UDim2.new(0, 0, 0, 0),
				BackgroundColor3 = CAMERA_CONFIG.OverlayColor,
				BackgroundTransparency = animatedTransparency,
				BorderSizePixel = 0,
				[Children] = {
					New "UICorner" { CornerRadius = UDim.new(0, 4) },
					-- Notch
					New "Frame" {
						Size = UDim2.new(0, 8, 0, 8),
						Position = UDim2.new(1, -8, 0, 0),
						BackgroundColor3 = Color3.fromRGB(30, 30, 30),
						BorderSizePixel = 0,
					},
				},
			},
			-- Memory text
			New "TextLabel" {
				Size = UDim2.new(0, 120, 0, 24),
				Position = UDim2.new(0, 30, 0, 0),
				BackgroundTransparency = 1,
				Font = Enum.Font.RobotoMono,
				TextSize = 18,
				TextColor3 = CAMERA_CONFIG.OverlayColor,
				TextTransparency = animatedTransparency,
				TextXAlignment = Enum.TextXAlignment.Left,
				Text = Computed(function()
					return string.format("%dGB/%dGB", memoryUsed:get(), CAMERA_CONFIG.MemoryTotal)
				end),
			},
			-- Remaining time
			New "TextLabel" {
				Size = UDim2.new(0, 120, 0, 20),
				Position = UDim2.new(0, 30, 0, 26),
				BackgroundTransparency = 1,
				Font = Enum.Font.RobotoMono,
				TextSize = 16,
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
		Size = UDim2.new(0, 130, 0, 32),
		Position = UDim2.new(1, -360, 1, -240),
		AnchorPoint = Vector2.new(1, 1),
		BackgroundTransparency = 1,
		Parent = parent,
		
		[Children] = {
			-- Battery outline
			New "Frame" {
				Name = "BatteryOutline",
				Size = UDim2.new(0, 50, 0, 26),
				Position = UDim2.new(0, 0, 0.5, 0),
				AnchorPoint = Vector2.new(0, 0.5),
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				
				[Children] = {
					New "UIStroke" {
						Color = CAMERA_CONFIG.OverlayColor,
						Thickness = 3,
						Transparency = animatedTransparency,
					},
					New "UICorner" {
						CornerRadius = UDim.new(0, 4),
					},
					-- Battery fill
					New "Frame" {
						Name = "BatteryFill",
						Size = Computed(function()
							return UDim2.new(batteryLevel:get() / 100, -6, 1, -6)
						end),
						Position = UDim2.new(0, 3, 0, 3),
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
								CornerRadius = UDim.new(0, 2),
							},
						},
					},
				},
			},
			-- Battery tip
			New "Frame" {
				Name = "BatteryTip",
				Size = UDim2.new(0, 5, 0, 14),
				Position = UDim2.new(0, 53, 0.5, 0),
				AnchorPoint = Vector2.new(0, 0.5),
				BackgroundColor3 = CAMERA_CONFIG.OverlayColor,
				BackgroundTransparency = animatedTransparency,
				BorderSizePixel = 0,
				
				[Children] = {
					New "UICorner" {
						CornerRadius = UDim.new(0, 2),
					},
				},
			},
			-- Percentage text
			New "TextLabel" {
				Name = "BatteryText",
				Size = UDim2.new(0, 55, 1, 0),
				Position = UDim2.new(0, 65, 0, 0),
				BackgroundTransparency = 1,
				Font = Enum.Font.RobotoMono,
				TextSize = 20,
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
	local screenHeight = 1080
	local lineCount = math.floor(screenHeight / CAMERA_CONFIG.ScanLineSpacing)
	
	for i = 1, math.min(lineCount, 200) do
		table.insert(lines, New "Frame" {
			Size = UDim2.new(1, 0, 0, 1),
			Position = UDim2.new(0, 0, 0, (i - 1) * CAMERA_CONFIG.ScanLineSpacing),
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
		Size = UDim2.new(0, 280, 0, 200),
		Position = UDim2.new(0, 360, 1, -180),
		AnchorPoint = Vector2.new(0, 1),
		BackgroundTransparency = 1,
		Parent = parent,
		
		[Children] = {
			-- Camera model
			New "TextLabel" {
				Size = UDim2.new(1, 0, 0, 28),
				Position = UDim2.new(0, 0, 0, 0),
				BackgroundTransparency = 1,
				Font = Enum.Font.RobotoMono,
				TextSize = 22,
				TextColor3 = CAMERA_CONFIG.OverlayColor,
				TextTransparency = animatedTransparency,
				TextXAlignment = Enum.TextXAlignment.Left,
				Text = "FACILITY CAM-01",
			},
			-- Resolution
			New "TextLabel" {
				Size = UDim2.new(1, 0, 0, 24),
				Position = UDim2.new(0, 0, 0, 32),
				BackgroundTransparency = 1,
				Font = Enum.Font.RobotoMono,
				TextSize = 18,
				TextColor3 = CAMERA_CONFIG.OverlayColor,
				TextTransparency = Computed(function()
					return 0.3 + animatedTransparency:get() * 0.7
				end),
				TextXAlignment = Enum.TextXAlignment.Left,
				Text = "1920x1080 30FPS",
			},
			-- Night vision indicator
			New "TextLabel" {
				Size = UDim2.new(1, 0, 0, 24),
				Position = UDim2.new(0, 0, 0, 60),
				BackgroundTransparency = 1,
				Font = Enum.Font.RobotoMono,
				TextSize = 18,
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
				Size = UDim2.new(1, 0, 0, 22),
				Position = UDim2.new(0, 0, 0, 88),
				BackgroundTransparency = 1,
				Font = Enum.Font.RobotoMono,
				TextSize = 16,
				TextColor3 = CAMERA_CONFIG.AccentColor,
				TextTransparency = animatedTransparency,
				TextXAlignment = Enum.TextXAlignment.Left,
				Text = "⟳ OIS ACTIVE",
			},
			
			-- Divider
			New "Frame" {
				Size = UDim2.new(0.9, 0, 0, 1),
				Position = UDim2.new(0, 0, 0, 118),
				BackgroundColor3 = CAMERA_CONFIG.OverlayColor,
				BackgroundTransparency = Computed(function()
					return 0.6 + animatedTransparency:get() * 0.4
				end),
				BorderSizePixel = 0,
			},
			
			-- Target label
			New "TextLabel" {
				Size = UDim2.new(1, 0, 0, 18),
				Position = UDim2.new(0, 0, 0, 125),
				BackgroundTransparency = 1,
				Font = Enum.Font.RobotoMono,
				TextSize = 14,
				TextColor3 = CAMERA_CONFIG.OverlayColor,
				TextTransparency = Computed(function()
					return 0.4 + animatedTransparency:get() * 0.6
				end),
				TextXAlignment = Enum.TextXAlignment.Left,
				Text = "TARGET:",
			},
			
			-- Target object name
			New "TextLabel" {
				Size = UDim2.new(1, 0, 0, 22),
				Position = UDim2.new(0, 0, 0, 143),
				BackgroundTransparency = 1,
				Font = Enum.Font.RobotoMono,
				TextSize = 18,
				TextColor3 = CAMERA_CONFIG.AccentColor,
				TextTransparency = animatedTransparency,
				TextXAlignment = Enum.TextXAlignment.Left,
				Text = Computed(function()
					return targetObjectName:get()
				end),
			},
			
			-- Target object class and distance
			New "TextLabel" {
				Size = UDim2.new(1, 0, 0, 18),
				Position = UDim2.new(0, 0, 0, 167),
				BackgroundTransparency = 1,
				Font = Enum.Font.RobotoMono,
				TextSize = 14,
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
					
					-- Focus distance
					CAMERA_CONFIG.FocusDistanceEnabled and createFocusDistance(nil, animatedTransparency) or nil,
					
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
				},
			},
		},
	}
	
	self.screenGui = screenGui
	return screenGui
end

-- === DEPTH OF FIELD ===

local depthOfFieldEffect = nil
local currentFocusDistance = CAMERA_CONFIG.DOFDefaultDistance
local targetFocusDistance = CAMERA_CONFIG.DOFDefaultDistance

-- === ENTITY BLUR EFFECT ===
-- Creates a visual blur effect directly on the entity using transparent shells and particles

local currentBlurredEntity = nil
local entityBlurParts = {}

local function clearEntityBlur()
	-- Remove all blur effect parts
	for _, part in ipairs(entityBlurParts) do
		if part and part.Parent then
			part:Destroy()
		end
	end
	entityBlurParts = {}
	currentBlurredEntity = nil
end

local function applyEntityBlur(entity)
	-- Clear any existing blur
	clearEntityBlur()
	
	if not entity then return end
	
	currentBlurredEntity = entity
	
	-- Find all BaseParts in the entity
	local parts = {}
	if entity:IsA("BasePart") then
		table.insert(parts, entity)
	end
	for _, descendant in ipairs(entity:GetDescendants()) do
		if descendant:IsA("BasePart") then
			table.insert(parts, descendant)
		end
	end
	
	-- Create blur shells around each part
	for _, part in ipairs(parts) do
		-- Create multiple offset transparent copies for blur effect
		local offsets = {
			Vector3.new(0.15, 0, 0),
			Vector3.new(-0.15, 0, 0),
			Vector3.new(0, 0.15, 0),
			Vector3.new(0, -0.15, 0),
			Vector3.new(0, 0, 0.15),
			Vector3.new(0, 0, -0.15),
			Vector3.new(0.1, 0.1, 0),
			Vector3.new(-0.1, -0.1, 0),
		}
		
		for i, offset in ipairs(offsets) do
			local blurPart = Instance.new("Part")
			blurPart.Name = "BlurShell_" .. i
			blurPart.Size = part.Size * 1.02  -- Slightly larger
			blurPart.CFrame = part.CFrame * CFrame.new(offset)
			blurPart.Color = part.Color
			blurPart.Material = Enum.Material.Glass
			blurPart.Transparency = 0.7 + (i * 0.03)  -- Varying transparency
			blurPart.Anchored = true
			blurPart.CanCollide = false
			blurPart.CanQuery = false
			blurPart.CanTouch = false
			blurPart.CastShadow = false
			blurPart.Parent = workspace
			
			table.insert(entityBlurParts, blurPart)
		end
		
		-- Add a foggy particle effect
		local attachment = Instance.new("Attachment")
		attachment.Name = "BlurAttachment"
		attachment.Parent = part
		table.insert(entityBlurParts, attachment)
		
		local particles = Instance.new("ParticleEmitter")
		particles.Name = "BlurParticles"
		particles.Color = ColorSequence.new(Color3.fromRGB(50, 50, 50))
		particles.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, part.Size.Magnitude * 0.3),
			NumberSequenceKeypoint.new(1, part.Size.Magnitude * 0.5),
		})
		particles.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.6),
			NumberSequenceKeypoint.new(0.5, 0.75),
			NumberSequenceKeypoint.new(1, 1),
		})
		particles.Lifetime = NumberRange.new(0.3, 0.6)
		particles.Rate = 30
		particles.Speed = NumberRange.new(0.5, 1)
		particles.SpreadAngle = Vector2.new(180, 180)
		particles.LockedToPart = true
		particles.Parent = attachment
		table.insert(entityBlurParts, particles)
		
		-- Make the original part slightly transparent
		if not part:GetAttribute("OriginalTransparency") then
			part:SetAttribute("OriginalTransparency", part.Transparency)
		end
		part.Transparency = math.min(part.Transparency + 0.3, 0.9)
	end
	
	print(string.format("[CameraEffectController] Applied blur effect to entity with %d blur parts", #entityBlurParts))
end

local function restoreEntityTransparency(entity)
	if not entity then return end
	
	local parts = {}
	if entity:IsA("BasePart") then
		table.insert(parts, entity)
	end
	for _, descendant in ipairs(entity:GetDescendants()) do
		if descendant:IsA("BasePart") then
			table.insert(parts, descendant)
		end
	end
	
	for _, part in ipairs(parts) do
		local originalTransparency = part:GetAttribute("OriginalTransparency")
		if originalTransparency then
			part.Transparency = originalTransparency
			part:SetAttribute("OriginalTransparency", nil)
		end
	end
end

local function createDepthOfFieldEffect()
	-- Check if DOF effect already exists in Lighting
	depthOfFieldEffect = Lighting:FindFirstChild("CameraDepthOfField")
	
	if not depthOfFieldEffect then
		depthOfFieldEffect = Instance.new("DepthOfFieldEffect")
		depthOfFieldEffect.Name = "CameraDepthOfField"
		depthOfFieldEffect.Parent = Lighting
	end
	
	-- Always update the properties
	depthOfFieldEffect.FarIntensity = CAMERA_CONFIG.DOFFarIntensity
	depthOfFieldEffect.NearIntensity = CAMERA_CONFIG.DOFNearIntensity
	depthOfFieldEffect.InFocusRadius = CAMERA_CONFIG.DOFInFocusRadius
	depthOfFieldEffect.FocusDistance = CAMERA_CONFIG.DOFDefaultDistance
	depthOfFieldEffect.Enabled = false  -- Start disabled, only enable when clicking on entity
	
	print("[CameraEffectController] DOF Effect created/updated - starts DISABLED until entity is clicked")
	
	return depthOfFieldEffect
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
		unitRay.Direction * CAMERA_CONFIG.DOFMaxDistance,
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

local function lockFocusOnTarget()
	local raycastResult, unitRay = performFocusRaycast()
	
	local rayOrigin = unitRay.Origin
	local rayEnd = rayOrigin + unitRay.Direction * CAMERA_CONFIG.DOFMaxDistance
	
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
			isFocusLocked:set(true)
			
			-- Apply blur effect directly to the entity
			local entityToBlur = taggedEntity or hitPart.Parent
			applyEntityBlur(entityToBlur)
			
			-- Draw debug gizmos - GREEN for valid entity hit
			drawDebugArrow(rayOrigin, hitPosition, CAMERA_CONFIG.DebugLineColor, CAMERA_CONFIG.DebugLineDuration)
			drawDebugSphere(hitPosition, CAMERA_CONFIG.DebugLineColor, CAMERA_CONFIG.DebugHitPointSize, CAMERA_CONFIG.DebugLineDuration, "ENTITY")
			
			print(string.format("[CameraEffectController] Entity detected: %s (%.1fm) - BLUR APPLIED TO ENTITY", 
				targetObjectName:get(), entityDistance))
		else
			-- Hit something but it doesn't have the entity tag - clear blur
			if currentBlurredEntity then
				restoreEntityTransparency(currentBlurredEntity)
				clearEntityBlur()
			end
			
			targetObjectName:set("---")
			targetObjectClass:set("---")
			targetObjectDistance:set(0)
			isFocusLocked:set(false)
			
			-- Draw debug gizmos - YELLOW for hit without tag
			drawDebugArrow(rayOrigin, hitPosition, CAMERA_CONFIG.DebugLineNoTagColor, CAMERA_CONFIG.DebugLineDuration)
			drawDebugSphere(hitPosition, CAMERA_CONFIG.DebugLineNoTagColor, CAMERA_CONFIG.DebugHitPointSize, CAMERA_CONFIG.DebugLineDuration, "NO TAG")
			
			print(string.format("[CameraEffectController] Hit object '%s' does not have '%s' tag - blur cleared", hitPart.Name, ENTITY_TAG))
		end
	else
		-- No hit - clear blur
		if currentBlurredEntity then
			restoreEntityTransparency(currentBlurredEntity)
			clearEntityBlur()
		end
		
		-- Draw debug gizmos - red line to max distance
		drawDebugRay(rayOrigin, rayEnd, CAMERA_CONFIG.DebugLineMissColor, CAMERA_CONFIG.DebugLineDuration)
		drawDebugBox(rayEnd, Vector3.new(0.5, 0.5, 0.5), CAMERA_CONFIG.DebugLineMissColor, CAMERA_CONFIG.DebugLineDuration)
		
		targetObjectName:set("---")
		targetObjectClass:set("---")
		targetObjectDistance:set(0)
		isFocusLocked:set(false)
		print("[CameraEffectController] No object hit by raycast - blur cleared")
	end
end

local function updateDepthOfField(deltaTime)
	if not CAMERA_CONFIG.DepthOfFieldEnabled then return end
	if not depthOfFieldEffect then return end
	
	-- Smooth focus transition
	local smoothingFactor = CAMERA_CONFIG.DOFSmoothingSpeed * deltaTime
	currentFocusDistance = currentFocusDistance + (targetFocusDistance - currentFocusDistance) * math.min(smoothingFactor, 1)
	
	-- Apply to depth of field effect
	depthOfFieldEffect.FocusDistance = currentFocusDistance
	
	-- Update the focus distance display in UI
	focusDistance:set(currentFocusDistance)
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
	
	-- Left mouse click to focus on target
	mouse.LeftDown:Connect(function()
		if CAMERA_CONFIG.DepthOfFieldEnabled then
			lockFocusOnTarget()
		end
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
	
	-- Update focus distance based on camera raycast
	task.spawn(function()
		local camera = workspace.CurrentCamera
		while true do
			if camera then
				local ray = Ray.new(camera.CFrame.Position, camera.CFrame.LookVector * 100)
				local hit, hitPos = workspace:FindPartOnRay(ray)
				if hit then
					local dist = (hitPos - camera.CFrame.Position).Magnitude
					focusDistance:set(dist)
				else
					focusDistance:set(99.9)
				end
			end
			task.wait(0.1)
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
	
	-- Initialize depth of field effect
	if CAMERA_CONFIG.DepthOfFieldEnabled then
		createDepthOfFieldEffect()
	end
	
	-- Initialize camera controls (zoom only, camera uses default Roblox behavior)
	if CAMERA_CONFIG.ControlsEnabled then
		initializeCameraControls(self)
		
		-- Start camera control update loop for zoom and DOF
		self.cameraControlConnection = RunService.RenderStepped:Connect(function(deltaTime)
			updateCameraControls(self, deltaTime)
			updateDepthOfField(deltaTime)
		end)
	end
	
	print("[CameraEffectController] Initialized with camera effect GUI and DOF")
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

-- Depth of Field Controls
function CameraEffectController:EnableDepthOfField()
	CAMERA_CONFIG.DepthOfFieldEnabled = true
	if depthOfFieldEffect then
		depthOfFieldEffect.Enabled = true
	end
end

function CameraEffectController:DisableDepthOfField()
	CAMERA_CONFIG.DepthOfFieldEnabled = false
	if depthOfFieldEffect then
		depthOfFieldEffect.Enabled = false
	end
end

function CameraEffectController:ToggleDepthOfField()
	if CAMERA_CONFIG.DepthOfFieldEnabled then
		self:DisableDepthOfField()
	else
		self:EnableDepthOfField()
	end
	return CAMERA_CONFIG.DepthOfFieldEnabled
end

function CameraEffectController:IsDepthOfFieldEnabled()
	return CAMERA_CONFIG.DepthOfFieldEnabled
end

function CameraEffectController:SetDOFInFocusRadius(radius)
	CAMERA_CONFIG.DOFInFocusRadius = radius
	if depthOfFieldEffect then
		depthOfFieldEffect.InFocusRadius = radius
	end
end

function CameraEffectController:SetDOFIntensity(nearIntensity, farIntensity)
	CAMERA_CONFIG.DOFNearIntensity = nearIntensity or CAMERA_CONFIG.DOFNearIntensity
	CAMERA_CONFIG.DOFFarIntensity = farIntensity or CAMERA_CONFIG.DOFFarIntensity
	if depthOfFieldEffect then
		depthOfFieldEffect.NearIntensity = CAMERA_CONFIG.DOFNearIntensity
		depthOfFieldEffect.FarIntensity = CAMERA_CONFIG.DOFFarIntensity
	end
end

function CameraEffectController:GetCurrentFocusDistance()
	return currentFocusDistance
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
