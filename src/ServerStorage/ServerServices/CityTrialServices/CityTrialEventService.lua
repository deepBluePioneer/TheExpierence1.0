local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local TweenService = game:GetService("TweenService")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Packages = ReplicatedStorage.Packages
local Knit = require(Packages.Knit)
local Signal = require(Packages.Signal)
local Trove = require(Packages.Trove)
local Timer = require(Packages.timer)

local CustomPackages = ReplicatedStorage.CustomPackages
local ReplicaService = require(CustomPackages.Replica.ReplicaService)

local EventsConfig = require(ReplicatedStorage.Source.EventsConfig)
local GameConfig = require(ReplicatedStorage.Source.GameConfig)
local Analytics = require(ReplicatedStorage.Source.Analytics)

local CityTrialEventService = Knit.CreateService {
	Name = "CityTrialEventService",
	Client = {
		EventStarted = Knit.CreateSignal(),
		EventEnded = Knit.CreateSignal(),
		EventWarning = Knit.CreateSignal(),
	},

	_trove = nil,
	_enabled = false,
	_activeEvents = {},
	_activeEventCount = 0,
	_lastEventEndTime = 0,
	_schedulerTimer = nil,
	_eventReplica = nil,

	EventStarted = Signal.new(),
	EventEnded = Signal.new(),
}

local EventReplicaClassToken = ReplicaService.NewClassToken("EventState")

-- Weighted random event selection
local _weightedPool = {}
local _totalWeight = 0

local function buildWeightedPool()
	_weightedPool = {}
	_totalWeight = 0
	for eventId, config in pairs(EventsConfig.events) do
		_totalWeight = _totalWeight + (config.weight or 1)
		table.insert(_weightedPool, {
			eventId = eventId,
			cumulativeWeight = _totalWeight,
		})
	end
end

