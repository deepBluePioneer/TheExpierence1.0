--[[
	LocomotionConfig
	Shared configuration for movement system
]]

local LocomotionConfig = {
	Enabled = true,
	
	-- Movement thresholds
	IdleThreshold = 0.5,         -- Below this speed = idle
	WalkThreshold = 12,          -- Below this = walk, above = run
	WalkSpeed = 24,              -- Base movement speed
	RunSpeed = 36,               -- Sprint speed
	
	-- Lantern/Item Settings
	UseArmCannon = true,         -- Enable lantern (kept name for compatibility)
	
	-- Movement Smoothing
	MovementSmoothing = true,    -- Enable smooth acceleration/deceleration
	AccelerationTime = 0.3,      -- Time to reach full speed (seconds)
	DecelerationTime = 0.2,      -- Time to stop (seconds)
	
	-- Jump Settings
	CustomJump = true,           -- Use custom jump curve
	JumpHeight = 14,             -- Jump height in studs
	JumpDuration = 0.6,          -- Time to reach peak (seconds)
	JumpHangTime = 0.2,          -- Extra time at peak (floaty feel)
	GravityMultiplier = 1.5,     -- Falling speed multiplier
}

return LocomotionConfig
