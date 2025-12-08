--[[
	CameraController
	Handles core camera mechanics: scriptable camera, mouse look, zoom, character rotation
	Camera shake is handled by CameraShakeController
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local Knit = require(Packages.Knit)
local Input = require(Packages.Input)
local Mouse = Input.Mouse
local Keyboard = Input.Keyboard

local CameraController = Knit.CreateController {
	Name = "CameraController",
	_cameraControlConnection = nil,
	_shakeController = nil,
}

-- === CONFIG ===
local CAMERA_CONFIG = {
	-- Camera Controls
	ControlsEnabled = true,
	MouseSensitivity = 0.15,
	SmoothingFactor = 0.2,
	MinZoom = 1.0,
	MaxZoom = 4.0,
	ZoomSpeed = 0.5,
	MinPitch = -80,
	MaxPitch = 80,
	CameraOffset = Vector3.new(0, 0, 0),
	CharacterRotationSpeed = 15,
	
	-- Mouse/Cursor
	HideCursor = true,
	LockCursor = true,
	
	-- Uneasy/Horror Effect
	UneasyEffectEnabled = true,
	
	-- Camera Sway (drifting)
	SwayAmount = 0.015,          -- How much the camera drifts
	SwaySpeed = 0.5,             -- Speed of primary sway
	SwaySpeed2 = 0.3,            -- Speed of secondary sway (creates irregular motion)
	SwaySpeed3 = 0.7,            -- Speed of tertiary sway
	
	-- FOV Breathing (creates claustrophobic feeling)
	FOVBreathingEnabled = true,
	FOVBreathingAmount = 5,      -- FOV variation in degrees
	FOVBreathingSpeed = 0.4,     -- Speed of FOV change
	FOVBreathingSpeed2 = 0.6,    -- Secondary speed for irregular effect
	
	-- Roll (tilt)
	RollAmount = 0.018,          -- Max roll in radians
	RollSpeed = 0.4,
}

-- === STATE ===
local cameraState = {
	yaw = 0,
	pitch = 0,
	targetYaw = 0,
	targetPitch = 0,
	currentZoom = 1.0,
	targetZoom = 1.0,
	initialized = false,
	lastCharacterYaw = 0,
	
	-- Uneasy effect state
	effectTime = 0,
}

-- === INPUT ===
local mouse = Mouse.new()
local keyboard = Keyboard.new()

-- === CURSOR CONTROL ===

local function lockAndHideCursor()
	if CAMERA_CONFIG.HideCursor then
		UserInputService.MouseIconEnabled = false
	end
	if CAMERA_CONFIG.LockCursor then
		mouse:LockCenter()
	end
end

local function unlockAndShowCursor()
	UserInputService.MouseIconEnabled = true
	mouse:Unlock()
end

-- === BODY TRANSPARENCY ===

-- Parts to KEEP visible (arms and hands)
local VISIBLE_PARTS = {
	-- R15 arms
	["LeftUpperArm"] = true,
	["LeftLowerArm"] = true,
	["LeftHand"] = true,
	["RightUpperArm"] = true,
	["RightLowerArm"] = true,
	["RightHand"] = true,
	-- R6 arms
	["Left Arm"] = true,
	["Right Arm"] = true,
}

-- Parts to HIDE
local HIDDEN_PARTS = {
	-- Head
	["Head"] = true,
	-- R15 torso
	["UpperTorso"] = true,
	["LowerTorso"] = true,
	-- R15 legs
	["LeftUpperLeg"] = true,
	["LeftLowerLeg"] = true,
	["LeftFoot"] = true,
	["RightUpperLeg"] = true,
	["RightLowerLeg"] = true,
	["RightFoot"] = true,
	-- R6
	["Torso"] = true,
	["Left Leg"] = true,
	["Right Leg"] = true,
	-- Root part (invisible anyway but just in case)
	["HumanoidRootPart"] = true,
}

local function makeBodyInvisible(character)
	if not character then return end
	
	-- Hide body parts (except arms/hands)
	for _, part in ipairs(character:GetDescendants()) do
		if part:IsA("BasePart") then
			local partName = part.Name
			
			-- Check if this is a part we should hide
			if HIDDEN_PARTS[partName] then
				part.LocalTransparencyModifier = 1
				
				-- Also hide decals on head
				if partName == "Head" then
					for _, child in ipairs(part:GetChildren()) do
						if child:IsA("Decal") then
							child.Transparency = 1
						end
					end
				end
			end
		end
	end
	
	-- Handle accessories - hide head/torso ones, keep arm ones
	for _, accessory in ipairs(character:GetChildren()) do
		if accessory:IsA("Accessory") then
			local handle = accessory:FindFirstChild("Handle")
			if handle then
				local attachment = handle:FindFirstChildOfClass("Attachment")
				if attachment then
					local attachName = attachment.Name:lower()
					
					-- Hide head/hair/face accessories
					if attachName:find("hat") or attachName:find("hair") or attachName:find("face") or attachName:find("head") then
						handle.LocalTransparencyModifier = 1
					end
					
					-- Hide body/torso accessories
					if attachName:find("body") or attachName:find("torso") or attachName:find("waist") or 
					   attachName:find("back") or attachName:find("neck") or attachName:find("shoulder") then
						handle.LocalTransparencyModifier = 1
					end
					
					-- Hide leg accessories
					if attachName:find("leg") or attachName:find("foot") then
						handle.LocalTransparencyModifier = 1
					end
				end
			end
		end
	end
	
	-- Handle clothing
	for _, item in ipairs(character:GetChildren()) do
		if item:IsA("Shirt") or item:IsA("Pants") then
			-- Can't fully hide these, but we've hidden the parts they're on
		end
	end
end

-- Alias for backward compatibility
local function makeHeadInvisible(character)
	makeBodyInvisible(character)
end

-- === CAMERA UPDATE ===

local function updateCamera(deltaTime)
	if not CAMERA_CONFIG.ControlsEnabled then return end
	if not cameraState.initialized then return end
	
	local camera = workspace.CurrentCamera
	local player = Players.LocalPlayer
	local character = player.Character
	if not character then return end
	
	local head = character:FindFirstChild("Head")
	local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not head or not humanoidRootPart or not humanoid then return end
	
	-- Ensure camera stays scriptable
	if camera.CameraType ~= Enum.CameraType.Scriptable then
		camera.CameraType = Enum.CameraType.Scriptable
	end
	
	-- Ensure mouse stays locked
	if UserInputService.MouseBehavior ~= Enum.MouseBehavior.LockCenter then
		UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
	end
	
	-- Smooth interpolation
	local smoothing = 1 - math.pow(1 - CAMERA_CONFIG.SmoothingFactor, deltaTime * 60)
	
	cameraState.yaw = cameraState.yaw + (cameraState.targetYaw - cameraState.yaw) * smoothing
	cameraState.pitch = cameraState.pitch + (cameraState.targetPitch - cameraState.pitch) * smoothing
	
	-- Zoom
	local prevZoom = cameraState.currentZoom
	cameraState.currentZoom = cameraState.currentZoom + 
		(cameraState.targetZoom - cameraState.currentZoom) * smoothing
	
	-- Update effect time
	cameraState.effectTime = cameraState.effectTime + deltaTime
	local t = cameraState.effectTime
	
	-- Apply zoom via FieldOfView with breathing effect
	local baseFOV = 70
	local fovBreathing = 0
	
	if CAMERA_CONFIG.UneasyEffectEnabled and CAMERA_CONFIG.FOVBreathingEnabled then
		-- Combine multiple sine waves for irregular, uneasy breathing
		fovBreathing = math.sin(t * CAMERA_CONFIG.FOVBreathingSpeed) * CAMERA_CONFIG.FOVBreathingAmount * 0.6
		fovBreathing = fovBreathing + math.sin(t * CAMERA_CONFIG.FOVBreathingSpeed2) * CAMERA_CONFIG.FOVBreathingAmount * 0.3
		fovBreathing = fovBreathing + math.sin(t * CAMERA_CONFIG.FOVBreathingSpeed * 1.7) * CAMERA_CONFIG.FOVBreathingAmount * 0.1
	end
	
	camera.FieldOfView = (baseFOV + fovBreathing) / cameraState.currentZoom
	
	-- Sync zoom with UI controller (only if changed significantly)
	if math.abs(cameraState.currentZoom - prevZoom) > 0.001 then
		local uiController = Knit.GetController("CameraUIController")
		if uiController and uiController.SetZoomLevel then
			uiController:SetZoomLevel(cameraState.currentZoom)
		end
	end
	
	-- Get camera shake from CameraShakeController
	local shakePos = Vector3.zero
	local shakeRot = Vector3.zero
	local shakeController = Knit.GetController("CameraShakeController")
	if shakeController then
		shakePos = shakeController:GetShakeOffset()
		shakeRot = shakeController:GetShakeRotation()
	end
	
	-- Camera position & rotation
	local cameraPosition = head.Position + CAMERA_CONFIG.CameraOffset
	local cameraRotation = CFrame.Angles(0, cameraState.yaw, 0) * 
		CFrame.Angles(cameraState.pitch, 0, 0)
	
	-- Apply shake from CameraShakeController
	local shakeCFrame = CFrame.new(shakePos) * CFrame.Angles(shakeRot.X, shakeRot.Y, shakeRot.Z)
	
	-- Calculate uneasy sway effect
	local swayYaw = 0
	local swayPitch = 0
	local swayRoll = 0
	
	if CAMERA_CONFIG.UneasyEffectEnabled then
		-- Combine multiple sine waves for irregular, unsettling motion
		-- Primary sway (slow drift)
		swayYaw = math.sin(t * CAMERA_CONFIG.SwaySpeed) * CAMERA_CONFIG.SwayAmount
		swayYaw = swayYaw + math.sin(t * CAMERA_CONFIG.SwaySpeed2 * 1.3) * CAMERA_CONFIG.SwayAmount * 0.5
		
		-- Pitch sway (slightly different frequencies)
		swayPitch = math.sin(t * CAMERA_CONFIG.SwaySpeed * 0.8) * CAMERA_CONFIG.SwayAmount * 0.7
		swayPitch = swayPitch + math.cos(t * CAMERA_CONFIG.SwaySpeed3) * CAMERA_CONFIG.SwayAmount * 0.3
		
		-- Roll (creates unease, like being off-balance)
		swayRoll = math.sin(t * CAMERA_CONFIG.RollSpeed) * CAMERA_CONFIG.RollAmount
		swayRoll = swayRoll + math.sin(t * CAMERA_CONFIG.RollSpeed * 1.6) * CAMERA_CONFIG.RollAmount * 0.4
	end
	
	local swayCFrame = CFrame.Angles(swayPitch, swayYaw, swayRoll)
	
	-- Set camera CFrame with all effects
	camera.CFrame = CFrame.new(cameraPosition) * cameraRotation * shakeCFrame * swayCFrame
	
	-- Character rotation
	local characterRotSpeed = CAMERA_CONFIG.CharacterRotationSpeed * deltaTime
	local targetCharacterYaw = cameraState.yaw
	
	local yawDiff = targetCharacterYaw - cameraState.lastCharacterYaw
	if yawDiff > math.pi then
		yawDiff = yawDiff - 2 * math.pi
	elseif yawDiff < -math.pi then
		yawDiff = yawDiff + 2 * math.pi
	end
	
	local newCharacterYaw = cameraState.lastCharacterYaw + yawDiff * math.min(characterRotSpeed, 1)
	cameraState.lastCharacterYaw = newCharacterYaw
	
	local currentPos = humanoidRootPart.Position
	humanoidRootPart.CFrame = CFrame.new(currentPos) * CFrame.Angles(0, newCharacterYaw, 0)
end

-- === INITIALIZATION ===

local function initializeCamera()
	local camera = workspace.CurrentCamera
	local player = Players.LocalPlayer
	
	-- Set camera to scriptable mode
	camera.CameraType = Enum.CameraType.Scriptable
	
	-- Lock mouse to center
	UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
	
	-- Initialize from character facing direction
	local character = player.Character
	if character then
		local rootPart = character:FindFirstChild("HumanoidRootPart")
		if rootPart then
			local _, currentYaw, _ = rootPart.CFrame:ToEulerAnglesYXZ()
			cameraState.yaw = currentYaw
			cameraState.targetYaw = currentYaw
			cameraState.lastCharacterYaw = currentYaw
		end
		makeHeadInvisible(character)
	end
	cameraState.initialized = true
	
	-- Mouse movement for camera look
	UserInputService.InputChanged:Connect(function(input, gameProcessed)
		if not CAMERA_CONFIG.ControlsEnabled then return end
		if input.UserInputType == Enum.UserInputType.MouseMovement then
			local delta = input.Delta
			local sensitivity = CAMERA_CONFIG.MouseSensitivity
			
			cameraState.targetYaw = cameraState.targetYaw - delta.X * sensitivity * 0.01
			cameraState.targetPitch = math.clamp(
				cameraState.targetPitch - delta.Y * sensitivity * 0.01,
				math.rad(CAMERA_CONFIG.MinPitch),
				math.rad(CAMERA_CONFIG.MaxPitch)
			)
		end
	end)
	
	-- Mouse scroll for zoom
	mouse.Scrolled:Connect(function(scrollAmount)
		if not CAMERA_CONFIG.ControlsEnabled then return end
		cameraState.targetZoom = math.clamp(
			cameraState.targetZoom - scrollAmount * CAMERA_CONFIG.ZoomSpeed,
			CAMERA_CONFIG.MinZoom,
			CAMERA_CONFIG.MaxZoom
		)
	end)
	
	-- Character respawn handling
	player.CharacterAdded:Connect(function(newCharacter)
		local rootPart = newCharacter:WaitForChild("HumanoidRootPart", 5)
		if rootPart then
			camera.CameraType = Enum.CameraType.Scriptable
			UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
			
			local _, currentYaw, _ = rootPart.CFrame:ToEulerAnglesYXZ()
			cameraState.yaw = currentYaw
			cameraState.targetYaw = currentYaw
			cameraState.lastCharacterYaw = currentYaw
			
			makeHeadInvisible(newCharacter)
		end
	end)
	
	print("[CameraController] Initialized (shake handled by CameraShakeController)")
end

-- === KNIT LIFECYCLE ===

function CameraController:KnitInit()
	self.mouse = mouse
	self.keyboard = keyboard
end

function CameraController:KnitStart()
	-- Hide cursor
	UserInputService.MouseIconEnabled = false
	
	-- Initialize camera
	initializeCamera()
	
	-- Start update loop
	self._cameraControlConnection = RunService.RenderStepped:Connect(function(deltaTime)
		updateCamera(deltaTime)
	end)
end

-- === PUBLIC METHODS ===

function CameraController:GetZoomLevel()
	return cameraState.currentZoom
end

function CameraController:SetZoomLevel(zoom)
	cameraState.targetZoom = math.clamp(zoom, CAMERA_CONFIG.MinZoom, CAMERA_CONFIG.MaxZoom)
end

function CameraController:GetCameraState()
	return cameraState
end

function CameraController:SetControlsEnabled(enabled)
	CAMERA_CONFIG.ControlsEnabled = enabled
end

function CameraController:LockCursor()
	lockAndHideCursor()
end

function CameraController:UnlockCursor()
	unlockAndShowCursor()
end

function CameraController:GetMouse()
	return mouse
end

function CameraController:GetKeyboard()
	return keyboard
end

function CameraController:SetUneasyEffectEnabled(enabled)
	CAMERA_CONFIG.UneasyEffectEnabled = enabled
end

function CameraController:IsUneasyEffectEnabled()
	return CAMERA_CONFIG.UneasyEffectEnabled
end

function CameraController:SetUneasyIntensity(intensity)
	-- intensity 0-1, scales all uneasy effects
	CAMERA_CONFIG.SwayAmount = 0.008 * intensity
	CAMERA_CONFIG.FOVBreathingAmount = 3 * intensity
	CAMERA_CONFIG.RollAmount = 0.01 * intensity
end

return CameraController

