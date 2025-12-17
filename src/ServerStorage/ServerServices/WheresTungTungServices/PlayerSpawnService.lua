-- PlayerSpawnService
-- Spawns a prefab model per player and places it flush on the ground
-- WITHOUT setting PrimaryPart (uses PivotTo + true lowest-point detection)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Packages = ReplicatedStorage.Packages
local Knit = require(Packages.Knit)

local PlayerSpawnService = Knit.CreateService {
	Name = "PlayerSpawnService",
	Client = {},
}

-- =========================================================
-- CONFIG
-- =========================================================

local CONFIG = {
	PrefabName = "prefabs", -- Folder name in ReplicatedStorage
	SpawnSpacing = 10,      -- Distance between each spawned model
}

-- =========================================================
-- STATE
-- =========================================================

local playerModels = {}

-- =========================================================
-- HELPERS
-- =========================================================

function PlayerSpawnService:GetPrefabsFolder()
	return ReplicatedStorage:FindFirstChild(CONFIG.PrefabName)
end

function PlayerSpawnService:GetSpawnLocation()
	return Workspace:FindFirstChildWhichIsA("SpawnLocation", true)
end

-- Finds the TRUE lowest world Y of a model (accounts for rotation)
local function getLowestWorldY(model: Model): number?
	local lowest = math.huge
	local found = false

	for _, inst in ipairs(model:GetDescendants()) do
		if inst:IsA("BasePart") then
			found = true
			local cf = inst.CFrame
			local half = inst.Size * 0.5

			local corners = {
				Vector3.new(-half.X, -half.Y, -half.Z),
				Vector3.new(-half.X, -half.Y,  half.Z),
				Vector3.new(-half.X,  half.Y, -half.Z),
				Vector3.new(-half.X,  half.Y,  half.Z),
				Vector3.new( half.X, -half.Y, -half.Z),
				Vector3.new( half.X, -half.Y,  half.Z),
				Vector3.new( half.X,  half.Y, -half.Z),
				Vector3.new( half.X,  half.Y,  half.Z),
			}

			for _, localCorner in ipairs(corners) do
				local worldCorner = cf:PointToWorldSpace(localCorner)
				if worldCorner.Y < lowest then
					lowest = worldCorner.Y
				end
			end
		end
	end

	if not found then return nil end
	return lowest
end

-- =========================================================
-- SPAWN LOGIC
-- =========================================================

function PlayerSpawnService:SpawnModelForPlayer(player)
	local prefabsFolder = self:GetPrefabsFolder()
	if not prefabsFolder then
		warn("[PlayerSpawnService] Prefabs folder not found")
		return
	end

	local prefab = prefabsFolder:FindFirstChildWhichIsA("Model")
	if not prefab then
		warn("[PlayerSpawnService] No model found in prefabs folder")
		return
	end

	local spawnLocation = self:GetSpawnLocation()
	if not spawnLocation then
		warn("[PlayerSpawnService] SpawnLocation not found")
		return
	end

	-- Stable-ish player index
	local players = Players:GetPlayers()
	local index = table.find(players, player) or #players

	local angle = (index - 1) * (math.pi * 2 / 8)
	local radius = CONFIG.SpawnSpacing

	local x = spawnLocation.Position.X + math.cos(angle) * radius
	local z = spawnLocation.Position.Z + math.sin(angle) * radius

	-- Clone and parent first
	local clone = prefab:Clone()
	clone.Name = player.Name .. "_Spawn"
	clone.Parent = Workspace

	-- Raycast down to find ground (baseplate / terrain)
	local rayStart = Vector3.new(x, spawnLocation.Position.Y + 300, z)
	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.FilterDescendantsInstances = { clone }
	rayParams.IgnoreWater = true

	local result = Workspace:Raycast(rayStart, Vector3.new(0, -1000, 0), rayParams)
	local groundY = result and result.Position.Y or 0

	-- Preserve prefab rotation, move to X/Z
	local pivot = clone:GetPivot()
	local rotationOnly = pivot - pivot.Position
	clone:PivotTo(CFrame.new(Vector3.new(x, rayStart.Y, z)) * rotationOnly)

	-- Snap model so its lowest point rests on ground
	local lowestY = getLowestWorldY(clone)
	if not lowestY then
		warn("[PlayerSpawnService] Model has no BaseParts")
		clone:Destroy()
		return
	end

	local deltaY = groundY - lowestY
	clone:PivotTo(clone:GetPivot() + Vector3.new(0, deltaY, 0))

	playerModels[player] = clone
end

-- =========================================================
-- CLEANUP
-- =========================================================

function PlayerSpawnService:RemoveModelForPlayer(player)
	local model = playerModels[player]
	if model then
		model:Destroy()
		playerModels[player] = nil
	end
end

-- =========================================================
-- KNIT LIFECYCLE
-- =========================================================

function PlayerSpawnService:OnPlayerAdded(player)
	self:SpawnModelForPlayer(player)
end

function PlayerSpawnService:OnPlayerRemoving(player)
	self:RemoveModelForPlayer(player)
end

function PlayerSpawnService:KnitInit()
	print("[PlayerSpawnService] Initializing")
end

function PlayerSpawnService:KnitStart()
	print("[PlayerSpawnService] Starting")

	Players.PlayerAdded:Connect(function(player)
		self:OnPlayerAdded(player)
	end)

	Players.PlayerRemoving:Connect(function(player)
		self:OnPlayerRemoving(player)
	end)

	for _, player in ipairs(Players:GetPlayers()) do
		self:OnPlayerAdded(player)
	end

	print("[PlayerSpawnService] Ready")
end

return PlayerSpawnService
