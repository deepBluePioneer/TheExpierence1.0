--[[
	FogOfWarController
	First-person fog of war system where fog is AHEAD of the player.
	
	Features:
	- Fog wall in front of the player that retreats as they move forward
	- Player area is always clear - fog is at a distance
	- Persistent revelation - areas stay revealed once walked through
	- Grid-based tracking for efficient revelation storage
	- Uses Roblox Lighting fog for natural depth-based obscuring
	- Object culling for unrevealed areas beyond the fog
	- Performance optimized with batched updates
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")
local Lighting = game:GetService("Lighting")
local TweenService = game:GetService("TweenService")
local CollectionService = game:GetService("CollectionService")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local Knit = require(Packages.Knit)

local FogOfWarController = Knit.CreateController {
	Name = "FogOfWarController",
	_updateConnection = nil,
	_trackedObjects = {},       -- Objects affected by fog of war
	_revealedCells = {},        -- Grid cells that have been revealed {key = {revealedAt, lastRefreshed}}
	_fogWallParts = {},         -- Parts that form the fog wall
	_enabled = true,
	_frameCounter = 0,
}

-- === CONFIGURATION ===
local FOG_CONFIG = {
	-- General
	Enabled = true,
	DebugMode = false,              -- Show debug visuals for cells
	
	-- Vision/Reveal settings
	VisionDistance = 80,            -- How far ahead the player can see (fog starts here)
	FogThickness = 30,              -- How thick the fog transition is
	RevealRadius = 20,              -- Radius around player that reveals cells
	
	-- Fog Return settings (revealed areas fade back to fog)
	FogReturns = true,              -- Whether fog returns to revealed areas
	RevealDuration = 8,             -- Seconds before fog starts returning to a cell
	FogReturnSpeed = 0.5,           -- Seconds for fog to fully return (fade duration)
	RefreshOnRevisit = true,        -- Reset timer when player revisits a cell
	
	-- Grid settings (for tracking revealed areas)
	CellSize = 16,                  -- Size of each grid cell in studs
	GridOrigin = Vector3.new(0, 0, 0), -- Origin point for the grid
	
	-- Fog visual settings (Roblox Lighting based)
	FogColor = Color3.fromRGB(20, 25, 35),      -- Fog color
	FogStart = 70,                  -- Where fog begins (will be set dynamically)
	FogEnd = 110,                   -- Where fog becomes solid (will be set dynamically)
	
	-- Atmosphere settings
	UseAtmosphere = true,
	AtmosphereDensity = 0.4,
	AtmosphereColor = Color3.fromRGB(25, 30, 40),
	AtmosphereOffset = 0.25,
	
	-- Fog wall (3D fog planes in the world)
	UseFogWall = true,
	FogWallSegments = 24,           -- Number of fog wall segments around player
	FogWallHeight = 100,            -- Height of fog wall
	FogWallWidth = 30,              -- Width of each fog segment
	FogWallTransparency = 0.3,      -- Base transparency of fog wall
	
	-- Object culling
	CullUnrevealed = true,          -- Hide objects in unrevealed areas
	CullDistance = 130,             -- Distance beyond which unrevealed objects are fully hidden
	CullTags = {                    -- Tags for objects to cull
		"FogCullable",
		"Cullable",
	},
	
	-- Performance
	UpdateInterval = 2,             -- Frames between updates
	BatchSize = 150,                -- Objects to process per frame
}

-- === STATE ===
local fogState = {
	playerPosition = Vector3.zero,
	playerLookDirection = Vector3.new(0, 0, -1),
	lastPlayerCell = {x = 0, z = 0},
	initialized = false,
	fogWallFolder = nil,
	atmosphere = nil,
	depthOfField = nil,
	colorCorrection = nil,
	bloom = nil,
}

-- === HELPER FUNCTIONS ===

-- Convert world position to grid cell coordinates
local function worldToCell(position)
	local offset = position - FOG_CONFIG.GridOrigin
	return {
		x = math.floor(offset.X / FOG_CONFIG.CellSize),
		z = math.floor(offset.Z / FOG_CONFIG.CellSize),
	}
end

-- Convert grid cell to world center position
local function cellToWorld(cellX, cellZ)
	return Vector3.new(
		FOG_CONFIG.GridOrigin.X + (cellX + 0.5) * FOG_CONFIG.CellSize,
		0,
		FOG_CONFIG.GridOrigin.Z + (cellZ + 0.5) * FOG_CONFIG.CellSize
	)
end

-- Get unique key for a cell
local function getCellKey(cellX, cellZ)
	return string.format("%d,%d", cellX, cellZ)
end

-- Check if a cell is revealed (and not expired)
local function isCellRevealed(cellX, cellZ)
	local key = getCellKey(cellX, cellZ)
	local cellData = FogOfWarController._revealedCells[key]
	
	if not cellData then
		return false
	end
	
	-- If fog doesn't return, cell stays revealed forever
	if not FOG_CONFIG.FogReturns then
		return true
	end
	
	-- Check if the cell has fully faded back
	local currentTime = tick()
	local timeSinceReveal = currentTime - cellData.lastRefreshed
	local totalFadeTime = FOG_CONFIG.RevealDuration + FOG_CONFIG.FogReturnSpeed
	
	return timeSinceReveal < totalFadeTime
end

-- Get the reveal strength of a cell (1 = fully revealed, 0 = fully fogged)
local function getCellRevealStrength(cellX, cellZ)
	local key = getCellKey(cellX, cellZ)
	local cellData = FogOfWarController._revealedCells[key]
	
	if not cellData then
		return 0
	end
	
	-- If fog doesn't return, always fully revealed
	if not FOG_CONFIG.FogReturns then
		return 1
	end
	
	local currentTime = tick()
	local timeSinceReveal = currentTime - cellData.lastRefreshed
	
	-- Still in the "fully revealed" period
	if timeSinceReveal < FOG_CONFIG.RevealDuration then
		return 1
	end
	
	-- In the fade-back period
	local fadeProgress = (timeSinceReveal - FOG_CONFIG.RevealDuration) / FOG_CONFIG.FogReturnSpeed
	
	if fadeProgress >= 1 then
		return 0 -- Fully fogged again
	end
	
	-- Smooth fade using smoothstep
	local t = fadeProgress
	local smoothFade = t * t * (3 - 2 * t)
	return 1 - smoothFade
end

-- Mark a cell as revealed (or refresh its timer)
local function revealCell(cellX, cellZ)
	local key = getCellKey(cellX, cellZ)
	local currentTime = tick()
	local existingData = FogOfWarController._revealedCells[key]
	
	if existingData then
		-- Cell was already revealed - refresh if enabled
		if FOG_CONFIG.RefreshOnRevisit then
			existingData.lastRefreshed = currentTime
		end
		return false -- Not newly revealed
	else
		-- New cell revealed
		FogOfWarController._revealedCells[key] = {
			revealedAt = currentTime,
			lastRefreshed = currentTime,
		}
		
		if FOG_CONFIG.DebugMode then
			print(string.format("[FogOfWar] Revealed cell: %s", key))
		end
		
		return true -- Newly revealed
	end
end

-- Check if a position is in a revealed area
local function isPositionRevealed(position)
	local cell = worldToCell(position)
	return isCellRevealed(cell.x, cell.z)
end

-- Get reveal strength at a position (1 = fully revealed, 0 = fogged)
local function getPositionRevealStrength(position)
	local cell = worldToCell(position)
	return getCellRevealStrength(cell.x, cell.z)
end

-- Get 3D distance from player
local function getDistanceFromPlayer(position)
	return (position - fogState.playerPosition).Magnitude
end

-- Get horizontal (XZ) distance from player
local function getHorizontalDistance(position)
	local playerPos2D = Vector2.new(fogState.playerPosition.X, fogState.playerPosition.Z)
	local pos2D = Vector2.new(position.X, position.Z)
	return (pos2D - playerPos2D).Magnitude
end

-- Check if position is within the player's immediate reveal radius
local function isInRevealRadius(position)
	return getHorizontalDistance(position) <= FOG_CONFIG.RevealRadius
end

-- Check if a position is currently visible (in front of fog wall OR revealed)
local function isPositionVisible(position)
	-- If already revealed, always visible
	if isPositionRevealed(position) then
		return true, 0
	end
	
	-- Check if within vision distance
	local distance = getHorizontalDistance(position)
	
	if distance <= FOG_CONFIG.VisionDistance then
		-- Fully visible - in front of fog
		return true, 0
	elseif distance <= FOG_CONFIG.VisionDistance + FOG_CONFIG.FogThickness then
		-- In the fog transition zone
		local t = (distance - FOG_CONFIG.VisionDistance) / FOG_CONFIG.FogThickness
		return true, t -- Partially fogged
	else
		-- Beyond fog - hidden unless revealed
		return false, 1
	end
end

-- Calculate fog opacity for a position (0 = clear, 1 = fully fogged)
local function getFogOpacity(position)
	local distance = getHorizontalDistance(position)
	
	-- In front of fog wall (within vision distance) - always clear
	if distance <= FOG_CONFIG.VisionDistance then
		return 0
	end
	
	-- Check reveal strength for this position (may be fading back)
	local revealStrength = getPositionRevealStrength(position)
	
	-- If fully revealed (or mostly), no fog
	if revealStrength >= 1 then
		return 0
	end
	
	-- Calculate base fog from distance
	local distanceFog = 1
	if distance <= FOG_CONFIG.VisionDistance + FOG_CONFIG.FogThickness then
		-- In fog transition zone
		local t = (distance - FOG_CONFIG.VisionDistance) / FOG_CONFIG.FogThickness
		distanceFog = t * t * (3 - 2 * t) -- Smoothstep for nice transition
	end
	
	-- If area was revealed but is fading back, blend between clear and distance fog
	if revealStrength > 0 then
		-- Revealed areas fade back to full fog
		return distanceFog * (1 - revealStrength)
	end
	
	-- Beyond fog and never revealed - fully fogged
	return distanceFog
end

-- === LIGHTING FOG SYSTEM ===

-- Set up the Roblox Lighting-based fog
local function setupLightingFog()
	-- Configure Lighting fog (this creates depth-based fog naturally)
	Lighting.FogColor = FOG_CONFIG.FogColor
	Lighting.FogStart = FOG_CONFIG.VisionDistance
	Lighting.FogEnd = FOG_CONFIG.VisionDistance + FOG_CONFIG.FogThickness
	
	-- Atmosphere for volumetric feel
	if FOG_CONFIG.UseAtmosphere then
		local atmosphere = Lighting:FindFirstChild("FogOfWarAtmosphere")
		if not atmosphere then
			atmosphere = Instance.new("Atmosphere")
			atmosphere.Name = "FogOfWarAtmosphere"
			atmosphere.Parent = Lighting
		end
		atmosphere.Density = FOG_CONFIG.AtmosphereDensity
		atmosphere.Color = FOG_CONFIG.AtmosphereColor
		atmosphere.Decay = FOG_CONFIG.AtmosphereColor
		atmosphere.Glare = 0
		atmosphere.Haze = 1.5
		atmosphere.Offset = FOG_CONFIG.AtmosphereOffset
		fogState.atmosphere = atmosphere
		
		-- Depth of field for extra blur at distance
		local dof = Lighting:FindFirstChild("FogOfWarDOF")
		if not dof then
			dof = Instance.new("DepthOfFieldEffect")
			dof.Name = "FogOfWarDOF"
			dof.Parent = Lighting
		end
		dof.FarIntensity = 0.4
		dof.FocusDistance = FOG_CONFIG.VisionDistance * 0.6
		dof.InFocusRadius = FOG_CONFIG.VisionDistance * 0.4
		dof.NearIntensity = 0
		fogState.depthOfField = dof
		
		-- Bloom for fog glow effect
		local bloom = Lighting:FindFirstChild("FogOfWarBloom")
		if not bloom then
			bloom = Instance.new("BloomEffect")
			bloom.Name = "FogOfWarBloom"
			bloom.Parent = Lighting
		end
		bloom.Intensity = 0.5
		bloom.Size = 30
		bloom.Threshold = 1.5
		fogState.bloom = bloom
		
		-- Color correction for mood
		local cc = Lighting:FindFirstChild("FogOfWarCC")
		if not cc then
			cc = Instance.new("ColorCorrectionEffect")
			cc.Name = "FogOfWarCC"
			cc.Parent = Lighting
		end
		cc.Brightness = -0.02
		cc.Contrast = 0.05
		cc.Saturation = -0.15
		cc.TintColor = Color3.fromRGB(210, 215, 230)
		fogState.colorCorrection = cc
	end
end

-- Update the lighting fog distance dynamically (optional, for effects)
local function updateLightingFog()
	-- Keep fog at consistent distance from player
	Lighting.FogStart = FOG_CONFIG.VisionDistance
	Lighting.FogEnd = FOG_CONFIG.VisionDistance + FOG_CONFIG.FogThickness
	
	if fogState.depthOfField then
		fogState.depthOfField.FocusDistance = FOG_CONFIG.VisionDistance * 0.6
		fogState.depthOfField.InFocusRadius = FOG_CONFIG.VisionDistance * 0.4
	end
end

-- === 3D FOG WALL SYSTEM ===

-- Create the fog wall parts that form a ring around the vision distance
local function createFogWall()
	if not FOG_CONFIG.UseFogWall then return end
	
	-- Create folder for fog wall parts
	local fogWallFolder = Instance.new("Folder")
	fogWallFolder.Name = "FogWallParts"
	fogWallFolder.Parent = Workspace
	fogState.fogWallFolder = fogWallFolder
	
	-- Create fog wall segments in a ring
	local segmentCount = FOG_CONFIG.FogWallSegments
	local angleStep = (2 * math.pi) / segmentCount
	
	for i = 1, segmentCount do
		local angle = (i - 1) * angleStep
		
		-- Create fog wall part
		local fogPart = Instance.new("Part")
		fogPart.Name = "FogWallSegment_" .. i
		fogPart.Size = Vector3.new(FOG_CONFIG.FogWallWidth, FOG_CONFIG.FogWallHeight, 2)
		fogPart.Anchored = true
		fogPart.CanCollide = false
		fogPart.CastShadow = false
		fogPart.Color = FOG_CONFIG.FogColor
		fogPart.Material = Enum.Material.SmoothPlastic
		fogPart.Transparency = FOG_CONFIG.FogWallTransparency
		
		-- Add particle emitter for fog effect
		local emitter = Instance.new("ParticleEmitter")
		emitter.Color = ColorSequence.new(FOG_CONFIG.FogColor)
		emitter.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 20),
			NumberSequenceKeypoint.new(0.5, 35),
			NumberSequenceKeypoint.new(1, 25),
		})
		emitter.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.7),
			NumberSequenceKeypoint.new(0.3, 0.5),
			NumberSequenceKeypoint.new(0.7, 0.6),
			NumberSequenceKeypoint.new(1, 1),
		})
		emitter.Lifetime = NumberRange.new(4, 7)
		emitter.Rate = 3
		emitter.Speed = NumberRange.new(2, 5)
		emitter.SpreadAngle = Vector2.new(30, 30)
		emitter.RotSpeed = NumberRange.new(-20, 20)
		emitter.Rotation = NumberRange.new(0, 360)
		emitter.Texture = "rbxassetid://1084137" -- Smoke texture
		emitter.LightEmission = 0
		emitter.LightInfluence = 0.3
		emitter.Drag = 1
		emitter.Parent = fogPart
		
		fogPart.Parent = fogWallFolder
		
		table.insert(FogOfWarController._fogWallParts, {
			part = fogPart,
			emitter = emitter,
			angle = angle,
			baseTransparency = FOG_CONFIG.FogWallTransparency,
		})
	end
