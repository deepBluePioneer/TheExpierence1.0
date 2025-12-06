--[[
	WorldInitService
	
	Central orchestrator that controls world generation in the correct order:
	
	1. Create baseplate grid
	2. Create GridService grid of parts for each baseplate
	3. Reserve cells (exclusion zones, building zones, etc.)
	4. Generate terrain
	5. Generate trees and formations
	6. Remove baseplates
	
	This service ensures all other services initialize in the correct sequence.
]]
--tes
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local Knit = require(Packages.Knit)

local WorldInitService = Knit.CreateService {
	Name = "WorldInitService",
	Client = {},
	
	-- State tracking
	_initPhase = "not_started",
	_baseplates = nil,
	_baseplateFolder = nil,
	_baseplateInfo = nil,
	
	-- Service references
	_loadingService = nil,
	_cubeTerrainService = nil,
	_gridService = nil,
	_reservedZoneService = nil,
	_redZoneService = nil,
	_treeService = nil,
	_formationService = nil,
}

-- === CONFIG ===
local CONFIG = {
	-- Baseplate grid settings
	BaseplateGridSize = 3,       -- 5x5 grid of baseplates
	BaseplateSize = Vector3.new(128, 1, 128),
	BaseplateThickness = 1,
	BaseHeight = 0,
	
	-- Grid settings
	CellsPerBaseplate = 16,      -- 16x16 cells per baseplate
	
	-- Generation delays (for visual feedback)
	PhaseDelayMs = 100,          -- Delay between phases
}

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         PHASE 1: BASEPLATE GRID                            ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

local function createBaseplateGrid(self, centerX, centerZ)
	--("[WorldInitService] Phase 1: Creating baseplate grid...")
	self._initPhase = "creating_baseplates"
	
	local baseplates = {}
	local gridSize = CONFIG.BaseplateGridSize
	local baseplateSize = CONFIG.BaseplateSize
	local spacing = baseplateSize.X
	
	local totalWidth = gridSize * spacing
	local totalDepth = gridSize * spacing
	local startX = centerX - (totalWidth / 2) + (spacing / 2)
	local startZ = centerZ - (totalDepth / 2) + (spacing / 2)
	
	-- Create folder for baseplates
	local baseplateFolder = Workspace:FindFirstChild("WorldBaseplates")
	if baseplateFolder then
		baseplateFolder:ClearAllChildren()
	else
		baseplateFolder = Instance.new("Folder")
		baseplateFolder.Name = "WorldBaseplates"
		baseplateFolder.Parent = Workspace
	end
	
	self._baseplateFolder = baseplateFolder
	
	-- Create each baseplate
	for x = 1, gridSize do
		baseplates[x] = {}
		for z = 1, gridSize do
			local positionX = startX + (x - 1) * spacing
			local positionZ = startZ + (z - 1) * spacing
			local positionY = CONFIG.BaseHeight + (baseplateSize.Y / 2)
			
			local baseplate = Instance.new("Part")
			baseplate.Name = string.format("WorldBaseplate_%d_%d", x, z)
			baseplate.Size = baseplateSize
			baseplate.Position = Vector3.new(positionX, positionY, positionZ)
			baseplate.Anchored = true
			baseplate.CanCollide = false
			baseplate.Transparency = 0.8
			baseplate.BrickColor = BrickColor.new("Bright green")
			baseplate.Material = Enum.Material.Plastic
			baseplate.Parent = baseplateFolder
			
			baseplates[x][z] = baseplate
		end
	end
	
	self._baseplates = baseplates
	
	-- Calculate combined baseplate info
	local firstBaseplate = baseplates[1][1]
	local lastBaseplate = baseplates[gridSize][gridSize]
	
	local gridCenterX = (firstBaseplate.Position.X + lastBaseplate.Position.X) / 2
	local gridCenterZ = (firstBaseplate.Position.Z + lastBaseplate.Position.Z) / 2
	local topY = firstBaseplate.Position.Y + (baseplateSize.Y / 2)
	
	self._baseplateInfo = {
		position = Vector3.new(gridCenterX, topY, gridCenterZ),
		size = Vector3.new(totalWidth, baseplateSize.Y, totalDepth),
		topY = topY,
		gridSize = gridSize,
		baseplateSize = baseplateSize,
		baseplates = baseplates,
	}
	
	--[[print(string.format("[WorldInitService] Created %dx%d baseplate grid (%.0f x %.0f studs)", 
		gridSize, gridSize, totalWidth, totalDepth))]]
	
	return baseplates, self._baseplateInfo
