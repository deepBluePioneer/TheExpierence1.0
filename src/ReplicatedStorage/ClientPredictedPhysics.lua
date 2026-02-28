local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Packages = ReplicatedStorage.Packages
local MachinePhysicsConfig = require(ReplicatedStorage.Source.MachinePhysicsConfig)

local Gizmo
local IS_STUDIO = RunService:IsStudio()
if IS_STUDIO then
	local ok, mod = pcall(require, Packages.imgizmo)
	if ok then Gizmo = mod end
end

local HIT_COLOR = Color3.fromRGB(255, 50, 50)
local NORMAL_COLOR = Color3.fromRGB(50, 150, 255)
local SENSOR_COLOR = Color3.fromRGB(255, 255, 0)

local ClientPredictedPhysics = {}
ClientPredictedPhysics.__index = ClientPredictedPhysics

function ClientPredictedPhysics.new()
	return setmetatable({
		_model = nil,
		_rootPart = nil,
		_driveForce = nil,
		_steerAlign = nil,
		_groundSensor = nil,
		_statsProvider = nil,

		_currentSpeed = 0,
		_currentYaw = 0,
		_currentPitch = 0,
		_smoothNormal = Vector3.new(0, 1, 0),
		_grounded = false,
		_wasGrounded = false,
		_hoverDistance = 0,
		_airTime = 0,
		_launchSpeed = 0,

		_inputState = {
			throttle = 0,
			steer = 0,
			pitch = 0,
			boost = false,
			drift = false,
			brake = false,
		},
	}, ClientPredictedPhysics)
end

function ClientPredictedPhysics:init(machineModel, statsProvider)
	self._model = machineModel
	self._rootPart = machineModel.PrimaryPart
	self._statsProvider = statsProvider

	self._driveForce = self._rootPart:FindFirstChild("DriveForce")
	self._steerAlign = self._rootPart:FindFirstChild("SteerAlign")
	self._groundSensor = self._rootPart:FindFirstChild("GroundSensor")

	local _, yaw, _ = self._rootPart.CFrame:ToEulerAnglesYXZ()
	self._currentYaw = yaw
end

function ClientPredictedPhysics:setInput(inputState)
	self._inputState = inputState
end

