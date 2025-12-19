--[[
	ArrowBowService
	
	Creates and manages bow and arrow models for players.
	Spawns bows when players are positioned on their platforms.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local Knit = require(Packages.Knit)
local Signal = require(Packages.Signal)

local ArrowBowService = Knit.CreateService({
	Name = "ArrowBowService",
	Client = {
		BowCreated = Knit.CreateSignal(),
		BowAimUpdated = Knit.CreateSignal(),
		ArrowFired = Knit.CreateSignal(),
	},
	
	-- Server-side signals
	BowsSpawned = Signal.new(),
})

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                              CONFIGURATION                                  ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

local CONFIG = {
	-- Bow Settings
	BowHeight = 5,              -- Height above player
	BowColor = Color3.fromRGB(139, 90, 43),  -- Wood brown
	BowMaterial = Enum.Material.Wood,
	BowThickness = 0.3,
	BowWidth = 4,
	BowCurve = 0.8,
	
	-- String Settings
	StringColor = Color3.fromRGB(200, 200, 200),
	StringThickness = 0.08,
	
	-- Arrow Settings
	ArrowLength = 3,
	ArrowThickness = 0.15,
	ArrowColor = Color3.fromRGB(139, 90, 43),
	ArrowHeadColor = Color3.fromRGB(150, 150, 160),
	ArrowFeatherColor = Color3.fromRGB(255, 50, 50),
	
	-- Aim Settings
	MinPitch = -45,  -- Degrees
	MaxPitch = 60,   -- Degrees
}

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                              STATE                                          ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

local playerBows = {}  -- {[Player] = bowModel}
local bowsFolder = nil
local ArrowPlayerPositionService = nil

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         BOW CREATION                                        ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

function ArrowBowService:CreateBowsFolder()
	local existing = Workspace:FindFirstChild("ArrowBows")
	if existing then
		existing:Destroy()
	end
	
	bowsFolder = Instance.new("Folder")
	bowsFolder.Name = "ArrowBows"
	bowsFolder.Parent = Workspace
	
	return bowsFolder
end

-- Create a simple arrow part (just a long part that points at target)
function ArrowBowService:CreateBowModel(player: Player, position: Vector3)
	local bowModel = Instance.new("Model")
	bowModel.Name = player.Name .. "_Bow"
	
	-- Create the simple arrow part (long rectangular part)
	local arrowPart = Instance.new("Part")
	arrowPart.Name = "ArrowPart"
	arrowPart.Size = Vector3.new(0.5, 0.5, 5) -- Long part, Z is the length (pointing direction)
	arrowPart.Material = Enum.Material.Neon
	arrowPart.Color = Color3.fromRGB(255, 100, 100) -- Red so it's visible
	arrowPart.Anchored = true
	arrowPart.CanCollide = false
	arrowPart.CFrame = CFrame.new(position)
	arrowPart.Parent = bowModel
	
	-- Create aim pivot (same as arrow part for simple version)
	local aimPivot = arrowPart
	
	bowModel.PrimaryPart = arrowPart
	bowModel.Parent = bowsFolder
	
	-- Store reference
	playerBows[player] = {
		model = bowModel,
		position = position,
		pitch = 0,
		aimPivot = aimPivot,
		arrowPart = arrowPart,
		partOffsets = {},
		baseRotation = CFrame.new(),
	}
	
	print(string.format("[ArrowBowService] ✓ Created simple arrow for %s", player.Name))
	self.Client.BowCreated:Fire(player, position)
	
	return bowModel
end

-- Create bows for all players on platforms
function ArrowBowService:CreateBowsForAllPlayers()
	self:CreateBowsFolder()
	self:ClearAllBows()
	
	-- Get platform positions from ArrowPlayerPositionService
	local allPlatforms = ArrowPlayerPositionService:GetAllPlatforms()
	
	local bowCount = 0
	for player, platformData in pairs(allPlatforms) do
		if platformData.platform then
			local platformTop = platformData.platform.Position + Vector3.new(0, platformData.platform.Size.Y / 2 + CONFIG.BowHeight, 0)
			self:CreateBowModel(player, platformTop)
			bowCount = bowCount + 1
		end
	end
	
	print(string.format("[ArrowBowService] ✓ Created %d bows", bowCount))
	self.BowsSpawned:Fire(bowCount)
	
	return bowCount
end

-- Clear all bows
function ArrowBowService:ClearAllBows()
	for player, data in pairs(playerBows) do
		if data.model then
			data.model:Destroy()
		end
	end
	playerBows = {}
	print("[ArrowBowService] Cleared all bows")
end

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         BOW AIMING                                          ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

-- Update bow pitch (rotation) for a player - only rotates up/down
function ArrowBowService:UpdateBowPitch(player: Player, pitch: number)
	local data = playerBows[player]
	if not data or not data.model then return false end
	
	-- Clamp pitch
	pitch = math.clamp(pitch, CONFIG.MinPitch, CONFIG.MaxPitch)
	data.pitch = pitch
	
	-- Calculate new pivot CFrame with pitch rotation
	-- Base rotation faces left, pitch rotates up/down around local X axis
	local pitchRotation = CFrame.Angles(math.rad(pitch), 0, 0)
	local newPivotCFrame = CFrame.new(data.position) * data.baseRotation * pitchRotation
	
	-- Update pivot
	data.aimPivot.CFrame = newPivotCFrame
	
	-- Update all parts using their stored local offsets
	for part, localCFrame in pairs(data.partOffsets) do
		if part and part.Parent then
			part.CFrame = newPivotCFrame * localCFrame
		end
	end
	
	return true
end

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         PUBLIC API                                          ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

function ArrowBowService:GetPlayerBow(player: Player)
	return playerBows[player]
end

function ArrowBowService:GetAllBows()
	return playerBows
end

function ArrowBowService:GetConfig()
	return CONFIG
end

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         CLIENT METHODS                                      ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

function ArrowBowService.Client:UpdateAim(player, pitch: number)
	return ArrowBowService:UpdateBowPitch(player, pitch)
end

function ArrowBowService.Client:GetBowPosition(player)
	local data = playerBows[player]
	if data then
		return data.position
	end
	return nil
end

function ArrowBowService.Client:FireArrow(player, power: number, pitch: number)
	print(string.format("[ArrowBowService] %s fired arrow with power %.1f at pitch %.1f", player.Name, power, pitch))
	ArrowBowService.Client.ArrowFired:FireAll(player, power, pitch)
	return true
end

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         KNIT LIFECYCLE                                      ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

function ArrowBowService:KnitInit()
	print("[ArrowBowService] Initializing...")
	self:CreateBowsFolder()
end

function ArrowBowService:KnitStart()
	print("[ArrowBowService] Starting...")
	
	-- Get ArrowPlayerPositionService
	ArrowPlayerPositionService = Knit.GetService("ArrowPlayerPositionService")
	
	-- Listen for when players are positioned on platforms (server-side signal)
	ArrowPlayerPositionService.PlatformsCreatedServer:Connect(function(count)
		-- Small delay to ensure platforms are set up
		task.wait(0.5)
		self:CreateBowsForAllPlayers()
	end)
	
	-- Clean up when player leaves
	Players.PlayerRemoving:Connect(function(player)
		local data = playerBows[player]
		if data and data.model then
			data.model:Destroy()
			playerBows[player] = nil
		end
	end)
	
	print("[ArrowBowService] Ready")
end

return ArrowBowService