end

-- Update fog wall positions around the player
local function updateFogWall()
	if not FOG_CONFIG.UseFogWall then return end
	
	local playerPos = fogState.playerPosition
	local visionDist = FOG_CONFIG.VisionDistance
	
	for _, fogData in ipairs(FogOfWarController._fogWallParts) do
		local angle = fogData.angle
		
		-- Calculate position on the ring at vision distance
		local offsetX = math.cos(angle) * visionDist
		local offsetZ = math.sin(angle) * visionDist
		
		local wallPos = Vector3.new(
			playerPos.X + offsetX,
			playerPos.Y + FOG_CONFIG.FogWallHeight * 0.3,
			playerPos.Z + offsetZ
		)
		
		-- Get reveal strength at this position (accounts for fading)
		local revealStrength = getPositionRevealStrength(wallPos)
		
		-- Calculate direction to face (tangent to the circle, facing inward)
		local dirToPlayer = (playerPos - wallPos).Unit
		local lookAt = wallPos + dirToPlayer
		
		-- Update position and rotation
		fogData.part.CFrame = CFrame.new(wallPos, Vector3.new(lookAt.X, wallPos.Y, lookAt.Z))
		
		-- Adjust fog transparency based on reveal strength
		if revealStrength > 0.5 then
			-- Area is mostly revealed - fog wall is transparent
			local targetTransparency = 0.95
			fogData.part.Transparency = fogData.part.Transparency + (targetTransparency - fogData.part.Transparency) * 0.1
			fogData.emitter.Rate = 0.5
		elseif revealStrength > 0 then
			-- Area is fading back - fog wall is partially visible
			local targetTransparency = fogData.baseTransparency + (0.95 - fogData.baseTransparency) * revealStrength
			fogData.part.Transparency = fogData.part.Transparency + (targetTransparency - fogData.part.Transparency) * 0.1
			fogData.emitter.Rate = 1 + (2 * (1 - revealStrength))
		else
			-- Area not revealed - normal fog
			fogData.part.Transparency = fogData.part.Transparency + (fogData.baseTransparency - fogData.part.Transparency) * 0.1
			fogData.emitter.Rate = 3
		end
	end
