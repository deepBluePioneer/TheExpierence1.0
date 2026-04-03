local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Packages = ReplicatedStorage.Packages
local Knit = require(Packages.Knit)
local Trove = require(Packages.Trove)

local LocalPlayer = Players.LocalPlayer

local MOVE_SPEED = 24
local JUMP_FORCE = 50
local TURN_SPEED = 30
local AIR_CONTROL = 0.15
local LATERAL_DEAD_ZONE = 0.5
local GROUND_SNAP_HEIGHT = 2.5
local GROUND_SNAP_TOLERANCE = 1.0
local JUMP_COOLDOWN = 0.25

local GraviBowCharacterController = Knit.CreateController({
	Name = "GraviBowCharacterController",

	_trove = nil,
	_characterTrove = nil,
	_jumpRequested = false,
	_jumpCooldown = 0,
	_cachedMass = 0,
	_orientation = CFrame.identity,
})

function GraviBowCharacterController:KnitInit()
	self._trove = Trove.new()
end

function GraviBowCharacterController:KnitStart()
	self._gravityController = Knit.GetController("GraviBowGravityController")
	self._groundController = Knit.GetController("GraviBowGroundController")
	self._cameraController = Knit.GetController("GraviBowCameraController")

	self._trove:Add(UserInputService.JumpRequest:Connect(function()
		self._jumpRequested = true
	end), "Disconnect")

	self._trove:Add(LocalPlayer.CharacterAdded:Connect(function(character)
		self:_onCharacterAdded(character)
	end), "Disconnect")

	if LocalPlayer.Character then
		self:_onCharacterAdded(LocalPlayer.Character)
	end

	print("[GraviBowCharacterController] Started")
end

function GraviBowCharacterController:_onCharacterAdded(character)
	if self._characterTrove then
		self._characterTrove:Clean()
	end
	self._characterTrove = self._trove:Extend()

	local hrp = character:WaitForChild("HumanoidRootPart", 10)
	if not hrp then return end

	self._cachedMass = 0
	for _, part in ipairs(character:GetDescendants()) do
		if part:IsA("BasePart") then
			self._cachedMass += part:GetMass()
		end
	end

	self:_hideLocalCharacter(character)
	self:_muteCharacterSounds(character)

	local upDir = -self._gravityController.GravityDirection
	self._orientation = (hrp.CFrame - hrp.CFrame.Position)
	local initForward = self._orientation.LookVector
	initForward = (initForward - upDir * initForward:Dot(upDir))
	if initForward.Magnitude > 0.001 then
		self._orientation = CFrame.lookAt(Vector3.zero, initForward, upDir)
	end

	self._characterTrove:Add(RunService.Heartbeat:Connect(function(dt)
		self:_update(hrp, dt)
	end), "Disconnect")
end

function GraviBowCharacterController:_fromToRotation(from, to)
	local cross = from:Cross(to)
	local dot = from:Dot(to)

	if cross.Magnitude < 1e-6 then
		if dot > 0 then
			return CFrame.identity
		end
		local perp = Vector3.new(1, 0, 0):Cross(from)
		if perp.Magnitude < 1e-6 then
			perp = Vector3.new(0, 1, 0):Cross(from)
		end
		return CFrame.fromAxisAngle(perp.Unit, math.pi)
	end

	local angle = math.acos(math.clamp(dot, -1, 1))
	return CFrame.fromAxisAngle(cross.Unit, angle)
end

function GraviBowCharacterController:_getInputDirection()
	local moveDir = Vector3.zero
	if UserInputService:IsKeyDown(Enum.KeyCode.W) then
		moveDir += Vector3.new(0, 0, -1)
	end
	if UserInputService:IsKeyDown(Enum.KeyCode.S) then
		moveDir += Vector3.new(0, 0, 1)
	end
	if UserInputService:IsKeyDown(Enum.KeyCode.A) then
		moveDir += Vector3.new(-1, 0, 0)
	end
	if UserInputService:IsKeyDown(Enum.KeyCode.D) then
		moveDir += Vector3.new(1, 0, 0)
	end

	if moveDir.Magnitude > 0.01 then
		return moveDir.Unit
	end
	return Vector3.zero
end

function GraviBowCharacterController:_update(hrp, dt)
	local gravityDir = self._gravityController.GravityDirection
	local upDir = -gravityDir
	local isGrounded = self._groundController.IsGrounded

	if self._jumpCooldown > 0 then
		self._jumpCooldown -= dt
		isGrounded = false
	end

	self:_updateRotation(hrp, upDir, dt)
	self:_updateMovement(hrp, gravityDir, upDir, isGrounded, dt)
	self:_updateGroundSnap(hrp, gravityDir, isGrounded)
	self:_updateJump(hrp, gravityDir, isGrounded)

	hrp.AssemblyAngularVelocity = Vector3.zero
