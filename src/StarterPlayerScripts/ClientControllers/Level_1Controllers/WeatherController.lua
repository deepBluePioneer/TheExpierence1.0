local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lighting = game:GetService("Lighting")
local TweenService = game:GetService("TweenService")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local CustomPackages = ReplicatedStorage:WaitForChild("CustomPackages")
local Knit = require(Packages.Knit)

-- Replica Module
local Replica = CustomPackages:WaitForChild("Replica")
local ReplicaController = require(Replica.ReplicaController)

local WeatherController = Knit.CreateController {
	Name = "WeatherController",
	atmosphere = nil,
	currentTweens = {},
}

-- === ATMOSPHERE SETUP ===

local function getOrCreateAtmosphere()
	local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
	if not atmosphere then
		atmosphere = Instance.new("Atmosphere")
		atmosphere.Parent = Lighting
	end
	return atmosphere
end

local function getOrCreateBloom()
	local bloom = Lighting:FindFirstChildOfClass("BloomEffect")
	if not bloom then
		bloom = Instance.new("BloomEffect")
		bloom.Intensity = 0.5
		bloom.Size = 24
		bloom.Threshold = 0.8
		bloom.Parent = Lighting
	end
	return bloom
end

local function getOrCreateColorCorrection()
	local cc = Lighting:FindFirstChildOfClass("ColorCorrectionEffect")
	if not cc then
		cc = Instance.new("ColorCorrectionEffect")
		cc.Parent = Lighting
	end
	return cc
end

-- === CANCEL EXISTING TWEENS ===

local function cancelTweens(self)
	for _, tween in pairs(self.currentTweens) do
		if tween then
			tween:Cancel()
		end
	end
	self.currentTweens = {}
end

-- === APPLY WEATHER SETTINGS ===

local function applyWeatherSettings(self, settings, transitionTime)
	cancelTweens(self)
	
	local atmosphere = getOrCreateAtmosphere()
	local bloom = getOrCreateBloom()
	local colorCorrection = getOrCreateColorCorrection()
	
	local tweenInfo = TweenInfo.new(
		transitionTime,
		Enum.EasingStyle.Sine,
		Enum.EasingDirection.InOut
	)
	
	-- Tween Lighting properties
	local lightingTween = TweenService:Create(Lighting, tweenInfo, {
		Brightness = settings.Brightness,
		Ambient = settings.Ambient,
		OutdoorAmbient = settings.OutdoorAmbient,
		FogStart = settings.FogStart,
		FogEnd = settings.FogEnd,
		FogColor = settings.FogColor,
		ClockTime = settings.ClockTime,
	})
	
	-- Tween Atmosphere properties
	local atmosphereTween = TweenService:Create(atmosphere, tweenInfo, {
		Density = settings.AtmosphereDensity,
		Offset = settings.AtmosphereOffset,
		Color = settings.AtmosphereColor,
		Decay = settings.AtmosphereDecay,
		Glare = settings.AtmosphereGlare,
		Haze = settings.AtmosphereHaze,
	})
	
	-- Adjust bloom for night/stormy weather
	local bloomIntensity = settings.Brightness < 0.5 and 0.8 or 0.3
	local bloomTween = TweenService:Create(bloom, tweenInfo, {
		Intensity = bloomIntensity,
	})
	
	-- Color correction for mood (full color)
	local saturation = settings.Brightness < 0.3 and -0.2 or 0  -- Slightly desaturated in dark weather
	local contrast = settings.Brightness < 0.3 and 0.1 or 0
	local ccTween = TweenService:Create(colorCorrection, tweenInfo, {
		Saturation = saturation,
		Contrast = contrast,
		Brightness = 0,
	})
	
	-- Store and play tweens
	self.currentTweens = {lightingTween, atmosphereTween, bloomTween, ccTween}
	
	for _, tween in pairs(self.currentTweens) do
		tween:Play()
	end
	
	print(string.format("[WeatherController] Transitioning weather over %.1f seconds", transitionTime))
end

-- === KNIT LIFECYCLE ===

function WeatherController:KnitInit()
	-- Ensure effects exist
	self.atmosphere = getOrCreateAtmosphere()
	getOrCreateBloom()
	getOrCreateColorCorrection()
	
	-- Request replica data if not already done
	if not ReplicaController.InitialDataReceived then
		ReplicaController.RequestData()
	end
end

function WeatherController:KnitStart()
	-- Listen for WeatherReplica
	ReplicaController.ReplicaOfClassCreated("WeatherReplica", function(replica)
		print("[WeatherController] Received WeatherReplica:", replica.Data.CurrentWeather)
		
		-- Apply initial weather (quick transition)
		applyWeatherSettings(self, replica.Data.Settings, 1)
		
		-- Listen for weather changes
		replica:ListenToChange({"Settings"}, function(newSettings)
			local transitionTime = replica.Data.TransitionTime or 3
			applyWeatherSettings(self, newSettings, transitionTime)
		end)
		
		-- Also listen to raw updates in case Settings is updated via SetValue
		replica:ListenToRaw(function(actionName, pathArray, ...)
			if actionName == "SetValue" and pathArray[1] == "Settings" then
				local newSettings = ...
				if newSettings then
					local transitionTime = replica.Data.TransitionTime or 3
					applyWeatherSettings(self, newSettings, transitionTime)
				end
			end
		end)
	end)
end

return WeatherController

