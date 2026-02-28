print("[HubQueueService] Module loading...")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local Packages = ReplicatedStorage.Packages
local Knit = require(Packages.Knit)
local Signal = require(Packages.Signal)
local Trove = require(Packages.Trove)
local Timer = require(Packages.timer)

local CustomPackages = ReplicatedStorage.CustomPackages
local TeleportQueue = require(CustomPackages.TeleportQueue.TeleportQueueService)
local Zone = require(CustomPackages.ZoneRoot.Zone)
local ReplicaService = require(CustomPackages.Replica.ReplicaService)

local TeleportConfig = require(ReplicatedStorage.Source.TeleportConfig)
local Analytics = require(ReplicatedStorage.Source.Analytics)

local QUEUE_STATE_WAITING = "WAITING"
local QUEUE_STATE_COUNTDOWN = "COUNTDOWN"
local QUEUE_STATE_TELEPORTING = "TELEPORTING"

local DEBOUNCE_INTERVAL = 0.5
local FAILURE_COOLDOWN = 8

local HubQueueService = Knit.CreateService {
	Name = "HubQueueService",
	Client = {
		QueueStateChanged = Knit.CreateSignal(),
	},

	_teleporters = {},
	_playerTeleporter = {},
	_playerDebounce = {},
	_trove = nil,

	TeleporterStateChanged = Signal.new(),
	PlayerQueued = Signal.new(),
	PlayerDequeued = Signal.new(),
}

local QueueReplicaClassToken = ReplicaService.NewClassToken("QueueState")

function HubQueueService:KnitInit()
	print("[HubQueueService] KnitInit")
	self._trove = Trove.new()
end

function HubQueueService:KnitStart()
	print("[HubQueueService] KnitStart")
	self:_setupTeleporters()

	self._trove:Add(Players.PlayerRemoving:Connect(function(player)
		self:_handlePlayerRemoving(player)
	end), "Disconnect")
end

