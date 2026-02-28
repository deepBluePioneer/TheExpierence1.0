local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local Workspace = game:GetService("Workspace")

local Packages = ReplicatedStorage.Packages
local Knit = require(Packages.Knit)
local Signal = require(Packages.Signal)
local Trove = require(Packages.Trove)
local Timer = require(Packages.timer)
local PartCache = require(Packages.partcache)

local PatchesConfig = require(ReplicatedStorage.Source.PatchesConfig)
local Analytics = require(ReplicatedStorage.Source.Analytics)

local CityTrialPatchSpawnService = Knit.CreateService {
	Name = "CityTrialPatchSpawnService",
	Client = {},

	_trove = nil,
	_cache = nil,
	_activePatches = {},
	_activePatchCount = 0,
	_patchBudget = PatchesConfig.targetPatchCount,
	_spawnBounds = nil,
	_killPlaneY = -50,
	_enabled = false,

	PatchCollected = Signal.new(),
	PatchSpawned = Signal.new(),
}

local PATCH_SIZE = Vector3.new(3, 3, 3)
local PATCH_FOLDER_NAME = "PatchParts"
local COLLECTION_RADIUS = 12

----------------------------------------------------------------
-- Weighted random type selection
----------------------------------------------------------------

local _weightedPool = {}
local _totalWeight = 0

local function buildWeightedPool()
	_weightedPool = {}
	_totalWeight = 0
	for patchType, config in pairs(PatchesConfig.patches) do
		_totalWeight = _totalWeight + (config.spawnWeight or 1)
		table.insert(_weightedPool, {
			patchType = patchType,
			cumulativeWeight = _totalWeight,
		})
	end
end

