local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Packages = ReplicatedStorage.Packages
local Knit = require(Packages.Knit)
local Signal = require(Packages.Signal)

local ShopConfig = require(ReplicatedStorage.Source.ShopConfig)
local MachinesConfig = require(ReplicatedStorage.Source.MachinesConfig)
local Analytics = require(ReplicatedStorage.Source.Analytics)

local HubShopService = Knit.CreateService {
	Name = "HubShopService",
	Client = {
		PurchaseCompleted = Knit.CreateSignal(),
	},

	_purchaseLocks = {},

	ItemPurchased = Signal.new(),
}

local function findItem(itemId)
	for _, item in ipairs(ShopConfig.items) do
		if item.id == itemId then
			return item
		end
	end
	return nil
end

function HubShopService:KnitInit()
end

function HubShopService:KnitStart()
	local Players = game:GetService("Players")
	Players.PlayerRemoving:Connect(function(player)
		self._purchaseLocks[player] = nil
	end)
end

function HubShopService:_acquireLock(player)
	if self._purchaseLocks[player] then
		return false
	end
	self._purchaseLocks[player] = true
	return true
end

function HubShopService:_releaseLock(player)
	self._purchaseLocks[player] = nil
end

function HubShopService:Purchase(player, itemId)
	Analytics.Funnel.ShopAttemptedPurchase(player, itemId)

	if not self:_acquireLock(player) then
		return false, "Purchase already in progress"
	end

	local ok, reason = self:_validateAndGrant(player, itemId)

	self:_releaseLock(player)
	return ok, reason
end

function HubShopService:_validateAndGrant(player, itemId)
	local HubProfileService = Knit.GetService("HubProfileService")
	local data = HubProfileService:GetProfileData(player)
	if not data then
		return false, "Profile not loaded"
	end

	local item = findItem(itemId)
	if not item then
		return false, "Invalid item"
	end

	if data.level < (item.levelRequired or 0) then
		return false, "Level too low"
	end

	if self:_playerOwnsItem(data, item) then
		return false, "Already owned"
	end

	if not HubProfileService:CanAfford(player, item.price) then
		return false, "Not enough currency"
	end

	local deducted, deductReason = HubProfileService:ApplyPurchase(player, item.price)
	if not deducted then
		return false, deductReason
	end

	self:_grantItem(player, data, item, HubProfileService)

	self.ItemPurchased:Fire(player, itemId)
	self.Client.PurchaseCompleted:Fire(player, true, itemId)
	Analytics.ShopItemPurchased(player, itemId, item.category, item.price)
	Analytics.Funnel.ShopPurchaseCompleted(player, itemId)

	return true
end

function HubShopService:_playerOwnsItem(data, item)
	local cat = item.category

	if cat == "trail" then
		return table.find(data.ownedTrails or {}, item.id) ~= nil
	elseif cat == "skin" then
		local machSkins = (data.ownedSkins or {})[item.machineId]
		return machSkins and table.find(machSkins, item.id) ~= nil
	elseif cat == "title" then
		return table.find(data.ownedTitles or {}, item.id) ~= nil
	elseif cat == "boostEffect" then
		return table.find(data.ownedBoostEffects or {}, item.id) ~= nil
	end

	return false
end

function HubShopService:_grantItem(player, data, item, profileService)
	local replica = profileService:GetReplica(player)
	local cat = item.category

	if cat == "trail" then
		table.insert(data.ownedTrails, item.id)
		if replica then
			replica:SetValue({ "ownedTrails" }, data.ownedTrails)
		end

	elseif cat == "skin" then
		if not data.ownedSkins[item.machineId] then
			data.ownedSkins[item.machineId] = {}
		end
		table.insert(data.ownedSkins[item.machineId], item.id)

	elseif cat == "title" then
		table.insert(data.ownedTitles, item.id)
		if replica then
			replica:SetValue({ "ownedTitles" }, data.ownedTitles)
		end

	elseif cat == "boostEffect" then
		table.insert(data.ownedBoostEffects, item.id)
	end
end

-- Handle machine purchases (routed from HubGarageService or directly)
function HubShopService:PurchaseMachine(player, machineId)
	if not self:_acquireLock(player) then
		return false, "Purchase already in progress"
	end

	local HubProfileService = Knit.GetService("HubProfileService")
	local data = HubProfileService:GetProfileData(player)
	if not data then
		self:_releaseLock(player)
		return false, "Profile not loaded"
	end

	local machineConfig = MachinesConfig.machines[machineId]
	if not machineConfig then
		self:_releaseLock(player)
		return false, "Invalid machine"
	end

	if machineConfig.unlock.type ~= "shop" then
		self:_releaseLock(player)
		return false, "Machine not purchasable"
	end

	if table.find(data.ownedMachines, machineId) then
		self:_releaseLock(player)
		return false, "Already owned"
	end

	if not HubProfileService:CanAfford(player, machineConfig.unlock.price) then
		self:_releaseLock(player)
		return false, "Not enough currency"
	end

	local deducted, reason = HubProfileService:ApplyPurchase(player, machineConfig.unlock.price)
	if not deducted then
		self:_releaseLock(player)
		return false, reason
	end

	HubProfileService:UnlockMachine(player, machineId)

	self._purchaseLocks[player] = nil
	self.ItemPurchased:Fire(player, machineId)
	self.Client.PurchaseCompleted:Fire(player, true, machineId)
	Analytics.MachineUnlocked(player, machineId, "shop")

	return true
end

----------------------------------------------------------------
-- Client-exposed methods
----------------------------------------------------------------

function HubShopService:LogShopOpened(player)
	Analytics.Funnel.ShopOpened(player)
	Analytics.Funnel.OnboardingExploredHub(player)
end

function HubShopService:LogItemViewed(player, itemId)
	Analytics.Funnel.ShopViewedItem(player, itemId)
end

function HubShopService.Client:Purchase(player, itemId)
	return self.Server:Purchase(player, itemId)
end

function HubShopService.Client:PurchaseMachine(player, machineId)
	return self.Server:PurchaseMachine(player, machineId)
end

function HubShopService.Client:LogShopOpened(player)
	self.Server:LogShopOpened(player)
end

function HubShopService.Client:LogItemViewed(player, itemId)
	self.Server:LogItemViewed(player, itemId)
end

return HubShopService
