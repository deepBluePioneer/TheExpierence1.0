--[[
	CullingController
	Optimizes rendering by culling objects outside the camera frustum
	and reducing detail for distant objects.
	
	Features:
	- Frustum culling (hide objects outside camera view)
	- Distance-based culling (LOD system)
	- Smart batching (staggered updates for performance)
	- Configurable cull zones and priorities
	- Particle/effect culling at distance
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local Knit = require(Packages.Knit)

local CullingController = Knit.CreateController {
	Name = "CullingController",
	_updateConnection = nil,
	_trackedObjects = {},      -- Objects being culled
	_cullZones = {},           -- Spatial zones for batch culling
	_frameCounter = 0,
	_enabled = true,
}

-- === CONFIGURATION ===
local CULLING_CONFIG = {
	-- General
	Enabled = false,            -- DISABLED: Culling system disabled
	DebugMode = false,          -- Show culling debug visuals
	
	-- Update frequency (stagger updates for performance)
	UpdateInterval = 2,         -- Frames between full cull checks
	BatchSize = 50,             -- Objects to check per frame
	
	-- Distance culling thresholds
	NearDistance = 50,          -- Full detail
	MediumDistance = 150,       -- Reduced particles/effects
	FarDistance = 300,          -- Minimal detail
	CullDistance = 500,         -- Complete cull
	
	-- Frustum culling
	FrustumEnabled = true,
	FrustumPadding = 10,        -- Extra margin around frustum (studs)
	
	-- Effect culling (particles, trails, lights)
	CullParticles = true,
	CullTrails = true,
	CullPointLights = true,
	CullDecals = false,         -- Usually cheap, keep enabled
	
	-- LOD settings
	LODEnabled = true,
	LODTransparencyFade = true, -- Fade objects at distance
	
	-- Tags to auto-register for culling
	CullTags = {
		"Cullable",             -- Generic cullable objects
		"CullableEffect",       -- Effects (particles, etc)
		"CullableProp",         -- Environmental props
		"CullableDetail",       -- Fine detail objects
	},
	
	-- Priority tags (checked less frequently)
	LowPriorityTags = {
		"CullableLowPriority",
	},
}

-- === STATE ===
local cullState = {
	camera = nil,
	cameraPosition = Vector3.zero,
	cameraCFrame = CFrame.identity,
	cameraFOV = 70,
	cameraAspect = 16/9,
	frustumPlanes = {},
}

-- === CULLING LEVELS ===
local CullLevel = {
	FULL_DETAIL = 1,        -- Everything visible
	REDUCED_EFFECTS = 2,    -- Particles/trails disabled
	MINIMAL_DETAIL = 3,     -- LOD + no effects
	CULLED = 4,             -- Completely hidden
}

-- === HELPER FUNCTIONS ===

-- Calculate frustum planes from camera
local function calculateFrustumPlanes(camera)
	local cf = camera.CFrame
	local fov = math.rad(camera.FieldOfView)
	local aspect = camera.ViewportSize.X / camera.ViewportSize.Y
	
	local nearDist = 0.1
	local farDist = CULLING_CONFIG.CullDistance
	
	-- Calculate frustum half-dimensions at near plane
	local tanHalfFov = math.tan(fov / 2)
	local nearHeight = 2 * tanHalfFov * nearDist
	local nearWidth = nearHeight * aspect
	
	local pos = cf.Position
	local forward = cf.LookVector
	local right = cf.RightVector
	local up = cf.UpVector
	
	-- Build frustum planes (normal points inward)
	local planes = {}
	
	-- Near plane
	planes[1] = {
		normal = forward,
		distance = forward:Dot(pos + forward * nearDist)
	}
	
	-- Far plane
	planes[2] = {
		normal = -forward,
		distance = (-forward):Dot(pos + forward * farDist)
	}
	
	-- Calculate edge normals for side planes
	local farHeight = 2 * tanHalfFov * farDist
	local farWidth = farHeight * aspect
	
	-- Right plane
	local rightEdge = (forward * farDist + right * (farWidth/2)).Unit
	local rightNormal = up:Cross(rightEdge).Unit
	planes[3] = {
		normal = rightNormal,
		distance = rightNormal:Dot(pos)
	}
	
	-- Left plane
	local leftEdge = (forward * farDist - right * (farWidth/2)).Unit
	local leftNormal = leftEdge:Cross(up).Unit
	planes[4] = {
		normal = leftNormal,
		distance = leftNormal:Dot(pos)
	}
	
	-- Top plane
	local topEdge = (forward * farDist + up * (farHeight/2)).Unit
	local topNormal = topEdge:Cross(right).Unit
	planes[5] = {
		normal = topNormal,
		distance = topNormal:Dot(pos)
	}
	
	-- Bottom plane
	local bottomEdge = (forward * farDist - up * (farHeight/2)).Unit
	local bottomNormal = right:Cross(bottomEdge).Unit
	planes[6] = {
		normal = bottomNormal,
		distance = bottomNormal:Dot(pos)
	}
	
	return planes
end

-- Check if a point is inside all frustum planes
local function isPointInFrustum(point, planes)
	for _, plane in ipairs(planes) do
		local dist = plane.normal:Dot(point) - plane.distance
		if dist < -CULLING_CONFIG.FrustumPadding then
			return false
		end
	end
	return true
end

-- Check if a bounding sphere intersects the frustum
local function isSphereInFrustum(center, radius, planes)
	for _, plane in ipairs(planes) do
		local dist = plane.normal:Dot(center) - plane.distance
		if dist < -(radius + CULLING_CONFIG.FrustumPadding) then
			return false
		end
	end
	return true
end

-- Get bounding sphere for a model/part
local function getBoundingSphere(object)
	if object:IsA("BasePart") then
		return object.Position, object.Size.Magnitude / 2
	elseif object:IsA("Model") then
		local cf, size = object:GetBoundingBox()
		return cf.Position, size.Magnitude / 2
	end
	return object:IsA("Attachment") and object.WorldPosition or Vector3.zero, 5
end

-- Get distance from camera to object
local function getDistanceToCamera(position)
	return (position - cullState.cameraPosition).Magnitude
end

-- Determine cull level based on distance
local function getCullLevel(distance)
	if distance <= CULLING_CONFIG.NearDistance then
		return CullLevel.FULL_DETAIL
	elseif distance <= CULLING_CONFIG.MediumDistance then
		return CullLevel.REDUCED_EFFECTS
	elseif distance <= CULLING_CONFIG.FarDistance then
		return CullLevel.MINIMAL_DETAIL
	else
		return CullLevel.CULLED
	end
end

-- === OBJECT CULLING ===

-- Store original state for an object
local function storeOriginalState(object)
	local state = {
		transparency = {},
		effectsEnabled = {},
		lightsEnabled = {},
	}
	
	if object:IsA("BasePart") then
		state.transparency[object] = object.Transparency
	elseif object:IsA("Model") then
		for _, part in ipairs(object:GetDescendants()) do
			if part:IsA("BasePart") then
				state.transparency[part] = part.Transparency
			elseif part:IsA("ParticleEmitter") or part:IsA("Trail") or part:IsA("Beam") then
				state.effectsEnabled[part] = part.Enabled
			elseif part:IsA("Light") then
				state.lightsEnabled[part] = part.Enabled
			end
		end
	end
	
	return state
end

-- Apply cull level to an object
local function applyCullLevel(trackedObject, cullLevel)
	local object = trackedObject.object
	local originalState = trackedObject.originalState
	local currentLevel = trackedObject.currentLevel
	
	if currentLevel == cullLevel then return end
	trackedObject.currentLevel = cullLevel
	
	-- FULL_DETAIL: Restore everything
	if cullLevel == CullLevel.FULL_DETAIL then
		-- Restore transparency
		for part, originalTransparency in pairs(originalState.transparency) do
			if part and part.Parent then
				part.Transparency = originalTransparency
			end
		end
		
		-- Restore effects
		for effect, wasEnabled in pairs(originalState.effectsEnabled) do
			if effect and effect.Parent then
				effect.Enabled = wasEnabled
			end
		end
		
		-- Restore lights
		for light, wasEnabled in pairs(originalState.lightsEnabled) do
			if light and light.Parent then
				light.Enabled = wasEnabled
			end
		end
		
	-- REDUCED_EFFECTS: Disable particles/trails
	elseif cullLevel == CullLevel.REDUCED_EFFECTS then
		-- Restore transparency
		for part, originalTransparency in pairs(originalState.transparency) do
			if part and part.Parent then
				part.Transparency = originalTransparency
			end
		end
		
		-- Disable effects
		if CULLING_CONFIG.CullParticles or CULLING_CONFIG.CullTrails then
			for effect, _ in pairs(originalState.effectsEnabled) do
				if effect and effect.Parent then
					effect.Enabled = false
				end
			end
		end
		
		-- Keep lights but could dim them
		for light, wasEnabled in pairs(originalState.lightsEnabled) do
			if light and light.Parent then
				light.Enabled = wasEnabled
			end
		end
		
	-- MINIMAL_DETAIL: Fade + no effects/lights
	elseif cullLevel == CullLevel.MINIMAL_DETAIL then
		-- Fade transparency
		if CULLING_CONFIG.LODTransparencyFade then
			for part, originalTransparency in pairs(originalState.transparency) do
				if part and part.Parent then
					local fadeAmount = 0.3
					part.Transparency = math.min(1, originalTransparency + fadeAmount)
				end
			end
		end
		
		-- Disable effects
		for effect, _ in pairs(originalState.effectsEnabled) do
			if effect and effect.Parent then
				effect.Enabled = false
			end
		end
		
		-- Disable lights
		if CULLING_CONFIG.CullPointLights then
			for light, _ in pairs(originalState.lightsEnabled) do
				if light and light.Parent then
					light.Enabled = false
				end
			end
		end
		
	-- CULLED: Hide everything
	elseif cullLevel == CullLevel.CULLED then
		-- Full transparency
		for part, _ in pairs(originalState.transparency) do
			if part and part.Parent then
				part.Transparency = 1
			end
		end
		
		-- Disable all effects
		for effect, _ in pairs(originalState.effectsEnabled) do
			if effect and effect.Parent then
				effect.Enabled = false
			end
		end
		
		-- Disable all lights
		for light, _ in pairs(originalState.lightsEnabled) do
			if light and light.Parent then
				light.Enabled = false
			end
		end
	end
end

-- === UPDATE LOOP ===

local function updateCulling()
	if not CULLING_CONFIG.Enabled then return end
	
	CullingController._frameCounter = CullingController._frameCounter + 1
	
	-- Only do full update on interval
	if CullingController._frameCounter % CULLING_CONFIG.UpdateInterval ~= 0 then
		return
	end
	
	-- Update camera state
	local camera = Workspace.CurrentCamera
	if not camera then return end
	
	cullState.camera = camera
	cullState.cameraCFrame = camera.CFrame
	cullState.cameraPosition = camera.CFrame.Position
	cullState.cameraFOV = camera.FieldOfView
	cullState.cameraAspect = camera.ViewportSize.X / camera.ViewportSize.Y
	
	-- Calculate frustum planes
	if CULLING_CONFIG.FrustumEnabled then
		cullState.frustumPlanes = calculateFrustumPlanes(camera)
	end
	
	-- Process tracked objects in batches
	local trackedObjects = CullingController._trackedObjects
	local batchStart = ((CullingController._frameCounter / CULLING_CONFIG.UpdateInterval) * CULLING_CONFIG.BatchSize) % (#trackedObjects + 1)
	batchStart = math.floor(batchStart) + 1
	
	local processed = 0
	for id, trackedObject in pairs(trackedObjects) do
		if processed >= CULLING_CONFIG.BatchSize then break end
		
		local object = trackedObject.object
		if not object or not object.Parent then
			-- Object was destroyed, remove from tracking
			trackedObjects[id] = nil
			continue
		end
		
		-- Get object position and bounds
		local center, radius = getBoundingSphere(object)
		local distance = getDistanceToCamera(center)
		
		-- Determine cull level
		local cullLevel = CullLevel.FULL_DETAIL
		
		-- Distance-based culling
		if CULLING_CONFIG.LODEnabled then
			cullLevel = getCullLevel(distance)
		end
		
		-- Frustum culling (override to CULLED if outside frustum)
		if CULLING_CONFIG.FrustumEnabled and cullLevel ~= CullLevel.CULLED then
			if not isSphereInFrustum(center, radius, cullState.frustumPlanes) then
				cullLevel = CullLevel.CULLED
			end
		end
		
		-- Apply cull level
		applyCullLevel(trackedObject, cullLevel)
		
		processed = processed + 1
	end
end

-- === PUBLIC API ===

-- Register an object for culling
function CullingController:RegisterObject(object, options)
	if not object then return end
	
	options = options or {}
	
	local id = tostring(object:GetDebugId())
	
	self._trackedObjects[id] = {
		object = object,
		originalState = storeOriginalState(object),
		currentLevel = CullLevel.FULL_DETAIL,
		priority = options.priority or 1,
		customDistance = options.cullDistance,
	}
	
	if CULLING_CONFIG.DebugMode then
		print("[CullingController] Registered:", object:GetFullName())
	end
	
	return id
end

-- Unregister an object from culling
function CullingController:UnregisterObject(object)
	if not object then return end
	
	local id = tostring(object:GetDebugId())
	local trackedObject = self._trackedObjects[id]
	
	if trackedObject then
		-- Restore to full detail before removing
		applyCullLevel(trackedObject, CullLevel.FULL_DETAIL)
		self._trackedObjects[id] = nil
	end
end

-- Register all objects with a specific tag
function CullingController:RegisterTaggedObjects(tag)
	for _, object in ipairs(CollectionService:GetTagged(tag)) do
		self:RegisterObject(object)
	end
	
	-- Auto-register future objects with this tag
	CollectionService:GetInstanceAddedSignal(tag):Connect(function(object)
		self:RegisterObject(object)
	end)
	
	CollectionService:GetInstanceRemovedSignal(tag):Connect(function(object)
		self:UnregisterObject(object)
	end)
end

-- Register a folder and all its children
function CullingController:RegisterFolder(folder, options)
	if not folder then return end
	
	options = options or {}
	local recursive = options.recursive ~= false  -- Default true
	
	local function registerDescendant(object)
		if object:IsA("BasePart") or object:IsA("Model") then
			self:RegisterObject(object, options)
		end
	end
	
	if recursive then
		for _, descendant in ipairs(folder:GetDescendants()) do
			registerDescendant(descendant)
		end
		folder.DescendantAdded:Connect(registerDescendant)
	else
		for _, child in ipairs(folder:GetChildren()) do
			registerDescendant(child)
		end
		folder.ChildAdded:Connect(registerDescendant)
	end
end

-- Force cull level for an object
function CullingController:ForceCullLevel(object, level)
	local id = tostring(object:GetDebugId())
	local trackedObject = self._trackedObjects[id]
	
	if trackedObject then
		applyCullLevel(trackedObject, level)
	end
end

-- Get current cull statistics
function CullingController:GetStats()
	local stats = {
		totalTracked = 0,
		fullDetail = 0,
		reducedEffects = 0,
		minimalDetail = 0,
		culled = 0,
	}
	
	for _, trackedObject in pairs(self._trackedObjects) do
		stats.totalTracked = stats.totalTracked + 1
		
		local level = trackedObject.currentLevel
		if level == CullLevel.FULL_DETAIL then
			stats.fullDetail = stats.fullDetail + 1
		elseif level == CullLevel.REDUCED_EFFECTS then
			stats.reducedEffects = stats.reducedEffects + 1
		elseif level == CullLevel.MINIMAL_DETAIL then
			stats.minimalDetail = stats.minimalDetail + 1
		elseif level == CullLevel.CULLED then
			stats.culled = stats.culled + 1
		end
	end
	
	return stats
end

-- Enable/disable culling
function CullingController:SetEnabled(enabled)
	CULLING_CONFIG.Enabled = enabled
	self._enabled = enabled
	
	if not enabled then
		-- Restore all objects to full detail
		for _, trackedObject in pairs(self._trackedObjects) do
			applyCullLevel(trackedObject, CullLevel.FULL_DETAIL)
		end
	end
end

-- Update configuration
function CullingController:SetConfig(key, value)
	if CULLING_CONFIG[key] ~= nil then
		CULLING_CONFIG[key] = value
	end
end

-- Get configuration
function CullingController:GetConfig()
	return CULLING_CONFIG
end

-- === KNIT LIFECYCLE ===

function CullingController:KnitInit()
	-- Initialize state
	cullState.camera = Workspace.CurrentCamera
end

function CullingController:KnitStart()
	-- Early exit if disabled
	if not CULLING_CONFIG.Enabled then
		return
	end
	
	-- Register default tagged objects
	for _, tag in ipairs(CULLING_CONFIG.CullTags) do
		self:RegisterTaggedObjects(tag)
	end
	
	-- Start culling update loop
	self._updateConnection = RunService.Heartbeat:Connect(function()
		updateCulling()
	end)
end

-- Expose CullLevel enum for external use
CullingController.CullLevel = CullLevel

return CullingController

