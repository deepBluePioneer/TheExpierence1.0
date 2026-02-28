local MachinePhysicsConfig = {
	-- Forward movement
	maxSpeed = 150,
	thrust = 8000,
	dragFactor = 8,
	coastDeceleration = 3,

	-- Steering
	turnSpeed = 80,
	turnSpeedPenalty = 0.08,

	-- Hover / ground detection
	hoverHeight = 3,
	hoverStiffness = 10,
	surfaceAlignSpeed = 10,
	groundRayLength = 2.5, -- multiplier of hoverHeight
	groundedThreshold = 1.3, -- multiplier of hoverHeight

	-- Boost
	maxBoostCharge = 3,
	boostThrust = 30000,
	boostDecay = 6,
	boostCooldown = 0.5,
	boostFOVIncrease = 10,

	-- Drift
	driftFrictionMultiplier = 0.4,
	driftTurnMultiplier = 1.3,
	driftBoostChargeMultiplier = 2.5,
	miniBoostOnDriftExit = 0.5,

	-- Braking
	brakeDeceleration = 12,

	-- Air control
	airHandlingMultiplier = 0.7,
	airPitchSpeed = 60,
	airLiftForce = 80,
	airMaxPitch = 35,
	airPitchReturnSpeed = 40,

	-- Air glide gravity
	airGlideGravityStart = 0.15,
	airGlideGravityEnd = 0.8,
	airGlideGravityRampTime = 2.0,

	-- Gravity
	gravityAcceleration = 196.2,

	-- Respawn / death
	respawnDelay = 3,
	respawnInvulnDuration = 2,

	-- Collision
	collisionStunDuration = 0.4,
	collisionStunThreshold = 30,
	collisionDamageMultiplier = 0.5,

	-- Boundaries
	voidThreshold = -200,

	-- Stuck detection
	stuckDetectionTime = 2,
	stuckVelocityThreshold = 1,

	-- Network validation (client-predicted mode)
	validationInterval = 2,
	maxSpeedTolerance = 1.5,

	-- Align orientation
	alignResponsiveness = 15,

	-- Debug (Studio only)
	debugRaycasts = true,
}

return MachinePhysicsConfig