local function getRandomEventId()
	local roll = math.random() * _totalWeight
	for _, entry in ipairs(_weightedPool) do
		if roll <= entry.cumulativeWeight then
			return entry.eventId
		end
	end
	return _weightedPool[#_weightedPool].eventId
end

----------------------------------------------------------------
-- Lifecycle
----------------------------------------------------------------

function CityTrialEventService:KnitInit()
	self._trove = Trove.new()
	buildWeightedPool()
end

function CityTrialEventService:KnitStart()
	local matchService = Knit.GetService("CityTrialMatchService")

	matchService.MatchStarted:Connect(function()
		self:StartScheduler()
	end)

	matchService.MatchEnded:Connect(function()
		self:StopScheduler()
	end)
end

function CityTrialEventService:StartScheduler()
	if self._enabled then return end
	self._enabled = true

	self._eventReplica = ReplicaService.NewReplica({
		ClassToken = EventReplicaClassToken,
		Tags = {},
		Data = {
			activeEvents = {},
		},
		Replication = "All",
	})

	self._trove:Add(function()
		if self._eventReplica then
			self._eventReplica:Destroy()
			self._eventReplica = nil
		end
	end)

	self:_scheduleNext()
	print("[CityTrialEventService] Scheduler started")
end

function CityTrialEventService:StopScheduler()
	self._enabled = false

	if self._schedulerTimer then
		self._schedulerTimer:Stop()
		self._schedulerTimer:Destroy()
		self._schedulerTimer = nil
	end

	for eventId, eventData in pairs(self._activeEvents) do
		self:_endEvent(eventId)
	end

	self._activeEvents = {}
	self._activeEventCount = 0

	print("[CityTrialEventService] Scheduler stopped, all events cleared")
end

function CityTrialEventService:_scheduleNext()
	if not self._enabled then return end

	local delay = math.random(EventsConfig.scheduleIntervalMin, EventsConfig.scheduleIntervalMax)

	self._schedulerTimer = Timer.new(delay)
	self._schedulerTimer.Tick:Connect(function()
		self._schedulerTimer:Stop()
		self._schedulerTimer:Destroy()
		self._schedulerTimer = nil

		if not self._enabled then return end

		local now = os.clock()
		if now - self._lastEventEndTime < EventsConfig.minCooldownSeconds then
			self:_scheduleNext()
			return
		end

		if self._activeEventCount >= EventsConfig.maxConcurrentEvents then
			self:_scheduleNext()
			return
		end

		local eventId = getRandomEventId()
		while self._activeEvents[eventId] do
			eventId = getRandomEventId()
		end

		self:_triggerEvent(eventId)
		self:_scheduleNext()
	end)
	self._schedulerTimer:Start()
end

----------------------------------------------------------------
-- Event trigger + dispatch
----------------------------------------------------------------

function CityTrialEventService:_triggerEvent(eventId)
	local config = EventsConfig.events[eventId]
	if not config then return end

	print("[CityTrialEventService] Warning: " .. config.displayName .. " in " .. config.warningSeconds .. "s")

	self.Client.EventWarning:FireAll(eventId, config.displayName, config.warningSeconds)

	task.delay(config.warningSeconds, function()
		if not self._enabled then return end
		self:_startEvent(eventId)
	end)
end

function CityTrialEventService:_startEvent(eventId)
	if not self._enabled then return end

	local config = EventsConfig.events[eventId]
	if not config then return end

	local eventTrove = Trove.new()

	local eventData = {
		id = eventId,
		config = config,
		startTime = os.clock(),
		trove = eventTrove,
	}

	self._activeEvents[eventId] = eventData
	self._activeEventCount = self._activeEventCount + 1

	self:_updateEventReplica()

	print("[CityTrialEventService] Started: " .. config.displayName .. " (" .. config.duration .. "s)")
	self.EventStarted:Fire(eventId, config)
	self.Client.EventStarted:FireAll(eventId, config.displayName, config.duration)

	for _, player in ipairs(Players:GetPlayers()) do
		Analytics.EventTriggered(player, eventId)
	end

	-- Dispatch to handler
	if eventId == "meteor_shower" then
		self:_runMeteorShower(eventData)
	elseif eventId == "rain" then
		self:_runRain(eventData)
	elseif eventId == "fog" then
		self:_runFog(eventData)
	elseif eventId == "shockwave" then
		self:_runShockwave(eventData)
	elseif eventId == "area_hazard" then
		self:_runAreaHazard(eventData)
	elseif eventId == "patch_rain" then
		self:_runPatchRain(eventData)
	elseif eventId == "wind" then
		self:_runWind(eventData)
	end

	-- Auto-end after duration
	task.delay(config.duration, function()
		if self._activeEvents[eventId] then
			self:_endEvent(eventId)
		end
	end)
end

function CityTrialEventService:_endEvent(eventId)
	local eventData = self._activeEvents[eventId]
	if not eventData then return end

	eventData.trove:Destroy()

	self._activeEvents[eventId] = nil
	self._activeEventCount = math.max(0, self._activeEventCount - 1)
	self._lastEventEndTime = os.clock()

	self:_updateEventReplica()

	print("[CityTrialEventService] Ended: " .. eventData.config.displayName)
	self.EventEnded:Fire(eventId, eventData.config)
	self.Client.EventEnded:FireAll(eventId, eventData.config.displayName)
end

function CityTrialEventService:_updateEventReplica()
	if not self._eventReplica then return end

	local active = {}
	for eventId, eventData in pairs(self._activeEvents) do
		active[eventId] = {
			displayName = eventData.config.displayName,
			remaining = math.max(0, eventData.config.duration - (os.clock() - eventData.startTime)),
		}
	end

	self._eventReplica:SetValue({ "activeEvents" }, active)
end

----------------------------------------------------------------
-- METEOR SHOWER
----------------------------------------------------------------

function CityTrialEventService:_runMeteorShower(eventData)
	local config = eventData.config
	local count = math.random(config.meteorCount.min, config.meteorCount.max)
	local interval = config.duration / count

	for i = 1, count do
		task.delay(interval * (i - 1), function()
			if not self._enabled or not self._activeEvents[eventData.id] then return end
			self:_spawnMeteor(config.damage)
		end)
	end
end

function CityTrialEventService:_spawnMeteor(damage)
	local bounds = self:_getMapBounds()
	local x = math.random(bounds.minX, bounds.maxX)
	local z = math.random(bounds.minZ, bounds.maxZ)

	local groundY = self:_getGroundHeight(x, z) or 0
	local impactPos = Vector3.new(x, groundY, z)

	-- Warning shadow on ground
	local shadow = Instance.new("Part")
	shadow.Name = "MeteorShadow"
	shadow.Shape = Enum.PartType.Cylinder
	shadow.Size = Vector3.new(0.2, 8, 8)
	shadow.CFrame = CFrame.new(impactPos + Vector3.new(0, 0.1, 0)) * CFrame.Angles(0, 0, math.rad(90))
	shadow.Anchored = true
	shadow.CanCollide = false
	shadow.CanTouch = false
	shadow.Material = Enum.Material.Neon
	shadow.Color = Color3.fromRGB(255, 50, 50)
	shadow.Transparency = 0.5
	shadow.Parent = Workspace

	-- Grow shadow over warning period
	TweenService:Create(shadow, TweenInfo.new(1.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(0.2, 14, 14),
		Transparency = 0.2,
	}):Play()

	task.delay(1.8, function()
		-- Meteor impact
		local explosion = Instance.new("Part")
		explosion.Name = "MeteorImpact"
		explosion.Shape = Enum.PartType.Ball
		explosion.Size = Vector3.new(2, 2, 2)
		explosion.CFrame = CFrame.new(impactPos)
		explosion.Anchored = true
		explosion.CanCollide = false
		explosion.CanTouch = false
		explosion.Material = Enum.Material.Neon
		explosion.Color = Color3.fromRGB(255, 120, 30)
		explosion.Parent = Workspace

		-- Expand + fade
		TweenService:Create(explosion, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Size = Vector3.new(16, 16, 16),
			Transparency = 1,
		}):Play()

		-- Damage nearby players
		for _, player in ipairs(Players:GetPlayers()) do
			local character = player.Character
			if not character then continue end
			local rootPart = character:FindFirstChild("HumanoidRootPart")
			if not rootPart then continue end

			local dist = (rootPart.Position - impactPos).Magnitude
			if dist <= 12 then
				local CityTrialPlayerService = Knit.GetService("CityTrialPlayerService")
				local session = CityTrialPlayerService:GetSessionData(player)
				if session then
					session.damageTaken = (session.damageTaken or 0) + damage
				end
				Analytics.EventDamageTaken(player, "meteor_shower", damage)
				print("[MeteorShower] " .. player.Name .. " hit by meteor for " .. damage .. " damage")
			end
		end

		task.delay(0.6, function()
			explosion:Destroy()
		end)

		shadow:Destroy()
	end)
