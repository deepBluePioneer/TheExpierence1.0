local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Packages = ReplicatedStorage.Packages
local Knit = require(Packages.Knit)
local Signal = require(Packages.Signal)
local Promise = require(Packages.promise)

local LEADERBOARD_STORE = "GlobalLeaderboard_XP"
local CACHE_DURATION = 30
local PAGE_SIZE = 50

local HubLeaderboardService = Knit.CreateService {
	Name = "HubLeaderboardService",
	Client = {},

	_orderedStore = nil,
	_cache = {},
	_cacheTimestamp = 0,

	LeaderboardUpdated = Signal.new(),
}

function HubLeaderboardService:KnitInit()
	self._orderedStore = DataStoreService:GetOrderedDataStore(LEADERBOARD_STORE)
end

function HubLeaderboardService:KnitStart()
end

function HubLeaderboardService:GetTopPlayers(count)
	count = count or PAGE_SIZE

	local now = os.clock()
	if now - self._cacheTimestamp < CACHE_DURATION and #self._cache > 0 then
		local result = {}
		for i = 1, math.min(count, #self._cache) do
			result[i] = self._cache[i]
		end
		return result
	end

	return self:_fetchLeaderboard(count)
end

function HubLeaderboardService:_fetchLeaderboard(count)
	local ok, pages = pcall(function()
		return self._orderedStore:GetSortedAsync(false, count)
	end)

	if not ok or not pages then
		warn("[HubLeaderboardService] Failed to fetch leaderboard: " .. tostring(pages))
		return self._cache
	end

	local entries = {}
	local pageData = pages:GetCurrentPage()

	for rank, entry in ipairs(pageData) do
		local userId = tonumber(string.match(entry.key, "(%d+)"))
		table.insert(entries, {
			rank = rank,
			userId = userId,
			key = entry.key,
			value = entry.value,
		})
	end

	self._cache = entries
	self._cacheTimestamp = os.clock()
	self.LeaderboardUpdated:Fire(entries)

	return entries
end

function HubLeaderboardService:SetPlayerScore(player, score)
	local key = "Player_" .. player.UserId

	return Promise.new(function(resolve, reject)
		local ok, err = pcall(function()
			self._orderedStore:SetAsync(key, score)
		end)

		if ok then
			resolve()
		else
			warn("[HubLeaderboardService] Failed to set score: " .. tostring(err))
			reject(err)
		end
	end)
end

function HubLeaderboardService:GetPlayerRank(player)
	local entries = self:GetTopPlayers(PAGE_SIZE)
	for _, entry in ipairs(entries) do
		if entry.userId == player.UserId then
			return entry.rank
		end
	end
	return nil
end

----------------------------------------------------------------
-- Client-exposed methods
----------------------------------------------------------------

function HubLeaderboardService.Client:GetTopPlayers(player, count)
	return self.Server:GetTopPlayers(count)
end

function HubLeaderboardService.Client:GetPlayerRank(player)
	return self.Server:GetPlayerRank(player)
end

return HubLeaderboardService
