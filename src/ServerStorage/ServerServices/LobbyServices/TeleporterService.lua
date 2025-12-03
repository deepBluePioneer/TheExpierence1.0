local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local TeleportService = game:GetService("TeleportService")

local Packages = ReplicatedStorage.Packages
local CustomPackages = ReplicatedStorage.CustomPackages
local Knit = require(Packages.Knit)
local Timer = require(Packages.timer)

-- Zone+ module
local ZoneRoot = CustomPackages:WaitForChild("ZoneRoot")
local Zone = require(ZoneRoot:WaitForChild("Zone"))

-- Replica module
local Replica = CustomPackages:WaitForChild("Replica")
local ReplicaService = require(Replica.ReplicaService)

-- TeleportQueue module
local TeleportQueueModule = require(CustomPackages:WaitForChild("TeleportQueue").TeleportQueueService)

-- Studio detection
local IS_STUDIO = RunService:IsStudio()

-- Place IDs
local LOBBY_PLACE_ID = 116406282300852
local MAIN_PLACE_ID = 93295390305658

-- Configuration
local CONFIG = {
	QUEUE_COUNTDOWN = 30, -- Seconds before auto-flush
	DEFAULT_MIN_PLAYERS = 2, -- Default minimum players to start countdown
	DEFAULT_MAX_PLAYERS = 2, -- Default max players per queue
	
	-- Place IDs for each teleporter
	TELEPORTER_DESTINATIONS = {
		Teleporter1 = MAIN_PLACE_ID,  -- Goes to main game (single-player test mode)
		Teleporter2 = MAIN_PLACE_ID,  -- Goes to main game
		Teleporter3 = LOBBY_PLACE_ID, -- Goes back to lobby
	},
	
	-- Per-teleporter max player settings (overrides DEFAULT_MAX_PLAYERS)
	TELEPORTER_MAX_PLAYERS = {
		Teleporter1 = 1, -- Single player only (for testing)
		Teleporter2 = 2, -- 2 players
		Teleporter3 = 2, -- 2 players
	},
	
	-- Per-teleporter min players to start countdown (overrides DEFAULT_MIN_PLAYERS)
	TELEPORTER_MIN_PLAYERS = {
		Teleporter1 = 1, -- Starts immediately with 1 player
		Teleporter2 = 2, -- Needs 2 players
		Teleporter3 = 2, -- Needs 2 players
	},
	
	-- Studio testing: Teleporter1 allows single-player teleport for testing
	STUDIO_TEST_TELEPORTER = "Teleporter1",
}

local TeleporterService = Knit.CreateService {
	Name = "TeleporterService",
	Client = {},
}

-- Store active zones and queues
TeleporterService.Zones = {}
TeleporterService.Queues = {} -- TeleportQueue per zone
TeleporterService.QueueTimers = {} -- Countdown timers per zone
TeleporterService.QueueReplica = nil -- Replica for popup UI data
TeleporterService.QueueCountReplica = nil -- Simple replica for billboard counts
-- 🔹 New: track counts per zone on the server
TeleporterService.CurrentQueueCounts = {} -- [zoneName] = current count
TeleporterService.MaxQueueCounts = {}     -- [zoneName] = max count
function TeleporterService:InitQueueReplica()
	-- Main replica for popup UI (complex data)
	self.QueueReplica = ReplicaService.NewReplica({
		ClassToken = ReplicaService.NewClassToken("TeleporterQueueReplica"),
		Data = {
			-- Per-zone queue data
			Queues = {
				-- ["Teleporter1Zone"] = { Players = {}, Countdown = 0, IsCountingDown = false }
			},
			-- Per-player current zone
			PlayerZones = {
				-- [userId] = { ZoneName = "", TeleporterName = "", ZoneColor = {R,G,B} }
			},
		},
		Replication = "All",
	})
	
	-- Simple replica just for billboard queue counts
	self.QueueCountReplica = ReplicaService.NewReplica({
		ClassToken = ReplicaService.NewClassToken("QueueCountReplica"),
		Data = {
			-- Simple: { [zoneName] = { Count = 0, Max = 8 } }
			Counts = {},
		},
		Replication = "All",
	})
end

