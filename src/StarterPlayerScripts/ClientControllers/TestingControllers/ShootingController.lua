--[[
	ShootingController
	Handles FastCast projectiles, firing, recoil, and impact effects
]]

local Workspace = game:GetService("Workspace")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")

local Packages = game:GetService("ReplicatedStorage"):WaitForChild("Packages")
local Knit = require(Packages.Knit)

local CustomPackages = game:GetService("ReplicatedStorage"):WaitForChild("CustomPackages")
local FastCast = require(CustomPackages:WaitForChild("FastCastFolder"):WaitForChild("FastCastRedux"))

local CONFIG = require(script.Parent.LocomotionConfig)

local ShootingController = Knit.CreateController {
	Name = "ShootingController",
	
	-- State
	_character = nil,
	_caster = nil,
	_castBehavior = nil,
	_lastFireTime = 0,
	_activeBullets = {},
	
	-- Recoil
	_recoilOffset = 0,
	_recoilTween = nil,
	_recoilValue = nil,
	
	-- Callbacks
	_onRecoilUpdate = nil,
	_getCannonTipPosition = nil,
	_getCannonParts = nil,
	
	-- Connections
	_connections = {},
}

-- === SHOOTING SETUP ===

function ShootingController:SetupShooting(character, getCannonTipPosition, getCannonParts, onRecoilUpdate)
	self._character = character
	self._getCannonTipPosition = getCannonTipPosition
	self._getCannonParts = getCannonParts
	self._onRecoilUpdate = onRecoilUpdate
	
	-- Create FastCast caster
	self._caster = FastCast.new()
	
	-- Create projectile template
	local bulletTemplate = Instance.new("Part")
	bulletTemplate.Name = "EnergyProjectile"
	bulletTemplate.Shape = Enum.PartType.Ball
	bulletTemplate.Size = Vector3.new(CONFIG.ProjectileSize, CONFIG.ProjectileSize, CONFIG.ProjectileSize)
	bulletTemplate.Color = CONFIG.ProjectileColor
	bulletTemplate.Material = Enum.Material.Neon
	bulletTemplate.CanCollide = false
	bulletTemplate.CanQuery = false
	bulletTemplate.CanTouch = false
	bulletTemplate.Anchored = true
	bulletTemplate.CastShadow = false
	
	-- Add glow effect
	local light = Instance.new("PointLight")
	light.Color = CONFIG.ProjectileColor
	light.Brightness = 2
	light.Range = 8
	light.Parent = bulletTemplate
	
	-- Add trail
	local trailAttach0 = Instance.new("Attachment")
	trailAttach0.Position = Vector3.new(0, 0, -CONFIG.ProjectileSize/2)
	trailAttach0.Parent = bulletTemplate
	
	local trailAttach1 = Instance.new("Attachment")
	trailAttach1.Position = Vector3.new(0, 0, CONFIG.ProjectileSize/2)
	trailAttach1.Parent = bulletTemplate
	
	local trail = Instance.new("Trail")
	trail.Attachment0 = trailAttach0
	trail.Attachment1 = trailAttach1
	trail.Color = ColorSequence.new(CONFIG.ProjectileColor)
	trail.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(1, 1)
	})
	trail.Lifetime = 0.3
	trail.WidthScale = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(1, 0)
	})
	trail.Parent = bulletTemplate
	
	-- Create bullet container
	local bulletContainer = Workspace:FindFirstChild("ProjectileContainer")
	if not bulletContainer then
		bulletContainer = Instance.new("Folder")
		bulletContainer.Name = "ProjectileContainer"
		bulletContainer.Parent = Workspace
	end
	
	-- Setup cast behavior
	self._castBehavior = FastCast.newBehavior()
	self._castBehavior.RaycastParams = RaycastParams.new()
	self._castBehavior.RaycastParams.FilterType = Enum.RaycastFilterType.Exclude
	self._castBehavior.RaycastParams.FilterDescendantsInstances = {character, bulletContainer}
	self._castBehavior.Acceleration = CONFIG.ProjectileGravity
	self._castBehavior.MaxDistance = CONFIG.ProjectileMaxDistance
	self._castBehavior.CosmeticBulletTemplate = bulletTemplate
	self._castBehavior.CosmeticBulletContainer = bulletContainer
	self._castBehavior.AutoIgnoreContainer = true
	
	-- Connect FastCast events
	self._caster.LengthChanged:Connect(function(cast, lastPoint, direction, length, velocity, bullet)
		if bullet then
			local newPos = lastPoint + (direction * length)
			bullet.CFrame = CFrame.lookAt(newPos, newPos + velocity)
		end
	end)
	
	self._caster.RayHit:Connect(function(cast, result, velocity, bullet)
		if bullet then
			self:OnProjectileHit(bullet, result, velocity)
		end
	end)
	
	self._caster.CastTerminating:Connect(function(cast)
		local bullet = cast.RayInfo.CosmeticBulletObject
		if bullet then
			self:DestroyProjectile(bullet)
		end
	end)
	
	-- Setup mouse input
	local inputConn = UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed then return end
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			self:FireProjectile()
		end
	end)
	table.insert(self._connections, inputConn)
end

-- === FIRING ===