function HubQueueService:_setupTeleporters()
	local teleporterParts = CollectionService:GetTagged("TeleporterZone")
	print("[HubQueueService] Found " .. #teleporterParts .. " tagged TeleporterZone parts")
	for _, part in ipairs(teleporterParts) do
		local teleporterId = part:GetAttribute("TeleporterId") or part.Name
		print("[HubQueueService] Registering teleporter: " .. tostring(teleporterId) .. " from part: " .. part:GetFullName())
		self:_registerTeleporter(teleporterId, part)
	end

	self._trove:Add(CollectionService:GetInstanceAddedSignal("TeleporterZone"):Connect(function(part)
		local teleporterId = part:GetAttribute("TeleporterId") or part.Name
		print("[HubQueueService] Late-tagged teleporter found: " .. tostring(teleporterId) .. " from part: " .. part:GetFullName())
		if not self._teleporters[teleporterId] then
			self:_registerTeleporter(teleporterId, part)
		end
	end), "Disconnect")
end

function HubQueueService:_registerTeleporter(teleporterId, zonePart)
	print("[HubQueueService] Creating zone for: " .. tostring(teleporterId) .. " | Part size: " .. tostring(zonePart.Size))
	local zone = Zone.new(zonePart)

	local queue = TeleportQueue.new({
		PlaceId = TeleportConfig.cityTrialPlaceId,
		MaxPlayers = TeleportConfig.maxPlayers,
		Id = teleporterId,
		OnPlayerAdded = function(_, player)
			self.PlayerQueued:Fire(player, teleporterId)
		end,
		OnPlayerRemoved = function(_, player)
			self.PlayerDequeued:Fire(player, teleporterId)
		end,
	})

	local replica = ReplicaService.NewReplica({
		ClassToken = QueueReplicaClassToken,
		Tags = { TeleporterId = teleporterId },
		Data = {
			state = QUEUE_STATE_WAITING,
			queueSize = 0,
			countdownEndTime = nil,
			lastError = nil,
		},
		Replication = "All",
	})

	local teleporterData = {
		id = teleporterId,
		zone = zone,
		queue = queue,
		replica = replica,
		countdownTimer = nil,
		maxWaitTimer = nil,
		state = QUEUE_STATE_WAITING,
		failureCooldownUntil = 0,
		trove = Trove.new(),
	}

	teleporterData.trove:Add(zone.playerEntered:Connect(function(player)
		print("[HubQueueService] zone.playerEntered fired for " .. player.Name)
		self:PlayerEnteredTeleporter(player, teleporterId)
	end), "Disconnect")

	teleporterData.trove:Add(zone.playerExited:Connect(function(player)
		print("[HubQueueService] zone.playerExited fired for " .. player.Name)
		self:PlayerLeftTeleporter(player, teleporterId)
	end), "Disconnect")

	-- Create a BillboardGui on the teleporter part for 3D queue display
	local billboard = self:_createBillboardGui(zonePart, teleporterId)
	teleporterData.billboard = billboard

	self._teleporters[teleporterId] = teleporterData
	print("[HubQueueService] Teleporter " .. tostring(teleporterId) .. " fully registered, zone signals connected")
	self._trove:Add(function()
		teleporterData.trove:Destroy()
		queue:Destroy()
		replica:Destroy()
		zone:Destroy()
		if billboard then billboard:Destroy() end
	end)
end

function HubQueueService:_createBillboardGui(part, teleporterId)
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "TeleporterUI_" .. tostring(teleporterId)
	billboard.Adornee = part
	billboard.Size = UDim2.fromScale(8, 4)
	billboard.StudsOffset = Vector3.new(0, part.Size.Y / 2 + 3, 0)
	billboard.AlwaysOnTop = false
	billboard.MaxDistance = 60
	billboard.Parent = part

	local bg = Instance.new("Frame")
	bg.Name = "Background"
	bg.Size = UDim2.fromScale(1, 1)
	bg.BackgroundColor3 = Color3.fromRGB(20, 20, 35)
	bg.BackgroundTransparency = 0.3
	bg.Parent = billboard

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.1, 0)
	corner.Parent = bg

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Size = UDim2.fromScale(1, 0.3)
	title.Position = UDim2.fromScale(0, 0.02)
	title.BackgroundTransparency = 1
	title.Text = "City Trial"
	title.TextColor3 = Color3.fromRGB(80, 220, 255)
	title.Font = Enum.Font.GothamBold
	title.TextScaled = true
	title.Parent = bg

	local queueLabel = Instance.new("TextLabel")
	queueLabel.Name = "QueueLabel"
	queueLabel.Size = UDim2.fromScale(1, 0.3)
	queueLabel.Position = UDim2.fromScale(0, 0.32)
	queueLabel.BackgroundTransparency = 1
	queueLabel.Text = "0 / " .. TeleportConfig.maxPlayers
	queueLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	queueLabel.Font = Enum.Font.GothamBold
	queueLabel.TextScaled = true
	queueLabel.Parent = bg

	local statusLabel = Instance.new("TextLabel")
	statusLabel.Name = "StatusLabel"
	statusLabel.Size = UDim2.fromScale(1, 0.28)
	statusLabel.Position = UDim2.fromScale(0, 0.65)
	statusLabel.BackgroundTransparency = 1
	statusLabel.Text = "Waiting for players..."
	statusLabel.TextColor3 = Color3.fromRGB(180, 180, 200)
	statusLabel.Font = Enum.Font.Gotham
	statusLabel.TextScaled = true
	statusLabel.Parent = bg

	return billboard
end

function HubQueueService:_updateBillboard(teleporter)
	local billboard = teleporter.billboard
	if not billboard then return end

	local bg = billboard:FindFirstChild("Background")
	if not bg then return end

	local queueLabel = bg:FindFirstChild("QueueLabel")
	local statusLabel = bg:FindFirstChild("StatusLabel")
	if not queueLabel or not statusLabel then return end

	local data = teleporter.replica.Data
	local size = data.queueSize or 0

	queueLabel.Text = size .. " / " .. TeleportConfig.maxPlayers

	if data.state == QUEUE_STATE_TELEPORTING then
		statusLabel.Text = "Teleporting!"
		statusLabel.TextColor3 = Color3.fromRGB(80, 255, 80)
		queueLabel.TextColor3 = Color3.fromRGB(80, 255, 80)
	elseif data.state == QUEUE_STATE_COUNTDOWN then
		local remaining = 0
		if data.countdownEndTime then
			remaining = math.max(0, math.ceil(data.countdownEndTime - os.clock()))
		end
		statusLabel.Text = "Starting in " .. remaining .. "s"
		statusLabel.TextColor3 = Color3.fromRGB(255, 220, 50)
		queueLabel.TextColor3 = Color3.fromRGB(255, 220, 50)
	else
		if data.lastError then
			statusLabel.Text = data.lastError
			statusLabel.TextColor3 = Color3.fromRGB(255, 100, 100)
		else
			statusLabel.Text = "Waiting for players..."
			statusLabel.TextColor3 = Color3.fromRGB(180, 180, 200)
		end
		queueLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	end
