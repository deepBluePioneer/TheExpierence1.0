--[[
	TestingController
	A template controller for the Testing place (PlaceID: 111394067928168)
	
	Use this controller to test new client-side features before deploying to main places.
	Now powered by Iris immediate-mode GUI for powerful debugging!
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Lighting = game:GetService("Lighting")

local Packages = ReplicatedStorage.Packages
local Knit = require(Packages.Knit)
local Iris = require(Packages.iris)

local TestingController = Knit.CreateController {
	Name = "TestingController",
}

-- References
local LocalPlayer = Players.LocalPlayer

-- State
TestingController.DebugMode = true
TestingController.TestingService = nil
TestingController.CameraController = nil
TestingController.ShowDemoWindow = false
TestingController.LastPingLatency = 0
TestingController.ServerTimeDisplay = "N/A"
TestingController.IrisVisible = true

-- Iris States (will be initialized after Iris.Init)
local IrisStates = {}

--=============================================
-- PRIVATE METHODS
--=============================================

local function log(...)
	if TestingController.DebugMode then
		print("[TestingController]", ...)
	end
end

--=============================================
-- IRIS DEBUG UI
--=============================================

function TestingController:InitializeIris()
	-- Initialize Iris
	Iris.Init()
	
	-- Create persistent states for Iris widgets
	IrisStates.TestValue = Iris.State(100)
	IrisStates.DebugModeEnabled = Iris.State(true)
	IrisStates.ShowDemoWindow = Iris.State(false)
	IrisStates.TestMessage = Iris.State("Hello from Testing!")
	IrisStates.SliderValue = Iris.State(50)
	IrisStates.ColorPicker = Iris.State(Color3.fromRGB(100, 255, 150))
	
	-- Ambience/Lighting states (initialize with custom defaults)
	IrisStates.ClockTime = Iris.State(22.20)
	IrisStates.Brightness = Iris.State(10)
	IrisStates.ExposureCompensation = Iris.State(1.5)
	IrisStates.Ambient = Iris.State(Color3.fromRGB(0, 0, 0))
	IrisStates.OutdoorAmbient = Iris.State(Color3.fromRGB(70, 70, 70))
	IrisStates.FogColor = Iris.State(Color3.fromRGB(226, 112, 203))
	IrisStates.FogStart = Iris.State(2150)
	IrisStates.FogEnd = Iris.State(6430)
	IrisStates.EnvironmentDiffuseScale = Iris.State(1)
	IrisStates.EnvironmentSpecularScale = Iris.State(1)
	
	-- Apply these values to actual Lighting
	Lighting.ClockTime = 22.20
	Lighting.Brightness = 10
	Lighting.ExposureCompensation = 1.5
	Lighting.Ambient = Color3.fromRGB(0, 0, 0)
	Lighting.OutdoorAmbient = Color3.fromRGB(70, 70, 70)
	Lighting.FogColor = Color3.fromRGB(226, 112, 203)
	Lighting.FogStart = 2150
	Lighting.FogEnd = 6430
	Lighting.EnvironmentDiffuseScale = 1
	Lighting.EnvironmentSpecularScale = 1
	
	-- Connect the main UI function to Iris
	Iris:Connect(function()
		self:DrawDebugUI()
	end)
	
	-- Show mouse cursor since Iris starts visible
	self:ShowMouseCursor()
	
	log("Iris GUI initialized")
end

function TestingController:DrawDebugUI()
	-- Main Testing Window
	local mainWindow = Iris.Window({"🧪 Testing Debug Panel", [Iris.Args.Window.NoClose] = true})
	
	if mainWindow.state.isOpened.value and mainWindow.state.isUncollapsed.value then
		-- Header
		Iris.SeparatorText({"Status"})
		Iris.Text({"Player: " .. LocalPlayer.Name})
		Iris.Text({"Server Time: " .. self.ServerTimeDisplay})
		Iris.Text({"Last Ping: " .. self.LastPingLatency .. "ms"})
		
		Iris.Separator()
		
		-- Debug Controls
		Iris.SeparatorText({"Debug Controls"})
		
		if Iris.Checkbox({"Debug Mode Enabled"}, {isChecked = IrisStates.DebugModeEnabled}).state.isChecked.value then
			self.DebugMode = IrisStates.DebugModeEnabled:get()
		end
		
		Iris.Separator()
		
		-- Server Communication
		Iris.SeparatorText({"Server Communication"})
		
		if Iris.Button({"Ping Server"}).clicked() then
			self:PingServer()
		end
		
		Iris.SameLine()
		if Iris.Button({"Get Server Time"}).clicked() then
			self:UpdateServerTime()
		end
		Iris.End()
		
		Iris.Separator()
		
		-- Demo Window Toggle
		Iris.SeparatorText({"Iris Demo"})
		
		if Iris.Checkbox({"Show Iris Demo Window"}, {isChecked = IrisStates.ShowDemoWindow}).state.isChecked.value then
			self.ShowDemoWindow = IrisStates.ShowDemoWindow:get()
		end
		
		-- Performance Info
		Iris.Separator()
		Iris.SeparatorText({"Performance"})
		
		local fps = math.floor(1 / RunService.Heartbeat:Wait())
		Iris.Text({"FPS: ~" .. fps})
		Iris.Text({"Memory: " .. string.format("%.2f MB", collectgarbage("count") / 1024)})
	end
	
	Iris.End()
	
	-- Ambience Control Window
	self:DrawAmbienceWindow()
	
	-- Show Demo Window if enabled
	if self.ShowDemoWindow then
		Iris.ShowDemoWindow()
	end
end

function TestingController:DrawAmbienceWindow()
	local ambienceWindow = Iris.Window({"🌤️ Ambience Controls"})
	
	if ambienceWindow.state.isOpened.value and ambienceWindow.state.isUncollapsed.value then
		-- Time of Day
		Iris.SeparatorText({"Time of Day"})
		
		Iris.SliderNum({"Clock Time", 0.1, 0, 24}, {number = IrisStates.ClockTime})
		Lighting.ClockTime = IrisStates.ClockTime:get()
		
		-- Quick time presets
		Iris.SameLine()
		if Iris.SmallButton({"Dawn"}).clicked() then
			IrisStates.ClockTime:set(6)
		end
		Iris.End()
		
		Iris.SameLine()
		if Iris.SmallButton({"Noon"}).clicked() then
			IrisStates.ClockTime:set(12)
		end
		if Iris.SmallButton({"Dusk"}).clicked() then
			IrisStates.ClockTime:set(18)
		end
		if Iris.SmallButton({"Midnight"}).clicked() then
			IrisStates.ClockTime:set(0)
		end
		Iris.End()
		
		Iris.Separator()
		
		-- Brightness & Exposure
		Iris.SeparatorText({"Brightness & Exposure"})
		
		Iris.SliderNum({"Brightness", 0.1, 0, 10}, {number = IrisStates.Brightness})
		Lighting.Brightness = IrisStates.Brightness:get()
		
		Iris.SliderNum({"Exposure Compensation", 0.1, -3, 3}, {number = IrisStates.ExposureCompensation})
		Lighting.ExposureCompensation = IrisStates.ExposureCompensation:get()
		
		Iris.Separator()
		
		-- Ambient Colors
		Iris.SeparatorText({"Ambient Colors"})
		
		Iris.InputColor3({"Ambient"}, {color = IrisStates.Ambient})
		Lighting.Ambient = IrisStates.Ambient:get()
		
		Iris.InputColor3({"Outdoor Ambient"}, {color = IrisStates.OutdoorAmbient})
		Lighting.OutdoorAmbient = IrisStates.OutdoorAmbient:get()
		
		Iris.Separator()
		
		-- Fog Settings
		Iris.SeparatorText({"Fog"})
		
		Iris.InputColor3({"Fog Color"}, {color = IrisStates.FogColor})
		Lighting.FogColor = IrisStates.FogColor:get()
		
		Iris.SliderNum({"Fog Start", 10, 0, 5000}, {number = IrisStates.FogStart})
		Lighting.FogStart = IrisStates.FogStart:get()
		
		Iris.SliderNum({"Fog End", 10, 0, 10000}, {number = IrisStates.FogEnd})
		Lighting.FogEnd = IrisStates.FogEnd:get()
		
		Iris.Separator()
		
		-- Environment
		Iris.SeparatorText({"Environment"})
		
		Iris.SliderNum({"Diffuse Scale", 0.05, 0, 1}, {number = IrisStates.EnvironmentDiffuseScale})
		Lighting.EnvironmentDiffuseScale = IrisStates.EnvironmentDiffuseScale:get()
		
		Iris.SliderNum({"Specular Scale", 0.05, 0, 1}, {number = IrisStates.EnvironmentSpecularScale})
		Lighting.EnvironmentSpecularScale = IrisStates.EnvironmentSpecularScale:get()
		
		Iris.Separator()
		
		-- Reset Button
		if Iris.Button({"Reset to Defaults"}).clicked() then
			self:ResetAmbienceToDefaults()
		end
		
		-- Print current values
		Iris.SameLine()
		if Iris.Button({"Print Values"}).clicked() then
			self:PrintAmbienceValues()
		end
		Iris.End()
	end
	
	Iris.End()
end

function TestingController:ResetAmbienceToDefaults()
	-- Custom default lighting values
	IrisStates.ClockTime:set(22.20)
	IrisStates.Brightness:set(10)
	IrisStates.ExposureCompensation:set(1.5)
	IrisStates.Ambient:set(Color3.fromRGB(0, 0, 0))
	IrisStates.OutdoorAmbient:set(Color3.fromRGB(70, 70, 70))
	IrisStates.FogColor:set(Color3.fromRGB(226, 112, 203))
	IrisStates.FogStart:set(2150)
	IrisStates.FogEnd:set(6430)
	IrisStates.EnvironmentDiffuseScale:set(1)
	IrisStates.EnvironmentSpecularScale:set(1)
	
	log("Ambience reset to defaults")
end

function TestingController:PrintAmbienceValues()
	print("===== AMBIENCE VALUES =====")
	print(string.format("ClockTime = %.2f", Lighting.ClockTime))
	print(string.format("Brightness = %.2f", Lighting.Brightness))
	print(string.format("ExposureCompensation = %.2f", Lighting.ExposureCompensation))
	print(string.format("Ambient = Color3.fromRGB(%d, %d, %d)", 
		math.floor(Lighting.Ambient.R * 255), 
		math.floor(Lighting.Ambient.G * 255), 
		math.floor(Lighting.Ambient.B * 255)))
	print(string.format("OutdoorAmbient = Color3.fromRGB(%d, %d, %d)", 
		math.floor(Lighting.OutdoorAmbient.R * 255), 
		math.floor(Lighting.OutdoorAmbient.G * 255), 
		math.floor(Lighting.OutdoorAmbient.B * 255)))
	print(string.format("FogColor = Color3.fromRGB(%d, %d, %d)", 
		math.floor(Lighting.FogColor.R * 255), 
		math.floor(Lighting.FogColor.G * 255), 
		math.floor(Lighting.FogColor.B * 255)))
	print(string.format("FogStart = %.0f", Lighting.FogStart))
	print(string.format("FogEnd = %.0f", Lighting.FogEnd))
	print(string.format("EnvironmentDiffuseScale = %.2f", Lighting.EnvironmentDiffuseScale))
	print(string.format("EnvironmentSpecularScale = %.2f", Lighting.EnvironmentSpecularScale))
	print("===========================")
end

--=============================================
-- MOUSE CURSOR HANDLING
--=============================================

function TestingController:ShowMouseCursor()
	-- Disable camera controls so it stops re-locking the mouse
	if self.CameraController then
		self.CameraController:SetControlsEnabled(false)
		self.CameraController:UnlockCursor()
	end
	
	-- Ensure mouse is unlocked and visible for Iris interaction
	UserInputService.MouseBehavior = Enum.MouseBehavior.Default
	UserInputService.MouseIconEnabled = true
	
	log("Mouse cursor shown for Iris (camera controls disabled)")
end

function TestingController:RestoreMouseCursor()
	-- Re-enable camera controls and lock cursor
	if self.CameraController then
		self.CameraController:SetControlsEnabled(true)
		self.CameraController:LockCursor()
	end
	
	log("Mouse cursor restored (camera controls enabled)")
end

function TestingController:ToggleIris()
	self.IrisVisible = not self.IrisVisible
	Iris.Disabled = not self.IrisVisible
	
	if self.IrisVisible then
		self:ShowMouseCursor()
	else
		self:RestoreMouseCursor()
	end
	
	log("Iris GUI toggled:", self.IrisVisible and "Visible" or "Hidden")
end

--=============================================
-- INPUT HANDLING
--=============================================

function TestingController:SetupInputHandling()
	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed then return end
		
		-- Q to toggle Iris visibility and mouse cursor
		if input.KeyCode == Enum.KeyCode.Q then
			self:ToggleIris()
		end
	end)
	
	log("Input handling set up - Q: Toggle Iris")
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
	self.TestingService:Ping():andThen(function(response)
		self.LastPingLatency = math.floor((tick() - startTime) * 1000)
		log("Server response:", response, "| Latency:", self.LastPingLatency, "ms")
	end):catch(function(err)
		warn("[TestingController] Ping failed:", err)
	end)
end

function TestingController:UpdateServerTime()
	if not self.TestingService then
		self.ServerTimeDisplay = "N/A"
		return
	end
	
	self.TestingService:GetServerTime():andThen(function(serverTime)
		self.ServerTimeDisplay = string.format("%.2f", serverTime)
		log("Server time:", self.ServerTimeDisplay)
	end):catch(function(err)
		self.ServerTimeDisplay = "Error"
		warn("[TestingController] GetServerTime failed:", err)
	end)
end

function TestingController:SendEcho(message)
	if not self.TestingService then
		warn("[TestingController] TestingService not available")
		return
	end
	
	self.TestingService:EchoMessage(message):andThen(function(response)
		log("Echo response:", response)
	end):catch(function(err)
		warn("[TestingController] Echo failed:", err)
	end)
end

--=============================================
-- KNIT LIFECYCLE
--=============================================

function TestingController:KnitInit()
	log("Initializing...")
end

function TestingController:KnitStart()
	log("Starting...")
	
	-- Get reference to the TestingService
	self.TestingService = Knit.GetService("TestingService")
	
	-- Get reference to the CameraController for mouse handling
	self.CameraController = Knit.GetController("CameraController")
	
	-- Initialize Iris GUI
	self:InitializeIris()
	
	-- Setup input handling
	self:SetupInputHandling()
	
	-- Listen to signals from server
	self.TestingService.TestSignal:Connect(function(data)
		log("Received TestSignal:", data)
	end)
	
	-- Initial server time fetch
	self:UpdateServerTime()
	
	log("Ready! Press Q to toggle Iris GUI")
end

return TestingController

