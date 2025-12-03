--[[
	TestingController
	A template controller for the Testing place (PlaceID: 111394067928168)
	
	Use this controller to test new client-side features before deploying to main places.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local Packages = ReplicatedStorage.Packages
local Knit = require(Packages.Knit)

local TestingController = Knit.CreateController {
	Name = "TestingController",
}

-- References
local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

-- State
TestingController.DebugMode = true
TestingController.TestingService = nil

--=============================================
-- PRIVATE METHODS
--=============================================

local function log(...)
	if TestingController.DebugMode then
		print("[TestingController]", ...)
	end
end

--=============================================
-- DEBUG UI
--=============================================

function TestingController:CreateDebugUI()
	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "TestingDebugUI"
	screenGui.ResetOnSpawn = false
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screenGui.Parent = PlayerGui
	self.ScreenGui = screenGui
	
	-- Debug label
	local debugLabel = Instance.new("TextLabel")
	debugLabel.Name = "DebugLabel"
	debugLabel.Size = UDim2.new(0, 300, 0, 50)
	debugLabel.Position = UDim2.new(0, 10, 0, 10)
	debugLabel.BackgroundColor3 = Color3.fromRGB(30, 30, 40)
	debugLabel.BackgroundTransparency = 0.3
	debugLabel.BorderSizePixel = 0
	debugLabel.Text = "🧪 Testing Place Active"
	debugLabel.TextColor3 = Color3.fromRGB(100, 255, 150)
	debugLabel.TextScaled = true
	debugLabel.Font = Enum.Font.GothamBold
	debugLabel.Parent = screenGui
	self.DebugLabel = debugLabel
	
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = debugLabel
	
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 10)
	padding.PaddingRight = UDim.new(0, 10)
	padding.Parent = debugLabel
	
	log("Debug UI created")
end

function TestingController:UpdateDebugLabel(text)
	if self.DebugLabel then
		self.DebugLabel.Text = text
	end
end

--=============================================
-- INPUT HANDLING
--=============================================

function TestingController:SetupInputHandling()
	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed then return end
		
		-- F9 to toggle debug mode
		if input.KeyCode == Enum.KeyCode.F9 then
			self.DebugMode = not self.DebugMode
			log("Debug mode toggled:", self.DebugMode)
			self:UpdateDebugLabel(self.DebugMode and "🧪 Debug: ON" or "🧪 Debug: OFF")
		end
		
		-- F10 to ping server
		if input.KeyCode == Enum.KeyCode.F10 then
			self:PingServer()
		end
	end)
	
	log("Input handling set up - F9: Toggle Debug, F10: Ping Server")
end

--=============================================
-- SERVER COMMUNICATION
--=============================================

function TestingController:PingServer()
	if not self.TestingService then
		warn("[TestingController] TestingService not available")
		return
	end
	
	local startTime = tick()
	local response = self.TestingService:Ping()
	local latency = math.floor((tick() - startTime) * 1000)
	
	log("Server response:", response, "| Latency:", latency, "ms")
	self:UpdateDebugLabel(string.format("🧪 Ping: %dms", latency))
end

function TestingController:GetServerTime()
	if not self.TestingService then return nil end
	return self.TestingService:GetServerTime()
end

--=============================================
-- KNIT LIFECYCLE
--=============================================

function TestingController:KnitInit()
	log("Initializing...")
	self:CreateDebugUI()
end

function TestingController:KnitStart()
	log("Starting...")
	
	-- Get reference to the TestingService
	self.TestingService = Knit.GetService("TestingService")
	
	-- Setup input handling
	self:SetupInputHandling()
	
	-- Listen to signals from server
	self.TestingService.TestSignal:Connect(function(data)
		log("Received TestSignal:", data)
	end)
	
	log("Ready! Press F9 to toggle debug, F10 to ping server")
	self:UpdateDebugLabel("🧪 Testing Place Ready")
end

return TestingController

