--[[
	ArmCannonController (now Lantern)
	Amnesia: The Dark Descent style lantern using ViewportFrame
	with world-space light for actual illumination
]]

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")

local Packages = game:GetService("ReplicatedStorage"):WaitForChild("Packages")
local Knit = require(Packages.Knit)

-- Lantern Config
local LANTERN = {
	-- Colors
	BrassColor = Color3.fromRGB(180, 140, 60),
	BrassDark = Color3.fromRGB(120, 90, 40),
	GlassColor = Color3.fromRGB(255, 240, 200),
	FlameColor = Color3.fromRGB(255, 180, 80),
	FlameColorAlt = Color3.fromRGB(255, 120, 40),
	
	-- Light settings
	LightColor = Color3.fromRGB(255, 200, 130),
	LightBrightness = 2,
	LightRange = 40,
	
	-- Flicker settings
	FlickerSpeed = 8,
	FlickerAmount = 0.3,
}

local ArmCannonController = Knit.CreateController {
	Name = "ArmCannonController",
	
	-- State
	_character = nil,
	_hrp = nil,
	_humanoid = nil,
	
	-- Viewport system
	_screenGui = nil,
	_viewportFrame = nil,
	_viewportCamera = nil,
	_lanternModel = nil,
	_lanternParts = {},
	
	-- World-space light
	_worldLight = nil,
	_worldLightPart = nil,
	
	-- Animation
	_time = 0,
	_flamePart = nil,
	
	-- Lantern positioning (held lower and to the side)
	_lanternOffset = CFrame.new(0.6, -0.6, -1.0),
	_lanternFOV = 70,
}

-- === VIEWPORT SETUP ===

function ArmCannonController:CreateViewport()
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")
	
	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "LanternViewport"
	screenGui.ResetOnSpawn = false
	screenGui.IgnoreGuiInset = true
	screenGui.DisplayOrder = 10
	screenGui.Parent = playerGui
	self._screenGui = screenGui
	
	local viewportFrame = Instance.new("ViewportFrame")
	viewportFrame.Name = "LanternViewport"
	viewportFrame.Size = UDim2.new(1, 0, 1, 0)
	viewportFrame.Position = UDim2.new(0, 0, 0, 0)
	viewportFrame.BackgroundTransparency = 1
	viewportFrame.ImageTransparency = 0
	viewportFrame.LightDirection = Vector3.new(-1, -1, -1)
	viewportFrame.LightColor = Color3.new(1, 0.9, 0.7)
	viewportFrame.Ambient = Color3.fromRGB(80, 60, 40)
	viewportFrame.Parent = screenGui
	self._viewportFrame = viewportFrame
	
	local viewportCamera = Instance.new("Camera")
	viewportCamera.FieldOfView = self._lanternFOV
	viewportCamera.Parent = viewportFrame
	viewportFrame.CurrentCamera = viewportCamera
	self._viewportCamera = viewportCamera
end

-- === LANTERN CREATION ===

