-- ComputerCameraController
-- FNAF-style camera: edge-based panning when seated, GUI button for terminal

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Packages = ReplicatedStorage.Packages
local Knit = require(Packages.Knit)
local Signal = require(Packages.Signal)

local ComputerCameraController = Knit.CreateController {
	Name = "ComputerCameraController",
}

-- Signals
ComputerCameraController.SeatedAtComputer = Signal.new()
ComputerCameraController.TerminalToggled = Signal.new()

-- =========================================================
-- CONFIG
-- =========================================================

local CONFIG = {
	-- Camera transition
	TransitionDuration = 0.8,
	TargetFOV = 70,
	EasingStyle = Enum.EasingStyle.Quad,
	EasingDirection = Enum.EasingDirection.Out,
	
	-- Pan limits (degrees)
	MaxYaw = 50,    -- Left/right limit
	MaxPitch = 25,  -- Up/down limit
	
	-- Edge panning
	EdgeZone = 0.15,       -- Screen edge zone (0-1, percentage from edge)
	PanSpeed = 2.5,        -- How fast camera pans
	PanSmoothing = 6,      -- Smoothing factor
	
	-- Dead zone in center (no panning)
	DeadZone = 0.3,        -- Center dead zone size (0-1)
}

-- =========================================================
-- STATE
-- =========================================================

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

local originalMinZoom = nil
local originalMaxZoom = nil
local originalCameraType = nil
local originalFOV = nil

local isSeatedAtComputer = false
local isTerminalOpen = false
local seatConnection = nil
local cameraUpdateConnection = nil
local inputConnection = nil
local currentSeat = nil

-- Pan angles (in radians)
local currentYaw = 0
local currentPitch = 0
local targetYaw = 0
local targetPitch = 0

-- Base direction
local baseLookVector = Vector3.new(0, 0, -1)
local headPosition = Vector3.new(0, 5, 0)

-- Character transparency storage
local originalTransparencies = {}

-- =========================================================
-- HELPERS
-- =========================================================

local function getPlayerComputerModel()
	local modelName = player.Name .. "_Spawn"
	return workspace:FindFirstChild(modelName)
end

local function clamp(value, min, max)
	return math.max(min, math.min(max, value))
end

local function lerp(a, b, t)
	return a + (b - a) * t
end

-- Map a value from one range to another
local function map(value, inMin, inMax, outMin, outMax)
	return outMin + (outMax - outMin) * ((value - inMin) / (inMax - inMin))
end

-- =========================================================
-- CHARACTER VISIBILITY
-- =========================================================

local function hideCharacter()
	local character = player.Character
	if not character then return end
	
	originalTransparencies = {}
	
	for _, descendant in ipairs(character:GetDescendants()) do
		if descendant:IsA("BasePart") then
			originalTransparencies[descendant] = descendant.LocalTransparencyModifier
			descendant.LocalTransparencyModifier = 1
		elseif descendant:IsA("Decal") or descendant:IsA("Texture") then
			originalTransparencies[descendant] = descendant.Transparency
			descendant.Transparency = 1
		elseif descendant:IsA("BillboardGui") or descendant:IsA("SurfaceGui") then
			originalTransparencies[descendant] = descendant.Enabled
			descendant.Enabled = false
		end
	end
	
	-- Also hide accessories
	for _, accessory in ipairs(character:GetChildren()) do
		if accessory:IsA("Accessory") then
			local handle = accessory:FindFirstChild("Handle")
			if handle then
				originalTransparencies[handle] = handle.LocalTransparencyModifier
				handle.LocalTransparencyModifier = 1
			end
		end
	end
	
	print("[ComputerCameraController] Character hidden")
end

local function showCharacter()
	local character = player.Character
	if not character then return end
	
	for instance, originalValue in pairs(originalTransparencies) do
		if instance and instance.Parent then
			if instance:IsA("BasePart") then
				instance.LocalTransparencyModifier = originalValue
			elseif instance:IsA("Decal") or instance:IsA("Texture") then
				instance.Transparency = originalValue
			elseif instance:IsA("BillboardGui") or instance:IsA("SurfaceGui") then
				instance.Enabled = originalValue
			end
		end
	end
	
	originalTransparencies = {}
	print("[ComputerCameraController] Character visible")
end

-- =========================================================
-- EDGE-BASED CAMERA PAN
-- =========================================================