local function getRandomPatchType()
	local roll = math.random() * _totalWeight
	for _, entry in ipairs(_weightedPool) do
		if roll <= entry.cumulativeWeight then
			return entry.patchType
		end
	end
	return _weightedPool[#_weightedPool].patchType
end

----------------------------------------------------------------
-- Template part
----------------------------------------------------------------

local function createTemplatePart()
	local part = Instance.new("Part")
	part.Name = "Patch"
	part.Size = PATCH_SIZE
	part.Shape = Enum.PartType.Ball
	part.Material = Enum.Material.Neon
	part.Color = Color3.fromRGB(255, 255, 255)
	part.Anchored = false
	part.CanCollide = true
	part.CanQuery = true
	part.CanTouch = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.CustomPhysicalProperties = PhysicalProperties.new(
		0.5,  -- Density
		0.0,  -- Friction (zero so bounces stay vertical)
		0.8,  -- Elasticity (high = bouncy)
		1.0,  -- FrictionWeight
		1.0   -- ElasticityWeight
	)
	part.CFrame = CFrame.new(0, 10e8, 0)

	-- Lock horizontal axes so patch only moves vertically
	local attachment = Instance.new("Attachment")
	attachment.Name = "PatchAttachment"
	attachment.Parent = part

	local linearVelocity = Instance.new("LinearVelocity")
	linearVelocity.Name = "HorizontalLock"
	linearVelocity.Attachment0 = attachment
	linearVelocity.VelocityConstraintMode = Enum.VelocityConstraintMode.Plane
	linearVelocity.PrimaryTangentAxis = Vector3.new(1, 0, 0)
	linearVelocity.SecondaryTangentAxis = Vector3.new(0, 0, 1)
	linearVelocity.PlaneVelocity = Vector2.new(0, 0)
	linearVelocity.MaxForce = math.huge
	linearVelocity.RelativeTo = Enum.ActuatorRelativeTo.World
	linearVelocity.Parent = part

	local highlight = Instance.new("Highlight")
	highlight.FillTransparency = 0.3
	highlight.OutlineTransparency = 0
	highlight.OutlineColor = Color3.fromRGB(255, 255, 255)
	highlight.Parent = part

	return part
end

----------------------------------------------------------------
-- Service lifecycle
----------------------------------------------------------------

function CityTrialPatchSpawnService:KnitInit()
	self._trove = Trove.new()
	buildWeightedPool()
end

function CityTrialPatchSpawnService:KnitStart()
	local matchService = Knit.GetService("CityTrialMatchService")

	matchService.MatchStarted:Connect(function()
		self:StartSpawning()
	end)

	matchService.MatchEnded:Connect(function()
		self:StopSpawning()
	end)
end

function CityTrialPatchSpawnService:StartSpawning()
	if self._enabled then return end
	self._enabled = true

	self:_initCache()
	self:_detectSpawnBounds()

	print("[PatchSpawnService] Starting patch spawns (budget: " .. self._patchBudget .. ")")

	local staggerInterval = PatchesConfig.spawn.initialBatchStaggerSeconds / self._patchBudget
	for i = 1, self._patchBudget do
		task.delay(staggerInterval * (i - 1), function()
			if self._enabled then
				self:_spawnPatch()
			end
		end)
	end
end

function CityTrialPatchSpawnService:StopSpawning()
	self._enabled = false
	self:_reclaimAll()
	print("[PatchSpawnService] Stopped, all patches reclaimed")
end

function CityTrialPatchSpawnService:_initCache()
	if self._cache then return end

	local template = createTemplatePart()

	local folder = Instance.new("Folder")
	folder.Name = PATCH_FOLDER_NAME
	folder.Parent = Workspace

	self._cache = PartCache.new(template, self._patchBudget + 20, folder)
	self._trove:Add(function()
		self._cache:Dispose()
		folder:Destroy()
	end)
end

function CityTrialPatchSpawnService:_detectSpawnBounds()
	local boundsPart = CollectionService:GetTagged("PatchSpawnBounds")[1]
	if boundsPart and boundsPart:IsA("BasePart") then
		local pos = boundsPart.Position
		local halfSize = boundsPart.Size / 2
		self._spawnBounds = {
			minX = pos.X - halfSize.X,
			maxX = pos.X + halfSize.X,
			minZ = pos.Z - halfSize.Z,
			maxZ = pos.Z + halfSize.Z,
		}
		print("[PatchSpawnService] Using PatchSpawnBounds part: " .. boundsPart:GetFullName())
	else
		self._spawnBounds = {
			minX = -200,
			maxX = 200,
			minZ = -200,
			maxZ = 200,
		}
		warn("[PatchSpawnService] No PatchSpawnBounds tagged part found, using default 400x400 area")
	end

	local killPlane = CollectionService:GetTagged("KillPlane")[1]
	if killPlane and killPlane:IsA("BasePart") then
		self._killPlaneY = killPlane.Position.Y
	end
end

----------------------------------------------------------------
-- Spawn logic
----------------------------------------------------------------

function CityTrialPatchSpawnService:_spawnPatch()
	if not self._enabled then return end
	if self._activePatchCount >= self._patchBudget then return end

	local patchType = getRandomPatchType()
	local config = PatchesConfig.patches[patchType]
	if not config then return end

	local spawnPos = self:_getRandomSpawnPosition()
	if not spawnPos then return end

	local part = self._cache:GetPart()
	if not part then
		warn("[PatchSpawnService] Cache exhausted")
		return
	end

	part.Color = config.color
	part.Name = "Patch_" .. patchType

	local highlight = part:FindFirstChildOfClass("Highlight")
	if highlight then
		highlight.FillColor = config.color
		highlight.OutlineColor = config.color
	end

	part.CFrame = CFrame.new(spawnPos)
	part.Anchored = false
	part.Velocity = Vector3.zero

	local patchId = tostring(part) .. "_" .. os.clock()

	local patchData = {
		id = patchId,
		part = part,
		patchType = patchType,
		collected = false,
		spawnTime = os.clock(),
	}

	self._activePatches[patchId] = patchData
	self._activePatchCount = self._activePatchCount + 1

	-- Touch detection for collection
	local touchConn
	touchConn = part.Touched:Connect(function(hit)
		if patchData.collected then return end

		local character = hit.Parent
		if not character then return end
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if not humanoid then return end

		local player = Players:GetPlayerFromCharacter(character)
		if not player then return end

		self:_collectPatch(patchId, player)
	end)
	patchData.touchConn = touchConn

	-- Landing timeout
	local timeoutTimer = Timer.new(1)
	local elapsed = 0
	timeoutTimer.Tick:Connect(function()
		elapsed = elapsed + 1

		if patchData.collected then
			timeoutTimer:Stop()
			timeoutTimer:Destroy()
			return
		end

		if part.Position.Y < self._killPlaneY then
			timeoutTimer:Stop()
			timeoutTimer:Destroy()
			self:_reclaimPatch(patchId, true)
			return
		end

		if elapsed >= PatchesConfig.spawn.landingTimeout then
			timeoutTimer:Stop()
			timeoutTimer:Destroy()

			if not patchData.collected then
				self:_validateLanding(patchId)
			end
		end
	end)
	timeoutTimer:Start()
	patchData.timeoutTimer = timeoutTimer

	self.PatchSpawned:Fire(patchType, spawnPos)
end

function CityTrialPatchSpawnService:_getRandomSpawnPosition()
	local bounds = self._spawnBounds
	local spawnConfig = PatchesConfig.spawn

	for _ = 1, spawnConfig.maxRetries do
		local x = math.random() * (bounds.maxX - bounds.minX) + bounds.minX
		local z = math.random() * (bounds.maxZ - bounds.minZ) + bounds.minZ

		local rayOrigin = Vector3.new(x, 500, z)
		local rayDir = Vector3.new(0, -1000, 0)

		local rayParams = RaycastParams.new()
		rayParams.FilterType = Enum.RaycastFilterType.Exclude
		rayParams.FilterDescendantsInstances = { Workspace:FindFirstChild(PATCH_FOLDER_NAME) }

		local result = Workspace:Raycast(rayOrigin, rayDir, rayParams)
		if result then
			local groundY = result.Position.Y
			if groundY > self._killPlaneY then
				local spawnY = groundY + spawnConfig.altitudeOffset
				return Vector3.new(x, spawnY, z)
			end
		end
	end

	local fallbackX = (bounds.minX + bounds.maxX) / 2
	local fallbackZ = (bounds.minZ + bounds.maxZ) / 2
	return Vector3.new(fallbackX, spawnConfig.altitudeOffset + 50, fallbackZ)
end

function CityTrialPatchSpawnService:_validateLanding(patchId)
	local patchData = self._activePatches[patchId]
	if not patchData or patchData.collected then return end

	local part = patchData.part
	local pos = part.Position

	if pos.Y < self._killPlaneY then
		self:_reclaimPatch(patchId, true)
		return
	end

	local upRay = Workspace:Raycast(pos, Vector3.new(0, 1.5, 0))
	if upRay then
		self:_reclaimPatch(patchId, true)
		return
	end

	part.Anchored = true
end

----------------------------------------------------------------
-- Collection
----------------------------------------------------------------

function CityTrialPatchSpawnService:_collectPatch(patchId, player)
	local patchData = self._activePatches[patchId]
	if not patchData or patchData.collected then return end

	local part = patchData.part
	local character = player.Character
	if character then
		local rootPart = character:FindFirstChild("HumanoidRootPart")
		if rootPart then
			local dist = (rootPart.Position - part.Position).Magnitude
			if dist > COLLECTION_RADIUS then return end
		end
	end

	patchData.collected = true

	local patchType = patchData.patchType

	self:_reclaimPatch(patchId, false)

	self.PatchCollected:Fire(player, patchType)

	local CityTrialPlayerService = Knit.GetService("CityTrialPlayerService")
	local sessionData = CityTrialPlayerService:GetSessionData(player)
	if sessionData then
		sessionData.patchCounts[patchType] = (sessionData.patchCounts[patchType] or 0) + 1
		sessionData.totalPatchesCollected = (sessionData.totalPatchesCollected or 0) + 1

		local replica = CityTrialPlayerService:GetReplica(player)
		if replica then
			replica:SetValue({ "patchCounts" }, sessionData.patchCounts)
		end
	end

	local config = PatchesConfig.patches[patchType]
	local delay = config and config.respawnDelay or 5

	task.delay(delay, function()
		if self._enabled then
			self:_spawnPatch()
		end
	end)

	local total = sessionData and sessionData.totalPatchesCollected or 1
	Analytics.PatchCollected(player, patchType, total)
	if total == 1 then
		Analytics.Funnel.MatchFirstPatch(player)
	end
	print("[PatchSpawnService] " .. player.Name .. " collected " .. patchType .. " patch")
end

----------------------------------------------------------------
-- Reclaim
----------------------------------------------------------------

function CityTrialPatchSpawnService:_reclaimPatch(patchId, respawnImmediate)
	local patchData = self._activePatches[patchId]
	if not patchData then return end

	if patchData.touchConn then
		patchData.touchConn:Disconnect()
		patchData.touchConn = nil
	end

	if patchData.timeoutTimer then
		patchData.timeoutTimer:Stop()
		patchData.timeoutTimer:Destroy()
		patchData.timeoutTimer = nil
	end

	local part = patchData.part
	part.Anchored = true
	part.Velocity = Vector3.zero

	self._cache:ReturnPart(part)

	self._activePatches[patchId] = nil
	self._activePatchCount = math.max(0, self._activePatchCount - 1)

	if respawnImmediate and self._enabled then
		task.defer(function()
			self:_spawnPatch()
		end)
	end
end

function CityTrialPatchSpawnService:_reclaimAll()
	for patchId, _ in pairs(self._activePatches) do
		self:_reclaimPatch(patchId, false)
	end
	self._activePatches = {}
	self._activePatchCount = 0
end

----------------------------------------------------------------
-- Bonus wave (for events)
----------------------------------------------------------------

function CityTrialPatchSpawnService:SpawnBonusWave(extraCount, duration)
	if not self._enabled then return end

	local oldBudget = self._patchBudget
	self._patchBudget = self._patchBudget + extraCount

	local staggerInterval = duration / extraCount
	for i = 1, extraCount do
		task.delay(staggerInterval * (i - 1), function()
			if self._enabled then
				self:_spawnPatch()
			end
		end)
	end

	task.delay(duration + 5, function()
		self._patchBudget = oldBudget
	end)

	print("[PatchSpawnService] Bonus wave: +" .. extraCount .. " patches over " .. duration .. "s")
end

----------------------------------------------------------------
-- Public queries
----------------------------------------------------------------

function CityTrialPatchSpawnService:GetActivePatchCount()
	return self._activePatchCount
end

function CityTrialPatchSpawnService:GetPatchBudget()
	return self._patchBudget
end

return CityTrialPatchSpawnService
