local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CustomPackages = ReplicatedStorage:WaitForChild("CustomPackages")
local Packages = ReplicatedStorage:WaitForChild("Packages")
local Knit = require(Packages.Knit)
local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

local FastCastFolder = CustomPackages:WaitForChild("FastCastFolder")
local FastCast = require(FastCastFolder:WaitForChild("FastCastRedux"))
local PartCache = require(Packages:WaitForChild("partcache"))

-- Prefab reference
local Prefabs = ReplicatedStorage:WaitForChild("Prefabs")
local meteorPrefab = Prefabs:WaitForChild("Meteor")

local CannonService = Knit.CreateService {
	Name = "CannonService",
	Client = {},
}

-- FastCast setup
local Caster = FastCast.new()
FastCast.DebugLogging = false
FastCast.VisualizeCasts = true

-- Use meteorPrefab as the visual projectile
local projectileTemplate = meteorPrefab:Clone()
projectileTemplate.Anchored = true
projectileTemplate.CanCollide = false
projectileTemplate.Name = "MeteorProjectile"

local cacheFolder = Instance.new("Folder")
cacheFolder.Name = "CannonProjectiles"
cacheFolder.Parent = workspace

local cache = PartCache.new(projectileTemplate, 50)
cache:SetCacheParent(cacheFolder)

local raycastParams = RaycastParams.new()
raycastParams.FilterType = Enum.RaycastFilterType.Blacklist
raycastParams.FilterDescendantsInstances = {cacheFolder}

local behavior = FastCast.newBehavior()
behavior.CosmeticBulletProvider = cache
behavior.CosmeticBulletContainer = cacheFolder
behavior.Acceleration = Vector3.new(0, -workspace.Gravity, 0)
behavior.RaycastParams = raycastParams
behavior.MaxDistance = 10000
behavior.AutoIgnoreContainer = true

Caster.LengthChanged:Connect(function(cast, lastPoint, direction, displacement, velocity, bullet)
	if bullet then
		bullet.CFrame = CFrame.new(lastPoint + direction * displacement)
	end
end)

Caster.RayHit:Connect(function(cast, result, velocity, bullet)
	if bullet then
		-- Return bullet to the cache instead of destroying
		--cache:ReturnPart(bullet)

		-- Optional: Play explosion/effects at result.Position
		-- Example: createExplosion(result.Position)
	end
end)

local fireRate = 1
local timeSinceLastFire = 0

-- Get closest player position
function CannonService:GetNearestPlayerPosition(origin)
	local closest, minDist = nil, math.huge
	for _, player in ipairs(Players:GetPlayers()) do
		local char = player.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		if hrp then
			local dist = (hrp.Position - origin).Magnitude
			if dist < minDist then
				minDist = dist
				closest = hrp.Position
			end
		end
	end
	return closest
end

-- Solve initial speed to reach target at a given angle
function CannonService:ComputeSpeedFromAngle(origin: Vector3, target: Vector3, angleRadians: number, gravity: number)
	local displacement = target - origin
	local horizontal = Vector3.new(displacement.X, 0, displacement.Z)
	local distance = horizontal.Magnitude
	local height = displacement.Y

	local cos = math.cos(angleRadians)
	local sin = math.sin(angleRadians)
	local denom = 2 * (distance * math.tan(angleRadians) - height)

	if denom <= 0 then return nil end

	local speedSquared = (gravity * distance^2) / (denom * cos^2)
	if speedSquared < 0 then return nil end

	return math.sqrt(speedSquared)
end

-- Get tagged cannon fire points
function CannonService:GetRootParts()
	local rootParts = {}

	for _, obj in ipairs(CollectionService:GetTagged("cannon")) do
		local rootPart = obj:FindFirstChild("rootPart")
		if rootPart then
			local firePoints = {}
			for _, child in ipairs(rootPart:GetChildren()) do
				if child.Name == "firePoint" then
					table.insert(firePoints, child)
				end
			end
			table.insert(rootParts, {
				Root = rootPart,
				FirePoints = firePoints,
				Parent = obj
			})
		end
	end

	return rootParts
end

-- Fire using FastCast with computed arc to reach target
function CannonService:FireFrom(firePoint, target)
	local origin = firePoint.Position
	local gravity = math.abs(workspace.Gravity)
	local angle = math.rad(45) -- desired launch angle

	local speed = self:ComputeSpeedFromAngle(origin, target, angle, gravity)
	if not speed then return end

	local displacement = target - origin
	local horizontal = Vector3.new(displacement.X, 0, displacement.Z)
	local flatDir = horizontal.Unit

	local launchRotation = CFrame.fromAxisAngle(flatDir:Cross(Vector3.yAxis), angle)
	local launchDirection = launchRotation:VectorToWorldSpace(flatDir)

	Caster:Fire(origin, launchDirection, speed, behavior)
end

-- Continuous smooth rotation + fire loop
function CannonService:StartLookLoop()
	local cannons = self:GetRootParts()

	RunService.Heartbeat:Connect(function(dt)
		timeSinceLastFire += dt

		for _, cannon in ipairs(cannons) do
			for _, firePoint in ipairs(cannon.FirePoints) do
				local origin = firePoint.Position
				local target = self:GetNearestPlayerPosition(origin)

				if target then
					-- Smoothly rotate toward target
					local currentCF = firePoint.CFrame
					local targetCF = CFrame.lookAt(origin, target)
					firePoint.CFrame = currentCF:Lerp(targetCF, 0.1)

					-- Fire when ready
					if timeSinceLastFire >= fireRate then
						self:FireFrom(firePoint, target)
					end
				end
			end
		end

		if timeSinceLastFire >= fireRate then
			timeSinceLastFire = 0
		end
	end)
end

function CannonService:KnitStart()
	self:StartLookLoop()
end

function CannonService:KnitInit() end

return CannonService
