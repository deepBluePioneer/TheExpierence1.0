local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Knit = require(ReplicatedStorage.Packages.Knit)

local SCAN_TICK_RATE = 1 / 10 -- 10 Hz
local DAMAGE_PER_SECOND = 5
local DWELL_TIME_MIN = 2
local DWELL_TIME_MAX = 3.5
local LERP_SPEED = 1.5

local BEAM_HALF_ANGLE = 2
local BEAM_HALF_ANGLE_COS = math.cos(math.rad(BEAM_HALF_ANGLE))

local SEARCH_RADIUS = 40
local SEARCH_DURATION = 5
local SEARCH_SWEEP_SPEED = 3
local SEARCH_DWELL_MIN = 0.4
local SEARCH_DWELL_MAX = 0.8

local EyeOfSauronService = Knit.CreateService({
	Name = "EyeOfSauronService",
	Client = {
		EyeUpdate = Knit.CreateSignal(),
	},
})

function EyeOfSauronService:KnitInit()
	self._eyeOrigin = nil
	self._eyeModel = nil

	self._state = "scanning" -- "scanning" | "locked" | "searching"
	self._lockedPlayer = nil

	self._currentTarget = nil
	self._nextTarget = nil
	self._lerpAlpha = 1
	self._dwellTimer = 0
	self._dwellDuration = 0
	self._tickAccumulator = 0

	self._searchOrigin = nil
	self._searchTimer = 0
	self._searchCurrentTarget = nil
	self._searchNextTarget = nil
	self._searchLerpAlpha = 1
	self._searchDwellTimer = 0
	self._searchDwellDuration = 0

	self._raycastParams = nil

	self._terrainMinX = 0
	self._terrainMaxX = 0
	self._terrainMinZ = 0
	self._terrainMaxZ = 0
	self._terrainSurfaceY = 0
end

function EyeOfSauronService:KnitStart()
	local eyeModel = Workspace:FindFirstChild("eye")
	if not eyeModel then
		warn("[EyeOfSauronService] No 'eye' model found in Workspace")
		return
	end

	self._eyeModel = eyeModel
	self._eyeOrigin = eyeModel.PrimaryPart.Position

	local terrainService = Knit.GetService("ProvingGroundsTerrainService")
	local minX, maxX, minZ, maxZ, surfaceY = terrainService:GetBounds()
	self._terrainMinX = minX
	self._terrainMaxX = maxX
	self._terrainMinZ = minZ
	self._terrainMaxZ = maxZ
	self._terrainSurfaceY = surfaceY

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { eyeModel }
	self._raycastParams = params

	self._currentTarget = self:_pickRandomTarget()
	self._nextTarget = self:_pickRandomTarget()
	self._dwellDuration = math.random() * (DWELL_TIME_MAX - DWELL_TIME_MIN) + DWELL_TIME_MIN

	RunService.Heartbeat:Connect(function(dt)
		self:_update(dt)
	end)

	print("[EyeOfSauronService] Eye of Sauron active at " .. tostring(self._eyeOrigin))
end

function EyeOfSauronService:_pickRandomTarget()
	local x = self._terrainMinX + math.random() * (self._terrainMaxX - self._terrainMinX)
	local z = self._terrainMinZ + math.random() * (self._terrainMaxZ - self._terrainMinZ)
	return Vector3.new(x, self._terrainSurfaceY, z)
end

function EyeOfSauronService:_pickSearchTarget()
	local angle = math.random() * math.pi * 2
	local dist = math.random() * SEARCH_RADIUS
	local ox = math.cos(angle) * dist
	local oz = math.sin(angle) * dist
	return self._searchOrigin + Vector3.new(ox, 0, oz)
end

function EyeOfSauronService:_getPlayerFromHit(hit)
	local model = hit:FindFirstAncestorOfClass("Model")
	if not model then return nil end
	local player = Players:GetPlayerFromCharacter(model)
	if player then
		return player
	end
	return nil
end

function EyeOfSauronService:_lookAt(targetPos)
	local primaryPart = self._eyeModel.PrimaryPart
	if not primaryPart then return end
	primaryPart.CFrame = CFrame.lookAt(self._eyeOrigin, targetPos)
end

function EyeOfSauronService:_checkConeForPlayers(lookTarget)
	local beamVec = lookTarget - self._eyeOrigin
	local beamRange = beamVec.Magnitude
	if beamRange < 0.01 then return nil end
	local beamDir = beamVec / beamRange

	for _, player in ipairs(Players:GetPlayers()) do
		local character = player.Character
		if not character then continue end
		local rootPart = character:FindFirstChild("HumanoidRootPart")
		local humanoid = character:FindFirstChild("Humanoid")
		if not rootPart or not humanoid or humanoid.Health <= 0 then continue end

		local toPlayer = rootPart.Position - self._eyeOrigin
		local dist = toPlayer.Magnitude
		if dist < 0.01 then continue end

		local cosAngle = toPlayer:Dot(beamDir) / dist
		if cosAngle < BEAM_HALF_ANGLE_COS then continue end

		local result = Workspace:Raycast(self._eyeOrigin, toPlayer, self._raycastParams)
		if result and result.Instance then
			local hitPlayer = self:_getPlayerFromHit(result.Instance)
			if hitPlayer == player then
				return player
			end
		end
	end
	return nil
end

