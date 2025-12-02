--[[
	HumanEnemyService
	Spawns humanoid enemies from ReplicatedStorage.Prefab in a circle formation
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
	_enemies = {},  -- Track spawned enemies with data: { model, humanoid, humanoidRootPart, currentTarget, lastWanderTime }
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
	WanderInterval = 2,             -- Time between choosing new destinations (seconds)
	WanderMinDistance = 10,         -- Minimum distance for new destination
	WanderMaxStuckTime = 3,         -- Max time stuck before choosing new destination (seconds)
	WalkSpeed = 8,                  -- Walking speed for humanoids
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

-- Raycast to find ground height
local function getGroundHeight(position)
	local rayOrigin = Vector3.new(position.X, 500, position.Z)
	local rayDirection = Vector3.new(0, -1000, 0)
	
	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Blacklist
	local excludeList = {}
	
	-- Exclude trees, formations, and spawned enemies
	local treesFolder = Workspace:FindFirstChild("Trees")
	if treesFolder then table.insert(excludeList, treesFolder) end
	
	local formationsFolder = Workspace:FindFirstChild("AlienFormations")
	if formationsFolder then table.insert(excludeList, formationsFolder) end
	
	local spawnedEnemiesFolder = Workspace:FindFirstChild("SpawnedEnemies")
	if spawnedEnemiesFolder then table.insert(excludeList, spawnedEnemiesFolder) end
	
	raycastParams.FilterDescendantsInstances = excludeList
	
	local raycastResult = Workspace:Raycast(rayOrigin, rayDirection, raycastParams)
	
	if raycastResult then
		return raycastResult.Position.Y
	else
		-- Fallback to GridService/TerrainService height
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
		
		-- Legacy fallback to baseplate height
		local baseplate = Workspace:FindFirstChild("Baseplate")
		if baseplate and baseplate:IsA("BasePart") then
			return baseplate.Position.Y + baseplate.Size.Y / 2
		end
		return position.Y
	end
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
		
		if humanoid then
			-- Set walk speed
			humanoid.WalkSpeed = ENEMY_CONFIG.WalkSpeed
			-- Enable pathfinding
			humanoid:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)
			humanoid:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, false)
		end
		
		-- Store enemy data
		local enemyData = {
			model = clone,
			humanoid = humanoid,
			humanoidRootPart = humanoidRootPart,
			spawnPosition = spawnPosition,
			currentTarget = nil,
			lastWanderTime = 0,
			lastPosition = spawnPosition,
			lastPositionTime = 0,
		}
		
		table.insert(self._enemies, enemyData)
		
		print(string.format("[HumanEnemyService] Spawned enemy %d at (%.1f, %.1f, %.1f) (ground: %.1f, offset: %.1f)", 
			i, spawnPosition.X, spawnPosition.Y, spawnPosition.Z, groundY, bottomOffset))
	end
	
	print(string.format("[HumanEnemyService] Spawned %d enemies in a circle", #self._enemies))
	
	-- Wait a bit for models to be fully replicated to clients
	task.wait(1)
	
	-- Fire signal to all clients that enemies were created
	-- Clients will find entities via CollectionService using the "entity" tag
	self.Client.EnemyCreated:FireAll()
	print("[HumanEnemyService] Fired EnemyCreated signal")
end

-- === WANDERING ===

-- Find a random wander destination
local function findWanderDestination(spawnPosition)
	local angle = math.random() * math.pi * 2
	local distance = math.random(ENEMY_CONFIG.WanderMinDistance, ENEMY_CONFIG.WanderRadius)
	
	local targetX = spawnPosition.X + math.cos(angle) * distance
	local targetZ = spawnPosition.Z + math.sin(angle) * distance
	
	-- Raycast to find ground height at target
	local rayOrigin = Vector3.new(targetX, 500, targetZ)
	local rayDirection = Vector3.new(0, -1000, 0)
	
	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Blacklist
	local excludeList = {}
	
	local treesFolder = Workspace:FindFirstChild("Trees")
	if treesFolder then table.insert(excludeList, treesFolder) end
	
	local formationsFolder = Workspace:FindFirstChild("AlienFormations")
	if formationsFolder then table.insert(excludeList, formationsFolder) end
	
	local spawnedEnemiesFolder = Workspace:FindFirstChild("SpawnedEnemies")
	if spawnedEnemiesFolder then table.insert(excludeList, spawnedEnemiesFolder) end
	
	raycastParams.FilterDescendantsInstances = excludeList
	
	local raycastResult = Workspace:Raycast(rayOrigin, rayDirection, raycastParams)
	
	if raycastResult then
		return raycastResult.Position
	else
		-- Fallback to spawn position height
		return Vector3.new(targetX, spawnPosition.Y, targetZ)
	end
end

-- Update wandering for all enemies
local function updateWandering(self, currentTime)
	for _, enemyData in ipairs(self._enemies) do
		if not enemyData.model or not enemyData.model.Parent then
			continue
		end
		
		local humanoid = enemyData.humanoid
		local humanoidRootPart = enemyData.humanoidRootPart
		
		if not humanoid or not humanoidRootPart then
			continue
		end
		
		-- Check if enemy is stuck (not moving)
		local currentPos = humanoidRootPart.Position
		local distanceMoved = (currentPos - enemyData.lastPosition).Magnitude
		
		if distanceMoved < 1 then  -- Moved less than 1 stud
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
		elseif (humanoidRootPart.Position - enemyData.currentTarget).Magnitude < 5 then
			-- Reached target
			shouldChooseNew = true
		elseif currentTime - enemyData.lastWanderTime >= ENEMY_CONFIG.WanderInterval then
			-- Time interval passed, choose new destination even if not reached
			shouldChooseNew = true
		end
		
		if shouldChooseNew then
			-- Find new destination
			local newTarget = findWanderDestination(enemyData.spawnPosition)
			enemyData.currentTarget = newTarget
			enemyData.lastWanderTime = currentTime
			enemyData.lastPosition = currentPos
			enemyData.lastPositionTime = 0
			
			-- Use NavMesh to move to destination
			humanoid:MoveTo(newTarget)
		end
		
		-- Keep moving if we have a target
		if enemyData.currentTarget then
			-- Check if we're stuck (not moving towards target)
			local distanceToTarget = (humanoidRootPart.Position - enemyData.currentTarget).Magnitude
			if distanceToTarget > 5 then
				-- Re-issue move command periodically to ensure navigation
				if math.random() < 0.1 then  -- 10% chance each frame
					humanoid:MoveTo(enemyData.currentTarget)
				end
			end
		end
	end
end

-- === KNIT LIFECYCLE ===

function HumanEnemyService:KnitInit()
	print("[HumanEnemyService] Initializing...")
end

function HumanEnemyService:KnitStart()
	-- Wait a bit for other services to initialize
	task.wait(1)
	
	-- Spawn enemies
	spawnEnemiesInCircle(self)
	
	-- Start wandering loop
	local startTime = tick()
	RunService.Heartbeat:Connect(function()
		local currentTime = tick() - startTime
		updateWandering(self, currentTime)
	end)
	
	print("[HumanEnemyService] Started!")
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

return HumanEnemyService