end

function HubQueueService:_isDebounced(player)
	local last = self._playerDebounce[player]
	local now = os.clock()
	if last and (now - last) < DEBOUNCE_INTERVAL then
		return true
	end
	self._playerDebounce[player] = now
	return false
end

function HubQueueService:PlayerEnteredTeleporter(player, teleporterId)
	print("[HubQueueService] " .. player.Name .. " entered teleporter: " .. tostring(teleporterId))
	if self:_isDebounced(player) then return end

	local teleporter = self._teleporters[teleporterId]
	if not teleporter then return end
	if teleporter.state == QUEUE_STATE_TELEPORTING then return end

	if os.clock() < teleporter.failureCooldownUntil then return end

	if self._playerTeleporter[player] then
		if self._playerTeleporter[player] ~= teleporterId then
			self:PlayerLeftTeleporter(player, self._playerTeleporter[player])
		else
			return
		end
	end

	local result = teleporter.queue:Add(player)
	if result ~= TeleportQueue.AddResult.Success then return end

	self._playerTeleporter[player] = teleporterId
	Analytics.TeleporterQueueJoined(player, teleporterId)
	Analytics.Funnel.OnboardingEnteredQueue(player)

	local queueSize = #teleporter.queue:GetPlayers()
	self:_updateReplica(teleporter, { queueSize = queueSize, lastError = nil })

	if queueSize >= TeleportConfig.maxPlayers then
		self:_AttemptTeleport(teleporterId)
		return
	end

	if queueSize >= TeleportConfig.minPlayers and teleporter.state == QUEUE_STATE_WAITING then
		self:_StartCountdown(teleporterId)
	elseif queueSize == 1 and not teleporter.maxWaitTimer then
		self:_startMaxWaitTimer(teleporterId)
	end
end

function HubQueueService:PlayerLeftTeleporter(player, teleporterId)
	if self:_isDebounced(player) then return end

	local teleporter = self._teleporters[teleporterId]
	if not teleporter then return end

	local removed = teleporter.queue:Remove(player)
	if not removed then return end

	if self._playerTeleporter[player] == teleporterId then
		self._playerTeleporter[player] = nil
	end

	local queueSize = #teleporter.queue:GetPlayers()
	self:_updateReplica(teleporter, { queueSize = queueSize })

	if teleporter.state == QUEUE_STATE_COUNTDOWN and queueSize < TeleportConfig.minPlayers then
		self:_CancelCountdown(teleporterId, "Not enough players")
	end

	if queueSize == 0 then
		self:_stopMaxWaitTimer(teleporterId)
	end
end

function HubQueueService:_startMaxWaitTimer(teleporterId)
	local teleporter = self._teleporters[teleporterId]
	if not teleporter or teleporter.maxWaitTimer then return end

	local elapsed = 0
	local timer = Timer.new(1)
	timer.Tick:Connect(function()
		elapsed = elapsed + 1
		if elapsed >= TeleportConfig.maxWaitTimeSeconds then
			timer:Stop()
			timer:Destroy()
			teleporter.maxWaitTimer = nil

			local queueSize = #teleporter.queue:GetPlayers()
			if queueSize >= TeleportConfig.minPlayers then
				self:_AttemptTeleport(teleporterId)
			end
		end
	end)
	timer:Start()
	teleporter.maxWaitTimer = timer
end

