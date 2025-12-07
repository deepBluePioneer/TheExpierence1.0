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
		-- Signal fired when rain state changes: (rainEnabled: boolean)
		RainEnabledChanged = Knit.CreateSignal(),
		-- Signal fired when lightning state changes: (lightningEnabled: boolean)
		LightningEnabledChanged = Knit.CreateSignal(),
	},
	weatherReplica = nil,
	_dayNightEnabled = true,
	_currentTime = 10,  -- Start at 6 AM
	_isNight = false,
	_rainEnabled = false,  -- Independent rain control
	_lightningEnabled = false,  -- Independent lightning control
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
		Brightness = 8,
		Ambient = Color3.fromRGB(55, 60, 80),
		OutdoorAmbient = Color3.fromRGB(70, 75, 95),
		FogStart = 15,
		FogEnd = 180,
		FogColor = Color3.fromRGB(50, 55, 70),
		ClockTime = 22,  -- 10 PM
		AtmosphereDensity = 0.8,
		AtmosphereOffset = 0.35,
		AtmosphereColor = Color3.fromRGB(90, 95, 115),
		AtmosphereDecay = Color3.fromRGB(40, 45, 60),
		AtmosphereGlare = 0,
		AtmosphereHaze = 3.5,
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
			RainEnabled = false,  -- Independent rain control
			LightningEnabled = false,  -- Independent lightning control
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
		--[[print(string.format("[WeatherService] Firing IsNightChanged signal: %s", tostring(self._isNight)))]]
		self.Client.IsNightChanged:FireAll(self._isNight)
		
		if self._isNight then
			-- Transition to night weather (rainy)
			--("[WeatherService] Night falling - starting rain...")
			self:SetWeather(DAY_NIGHT_CONFIG.NightWeather, DAY_NIGHT_CONFIG.TransitionTime)
		else
			-- Transition to day weather (sunny)
			--("[WeatherService] Dawn breaking - stopping rain...")
			self:SetWeather(DAY_NIGHT_CONFIG.DayWeather, DAY_NIGHT_CONFIG.TransitionTime)
		end
	end
end

local function startDayNightCycle(self)
	-- Initialize time - start at night
	self._currentTime = DAY_NIGHT_CONFIG.NightStart  -- Start at 8 PM (night)
	self._isNight = true
	self._dayNightEnabled = false  -- Disable day/night cycle - stay in night
	self._rainEnabled = false  -- Start without rain
	self._lightningEnabled = false  -- Start without lightning
	Lighting.ClockTime = self._currentTime
	
	-- Set initial state in replica
	self.weatherReplica:SetValue({"IsNight"}, self._isNight)
	self.weatherReplica:SetValue({"ClockTime"}, self._currentTime)
	self.weatherReplica:SetValue({"DayNightEnabled"}, self._dayNightEnabled)
	self.weatherReplica:SetValue({"RainEnabled"}, self._rainEnabled)
	self.weatherReplica:SetValue({"LightningEnabled"}, self._lightningEnabled)
	
	-- Fire initial signals to all clients
	self.Client.IsNightChanged:FireAll(self._isNight)
	self.Client.RainEnabledChanged:FireAll(self._rainEnabled)
	self.Client.LightningEnabledChanged:FireAll(self._lightningEnabled)
	
	--[[print(string.format("[WeatherService] Initial state - IsNight: %s, Time: %.1f, CycleEnabled: %s", 
		tostring(self._isNight), self._currentTime, tostring(self._dayNightEnabled)))]]
	
	-- Set initial weather to night but WITHOUT rain (use Night preset instead of StormyNight)
	self:SetWeather("Night", 0)
	
	-- Update loop (only advances time if cycle is enabled)
	RunService.Heartbeat:Connect(function(deltaTime)
		updateTimeOfDay(self, deltaTime)
	end)
	
	if self._dayNightEnabled then
		--[[print(string.format("[WeatherService] Day/Night cycle started - %.1f seconds per hour, starting at %d:00", 
			DAY_NIGHT_CONFIG.SecondsPerHour, math.floor(self._currentTime)))]]
	else
		--[[print(string.format("[WeatherService] Time fixed at %d:00 (night) - cycle disabled", 
			math.floor(self._currentTime)))]]
	end
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
	
	--("[WeatherService] Weather changed to:", weatherName)
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
	
	--[[print(string.format("[WeatherService] Time set to %d:00", math.floor(self._currentTime)))]]
