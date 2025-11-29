local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local CustomPackages = ReplicatedStorage:WaitForChild("CustomPackages")
local Knit = require(Packages.Knit)
local PlayerAddedFunctions = require(CustomPackages:WaitForChild("PlayerAddedController"):WaitForChild("PlayerAddedFunctions"))

local CameraService = Knit.CreateService {
	Name = "CameraService",
	Client = {},
	isFPSMode = true,  -- Track current camera mode
}

-- === CONFIG ===
local CAMERA_CONFIG = {
	-- First Person Settings
	FPSEnabled = true,                    -- Start in FPS mode
	LockFirstPerson = true,               -- Use Roblox's built-in lock (prevents any zoom out)
	
	-- If not using LockFirstPerson, use zoom limits instead
	MinZoomDistance = 0.5,                -- Minimum zoom (0.5 = first person)
	MaxZoomDistance = 0.5,                -- Maximum zoom (0.5 = locked to first person)
	
	-- Third Person Settings (when FPS is disabled)
	ThirdPersonMinZoom = 0.5,
	ThirdPersonMaxZoom = 128,
	ThirdPersonDefaultZoom = 12,
}

-- === CAMERA MODE FUNCTIONS ===

-- Set a player to first-person mode
local function setFirstPerson(player)
	if not player then return end
	
	if CAMERA_CONFIG.LockFirstPerson then
		-- Use Roblox's built-in first person lock
		player.CameraMode = Enum.CameraMode.LockFirstPerson
	else
		-- Use zoom distance limits
		player.CameraMinZoomDistance = CAMERA_CONFIG.MinZoomDistance
		player.CameraMaxZoomDistance = CAMERA_CONFIG.MaxZoomDistance
	end
	
	print(string.format("[CameraService] Set %s to First Person mode", player.Name))
end

-- Set a player to third-person mode
local function setThirdPerson(player)
	if not player then return end
	
	-- Unlock camera mode
	player.CameraMode = Enum.CameraMode.Classic
	
	-- Set zoom limits for third person
	player.CameraMinZoomDistance = CAMERA_CONFIG.ThirdPersonMinZoom
	player.CameraMaxZoomDistance = CAMERA_CONFIG.ThirdPersonMaxZoom
	
	print(string.format("[CameraService] Set %s to Third Person mode", player.Name))
end

-- === PLAYER ADDED FUNCTIONS ===

local function onPlayerAdded(player)
	print(string.format("[CameraService] Player joined: %s", player.Name))
	
	-- Apply initial camera mode
	if CAMERA_CONFIG.FPSEnabled then
		setFirstPerson(player)
	else
		setThirdPerson(player)
	end
end

local function onPlayerRemoving(player)
	print(string.format("[CameraService] Player leaving: %s", player.Name))
end

local function onCharacterAdded(player, character)
	print(string.format("[CameraService] Character spawned for: %s", player.Name))
	
	-- Re-apply camera mode when character respawns (in case it was reset)
	if CameraService.isFPSMode then
		setFirstPerson(player)
	else
		setThirdPerson(player)
	end
end

-- === KNIT LIFECYCLE ===

function CameraService:KnitInit()
	self.isFPSMode = CAMERA_CONFIG.FPSEnabled
end

function CameraService:KnitStart()
	-- Set up player added/removing/character added listeners
	PlayerAddedFunctions(
		onPlayerAdded,           -- When player joins
		onPlayerRemoving,        -- When player leaves
		onCharacterAdded         -- When character spawns
	)
	
	print("[CameraService] Initialized - FPS Mode:", self.isFPSMode)
end

-- === PUBLIC METHODS ===

-- Enable FPS mode for all players
function CameraService:EnableFPSMode()
	self.isFPSMode = true
	
	for _, player in ipairs(Players:GetPlayers()) do
		setFirstPerson(player)
	end
	
	print("[CameraService] FPS Mode enabled for all players")
end

-- Disable FPS mode (enable third person) for all players
function CameraService:DisableFPSMode()
	self.isFPSMode = false
	
	for _, player in ipairs(Players:GetPlayers()) do
		setThirdPerson(player)
	end
	
	print("[CameraService] Third Person Mode enabled for all players")
end

-- Toggle between FPS and third person
function CameraService:ToggleFPSMode()
	if self.isFPSMode then
		self:DisableFPSMode()
	else
		self:EnableFPSMode()
	end
end

-- Set camera mode for a specific player
function CameraService:SetPlayerCameraMode(player, isFPS)
	if isFPS then
		setFirstPerson(player)
	else
		setThirdPerson(player)
	end
end

-- Get current FPS mode state
function CameraService:IsFPSMode()
	return self.isFPSMode
end

-- Set custom zoom limits (only works if LockFirstPerson is false)
function CameraService:SetZoomLimits(minZoom, maxZoom)
	CAMERA_CONFIG.MinZoomDistance = minZoom
	CAMERA_CONFIG.MaxZoomDistance = maxZoom
	
	-- Apply to all players
	for _, player in ipairs(Players:GetPlayers()) do
		player.CameraMinZoomDistance = minZoom
		player.CameraMaxZoomDistance = maxZoom
	end
end

-- === CLIENT METHODS ===

-- Client can request their camera mode
function CameraService.Client:GetCameraMode(player)
	return self.Server.isFPSMode
end

-- Client can check if FPS mode is active
function CameraService.Client:IsFPSMode(player)
	return self.Server:IsFPSMode()
end

return CameraService