function ShootingController:FireProjectile()
	if not self._caster or not self._castBehavior then return end
	if not self._getCannonTipPosition then return end
	
	-- Check fire rate
	local now = tick()
	if now - self._lastFireTime < CONFIG.FireRate then
		return
	end
	self._lastFireTime = now
	
	-- Get fire position and direction
	local origin, direction = self._getCannonTipPosition()
	if not origin or not direction then return end
	
	-- Update raycast filter
	self._castBehavior.RaycastParams.FilterDescendantsInstances = {
		self._character,
		Workspace:FindFirstChild("ProjectileContainer")
	}
	
	-- Fire!
	self._caster:Fire(origin, direction, CONFIG.ProjectileSpeed, self._castBehavior)
	
	-- Visual feedback
	self:CannonFireEffect()
end

function ShootingController:CannonFireEffect()
	-- Create NumberValue for tweening if it doesn't exist
	if not self._recoilValue then
		self._recoilValue = Instance.new("NumberValue")
		self._recoilValue.Value = 0
		self._recoilValue.Changed:Connect(function(value)
			self._recoilOffset = value
			if self._onRecoilUpdate then
				self._onRecoilUpdate(value)
			end
		end)
	end
	
	-- Cancel existing tween
	if self._recoilTween then
		self._recoilTween:Cancel()
	end
	
	-- Instant kick back
	self._recoilValue.Value = 1
	self._recoilOffset = 1
	if self._onRecoilUpdate then
		self._onRecoilUpdate(1)
	end
	
	-- Tween back to 0
	local tweenInfo = TweenInfo.new(
		CONFIG.RecoilDuration,
		Enum.EasingStyle.Quad,
		Enum.EasingDirection.Out,
		0, false, 0
	)
	
	self._recoilTween = TweenService:Create(self._recoilValue, tweenInfo, {Value = 0})
	self._recoilTween:Play()
	
	-- Flash effects
	if self._getCannonParts then
		local cannonParts = self._getCannonParts()
		
		-- Flash barrel tip
		if cannonParts[6] then
			local tip = cannonParts[6]
			local originalColor = tip.Color
			tip.Color = Color3.new(1, 1, 1)
			tip.Size = tip.Size * 1.5
			
			task.delay(0.05, function()
				if tip and tip.Parent then
					tip.Color = originalColor
					tip.Size = Vector3.new(0.1, CONFIG.CannonTipWidth * 0.8, CONFIG.CannonTipWidth * 0.8)
				end
			end)
		end
		
		-- Flash energy core
		if cannonParts[7] then
			local core = cannonParts[7]
			local originalSize = core.Size
			core.Size = originalSize * 2
			
			task.delay(0.1, function()
				if core and core.Parent then
					core.Size = originalSize
				end
			end)
		end
	end
end

-- === IMPACT ===

function ShootingController:OnProjectileHit(bullet, rayResult, velocity)
	local hitPos = rayResult.Position
	
	-- Spawn impact effect
	local impactPart = Instance.new("Part")
	impactPart.Shape = Enum.PartType.Ball
	impactPart.Size = Vector3.new(CONFIG.ProjectileSize * 2, CONFIG.ProjectileSize * 2, CONFIG.ProjectileSize * 2)
	impactPart.Position = hitPos
	impactPart.Color = CONFIG.ProjectileColor
	impactPart.Material = Enum.Material.Neon
	impactPart.Anchored = true
	impactPart.CanCollide = false
	impactPart.CanQuery = false
	impactPart.CanTouch = false
	impactPart.Transparency = 0.3
	impactPart.Parent = Workspace
	
	-- Add light flash
	local impactLight = Instance.new("PointLight")
	impactLight.Color = CONFIG.ProjectileColor
	impactLight.Brightness = 5
	impactLight.Range = 15
	impactLight.Parent = impactPart
	
	-- Animate impact
	task.spawn(function()
		for i = 1, 10 do
			if impactPart and impactPart.Parent then
				local t = i / 10
				impactPart.Size = Vector3.new(1, 1, 1) * (CONFIG.ProjectileSize * 2 + t * 3)
				impactPart.Transparency = 0.3 + t * 0.7
				impactLight.Brightness = 5 * (1 - t)
				task.wait(0.02)
			end
		end
		if impactPart then
			impactPart:Destroy()
		end
	end)
end

function ShootingController:DestroyProjectile(bullet)
	if bullet and bullet.Parent then
		bullet:Destroy()
	end
end

-- === CLEANUP ===

function ShootingController:Cleanup()
	for _, conn in ipairs(self._connections) do
		if conn and conn.Connected then
			conn:Disconnect()
		end
	end
	self._connections = {}
	
	self._caster = nil
	self._castBehavior = nil
	self._activeBullets = {}
	
	if self._recoilTween then
		self._recoilTween:Cancel()
		self._recoilTween = nil
	end
	if self._recoilValue then
		self._recoilValue:Destroy()
		self._recoilValue = nil
	end
	self._recoilOffset = 0
	
	self._character = nil
	self._getCannonTipPosition = nil
	self._getCannonParts = nil
	self._onRecoilUpdate = nil
end

-- === PUBLIC API ===

function ShootingController:GetRecoilOffset()
	return self._recoilOffset
end

-- === KNIT LIFECYCLE ===

function ShootingController:KnitInit()
end

function ShootingController:KnitStart()
	-- This controller is managed by ProceduralLocomotionController
end

return ShootingController

