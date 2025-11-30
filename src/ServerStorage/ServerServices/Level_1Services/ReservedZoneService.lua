--[[
	ReservedZoneService
	Selects random grid cells and marks them as reserved, making them semi-transparent
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local Knit = require(Packages.Knit)

local ReservedZoneService = Knit.CreateService {
	Name = "ReservedZoneService",
	Client = {},
	_gridService = nil,
	_reservedCells = {},  -- Track which cells we've reserved
}

-- === CONFIG ===
local RESERVED_CONFIG = {
	BlockSizeX = 2,             -- Width of reserved block (cells)
	BlockSizeZ = 2,             -- Depth of reserved block (cells)
	Transparency = 0.5,         -- Transparency for reserved cell cubes
	OwnerId = "ReservedZoneService",  -- Owner identifier for reserved cells
}

-- === TERRAIN FLATTENING ===

-- Flatten terrain under the reserved area
local function flattenTerrainUnderReservedArea(self, cellPositions)
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

-- Separate function to handle the actual reservation process
local function proceedWithReservation(self, LoadingService, reportProgress)
	
	-- Get grid dimensions
	local gridWidth, gridDepth = self._gridService:GetGridDimensions()
	
	if not gridWidth or not gridDepth then
		warn("[ReservedZoneService] Could not get grid dimensions")
		return
	end
	
	print(string.format("[ReservedZoneService] Grid size: %dx%d", gridWidth, gridDepth))
	
	-- Find a valid 2x2 block of cells
	local startX, startZ = nil, nil
	local attempts = 0
	local maxAttempts = 100
	
	-- Valid starting positions for a 2x2 block
	local maxStartX = gridWidth - RESERVED_CONFIG.BlockSizeX + 1
	local maxStartZ = gridDepth - RESERVED_CONFIG.BlockSizeZ + 1
	
	while attempts < maxAttempts do
		attempts += 1
		
		-- Random starting cell for the 2x2 block
		local testX = math.random(1, maxStartX)
		local testZ = math.random(1, maxStartZ)
		
		-- Check if all 4 cells in the 2x2 block are available
		local allCellsValid = true
		for dx = 0, RESERVED_CONFIG.BlockSizeX - 1 do
			for dz = 0, RESERVED_CONFIG.BlockSizeZ - 1 do
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
		warn(string.format("[ReservedZoneService] Could not find valid 2x2 block after %d attempts", maxAttempts))
		return
	end
	
	print(string.format("[ReservedZoneService] Selected 2x2 block starting at (%d,%d)", startX, startZ))
	
	-- Reserve all cells in the 2x2 block
	local cellIndex = 0
	local totalCells = RESERVED_CONFIG.BlockSizeX * RESERVED_CONFIG.BlockSizeZ
	local cellPositions = {}  -- Store cell positions for terrain flattening
	
	for dx = 0, RESERVED_CONFIG.BlockSizeX - 1 do
		for dz = 0, RESERVED_CONFIG.BlockSizeZ - 1 do
			local cellX = startX + dx
			local cellZ = startZ + dz
			cellIndex += 1
			
			-- Mark cell as occupied
			if self._gridService.SetCellOccupied then
				self._gridService:SetCellOccupied(cellX, cellZ, RESERVED_CONFIG.OwnerId)
			end
			
			-- Get the cell data and modify the cube
			local cellData = self._gridService:GetCell(cellX, cellZ)
			if cellData and cellData.cube then
				cellData.cube.Transparency = RESERVED_CONFIG.Transparency
				print(string.format("[ReservedZoneService] Reserved cell (%d,%d) - cube transparency set to %.1f", 
					cellX, cellZ, RESERVED_CONFIG.Transparency))
			else
				warn(string.format("[ReservedZoneService] Could not find cube for cell (%d,%d)", cellX, cellZ))
			end
			
			-- Store cell position for terrain flattening
			local cellPos = self._gridService:GridToWorld(cellX, cellZ)
			table.insert(cellPositions, cellPos)
			
			-- Store reserved cell
			table.insert(self._reservedCells, {x = cellX, z = cellZ})
			
			local progress = 10 + (cellIndex / totalCells) * 70
			reportProgress(string.format("Reserving zones (%d/%d)...", cellIndex, totalCells), progress)
		end
	end
	
	-- Flatten terrain under the reserved area
	reportProgress("Flattening terrain...", 80)
	flattenTerrainUnderReservedArea(self, cellPositions)
	
	reportProgress("Zones reserved", 100)
	
	-- Mark step complete
	if LoadingService then
		LoadingService:MarkStepComplete("ReservedZoneService")
	end
	
	print(string.format("[ReservedZoneService] Reserved %d cells", #self._reservedCells))
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

function ReservedZoneService:GetReservedCells()
	return self._reservedCells
end

function ReservedZoneService:IsCellReserved(x, z)
	for _, cell in ipairs(self._reservedCells) do
		if cell.x == x and cell.z == z then
			return true
		end
	end
	return false
end

function ReservedZoneService:ClearReservedCells()
	for _, cell in ipairs(self._reservedCells) do
		if self._gridService and self._gridService.ClearCellOccupancy then
			self._gridService:ClearCellOccupancy(cell.x, cell.z)
		end
		
		-- Reset cube transparency
		local cellData = self._gridService:GetCell(cell.x, cell.z)
		if cellData and cellData.cube then
			cellData.cube.Transparency = 0
		end
	end
	
	self._reservedCells = {}
	print("[ReservedZoneService] Cleared all reserved cells")
end

return ReservedZoneService

