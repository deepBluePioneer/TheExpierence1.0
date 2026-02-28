--[[
	Analytics.lua  –  shared wrapper around AnalyticsService

	SERVER-ONLY. AnalyticsService rejects calls from the client and from Studio.
	Every helper below is a no-op when called in Studio so services can call
	them unconditionally without pcall-guarding every site.

	Covers:
	  • Custom events   (LogCustomEvent)
	  • Funnel events   (LogOnboardingFunnelStepEvent, LogFunnelStepEvent)

	Usage:
		local Analytics = require(ReplicatedStorage.Source.Analytics)
		Analytics.PatchCollected(player, "speed", 3)
		Analytics.Funnel.Onboarding(player, 1, "Player Joined")

	Event naming convention  (max 100 unique event names per experience):
		• Use a small set of broad event names
		• Differentiate via customFields, NOT by creating new event names

	Funnel design  (max 10 funnels):
		• Onboarding   (one-time) – new-player first session flow
		• ShopCheckout (recurring) – shop open → browse → purchase
		• GarageFlow   (recurring) – garage open → view machine → select/buy
		• MatchLoop     (recurring) – teleport in → play → rewards → return
]]

local AnalyticsService = game:GetService("AnalyticsService")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")

local IS_STUDIO = RunService:IsStudio()

local Analytics = {}
Analytics.Funnel = {}

local function log(player, eventName, value, customFields)
	if IS_STUDIO then return end

	local ok, err = pcall(function()
		if value and customFields then
			AnalyticsService:LogCustomEvent(player, eventName, value, customFields)
		elseif value then
			AnalyticsService:LogCustomEvent(player, eventName, value)
		elseif customFields then
			AnalyticsService:LogCustomEvent(player, eventName, 1, customFields)
		else
			AnalyticsService:LogCustomEvent(player, eventName)
		end
	end)

	if not ok then
		warn("[Analytics] Failed to log '" .. eventName .. "': " .. tostring(err))
	end
end

----------------------------------------------------------------
-- HUB EVENTS
----------------------------------------------------------------

function Analytics.HubJoined(player)
	log(player, "HubJoined")
end

function Analytics.ShopItemPurchased(player, itemId, category, price)
	log(player, "ItemPurchased", price, {
		[Enum.AnalyticsCustomFieldKeys.CustomField01.Name] = itemId,
		[Enum.AnalyticsCustomFieldKeys.CustomField02.Name] = category,
	})
end

function Analytics.MachineSelected(player, machineId)
	log(player, "MachineSelected", nil, {
		[Enum.AnalyticsCustomFieldKeys.CustomField01.Name] = machineId,
	})
end

function Analytics.MachineUnlocked(player, machineId, method)
	log(player, "MachineUnlocked", nil, {
		[Enum.AnalyticsCustomFieldKeys.CustomField01.Name] = machineId,
		[Enum.AnalyticsCustomFieldKeys.CustomField02.Name] = method, -- "shop" | "level"
	})
end

function Analytics.LeaderboardViewed(player)
	log(player, "LeaderboardViewed")
end

function Analytics.TeleporterQueueJoined(player, teleporterId)
	log(player, "TeleporterQueueJoined", nil, {
		[Enum.AnalyticsCustomFieldKeys.CustomField01.Name] = tostring(teleporterId),
	})
end

function Analytics.TeleportedToCityTrial(player)
	log(player, "TeleportedToCityTrial")
end

----------------------------------------------------------------
-- CITY TRIAL EVENTS
----------------------------------------------------------------

function Analytics.MatchJoined(player, machineId)
	log(player, "MatchJoined", nil, {
		[Enum.AnalyticsCustomFieldKeys.CustomField01.Name] = machineId,
	})
end

function Analytics.MatchCompleted(player, durationSeconds, patchesCollected, deaths)
	log(player, "MatchCompleted", durationSeconds, {
		[Enum.AnalyticsCustomFieldKeys.CustomField01.Name] = tostring(patchesCollected),
		[Enum.AnalyticsCustomFieldKeys.CustomField02.Name] = tostring(deaths),
	})
end

function Analytics.PatchCollected(player, patchType, totalPatches)
	log(player, "PatchCollected", totalPatches, {
		[Enum.AnalyticsCustomFieldKeys.CustomField01.Name] = patchType,
	})
end

function Analytics.PlayerDeath(player, cause)
	log(player, "PlayerDeath", nil, {
		[Enum.AnalyticsCustomFieldKeys.CustomField01.Name] = cause or "unknown",
	})
