local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Packages = ReplicatedStorage.Packages
local CustomPackages = ReplicatedStorage:WaitForChild("CustomPackages")
local Knit = require(Packages.Knit)

local ReplicaService = require(CustomPackages.Replica.ReplicaService)

local ITEM_COSTS = {
	Harvester = 1,
}

local GraviBowOreService = Knit.CreateService({
	Name = "GraviBowOreService",
	Client = {
		CrystalMined = Knit.CreateSignal(),
		PurchaseItem = Knit.CreateSignal(),
		ItemPurchased = Knit.CreateSignal(),
	},

	_oreClassToken = nil,
	_oreReplicas = {},
})

function GraviBowOreService:KnitInit()
	self._oreClassToken = ReplicaService.NewClassToken("GraviBowOreState")
end

function GraviBowOreService:KnitStart()
	self._harvesterService = Knit.GetService("GraviBowHarvesterService")

	self.Client.CrystalMined:Connect(function(player)
		self:OnCrystalMined(player)
	end)

	self.Client.PurchaseItem:Connect(function(player, itemName)
		self:_onPurchaseItem(player, itemName)
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

	if itemName == "Harvester" then
		local harvester = self._harvesterService:SpawnHarvester(player)
		if harvester then
			self.Client.ItemPurchased:Fire(player, itemName, harvester)
			print("[GraviBowOreService] Player", player.Name, "purchased Harvester - ore left:", currentOre - cost)
			return
		end
	end

	self.Client.ItemPurchased:Fire(player, itemName, nil)
	print("[GraviBowOreService] Player", player.Name, "purchased", itemName, "- ore left:", currentOre - cost)
end

return GraviBowOreService
