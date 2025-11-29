local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Packages = ReplicatedStorage.Packages
local Knit = require(Packages.Knit)

local AmbienceService = Knit.CreateService {
	Name = "AmbienceService",
	Client = {},
}

-- Configuration for lobby ambience
local CONFIG = {
	-- Time settings (night)
	ClockTime = 21.5, -- 9:30 PM
	GeographicLatitude = 40,
	
	-- Lighting colors (bright night)
	Ambient = Color3.fromRGB(80, 85, 100),      -- Soft blue ambient
	OutdoorAmbient = Color3.fromRGB(70, 75, 95), -- Slightly darker outdoor
	ColorShift_Top = Color3.fromRGB(180, 180, 200), -- Moonlit sky tint
	ColorShift_Bottom = Color3.fromRGB(60, 65, 80), -- Ground shadow tint
	
	-- Brightness
	Brightness = 2.5, -- Bright for night
	EnvironmentDiffuseScale = 0.8,
	EnvironmentSpecularScale = 0.6,
	
	-- Fog settings
	FogColor = Color3.fromRGB(45, 50, 65), -- Dark blue-gray fog
	FogStart = 50,
	FogEnd = 400,
	
	-- Atmosphere settings
	Atmosphere = {
		Density = 0.35,
		Offset = 0.1,
		Color = Color3.fromRGB(130, 140, 170), -- Misty blue
		Decay = Color3.fromRGB(90, 100, 130),  -- Distant fog color
		Glare = 0.2,
		Haze = 2.5,
	},
	
	-- Sky settings
	Sky = {
		SkyboxBk = "rbxassetid://1234567890", -- Will use default if invalid
		SkyboxDn = "rbxassetid://1234567890",
		SkyboxFt = "rbxassetid://1234567890",
		SkyboxLf = "rbxassetid://1234567890",
		SkyboxRt = "rbxassetid://1234567890",
		SkyboxUp = "rbxassetid://1234567890",
		StarCount = 5000,
		MoonAngularSize = 15,
		MoonTextureId = "",
		SunAngularSize = 8,
		SunTextureId = "",
		CelestialBodiesShown = true,
	},
	
	-- Bloom effect
	Bloom = {
		Enabled = true,
		Intensity = 0.8,
		Size = 30,
		Threshold = 1.5,
	},
	
	-- Color correction
	ColorCorrection = {
		Enabled = true,
		Brightness = 0.05,
		Contrast = 0.1,
		Saturation = -0.1, -- Slightly desaturated for foggy night feel
		TintColor = Color3.fromRGB(240, 245, 255), -- Cool tint
	},
}

function AmbienceService:SetupLighting()
	-- Core lighting settings
	Lighting.ClockTime = CONFIG.ClockTime
	Lighting.GeographicLatitude = CONFIG.GeographicLatitude
	Lighting.Ambient = CONFIG.Ambient
	Lighting.OutdoorAmbient = CONFIG.OutdoorAmbient
	Lighting.ColorShift_Top = CONFIG.ColorShift_Top
	Lighting.ColorShift_Bottom = CONFIG.ColorShift_Bottom
	Lighting.Brightness = CONFIG.Brightness
	Lighting.EnvironmentDiffuseScale = CONFIG.EnvironmentDiffuseScale
	Lighting.EnvironmentSpecularScale = CONFIG.EnvironmentSpecularScale
	
	-- Fog
	Lighting.FogColor = CONFIG.FogColor
	Lighting.FogStart = CONFIG.FogStart
	Lighting.FogEnd = CONFIG.FogEnd
	
	print("[AmbienceService] Lighting configured")
end

function AmbienceService:SetupAtmosphere()
	-- Remove existing atmosphere
	local existingAtmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
	if existingAtmosphere then
		existingAtmosphere:Destroy()
	end
	
	local atmosphere = Instance.new("Atmosphere")
	atmosphere.Density = CONFIG.Atmosphere.Density
	atmosphere.Offset = CONFIG.Atmosphere.Offset
	atmosphere.Color = CONFIG.Atmosphere.Color
	atmosphere.Decay = CONFIG.Atmosphere.Decay
	atmosphere.Glare = CONFIG.Atmosphere.Glare
	atmosphere.Haze = CONFIG.Atmosphere.Haze
	atmosphere.Parent = Lighting
	
	print("[AmbienceService] Atmosphere configured")
end

function AmbienceService:SetupSky()
	-- Remove existing sky
	local existingSky = Lighting:FindFirstChildOfClass("Sky")
	if existingSky then
		existingSky:Destroy()
	end
	
	local sky = Instance.new("Sky")
	sky.StarCount = CONFIG.Sky.StarCount
	sky.MoonAngularSize = CONFIG.Sky.MoonAngularSize
	sky.SunAngularSize = CONFIG.Sky.SunAngularSize
	sky.CelestialBodiesShown = CONFIG.Sky.CelestialBodiesShown
	sky.Parent = Lighting
	
	print("[AmbienceService] Sky configured with", CONFIG.Sky.StarCount, "stars")
end

function AmbienceService:SetupPostEffects()
	-- Bloom
	local existingBloom = Lighting:FindFirstChild("LobbyBloom")
	if existingBloom then existingBloom:Destroy() end
	
	if CONFIG.Bloom.Enabled then
		local bloom = Instance.new("BloomEffect")
		bloom.Name = "LobbyBloom"
		bloom.Intensity = CONFIG.Bloom.Intensity
		bloom.Size = CONFIG.Bloom.Size
		bloom.Threshold = CONFIG.Bloom.Threshold
		bloom.Parent = Lighting
	end
	
	-- Color Correction
	local existingCC = Lighting:FindFirstChild("LobbyColorCorrection")
	if existingCC then existingCC:Destroy() end
	
	if CONFIG.ColorCorrection.Enabled then
		local cc = Instance.new("ColorCorrectionEffect")
		cc.Name = "LobbyColorCorrection"
		cc.Brightness = CONFIG.ColorCorrection.Brightness
		cc.Contrast = CONFIG.ColorCorrection.Contrast
		cc.Saturation = CONFIG.ColorCorrection.Saturation
		cc.TintColor = CONFIG.ColorCorrection.TintColor
		cc.Parent = Lighting
	end
	
	print("[AmbienceService] Post effects configured")
end

function AmbienceService:KnitInit()
	print("[AmbienceService] Initializing...")
end

function AmbienceService:KnitStart()
	print("[AmbienceService] Starting...")
	
	self:SetupLighting()
	self:SetupAtmosphere()
	self:SetupSky()
	self:SetupPostEffects()
	
	print("[AmbienceService] Lobby ambience ready - Bright foggy night")
end

return AmbienceService

