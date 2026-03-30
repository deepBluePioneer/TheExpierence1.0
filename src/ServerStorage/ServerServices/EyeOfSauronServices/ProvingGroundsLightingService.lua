local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Knit = require(ReplicatedStorage.Packages.Knit)

local ProvingGroundsLightingService = Knit.CreateService({
	Name = "ProvingGroundsLightingService",
	Client = {},
})

function ProvingGroundsLightingService:KnitInit() end

function ProvingGroundsLightingService:KnitStart()
	self:Apply()
end

function ProvingGroundsLightingService:Apply()
	Lighting.ClockTime = 6.5
	Lighting.Brightness = 1
	Lighting.Ambient = Color3.fromRGB(50, 45, 55)
	Lighting.OutdoorAmbient = Color3.fromRGB(80, 75, 85)
	Lighting.FogEnd = 600
	Lighting.FogStart = 60
	Lighting.FogColor = Color3.fromRGB(45, 40, 50)
	Lighting.EnvironmentDiffuseScale = 0.5
	Lighting.EnvironmentSpecularScale = 0.3
	Lighting.GeographicLatitude = 40

	local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
	if atmosphere then
		atmosphere.Density = 0.35
		atmosphere.Haze = 2
		atmosphere.Glare = 0.1
		atmosphere.Color = Color3.fromRGB(70, 65, 80)
		atmosphere.Decay = Color3.fromRGB(50, 45, 55)
	end

	local bloom = Lighting:FindFirstChild("Bloom")
	if bloom and bloom:IsA("BloomEffect") then
		bloom.Intensity = 0.15
		bloom.Size = 18
		bloom.Threshold = 1.2
	end

	local sunRays = Lighting:FindFirstChild("SunRays")
	if sunRays and sunRays:IsA("SunRaysEffect") then
		sunRays.Intensity = 0.02
		sunRays.Spread = 0.3
	end

	local cc = Lighting:FindFirstChild("ProvingGroundsCC")
	if not cc then
		cc = Instance.new("ColorCorrectionEffect")
		cc.Name = "ProvingGroundsCC"
		cc.Parent = Lighting
	end
	cc.Brightness = 0
	cc.Contrast = 0.15
	cc.Saturation = -0.4
	cc.TintColor = Color3.fromRGB(200, 190, 180)

	print("[ProvingGroundsLightingService] Dark lighting applied")
end

return ProvingGroundsLightingService
