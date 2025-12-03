--[[
	FPSController
	Displays a real-time FPS counter UI with performance metrics.
	
	Features:
	- Smooth FPS averaging (avoids jitter)
	- Color-coded performance indicator
	- Optional detailed stats (frame time, memory)
	- Toggleable visibility
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local Stats = game:GetService("Stats")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local Knit = require(Packages.Knit)

local FPSController = Knit.CreateController {
	Name = "FPSController",
	_updateConnection = nil,
	_gui = nil,
	_visible = true,
}

-- === CONFIGURATION ===
local FPS_CONFIG = {
	-- Display
	Enabled = true,
	ShowDetailedStats = false,   -- Show frame time + memory
	Position = UDim2.new(0, 12, 0, 50),  -- Top-left, moved down
	
	-- Averaging (smooths out jitter)
	SampleCount = 30,            -- Frames to average
	UpdateInterval = 0.1,        -- UI update frequency (seconds)
	
	-- Colors (based on performance)
	ColorExcellent = Color3.fromRGB(100, 255, 130),  -- 60+ FPS - Green
	ColorGood = Color3.fromRGB(255, 220, 100),       -- 45-59 FPS - Yellow
	ColorPoor = Color3.fromRGB(255, 130, 100),       -- 30-44 FPS - Orange
	ColorBad = Color3.fromRGB(255, 80, 80),          -- <30 FPS - Red
	
	-- Thresholds
	ExcellentFPS = 60,
	GoodFPS = 45,
	PoorFPS = 30,
	
	-- Visual style
	Font = Enum.Font.Code,
	TextSize = 14,
	BackgroundTransparency = 0.3,
	BackgroundColor = Color3.fromRGB(20, 20, 25),
	StrokeColor = Color3.fromRGB(60, 60, 70),
	
	-- Toggle key
	ToggleKey = Enum.KeyCode.F3,
}

-- === STATE ===
local fpsState = {
	frameTimes = {},
	frameIndex = 1,
	lastUpdateTime = 0,
	currentFPS = 60,
	averageFPS = 60,
	frameTime = 0,
}

-- === UI ELEMENTS ===
local uiElements = {
	screenGui = nil,
	mainFrame = nil,
	fpsLabel = nil,
	detailLabel = nil,
}

-- === HELPER FUNCTIONS ===

local function getFPSColor(fps)
	if fps >= FPS_CONFIG.ExcellentFPS then
		return FPS_CONFIG.ColorExcellent
	elseif fps >= FPS_CONFIG.GoodFPS then
		return FPS_CONFIG.ColorGood
	elseif fps >= FPS_CONFIG.PoorFPS then
		return FPS_CONFIG.ColorPoor
	else
		return FPS_CONFIG.ColorBad
	end
end

local function formatNumber(num, decimals)
	return string.format("%." .. decimals .. "f", num)
end

-- === UI CREATION ===

local function createUI()
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")
	
	-- ScreenGui
	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "FPSDisplay"
	screenGui.ResetOnSpawn = false
	screenGui.DisplayOrder = 999
	screenGui.IgnoreGuiInset = true
	screenGui.Parent = playerGui
	uiElements.screenGui = screenGui
	
	-- Main container frame
	local mainFrame = Instance.new("Frame")
	mainFrame.Name = "FPSFrame"
	mainFrame.Size = UDim2.new(0, 90, 0, 32)
	mainFrame.Position = FPS_CONFIG.Position
	mainFrame.AnchorPoint = Vector2.new(0, 0)
	mainFrame.BackgroundColor3 = FPS_CONFIG.BackgroundColor
	mainFrame.BackgroundTransparency = FPS_CONFIG.BackgroundTransparency
	mainFrame.BorderSizePixel = 0
	mainFrame.Parent = screenGui
	uiElements.mainFrame = mainFrame
	
	-- Corner rounding
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = mainFrame
	
	-- Border stroke
	local stroke = Instance.new("UIStroke")
	stroke.Color = FPS_CONFIG.StrokeColor
	stroke.Thickness = 1
	stroke.Transparency = 0.5
	stroke.Parent = mainFrame
	
	-- Padding
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 10)
	padding.PaddingRight = UDim.new(0, 10)
	padding.PaddingTop = UDim.new(0, 6)
	padding.PaddingBottom = UDim.new(0, 6)
	padding.Parent = mainFrame
	
	-- FPS label
	local fpsLabel = Instance.new("TextLabel")
	fpsLabel.Name = "FPSLabel"
	fpsLabel.Size = UDim2.new(1, 0, 1, 0)
	fpsLabel.Position = UDim2.new(0, 0, 0, 0)
	fpsLabel.BackgroundTransparency = 1
	fpsLabel.Font = FPS_CONFIG.Font
	fpsLabel.TextSize = FPS_CONFIG.TextSize
	fpsLabel.TextColor3 = FPS_CONFIG.ColorExcellent
	fpsLabel.TextXAlignment = Enum.TextXAlignment.Left
	fpsLabel.TextYAlignment = Enum.TextYAlignment.Center
	fpsLabel.Text = "60 FPS"
	fpsLabel.Parent = mainFrame
	uiElements.fpsLabel = fpsLabel
	
	-- Text shadow for readability
	local shadow = Instance.new("TextLabel")
	shadow.Name = "Shadow"
	shadow.Size = UDim2.new(1, 0, 1, 0)
	shadow.Position = UDim2.new(0, 1, 0, 1)
	shadow.BackgroundTransparency = 1
	shadow.Font = FPS_CONFIG.Font
	shadow.TextSize = FPS_CONFIG.TextSize
	shadow.TextColor3 = Color3.new(0, 0, 0)
	shadow.TextTransparency = 0.6
	shadow.TextXAlignment = Enum.TextXAlignment.Left
	shadow.TextYAlignment = Enum.TextYAlignment.Center
	shadow.Text = "60 FPS"
	shadow.ZIndex = fpsLabel.ZIndex - 1
	shadow.Parent = mainFrame
	uiElements.shadowLabel = shadow
	
	-- Detailed stats label (optional)
	if FPS_CONFIG.ShowDetailedStats then
		mainFrame.Size = UDim2.new(0, 120, 0, 50)
		
		local detailLabel = Instance.new("TextLabel")
		detailLabel.Name = "DetailLabel"
		detailLabel.Size = UDim2.new(1, 0, 0, 14)
		detailLabel.Position = UDim2.new(0, 0, 1, -14)
		detailLabel.BackgroundTransparency = 1
		detailLabel.Font = FPS_CONFIG.Font
		detailLabel.TextSize = 11
		detailLabel.TextColor3 = Color3.fromRGB(150, 150, 160)
		detailLabel.TextXAlignment = Enum.TextXAlignment.Left
		detailLabel.TextYAlignment = Enum.TextYAlignment.Bottom
		detailLabel.Text = "0.0ms | 0MB"
		detailLabel.Parent = mainFrame
		uiElements.detailLabel = detailLabel
	end
	
	return screenGui
end

-- === UPDATE FUNCTIONS ===

local function recordFrame(deltaTime)
	-- Store frame time in circular buffer
	fpsState.frameTimes[fpsState.frameIndex] = deltaTime
	fpsState.frameIndex = (fpsState.frameIndex % FPS_CONFIG.SampleCount) + 1
	
	-- Calculate instantaneous FPS
	fpsState.currentFPS = 1 / deltaTime
	fpsState.frameTime = deltaTime * 1000  -- Convert to ms
end

local function calculateAverageFPS()
	local totalTime = 0
	local count = 0
	
	for _, frameTime in pairs(fpsState.frameTimes) do
		totalTime = totalTime + frameTime
		count = count + 1
	end
	
	if count > 0 and totalTime > 0 then
		fpsState.averageFPS = count / totalTime
	end
	
	return fpsState.averageFPS
end

local function updateUI()
	if not uiElements.fpsLabel then return end
	
	local fps = math.floor(fpsState.averageFPS + 0.5)
	local color = getFPSColor(fps)
	
	-- Update main FPS display
	local fpsText = fps .. " FPS"
	uiElements.fpsLabel.Text = fpsText
	uiElements.fpsLabel.TextColor3 = color
	
	-- Update shadow
	if uiElements.shadowLabel then
		uiElements.shadowLabel.Text = fpsText
	end
	
	-- Update detailed stats
	if FPS_CONFIG.ShowDetailedStats and uiElements.detailLabel then
		local frameTimeMs = formatNumber(fpsState.frameTime, 1)
		local memoryMB = formatNumber(Stats:GetTotalMemoryUsageMb(), 0)
		uiElements.detailLabel.Text = frameTimeMs .. "ms | " .. memoryMB .. "MB"
	end
end

local function onRenderStep(deltaTime)
	recordFrame(deltaTime)
	
	-- Throttle UI updates
	local now = tick()
	if now - fpsState.lastUpdateTime >= FPS_CONFIG.UpdateInterval then
		fpsState.lastUpdateTime = now
		calculateAverageFPS()
		updateUI()
	end
end

-- === INPUT HANDLING ===

local function setupToggle()
	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed then return end
		
		if input.KeyCode == FPS_CONFIG.ToggleKey then
			FPSController:Toggle()
		end
	end)