function EyeOfSauronService:_updateScanning(dt)
	self._dwellTimer = self._dwellTimer + dt

	if self._lerpAlpha < 1 then
		self._lerpAlpha = math.min(1, self._lerpAlpha + dt * LERP_SPEED)
	end

	local lookTarget = self._currentTarget:Lerp(self._nextTarget, self._lerpAlpha)

	if self._dwellTimer >= self._dwellDuration then
		self._currentTarget = self._nextTarget
		self._nextTarget = self:_pickRandomTarget()
		self._lerpAlpha = 0
		self._dwellTimer = 0
		self._dwellDuration = math.random() * (DWELL_TIME_MAX - DWELL_TIME_MIN) + DWELL_TIME_MIN
	end

	local found = self:_checkConeForPlayers(lookTarget)
	if found then
		self._state = "locked"
		self._lockedPlayer = found
		return
	end

	self:_lookAt(lookTarget)
	self.Client.EyeUpdate:FireAll(self._eyeOrigin, lookTarget, false)
end

function EyeOfSauronService:_updateLocked(dt)
	local player = self._lockedPlayer
	if not player or not player.Character then
		self:_dropLock()
		return
	end

	local rootPart = player.Character:FindFirstChild("HumanoidRootPart")
	local humanoid = player.Character:FindFirstChild("Humanoid")
	if not rootPart or not humanoid or humanoid.Health <= 0 then
		self:_dropLock()
		return
	end

	local targetPos = rootPart.Position
	local direction = targetPos - self._eyeOrigin
	local result = Workspace:Raycast(self._eyeOrigin, direction, self._raycastParams)

	local hasLOS = false
	if result and result.Instance then
		local hitPlayer = self:_getPlayerFromHit(result.Instance)
		if hitPlayer == player then
			hasLOS = true
		end
	end

	self:_lookAt(targetPos)

	if hasLOS then
		humanoid:TakeDamage(DAMAGE_PER_SECOND * dt)
		self.Client.EyeUpdate:FireAll(self._eyeOrigin, targetPos, true)
	else
		self:_dropLock(targetPos)
	end
end

function EyeOfSauronService:_updateSearching(dt)
	self._searchTimer = self._searchTimer + dt

	if self._searchTimer >= SEARCH_DURATION then
		self:_dropSearch()
		return
	end

	self._searchDwellTimer = self._searchDwellTimer + dt

	if self._searchLerpAlpha < 1 then
		self._searchLerpAlpha = math.min(1, self._searchLerpAlpha + dt * SEARCH_SWEEP_SPEED)
	end

	local lookTarget = self._searchCurrentTarget:Lerp(self._searchNextTarget, self._searchLerpAlpha)

	if self._searchDwellTimer >= self._searchDwellDuration then
		self._searchCurrentTarget = self._searchNextTarget
		self._searchNextTarget = self:_pickSearchTarget()
		self._searchLerpAlpha = 0
		self._searchDwellTimer = 0
		self._searchDwellDuration = SEARCH_DWELL_MIN + math.random() * (SEARCH_DWELL_MAX - SEARCH_DWELL_MIN)
	end

	local found = self:_checkConeForPlayers(lookTarget)
	if found then
		self._state = "locked"
		self._lockedPlayer = found
		return
	end

	self:_lookAt(lookTarget)
	self.Client.EyeUpdate:FireAll(self._eyeOrigin, lookTarget, false)
end

function EyeOfSauronService:AlertToPlayer(player)
	if not player or not player.Character then return end
	if self._state == "locked" and self._lockedPlayer == player then return end
	local humanoid = player.Character:FindFirstChild("Humanoid")
	if not humanoid or humanoid.Health <= 0 then return end

	self._state = "locked"
	self._lockedPlayer = player
end

function EyeOfSauronService:_dropLock(lastKnownPos)
	self._state = "searching"
	self._lockedPlayer = nil
	self._searchOrigin = lastKnownPos or self:_pickRandomTarget()
	self._searchTimer = 0
	self._searchCurrentTarget = self._searchOrigin
	self._searchNextTarget = self:_pickSearchTarget()
	self._searchLerpAlpha = 0
	self._searchDwellTimer = 0
	self._searchDwellDuration = SEARCH_DWELL_MIN + math.random() * (SEARCH_DWELL_MAX - SEARCH_DWELL_MIN)
end

function EyeOfSauronService:_dropSearch()
	self._state = "scanning"
	self._searchOrigin = nil
	self._currentTarget = self._searchCurrentTarget or self:_pickRandomTarget()
	self._nextTarget = self:_pickRandomTarget()
	self._lerpAlpha = 0
	self._dwellTimer = 0
	self._dwellDuration = math.random() * (DWELL_TIME_MAX - DWELL_TIME_MIN) + DWELL_TIME_MIN
end

function EyeOfSauronService:_update(dt)
	if not self._eyeOrigin then return end

	self._tickAccumulator = self._tickAccumulator + dt
	if self._tickAccumulator < SCAN_TICK_RATE then return end
	self._tickAccumulator = self._tickAccumulator - SCAN_TICK_RATE

	self._raycastParams.FilterDescendantsInstances = { self._eyeModel }

	if self._state == "scanning" then
		self:_updateScanning(SCAN_TICK_RATE)
	elseif self._state == "locked" then
		self:_updateLocked(SCAN_TICK_RATE)
	elseif self._state == "searching" then
		self:_updateSearching(SCAN_TICK_RATE)
	end
end

return EyeOfSauronService
