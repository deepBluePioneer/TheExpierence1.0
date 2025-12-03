--[[
	TestingService
	A template service for the Testing place (PlaceID: 111394067928168)
	
	Use this service to test new server-side features before deploying to main places.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Packages = ReplicatedStorage.Packages
local Knit = require(Packages.Knit)

local TestingService = Knit.CreateService {
	Name = "TestingService",
	Client = {
		-- Define client-exposed methods and signals here
		TestSignal = Knit.CreateSignal(),
	},
}

-- Configuration
local CONFIG = {
	DebugMode = true,
	TestValue = 100,
}

--=============================================
-- PRIVATE METHODS
--=============================================

local function log(...)
	if CONFIG.DebugMode then
		print("[TestingService]", ...)
	end
end

--=============================================
-- PUBLIC METHODS (Server-side)
--=============================================

function TestingService:GetTestValue()
	return CONFIG.TestValue
end

function TestingService:SetTestValue(value)
	CONFIG.TestValue = value
	log("TestValue set to:", value)
end

--=============================================
-- CLIENT METHODS (Exposed to clients)
--=============================================

function TestingService.Client:Ping(player)
	log("Ping received from:", player.Name)
	return "Pong!"
end

function TestingService.Client:GetServerTime(player)
	return workspace:GetServerTimeNow()
end

function TestingService.Client:EchoMessage(player, message)
	log("Echo from", player.Name, ":", message)
	return message
end

--=============================================
-- KNIT LIFECYCLE
--=============================================

function TestingService:KnitInit()
	log("Initializing...")
	
	-- Set up player connections
	Players.PlayerAdded:Connect(function(player)
		log("Player joined:", player.Name)
	end)
	
	Players.PlayerRemoving:Connect(function(player)
		log("Player leaving:", player.Name)
	end)
end

function TestingService:KnitStart()
	log("Started!")
	log("Testing place is ready for experiments")
	log("Debug mode:", CONFIG.DebugMode)
end

return TestingService

