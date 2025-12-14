--[[
	KudosShopService
	
	Handles Kudos purchases via Developer Products.
	Uses MarketplaceService to process Robux purchases and grant kudos.
]]

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local Knit = require(Packages.Knit)

local KudosShopService = Knit.CreateService {
	Name = "KudosShopService",
	Client = {
		PurchaseComplete = Knit.CreateSignal(),  -- Fires when purchase completes
		PurchaseFailed = Knit.CreateSignal(),    -- Fires when purchase fails
	},
}

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         KUDOS PACKS CONFIG                                  ║
-- ╚════════════════════════════════════════════════════════════════════════════╝
-- NOTE: Replace these with your actual Developer Product IDs from Roblox Creator Dashboard
-- To create products: Game Settings > Monetization > Developer Products > Create

local KUDOS_PACKS = {
	{
		Name = "Starter Pack",
		ProductId = 3479973967,
		KudosAmount = 100,
		RobuxPrice = 25,  -- For display only, actual price set in Creator Dashboard
		Icon = "💰",
		BestValue = false,
	},
	{
		Name = "Value Pack",
		ProductId = 3479974190,
		KudosAmount = 500,
		RobuxPrice = 99,
		Icon = "💎",
		BestValue = false,
	},
	{
		Name = "Super Pack",
		ProductId = 3479974347,
		KudosAmount = 1200,
		RobuxPrice = 199,
		Icon = "🌟",
		BestValue = true,  -- Highlighted as best value
	},
	{
		Name = "Mega Pack",
		ProductId = 3479974541,
		KudosAmount = 3000,
		RobuxPrice = 399,
		Icon = "👑",
		BestValue = false,
	},
}

-- Track pending purchases to prevent duplicates
local pendingPurchases = {}

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         PURCHASE PROCESSING                                 ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

function KudosShopService:GetPackByProductId(productId)
	for _, pack in ipairs(KUDOS_PACKS) do
		if pack.ProductId == productId then
			return pack
		end
	end
	return nil
end

function KudosShopService:GrantKudos(player, amount, reason)
	local HubService = Knit.GetService("HubService")
	if HubService and HubService.AwardKudos then
		HubService:AwardKudos(player, amount)
		print(string.format("[KudosShopService] Granted %d kudos to %s (%s)", amount, player.Name, reason))
		return true
	else
		warn("[KudosShopService] HubService not found or AwardKudos not available")
		return false
	end
end

-- Process receipt callback for MarketplaceService
function KudosShopService:ProcessReceipt(receiptInfo)
	local player = Players:GetPlayerByUserId(receiptInfo.PlayerId)
	if not player then
		-- Player left, we'll grant on rejoin
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	
	local productId = receiptInfo.ProductId
	local pack = self:GetPackByProductId(productId)
	
	if not pack then
		warn(string.format("[KudosShopService] Unknown product ID: %d", productId))
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	
	-- Prevent duplicate processing
	local purchaseKey = string.format("%s_%s", tostring(receiptInfo.PurchaseId), tostring(player.UserId))
	if pendingPurchases[purchaseKey] then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	pendingPurchases[purchaseKey] = true
	
	-- Grant the kudos
	local success = self:GrantKudos(player, pack.KudosAmount, "Purchased " .. pack.Name)
	
	if success then
		-- Notify client
		self.Client.PurchaseComplete:Fire(player, pack.Name, pack.KudosAmount)
		
		-- Clean up pending
		task.delay(10, function()
			pendingPurchases[purchaseKey] = nil
		end)
		
		print(string.format("[KudosShopService] Purchase complete: %s bought %s (+%d kudos)", 
			player.Name, pack.Name, pack.KudosAmount))
		
		return Enum.ProductPurchaseDecision.PurchaseGranted
	else
		pendingPurchases[purchaseKey] = nil
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
end

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         CLIENT METHODS                                      ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

-- Get available packs for UI
function KudosShopService.Client:GetKudosPacks(player)
	print(string.format("[KudosShopService] GetKudosPacks called by %s", player.Name))
	print(string.format("[KudosShopService] KUDOS_PACKS has %d entries", #KUDOS_PACKS))
	
	local packs = {}
	for i, pack in ipairs(KUDOS_PACKS) do
		print(string.format("[KudosShopService] Adding pack %d: %s", i, pack.Name))
		table.insert(packs, {
			Name = pack.Name,
			ProductId = pack.ProductId,
			KudosAmount = pack.KudosAmount,
			RobuxPrice = pack.RobuxPrice,
			Icon = pack.Icon,
			BestValue = pack.BestValue,
		})
	end
	
	print(string.format("[KudosShopService] Returning %d packs to client", #packs))
	return packs
end

-- Request to purchase a pack (client calls this, then prompts purchase)
function KudosShopService.Client:RequestPurchase(player, productId)
	local pack = KudosShopService:GetPackByProductId(productId)
	if not pack then
		warn(string.format("[KudosShopService] Invalid product ID requested: %d", productId))
		return false
	end
	
	-- The actual purchase prompt happens on the client via MarketplaceService
	-- This just validates the product exists
	print(string.format("[KudosShopService] %s requesting purchase of %s", player.Name, pack.Name))
	return true
end

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         LIFECYCLE                                           ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

function KudosShopService:KnitInit()
	print("[KudosShopService] Initializing...")
	
	-- Set up ProcessReceipt callback
	MarketplaceService.ProcessReceipt = function(receiptInfo)
		return self:ProcessReceipt(receiptInfo)
	end
end

function KudosShopService:KnitStart()
	print("[KudosShopService] Started!")
	
	-- Log configured packs
	print("[KudosShopService] Configured packs:")
	for _, pack in ipairs(KUDOS_PACKS) do
		local status = pack.ProductId > 0 and "✓" or "⚠ NO PRODUCT ID"
		print(string.format("  %s %s: %d kudos for %d R$ (ID: %d)", 
			status, pack.Name, pack.KudosAmount, pack.RobuxPrice, pack.ProductId))
	end
	
	if KUDOS_PACKS[1].ProductId == 0 then
		warn("[KudosShopService] ⚠️ Product IDs are not configured! Create Developer Products in Creator Dashboard.")
	end
end

return KudosShopService

