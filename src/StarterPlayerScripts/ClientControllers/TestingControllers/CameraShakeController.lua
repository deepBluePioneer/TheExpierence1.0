--[[
	CameraShakeController
	Handles camera shake effects that trigger at random intervals
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local Knit = require(Packages.Knit)
local Shake = require(Packages.Shake)

local CameraShakeController = Knit.CreateController {
	Name = "CameraShakeController",
	_currentShake = nil,
	_continuousSway = nil,  -- Continuous sway shake instance
	_swayOffset = Vector3.zero,
	_shakeOffset = Vector3.zero,
	_shakeRotation = Vector3.zero,
	_updateConnection = nil,
	_randomShakeEnabled = false,  -- Disable random shakes, use continuous sway instead
}

-- === CONFIG ===
local SHAKE_CONFIG = {
	-- Random shake timing
	MinTimeBetweenShakes = 1,    -- Minimum seconds between random shakes
	MaxTimeBetweenShakes = 5,   -- Maximum seconds between random shakes
	
	-- Continuous sway (always running)
	ContinuousSwayEnabled = true,
	ContinuousSway = {
		Amplitude = 5,
		Frequency = 100,        -- Slow, organic movement
		PositionInfluence = Vector3.new(0.5, 0.06, 0),  -- X/Y only, no Z
		RotationInfluence = Vector3.zero,  -- No rotation
	},
	
	-- Shake presets (X = left/right, Y = up/down, Z = 0 for no forward/backward)
	-- No rotation, only lateral position movement
	Presets = {
		-- Subtle breathing/handheld shake
		Subtle = {
			Amplitude = 5,
			Frequency = 1.0,
			FadeInTime = 0.01,
			FadeOutTime = 0.5,
			SustainTime = 0.5,
			PositionInfluence = Vector3.new(.5, .5, 0),  -- X/Y only, no Z
			RotationInfluence = Vector3.zero,  -- No rotation
		},
		-- Light shake (footsteps, small bump)
		Light = {
			Amplitude = 0.15,
			Frequency = 0.7,
			FadeInTime = 0.1,
			FadeOutTime = 0.4,
			SustainTime = 0.3,
			PositionInfluence = Vector3.new(0.1, 0.12, 0),  -- X/Y only, no Z
			RotationInfluence = Vector3.zero,  -- No rotation
		},
		-- Medium shake (nearby impact, stumble)
		Medium = {
			Amplitude = 0.3,
			Frequency = 0.5,
			FadeInTime = 0.05,
			FadeOutTime = 0.6,
			SustainTime = 0.4,
			PositionInfluence = Vector3.new(0.15, 0.2, 0),  -- X/Y only, no Z
			RotationInfluence = Vector3.zero,  -- No rotation
		},
		-- Heavy shake (explosion, big hit)
		Heavy = {
			Amplitude = 0.5,
			Frequency = 0.3,
			FadeInTime = 0.02,
			FadeOutTime = 0.8,
			SustainTime = 0.5,
			PositionInfluence = Vector3.new(0.25, 0.3, 0),  -- X/Y only, no Z
			RotationInfluence = Vector3.zero,  -- No rotation
		},
		-- Earthquake (sustained heavy shake)
		Earthquake = {
			Amplitude = 0.45,
			Frequency = 0.35,
			FadeInTime = 0.5,
			FadeOutTime = 1.0,
			SustainTime = 2.0,
			PositionInfluence = Vector3.new(0.2, 0.25, 0),  -- X/Y only, no Z
			RotationInfluence = Vector3.zero,  -- No rotation
		},
	},
	
	-- Which presets to use for random shakes (weighted)
	RandomShakeWeights = {
		Subtle = 100,  -- Only subtle shakes
	},
}

-- === HELPER FUNCTIONS ===

local function selectWeightedRandom(weights)
	local totalWeight = 0
	for _, weight in pairs(weights) do
		totalWeight = totalWeight + weight
	end
	
	local random = math.random() * totalWeight
	local cumulative = 0
	
	for name, weight in pairs(weights) do
		cumulative = cumulative + weight
		if random <= cumulative then
			return name
		end
	end
	
	-- Fallback
	return "Subtle"
end

-- === SHAKE FUNCTIONS ===

local function createShakeFromPreset(presetName)
	local preset = SHAKE_CONFIG.Presets[presetName]
	if not preset then
		preset = SHAKE_CONFIG.Presets.Subtle
	end
	
	local shake = Shake.new()
	shake.Amplitude = preset.Amplitude
	shake.Frequency = preset.Frequency
	shake.FadeInTime = preset.FadeInTime
	shake.FadeOutTime = preset.FadeOutTime
	shake.SustainTime = preset.SustainTime
	shake.Sustain = false
	shake.PositionInfluence = preset.PositionInfluence
	shake.RotationInfluence = preset.RotationInfluence
	
	return shake
end

local function triggerShake(self, presetName)
	-- Stop any existing shake
	if self._currentShake and self._currentShake:IsShaking() then
		self._currentShake:Stop()
	end
	
	-- Create and start new shake
	self._currentShake = createShakeFromPreset(presetName)
	self._currentShake:Start()
	
	print("[CameraShakeController] Triggered shake:", presetName)
end

local function updateShake(self)
	-- Update continuous sway (always running)
	if self._continuousSway and self._continuousSway:IsShaking() then
		local swayPos, _, _ = self._continuousSway:Update()
		self._swayOffset = swayPos
	end
	
	-- Update triggered shake (one-time events)
	if self._currentShake and self._currentShake:IsShaking() then
		local pos, rot, done = self._currentShake:Update()
		self._shakeOffset = pos
		self._shakeRotation = rot
		
		if done then
			self._shakeOffset = Vector3.zero
			self._shakeRotation = Vector3.zero
		end
	else
		-- Smoothly return to zero when no triggered shake
		self._shakeOffset = self._shakeOffset:Lerp(Vector3.zero, 0.1)
		self._shakeRotation = self._shakeRotation:Lerp(Vector3.zero, 0.1)
	end
end

local function startRandomShakeLoop(self)
	task.spawn(function()
		while true do
			-- Wait random time
			local waitTime = math.random(
				SHAKE_CONFIG.MinTimeBetweenShakes,
				SHAKE_CONFIG.MaxTimeBetweenShakes
			)
			task.wait(waitTime)
			
			-- Trigger random shake if enabled
			if self._randomShakeEnabled then
				local presetName = selectWeightedRandom(SHAKE_CONFIG.RandomShakeWeights)
				triggerShake(self, presetName)
			end
		end
	end)
end

local function startContinuousSway(self)
	if not SHAKE_CONFIG.ContinuousSwayEnabled then
		return
	end
	
	local swayConfig = SHAKE_CONFIG.ContinuousSway
	
	-- Create a sustained shake that loops forever
	local shake = Shake.new()
	shake.Amplitude = swayConfig.Amplitude
	shake.Frequency = swayConfig.Frequency
	shake.FadeInTime = 0.5
	shake.FadeOutTime = 0
	shake.SustainTime = 999999  -- Effectively infinite
	shake.Sustain = true  -- Keep it sustained
	shake.PositionInfluence = swayConfig.PositionInfluence
	shake.RotationInfluence = swayConfig.RotationInfluence
	
	shake:Start()
	self._continuousSway = shake
	
	print("[CameraShakeController] Continuous sway started")
end

-- === KNIT LIFECYCLE ===

function CameraShakeController:KnitInit()
	self._swayOffset = Vector3.zero
	self._shakeOffset = Vector3.zero
	self._shakeRotation = Vector3.zero
end

function CameraShakeController:KnitStart()
	-- Start update loop
	self._updateConnection = RunService.RenderStepped:Connect(function()
		updateShake(self)
	end)
	
	-- Start continuous sway (subtle handheld camera feel)
	startContinuousSway(self)
	
	-- Start random shake loop (disabled by default)
	if self._randomShakeEnabled then
		startRandomShakeLoop(self)
	end
	
	print("[CameraShakeController] Initialized with continuous sway")
end

-- === PUBLIC METHODS ===

-- Get current shake offset (position)
function CameraShakeController:GetShakeOffset()
	-- Combine continuous sway with any triggered shakes
	return self._swayOffset + self._shakeOffset
end

-- Get current shake rotation
function CameraShakeController:GetShakeRotation()
	return self._shakeRotation
end

-- Trigger a specific shake preset
function CameraShakeController:TriggerShake(presetName)
	triggerShake(self, presetName or "Light")
end

-- Trigger a subtle shake
function CameraShakeController:ShakeSubtle()
	triggerShake(self, "Subtle")
end

-- Trigger a light shake
function CameraShakeController:ShakeLight()
	triggerShake(self, "Light")
end

-- Trigger a medium shake
function CameraShakeController:ShakeMedium()
	triggerShake(self, "Medium")
end

-- Trigger a heavy shake
function CameraShakeController:ShakeHeavy()
	triggerShake(self, "Heavy")
end

-- Trigger an earthquake shake
function CameraShakeController:ShakeEarthquake()
	triggerShake(self, "Earthquake")
end

-- Enable/disable random shakes
function CameraShakeController:SetRandomShakesEnabled(enabled)
	self._randomShakeEnabled = enabled
end

-- Check if random shakes are enabled
function CameraShakeController:AreRandomShakesEnabled()
	return self._randomShakeEnabled
end

-- Stop any current shake immediately
function CameraShakeController:StopShake()
	if self._currentShake then
		self._currentShake:Stop()
	end
	self._shakeOffset = Vector3.zero
	self._shakeRotation = Vector3.zero
end

-- Create a custom shake
function CameraShakeController:TriggerCustomShake(config)
	if self._currentShake and self._currentShake:IsShaking() then
		self._currentShake:Stop()
	end
	
	local shake = Shake.new()
	shake.Amplitude = config.Amplitude or 0.1
	shake.Frequency = config.Frequency or 0.5
	shake.FadeInTime = config.FadeInTime or 0.1
	shake.FadeOutTime = config.FadeOutTime or 0.5
	shake.SustainTime = config.SustainTime or 0.3
	shake.Sustain = config.Sustain or false
	shake.PositionInfluence = config.PositionInfluence or Vector3.new(0.1, 0.12, 0)  -- X/Y only, no Z
	shake.RotationInfluence = config.RotationInfluence or Vector3.zero  -- No rotation by default
	
	print("[CameraShakeController] Triggered custom shake - Amplitude:", shake.Amplitude, "Frequency:", shake.Frequency)
	
	self._currentShake = shake
	shake:Start()
end

return CameraShakeController

