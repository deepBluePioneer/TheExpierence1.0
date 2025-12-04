--[[
	RedZoneService
	Creates red zone parts for each baseplate and registers them with ZonePlus
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local CollectionService = game:GetService("CollectionService")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local CustomPackages = ReplicatedStorage:WaitForChild("CustomPackages")
local Knit = require(Packages.Knit)

-- Zone+ Module
local ZoneRoot = CustomPackages:WaitForChild("ZoneRoot")
local Zone = require(ZoneRoot:WaitForChild("Zone"))

local RedZoneService = Knit.CreateService {
	Name = "RedZoneService",
	Client = {},
	_zones = {},  -- Store all zone instances
	_zoneParts = {},  -- Store all zone parts
	_autoStart = false,  -- Set to false to let WorldInitService control initialization
	_isInitialized = false,
}

-- === CONFIG ===
local CONFIG = {
	Enabled = true,
	ZoneTag = "redZone",
	ZoneColor = Color3.fromRGB(255, 50, 50),  -- Red (slightly brighter)
	ZoneTransparency = 1,  -- Very transparent (0.85 = 85% transparent, barely visible)
	CreateZonesAfterTerrain = true,  -- Wait for terrain generation
	WaitForTerrainDelay = 1,  -- Seconds to wait after terrain completes
	ZoneHeight = 50,  -- Height of the red zone (tall enough to cover terrain)
}

-- === ZONE CREATION ===

-- Create a red zone part for a baseplate
local function createRedZone(baseplateInfo, cellHeight)
	local centerX = baseplateInfo.centerX
	local centerZ = baseplateInfo.centerZ
	local centerY = baseplateInfo.centerY
	local width = baseplateInfo.size.X
	local depth = baseplateInfo.size.Z
	
	-- Use config height or fallback to cellHeight
	local zoneHeight = CONFIG.ZoneHeight or cellHeight
	
	-- Create folder for red zones
	local zoneFolder = Workspace:FindFirstChild("RedZones")
	if not zoneFolder then
		zoneFolder = Instance.new("Folder")
		zoneFolder.Name = "RedZones"
		zoneFolder.Parent = Workspace
	end
	
	-- Create the zone part - semi-transparent red zone
	local zonePart = Instance.new("Part")
	zonePart.Name = string.format("RedZone_%.0f_%.0f", centerX, centerZ)
	zonePart.Size = Vector3.new(width, zoneHeight, depth)
	zonePart.Position = Vector3.new(centerX, centerY + (zoneHeight / 2), centerZ)
	zonePart.Color = CONFIG.ZoneColor
	zonePart.Material = Enum.Material.ForceField  -- ForceField material looks nice for zones
	zonePart.Transparency = CONFIG.ZoneTransparency
	zonePart.Anchored = true
	zonePart.CanCollide = false
	zonePart.CastShadow = false
	zonePart.TopSurface = Enum.SurfaceType.Smooth
	zonePart.BottomSurface = Enum.SurfaceType.Smooth
	zonePart.Parent = zoneFolder
	
	-- Add tag
	CollectionService:AddTag(zonePart, CONFIG.ZoneTag)
	
	-- Create ZonePlus zone
	local zone = Zone.new(zonePart)
	zone:setAccuracy("High")
	
	-- Log when player enters red zone
	zone.playerEntered:Connect(function(player)
		--[[print(string.format("[RedZoneService] Player %s entered red zone at (%.1f, %.1f, %.1f)", 
			player.Name, centerX, centerY, centerZ))]]
	end)
	
	-- Log when player exits red zone
	zone.playerExited:Connect(function(player)
		--[[print(string.format("[RedZoneService] Player %s exited red zone at (%.1f, %.1f, %.1f)", 
			player.Name, centerX, centerY, centerZ))]]
	end)
	
	-- Store zone info
	local zoneData = {
		zone = zone,
		part = zonePart,
		baseplateInfo = baseplateInfo,
	}
	
	table.insert(RedZoneService._zones, zoneData)
	table.insert(RedZoneService._zoneParts, zonePart)
	
	--[[print(string.format("[RedZoneService] Created red zone at (%.1f, %.1f, %.1f) size (%.1f, %.1f, %.1f)", 
		centerX, centerY, centerZ, width, cellHeight, depth))]]
	
	return zoneData
end

-- Create red zones for all baseplates in the grid
local function createAllRedZones()
	local GridService = Knit.GetService("GridService")
	local WorldInitService = nil
	pcall(function()
		WorldInitService = Knit.GetService("WorldInitService")
	end)
	
	-- Get baseplate positions from WorldInitService
	local baseplatePositions = {}
	if WorldInitService then
		baseplatePositions = WorldInitService:GetBaseplatePositions()
	end
	
	if #baseplatePositions == 0 then
		warn("[RedZoneService] No baseplates found. Make sure WorldInitService has created the baseplate grid.")
		return
	end
	
	-- Get cell size from GridService for zone height
	local cellSize = GridService:GetCellSize()
	if not cellSize or cellSize <= 0 then
		warn("[RedZoneService] Could not get cell size from GridService. Using default height of 8.")
		cellSize = 8
	end
	
	--[[print(string.format("[RedZoneService] Creating %d red zones with cell height %.1f...", #baseplatePositions, cellSize))]]
	
	-- Get LoadingService for progress reporting
	local LoadingService = nil
	pcall(function()
		LoadingService = Knit.GetService("LoadingService")
	end)
	
	local function reportProgress(current, total, message)
		if LoadingService then
			LoadingService:ReportProgress("RedZoneService", current, total, message or "Creating red zones")
		end
	end
	
	reportProgress(0, #baseplatePositions, "Creating red zones...")
	
	-- Create zone for each baseplate
	for i, baseplateInfo in ipairs(baseplatePositions) do
		createRedZone(baseplateInfo, cellSize)
		reportProgress(i, #baseplatePositions, string.format("Creating red zone %d/%d", i, #baseplatePositions))
		
		-- Yield between zones
		task.wait(0.05)
	end
	
	reportProgress(#baseplatePositions, #baseplatePositions, "Red zones complete")
	--[[print(string.format("[RedZoneService] Created %d red zones", #RedZoneService._zones))]]
end

-- === KNIT LIFECYCLE ===

function RedZoneService:KnitInit()
	--("[RedZoneService] Initializing...")
end

function RedZoneService:KnitStart()
	--("[RedZoneService] Starting...")
	
	if not CONFIG.Enabled then
		--("[RedZoneService] Red zone creation disabled")
		return
	end
	
	-- Only auto-create if _autoStart is true (legacy mode)
	-- WorldInitService will call InitializeZones() instead
	if self._autoStart then
		-- Wait for grid/terrain to be generated
		if CONFIG.CreateZonesAfterTerrain then
			local LoadingService = nil
			pcall(function()
				LoadingService = Knit.GetService("LoadingService")
			end)
			
			-- Wait for GridService step to complete
			if LoadingService then
				LoadingService:OnStepComplete("GridService", function()
					--("[RedZoneService] GridService complete, waiting before creating red zones...")
					task.wait(CONFIG.WaitForTerrainDelay)
					createAllRedZones()
					
					-- Mark step complete
					if LoadingService then
						LoadingService:MarkStepComplete("RedZoneService")
					end
				end)
			else
				-- Fallback: wait a bit then create zones
				task.wait(CONFIG.WaitForTerrainDelay)
				createAllRedZones()
			end
		else
			-- Create immediately
			createAllRedZones()
		end
	else
		--("[RedZoneService] Waiting for WorldInitService to initialize zones...")
	end
end

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║               WORLDINITSERVICE INTEGRATION                                 ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

-- Initialize zones (called by WorldInitService)
function RedZoneService:InitializeZones()
	if self._isInitialized then
		--("[RedZoneService] Already initialized, skipping...")
		return true
	end
	
	if not CONFIG.Enabled then
		--("[RedZoneService] Red zone creation disabled")
		return true
	end
	
	--("[RedZoneService] Initializing zones (called by WorldInitService)...")
	
	createAllRedZones()
	
	self._isInitialized = true
	--("[RedZoneService] Zone initialization complete")
	return true
end

-- === PUBLIC API ===

function RedZoneService:GetZones()
	return self._zones
end

function RedZoneService:GetZoneCount()
	return #self._zones
end

function RedZoneService:GetZoneParts()
	return self._zoneParts
end

function RedZoneService:CreateZones()
	createAllRedZones()
end

function RedZoneService:SetEnabled(enabled)
	CONFIG.Enabled = enabled
	--("[RedZoneService] Red zone creation", enabled and "enabled" or "disabled")
end

function RedZoneService:SetZoneTransparency(transparency)
	CONFIG.ZoneTransparency = transparency
	-- Update existing zones
	for _, zoneData in ipairs(self._zones) do
		if zoneData.part then
			zoneData.part.Transparency = transparency
		end
	end
	--[[print(string.format("[RedZoneService] Zone transparency set to %.2f", transparency))]]
end

function RedZoneService:SetZoneColor(color)
	CONFIG.ZoneColor = color
	-- Update existing zones
	for _, zoneData in ipairs(self._zones) do
		if zoneData.part then
			zoneData.part.BrickColor = BrickColor.new(color)
		end
	end
	--[[print(string.format("[RedZoneService] Zone color set to %s", tostring(color)))]]
end

return RedZoneService

