local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local CustomPackages = ReplicatedStorage:WaitForChild("CustomPackages")
local Knit = require(Packages.Knit)

-- Replica Module
local Replica = CustomPackages:WaitForChild("Replica")
local ReplicaService = require(Replica.ReplicaService)

local WeatherService = Knit.CreateService {
	Name = "WeatherService",
	Client = {
		-- Signal fired when day/night changes: (isNight: boolean)
		IsNightChanged = Knit.CreateSignal(),
	},
	weatherReplica = nil,
	_dayNightEnabled = true,
	_currentTime = 6,  -- Start at 6 AM
	_isNight = false,
}

-- === DAY/NIGHT CYCLE CONFIG ===
local DAY_NIGHT_CONFIG = {
	-- Time settings (in-game hours)
	DawnStart = 5,        -- 5 AM - dawn begins
	DayStart = 7,         -- 7 AM - full daylight
	DuskStart = 18,       -- 6 PM - dusk begins  
	NightStart = 20,      -- 8 PM - full night
	
	-- Cycle speed (real seconds per in-game hour)
	SecondsPerHour = 10,  -- 10 real seconds = 1 in-game hour (full day = 4 minutes)
	
	-- Weather transitions
	DayWeather = "Sunny",
	NightWeather = "StormyNight",  -- Rain at night
	TransitionTime = 5,   -- Seconds to transition weather
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
		Brightness = 10,
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
			CurrentWeather = "Sunny",
			TransitionTime = 3,
			Settings = WEATHER_PRESETS.Sunny,
			ClockTime = 6,  -- Current in-game hour
			IsNight = false,
			DayNightEnabled = true,
		},
		Replication = "All",
	})
end

-- === DAY/NIGHT CYCLE ===

local function isNightTime(hour)
	return hour >= DAY_NIGHT_CONFIG.NightStart or hour < DAY_NIGHT_CONFIG.DawnStart
end

local function isDuskOrDawn(hour)
	return (hour >= DAY_NIGHT_CONFIG.DawnStart and hour < DAY_NIGHT_CONFIG.DayStart) or
	       (hour >= DAY_NIGHT_CONFIG.DuskStart and hour < DAY_NIGHT_CONFIG.NightStart)
end

local function updateTimeOfDay(self, deltaTime)
	if not self._dayNightEnabled then return end
	
	-- Advance time
	local hoursPerSecond = 1 / DAY_NIGHT_CONFIG.SecondsPerHour
	self._currentTime = self._currentTime + (deltaTime * hoursPerSecond)
	
	-- Wrap around at 24 hours
	if self._currentTime >= 24 then
		self._currentTime = self._currentTime - 24
	end
	
	-- Update Lighting ClockTime
	Lighting.ClockTime = self._currentTime
	
	-- Update replica
	self.weatherReplica:SetValue({"ClockTime"}, self._currentTime)
	
	-- Check for night/day transition
	local wasNight = self._isNight
	self._isNight = isNightTime(self._currentTime)
	
	-- Weather change on transition
	if self._isNight ~= wasNight then
		self.weatherReplica:SetValue({"IsNight"}, self._isNight)
		
		-- Fire signal to all clients
		print(string.format("[WeatherService] Firing IsNightChanged signal: %s", tostring(self._isNight)))
		self.Client.IsNightChanged:FireAll(self._isNight)
		
		if self._isNight then
			-- Transition to night weather (rainy)
			print("[WeatherService] Night falling - starting rain...")
			self:SetWeather(DAY_NIGHT_CONFIG.NightWeather, DAY_NIGHT_CONFIG.TransitionTime)
		else
			-- Transition to day weather (sunny)
			print("[WeatherService] Dawn breaking - stopping rain...")
			self:SetWeather(DAY_NIGHT_CONFIG.DayWeather, DAY_NIGHT_CONFIG.TransitionTime)
		end
	end
end