end

-- Clean up fully expired cells from memory
local function cleanupExpiredCells()
	if not FOG_CONFIG.FogReturns then return end
	
	local currentTime = tick()
	local totalFadeTime = FOG_CONFIG.RevealDuration + FOG_CONFIG.FogReturnSpeed
	local cellsToRemove = {}
	
	for key, cellData in pairs(FogOfWarController._revealedCells) do
		local timeSinceReveal = currentTime - cellData.lastRefreshed
		
		-- Add some buffer time before removing to avoid thrashing
		if timeSinceReveal > totalFadeTime + 5 then
			table.insert(cellsToRemove, key)
		end
	end
	
	-- Remove expired cells
	for _, key in ipairs(cellsToRemove) do
		FogOfWarController._revealedCells[key] = nil
		
		if FOG_CONFIG.DebugMode then
			print(string.format("[FogOfWar] Cell expired and removed: %s", key))
		end
	end
end

-- === REVELATION SYSTEM ===

-- Reveal cells around the player as they walk
local function updateRevelation()
	local playerPos = fogState.playerPosition
	local currentCell = worldToCell(playerPos)
	
	-- Reveal cells within the reveal radius (immediate area around player)
	local cellRadius = math.ceil(FOG_CONFIG.RevealRadius / FOG_CONFIG.CellSize)
	
	local newlyRevealed = 0
	for dx = -cellRadius, cellRadius do
		for dz = -cellRadius, cellRadius do
			local cellX = currentCell.x + dx
			local cellZ = currentCell.z + dz
			
			-- Check if cell center is within reveal radius
			local cellCenter = cellToWorld(cellX, cellZ)
			local dist = getHorizontalDistance(cellCenter)
			
			if dist <= FOG_CONFIG.RevealRadius then
				if revealCell(cellX, cellZ) then
					newlyRevealed = newlyRevealed + 1
				end
			end
		end
	end
	
	-- Update last player cell
	fogState.lastPlayerCell = currentCell
	
	return newlyRevealed
