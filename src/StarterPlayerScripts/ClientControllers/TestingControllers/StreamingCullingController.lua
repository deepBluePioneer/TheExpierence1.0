--[[
	StreamingCullingController (CLIENT-SIDE)
	AGGRESSIVE distance-based culling - everything outside the fog/particle zone gets culled.
	
	Purpose:
	- Workspace StreamingEnabled only affects server-created instances
	- This controller aggressively culls EVERYTHING beyond fog distance
	- Syncs with fog settings for seamless visibility boundary
	
	Features:
	- Reads fog settings from Lighting automatically
	- AGGRESSIVELY culls ALL tracked entities beyond fog distance
	- Disables rendering (Transparency=1, CastShadow=false) for culled parts
	- Can auto-scan workspace folders for cullable objects
	- Performance optimized with spatial hashing
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local Workspace = game:GetService("Workspace")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local Knit = require(Packages.Knit)

local StreamingCullingController = Knit.CreateController {
	Name = "StreamingCullingController",
	_trackedEntities = {},  -- { model = {parts, originalTransparencies, enabled, isCulled} }
	_cullableTags = {},     -- Tags to auto-track for culling
	_trackedFolders = {},   -- Folders to scan for cullable children
}

-- === CONFIGURATION ===
local CULLING_CONFIG = {
	-- Core distances (will be overridden by fog settings if available)
	MinRadius = 32,             -- Minimum distance - always fully visible (reduced for tighter culling)
	TargetRadius = 180,         -- Maximum distance - fully culled beyond this (tighter default)
	FadeStartPercent = 0.8,     -- Start fading at 80% of target radius (faster fade)
	
	-- Sync with fog
	SyncWithFog = true,         -- Automatically read FogEnd from Lighting
	FogBufferDistance = 10,     -- Cull slightly before FogEnd for seamless transition (tighter)
	
	-- Update frequency
	UpdateInterval = 0.05,      -- Faster updates for responsive culling
	
	-- Performance
	MaxEntitiesPerFrame = 100,  -- Process more entities per frame
	
	-- Fade behavior
	EnableFade = false,         -- DISABLED for instant culling (better performance)
	FadeSpeed = 10.0,           -- Faster fade when enabled
	
	-- Aggressive culling options
	AggressiveMode = true,      -- Full culling (transparency + disable shadows)
	DisableShadowsWhenCulled = true,  -- Turn off CastShadow for culled parts
	DisableQueryWhenCulled = true,    -- Turn off CanQuery for culled parts
	
	-- Auto-track tags (entities with these tags will be auto-culled)
	AutoCullTags = {
		"cullable",             -- Generic cullable tag
		"clientEntity",         -- Client-spawned entities
		-- Server-side environment tags (from services)
		"proceduralTree",       -- TreeService trees
		"alienFormation",       -- FormationService formations
		"terrainCube",          -- CubeTerrainService terrain
		"particleGroup",        -- ParticleService particles
	},
	
	-- Folders to auto-scan (children of these folders will be tracked)
	AutoScanFolders = {
		"ProceduralTrees",      -- TreeService folder
		"AlienFormations",      -- FormationService folder
		"TerrainCubes",         -- CubeTerrainService folder
		"AmbientParticles",     -- ParticleService folder
	},
	
	-- Debug
	DebugEnabled = false,
	DebugPrintInterval = 1,     -- Faster debug output
}

-- Runtime state
local lastUpdateTime = 0
local lastDebugTime = 0
local currentPlayer = nil
local cullingRadius = CULLING_CONFIG.TargetRadius
local fadeStartRadius = CULLING_CONFIG.TargetRadius * CULLING_CONFIG.FadeStartPercent

-- === HELPER FUNCTIONS ===

local function lerp(a, b, t)
	return a + (b - a) * math.clamp(t, 0, 1)
end

local function getPlayerPosition()
	if not currentPlayer then return nil end
	local character = currentPlayer.Character
	if not character then return nil end
	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if not rootPart then return nil end
	return rootPart.Position
end

-- Read fog distance from Lighting
local function getFogDistance()
	local fogEnd = Lighting.FogEnd
	
	-- Also check Atmosphere if present
	local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
	if atmosphere then
		-- Atmosphere density affects visible distance
		-- Higher density = shorter visible distance
		local density = atmosphere.Density
		if density > 0 then
			-- Rough estimate: at density 0.5, visibility is ~500 studs
			local atmosphereDistance = 500 / (density + 0.1)
			-- Use the shorter of fog or atmosphere distance
			fogEnd = math.min(fogEnd, atmosphereDistance)
		end
	end
	
	return fogEnd
end

-- Update culling radius based on fog
local function syncWithFog()
	if not CULLING_CONFIG.SyncWithFog then return end
	
	local fogDistance = getFogDistance()
	cullingRadius = math.max(
		CULLING_CONFIG.MinRadius,
		fogDistance - CULLING_CONFIG.FogBufferDistance
	)
	fadeStartRadius = cullingRadius * CULLING_CONFIG.FadeStartPercent
	
	if CULLING_CONFIG.DebugEnabled then
		print(string.format(
			"[StreamingCulling] Synced with fog: cullingRadius=%.0f, fadeStart=%.0f",
			cullingRadius, fadeStartRadius
		))
	end
end

-- === ENTITY TRACKING ===

-- Store original state for parts (transparency, shadows, query)
local function storeOriginalState(parts, forceOpaqueForTerrain)
	local originals = {}
	for _, part in ipairs(parts) do
		if part:IsA("BasePart") then
			-- For terrain cubes, if transparency is 1 (fully transparent) when it should be 0,
			-- this is likely a replication timing issue - force to 0
			local transparency = part.Transparency
			if forceOpaqueForTerrain and transparency >= 0.9 then
				-- Terrain cubes should be opaque - this is likely a replication timing issue
				transparency = 0
			end
			
			originals[part] = {
				Transparency = transparency,
				CastShadow = part.CastShadow,
				CanQuery = part.CanQuery,
			}
		end
	end
	return originals
end

-- Get all BaseParts from a model/folder
local function getPartsFromModel(model)
	local parts = {}
	if model:IsA("BasePart") then
		table.insert(parts, model)
	end
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart") then
			table.insert(parts, descendant)
		end
	end
	return parts
end

-- Get position of a model/part/folder
local function getInstancePosition(instance)
	if instance:IsA("Model") then
		local primaryPart = instance.PrimaryPart
		if primaryPart then
			return primaryPart.Position
		end
		local firstPart = instance:FindFirstChildWhichIsA("BasePart", true)
		return firstPart and firstPart.Position
	elseif instance:IsA("BasePart") then
		return instance.Position
	elseif instance:IsA("Folder") then
		local firstPart = instance:FindFirstChildWhichIsA("BasePart", true)
		return firstPart and firstPart.Position
	end
	return nil
end

-- === CULLING LOGIC ===

local function calculateVisibility(distance)
	if distance <= fadeStartRadius then
		return 1  -- Fully visible
	elseif distance >= cullingRadius then
		return 0  -- Fully culled
	else
		-- Smooth fade between fadeStart and culling radius
		local t = (distance - fadeStartRadius) / (cullingRadius - fadeStartRadius)
		return 1 - t
	end
end

local function applyVisibility(entityData, visibility, deltaTime)
	if not entityData or not entityData.parts then return end
	
	local shouldBeCulled = visibility < 0.01
	local wasCulled = entityData.isCulled or false
	
	-- Quick path: if state hasn't changed, skip
	if shouldBeCulled == wasCulled and not CULLING_CONFIG.EnableFade then
		return
	end
	
	entityData.isCulled = shouldBeCulled
	
	-- AGGRESSIVE MODE: Instant culling with full disable
	if not CULLING_CONFIG.EnableFade or CULLING_CONFIG.AggressiveMode then
		for _, part in ipairs(entityData.parts) do
			if part and part.Parent then
				local original = entityData.originals[part]
				if not original then continue end
				
				if shouldBeCulled then
					-- CULL: Hide completely
					part.Transparency = 1
					if CULLING_CONFIG.DisableShadowsWhenCulled then
						part.CastShadow = false
					end
					if CULLING_CONFIG.DisableQueryWhenCulled then
						part.CanQuery = false
					end
				else
					-- RESTORE: Show with original values
					part.Transparency = original.Transparency
					part.CastShadow = original.CastShadow
					part.CanQuery = original.CanQuery
				end
			end
		end
		entityData.currentVisibility = visibility
		return
	end
	
	-- Smooth fade (when enabled and not aggressive)
	local currentVis = entityData.currentVisibility or 1
	local newVis = lerp(currentVis, visibility, deltaTime * CULLING_CONFIG.FadeSpeed)
	entityData.currentVisibility = newVis
	
	local isMostlyCulled = newVis < 0.1
	
	for _, part in ipairs(entityData.parts) do
		if part and part.Parent then
			local original = entityData.originals[part]
			if not original then continue end
			
			-- Calculate final transparency: blend between original and fully transparent
			local targetTransparency = lerp(original.Transparency, 1, 1 - newVis)
			part.Transparency = targetTransparency
			
			-- Disable shadows/query when mostly culled
			if CULLING_CONFIG.DisableShadowsWhenCulled then
				part.CastShadow = not isMostlyCulled and original.CastShadow
			end
			if CULLING_CONFIG.DisableQueryWhenCulled then
				part.CanQuery = not isMostlyCulled and original.CanQuery
			end
		end
	end
end

-- === PUBLIC API ===

-- Register an entity for culling
function StreamingCullingController:RegisterEntity(model, customTag)
	if not model then return end
	
	-- Skip if already tracked
	if self._trackedEntities[model] then return end
	
	local parts = getPartsFromModel(model)
	if #parts == 0 then return end
	
	-- Check if this is a terrain cube (should be forced opaque if transparency seems wrong)
	local isTerrainCube = customTag == "terrainCube" 
		or customTag == "TerrainCubes"
		or CollectionService:HasTag(model, "terrainCube")
	
	local entityData = {
		model = model,
		parts = parts,
		originals = storeOriginalState(parts, isTerrainCube),
		enabled = true,
		currentVisibility = 1,
		isCulled = false,
		tag = customTag,
	}
	
	self._trackedEntities[model] = entityData
	
	-- Watch for model destruction
	model.AncestryChanged:Connect(function(_, parent)
		if not parent then
			self._trackedEntities[model] = nil
		end
	end)
	
	if CULLING_CONFIG.DebugEnabled then
		print(string.format("[StreamingCulling] Registered: %s (%d parts)", model.Name, #parts))
	end
	
	return entityData
end

-- Register all children of a folder for culling
function StreamingCullingController:RegisterFolder(folderName)
	local folder = Workspace:FindFirstChild(folderName)
	if not folder then return end
	
	-- Track this folder
	self._trackedFolders[folderName] = folder
	
	-- Register existing children
	for _, child in ipairs(folder:GetChildren()) do
		if child:IsA("Model") or child:IsA("BasePart") or child:IsA("Folder") then
			self:RegisterEntity(child, folderName)
		end
	end
	
	-- Watch for new children (with delay to ensure properties are replicated)
	folder.ChildAdded:Connect(function(child)
		if child:IsA("Model") or child:IsA("BasePart") or child:IsA("Folder") then
			-- Wait a frame for properties to fully replicate from server
			task.defer(function()
				if child and child.Parent then
					self:RegisterEntity(child, folderName)
				end
			end)
		end
	end)
	
	if CULLING_CONFIG.DebugEnabled then
		print(string.format("[StreamingCulling] Registered folder: %s", folderName))
	end
end

-- Scan workspace for all cullable folders
function StreamingCullingController:ScanWorkspaceFolders()
	for _, folderName in ipairs(CULLING_CONFIG.AutoScanFolders) do
		self:RegisterFolder(folderName)
	end
	
	-- Also watch for folders being created later
	Workspace.ChildAdded:Connect(function(child)
		if child:IsA("Folder") and table.find(CULLING_CONFIG.AutoScanFolders, child.Name) then
			task.defer(function()
				self:RegisterFolder(child.Name)
			end)
		end
	end)
end

-- Unregister an entity
function StreamingCullingController:UnregisterEntity(model)
	local entityData = self._trackedEntities[model]
	if entityData then
		-- Restore all original state
		for part, original in pairs(entityData.originals) do
			if part and part.Parent and original then
				part.Transparency = original.Transparency
				part.CastShadow = original.CastShadow
				part.CanQuery = original.CanQuery
			end
		end
		self._trackedEntities[model] = nil
	end
end

-- Set culling enabled/disabled for a specific entity
function StreamingCullingController:SetEntityCullingEnabled(model, enabled)
	local entityData = self._trackedEntities[model]
	if entityData then
		entityData.enabled = enabled
		if not enabled then
			-- Restore all original state
			for part, original in pairs(entityData.originals) do
				if part and part.Parent and original then
					part.Transparency = original.Transparency
					part.CastShadow = original.CastShadow
					part.CanQuery = original.CanQuery
				end
			end
			entityData.currentVisibility = 1
			entityData.isCulled = false
		end
	end
end

-- Add a tag for auto-culling
function StreamingCullingController:AddCullableTag(tag)
	if not table.find(self._cullableTags, tag) then
		table.insert(self._cullableTags, tag)
		
		-- Register existing instances with this tag
		for _, instance in ipairs(CollectionService:GetTagged(tag)) do
			self:RegisterEntity(instance, tag)
		end
		
		-- Watch for new instances (with delay to ensure properties are replicated)
		CollectionService:GetInstanceAddedSignal(tag):Connect(function(instance)
			-- Wait a frame for properties to fully replicate from server
			task.defer(function()
				if instance and instance.Parent then
					self:RegisterEntity(instance, tag)
				end
			end)
		end)
	end
end

-- Manual configuration setters
function StreamingCullingController:SetCullingRadius(radius)
	CULLING_CONFIG.TargetRadius = radius
	cullingRadius = radius
	fadeStartRadius = radius * CULLING_CONFIG.FadeStartPercent
end

function StreamingCullingController:SetMinRadius(radius)
	CULLING_CONFIG.MinRadius = radius
end

function StreamingCullingController:SetSyncWithFog(enabled)
	CULLING_CONFIG.SyncWithFog = enabled
	if enabled then
		syncWithFog()
	end
end

function StreamingCullingController:SetDebugEnabled(enabled)
	CULLING_CONFIG.DebugEnabled = enabled
end

function StreamingCullingController:GetConfig()
	return CULLING_CONFIG
end

function StreamingCullingController:GetCullingRadius()
	return cullingRadius
end

function StreamingCullingController:GetTrackedCount()
	local count = 0
	for _ in pairs(self._trackedEntities) do
		count = count + 1
	end
	return count
end

-- === UPDATE LOOP ===

local function updateCulling(self, deltaTime)
	local playerPos = getPlayerPosition()
	if not playerPos then return end
	
	local processedCount = 0
	local visibleCount = 0
	local culledCount = 0
	local totalTracked = 0
	
	for model, entityData in pairs(self._trackedEntities) do
		totalTracked = totalTracked + 1
		
		if processedCount >= CULLING_CONFIG.MaxEntitiesPerFrame then
			break
		end
		
		if not entityData.enabled then
			processedCount = processedCount + 1
			continue
		end
		
		-- Skip if model was destroyed
		if not model or not model.Parent then
			self._trackedEntities[model] = nil
			continue
		end
		
		-- Get model position using helper
		local modelPos = getInstancePosition(model)
		
		if not modelPos then
			processedCount = processedCount + 1
			continue
		end
		
		-- Calculate distance and visibility
		local distance = (modelPos - playerPos).Magnitude
		local visibility = calculateVisibility(distance)
		
		applyVisibility(entityData, visibility, deltaTime)
		
		if visibility > 0.01 then
			visibleCount = visibleCount + 1
		else
			culledCount = culledCount + 1
		end
		
		processedCount = processedCount + 1
	end
	
	-- Debug output
	if CULLING_CONFIG.DebugEnabled then
		local now = tick()
		if now - lastDebugTime >= CULLING_CONFIG.DebugPrintInterval then
			lastDebugTime = now
			print(string.format(
				"[StreamingCulling] Visible: %d, Culled: %d, Total: %d, Radius: %.0f studs",
				visibleCount, culledCount, totalTracked, cullingRadius
			))
		end
	end
end

-- === KNIT LIFECYCLE ===

function StreamingCullingController:KnitInit()
	print("[StreamingCullingController] Initializing...")
	currentPlayer = Players.LocalPlayer
	
	-- Initialize cullable tags
	for _, tag in ipairs(CULLING_CONFIG.AutoCullTags) do
		self:AddCullableTag(tag)
	end
end

function StreamingCullingController:KnitStart()
	-- Initial sync with fog
	syncWithFog()
	
	-- Watch for fog changes
	Lighting:GetPropertyChangedSignal("FogEnd"):Connect(syncWithFog)
	Lighting:GetPropertyChangedSignal("FogStart"):Connect(syncWithFog)
	
	-- Watch for atmosphere changes
	Lighting.ChildAdded:Connect(function(child)
		if child:IsA("Atmosphere") then
			syncWithFog()
			child:GetPropertyChangedSignal("Density"):Connect(syncWithFog)
		end
	end)
	
	local existingAtmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
	if existingAtmosphere then
		existingAtmosphere:GetPropertyChangedSignal("Density"):Connect(syncWithFog)
	end
	
	-- Scan workspace folders for cullable objects
	task.defer(function()
		task.wait(1) -- Wait for services to create their folders
		self:ScanWorkspaceFolders()
		
		if CULLING_CONFIG.DebugEnabled then
			print(string.format("[StreamingCulling] Scanned folders, tracking %d entities", self:GetTrackedCount()))
		end
	end)
	
	-- Main update loop
	local updateAccumulator = 0
	
	RunService.Heartbeat:Connect(function(deltaTime)
		if CULLING_CONFIG.UpdateInterval > 0 then
			updateAccumulator = updateAccumulator + deltaTime
			if updateAccumulator >= CULLING_CONFIG.UpdateInterval then
				updateCulling(self, updateAccumulator)
				updateAccumulator = 0
			end
		else
			updateCulling(self, deltaTime)
		end
	end)
	
	print(string.format(
		"[StreamingCullingController] Started - AGGRESSIVE MODE | CullingRadius: %.0f studs | SyncWithFog: %s",
		cullingRadius,
		tostring(CULLING_CONFIG.SyncWithFog)
	))
end

-- Expose config for external access (DebugVisualsController)
StreamingCullingController.CULLING_CONFIG = CULLING_CONFIG

return StreamingCullingController