function ArmCannonController:CreateLanternModel(parent)
	local lanternModel = Instance.new("Model")
	lanternModel.Name = "Lantern"
	
	local parts = {}
	
	-- 1. Handle (curved brass)
	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = Vector3.new(0.08, 0.4, 0.08)
	handle.Color = LANTERN.BrassColor
	handle.Material = Enum.Material.Metal
	handle.CanCollide = false
	handle.Anchored = true
	handle.Parent = lanternModel
	table.insert(parts, handle)
	
	-- 2. Handle Top Ring
	local handleRing = Instance.new("Part")
	handleRing.Name = "HandleRing"
	handleRing.Shape = Enum.PartType.Cylinder
	handleRing.Size = Vector3.new(0.05, 0.2, 0.2)
	handleRing.Color = LANTERN.BrassColor
	handleRing.Material = Enum.Material.Metal
	handleRing.CanCollide = false
	handleRing.Anchored = true
	handleRing.Parent = lanternModel
	table.insert(parts, handleRing)
	
	-- 3. Top Cap (brass dome)
	local topCap = Instance.new("Part")
	topCap.Name = "TopCap"
	topCap.Shape = Enum.PartType.Ball
	topCap.Size = Vector3.new(0.35, 0.25, 0.35)
	topCap.Color = LANTERN.BrassColor
	topCap.Material = Enum.Material.Metal
	topCap.CanCollide = false
	topCap.Anchored = true
	topCap.Parent = lanternModel
	table.insert(parts, topCap)
	
	-- 4. Top Vent
	local topVent = Instance.new("Part")
	topVent.Name = "TopVent"
	topVent.Shape = Enum.PartType.Cylinder
	topVent.Size = Vector3.new(0.15, 0.15, 0.15)
	topVent.Color = LANTERN.BrassDark
	topVent.Material = Enum.Material.Metal
	topVent.CanCollide = false
	topVent.Anchored = true
	topVent.Parent = lanternModel
	table.insert(parts, topVent)
	
	-- 5. Glass Chamber (main body)
	local glassChamber = Instance.new("Part")
	glassChamber.Name = "GlassChamber"
	glassChamber.Size = Vector3.new(0.3, 0.5, 0.3)
	glassChamber.Color = LANTERN.GlassColor
	glassChamber.Material = Enum.Material.Glass
	glassChamber.Transparency = 0.6
	glassChamber.CanCollide = false
	glassChamber.Anchored = true
	glassChamber.Parent = lanternModel
	table.insert(parts, glassChamber)
	
	-- 6. Flame (inner glow)
	local flame = Instance.new("Part")
	flame.Name = "Flame"
	flame.Shape = Enum.PartType.Ball
	flame.Size = Vector3.new(0.15, 0.25, 0.15)
	flame.Color = LANTERN.FlameColor
	flame.Material = Enum.Material.Neon
	flame.CanCollide = false
	flame.Anchored = true
	flame.Parent = lanternModel
	table.insert(parts, flame)
	self._flamePart = flame
	
	-- 7. Brass Frame Bars (4 vertical)
	for i = 1, 4 do
		local bar = Instance.new("Part")
		bar.Name = "FrameBar" .. i
		bar.Size = Vector3.new(0.03, 0.5, 0.03)
		bar.Color = LANTERN.BrassColor
		bar.Material = Enum.Material.Metal
		bar.CanCollide = false
		bar.Anchored = true
		bar.Parent = lanternModel
		table.insert(parts, bar)
	end
	
	-- 11. Bottom Ring
	local bottomRing = Instance.new("Part")
	bottomRing.Name = "BottomRing"
	bottomRing.Shape = Enum.PartType.Cylinder
	bottomRing.Size = Vector3.new(0.08, 0.35, 0.35)
	bottomRing.Color = LANTERN.BrassColor
	bottomRing.Material = Enum.Material.Metal
	bottomRing.CanCollide = false
	bottomRing.Anchored = true
	bottomRing.Parent = lanternModel
	table.insert(parts, bottomRing)
	
	-- 12. Fuel Base
	local fuelBase = Instance.new("Part")
	fuelBase.Name = "FuelBase"
	fuelBase.Size = Vector3.new(0.25, 0.15, 0.25)
	fuelBase.Color = LANTERN.BrassDark
	fuelBase.Material = Enum.Material.Metal
	fuelBase.CanCollide = false
	fuelBase.Anchored = true
	fuelBase.Parent = lanternModel
	table.insert(parts, fuelBase)
	
	lanternModel.Parent = parent
	return lanternModel, parts
end