end

-- === OBJECT CULLING ===

-- Store original transparency for an object
local function storeObjectState(object)
	local state = {
		transparency = {},
		particlesEnabled = {},
		lightsEnabled = {},
	}
	
	if object:IsA("BasePart") then
		state.transparency[object] = object.Transparency
	elseif object:IsA("Model") then
		for _, part in ipairs(object:GetDescendants()) do
			if part:IsA("BasePart") then
				state.transparency[part] = part.Transparency
			elseif part:IsA("ParticleEmitter") or part:IsA("Trail") or part:IsA("Beam") then
				state.particlesEnabled[part] = part.Enabled
			elseif part:IsA("Light") then
				state.lightsEnabled[part] = part.Enabled
			end
		end
	end
	
	return state
end

-- Apply visibility to an object based on fog state
local function applyObjectVisibility(trackedObject, visible, opacity)
	local object = trackedObject.object
	local originalState = trackedObject.originalState
	
	if visible and (opacity == nil or opacity == 0) then
		-- Fully visible - restore to original state
		for part, originalTransparency in pairs(originalState.transparency) do
			if part and part.Parent then
				part.Transparency = originalTransparency
			end
		end
		
		for effect, wasEnabled in pairs(originalState.particlesEnabled) do
			if effect and effect.Parent then
				effect.Enabled = wasEnabled
			end
		end
		
		for light, wasEnabled in pairs(originalState.lightsEnabled) do
			if light and light.Parent then
				light.Enabled = wasEnabled
			end
		end
		
		trackedObject.isVisible = true
		trackedObject.currentOpacity = 0
	else
		-- Apply fog opacity to transparency
		local fogOpacity = opacity or 1
		
		for part, originalTransparency in pairs(originalState.transparency) do
			if part and part.Parent then
				-- Blend between original and fully transparent
				part.Transparency = originalTransparency + (1 - originalTransparency) * fogOpacity
			end
		end
		
		-- Disable effects when heavily fogged
		if fogOpacity > 0.5 then
			for effect, _ in pairs(originalState.particlesEnabled) do
				if effect and effect.Parent then
					effect.Enabled = false
				end
			end
			
			for light, _ in pairs(originalState.lightsEnabled) do
				if light and light.Parent then
					light.Enabled = false
				end
			end
		else
			-- Re-enable effects when less fogged
			for effect, wasEnabled in pairs(originalState.particlesEnabled) do
				if effect and effect.Parent then
					effect.Enabled = wasEnabled
				end
			end
			
			for light, wasEnabled in pairs(originalState.lightsEnabled) do
				if light and light.Parent then
					light.Enabled = wasEnabled
				end
			end
		end
		
		trackedObject.isVisible = fogOpacity < 1
		trackedObject.currentOpacity = fogOpacity
	end
