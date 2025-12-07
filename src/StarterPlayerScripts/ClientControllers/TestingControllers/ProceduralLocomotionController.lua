--[[
	ProceduralLocomotionController (CLIENT-SIDE)
	
	Fully IK-driven procedural locomotion system that replaces default Roblox animations.
	Creates natural-looking walk/run cycles using inverse kinematics.
	
	Features:
	- Procedural foot placement with terrain raycasting
	- Velocity-based stride length and speed
	- Arm swing synchronized with legs
	- Body bob and sway
	- Head stabilization
	- Smooth idle ↔ walk ↔ run transitions
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local UserInputService = game:GetService("UserInputService")
local Debris = game:GetService("Debris")
local TweenService = game:GetService("TweenService")

local Packages = game:GetService("ReplicatedStorage"):WaitForChild("Packages")
local Knit = require(Packages.Knit)

-- FastCast for projectile physics
local CustomPackages = game:GetService("ReplicatedStorage"):WaitForChild("CustomPackages")
local FastCast = require(CustomPackages:WaitForChild("FastCastFolder"):WaitForChild("FastCastRedux"))

local ProceduralLocomotionController = Knit.CreateController {
	Name = "ProceduralLocomotionController",
	
	-- State
	_character = nil,
	_humanoid = nil,
	_hrp = nil,
	
	-- IK Controls
	_ikControls = {},
	_ikTargets = {},
	
	-- Motor6D references
	_motors = {},
	
	-- Locomotion state
	_walkPhase = 0,          -- 0 to 1 cycle
	_lastGroundedFoot = "Left",
	_leftFootPlanted = true,
	_rightFootPlanted = false,
	_leftFootTarget = CFrame.new(),
	_rightFootTarget = CFrame.new(),
	_lastLeftFootPos = Vector3.zero,
	_lastRightFootPos = Vector3.zero,
	_lastRightHandPos = nil, -- For smooth camera tracking
	_armCannon = nil,        -- Arm cannon model
	_cannonParts = {},       -- Individual cannon parts
	
	-- Movement smoothing state
	_smoothedSpeed = 0,      -- Current smoothed movement speed
	_targetSpeed = 0,        -- Target speed we're interpolating to
	_smoothedDirection = Vector3.zero, -- Smoothed movement direction
	
	-- Physics forces
	_moveForce = nil,        -- VectorForce for movement
	_jumpForce = nil,        -- VectorForce for jump
	_attachment = nil,       -- Attachment for forces
	
	-- Jump state
	_isJumping = false,
	_jumpStartTime = 0,
	_jumpPhase = "none",     -- "rising", "hanging", "falling", "none"
	_wasGrounded = true,
	
	-- Shooting state
	_caster = nil,           -- FastCast caster instance
	_castBehavior = nil,     -- FastCast behavior settings
	_lastFireTime = 0,       -- For fire rate limiting
	_activeBullets = {},     -- Track active projectiles
	_recoilOffset = 0,       -- Current recoil offset (0-1)
	_recoilTween = nil,      -- Current recoil tween
	_recoilValue = nil,      -- NumberValue for tweening
	
	-- Connections
	_connections = {},
}

-- === CONFIGURATION ===
local CONFIG = {
	Enabled = true,
	
	-- Movement thresholds
	IdleThreshold = 0.5,         -- Below this speed = idle
	WalkThreshold = 12,          -- Below this = walk, above = run
	WalkSpeed = 24,              -- Base movement speed (higher!)
	RunSpeed = 36,               -- Sprint speed
	
	-- Stride settings
	StrideLength = 2.5,          -- Distance between steps (studs)
	StrideLengthRun = 3.5,       -- Stride when running
	StepHeight = 1.0,            -- How high feet lift
	StepHeightRun = 1.5,         -- Higher steps when running
	
	-- Foot placement
	FootRaycastDistance = 4,     -- How far down to raycast for ground
	FootGroundOffset = 0.1,      -- Offset from ground surface
	FootPlantDuration = 0.3,     -- Time foot stays planted (ratio of cycle)
	
	-- Body motion
	BodyBobAmount = 0.15,        -- Vertical bounce
	BodyBobAmountRun = 0.25,
	BodySwayAmount = 0.05,       -- Side-to-side lean
	BodyTiltForward = 0.1,       -- Lean forward when moving
	
	-- Arm swing
	ArmSwingAmount = 0.8,        -- How much arms swing (radians)
	ArmSwingAmountRun = 1.2,
	ArmForwardOffset = 0.3,      -- Arms slightly forward
	
	-- Right arm extended forward (like pointing/aiming)
	RightArmExtended = true,     -- Keep right arm extended forward
	RightArmForwardDistance = 2.5, -- How far forward the right hand extends
	RightArmHeightOffset = 0.8,  -- Height relative to shoulder
	
	-- Arm Cannon Settings (Samus-style)
	UseArmCannon = true,         -- Replace right arm with cannon
	CannonLength = 2.5,          -- Total cannon length
	CannonBaseWidth = 0.6,       -- Width at shoulder
	CannonTipWidth = 0.4,        -- Width at barrel tip
	CannonColor = Color3.fromRGB(255, 140, 0),      -- Orange (Samus color)
	CannonAccentColor = Color3.fromRGB(40, 40, 50), -- Dark metal
	CannonGlowColor = Color3.fromRGB(0, 200, 255),  -- Cyan glow
	
	-- Projectile Settings
	ProjectileSpeed = 200,       -- Studs per second
	ProjectileGravity = Vector3.new(0, 0, 0),   -- No gravity - straight line
	ProjectileSize = 0.8,        -- Sphere diameter
	ProjectileColor = Color3.fromRGB(0, 200, 255), -- Cyan energy ball
	ProjectileMaxDistance = 500, -- Max travel distance
	FireRate = 0,                -- No rate limiting - fire as fast as you click
	
	-- Recoil Settings
	RecoilAmount = 0.5,          -- How far cannon kicks back (studs)
	RecoilDuration = 0.15,       -- How long recoil animation takes (seconds)
	
	-- Head
	HeadStabilization = true,    -- Keep head level
	HeadLookAhead = 2,           -- Look ahead distance
	
	-- Smoothing
	IKSmoothTime = 0.05,         -- IK interpolation
	TransitionSpeed = 8,         -- Idle/walk/run blend speed
	
	-- Movement Smoothing
	MovementSmoothing = true,    -- Enable smooth acceleration/deceleration
	AccelerationTime = 0.3,      -- Time to reach full speed (seconds)
	DecelerationTime = 0.2,      -- Time to stop (seconds)
	
	-- Jump Smoothing
	CustomJump = true,           -- Use custom jump curve
	JumpHeight = 14,             -- Jump height in studs (increased!)
	JumpDuration = 0.6,          -- Time to reach peak (seconds)
	JumpHangTime = 0.2,          -- Extra time at peak (floaty feel)
	GravityMultiplier = 1.5,     -- Falling speed multiplier
	
	-- Debug
	ShowTargets = false,
	ShowRaycasts = false,
}

-- === HELPER FUNCTIONS ===

local function lerp(a, b, t)
	return a + (b - a) * t
end

local function lerpCFrame(a, b, t)
	return a:Lerp(b, t)
end

-- Smooth step function (ease in/out)
local function smoothstep(t)
	return t * t * (3 - 2 * t)
end

-- Easing functions for smooth movement
local Easing = {
	-- Ease out quad - fast start, slow end (good for deceleration)
	outQuad = function(t)
		return 1 - (1 - t) * (1 - t)
	end,
	
	-- Ease in quad - slow start, fast end (good for acceleration)
	inQuad = function(t)
		return t * t
	end,
	
	-- Ease in-out quad - smooth both ends
	inOutQuad = function(t)
		if t < 0.5 then
			return 2 * t * t
		else
			return 1 - math.pow(-2 * t + 2, 2) / 2
		end
	end,
	
	-- Ease out cubic - smoother deceleration
	outCubic = function(t)
		return 1 - math.pow(1 - t, 3)
	end,
	
	-- Ease in-out cubic
	inOutCubic = function(t)
		if t < 0.5 then
			return 4 * t * t * t
		else
			return 1 - math.pow(-2 * t + 2, 3) / 2
		end
	end,
	
	-- Ease out elastic - bouncy overshoot
	outElastic = function(t)
		if t == 0 or t == 1 then return t end
		return math.pow(2, -10 * t) * math.sin((t * 10 - 0.75) * (2 * math.pi) / 3) + 1
	end,
	
	-- Jump curve - fast up, hang at top, fast down
	jumpCurve = function(t, hangTime)
		hangTime = hangTime or 0.15
		local hangStart = 0.5 - hangTime / 2
		local hangEnd = 0.5 + hangTime / 2
		
		if t < hangStart then
			-- Rising - ease out (fast then slow)
			local normalized = t / hangStart
			return Easing.outCubic(normalized) * 0.5
		elseif t < hangEnd then
			-- Hang time at peak
			return 0.5
		else
			-- Falling - ease in (slow then fast)
			local normalized = (t - hangEnd) / (1 - hangEnd)
			return 0.5 + Easing.inQuad(normalized) * 0.5
		end
	end
}

-- Smooth damp function (like Unity's SmoothDamp)
local function smoothDamp(current, target, velocity, smoothTime, maxSpeed, dt)
	smoothTime = math.max(0.0001, smoothTime)
	local omega = 2 / smoothTime
	local x = omega * dt
	local exp = 1 / (1 + x + 0.48 * x * x + 0.235 * x * x * x)
	local change = current - target
	local originalTo = target
	
	local maxChange = maxSpeed * smoothTime
	change = math.clamp(change, -maxChange, maxChange)
	target = current - change
	
	local temp = (velocity + omega * change) * dt
	velocity = (velocity - omega * temp) * exp
	local output = target + (change + temp) * exp
	
	if (originalTo - current > 0) == (output > originalTo) then
		output = originalTo
		velocity = (output - originalTo) / dt
	end
	
	return output, velocity
end

-- Vector3 smooth damp
local function smoothDampVector3(current, target, velocity, smoothTime, maxSpeed, dt)
	local x, vx = smoothDamp(current.X, target.X, velocity.X, smoothTime, maxSpeed, dt)
	local y, vy = smoothDamp(current.Y, target.Y, velocity.Y, smoothTime, maxSpeed, dt)
	local z, vz = smoothDamp(current.Z, target.Z, velocity.Z, smoothTime, maxSpeed, dt)
	return Vector3.new(x, y, z), Vector3.new(vx, vy, vz)
end

-- Get movement direction and speed from HRP
local function getMovementInfo(hrp)
	local velocity = hrp.AssemblyLinearVelocity
	local horizontalVel = Vector3.new(velocity.X, 0, velocity.Z)
	local speed = horizontalVel.Magnitude
	local direction = speed > 0.1 and horizontalVel.Unit or hrp.CFrame.LookVector
	return speed, direction, velocity.Y
end

-- Raycast to find ground position
local function raycastGround(origin, character)
	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.FilterDescendantsInstances = {character}
	
	local result = Workspace:Raycast(origin, Vector3.new(0, -CONFIG.FootRaycastDistance, 0), rayParams)
	
	if result then
		return result.Position, result.Normal, true
	else
		return origin + Vector3.new(0, -CONFIG.FootRaycastDistance, 0), Vector3.yAxis, false
	end
end

-- Calculate foot arc position during step
local function calculateFootArc(startPos, endPos, progress, stepHeight)
	-- Parabolic arc for foot lift
	local arcHeight = math.sin(progress * math.pi) * stepHeight
	local pos = startPos:Lerp(endPos, smoothstep(progress))
	return pos + Vector3.new(0, arcHeight, 0)
end

-- === IK SETUP ===

function ProceduralLocomotionController:CreateIKTarget(name, parent)
	local target = Instance.new("Part")
	target.Name = name .. "Target"
	target.Size = Vector3.new(0.3, 0.3, 0.3)
	target.Anchored = true
	target.CanCollide = false
	target.CanQuery = false
	target.CanTouch = false
	target.Transparency = CONFIG.ShowTargets and 0 or 1
	target.Color = Color3.fromRGB(0, 255, 100)
	target.Material = Enum.Material.Neon
	target.Parent = parent
	return target
end

function ProceduralLocomotionController:CreateIKControl(name, humanoid, endEffector, chainRoot, target)
	local ikControl = Instance.new("IKControl")
	ikControl.Name = name
	ikControl.Type = Enum.IKControlType.Transform
	ikControl.EndEffector = endEffector
	ikControl.ChainRoot = chainRoot
	ikControl.Target = target
	ikControl.Weight = 1
	ikControl.SmoothTime = CONFIG.IKSmoothTime
	ikControl.Parent = humanoid
	return ikControl
end

function ProceduralLocomotionController:SetupAllIK(character)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then return false end
	
	-- Get all required body parts
	local parts = {
		LeftFoot = character:FindFirstChild("LeftFoot"),
		RightFoot = character:FindFirstChild("RightFoot"),
		LeftHand = character:FindFirstChild("LeftHand"),
		RightHand = character:FindFirstChild("RightHand"),
		LeftUpperLeg = character:FindFirstChild("LeftUpperLeg"),
		RightUpperLeg = character:FindFirstChild("RightUpperLeg"),
		LeftUpperArm = character:FindFirstChild("LeftUpperArm"),
		RightUpperArm = character:FindFirstChild("RightUpperArm"),
		Head = character:FindFirstChild("Head"),
		UpperTorso = character:FindFirstChild("UpperTorso"),
	}
	
	-- Verify all parts exist
	for name, part in pairs(parts) do
		if not part then
			warn("[ProceduralLocomotion] Missing body part:", name)
			return false
		end
	end
	
	-- Create IK folder
	local ikFolder = Instance.new("Folder")
	ikFolder.Name = "ProceduralIK"
	ikFolder.Parent = character
	
	-- Left Leg IK
	self._ikTargets.LeftFoot = self:CreateIKTarget("LeftFoot", ikFolder)
	self._ikControls.LeftLeg = self:CreateIKControl(
		"LeftLegIK", humanoid, parts.LeftFoot, parts.LeftUpperLeg, self._ikTargets.LeftFoot
	)
	
	-- Right Leg IK
	self._ikTargets.RightFoot = self:CreateIKTarget("RightFoot", ikFolder)
	self._ikControls.RightLeg = self:CreateIKControl(
		"RightLegIK", humanoid, parts.RightFoot, parts.RightUpperLeg, self._ikTargets.RightFoot
	)
	
	-- Left Arm IK
	self._ikTargets.LeftHand = self:CreateIKTarget("LeftHand", ikFolder)
	self._ikControls.LeftArm = self:CreateIKControl(
		"LeftArmIK", humanoid, parts.LeftHand, parts.LeftUpperArm, self._ikTargets.LeftHand
	)
	
	-- Right Arm IK
	self._ikTargets.RightHand = self:CreateIKTarget("RightHand", ikFolder)
	self._ikControls.RightArm = self:CreateIKControl(
		"RightArmIK", humanoid, parts.RightHand, parts.RightUpperArm, self._ikTargets.RightHand
	)
	
	return true
end

-- === ARM CANNON ===

function ProceduralLocomotionController:CreateArmCannon(character)
	-- Hide both arms
	local armParts = {
		"RightUpperArm", "RightLowerArm", "RightHand",
		"LeftUpperArm", "LeftLowerArm", "LeftHand"
	}
	for _, partName in ipairs(armParts) do
		local part = character:FindFirstChild(partName)
		if part then
			part.Transparency = 1
			for _, child in ipairs(part:GetChildren()) do
				if child:IsA("BasePart") then
					child.Transparency = 1
				end
			end
		end
	end
	
	-- Create cannon model
	local cannonModel = Instance.new("Model")
	cannonModel.Name = "ArmCannon"
	
	-- 1. Shoulder Mount
	local shoulderMount = Instance.new("Part")
	shoulderMount.Name = "ShoulderMount"
	shoulderMount.Shape = Enum.PartType.Ball
	shoulderMount.Size = Vector3.new(0.8, 0.8, 0.8)
	shoulderMount.Color = CONFIG.CannonAccentColor
	shoulderMount.Material = Enum.Material.Metal
	shoulderMount.CanCollide = false
	shoulderMount.Anchored = true
	shoulderMount.Parent = cannonModel
	table.insert(self._cannonParts, shoulderMount)
	
	-- 2. Upper Section
	local upperSection = Instance.new("Part")
	upperSection.Name = "UpperSection"
	upperSection.Size = Vector3.new(CONFIG.CannonBaseWidth, 0.8, CONFIG.CannonBaseWidth)
	upperSection.Color = CONFIG.CannonColor
	upperSection.Material = Enum.Material.SmoothPlastic
	upperSection.CanCollide = false
	upperSection.Anchored = true
	upperSection.Parent = cannonModel
	local upperMesh = Instance.new("SpecialMesh")
	upperMesh.MeshType = Enum.MeshType.Cylinder
	upperMesh.Parent = upperSection
	table.insert(self._cannonParts, upperSection)
	
	-- 3. Elbow Ring
	local elbowRing = Instance.new("Part")
	elbowRing.Name = "ElbowRing"
	elbowRing.Shape = Enum.PartType.Cylinder
	elbowRing.Size = Vector3.new(0.15, 0.7, 0.7)
	elbowRing.Color = CONFIG.CannonAccentColor
	elbowRing.Material = Enum.Material.Metal
	elbowRing.CanCollide = false
	elbowRing.Anchored = true
	elbowRing.Parent = cannonModel
	table.insert(self._cannonParts, elbowRing)
	
	-- 4. Main Body
	local mainBody = Instance.new("Part")
	mainBody.Name = "MainBody"
	mainBody.Size = Vector3.new(CONFIG.CannonBaseWidth * 1.2, 1.2, CONFIG.CannonBaseWidth * 1.2)
	mainBody.Color = CONFIG.CannonColor
	mainBody.Material = Enum.Material.SmoothPlastic
	mainBody.CanCollide = false
	mainBody.Anchored = true
	mainBody.Parent = cannonModel
	local mainMesh = Instance.new("SpecialMesh")
	mainMesh.MeshType = Enum.MeshType.Cylinder
	mainMesh.Parent = mainBody
	table.insert(self._cannonParts, mainBody)
	
	-- 5. Barrel
	local barrel = Instance.new("Part")
	barrel.Name = "Barrel"
	barrel.Size = Vector3.new(CONFIG.CannonTipWidth, 0.8, CONFIG.CannonTipWidth)
	barrel.Color = CONFIG.CannonAccentColor
	barrel.Material = Enum.Material.Metal
	barrel.CanCollide = false
	barrel.Anchored = true
	barrel.Parent = cannonModel
	local barrelMesh = Instance.new("SpecialMesh")
	barrelMesh.MeshType = Enum.MeshType.Cylinder
	barrelMesh.Parent = barrel
	table.insert(self._cannonParts, barrel)
	
	-- 6. Barrel Tip
	local barrelTip = Instance.new("Part")
	barrelTip.Name = "BarrelTip"
	barrelTip.Shape = Enum.PartType.Cylinder
	barrelTip.Size = Vector3.new(0.1, CONFIG.CannonTipWidth * 0.8, CONFIG.CannonTipWidth * 0.8)
	barrelTip.Color = CONFIG.CannonGlowColor
	barrelTip.Material = Enum.Material.Neon
	barrelTip.CanCollide = false
	barrelTip.Anchored = true
	barrelTip.Parent = cannonModel
	table.insert(self._cannonParts, barrelTip)
	
	-- 7. Energy Core
	local energyCore = Instance.new("Part")
	energyCore.Name = "EnergyCore"
	energyCore.Shape = Enum.PartType.Ball
	energyCore.Size = Vector3.new(0.3, 0.3, 0.3)
	energyCore.Color = CONFIG.CannonGlowColor
	energyCore.Material = Enum.Material.Neon
	energyCore.CanCollide = false
	energyCore.Anchored = true
	energyCore.Parent = cannonModel
	table.insert(self._cannonParts, energyCore)
	
	-- 8-9. Side Vents
	for i = 1, 2 do
		local vent = Instance.new("Part")
		vent.Name = "Vent" .. i
		vent.Size = Vector3.new(0.1, 0.3, 0.15)
		vent.Color = CONFIG.CannonAccentColor
		vent.Material = Enum.Material.Metal
		vent.CanCollide = false
		vent.Anchored = true
		vent.Parent = cannonModel
		table.insert(self._cannonParts, vent)
	end
	
	-- Add glow light
	local glowLight = Instance.new("PointLight")
	glowLight.Color = CONFIG.CannonGlowColor
	glowLight.Brightness = 1
	glowLight.Range = 4
	glowLight.Parent = barrelTip
	
	cannonModel.Parent = character
	self._armCannon = cannonModel
end

function ProceduralLocomotionController:UpdateArmCannon()
	if not self._armCannon or not self._hrp then return end
	if #self._cannonParts == 0 then return end
	
	local hrpCF = self._hrp.CFrame
	local hrpPos = hrpCF.Position
	
	-- Get camera direction for aiming
	local camera = Workspace.CurrentCamera
	local aimDir = camera and camera.CFrame.LookVector or hrpCF.LookVector
	
	-- Shoulder position based on character
	local shoulderHeight = 1.3
	local shoulderWidth = 0.8
	local shoulderPos = hrpPos + hrpCF.RightVector * shoulderWidth + Vector3.new(0, shoulderHeight, 0)
	
	-- Smooth the aim direction with drift clamping
	local smoothFactor = 0.5
	local maxDriftAngle = 0.1  -- Maximum radians the cannon can drift from camera (about 6 degrees)
	
	local smoothAimDir
	if self._lastAimDir then
		-- Lerp toward camera direction
		smoothAimDir = self._lastAimDir:Lerp(aimDir.Unit, smoothFactor)
		
		-- Clamp: if drifted too far from camera, snap closer
		local drift = smoothAimDir:Dot(aimDir.Unit)  -- 1 = same direction, -1 = opposite
		if drift < math.cos(maxDriftAngle) then
			-- Too much drift, lerp more aggressively toward camera
			smoothAimDir = smoothAimDir:Lerp(aimDir.Unit, 0.8)
		end
	else
		smoothAimDir = aimDir.Unit
	end
	self._lastAimDir = smoothAimDir
	
	-- Calculate recoil (only applied to front barrel parts)
	local recoilAmount = (self._recoilOffset or 0) * CONFIG.RecoilAmount
	local recoilVector = -smoothAimDir * recoilAmount
	
	local cylinderRotation = CFrame.Angles(0, math.rad(90), 0)
	
	-- 1. Shoulder Mount (no recoil)
	if self._cannonParts[1] then
		self._cannonParts[1].CFrame = CFrame.new(shoulderPos)
	end
	
	-- 2. Upper Section (no recoil)
	if self._cannonParts[2] then
		local pos = shoulderPos + smoothAimDir * 0.5
		self._cannonParts[2].CFrame = CFrame.lookAt(pos, pos + smoothAimDir) * cylinderRotation
	end
	
	-- 3. Elbow Ring (no recoil)
	if self._cannonParts[3] then
		local pos = shoulderPos + smoothAimDir * 0.9
		self._cannonParts[3].CFrame = CFrame.lookAt(pos, pos + smoothAimDir) * cylinderRotation
	end
	
	-- 4. Main Body (no recoil)
	if self._cannonParts[4] then
		local pos = shoulderPos + smoothAimDir * 1.5
		self._cannonParts[4].CFrame = CFrame.lookAt(pos, pos + smoothAimDir) * cylinderRotation
	end
	
	-- 5. Barrel (RECOIL - slides back)
	if self._cannonParts[5] then
		local pos = shoulderPos + smoothAimDir * 2.2 + recoilVector
		self._cannonParts[5].CFrame = CFrame.lookAt(pos, pos + smoothAimDir) * cylinderRotation
	end
	
	-- 6. Barrel Tip (RECOIL - slides back)
	if self._cannonParts[6] then
		local pos = shoulderPos + smoothAimDir * CONFIG.CannonLength + recoilVector
		self._cannonParts[6].CFrame = CFrame.lookAt(pos, pos + smoothAimDir) * cylinderRotation
	end
	
	-- 7. Energy Core (pulsing, no recoil)
	if self._cannonParts[7] then
		local pulse = 0.3 + math.sin(tick() * 4) * 0.1
		self._cannonParts[7].Size = Vector3.new(pulse, pulse, pulse)
		local pos = shoulderPos + smoothAimDir * 1.5
		self._cannonParts[7].CFrame = CFrame.new(pos)
	end
	
	-- 8-9. Side Vents (no recoil)
	local ventCF = CFrame.lookAt(shoulderPos + smoothAimDir * 1.3, shoulderPos + smoothAimDir * 2)
	if self._cannonParts[8] then
		local pos = shoulderPos + smoothAimDir * 1.3 + ventCF.RightVector * 0.4
		self._cannonParts[8].CFrame = CFrame.lookAt(pos, pos + smoothAimDir)
	end
	if self._cannonParts[9] then
		local pos = shoulderPos + smoothAimDir * 1.3 + ventCF.RightVector * -0.4
		self._cannonParts[9].CFrame = CFrame.lookAt(pos, pos + smoothAimDir)
	end
end

function ProceduralLocomotionController:DestroyArmCannon()
	if self._armCannon then
		self._armCannon:Destroy()
		self._armCannon = nil
	end
	self._cannonParts = {}
	self._cannonPivot = nil
	self._cannonMotor = nil
	self._lastAimDir = nil
end

-- === SHOOTING SYSTEM ===

function ProceduralLocomotionController:SetupShooting()
	-- Create FastCast caster
	self._caster = FastCast.new()
	
	-- Create projectile template (energy sphere)
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
	
	-- Create bullet container folder
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
	self._castBehavior.RaycastParams.FilterDescendantsInstances = {self._character, bulletContainer}
	self._castBehavior.Acceleration = CONFIG.ProjectileGravity
	self._castBehavior.MaxDistance = CONFIG.ProjectileMaxDistance
	self._castBehavior.CosmeticBulletTemplate = bulletTemplate
	self._castBehavior.CosmeticBulletContainer = bulletContainer
	self._castBehavior.AutoIgnoreContainer = true
	
	-- Connect FastCast events
	self._caster.LengthChanged:Connect(function(cast, lastPoint, direction, length, velocity, bullet)
		if bullet then
			-- Update bullet position along the ray
			local newPos = lastPoint + (direction * length)
			bullet.CFrame = CFrame.lookAt(newPos, newPos + velocity)
		end
	end)
	
	self._caster.RayHit:Connect(function(cast, result, velocity, bullet)
		-- Hit something!
		if bullet then
			self:OnProjectileHit(bullet, result, velocity)
		end
	end)
	
	self._caster.CastTerminating:Connect(function(cast)
		-- Cast ended (max distance or hit)
		local bullet = cast.RayInfo.CosmeticBulletObject
		if bullet then
			self:DestroyProjectile(bullet)
		end
	end)
	
	-- Setup mouse input for shooting
	local inputConn = UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed then return end
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			self:FireProjectile()
		end
	end)
	table.insert(self._connections, inputConn)
	
end

function ProceduralLocomotionController:GetCannonTipPosition()
	-- Get the position at the end of the cannon barrel
	-- Barrel tip is _cannonParts[6]
	local barrelTip = self._cannonParts and self._cannonParts[6]
	if not barrelTip then return nil, nil end
	
	local camera = Workspace.CurrentCamera
	local aimDir = camera and camera.CFrame.LookVector or Vector3.new(0, 0, -1)
	
	-- Get tip position from barrel tip part
	local tipPos = barrelTip.Position + aimDir * 0.2  -- Slightly in front of tip
	
	return tipPos, aimDir
end

function ProceduralLocomotionController:FireProjectile()
	if not self._caster or not self._castBehavior then return end
	
	-- Check fire rate
	local now = tick()
	if now - self._lastFireTime < CONFIG.FireRate then
		return
	end
	self._lastFireTime = now
	
	-- Get fire position and direction
	local origin, direction = self:GetCannonTipPosition()
	if not origin or not direction then return end
	
	-- Update raycast filter to exclude current character
	self._castBehavior.RaycastParams.FilterDescendantsInstances = {
		self._character,
		Workspace:FindFirstChild("ProjectileContainer")
	}
	
	-- Fire the projectile!
	self._caster:Fire(origin, direction, CONFIG.ProjectileSpeed, self._castBehavior)
	
	-- Visual feedback - flash the cannon tip
	self:CannonFireEffect()
	
end

function ProceduralLocomotionController:CannonFireEffect()
	-- Create NumberValue for tweening if it doesn't exist
	if not self._recoilValue then
		self._recoilValue = Instance.new("NumberValue")
		self._recoilValue.Value = 0
		self._recoilValue.Changed:Connect(function(value)
			self._recoilOffset = value
		end)
	end
	
	-- Cancel any existing tween
	if self._recoilTween then
		self._recoilTween:Cancel()
	end
	
	-- Instantly kick back to max recoil
	self._recoilValue.Value = 1
	self._recoilOffset = 1
	
	-- Tween back to 0 (return to normal position)
	local tweenInfo = TweenInfo.new(
		CONFIG.RecoilDuration,           -- Duration
		Enum.EasingStyle.Quad,           -- Easing style
		Enum.EasingDirection.Out,        -- Ease out (fast start, slow end)
		0,                               -- Repeat count
		false,                           -- Reverses
		0                                -- Delay
	)
	
	self._recoilTween = TweenService:Create(self._recoilValue, tweenInfo, {Value = 0})
	self._recoilTween:Play()
	
	-- Flash effect on the barrel tip
	if self._cannonParts[6] then -- Barrel tip
		local tip = self._cannonParts[6]
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
	
	-- Flash the energy core
	if self._cannonParts[7] then
		local core = self._cannonParts[7]
		local originalSize = core.Size
		core.Size = originalSize * 2
		
		task.delay(0.1, function()
			if core and core.Parent then
				core.Size = originalSize
			end
		end)
	end
end

function ProceduralLocomotionController:UpdateRecoil(dt)
	-- Recoil is now handled by TweenService, nothing to do here
	-- _recoilOffset is updated automatically via NumberValue.Changed
end

function ProceduralLocomotionController:OnProjectileHit(bullet, rayResult, velocity)
	-- Create impact effect
	local hitPos = rayResult.Position
	local hitNormal = rayResult.Normal
	
	-- Spawn impact particles/effect
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
	
	-- Animate impact (expand and fade)
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
	
	-- TODO: Add damage logic here if hitting an enemy
	local hitPart = rayResult.Instance
	if hitPart then
	end
end

function ProceduralLocomotionController:DestroyProjectile(bullet)
	if bullet and bullet.Parent then
		bullet:Destroy()
	end
end

function ProceduralLocomotionController:CleanupShooting()
	self._caster = nil
	self._castBehavior = nil
	self._activeBullets = {}
	
	-- Clean up recoil tween
	if self._recoilTween then
		self._recoilTween:Cancel()
		self._recoilTween = nil
	end
	if self._recoilValue then
		self._recoilValue:Destroy()
		self._recoilValue = nil
	end
	self._recoilOffset = 0
end

-- === ANIMATION DISABLING ===

function ProceduralLocomotionController:DisableDefaultAnimations(character)
	-- Remove default scripts attached to player character
	local scriptsToRemove = {
		"Animate",      -- Default animation controller
		"Health",       -- Health regeneration script
		"Sound",        -- Footstep and other sounds
	}
	
	for _, scriptName in ipairs(scriptsToRemove) do
		local script = character:FindFirstChild(scriptName)
		if script then
			script:Destroy()
		end
	end
	
	-- Disable RbxCharacterSounds (handles footstep sounds from StarterPlayerScripts)
	local player = Players.LocalPlayer
	local playerScripts = player:FindFirstChild("PlayerScripts")
	if playerScripts then
		local rbxCharSounds = playerScripts:FindFirstChild("RbxCharacterSounds")
		if rbxCharSounds then
			rbxCharSounds.Disabled = true
			rbxCharSounds:Destroy()
		end
	end
	
	-- Also check StarterPlayerScripts directly
	local starterPlayerScripts = game:GetService("StarterPlayer"):FindFirstChild("StarterPlayerScripts")
	if starterPlayerScripts then
		local rbxCharSounds = starterPlayerScripts:FindFirstChild("RbxCharacterSounds")
		if rbxCharSounds then
			rbxCharSounds.Disabled = true
		end
	end
	
	-- Remove/mute all Sound instances in the character (footsteps, etc.)
	for _, descendant in ipairs(character:GetDescendants()) do
		if descendant:IsA("Sound") then
			descendant.Volume = 0
			descendant:Stop()
			descendant:Destroy()
		end
	end
	
	-- Also destroy the HumanoidRootPart sounds folder if it exists
	local hrp = character:FindFirstChild("HumanoidRootPart")
	if hrp then
		-- Check for any sound-related children
		for _, child in ipairs(hrp:GetChildren()) do
			if child:IsA("Sound") or child.Name == "Running" or child.Name == "Climbing" or child.Name == "Jumping" or child.Name == "GettingUp" or child.Name == "FreeFalling" or child.Name == "Landing" or child.Name == "Splash" or child.Name == "Swimming" then
				child:Destroy()
			end
		end
	end
	
	-- Destroy sounds in Head too
	local head = character:FindFirstChild("Head")
	if head then
		for _, child in ipairs(head:GetChildren()) do
			if child:IsA("Sound") then
				child:Destroy()
			end
		end
	end
	
	-- Watch for any sounds added later and destroy them too
	local soundWatcher = character.DescendantAdded:Connect(function(descendant)
		if descendant:IsA("Sound") then
			task.defer(function()
				if descendant and descendant.Parent then
					descendant.Volume = 0
					descendant:Stop()
					descendant:Destroy()
				end
			end)
		end
	end)
	table.insert(self._connections, soundWatcher)
	
	-- Stop any playing animation tracks
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		local animator = humanoid:FindFirstChildOfClass("Animator")
		if animator then
			for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
				track:Stop(0)
			end
		end
	end
	
	-- Get motor references for transform override
	self._motors = {}
	local motorNames = {
		"LeftHip", "LeftKnee", "LeftAnkle",
		"RightHip", "RightKnee", "RightAnkle",
		"LeftShoulder", "LeftElbow", "LeftWrist",
		"RightShoulder", "RightElbow", "RightWrist",
		"Waist", "Neck", "Root"
	}
	
	for _, descendant in ipairs(character:GetDescendants()) do
		if descendant:IsA("Motor6D") then
			for _, motorName in ipairs(motorNames) do
				if descendant.Name == motorName then
					self._motors[motorName] = descendant
				end
			end
		end
	end
	
end

-- === PHYSICS-BASED MOVEMENT ===

function ProceduralLocomotionController:SetupMovementSmoothing(character)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not humanoid or not hrp then return end
	
	-- Store original values
	self._originalWalkSpeed = humanoid.WalkSpeed
	self._originalJumpPower = humanoid.JumpPower
	self._originalJumpHeight = humanoid.JumpHeight
	
	-- Apply custom walk speed
	humanoid.WalkSpeed = CONFIG.WalkSpeed
	
	-- Create attachment for forces (at center of HRP)
	local attachment = hrp:FindFirstChild("MovementAttachment")
	if not attachment then
		attachment = Instance.new("Attachment")
		attachment.Name = "MovementAttachment"
		attachment.Position = Vector3.zero
		attachment.Parent = hrp
	end
	self._attachment = attachment
	
	-- Create VectorForce for horizontal movement
	if CONFIG.MovementSmoothing then
		local moveForce = Instance.new("VectorForce")
		moveForce.Name = "MoveForce"
		moveForce.Attachment0 = attachment
		moveForce.RelativeTo = Enum.ActuatorRelativeTo.World
		moveForce.ApplyAtCenterOfMass = true
		moveForce.Force = Vector3.zero
		moveForce.Parent = hrp
		self._moveForce = moveForce
	end
	
	-- Create VectorForce for jump
	if CONFIG.CustomJump then
		local jumpForce = Instance.new("VectorForce")
		jumpForce.Name = "JumpForce"
		jumpForce.Attachment0 = attachment
		jumpForce.RelativeTo = Enum.ActuatorRelativeTo.World
		jumpForce.ApplyAtCenterOfMass = true
		jumpForce.Force = Vector3.zero
		jumpForce.Parent = hrp
		self._jumpForce = jumpForce
		
		-- Disable default jump
		humanoid.JumpPower = 0
		humanoid.JumpHeight = 0
		
		-- Listen for jump input
		local jumpConn = humanoid:GetPropertyChangedSignal("Jump"):Connect(function()
			if humanoid.Jump and self:IsGrounded() and not self._isJumping then
				self:StartCustomJump()
			end
			humanoid.Jump = false
		end)
		table.insert(self._connections, jumpConn)
	end
	
end

function ProceduralLocomotionController:IsGrounded()
	if not self._hrp then return true end
	
	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.FilterDescendantsInstances = {self._character}
	
	local origin = self._hrp.Position
	local result = Workspace:Raycast(origin, Vector3.new(0, -3.5, 0), rayParams)
	
	return result ~= nil
end

function ProceduralLocomotionController:StartCustomJump()
	if self._isJumping then return end
	
	self._isJumping = true
	self._jumpStartTime = tick()
	self._jumpPhase = "rising"
	
	-- Calculate initial jump impulse using physics
	-- v = sqrt(2 * g * h) for desired height
	local gravity = Workspace.Gravity
	local jumpVelocity = math.sqrt(2 * gravity * CONFIG.JumpHeight)
	
	-- Apply initial impulse
	if self._hrp then
		self._hrp.AssemblyLinearVelocity = Vector3.new(
			self._hrp.AssemblyLinearVelocity.X,
			jumpVelocity,
			self._hrp.AssemblyLinearVelocity.Z
		)
	end
	
end

function ProceduralLocomotionController:UpdateCustomJump(dt)
	if not self._isJumping then return end
	if not self._jumpForce or not self._hrp then return end
	
	local elapsed = tick() - self._jumpStartTime
	local verticalVel = self._hrp.AssemblyLinearVelocity.Y
	local gravity = Workspace.Gravity
	local mass = self._hrp.AssemblyMass
	
	-- Determine jump phase
	if self._jumpPhase == "rising" and verticalVel <= 2 then
		self._jumpPhase = "hanging"
		self._hangStartTime = tick()
	elseif self._jumpPhase == "hanging" then
		local hangElapsed = tick() - self._hangStartTime
		if hangElapsed > CONFIG.JumpHangTime then
			self._jumpPhase = "falling"
		end
	end
	
	-- Apply forces based on phase
	local force = Vector3.zero
	
	if self._jumpPhase == "rising" then
		-- Slight upward boost for more floaty rise
		local riseBoost = mass * gravity * 0.2 * Easing.outQuad(math.clamp(verticalVel / 20, 0, 1))
		force = Vector3.new(0, riseBoost, 0)
		
	elseif self._jumpPhase == "hanging" then
		-- Counter gravity during hang time for floaty peak
		local hangProgress = (tick() - self._hangStartTime) / CONFIG.JumpHangTime
		local hangStrength = Easing.inOutQuad(1 - math.abs(hangProgress * 2 - 1))
		local counterGravity = mass * gravity * 0.9 * hangStrength
		force = Vector3.new(0, counterGravity, 0)
		
	elseif self._jumpPhase == "falling" then
		-- Extra downward force for snappy landing (coyote-style)
		local fallBoost = mass * gravity * (CONFIG.GravityMultiplier - 1)
		force = Vector3.new(0, -fallBoost, 0)
	end
	
	self._jumpForce.Force = force
	
	-- Check if landed
	if self._jumpPhase == "falling" and self:IsGrounded() and verticalVel <= 0 then
		self:EndCustomJump()
	end
	
	-- Safety timeout
	if elapsed > 3 then
		self:EndCustomJump()
	end
end

function ProceduralLocomotionController:EndCustomJump()
	self._isJumping = false
	self._jumpPhase = "none"
	
	if self._jumpForce then
		self._jumpForce.Force = Vector3.zero
	end
	
end

function ProceduralLocomotionController:UpdateMovementSmoothing(dt)
	if not CONFIG.MovementSmoothing then return end
	if not self._hrp or not self._humanoid or not self._moveForce then return end
	
	local moveDir = self._humanoid.MoveDirection
	local currentVel = self._hrp.AssemblyLinearVelocity
	local horizontalVel = Vector3.new(currentVel.X, 0, currentVel.Z)
	local mass = self._hrp.AssemblyMass
	
	-- Target velocity based on input
	local targetSpeed = self._humanoid.WalkSpeed
	local targetVel = moveDir * targetSpeed
	
	-- Calculate velocity error
	local velError = targetVel - horizontalVel
	
	-- PD controller for smooth force application
	local kP = mass * (1 / CONFIG.AccelerationTime) * 10  -- Proportional gain
	local kD = mass * 2  -- Damping
	
	-- Calculate force
	local force = velError * kP
	
	-- Add damping when stopping
	if moveDir.Magnitude < 0.1 then
		force = force - horizontalVel * (mass / CONFIG.DecelerationTime) * 5
	end
	
	-- Clamp force magnitude
	local maxForce = mass * 100
	if force.Magnitude > maxForce then
		force = force.Unit * maxForce
	end
	
	-- Apply easing curve to force for smoother feel
	local speedRatio = horizontalVel.Magnitude / math.max(targetSpeed, 0.1)
	local easedMultiplier = moveDir.Magnitude > 0.1 
		and Easing.outQuad(math.clamp(1 - speedRatio, 0, 1))  -- Accelerating
		or Easing.inQuad(math.clamp(speedRatio, 0, 1))        -- Decelerating
	
	force = force * (0.5 + easedMultiplier * 0.5)
	
	self._moveForce.Force = force
	
	-- Update smoothed values for animation
	self._smoothedSpeed = horizontalVel.Magnitude
	if moveDir.Magnitude > 0.1 then
		self._smoothedDirection = moveDir
	end
end

-- === LOCOMOTION UPDATE ===

function ProceduralLocomotionController:UpdateLocomotion(dt)
	if not self._hrp or not self._hrp.Parent then return end
	
	local speed, moveDir, verticalVel = getMovementInfo(self._hrp)
	local hrpCF = self._hrp.CFrame
	local hrpPos = hrpCF.Position
	
	-- Use smoothed values if movement smoothing is enabled
	if CONFIG.MovementSmoothing and self._smoothedSpeed then
		speed = self._smoothedSpeed
		if self._smoothedDirection and self._smoothedDirection.Magnitude > 0.1 then
			moveDir = self._smoothedDirection.Unit
		end
	end
	
	-- Determine locomotion state
	local isIdle = speed < CONFIG.IdleThreshold
	local isRunning = speed > CONFIG.WalkThreshold
	
	-- Get speed-dependent values
	local strideLength = isRunning and CONFIG.StrideLengthRun or CONFIG.StrideLength
	local stepHeight = isRunning and CONFIG.StepHeightRun or CONFIG.StepHeight
	local bodyBob = isRunning and CONFIG.BodyBobAmountRun or CONFIG.BodyBobAmount
	local armSwing = isRunning and CONFIG.ArmSwingAmountRun or CONFIG.ArmSwingAmount
	
	-- Update walk phase based on speed
	if not isIdle then
		local cycleSpeed = speed / strideLength
		self._walkPhase = (self._walkPhase + cycleSpeed * dt) % 1
	end
	
	-- Phase for each leg (offset by 0.5 for alternating)
	local leftPhase = self._walkPhase
	local rightPhase = (self._walkPhase + 0.5) % 1
	
	-- === FOOT PLACEMENT ===
	
	-- Hip positions (where legs start)
	local hipOffset = 0.5  -- Distance from center to hip
	local leftHipPos = hrpPos + hrpCF.RightVector * -hipOffset
	local rightHipPos = hrpPos + hrpCF.RightVector * hipOffset
	
	-- Calculate stride positions
	local strideOffset = strideLength / 2
	
	-- Left foot target
	local leftFootProgress = leftPhase
	local leftGrounded = leftFootProgress < CONFIG.FootPlantDuration or leftFootProgress > (1 - CONFIG.FootPlantDuration)
	
	if isIdle then
		-- Idle: feet at rest position
		local leftRestPos = leftHipPos + Vector3.new(0, -2.5, 0) + hrpCF.RightVector * -0.2
		local groundPos, groundNormal, hit = raycastGround(leftRestPos + Vector3.new(0, 2, 0), self._character)
		self._leftFootTarget = CFrame.new(groundPos + Vector3.new(0, CONFIG.FootGroundOffset, 0))
	else
		if leftGrounded then
			-- Foot planted - keep at last planted position
			if self._leftFootPlanted == false then
				-- Just planted - record position
				local plantPos = leftHipPos + moveDir * -strideOffset + Vector3.new(0, -2, 0)
				local groundPos, _, _ = raycastGround(plantPos + Vector3.new(0, 2, 0), self._character)
				self._lastLeftFootPos = groundPos + Vector3.new(0, CONFIG.FootGroundOffset, 0)
				self._leftFootPlanted = true
			end
			self._leftFootTarget = CFrame.new(self._lastLeftFootPos) * CFrame.Angles(0, math.atan2(moveDir.X, moveDir.Z), 0)
		else
			-- Foot lifting/swinging
			self._leftFootPlanted = false
			local swingProgress = (leftFootProgress - CONFIG.FootPlantDuration) / (1 - 2 * CONFIG.FootPlantDuration)
			swingProgress = math.clamp(swingProgress, 0, 1)
			
			-- Target position ahead
			local targetPos = leftHipPos + moveDir * strideOffset + Vector3.new(0, -2, 0)
			local groundPos, _, _ = raycastGround(targetPos + Vector3.new(0, 2, 0), self._character)
			targetPos = groundPos + Vector3.new(0, CONFIG.FootGroundOffset, 0)
			
			-- Arc from planted to target
			local arcPos = calculateFootArc(self._lastLeftFootPos, targetPos, swingProgress, stepHeight)
			self._leftFootTarget = CFrame.new(arcPos) * CFrame.Angles(
				math.sin(swingProgress * math.pi) * 0.3, -- Toe lift during swing
				math.atan2(moveDir.X, moveDir.Z),
				0
			)
		end
	end
	
	-- Right foot (same logic, offset phase)
	local rightFootProgress = rightPhase
	local rightGrounded = rightFootProgress < CONFIG.FootPlantDuration or rightFootProgress > (1 - CONFIG.FootPlantDuration)
	
	if isIdle then
		local rightRestPos = rightHipPos + Vector3.new(0, -2.5, 0) + hrpCF.RightVector * 0.2
		local groundPos, _, _ = raycastGround(rightRestPos + Vector3.new(0, 2, 0), self._character)
		self._rightFootTarget = CFrame.new(groundPos + Vector3.new(0, CONFIG.FootGroundOffset, 0))
	else
		if rightGrounded then
			if self._rightFootPlanted == false then
				local plantPos = rightHipPos + moveDir * -strideOffset + Vector3.new(0, -2, 0)
				local groundPos, _, _ = raycastGround(plantPos + Vector3.new(0, 2, 0), self._character)
				self._lastRightFootPos = groundPos + Vector3.new(0, CONFIG.FootGroundOffset, 0)
				self._rightFootPlanted = true
			end
			self._rightFootTarget = CFrame.new(self._lastRightFootPos) * CFrame.Angles(0, math.atan2(moveDir.X, moveDir.Z), 0)
		else
			self._rightFootPlanted = false
			local swingProgress = (rightFootProgress - CONFIG.FootPlantDuration) / (1 - 2 * CONFIG.FootPlantDuration)
			swingProgress = math.clamp(swingProgress, 0, 1)
			
			local targetPos = rightHipPos + moveDir * strideOffset + Vector3.new(0, -2, 0)
			local groundPos, _, _ = raycastGround(targetPos + Vector3.new(0, 2, 0), self._character)
			targetPos = groundPos + Vector3.new(0, CONFIG.FootGroundOffset, 0)
			
			local arcPos = calculateFootArc(self._lastRightFootPos, targetPos, swingProgress, stepHeight)
			self._rightFootTarget = CFrame.new(arcPos) * CFrame.Angles(
				math.sin(swingProgress * math.pi) * 0.3,
				math.atan2(moveDir.X, moveDir.Z),
				0
			)
		end
	end
	
	-- Apply foot targets
	if self._ikTargets.LeftFoot then
		self._ikTargets.LeftFoot.CFrame = self._leftFootTarget
	end
	if self._ikTargets.RightFoot then
		self._ikTargets.RightFoot.CFrame = self._rightFootTarget
	end
	
	-- === ARM SWING ===
	
	local shoulderHeight = 1.3
	local shoulderWidth = 0.8
	local armLength = 1.8
	
	-- Left arm swings opposite to right leg
	local leftArmSwing = isIdle and 0 or math.sin(rightPhase * math.pi * 2) * armSwing
	
	-- Left arm
	local leftShoulderPos = hrpPos + hrpCF.RightVector * -shoulderWidth + Vector3.new(0, shoulderHeight, 0)
	local leftArmDir = hrpCF.LookVector * (CONFIG.ArmForwardOffset + math.sin(leftArmSwing)) + Vector3.new(0, -1, 0)
	local leftHandPos = leftShoulderPos + leftArmDir.Unit * armLength
	
	if self._ikTargets.LeftHand then
		self._ikTargets.LeftHand.CFrame = CFrame.new(leftHandPos) * CFrame.Angles(leftArmSwing, 0, 0)
	end
	
	-- Right arm - either extended toward camera (updated in RenderStepped) or swinging
	if CONFIG.RightArmExtended then
		-- Right arm is updated in RenderStepped via UpdateRightArmToCamera()
		-- This prevents jitter from camera/physics timing mismatch
	else
		-- Normal arm swing (opposite to left leg)
		local rightArmSwing = isIdle and 0 or math.sin(leftPhase * math.pi * 2) * armSwing
		local rightShoulderPos = hrpPos + hrpCF.RightVector * shoulderWidth + Vector3.new(0, shoulderHeight, 0)
		local rightArmDir = hrpCF.LookVector * (CONFIG.ArmForwardOffset + math.sin(rightArmSwing)) + Vector3.new(0, -1, 0)
		local rightHandPos = rightShoulderPos + rightArmDir.Unit * armLength
		
		if self._ikTargets.RightHand then
			self._ikTargets.RightHand.CFrame = CFrame.new(rightHandPos) * CFrame.Angles(rightArmSwing, 0, 0)
		end
	end
	
	-- === BODY MOTION ===
	
	-- Body bob (up/down with each step)
	local bobPhase = self._walkPhase * 2 -- Bob twice per cycle
	local currentBob = isIdle and 0 or math.abs(math.sin(bobPhase * math.pi)) * bodyBob
	
	-- Apply to Waist motor if we have it
	if self._motors.Waist then
		local tiltForward = isIdle and 0 or CONFIG.BodyTiltForward * (speed / CONFIG.WalkThreshold)
		local sway = isIdle and 0 or math.sin(self._walkPhase * math.pi * 2) * CONFIG.BodySwayAmount
		
		self._motors.Waist.Transform = CFrame.new(0, currentBob, 0) 
			* CFrame.Angles(tiltForward, 0, sway)
	end
	
	-- Root motor for overall body position
	if self._motors.Root then
		self._motors.Root.Transform = CFrame.new(0, currentBob * 0.5, 0)
	end
end

function ProceduralLocomotionController:ResetMotorTransforms()
	-- Reset motor transforms after animator (to override any residual animation)
	local overrideMotors = {
		"LeftHip", "LeftKnee", "LeftAnkle",
		"RightHip", "RightKnee", "RightAnkle",
		"LeftShoulder", "LeftElbow", "LeftWrist",
		"RightShoulder", "RightElbow", "RightWrist",
	}
	
	for _, motorName in ipairs(overrideMotors) do
		local motor = self._motors[motorName]
		if motor and motor.Parent then
			motor.Transform = CFrame.identity
		end
	end
end

-- Update right arm to follow camera (called in RenderStepped for smooth tracking)
function ProceduralLocomotionController:UpdateRightArmToCamera()
	if not self._hrp or not self._hrp.Parent then return end
	if not CONFIG.RightArmExtended then return end
	if not self._ikTargets.RightHand then return end
	
	local hrpCF = self._hrp.CFrame
	local hrpPos = hrpCF.Position
	
	local shoulderHeight = 1.3
	local shoulderWidth = 0.8
	
	-- Get camera direction
	local camera = Workspace.CurrentCamera
	local cameraLook = camera and camera.CFrame.LookVector or hrpCF.LookVector
	
	-- Shoulder position
	local rightShoulderPos = hrpPos + hrpCF.RightVector * shoulderWidth + Vector3.new(0, shoulderHeight, 0)
	
	-- Target hand position in camera direction
	local targetHandPos = rightShoulderPos + cameraLook * CONFIG.RightArmForwardDistance
	
	-- Smooth the hand position to reduce jitter
	if not self._lastRightHandPos then
		self._lastRightHandPos = targetHandPos
	end
	
	-- Lerp towards target for smooth movement
	local smoothFactor = 0.5
	local smoothedHandPos = self._lastRightHandPos:Lerp(targetHandPos, smoothFactor)
	self._lastRightHandPos = smoothedHandPos
	
	-- Calculate look direction from smoothed position
	local lookDir = (targetHandPos - rightShoulderPos).Unit
	
	-- Apply to IK target
	self._ikTargets.RightHand.CFrame = CFrame.lookAt(smoothedHandPos, smoothedHandPos + lookDir)
		* CFrame.Angles(0, math.rad(-90), 0)
end

-- === SETUP & CLEANUP ===

-- Ensure all character body parts are visible
function ProceduralLocomotionController:EnsureCharacterVisible(character)
	-- List of body part names that should be visible
	local bodyParts = {
		"Head", "UpperTorso", "LowerTorso", "HumanoidRootPart",
		"LeftUpperArm", "LeftLowerArm", "LeftHand",
		"RightUpperArm", "RightLowerArm", "RightHand",
		"LeftUpperLeg", "LeftLowerLeg", "LeftFoot",
		"RightUpperLeg", "RightLowerLeg", "RightFoot",
	}
	
	for _, partName in ipairs(bodyParts) do
		local part = character:FindFirstChild(partName)
		if part and part:IsA("BasePart") then
			part.Transparency = 0
		end
	end
	
	-- Also ensure any MeshParts/Parts in the character are visible
	for _, descendant in ipairs(character:GetDescendants()) do
		if descendant:IsA("BasePart") and descendant.Name ~= "HumanoidRootPart" then
			-- Don't touch accessories or tool parts, just body parts
			if descendant.Parent == character or 
			   (descendant.Parent and descendant.Parent.Parent == character) then
				if descendant.Transparency > 0 then
					descendant.Transparency = 0
				end
			end
		end
	end
	
end

function ProceduralLocomotionController:SetupCharacter(character)
	self._character = character
	self._humanoid = character:WaitForChild("Humanoid", 10)
	self._hrp = character:WaitForChild("HumanoidRootPart", 10)
	
	if not self._humanoid or not self._hrp then
		warn("[ProceduralLocomotion] Failed to find Humanoid or HRP")
		return
	end
	
	-- Ensure character parts are visible
	self:EnsureCharacterVisible(character)
	
	-- Initialize foot positions
	local hrpPos = self._hrp.Position
	self._lastLeftFootPos = hrpPos + Vector3.new(-0.5, -2.5, 0)
	self._lastRightFootPos = hrpPos + Vector3.new(0.5, -2.5, 0)
	
	-- Disable default animations
	self:DisableDefaultAnimations(character)
	
	-- Setup IK
	if not self:SetupAllIK(character) then
		warn("[ProceduralLocomotion] Failed to setup IK")
		return
	end
	
	-- Create arm cannon if enabled
	if CONFIG.UseArmCannon then
		self:CreateArmCannon(character)
		-- Setup shooting system for the cannon
		self:SetupShooting()
	end
	
	-- Setup movement smoothing and custom jump
	self:SetupMovementSmoothing(character)
	
	-- Main update loop (Heartbeat for physics)
	local heartbeatConn = RunService.Heartbeat:Connect(function(dt)
		self:UpdateMovementSmoothing(dt)
		self:UpdateCustomJump(dt)
		self:UpdateLocomotion(dt)
	end)
	table.insert(self._connections, heartbeatConn)
	
	-- Motor reset and cannon update on RenderStepped
	local renderConn = RunService.RenderStepped:Connect(function(dt)
		self:ResetMotorTransforms()
		self:UpdateRightArmToCamera()
		self:UpdateRecoil(dt)
		self:UpdateArmCannon()
	end)
	table.insert(self._connections, renderConn)
	
	-- Cleanup on death
	self._humanoid.Died:Connect(function()
		self:Cleanup()
	end)
	
end

function ProceduralLocomotionController:Cleanup()
	-- Disconnect all connections
	for _, conn in ipairs(self._connections) do
		if conn and conn.Connected then
			conn:Disconnect()
		end
	end
	self._connections = {}
	
	-- Destroy IK controls
	for _, ik in pairs(self._ikControls) do
		if ik and ik.Parent then
			ik:Destroy()
		end
	end
	self._ikControls = {}
	
	-- Destroy targets
	for _, target in pairs(self._ikTargets) do
		if target and target.Parent then
			target:Destroy()
		end
	end
	self._ikTargets = {}
	
	-- Clear motors
	self._motors = {}
	
	-- Destroy arm cannon
	self:DestroyArmCannon()
	
	-- Clean up shooting
	self:CleanupShooting()
	
	-- Clean up physics forces
	if self._moveForce then
		self._moveForce:Destroy()
		self._moveForce = nil
	end
	if self._jumpForce then
		self._jumpForce:Destroy()
		self._jumpForce = nil
	end
	if self._attachment then
		self._attachment:Destroy()
		self._attachment = nil
	end
	self._isJumping = false
	self._jumpPhase = "none"
	
	-- Note: Default scripts (Animate, Health, Sound) were destroyed and cannot be restored
	-- Player will need to respawn to get them back
	
	self._character = nil
	self._humanoid = nil
	self._hrp = nil
	
end

-- === PUBLIC API ===

-- Toggle the system on/off
function ProceduralLocomotionController:SetEnabled(enabled)
	CONFIG.Enabled = enabled
	if not enabled then
		self:Cleanup()
	elseif Players.LocalPlayer.Character then
		self:SetupCharacter(Players.LocalPlayer.Character)
	end
end

-- Adjust stride length
function ProceduralLocomotionController:SetStrideLength(walk, run)
	CONFIG.StrideLength = walk
	CONFIG.StrideLengthRun = run or walk * 1.4
end

-- Adjust step height
function ProceduralLocomotionController:SetStepHeight(walk, run)
	CONFIG.StepHeight = walk
	CONFIG.StepHeightRun = run or walk * 1.5
end

-- Adjust body bob
function ProceduralLocomotionController:SetBodyBob(amount)
	CONFIG.BodyBobAmount = amount
	CONFIG.BodyBobAmountRun = amount * 1.5
end

-- Adjust arm swing
function ProceduralLocomotionController:SetArmSwing(amount)
	CONFIG.ArmSwingAmount = amount
	CONFIG.ArmSwingAmountRun = amount * 1.5
end

-- Show/hide debug targets
function ProceduralLocomotionController:SetDebugTargets(show)
	CONFIG.ShowTargets = show
	for _, target in pairs(self._ikTargets) do
		if target then
			target.Transparency = show and 0 or 1
		end
	end
end

-- Toggle right arm extended forward
function ProceduralLocomotionController:SetRightArmExtended(extended)
	CONFIG.RightArmExtended = extended
end

-- Adjust right arm forward distance
function ProceduralLocomotionController:SetRightArmForwardDistance(distance)
	CONFIG.RightArmForwardDistance = distance
end

-- Adjust right arm height
function ProceduralLocomotionController:SetRightArmHeight(height)
	CONFIG.RightArmHeightOffset = height
end

-- Toggle arm cannon
function ProceduralLocomotionController:SetArmCannonEnabled(enabled)
	CONFIG.UseArmCannon = enabled
	if enabled and self._character and not self._armCannon then
		self:CreateArmCannon(self._character)
	elseif not enabled and self._armCannon then
		self:DestroyArmCannon()
		-- Show both arms again
		if self._character then
			local armParts = {
				"RightUpperArm", "RightLowerArm", "RightHand",
				"LeftUpperArm", "LeftLowerArm", "LeftHand"
			}
			for _, partName in ipairs(armParts) do
				local part = self._character:FindFirstChild(partName)
				if part then
					part.Transparency = 0
				end
			end
		end
	end
end

-- Set movement smoothing parameters
function ProceduralLocomotionController:SetMovementSmoothing(enabled, accelTime, decelTime)
	CONFIG.MovementSmoothing = enabled
	if accelTime then CONFIG.AccelerationTime = accelTime end
	if decelTime then CONFIG.DecelerationTime = decelTime end
end

-- Set movement speed
function ProceduralLocomotionController:SetMoveSpeed(walkSpeed, runSpeed)
	CONFIG.WalkSpeed = walkSpeed or CONFIG.WalkSpeed
	CONFIG.RunSpeed = runSpeed or CONFIG.RunSpeed
	if self._humanoid then
		self._humanoid.WalkSpeed = CONFIG.WalkSpeed
	end
end

-- Set custom jump parameters
function ProceduralLocomotionController:SetJumpSettings(height, duration, hangTime)
	CONFIG.JumpHeight = height or CONFIG.JumpHeight
	CONFIG.JumpDuration = duration or CONFIG.JumpDuration
	CONFIG.JumpHangTime = hangTime or CONFIG.JumpHangTime
end

-- Toggle custom jump
function ProceduralLocomotionController:SetCustomJumpEnabled(enabled)
	CONFIG.CustomJump = enabled
	if self._humanoid then
		if enabled then
			self._humanoid.JumpPower = 0
			self._humanoid.JumpHeight = 0
		else
			self._humanoid.JumpPower = self._originalJumpPower or 50
			self._humanoid.JumpHeight = self._originalJumpHeight or 7.2
		end
	end
end

-- Set cannon colors
function ProceduralLocomotionController:SetCannonColors(main, accent, glow)
	CONFIG.CannonColor = main or CONFIG.CannonColor
	CONFIG.CannonAccentColor = accent or CONFIG.CannonAccentColor
	CONFIG.CannonGlowColor = glow or CONFIG.CannonGlowColor
	-- Update existing parts
	for _, part in ipairs(self._cannonParts) do
		if part.Name == "ShoulderMount" or part.Name == "ElbowRing" or part.Name == "Barrel" then
			part.Color = CONFIG.CannonAccentColor
		elseif part.Name == "BarrelTip" or part.Name == "EnergyCore" then
			part.Color = CONFIG.CannonGlowColor
		elseif part.Name:find("Vent") then
			part.Color = CONFIG.CannonAccentColor
		else
			part.Color = CONFIG.CannonColor
		end
	end
end

-- === KNIT LIFECYCLE ===

function ProceduralLocomotionController:KnitInit()
end

function ProceduralLocomotionController:KnitStart()
	if not CONFIG.Enabled then
		warn("[ProceduralLocomotion] System is disabled")
		return
	end
	
	local player = Players.LocalPlayer
	
	-- Setup current character
	if player.Character then
		task.spawn(function()
			task.wait(1) -- Wait for character to fully load
			self:SetupCharacter(player.Character)
		end)
	end
	
	-- Handle respawns
	player.CharacterAdded:Connect(function(character)
		self:Cleanup()
		task.wait(1)
		self:SetupCharacter(character)
	end)
	
end

return ProceduralLocomotionController