function HubQueueService:_stopMaxWaitTimer(teleporterId)
	local teleporter = self._teleporters[teleporterId]
	if not teleporter or not teleporter.maxWaitTimer then return end

	teleporter.maxWaitTimer:Stop()
	teleporter.maxWaitTimer:Destroy()
	teleporter.maxWaitTimer = nil
end

function HubQueueService:_StartCountdown(teleporterId)
	local teleporter = self._teleporters[teleporterId]
	if not teleporter then return end
	if teleporter.state ~= QUEUE_STATE_WAITING then return end

	self:_stopMaxWaitTimer(teleporterId)

	teleporter.state = QUEUE_STATE_COUNTDOWN
	local countdownEnd = os.clock() + TeleportConfig.countdownDuration

	self:_updateReplica(teleporter, {
		state = QUEUE_STATE_COUNTDOWN,
		countdownEndTime = countdownEnd,
	})

	self.TeleporterStateChanged:Fire(teleporterId, {
		state = QUEUE_STATE_COUNTDOWN,
		queueSize = #teleporter.queue:GetPlayers(),
		countdownEndTime = countdownEnd,
	})

	local remaining = TeleportConfig.countdownDuration
	local timer = Timer.new(1)
	timer.Tick:Connect(function()
		remaining = remaining - 1
		self:_updateBillboard(teleporter)
		if remaining <= 0 then
			timer:Stop()
			timer:Destroy()
			teleporter.countdownTimer = nil
			self:_AttemptTeleport(teleporterId)
		end
	end)
	timer:Start()
	teleporter.countdownTimer = timer
end

function HubQueueService:_CancelCountdown(teleporterId, reason)
	local teleporter = self._teleporters[teleporterId]
	if not teleporter then return end

	if teleporter.countdownTimer then
		teleporter.countdownTimer:Stop()
		teleporter.countdownTimer:Destroy()
		teleporter.countdownTimer = nil
	end

	teleporter.state = QUEUE_STATE_WAITING
	self:_updateReplica(teleporter, {
		state = QUEUE_STATE_WAITING,
		countdownEndTime = nil,
		lastError = reason,
	})

	self.TeleporterStateChanged:Fire(teleporterId, {
		state = QUEUE_STATE_WAITING,
		queueSize = #teleporter.queue:GetPlayers(),
	})

	local queueSize = #teleporter.queue:GetPlayers()
	if queueSize > 0 then
		self:_startMaxWaitTimer(teleporterId)
	end
end

function HubQueueService:_AttemptTeleport(teleporterId)
	local teleporter = self._teleporters[teleporterId]
	if not teleporter then return end

	if teleporter.countdownTimer then
		teleporter.countdownTimer:Stop()
		teleporter.countdownTimer:Destroy()
		teleporter.countdownTimer = nil
	end
	self:_stopMaxWaitTimer(teleporterId)

	local playersInQueue = teleporter.queue:GetPlayers()
	if #playersInQueue < TeleportConfig.minPlayers then
		self:_CancelCountdown(teleporterId, "Not enough players to teleport")
		return
	end

	local validPlayers = {}
	for _, player in ipairs(playersInQueue) do
		if player:IsDescendantOf(Players) then
			table.insert(validPlayers, player)
		end
	end

	if #validPlayers < TeleportConfig.minPlayers then
		self:_CancelCountdown(teleporterId, "Not enough valid players")
		return
	end

	teleporter.state = QUEUE_STATE_TELEPORTING
	self:_updateReplica(teleporter, {
		state = QUEUE_STATE_TELEPORTING,
		lastError = nil,
	})

	self.TeleporterStateChanged:Fire(teleporterId, {
		state = QUEUE_STATE_TELEPORTING,
		queueSize = #validPlayers,
	})

	local flushResult, teleportResult = teleporter.queue:Flush()

	if flushResult == TeleportQueue.FlushResult.Success then
		for _, player in ipairs(validPlayers) do
			self._playerTeleporter[player] = nil
			Analytics.TeleportedToCityTrial(player)
			Analytics.Funnel.OnboardingTeleported(player)
		end

		teleporter.state = QUEUE_STATE_WAITING
		self:_updateReplica(teleporter, {
			state = QUEUE_STATE_WAITING,
			queueSize = 0,
			countdownEndTime = nil,
		})
	else
		self:_HandleTeleportFailure(teleporterId, validPlayers, tostring(teleportResult))
	end
