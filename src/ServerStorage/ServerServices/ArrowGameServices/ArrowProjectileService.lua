--[[
	ArrowProjectileService
	
	Handles firing arrow projectiles using FastCast.
	Manages projectile physics, collision detection, and hit registration.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local Debris = game:GetService("Debris")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local Knit = require(Packages.Knit)
local Signal = require(Packages.Signal)

local CustomPackages = ReplicatedStorage:WaitForChild("CustomPackages")
local FastCast = require(CustomPackages.FastCastFolder.FastCastRedux)

local ArrowProjectileService = Knit.CreateService({
	Name = "ArrowProjectileService",
	Client = {
		ProjectileFired = Knit.CreateSignal(),
		ProjectileHit = Knit.CreateSignal(),
	},
	
	-- Server-side signals
	OnHit = Signal.new(),
})

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                              CONFIGURATION                                  ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

local CONFIG = {
	-- Projectile Settings
	BaseSpeed = 50,           -- Base projectile speed (studs/sec)
	MaxSpeed = 300,           -- Max speed at full power
	Gravity = Vector3.new(0, -workspace.Gravity * 0.5, 0),  -- Gravity acceleration
	MaxDistance = 1000,       -- Max travel distance
	
	-- Projectile Visual
	ProjectileSize = Vector3.new(0.3, 0.3, 3),
	ProjectileColor = Color3.fromRGB(255, 200, 80),
	ProjectileMaterial = Enum.Material.Neon,
	
	-- Trail
	TrailEnabled = true,
	TrailColor = Color3.fromRGB(255, 150, 50),
	TrailLifetime = 0.3,
}

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                              STATE                                          ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

local caster = nil
local castBehavior = nil
local projectilesFolder = nil
local castParams = nil

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         FASTCAST SETUP                                      ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

function ArrowProjectileService:SetupFastCast()
	-- Create caster
	caster = FastCast.new()
	
	-- Create behavior
	castBehavior = FastCast.newBehavior()
	castBehavior.Acceleration = CONFIG.Gravity
	castBehavior.MaxDistance = CONFIG.MaxDistance
	castBehavior.AutoIgnoreContainer = true
	
	-- Create raycast params
	castParams = RaycastParams.new()
	castParams.FilterType = Enum.RaycastFilterType.Exclude
	castParams.FilterDescendantsInstances = {projectilesFolder}
	castBehavior.RaycastParams = castParams
	
	-- Connect signals
	caster.LengthChanged:Connect(function(cast, lastPoint, direction, length, velocity, bullet)
		if bullet then
			-- Update bullet position and rotation
			local newPos = lastPoint + (direction * length)
			bullet.CFrame = CFrame.lookAt(newPos, newPos + direction)
		end
	end)
	
	caster.RayHit:Connect(function(cast, result, velocity, bullet)
		self:OnProjectileHit(cast, result, velocity, bullet)
	end)
	
	caster.CastTerminating:Connect(function(cast)
		local bullet = cast.RayInfo.CosmeticBulletObject
		if bullet then
			-- Fade out and destroy
			Debris:AddItem(bullet, 0.5)
		end
	end)
	
	print("[ArrowProjectileService] ✓ FastCast initialized")
end

function ArrowProjectileService:CreateProjectilesFolder()
	local existing = Workspace:FindFirstChild("ArrowProjectiles")
	if existing then
		existing:Destroy()
	end
	
	projectilesFolder = Instance.new("Folder")
	projectilesFolder.Name = "ArrowProjectiles"
	projectilesFolder.Parent = Workspace
	
	return projectilesFolder
end

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         PROJECTILE CREATION                                 ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

function ArrowProjectileService:CreateProjectileVisual(origin: Vector3, direction: Vector3)
	local projectile = Instance.new("Part")
	projectile.Name = "ArrowProjectile"
	projectile.Size = CONFIG.ProjectileSize
	projectile.Color = CONFIG.ProjectileColor
	projectile.Material = CONFIG.ProjectileMaterial
	projectile.Anchored = true
	projectile.CanCollide = false
	projectile.CastShadow = false
	projectile.CFrame = CFrame.lookAt(origin, origin + direction)
	projectile.Parent = projectilesFolder
	
	-- Add trail
	if CONFIG.TrailEnabled then
		local attachment0 = Instance.new("Attachment")
		attachment0.Position = Vector3.new(0, 0, -CONFIG.ProjectileSize.Z / 2)
		attachment0.Parent = projectile
		
		local attachment1 = Instance.new("Attachment")
		attachment1.Position = Vector3.new(0, 0, CONFIG.ProjectileSize.Z / 2)
		attachment1.Parent = projectile
		
		local trail = Instance.new("Trail")
		trail.Attachment0 = attachment0
		trail.Attachment1 = attachment1
		trail.Color = ColorSequence.new(CONFIG.TrailColor)
		trail.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(1, 1),
		})
		trail.Lifetime = CONFIG.TrailLifetime
		trail.MinLength = 0.1
		trail.FaceCamera = true
		trail.Parent = projectile
	end
	
	-- Add point light for glow
	local light = Instance.new("PointLight")
	light.Color = CONFIG.ProjectileColor
	light.Brightness = 2
	light.Range = 8
	light.Parent = projectile
	
	return projectile
