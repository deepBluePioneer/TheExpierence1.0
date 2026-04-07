local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Packages = ReplicatedStorage.Packages
local Knit = require(Packages.Knit)
local Trove = require(Packages.Trove)
local fsm = require(ReplicatedStorage.Source.fsm)

local Gizmo
do
	local ok, mod = pcall(require, Packages.imgizmo)
	if ok then
		Gizmo = mod
		Gizmo.Init()
	end
end

local LocalPlayer = Players.LocalPlayer

local WALK_SPEED = 24
local XZ_DRAG_FACTOR = 3
local FLAT_FRICTION = 500
local AIR_CONTROL = 0.15
local JETPACK_AIR_CONTROL = 0.5
local AIR_DRAG_FACTOR = 0.5
local STOP_DAMPING = 60

local JUMP_VELOCITY = 58
local JUMP_CUT_DAMPING = 0.4
local APEX_GRAVITY_SCALE = 1.0
local APEX_SPEED_THRESHOLD = 0
local FALL_GRAVITY_SCALE = 4.5
local COYOTE_TIME = 0.12
local JUMP_BUFFER_TIME = 0.15
local JUMP_DEBOUNCE_TIME = 0.1
local JUMP_ANIM_TRANSITION = 0.31

local ALIGN_RESPONSIVENESS = 20
local FADE_IN_START = 2
local FADE_IN_END = 6
local ANIM_FADE_TIME = 0.2

local GRAVITY_FORCE = 40

local LUNGE_IMPULSE = 250
local LUNGE_COOLDOWN = 1.0

local DIG_SPEED_THRESHOLD = 40
local DIG_DURATION = 0.6
local DIG_EXIT_VELOCITY = 55

local DIG_GIZMO_SEGMENTS = 32
local DIG_GIZMO_COLOR_ENTRY = Color3.fromRGB(255, 120, 40)
local DIG_GIZMO_COLOR_EXIT = Color3.fromRGB(40, 200, 255)
local DIG_GIZMO_COLOR_ARC = Color3.fromRGB(255, 200, 60)

local ANIM_IDS = {
	Idle     = "rbxassetid://507766666",
	Walk     = "rbxassetid://507777826",
	Jump     = "rbxassetid://507765000",
	Fall     = "rbxassetid://507767968",
}

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
	_jumpPhaseForce = nil,
	_alignOrientation = nil,
	_terrainAttachment = nil,
	_centerAttachment = nil,
	_animator = nil,
	_animTracks = {},
	_currentAnimState = nil,
	_character = nil,

	_jumpHeld = false,
	_jumpReleased = false,
	_jumpCutApplied = false,
	_coyoteTimer = 0,
	_jumpBuffered = false,
	_jumpBufferTimer = 0,
	_wasGrounded = false,

	_lungeCooldownTimer = 0,
	_isMobile = false,
	_thumbstickDir = nil,
	_thumbstickTouchId = nil,

	_isDigging = false,
	_digTimer = 0,
	_digEntryPos = nil,
	_digExitPos = nil,
	_digExitUpDir = nil,
	_digCP1 = nil,
	_digCP2 = nil,
	_digEntryLook = nil,
})

function GraviBowCharacterController:KnitInit()
	self._trove = Trove.new()
end

function GraviBowCharacterController:KnitStart()
	self._gravityController = Knit.GetController("GraviBowGravityController")
	self._groundController = Knit.GetController("GraviBowGroundController")
	self._cameraController = Knit.GetController("GraviBowCameraController")
	self._jetpackController = Knit.GetController("GraviBowJetpackController")
	self._matchController = Knit.GetController("GraviBowMatchController")

	self._isMobile = UserInputService.TouchEnabled
	self._thumbstickDir = Vector3.zero

	self._trove:Add(UserInputService.JumpRequest:Connect(function()
		self:_onJumpRequest()
	end), "Disconnect")

	self._trove:Add(UserInputService.InputBegan:Connect(function(input, processed)
		if processed then return end
		if input.KeyCode == Enum.KeyCode.Space
			or input.KeyCode == Enum.KeyCode.ButtonA then
			self._jumpHeld = true
			self._jumpReleased = false
		end
	end), "Disconnect")

	self._trove:Add(UserInputService.InputEnded:Connect(function(input)
		if input.KeyCode == Enum.KeyCode.Space
			or input.KeyCode == Enum.KeyCode.ButtonA then
			self._jumpHeld = false
			self._jumpReleased = true
		end
	end), "Disconnect")

	if self._isMobile then
		self:_createMobileControls()
	end

	self._trove:Add(LocalPlayer.CharacterAdded:Connect(function(character)
		self:_onCharacterAdded(character)
	end), "Disconnect")

	if LocalPlayer.Character then
		self:_onCharacterAdded(LocalPlayer.Character)
	end
end