function ComputerCameraController:UpdateCameraPan(deltaTime)
	if not isSeatedAtComputer or isTerminalOpen then return end
	
	-- Get mouse position normalized (0-1)
	local mouse = player:GetMouse()
	local viewportSize = camera.ViewportSize
	
	local mouseX = mouse.X / viewportSize.X  -- 0 = left, 1 = right
	local mouseY = mouse.Y / viewportSize.Y  -- 0 = top, 1 = bottom
	
	-- Calculate pan amount based on mouse position
	local panX = 0
	local panY = 0
	
	-- Horizontal panning (left/right edges)
	local centerX = 0.5
	local distFromCenterX = mouseX - centerX
	
	if math.abs(distFromCenterX) > CONFIG.DeadZone / 2 then
		-- Outside dead zone, calculate pan
		if distFromCenterX > 0 then
			-- Right side
			panX = -map(distFromCenterX, CONFIG.DeadZone / 2, 0.5, 0, 1)
		else
			-- Left side
			panX = -map(distFromCenterX, -0.5, -CONFIG.DeadZone / 2, -1, 0)
		end
	end
	
	-- Vertical panning (top/bottom edges)
	local centerY = 0.5
	local distFromCenterY = mouseY - centerY
	
	if math.abs(distFromCenterY) > CONFIG.DeadZone / 2 then
		if distFromCenterY > 0 then
			-- Bottom
			panY = map(distFromCenterY, CONFIG.DeadZone / 2, 0.5, 0, 1)
		else
			-- Top
			panY = map(distFromCenterY, -0.5, -CONFIG.DeadZone / 2, -1, 0)
		end
	end
	
	-- Clamp pan values
	panX = clamp(panX, -1, 1)
	panY = clamp(panY, -1, 1)
	
	-- Apply pan to target angles
	targetYaw = panX * math.rad(CONFIG.MaxYaw)
	targetPitch = panY * math.rad(CONFIG.MaxPitch)
	
	-- Smooth interpolation
	local smoothFactor = 1 - math.exp(-CONFIG.PanSmoothing * deltaTime)
	currentYaw = lerp(currentYaw, targetYaw, smoothFactor)
	currentPitch = lerp(currentPitch, targetPitch, smoothFactor)
end

function ComputerCameraController:UpdateCamera()
	if not isSeatedAtComputer then return end
	
	local character = player.Character
	local head = character and character:FindFirstChild("Head")
	if head then
		headPosition = head.Position
	end
	
	-- If terminal is open, look straight forward
	if isTerminalOpen then
		local targetCFrame = CFrame.lookAt(headPosition, headPosition + baseLookVector)
		camera.CFrame = camera.CFrame:Lerp(targetCFrame, 0.15)
		return
	end
	
	-- Calculate look direction with yaw and pitch
	local yawRotation = CFrame.Angles(0, currentYaw, 0)
	local pitchRotation = CFrame.Angles(currentPitch, 0, 0)
	
	local baseCFrame = CFrame.lookAt(Vector3.zero, baseLookVector)
	local rotatedCFrame = baseCFrame * yawRotation * pitchRotation
	local lookDirection = rotatedCFrame.LookVector
	
	camera.CFrame = CFrame.lookAt(headPosition, headPosition + lookDirection)
end

-- =========================================================
-- TERMINAL TOGGLE (called by UI button)
-- =========================================================

function ComputerCameraController:OpenTerminal()
	if not isSeatedAtComputer or isTerminalOpen then return end
	
	isTerminalOpen = true
	
	-- Smoothly center camera
	targetYaw = 0
	targetPitch = 0
	
	self.TerminalToggled:Fire(true)
	print("[ComputerCameraController] Terminal OPENED")
end

function ComputerCameraController:CloseTerminal()
	if not isTerminalOpen then return end
	
	isTerminalOpen = false
	
	self.TerminalToggled:Fire(false)
	print("[ComputerCameraController] Terminal CLOSED")
end

function ComputerCameraController:ToggleTerminal()
	if isTerminalOpen then
		self:CloseTerminal()
	else
		self:OpenTerminal()
	end
end

-- =========================================================
-- CAMERA TRANSITIONS
-- =========================================================

function ComputerCameraController:TransitionToSeat(seat)
	if isSeatedAtComputer then return end
	isSeatedAtComputer = true
	currentSeat = seat
	
	-- Hide character (first person view)
	hideCharacter()
	
	-- Reset pan angles
	currentYaw = 0
	currentPitch = 0
	targetYaw = 0
	targetPitch = 0
	
	-- Store original settings
	originalMinZoom = player.CameraMinZoomDistance
	originalMaxZoom = player.CameraMaxZoomDistance
	originalCameraType = camera.CameraType
	originalFOV = camera.FieldOfView
	
	-- Base look direction from seat
	baseLookVector = seat.CFrame.LookVector
	
	local character = player.Character
	local head = character and character:FindFirstChild("Head")
	if head then
		headPosition = head.Position
	end
	
	-- Transition
	local startCFrame = camera.CFrame
	local startFOV = camera.FieldOfView
	local startTime = tick()
	
	camera.CameraType = Enum.CameraType.Scriptable
	
	local transitionConnection
	transitionConnection = RunService.RenderStepped:Connect(function()
		local elapsed = tick() - startTime
		local alpha = math.min(elapsed / CONFIG.TransitionDuration, 1)
		local easedAlpha = TweenService:GetValue(alpha, CONFIG.EasingStyle, CONFIG.EasingDirection)
		
		local head = player.Character and player.Character:FindFirstChild("Head")
		if head then
			headPosition = head.Position
		end
		
		local targetCFrame = CFrame.lookAt(headPosition, headPosition + baseLookVector)
		
		camera.CFrame = startCFrame:Lerp(targetCFrame, easedAlpha)
		camera.FieldOfView = startFOV + (CONFIG.TargetFOV - startFOV) * easedAlpha
		
		if alpha >= 1 then
			transitionConnection:Disconnect()
			camera.FieldOfView = CONFIG.TargetFOV
			
			self:StartCameraLoop()
			self:SetupInput()
			self.SeatedAtComputer:Fire(true)
			
			print("[ComputerCameraController] Seated - Edge pan mode active")
		end
	end)
