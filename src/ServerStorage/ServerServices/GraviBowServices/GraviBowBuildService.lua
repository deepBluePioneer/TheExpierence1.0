local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Packages = ReplicatedStorage.Packages
local Knit = require(Packages.Knit)

local ItemRegistry = require(ReplicatedStorage.Source.GraviBowItemRegistry)

local PLACEMENT_GHOST_TRANSPARENCY = 0.5

local function buildCostLookup()
	local costs = {}
	for _, item in ipairs(ItemRegistry) do
		if item.cost and item.cost > 0 then
			costs[item.name] = item.cost
		end
	end
	return costs
end

local ITEM_COSTS = buildCostLookup()

local GraviBowBuildService = Knit.CreateService({
	Name = "GraviBowBuildService",
	Client = {
		PlaceBuildable = Knit.CreateSignal(),
		CancelBuildable = Knit.CreateSignal(),
		BuildablePlaced = Knit.CreateSignal(),
	},

	_playerPlacements = {},
})

function GraviBowBuildService:KnitInit()
end

function GraviBowBuildService:KnitStart()
	self._oreService = Knit.GetService("GraviBowOreService")

	self.Client.PlaceBuildable:Connect(function(player, model, finalCFrame)
		self:_onPlaceBuildable(player, model, finalCFrame)
	end)

	self.Client.CancelBuildable:Connect(function(player, model)
		self:_onCancelBuildable(player, model)
	end)

	Players.PlayerRemoving:Connect(function(player)
		self:_cleanupPlayer(player)
	end)
end

function GraviBowBuildService:SpawnBuildable(player, itemName)
	local prefab = self:_findPrefab(itemName)
	if not prefab then
		warn("[GraviBowBuildService] Could not find prefab for:", itemName)
		return nil
	end

	local clone = prefab:Clone()

	local parts = {}
	if clone:IsA("BasePart") then table.insert(parts, clone) end
	for _, desc in ipairs(clone:GetDescendants()) do
		if desc:IsA("BasePart") then table.insert(parts, desc) end
	end

	for _, part in ipairs(parts) do
		part.Anchored = true
		part.CanCollide = false
		part.CanTouch = false
		part.CanQuery = false
		part.Transparency = PLACEMENT_GHOST_TRANSPARENCY
	end

	local character = player.Character
	if character then
		local hrp = character:FindFirstChild("HumanoidRootPart")
		if hrp then
			local spawnPos = hrp.CFrame:PointToWorldSpace(Vector3.new(0, 0, -8))
			if clone:IsA("Model") then
				clone:PivotTo(CFrame.new(spawnPos))
			else
				clone.CFrame = CFrame.new(spawnPos)
			end
		end
	end

	clone.Parent = Workspace

	self._playerPlacements[player] = { model = clone, itemName = itemName }
	print("[GraviBowBuildService] Spawned buildable", itemName, "for", player.Name)
	return clone
end

function GraviBowBuildService:_findPrefab(itemName)
	local prefabsFolder = ReplicatedStorage:FindFirstChild("prefabs")
	if not prefabsFolder then return nil end

	for _, child in ipairs(prefabsFolder:GetChildren()) do
		if child.Name:lower() == itemName:lower() then
			return child
		end
	end
	return nil
end

function GraviBowBuildService:_onPlaceBuildable(player, model, finalCFrame)
	local placement = self._playerPlacements[player]
	if not placement or placement.model ~= model then
		warn("[GraviBowBuildService] Invalid placement request from", player.Name)
		return
	end

	if not model or not model.Parent then
		self._playerPlacements[player] = nil
		return
	end

	if typeof(finalCFrame) ~= "CFrame" then
		warn("[GraviBowBuildService] Invalid CFrame from", player.Name)
		return
	end

	if model:IsA("Model") then
		model:PivotTo(finalCFrame)
	elseif model:IsA("BasePart") then
		model.CFrame = finalCFrame
	end

	local parts = {}
	if model:IsA("BasePart") then table.insert(parts, model) end
	for _, desc in ipairs(model:GetDescendants()) do
		if desc:IsA("BasePart") then table.insert(parts, desc) end
	end

	for _, part in ipairs(parts) do
		part.Anchored = true
		part.CanCollide = true
		part.CanTouch = true
		part.CanQuery = true
		part.Transparency = 0
	end

	self._playerPlacements[player] = nil
	self.Client.BuildablePlaced:Fire(player, model)
	print("[GraviBowBuildService] Placed", placement.itemName, "for", player.Name)
end

function GraviBowBuildService:_onCancelBuildable(player, model)
	local placement = self._playerPlacements[player]
	if not placement or placement.model ~= model then return end

	local cost = ITEM_COSTS[placement.itemName] or 0
	if cost > 0 then
		self._oreService:RefundOre(player, cost)
	end

	if model and model.Parent then
		model:Destroy()
	end

	self._playerPlacements[player] = nil
	print("[GraviBowBuildService] Cancelled", placement.itemName, "for", player.Name, "- refunded", cost)
end

function GraviBowBuildService:_cleanupPlayer(player)
	local placement = self._playerPlacements[player]
	if placement then
		if placement.model and placement.model.Parent then
			placement.model:Destroy()
		end
		self._playerPlacements[player] = nil
	end
end

return GraviBowBuildService
