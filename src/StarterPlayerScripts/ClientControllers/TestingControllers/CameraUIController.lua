--[[
	HelmetHUDController (formerly CameraUIController)
	Sci-Fi helmet visor HUD overlay - symmetrical design with animated meters
	Includes parallax effect based on camera movement
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

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
local HUD_CONFIG = {
	-- Vignette
	VignetteEnabled = false,
	VignetteIntensity = 0.3,
	
	-- Scan lines
	ScanLinesEnabled = true,
	ScanLineOpacity = 0.035,
	
	-- Holographic noise
	HoloNoiseEnabled = true,
	HoloNoiseOpacity = 0.02,
	
	-- Parallax/Camera shift effect
	ParallaxEnabled = true,
	ParallaxIntensity = 25,
	ParallaxSmoothing = 8,
	ParallaxLayerMultipliers = {
		Background = 0.3,
		Frame = 0.5,
		Panels = 0.8,
	},
	
	-- Layout margins
	MarginX = 0.08,
	MarginY = 0.055,
	
	-- Colors - Sci-Fi Cyan/Teal theme
	PrimaryColor = Color3.fromRGB(0, 235, 235),
	SecondaryColor = Color3.fromRGB(0, 190, 210),
	AccentColor = Color3.fromRGB(120, 255, 255),
	DimColor = Color3.fromRGB(0, 130, 150),
	WarningColor = Color3.fromRGB(255, 190, 0),
	CriticalColor = Color3.fromRGB(255, 70, 70),
	SafeColor = Color3.fromRGB(70, 255, 130),
	HazardTintColor = Color3.fromRGB(0, 50, 65),
	
	-- Initial values
	SuitPower = 94,
	OxygenLevel = 87,
	HeartRate = 72,
	RadiationLevel = 0.28,
	AtmoPressure = 0.12,
	Temperature = -43,
	Toxicity = 0.64,
	SignalStrength = 0.85,
	SuitIntegrity = 96,
}

-- === STATE VALUES ===
local isEffectVisible = Value(false)
local hudOpacity = Value(0)
local missionTime = Value("00:00:00")
local linkBlinkState = Value(true)
local scanPulseAlpha = Value(0)

-- Left side stats
local suitPower = Value(HUD_CONFIG.SuitPower)
local oxygenLevel = Value(HUD_CONFIG.OxygenLevel)
local heartRate = Value(HUD_CONFIG.HeartRate)
local suitIntegrity = Value(HUD_CONFIG.SuitIntegrity)

-- Right side stats  
local radiationLevel = Value(HUD_CONFIG.RadiationLevel)
local atmoPressure = Value(HUD_CONFIG.AtmoPressure)
local temperature = Value(HUD_CONFIG.Temperature)
local toxicity = Value(HUD_CONFIG.Toxicity)
local signalStrength = Value(HUD_CONFIG.SignalStrength)

-- Animated meter values
local heartBeatPhase = Value(0)
local scanWavePhase = Value(0)
local meterPulse = Value(0)

-- Threat/waypoint
local threatLevel = Value("NOMINAL")
local visorMode = Value("STANDARD")
local currentWaypoint = Value("BASE CAMP")
local waypointDistance = Value(1247)

local missionStartTime = os.time()

-- Parallax state
local parallaxOffsetX = Value(0)
local parallaxOffsetY = Value(0)
local lastCameraLookVector = nil
local parallaxConnection = nil

-- === HELPER FUNCTIONS ===

local function formatMissionTime(seconds)
	local hours = math.floor(seconds / 3600)
	local mins = math.floor((seconds % 3600) / 60)
	local secs = seconds % 60
	return string.format("%02d:%02d:%02d", hours, mins, secs)
end

local function getStatusColor(value, warningThreshold, criticalThreshold, inverted)
	if inverted then
		if value >= criticalThreshold then return HUD_CONFIG.CriticalColor
		elseif value >= warningThreshold then return HUD_CONFIG.WarningColor
		else return HUD_CONFIG.PrimaryColor end
	else
		if value <= criticalThreshold then return HUD_CONFIG.CriticalColor
		elseif value <= warningThreshold then return HUD_CONFIG.WarningColor
		else return HUD_CONFIG.PrimaryColor end
	end
end

-- === UI COMPONENTS ===

local function createHazardTint(parent)
	return New "Frame" {
		Name = "HazardTint",
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundColor3 = HUD_CONFIG.HazardTintColor,
		BackgroundTransparency = 0.94,
		Parent = parent,
	}
end

local function createScanLines(parent, animatedTransparency)
	local lines = {}
	local lineCount = 180
	
	for i = 1, lineCount do
		local yPosScale = (i - 1) / lineCount
		table.insert(lines, New "Frame" {
			Size = UDim2.new(1, 0, 0.0006, 0),
			Position = UDim2.new(0, 0, yPosScale, 0),
			BackgroundColor3 = Color3.fromRGB(0, 0, 0),
			BackgroundTransparency = Computed(function()
				return 1 - HUD_CONFIG.ScanLineOpacity + animatedTransparency:get() * HUD_CONFIG.ScanLineOpacity
			end),
			BorderSizePixel = 0,
		})
	end
	
	return New "Frame" {
		Name = "VisorScanLines",
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundTransparency = 1,
		Parent = parent,
		[Children] = lines,
	}
end

local function createHoloNoise(parent, animatedTransparency)
	return New "ImageLabel" {
		Name = "HoloNoise",
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundTransparency = 1,
		Image = "rbxassetid://2833078857",
		ImageColor3 = HUD_CONFIG.PrimaryColor,
		ImageTransparency = Computed(function()
			return 1 - HUD_CONFIG.HoloNoiseOpacity + animatedTransparency:get() * HUD_CONFIG.HoloNoiseOpacity
		end),
		ScaleType = Enum.ScaleType.Tile,
		TileSize = UDim2.new(0, 100, 0, 100),
		Parent = parent,
	}
end

local function createCornerBrackets(parent, animatedTransparency)
	local cornerSizeX = 0.04
	local cornerSizeY = 0.07
	local marginX = HUD_CONFIG.MarginX - 0.025
	local marginY = HUD_CONFIG.MarginY - 0.018
	local lineThicknessX = 0.003
	local lineThicknessY = 0.005
	
	local brackets = {}
	
	local corners = {
		{x = marginX, y = marginY, ax = 0, ay = 0},
		{x = 1 - marginX, y = marginY, ax = 1, ay = 0},
		{x = marginX, y = 1 - marginY, ax = 0, ay = 1},
		{x = 1 - marginX, y = 1 - marginY, ax = 1, ay = 1},
	}
	
	for _, c in ipairs(corners) do
		table.insert(brackets, New "Frame" {
			Size = UDim2.new(cornerSizeX, 0, lineThicknessY, 0),
			Position = UDim2.new(c.x, 0, c.y, 0),
			AnchorPoint = Vector2.new(c.ax, c.ay),
			BackgroundColor3 = HUD_CONFIG.PrimaryColor,
			BackgroundTransparency = animatedTransparency,
			BorderSizePixel = 0,
		})
		table.insert(brackets, New "Frame" {
			Size = UDim2.new(lineThicknessX, 0, cornerSizeY, 0),
			Position = UDim2.new(c.x, 0, c.y, 0),
			AnchorPoint = Vector2.new(c.ax, c.ay),
			BackgroundColor3 = HUD_CONFIG.PrimaryColor,
			BackgroundTransparency = animatedTransparency,
			BorderSizePixel = 0,
		})
		
		local tickOffsetX = c.ax == 0 and 0.015 or -0.015
		local tickOffsetY = c.ay == 0 and 0.025 or -0.025
		table.insert(brackets, New "Frame" {
			Size = UDim2.new(0.015, 0, lineThicknessY * 0.6, 0),
			Position = UDim2.new(c.x + tickOffsetX, 0, c.y + tickOffsetY, 0),
			AnchorPoint = Vector2.new(c.ax, c.ay),
			BackgroundColor3 = HUD_CONFIG.AccentColor,
			BackgroundTransparency = Computed(function() return 0.4 + animatedTransparency:get() * 0.6 end),
			BorderSizePixel = 0,
		})
	end
	
	return New "Frame" {
		Name = "CornerBrackets",
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundTransparency = 1,
		Parent = parent,
		[Children] = brackets,
	}
end

local function createCenterReticle(parent, animatedTransparency)
	return New "Frame" {
		Name = "CenterReticle",
		Size = UDim2.new(0.055, 0, 0.055, 0),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		Parent = parent,
		
		[Children] = {
			New "Frame" {
				Size = UDim2.new(1, 0, 1, 0),
				Position = UDim2.new(0.5, 0, 0.5, 0),
				AnchorPoint = Vector2.new(0.5, 0.5),
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				[Children] = {
					New "UICorner" { CornerRadius = UDim.new(1, 0) },
					New "UIStroke" {
						Color = HUD_CONFIG.PrimaryColor,
						Thickness = 1.5,
						Transparency = Computed(function()
							return 0.5 + animatedTransparency:get() * 0.5 + math.sin(scanWavePhase:get()) * 0.15
						end),
					},
				},
			},
			New "Frame" {
				Size = UDim2.new(0.35, 0, 0.025, 0),
				Position = UDim2.new(0.5, 0, 0, 0),
				AnchorPoint = Vector2.new(0.5, 0.5),
				BackgroundColor3 = HUD_CONFIG.PrimaryColor,
				BackgroundTransparency = Computed(function() return 0.45 + animatedTransparency:get() * 0.55 end),
				BorderSizePixel = 0,
			},
			New "Frame" {
				Size = UDim2.new(0.35, 0, 0.025, 0),
				Position = UDim2.new(0.5, 0, 1, 0),
				AnchorPoint = Vector2.new(0.5, 0.5),
				BackgroundColor3 = HUD_CONFIG.PrimaryColor,
				BackgroundTransparency = Computed(function() return 0.45 + animatedTransparency:get() * 0.55 end),
				BorderSizePixel = 0,
			},
			New "Frame" {
				Size = UDim2.new(0.025, 0, 0.35, 0),
				Position = UDim2.new(0, 0, 0.5, 0),
				AnchorPoint = Vector2.new(0.5, 0.5),
				BackgroundColor3 = HUD_CONFIG.PrimaryColor,
				BackgroundTransparency = Computed(function() return 0.45 + animatedTransparency:get() * 0.55 end),
				BorderSizePixel = 0,
			},
			New "Frame" {
				Size = UDim2.new(0.025, 0, 0.35, 0),
				Position = UDim2.new(1, 0, 0.5, 0),
				AnchorPoint = Vector2.new(0.5, 0.5),
				BackgroundColor3 = HUD_CONFIG.PrimaryColor,
				BackgroundTransparency = Computed(function() return 0.45 + animatedTransparency:get() * 0.55 end),
				BorderSizePixel = 0,
			},
			New "Frame" {
				Size = UDim2.new(0.1, 0, 0.1, 0),
				Position = UDim2.new(0.5, 0, 0.5, 0),
				AnchorPoint = Vector2.new(0.5, 0.5),
				BackgroundColor3 = HUD_CONFIG.AccentColor,
				BackgroundTransparency = Computed(function() return 0.3 + animatedTransparency:get() * 0.7 end),
				BorderSizePixel = 0,
				[Children] = { New "UICorner" { CornerRadius = UDim.new(1, 0) } },
			},
		},
	}
end

local function createVerticalMeter(name, valueState, maxVal, colorFunc, labelText, unitText)
	return New "Frame" {
		Name = name,
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundTransparency = 1,
		
		[Children] = {
			New "TextLabel" {
				Size = UDim2.new(1, 0, 0.15, 0),
				Position = UDim2.new(0.5, 0, 0, 0),
				AnchorPoint = Vector2.new(0.5, 0),
				BackgroundTransparency = 1,
				Font = Enum.Font.SciFi,
				TextScaled = true,
				TextColor3 = HUD_CONFIG.DimColor,
				Text = labelText,
			},
			New "Frame" {
				Name = "MeterBG",
				Size = UDim2.new(0.45, 0, 0.65, 0),
				Position = UDim2.new(0.5, 0, 0.17, 0),
				AnchorPoint = Vector2.new(0.5, 0),
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				[Children] = {
					New "UIStroke" {
						Color = HUD_CONFIG.DimColor,
						Thickness = 1,
						Transparency = 0.7,
					},
					New "Frame" {
						Name = "Fill",
						Size = Computed(function()
							local pct = math.clamp(valueState:get() / maxVal, 0, 1)
							return UDim2.new(0.8, 0, pct * 0.9, 0)
						end),
						Position = UDim2.new(0.5, 0, 0.95, 0),
						AnchorPoint = Vector2.new(0.5, 1),
						BackgroundColor3 = Computed(function()
							return colorFunc(valueState:get())
						end),
						BackgroundTransparency = Computed(function()
							return 0.35 + math.sin(meterPulse:get() + math.random() * 0.5) * 0.1
						end),
						BorderSizePixel = 0,
						[Children] = { New "UICorner" { CornerRadius = UDim.new(0.15, 0) } },
					},
				},
			},
			New "TextLabel" {
				Size = UDim2.new(1, 0, 0.15, 0),
				Position = UDim2.new(0.5, 0, 0.85, 0),
				AnchorPoint = Vector2.new(0.5, 0),
				BackgroundTransparency = 1,
				Font = Enum.Font.RobotoMono,
				TextScaled = true,
				TextColor3 = Computed(function()
					return colorFunc(valueState:get())
				end),
				Text = Computed(function()
					return string.format("%.0f%s", valueState:get(), unitText)
				end),
			},
		},
	}
end

local function createTopCenterPanel(parent, animatedTransparency)
	return New "Frame" {
		Name = "TopCenterPanel",
		Size = UDim2.new(0.28, 0, 0.055, 0),
		Position = UDim2.new(0.5, 0, HUD_CONFIG.MarginY, 0),
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundTransparency = 1,
		Parent = parent,
		
		[Children] = {
			New "Frame" {
				Size = UDim2.new(0.6, 0, 0.02, 0),
				Position = UDim2.new(0.5, 0, 0, 0),
				AnchorPoint = Vector2.new(0.5, 0),
				BackgroundColor3 = HUD_CONFIG.PrimaryColor,
				BackgroundTransparency = Computed(function() return 0.5 + animatedTransparency:get() * 0.5 end),
				BorderSizePixel = 0,
			},
			New "TextLabel" {
				Size = UDim2.new(1, 0, 0.45, 0),
				Position = UDim2.new(0.5, 0, 0.12, 0),
				AnchorPoint = Vector2.new(0.5, 0),
				BackgroundTransparency = 1,
				Font = Enum.Font.SciFi,
				TextScaled = true,
				TextColor3 = HUD_CONFIG.PrimaryColor,
				TextTransparency = animatedTransparency,
				Text = "◈  KEPLER-442b  SURVEY  ◈",
			},
			New "TextLabel" {
				Size = UDim2.new(0.5, 0, 0.35, 0),
				Position = UDim2.new(0.5, 0, 0.6, 0),
				AnchorPoint = Vector2.new(0.5, 0),
				BackgroundTransparency = 1,
				Font = Enum.Font.RobotoMono,
				TextScaled = true,
				TextColor3 = HUD_CONFIG.SecondaryColor,
				TextTransparency = Computed(function() return 0.2 + animatedTransparency:get() * 0.8 end),
				Text = Computed(function()
					return "MET " .. missionTime:get()
				end),
			},
		},
	}
end

local function createLeftPanel(parent, animatedTransparency)
	return New "Frame" {
		Name = "LeftPanel",
		Size = UDim2.new(0.09, 0, 0.5, 0),
		Position = UDim2.new(HUD_CONFIG.MarginX, 0, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		BackgroundTransparency = 1,
		Parent = parent,
		
		[Children] = {
			New "TextLabel" {
				Size = UDim2.new(1, 0, 0.06, 0),
				Position = UDim2.new(0.5, 0, 0, 0),
				AnchorPoint = Vector2.new(0.5, 0),
				BackgroundTransparency = 1,
				Font = Enum.Font.SciFi,
				TextScaled = true,
				TextColor3 = HUD_CONFIG.PrimaryColor,
				TextTransparency = animatedTransparency,
				Text = "◀ SUIT",
			},
			New "Frame" {
				Size = UDim2.new(0.8, 0, 0.003, 0),
				Position = UDim2.new(0.5, 0, 0.07, 0),
				AnchorPoint = Vector2.new(0.5, 0),
				BackgroundColor3 = HUD_CONFIG.DimColor,
				BackgroundTransparency = 0.5,
				BorderSizePixel = 0,
			},
			New "Frame" {
				Size = UDim2.new(0.24, 0, 0.85, 0),
				Position = UDim2.new(0, 0, 0.1, 0),
				BackgroundTransparency = 1,
				[Children] = {
					createVerticalMeter("Power", suitPower, 100, function(v)
						return getStatusColor(v, 25, 10, false)
					end, "PWR", "%"),
				},
			},
			New "Frame" {
				Size = UDim2.new(0.24, 0, 0.85, 0),
				Position = UDim2.new(0.25, 0, 0.1, 0),
				BackgroundTransparency = 1,
				[Children] = {
					createVerticalMeter("Oxygen", oxygenLevel, 100, function(v)
						return getStatusColor(v, 30, 15, false)
					end, "O₂", "%"),
				},
			},
			New "Frame" {
				Size = UDim2.new(0.24, 0, 0.85, 0),
				Position = UDim2.new(0.5, 0, 0.1, 0),
				BackgroundTransparency = 1,
				[Children] = {
					createVerticalMeter("Integrity", suitIntegrity, 100, function(v)
						return getStatusColor(v, 50, 25, false)
					end, "INT", "%"),
				},
			},
			New "Frame" {
				Size = UDim2.new(0.24, 0, 0.85, 0),
				Position = UDim2.new(0.75, 0, 0.1, 0),
				BackgroundTransparency = 1,
				[Children] = {
					createVerticalMeter("HeartRate", heartRate, 160, function(v)
						if v > 120 or v < 50 then return HUD_CONFIG.CriticalColor
						elseif v > 100 or v < 60 then return HUD_CONFIG.WarningColor
						else return HUD_CONFIG.SafeColor end
					end, "♥", ""),
				},
			},
		},
	}
end

local function createRightPanel(parent, animatedTransparency)
	return New "Frame" {
		Name = "RightPanel",
		Size = UDim2.new(0.09, 0, 0.5, 0),
		Position = UDim2.new(1 - HUD_CONFIG.MarginX, 0, 0.5, 0),
		AnchorPoint = Vector2.new(1, 0.5),
		BackgroundTransparency = 1,
		Parent = parent,
		
		[Children] = {
			New "TextLabel" {
				Size = UDim2.new(1, 0, 0.06, 0),
				Position = UDim2.new(0.5, 0, 0, 0),
				AnchorPoint = Vector2.new(0.5, 0),
				BackgroundTransparency = 1,
				Font = Enum.Font.SciFi,
				TextScaled = true,
				TextColor3 = HUD_CONFIG.PrimaryColor,
				TextTransparency = animatedTransparency,
				Text = "ENV ▶",
			},
			New "Frame" {
				Size = UDim2.new(0.8, 0, 0.003, 0),
				Position = UDim2.new(0.5, 0, 0.07, 0),
				AnchorPoint = Vector2.new(0.5, 0),
				BackgroundColor3 = HUD_CONFIG.DimColor,
				BackgroundTransparency = 0.5,
				BorderSizePixel = 0,
			},
			New "Frame" {
				Size = UDim2.new(0.24, 0, 0.85, 0),
				Position = UDim2.new(0, 0, 0.1, 0),
				BackgroundTransparency = 1,
				[Children] = {
					createVerticalMeter("Radiation", Computed(function()
						return radiationLevel:get() * 100
					end), 100, function(v)
						return getStatusColor(v, 50, 80, true)
					end, "RAD", "%"),
				},
			},
			New "Frame" {
				Size = UDim2.new(0.24, 0, 0.85, 0),
				Position = UDim2.new(0.25, 0, 0.1, 0),
				BackgroundTransparency = 1,
				[Children] = {
					createVerticalMeter("Atmosphere", Computed(function()
						return atmoPressure:get() * 100
					end), 100, function(v)
						return getStatusColor(v, 30, 10, false)
					end, "ATM", "%"),
				},
			},
			New "Frame" {
				Size = UDim2.new(0.24, 0, 0.85, 0),
				Position = UDim2.new(0.5, 0, 0.1, 0),
				BackgroundTransparency = 1,
				[Children] = {
					createVerticalMeter("Temperature", Computed(function()
						return (temperature:get() + 100) / 2
					end), 100, function(v)
						local temp = (v * 2) - 100
						if temp < -60 or temp > 50 then return HUD_CONFIG.CriticalColor
						elseif temp < -30 or temp > 35 then return HUD_CONFIG.WarningColor
						else return HUD_CONFIG.PrimaryColor end
					end, "TMP", ""),
				},
			},
			New "Frame" {
				Size = UDim2.new(0.24, 0, 0.85, 0),
				Position = UDim2.new(0.75, 0, 0.1, 0),
				BackgroundTransparency = 1,
				[Children] = {
					createVerticalMeter("Toxicity", Computed(function()
						return toxicity:get() * 100
					end), 100, function(v)
						return getStatusColor(v, 40, 70, true)
					end, "TOX", "%"),
				},
			},
		},
	}
end

local function createBottomLeftPanel(parent, animatedTransparency)
	return New "Frame" {
		Name = "BottomLeftPanel",
		Size = UDim2.new(0.15, 0, 0.08, 0),
		Position = UDim2.new(HUD_CONFIG.MarginX, 0, 1 - HUD_CONFIG.MarginY, 0),
		AnchorPoint = Vector2.new(0, 1),
		BackgroundTransparency = 1,
		Parent = parent,
		
		[Children] = {
			New "Frame" {
				Size = UDim2.new(1, 0, 0.35, 0),
				Position = UDim2.new(0, 0, 0, 0),
				BackgroundTransparency = 1,
				[Children] = {
					New "Frame" {
						Name = "LinkDot",
						Size = UDim2.new(0.04, 0, 0.7, 0),
						Position = UDim2.new(0, 0, 0.5, 0),
						AnchorPoint = Vector2.new(0, 0.5),
						BackgroundColor3 = HUD_CONFIG.SafeColor,
						BackgroundTransparency = Computed(function()
							return linkBlinkState:get() and 0.1 or 0.6
						end),
						BorderSizePixel = 0,
						[Children] = {
							New "UICorner" { CornerRadius = UDim.new(1, 0) },
							New "UIAspectRatioConstraint" { AspectRatio = 1 },
						},
					},
					New "TextLabel" {
						Size = UDim2.new(0.85, 0, 1, 0),
						Position = UDim2.new(0.06, 0, 0, 0),
						BackgroundTransparency = 1,
						Font = Enum.Font.SciFi,
						TextScaled = true,
						TextColor3 = HUD_CONFIG.SafeColor,
						TextTransparency = Computed(function()
							return linkBlinkState:get() and animatedTransparency:get() or 0.4
						end),
						TextXAlignment = Enum.TextXAlignment.Left,
						Text = "LINK ACTIVE",
					},
				},
			},
			New "TextLabel" {
				Size = UDim2.new(1, 0, 0.3, 0),
				Position = UDim2.new(0, 0, 0.38, 0),
				BackgroundTransparency = 1,
				Font = Enum.Font.RobotoMono,
				TextScaled = true,
				TextColor3 = HUD_CONFIG.SecondaryColor,
				TextTransparency = Computed(function() return 0.2 + animatedTransparency:get() * 0.8 end),
				TextXAlignment = Enum.TextXAlignment.Left,
				Text = Computed(function()
					return "◇ VISOR: " .. visorMode:get()
				end),
			},
			New "TextLabel" {
				Size = UDim2.new(1, 0, 0.28, 0),
				Position = UDim2.new(0, 0, 0.7, 0),
				BackgroundTransparency = 1,
				Font = Enum.Font.RobotoMono,
				TextScaled = true,
				TextColor3 = Computed(function()
					local t = threatLevel:get()
					if t == "HOSTILE" then return HUD_CONFIG.CriticalColor
					elseif t == "CAUTION" then return HUD_CONFIG.WarningColor
					else return HUD_CONFIG.SafeColor end
				end),
				TextTransparency = animatedTransparency,
				TextXAlignment = Enum.TextXAlignment.Left,
				Text = Computed(function()
					return "THREAT: " .. threatLevel:get()
				end),
			},
		},
	}
end

local function createBottomRightPanel(parent, animatedTransparency)
	return New "Frame" {
		Name = "BottomRightPanel",
		Size = UDim2.new(0.15, 0, 0.08, 0),
		Position = UDim2.new(1 - HUD_CONFIG.MarginX, 0, 1 - HUD_CONFIG.MarginY, 0),
		AnchorPoint = Vector2.new(1, 1),
		BackgroundTransparency = 1,
		Parent = parent,
		
		[Children] = {
			New "Frame" {
				Size = UDim2.new(1, 0, 0.35, 0),
				Position = UDim2.new(0, 0, 0, 0),
				BackgroundTransparency = 1,
				[Children] = {
					New "Frame" {
						Size = UDim2.new(0.12, 0, 0.7, 0),
						Position = UDim2.new(1, 0, 0.5, 0),
						AnchorPoint = Vector2.new(1, 0.5),
						BackgroundTransparency = 1,
						[Children] = {
							New "Frame" {
								Size = UDim2.new(0.2, 0, 0.3, 0),
								Position = UDim2.new(0, 0, 1, 0),
								AnchorPoint = Vector2.new(0, 1),
								BackgroundColor3 = Computed(function()
									return signalStrength:get() > 0.2 and HUD_CONFIG.PrimaryColor or HUD_CONFIG.DimColor
								end),
								BackgroundTransparency = 0.2,
								BorderSizePixel = 0,
							},
							New "Frame" {
								Size = UDim2.new(0.2, 0, 0.5, 0),
								Position = UDim2.new(0.27, 0, 1, 0),
								AnchorPoint = Vector2.new(0, 1),
								BackgroundColor3 = Computed(function()
									return signalStrength:get() > 0.4 and HUD_CONFIG.PrimaryColor or HUD_CONFIG.DimColor
								end),
								BackgroundTransparency = 0.2,
								BorderSizePixel = 0,
							},
							New "Frame" {
								Size = UDim2.new(0.2, 0, 0.7, 0),
								Position = UDim2.new(0.54, 0, 1, 0),
								AnchorPoint = Vector2.new(0, 1),
								BackgroundColor3 = Computed(function()
									return signalStrength:get() > 0.6 and HUD_CONFIG.PrimaryColor or HUD_CONFIG.DimColor
								end),
								BackgroundTransparency = 0.2,
								BorderSizePixel = 0,
							},
							New "Frame" {
								Size = UDim2.new(0.2, 0, 1, 0),
								Position = UDim2.new(0.8, 0, 1, 0),
								AnchorPoint = Vector2.new(0, 1),
								BackgroundColor3 = Computed(function()
									return signalStrength:get() > 0.8 and HUD_CONFIG.PrimaryColor or HUD_CONFIG.DimColor
								end),
								BackgroundTransparency = 0.2,
								BorderSizePixel = 0,
							},
						},
					},
					New "TextLabel" {
						Size = UDim2.new(0.82, 0, 1, 0),
						Position = UDim2.new(0, 0, 0, 0),
						BackgroundTransparency = 1,
						Font = Enum.Font.SciFi,
						TextScaled = true,
						TextColor3 = HUD_CONFIG.PrimaryColor,
						TextTransparency = animatedTransparency,
						TextXAlignment = Enum.TextXAlignment.Right,
						Text = "SIGNAL",
					},
				},
			},
			New "TextLabel" {
				Size = UDim2.new(1, 0, 0.3, 0),
				Position = UDim2.new(0, 0, 0.38, 0),
				BackgroundTransparency = 1,
				Font = Enum.Font.RobotoMono,
				TextScaled = true,
				TextColor3 = HUD_CONFIG.SecondaryColor,
				TextTransparency = Computed(function() return 0.2 + animatedTransparency:get() * 0.8 end),
				TextXAlignment = Enum.TextXAlignment.Right,
				Text = "NEXUS-7  EXOSUIT",
			},
			New "TextLabel" {
				Size = UDim2.new(1, 0, 0.28, 0),
				Position = UDim2.new(0, 0, 0.7, 0),
				BackgroundTransparency = 1,
				Font = Enum.Font.RobotoMono,
				TextScaled = true,
				TextColor3 = HUD_CONFIG.DimColor,
				TextTransparency = Computed(function() return 0.15 + animatedTransparency:get() * 0.85 end),
				TextXAlignment = Enum.TextXAlignment.Right,
				Text = Computed(function()
					return string.format("%s  %dm ◀", currentWaypoint:get(), waypointDistance:get())
				end),
			},
		},
	}
end

local function createBottomCenterPanel(parent, animatedTransparency)
	return New "Frame" {
		Name = "BottomCenterPanel",
		Size = UDim2.new(0.2, 0, 0.04, 0),
		Position = UDim2.new(0.5, 0, 1 - HUD_CONFIG.MarginY, 0),
		AnchorPoint = Vector2.new(0.5, 1),
		BackgroundTransparency = 1,
		Parent = parent,
		
		[Children] = {
			New "Frame" {
				Size = UDim2.new(1, 0, 0.6, 0),
				Position = UDim2.new(0.5, 0, 0, 0),
				AnchorPoint = Vector2.new(0.5, 0),
				BackgroundTransparency = 1,
				ClipsDescendants = true,
				BorderSizePixel = 0,
				[Children] = {
					New "UIStroke" {
						Color = HUD_CONFIG.DimColor,
						Thickness = 1,
						Transparency = 0.75,
					},
					New "Frame" {
						Name = "ScanLine",
						Size = UDim2.new(0.004, 0, 0.9, 0),
						Position = Computed(function()
							local phase = scanWavePhase:get() % (math.pi * 2)
							local x = (math.sin(phase) + 1) / 2
							return UDim2.new(x * 0.98 + 0.01, 0, 0.5, 0)
						end),
						AnchorPoint = Vector2.new(0.5, 0.5),
						BackgroundColor3 = HUD_CONFIG.AccentColor,
						BackgroundTransparency = 0.2,
						BorderSizePixel = 0,
					},
					New "Frame" {
						Size = UDim2.new(0.08, 0, 0.5, 0),
						Position = UDim2.new(0.15, 0, 0.5, 0),
						AnchorPoint = Vector2.new(0.5, 0.5),
						BackgroundColor3 = HUD_CONFIG.PrimaryColor,
						BackgroundTransparency = Computed(function()
							return 0.5 + math.sin(scanWavePhase:get() * 2) * 0.25
						end),
						BorderSizePixel = 0,
					},
					New "Frame" {
						Size = UDim2.new(0.08, 0, 0.7, 0),
						Position = UDim2.new(0.32, 0, 0.5, 0),
						AnchorPoint = Vector2.new(0.5, 0.5),
						BackgroundColor3 = HUD_CONFIG.PrimaryColor,
						BackgroundTransparency = Computed(function()
							return 0.45 + math.sin(scanWavePhase:get() * 2 + 1) * 0.25
						end),
						BorderSizePixel = 0,
					},
					New "Frame" {
						Size = UDim2.new(0.08, 0, 0.9, 0),
						Position = UDim2.new(0.5, 0, 0.5, 0),
						AnchorPoint = Vector2.new(0.5, 0.5),
						BackgroundColor3 = HUD_CONFIG.AccentColor,
						BackgroundTransparency = Computed(function()
							return 0.4 + math.sin(scanWavePhase:get() * 2 + 2) * 0.2
						end),
						BorderSizePixel = 0,
					},
					New "Frame" {
						Size = UDim2.new(0.08, 0, 0.65, 0),
						Position = UDim2.new(0.68, 0, 0.5, 0),
						AnchorPoint = Vector2.new(0.5, 0.5),
						BackgroundColor3 = HUD_CONFIG.PrimaryColor,
						BackgroundTransparency = Computed(function()
							return 0.45 + math.sin(scanWavePhase:get() * 2 + 3) * 0.25
						end),
						BorderSizePixel = 0,
					},
					New "Frame" {
						Size = UDim2.new(0.08, 0, 0.45, 0),
						Position = UDim2.new(0.85, 0, 0.5, 0),
						AnchorPoint = Vector2.new(0.5, 0.5),
						BackgroundColor3 = HUD_CONFIG.PrimaryColor,
						BackgroundTransparency = Computed(function()
							return 0.5 + math.sin(scanWavePhase:get() * 2 + 4) * 0.25
						end),
						BorderSizePixel = 0,
					},
				},
			},
			New "TextLabel" {
				Size = UDim2.new(1, 0, 0.35, 0),
				Position = UDim2.new(0.5, 0, 0.68, 0),
				AnchorPoint = Vector2.new(0.5, 0),
				BackgroundTransparency = 1,
				Font = Enum.Font.RobotoMono,
				TextScaled = true,
				TextColor3 = HUD_CONFIG.DimColor,
				Text = "▼ BIOMETRIC SCANNER ▼",
			},
		},
	}
end

-- Parallax container
local function createParallaxContainer(name, layerMultiplier, children)
	local mult = layerMultiplier or 1
	
	return New "Frame" {
		Name = name,
		Size = UDim2.new(1, 0, 1, 0),
		Position = Computed(function()
			if not HUD_CONFIG.ParallaxEnabled then
				return UDim2.new(0, 0, 0, 0)
			end
			local offsetX = parallaxOffsetX:get() * mult
			local offsetY = parallaxOffsetY:get() * mult
			return UDim2.new(0, offsetX, 0, offsetY)
		end),
		BackgroundTransparency = 1,
		[Children] = children,
	}
end

local function createHelmetHUD(self)
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")
	
	self.effectTransparency = Value(0)
	local animatedTransparency = Spring(self.effectTransparency, 18, 1)
	
	local screenGui = New "ScreenGui" {
		Name = "HelmetHUD",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = 50,
		Parent = playerGui,
		
		[Children] = {
			New "Frame" {
				Name = "HUDOverlay",
				Size = UDim2.new(1, 0, 1, 0),
				BackgroundTransparency = 1,
				ClipsDescendants = true,
				Visible = Computed(function()
					return isEffectVisible:get()
				end),
				
				[Children] = {
					createParallaxContainer("BackgroundLayer", HUD_CONFIG.ParallaxLayerMultipliers.Background, {
						createHazardTint(nil),
						HUD_CONFIG.ScanLinesEnabled and createScanLines(nil, animatedTransparency) or nil,
						HUD_CONFIG.HoloNoiseEnabled and createHoloNoise(nil, animatedTransparency) or nil,
					}),
					createParallaxContainer("FrameLayer", HUD_CONFIG.ParallaxLayerMultipliers.Frame, {
						createCornerBrackets(nil, animatedTransparency),
						createCenterReticle(nil, animatedTransparency),
					}),
					createParallaxContainer("PanelsLayer", HUD_CONFIG.ParallaxLayerMultipliers.Panels, {
						createTopCenterPanel(nil, animatedTransparency),
						createLeftPanel(nil, animatedTransparency),
						createRightPanel(nil, animatedTransparency),
						createBottomLeftPanel(nil, animatedTransparency),
						createBottomRightPanel(nil, animatedTransparency),
						createBottomCenterPanel(nil, animatedTransparency),
					}),
				},
			},
		},
	}
	
	self.screenGui = screenGui
	return screenGui
end

-- === UPDATE LOOPS ===

local function startUpdateLoops()
	-- Camera parallax
	if HUD_CONFIG.ParallaxEnabled then
		local camera = workspace.CurrentCamera
		local currentOffsetX = 0
		local currentOffsetY = 0
		local targetOffsetX = 0
		local targetOffsetY = 0
		
		if parallaxConnection then
			parallaxConnection:Disconnect()
		end
		
		parallaxConnection = RunService.RenderStepped:Connect(function(deltaTime)
			if not camera then
				camera = workspace.CurrentCamera
				return
			end
			
			local lookVector = camera.CFrame.LookVector
			
			if lastCameraLookVector then
				local deltaX = lookVector.X - lastCameraLookVector.X
				local deltaY = lookVector.Y - lastCameraLookVector.Y
				
				targetOffsetX = targetOffsetX - deltaX * HUD_CONFIG.ParallaxIntensity * 50
				targetOffsetY = targetOffsetY + deltaY * HUD_CONFIG.ParallaxIntensity * 30
				
				local maxOffset = HUD_CONFIG.ParallaxIntensity
				targetOffsetX = math.clamp(targetOffsetX, -maxOffset, maxOffset)
				targetOffsetY = math.clamp(targetOffsetY, -maxOffset * 0.6, maxOffset * 0.6)
				
				targetOffsetX = targetOffsetX * 0.95
				targetOffsetY = targetOffsetY * 0.95
			end
			
			lastCameraLookVector = lookVector
			
			local smoothing = HUD_CONFIG.ParallaxSmoothing * deltaTime
			currentOffsetX = currentOffsetX + (targetOffsetX - currentOffsetX) * math.min(smoothing, 1)
			currentOffsetY = currentOffsetY + (targetOffsetY - currentOffsetY) * math.min(smoothing, 1)
			
			parallaxOffsetX:set(currentOffsetX)
			parallaxOffsetY:set(currentOffsetY)
		end)
	end
	
	-- Mission time
	task.spawn(function()
		while true do
			local elapsed = os.time() - missionStartTime
			missionTime:set(formatMissionTime(elapsed))
			task.wait(1)
		end
	end)
	
	-- Link blink
	task.spawn(function()
		while true do
			linkBlinkState:set(not linkBlinkState:get())
			task.wait(0.8)
		end
	end)
	
	-- Scan wave
	task.spawn(function()
		while true do
			scanWavePhase:set(scanWavePhase:get() + 0.08)
			task.wait(0.016)
		end
	end)
	
	-- Meter pulse
	task.spawn(function()
		while true do
			meterPulse:set(meterPulse:get() + 0.15)
			task.wait(0.05)
		end
	end)
	
	-- Environmental fluctuations
	task.spawn(function()
		while true do
			radiationLevel:set(math.clamp(HUD_CONFIG.RadiationLevel + (math.random() - 0.5) * 0.08, 0.05, 0.95))
			temperature:set(HUD_CONFIG.Temperature + math.random(-3, 3))
			atmoPressure:set(math.clamp(HUD_CONFIG.AtmoPressure + (math.random() - 0.5) * 0.02, 0.05, 0.5))
			toxicity:set(math.clamp(HUD_CONFIG.Toxicity + (math.random() - 0.5) * 0.06, 0.1, 0.9))
			task.wait(1.5)
		end
	end)
	
	-- Suit fluctuations
	task.spawn(function()
		while true do
			heartRate:set(math.clamp(HUD_CONFIG.HeartRate + math.random(-4, 6), 55, 135))
			suitIntegrity:set(math.clamp(suitIntegrity:get() + math.random(-1, 1) * 0.5, 80, 100))
			signalStrength:set(math.clamp(HUD_CONFIG.SignalStrength + (math.random() - 0.5) * 0.15, 0.3, 1))
			task.wait(1.2)
		end
	end)
	
	-- Resource drain
	task.spawn(function()
		while true do
			task.wait(45)
			oxygenLevel:set(math.max(5, oxygenLevel:get() - 1))
		end
	end)
	
	task.spawn(function()
		while true do
			task.wait(120)
			suitPower:set(math.max(5, suitPower:get() - 1))
		end
	end)
	
	-- Waypoint
	task.spawn(function()
		while true do
			waypointDistance:set(math.max(10, waypointDistance:get() + math.random(-20, 15)))
			task.wait(0.4)
		end
	end)
end

-- === KNIT LIFECYCLE ===

function CameraUIController:KnitInit()
	print("[HelmetHUD] Initializing...")
end

function CameraUIController:KnitStart()
	createHelmetHUD(self)
	print("[HelmetHUD] Initialized - Awaiting boot sequence completion")
end

-- === PUBLIC METHODS ===

function CameraUIController:FadeIn(duration)
	duration = duration or 1.5
	
	print("[HelmetHUD] Initiating HUD fade-in sequence...")
	
	isEffectVisible:set(true)
	
	if self.effectTransparency then
		self.effectTransparency:set(1)
	end
	
	if self.screenGui then
		local hudOverlay = self.screenGui:FindFirstChild("HUDOverlay")
		if hudOverlay then
			for _, child in ipairs(hudOverlay:GetDescendants()) do
				if child:IsA("Frame") then
					child.BackgroundTransparency = 1
					TweenService:Create(child, TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
						BackgroundTransparency = child:GetAttribute("TargetTransparency") or child.BackgroundTransparency
					}):Play()
				elseif child:IsA("TextLabel") then
					child.TextTransparency = 1
					TweenService:Create(child, TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
						TextTransparency = 0
					}):Play()
				elseif child:IsA("UIStroke") then
					local originalTransparency = child.Transparency
					child.Transparency = 1
					TweenService:Create(child, TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
						Transparency = originalTransparency
					}):Play()
				end
			end
		end
	end
	
	task.spawn(function()
		local startTime = tick()
		while tick() - startTime < duration do
			local alpha = (tick() - startTime) / duration
			if self.effectTransparency then
				self.effectTransparency:set(1 - alpha)
			end
			task.wait()
		end
		if self.effectTransparency then
			self.effectTransparency:set(0)
		end
	end)
	
	startUpdateLoops()
	
	task.delay(duration, function()
		print("[HelmetHUD] All systems online - Welcome to Kepler-442b")
	end)