function ArmCannonController:CreateWorldLight()
	-- Create invisible part to hold the world-space light
	self._worldLightPart = Instance.new("Part")
	self._worldLightPart.Name = "LanternWorldLight"
	self._worldLightPart.Size = Vector3.new(0.1, 0.1, 0.1)
	self._worldLightPart.Transparency = 1
	self._worldLightPart.CanCollide = false
	self._worldLightPart.CanQuery = false
	self._worldLightPart.CanTouch = false
	self._worldLightPart.Anchored = true
	self._worldLightPart.Parent = Workspace
	
	-- Create the actual point light
	self._worldLight = Instance.new("PointLight")
	self._worldLight.Name = "LanternLight"
	self._worldLight.Color = LANTERN.LightColor
	self._worldLight.Brightness = LANTERN.LightBrightness
	self._worldLight.Range = LANTERN.LightRange
	self._worldLight.Shadows = true
	self._worldLight.Parent = self._worldLightPart
end

function ArmCannonController:CreateArmCannon(character)
	self._character = character
	self._hrp = character:FindFirstChild("HumanoidRootPart")
	self._humanoid = character:FindFirstChildOfClass("Humanoid")
	
	-- Hide character arms (optional - can keep visible for lantern)
	local armParts = {
		"RightUpperArm", "RightLowerArm", "RightHand",
	}
	for _, partName in ipairs(armParts) do
		local part = character:FindFirstChild(partName)
		if part then
			part.Transparency = 1
			for _, child in ipairs(part:GetChildren()) do
				if child:IsA("BasePart") then
					child.Transparency = 1
				end
			end
		end
	end
	
	-- Create viewport system
	self:CreateViewport()
	
	-- Create lantern model in viewport
	self._lanternModel, self._lanternParts = self:CreateLanternModel(self._viewportFrame)
	
	-- Create world-space light
	self:CreateWorldLight()
	
	self._time = 0
end

-- === LANTERN UPDATE ===

function ArmCannonController:UpdateLanternParts(parts, baseCFrame)
	local down = Vector3.new(0, -1, 0)
	
	-- 1. Handle
	if parts[1] then
		parts[1].CFrame = baseCFrame * CFrame.new(0, 0.35, 0)
	end
	
	-- 2. Handle Ring
	if parts[2] then
		parts[2].CFrame = baseCFrame * CFrame.new(0, 0.55, 0) * CFrame.Angles(0, 0, math.rad(90))
	end
	
	-- 3. Top Cap
	if parts[3] then
		parts[3].CFrame = baseCFrame * CFrame.new(0, 0.15, 0)
	end
	
	-- 4. Top Vent
	if parts[4] then
		parts[4].CFrame = baseCFrame * CFrame.new(0, 0.25, 0)
	end
	
	-- 5. Glass Chamber
	if parts[5] then
		parts[5].CFrame = baseCFrame * CFrame.new(0, -0.15, 0)
	end
	
	-- 6. Flame (animated)
	if parts[6] then
		local flicker = math.sin(self._time * LANTERN.FlickerSpeed) * 0.02
		local sizeFlicker = 1 + math.sin(self._time * LANTERN.FlickerSpeed * 1.3) * 0.1
		parts[6].CFrame = baseCFrame * CFrame.new(0, -0.12 + flicker, 0)
		parts[6].Size = Vector3.new(0.15 * sizeFlicker, 0.25 * sizeFlicker, 0.15 * sizeFlicker)
		
		-- Alternate flame color
		if math.sin(self._time * LANTERN.FlickerSpeed * 2) > 0.5 then
			parts[6].Color = LANTERN.FlameColorAlt
		else
			parts[6].Color = LANTERN.FlameColor
		end
	end
	
	-- 7-10. Frame Bars
	local barAngles = {0, 90, 180, 270}
	for i = 1, 4 do
		if parts[6 + i] then
			local angle = math.rad(barAngles[i])
			local offset = Vector3.new(math.cos(angle) * 0.14, -0.15, math.sin(angle) * 0.14)
			parts[6 + i].CFrame = baseCFrame * CFrame.new(offset)
		end
	end
	
	-- 11. Bottom Ring
	if parts[11] then
		parts[11].CFrame = baseCFrame * CFrame.new(0, -0.4, 0)
	end
	
	-- 12. Fuel Base
	if parts[12] then
		parts[12].CFrame = baseCFrame * CFrame.new(0, -0.5, 0)
	end
