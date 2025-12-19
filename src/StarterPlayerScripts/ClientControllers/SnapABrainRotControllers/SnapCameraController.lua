-- SnapCameraController
-- First-person camera with Pokemon Snap style GUI

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local Packages = ReplicatedStorage.Packages
local Knit = require(Packages.Knit)

local SnapCameraController = Knit.CreateController {
	Name = "SnapCameraController",
}

-- =========================================================
-- CONFIG
-- =========================================================

local CONFIG = {
	MaxPhotos = 60,              -- Maximum photos per roll
	ZoomLevels = {1, 1.5, 2},    -- Zoom multipliers (while in camera mode)
	DefaultFOV = 70,             -- Default field of view
	CameraModeFOV = 50,          -- FOV when entering camera mode (zoomed in)
	PhotoCooldown = 0.5,         -- Seconds between photos
	ZoomTransitionTime = 0.2,    -- Time to zoom in/out
}

-- =========================================================
-- STATE
-- =========================================================

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera
local gui = nil
local photosRemaining = CONFIG.MaxPhotos
local currentZoomIndex = 1
local canTakePhoto = true
local score = 0
local inCameraMode = false  -- Whether player is holding RMB

-- Camera smoothing and mouse look
local cameraConnection = nil
local smoothedPosition = nil
local smoothedCFrame = nil
local cameraRotationX = 0  -- Horizontal rotation (yaw)
local cameraRotationY = 0  -- Vertical rotation (pitch)
local POSITION_SMOOTHING = 0.08  -- Very smooth position following
local ROTATION_SMOOTHING = 0.5   -- More responsive rotation
local MOUSE_SENSITIVITY = 0.3    -- Mouse look sensitivity

-- GUI Elements
local viewfinderFrame = nil
local photosLabel = nil
local scoreLabel = nil
local zoomLabel = nil
local flashOverlay = nil
local crosshair = nil
local captureIndicator = nil
local cameraModeOverlay = nil  -- Darkened edges when in camera mode
local cameraModeLabel = nil    -- Shows "CAMERA MODE" when active

-- =========================================================
-- CAMERA SETUP
-- =========================================================

function SnapCameraController:SetupFirstPersonCamera()
	-- Wait for character
	local character = player.Character or player.CharacterAdded:Wait()
	local humanoid = character:WaitForChild("Humanoid")
	local head = character:WaitForChild("Head")
	
	-- Use scriptable camera for full control (allows smoothing)
	camera.CameraType = Enum.CameraType.Scriptable
	
	-- Lock mouse to center
	UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
	
	-- Hide character in first person
	player.CameraMinZoomDistance = 0
	player.CameraMaxZoomDistance = 0
	
	-- Apply default FOV
	camera.FieldOfView = CONFIG.DefaultFOV
	
	-- Disconnect existing camera loop
	if cameraConnection then
		cameraConnection:Disconnect()
		cameraConnection = nil
	end
	
	-- Initialize smoothed position and CFrame
	smoothedPosition = head.Position
	smoothedCFrame = CFrame.new(head.Position)
	cameraRotationX = 0
	cameraRotationY = 0
	
	-- Smooth camera update loop with mouse look
	cameraConnection = RunService.RenderStepped:Connect(function(deltaTime)
		if not character or not character.Parent then return end
		
		local headCheck = character:FindFirstChild("Head")
		if not headCheck then return end
		
		-- Get mouse delta for look rotation
		local mouseDelta = UserInputService:GetMouseDelta()
		cameraRotationX = cameraRotationX - mouseDelta.X * MOUSE_SENSITIVITY
		cameraRotationY = math.clamp(cameraRotationY - mouseDelta.Y * MOUSE_SENSITIVITY, -80, 80)
		
		-- Get target position from character's head
		local targetPosition = headCheck.Position + Vector3.new(0, 0.5, 0)
		
		-- Smooth position interpolation (very smooth for jitter elimination)
		local posAlpha = 1 - math.pow(1 - POSITION_SMOOTHING, deltaTime * 60)
		smoothedPosition = smoothedPosition:Lerp(targetPosition, posAlpha)
		
		-- Build target camera CFrame with smoothed position and mouse rotation
		local rotationCFrame = CFrame.Angles(0, math.rad(cameraRotationX), 0) * CFrame.Angles(math.rad(cameraRotationY), 0, 0)
		local targetCFrame = CFrame.new(smoothedPosition) * rotationCFrame
		
		-- Additional CFrame smoothing for extra smoothness
		local cfAlpha = 1 - math.pow(1 - ROTATION_SMOOTHING, deltaTime * 60)
		smoothedCFrame = smoothedCFrame:Lerp(targetCFrame, cfAlpha)
		
		camera.CFrame = smoothedCFrame
	end)
	
	print("[SnapCameraController] First person camera with smoothing and mouse look enabled")