end

function HubQueueService:_HandleTeleportFailure(teleporterId, players, errorCode)
	local teleporter = self._teleporters[teleporterId]
	if not teleporter then return end

	warn("[HubQueueService] Teleport failed for " .. teleporterId .. ": " .. (errorCode or "unknown"))

	teleporter.failureCooldownUntil = os.clock() + FAILURE_COOLDOWN

	for _, player in ipairs(players) do
		if player:IsDescendantOf(Players) then
			local result = teleporter.queue:Add(player)
			if result == TeleportQueue.AddResult.Success then
				self._playerTeleporter[player] = teleporterId
			end
		end
	end

	teleporter.state = QUEUE_STATE_WAITING
	local queueSize = #teleporter.queue:GetPlayers()
	self:_updateReplica(teleporter, {
		state = QUEUE_STATE_WAITING,
		queueSize = queueSize,
		countdownEndTime = nil,
		lastError = "Teleport failed — retrying soon",
	})

	self.TeleporterStateChanged:Fire(teleporterId, {
		state = QUEUE_STATE_WAITING,
		queueSize = queueSize,
		lastError = errorCode,
	})

	if queueSize > 0 then
		self:_startMaxWaitTimer(teleporterId)
	end
end

function HubQueueService:_handlePlayerRemoving(player)
	self._playerDebounce[player] = nil

	local teleporterId = self._playerTeleporter[player]
	if not teleporterId then return end

	local teleporter = self._teleporters[teleporterId]
	if not teleporter then
		self._playerTeleporter[player] = nil
		return
	end

	teleporter.queue:Remove(player)
	self._playerTeleporter[player] = nil

	local queueSize = #teleporter.queue:GetPlayers()
	self:_updateReplica(teleporter, { queueSize = queueSize })

	if teleporter.state == QUEUE_STATE_COUNTDOWN and queueSize < TeleportConfig.minPlayers then
		self:_CancelCountdown(teleporterId, "Player left, not enough players")
	end

	if queueSize == 0 then
		self:_stopMaxWaitTimer(teleporterId)
	end
end

function HubQueueService:_updateReplica(teleporter, changes)
	local replica = teleporter.replica
	for key, value in pairs(changes) do
		replica:SetValue({ key }, value)
	end

	self:_updateBillboard(teleporter)

	local state = replica.Data
	self.Client.QueueStateChanged:FireAll(teleporter.id, {
		state = state.state,
		queueSize = state.queueSize,
		countdownEndTime = state.countdownEndTime,
		lastError = state.lastError,
	})
end

function HubQueueService:GetQueueState(teleporterId)
	local teleporter = self._teleporters[teleporterId]
	if not teleporter then return nil end

	local data = teleporter.replica.Data
	return {
		state = data.state,
		queueSize = data.queueSize,
		countdownEndTime = data.countdownEndTime,
		lastError = data.lastError,
	}
end

function HubQueueService:GetTeleporterConfig(teleporterId)
	return {
		placeId = TeleportConfig.cityTrialPlaceId,
		minPlayers = TeleportConfig.minPlayers,
		maxPlayers = TeleportConfig.maxPlayers,
		maxWaitTimeSeconds = TeleportConfig.maxWaitTimeSeconds,
		countdownDuration = TeleportConfig.countdownDuration,
	}
end

----------------------------------------------------------------
-- Client-exposed methods
----------------------------------------------------------------

function HubQueueService.Client:GetQueueState(player, teleporterId)
	return self.Server:GetQueueState(teleporterId)
end

function HubQueueService.Client:GetTeleporterConfig(player, teleporterId)
	return self.Server:GetTeleporterConfig(teleporterId)
end

function HubQueueService.Client:JoinQueue(player, teleporterId)
	self.Server:PlayerEnteredTeleporter(player, teleporterId)
	return true
end

function HubQueueService.Client:LeaveQueue(player, teleporterId)
	self.Server:PlayerLeftTeleporter(player, teleporterId)
end

return HubQueueService