end

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         PHASE 2: GRID SERVICE                              ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

local function initializeGridService(self)
	--("[WorldInitService] Phase 2: Initializing GridService with baseplates...")
	self._initPhase = "creating_grid"
	
	if not self._gridService then
		warn("[WorldInitService] GridService not available!")
		return false
	end
	
	if not self._baseplateInfo then
		warn("[WorldInitService] No baseplate info available!")
		return false
	end
	
	-- Pass baseplate info to GridService and trigger grid creation
	self._gridService:InitializeWithBaseplates(self._baseplateInfo)
	
	--("[WorldInitService] GridService initialized with baseplates")
	return true
end

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                      PHASE 3: GENERATE TERRAIN                             ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

local function generateTerrain(self)
	--("[WorldInitService] Phase 3: Generating cube terrain...")
	self._initPhase = "generating_terrain"
	
	if not self._baseplateInfo then
		warn("[WorldInitService] No baseplate info available!")
		return false
	end
	
	-- Generate cube-based terrain using CubeTerrainService
	if self._cubeTerrainService then
		--("[WorldInitService] Generating cube terrain via CubeTerrainService")
		local width, depth = 20, 20
		local cellSize = 8
		
		if self._gridService then
			width, depth = self._gridService:GetGridDimensions()
			cellSize = self._gridService:GetCellSize()
		end
		
		self._cubeTerrainService:GenerateTerrain(
			width,
			depth,
			cellSize,
			self._baseplateInfo.position.X,
			self._baseplateInfo.position.Z,
			self._baseplateInfo.topY
		)
		
		--("[WorldInitService] Cube terrain generation complete")
		return true
	else
		warn("[WorldInitService] CubeTerrainService not available!")
		return false
	end
end

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                      PHASE 4: RESERVE CELLS                                ║
-- ╚════════════════════════════════════════════════════════════════════════════╝
-- NOTE: Reserve cells AFTER terrain so flattening works properly!

local function reserveCells(self)
	--("[WorldInitService] Phase 4: Reserving cells (after terrain for flattening)...")
	self._initPhase = "reserving_cells"
	
	-- Initialize ReservedZoneService (will flatten terrain under Building zones)
	if self._reservedZoneService then
		self._reservedZoneService:InitializeZones()
		--("[WorldInitService] Reserved zones created and terrain flattened")
	end
	
	-- Initialize RedZoneService
	if self._redZoneService then
		self._redZoneService:InitializeZones()
		--("[WorldInitService] Red zones created")
	end
	
	return true
end

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                  PHASE 5: GENERATE TREES & FORMATIONS                      ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

local function generateVegetation(self)
	--("[WorldInitService] Phase 5: Generating trees and formations...")
	self._initPhase = "generating_vegetation"
	
	-- Generate trees
	if self._treeService then
		--("[WorldInitService] Generating trees...")
		self._treeService:GenerateTreesWithBaseplates(self._baseplateInfo)
	end
	
	-- Generate formations
	if self._formationService then
		--("[WorldInitService] Generating formations...")
		self._formationService:GenerateFormationsWithBaseplates(self._baseplateInfo)
	end
	
	--("[WorldInitService] Vegetation generation complete")
	return true
end

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                      PHASE 6: REMOVE BASEPLATES                            ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

