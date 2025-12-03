--[[
	CameraUIController
	Handles all camera overlay UI elements: vignette, scan lines, REC indicator, battery, etc.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local CustomPackages = ReplicatedStorage:WaitForChild("CustomPackages")
local Knit = require(Packages.Knit)
local Fusion = require(CustomPackages:WaitForChild("FusionRoot"):WaitForChild("Fusion"))

-- Fusion imports
local New = Fusion.New
local Children = Fusion.Children
local Value = Fusion.Value
local Computed = Fusion.Computed
local Spring = Fusion.Spring

local CameraUIController = Knit.CreateController {
	Name = "CameraUIController",
	screenGui = nil,
	effectTransparency = nil,
}

-- === CONFIG ===
local UI_CONFIG = {
	-- Vignette
	VignetteEnabled = false,
	VignetteIntensity = 0.7,
	
	-- Recording indicator
	RecIndicatorEnabled = true,
	RecBlinkSpeed = 1,
	
	-- Timestamp
	TimestampEnabled = true,
	TimestampFormat = "%m/%d/%Y  %H:%M:%S",
	
	-- Scan lines
	ScanLinesEnabled = true,
	ScanLineOpacity = 0.06,
	ScanLineSpacing = 4,
	
	-- Film grain
	FilmGrainEnabled = true,
	FilmGrainOpacity = 0.04,
	
	-- Battery indicator
	BatteryEnabled = true,
	BatteryLevel = 87,
	
	-- Audio levels
	AudioLevelsEnabled = true,
	
	-- Memory card
	MemoryCardEnabled = true,
	MemoryUsed = 64,
	MemoryTotal = 128,
	
	-- Camera settings
	CameraSettingsEnabled = true,
	Aperture = "f/2.8",
	ISO = "3200",
	ShutterSpeed = "1/60",
	FocalLength = "24mm",
	
	-- Zoom indicator
	ZoomEnabled = true,
	ZoomLevel = 1.0,
	
	-- Film border (letterbox)
	FilmBorderEnabled = false,
	
	-- Corner brackets
	CornerBracketsEnabled = true,
	
	-- Layout margins (distance from screen edge to content)
	MarginX = 0.14,           -- Horizontal margin
	MarginY = 0.055,          -- Vertical margin
	ElementSpacing = 0.008,   -- Spacing between elements
	
	-- Colors
	OverlayColor = Color3.fromRGB(255, 255, 255),
	AccentColor = Color3.fromRGB(200, 200, 200),
	RecColor = Color3.fromRGB(255, 50, 50),
	WarningColor = Color3.fromRGB(255, 200, 50),
	
	-- Night Vision
	NightVisionTint = Color3.fromRGB(0, 255, 0),
	NightVisionAccent = Color3.fromRGB(150, 255, 150),
}

-- === STATE ===
local isEffectVisible = Value(true)
local currentTime = Value(os.date(UI_CONFIG.TimestampFormat))
local recBlinkState = Value(true)
local batteryLevel = Value(UI_CONFIG.BatteryLevel)
local audioLevelL = Value(0.6)
local audioLevelR = Value(0.5)
local zoomLevel = Value(UI_CONFIG.ZoomLevel)
local memoryUsed = Value(UI_CONFIG.MemoryUsed)
local isNightVisionEnabled = Value(false)

-- Target info (set by PhotoTargetController)
local currentTargetInfo = Value("---")

-- === UI CREATION FUNCTIONS ===

local function createVignette(parent)
	return New "ImageLabel" {
		Name = "Vignette",
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundTransparency = 1,
		Image = "rbxassetid://1049719798",
		ImageColor3 = Color3.fromRGB(0, 0, 0),
		ImageTransparency = 1 - UI_CONFIG.VignetteIntensity,
		ScaleType = Enum.ScaleType.Stretch,
		Parent = parent,
	}
end

local function createNightVisionOverlay(parent)
	return New "Frame" {
		Name = "NightVisionOverlay",
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundColor3 = UI_CONFIG.NightVisionTint,
		BackgroundTransparency = Computed(function()
			return isNightVisionEnabled:get() and 0.7 or 1
		end),
		Parent = parent,
	}
end

local function createFilmBorderAndCorners(parent, animatedTransparency)
	local borderThicknessScale = UI_CONFIG.FilmBorderEnabled and 0.083 or 0
	local cornerSizeX = 0.025
	local cornerSizeY = 0.045
	local marginX = UI_CONFIG.MarginX - 0.015
	local marginY = UI_CONFIG.MarginY - 0.01
	local lineThicknessX = 0.002
	local lineThicknessY = 0.0035
	
	local children = {}
	
	if UI_CONFIG.FilmBorderEnabled then
		table.insert(children, New "Frame" {
			Name = "TopBorder",
			Size = UDim2.new(1, 0, borderThicknessScale, 0),
			Position = UDim2.new(0, 0, 0, 0),
			BackgroundColor3 = Color3.fromRGB(0, 0, 0),
			BackgroundTransparency = 0.3,
			BorderSizePixel = 0,
		})
		table.insert(children, New "Frame" {
			Name = "BottomBorder",
			Size = UDim2.new(1, 0, borderThicknessScale, 0),
			Position = UDim2.new(0, 0, 1 - borderThicknessScale, 0),
			BackgroundColor3 = Color3.fromRGB(0, 0, 0),
			BackgroundTransparency = 0.3,
			BorderSizePixel = 0,
		})
	end
	
	if UI_CONFIG.CornerBracketsEnabled then
		-- Top-left bracket
		table.insert(children, New "Frame" {
			Size = UDim2.new(cornerSizeX, 0, lineThicknessY, 0),
			Position = UDim2.new(marginX, 0, marginY, 0),
			BackgroundColor3 = UI_CONFIG.OverlayColor,
			BackgroundTransparency = animatedTransparency,
			BorderSizePixel = 0,
		})
		table.insert(children, New "Frame" {
			Size = UDim2.new(lineThicknessX, 0, cornerSizeY, 0),
			Position = UDim2.new(marginX, 0, marginY, 0),
			BackgroundColor3 = UI_CONFIG.OverlayColor,
			BackgroundTransparency = animatedTransparency,
			BorderSizePixel = 0,
		})
		-- Top-right bracket
		table.insert(children, New "Frame" {
			Size = UDim2.new(cornerSizeX, 0, lineThicknessY, 0),
			Position = UDim2.new(1 - marginX - cornerSizeX, 0, marginY, 0),
			BackgroundColor3 = UI_CONFIG.OverlayColor,
			BackgroundTransparency = animatedTransparency,
			BorderSizePixel = 0,
		})
		table.insert(children, New "Frame" {
			Size = UDim2.new(lineThicknessX, 0, cornerSizeY, 0),
			Position = UDim2.new(1 - marginX - lineThicknessX, 0, marginY, 0),
			BackgroundColor3 = UI_CONFIG.OverlayColor,
			BackgroundTransparency = animatedTransparency,
			BorderSizePixel = 0,
		})
		-- Bottom-left bracket
		table.insert(children, New "Frame" {
			Size = UDim2.new(cornerSizeX, 0, lineThicknessY, 0),
			Position = UDim2.new(marginX, 0, 1 - marginY - lineThicknessY, 0),
			BackgroundColor3 = UI_CONFIG.OverlayColor,
			BackgroundTransparency = animatedTransparency,
			BorderSizePixel = 0,
		})
		table.insert(children, New "Frame" {
			Size = UDim2.new(lineThicknessX, 0, cornerSizeY, 0),
			Position = UDim2.new(marginX, 0, 1 - marginY - cornerSizeY, 0),
			BackgroundColor3 = UI_CONFIG.OverlayColor,
			BackgroundTransparency = animatedTransparency,
			BorderSizePixel = 0,
		})
		-- Bottom-right bracket
		table.insert(children, New "Frame" {
			Size = UDim2.new(cornerSizeX, 0, lineThicknessY, 0),
			Position = UDim2.new(1 - marginX - cornerSizeX, 0, 1 - marginY - lineThicknessY, 0),
			BackgroundColor3 = UI_CONFIG.OverlayColor,
			BackgroundTransparency = animatedTransparency,
			BorderSizePixel = 0,
		})
		table.insert(children, New "Frame" {
			Size = UDim2.new(lineThicknessX, 0, cornerSizeY, 0),
			Position = UDim2.new(1 - marginX - lineThicknessX, 0, 1 - marginY - cornerSizeY, 0),
			BackgroundColor3 = UI_CONFIG.OverlayColor,
			BackgroundTransparency = animatedTransparency,
			BorderSizePixel = 0,
		})
	end
	
	if #children == 0 then return nil end
	
	return New "Frame" {
		Name = "FilmBorderAndCorners",
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundTransparency = 1,
		Parent = parent,
		[Children] = children,
	}
end

local function createScanLines(parent, animatedTransparency)
	local lines = {}
	local lineCount = math.min(math.floor(1 / (UI_CONFIG.ScanLineSpacing / 1080)), 200)
	
	for i = 1, lineCount do
		local yPosScale = (i - 1) / lineCount
		table.insert(lines, New "Frame" {
			Size = UDim2.new(1, 0, 0.001, 0),
			Position = UDim2.new(0, 0, yPosScale, 0),
			BackgroundColor3 = Color3.fromRGB(0, 0, 0),
			BackgroundTransparency = Computed(function()
				return 1 - UI_CONFIG.ScanLineOpacity + animatedTransparency:get() * UI_CONFIG.ScanLineOpacity
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
			return 1 - UI_CONFIG.FilmGrainOpacity + animatedTransparency:get() * UI_CONFIG.FilmGrainOpacity
		end),
		ScaleType = Enum.ScaleType.Tile,
		TileSize = UDim2.new(0, 256, 0, 256),
		Parent = parent,
	}
end

local function createTopLeftInfo(parent, animatedTransparency)
	return New "Frame" {
		Name = "TopLeftInfo",
		Size = UDim2.new(0.1, 0, 0.08, 0),
		Position = UDim2.new(UI_CONFIG.MarginX, 0, UI_CONFIG.MarginY, 0),
		BackgroundTransparency = 1,
		Parent = parent,
		
		[Children] = {
			-- REC indicator with dot
			New "Frame" {
				Name = "RecIndicator",
				Size = UDim2.new(1, 0, 0.3, 0),
				Position = UDim2.new(0, 0, 0, 0),
				BackgroundTransparency = 1,
				[Children] = {
					New "Frame" {
						Name = "RecDot",
						Size = UDim2.new(0.08, 0, 0.7, 0),
						Position = UDim2.new(0, 0, 0.5, 0),
						AnchorPoint = Vector2.new(0, 0.5),
						BackgroundColor3 = UI_CONFIG.RecColor,
						BackgroundTransparency = Computed(function()
							return recBlinkState:get() and animatedTransparency:get() or 1
						end),
						BorderSizePixel = 0,
						[Children] = {
							New "UICorner" { CornerRadius = UDim.new(1, 0) },
							New "UIAspectRatioConstraint" { AspectRatio = 1 },
						},
					},
					New "TextLabel" {
						Name = "RecText",
						Size = UDim2.new(0.5, 0, 1, 0),
						Position = UDim2.new(0.12, 0, 0, 0),
						BackgroundTransparency = 1,
						Font = Enum.Font.RobotoMono,
						TextScaled = true,
						TextColor3 = UI_CONFIG.RecColor,
						TextTransparency = Computed(function()
							return recBlinkState:get() and animatedTransparency:get() or 0.5
						end),
						TextXAlignment = Enum.TextXAlignment.Left,
						Text = "REC",
					},
					-- Timecode
					New "TextLabel" {
						Name = "Timecode",
						Size = UDim2.new(0.5, 0, 0.85, 0),
						Position = UDim2.new(0.45, 0, 0.08, 0),
						BackgroundTransparency = 1,
						Font = Enum.Font.RobotoMono,
						TextScaled = true,
						TextColor3 = UI_CONFIG.OverlayColor,
						TextTransparency = animatedTransparency,
						TextXAlignment = Enum.TextXAlignment.Left,
						Text = Computed(function()
							return os.date("%H:%M:%S")
						end),
					},
				},
			},
			-- Camera model
			New "TextLabel" {
				Name = "CameraModel",
				Size = UDim2.new(1, 0, 0.28, 0),
				Position = UDim2.new(0, 0, 0.35, 0),
				BackgroundTransparency = 1,
				Font = Enum.Font.RobotoMono,
				TextScaled = true,
				TextColor3 = UI_CONFIG.OverlayColor,
				TextTransparency = animatedTransparency,
				TextXAlignment = Enum.TextXAlignment.Left,
				Text = "SONY FX6-K",
			},
			-- Recording format
			New "TextLabel" {
				Name = "RecFormat",
				Size = UDim2.new(1, 0, 0.25, 0),
				Position = UDim2.new(0, 0, 0.66, 0),
				BackgroundTransparency = 1,
				Font = Enum.Font.RobotoMono,
				TextScaled = true,
				TextColor3 = UI_CONFIG.AccentColor,
				TextTransparency = Computed(function() return 0.25 + animatedTransparency:get() * 0.75 end),
				TextXAlignment = Enum.TextXAlignment.Left,
				Text = "XAVC-I  4K  23.976p",
			},
		},
	}
end

local function createTimestamp(parent, animatedTransparency)
	return New "TextLabel" {
		Name = "Timestamp",
		Size = UDim2.new(0.16, 0, 0.022, 0),
		Position = UDim2.new(1 - UI_CONFIG.MarginX, 0, UI_CONFIG.MarginY, 0),
		AnchorPoint = Vector2.new(1, 0),
		BackgroundTransparency = 1,
		Font = Enum.Font.RobotoMono,
		TextScaled = true,
		TextColor3 = UI_CONFIG.OverlayColor,
		TextTransparency = animatedTransparency,
		TextXAlignment = Enum.TextXAlignment.Right,
		Text = Computed(function()
			return currentTime:get()
		end),
		Parent = parent,
	}
end

local function createCameraSettings(parent, animatedTransparency)
	local topY = UI_CONFIG.MarginY + 0.026
	return New "Frame" {
		Name = "CameraSettings",
		Size = UDim2.new(0.14, 0, 0.05, 0),
		Position = UDim2.new(1 - UI_CONFIG.MarginX, 0, topY, 0),
		AnchorPoint = Vector2.new(1, 0),
		BackgroundTransparency = 1,
		Parent = parent,
		
		[Children] = {
			New "TextLabel" {
				Size = UDim2.new(1, 0, 0.45, 0),
				Position = UDim2.new(0, 0, 0, 0),
				BackgroundTransparency = 1,
				Font = Enum.Font.RobotoMono,
				TextScaled = true,
				TextColor3 = UI_CONFIG.OverlayColor,
				TextTransparency = animatedTransparency,
				TextXAlignment = Enum.TextXAlignment.Right,
				Text = UI_CONFIG.Aperture .. "  ISO " .. UI_CONFIG.ISO,
			},
			New "TextLabel" {
				Size = UDim2.new(1, 0, 0.45, 0),
				Position = UDim2.new(0, 0, 0.5, 0),
				BackgroundTransparency = 1,
				Font = Enum.Font.RobotoMono,
				TextScaled = true,
				TextColor3 = UI_CONFIG.AccentColor,
				TextTransparency = Computed(function() return 0.2 + animatedTransparency:get() * 0.8 end),
				TextXAlignment = Enum.TextXAlignment.Right,
				Text = UI_CONFIG.ShutterSpeed .. "  " .. UI_CONFIG.FocalLength,
			},
		},
	}
end

local function createZoomIndicator(parent, animatedTransparency)
	local topY = UI_CONFIG.MarginY + 0.08
	return New "TextLabel" {
		Name = "ZoomIndicator",
		Size = UDim2.new(0.055, 0, 0.02, 0),
		Position = UDim2.new(1 - UI_CONFIG.MarginX, 0, topY, 0),
		AnchorPoint = Vector2.new(1, 0),
		BackgroundTransparency = 1,
		Font = Enum.Font.RobotoMono,
		TextScaled = true,
		TextColor3 = UI_CONFIG.OverlayColor,
		TextTransparency = animatedTransparency,
		TextXAlignment = Enum.TextXAlignment.Right,
		Text = Computed(function()
			return string.format("ZOOM %.1fx", zoomLevel:get())
		end),
		Parent = parent,
	}
end

local function createBatteryIndicator(parent, animatedTransparency)
	local bottomY = 1 - UI_CONFIG.MarginY
	return New "Frame" {
		Name = "BatteryIndicator",
		Size = UDim2.new(0.065, 0, 0.022, 0),
		Position = UDim2.new(1 - UI_CONFIG.MarginX, 0, bottomY, 0),
		AnchorPoint = Vector2.new(1, 1),
		BackgroundTransparency = 1,
		Parent = parent,
		
		[Children] = {
			New "Frame" {
				Name = "BatteryOutline",
				Size = UDim2.new(0.32, 0, 0.85, 0),
				Position = UDim2.new(0, 0, 0.5, 0),
				AnchorPoint = Vector2.new(0, 0.5),
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				[Children] = {
					New "UIStroke" {
						Color = UI_CONFIG.OverlayColor,
						Thickness = 1.5,
						Transparency = animatedTransparency,
					},
					New "UICorner" { CornerRadius = UDim.new(0.15, 0) },
					New "Frame" {
						Name = "BatteryFill",
						Size = Computed(function()
							return UDim2.new(batteryLevel:get() / 100 * 0.85, 0, 0.7, 0)
						end),
						Position = UDim2.new(0.075, 0, 0.15, 0),
						BackgroundColor3 = Computed(function()
							local level = batteryLevel:get()
							if level <= 20 then return UI_CONFIG.RecColor
							elseif level <= 40 then return UI_CONFIG.WarningColor
							else return UI_CONFIG.OverlayColor end
						end),
						BackgroundTransparency = animatedTransparency,
						BorderSizePixel = 0,
						[Children] = { New "UICorner" { CornerRadius = UDim.new(0.1, 0) } },
					},
				},
			},
			New "Frame" {
				Name = "BatteryTip",
				Size = UDim2.new(0.035, 0, 0.4, 0),
				Position = UDim2.new(0.34, 0, 0.5, 0),
				AnchorPoint = Vector2.new(0, 0.5),
				BackgroundColor3 = UI_CONFIG.OverlayColor,
				BackgroundTransparency = animatedTransparency,
				BorderSizePixel = 0,
				[Children] = { New "UICorner" { CornerRadius = UDim.new(0.3, 0) } },
			},
			New "TextLabel" {
				Name = "BatteryText",
				Size = UDim2.new(0.55, 0, 1, 0),
				Position = UDim2.new(0.42, 0, 0, 0),
				BackgroundTransparency = 1,
				Font = Enum.Font.RobotoMono,
				TextScaled = true,
				TextColor3 = UI_CONFIG.OverlayColor,
				TextTransparency = animatedTransparency,
				TextXAlignment = Enum.TextXAlignment.Left,
				Text = Computed(function() return batteryLevel:get() .. "%" end),
			},
		},
	}
end

local function createMemoryCard(parent, animatedTransparency)
	local bottomY = 1 - UI_CONFIG.MarginY - 0.028
	return New "Frame" {
		Name = "MemoryCard",
		Size = UDim2.new(0.1, 0, 0.04, 0),
		Position = UDim2.new(1 - UI_CONFIG.MarginX, 0, bottomY, 0),
		AnchorPoint = Vector2.new(1, 1),
		BackgroundTransparency = 1,
		Parent = parent,
		
		[Children] = {
			New "Frame" {
				Name = "SDIcon",
				Size = UDim2.new(0.12, 0, 0.55, 0),
				Position = UDim2.new(0, 0, 0.22, 0),
				BackgroundColor3 = UI_CONFIG.OverlayColor,
				BackgroundTransparency = animatedTransparency,
				BorderSizePixel = 0,
				[Children] = {
					New "UICorner" { CornerRadius = UDim.new(0.08, 0) },
					New "UIAspectRatioConstraint" { AspectRatio = 0.8 },
					New "Frame" {
						Size = UDim2.new(0.35, 0, 0.25, 0),
						Position = UDim2.new(0.65, 0, 0, 0),
						BackgroundColor3 = Color3.fromRGB(30, 30, 30),
						BorderSizePixel = 0,
					},
				},
			},
			New "TextLabel" {
				Size = UDim2.new(0.82, 0, 0.5, 0),
				Position = UDim2.new(0.18, 0, 0, 0),
				BackgroundTransparency = 1,
				Font = Enum.Font.RobotoMono,
				TextScaled = true,
				TextColor3 = UI_CONFIG.OverlayColor,
				TextTransparency = animatedTransparency,
				TextXAlignment = Enum.TextXAlignment.Left,
				Text = Computed(function()
					return string.format("%dGB / %dGB", memoryUsed:get(), UI_CONFIG.MemoryTotal)
				end),
			},
			New "TextLabel" {
				Size = UDim2.new(0.82, 0, 0.4, 0),
				Position = UDim2.new(0.18, 0, 0.55, 0),
				BackgroundTransparency = 1,
				Font = Enum.Font.RobotoMono,
				TextScaled = true,
				TextColor3 = UI_CONFIG.AccentColor,
				TextTransparency = Computed(function() return 0.3 + animatedTransparency:get() * 0.7 end),
				TextXAlignment = Enum.TextXAlignment.Left,
				Text = Computed(function()
					local remaining = UI_CONFIG.MemoryTotal - memoryUsed:get()
					local minutes = math.floor(remaining * 2)
					return string.format("%02d:%02d REMAINING", math.floor(minutes / 60), minutes % 60)
				end),
			},
		},
	}
end

local function createAudioLevelMeter(parent, animatedTransparency, side, levelValue)
	local bottomY = 1 - UI_CONFIG.MarginY
	local xOffset = side == "L" and 0 or 0.018
	
	return New "Frame" {
		Name = "AudioLevel" .. side,
		Size = UDim2.new(0.015, 0, 0.1, 0),
		Position = UDim2.new(UI_CONFIG.MarginX + xOffset, 0, bottomY, 0),
		AnchorPoint = Vector2.new(0, 1),
		BackgroundTransparency = 1,
		Parent = parent,
		
		[Children] = {
			New "TextLabel" {
				Size = UDim2.new(1, 0, 0.12, 0),
				Position = UDim2.new(0.5, 0, 0, 0),
				AnchorPoint = Vector2.new(0.5, 0),
				BackgroundTransparency = 1,
				Font = Enum.Font.RobotoMono,
				TextScaled = true,
				TextColor3 = UI_CONFIG.OverlayColor,
				TextTransparency = animatedTransparency,
				Text = side,
			},
			New "Frame" {
				Name = "MeterBG",
				Size = UDim2.new(0.6, 0, 0.82, 0),
				Position = UDim2.new(0.5, 0, 0.15, 0),
				AnchorPoint = Vector2.new(0.5, 0),
				BackgroundColor3 = Color3.fromRGB(30, 30, 30),
				BackgroundTransparency = Computed(function() return 0.4 + animatedTransparency:get() * 0.6 end),
				BorderSizePixel = 0,
				[Children] = {
					New "UICorner" { CornerRadius = UDim.new(0.15, 0) },
					New "Frame" {
						Name = "MeterFill",
						Size = Computed(function()
							return UDim2.new(1, 0, math.clamp(levelValue:get(), 0, 1), 0)
						end),
						Position = UDim2.new(0, 0, 1, 0),
						AnchorPoint = Vector2.new(0, 1),
						BackgroundColor3 = Computed(function()
							local level = levelValue:get()
							if level > 0.9 then return UI_CONFIG.RecColor
							elseif level > 0.7 then return UI_CONFIG.WarningColor
							else return Color3.fromRGB(50, 200, 50) end
						end),
						BackgroundTransparency = animatedTransparency,
						BorderSizePixel = 0,
						[Children] = { New "UICorner" { CornerRadius = UDim.new(0.15, 0) } },
					},
				},
			},
		},
	}
end

local function createCameraInfo(parent, animatedTransparency)
	local bottomY = 1 - UI_CONFIG.MarginY - 0.008
	return New "Frame" {
		Name = "CameraInfo",
		Size = UDim2.new(0.12, 0, 0.065, 0),
		Position = UDim2.new(UI_CONFIG.MarginX + 0.04, 0, bottomY, 0),
		AnchorPoint = Vector2.new(0, 1),
		BackgroundTransparency = 1,
		Parent = parent,
		
		[Children] = {
			New "TextLabel" {
				Size = UDim2.new(1, 0, 0.32, 0),
				Position = UDim2.new(0, 0, 0, 0),
				BackgroundTransparency = 1,
				Font = Enum.Font.RobotoMono,
				TextScaled = true,
				TextColor3 = UI_CONFIG.OverlayColor,
				TextTransparency = animatedTransparency,
				TextXAlignment = Enum.TextXAlignment.Left,
				Text = "CAM-01  STAB:ON",
			},
			New "TextLabel" {
				Name = "TargetInfo",
				Size = UDim2.new(1, 0, 0.32, 0),
				Position = UDim2.new(0, 0, 0.36, 0),
				BackgroundTransparency = 1,
				Font = Enum.Font.RobotoMono,
				TextScaled = true,
				TextColor3 = UI_CONFIG.AccentColor,
				TextTransparency = Computed(function() return 0.2 + animatedTransparency:get() * 0.8 end),
				TextXAlignment = Enum.TextXAlignment.Left,
				Text = Computed(function()
					return "TGT: " .. currentTargetInfo:get()
				end),
			},
			New "TextLabel" {
				Name = "FrameRate",
				Size = UDim2.new(1, 0, 0.28, 0),
				Position = UDim2.new(0, 0, 0.72, 0),
				BackgroundTransparency = 1,
				Font = Enum.Font.RobotoMono,
				TextScaled = true,
				TextColor3 = UI_CONFIG.AccentColor,
				TextTransparency = Computed(function() return 0.3 + animatedTransparency:get() * 0.7 end),
				TextXAlignment = Enum.TextXAlignment.Left,
				Text = "24p  4K  S-LOG3",
			},
		},
	}
end

-- === MAIN UI CREATION ===

local function createCameraUI(self)
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")
	
	self.effectTransparency = Value(0)
	local animatedTransparency = Spring(self.effectTransparency, 20, 1)
	
	local screenGui = New "ScreenGui" {
		Name = "CameraUI",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = 50,
		Parent = playerGui,
		
		[Children] = {
			New "Frame" {
				Name = "CameraOverlay",
				Size = UDim2.new(1, 0, 1, 0),
				BackgroundTransparency = 1,
				Visible = Computed(function()
					return isEffectVisible:get()
				end),
				
				[Children] = {
					-- Effects layers
					createNightVisionOverlay(nil),
					(UI_CONFIG.FilmBorderEnabled or UI_CONFIG.CornerBracketsEnabled) and createFilmBorderAndCorners(nil, animatedTransparency) or nil,
					UI_CONFIG.VignetteEnabled and createVignette(nil) or nil,
					UI_CONFIG.ScanLinesEnabled and createScanLines(nil, animatedTransparency) or nil,
					UI_CONFIG.FilmGrainEnabled and createFilmGrain(nil, animatedTransparency) or nil,
					
					-- TOP-LEFT: Recording info, camera model
					UI_CONFIG.RecIndicatorEnabled and createTopLeftInfo(nil, animatedTransparency) or nil,
					
					-- TOP-RIGHT: Timestamp, camera settings, zoom
					UI_CONFIG.TimestampEnabled and createTimestamp(nil, animatedTransparency) or nil,
					UI_CONFIG.CameraSettingsEnabled and createCameraSettings(nil, animatedTransparency) or nil,
					UI_CONFIG.ZoomEnabled and createZoomIndicator(nil, animatedTransparency) or nil,
					
					-- BOTTOM-LEFT: Audio meters, camera info
					UI_CONFIG.AudioLevelsEnabled and createAudioLevelMeter(nil, animatedTransparency, "L", audioLevelL) or nil,
					UI_CONFIG.AudioLevelsEnabled and createAudioLevelMeter(nil, animatedTransparency, "R", audioLevelR) or nil,
					createCameraInfo(nil, animatedTransparency),
					
					-- BOTTOM-RIGHT: Memory card, battery
					UI_CONFIG.MemoryCardEnabled and createMemoryCard(nil, animatedTransparency) or nil,
					UI_CONFIG.BatteryEnabled and createBatteryIndicator(nil, animatedTransparency) or nil,
				},
			},
		},
	}
	
	self.screenGui = screenGui
	return screenGui
end

-- === UPDATE LOOPS ===

local function startUpdateLoops()
	-- Timestamp
	task.spawn(function()
		while true do
			currentTime:set(os.date(UI_CONFIG.TimestampFormat))
			task.wait(1)
		end
	end)
	
	-- REC blink
	task.spawn(function()
		while true do
			recBlinkState:set(not recBlinkState:get())
			task.wait(1 / UI_CONFIG.RecBlinkSpeed)
		end
	end)
	
	-- Audio levels
	task.spawn(function()
		while true do
			audioLevelL:set(math.clamp(audioLevelL:get() + (math.random() - 0.5) * 0.2, 0.1, 0.95))
			audioLevelR:set(math.clamp(audioLevelR:get() + (math.random() - 0.5) * 0.2, 0.1, 0.95))
			task.wait(0.05)
		end
	end)
	
	-- Memory usage
	task.spawn(function()
		while true do
			task.wait(30)
			local current = memoryUsed:get()
			if current < UI_CONFIG.MemoryTotal - 1 then
				memoryUsed:set(current + 1)
			end
		end
	end)
	
	-- Battery drain
	task.spawn(function()
		while true do
			task.wait(120)
			local current = batteryLevel:get()
			if current > 5 then
				batteryLevel:set(current - 1)
			end
		end
	end)
end

-- === KNIT LIFECYCLE ===

function CameraUIController:KnitInit()
	-- Nothing to init
end

function CameraUIController:KnitStart()
	createCameraUI(self)
	startUpdateLoops()
	print("[CameraUIController] Initialized")
end

-- === PUBLIC METHODS ===

function CameraUIController:Show()
	isEffectVisible:set(true)
	if self.effectTransparency then
		self.effectTransparency:set(0)
	end
end

function CameraUIController:Hide()
	if self.effectTransparency then
		self.effectTransparency:set(1)
	end
	task.delay(0.3, function()
		isEffectVisible:set(false)
	end)
end

function CameraUIController:Toggle()
	if isEffectVisible:get() then
		self:Hide()
	else
		self:Show()
	end
end

function CameraUIController:IsVisible()
	return isEffectVisible:get()
end

function CameraUIController:SetBatteryLevel(level)
	batteryLevel:set(math.clamp(level, 0, 100))
end

function CameraUIController:SetZoomLevel(zoom)
	zoomLevel:set(math.clamp(zoom, 1, 4))
end

function CameraUIController:SetMemoryUsed(gb)
	memoryUsed:set(math.clamp(gb, 0, UI_CONFIG.MemoryTotal))
end

function CameraUIController:SetTargetInfo(info)
	currentTargetInfo:set(info)
end

function CameraUIController:ToggleNightVision()
	isNightVisionEnabled:set(not isNightVisionEnabled:get())
	return isNightVisionEnabled:get()
end

function CameraUIController:EnableNightVision()
	isNightVisionEnabled:set(true)
end

function CameraUIController:DisableNightVision()
	isNightVisionEnabled:set(false)
end

function CameraUIController:IsNightVisionEnabled()
	return isNightVisionEnabled:get()
end

return CameraUIController