end

function SnapCameraController:StopCameraSmoothing()
	if cameraConnection then
		cameraConnection:Disconnect()
		cameraConnection = nil
	end
	-- Restore mouse behavior
	UserInputService.MouseBehavior = Enum.MouseBehavior.Default
end

-- =========================================================
-- GUI CREATION
-- =========================================================

function SnapCameraController:CreateSnapGUI()
	-- Main ScreenGui
	gui = Instance.new("ScreenGui")
	gui.Name = "SnapCameraGUI"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.Parent = player.PlayerGui
	
	-- Viewfinder Frame (camera border)
	viewfinderFrame = Instance.new("Frame")
	viewfinderFrame.Name = "Viewfinder"
	viewfinderFrame.Size = UDim2.new(1, 0, 1, 0)
	viewfinderFrame.Position = UDim2.new(0, 0, 0, 0)
	viewfinderFrame.BackgroundTransparency = 1
	viewfinderFrame.Parent = gui
	
	-- Corner brackets (Pokemon Snap style viewfinder)
	self:CreateViewfinderCorners()
	
	-- Crosshair/Focus point - Pokemon Snap style with brackets and circle
	crosshair = Instance.new("Frame")
	crosshair.Name = "Crosshair"
	crosshair.Size = UDim2.new(0, 100, 0, 100)
	crosshair.Position = UDim2.new(0.5, -50, 0.5, -50)
	crosshair.BackgroundTransparency = 1
	crosshair.Parent = gui
	crosshair.ZIndex = 5
	
	local bracketColor = Color3.fromRGB(180, 190, 210)
	local bracketSize = 20
	local bracketThickness = 2
	
	-- Corner brackets
	-- Top-left
	local tlH = Instance.new("Frame")
	tlH.Size = UDim2.new(0, bracketSize, 0, bracketThickness)
	tlH.Position = UDim2.new(0, 0, 0, 0)
	tlH.BackgroundColor3 = bracketColor
	tlH.BackgroundTransparency = 0.2
	tlH.BorderSizePixel = 0
	tlH.Parent = crosshair
	
	local tlV = Instance.new("Frame")
	tlV.Size = UDim2.new(0, bracketThickness, 0, bracketSize)
	tlV.Position = UDim2.new(0, 0, 0, 0)
	tlV.BackgroundColor3 = bracketColor
	tlV.BackgroundTransparency = 0.2
	tlV.BorderSizePixel = 0
	tlV.Parent = crosshair
	
	-- Top-right
	local trH = Instance.new("Frame")
	trH.Size = UDim2.new(0, bracketSize, 0, bracketThickness)
	trH.Position = UDim2.new(1, -bracketSize, 0, 0)
	trH.BackgroundColor3 = bracketColor
	trH.BackgroundTransparency = 0.2
	trH.BorderSizePixel = 0
	trH.Parent = crosshair
	
	local trV = Instance.new("Frame")
	trV.Size = UDim2.new(0, bracketThickness, 0, bracketSize)
	trV.Position = UDim2.new(1, -bracketThickness, 0, 0)
	trV.BackgroundColor3 = bracketColor
	trV.BackgroundTransparency = 0.2
	trV.BorderSizePixel = 0
	trV.Parent = crosshair
	
	-- Bottom-left
	local blH = Instance.new("Frame")
	blH.Size = UDim2.new(0, bracketSize, 0, bracketThickness)
	blH.Position = UDim2.new(0, 0, 1, -bracketThickness)
	blH.BackgroundColor3 = bracketColor
	blH.BackgroundTransparency = 0.2
	blH.BorderSizePixel = 0
	blH.Parent = crosshair
	
	local blV = Instance.new("Frame")
	blV.Size = UDim2.new(0, bracketThickness, 0, bracketSize)
	blV.Position = UDim2.new(0, 0, 1, -bracketSize)
	blV.BackgroundColor3 = bracketColor
	blV.BackgroundTransparency = 0.2
	blV.BorderSizePixel = 0
	blV.Parent = crosshair
	
	-- Bottom-right
	local brH = Instance.new("Frame")
	brH.Size = UDim2.new(0, bracketSize, 0, bracketThickness)
	brH.Position = UDim2.new(1, -bracketSize, 1, -bracketThickness)
	brH.BackgroundColor3 = bracketColor
	brH.BackgroundTransparency = 0.2
	brH.BorderSizePixel = 0
	brH.Parent = crosshair
	
	local brV = Instance.new("Frame")
	brV.Size = UDim2.new(0, bracketThickness, 0, bracketSize)
	brV.Position = UDim2.new(1, -bracketThickness, 1, -bracketSize)
	brV.BackgroundColor3 = bracketColor
	brV.BackgroundTransparency = 0.2
	brV.BorderSizePixel = 0
	brV.Parent = crosshair
	
	-- Center circle ring
	local centerRing = Instance.new("Frame")
	centerRing.Name = "CenterRing"
	centerRing.Size = UDim2.new(0, 40, 0, 40)
	centerRing.Position = UDim2.new(0.5, -20, 0.5, -20)
	centerRing.BackgroundTransparency = 1
	centerRing.Parent = crosshair
	
	local ringStroke = Instance.new("UIStroke")
	ringStroke.Name = "RingStroke"
	ringStroke.Color = bracketColor
	ringStroke.Thickness = 2
	ringStroke.Transparency = 0.2
	ringStroke.Parent = centerRing
	
	local ringCorner = Instance.new("UICorner")
	ringCorner.CornerRadius = UDim.new(1, 0)
	ringCorner.Parent = centerRing
	
	-- Short horizontal lines extending from circle
	local hLineL = Instance.new("Frame")
	hLineL.Size = UDim2.new(0, 10, 0, bracketThickness)
	hLineL.Position = UDim2.new(0.5, -30, 0.5, -1)
	hLineL.BackgroundColor3 = bracketColor
	hLineL.BackgroundTransparency = 0.2
	hLineL.BorderSizePixel = 0
	hLineL.Parent = crosshair
	
	local hLineR = Instance.new("Frame")
	hLineR.Size = UDim2.new(0, 10, 0, bracketThickness)
	hLineR.Position = UDim2.new(0.5, 20, 0.5, -1)
	hLineR.BackgroundColor3 = bracketColor
	hLineR.BackgroundTransparency = 0.2
	hLineR.BorderSizePixel = 0
	hLineR.Parent = crosshair
	
	-- Orange center dot
	local centerDot = Instance.new("Frame")
	centerDot.Name = "CenterDot"
	centerDot.Size = UDim2.new(0, 10, 0, 10)
	centerDot.Position = UDim2.new(0.5, -5, 0.5, -5)
	centerDot.BackgroundColor3 = Color3.fromRGB(255, 140, 50)
	centerDot.BackgroundTransparency = 0
	centerDot.BorderSizePixel = 0
	centerDot.Parent = crosshair
	
	local dotCorner = Instance.new("UICorner")
	dotCorner.CornerRadius = UDim.new(1, 0)
	dotCorner.Parent = centerDot
	
	-- Top info bar
	local topBar = Instance.new("Frame")
	topBar.Name = "TopBar"
	topBar.Size = UDim2.new(1, 0, 0, 60)
	topBar.Position = UDim2.new(0, 0, 0, 0)
	topBar.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	topBar.BackgroundTransparency = 0.5
	topBar.BorderSizePixel = 0
	topBar.Parent = gui
	
	-- Film/Photos counter (top left)
	local filmFrame = Instance.new("Frame")
	filmFrame.Name = "FilmFrame"
	filmFrame.Size = UDim2.new(0, 150, 0, 40)
	filmFrame.Position = UDim2.new(0, 20, 0, 10)
	filmFrame.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
	filmFrame.BorderSizePixel = 0
	filmFrame.Parent = topBar
	
	local filmCorner = Instance.new("UICorner")
	filmCorner.CornerRadius = UDim.new(0, 8)
	filmCorner.Parent = filmFrame
	
	local filmIcon = Instance.new("TextLabel")
	filmIcon.Name = "FilmIcon"
	filmIcon.Size = UDim2.new(0, 30, 1, 0)
	filmIcon.Position = UDim2.new(0, 5, 0, 0)
	filmIcon.BackgroundTransparency = 1
	filmIcon.Text = "📷"
	filmIcon.TextSize = 24
	filmIcon.Font = Enum.Font.GothamBold
	filmIcon.TextColor3 = Color3.fromRGB(255, 255, 255)
	filmIcon.Parent = filmFrame
	
	photosLabel = Instance.new("TextLabel")
	photosLabel.Name = "PhotosLabel"
	photosLabel.Size = UDim2.new(0, 100, 1, 0)
	photosLabel.Position = UDim2.new(0, 40, 0, 0)
	photosLabel.BackgroundTransparency = 1
	photosLabel.Text = string.format("%02d / %02d", photosRemaining, CONFIG.MaxPhotos)
	photosLabel.TextSize = 20
	photosLabel.Font = Enum.Font.Code
	photosLabel.TextColor3 = Color3.fromRGB(0, 255, 100)
	photosLabel.TextXAlignment = Enum.TextXAlignment.Left
	photosLabel.Parent = filmFrame
	
	-- Score display (top right)
	local scoreFrame = Instance.new("Frame")
	scoreFrame.Name = "ScoreFrame"
	scoreFrame.Size = UDim2.new(0, 180, 0, 40)
	scoreFrame.Position = UDim2.new(1, -200, 0, 10)
	scoreFrame.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
	scoreFrame.BorderSizePixel = 0
	scoreFrame.Parent = topBar
	
	local scoreCorner = Instance.new("UICorner")
	scoreCorner.CornerRadius = UDim.new(0, 8)
	scoreCorner.Parent = scoreFrame
	
	local scoreTitle = Instance.new("TextLabel")
	scoreTitle.Name = "ScoreTitle"
	scoreTitle.Size = UDim2.new(0, 60, 1, 0)
	scoreTitle.Position = UDim2.new(0, 10, 0, 0)
	scoreTitle.BackgroundTransparency = 1
	scoreTitle.Text = "SCORE"
	scoreTitle.TextSize = 14
	scoreTitle.Font = Enum.Font.GothamBold
	scoreTitle.TextColor3 = Color3.fromRGB(200, 200, 200)
	scoreTitle.TextXAlignment = Enum.TextXAlignment.Left
	scoreTitle.Parent = scoreFrame
	
	scoreLabel = Instance.new("TextLabel")
	scoreLabel.Name = "ScoreLabel"
	scoreLabel.Size = UDim2.new(0, 100, 1, 0)
	scoreLabel.Position = UDim2.new(0, 70, 0, 0)
	scoreLabel.BackgroundTransparency = 1
	scoreLabel.Text = string.format("%08d", score)
	scoreLabel.TextSize = 22
	scoreLabel.Font = Enum.Font.Code
	scoreLabel.TextColor3 = Color3.fromRGB(255, 220, 0)
	scoreLabel.TextXAlignment = Enum.TextXAlignment.Right
	scoreLabel.Parent = scoreFrame
	
	-- Bottom info bar
	local bottomBar = Instance.new("Frame")
	bottomBar.Name = "BottomBar"
	bottomBar.Size = UDim2.new(1, 0, 0, 50)
	bottomBar.Position = UDim2.new(0, 0, 1, -50)
	bottomBar.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	bottomBar.BackgroundTransparency = 0.5
	bottomBar.BorderSizePixel = 0
	bottomBar.Parent = gui
	
	-- Zoom indicator (bottom left)
	local zoomFrame = Instance.new("Frame")
	zoomFrame.Name = "ZoomFrame"
	zoomFrame.Size = UDim2.new(0, 120, 0, 35)
	zoomFrame.Position = UDim2.new(0, 20, 0, 8)
	zoomFrame.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
	zoomFrame.BorderSizePixel = 0
	zoomFrame.Parent = bottomBar
	
	local zoomCorner = Instance.new("UICorner")
	zoomCorner.CornerRadius = UDim.new(0, 8)
	zoomCorner.Parent = zoomFrame
	
	local zoomIcon = Instance.new("TextLabel")
	zoomIcon.Name = "ZoomIcon"
	zoomIcon.Size = UDim2.new(0, 30, 1, 0)
	zoomIcon.Position = UDim2.new(0, 5, 0, 0)
	zoomIcon.BackgroundTransparency = 1
	zoomIcon.Text = "🔍"
	zoomIcon.TextSize = 18
	zoomIcon.Parent = zoomFrame
	
	zoomLabel = Instance.new("TextLabel")
	zoomLabel.Name = "ZoomLabel"
	zoomLabel.Size = UDim2.new(0, 70, 1, 0)
	zoomLabel.Position = UDim2.new(0, 35, 0, 0)
	zoomLabel.BackgroundTransparency = 1
	zoomLabel.Text = "x1.0"
	zoomLabel.TextSize = 20
	zoomLabel.Font = Enum.Font.Code
	zoomLabel.TextColor3 = Color3.fromRGB(100, 200, 255)
	zoomLabel.TextXAlignment = Enum.TextXAlignment.Left
	zoomLabel.Parent = zoomFrame
	
	-- Capture button hint (bottom center)
	captureIndicator = Instance.new("Frame")
	captureIndicator.Name = "CaptureIndicator"
	captureIndicator.Size = UDim2.new(0, 200, 0, 35)
	captureIndicator.Position = UDim2.new(0.5, -100, 0, 8)
	captureIndicator.BackgroundColor3 = Color3.fromRGB(200, 50, 50)
	captureIndicator.BorderSizePixel = 0
	captureIndicator.Parent = bottomBar
	
	local captureCorner = Instance.new("UICorner")
	captureCorner.CornerRadius = UDim.new(0, 8)
	captureCorner.Parent = captureIndicator
	
	local captureText = Instance.new("TextLabel")
	captureText.Name = "CaptureText"
	captureText.Size = UDim2.new(1, 0, 1, 0)
	captureText.BackgroundTransparency = 1
	captureText.Text = "[ HOLD RMB ] AIM  •  [ LMB ] SNAP"
	captureText.TextSize = 14
	captureText.Font = Enum.Font.GothamBold
	captureText.TextColor3 = Color3.fromRGB(255, 255, 255)
	captureText.Parent = captureIndicator
	
	-- Start with grey (inactive) color
	captureIndicator.BackgroundColor3 = Color3.fromRGB(100, 100, 100)
	
	-- Flash overlay (for photo effect)
	flashOverlay = Instance.new("Frame")
	flashOverlay.Name = "FlashOverlay"
	flashOverlay.Size = UDim2.new(1, 0, 1, 0)
	flashOverlay.Position = UDim2.new(0, 0, 0, 0)
	flashOverlay.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	flashOverlay.BackgroundTransparency = 1
	flashOverlay.BorderSizePixel = 0
	flashOverlay.ZIndex = 10
	flashOverlay.Parent = gui
	
	-- Camera mode overlay with SQUARE clear zone
	cameraModeOverlay = Instance.new("Frame")
	cameraModeOverlay.Name = "CameraModeOverlay"
	cameraModeOverlay.Size = UDim2.new(1, 0, 1, 0)
	cameraModeOverlay.Position = UDim2.new(0, 0, 0, 0)
	cameraModeOverlay.BackgroundTransparency = 1
	cameraModeOverlay.Visible = false
	cameraModeOverlay.ZIndex = 2
	cameraModeOverlay.Parent = gui
	
	-- Create the darkened border areas for SQUARE viewfinder
	local overlayColor = Color3.fromRGB(15, 20, 35)
	local overlayTransparency = 0.3
	
	-- Square size will be 70% of viewport height, centered
	local squareScale = 0.7  -- 70% of height
	local topBottomHeight = (1 - squareScale) / 2  -- Space above/below square
	
	-- Top dark area (full width, covers top portion)
	local topOverlay = Instance.new("Frame")
	topOverlay.Name = "TopOverlay"
	topOverlay.Size = UDim2.new(1, 0, topBottomHeight, 0)
	topOverlay.Position = UDim2.new(0, 0, 0, 0)
	topOverlay.BackgroundColor3 = overlayColor
	topOverlay.BackgroundTransparency = overlayTransparency
	topOverlay.BorderSizePixel = 0
	topOverlay.Parent = cameraModeOverlay
	
	-- Bottom dark area (full width, covers bottom portion)
	local bottomOverlay = Instance.new("Frame")
	bottomOverlay.Name = "BottomOverlay"
	bottomOverlay.Size = UDim2.new(1, 0, topBottomHeight, 0)
	bottomOverlay.Position = UDim2.new(0, 0, 1 - topBottomHeight, 0)
	bottomOverlay.BackgroundColor3 = overlayColor
	bottomOverlay.BackgroundTransparency = overlayTransparency
	bottomOverlay.BorderSizePixel = 0
	bottomOverlay.Parent = cameraModeOverlay
	
	-- Left dark area (will be dynamically sized based on viewport to create square)
	local leftOverlay = Instance.new("Frame")
	leftOverlay.Name = "LeftOverlay"
	leftOverlay.BackgroundColor3 = overlayColor
	leftOverlay.BackgroundTransparency = overlayTransparency
	leftOverlay.BorderSizePixel = 0
	leftOverlay.Parent = cameraModeOverlay
	
	-- Right dark area (will be dynamically sized based on viewport to create square)
	local rightOverlay = Instance.new("Frame")
	rightOverlay.Name = "RightOverlay"
	rightOverlay.BackgroundColor3 = overlayColor
	rightOverlay.BackgroundTransparency = overlayTransparency
	rightOverlay.BorderSizePixel = 0
	rightOverlay.Parent = cameraModeOverlay
	
	-- Clear zone border frame (SQUARE outline)
	local clearZone = Instance.new("Frame")
	clearZone.Name = "ClearZone"
	clearZone.BackgroundTransparency = 1
	clearZone.Parent = cameraModeOverlay
	
	local clearZoneStroke = Instance.new("UIStroke")
	clearZoneStroke.Color = Color3.fromRGB(100, 120, 150)
	clearZoneStroke.Thickness = 3
	clearZoneStroke.Transparency = 0.3
	clearZoneStroke.Parent = clearZone
	
	local clearZoneCorner = Instance.new("UICorner")
	clearZoneCorner.CornerRadius = UDim.new(0, 12)
	clearZoneCorner.Parent = clearZone
	
	-- Function to update overlay sizes for square viewfinder
	local function updateSquareOverlay()
		local viewportSize = camera.ViewportSize
		local viewportWidth = viewportSize.X
		local viewportHeight = viewportSize.Y
		
		-- Calculate square size (70% of viewport height)
		local squareSize = viewportHeight * squareScale
		local sideWidth = (viewportWidth - squareSize) / 2
		local sideWidthScale = sideWidth / viewportWidth
		
		-- Update left overlay (fills left side next to square)
		leftOverlay.Size = UDim2.new(sideWidthScale, 0, squareScale, 0)
		leftOverlay.Position = UDim2.new(0, 0, topBottomHeight, 0)
		
		-- Update right overlay (fills right side next to square)
		rightOverlay.Size = UDim2.new(sideWidthScale, 0, squareScale, 0)
		rightOverlay.Position = UDim2.new(1 - sideWidthScale, 0, topBottomHeight, 0)
		
		-- Update clear zone (centered square)
		clearZone.Size = UDim2.new(0, squareSize, squareScale, 0)
		clearZone.Position = UDim2.new(0.5, -squareSize / 2, topBottomHeight, 0)
	end
	
	-- Initial update
	updateSquareOverlay()
	
	-- Update when viewport changes
	camera:GetPropertyChangedSignal("ViewportSize"):Connect(updateSquareOverlay)
	
	-- Camera mode indicator label
	cameraModeLabel = Instance.new("TextLabel")
	cameraModeLabel.Name = "CameraModeLabel"
	cameraModeLabel.Size = UDim2.new(0, 200, 0, 30)
	cameraModeLabel.Position = UDim2.new(0.5, -100, 0, 70)
	cameraModeLabel.BackgroundColor3 = Color3.fromRGB(200, 50, 50)
	cameraModeLabel.BackgroundTransparency = 0.3
	cameraModeLabel.Text = "📸 CAMERA MODE"
	cameraModeLabel.TextSize = 18
	cameraModeLabel.Font = Enum.Font.GothamBold
	cameraModeLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	cameraModeLabel.Visible = false
	cameraModeLabel.Parent = gui
	
	local cameraLabelCorner = Instance.new("UICorner")
	cameraLabelCorner.CornerRadius = UDim.new(0, 6)
	cameraLabelCorner.Parent = cameraModeLabel
	
	-- Initially hide viewfinder elements (shown only in camera mode)
	viewfinderFrame.Visible = false
	-- Crosshair is always visible (don't hide it)
	
	print("[SnapCameraController] GUI created")
end

function SnapCameraController:CreateViewfinderCorners()
	local cornerSize = 60
	local cornerThickness = 4
	local cornerColor = Color3.fromRGB(255, 255, 255)
	local cornerOffset = 40
	
	local corners = {
		{pos = UDim2.new(0, cornerOffset, 0, cornerOffset), rot = 0},           -- Top-left
		{pos = UDim2.new(1, -cornerOffset - cornerSize, 0, cornerOffset), rot = 90},  -- Top-right
		{pos = UDim2.new(0, cornerOffset, 1, -cornerOffset - cornerSize), rot = 270}, -- Bottom-left
		{pos = UDim2.new(1, -cornerOffset - cornerSize, 1, -cornerOffset - cornerSize), rot = 180}, -- Bottom-right
	}
	
	for i, corner in ipairs(corners) do
		local cornerFrame = Instance.new("Frame")
		cornerFrame.Name = "Corner" .. i
		cornerFrame.Size = UDim2.new(0, cornerSize, 0, cornerSize)
		cornerFrame.Position = corner.pos
		cornerFrame.BackgroundTransparency = 1
		cornerFrame.Rotation = corner.rot
		cornerFrame.Parent = viewfinderFrame
		
		-- Horizontal line
		local hLine = Instance.new("Frame")
		hLine.Size = UDim2.new(0, cornerSize, 0, cornerThickness)
		hLine.Position = UDim2.new(0, 0, 0, 0)
		hLine.BackgroundColor3 = cornerColor
		hLine.BorderSizePixel = 0
		hLine.Parent = cornerFrame
		
		-- Vertical line
		local vLine = Instance.new("Frame")
		vLine.Size = UDim2.new(0, cornerThickness, 0, cornerSize)
		vLine.Position = UDim2.new(0, 0, 0, 0)
		vLine.BackgroundColor3 = cornerColor
		vLine.BorderSizePixel = 0
		vLine.Parent = cornerFrame
	end
end


-- =========================================================
-- CAMERA MODE
-- =========================================================

function SnapCameraController:EnterCameraMode()
	if inCameraMode then return end
	inCameraMode = true
	
	-- Show camera mode overlay with clear zone
	cameraModeOverlay.Visible = true
	cameraModeLabel.Visible = true
	
	-- Zoom in FOV
	local zoomLevel = CONFIG.ZoomLevels[currentZoomIndex]
	local targetFOV = CONFIG.CameraModeFOV / zoomLevel
	
	local fovTween = TweenService:Create(
		camera,
		TweenInfo.new(CONFIG.ZoomTransitionTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{FieldOfView = targetFOV}
	)
	fovTween:Play()
	
	-- Make crosshair more visible and yellow/gold in camera mode
	local centerRing = crosshair:FindFirstChild("CenterRing")
	local centerDot = crosshair:FindFirstChild("CenterDot")
	
	-- Update all bracket elements to gold
	for _, child in ipairs(crosshair:GetChildren()) do
		if child:IsA("Frame") and child.Name ~= "CenterRing" and child.Name ~= "CenterDot" then
			child.BackgroundColor3 = Color3.fromRGB(255, 220, 100)
			child.BackgroundTransparency = 0
		end
	end
	
	if centerRing then
		local stroke = centerRing:FindFirstChild("RingStroke")
		if stroke then
			stroke.Color = Color3.fromRGB(255, 220, 100)
			stroke.Transparency = 0
			stroke.Thickness = 3
		end
	end
	
	-- Animate crosshair size larger
	local sizeTween = TweenService:Create(
		crosshair,
		TweenInfo.new(CONFIG.ZoomTransitionTime, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{Size = UDim2.new(0, 120, 0, 120), Position = UDim2.new(0.5, -60, 0.5, -60)}
	)
	sizeTween:Play()
	
	-- Update capture indicator
	captureIndicator.BackgroundColor3 = Color3.fromRGB(50, 200, 50)  -- Green when active
	
	print("[SnapCameraController] Entered camera mode")
end

function SnapCameraController:ExitCameraMode()
	if not inCameraMode then return end
	inCameraMode = false
	
	-- Hide camera mode overlay
	cameraModeOverlay.Visible = false
	cameraModeLabel.Visible = false
	
	-- Zoom out FOV to default
	local fovTween = TweenService:Create(
		camera,
		TweenInfo.new(CONFIG.ZoomTransitionTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{FieldOfView = CONFIG.DefaultFOV}
	)
	fovTween:Play()
	
	-- Reset crosshair to default appearance (subtle white/blue-grey)
	local bracketColor = Color3.fromRGB(180, 190, 210)
	local centerRing = crosshair:FindFirstChild("CenterRing")
	
	-- Reset all bracket elements
	for _, child in ipairs(crosshair:GetChildren()) do
		if child:IsA("Frame") and child.Name ~= "CenterRing" and child.Name ~= "CenterDot" then
			child.BackgroundColor3 = bracketColor
			child.BackgroundTransparency = 0.2
		end
	end
	
	if centerRing then
		local stroke = centerRing:FindFirstChild("RingStroke")
		if stroke then
			stroke.Color = bracketColor
			stroke.Transparency = 0.2
			stroke.Thickness = 2
		end
	end
	
	-- Animate crosshair size back to normal
	local sizeTween = TweenService:Create(
		crosshair,
		TweenInfo.new(CONFIG.ZoomTransitionTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{Size = UDim2.new(0, 100, 0, 100), Position = UDim2.new(0.5, -50, 0.5, -50)}
	)
	sizeTween:Play()
	
	-- Update capture indicator
	captureIndicator.BackgroundColor3 = Color3.fromRGB(100, 100, 100)  -- Grey when inactive
	
	print("[SnapCameraController] Exited camera mode")
end

-- =========================================================
-- PHOTO MECHANICS
-- =========================================================

function SnapCameraController:TakePhoto()
	-- Can only take photos in camera mode
	if not inCameraMode then
		return
	end
	
	if not canTakePhoto or photosRemaining <= 0 then
		return
	end
	
	canTakePhoto = false
	photosRemaining = photosRemaining - 1
	
	-- Update UI
	photosLabel.Text = string.format("%02d / %02d", photosRemaining, CONFIG.MaxPhotos)
	
	-- Flash effect
	self:PlayFlashEffect()
	
	-- Camera shutter sound (optional)
	self:PlayShutterSound()
	
	-- Add score (placeholder - would be based on what's in frame)
	local photoScore = math.random(100, 1000)
	score = score + photoScore
	scoreLabel.Text = string.format("%08d", score)
	
	-- Show score popup
	self:ShowScorePopup(photoScore)
	
	-- Cooldown
	task.delay(CONFIG.PhotoCooldown, function()
		canTakePhoto = true
	end)
	
	print("[SnapCameraController] Photo taken! Score:", photoScore)
end

function SnapCameraController:PlayFlashEffect()
	flashOverlay.BackgroundTransparency = 0
	
	local tween = TweenService:Create(
		flashOverlay,
		TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{BackgroundTransparency = 1}
	)
	tween:Play()
end

function SnapCameraController:PlayShutterSound()
	local sound = Instance.new("Sound")
	sound.SoundId = "rbxassetid://138721813"  -- Camera shutter sound
	sound.Volume = 0.5
	sound.Parent = camera
	sound:Play()
	sound.Ended:Connect(function()
		sound:Destroy()
	end)
end

function SnapCameraController:ShowScorePopup(points)
	local popup = Instance.new("TextLabel")
	popup.Name = "ScorePopup"
	popup.Size = UDim2.new(0, 200, 0, 50)
	popup.Position = UDim2.new(0.5, -100, 0.4, 0)
	popup.BackgroundTransparency = 1
	popup.Text = "+" .. tostring(points) .. " pts"
	popup.TextSize = 36
	popup.Font = Enum.Font.GothamBold
	popup.TextColor3 = Color3.fromRGB(255, 220, 0)
	popup.TextStrokeTransparency = 0.5
	popup.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	popup.Parent = gui
	
	-- Animate up and fade out
	local tween = TweenService:Create(
		popup,
		TweenInfo.new(1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{Position = UDim2.new(0.5, -100, 0.3, 0), TextTransparency = 1, TextStrokeTransparency = 1}
	)
	tween:Play()
	tween.Completed:Connect(function()
		popup:Destroy()
	end)
end

-- =========================================================
-- ZOOM MECHANICS
-- =========================================================

function SnapCameraController:CycleZoom()
	-- Can only zoom in camera mode
	if not inCameraMode then
		return
	end
	
	currentZoomIndex = currentZoomIndex + 1
	if currentZoomIndex > #CONFIG.ZoomLevels then
		currentZoomIndex = 1
	end
	
	local zoomLevel = CONFIG.ZoomLevels[currentZoomIndex]
	local newFOV = CONFIG.CameraModeFOV / zoomLevel  -- Use camera mode FOV as base
	
	-- Tween FOV change
	local tween = TweenService:Create(
		camera,
		TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{FieldOfView = newFOV}
	)
	tween:Play()
	
	-- Update UI
	zoomLabel.Text = string.format("x%.1f", zoomLevel)
	
	print("[SnapCameraController] Zoom:", zoomLevel)
end

-- =========================================================
-- INPUT HANDLING
-- =========================================================

function SnapCameraController:SetupInput()
	-- Right mouse button: Hold to enter camera mode
	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed then return end
		
		-- RMB to enter camera mode
		if input.UserInputType == Enum.UserInputType.MouseButton2 then
			self:EnterCameraMode()
		end
		
		-- LMB to take photo (only works in camera mode)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			self:TakePhoto()
		end
		
		-- Q/E to cycle zoom (only in camera mode)
		if input.KeyCode == Enum.KeyCode.Q or input.KeyCode == Enum.KeyCode.E then
			self:CycleZoom()
		end
	end)
	
	-- Release RMB to exit camera mode
	UserInputService.InputEnded:Connect(function(input, gameProcessed)
		if input.UserInputType == Enum.UserInputType.MouseButton2 then
			self:ExitCameraMode()
		end
	end)
	
	-- Scroll wheel zoom disabled
end

-- =========================================================
-- KNIT LIFECYCLE
-- =========================================================

function SnapCameraController:KnitInit()
	print("[SnapCameraController] Initializing")
end

function SnapCameraController:KnitStart()
	print("[SnapCameraController] Starting")
	
	-- Wait for character
	local character = player.Character or player.CharacterAdded:Wait()
	
	-- Setup camera and GUI
	self:SetupFirstPersonCamera()
	self:CreateSnapGUI()
	self:SetupInput()
	
	-- Re-setup on respawn
	player.CharacterAdded:Connect(function(char)
		task.wait(0.5)
		self:SetupFirstPersonCamera()
	end)
	
	print("[SnapCameraController] Ready")
end

return SnapCameraController