end

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
	suitPower:set(math.clamp(level, 0, 100))
end

function CameraUIController:SetZoomLevel(zoom)
	if zoom > 2 then
		visorMode:set("XENO-SCAN")
	elseif zoom > 1.5 then
		visorMode:set("THERMAL")
	else
		visorMode:set("STANDARD")
	end
end

function CameraUIController:SetMemoryUsed(gb)
	oxygenLevel:set(math.clamp(100 - gb, 0, 100))
end

function CameraUIController:SetTargetInfo(info)
	currentWaypoint:set(info)
end

function CameraUIController:ToggleNightVision()
	local current = visorMode:get()
	visorMode:set(current == "THERMAL" and "STANDARD" or "THERMAL")
	return visorMode:get() == "THERMAL"
end

function CameraUIController:EnableNightVision()
	visorMode:set("THERMAL")
end

function CameraUIController:DisableNightVision()
	visorMode:set("STANDARD")
end

function CameraUIController:IsNightVisionEnabled()
	return visorMode:get() == "THERMAL"
end

function CameraUIController:SetOxygenLevel(level)
	oxygenLevel:set(math.clamp(level, 0, 100))
end

function CameraUIController:SetSuitPower(level)
	suitPower:set(math.clamp(level, 0, 100))
end

function CameraUIController:SetThreatLevel(level)
	threatLevel:set(level)