local function startDayNightCycle(self)
	-- Initialize time (start at night for testing - change to DayStart for normal behavior)
	self._currentTime = DAY_NIGHT_CONFIG.NightStart  -- Start at night to test rain
	self._isNight = isNightTime(self._currentTime)
	Lighting.ClockTime = self._currentTime
	
	-- Set initial IsNight state in replica
	print("[WeatherService] *** SETTING INITIAL REPLICA VALUES ***")
	print(string.format("[WeatherService] _isNight = %s", tostring(self._isNight)))
	print(string.format("[WeatherService] _currentTime = %.1f", self._currentTime))
	
	self.weatherReplica:SetValue({"IsNight"}, self._isNight)
	self.weatherReplica:SetValue({"ClockTime"}, self._currentTime)
	
	-- Fire initial signal to all clients
	print(string.format("[WeatherService] Firing INITIAL IsNightChanged signal: %s", tostring(self._isNight)))
	self.Client.IsNightChanged:FireAll(self._isNight)
	
	print(string.format("[WeatherService] Replica IsNight now: %s", tostring(self.weatherReplica.Data.IsNight)))
	print(string.format("[WeatherService] Initial state - IsNight: %s, Time: %.1f", tostring(self._isNight), self._currentTime))
	
	-- Set initial weather based on time
	if self._isNight then
		self:SetWeather(DAY_NIGHT_CONFIG.NightWeather, 0)
	else
		self:SetWeather(DAY_NIGHT_CONFIG.DayWeather, 0)
	end
	
	-- Update loop
	RunService.Heartbeat:Connect(function(deltaTime)
		updateTimeOfDay(self, deltaTime)
	end)
	
	print(string.format("[WeatherService] Day/Night cycle started - %.1f seconds per hour, starting at %d:00", 
		DAY_NIGHT_CONFIG.SecondsPerHour, math.floor(self._currentTime)))
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

function WeatherService:GetCurrentTime()
	return self._currentTime
end

function WeatherService:SetTime(hour)
	self._currentTime = hour % 24
	Lighting.ClockTime = self._currentTime
	self.weatherReplica:SetValue({"ClockTime"}, self._currentTime)
	
	-- Check and update weather based on new time
	local wasNight = self._isNight
	self._isNight = isNightTime(self._currentTime)
	
	if self._isNight ~= wasNight then
		self.weatherReplica:SetValue({"IsNight"}, self._isNight)
		if self._isNight then
			self:SetWeather(DAY_NIGHT_CONFIG.NightWeather, DAY_NIGHT_CONFIG.TransitionTime)
		else
			self:SetWeather(DAY_NIGHT_CONFIG.DayWeather, DAY_NIGHT_CONFIG.TransitionTime)
		end
	end
	
	print(string.format("[WeatherService] Time set to %d:00", math.floor(self._currentTime)))
end

function WeatherService:SetDayNightEnabled(enabled)
	self._dayNightEnabled = enabled
	self.weatherReplica:SetValue({"DayNightEnabled"}, enabled)
	print("[WeatherService] Day/Night cycle:", enabled and "ENABLED" or "DISABLED")
end

function WeatherService:IsDayNightEnabled()
	return self._dayNightEnabled
end

function WeatherService:IsNight()
	return self._isNight
end

-- Client-callable method to get current IsNight state
function WeatherService.Client:GetIsNight()
	return self.Server._isNight
end

function WeatherService:SetCycleSpeed(secondsPerHour)
	DAY_NIGHT_CONFIG.SecondsPerHour = secondsPerHour
	print(string.format("[WeatherService] Cycle speed set to %.1f seconds per hour", secondsPerHour))
end

function WeatherService:SkipToNight()
	self:SetTime(DAY_NIGHT_CONFIG.NightStart)
end

function WeatherService:SkipToDay()
	self:SetTime(DAY_NIGHT_CONFIG.DayStart)
end

-- === KNIT LIFECYCLE ===

function WeatherService:KnitInit()
	initReplica(self)
end

function WeatherService:KnitStart()
	-- Start the day/night cycle
	startDayNightCycle(self)
	print("[WeatherService] Started with day/night cycle enabled")
end

return WeatherService