end

----------------------------------------------------------------
-- RAIN
----------------------------------------------------------------

function CityTrialEventService:_runRain(eventData)
	local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
	local originalDensity = atmosphere and atmosphere.Density or 0.3
	local originalHaze = atmosphere and atmosphere.Haze or 0

	if atmosphere then
		TweenService:Create(atmosphere, TweenInfo.new(2), {
			Density = 0.6,
			Haze = 5,
		}):Play()
	end

	Lighting.Brightness = 1.5
	Lighting.FogEnd = 300

	TweenService:Create(Lighting, TweenInfo.new(2), {
		Brightness = 0.8,
		FogEnd = 150,
		FogColor = Color3.fromRGB(130, 140, 160),
	}):Play()

	eventData.trove:Add(function()
		TweenService:Create(Lighting, TweenInfo.new(3), {
			Brightness = 1.5,
			FogEnd = 100000,
			FogColor = Color3.fromRGB(192, 192, 192),
		}):Play()

		if atmosphere then
			TweenService:Create(atmosphere, TweenInfo.new(3), {
				Density = originalDensity,
				Haze = originalHaze,
			}):Play()
		end
	end)
end

----------------------------------------------------------------
-- FOG
----------------------------------------------------------------

function CityTrialEventService:_runFog(eventData)
	local originalFogEnd = Lighting.FogEnd

	TweenService:Create(Lighting, TweenInfo.new(2), {
		FogEnd = 80,
		FogColor = Color3.fromRGB(200, 200, 210),
	}):Play()

	eventData.trove:Add(function()
		TweenService:Create(Lighting, TweenInfo.new(3), {
			FogEnd = 100000,
			FogColor = Color3.fromRGB(192, 192, 192),
		}):Play()
	end)
end

----------------------------------------------------------------
-- SHOCKWAVE
----------------------------------------------------------------

