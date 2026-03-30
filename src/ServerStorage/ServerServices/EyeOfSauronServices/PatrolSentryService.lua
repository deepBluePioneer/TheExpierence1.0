local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Knit = require(ReplicatedStorage.Packages.Knit)

local PATROL_PER_TRENCH = 2
local WAYPOINTS_PER_ROUTE = 12
local TRENCH_EDGE_OFFSET = 24
local HOVER_HEIGHT = 25
local MOVE_SPEED = 18
local SENTRY_SIZE = 4
local SPOTLIGHT_RANGE = 60
local SPOTLIGHT_ANGLE = 35
local DETECTION_RATE = 1 / 5
local WAYPOINT_ARRIVE_DIST = 6
local GROUND_RAY_HEIGHT = 200

local DOWN = Vector3.new(0, -1, 0)
local CONE_HALF_ANGLE_COS = math.cos(math.rad(SPOTLIGHT_ANGLE / 2))

local PatrolSentryService = Knit.CreateService({
	Name = "PatrolSentryService",
	Client = {},
})

function PatrolSentryService:KnitInit()
	self._sentries = {}
	self._folder = nil
	self._raycastParams = nil
	self._detectionAccumulator = 0
end

function PatrolSentryService:KnitStart()
	local sentryFolder = Workspace:WaitForChild("Sentries", 15)
	if not sentryFolder then
		sentryFolder = Instance.new("Folder")
		sentryFolder.Name = "Sentries"
		sentryFolder.Parent = Workspace
	end
	self._folder = sentryFolder

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { sentryFolder }
	self._raycastParams = params

	local terrainService = Knit.GetService("ProvingGroundsTerrainService")
	local trenchCount = terrainService:GetTrenchCount()

	for i = 1, trenchCount do
		for side = 1, PATROL_PER_TRENCH do
			local offset = (side % 2 == 1) and TRENCH_EDGE_OFFSET or -TRENCH_EDGE_OFFSET
			local waypoints = terrainService:SampleTrenchWaypoints(i, WAYPOINTS_PER_ROUTE, offset)
			if #waypoints < 2 then continue end
			self:_spawnPatrolSentry(waypoints)
		end
	end

	RunService.Heartbeat:Connect(function(dt)
		self:_update(dt)
	end)

	print("[PatrolSentryService] " .. #self._sentries .. " patrol sentries deployed")
end

function PatrolSentryService:_getGroundY(x, z)
	local origin = Vector3.new(x, GROUND_RAY_HEIGHT, z)
	local result = Workspace:Raycast(origin, Vector3.new(0, -(GROUND_RAY_HEIGHT + 100), 0), self._raycastParams)
	if result then
		return result.Position.Y
	end
	return 0
end

function PatrolSentryService:_spawnPatrolSentry(waypoints)
	local part = Instance.new("Part")
	part.Shape = Enum.PartType.Ball
	part.Size = Vector3.new(SENTRY_SIZE, SENTRY_SIZE, SENTRY_SIZE)
	part.Material = Enum.Material.Neon
	part.Color = Color3.fromRGB(120, 60, 255)
	part.Anchored = true
	part.CanCollide = false
	part.CastShadow = false

	local spot = Instance.new("SpotLight")
	spot.Face = Enum.NormalId.Bottom
	spot.Range = SPOTLIGHT_RANGE
	spot.Angle = SPOTLIGHT_ANGLE
	spot.Brightness = 3
	spot.Color = Color3.fromRGB(140, 100, 255)
	spot.Parent = part

	local glow = Instance.new("PointLight")
	glow.Range = 8
	glow.Brightness = 1
	glow.Color = Color3.fromRGB(120, 60, 255)
	glow.Parent = part

	local startIdx = math.random(1, #waypoints)
	local wp = waypoints[startIdx]
	local groundY = self:_getGroundY(wp.X, wp.Z)
	part.CFrame = CFrame.new(wp.X, groundY + HOVER_HEIGHT, wp.Z)
	part.Parent = self._folder

	table.insert(self._sentries, {
		part = part,
		route = waypoints,
		waypointIndex = startIdx,
		direction = 1,
	})
end

function PatrolSentryService:_updateMovement(dt)
	for _, sentry in ipairs(self._sentries) do
		local part = sentry.part
		local pos = part.Position
		local route = sentry.route
		local wp = route[sentry.waypointIndex]

		local dx = wp.X - pos.X
		local dz = wp.Z - pos.Z
		local hDist = math.sqrt(dx * dx + dz * dz)

		if hDist < WAYPOINT_ARRIVE_DIST then
			local nextIdx = sentry.waypointIndex + sentry.direction
			if nextIdx > #route then
				sentry.direction = -1
				nextIdx = sentry.waypointIndex - 1
			elseif nextIdx < 1 then
				sentry.direction = 1
				nextIdx = sentry.waypointIndex + 1
			end
			sentry.waypointIndex = nextIdx
			wp = route[sentry.waypointIndex]
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

function PatrolSentryService:_isInCone(sentryPos, targetPos)
	local toTarget = targetPos - sentryPos
	local dist = toTarget.Magnitude
	if dist < 0.01 or dist > SPOTLIGHT_RANGE then
		return false
	end
	local dirNorm = toTarget / dist
	local cosAngle = dirNorm:Dot(DOWN)
	return cosAngle >= CONE_HALF_ANGLE_COS
end

function PatrolSentryService:_updateDetection()
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

function PatrolSentryService:_update(dt)
	self:_updateMovement(dt)

	self._detectionAccumulator = self._detectionAccumulator + dt
	if self._detectionAccumulator >= DETECTION_RATE then
		self._detectionAccumulator = self._detectionAccumulator - DETECTION_RATE
		self:_updateDetection()
	end
end

function PatrolSentryService:Clear()
	for _, sentry in ipairs(self._sentries) do
		sentry.part:Destroy()
	end
	self._sentries = {}
end

return PatrolSentryService
