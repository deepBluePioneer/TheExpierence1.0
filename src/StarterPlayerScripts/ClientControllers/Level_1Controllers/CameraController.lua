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

-- === HEAD TRANSPARENCY ===

local function makeHeadInvisible(character)
	if not character then return end
	
	local head = character:FindFirstChild("Head")
	if head then
		head.LocalTransparencyModifier = 1
		for _, child in ipairs(head:GetChildren()) do
			if child:IsA("Decal") then
				child.Transparency = 1
			end
		end
	end
	
	for _, accessory in ipairs(character:GetChildren()) do
		if accessory:IsA("Accessory") then
			local handle = accessory:FindFirstChild("Handle")
			if handle then
				local attachment = handle:FindFirstChildOfClass("Attachment")
				if attachment then
					local attachName = attachment.Name:lower()
					if attachName:find("hat") or attachName:find("hair") or attachName:find("face") or attachName:find("head") then
						handle.LocalTransparencyModifier = 1
					end
				end
			end
		end
	end
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
	
	-- Apply zoom via FieldOfView
	local baseFOV = 70
	camera.FieldOfView = baseFOV / cameraState.currentZoom
	
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
	
	-- Set camera CFrame
	camera.CFrame = CFrame.new(cameraPosition) * cameraRotation * shakeCFrame
	
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

return CameraController