function TeleporterService:InitQueueData(zoneName, teleporterName)
	-- Get per-teleporter max players (or use default)
	local maxPlayers = CONFIG.TELEPORTER_MAX_PLAYERS[teleporterName] or CONFIG.DEFAULT_MAX_PLAYERS

	-- 🔹 Store initial queue counts on the server
	self.CurrentQueueCounts[zoneName] = 0
	self.MaxQueueCounts[zoneName] = maxPlayers

	-- Initialize queue data in main replica (for popup UI)
	self.QueueReplica:SetValue({ "Queues", zoneName }, {
		Players = {},
		PlayerCount = 0,
		MaxPlayers = maxPlayers,
		Countdown = CONFIG.QUEUE_COUNTDOWN,
		IsCountingDown = false,
		TeleporterName = teleporterName,
		DestinationPlaceId = CONFIG.TELEPORTER_DESTINATIONS[teleporterName] or 0,
		IsSinglePlayer = maxPlayers == 1, -- Flag for UI to show appropriate text
	})

	-- Initialize the billboard count replica
	self.QueueCountReplica:SetValue({ "Counts", zoneName }, {
		Count = 0,      -- Current queue size
		Max = maxPlayers, -- Max allowed players
	})

	print("[TeleporterService] Initialized zone:", zoneName, "-> 0 /", maxPlayers)
end


function TeleporterService:CreateQueue(zoneName, teleporterName)
	local placeId = CONFIG.TELEPORTER_DESTINATIONS[teleporterName] or 0
	local maxPlayers = CONFIG.TELEPORTER_MAX_PLAYERS[teleporterName] or CONFIG.DEFAULT_MAX_PLAYERS
	
	local queue = TeleportQueueModule.new({
		PlaceId = placeId,
		Id = zoneName,
		MaxPlayers = maxPlayers,
		
		OnPlayerAdded = function(q, player)
			print("[TeleporterService] Player added to queue (callback):", player.Name, zoneName)
			-- DON'T call UpdateQueueReplica here (fires before internal state is updated)
		end,
		
		OnPlayerRemoved = function(q, player)
			print("[TeleporterService] Player removed from queue (callback):", player.Name, zoneName)
			-- DON'T call UpdateQueueReplica here either
		end,
		
		AllowedWithinQueue = function(q, player)
			return true
		end,
	})
	
	self.Queues[zoneName] = queue
	return queue
end


function TeleporterService:UpdateQueueReplica(zoneName)
	local queue = self.Queues[zoneName]
	if not queue then return end

	local playersTable = queue:GetPlayers()

	local playerNames = {}
	local currentCount = 0

	for _, player in pairs(playersTable) do
		currentCount += 1
		table.insert(playerNames, player.Name)
	end

	-- Get max from stored value (set during init)
	local maxCount = self.MaxQueueCounts[zoneName] or CONFIG.DEFAULT_MAX_PLAYERS

	-- 🔹 update tracked counts
	self.CurrentQueueCounts[zoneName] = currentCount

	-- Update main Replica (for popup UI)
	self.QueueReplica:SetValue({ "Queues", zoneName, "Players" }, playerNames)
	self.QueueReplica:SetValue({ "Queues", zoneName, "PlayerCount" }, currentCount)

	-- Update billboard count Replica (both current and max)
	self.QueueCountReplica:SetValue({ "Counts", zoneName, "Count" }, currentCount)
	self.QueueCountReplica:SetValue({ "Counts", zoneName, "Max" }, maxCount)

	-- 🔹 log current queue count
	print(("[TeleporterService] Queue '%s' count: %d/%d")
		:format(zoneName, currentCount, maxCount))
end


function TeleporterService:UpdatePlayerZone(player, zoneName, teleporterName, zoneColor)
	local userId = tostring(player.UserId)
	
	if zoneName and zoneName ~= "" then
		self.QueueReplica:SetValue({ "PlayerZones", userId }, {
			ZoneName = zoneName,
			TeleporterName = teleporterName or "",
			ZoneColor = zoneColor and {
				R = math.floor(zoneColor.R * 255),
				G = math.floor(zoneColor.G * 255),
				B = math.floor(zoneColor.B * 255),
			} or { R = 255, G = 255, B = 255 },
		})
	else
		self.QueueReplica:SetValue({ "PlayerZones", userId }, nil)
	end
end

function TeleporterService:CheckQueueCountdown(zoneName)
	local queue = self.Queues[zoneName]
	if not queue then return end
	
	-- Get teleporter name for this zone
	local zoneData = self.Zones[zoneName]
	local teleporterName = zoneData and zoneData.teleporterName or "Unknown"
	
	-- Get per-teleporter settings
	local minPlayers = CONFIG.TELEPORTER_MIN_PLAYERS[teleporterName] or CONFIG.DEFAULT_MIN_PLAYERS
	local maxPlayers = CONFIG.TELEPORTER_MAX_PLAYERS[teleporterName] or CONFIG.DEFAULT_MAX_PLAYERS
	
	local playersTable = queue:GetPlayers()
	local playerCount = 0

	for _, _ in pairs(playersTable) do
		playerCount += 1
	end

	-- Start countdown if minimum players reached
	if playerCount >= minPlayers and not self.QueueTimers[zoneName] then
		self:StartQueueCountdown(zoneName)
	-- Stop countdown if not enough players
	elseif playerCount < minPlayers and self.QueueTimers[zoneName] then
		self:StopQueueCountdown(zoneName)
	end
	
	-- Auto-flush if queue is full
	if playerCount >= maxPlayers then
		self:FlushQueue(zoneName)
	end
