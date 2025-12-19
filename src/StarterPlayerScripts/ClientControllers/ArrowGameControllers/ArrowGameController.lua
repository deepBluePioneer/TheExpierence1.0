--[[
	ArrowGameController
	
	Main client controller for the Arrow Game experience.
	Handles client-side game logic and UI interactions.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local Knit = require(Packages.Knit)

local ArrowGameController = Knit.CreateController({
	Name = "ArrowGameController",
})

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                              CONFIGURATION                                  ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

local CONFIG = {
	-- Add your configuration here
}

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                              STATE                                          ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

local player = Players.LocalPlayer
local ArrowGameService

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         PUBLIC API                                          ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

function ArrowGameController:GetConfig()
	return CONFIG
end

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         KNIT LIFECYCLE                                      ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

function ArrowGameController:KnitInit()
	print("[ArrowGameController] Initializing...")
end

function ArrowGameController:KnitStart()
	print("[ArrowGameController] Starting...")
	
	-- Get service reference
	ArrowGameService = Knit.GetService("ArrowGameService")
	
	-- Connect to server signals
	ArrowGameService.GameStateChanged:Connect(function(newState)
		print("[ArrowGameController] Game state changed:", newState)
	end)
	
	print("[ArrowGameController] Ready")
end

return ArrowGameController

