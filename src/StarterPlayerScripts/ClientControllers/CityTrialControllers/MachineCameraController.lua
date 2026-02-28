local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Packages = ReplicatedStorage.Packages
local Knit = require(Packages.Knit)
local Trove = require(Packages.Trove)
local Shake = require(Packages.Shake)

local MachinePhysicsConfig = require(ReplicatedStorage.Source.MachinePhysicsConfig)

local LocalPlayer = Players.LocalPlayer

local FOLLOW_OFFSET = Vector3.new(0, 5, 12)
local LOOK_AHEAD = 4
local SMOOTH_SPEED = 12
local CLIP_OFFSET = 1
local BASE_FOV = 70
local TURN_FOV_INCREASE = 3
local TURN_FOV_SPEED = 6

local SNAP_BACK_SPEED = 6
local FREE_LOOK_SENSITIVITY = 0.003
local SPECTATOR_SWITCH_COOLDOWN = 0.3

local MachineCameraController = Knit.CreateController({
	Name = "MachineCameraController",

	_trove = nil,
	_renderConn = nil,

	_currentCFrame = CFrame.new(),
	_currentFOV = BASE_FOV,
	_targetFOV = BASE_FOV,

	_freeLookActive = false,
	_freeLookYaw = 0,
	_freeLookPitch = 0,

	_spectating = false,
	_spectateTarget = nil,
	_spectateIndex = 0,
	_spectateSwitchCooldown = 0,

	_shaker = nil,
	_shakeOffset = CFrame.new(),

	_rayParams = nil,
	_machineController = nil,
})

----------------------------------------------------------------
-- Lifecycle
----------------------------------------------------------------

function MachineCameraController:KnitStart()
	self._trove = Trove.new()

	self._shaker = nil
	self._shakeActive = false

	self._rayParams = RaycastParams.new()
	self._rayParams.FilterType = Enum.RaycastFilterType.Exclude
	self._rayParams.FilterDescendantsInstances = {}

	task.spawn(function()
		self._machineController = Knit.GetController("MachineController")
		self:_waitForMachine()
	end)
end

function MachineCameraController:_waitForMachine()
	while not self._machineController:GetMachineModel() do
		task.wait(0.25)
	end

	self:_updateRayParams()
	self:_disableDefaultCamera()
	self:_startRenderLoop()
	self:_bindInputs()

	self._machineController.StateChanged:Connect(function(newState)
		if newState == "DEAD" then
			self:_enterSpectatorMode()
		elseif newState == "DRIVING" and self._spectating then
			self:_exitSpectatorMode()
		elseif newState == "STUNNED" then
			self:TriggerShake(0.4, 0.5)
		end
	end)

	print("[MachineCameraController] Camera active")
end

function MachineCameraController:_disableDefaultCamera()
	local camera = Workspace.CurrentCamera
	camera.CameraType = Enum.CameraType.Scriptable
end

function MachineCameraController:_updateRayParams()
	local filterList = {}

	local machinesFolder = Workspace:FindFirstChild("CityTrialMachines")
	if machinesFolder then
		table.insert(filterList, machinesFolder)
	end

	for _, player in Players:GetPlayers() do
		if player.Character then
			table.insert(filterList, player.Character)
		end
	end

	self._rayParams.FilterDescendantsInstances = filterList
end

----------------------------------------------------------------
-- Input bindings (free-look + spectator)
----------------------------------------------------------------

