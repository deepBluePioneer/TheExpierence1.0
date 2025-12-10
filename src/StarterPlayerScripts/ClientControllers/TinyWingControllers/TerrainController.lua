--[[
	TerrainController
	
	Client-side terrain height calculations.
	Uses the same wave formula as the server terrain generation.
	All calculations happen locally - no network calls.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local Knit = require(Packages.Knit)

local TerrainController = Knit.CreateController {
	Name = "TerrainController",
}

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         CONFIGURATION                                       ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

-- Must match WavyTerrainService exactly!
local CONFIG = {
	-- Terrain dimensions
	TerrainWidth = 80,
	TerrainLength = 2000,
	TerrainStart = -200,
	BaseHeight = 50,
	
	-- Wave parameters (same as server)
	Waves = {
		{ Frequency = 0.012, Amplitude = 40, Phase = 0 },
		{ Frequency = 0.028, Amplitude = 20, Phase = 1.5 },
		{ Frequency = 0.06, Amplitude = 10, Phase = 3.2 },
		{ Frequency = 0.12, Amplitude = 4, Phase = 0.7 },
	},
	
	-- Seed for reproducible terrain
	Seed = 12345,
}

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         HEIGHT CALCULATION                                  ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

-- Calculate terrain height at X position (primary formula)
local function calculateHeight(x)
	local height = CONFIG.BaseHeight
	
	for _, wave in ipairs(CONFIG.Waves) do
		local phase = wave.Phase + (CONFIG.Seed * 0.001)
		height = height + math.sin(x * wave.Frequency + phase) * wave.Amplitude
	end
	
	return height
end

-- Calculate terrain height with Z variation (smooth terrain formula)
local function calculateSmoothHeight(x, z)
	z = z or 0
	local height = calculateHeight(x)
	
	-- Add subtle Z variation for natural look
	local zVariation = math.sin(z * 0.02 + CONFIG.Seed * 0.1) * 2
	return height + zVariation
end

-- Calculate slope at X position
local function calculateSlope(x)
	local delta = 0.1
	local h1 = calculateHeight(x - delta)
	local h2 = calculateHeight(x + delta)
	return (h2 - h1) / (2 * delta)
end

-- Calculate slope angle in radians
local function calculateSlopeAngle(x)
	return math.atan(calculateSlope(x))
end

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         KNIT LIFECYCLE                                      ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

function TerrainController:KnitInit()
	print("[TerrainController] Initializing...")
end

function TerrainController:KnitStart()
	print("[TerrainController] Started - client-side terrain calculations ready")
end

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         PUBLIC API                                          ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

-- Get height at X position (no Z variation)
function TerrainController:GetHeightAtX(x)
	return calculateHeight(x)
end

-- Get height at X, Z position (with Z variation)
function TerrainController:GetHeightAt(x, z)
	return calculateSmoothHeight(x, z)
end

-- Get slope at X position
function TerrainController:GetSlopeAtX(x)
	return calculateSlope(x)
end

-- Get slope angle in radians at X position
function TerrainController:GetSlopeAngleAtX(x)
	return calculateSlopeAngle(x)
end

-- Get terrain bounds
function TerrainController:GetBounds()
	return {
		StartX = CONFIG.TerrainStart,
		EndX = CONFIG.TerrainStart + CONFIG.TerrainLength,
		Width = CONFIG.TerrainWidth,
		Length = CONFIG.TerrainLength,
	}
end

-- Get config
function TerrainController:GetConfig()
	return CONFIG
end

-- Update a config value (for testing)
function TerrainController:SetConfig(key, value)
	if CONFIG[key] ~= nil then
		CONFIG[key] = value
		return true
	end
	return false
end

return TerrainController