function GraviBowCharacterController:_createMobileControls()
	local STICK_COLOR = Color3.fromRGB(255, 150, 40)
	local STICK_BG = Color3.fromRGB(25, 18, 12)
	local JUMP_COLOR = Color3.fromRGB(255, 150, 40)

	local gui = Instance.new("ScreenGui")
	gui.Name = "MobileControls"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 200
	gui.IgnoreGuiInset = true
	gui.Parent = LocalPlayer.PlayerGui
	self._trove:Add(gui)

	local thumbOuter = Instance.new("TextButton")
	thumbOuter.Name = "ThumbstickOuter"
	thumbOuter.Active = true
	thumbOuter.AnchorPoint = Vector2.new(0.5, 0.5)
	thumbOuter.Position = UDim2.fromScale(0.13, 0.72)
	thumbOuter.Size = UDim2.fromScale(0.18, 0)
	thumbOuter.BackgroundColor3 = STICK_BG
	thumbOuter.BackgroundTransparency = 0.5
	thumbOuter.BorderSizePixel = 0
	thumbOuter.Text = ""
	thumbOuter.AutoButtonColor = false
	thumbOuter.Parent = gui

	local outerAR = Instance.new("UIAspectRatioConstraint")
	outerAR.AspectRatio = 1
	outerAR.Parent = thumbOuter

	local outerCorner = Instance.new("UICorner")
	outerCorner.CornerRadius = UDim.new(1, 0)
	outerCorner.Parent = thumbOuter

	local outerStroke = Instance.new("UIStroke")
	outerStroke.Color = STICK_COLOR
	outerStroke.Thickness = 2
	outerStroke.Transparency = 0.4
	outerStroke.Parent = thumbOuter

	local thumbInner = Instance.new("Frame")
	thumbInner.Name = "ThumbstickInner"
	thumbInner.AnchorPoint = Vector2.new(0.5, 0.5)
	thumbInner.Position = UDim2.fromScale(0.5, 0.5)
	thumbInner.Size = UDim2.fromScale(0.4, 0.4)
	thumbInner.BackgroundColor3 = STICK_COLOR
	thumbInner.BackgroundTransparency = 0.3
	thumbInner.BorderSizePixel = 0
	thumbInner.Parent = thumbOuter

	local innerAR = Instance.new("UIAspectRatioConstraint")
	innerAR.AspectRatio = 1
	innerAR.Parent = thumbInner

	local innerCorner = Instance.new("UICorner")
	innerCorner.CornerRadius = UDim.new(1, 0)
	innerCorner.Parent = thumbInner

	local jumpBtn = Instance.new("TextButton")
	jumpBtn.Name = "JumpButton"
	jumpBtn.AnchorPoint = Vector2.new(0.5, 0.5)
	jumpBtn.Position = UDim2.fromScale(0.88, 0.72)
	jumpBtn.Size = UDim2.fromScale(0.13, 0)
	jumpBtn.BackgroundColor3 = STICK_BG
	jumpBtn.BackgroundTransparency = 0.5
	jumpBtn.BorderSizePixel = 0
	jumpBtn.Text = ""
	jumpBtn.AutoButtonColor = false
	jumpBtn.Parent = gui

	local jumpAR = Instance.new("UIAspectRatioConstraint")
	jumpAR.AspectRatio = 1
	jumpAR.Parent = jumpBtn

	local jumpCorner = Instance.new("UICorner")
	jumpCorner.CornerRadius = UDim.new(1, 0)
	jumpCorner.Parent = jumpBtn

	local jumpStroke = Instance.new("UIStroke")
	jumpStroke.Color = JUMP_COLOR
	jumpStroke.Thickness = 2
	jumpStroke.Transparency = 0.4
	jumpStroke.Parent = jumpBtn

	local jumpIcon = Instance.new("TextLabel")
	jumpIcon.Size = UDim2.fromScale(1, 1)
	jumpIcon.BackgroundTransparency = 1
	jumpIcon.Text = "^"
	jumpIcon.TextScaled = true
	jumpIcon.TextColor3 = JUMP_COLOR
	jumpIcon.Font = Enum.Font.GothamBold
	jumpIcon.Parent = jumpBtn

	local jumpTSC = Instance.new("UITextSizeConstraint")
	jumpTSC.MinTextSize = 16
	jumpTSC.MaxTextSize = 48
	jumpTSC.Parent = jumpIcon

	thumbOuter.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch then
			self._thumbstickTouchId = input
		end
	end)

	self._trove:Add(UserInputService.InputChanged:Connect(function(input)
		if input ~= self._thumbstickTouchId then return end
		if input.UserInputType ~= Enum.UserInputType.Touch then return end

		local center = thumbOuter.AbsolutePosition + thumbOuter.AbsoluteSize / 2
		local touchPos = Vector2.new(input.Position.X, input.Position.Y)
		local offset = touchPos - center
		local radius = thumbOuter.AbsoluteSize.X / 2

		local clampedOffset = offset
		if offset.Magnitude > radius then
			clampedOffset = offset.Unit * radius
		end

		local norm = clampedOffset / radius
		thumbInner.Position = UDim2.fromScale(0.5 + norm.X * 0.35, 0.5 + norm.Y * 0.35)

		local mag = math.min(offset.Magnitude / radius, 1)
		if mag < 0.15 then
			self._thumbstickDir = Vector3.zero
		else
			local dir = offset.Unit
			self._thumbstickDir = Vector3.new(dir.X, 0, dir.Y) * mag
		end
	end), "Disconnect")

	self._trove:Add(UserInputService.InputEnded:Connect(function(input)
		if input ~= self._thumbstickTouchId then return end
		self._thumbstickTouchId = nil
		self._thumbstickDir = Vector3.zero
		thumbInner.Position = UDim2.fromScale(0.5, 0.5)
	end), "Disconnect")

	jumpBtn.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch then
			self._jumpHeld = true
			self._jumpReleased = false
			self:_onJumpRequest()
		end
	end)

	jumpBtn.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch then
			self._jumpHeld = false
			self._jumpReleased = true
		end
	end)
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

	self._character = character

	self:_createPhysicsConstraints(character, centerAttachment)
	self:_setupAnimations(character)
	self:_setCharacterTransparency(1)
	self:_muteCharacterSounds(character)

	self._characterTrove:Add(RunService.Stepped:Connect(function(_, dt)
		self:_update(hrp, dt)
	end), "Disconnect")

	if Gizmo then
		self._characterTrove:Add(RunService.RenderStepped:Connect(function()
			self:_drawDigTrajectory(hrp)
		end), "Disconnect")
	end

	self._characterTrove:Add(function()
		self:_destroyPhysicsConstraints()
		self:_cleanupAnimations()
		self._character = nil
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

	local jumpPhaseForce = Instance.new("VectorForce")
	jumpPhaseForce.Name = "JumpPhaseForce"
	jumpPhaseForce.Attachment0 = centerAttachment
	jumpPhaseForce.ApplyAtCenterOfMass = true
	jumpPhaseForce.Force = Vector3.zero
	jumpPhaseForce.RelativeTo = Enum.ActuatorRelativeTo.World
	jumpPhaseForce.Parent = model
	self._jumpPhaseForce = jumpPhaseForce

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
	if self._jumpPhaseForce then
		self._jumpPhaseForce:Destroy()
		self._jumpPhaseForce = nil
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
	if self._isDigging then
		self:_updateDig(hrp, dt)
		return
	end

	local gravityDir = self._gravityController.GravityDirection
	local upDir = -gravityDir
	local isGrounded = self._groundController.IsGrounded

	local currentVel = hrp.AssemblyLinearVelocity

	local tangentVel = currentVel - upDir * currentVel:Dot(upDir)
	local tangentSpeed = tangentVel.Magnitude
	local tangentUnit = if tangentSpeed > 0.001 then tangentVel / tangentSpeed else Vector3.zero

	local moveDirection = self:_getWorldMoveDirection(upDir)
	local isMoving = moveDirection.Magnitude > 0.01

	if isGrounded and not isMoving and tangentSpeed > 0.001 then
		local verticalVel = upDir * currentVel:Dot(upDir)
		hrp.AssemblyLinearVelocity = verticalVel
	end

	self:_updateCoyoteTime(isGrounded, dt)
	self:_updateJumpBuffer(isGrounded, dt)
	self:_updateMovementForces(moveDirection, isMoving, isGrounded, tangentUnit, tangentSpeed)
	self:_updateJumpPhaseForces(hrp, gravityDir, upDir, isGrounded, dt)
	local orientUpDir = -self._gravityController:GetSmoothedGravityDirection()
	self:_updateAutoRotate(hrp, moveDirection, isMoving, orientUpDir)
	self:_updateFreeFall(hrp, upDir, dt)
	self:_updateStateMachine(hrp, isMoving, isGrounded, tangentSpeed, upDir)
	self:_updateAnimation()
	self:_updateCharacterVisibility()

	if self._lungeCooldownTimer > 0 then
		self._lungeCooldownTimer -= dt
	end

	self._wasGrounded = isGrounded
	hrp.AssemblyAngularVelocity = Vector3.zero

	self.State = self._stateMachine.current
end

function GraviBowCharacterController:_tryLunge()
	if self._lungeCooldownTimer > 0 then return end
	if self._isDigging then return end

	local character = self._character
	if not character then return end
	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not hrp then return end

	local upDir = -self._gravityController.GravityDirection
	local moveDir = self:_getWorldMoveDirection(upDir)

	if moveDir.Magnitude < 0.01 then
		local vel = hrp.AssemblyLinearVelocity
		local tangent = vel - upDir * vel:Dot(upDir)
		if tangent.Magnitude > 1 then
			moveDir = tangent.Unit
		else
			moveDir = self._cameraController.CameraLookOnSurface
			if not moveDir or moveDir.Magnitude < 0.01 then return end
		end
	end

	moveDir = (moveDir - upDir * moveDir:Dot(upDir))
	if moveDir.Magnitude < 0.01 then return end
	moveDir = moveDir.Unit

	hrp.AssemblyLinearVelocity = hrp.AssemblyLinearVelocity + moveDir * LUNGE_IMPULSE
	self._lungeCooldownTimer = LUNGE_COOLDOWN
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

	if self._thumbstickDir and self._thumbstickDir.Magnitude > 0.15 then
		return self._thumbstickDir.Unit
	end

	return Vector3.zero
end

function GraviBowCharacterController:_updateMovementForces(moveDirection, isMoving, isGrounded, tangentUnit, tangentSpeed)
	if not self._movementForce or not self._dragForce then return end

	local totalDrag = Vector3.zero

	if isGrounded then
		if tangentSpeed > 0.001 then
			if isMoving then
				local friction = FLAT_FRICTION * (1.0 - math.exp(-2 * tangentSpeed))
				totalDrag += -tangentUnit * friction
			else
				totalDrag += -tangentUnit * tangentSpeed * STOP_DAMPING
			end
			totalDrag += -tangentUnit * (tangentSpeed ^ 2) * XZ_DRAG_FACTOR
		end

		if isMoving then
			local counterDrag = (WALK_SPEED ^ 2) * XZ_DRAG_FACTOR
			local counterFriction = FLAT_FRICTION
			self._movementForce.Force = moveDirection * (counterDrag + counterFriction)
		else
			self._movementForce.Force = Vector3.zero
		end
	else
		if tangentSpeed > 0.001 then
			totalDrag += -tangentUnit * (tangentSpeed ^ 2) * AIR_DRAG_FACTOR
		end

		local airControl = AIR_CONTROL
		if self._jetpackController and self._jetpackController:IsThrusting() then
			airControl = JETPACK_AIR_CONTROL
		end

		if isMoving then
			local groundForce = (WALK_SPEED ^ 2) * XZ_DRAG_FACTOR + FLAT_FRICTION
			self._movementForce.Force = moveDirection * groundForce * airControl
		else
			self._movementForce.Force = Vector3.zero
		end
	end

	self._dragForce.Force = totalDrag
end

function GraviBowCharacterController:_setupAnimations(character)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then return end

	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = humanoid
	end
	self._animator = animator
	self._animTracks = {}
	self._currentAnimState = nil

	for name, id in pairs(ANIM_IDS) do
		local anim = Instance.new("Animation")
		anim.AnimationId = id
		local track = animator:LoadAnimation(anim)
		track.Priority = Enum.AnimationPriority.Core
		if name == "Idle" or name == "Walk" then
			track.Looped = true
		else
			track.Looped = false
		end
		self._animTracks[name] = track
	end
end

function GraviBowCharacterController:_cleanupAnimations()
	for _, track in pairs(self._animTracks) do
		track:Stop(0)
	end
	self._animTracks = {}
	self._animator = nil
	self._currentAnimState = nil
end

function GraviBowCharacterController:_updateAnimation()
	if not self._animator then return end

	local sm = self._stateMachine
	if not sm then return end

	local state = sm.current
	local targetAnim
	if state == "Running" then
		targetAnim = "Walk"
	elseif state == "Jumping" then
		targetAnim = "Jump"
	elseif state == "FreeFalling" then
		targetAnim = "Fall"
	else
		targetAnim = "Idle"
	end

	if targetAnim == self._currentAnimState then return end

	if self._currentAnimState and self._animTracks[self._currentAnimState] then
		self._animTracks[self._currentAnimState]:Stop(ANIM_FADE_TIME)
	end

	local track = self._animTracks[targetAnim]
	if track then
		track:Play(ANIM_FADE_TIME)
	end

	self._currentAnimState = targetAnim
end

function GraviBowCharacterController:_updateAutoRotate(hrp, moveDirection, isMoving, upDir)
	if not self._terrainAttachment then return end

	local forwardOnSurface = self._cameraController.CameraLookOnSurface
	local projected = forwardOnSurface - upDir * forwardOnSurface:Dot(upDir)
	if projected.Magnitude > 0.001 then
		self._terrainAttachment.CFrame = CFrame.lookAt(Vector3.zero, projected.Unit, upDir)
	end
end

function GraviBowCharacterController:_updateCoyoteTime(isGrounded, dt)
	if isGrounded then
		self._coyoteTimer = COYOTE_TIME
	else
		self._coyoteTimer = math.max(0, self._coyoteTimer - dt)
	end
end

function GraviBowCharacterController:_updateJumpBuffer(isGrounded, dt)
	if self._jumpBuffered then
		self._jumpBufferTimer = math.max(0, self._jumpBufferTimer - dt)
		if self._jumpBufferTimer <= 0 then
			self._jumpBuffered = false
		end
	end

	if isGrounded and self._jumpBuffered then
		self._jumpBuffered = false
		self:_executeJump()
	end
end

function GraviBowCharacterController:_updateJumpPhaseForces(hrp, gravityDir, upDir, isGrounded, dt)
	if not self._jumpPhaseForce then return end

	if isGrounded then
		self._jumpPhaseForce.Force = Vector3.zero
		self._jumpCutApplied = false
		return
	end

	local verticalVel = hrp.AssemblyLinearVelocity:Dot(upDir)
	local baseGravityForce = GRAVITY_FORCE * self._cachedMass
	local ascending = verticalVel > 0
	local nearApex = math.abs(verticalVel) < APEX_SPEED_THRESHOLD

	if ascending and self._jumpReleased and not self._jumpCutApplied then
		self._jumpCutApplied = true
		local currentVel = hrp.AssemblyLinearVelocity
		local tangentVel = currentVel - upDir * verticalVel
		hrp.AssemblyLinearVelocity = tangentVel + upDir * (verticalVel * JUMP_CUT_DAMPING)
	end

	local phaseForce = Vector3.zero

	if nearApex and not isGrounded then
		local apexReduction = (1 - APEX_GRAVITY_SCALE) * baseGravityForce
		phaseForce = upDir * apexReduction
	elseif not ascending then
		local fallExtra = (FALL_GRAVITY_SCALE - 1) * baseGravityForce
		phaseForce = gravityDir * fallExtra
	end

	self._jumpPhaseForce.Force = phaseForce
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

function GraviBowCharacterController:_updateStateMachine(hrp, isMoving, isGrounded, tangentSpeed, upDir)
	if not self._stateMachine then return end

	local sm = self._stateMachine

	if isGrounded and sm.current == "FreeFalling" then
		local impactVelocity = hrp.AssemblyLinearVelocity
		if self:_tryStartDig(hrp, upDir, impactVelocity) then
			sm.land()
			return
		end
		sm.land()
		sm.recover()
	end

	if sm.current == "Standing" and isMoving and tangentSpeed >= 0.1 then
		sm.run()
	end

	if sm.current == "Running" and (tangentSpeed < 0.1 or (isGrounded and not isMoving)) then
		sm.stand()
	end
end

function GraviBowCharacterController:_onJumpRequest()
	local sm = self._stateMachine
	if not sm then return end

	if self._jumpDebounce then
		self._jumpBuffered = true
		self._jumpBufferTimer = JUMP_BUFFER_TIME
		return
	end

	local isGrounded = self._groundController.IsGrounded
	local canCoyote = self._coyoteTimer > 0
		and (sm.current == "FreeFalling" or not isGrounded)

	if not isGrounded and not canCoyote then
		self._jumpBuffered = true
		self._jumpBufferTimer = JUMP_BUFFER_TIME
		return
	end

	self:_executeJump()
end

function GraviBowCharacterController:_executeJump()
	if self._jumpDebounce then return end

	local sm = self._stateMachine
	if not sm then return end

	local character = LocalPlayer.Character
	if not character then return end
	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not hrp then return end

	self._jumpDebounce = true
	self._jumpCutApplied = false
	self._jumpReleased = false
	self._coyoteTimer = 0

	local gravityDir = self._gravityController.GravityDirection
	local upDir = -gravityDir

	local currentVel = hrp.AssemblyLinearVelocity
	local tangentVel = currentVel - upDir * currentVel:Dot(upDir)
	hrp.AssemblyLinearVelocity = tangentVel + upDir * JUMP_VELOCITY

	if sm.current == "Standing" then
		sm.jump()
	elseif sm.current == "Running" then
		sm.leap()
	elseif sm.current == "FreeFalling" then
		-- Coyote jump from freefall — force back through the state machine
	end

	self._jumpAnimTimer = JUMP_ANIM_TRANSITION

	task.delay(JUMP_DEBOUNCE_TIME, function()
		self._jumpDebounce = false
	end)
end

function GraviBowCharacterController:RequestJump()
	self:_onJumpRequest()
end

function GraviBowCharacterController:IsDigging()
	return self._isDigging
end

function GraviBowCharacterController:GetDigBezier()
	if not self._isDigging then return nil end
	return {
		p0 = self._digEntryPos,
		p1 = self._digCP1,
		p2 = self._digCP2,
		p3 = self._digExitPos,
		alpha = math.clamp(self._digTimer / DIG_DURATION, 0, 1),
	}
end

function GraviBowCharacterController:_tryStartDig(hrp, upDir, impactVelocity)
	if not self._matchController:IsLocalPlayerSnake() then
		return false
	end

	local downSpeed = -impactVelocity:Dot(upDir)
	if downSpeed < DIG_SPEED_THRESHOLD then
		return false
	end

	local character = self._character
	if not character then return false end

	local planetCenter = self._gravityController:GetSphereCenter()
	local planetRadius = self._gravityController:GetSphereRadius()
	local entryPos = hrp.Position
	local entryUpDir = upDir

	local tangentVel = impactVelocity - entryUpDir * impactVelocity:Dot(entryUpDir)
	local forwardSpeed = tangentVel.Magnitude
	local forwardDir
	if forwardSpeed > 0.1 then
		forwardDir = tangentVel.Unit
	else
		forwardDir = entryUpDir:Cross(Vector3.new(0, 0, 1))
		if forwardDir.Magnitude < 0.01 then
			forwardDir = entryUpDir:Cross(Vector3.new(1, 0, 0))
		end
		forwardDir = forwardDir.Unit
		forwardSpeed = 10
	end

	local speedFactor = math.clamp(forwardSpeed / 60, 0.3, 1)
	local arcAngle = math.rad(40) * speedFactor + math.rad(25)

	local rotAxis = entryUpDir:Cross(forwardDir)
	if rotAxis.Magnitude < 0.001 then
		rotAxis = entryUpDir:Cross(Vector3.new(0, 0, 1))
	end
	rotAxis = rotAxis.Unit

	local exitUpDir = entryUpDir * math.cos(arcAngle)
		+ rotAxis:Cross(entryUpDir) * math.sin(arcAngle)
		+ rotAxis * rotAxis:Dot(entryUpDir) * (1 - math.cos(arcAngle))
	exitUpDir = exitUpDir.Unit

	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	local excludeList = { character }
	local snakeBodies = Workspace:FindFirstChild("SnakeBodies")
	if snakeBodies then table.insert(excludeList, snakeBodies) end
	local gravZones = Workspace:FindFirstChild("GravityZones")
	if gravZones then table.insert(excludeList, gravZones) end
	local tpFolder = Workspace:FindFirstChild("TerrainPlanets")
	if tpFolder then table.insert(excludeList, tpFolder) end
	rayParams.FilterDescendantsInstances = excludeList

	local exitRayOrigin = planetCenter + exitUpDir * (planetRadius + 30)
	local result = Workspace:Raycast(exitRayOrigin, -exitUpDir * 60, rayParams)
	local exitPos
	if result then
		exitPos = result.Position + exitUpDir * 3
	else
		exitPos = planetCenter + exitUpDir * (planetRadius + 3)
	end

	local entryVelDir = impactVelocity.Unit
	local exitForwardDir = exitUpDir:Cross(rotAxis)
	if exitForwardDir:Dot(forwardDir) < 0 then exitForwardDir = -exitForwardDir end
	exitForwardDir = exitForwardDir.Unit
	local exitVelDir = (exitForwardDir * 0.4 + exitUpDir * 2).Unit

	local arcDist = (entryPos - exitPos).Magnitude
	local pullStrength = arcDist * 0.45

	local cp1 = entryPos + entryVelDir * pullStrength
	local cp2 = exitPos - exitVelDir * (pullStrength * 0.7)

	self._digEntryPos = entryPos
	self._digExitPos = exitPos
	self._digExitUpDir = exitUpDir
	self._digCP1 = cp1
	self._digCP2 = cp2
	self._digEntryLook = hrp.CFrame.LookVector
	self._digTimer = 0
	self._isDigging = true

	if self._movementForce then self._movementForce.Force = Vector3.zero end
	if self._dragForce then self._dragForce.Force = Vector3.zero end
	if self._jumpPhaseForce then self._jumpPhaseForce.Force = Vector3.zero end

	for _, desc in ipairs(character:GetDescendants()) do
		if desc:IsA("BasePart") then
			desc.CanCollide = false
		end
	end

	hrp.AssemblyLinearVelocity = Vector3.zero
	hrp.AssemblyAngularVelocity = Vector3.zero

	self:_spawnDigParticles(entryPos, -entryUpDir)

	self._cameraController:SetDigTarget(exitPos, exitUpDir)

	return true
end

function GraviBowCharacterController:_updateDig(hrp, dt)
	if not self._isDigging then return end

	self._digTimer += dt
	local alpha = math.clamp(self._digTimer / DIG_DURATION, 0, 1)
	alpha = alpha * alpha * (3 - 2 * alpha)

	local p0 = self._digEntryPos
	local p1 = self._digCP1
	local p2 = self._digCP2
	local p3 = self._digExitPos
	local t = alpha
	local u = 1 - t

	local pos = u*u*u * p0 + 3*u*u*t * p1 + 3*u*t*t * p2 + t*t*t * p3

	local tangent = 3*u*u * (p1 - p0) + 6*u*t * (p2 - p1) + 3*t*t * (p3 - p2)
	if tangent.Magnitude < 0.01 then
		tangent = (p3 - p0)
	end
	if tangent.Magnitude > 0.01 then
		tangent = tangent.Unit
	else
		tangent = self._digExitUpDir
	end

	local charUp = tangent
	local entryLook = self._digEntryLook or Vector3.zAxis
	local charLook = entryLook - charUp * entryLook:Dot(charUp)
	if charLook.Magnitude < 0.01 then
		charLook = charUp:Cross(Vector3.new(0, 0, 1))
		if charLook.Magnitude < 0.01 then
			charLook = charUp:Cross(Vector3.new(1, 0, 0))
		end
	end
	charLook = charLook.Unit
	local charRight = charLook:Cross(charUp).Unit

	hrp.CFrame = CFrame.fromMatrix(pos, charRight, charUp, -charLook)
	hrp.AssemblyLinearVelocity = Vector3.zero
	hrp.AssemblyAngularVelocity = Vector3.zero

	hrp.CanCollide = false
	local character = self._character
	if character then
		for _, desc in ipairs(character:GetDescendants()) do
			if desc:IsA("BasePart") then
				desc.CanCollide = false
			end
		end
	end

	if alpha >= 1 then
		self:_endDig(hrp)
	end
end

function GraviBowCharacterController:_endDig(hrp)
	self._isDigging = false

	local character = self._character
	if character then
		for _, desc in ipairs(character:GetDescendants()) do
			if desc:IsA("BasePart") and desc.Name ~= "HumanoidRootPart" then
				desc.CanCollide = false
			end
		end
		local hrpPart = character:FindFirstChild("HumanoidRootPart")
		if hrpPart then
			hrpPart.CanCollide = true
		end
	end

	local exitTangent = self._digExitUpDir
	if self._digCP2 and self._digExitPos then
		local t = (self._digExitPos - self._digCP2)
		if t.Magnitude > 0.01 then
			exitTangent = t.Unit
		end
	end
	hrp.AssemblyLinearVelocity = exitTangent * DIG_EXIT_VELOCITY
	hrp.AssemblyAngularVelocity = Vector3.zero

	self:_spawnDigParticles(self._digExitPos, self._digExitUpDir)

	self._cameraController:ClearDigTarget()

	if self._stateMachine then
		if self._stateMachine.current == "Landed" then
			self._stateMachine.recover()
		end
	end

	self._jumpCutApplied = false
	self._jumpReleased = false
end

function GraviBowCharacterController:_drawDigTrajectory(hrp)
	if not Gizmo then return end
	if not self._matchController:IsLocalPlayerSnake() then return end

	local planetCenter = self._gravityController:GetSphereCenter()
	local planetRadius = self._gravityController:GetSphereRadius()

	local entryPos, exitPos, cp1, cp2, entryUpDir, exitUpDir

	if self._isDigging and self._digEntryPos and self._digExitPos then
		entryPos = self._digEntryPos
		exitPos = self._digExitPos
		cp1 = self._digCP1
		cp2 = self._digCP2
		entryUpDir = (entryPos - planetCenter)
		if entryUpDir.Magnitude > 0.01 then entryUpDir = entryUpDir.Unit else entryUpDir = Vector3.yAxis end
		exitUpDir = self._digExitUpDir
	else
		local isGrounded = self._groundController.IsGrounded
		if isGrounded then return end

		local vel = hrp.AssemblyLinearVelocity
		local upDir = -self._gravityController.GravityDirection
		local downSpeed = -vel:Dot(upDir)
		if downSpeed < 1 then return end

		entryPos = hrp.Position
		entryUpDir = upDir

		local tangentVel = vel - entryUpDir * vel:Dot(entryUpDir)
		local forwardSpeed = tangentVel.Magnitude
		local forwardDir
		if forwardSpeed > 0.1 then
			forwardDir = tangentVel.Unit
		else
			forwardDir = entryUpDir:Cross(Vector3.new(0, 0, 1))
			if forwardDir.Magnitude < 0.01 then
				forwardDir = entryUpDir:Cross(Vector3.new(1, 0, 0))
			end
			forwardDir = forwardDir.Unit
			forwardSpeed = 10
		end

		local speedFactor = math.clamp(forwardSpeed / 60, 0.3, 1)
		local arcAngle = math.rad(40) * speedFactor + math.rad(25)

		local rotAxis = entryUpDir:Cross(forwardDir)
		if rotAxis.Magnitude < 0.001 then
			rotAxis = entryUpDir:Cross(Vector3.new(0, 0, 1))
		end
		rotAxis = rotAxis.Unit

		exitUpDir = entryUpDir * math.cos(arcAngle)
			+ rotAxis:Cross(entryUpDir) * math.sin(arcAngle)
			+ rotAxis * rotAxis:Dot(entryUpDir) * (1 - math.cos(arcAngle))
		exitUpDir = exitUpDir.Unit

		local character = self._character
		local rayParams = RaycastParams.new()
		rayParams.FilterType = Enum.RaycastFilterType.Exclude
		local excludeList = {}
		if character then table.insert(excludeList, character) end
		local snakeBodies = Workspace:FindFirstChild("SnakeBodies")
		if snakeBodies then table.insert(excludeList, snakeBodies) end
		local gravZones = Workspace:FindFirstChild("GravityZones")
		if gravZones then table.insert(excludeList, gravZones) end
		local tpFolder = Workspace:FindFirstChild("TerrainPlanets")
		if tpFolder then table.insert(excludeList, tpFolder) end
		rayParams.FilterDescendantsInstances = excludeList

		local exitRayOrigin = planetCenter + exitUpDir * (planetRadius + 30)
		local result = Workspace:Raycast(exitRayOrigin, -exitUpDir * 60, rayParams)
		if result then
			exitPos = result.Position + exitUpDir * 3
		else
			exitPos = planetCenter + exitUpDir * (planetRadius + 3)
		end

		local entryVelDir = vel.Unit
		local exitForwardDir = exitUpDir:Cross(rotAxis)
		if exitForwardDir:Dot(forwardDir) < 0 then exitForwardDir = -exitForwardDir end
		exitForwardDir = exitForwardDir.Unit
		local exitVelDir = (exitForwardDir * 0.4 + exitUpDir * 2).Unit

		local arcDist = (entryPos - exitPos).Magnitude
		local pullStrength = arcDist * 0.45

		cp1 = entryPos + entryVelDir * pullStrength
		cp2 = exitPos - exitVelDir * (pullStrength * 0.7)
	end

	Gizmo.PushProperty("AlwaysOnTop", true)

	for i = 0, DIG_GIZMO_SEGMENTS - 1 do
		local t0 = i / DIG_GIZMO_SEGMENTS
		local t1 = (i + 1) / DIG_GIZMO_SEGMENTS

		local a0 = (1 - t0)
		local b0 = t0
		local g0 = a0*a0*a0 * entryPos + 3*a0*a0*b0 * cp1 + 3*a0*b0*b0 * cp2 + b0*b0*b0 * exitPos

		local a1 = (1 - t1)
		local b1 = t1
		local g1 = a1*a1*a1 * entryPos + 3*a1*a1*b1 * cp1 + 3*a1*b1*b1 * cp2 + b1*b1*b1 * exitPos

		local segColor = DIG_GIZMO_COLOR_ENTRY:Lerp(DIG_GIZMO_COLOR_EXIT, t0)
		Gizmo.PushProperty("Color3", segColor)
		Gizmo.Ray:Draw(g0, g1)
	end

	Gizmo.PushProperty("Color3", DIG_GIZMO_COLOR_ENTRY)
	Gizmo.Arrow:Draw(entryPos, entryPos - entryUpDir * 6, 0.3, 0.8, 6)

	Gizmo.PushProperty("Color3", DIG_GIZMO_COLOR_EXIT)
	Gizmo.Arrow:Draw(exitPos, exitPos + exitUpDir * 6, 0.3, 0.8, 6)

	Gizmo.PushProperty("Color3", DIG_GIZMO_COLOR_ARC)
	Gizmo.Sphere:Draw(CFrame.new(entryPos), 1.5, 8, 360)
	Gizmo.Sphere:Draw(CFrame.new(exitPos), 1.5, 8, 360)
end

function GraviBowCharacterController:_spawnDigParticles(position, direction)
	local att = Instance.new("Attachment")
	att.WorldPosition = position
	att.Parent = Workspace.Terrain

	local emitter = Instance.new("ParticleEmitter")
	emitter.Color = ColorSequence.new(Color3.fromRGB(190, 160, 110))
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.3),
		NumberSequenceKeypoint.new(1, 1),
	})
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 2),
		NumberSequenceKeypoint.new(0.5, 6),
		NumberSequenceKeypoint.new(1, 3),
	})
	emitter.Texture = "rbxasset://textures/particles/smoke_main.dds"
	emitter.Lifetime = NumberRange.new(0.5, 1.2)
	emitter.Speed = NumberRange.new(10, 25)
	emitter.SpreadAngle = Vector2.new(45, 45)
	emitter.Rotation = NumberRange.new(0, 360)
	emitter.RotSpeed = NumberRange.new(-60, 60)
	emitter.Rate = 0
	emitter.LightEmission = 0.1
	emitter.LightInfluence = 0.8
	emitter.Drag = 3
	emitter.Parent = att

	emitter:Emit(30)

	task.delay(2, function()
		att:Destroy()
	end)
end

function GraviBowCharacterController:_setCharacterTransparency(alpha)
	local character = self._character
	if not character then return end

	for _, desc in ipairs(character:GetDescendants()) do
		if desc:IsA("BasePart") and desc.Name ~= "HumanoidRootPart" then
			desc.LocalTransparencyModifier = alpha
		end
	end
end

function GraviBowCharacterController:_updateCharacterVisibility()
	local dist = self._cameraController._distance
	if dist <= FADE_IN_START then
		self:_setCharacterTransparency(1)
	elseif dist >= FADE_IN_END then
		self:_setCharacterTransparency(0)
	else
		local t = (dist - FADE_IN_START) / (FADE_IN_END - FADE_IN_START)
		self:_setCharacterTransparency(1 - t)
	end
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