function MachineCameraController:_bindInputs()
	self._trove:Add(UserInputService.InputBegan:Connect(function(input, processed)
		if processed then return end

		if input.UserInputType == Enum.UserInputType.MouseButton2 then
			self._freeLookActive = true
			UserInputService.MouseBehavior = Enum.MouseBehavior.LockCurrentPosition
		end

		if self._spectating then
			if input.KeyCode == Enum.KeyCode.E or input.KeyCode == Enum.KeyCode.ButtonR1 then
				self:_cycleSpectateTarget(1)
			elseif input.KeyCode == Enum.KeyCode.Q or input.KeyCode == Enum.KeyCode.ButtonL1 then
				self:_cycleSpectateTarget(-1)
			end
		end
	end), "Disconnect")

	self._trove:Add(UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton2 then
			self._freeLookActive = false
			UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		end
	end), "Disconnect")

	self._trove:Add(UserInputService.InputChanged:Connect(function(input)
		if not self._freeLookActive then return end

		if input.UserInputType == Enum.UserInputType.MouseMovement then
			self._freeLookYaw = self._freeLookYaw - input.Delta.X * FREE_LOOK_SENSITIVITY
			self._freeLookPitch = math.clamp(
				self._freeLookPitch - input.Delta.Y * FREE_LOOK_SENSITIVITY,
				-math.rad(60),
				math.rad(30)
			)
		end

		if input.KeyCode == Enum.KeyCode.Thumbstick2 then
			self._freeLookYaw = self._freeLookYaw - input.Position.X * FREE_LOOK_SENSITIVITY * 5
			self._freeLookPitch = math.clamp(
				self._freeLookPitch - input.Position.Y * FREE_LOOK_SENSITIVITY * 5,
				-math.rad(60),
				math.rad(30)
			)
		end
	end), "Disconnect")
end

----------------------------------------------------------------
-- Render loop
----------------------------------------------------------------

function MachineCameraController:_startRenderLoop()
	self._renderConn = RunService.RenderStepped:Connect(function(dt)
		self:_updateCamera(dt)
	end)

	self._trove:Add(self._renderConn)
end

function MachineCameraController:_updateCamera(dt)
	local camera = Workspace.CurrentCamera
	if not camera then return end

	local targetCFrame, targetPos
	local cameraState

	if self._spectating and self._spectateTarget then
		local targetModel = self:_getSpectateModel()
		if targetModel and targetModel.PrimaryPart then
			local rootCF = targetModel.PrimaryPart.CFrame
			local velocity = targetModel.PrimaryPart.AssemblyLinearVelocity
			targetCFrame = rootCF
			cameraState = {
				rootCFrame = rootCF,
				velocity = velocity,
				isBoosting = false,
				isStunned = false,
				isDead = false,
				currentSpeed = velocity.Magnitude,
			}
		end
	else
		cameraState = self._machineController:GetCameraState()
		targetCFrame = cameraState.rootCFrame
	end

	if not targetCFrame then return end

	if not self._freeLookActive then
		self._freeLookYaw = self._freeLookYaw * (1 - math.min(SNAP_BACK_SPEED * dt, 1))
		self._freeLookPitch = self._freeLookPitch * (1 - math.min(SNAP_BACK_SPEED * dt, 1))
	end

	local freeLookRotation = CFrame.Angles(self._freeLookPitch, self._freeLookYaw, 0)

	-- When airborne and pitched, pull the camera back a bit more and raise look target
	local offset = FOLLOW_OFFSET
	local lookAhead = LOOK_AHEAD
	if cameraState and not cameraState.grounded and math.abs(cameraState.pitch or 0) > 0.05 then
		local pitchFactor = math.abs(cameraState.pitch) / math.rad(MachinePhysicsConfig.airMaxPitch)
		offset = offset + Vector3.new(0, 2 * pitchFactor, 4 * pitchFactor)
		lookAhead = lookAhead + 4 * pitchFactor
	end

	local behind = targetCFrame * freeLookRotation * CFrame.new(offset)
	local lookTarget = targetCFrame.Position + targetCFrame.LookVector * lookAhead

	local desiredCFrame = CFrame.lookAt(behind.Position, lookTarget)

	local clippedPos = self:_clipCamera(targetCFrame.Position, desiredCFrame.Position)
	desiredCFrame = CFrame.lookAt(clippedPos, lookTarget)

	self._currentCFrame = self._currentCFrame:Lerp(desiredCFrame, math.min(SMOOTH_SPEED * dt, 1))

	local fovTarget = BASE_FOV
	if cameraState then
		if cameraState.isBoosting then
			fovTarget = fovTarget + MachinePhysicsConfig.boostFOVIncrease
		end
		local steerAbs = math.abs(cameraState.steer or 0)
		if steerAbs > 0.05 then
			fovTarget = fovTarget + steerAbs * TURN_FOV_INCREASE
		end
	end
	self._targetFOV = fovTarget
	self._currentFOV = self._currentFOV + (self._targetFOV - self._currentFOV) * math.min(TURN_FOV_SPEED * dt, 1)

	self._shakeOffset = CFrame.new()
	if self._shaker and self._shakeActive then
		local pos, rot, completed = self._shaker:Update()
		if pos then
			self._shakeOffset = CFrame.new(pos) * CFrame.Angles(rot.X, rot.Y, rot.Z)
		end
		if completed then
			self._shakeActive = false
		end
	end

	camera.CFrame = self._currentCFrame * self._shakeOffset
	camera.FieldOfView = self._currentFOV