end

function ComputerCameraController:StartCameraLoop()
	if cameraUpdateConnection then
		cameraUpdateConnection:Disconnect()
	end
	
	cameraUpdateConnection = RunService.RenderStepped:Connect(function(deltaTime)
		self:UpdateCameraPan(deltaTime)
		self:UpdateCamera()
	end)
end

function ComputerCameraController:TransitionFromSeat()
	if not isSeatedAtComputer then return end
	isSeatedAtComputer = false
	isTerminalOpen = false
	currentSeat = nil
	
	-- Show character again
	showCharacter()
	
	self.TerminalToggled:Fire(false)
	self.SeatedAtComputer:Fire(false)
	
	if cameraUpdateConnection then
		cameraUpdateConnection:Disconnect()
		cameraUpdateConnection = nil
	end
	
	if inputConnection then
		inputConnection:Disconnect()
		inputConnection = nil
	end
	
	local targetMinZoom = originalMinZoom or 0.5
	local targetMaxZoom = originalMaxZoom or 128
	local targetFOV = originalFOV or 70
	
	local startFOV = camera.FieldOfView
	local startTime = tick()
	
	local transitionConnection
	transitionConnection = RunService.RenderStepped:Connect(function()
		local elapsed = tick() - startTime
		local alpha = math.min(elapsed / CONFIG.TransitionDuration, 1)
		local easedAlpha = TweenService:GetValue(alpha, CONFIG.EasingStyle, CONFIG.EasingDirection)
		
		camera.FieldOfView = startFOV + (targetFOV - startFOV) * easedAlpha
		
		if alpha >= 1 then
			transitionConnection:Disconnect()
			camera.FieldOfView = targetFOV
			camera.CameraType = originalCameraType or Enum.CameraType.Custom
			player.CameraMinZoomDistance = targetMinZoom
			player.CameraMaxZoomDistance = targetMaxZoom
			
			originalMinZoom = nil
			originalMaxZoom = nil
			originalCameraType = nil
			originalFOV = nil
			
			print("[ComputerCameraController] Exited seat")
		end
	end)
end

-- =========================================================
-- INPUT
-- =========================================================

function ComputerCameraController:SetupInput()
	if inputConnection then
		inputConnection:Disconnect()
	end
	
	inputConnection = UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed then return end
		
		-- Escape or Tab to close terminal
		if input.KeyCode == Enum.KeyCode.Escape or input.KeyCode == Enum.KeyCode.Tab then
			if isTerminalOpen then
				self:CloseTerminal()
			end
		end
		
		-- Space to exit seat (only if terminal closed)
		if input.KeyCode == Enum.KeyCode.Space then
			if not isTerminalOpen then
				local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
				if humanoid then
					humanoid.Jump = true
				end
			end
		end
	end)
end

-- =========================================================
-- SEAT DETECTION
-- =========================================================

function ComputerCameraController:SetupSeatDetection()
	local character = player.Character
	if not character then return end
	
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then return end
	
	if seatConnection then
		seatConnection:Disconnect()
	end
	
	seatConnection = humanoid.Seated:Connect(function(isSeated, seat)
		if isSeated and seat then
			local computerModel = getPlayerComputerModel()
			if computerModel and seat:IsDescendantOf(computerModel) then
				self:TransitionToSeat(seat)
			end
		else
			if isSeatedAtComputer then
				self:TransitionFromSeat()
			end
		end
	end)
end

-- =========================================================
-- PUBLIC API
-- =========================================================

function ComputerCameraController:IsSeated()
	return isSeatedAtComputer
end

function ComputerCameraController:IsTerminalOpen()
	return isTerminalOpen
end

-- =========================================================
-- KNIT LIFECYCLE
-- =========================================================

function ComputerCameraController:KnitInit()
	print("[ComputerCameraController] Initializing")
end

function ComputerCameraController:KnitStart()
	print("[ComputerCameraController] Starting")
	
	if player.Character then
		self:SetupSeatDetection()
	end
	
	player.CharacterAdded:Connect(function(character)
		local humanoid = character:WaitForChild("Humanoid", 10)
		if humanoid then
			self:SetupSeatDetection()
		end
	end)
	
	print("[ComputerCameraController] Ready - Move mouse to edges to pan camera")
end

return ComputerCameraController
