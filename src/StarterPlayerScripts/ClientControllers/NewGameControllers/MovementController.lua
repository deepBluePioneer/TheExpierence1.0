--[[
	MovementController
	Handles physics-based movement smoothing and custom jump mechanics
]]

local Workspace = game:GetService("Workspace")

local Packages = game:GetService("ReplicatedStorage"):WaitForChild("Packages")
local Knit = require(Packages.Knit)

local CONFIG = require(script.Parent.LocomotionConfig) -- Located in same folder (NewGameControllers)

local MovementController = Knit.CreateController {
	Name = "MovementController",
	
	-- State
	_character = nil,
	_humanoid = nil,
	_hrp = nil,
	
	-- Physics forces
	_moveForce = nil,
	_jumpForce = nil,
	_attachment = nil,
	
	-- Movement state
	_smoothedSpeed = 0,
	_targetSpeed = 0,
	_smoothedDirection = Vector3.zero,
	
	-- Jump state
	_isJumping = false,
	_jumpStartTime = 0,
	_jumpPhase = "none",
	_hangStartTime = 0,
	_wasGrounded = true,
	
	-- Original values
	_originalWalkSpeed = 16,
	_originalJumpPower = 50,
	_originalJumpHeight = 7.2,
	
	-- Connections
	_connections = {},
}

-- === EASING FUNCTIONS ===

local Easing = {
	outQuad = function(t)
		return 1 - (1 - t) * (1 - t)
	end,
	
	inQuad = function(t)
		return t * t
	end,
	
	inOutQuad = function(t)
		if t < 0.5 then
			return 2 * t * t
		else
			return 1 - math.pow(-2 * t + 2, 2) / 2
		end
	end,
	
	outCubic = function(t)
		return 1 - math.pow(1 - t, 3)
	end,
}

-- === SETUP ===

function MovementController:SetupMovementSmoothing(character)
	self._character = character
	self._humanoid = character:FindFirstChildOfClass("Humanoid")
	self._hrp = character:FindFirstChild("HumanoidRootPart")
	
	if not self._humanoid or not self._hrp then return end
	
	-- Store original values
	self._originalWalkSpeed = self._humanoid.WalkSpeed
	self._originalJumpPower = self._humanoid.JumpPower
	self._originalJumpHeight = self._humanoid.JumpHeight
	
	-- Apply custom walk speed
	self._humanoid.WalkSpeed = CONFIG.WalkSpeed
	
	-- Create attachment for forces
	local attachment = self._hrp:FindFirstChild("MovementAttachment")
	if not attachment then
		attachment = Instance.new("Attachment")
		attachment.Name = "MovementAttachment"
		attachment.Position = Vector3.zero
		attachment.Parent = self._hrp
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
		moveForce.Parent = self._hrp
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
		jumpForce.Parent = self._hrp
		self._jumpForce = jumpForce
		
		-- Disable default jump
		self._humanoid.JumpPower = 0
		self._humanoid.JumpHeight = 0
		
		-- Listen for jump input
		local jumpConn = self._humanoid:GetPropertyChangedSignal("Jump"):Connect(function()
			if self._humanoid.Jump and self:IsGrounded() and not self._isJumping then
				self:StartCustomJump()
			end
			self._humanoid.Jump = false
		end)
		table.insert(self._connections, jumpConn)
	end
end

-- === GROUNDED CHECK ===

function MovementController:IsGrounded()
	if not self._hrp then return true end
	
	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.FilterDescendantsInstances = {self._character}
	
	local origin = self._hrp.Position
	local result = Workspace:Raycast(origin, Vector3.new(0, -3.5, 0), rayParams)
	
	return result ~= nil
end

-- === CUSTOM JUMP ===

function MovementController:StartCustomJump()
	if self._isJumping then return end
	
	self._isJumping = true
	self._jumpStartTime = tick()
	self._jumpPhase = "rising"
	
	-- Calculate initial jump impulse
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

function MovementController:UpdateCustomJump(dt)
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
		local riseBoost = mass * gravity * 0.2 * Easing.outQuad(math.clamp(verticalVel / 20, 0, 1))
		force = Vector3.new(0, riseBoost, 0)
		
	elseif self._jumpPhase == "hanging" then
		local hangProgress = (tick() - self._hangStartTime) / CONFIG.JumpHangTime
		local hangStrength = Easing.inOutQuad(1 - math.abs(hangProgress * 2 - 1))
		local counterGravity = mass * gravity * 0.9 * hangStrength
		force = Vector3.new(0, counterGravity, 0)
		
	elseif self._jumpPhase == "falling" then
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

function MovementController:EndCustomJump()
	self._isJumping = false
	self._jumpPhase = "none"
	
	if self._jumpForce then
		self._jumpForce.Force = Vector3.zero
	end
end

-- === MOVEMENT SMOOTHING ===

function MovementController:UpdateMovementSmoothing(dt)
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
	
	-- PD controller
	local kP = mass * (1 / CONFIG.AccelerationTime) * 10
	local kD = mass * 2
	
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
	
	-- Apply easing curve
	local speedRatio = horizontalVel.Magnitude / math.max(targetSpeed, 0.1)
	local easedMultiplier = moveDir.Magnitude > 0.1 
		and Easing.outQuad(math.clamp(1 - speedRatio, 0, 1))
		or Easing.inQuad(math.clamp(speedRatio, 0, 1))
	
	force = force * (0.5 + easedMultiplier * 0.5)
	
	self._moveForce.Force = force
	
	-- Update smoothed values
	self._smoothedSpeed = horizontalVel.Magnitude
	if moveDir.Magnitude > 0.1 then
		self._smoothedDirection = moveDir
	end
end

-- === CLEANUP ===

function MovementController:Cleanup()
	for _, conn in ipairs(self._connections) do
		if conn and conn.Connected then
			conn:Disconnect()
		end
	end
	self._connections = {}
	
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
	
	self._character = nil
	self._humanoid = nil
	self._hrp = nil
end

-- === PUBLIC API ===

function MovementController:GetSmoothedSpeed()
	return self._smoothedSpeed
end

function MovementController:GetSmoothedDirection()
	return self._smoothedDirection
end

function MovementController:SetMoveSpeed(walkSpeed, runSpeed)
	CONFIG.WalkSpeed = walkSpeed or CONFIG.WalkSpeed
	CONFIG.RunSpeed = runSpeed or CONFIG.RunSpeed
	if self._humanoid then
		self._humanoid.WalkSpeed = CONFIG.WalkSpeed
	end
end

function MovementController:SetJumpSettings(height, duration, hangTime)
	CONFIG.JumpHeight = height or CONFIG.JumpHeight
	CONFIG.JumpDuration = duration or CONFIG.JumpDuration
	CONFIG.JumpHangTime = hangTime or CONFIG.JumpHangTime
end

function MovementController:SetCustomJumpEnabled(enabled)
	CONFIG.CustomJump = enabled
	if self._humanoid then
		if enabled then
			self._humanoid.JumpPower = 0
			self._humanoid.JumpHeight = 0
		else
			self._humanoid.JumpPower = self._originalJumpPower
			self._humanoid.JumpHeight = self._originalJumpHeight
		end
	end
end

function MovementController:SetMovementSmoothing(enabled, accelTime, decelTime)
	CONFIG.MovementSmoothing = enabled
	if accelTime then CONFIG.AccelerationTime = accelTime end
	if decelTime then CONFIG.DecelerationTime = decelTime end
end

-- === KNIT LIFECYCLE ===

function MovementController:KnitInit()
end

function MovementController:KnitStart()
	-- This controller is managed by ProceduralLocomotionController
end

return MovementController