end

function WeatherService:SetDayNightEnabled(enabled)
	self._dayNightEnabled = enabled
	self.weatherReplica:SetValue({"DayNightEnabled"}, enabled)
	--("[WeatherService] Day/Night cycle:", enabled and "ENABLED" or "DISABLED")
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
	--[[print(string.format("[WeatherService] Cycle speed set to %.1f seconds per hour", secondsPerHour))]]
end

function WeatherService:SkipToNight()
	self:SetTime(DAY_NIGHT_CONFIG.NightStart)
end

function WeatherService:SkipToDay()
	self:SetTime(DAY_NIGHT_CONFIG.DayStart)
end

-- === RAIN/LIGHTNING CONTROL (Independent of day/night) ===

function WeatherService:SetRainEnabled(enabled)
	local wasEnabled = self._rainEnabled
	self._rainEnabled = enabled
	self.weatherReplica:SetValue({"RainEnabled"}, enabled)
	
	-- Fire signal if state changed
	if enabled ~= wasEnabled then
		print(string.format("[WeatherService] Rain %s", enabled and "ENABLED" or "DISABLED"))
		self.Client.RainEnabledChanged:FireAll(enabled)
	end
end

function WeatherService:SetLightningEnabled(enabled)
	local wasEnabled = self._lightningEnabled
	self._lightningEnabled = enabled
	self.weatherReplica:SetValue({"LightningEnabled"}, enabled)
	
	-- Fire signal if state changed
	if enabled ~= wasEnabled then
		print(string.format("[WeatherService] Lightning %s", enabled and "ENABLED" or "DISABLED"))
		self.Client.LightningEnabledChanged:FireAll(enabled)
	end
end

function WeatherService:IsRainEnabled()
	return self._rainEnabled
end

function WeatherService:IsLightningEnabled()
	return self._lightningEnabled
end

-- Client-callable methods
function WeatherService.Client:GetRainEnabled()
	return self.Server._rainEnabled
end

function WeatherService.Client:GetLightningEnabled()
	return self.Server._lightningEnabled
end

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                    RANDOM LIGHTING PROFILE GENERATION                       ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

