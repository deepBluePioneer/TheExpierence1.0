--[[
	ArrowGameService
	
	Main service for the Arrow Game experience.
	Handles server-side game logic and state management.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local Knit = require(Packages.Knit)

local ArrowGameService = Knit.CreateService({
	Name = "ArrowGameService",
	Client = {
		GameStateChanged = Knit.CreateSignal(),
	},
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

local gameState = {
	isActive = false,
}

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         PUBLIC API                                          ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

function ArrowGameService:GetGameState()
	return gameState
end

function ArrowGameService:GetConfig()
	return CONFIG
end

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         CLIENT METHODS                                      ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

function ArrowGameService.Client:GetGameState(player)
	return ArrowGameService:GetGameState()
end

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         KNIT LIFECYCLE                                      ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

function ArrowGameService:KnitInit()
	print("[ArrowGameService] Initializing...")
end

function ArrowGameService:KnitStart()
	print("[ArrowGameService] Starting...")
	print("[ArrowGameService] Ready")
end

return ArrowGameService