end


function TeleporterService:StartQueueCountdown(zoneName)
	if self.QueueTimers[zoneName] then return end
	
	local countdown = CONFIG.QUEUE_COUNTDOWN
	self.QueueReplica:SetValue({ "Queues", zoneName, "Countdown" }, countdown)
	self.QueueReplica:SetValue({ "Queues", zoneName, "IsCountingDown" }, true)
	
	local timer = Timer.new(1)
	self.QueueTimers[zoneName] = timer
	
	timer.Tick:Connect(function()
		countdown = countdown - 1
		self.QueueReplica:SetValue({ "Queues", zoneName, "Countdown" }, countdown)
		
		if countdown <= 0 then
			self:FlushQueue(zoneName)
		end
	end)
	
	timer:Start()
	print("[TeleporterService] Started countdown for", zoneName)
end

function TeleporterService:StopQueueCountdown(zoneName)
	local timer = self.QueueTimers[zoneName]
	if timer then
		timer:Stop()
		timer:Destroy()
		self.QueueTimers[zoneName] = nil
	end
	
	self.QueueReplica:SetValue({ "Queues", zoneName, "Countdown" }, CONFIG.QUEUE_COUNTDOWN)
	self.QueueReplica:SetValue({ "Queues", zoneName, "IsCountingDown" }, false)
	print("[TeleporterService] Stopped countdown for", zoneName)
end