end

function ArmCannonController:UpdateArmCannon(dt)
	if not self._viewportCamera or not self._lanternModel then return end
	
	local camera = Workspace.CurrentCamera
	if not camera then return end
	
	self._time = self._time + dt
	
	local cameraCF = camera.CFrame
	
	-- Match viewport camera to world camera
	self._viewportCamera.CFrame = cameraCF
	
	-- Lantern position with slight sway
	local sway = math.sin(self._time * 2) * 0.02
	local lanternBaseCF = cameraCF * self._lanternOffset * CFrame.new(sway, 0, 0)
	
	-- Update viewport lantern
	self:UpdateLanternParts(self._lanternParts, lanternBaseCF)
	
	-- Update world-space light position (follows lantern)
	if self._worldLightPart then
		-- Position light slightly in front and at lantern position
		local worldLightPos = cameraCF * self._lanternOffset * CFrame.new(0, 0, 0.5)
		self._worldLightPart.CFrame = worldLightPos
		
		-- Flicker the light brightness
		if self._worldLight then
			local flickerBrightness = LANTERN.LightBrightness * (1 + math.sin(self._time * LANTERN.FlickerSpeed) * LANTERN.FlickerAmount)
			self._worldLight.Brightness = flickerBrightness
		end
	end
end

function ArmCannonController:DestroyArmCannon()
	-- Destroy viewport
	if self._screenGui then
		self._screenGui:Destroy()
		self._screenGui = nil
	end
	self._viewportFrame = nil
	self._viewportCamera = nil
	self._lanternModel = nil
	self._lanternParts = {}
	self._flamePart = nil
	
	-- Destroy world light
	if self._worldLightPart then
		self._worldLightPart:Destroy()
		self._worldLightPart = nil
	end
	self._worldLight = nil
	
	-- Show arms again
	if self._character then
		local armParts = {
			"RightUpperArm", "RightLowerArm", "RightHand",
		}
		for _, partName in ipairs(armParts) do
			local part = self._character:FindFirstChild(partName)
			if part then
				part.Transparency = 0
			end
		end
	end
end

-- === PUBLIC API ===

function ArmCannonController:SetRecoilOffset(offset)
	-- Not used for lantern, but kept for compatibility
end

function ArmCannonController:GetCannonTipPosition()
	-- Returns lantern position for gravity gun raycast origin
	local camera = Workspace.CurrentCamera
	if not camera then return nil, nil end
	
	local cameraCF = camera.CFrame
	local aimDir = cameraCF.LookVector
	
	return cameraCF.Position, aimDir
end

function ArmCannonController:GetCannonParts()
	return self._lanternParts
end

function ArmCannonController:SetLightEnabled(enabled)
	if self._worldLight then
		self._worldLight.Enabled = enabled
	end
end

function ArmCannonController:SetLightBrightness(brightness)
	LANTERN.LightBrightness = brightness
end

function ArmCannonController:SetLightRange(range)
	LANTERN.LightRange = range
	if self._worldLight then
		self._worldLight.Range = range
	end
end

function ArmCannonController:SetLightColor(color)
	LANTERN.LightColor = color
	if self._worldLight then
		self._worldLight.Color = color
	end
end

function ArmCannonController:Cleanup()
	self:DestroyArmCannon()
	self._character = nil
	self._hrp = nil
	self._humanoid = nil
end

-- === KNIT LIFECYCLE ===

function ArmCannonController:KnitInit()
end

function ArmCannonController:KnitStart()
	-- This controller is managed by ProceduralLocomotionController
end

return ArmCannonController