end

-- === PUBLIC API ===

function FPSController:Show()
	self._visible = true
	if uiElements.screenGui then
		uiElements.screenGui.Enabled = true
	end
end

function FPSController:Hide()
	self._visible = false
	if uiElements.screenGui then
		uiElements.screenGui.Enabled = false
	end
end

function FPSController:Toggle()
	if self._visible then
		self:Hide()
	else
		self:Show()
	end
end

function FPSController:IsVisible()
	return self._visible
end

function FPSController:GetFPS()
	return math.floor(fpsState.averageFPS + 0.5)
end

function FPSController:GetFrameTime()
	return fpsState.frameTime
end

function FPSController:SetPosition(position)
	FPS_CONFIG.Position = position
	if uiElements.mainFrame then
		uiElements.mainFrame.Position = position
	end
end

function FPSController:SetDetailedStats(enabled)
	FPS_CONFIG.ShowDetailedStats = enabled
	-- Would need to rebuild UI to add/remove detail label
end

-- === KNIT LIFECYCLE ===

function FPSController:KnitInit()
	-- Initialize frame time buffer
	for i = 1, FPS_CONFIG.SampleCount do
		fpsState.frameTimes[i] = 1/60
	end
end

function FPSController:KnitStart()
	-- Create UI
	self._gui = createUI()
	
	-- Start update loop
	self._updateConnection = RunService.RenderStepped:Connect(onRenderStep)
	
	print("[FPSController] Initialized")
end

return FPSController

