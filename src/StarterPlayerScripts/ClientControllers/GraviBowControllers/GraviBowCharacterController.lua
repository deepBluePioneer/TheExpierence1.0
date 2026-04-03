local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Packages = ReplicatedStorage.Packages
local Knit = require(Packages.Knit)
local Trove = require(Packages.Trove)
local fsm = require(ReplicatedStorage.Source.fsm)

local LocalPlayer = Players.LocalPlayer

local WALK_SPEED = 24
local XZ_DRAG_FACTOR = 3
local FLAT_FRICTION = 500
local JUMP_POWER = 1000
local JUMP_DEBOUNCE_TIME = 0.25
local JUMP_ANIM_TRANSITION = 0.31
local ALIGN_RESPONSIVENESS = 20

local GraviBowCharacterController = Knit.CreateController({
	Name = "GraviBowCharacterController",

	State = "none",

	_trove = nil,
	_characterTrove = nil,
	_jumpDebounce = false,
	_jumpAnimTimer = 0,
	_cachedMass = 0,
	_stateMachine = nil,
	_movementForce = nil,
	_dragForce = nil,
	_alignOrientation = nil,
	_terrainAttachment = nil,
	_centerAttachment = nil,
})

function GraviBowCharacterController:KnitInit()
	self._trove = Trove.new()
end

function GraviBowCharacterController:KnitStart()
	self._gravityController = Knit.GetController("GraviBowGravityController")
	self._groundController = Knit.GetController("GraviBowGroundController")
	self._cameraController = Knit.GetController("GraviBowCameraController")

	self._trove:Add(UserInputService.JumpRequest:Connect(function()
		self:_onJumpRequest()
	end), "Disconnect")

	self._trove:Add(LocalPlayer.CharacterAdded:Connect(function(character)
		self:_onCharacterAdded(character)
	end), "Disconnect")

	if LocalPlayer.Character then
		self:_onCharacterAdded(LocalPlayer.Character)
	end
end

function GraviBowCharacterController:_createStateMachine()
	return fsm.create({
		initial = "Standing",
		events = {
			{ name = "run",     from = "Standing",    to = "Running" },
			{ name = "stand",   from = "Running",     to = "Standing" },
			{ name = "jump",    from = "Standing",    to = "Jumping" },
			{ name = "leap",    from = "Running",     to = "Jumping" },
			{ name = "fall",    from = "Jumping",     to = "FreeFalling" },
			{ name = "land",    from = "FreeFalling", to = "Landed" },
			{ name = "recover", from = "Landed",      to = "Standing" },
		},
	})
end

function GraviBowCharacterController:_onCharacterAdded(character)
	if self._characterTrove then
		self._characterTrove:Clean()
	end
	self._characterTrove = self._trove:Extend()

	local hrp = character:WaitForChild("HumanoidRootPart", 10)
	if not hrp then return end

	local centerAttachment = hrp:WaitForChild("CenterAttachment", 10)
	if not centerAttachment then
		warn("[GraviBowCharacterController] Missing CenterAttachment on HumanoidRootPart")
		return
	end
	self._centerAttachment = centerAttachment

	self._cachedMass = 0
	for _, part in ipairs(character:GetDescendants()) do
		if part:IsA("BasePart") then
			self._cachedMass += part:GetMass()
		end
	end

	self._stateMachine = self:_createStateMachine()
	self._jumpAnimTimer = 0

	self:_createPhysicsConstraints(character, centerAttachment)
	self:_hideLocalCharacter(character)
	self:_muteCharacterSounds(character)

	self._characterTrove:Add(RunService.Stepped:Connect(function(_, dt)
		self:_update(hrp, dt)
	end), "Disconnect")

	self._characterTrove:Add(function()
		self:_destroyPhysicsConstraints()
	end)
end

function GraviBowCharacterController:_createPhysicsConstraints(character, centerAttachment)
	local model = character

	local movementForce = Instance.new("VectorForce")
	movementForce.Name = "MovementForce"
	movementForce.Attachment0 = centerAttachment
	movementForce.ApplyAtCenterOfMass = true
	movementForce.Force = Vector3.zero
	movementForce.RelativeTo = Enum.ActuatorRelativeTo.World
	movementForce.Parent = model
	self._movementForce = movementForce

	local dragForce = Instance.new("VectorForce")
	dragForce.Name = "DragForce"
	dragForce.Attachment0 = centerAttachment
	dragForce.ApplyAtCenterOfMass = true
	dragForce.Force = Vector3.zero
	dragForce.RelativeTo = Enum.ActuatorRelativeTo.World
	dragForce.Parent = model
	self._dragForce = dragForce

	local terrainAttachment = Instance.new("Attachment")
	terrainAttachment.Name = "CharacterAlignAttachment"
	terrainAttachment.Parent = Workspace.Terrain
	self._terrainAttachment = terrainAttachment

	local alignOrientation = Instance.new("AlignOrientation")
	alignOrientation.Name = "CharacterAlign"
	alignOrientation.Attachment0 = centerAttachment
	alignOrientation.Attachment1 = terrainAttachment
	alignOrientation.MaxAngularVelocity = 100
	alignOrientation.Responsiveness = ALIGN_RESPONSIVENESS
	alignOrientation.RigidityEnabled = true
	alignOrientation.Parent = model
	self._alignOrientation = alignOrientation
end

