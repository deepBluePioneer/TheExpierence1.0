local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Packages = ReplicatedStorage.Packages
local CustomPackages = ReplicatedStorage:WaitForChild("CustomPackages")
local Knit = require(Packages.Knit)

local ReplicaService = require(CustomPackages.Replica.ReplicaService)
local ItemRegistry = require(ReplicatedStorage.Source.GraviBowItemRegistry)

local ITEM_COSTS = {}
local ITEM_PLACEMENT = {}
local ITEM_PREFAB_NAMES = {
	Floodlight = "floodlight",
	Wall = "wall",
	Floor = "floor",
	Ramp = "ramp",
	Turret = "turret",
}
for _, item in ipairs(ItemRegistry) do
	if item.cost and item.cost > 0 then
		ITEM_COSTS[item.name] = item.cost
	end
	if item.placement then
		ITEM_PLACEMENT[item.name] = item.placement
	end
end

local GraviBowOreService = Knit.CreateService({
	Name = "GraviBowOreService",
	Client = {
		CrystalMined = Knit.CreateSignal(),
		PurchaseItem = Knit.CreateSignal(),
		ItemPurchased = Knit.CreateSignal(),
		PlaceSnapItem = Knit.CreateSignal(),
	},

	_oreClassToken = nil,
	_oreReplicas = {},
	_itemsFolder = nil,
})

function GraviBowOreService:KnitInit()
	self._oreClassToken = ReplicaService.NewClassToken("GraviBowOreState")
end

function GraviBowOreService:KnitStart()
	self._harvesterService = Knit.GetService("GraviBowHarvesterService")

	self._itemsFolder = Instance.new("Folder")
	self._itemsFolder.Name = "PlacedItems"
	self._itemsFolder.Parent = Workspace

	self.Client.CrystalMined:Connect(function(player)
		self:OnCrystalMined(player)
	end)

	self.Client.PurchaseItem:Connect(function(player, itemName)
		self:_onPurchaseItem(player, itemName)
	end)

	self.Client.PlaceSnapItem:Connect(function(player, model, cframe)
		self:_onPlaceSnapItem(player, model, cframe)
	end)
end

function GraviBowOreService:CreateOreReplica(player)
	if self._oreReplicas[player] then return end
	local replica = ReplicaService.NewReplica({
		ClassToken = self._oreClassToken,
		Data = { ore = 0 },
		Replication = { [player] = true },
	})
	self._oreReplicas[player] = replica
end

function GraviBowOreService:DestroyOreReplica(player)
	local replica = self._oreReplicas[player]
	if replica then
		replica:Destroy()
		self._oreReplicas[player] = nil
	end
end

function GraviBowOreService:OnCrystalMined(player)
	local replica = self._oreReplicas[player]
	if not replica then return end
	local current = replica.Data.ore or 0
	replica:SetValue({"ore"}, current + 1)
end

function GraviBowOreService:GetPlayerOre(player)
	local replica = self._oreReplicas[player]
	return replica and replica.Data.ore or 0
end

function GraviBowOreService:RefundOre(player, amount)
	if amount <= 0 then return end
	local replica = self._oreReplicas[player]
	if not replica then return end
	local current = replica.Data.ore or 0
	replica:SetValue({"ore"}, current + amount)
	print("[GraviBowOreService] Refunded", amount, "ore to", player.Name)
end

function GraviBowOreService:_onPurchaseItem(player, itemName)
	if type(itemName) ~= "string" then return end

	local cost = ITEM_COSTS[itemName]
	if not cost then
		warn("[GraviBowOreService] Unknown item:", itemName)
		return
	end

	local currentOre = self:GetPlayerOre(player)
	if currentOre < cost then
		warn("[GraviBowOreService] Not enough ore for", itemName, "- has", currentOre, "needs", cost)
		return
	end

	local replica = self._oreReplicas[player]
	if not replica then return end
	replica:SetValue({"ore"}, currentOre - cost)

	local placement = ITEM_PLACEMENT[itemName]
	local spawnedModel = nil

	if placement == "drop" then
		spawnedModel = self._harvesterService:SpawnHarvester(player)
	elseif placement == "snap" then
		spawnedModel = self:_spawnSnapItem(player, itemName)
	end

	self.Client.ItemPurchased:Fire(player, itemName, spawnedModel)
	print("[GraviBowOreService] Player", player.Name, "purchased", itemName, "- ore left:", currentOre - cost)
end

function GraviBowOreService:_spawnSnapItem(player, itemName)
	local prefabName = ITEM_PREFAB_NAMES[itemName]
	if not prefabName then
		warn("[GraviBowOreService] No prefab mapping for snap item:", itemName)
		return nil
	end

	local prefabs = ReplicatedStorage:FindFirstChild("prefabs") or ReplicatedStorage:FindFirstChild("Prefabs")
	if not prefabs then
		warn("[GraviBowOreService] No prefabs folder in ReplicatedStorage")
		return nil
	end

	local prefab = prefabs:FindFirstChild(prefabName)
	if not prefab then
		warn("[GraviBowOreService] Prefab not found:", prefabName)
		return nil
	end

	local clone = prefab:Clone()
	clone.Name = itemName .. "_" .. player.UserId .. "_" .. tick()

	local character = player.Character
	if character then
		local head = character:FindFirstChild("Head") or character:FindFirstChild("HumanoidRootPart")
		if head then
			if clone:IsA("Model") then
				clone:PivotTo(head.CFrame * CFrame.new(0, 0, -8))
			elseif clone:IsA("BasePart") then
				clone.CFrame = head.CFrame * CFrame.new(0, 0, -8)
			end
		end
	end

	for _, desc in ipairs(clone:GetDescendants()) do
		if desc:IsA("BasePart") then
			desc.Anchored = true
			desc.CanCollide = false
		end
	end
	if clone:IsA("BasePart") then
		clone.Anchored = true
		clone.CanCollide = false
	end

	clone.Parent = self._itemsFolder

	print("[GraviBowOreService] Spawned snap item:", clone.Name)
	return clone
end

function GraviBowOreService:_onPlaceSnapItem(player, model, cframe)
	if typeof(model) ~= "Instance" then return end
	if not model.Parent then return end
	if model.Parent ~= self._itemsFolder then return end

	if typeof(cframe) ~= "CFrame" then return end

	if model:IsA("Model") then
		model:PivotTo(cframe)
	elseif model:IsA("BasePart") then
		model.CFrame = cframe
	end

	for _, desc in ipairs(model:GetDescendants()) do
		if desc:IsA("BasePart") then
			desc.Anchored = true
			desc.CanCollide = true
		end
	end
	if model:IsA("BasePart") then
		model.Anchored = true
		model.CanCollide = true
	end

	print("[GraviBowOreService] Placed snap item:", model.Name, "at", cframe.Position)
end

return GraviBowOreService
