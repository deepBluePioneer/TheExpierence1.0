local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Packages = ReplicatedStorage.Packages
local Knit = require(Packages.Knit)
local Trove = require(Packages.Trove)
local Shake = require(Packages.Shake)

local LocalPlayer = Players.LocalPlayer

local MOUSE_SENSITIVITY = 0.3
local PITCH_MIN = -80
local PITCH_MAX = 80
local FIRST_PERSON_DISTANCE = 0
local THIRD_PERSON_DISTANCE = 20

local GraviBowCameraController = Knit.CreateController({
	Name = "GraviBowCameraController",

	CameraLookOnSurface = Vector3.new(0, 0, -1),
	CameraRightOnSurface = Vector3.new(1, 0, 0),
	Pitch = 0,

	_trove = nil,
	_characterTrove = nil,
	_yaw = 0,
	_pitch = 15,
	_distance = FIRST_PERSON_DISTANCE,
	_prevUp = Vector3.new(0, 1, 0),
	_refForward = Vector3.new(0, 0, -1),
	_shaker = nil,
	_shakeActive = false,
	_shakeOffset = CFrame.new(),
	_spectatingDeath = false,
})

function GraviBowCameraController:KnitInit()
	self._trove = Trove.new()
end

function GraviBowCameraController:KnitStart()
	self._gravityController = Knit.GetController("GraviBowGravityController")
	self._mouseLocked = true

	self._trove:Add(UserInputService.InputBegan:Connect(function(input, processed)
		if processed then return end
		if input.KeyCode == Enum.KeyCode.U then
			self._mouseLocked = not self._mouseLocked
			UserInputService.MouseBehavior = self._mouseLocked
				and Enum.MouseBehavior.LockCenter
				or Enum.MouseBehavior.Default
		elseif input.KeyCode == Enum.KeyCode.Y then
			if self._distance == FIRST_PERSON_DISTANCE then
				self._distance = THIRD_PERSON_DISTANCE
			else
				self._distance = FIRST_PERSON_DISTANCE
			end
		end
	end), "Disconnect")

	self._trove:Add(UserInputService.InputChanged:Connect(function(input, processed)
		if processed then return end
		if not self._mouseLocked then return end
		if input.UserInputType == Enum.UserInputType.MouseMovement then
			self._yaw = self._yaw + input.Delta.X * MOUSE_SENSITIVITY
			self._pitch = math.clamp(self._pitch - input.Delta.Y * MOUSE_SENSITIVITY, PITCH_MIN, PITCH_MAX)
		end
	end), "Disconnect")

	self._trove:Add(LocalPlayer.CharacterAdded:Connect(function(character)
		self:_onCharacterAdded(character)
	end), "Disconnect")

	if LocalPlayer.Character then
		self:_onCharacterAdded(LocalPlayer.Character)
	end

end

function GraviBowCameraController:_onCharacterAdded(character)
	if self._spectatingDeath then return end

	if self._characterTrove then
		self._characterTrove:Clean()
	end
	self._characterTrove = self._trove:Extend()

	local hrp = character:WaitForChild("HumanoidRootPart", 10)
	local head = character:WaitForChild("Head", 10)
	local humanoid = character:WaitForChild("Humanoid", 10)
	if not hrp then return end

	local camera = Workspace.CurrentCamera
	camera.CameraType = Enum.CameraType.Scriptable
	UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter

	local initUp = -self._gravityController:GetSmoothedGravityDirection()
	self._prevUp = initUp
	local initForward = hrp.CFrame.LookVector
	initForward = (initForward - initUp * initForward:Dot(initUp))
	if initForward.Magnitude < 0.001 then
		initForward = Vector3.new(0, 0, -1)
	end
	self._refForward = initForward.Unit

	local CAM_RENDER_NAME = "GraviBowCamera"
	RunService:BindToRenderStep(CAM_RENDER_NAME, Enum.RenderPriority.Camera.Value, function(_dt)
		camera.CameraType = Enum.CameraType.Scriptable
		self:_updateCamera(hrp, head, camera)
	end)

	self._characterTrove:Add(function()
		RunService:UnbindFromRenderStep(CAM_RENDER_NAME)
		camera.CameraType = Enum.CameraType.Custom
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
	end)

	if humanoid then
		self._characterTrove:Add(humanoid.Died:Connect(function()
			self._spectatingDeath = true
			task.delay(3, function()
				self._spectatingDeath = false
				if LocalPlayer.Character and LocalPlayer.Character ~= character then
					self:_onCharacterAdded(LocalPlayer.Character)
				end
			end)
		end), "Disconnect")
	end
end

function GraviBowCameraController:_fromToRotation(from, to)
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

function GraviBowCameraController:_updateCamera(hrp, head, camera)
	local gravityDir = self._gravityController:GetSmoothedGravityDirection()
	local upDir = -gravityDir

	local deltaRot = self:_fromToRotation(self._prevUp, upDir)
	self._refForward = (deltaRot * self._refForward)
	self._prevUp = upDir

	local projected = self._refForward - upDir * self._refForward:Dot(upDir)
	if projected.Magnitude < 0.001 then
		projected = Vector3.new(0, 0, -1) - upDir * Vector3.new(0, 0, -1):Dot(upDir)
		if projected.Magnitude < 0.001 then
			projected = Vector3.new(1, 0, 0) - upDir * Vector3.new(1, 0, 0):Dot(upDir)
		end
	end
	self._refForward = projected.Unit

	local refRight = self._refForward:Cross(upDir).Unit

	local yawRad = math.rad(self._yaw)
	local pitchRad = math.rad(self._pitch)

	local rotatedForward = (self._refForward * math.cos(yawRad) + refRight * math.sin(yawRad)).Unit
	local rotatedRight = rotatedForward:Cross(upDir).Unit

	local camForward = (rotatedForward * math.cos(pitchRad) + upDir * math.sin(pitchRad)).Unit

	local focusPos = head and head.Position or hrp.Position
	local camRight = camForward:Cross(upDir)
	if camRight.Magnitude < 0.001 then
		camRight = rotatedRight
	end
	camRight = camRight.Unit
	local camUp = camRight:Cross(camForward).Unit

	local eyePos = focusPos - camForward * self._distance

	if self._distance > 0.5 then
		local rayParams = RaycastParams.new()
		rayParams.FilterDescendantsInstances = { hrp.Parent }
		rayParams.FilterType = Enum.RaycastFilterType.Exclude
		local ray = Workspace:Raycast(focusPos, (eyePos - focusPos).Unit * self._distance, rayParams)
		if ray then
			eyePos = ray.Position + (focusPos - eyePos).Unit * 0.5
		end
	end

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

	camera.CFrame = CFrame.fromMatrix(eyePos, camRight, camUp, -camForward) * self._shakeOffset
	camera.Focus = CFrame.new(focusPos)

	self.CameraLookOnSurface = (rotatedForward - upDir * rotatedForward:Dot(upDir)).Unit
	self.CameraRightOnSurface = (rotatedRight - upDir * rotatedRight:Dot(upDir)).Unit
	self.Pitch = self._pitch
end

function GraviBowCameraController:TriggerShake(amplitude, duration)
	local shaker = Shake.new()
	shaker.Amplitude = amplitude or 0.6
	shaker.Frequency = 0.1
	shaker.FadeInTime = 0
	shaker.FadeOutTime = duration or 0.4
	shaker.PositionInfluence = Vector3.new(0.3, 0.3, 0.3)
	shaker.RotationInfluence = Vector3.new(0.08, 0.08, 0.08)

	self._shaker = shaker
	self._shakeActive = true
	shaker:Start()
end

return GraviBowCameraController