function ClientPredictedPhysics:update(dt)
	if not self._rootPart or not self._rootPart.Parent then return end

	local stats = self._statsProvider()
	local input = self._inputState
	local config = MachinePhysicsConfig

	local grounded, hitDistance, hitNormal, hitPosition = self:_readGroundSensor()
	self._grounded = grounded
	self._hoverDistance = hitDistance or math.huge

	if IS_STUDIO and config.debugRaycasts and Gizmo then
		self:_debugDraw(grounded, hitPosition, hitNormal, hitDistance)
	end

	-- Track air time
	if grounded then
		if not self._wasGrounded then
			self._currentPitch = 0
		end
		self._airTime = 0
		self._launchSpeed = self._currentSpeed
	else
		self._airTime = self._airTime + dt
	end
	self._wasGrounded = grounded

	-- Smooth surface normal for ramp alignment
	if grounded and hitNormal then
		local alignSpeed = config.surfaceAlignSpeed * dt
		self._smoothNormal = self._smoothNormal:Lerp(hitNormal, math.min(alignSpeed, 1))
	elseif not grounded then
		self._smoothNormal = self._smoothNormal:Lerp(Vector3.new(0, 1, 0), math.min(2 * dt, 1))
	end

	-- Speed
	local topSpeed = stats.topSpeed
	local acceleration = stats.acceleration
	local handling = stats.handling
	local boostPower = stats.boostPower
	local targetSpeed = self._currentSpeed

	if grounded then
		if input.brake then
			targetSpeed = targetSpeed - config.brakeDeceleration * dt * 10
			targetSpeed = math.max(0, targetSpeed)
		elseif input.throttle > 0 then
			local maxForward = topSpeed
			if input.boost and self._currentSpeed > 0 then
				maxForward = topSpeed + boostPower
			end
			targetSpeed = targetSpeed + acceleration * input.throttle * dt * 10
			targetSpeed = math.min(targetSpeed, maxForward)
		else
			targetSpeed = targetSpeed - config.coastDeceleration * dt * 10
			targetSpeed = math.max(0, targetSpeed)
		end
	else
		local airDecel = config.coastDeceleration * 0.3
		targetSpeed = targetSpeed - airDecel * dt
		targetSpeed = math.max(0, targetSpeed)
	end

	-- Steering (yaw)
	local steerAmount = input.steer
	local turnRate = config.turnSpeed * (handling / 6)

	if input.drift then
		turnRate = turnRate * config.driftTurnMultiplier
	end

	if not grounded then
		turnRate = turnRate * config.airHandlingMultiplier
	end

	self._currentYaw = self._currentYaw - steerAmount * math.rad(turnRate) * dt
	self._currentSpeed = targetSpeed

	-- Air pitch control (W = pitch nose up, S = pitch nose down)
	if not grounded then
		local pitchInput = input.pitch or 0
		if math.abs(pitchInput) > 0.05 then
			local pitchRate = config.airPitchSpeed * (handling / 6)
			self._currentPitch = self._currentPitch + pitchInput * math.rad(pitchRate) * dt
			local maxPitch = math.rad(config.airMaxPitch)
			self._currentPitch = math.clamp(self._currentPitch, -maxPitch, maxPitch)
		end
	else
		local returnSpeed = config.airPitchReturnSpeed * dt
		if math.abs(self._currentPitch) > 0.01 then
			self._currentPitch = self._currentPitch - math.sign(self._currentPitch) * math.min(math.rad(returnSpeed), math.abs(self._currentPitch))
		else
			self._currentPitch = 0
		end
	end

	-- Build orientation
	local yawCF = CFrame.Angles(0, self._currentYaw, 0)

	if grounded then
		local lookDir = yawCF.LookVector
		local upVector = self._smoothNormal
		local targetCFrame = CFrame.lookAt(Vector3.zero, lookDir, upVector)

		if self._steerAlign then
			self._steerAlign.CFrame = targetCFrame
		end

		if self._driveForce then
			self._driveForce.LineDirection = lookDir
			self._driveForce.LineVelocity = self._currentSpeed
		end
	else
		local pitchCF = CFrame.Angles(self._currentPitch, 0, 0)
		local orientCF = yawCF * pitchCF
		local flyDir = orientCF.LookVector

		if self._steerAlign then
			self._steerAlign.CFrame = orientCF
		end

		if self._driveForce then
			self._driveForce.LineDirection = flyDir
			self._driveForce.LineVelocity = self._currentSpeed
		end
	end

	-- Hover (grounded) or glide gravity (airborne)
	if grounded and hitPosition then
		local targetY = hitPosition.Y + config.hoverHeight
		local pos = self._rootPart.Position

		local rotation = self._rootPart.CFrame - pos
		self._rootPart.CFrame = CFrame.new(pos.X, targetY, pos.Z) * rotation

		local vel = self._rootPart.AssemblyLinearVelocity
		self._rootPart.AssemblyLinearVelocity = Vector3.new(vel.X, 0, vel.Z)
	else
		-- Glide: ramp gravity from low to normal over time
		local t = math.clamp(self._airTime / config.airGlideGravityRampTime, 0, 1)
		local gravityScale = config.airGlideGravityStart + (config.airGlideGravityEnd - config.airGlideGravityStart) * t

		local fullGravity = config.gravityAcceleration
		local targetGravity = fullGravity * gravityScale

		-- Pitch affects vertical velocity: nose up = lift, nose down = dive
		local pitchLift = 0
		if math.abs(self._currentPitch) > 0.01 then
			local speedFactor = math.clamp(self._currentSpeed / stats.topSpeed, 0, 1)
			pitchLift = -math.sin(self._currentPitch) * config.airLiftForce * speedFactor
		end

		local vel = self._rootPart.AssemblyLinearVelocity
		local desiredVertAccel = -targetGravity + pitchLift
		local currentVertAccel = -fullGravity

		local correction = (desiredVertAccel - currentVertAccel) * self._rootPart.AssemblyMass
		self._rootPart:ApplyImpulse(Vector3.new(0, correction * dt, 0))
	end

	-- Lateral damping
	if grounded then
		local velocity = self._rootPart.AssemblyLinearVelocity
		local right = self._rootPart.CFrame.RightVector
		local lateralSpeed = velocity:Dot(right)

		local dampMult = 10
		if input.drift then
			dampMult = dampMult * config.driftFrictionMultiplier
		end

		local dampForce = -right * lateralSpeed * dampMult * self._rootPart.AssemblyMass * dt
		self._rootPart:ApplyImpulse(dampForce)
	else
		local velocity = self._rootPart.AssemblyLinearVelocity
		local right = self._rootPart.CFrame.RightVector
		local lateralSpeed = velocity:Dot(right)
		local dampForce = -right * lateralSpeed * 3 * self._rootPart.AssemblyMass * dt
		self._rootPart:ApplyImpulse(dampForce)
	end

	-- Void check
	if self._rootPart.Position.Y < config.voidThreshold then
		self._currentSpeed = 0
		if self._driveForce then
			self._driveForce.LineVelocity = 0
		end
	end
