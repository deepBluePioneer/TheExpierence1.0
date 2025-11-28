local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local CustomPackages = ReplicatedStorage:WaitForChild("CustomPackages")
local Knit = require(Packages.Knit)

-- Replica Module
local Replica = CustomPackages:WaitForChild("Replica")
local ReplicaService = require(Replica.ReplicaService)

local WeatherService = Knit.CreateService {
	Name = "WeatherService",
	Client = {},
	weatherReplica = nil,
}

-- === WEATHER PRESETS ===
local WEATHER_PRESETS = {
	Sunny = {
		Brightness = 2,
		Ambient = Color3.fromRGB(150, 150, 150),
		OutdoorAmbient = Color3.fromRGB(180, 180, 180),
		FogStart = 1000,
		FogEnd = 10000,
		FogColor = Color3.fromRGB(200, 200, 200),
		ClockTime = 14,  -- 2 PM
		AtmosphereDensity = 0.3,
		AtmosphereOffset = 0,
		AtmosphereColor = Color3.fromRGB(200, 200, 200),
		AtmosphereDecay = Color3.fromRGB(100, 100, 100),
		AtmosphereGlare = 0,
		AtmosphereHaze = 0,
	},
	
	Rainy = {
		Brightness = 0.5,
		Ambient = Color3.fromRGB(80, 85, 95),
		OutdoorAmbient = Color3.fromRGB(100, 105, 115),
		FogStart = 50,
		FogEnd = 500,
		FogColor = Color3.fromRGB(120, 125, 135),
		ClockTime = 16,  -- 4 PM (overcast)
		AtmosphereDensity = 0.5,
		AtmosphereOffset = 0.2,
		AtmosphereColor = Color3.fromRGB(150, 155, 165),
		AtmosphereDecay = Color3.fromRGB(80, 85, 95),
		AtmosphereGlare = 0,
		AtmosphereHaze = 2,
	},
	
	Night = {
		Brightness = 0.1,
		Ambient = Color3.fromRGB(40, 45, 60),
		OutdoorAmbient = Color3.fromRGB(50, 55, 70),
		FogStart = 100,
		FogEnd = 600,
		FogColor = Color3.fromRGB(30, 35, 50),
		ClockTime = 0,  -- Midnight
		AtmosphereDensity = 0.4,
		AtmosphereOffset = 0.1,
		AtmosphereColor = Color3.fromRGB(60, 65, 80),
		AtmosphereDecay = Color3.fromRGB(20, 25, 40),
		AtmosphereGlare = 0,
		AtmosphereHaze = 1.5,
	},
	
	StormyNight = {
		Brightness = 1,
		Ambient = Color3.fromRGB(25, 30, 45),
		OutdoorAmbient = Color3.fromRGB(35, 40, 55),
		FogStart = 30,
		FogEnd = 300,
		FogColor = Color3.fromRGB(40, 45, 60),
		ClockTime = 22,  -- 10 PM
		AtmosphereDensity = 0.6,
		AtmosphereOffset = 0.3,
		AtmosphereColor = Color3.fromRGB(80, 85, 100),
		AtmosphereDecay = Color3.fromRGB(30, 35, 50),
		AtmosphereGlare = 0,
		AtmosphereHaze = 2.5,
	},
}

-- === REPLICA INITIALIZATION ===

local function initReplica(self)
	self.weatherReplica = ReplicaService.NewReplica({
		ClassToken = ReplicaService.NewClassToken("WeatherReplica"),
		Data = {
			CurrentWeather = "StormyNight",  -- Default to stormy night for rain
			TransitionTime = 3,  -- Seconds to transition between weather states
			Settings = WEATHER_PRESETS.StormyNight,
		},
		Replication = "All",
	})
end

-- === PUBLIC METHODS ===

function WeatherService:SetWeather(weatherName, transitionTime)
	local preset = WEATHER_PRESETS[weatherName]
	if not preset then
		warn("[WeatherService] Unknown weather preset:", weatherName)
		return false
	end
	
	transitionTime = transitionTime or 3
	
	self.weatherReplica:SetValue({"CurrentWeather"}, weatherName)
	self.weatherReplica:SetValue({"TransitionTime"}, transitionTime)
	self.weatherReplica:SetValue({"Settings"}, preset)
	
	print("[WeatherService] Weather changed to:", weatherName)
	return true
end

function WeatherService:GetCurrentWeather()
	return self.weatherReplica.Data.CurrentWeather
end

function WeatherService:GetPresets()
	return WEATHER_PRESETS
end

-- === KNIT LIFECYCLE ===

function WeatherService:KnitInit()
	initReplica(self)
end

function WeatherService:KnitStart()
	print("[WeatherService] Started with weather:", self.weatherReplica.Data.CurrentWeather)
end

return WeatherService

