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
	_terrainService = nil,
	_gridService = nil,
	_reservedZoneService = nil,
	_redZoneService = nil,
	_treeService = nil,
	_formationService = nil,
}

-- === CONFIG ===
local CONFIG = {
	-- Baseplate grid settings
	BaseplateGridSize = 3,       -- 3x3 grid = 9 baseplates
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
	print("[WorldInitService] Phase 1: Creating baseplate grid...")
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
	
	print(string.format("[WorldInitService] Created %dx%d baseplate grid (%.0f x %.0f studs)", 
		gridSize, gridSize, totalWidth, totalDepth))
	
	return baseplates, self._baseplateInfo
end

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         PHASE 2: GRID SERVICE                              ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

local function initializeGridService(self)
	print("[WorldInitService] Phase 2: Initializing GridService with baseplates...")
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
	
	print("[WorldInitService] GridService initialized with baseplates")
	return true
end

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                      PHASE 3: GENERATE TERRAIN                             ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

local function generateTerrain(self)
	print("[WorldInitService] Phase 3: Generating terrain...")
	self._initPhase = "generating_terrain"
	
	if not self._terrainService then
		warn("[WorldInitService] TerrainService not available!")
		return false
	end
	
	if not self._baseplateInfo then
		warn("[WorldInitService] No baseplate info available!")
		return false
	end
	
	-- Generate terrain using baseplate info
	self._terrainService:GenerateTerrainWithBaseplates(self._baseplateInfo)
	
	print("[WorldInitService] Terrain generation complete")
	return true
end

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                      PHASE 4: RESERVE CELLS                                ║
-- ╚════════════════════════════════════════════════════════════════════════════╝
-- NOTE: Reserve cells AFTER terrain so flattening works properly!

local function reserveCells(self)
	print("[WorldInitService] Phase 4: Reserving cells (after terrain for flattening)...")
	self._initPhase = "reserving_cells"
	
	-- Initialize ReservedZoneService (will flatten terrain under Building zones)
	if self._reservedZoneService then
		self._reservedZoneService:InitializeZones()
		print("[WorldInitService] Reserved zones created and terrain flattened")
	end
	
	-- Initialize RedZoneService
	if self._redZoneService then
		self._redZoneService:InitializeZones()
		print("[WorldInitService] Red zones created")
	end
	
	return true
end

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                  PHASE 5: GENERATE TREES & FORMATIONS                      ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

local function generateVegetation(self)
	print("[WorldInitService] Phase 5: Generating trees and formations...")
	self._initPhase = "generating_vegetation"
	
	-- Generate trees
	if self._treeService then
		print("[WorldInitService] Generating trees...")
		self._treeService:GenerateTreesWithBaseplates(self._baseplateInfo)
	end
	
	-- Generate formations
	if self._formationService then
		print("[WorldInitService] Generating formations...")
		self._formationService:GenerateFormationsWithBaseplates(self._baseplateInfo)
	end
	
	print("[WorldInitService] Vegetation generation complete")
	return true
end

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                      PHASE 6: REMOVE BASEPLATES                            ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

local function removeBaseplates(self)
	print("[WorldInitService] Phase 6: Removing baseplates...")
	self._initPhase = "removing_baseplates"
	
	-- Remove the WorldBaseplates folder we created
	if self._baseplateFolder then
		self._baseplateFolder:Destroy()
		self._baseplateFolder = nil
		print("[WorldInitService] WorldBaseplates folder removed")
	end
	
	-- Also check for WorldBaseplates folder in case reference was lost
	local worldBaseplates = Workspace:FindFirstChild("WorldBaseplates")
	if worldBaseplates then
		worldBaseplates:Destroy()
		print("[WorldInitService] Found and removed WorldBaseplates folder")
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
		print("[WorldInitService] Removing baseplate:", baseplate.Name)
		baseplate:Destroy()
	end
	
	if #baseplatesToRemove > 0 then
		print(string.format("[WorldInitService] Removed %d baseplate(s) from workspace", #baseplatesToRemove))
	end
	
	-- Also remove TerrainBaseplates folder if it exists (from old TerrainService)
	local terrainBaseplates = Workspace:FindFirstChild("TerrainBaseplates")
	if terrainBaseplates then
		terrainBaseplates:Destroy()
		print("[WorldInitService] Removed TerrainBaseplates folder")
	end
	
	self._initPhase = "complete"
	return true
end

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                      MAIN INITIALIZATION SEQUENCE                          ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

local function runInitializationSequence(self)
	local startTime = tick()
	print("[WorldInitService] ========== STARTING WORLD INITIALIZATION ==========")
	
	local function reportProgress(phase, progress, message)
		if self._loadingService then
			self._loadingService:UpdateStatus("WorldInitService", message, progress)
		end
		print(string.format("[WorldInitService] [%s] %s", phase, message))
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
	
	-- ===== PHASE 3: Generate Terrain FIRST =====
	reportProgress("Phase 3", 0.25, "Generating terrain...")
	generateTerrain(self)
	task.wait(CONFIG.PhaseDelayMs / 1000)
	
	if self._loadingService then
		self._loadingService:MarkStepComplete("TerrainService")
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
	print(string.format("[WorldInitService] ========== WORLD INITIALIZATION COMPLETE (%.2fs) ==========", elapsed))
	
	if self._loadingService then
		self._loadingService:MarkStepComplete("WorldInitService")
	end
	
	return true
end

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                           KNIT LIFECYCLE                                   ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

function WorldInitService:KnitInit()
	print("[WorldInitService] Initializing - World generation orchestrator")
	
	-- Get service references (they may not all be available yet)
	pcall(function() self._loadingService = Knit.GetService("LoadingService") end)
	pcall(function() self._terrainService = Knit.GetService("TerrainService") end)
	pcall(function() self._gridService = Knit.GetService("GridService") end)
	pcall(function() self._reservedZoneService = Knit.GetService("ReservedZoneService") end)
	pcall(function() self._redZoneService = Knit.GetService("RedZoneService") end)
	pcall(function() self._treeService = Knit.GetService("TreeService") end)
	pcall(function() self._formationService = Knit.GetService("FormationService") end)
end

function WorldInitService:KnitStart()
	print("[WorldInitService] Starting world generation sequence...")
	
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
		print("[WorldInitService] Config updated:", key, "=", value)
	end
end

-- Manual regeneration (useful for debugging)
function WorldInitService:RegenerateWorld()
	print("[WorldInitService] Regenerating world...")
	
	-- Clear existing world
	if self._terrainService then
		self._terrainService:ClearTerrain()
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