function CityTrialEventService:_runShockwave(eventData)
	local config = eventData.config
	local bounds = self:_getMapBounds()

	local x = math.random(bounds.minX, bounds.maxX)
	local z = math.random(bounds.minZ, bounds.maxZ)
	local groundY = self:_getGroundHeight(x, z) or 0
	local origin = Vector3.new(x, groundY + 2, z)

	-- Visual ring
	local ring = Instance.new("Part")
	ring.Name = "ShockwaveRing"
	ring.Shape = Enum.PartType.Cylinder
	ring.Size = Vector3.new(1, 4, 4)
	ring.CFrame = CFrame.new(origin) * CFrame.Angles(0, 0, math.rad(90))
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanTouch = false
	ring.Material = Enum.Material.Neon
	ring.Color = Color3.fromRGB(255, 200, 50)
	ring.Transparency = 0.3
	ring.Parent = Workspace

	local expandSize = Vector3.new(1, config.radius * 2, config.radius * 2)
	TweenService:Create(ring, TweenInfo.new(1.0, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = expandSize,
		Transparency = 1,
	}):Play()

	-- Apply knockback + damage to nearby players
	task.delay(0.3, function()
		for _, player in ipairs(Players:GetPlayers()) do
			local character = player.Character
			if not character then continue end
			local rootPart = character:FindFirstChild("HumanoidRootPart")
			if not rootPart then continue end

			local diff = rootPart.Position - origin
			local dist = diff.Magnitude
			if dist <= config.radius then
				local dir = dist > 0 and diff.Unit or Vector3.new(0, 1, 0)
				local knockback = dir * config.knockbackForce + Vector3.new(0, config.knockbackForce * 0.5, 0)
				rootPart:ApplyImpulse(knockback * rootPart.AssemblyMass)

				local CityTrialPlayerService = Knit.GetService("CityTrialPlayerService")
				local session = CityTrialPlayerService:GetSessionData(player)
				if session then
					session.damageTaken = (session.damageTaken or 0) + config.damage
				end
				Analytics.EventDamageTaken(player, "shockwave", config.damage)
				print("[Shockwave] " .. player.Name .. " knocked back (" .. config.damage .. " dmg)")
			end
		end
	end)

	task.delay(1.5, function()
		ring:Destroy()
	end)
end

----------------------------------------------------------------
-- AREA HAZARD (Danger Zone)
----------------------------------------------------------------

function CityTrialEventService:_runAreaHazard(eventData)
	local config = eventData.config
	local bounds = self:_getMapBounds()

	local x = math.random(bounds.minX, bounds.maxX)
	local z = math.random(bounds.minZ, bounds.maxZ)
	local groundY = self:_getGroundHeight(x, z) or 0
	local center = Vector3.new(x, groundY + 0.5, z)

	-- Visual danger zone
	local zonePart = Instance.new("Part")
	zonePart.Name = "DangerZone"
	zonePart.Shape = Enum.PartType.Cylinder
	zonePart.Size = Vector3.new(1, config.radius * 2, config.radius * 2)
	zonePart.CFrame = CFrame.new(center) * CFrame.Angles(0, 0, math.rad(90))
	zonePart.Anchored = true
	zonePart.CanCollide = false
	zonePart.CanTouch = false
	zonePart.Material = Enum.Material.Neon
	zonePart.Color = Color3.fromRGB(255, 50, 50)
	zonePart.Transparency = 0.7
	zonePart.Parent = Workspace

	eventData.trove:Add(function()
		zonePart:Destroy()
	end)

	-- Tick damage to players inside the zone
	local tickTimer = Timer.new(config.tickInterval)
	tickTimer.Tick:Connect(function()
		if not self._activeEvents[eventData.id] then
			tickTimer:Stop()
			tickTimer:Destroy()
			return
		end

		for _, player in ipairs(Players:GetPlayers()) do
			local character = player.Character
			if not character then continue end
			local rootPart = character:FindFirstChild("HumanoidRootPart")
			if not rootPart then continue end

			local dist = (Vector3.new(rootPart.Position.X, center.Y, rootPart.Position.Z) - center).Magnitude
			if dist <= config.radius then
				local CityTrialPlayerService = Knit.GetService("CityTrialPlayerService")
				local session = CityTrialPlayerService:GetSessionData(player)
				if session then
					session.damageTaken = (session.damageTaken or 0) + config.tickDamage
					Analytics.EventDamageTaken(player, "area_hazard", config.tickDamage)
				end
			end
		end
	end)
	tickTimer:Start()

	eventData.trove:Add(function()
		tickTimer:Stop()
		tickTimer:Destroy()
	end)