local function removeBaseplates(self)
	--("[WorldInitService] Phase 6: Removing baseplates...")
	self._initPhase = "removing_baseplates"
	
	-- Remove the WorldBaseplates folder we created
	if self._baseplateFolder then
		self._baseplateFolder:Destroy()
		self._baseplateFolder = nil
		--("[WorldInitService] WorldBaseplates folder removed")
	end
	
	-- Also check for WorldBaseplates folder in case reference was lost
	local worldBaseplates = Workspace:FindFirstChild("WorldBaseplates")
	if worldBaseplates then
		worldBaseplates:Destroy()
		--("[WorldInitService] Found and removed WorldBaseplates folder")
	end
	
	-- Remove ANY baseplate parts in workspace (including default spawn plate)
	local baseplatesToRemove = {}
	
	-- Find all parts named "Baseplate" or containing "baseplate" 
	for _, child in ipairs(Workspace:GetChildren()) do
		if child:IsA("BasePart") then
			local nameLower = child.Name:lower()
			if nameLower == "baseplate" or nameLower:find("baseplate") then
				table.insert(baseplatesToRemove, child)
			end
		end
	end
	
	-- Remove all found baseplates
	for _, baseplate in ipairs(baseplatesToRemove) do
		--("[WorldInitService] Removing baseplate:", baseplate.Name)
		baseplate:Destroy()
	end
	
	if #baseplatesToRemove > 0 then
		--[[print(string.format("[WorldInitService] Removed %d baseplate(s) from workspace", #baseplatesToRemove))]]
	end
	
	-- Also remove TerrainBaseplates folder if it exists (from old TerrainService)
	local terrainBaseplates = Workspace:FindFirstChild("TerrainBaseplates")
	if terrainBaseplates then
		terrainBaseplates:Destroy()
		--("[WorldInitService] Removed TerrainBaseplates folder")
	end
	
	self._initPhase = "complete"
	return true
end

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                      MAIN INITIALIZATION SEQUENCE                          ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

local function runInitializationSequence(self)
	local startTime = tick()
	--("[WorldInitService] ========== STARTING WORLD INITIALIZATION ==========")
	
	local function reportProgress(phase, progress, message)
		if self._loadingService then
			self._loadingService:UpdateStatus("WorldInitService", message, progress)
		end
		--[[print(string.format("[WorldInitService] [%s] %s", phase, message))]]
	end
	
	-- ===== PHASE 1: Create Baseplate Grid =====
	reportProgress("Phase 1", 0.05, "Creating baseplate grid...")
	createBaseplateGrid(self, 0, 0)  -- Centered at origin
	task.wait(CONFIG.PhaseDelayMs / 1000)
	
	-- ===== PHASE 2: Initialize Grid Service =====
	reportProgress("Phase 2", 0.15, "Creating world grid...")
	initializeGridService(self)
	task.wait(CONFIG.PhaseDelayMs / 1000)
	
	-- Wait for grid to be fully created
	while self._gridService and not self._gridService:IsGridReady() do
		task.wait(0.1)
	end
	
	if self._loadingService then
		self._loadingService:MarkStepComplete("GridService")
	end
	
	-- ===== PHASE 3: Generate Cube Terrain =====
	reportProgress("Phase 3", 0.25, "Generating cube terrain...")
	generateTerrain(self)
	task.wait(CONFIG.PhaseDelayMs / 1000)
	
	if self._loadingService then
		self._loadingService:MarkStepComplete("CubeTerrainService")
	end
	
	-- ===== PHASE 4: Reserve Cells (AFTER terrain so flattening works) =====
	reportProgress("Phase 4", 0.45, "Reserving zones and flattening terrain...")
	reserveCells(self)
	task.wait(CONFIG.PhaseDelayMs / 1000)
	
	if self._loadingService then
		self._loadingService:MarkStepComplete("ReservedZoneService")
		self._loadingService:MarkStepComplete("RedZoneService")
	end
	
	-- ===== PHASE 5: Generate Vegetation =====
	reportProgress("Phase 5", 0.70, "Growing alien forest...")
	generateVegetation(self)
	task.wait(CONFIG.PhaseDelayMs / 1000)
	
	if self._loadingService then
		self._loadingService:MarkStepComplete("TreeService")
		self._loadingService:MarkStepComplete("FormationService")
	end
	
	-- ===== PHASE 6: Remove Baseplates =====
	reportProgress("Phase 6", 0.95, "Finalizing world...")
	removeBaseplates(self)
	
	-- ===== COMPLETE =====
	local elapsed = tick() - startTime
	--[[print(string.format("[WorldInitService] ========== WORLD INITIALIZATION COMPLETE (%.2fs) ==========", elapsed))]]
	
	if self._loadingService then
		self._loadingService:MarkStepComplete("WorldInitService")
	end
	
	return true
end

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                           KNIT LIFECYCLE                                   ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

function WorldInitService:KnitInit()
	--("[WorldInitService] Initializing - World generation orchestrator")
	
	-- Get service references (they may not all be available yet)
	pcall(function() self._loadingService = Knit.GetService("LoadingService") end)
	pcall(function() self._cubeTerrainService = Knit.GetService("CubeTerrainService") end)
	pcall(function() self._gridService = Knit.GetService("GridService") end)
	pcall(function() self._reservedZoneService = Knit.GetService("ReservedZoneService") end)
	pcall(function() self._redZoneService = Knit.GetService("RedZoneService") end)
	pcall(function() self._treeService = Knit.GetService("TreeService") end)
	pcall(function() self._formationService = Knit.GetService("FormationService") end)
end

function WorldInitService:KnitStart()
	--("[WorldInitService] Starting world generation sequence...")
	
	-- Run the initialization sequence
	task.spawn(function()
		-- Small delay to ensure all services are ready
		task.wait(0.5)
		
		local success, err = pcall(function()
			runInitializationSequence(self)
		end)
		
		if not success then
			warn("[WorldInitService] Initialization failed:", err)
		end
	end)
end

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                            PUBLIC API                                      ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

function WorldInitService:GetBaseplateInfo()
	return self._baseplateInfo
end

-- Get individual baseplate positions (for RedZoneService, etc.)
function WorldInitService:GetBaseplatePositions()
	local positions = {}
	
	if not self._baseplateInfo then
		return positions
	end
	
	local gridSize = self._baseplateInfo.gridSize or CONFIG.BaseplateGridSize
	local baseplateSize = self._baseplateInfo.baseplateSize or CONFIG.BaseplateSize
	local spacing = baseplateSize.X
	
	local totalWidth = gridSize * spacing
	local totalDepth = gridSize * spacing
	local centerX = self._baseplateInfo.position.X
	local centerZ = self._baseplateInfo.position.Z
	local topY = self._baseplateInfo.topY or CONFIG.BaseHeight
	
	local startX = centerX - (totalWidth / 2) + (spacing / 2)
	local startZ = centerZ - (totalDepth / 2) + (spacing / 2)
	
	-- Generate position info for each baseplate in the grid
	for x = 1, gridSize do
		for z = 1, gridSize do
			local positionX = startX + (x - 1) * spacing
			local positionZ = startZ + (z - 1) * spacing
			
			table.insert(positions, {
				centerX = positionX,
				centerZ = positionZ,
				centerY = topY,
				size = baseplateSize,
				gridX = x,
				gridZ = z,
			})
		end
	end
	
	return positions
end

function WorldInitService:GetInitPhase()
	return self._initPhase
end

function WorldInitService:IsInitComplete()
	return self._initPhase == "complete"
end

function WorldInitService:GetConfig()
	return CONFIG
end

function WorldInitService:SetConfig(key, value)
	if CONFIG[key] ~= nil then
		CONFIG[key] = value
		--("[WorldInitService] Config updated:", key, "=", value)
	end
end

-- Manual regeneration (useful for debugging)
function WorldInitService:RegenerateWorld()
	--("[WorldInitService] Regenerating world...")
	
	-- Clear existing world
	if self._cubeTerrainService then
		self._cubeTerrainService:ClearTerrain()
	end
	if self._gridService then
		self._gridService:ClearGrid()
	end
	if self._treeService then
		self._treeService:ClearTrees()
	end
	if self._formationService then
		self._formationService:ClearFormations()
	end
	
	task.wait(0.5)
	
	-- Run initialization again
	runInitializationSequence(self)
end

return WorldInitService

