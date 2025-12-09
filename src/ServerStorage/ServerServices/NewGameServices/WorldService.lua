--[[
	WorldService
	Handles server-side world setup - removing baseplate, etc.
]]

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lighting = game:GetService("Lighting")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local Knit = require(Packages.Knit)

local WorldService = Knit.CreateService {
	Name = "WorldService",
	Client = {},
}

-- === BASEPLATE REMOVAL ===

function WorldService:RemoveBaseplate()
	-- Check multiple common names
	local baseplateNames = {
		"Baseplate"
	}
	
	for _, name in ipairs(baseplateNames) do
		local baseplate = Workspace:FindFirstChild(name)
		if baseplate and baseplate:IsA("BasePart") then
			baseplate:Destroy()
			print("[WorldService] Removed:", name)
		end
	end
	
	-- Also search for any large flat part that might be a baseplate
	for _, child in ipairs(Workspace:GetChildren()) do
		if child:IsA("BasePart") then
			local name = child.Name:lower()
			if name:find("base") or name:find("plate") or name:find("floor") then
				-- Check if it's large and flat (typical baseplate characteristics)
				if child.Size.X > 100 or child.Size.Z > 100 then
					child:Destroy()
					print("[WorldService] Removed large base part:", child.Name)
				end
			end
		end
	end
end

-- === LIGHTING SETUP (Horror Atmosphere) ===

function WorldService:SetupHorrorLighting()
	-- Dark, oppressive lighting for horror atmosphere
	Lighting.Ambient = Color3.fromRGB(20, 18, 15)
	Lighting.OutdoorAmbient = Color3.fromRGB(30, 25, 20)
	Lighting.Brightness = 0.5
	Lighting.ClockTime = 0 -- Midnight
	Lighting.GeographicLatitude = 45
	Lighting.FogColor = Color3.fromRGB(10, 8, 5)
	Lighting.FogEnd = 200
	Lighting.FogStart = 20
	
	-- Remove existing sky if any
	local existingSky = Lighting:FindFirstChildOfClass("Sky")
	if existingSky then
		existingSky:Destroy()
	end
	
	-- Remove existing atmosphere if any
	local existingAtmo = Lighting:FindFirstChildOfClass("Atmosphere")
	if existingAtmo then
		existingAtmo:Destroy()
	end
	
	-- Add dark atmosphere
	local atmosphere = Instance.new("Atmosphere")
	atmosphere.Density = 0.4
	atmosphere.Offset = 0.1
	atmosphere.Color = Color3.fromRGB(50, 40, 30)
	atmosphere.Decay = Color3.fromRGB(30, 25, 20)
	atmosphere.Glare = 0
	atmosphere.Haze = 2
	atmosphere.Parent = Lighting
	
	-- Add color correction for horror feel
	local colorCorrection = Lighting:FindFirstChildOfClass("ColorCorrectionEffect")
	if not colorCorrection then
		colorCorrection = Instance.new("ColorCorrectionEffect")
		colorCorrection.Parent = Lighting
	end
	colorCorrection.Brightness = -0.05
	colorCorrection.Contrast = 0.15
	colorCorrection.Saturation = -0.3
	colorCorrection.TintColor = Color3.fromRGB(255, 240, 220)
	
	print("[WorldService] Horror lighting applied")
end

-- === CLIENT METHODS ===

function WorldService.Client:RequestRemoveBaseplate()
	self.Server:RemoveBaseplate()
end

-- === KNIT LIFECYCLE ===

function WorldService:KnitInit()
end

function WorldService:KnitStart()
	-- Automatically remove baseplate on start
	self:RemoveBaseplate()
	
	-- Setup horror lighting
	--self:SetupHorrorLighting()
	
	print("[WorldService] World initialized")
end

return WorldService

addcommand				