end

----------------------------------------------------------------
-- PATCH RAIN
----------------------------------------------------------------

function CityTrialEventService:_runPatchRain(eventData)
	local config = eventData.config

	local ok, patchService = pcall(function()
		return Knit.GetService("CityTrialPatchSpawnService")
	end)

	if ok and patchService then
		patchService:SpawnBonusWave(config.bonusPatches, config.duration)
		print("[CityTrialEventService] Patch Rain: spawning " .. config.bonusPatches .. " bonus patches")
	else
		warn("[CityTrialEventService] CityTrialPatchSpawnService not available for Patch Rain")
	end
end

----------------------------------------------------------------
-- WIND
----------------------------------------------------------------

function CityTrialEventService:_runWind(eventData)
	local config = eventData.config

	local windDir = Vector3.new(
		math.random() * 2 - 1,
		0,
		math.random() * 2 - 1
	).Unit

	-- Apply wind force to all players via BodyForce or LinearVelocity
	local windParts = {}

	local applyWind
	applyWind = function()
		for _, player in ipairs(Players:GetPlayers()) do
			local character = player.Character
			if not character then continue end
			local rootPart = character:FindFirstChild("HumanoidRootPart")
			if not rootPart then continue end

			if not windParts[player] then
				local attachment = rootPart:FindFirstChild("WindAttachment")
				if not attachment then
					attachment = Instance.new("Attachment")
					attachment.Name = "WindAttachment"
					attachment.Parent = rootPart
				end

				local force = Instance.new("LinearVelocity")
				force.Name = "WindForce"
				force.Attachment0 = attachment
				force.VelocityConstraintMode = Enum.VelocityConstraintMode.Line
				force.LineDirection = windDir
				force.LineVelocity = config.windForce
				force.MaxForce = config.windForce * rootPart.AssemblyMass * 0.3
				force.RelativeTo = Enum.ActuatorRelativeTo.World
				force.Parent = rootPart

				windParts[player] = { force = force, attachment = attachment }
			end
		end
	end

	applyWind()

	local windTimer = Timer.new(2)
	windTimer.Tick:Connect(function()
		if not self._activeEvents[eventData.id] then
			windTimer:Stop()
			windTimer:Destroy()
			return
		end
		applyWind()
	end)
	windTimer:Start()

	eventData.trove:Add(function()
		windTimer:Stop()
		windTimer:Destroy()

		for _, data in pairs(windParts) do
			data.force:Destroy()
			data.attachment:Destroy()
		end
		windParts = {}
	end)
end

----------------------------------------------------------------
-- Helpers
----------------------------------------------------------------

function CityTrialEventService:_getMapBounds()
	local CollectionService = game:GetService("CollectionService")
	local boundsPart = CollectionService:GetTagged("PatchSpawnBounds")[1]
	if boundsPart and boundsPart:IsA("BasePart") then
		local pos = boundsPart.Position
		local half = boundsPart.Size / 2
		return {
			minX = math.floor(pos.X - half.X),
			maxX = math.floor(pos.X + half.X),
			minZ = math.floor(pos.Z - half.Z),
			maxZ = math.floor(pos.Z + half.Z),
		}
	end
	return { minX = -150, maxX = 150, minZ = -150, maxZ = 150 }
end

function CityTrialEventService:_getGroundHeight(x, z)
	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.FilterDescendantsInstances = {}

	local result = Workspace:Raycast(Vector3.new(x, 500, z), Vector3.new(0, -1000, 0), rayParams)
	return result and result.Position.Y or nil
end

function CityTrialEventService:GetActiveEvents()
	local result = {}
	for eventId, data in pairs(self._activeEvents) do
		result[eventId] = {
			displayName = data.config.displayName,
			remaining = math.max(0, data.config.duration - (os.clock() - data.startTime)),
		}
	end
	return result
end

return CityTrialEventService