function TeleporterService:FlushQueue(zoneName)
	local queue = self.Queues[zoneName]
	if not queue then return end
	
	-- Stop the countdown timer
	self:StopQueueCountdown(zoneName)
	
	-- Flush the queue (teleport all players)
	local result, teleportResult = queue:Flush()
	print("[TeleporterService] Flush result for", zoneName, ":", result)
	
	-- Update replica after flush
	self:UpdateQueueReplica(zoneName)
	
	-- Clear player zones for teleported players
	-- (They'll be gone from the game soon anyway)
end

-- Studio testing: Teleport a single player directly (bypasses queue system)
function TeleporterService:TeleportSinglePlayer(player, teleporterName)
	local placeId = CONFIG.TELEPORTER_DESTINATIONS[teleporterName]
	if not placeId then
		warn("[TeleporterService] No destination for teleporter:", teleporterName)
		return false
	end
	
	if IS_STUDIO then
		-- In Studio, teleports don't work to live games
		-- Show a message instead and simulate the teleport
		print("[TeleporterService] STUDIO MODE: Would teleport", player.Name, "to PlaceId:", placeId)
		print("[TeleporterService] Teleporter:", teleporterName)
		print("[TeleporterService] Destination:", placeId == MAIN_PLACE_ID and "Main Game" or "Lobby")
		
		-- You can still try the teleport - it will fail gracefully in Studio
		-- but this lets you test the flow
		local success, err = pcall(function()
			TeleportService:Teleport(placeId, player)
		end)
		
		if not success then
			print("[TeleporterService] STUDIO: Teleport blocked (expected):", err)
		end
		
		return true
	else
		-- Live game: Actually teleport
		local success, err = pcall(function()
			TeleportService:Teleport(placeId, player)
		end)
		
		if success then
			print("[TeleporterService] Teleported", player.Name, "to", placeId)
		else
			warn("[TeleporterService] Teleport failed:", err)
		end
		
		return success
	end
end

function TeleporterService:AddPlayerToQueue(player, zoneName)
	local queue = self.Queues[zoneName]
	if not queue then return false, "Queue not found" end
	
	local result = queue:Add(player)
	local success = result == TeleportQueueModule.AddResult.Success

	print("[TeleporterService] AddPlayerToQueue result:", success, result)

	if success then
		self:UpdateQueueReplica(zoneName)
		self:CheckQueueCountdown(zoneName)
	end

	return success, result
end

function TeleporterService:RemovePlayerFromQueue(player, zoneName)
	local queue = self.Queues[zoneName]
	if not queue then return false end
	
	local success = queue:Remove(player)

	print("[TeleporterService] RemovePlayerFromQueue result:", success)

	-- If your TeleportQueueService.Remove returns booleans or enums,
	-- adapt success check as needed. For now we just trust it.

	self:UpdateQueueReplica(zoneName)
	self:CheckQueueCountdown(zoneName)

	return success
end


function TeleporterService:RemovePlayerFromAllQueues(player)
	for zoneName, queue in pairs(self.Queues) do
		queue:Remove(player)
	end
end

function TeleporterService:SetupZone(zonePart)
	local zoneName = zonePart.Name
	local linkedTeleporter = zonePart:FindFirstChild("LinkedTeleporter")
	local teleporterRef = linkedTeleporter and linkedTeleporter.Value
	local teleporterName = teleporterRef and teleporterRef.Name or "Unknown"
	local zoneColor = teleporterRef and teleporterRef.Color or Color3.new(1, 1, 1)
	
	-- Create Zone+ zone
	local zone = Zone.new(zonePart)
	zone:setAccuracy("High")
	
	-- Initialize queue data and create queue
	self:InitQueueData(zoneName, teleporterName)
	self:CreateQueue(zoneName, teleporterName)
	
	self.Zones[zoneName] = {
		zone = zone,
		zonePart = zonePart,
		teleporterName = teleporterName,
		zoneColor = zoneColor,
	}
	
	-- Player entered zone -> Add to queue FIRST, then update player zone (triggers popup)
	zone.playerEntered:Connect(function(player)
		print("[TeleporterService]", player.Name, "entered", zoneName)
		
		-- STUDIO TEST MODE: If this is the test teleporter and we're in Studio,
		-- allow immediate single-player teleport
		if IS_STUDIO and teleporterName == CONFIG.STUDIO_TEST_TELEPORTER then
			print("[TeleporterService] STUDIO TEST MODE: Single-player teleport enabled for", teleporterName)
			self:UpdatePlayerZone(player, zoneName, teleporterName, zoneColor)
			
			-- Wait a moment then teleport (gives player time to see the zone)
			task.delay(2, function()
				-- Check if player is still in the zone
				local userId = tostring(player.UserId)
				local playerZoneData = self.QueueReplica.Data.PlayerZones[userId]
				if playerZoneData and playerZoneData.ZoneName == zoneName then
					self:TeleportSinglePlayer(player, teleporterName)
				end
			end)
			return
		end
		
		-- Add to queue first (updates count replica)
		local success, result = self:AddPlayerToQueue(player, zoneName)
		print("[TeleporterService] Add to queue result:", success, result)
		
		-- Then update player zone (triggers popup on client - now queue data is ready)
		self:UpdatePlayerZone(player, zoneName, teleporterName, zoneColor)
	end)
	
	-- Player exited zone -> Remove from queue FIRST, then update player zone
	zone.playerExited:Connect(function(player)
		print("[TeleporterService]", player.Name, "exited", zoneName)
		
		-- Remove from queue first (updates count replica)
		self:RemovePlayerFromQueue(player, zoneName)
		
		-- Then update player zone (hides popup on client)
		local userId = tostring(player.UserId)
		local playerZoneData = self.QueueReplica.Data.PlayerZones[userId]
		if playerZoneData and playerZoneData.ZoneName == zoneName then
			self:UpdatePlayerZone(player, nil, nil, nil)
		end
	end)
	
	print("[TeleporterService] Setup zone:", zoneName, "->", teleporterName)
end

function TeleporterService:SetupAllZones()
	local zonesFolder = workspace:FindFirstChild("TeleporterZones")
	if not zonesFolder then
		warn("[TeleporterService] TeleporterZones folder not found!")
		return
	end
	
	local zoneCount = 0
	for _, zonePart in ipairs(zonesFolder:GetChildren()) do
		-- Setup any BasePart in the folder (no tag required)
		if zonePart:IsA("BasePart") then
			self:SetupZone(zonePart)
			zoneCount = zoneCount + 1
		end
	end
	
	print("[TeleporterService] Setup", zoneCount, "zones")
end

function TeleporterService:OnPlayerRemoving(player)
	-- Remove from all queues
	self:RemovePlayerFromAllQueues(player)
	
	-- Clear player zone data
	local userId = tostring(player.UserId)
	self.QueueReplica:SetValue({ "PlayerZones", userId }, nil)
end

function TeleporterService:KnitInit()
	print("[TeleporterService] Initializing...")
	
	-- Initialize the queue replica
	self:InitQueueReplica()
	
	-- Handle player leaving
	Players.PlayerRemoving:Connect(function(player)
		self:OnPlayerRemoving(player)
	end)
end

function TeleporterService:KnitStart()
	print("[TeleporterService] Starting...")
	self:SetupAllZones()
end

return TeleporterService
