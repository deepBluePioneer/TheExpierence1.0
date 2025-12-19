--[[
	ArrowPlayerPositionService
	
	Manages player positioning for the Arrow Game.
	When the timer expires, teleports all players to individual
	floating platforms in front of the main ArrowPlatform.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local Knit = require(Packages.Knit)
local Signal = require(Packages.Signal)

local ArrowPlayerPositionService = Knit.CreateService({
	Name = "ArrowPlayerPositionService",
	Client = {
		PlayerPositioned = Knit.CreateSignal(),
		PlatformsCreated = Knit.CreateSignal(),
	},
	
	-- Server-side signals (for other services to listen to)
	PlatformsCreatedServer = Signal.new(),
	PlayerPositionedServer = Signal.new(),
})

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                              CONFIGURATION                                  ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

local CONFIG = {
	-- Platform Settings
	PlatformSize = Vector3.new(8, 2, 8),
	PlatformColor = Color3.fromRGB(80, 200, 255),
	PlatformMaterial = Enum.Material.Neon,
	PlatformTransparency = 0.2,
	
	-- Positioning on the baseplate (away from ArrowPlatform which is at 0,50,0)
	PlatformX = 0,            -- X position
	PlatformZ = 150,          -- Z position (away from ArrowPlatform)
	PlatformHeight = 5,       -- Height just above baseplate
	PlayerSpacing = 15,       -- Horizontal spacing between player platforms
	
	-- Animation/Effects
	FloatAmplitude = 0.5,     -- How much platforms float up/down
	FloatSpeed = 2,           -- Speed of floating animation
	
	-- Ring decoration
	RingColor = Color3.fromRGB(255, 200, 80),
	RingSize = 12,
}

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                              STATE                                          ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

local playerPlatforms = {}  -- {[Player] = platformModel}
local platformsFolder = nil
local floatConnection = nil
local ArrowTimerService = nil

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         PLATFORM CREATION                                   ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

-- Create the platforms folder
function ArrowPlayerPositionService:CreatePlatformsFolder()
	-- Clean up existing folder
	local existing = Workspace:FindFirstChild("ArrowPlayerPlatforms")
	if existing then
		existing:Destroy()
	end
	
	platformsFolder = Instance.new("Folder")
	platformsFolder.Name = "ArrowPlayerPlatforms"
	platformsFolder.Parent = Workspace
	
	return platformsFolder
end

-- Create a single floating platform for a player
function ArrowPlayerPositionService:CreatePlayerPlatform(player: Player, index: number, totalPlayers: number)
	local platformModel = Instance.new("Model")
	platformModel.Name = player.Name .. "_Platform"
	
	-- Calculate position (spread players horizontally, centered)
	local offsetX = CONFIG.PlatformX + (index - 1 - (totalPlayers - 1) / 2) * CONFIG.PlayerSpacing
	local basePosition = Vector3.new(offsetX, CONFIG.PlatformHeight, CONFIG.PlatformZ)
	
	-- Main platform
	local platform = Instance.new("Part")
	platform.Name = "Platform"
	platform.Size = CONFIG.PlatformSize
	platform.Position = basePosition
	platform.Anchored = true
	platform.CanCollide = true
	platform.Material = CONFIG.PlatformMaterial
	platform.Color = CONFIG.PlatformColor
	platform.Transparency = CONFIG.PlatformTransparency
	platform.TopSurface = Enum.SurfaceType.Smooth
	platform.BottomSurface = Enum.SurfaceType.Smooth
	platform.Parent = platformModel
	
	-- Corner radius effect using wedges
	local corner = Instance.new("UICorner")
	-- Note: UICorner doesn't work on Parts, so we'll use a cylinder ring instead
	
	-- Decorative ring around platform
	local ring = Instance.new("Part")
	ring.Name = "Ring"
	ring.Shape = Enum.PartType.Cylinder
	ring.Size = Vector3.new(1, CONFIG.RingSize, CONFIG.RingSize)
	ring.CFrame = CFrame.new(basePosition - Vector3.new(0, CONFIG.PlatformSize.Y / 2 + 0.5, 0)) * CFrame.Angles(0, 0, math.rad(90))
	ring.Anchored = true
	ring.CanCollide = false
	ring.Material = Enum.Material.Neon
	ring.Color = CONFIG.RingColor
	ring.Transparency = 0.3
	ring.Parent = platformModel
	
	-- Glow underneath
	local glow = Instance.new("Part")
	glow.Name = "Glow"
	glow.Shape = Enum.PartType.Ball
	glow.Size = Vector3.new(6, 6, 6)
	glow.Position = basePosition - Vector3.new(0, CONFIG.PlatformSize.Y, 0)
	glow.Anchored = true
	glow.CanCollide = false
	glow.Material = Enum.Material.Neon
	glow.Color = CONFIG.PlatformColor
	glow.Transparency = 0.5
	glow.Parent = platformModel
	
	-- Point light for effect
	local light = Instance.new("PointLight")
	light.Color = CONFIG.PlatformColor
	light.Brightness = 1.5
	light.Range = 20
	light.Parent = glow
	
	-- Player name label (BillboardGui)
	local billboardGui = Instance.new("BillboardGui")
	billboardGui.Name = "NameLabel"
	billboardGui.Size = UDim2.new(0, 100, 0, 30)
	billboardGui.StudsOffset = Vector3.new(0, 4, 0)
	billboardGui.Adornee = platform
	billboardGui.AlwaysOnTop = true
	billboardGui.Parent = platformModel
	
	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "Text"
	nameLabel.Size = UDim2.new(1, 0, 1, 0)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Text = player.DisplayName
	nameLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	nameLabel.TextStrokeTransparency = 0.5
	nameLabel.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	nameLabel.FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Bold)
	nameLabel.TextScaled = true
	nameLabel.Parent = billboardGui
	
	platformModel.PrimaryPart = platform
	platformModel.Parent = platformsFolder
	
	-- Store reference
	playerPlatforms[player] = {
		model = platformModel,
		platform = platform,
		basePosition = basePosition,
		index = index,
	}
	
	print(string.format("[ArrowPlayerPosition] ✓ Created platform for %s at index %d", player.Name, index))
	
	return platformModel
end

-- Create platforms for all current players
function ArrowPlayerPositionService:CreateAllPlayerPlatforms()
	self:CreatePlatformsFolder()
	self:ClearPlayerPlatforms()
	
	local allPlayers = Players:GetPlayers()
	local totalPlayers = #allPlayers
	
	if totalPlayers == 0 then
		print("[ArrowPlayerPosition] No players to create platforms for")
		return
	end
	
	for index, player in ipairs(allPlayers) do
		self:CreatePlayerPlatform(player, index, totalPlayers)
	end
	
	-- Don't start floating animation - keeps platforms stable for players
	-- self:StartFloatingAnimation()
	
	print(string.format("[ArrowPlayerPosition] ✓ Created %d player platforms", totalPlayers))
	self.Client.PlatformsCreated:FireAll(totalPlayers)
	self.PlatformsCreatedServer:Fire(totalPlayers)
	
	return playerPlatforms
end

-- Clear all player platforms
function ArrowPlayerPositionService:ClearPlayerPlatforms()
	self:StopFloatingAnimation()
	
	for player, data in pairs(playerPlatforms) do
		if data.model then
			data.model:Destroy()
		end
	end
	playerPlatforms = {}
	
	print("[ArrowPlayerPosition] Cleared all player platforms")
end

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         FLOATING ANIMATION                                  ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

function ArrowPlayerPositionService:StartFloatingAnimation()
	self:StopFloatingAnimation()
	
	local RunService = game:GetService("RunService")
	local startTime = tick()
	
	floatConnection = RunService.Heartbeat:Connect(function()
		local elapsed = tick() - startTime
		
		for player, data in pairs(playerPlatforms) do
			if data.model and data.platform and data.platform.Parent then
				-- Calculate floating offset with slight variation per platform
				local offset = math.sin(elapsed * CONFIG.FloatSpeed + data.index * 0.5) * CONFIG.FloatAmplitude
				local newPosition = data.basePosition + Vector3.new(0, offset, 0)
				
				-- Move the entire model
				local currentCFrame = data.platform.CFrame
				local targetCFrame = CFrame.new(newPosition) * (currentCFrame - currentCFrame.Position)
				data.model:SetPrimaryPartCFrame(targetCFrame)
			end
		end
	end)
	
	print("[ArrowPlayerPosition] Started floating animation")
end

function ArrowPlayerPositionService:StopFloatingAnimation()
	if floatConnection then
		floatConnection:Disconnect()
		floatConnection = nil
		print("[ArrowPlayerPosition] Stopped floating animation")
	end
end

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         PLAYER TELEPORTATION                                ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

-- Teleport a single player to their platform
function ArrowPlayerPositionService:TeleportPlayerToPlatform(player: Player)
	local data = playerPlatforms[player]
	if not data or not data.platform then
		warn("[ArrowPlayerPosition] No platform found for player:", player.Name)
		return false
	end
	
	local character = player.Character
	if not character then
		warn("[ArrowPlayerPosition] No character for player:", player.Name)
		return false
	end
	
	local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")
	if not humanoidRootPart then
		warn("[ArrowPlayerPosition] No HumanoidRootPart for player:", player.Name)
		return false
	end
	
	-- Calculate spawn position on top of platform
	local platformTop = data.platform.Position + Vector3.new(0, CONFIG.PlatformSize.Y / 2 + 3, 0)
	
	-- Teleport player and rotate them to face left (-X direction, 90 degrees)
	humanoidRootPart.CFrame = CFrame.new(platformTop) * CFrame.Angles(0, math.rad(90), 0)
	
	-- Reset velocity
	humanoidRootPart.AssemblyLinearVelocity = Vector3.zero
	humanoidRootPart.AssemblyAngularVelocity = Vector3.zero
	
	print(string.format("[ArrowPlayerPosition] ✓ Teleported %s to their platform", player.Name))
	-- Fire to the specific player that was positioned
	self.Client.PlayerPositioned:Fire(player, player, platformTop)
	-- Fire server-side signal for other services
	self.PlayerPositionedServer:Fire(player, platformTop)
	
	return true
end

-- Teleport all players to their platforms
function ArrowPlayerPositionService:TeleportAllPlayersToPlatforms()
	print("[ArrowPlayerPosition] Teleporting all players to platforms...")
	
	-- First create platforms for current players
	self:CreateAllPlayerPlatforms()
	
	-- Small delay to ensure platforms are created
	task.wait(0.1)
	
	-- Teleport each player
	local teleportedCount = 0
	for player, _ in pairs(playerPlatforms) do
		if self:TeleportPlayerToPlatform(player) then
			teleportedCount = teleportedCount + 1
		end
	end
	
	print(string.format("[ArrowPlayerPosition] ✓ Teleported %d players to platforms", teleportedCount))
	return teleportedCount
end

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         TIMER EVENT HANDLER                                 ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

function ArrowPlayerPositionService:OnTimerExpired()
	print("[ArrowPlayerPosition] Timer expired! Moving players to platforms...")
	self:TeleportAllPlayersToPlatforms()
end

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         PUBLIC API                                          ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

function ArrowPlayerPositionService:GetPlayerPlatform(player: Player)
	return playerPlatforms[player]
end

function ArrowPlayerPositionService:GetAllPlatforms()
	return playerPlatforms
end

function ArrowPlayerPositionService:GetConfig()
	return CONFIG
end

function ArrowPlayerPositionService:UpdateConfig(key: string, value: any)
	if CONFIG[key] ~= nil then
		CONFIG[key] = value
		return true
	end
	return false
end

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         CLIENT METHODS                                      ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

function ArrowPlayerPositionService.Client:GetMyPlatformPosition(player)
	local data = playerPlatforms[player]
	if data and data.platform then
		return data.platform.Position
	end
	return nil
end

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         KNIT LIFECYCLE                                      ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

function ArrowPlayerPositionService:KnitInit()
	print("[ArrowPlayerPositionService] Initializing...")
	self:CreatePlatformsFolder()
end

function ArrowPlayerPositionService:KnitStart()
	print("[ArrowPlayerPositionService] Starting...")
	
	-- Get ArrowTimerService and connect to server-side timer end signal
	ArrowTimerService = Knit.GetService("ArrowTimerService")
	
	-- Listen for timer expiration (server-side signal)
	ArrowTimerService.TimerEndedServer:Connect(function()
		print("[ArrowPlayerPositionService] Received TimerEndedServer signal!")
		self:OnTimerExpired()
	end)
	
	-- Clean up platforms when player leaves
	Players.PlayerRemoving:Connect(function(player)
		local data = playerPlatforms[player]
		if data and data.model then
			data.model:Destroy()
			playerPlatforms[player] = nil
			print(string.format("[ArrowPlayerPosition] Removed platform for leaving player: %s", player.Name))
		end
	end)
	
	print("[ArrowPlayerPositionService] Ready")
end

return ArrowPlayerPositionService

