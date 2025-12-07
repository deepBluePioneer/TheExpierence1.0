--[[
	LocomotionConfig
	Shared configuration for procedural locomotion system
]]

local LocomotionConfig = {
	Enabled = true,
	
	-- Movement thresholds
	IdleThreshold = 0.5,         -- Below this speed = idle
	WalkThreshold = 12,          -- Below this = walk, above = run
	WalkSpeed = 24,              -- Base movement speed
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
	JumpHeight = 14,             -- Jump height in studs
	JumpDuration = 0.6,          -- Time to reach peak (seconds)
	JumpHangTime = 0.2,          -- Extra time at peak (floaty feel)
	GravityMultiplier = 1.5,     -- Falling speed multiplier
	
	-- Debug
	ShowTargets = false,
	ShowRaycasts = false,
}

return LocomotionConfig