end

function Analytics.RewardsEarned(player, currency, xp)
	log(player, "RewardsEarned", currency, {
		[Enum.AnalyticsCustomFieldKeys.CustomField01.Name] = tostring(xp),
	})
end

function Analytics.EventTriggered(player, eventType)
	log(player, "EventTriggered", nil, {
		[Enum.AnalyticsCustomFieldKeys.CustomField01.Name] = eventType,
	})
end

function Analytics.EventDamageTaken(player, eventType, damage)
	log(player, "EventDamageTaken", damage, {
		[Enum.AnalyticsCustomFieldKeys.CustomField01.Name] = eventType,
	})
end

----------------------------------------------------------------
-- SHARED / GENERAL
----------------------------------------------------------------

function Analytics.SessionDuration(player, seconds)
	log(player, "SessionDuration", seconds)
end

function Analytics.UIButtonClicked(player, buttonName, screenName)
	log(player, "UIButtonClicked", nil, {
		[Enum.AnalyticsCustomFieldKeys.CustomField01.Name] = buttonName,
		[Enum.AnalyticsCustomFieldKeys.CustomField02.Name] = screenName or "",
	})
end

----------------------------------------------------------------
-- FUNNELS
----------------------------------------------------------------

local function logOnboarding(player, step, stepName, customFields)
	if IS_STUDIO then return end

	local ok, err = pcall(function()
		if customFields then
			AnalyticsService:LogOnboardingFunnelStepEvent(player, step, stepName, customFields)
		else
			AnalyticsService:LogOnboardingFunnelStepEvent(player, step, stepName)
		end
	end)

	if not ok then
		warn("[Analytics] Onboarding funnel step " .. step .. " failed: " .. tostring(err))
	end
end

local function logFunnel(player, funnelName, sessionId, step, stepName, customFields)
	if IS_STUDIO then return end

	local ok, err = pcall(function()
		if customFields then
			AnalyticsService:LogFunnelStepEvent(player, funnelName, sessionId, step, stepName, customFields)
		else
			AnalyticsService:LogFunnelStepEvent(player, funnelName, sessionId, step, stepName)
		end
	end)

	if not ok then
		warn("[Analytics] Funnel '" .. funnelName .. "' step " .. step .. " failed: " .. tostring(err))
	end
end

-- Per-player session IDs for recurring funnels
local _funnelSessions = {}

function Analytics.Funnel.NewSession(player, funnelName)
	if not _funnelSessions[player] then
		_funnelSessions[player] = {}
	end
	local sessionId = HttpService:GenerateGUID(false)
	_funnelSessions[player][funnelName] = sessionId
	return sessionId
end

function Analytics.Funnel.GetSession(player, funnelName)
	return _funnelSessions[player] and _funnelSessions[player][funnelName]
end

function Analytics.Funnel.ClearPlayer(player)
	_funnelSessions[player] = nil
end

----------------------------------------------------------------
-- ONBOARDING FUNNEL (one-time, 6 steps)
--
--   1. Player Joined
--   2. Profile Loaded
--   3. Explored Hub (opened any panel: shop, garage, or leaderboard)
--   4. Selected Machine
--   5. Entered Queue
--   6. Teleported to CityTrial
----------------------------------------------------------------

function Analytics.Funnel.Onboarding(player, step, stepName)
	logOnboarding(player, step, stepName)
end

function Analytics.Funnel.OnboardingJoined(player)
	logOnboarding(player, 1, "Player Joined")
end

function Analytics.Funnel.OnboardingProfileLoaded(player)
	logOnboarding(player, 2, "Profile Loaded")
end

function Analytics.Funnel.OnboardingExploredHub(player)
	logOnboarding(player, 3, "Explored Hub")
end

function Analytics.Funnel.OnboardingSelectedMachine(player)
	logOnboarding(player, 4, "Selected Machine")
end

function Analytics.Funnel.OnboardingEnteredQueue(player)
	logOnboarding(player, 5, "Entered Queue")
end

function Analytics.Funnel.OnboardingTeleported(player)
	logOnboarding(player, 6, "Teleported to CityTrial")
end

----------------------------------------------------------------
-- SHOP CHECKOUT FUNNEL (recurring, 4 steps)
--
--   1. Opened Shop
--   2. Viewed Item
--   3. Attempted Purchase
--   4. Purchase Completed
----------------------------------------------------------------