end

-- Update culling for all tracked objects
local function updateObjectCulling()
	if not FOG_CONFIG.CullUnrevealed then return end
	
	local trackedObjects = FogOfWarController._trackedObjects
	local processed = 0
	
	for id, trackedObject in pairs(trackedObjects) do
		if processed >= FOG_CONFIG.BatchSize then break end
		
		local object = trackedObject.object
		if not object or not object.Parent then
			-- Object destroyed, remove from tracking
			trackedObjects[id] = nil
			continue
		end
		
		-- Get object position
		local position
		if object:IsA("BasePart") then
			position = object.Position
		elseif object:IsA("Model") then
			local primaryPart = object.PrimaryPart or object:FindFirstChildWhichIsA("BasePart")
			position = primaryPart and primaryPart.Position or Vector3.zero
		end
		
		if position then
			local fogOpacity = getFogOpacity(position)
			
			if fogOpacity == 0 then
				-- Object is visible (either in view or revealed)
				if trackedObject.currentOpacity ~= 0 then
					applyObjectVisibility(trackedObject, true, 0)
				end
			else
				-- Object is in fog or beyond
				applyObjectVisibility(trackedObject, false, fogOpacity)
			end
		end
		
		processed = processed + 1
	end
end

-- === MAIN UPDATE LOOP ===

