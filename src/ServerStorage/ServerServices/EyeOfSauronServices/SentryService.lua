local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Knit = require(ReplicatedStorage.Packages.Knit)

local SENTRY_COUNT = 12
local HOVER_HEIGHT = 30
local MOVE_SPEED = 25
local SENTRY_SIZE = 4
local SPOTLIGHT_RANGE = 60
local SPOTLIGHT_ANGLE = 35
local DETECTION_RATE = 1 / 5
local WAYPOINT_ARRIVE_DIST = 8
local GROUND_RAY_HEIGHT = 200

local DOWN = Vector3.new(0, -1, 0)
local CONE_HALF_ANGLE_COS = math.cos(math.rad(SPOTLIGHT_ANGLE / 2))

local SentryService = Knit.CreateService({
	Name = "SentryService",
	Client = {},
})

function SentryService:KnitInit()
	self._sentries = {}
	self._folder = nil
	self._raycastParams = nil
	self._terrainMinX = 0
	self._terrainMaxX = 0
	self._terrainMinZ = 0
	self._terrainMaxZ = 0
	self._detectionAccumulator = 0
end

function SentryService:KnitStart()
	local terrainService = Knit.GetService("ProvingGroundsTerrainService")
	local minX, maxX, minZ, maxZ = terrainService:GetBounds()
	self._terrainMinX = minX
	self._terrainMaxX = maxX
	self._terrainMinZ = minZ
	self._terrainMaxZ = maxZ

	local folder = Workspace:FindFirstChild("Sentries")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "Sentries"
		folder.Parent = Workspace
	end
	self._folder = folder

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { folder }
	self._raycastParams = params

	for _ = 1, SENTRY_COUNT do
		self:_spawnSentry()
	end

	RunService.Heartbeat:Connect(function(dt)
		self:_update(dt)
	end)

	print("[SentryService] " .. SENTRY_COUNT .. " sentries deployed")
end

function SentryService:_pickRandomWaypoint()
	local x = self._terrainMinX + math.random() * (self._terrainMaxX - self._terrainMinX)
	local z = self._terrainMinZ + math.random() * (self._terrainMaxZ - self._terrainMinZ)
	return Vector3.new(x, 0, z)
end

function SentryService:_getGroundY(x, z)
	local origin = Vector3.new(x, GROUND_RAY_HEIGHT, z)
	local result = Workspace:Raycast(origin, Vector3.new(0, -(GROUND_RAY_HEIGHT + 100), 0), self._raycastParams)
	if result then
		return result.Position.Y
	end
	return 0
end

function SentryService:_spawnSentry()
	local part = Instance.new("Part")
	part.Shape = Enum.PartType.Ball
	part.Size = Vector3.new(SENTRY_SIZE, SENTRY_SIZE, SENTRY_SIZE)
	part.Material = Enum.Material.Neon
	part.Color = Color3.fromRGB(255, 80, 30)
	part.Anchored = true
	part.CanCollide = false
	part.CastShadow = false

	local spot = Instance.new("SpotLight")
	spot.Face = Enum.NormalId.Bottom
	spot.Range = SPOTLIGHT_RANGE
	spot.Angle = SPOTLIGHT_ANGLE
	spot.Brightness = 3
	spot.Color = Color3.fromRGB(255, 120, 40)
	spot.Parent = part

	local glow = Instance.new("PointLight")
	glow.Range = 8
	glow.Brightness = 1
	glow.Color = Color3.fromRGB(255, 80, 30)
	glow.Parent = part

	local wp = self:_pickRandomWaypoint()
	local groundY = self:_getGroundY(wp.X, wp.Z)
	part.CFrame = CFrame.new(wp.X, groundY + HOVER_HEIGHT, wp.Z)
	part.Parent = self._folder

	table.insert(self._sentries, {
		part = part,
		waypoint = wp,
	})
end

function SentryService:_updateMovement(dt)
	for _, sentry in ipairs(self._sentries) do
		local part = sentry.part
		local pos = part.Position
		local wp = sentry.waypoint

		local dx = wp.X - pos.X
		local dz = wp.Z - pos.Z
		local hDist = math.sqrt(dx * dx + dz * dz)

		if hDist < WAYPOINT_ARRIVE_DIST then
			sentry.waypoint = self:_pickRandomWaypoint()
			wp = sentry.waypoint
			dx = wp.X - pos.X
			dz = wp.Z - pos.Z
			hDist = math.sqrt(dx * dx + dz * dz)
		end

		if hDist > 0.01 then
			local step = math.min(MOVE_SPEED * dt, hDist)
			local nx = dx / hDist * step
			local nz = dz / hDist * step
			local newX = pos.X + nx
			local newZ = pos.Z + nz
			local groundY = self:_getGroundY(newX, newZ)
			local targetY = groundY + HOVER_HEIGHT
			local newY = pos.Y + (targetY - pos.Y) * math.min(1, dt * 3)

			part.CFrame = CFrame.new(newX, newY, newZ)
		end
	end
end

function SentryService:_isInCone(sentryPos, targetPos)
	local toTarget = targetPos - sentryPos
	local dist = toTarget.Magnitude
	if dist < 0.01 or dist > SPOTLIGHT_RANGE then
		return false
	end
	local dirNorm = toTarget / dist
	local cosAngle = dirNorm:Dot(DOWN)
	return cosAngle >= CONE_HALF_ANGLE_COS
end

function SentryService:_updateDetection()
	local eyeService = Knit.GetService("EyeOfSauronService")

	for _, sentry in ipairs(self._sentries) do
		local sentryPos = sentry.part.Position

		for _, player in ipairs(Players:GetPlayers()) do
			local character = player.Character
			if not character then continue end
			local rootPart = character:FindFirstChild("HumanoidRootPart")
			local humanoid = character:FindFirstChild("Humanoid")
			if not rootPart or not humanoid or humanoid.Health <= 0 then continue end

			if self:_isInCone(sentryPos, rootPart.Position) then
				local direction = rootPart.Position - sentryPos
				local result = Workspace:Raycast(sentryPos, direction, self._raycastParams)
				if result and result.Instance then
					local hitModel = result.Instance:FindFirstAncestorOfClass("Model")
					if hitModel and Players:GetPlayerFromCharacter(hitModel) == player then
						eyeService:AlertToPlayer(player)
					end
				end
			end
		end
	end
end

function SentryService:_update(dt)
	self:_updateMovement(dt)

	self._detectionAccumulator = self._detectionAccumulator + dt
	if self._detectionAccumulator >= DETECTION_RATE then
		self._detectionAccumulator = self._detectionAccumulator - DETECTION_RATE
		self:_updateDetection()
	end
end

function SentryService:Clear()
	for _, sentry in ipairs(self._sentries) do
		sentry.part:Destroy()
	end
	self._sentries = {}
end

return SentryService