end

function GraviBowCharacterController:_updateRotation(hrp, upDir, dt)
	local currentUp = self._orientation.UpVector
	local deltaRot = self:_fromToRotation(currentUp, upDir)
	self._orientation = deltaRot * self._orientation

	local forwardOnSurface = self._cameraController.CameraLookOnSurface
	local rightOnSurface = self._cameraController.CameraRightOnSurface

	local targetDir = forwardOnSurface
	targetDir = targetDir - upDir * targetDir:Dot(upDir)
	if targetDir.Magnitude > 0.001 then
		targetDir = targetDir.Unit
		self._orientation = CFrame.lookAt(Vector3.zero, targetDir, upDir)
	end

	hrp.CFrame = CFrame.new(hrp.Position) * self._orientation
end

function GraviBowCharacterController:_updateMovement(hrp, gravityDir, upDir, isGrounded, _dt)
	local forwardOnSurface = self._cameraController.CameraLookOnSurface
	local rightOnSurface = self._cameraController.CameraRightOnSurface

	local inputDir = self:_getInputDirection()
	local isMoving = inputDir.Magnitude > 0.01

	local currentVel = hrp.AssemblyLinearVelocity
	local radialSpeed = currentVel:Dot(gravityDir)
	local gravityComponent = gravityDir * radialSpeed
	local lateralVel = currentVel - gravityComponent

	if isGrounded then
		gravityComponent = Vector3.zero
	end

	if isMoving then
		local rawMoveDir = rightOnSurface * inputDir.X + forwardOnSurface * -inputDir.Z
		rawMoveDir = rawMoveDir - upDir * rawMoveDir:Dot(upDir)
		if rawMoveDir.Magnitude < 0.001 then return end
		local worldMoveDir = rawMoveDir.Unit

		if isGrounded then
			hrp.AssemblyLinearVelocity = gravityComponent + worldMoveDir * MOVE_SPEED
		else
			local desired = worldMoveDir * MOVE_SPEED
			local blended = lateralVel + (desired - lateralVel) * AIR_CONTROL
			hrp.AssemblyLinearVelocity = gravityComponent + blended
		end
	else
		if lateralVel.Magnitude < LATERAL_DEAD_ZONE then
			hrp.AssemblyLinearVelocity = gravityComponent
		else
			hrp.AssemblyLinearVelocity = gravityComponent + lateralVel * 0.85
		end
	end
end

function GraviBowCharacterController:_updateGroundSnap(hrp, gravityDir, isGrounded)
	if not isGrounded then return end

	local groundDist = self._groundController.GroundDistance
	local offset = GROUND_SNAP_HEIGHT - groundDist
	if math.abs(offset) > 0.01 and math.abs(offset) < GROUND_SNAP_TOLERANCE then
		hrp.Position = hrp.Position - gravityDir * offset
	end
end

function GraviBowCharacterController:_updateJump(hrp, gravityDir, isGrounded)
	if not self._jumpRequested then return end
	self._jumpRequested = false

	if isGrounded then
		local jumpImpulse = -gravityDir * JUMP_FORCE
		hrp:ApplyImpulse(jumpImpulse * self._cachedMass)
		self._jumpCooldown = JUMP_COOLDOWN
	end
end

function GraviBowCharacterController:_hideLocalCharacter(character)
	local function hideDesc(desc)
		if desc:IsA("BasePart") and desc.Name ~= "HumanoidRootPart" then
			desc.LocalTransparencyModifier = 1
		elseif desc:IsA("Decal") or desc:IsA("Texture") then
			desc.Transparency = 1
		end
	end

	for _, desc in ipairs(character:GetDescendants()) do
		hideDesc(desc)
	end

	character.DescendantAdded:Connect(function(desc)
		hideDesc(desc)
	end)
end

function GraviBowCharacterController:_muteCharacterSounds(character)
	local function muteSound(sound)
		if sound:IsA("Sound") then
			sound.Volume = 0
			sound.PlayOnRemove = false
			sound:Stop()
		end
	end

	for _, desc in ipairs(character:GetDescendants()) do
		muteSound(desc)
	end

	self._characterTrove:Add(character.DescendantAdded:Connect(function(desc)
		muteSound(desc)
	end), "Disconnect")
end

return GraviBowCharacterController
