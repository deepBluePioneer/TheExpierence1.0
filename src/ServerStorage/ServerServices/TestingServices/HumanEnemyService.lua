--[[
	HumanEnemyService
	Spawns humanoid enemies from ReplicatedStorage.Prefab in a circle formation
	Uses physics constraints (LinearVelocity, AlignOrientation) for movement instead of MoveTo
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local CollectionService = game:GetService("CollectionService")
local PathfindingService = game:GetService("PathfindingService")
local RunService = game:GetService("RunService")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local Knit = require(Packages.Knit)

local HumanEnemyService = Knit.CreateService {
	Name = "HumanEnemyService",
	Client = {
		EnemyCreated = Knit.CreateSignal(),  -- Signal fired when enemies are created
	},
	_enemies = {},  -- Track spawned enemies with data: { model, humanoid, humanoidRootPart, currentTarget, lastWanderTime, constraints }
	_autoSpawn = false,  -- Set to false to let ReservedZoneService control spawning
}

-- === CONFIG ===
local ENEMY_CONFIG = {
	EntityTag = "entity",           -- Tag to find in Prefab folder
	PrefabFolderName = "Prefab",    -- Folder name in ReplicatedStorage
	Count = 5,                      -- Number of enemies to spawn
	CircleRadius = 20,              -- Radius of the circle in studs
	CenterPosition = Vector3.new(0, 0, 0),  -- Center of the circle
	Spacing = 5,                    -- Minimum spacing between enemies
	GroundOffset = 0.5,             -- Offset above ground to prevent clipping
	-- Wandering config
	WanderRadius = 50,              -- Maximum distance from spawn to wander
	WanderInterval = 4,             -- Time between choosing new destinations (seconds)
	WanderMinDistance = 10,         -- Minimum distance for new destination
	WanderMaxStuckTime = 5,         -- Max time stuck before choosing new destination (seconds)
	WalkSpeed = 8,                  -- Walking speed for humanoids
	-- Physics constraint config
	MaxForce = 50000,               -- Max force for LinearVelocity constraint
	MaxTorque = 100000,             -- Max torque for AlignOrientation constraint
	TurnResponsiveness = 15,        -- How fast to rotate towards target
	AccelerationTime = 0.3,         -- How fast to accelerate to target speed
	StopDistance = 3,               -- Distance at which to start slowing down
	IdleChance = 0.2,               -- Chance to idle instead of moving to new target
	IdleDuration = 2,               -- How long to idle (seconds)
}

-- === SPAWNING ===

-- Find the entity model in Prefab folder
local function findEntityModel()
	local prefabFolder = ReplicatedStorage:FindFirstChild(ENEMY_CONFIG.PrefabFolderName)
	if not prefabFolder then
		warn(string.format("[HumanEnemyService] Prefab folder not found in ReplicatedStorage"))
		return nil
	end
	
	-- Search for a model with the "entity" tag
	for _, child in ipairs(prefabFolder:GetChildren()) do
		if child:IsA("Model") and CollectionService:HasTag(child, ENEMY_CONFIG.EntityTag) then
			warn(string.format("[HumanEnemyService] Found entity model: %s", child.Name))
			return child
		end
	end
	
	warn(string.format("[HumanEnemyService] No model with '%s' tag found in Prefab folder", ENEMY_CONFIG.EntityTag))
	return nil
end

-- Calculate positions in a circle
local function calculateCirclePositions(center, radius, count)
	local positions = {}
	local angleStep = (math.pi * 2) / count
	
	for i = 1, count do
		local angle = (i - 1) * angleStep
		local x = center.X + math.cos(angle) * radius
		local z = center.Z + math.sin(angle) * radius
		-- Y will be set based on terrain height
		table.insert(positions, Vector3.new(x, center.Y, z))
	end
	
	return positions
end

-- === TERRAIN HEIGHT LOOKUP (via CubeTerrainService - no raycasting) ===

-- Cache for CubeTerrainService reference
local _cubeTerrainService = nil

local function getCubeTerrainService()
	if not _cubeTerrainService then
		pcall(function()
			_cubeTerrainService = Knit.GetService("CubeTerrainService")
		end)
	end
	return _cubeTerrainService
end

-- Get terrain surface height at position (uses CubeTerrainService direct lookup)
local function getGroundHeight(position)
	local terrainService = getCubeTerrainService()
	if terrainService then
		local height = terrainService:GetSurfaceHeightAt(position.X, position.Z)
		if height and height > 0 then
			return height
		end
	end
	
	-- Fallback to GridService height
	local GridService = nil
	pcall(function()
		GridService = Knit.GetService("GridService")
	end)
	
	if GridService then
		local gridData = GridService:GetGridData()
		if gridData and gridData.topY then
			return gridData.topY
		end
	end
	
	-- Legacy fallback
	return position.Y
end

-- Calculate the bottom offset of a model (for humanoid rigs)
local function getModelBottomOffset(model)
	-- For humanoid rigs, find the lowest part
	local lowestY = math.huge
	local humanoidRootPart = model:FindFirstChild("HumanoidRootPart")
	
	if humanoidRootPart then
		-- Get all parts in the model
		for _, part in ipairs(model:GetDescendants()) do
			if part:IsA("BasePart") and part ~= humanoidRootPart then
				-- Calculate relative position to HumanoidRootPart
				local relativePos = humanoidRootPart.CFrame:PointToObjectSpace(part.Position)
				local bottomY = relativePos.Y - (part.Size.Y / 2)
				lowestY = math.min(lowestY, bottomY)
			end
		end
		
		-- If we found parts, return the offset (negative because it's below)
		if lowestY ~= math.huge then
			return math.abs(lowestY)
		end
		
		-- Fallback: estimate based on typical humanoid size
		return 3  -- Typical humanoid is about 6 studs tall, so 3 studs from center to bottom
	end
	
	-- For non-humanoid models, try to find the bounding box
	if model.PrimaryPart then
		local boundingBox = model:GetBoundingBox()
		local size = boundingBox.Size
		return size.Y / 2
	end
	
	-- Default offset
	return 0
end

-- === PHYSICS CONSTRAINTS ===

-- Create physics constraints for an enemy (LinearVelocity + AlignOrientation)
local function createMovementConstraints(humanoidRootPart)
	-- Create attachment for constraints
	local attachment = Instance.new("Attachment")
	attachment.Name = "MovementAttachment"
	attachment.Parent = humanoidRootPart
	
	-- LinearVelocity for movement (horizontal only)
	local linearVelocity = Instance.new("LinearVelocity")
	linearVelocity.Name = "WanderLinearVelocity"
	linearVelocity.Attachment0 = attachment
	linearVelocity.MaxForce = ENEMY_CONFIG.MaxForce
	linearVelocity.VelocityConstraintMode = Enum.VelocityConstraintMode.Plane
	linearVelocity.PrimaryTangentAxis = Vector3.new(1, 0, 0)
	linearVelocity.SecondaryTangentAxis = Vector3.new(0, 0, 1)
	linearVelocity.PlaneVelocity = Vector2.new(0, 0)  -- Start stationary
	linearVelocity.Parent = humanoidRootPart
	
	-- AlignOrientation to face movement direction
	local alignOrientation = Instance.new("AlignOrientation")
	alignOrientation.Name = "WanderAlignOrientation"
	alignOrientation.Attachment0 = attachment
	alignOrientation.Mode = Enum.OrientationAlignmentMode.OneAttachment
	alignOrientation.MaxTorque = ENEMY_CONFIG.MaxTorque
	alignOrientation.Responsiveness = ENEMY_CONFIG.TurnResponsiveness
	alignOrientation.CFrame = humanoidRootPart.CFrame  -- Start facing current direction
	alignOrientation.Parent = humanoidRootPart
	
	return {
		attachment = attachment,
		linearVelocity = linearVelocity,
		alignOrientation = alignOrientation,
	}
end

-- Update constraint to move towards target position
local function updateMovementConstraint(enemyData, deltaTime)
	local constraints = enemyData.constraints
	if not constraints then return end
	
	local linearVelocity = constraints.linearVelocity
	local alignOrientation = constraints.alignOrientation
	local humanoidRootPart = enemyData.humanoidRootPart
	
	if not linearVelocity or not alignOrientation or not humanoidRootPart then return end
	if not humanoidRootPart.Parent then return end
	
	-- Check if idling
	if enemyData.isIdling then
		-- Gradually slow down
		local currentVel = linearVelocity.PlaneVelocity
		local damping = 1 - (deltaTime * 5)
		linearVelocity.PlaneVelocity = currentVel * damping
		return
	end
	
	local target = enemyData.currentTarget
	if not target then
		-- No target, slow down
		local currentVel = linearVelocity.PlaneVelocity
		local damping = 1 - (deltaTime * 5)
		linearVelocity.PlaneVelocity = currentVel * damping
		return
	end
	
	local currentPos = humanoidRootPart.Position
	local toTarget = target - currentPos
	local horizontalDir = Vector3.new(toTarget.X, 0, toTarget.Z)
	local distance = horizontalDir.Magnitude
	
	if distance < 0.1 then
		-- At target
		linearVelocity.PlaneVelocity = Vector2.new(0, 0)
		return
	end
	
	local direction = horizontalDir.Unit
	
	-- Calculate target speed based on distance (slow down when close)
	local targetSpeed = ENEMY_CONFIG.WalkSpeed
	if distance < ENEMY_CONFIG.StopDistance then
		targetSpeed = targetSpeed * (distance / ENEMY_CONFIG.StopDistance)
	end
	
	-- Current velocity
	local currentVel = linearVelocity.PlaneVelocity
	local targetVel = Vector2.new(direction.X * targetSpeed, direction.Z * targetSpeed)
	
	-- Smooth acceleration
	local lerpFactor = math.min(1, deltaTime / ENEMY_CONFIG.AccelerationTime)
	local newVel = currentVel:Lerp(targetVel, lerpFactor)
	linearVelocity.PlaneVelocity = newVel
	
	-- Update facing direction (only if moving)
	if newVel.Magnitude > 0.5 then
		local facingDir = Vector3.new(newVel.X, 0, newVel.Y).Unit
		local lookAt = currentPos + facingDir
		alignOrientation.CFrame = CFrame.lookAt(currentPos, lookAt)
	end
end

-- Clean up constraints for an enemy
local function cleanupConstraints(constraints)
	if not constraints then return end
	
	if constraints.linearVelocity then
		constraints.linearVelocity:Destroy()
	end
	if constraints.alignOrientation then
		constraints.alignOrientation:Destroy()
	end
	if constraints.attachment then
		constraints.attachment:Destroy()
	end
end

-- Spawn enemies in a circle
local function spawnEnemiesInCircle(self)
	local entityModel = findEntityModel()
	if not entityModel then
		return
	end
	
	-- Calculate circle positions
	local positions = calculateCirclePositions(
		ENEMY_CONFIG.CenterPosition,
		ENEMY_CONFIG.CircleRadius,
		ENEMY_CONFIG.Count
	)
	
	-- Create folder for spawned enemies
	local enemyFolder = Workspace:FindFirstChild("SpawnedEnemies")
	if not enemyFolder then
		enemyFolder = Instance.new("Folder")
		enemyFolder.Name = "SpawnedEnemies"
		enemyFolder.Parent = Workspace
	end
	
	-- Spawn each enemy
	for i, position in ipairs(positions) do
		-- Clone the model first (before parenting) to calculate offsets
		local clone = entityModel:Clone()
		clone.Name = string.format("%s_%d", entityModel.Name, i)
		
		-- Get ground height
		local groundY = getGroundHeight(position)
		
		-- Calculate bottom offset for proper positioning
		local bottomOffset = getModelBottomOffset(clone)
		
		-- Calculate spawn position: ground + offset + bottom offset
		-- This ensures the enemy's feet are on the ground
		local spawnY = groundY + ENEMY_CONFIG.GroundOffset + bottomOffset
		local spawnPosition = Vector3.new(position.X, spawnY, position.Z)
		
		-- Position the enemy
		if clone.PrimaryPart then
			clone:SetPrimaryPartCFrame(CFrame.new(spawnPosition))
		elseif clone:FindFirstChild("HumanoidRootPart") then
			-- For humanoid rigs, position the HumanoidRootPart
			clone.HumanoidRootPart.Position = spawnPosition
			
			-- Ensure the humanoid is properly set up
			local humanoid = clone:FindFirstChildOfClass("Humanoid")
			if humanoid then
				-- Make sure the humanoid is not in a weird state
				humanoid.PlatformStand = false
			end
		else
			-- Try to find any BasePart and position it
			for _, part in ipairs(clone:GetDescendants()) do
				if part:IsA("BasePart") then
					part.Position = spawnPosition
					break
				end
			end
		end
		
		-- Parent to workspace (after positioning)
		clone.Parent = enemyFolder
		
		-- Add tag
		CollectionService:AddTag(clone, ENEMY_CONFIG.EntityTag)
		
		-- Get humanoid and setup
		local humanoid = clone:FindFirstChildOfClass("Humanoid")
		local humanoidRootPart = clone:FindFirstChild("HumanoidRootPart")
		
		-- Create physics constraints for movement
		local constraints = nil
		if humanoidRootPart then
			constraints = createMovementConstraints(humanoidRootPart)
		end
		
		if humanoid then
			-- Disable humanoid auto-movement (we use constraints instead)
			humanoid.WalkSpeed = 0  -- Disable built-in walking
			humanoid:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)
			humanoid:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, false)
			-- Keep the humanoid for animations but movement is via constraints
		end
		
		-- Store enemy data
		local enemyData = {
			model = clone,
			humanoid = humanoid,
			humanoidRootPart = humanoidRootPart,
			constraints = constraints,
			spawnPosition = spawnPosition,
			currentTarget = nil,
			lastWanderTime = 0,
			lastPosition = spawnPosition,
			lastPositionTime = 0,
			isIdling = false,
			idleEndTime = 0,
		}
		
		table.insert(self._enemies, enemyData)
		
		--[[print(string.format("[HumanEnemyService] Spawned enemy %d at (%.1f, %.1f, %.1f) with physics constraints", 
			i, spawnPosition.X, spawnPosition.Y, spawnPosition.Z))]]
	end
	
	--[[print(string.format("[HumanEnemyService] Spawned %d enemies in a circle", #self._enemies))]]
	
	-- Wait a bit for models to be fully replicated to clients
	task.wait(1)
	
	-- Fire signal to all clients that enemies were created
	-- Clients will find entities via CollectionService using the "entity" tag
	self.Client.EnemyCreated:FireAll()
	--("[HumanEnemyService] Fired EnemyCreated signal")
end

-- === WANDERING (PHYSICS-BASED) ===

-- Find a random wander destination
local function findWanderDestination(spawnPosition, currentPosition)
	-- Sometimes wander relative to current position, sometimes back towards spawn
	local basePos = math.random() < 0.3 and spawnPosition or currentPosition
	
	local angle = math.random() * math.pi * 2
	local distance = math.random(ENEMY_CONFIG.WanderMinDistance, ENEMY_CONFIG.WanderRadius)
	
	local targetX = basePos.X + math.cos(angle) * distance
	local targetZ = basePos.Z + math.sin(angle) * distance
	
	-- Clamp to wander radius from spawn
	local offsetFromSpawn = Vector3.new(targetX - spawnPosition.X, 0, targetZ - spawnPosition.Z)
	if offsetFromSpawn.Magnitude > ENEMY_CONFIG.WanderRadius then
		offsetFromSpawn = offsetFromSpawn.Unit * ENEMY_CONFIG.WanderRadius
		targetX = spawnPosition.X + offsetFromSpawn.X
		targetZ = spawnPosition.Z + offsetFromSpawn.Z
	end
	
	-- Get terrain surface height at target (using CubeTerrainService - no raycast)
	local terrainService = getCubeTerrainService()
	if terrainService then
		local terrainY = terrainService:GetSurfaceHeightAt(targetX, targetZ)
		if terrainY and terrainY > 0 then
			return Vector3.new(targetX, terrainY, targetZ)
		end
	end
	
	-- Fallback to spawn position height
	return Vector3.new(targetX, spawnPosition.Y, targetZ)
end

-- Store deltaTime for constraint updates
local _lastUpdateTime = 0

-- Update wandering for all enemies using physics constraints
local function updateWandering(self, currentTime)
	local deltaTime = currentTime - _lastUpdateTime
	_lastUpdateTime = currentTime
	
	-- Clamp deltaTime to avoid huge jumps
	deltaTime = math.min(deltaTime, 0.1)
	
	for _, enemyData in ipairs(self._enemies) do
		if not enemyData.model or not enemyData.model.Parent then
			continue
		end
		
		local humanoidRootPart = enemyData.humanoidRootPart
		
		if not humanoidRootPart or not humanoidRootPart.Parent then
			continue
		end
		
		-- Check if currently idling
		if enemyData.isIdling then
			if currentTime >= enemyData.idleEndTime then
				-- Done idling
				enemyData.isIdling = false
			else
				-- Continue idling, just update constraints to slow down
				updateMovementConstraint(enemyData, deltaTime)
				continue
			end
		end
		
		-- Check if enemy is stuck (not moving)
		local currentPos = humanoidRootPart.Position
		local distanceMoved = (currentPos - enemyData.lastPosition).Magnitude
		
		if distanceMoved < 0.5 then  -- Moved less than 0.5 studs
			if enemyData.lastPositionTime == 0 then
				enemyData.lastPositionTime = currentTime
			elseif currentTime - enemyData.lastPositionTime >= ENEMY_CONFIG.WanderMaxStuckTime then
				-- Stuck for too long, choose new destination
				enemyData.currentTarget = nil
				enemyData.lastPositionTime = 0
			end
		else
			-- Moving, reset stuck timer
			enemyData.lastPosition = currentPos
			enemyData.lastPositionTime = 0
		end
		
		-- Check if it's time to choose a new destination
		local shouldChooseNew = false
		if not enemyData.currentTarget then
			shouldChooseNew = true
		else
			local toTarget = enemyData.currentTarget - currentPos
			local horizontalDist = Vector3.new(toTarget.X, 0, toTarget.Z).Magnitude
			
			if horizontalDist < ENEMY_CONFIG.StopDistance then
				-- Reached target
				shouldChooseNew = true
			elseif currentTime - enemyData.lastWanderTime >= ENEMY_CONFIG.WanderInterval then
				-- Time interval passed, choose new destination even if not reached
				shouldChooseNew = true
			end
		end
		
		if shouldChooseNew then
			-- Maybe idle instead of immediately moving
			if math.random() < ENEMY_CONFIG.IdleChance then
				enemyData.isIdling = true
				enemyData.idleEndTime = currentTime + ENEMY_CONFIG.IdleDuration * (0.5 + math.random())
				enemyData.currentTarget = nil
				enemyData.lastWanderTime = currentTime
			else
				-- Find new destination
				local newTarget = findWanderDestination(enemyData.spawnPosition, currentPos)
				enemyData.currentTarget = newTarget
				enemyData.lastWanderTime = currentTime
				enemyData.lastPosition = currentPos
				enemyData.lastPositionTime = 0
			end
		end
		
		-- Update physics constraints to move towards target
		updateMovementConstraint(enemyData, deltaTime)
	end
end

-- === KNIT LIFECYCLE ===

function HumanEnemyService:KnitInit()
	--("[HumanEnemyService] Initializing...")
end

function HumanEnemyService:KnitStart()
	-- Start wandering loop (runs even if enemies are spawned by ReservedZoneService)
	local startTime = tick()
	RunService.Heartbeat:Connect(function()
		local currentTime = tick() - startTime
		updateWandering(self, currentTime)
	end)
	
	-- Only auto-spawn if _autoSpawn is true (legacy mode)
	if self._autoSpawn then
		task.wait(1)
		spawnEnemiesInCircle(self)
	else
		--("[HumanEnemyService] Waiting for ReservedZoneService to spawn enemies...")
	end
	
	--("[HumanEnemyService] Started!")
end

-- === PUBLIC API ===

function HumanEnemyService:GetSpawnedEnemies()
	return self._enemies
end

function HumanEnemyService:GetEnemyCount()
	return #self._enemies
end

function HumanEnemyService:GetEnemyModels()
	-- Return just the enemy models
	local models = {}
	for _, enemyData in ipairs(self._enemies) do
		if enemyData.model then
			table.insert(models, enemyData.model)
		end
	end
	return models
end

-- Remove an enemy and clean up its constraints
function HumanEnemyService:RemoveEnemy(enemyModel)
	for i, enemyData in ipairs(self._enemies) do
		if enemyData.model == enemyModel then
			-- Clean up constraints
			cleanupConstraints(enemyData.constraints)
			
			-- Remove model
			if enemyData.model then
				enemyData.model:Destroy()
			end
			
			-- Remove from list
			table.remove(self._enemies, i)
			--("[HumanEnemyService] Removed enemy and cleaned up constraints")
			return true
		end
	end
	return false
end

-- Remove all enemies
function HumanEnemyService:RemoveAllEnemies()
	for _, enemyData in ipairs(self._enemies) do
		cleanupConstraints(enemyData.constraints)
		if enemyData.model then
			enemyData.model:Destroy()
		end
	end
	self._enemies = {}
	--("[HumanEnemyService] Removed all enemies")
end

-- Spawn enemies at a specific location (called by ReservedZoneService)
function HumanEnemyService:SpawnEnemiesAt(centerPosition, radius, count)
	local entityModel = findEntityModel()
	if not entityModel then
		warn("[HumanEnemyService] No entity model found for SpawnEnemiesAt")
		return {}
	end
	
	-- Create folder for spawned enemies if it doesn't exist
	local enemyFolder = Workspace:FindFirstChild("SpawnedEnemies")
	if not enemyFolder then
		enemyFolder = Instance.new("Folder")
		enemyFolder.Name = "SpawnedEnemies"
		enemyFolder.Parent = Workspace
	end
	
	-- Calculate positions in a circle
	local positions = calculateCirclePositions(centerPosition, radius, count)
	local spawnedEnemies = {}
	
	for i, position in ipairs(positions) do
		-- Clone the model
		local clone = entityModel:Clone()
		clone.Name = string.format("%s_Zone_%d", entityModel.Name, i)
		
		-- Get ground height
		local groundY = getGroundHeight(position)
		
		-- Calculate bottom offset
		local bottomOffset = getModelBottomOffset(clone)
		
		-- Calculate spawn position
		local spawnY = groundY + ENEMY_CONFIG.GroundOffset + bottomOffset
		local spawnPosition = Vector3.new(position.X, spawnY, position.Z)
		
		-- Position the enemy
		if clone.PrimaryPart then
			clone:SetPrimaryPartCFrame(CFrame.new(spawnPosition))
		elseif clone:FindFirstChild("HumanoidRootPart") then
			clone.HumanoidRootPart.Position = spawnPosition
			local humanoid = clone:FindFirstChildOfClass("Humanoid")
			if humanoid then
				humanoid.PlatformStand = false
			end
		else
			for _, part in ipairs(clone:GetDescendants()) do
				if part:IsA("BasePart") then
					part.Position = spawnPosition
					break
				end
			end
		end
		
		-- Parent to workspace
		clone.Parent = enemyFolder
		
		-- Add tag
		CollectionService:AddTag(clone, ENEMY_CONFIG.EntityTag)
		
		-- Get humanoid and setup
		local humanoid = clone:FindFirstChildOfClass("Humanoid")
		local humanoidRootPart = clone:FindFirstChild("HumanoidRootPart")
		
		-- Create physics constraints for movement
		local constraints = nil
		if humanoidRootPart then
			constraints = createMovementConstraints(humanoidRootPart)
		end
		
		if humanoid then
			-- Disable humanoid auto-movement (we use constraints instead)
			humanoid.WalkSpeed = 0  -- Disable built-in walking
			humanoid:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)
			humanoid:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, false)
		end
		
		-- Store enemy data
		local enemyData = {
			model = clone,
			humanoid = humanoid,
			humanoidRootPart = humanoidRootPart,
			constraints = constraints,
			spawnPosition = spawnPosition,
			currentTarget = nil,
			lastWanderTime = 0,
			lastPosition = spawnPosition,
			lastPositionTime = 0,
			isIdling = false,
			idleEndTime = 0,
		}
		
		table.insert(self._enemies, enemyData)
		table.insert(spawnedEnemies, enemyData)
		
		--[[print(string.format("[HumanEnemyService] Spawned zone enemy %d at (%.1f, %.1f, %.1f) with physics constraints", 
			i, spawnPosition.X, spawnPosition.Y, spawnPosition.Z))]]
	end
	
	--[[print(string.format("[HumanEnemyService] Spawned %d enemies at zone center (%.1f, %.1f, %.1f) using physics constraints", 
		#spawnedEnemies, centerPosition.X, centerPosition.Y, centerPosition.Z))]]
	
	-- Fire signal
	task.delay(1, function()
		self.Client.EnemyCreated:FireAll()
	end)
	
	return spawnedEnemies
end

return HumanEnemyService