local function updateFogOfWar()
	if not FOG_CONFIG.Enabled then return end
	if not fogState.initialized then return end
	
	FogOfWarController._frameCounter = FogOfWarController._frameCounter + 1
	
	-- Get player position and camera direction
	local player = Players.LocalPlayer
	local character = player.Character
	if not character then return end
	
	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if not rootPart then return end
	
	local camera = Workspace.CurrentCamera
	
	fogState.playerPosition = rootPart.Position
	if camera then
		fogState.playerLookDirection = camera.CFrame.LookVector
	end
	
	-- Update revelation (check if we've walked into new cells)
	updateRevelation()
	
	-- Update fog wall positions every frame for smooth following
	updateFogWall()
	
	-- Only do expensive updates on interval
	if FogOfWarController._frameCounter % FOG_CONFIG.UpdateInterval == 0 then
		-- Update object culling (now needs to run regularly since fog fades back)
		updateObjectCulling()
		
		-- Update lighting fog
		updateLightingFog()
	end
	
	-- Cleanup expired cells periodically (every 60 frames)
	if FogOfWarController._frameCounter % 60 == 0 then
		cleanupExpiredCells()
	end
end

-- === PUBLIC API ===

-- Register an object for fog of war culling
function FogOfWarController:RegisterObject(object, options)
	if not object then return end
	
	options = options or {}
	
	local id = tostring(object:GetDebugId())
	
	self._trackedObjects[id] = {
		object = object,
		originalState = storeObjectState(object),
		isVisible = true,
		currentOpacity = 0,
		priority = options.priority or 1,
	}
	
	-- Initial visibility check
	local position
	if object:IsA("BasePart") then
		position = object.Position
	elseif object:IsA("Model") then
		local primaryPart = object.PrimaryPart or object:FindFirstChildWhichIsA("BasePart")
		position = primaryPart and primaryPart.Position or nil
	end
	
	if position then
		local fogOpacity = getFogOpacity(position)
		if fogOpacity > 0 then
			applyObjectVisibility(self._trackedObjects[id], false, fogOpacity)
		end
	end
	
	if FOG_CONFIG.DebugMode then
		print("[FogOfWar] Registered:", object:GetFullName())
	end
	
	return id
end

-- Unregister an object from fog of war
function FogOfWarController:UnregisterObject(object)
	if not object then return end
	
	local id = tostring(object:GetDebugId())
	local trackedObject = self._trackedObjects[id]
	
	if trackedObject then
		-- Restore to visible before removing
		applyObjectVisibility(trackedObject, true, 0)
		self._trackedObjects[id] = nil
	end
end

-- Register all objects with a tag
function FogOfWarController:RegisterTaggedObjects(tag)
	for _, object in ipairs(CollectionService:GetTagged(tag)) do
		self:RegisterObject(object)
	end
	
	CollectionService:GetInstanceAddedSignal(tag):Connect(function(object)
		self:RegisterObject(object)
	end)
	
	CollectionService:GetInstanceRemovedSignal(tag):Connect(function(object)
		self:UnregisterObject(object)
	end)
end

-- Register a folder and its contents
function FogOfWarController:RegisterFolder(folder, options)
	if not folder then return end
	
	options = options or {}
	local recursive = options.recursive ~= false
	
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

-- Manually reveal an area (for scripted events, cutscenes, etc.)
function FogOfWarController:RevealArea(position, radius)
	radius = radius or FOG_CONFIG.RevealRadius
	
	local centerCell = worldToCell(position)
	local cellRadius = math.ceil(radius / FOG_CONFIG.CellSize)
	
	for dx = -cellRadius, cellRadius do
		for dz = -cellRadius, cellRadius do
			local cellX = centerCell.x + dx
			local cellZ = centerCell.z + dz
			
			local cellCenter = cellToWorld(cellX, cellZ)
			local dist = (Vector2.new(cellCenter.X, cellCenter.Z) - Vector2.new(position.X, position.Z)).Magnitude
			
			if dist <= radius then
				revealCell(cellX, cellZ)
			end
		end
	end
	
	-- Update object visibility for the newly revealed area
	updateObjectCulling()
end

-- Reset all revelation (hide everything again)
function FogOfWarController:ResetRevelation()
	self._revealedCells = {}
	
	-- Re-hide all objects based on current fog state
	for _, trackedObject in pairs(self._trackedObjects) do
		local object = trackedObject.object
		if object and object.Parent then
			local position
			if object:IsA("BasePart") then
				position = object.Position
			elseif object:IsA("Model") then
				local primaryPart = object.PrimaryPart or object:FindFirstChildWhichIsA("BasePart")
				position = primaryPart and primaryPart.Position or nil
			end
			
			if position then
				local fogOpacity = getFogOpacity(position)
				applyObjectVisibility(trackedObject, fogOpacity == 0, fogOpacity)
			end
		end
	end
end

-- Set vision distance (how far ahead the player can see)
function FogOfWarController:SetVisionDistance(distance)
	FOG_CONFIG.VisionDistance = distance
	updateLightingFog()
end

-- Get vision distance
function FogOfWarController:GetVisionDistance()
	return FOG_CONFIG.VisionDistance
end

-- Set reveal radius (area around player that permanently reveals)
function FogOfWarController:SetRevealRadius(radius)
	FOG_CONFIG.RevealRadius = radius
end

-- Get reveal radius
function FogOfWarController:GetRevealRadius()
	return FOG_CONFIG.RevealRadius
end

-- Enable/disable fog of war
function FogOfWarController:SetEnabled(enabled)
	FOG_CONFIG.Enabled = enabled
	self._enabled = enabled
	
	if enabled then
		-- Re-enable lighting fog
		Lighting.FogStart = FOG_CONFIG.VisionDistance
		Lighting.FogEnd = FOG_CONFIG.VisionDistance + FOG_CONFIG.FogThickness
		
		if fogState.atmosphere then
			fogState.atmosphere.Density = FOG_CONFIG.AtmosphereDensity
		end
		if fogState.depthOfField then
			fogState.depthOfField.Enabled = true
		end
		if fogState.colorCorrection then
			fogState.colorCorrection.Enabled = true
		end
		if fogState.bloom then
			fogState.bloom.Enabled = true
		end
		
		-- Show fog wall
		for _, fogData in ipairs(self._fogWallParts) do
			fogData.part.Transparency = fogData.baseTransparency
			fogData.emitter.Enabled = true
		end
	else
		-- Disable lighting fog
		Lighting.FogStart = 100000
		Lighting.FogEnd = 100001
		
		if fogState.atmosphere then
			fogState.atmosphere.Density = 0
		end
		if fogState.depthOfField then
			fogState.depthOfField.Enabled = false
		end
		if fogState.colorCorrection then
			fogState.colorCorrection.Enabled = false
		end
		if fogState.bloom then
			fogState.bloom.Enabled = false
		end
		
		-- Hide fog wall
		for _, fogData in ipairs(self._fogWallParts) do
			fogData.part.Transparency = 1
			fogData.emitter.Enabled = false
		end
		
		-- Restore all objects to visible
		for _, trackedObject in pairs(self._trackedObjects) do
			applyObjectVisibility(trackedObject, true, 0)
		end
	end
end

-- Check if a position is currently revealed (may be fading)
function FogOfWarController:IsPositionRevealed(position)
	return isPositionRevealed(position)
end

-- Check if a position is currently visible (in view or revealed)
function FogOfWarController:IsPositionVisible(position)
	local visible, opacity = isPositionVisible(position)
	return visible
end

-- Get fog opacity at a position
function FogOfWarController:GetFogOpacity(position)
	return getFogOpacity(position)
end

-- Get reveal strength at a position (1 = fully revealed, 0 = fully fogged/faded)
function FogOfWarController:GetRevealStrength(position)
	return getPositionRevealStrength(position)
end

-- Set whether fog returns to revealed areas
function FogOfWarController:SetFogReturns(enabled)
	FOG_CONFIG.FogReturns = enabled
end

-- Set how long areas stay revealed before fog starts returning
function FogOfWarController:SetRevealDuration(seconds)
	FOG_CONFIG.RevealDuration = seconds
end

-- Set how long it takes for fog to fully return
function FogOfWarController:SetFogReturnSpeed(seconds)
	FOG_CONFIG.FogReturnSpeed = seconds
end

-- Permanently reveal a cell (won't fade back)
function FogOfWarController:PermanentlyRevealCell(position)
	local cell = worldToCell(position)
	local key = getCellKey(cell.x, cell.z)
	
	-- Set to a special "permanent" state by using math.huge as the refresh time
	FogOfWarController._revealedCells[key] = {
		revealedAt = tick(),
		lastRefreshed = math.huge, -- Will never expire
	}
end

-- Permanently reveal an area (won't fade back)
function FogOfWarController:PermanentlyRevealArea(position, radius)
	radius = radius or FOG_CONFIG.RevealRadius
	
	local centerCell = worldToCell(position)
	local cellRadius = math.ceil(radius / FOG_CONFIG.CellSize)
	
	for dx = -cellRadius, cellRadius do
		for dz = -cellRadius, cellRadius do
			local cellX = centerCell.x + dx
			local cellZ = centerCell.z + dz
			
			local cellCenter = cellToWorld(cellX, cellZ)
			local dist = (Vector2.new(cellCenter.X, cellCenter.Z) - Vector2.new(position.X, position.Z)).Magnitude
			
			if dist <= radius then
				local key = getCellKey(cellX, cellZ)
				FogOfWarController._revealedCells[key] = {
					revealedAt = tick(),
					lastRefreshed = math.huge,
				}
			end
		end
	end
	
	updateObjectCulling()
end

-- Get revelation statistics
function FogOfWarController:GetStats()
	local totalRevealed = 0
	local fadingCells = 0
	local permanentCells = 0
	local currentTime = tick()
	
	for _, cellData in pairs(self._revealedCells) do
		totalRevealed = totalRevealed + 1
		
		if cellData.lastRefreshed == math.huge then
			permanentCells = permanentCells + 1
		elseif FOG_CONFIG.FogReturns then
			local timeSinceReveal = currentTime - cellData.lastRefreshed
			if timeSinceReveal > FOG_CONFIG.RevealDuration then
				fadingCells = fadingCells + 1
			end
		end
	end
	
	local totalTracked = 0
	for _ in pairs(self._trackedObjects) do
		totalTracked = totalTracked + 1
	end
	
	return {
		revealedCells = totalRevealed,
		fadingCells = fadingCells,
		permanentCells = permanentCells,
		trackedObjects = totalTracked,
		visionDistance = FOG_CONFIG.VisionDistance,
		revealRadius = FOG_CONFIG.RevealRadius,
		revealDuration = FOG_CONFIG.RevealDuration,
		fogReturnSpeed = FOG_CONFIG.FogReturnSpeed,
		fogReturns = FOG_CONFIG.FogReturns,
		cellSize = FOG_CONFIG.CellSize,
	}
end

-- Update configuration
function FogOfWarController:SetConfig(key, value)
	if FOG_CONFIG[key] ~= nil then
		FOG_CONFIG[key] = value
		
		-- Apply immediate updates for certain config changes
		if key == "VisionDistance" or key == "FogThickness" then
			updateLightingFog()
		elseif key == "FogColor" then
			Lighting.FogColor = value
			if fogState.atmosphere then
				fogState.atmosphere.Color = value
				fogState.atmosphere.Decay = value
			end
			for _, fogData in ipairs(self._fogWallParts) do
				fogData.part.Color = value
				fogData.emitter.Color = ColorSequence.new(value)
			end
		end
	end
end

-- Get configuration
function FogOfWarController:GetConfig()
	return FOG_CONFIG
end

-- === KNIT LIFECYCLE ===

function FogOfWarController:KnitInit()
	-- Initialize state
	self._revealedCells = {}
	self._trackedObjects = {}
	self._fogWallParts = {}
end

function FogOfWarController:KnitStart()
	-- Set up lighting-based fog
	setupLightingFog()
	
	-- Create 3D fog wall
	createFogWall()
	
	-- Register default tagged objects
	for _, tag in ipairs(FOG_CONFIG.CullTags) do
		self:RegisterTaggedObjects(tag)
	end
	
	-- Start update loop
	self._updateConnection = RunService.Heartbeat:Connect(function()
		updateFogOfWar()
	end)
	
	fogState.initialized = true
	
	-- Print initialization
	print("[FogOfWarController] Initialized - Forward-Facing Fog with Fade-Back")
	print(string.format("  - Vision Distance: %d studs (fog starts here)", FOG_CONFIG.VisionDistance))
	print(string.format("  - Fog Thickness: %d studs", FOG_CONFIG.FogThickness))
	print(string.format("  - Reveal Radius: %d studs", FOG_CONFIG.RevealRadius))
	if FOG_CONFIG.FogReturns then
		print(string.format("  - Fog Returns: Yes (after %.1fs, fades over %.1fs)", 
			FOG_CONFIG.RevealDuration, FOG_CONFIG.FogReturnSpeed))
	else
		print("  - Fog Returns: No (areas stay revealed permanently)")
	end
	print(string.format("  - Cell Size: %d studs", FOG_CONFIG.CellSize))
end

-- Cleanup
function FogOfWarController:Destroy()
	if self._updateConnection then
		self._updateConnection:Disconnect()
	end
	
	-- Clean up fog wall
	if fogState.fogWallFolder then
		fogState.fogWallFolder:Destroy()
	end
	
	-- Reset lighting fog
	Lighting.FogStart = 100000
	Lighting.FogEnd = 100001
	
	-- Clean up lighting effects
	if fogState.atmosphere then
		fogState.atmosphere:Destroy()
	end
	if fogState.depthOfField then
		fogState.depthOfField:Destroy()
	end
	if fogState.colorCorrection then
		fogState.colorCorrection:Destroy()
	end
	if fogState.bloom then
		fogState.bloom:Destroy()
	end
end

return FogOfWarController