end

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         FIRING LOGIC                                        ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

function ArrowProjectileService:FireProjectile(player: Player, origin: Vector3, direction: Vector3, power: number)
	-- Calculate speed based on power (0-100)
	local powerRatio = math.clamp(power / 100, 0, 1)
	local speed = CONFIG.BaseSpeed + (CONFIG.MaxSpeed - CONFIG.BaseSpeed) * powerRatio
	
	-- Normalize direction
	direction = direction.Unit
	
	-- Update raycast filter to exclude the firing player
	if player.Character then
		castParams.FilterDescendantsInstances = {projectilesFolder, player.Character}
	end
	
	-- Create projectile visual
	local projectile = self:CreateProjectileVisual(origin, direction)
	
	-- Set cosmetic bullet in behavior
	castBehavior.CosmeticBulletTemplate = nil -- We create manually
	
	-- Fire the cast
	local activeCast = caster:Fire(origin, direction, speed, castBehavior)
	
	-- Attach our visual to the cast
	activeCast.RayInfo.CosmeticBulletObject = projectile
	
	-- Store player info for hit detection
	activeCast.UserData = {
		Player = player,
		Power = power,
	}
	
	print(string.format("[ArrowProjectileService] %s fired projectile - Power: %.0f%%, Speed: %.0f", 
		player.Name, power, speed))
	
	-- Notify clients
	self.Client.ProjectileFired:FireAll(player, origin, direction, speed)
	
	return activeCast
end

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         HIT DETECTION                                       ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

function ArrowProjectileService:OnProjectileHit(cast, result, velocity, bullet)
	local hitPart = result.Instance
	local hitPosition = result.Position
	local hitNormal = result.Normal
	
	local userData = cast.UserData or {}
	local firingPlayer = userData.Player
	local power = userData.Power or 0
	
	print(string.format("[ArrowProjectileService] Projectile hit: %s at %s", 
		hitPart and hitPart.Name or "nil", tostring(hitPosition)))
	
	-- Check if we hit a player
	local hitPlayer = nil
	local hitCharacter = hitPart and hitPart.Parent
	if hitCharacter then
		hitPlayer = Players:GetPlayerFromCharacter(hitCharacter)
		if not hitPlayer then
			-- Check one level up (for accessories)
			hitCharacter = hitCharacter.Parent
			hitPlayer = Players:GetPlayerFromCharacter(hitCharacter)
		end
	end
	
	-- Create hit effect
	self:CreateHitEffect(hitPosition, hitNormal)
	
	-- Fire signals
	self.OnHit:Fire(firingPlayer, hitPlayer, hitPart, hitPosition, power)
	self.Client.ProjectileHit:FireAll(firingPlayer, hitPosition, hitPart and hitPart.Name or "")
	
	-- Destroy the bullet visual
	if bullet then
		bullet:Destroy()
	end
end

function ArrowProjectileService:CreateHitEffect(position: Vector3, normal: Vector3)
	-- Create a simple hit spark
	local spark = Instance.new("Part")
	spark.Name = "HitSpark"
	spark.Size = Vector3.new(1, 1, 1)
	spark.Shape = Enum.PartType.Ball
	spark.Color = CONFIG.ProjectileColor
	spark.Material = Enum.Material.Neon
	spark.Anchored = true
	spark.CanCollide = false
	spark.Position = position
	spark.Parent = projectilesFolder
	
	-- Tween it to expand and fade
	local TweenService = game:GetService("TweenService")
	local tween = TweenService:Create(spark, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(3, 3, 3),
		Transparency = 1,
	})
	tween:Play()
	
	Debris:AddItem(spark, 0.5)
end

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         PUBLIC API                                          ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

function ArrowProjectileService:GetConfig()
	return CONFIG
end

function ArrowProjectileService:UpdateConfig(key: string, value: any)
	if CONFIG[key] ~= nil then
		CONFIG[key] = value
		return true
	end
	return false
end

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         CLIENT METHODS                                      ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

function ArrowProjectileService.Client:FireArrow(player, origin: Vector3, direction: Vector3, power: number)
	ArrowProjectileService:FireProjectile(player, origin, direction, power)
	return true  -- Return simple value to avoid cyclic table error
end

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         KNIT LIFECYCLE                                      ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

function ArrowProjectileService:KnitInit()
	print("[ArrowProjectileService] Initializing...")
	self:CreateProjectilesFolder()
	self:SetupFastCast()
end

function ArrowProjectileService:KnitStart()
	print("[ArrowProjectileService] Starting...")
	print("[ArrowProjectileService] Ready")
end

return ArrowProjectileService