-- Generate a completely random lighting profile for world regeneration
-- All settings are randomized for maximum variety
function WeatherService:GenerateRandomLightingProfile()
	-- Random number helper
	local function randomRange(min, max)
		return min + math.random() * (max - min)
	end
	
	-- Random color helper - fully random within range
	local function randomColor(minBrightness, maxBrightness)
		minBrightness = minBrightness or 0
		maxBrightness = maxBrightness or 255
		return Color3.fromRGB(
			math.random(minBrightness, maxBrightness),
			math.random(minBrightness, maxBrightness),
			math.random(minBrightness, maxBrightness)
		)
	end
	
	-- Randomly decide if it should rain (30% chance)
	local shouldRain = math.random() < 0.30
	local shouldLightning = shouldRain and math.random() < 0.50  -- 50% of rainy times have lightning
	
	-- Generate fully randomized profile
	local profile = {
		Name = "Random_" .. math.random(10000, 99999),
		
		-- Core lighting - random brightness (darker tends to look better for alien world)
		Brightness = randomRange(0.1, 2.0),
		
		-- Ambient colors - random but darker range for atmosphere
		Ambient = randomColor(20, 120),
		OutdoorAmbient = randomColor(30, 140),
		
		-- Fog settings - random distances and color
		FogStart = randomRange(5, 150),
		FogEnd = randomRange(100, 800),
		FogColor = randomColor(15, 100),
		
		-- Clock time - keep it mostly dark/dusk/night for alien feel
		ClockTime = randomRange(0, 24),
		
		-- Atmosphere - random density, haze, etc.
		AtmosphereDensity = randomRange(0.2, 1.0),
		AtmosphereOffset = randomRange(0, 0.6),
		AtmosphereColor = randomColor(30, 150),
		AtmosphereDecay = randomColor(10, 80),
		AtmosphereGlare = randomRange(0, 0.5),
		AtmosphereHaze = randomRange(0.5, 8.0),
		
		-- Weather effects
		RainEnabled = shouldRain,
		LightningEnabled = shouldLightning,
	}
	
	-- Ensure fog end is always greater than fog start
	if profile.FogEnd <= profile.FogStart then
		profile.FogEnd = profile.FogStart + randomRange(50, 300)
	end
	
	print(string.format("[WeatherService] Generated random lighting profile: %s", profile.Name))
	print(string.format("  Brightness: %.2f, Haze: %.2f, Density: %.2f, Fog: %.0f-%.0f", 
		profile.Brightness, profile.AtmosphereHaze, profile.AtmosphereDensity, profile.FogStart, profile.FogEnd))
	print(string.format("  Rain: %s, Lightning: %s", 
		tostring(profile.RainEnabled), tostring(profile.LightningEnabled)))
	
	return profile
end

-- Apply a custom lighting profile (from GenerateRandomLightingProfile or custom)
function WeatherService:ApplyLightingProfile(profile, transitionTime)
	transitionTime = transitionTime or 3
	
	if not profile then
		warn("[WeatherService] No profile provided")
		return false
	end
	
	-- Update replica with the custom profile
	self.weatherReplica:SetValue({"CurrentWeather"}, profile.Name or "Custom")
	self.weatherReplica:SetValue({"TransitionTime"}, transitionTime)
	self.weatherReplica:SetValue({"Settings"}, profile)
	
	-- Update clock time
	if profile.ClockTime then
		self._currentTime = profile.ClockTime
		Lighting.ClockTime = self._currentTime
		self.weatherReplica:SetValue({"ClockTime"}, self._currentTime)
	end
	
	-- Apply rain/lightning settings if specified in profile
	if profile.RainEnabled ~= nil then
		self:SetRainEnabled(profile.RainEnabled)
	end
	
	if profile.LightningEnabled ~= nil then
		self:SetLightningEnabled(profile.LightningEnabled)
	end
	
	print(string.format("[WeatherService] Applied lighting profile: %s (transition: %.1fs)", 
		profile.Name or "Custom", transitionTime))
	
	return true
end

-- Generate and apply a new random lighting profile
-- Call this during world regeneration for a fresh atmosphere each time
function WeatherService:RandomizeLighting(transitionTime)
	local profile = self:GenerateRandomLightingProfile()
	self:ApplyLightingProfile(profile, transitionTime or 3)
	return profile
end

-- === KNIT LIFECYCLE ===

function WeatherService:KnitInit()
	initReplica(self)
end

function WeatherService:KnitStart()
	-- Get LoadingService for progress updates
	local LoadingService = nil
	pcall(function()
		LoadingService = Knit.GetService("LoadingService")
	end)
	
	if LoadingService then
		LoadingService:UpdateStatus("WeatherService", "Initializing weather system...", 0)
	end
	
	-- Start the day/night cycle (disabled by default - stays night)
	startDayNightCycle(self)
	--("[WeatherService] Started - Day/night cycle DISABLED, fixed at night")
	
	if LoadingService then
		LoadingService:UpdateStatus("WeatherService", "Weather system ready", 1)
		LoadingService:MarkStepComplete("WeatherService")
	end
end

return WeatherService