end

function MachineCameraController:_clipCamera(targetPos, cameraPos)
	self:_updateRayParams()

	local direction = cameraPos - targetPos
	local distance = direction.Magnitude

	local result = Workspace:Raycast(targetPos, direction, self._rayParams)
	if result then
		local hitDist = (result.Position - targetPos).Magnitude
		if hitDist < distance then
			return targetPos + direction.Unit * (hitDist - CLIP_OFFSET)
		end
	end

	return cameraPos
end

----------------------------------------------------------------
-- Spectator mode
----------------------------------------------------------------

function MachineCameraController:_enterSpectatorMode()
	self._spectating = true
	self._spectateIndex = 0
	self:_cycleSpectateTarget(1)
	print("[MachineCameraController] Entered spectator mode")
end

function MachineCameraController:_exitSpectatorMode()
	self._spectating = false
	self._spectateTarget = nil
	print("[MachineCameraController] Exited spectator mode")
end

function MachineCameraController:_getSpectatablePlayers()
	local result = {}
	local machinesFolder = Workspace:FindFirstChild("CityTrialMachines")
	if not machinesFolder then return result end

	for _, model in machinesFolder:GetChildren() do
		local ownerUserId = model:GetAttribute("OwnerUserId")
		if ownerUserId and ownerUserId ~= LocalPlayer.UserId and model.PrimaryPart then
			local player = Players:GetPlayerByUserId(ownerUserId)
			if player then
				table.insert(result, { player = player, model = model })
			end
		end
	end

	return result
end

function MachineCameraController:_cycleSpectateTarget(direction)
	if self._spectateSwitchCooldown > 0 then return end
	self._spectateSwitchCooldown = SPECTATOR_SWITCH_COOLDOWN

	task.delay(SPECTATOR_SWITCH_COOLDOWN, function()
		self._spectateSwitchCooldown = 0
	end)

	local targets = self:_getSpectatablePlayers()
	if #targets == 0 then
		self._spectateTarget = nil
		return
	end

	self._spectateIndex = ((self._spectateIndex - 1 + direction) % #targets) + 1
	self._spectateTarget = targets[self._spectateIndex]

	if self._spectateTarget then
		print("[MachineCameraController] Spectating: " .. self._spectateTarget.player.Name)
	end
end

function MachineCameraController:_getSpectateModel()
	if not self._spectateTarget then return nil end

	local model = self._spectateTarget.model
	if model and model.Parent and model.PrimaryPart then
		return model
	end

	self:_cycleSpectateTarget(1)
	return nil
end

----------------------------------------------------------------
-- Public API
----------------------------------------------------------------

function MachineCameraController:TriggerShake(amplitude, duration)
	local shaker = Shake.new()
	shaker.Amplitude = amplitude or 1
	shaker.Frequency = 0.1
	shaker.FadeInTime = 0
	shaker.FadeOutTime = duration or 0.5
	shaker.PositionInfluence = Vector3.new(0.5, 0.5, 0.5)
	shaker.RotationInfluence = Vector3.new(0.1, 0.1, 0.1)

	self._shaker = shaker
	self._shakeActive = true
	shaker:Start()
end

function MachineCameraController:IsSpectating()
	return self._spectating
end

function MachineCameraController:GetSpectateTarget()
	return self._spectateTarget and self._spectateTarget.player or nil
end

return MachineCameraController