end

function CameraUIController:SetVisorMode(mode)
	visorMode:set(mode)
end

function CameraUIController:SetRadiation(level)
	radiationLevel:set(math.clamp(level, 0, 1))
end

function CameraUIController:SetTemperature(temp)
	temperature:set(temp)
end

function CameraUIController:SetWaypoint(name, distance)
	currentWaypoint:set(name)
	if distance then
		waypointDistance:set(distance)
	end
end

function CameraUIController:SetHeartRate(bpm)
	heartRate:set(math.clamp(bpm, 40, 200))
end

function CameraUIController:SetSuitIntegrity(level)
	suitIntegrity:set(math.clamp(level, 0, 100))
end

function CameraUIController:SetParallaxEnabled(enabled)
	HUD_CONFIG.ParallaxEnabled = enabled
	if not enabled then
		parallaxOffsetX:set(0)
		parallaxOffsetY:set(0)
	end
end

function CameraUIController:IsParallaxEnabled()
	return HUD_CONFIG.ParallaxEnabled
end

function CameraUIController:SetParallaxIntensity(intensity)
	HUD_CONFIG.ParallaxIntensity = math.clamp(intensity, 0, 100)
end

function CameraUIController:Cleanup()
	if parallaxConnection then
		parallaxConnection:Disconnect()
		parallaxConnection = nil
	end
end

return CameraUIController