function GraviBowCharacterController:_destroyPhysicsConstraints()
	if self._movementForce then
		self._movementForce:Destroy()
		self._movementForce = nil
	end
	if self._dragForce then
		self._dragForce:Destroy()
		self._dragForce = nil
	end
	if self._alignOrientation then
		self._alignOrientation:Destroy()
		self._alignOrientation = nil
	end
	if self._terrainAttachment then
		self._terrainAttachment:Destroy()
		self._terrainAttachment = nil
	end
end

function GraviBowCharacterController:_update(hrp, dt)
	local gravityDir = self._gravityController.GravityDirection
	local upDir = -gravityDir
	local isGrounded = self._groundController.IsGrounded

	local currentVel = hrp.AssemblyLinearVelocity

	local tangentVel = currentVel - upDir * currentVel:Dot(upDir)
	local tangentSpeed = tangentVel.Magnitude
	local tangentUnit = if tangentSpeed > 0.001 then tangentVel / tangentSpeed else Vector3.zero

	local moveDirection = self:_getWorldMoveDirection(upDir)
	local isMoving = moveDirection.Magnitude > 0.01

	self:_updateMovementForces(moveDirection, isMoving, isGrounded, tangentUnit, tangentSpeed)
	self:_updateAutoRotate(hrp, moveDirection, isMoving, upDir)
	self:_updateFreeFall(hrp, upDir, dt)
	self:_updateStateMachine(isMoving, isGrounded, tangentSpeed)

	hrp.AssemblyAngularVelocity = Vector3.zero

	self.State = self._stateMachine.current
end

function GraviBowCharacterController:_getWorldMoveDirection(upDir)
	local forwardOnSurface = self._cameraController.CameraLookOnSurface
	local rightOnSurface = self._cameraController.CameraRightOnSurface

	local inputDir = self:_getInputDirection()
	if inputDir.Magnitude < 0.01 then
		return Vector3.zero
	end

	local rawMoveDir = rightOnSurface * inputDir.X + forwardOnSurface * -inputDir.Z
	rawMoveDir = rawMoveDir - upDir * rawMoveDir:Dot(upDir)
	if rawMoveDir.Magnitude < 0.001 then
		return Vector3.zero
	end

	return rawMoveDir.Unit
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

function GraviBowCharacterController:_updateMovementForces(moveDirection, isMoving, isGrounded, tangentUnit, tangentSpeed)
	if not self._movementForce or not self._dragForce then return end

	local totalDrag = Vector3.zero

	local flatFrictionScalar = nil
	if isGrounded and isMoving and tangentSpeed > 0.001 then
		flatFrictionScalar = FLAT_FRICTION * (1.0 - math.exp(-2 * tangentSpeed))
		totalDrag += -tangentUnit * flatFrictionScalar
	end

	local counterFriction = flatFrictionScalar or FLAT_FRICTION
	local counterDrag = (WALK_SPEED ^ 2) * XZ_DRAG_FACTOR

	if counterDrag <= 0.01 then
		counterFriction = 0
	end

	local movementScalar = counterDrag + counterFriction
	self._movementForce.Force = moveDirection * movementScalar

	if isMoving and tangentSpeed > 0.001 then
		totalDrag += -tangentUnit * (tangentSpeed ^ 2) * XZ_DRAG_FACTOR
	end

	self._dragForce.Force = totalDrag
end

function GraviBowCharacterController:_updateAutoRotate(hrp, moveDirection, isMoving, upDir)
	if not self._terrainAttachment then return end

	local forwardOnSurface = self._cameraController.CameraLookOnSurface
	local projected = forwardOnSurface - upDir * forwardOnSurface:Dot(upDir)
	if projected.Magnitude > 0.001 then
		self._terrainAttachment.CFrame = CFrame.lookAt(Vector3.zero, projected.Unit, upDir)
	end
end

function GraviBowCharacterController:_updateFreeFall(hrp, upDir, dt)
	if not self._stateMachine then return end

	self._jumpAnimTimer = math.max(0, self._jumpAnimTimer - dt)

	local verticalVel = hrp.AssemblyLinearVelocity:Dot(upDir)

	if verticalVel < 0
		and self._stateMachine.current == "Jumping"
		and self._jumpAnimTimer <= 0
	then
		self._stateMachine.fall()
	end
end

function GraviBowCharacterController:_updateStateMachine(isMoving, isGrounded, tangentSpeed)
	if not self._stateMachine then return end

	local sm = self._stateMachine

	if isGrounded and sm.current == "FreeFalling" then
		sm.land()
		sm.recover()
	end

	if sm.current == "Standing" and isMoving and tangentSpeed >= 0.1 then
		sm.run()
	end

	if sm.current == "Running" and tangentSpeed < 0.1 then
		sm.stand()
	end
end

function GraviBowCharacterController:_onJumpRequest()
	if self._jumpDebounce then return end

	local isGrounded = self._groundController.IsGrounded
	if not isGrounded then return end

	local sm = self._stateMachine
	if not sm then return end

	self._jumpDebounce = true

	local gravityDir = self._gravityController.GravityDirection
	local upDir = -gravityDir

	local character = LocalPlayer.Character
	if not character then
		self._jumpDebounce = false
		return
	end
	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not hrp then
		self._jumpDebounce = false
		return
	end

	hrp:ApplyImpulse(upDir * JUMP_POWER)

	if sm.current == "Standing" then
		sm.jump()
	elseif sm.current == "Running" then
		sm.leap()
	end

	self._jumpAnimTimer = JUMP_ANIM_TRANSITION

	task.delay(JUMP_DEBOUNCE_TIME, function()
		self._jumpDebounce = false
	end)
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