end

----------------------------------------------------------------
-- Ground sensor reading
----------------------------------------------------------------

function ClientPredictedPhysics:_readGroundSensor()
	local sensor = self._groundSensor
	if not sensor then
		return false, nil, nil, nil
	end

	local sensedPart = sensor.SensedPart
	if not sensedPart then
		return false, nil, nil, nil
	end

	local hitFrame = sensor.HitFrame
	local hitNormal = sensor.HitNormal

	local hitPosition = hitFrame.Position
	local hitDistance = (self._rootPart.Position - hitPosition).Magnitude

	local config = MachinePhysicsConfig
	local isGrounded = hitDistance < config.hoverHeight * config.groundedThreshold

	return isGrounded, hitDistance, hitNormal, hitPosition
end

----------------------------------------------------------------
-- Debug visualization (imgizmo, Studio only)
----------------------------------------------------------------

function ClientPredictedPhysics:_debugDraw(grounded, hitPosition, hitNormal, hitDistance)
	if not Gizmo then return end

	local rootPos = self._rootPart.Position
	Gizmo.PushProperty("AlwaysOnTop", true)

	local rayEnd = rootPos + Vector3.new(0, -(MachinePhysicsConfig.hoverHeight * MachinePhysicsConfig.groundRayLength), 0)

	if grounded and hitPosition then
		Gizmo.PushProperty("Color3", SENSOR_COLOR)
		Gizmo.Ray:Draw(rootPos, hitPosition)

		Gizmo.PushProperty("Color3", HIT_COLOR)
		Gizmo.VolumeSphere:Draw(CFrame.new(hitPosition), 0.3)

		if hitNormal then
			Gizmo.PushProperty("Color3", NORMAL_COLOR)
			Gizmo.Arrow:Draw(hitPosition, hitPosition + hitNormal * 3, 0.15, 0.4, 8)
		end

		if hitDistance then
			Gizmo.PushProperty("Color3", Color3.new(1, 1, 1))
			Gizmo.Text:Draw(hitPosition + Vector3.new(0, 0.5, 0), string.format("%.1f", hitDistance))
		end
	else
		Gizmo.PushProperty("Color3", Color3.fromRGB(100, 100, 100))
		Gizmo.Ray:Draw(rootPos, rayEnd)
	end
end

----------------------------------------------------------------
-- State
----------------------------------------------------------------

function ClientPredictedPhysics:getState()
	return {
		cframe = self._rootPart and self._rootPart.CFrame or CFrame.new(),
		velocity = self._rootPart and self._rootPart.AssemblyLinearVelocity or Vector3.zero,
		grounded = self._grounded,
		currentSpeed = self._currentSpeed,
		hoverDistance = self._hoverDistance,
		pitch = self._currentPitch,
		airTime = self._airTime,
	}
end

function ClientPredictedPhysics:destroy()
	self._model = nil
	self._rootPart = nil
	self._driveForce = nil
	self._steerAlign = nil
	self._groundSensor = nil
	self._statsProvider = nil
end

return ClientPredictedPhysics
