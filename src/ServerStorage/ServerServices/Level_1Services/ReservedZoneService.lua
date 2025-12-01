--[[
	ReservedZoneService
	Manages different types of zones: Building zones and Radiation zones
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local CustomPackages = ReplicatedStorage:WaitForChild("CustomPackages")
local Knit = require(Packages.Knit)

-- Zone+ Module
local ZoneRoot = CustomPackages:WaitForChild("ZoneRoot")
local Zone = require(ZoneRoot:WaitForChild("Zone"))

local ReservedZoneService = Knit.CreateService {
	Name = "ReservedZoneService",
	Client = {},
	_gridService = nil,
	_zones = {},  -- Track all zones by type: { [zoneType] = { cells = {}, zoneCube = Part, zone = Zone } }
}

-- === ZONE TYPE DEFINITIONS ===
local ZONE_TYPES = {
	Building = {
		name = "Building",
		cellTransparency = 1.0,  -- Fully transparent cells
		zoneCubeTransparency = 0.7,
		zoneCubeColor = Color3.fromRGB(255, 255, 0),  -- Yellow
		flattenTerrain = true,
	},
	Radiation = {
		name = "Radiation",
		cellTransparency = 1.0,  -- Fully transparent cells
		zoneCubeTransparency = 0.7,
		zoneCubeColor = Color3.fromRGB(128, 0, 128),  -- Purple
		flattenTerrain = false,
	},
}

-- === CONFIG ===
local ZONE_CONFIG = {
	BuildingZoneSizeX = 2,      -- Width of building zone (cells)
	BuildingZoneSizeZ = 2,      -- Depth of building zone (cells)
	RadiationZoneSizeX = 2,     -- Width of radiation zone (cells)
	RadiationZoneSizeZ = 2,     -- Depth of radiation zone (cells)
	OwnerId = "ReservedZoneService",
}

-- === TERRAIN FLATTENING ===

-- Flatten terrain under the reserved area
local function flattenTerrainUnderReservedArea(self, cellPositions, zoneType)
	if not ZONE_TYPES[zoneType] or not ZONE_TYPES[zoneType].flattenTerrain then
		return  -- Don't flatten if zone type doesn't require it
	end
	if not cellPositions or #cellPositions == 0 then
		return
	end
	
	-- Get TerrainService
	local TerrainService = nil
	pcall(function()
		TerrainService = Knit.GetService("TerrainService")
	end)
	
	if not TerrainService then
		warn("[ReservedZoneService] TerrainService not found, cannot flatten terrain")
		return
	end
	
	if not self._gridService then
		warn("[ReservedZoneService] GridService not available, cannot calculate area size")
		return
	end
	
	-- Calculate the bounds of the reserved area
	local minX, maxX = math.huge, -math.huge
	local minZ, maxZ = math.huge, -math.huge
	local avgY = 0
	
	for _, pos in ipairs(cellPositions) do
		minX = math.min(minX, pos.X)
		maxX = math.max(maxX, pos.X)
		minZ = math.min(minZ, pos.Z)
		maxZ = math.max(maxZ, pos.Z)
		avgY = avgY + pos.Y
	end
	avgY = avgY / #cellPositions
	
	-- Calculate center and size of the reserved area
	local centerX = (minX + maxX) / 2
	local centerZ = (minZ + maxZ) / 2
	local cellSize = self._gridService:GetCellSize()
	local sizeX = maxX - minX + cellSize
	local sizeZ = maxZ - minZ + cellSize
	
	-- Get the desired height (use baseplate top or a default height)
	local baseplate = Workspace:FindFirstChild("Baseplate")
	local flatHeight = avgY
	if baseplate and baseplate:IsA("BasePart") then
		flatHeight = baseplate.Position.Y + baseplate.Size.Y / 2
	end
	
	local centerPos = Vector3.new(centerX, flatHeight, centerZ)
	local areaSize = Vector3.new(sizeX, 10, sizeZ)  -- Height of 10 for the flat area
	
	-- Flatten the terrain
	print(string.format("[ReservedZoneService] Flattening terrain at (%.1f, %.1f, %.1f) size (%.1f, %.1f, %.1f)", 
		centerPos.X, centerPos.Y, centerPos.Z, areaSize.X, areaSize.Y, areaSize.Z))
	
	TerrainService:CreateFlatArea(centerPos, areaSize, flatHeight)
	
	-- Remove grass by replacing it with a non-grass material (Rock/Concrete)
	-- Create a region that covers the flat area
	local region = Region3.new(
		Vector3.new(centerPos.X - areaSize.X/2, flatHeight - 5, centerPos.Z - areaSize.Z/2),
		Vector3.new(centerPos.X + areaSize.X/2, flatHeight + 2, centerPos.Z + areaSize.Z/2)
	)
	
	-- Replace grass with concrete/rock to remove grass appearance
	local Workspace = game:GetService("Workspace")
	local Terrain = Workspace.Terrain
	local resolution = 4  -- Standard terrain resolution
	
	-- Replace Grass with Concrete (or Rock) to remove grass
	pcall(function()
		Terrain:ReplaceMaterial(region, resolution, Enum.Material.Grass, Enum.Material.Concrete)
		print("[ReservedZoneService] Replaced grass with concrete in reserved area")
	end)
	
	print("[ReservedZoneService] Terrain flattened and grass removed under reserved area")
end

-- Create a zone for a specific zone type
local function createZone(self, zoneType, cells, sizeX, sizeZ)
	if not self._gridService then
		return
	end
	
	if not ZONE_TYPES[zoneType] then
		warn(string.format("[ReservedZoneService] Invalid zone type: %s", tostring(zoneType)))
		return
	end
	
	if not cells or #cells == 0 then
		warn(string.format("[ReservedZoneService] No cells provided for %s zone", zoneType))
		return
	end
	
	local zoneTypeData = ZONE_TYPES[zoneType]
	
	-- Clear any existing zone of this type
	if self._zones[zoneType] then
		local existingZone = self._zones[zoneType]
		if existingZone.zone and existingZone.zone.Destroy then
			existingZone.zone:Destroy()
		end
		if existingZone.zoneCube then
			existingZone.zoneCube:Destroy()
		end
	end
	
	-- Calculate the center position and size
	local cellSize = self._gridService:GetCellSize()
	
	-- Calculate center position and boundaries from the cells
	local minX, maxX = math.huge, -math.huge
	local minZ, maxZ = math.huge, -math.huge
	
	for _, cell in ipairs(cells) do
		local worldPos = self._gridService:GridToWorld(cell.x, cell.z)
		minX = math.min(minX, worldPos.X)
		maxX = math.max(maxX, worldPos.X)
		minZ = math.min(minZ, worldPos.Z)
		maxZ = math.max(maxZ, worldPos.Z)
	end
	
	-- Calculate total size to cover all cells
	local totalSizeX = (maxX - minX) + cellSize
	local totalSizeZ = (maxZ - minZ) + cellSize
	
	-- Center position
	local centerX = (minX + maxX) / 2
	local centerZ = (minZ + maxZ) / 2
	-- Match grid cube height: grid cubes are positioned at topY + cellSize/2
	local centerY = self._gridService._gridData.topY + (cellSize / 2)
	
	-- Create a cube part covering the entire area
	local cube = Instance.new("Part")
	cube.Name = string.format("%sZoneCube", zoneType)
	cube.Size = Vector3.new(totalSizeX, cellSize, totalSizeZ)
	cube.Position = Vector3.new(centerX, centerY, centerZ)
	cube.Transparency = zoneTypeData.zoneCubeTransparency
	cube.Color = zoneTypeData.zoneCubeColor
	cube.CanCollide = false
	cube.Anchored = true
	cube.Parent = workspace
	
	-- Create Zone+ zone on the cube
	local success, zoneInstance = pcall(function()
		return Zone.new(cube)
	end)
	
	if not success then
		warn(string.format("[ReservedZoneService] Failed to create %s zone: %s", zoneType, tostring(zoneInstance)))
		return
	end
	
	-- Event handlers for the zone
	zoneInstance.playerEntered:Connect(function(player)
		local character = player.Character
		local position = character and character:FindFirstChild("HumanoidRootPart") and 
			character.HumanoidRootPart.Position or Vector3.zero
		
		print(string.format(
			"[ReservedZoneService] >>> Player '%s' (UserId: %d) ENTERED %s zone at position (%.1f, %.1f, %.1f)",
			player.Name, player.UserId, zoneType, position.X, position.Y, position.Z
		))
	end)
	
	zoneInstance.playerExited:Connect(function(player)
		local character = player.Character
		local position = character and character:FindFirstChild("HumanoidRootPart") and 
			character.HumanoidRootPart.Position or Vector3.zero
		
		print(string.format(
			"[ReservedZoneService] <<< Player '%s' (UserId: %d) EXITED %s zone at position (%.1f, %.1f, %.1f)",
			player.Name, player.UserId, zoneType, position.X, position.Y, position.Z
		))
	end)
	
	-- Store zone data
	self._zones[zoneType] = {
		cells = cells,
		zoneCube = cube,
		zone = zoneInstance,
	}
	
	print(string.format("[ReservedZoneService] ✓ Created %s zone (%.1f x %.1f x %.1f studs) covering %d cells", 
		zoneType, totalSizeX, cellSize, totalSizeZ, #cells))
end

-- Helper function to create a zone of a specific type
local function createZoneOfType(self, zoneType, sizeX, sizeZ, LoadingService, reportProgress)
	if not ZONE_TYPES[zoneType] then
		warn(string.format("[ReservedZoneService] Invalid zone type: %s", tostring(zoneType)))
		return
	end
	
	-- Get grid dimensions
	local gridWidth, gridDepth = self._gridService:GetGridDimensions()
	
	if not gridWidth or not gridDepth then
		warn("[ReservedZoneService] Could not get grid dimensions")
		return
	end
	
	-- Find a valid block of cells
	local startX, startZ = nil, nil
	local attempts = 0
	local maxAttempts = 100
	
	-- Valid starting positions for the block
	local maxStartX = gridWidth - sizeX + 1
	local maxStartZ = gridDepth - sizeZ + 1
	
	while attempts < maxAttempts do
		attempts += 1
		
		-- Random starting cell for the block
		local testX = math.random(1, maxStartX)
		local testZ = math.random(1, maxStartZ)
		
		-- Check if all cells in the block are available
		local allCellsValid = true
		for dx = 0, sizeX - 1 do
			for dz = 0, sizeZ - 1 do
				local checkX = testX + dx
				local checkZ = testZ + dz
				
				-- Check if cell is valid and not occupied
				if not self._gridService:IsValidCell(checkX, checkZ) or 
				   self._gridService:IsCellOccupied(checkX, checkZ) then
					allCellsValid = false
					break
				end
			end
			if not allCellsValid then break end
		end
		
		if allCellsValid then
			startX = testX
			startZ = testZ
			break
		end
	end
	
	if not startX or not startZ then
		warn(string.format("[ReservedZoneService] Could not find valid %dx%d block for %s zone after %d attempts", 
			sizeX, sizeZ, zoneType, maxAttempts))
		return
	end
	
	print(string.format("[ReservedZoneService] Selected %dx%d block starting at (%d,%d) for %s zone", 
		sizeX, sizeZ, startX, startZ, zoneType))
	
	local zoneTypeData = ZONE_TYPES[zoneType]
	local cells = {}
	local cellPositions = {}  -- Store cell positions for terrain flattening
	local totalCells = sizeX * sizeZ
	local cellIndex = 0
	
	-- Reserve all cells in the block
	for dx = 0, sizeX - 1 do
		for dz = 0, sizeZ - 1 do
			local cellX = startX + dx
			local cellZ = startZ + dz
			cellIndex += 1
			
			-- Mark cell as occupied
			if self._gridService.SetCellOccupied then
				self._gridService:SetCellOccupied(cellX, cellZ, ZONE_CONFIG.OwnerId)
			end
			
			-- Get the cell data and modify the cube
			local cellData = self._gridService:GetCell(cellX, cellZ)
			if cellData and cellData.cube then
				cellData.cube.Transparency = zoneTypeData.cellTransparency
				-- Color doesn't matter when fully transparent, but set it anyway
				print(string.format("[ReservedZoneService] Reserved cell (%d,%d) for %s zone", 
					cellX, cellZ, zoneType))
			else
				warn(string.format("[ReservedZoneService] Could not find cube for cell (%d,%d)", cellX, cellZ))
			end
			
			-- Store cell position for terrain flattening (if needed)
			local cellPos = self._gridService:GridToWorld(cellX, cellZ)
			table.insert(cellPositions, cellPos)
			
			-- Store reserved cell
			table.insert(cells, {x = cellX, z = cellZ})
			
			if reportProgress then
				local progress = 10 + (cellIndex / totalCells) * 60
				reportProgress(string.format("Reserving %s zone (%d/%d)...", zoneType, cellIndex, totalCells), progress)
			end
		end
	end
	
	-- Wait a moment for GridService zones to be fully initialized
	task.wait(0.5)
	
	-- Create the zone
	if reportProgress then
		reportProgress(string.format("Creating %s zone...", zoneType), 75)
	end
	createZone(self, zoneType, cells, sizeX, sizeZ)
	
	-- Flatten terrain if needed
	if zoneTypeData.flattenTerrain then
		if reportProgress then
			reportProgress(string.format("Flattening terrain for %s zone...", zoneType), 85)
		end
		flattenTerrainUnderReservedArea(self, cellPositions, zoneType)
	end
	
	if reportProgress then
		reportProgress(string.format("%s zone created", zoneType), 100)
	end
end

-- Main function to create all zones
local function proceedWithReservation(self, LoadingService, reportProgress)
	-- Create building zone
	createZoneOfType(self, "Building", ZONE_CONFIG.BuildingZoneSizeX, ZONE_CONFIG.BuildingZoneSizeZ, 
		LoadingService, function(msg, progress)
			if reportProgress then
				reportProgress(msg, progress * 0.5)  -- Building zone takes first 50%
			end
		end)
	
	-- Create radiation zone
	createZoneOfType(self, "Radiation", ZONE_CONFIG.RadiationZoneSizeX, ZONE_CONFIG.RadiationZoneSizeZ, 
		LoadingService, function(msg, progress)
			if reportProgress then
				reportProgress(msg, 50 + progress * 0.5)  -- Radiation zone takes second 50%
			end
		end)
	
	-- Mark step complete
	if LoadingService then
		LoadingService:MarkStepComplete("ReservedZoneService")
	end
	
	print("[ReservedZoneService] All zones created")
end

-- === KNIT LIFECYCLE ===

function ReservedZoneService:KnitInit()
	print("[ReservedZoneService] Initializing...")
	
	-- Get GridService reference
	pcall(function()
		self._gridService = Knit.GetService("GridService")
	end)
end

function ReservedZoneService:KnitStart()
	-- Get LoadingService for progress updates
	local LoadingService = nil
	pcall(function()
		LoadingService = Knit.GetService("LoadingService")
	end)
	
	local function reportProgress(message, progress)
		if LoadingService then
			LoadingService:UpdateStatus("ReservedZoneService", message, progress or 0)
		end
	end
	
	if not self._gridService then
		warn("[ReservedZoneService] GridService not found!")
		return
	end
	
	-- Wait for TerrainService to complete before flattening
	if LoadingService then
		print("[ReservedZoneService] Waiting for TerrainService to complete...")
		LoadingService:OnStepComplete("TerrainService", function()
			print("[ReservedZoneService] TerrainService complete, proceeding with reservation...")
			proceedWithReservation(self, LoadingService, reportProgress)
		end)
	else
		-- Fallback if LoadingService not available
		task.wait(2)  -- Give terrain time to generate
		proceedWithReservation(self, LoadingService, reportProgress)
	end
end

-- === PUBLIC API ===

function ReservedZoneService:GetZones()
	return self._zones
end

function ReservedZoneService:GetZone(zoneType)
	return self._zones[zoneType]
end

function ReservedZoneService:GetZoneCells(zoneType)
	local zoneData = self._zones[zoneType]
	return zoneData and zoneData.cells or {}
end

function ReservedZoneService:IsCellInZone(x, z, zoneType)
	local cells = self:GetZoneCells(zoneType)
	for _, cell in ipairs(cells) do
		if cell.x == x and cell.z == z then
			return true
		end
	end
	return false
end

function ReservedZoneService:IsCellReserved(x, z)
	-- Check if cell is in any zone
	for zoneType, _ in pairs(self._zones) do
		if self:IsCellInZone(x, z, zoneType) then
			return true
		end
	end
	return false
end

function ReservedZoneService:ClearZone(zoneType)
	local zoneData = self._zones[zoneType]
	if not zoneData then
		return
	end
	
	-- Destroy zone
	if zoneData.zone and zoneData.zone.Destroy then
		zoneData.zone:Destroy()
	end
	
	-- Destroy zone cube
	if zoneData.zoneCube then
		zoneData.zoneCube:Destroy()
	end
	
	-- Clear cell occupancy and reset transparency
	for _, cell in ipairs(zoneData.cells) do
		if self._gridService and self._gridService.ClearCellOccupancy then
			self._gridService:ClearCellOccupancy(cell.x, cell.z)
		end
		
		-- Reset cube transparency and color (checkerboard pattern)
		local cellData = self._gridService:GetCell(cell.x, cell.z)
		if cellData and cellData.cube then
			cellData.cube.Transparency = 0
			-- Reset to original checkerboard color
			if (cell.x + cell.z) % 2 == 0 then
				cellData.cube.Color = Color3.fromRGB(66, 135, 245)  -- Blue
			else
				cellData.cube.Color = Color3.fromRGB(245, 166, 66)  -- Orange
			end
		end
	end
	
	self._zones[zoneType] = nil
	print(string.format("[ReservedZoneService] Cleared %s zone", zoneType))
end

function ReservedZoneService:ClearAllZones()
	for zoneType, _ in pairs(self._zones) do
		self:ClearZone(zoneType)
	end
	print("[ReservedZoneService] Cleared all zones")
end

return ReservedZoneService