function Analytics.Funnel.ShopOpened(player)
	local sessionId = Analytics.Funnel.NewSession(player, "ShopCheckout")
	logFunnel(player, "ShopCheckout", sessionId, 1, "Opened Shop")
end

function Analytics.Funnel.ShopViewedItem(player, itemId)
	local sessionId = Analytics.Funnel.GetSession(player, "ShopCheckout")
	if not sessionId then return end
	logFunnel(player, "ShopCheckout", sessionId, 2, "Viewed Item", {
		[Enum.AnalyticsCustomFieldKeys.CustomField01.Name] = itemId,
	})
end

function Analytics.Funnel.ShopAttemptedPurchase(player, itemId)
	local sessionId = Analytics.Funnel.GetSession(player, "ShopCheckout")
	if not sessionId then return end
	logFunnel(player, "ShopCheckout", sessionId, 3, "Attempted Purchase", {
		[Enum.AnalyticsCustomFieldKeys.CustomField01.Name] = itemId,
	})
end

function Analytics.Funnel.ShopPurchaseCompleted(player, itemId)
	local sessionId = Analytics.Funnel.GetSession(player, "ShopCheckout")
	if not sessionId then return end
	logFunnel(player, "ShopCheckout", sessionId, 4, "Purchase Completed", {
		[Enum.AnalyticsCustomFieldKeys.CustomField01.Name] = itemId,
	})
end

----------------------------------------------------------------
-- GARAGE FUNNEL (recurring, 3 steps)
--
--   1. Opened Garage
--   2. Viewed Machine
--   3. Selected / Purchased Machine
----------------------------------------------------------------

function Analytics.Funnel.GarageOpened(player)
	local sessionId = Analytics.Funnel.NewSession(player, "GarageFlow")
	logFunnel(player, "GarageFlow", sessionId, 1, "Opened Garage")
end

function Analytics.Funnel.GarageViewedMachine(player, machineId)
	local sessionId = Analytics.Funnel.GetSession(player, "GarageFlow")
	if not sessionId then return end
	logFunnel(player, "GarageFlow", sessionId, 2, "Viewed Machine", {
		[Enum.AnalyticsCustomFieldKeys.CustomField01.Name] = machineId,
	})
end

function Analytics.Funnel.GarageSelectedMachine(player, machineId)
	local sessionId = Analytics.Funnel.GetSession(player, "GarageFlow")
	if not sessionId then return end
	logFunnel(player, "GarageFlow", sessionId, 3, "Selected Machine", {
		[Enum.AnalyticsCustomFieldKeys.CustomField01.Name] = machineId,
	})
end

----------------------------------------------------------------
-- MATCH LOOP FUNNEL (recurring, 6 steps)
--
--   1. Teleported In
--   2. Match Started
--   3. First Patch Collected
--   4. Match Completed
--   5. Rewards Earned
--   6. Returned to Hub
----------------------------------------------------------------

function Analytics.Funnel.MatchTeleportedIn(player)
	local sessionId = Analytics.Funnel.NewSession(player, "MatchLoop")
	logFunnel(player, "MatchLoop", sessionId, 1, "Teleported In")
end

function Analytics.Funnel.MatchStarted(player)
	local sessionId = Analytics.Funnel.GetSession(player, "MatchLoop")
	if not sessionId then return end
	logFunnel(player, "MatchLoop", sessionId, 2, "Match Started")
end

function Analytics.Funnel.MatchFirstPatch(player)
	local sessionId = Analytics.Funnel.GetSession(player, "MatchLoop")
	if not sessionId then return end
	logFunnel(player, "MatchLoop", sessionId, 3, "First Patch Collected")
end

function Analytics.Funnel.MatchCompleted(player)
	local sessionId = Analytics.Funnel.GetSession(player, "MatchLoop")
	if not sessionId then return end
	logFunnel(player, "MatchLoop", sessionId, 4, "Match Completed")
end

function Analytics.Funnel.MatchRewardsEarned(player)
	local sessionId = Analytics.Funnel.GetSession(player, "MatchLoop")
	if not sessionId then return end
	logFunnel(player, "MatchLoop", sessionId, 5, "Rewards Earned")
end

function Analytics.Funnel.MatchReturnedToHub(player)
	local sessionId = Analytics.Funnel.GetSession(player, "MatchLoop")
	if not sessionId then return end
	logFunnel(player, "MatchLoop", sessionId, 6, "Returned to Hub")
end

return Analytics
