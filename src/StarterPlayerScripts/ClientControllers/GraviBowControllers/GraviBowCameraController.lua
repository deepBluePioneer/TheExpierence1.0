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
local TOUCH_SENSITIVITY = 0.18
local PINCH_ZOOM_SPEED = 0.08
local PITCH_MIN = -80
local PITCH_MAX = 80
local MIN_DISTANCE = 0
local MAX_DISTANCE = 30
local SNAKE_MIN_DISTANCE = 10
local DEFAULT_MOBILE_DISTANCE = 15
local SCROLL_STEP = 3
local FOV_FIRST_PERSON = 55
local FOV_THIRD_PERSON = 70
local FOV_BLEND_DISTANCE = 6

local GraviBowCameraController = Knit.CreateController({
	Name = "GraviBowCameraController",

	CameraLookOnSurface = Vector3.new(0, 0, -1),
	CameraRightOnSurface = Vector3.new(1, 0, 0),
	Pitch = 0,

	_trove = nil,
	_characterTrove = nil,
	_yaw = 0,
	_pitch = 15,
	_distance = MIN_DISTANCE,
	_prevUp = Vector3.new(0, 1, 0),
	_refForward = Vector3.new(0, 0, -1),
	_shaker = nil,
	_shakeActive = false,
	_shakeOffset = CFrame.new(),
	_spectatingDeath = false,
	_digTarget = nil,
	_digLerpAlpha = 0,
	_isMobile = false,
	_activeTouches = {},
	_cameraTouchId = nil,
	_lastPinchDistance = nil,
})

function GraviBowCameraController:KnitInit()
	self._trove = Trove.new()
end

function GraviBowCameraController:KnitStart()
	self._gravityController = Knit.GetController("GraviBowGravityController")
	self._toolController = Knit.GetController("GraviBowToolController")
	self._matchController = Knit.GetController("GraviBowMatchController")

	self._isMobile = UserInputService.TouchEnabled
	self._mouseLocked = not self._isMobile

	if self._isMobile then
		self._distance = DEFAULT_MOBILE_DISTANCE
	end

	self._trove:Add(UserInputService.InputBegan:Connect(function(input, processed)
		if input.UserInputType == Enum.UserInputType.Touch then
			if not processed then
				self:_handleTouchBegan(input)
			end
			return
		end
		if processed then return end
		if input.KeyCode == Enum.KeyCode.U then
			self._mouseLocked = not self._mouseLocked
			UserInputService.MouseBehavior = self._mouseLocked
				and Enum.MouseBehavior.LockCenter
				or Enum.MouseBehavior.Default
			UserInputService.MouseIconEnabled = not self._mouseLocked
		end
	end), "Disconnect")

	self._trove:Add(UserInputService.InputChanged:Connect(function(input, processed)
		if input.UserInputType == Enum.UserInputType.Touch then
			if not processed then
				self:_handleTouchChanged(input)
			end
			return
		end
		if processed then return end
		if input.UserInputType == Enum.UserInputType.MouseMovement then
			if self._mouseLocked then
				self._yaw = self._yaw + input.Delta.X * MOUSE_SENSITIVITY
				self._pitch = math.clamp(self._pitch - input.Delta.Y * MOUSE_SENSITIVITY, PITCH_MIN, PITCH_MAX)
			end
		elseif input.UserInputType == Enum.UserInputType.MouseWheel then
			if not (self._toolController and self._toolController:IsRadialOpen()) then
				self._distance = math.clamp(self._distance - input.Position.Z * SCROLL_STEP, MIN_DISTANCE, MAX_DISTANCE)
			end
		end
	end), "Disconnect")

	self._trove:Add(UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch then
			self:_handleTouchEnded(input)
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
	if not self._isMobile then
		UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
		UserInputService.MouseIconEnabled = false
	end

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
		if not self._isMobile then
			UserInputService.MouseBehavior = Enum.MouseBehavior.Default
			UserInputService.MouseIconEnabled = true
		end
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

function GraviBowCameraController:_handleTouchBegan(input)
	self._activeTouches[input] = true
	if not self._cameraTouchId then
		self._cameraTouchId = input
	end
	self._lastPinchDistance = nil
end

function GraviBowCameraController:_handleTouchChanged(input)
	if not self._activeTouches[input] then return end

	local touchCount = 0
	for _ in pairs(self._activeTouches) do touchCount += 1 end

	if touchCount >= 2 then
		self:_updatePinchZoom()
	elseif self._cameraTouchId == input then
		self._yaw = self._yaw + input.Delta.X * TOUCH_SENSITIVITY
		self._pitch = math.clamp(self._pitch - input.Delta.Y * TOUCH_SENSITIVITY, PITCH_MIN, PITCH_MAX)
	end
end

function GraviBowCameraController:_handleTouchEnded(input)
	self._activeTouches[input] = nil
	if self._cameraTouchId == input then
		self._cameraTouchId = nil
		for touch in pairs(self._activeTouches) do
			self._cameraTouchId = touch
			break
		end
	end
	self._lastPinchDistance = nil
end

function GraviBowCameraController:_updatePinchZoom()
	local touches = {}
	for touch in pairs(self._activeTouches) do
		table.insert(touches, touch)
		if #touches == 2 then break end
	end
	if #touches < 2 then return end

	local dist = (touches[1].Position - touches[2].Position).Magnitude
	if self._lastPinchDistance then
		local delta = dist - self._lastPinchDistance
		self._distance = math.clamp(self._distance - delta * PINCH_ZOOM_SPEED, MIN_DISTANCE, MAX_DISTANCE)
	end
	self._lastPinchDistance = dist
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
	if self._matchController and self._matchController:IsLocalPlayerSnake() then
		if self._distance < SNAKE_MIN_DISTANCE then
			self._distance = SNAKE_MIN_DISTANCE
		end
	end

	local gravityDir = self._gravityController:GetSmoothedGravityDirection()
	local upDir = -gravityDir

	local digTarget = self._digTarget
	if digTarget then
		self._digLerpAlpha = math.min(self._digLerpAlpha + 3.5 * (1 / 60), 1)
		local t = self._digLerpAlpha
		t = t * t * (3 - 2 * t)

		upDir = self._prevUp:Lerp(digTarget.upDir, t)
		if upDir.Magnitude > 0.001 then
			upDir = upDir.Unit
		else
			upDir = digTarget.upDir
		end
	end

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
	if digTarget then
		local t = self._digLerpAlpha
		t = t * t * (3 - 2 * t)
		focusPos = focusPos:Lerp(digTarget.position, t)
	end

	local camRight = camForward:Cross(upDir)
	if camRight.Magnitude < 0.001 then
		camRight = rotatedRight
	end
	camRight = camRight.Unit
	local camUp = camRight:Cross(camForward).Unit

	local eyePos = focusPos - camForward * self._distance

	if self._distance > 0.5 then
		local camFilter = { hrp.Parent }
		local snakeBodies = Workspace:FindFirstChild("SnakeBodies")
		if snakeBodies then table.insert(camFilter, snakeBodies) end
		local npcFolder = Workspace:FindFirstChild("GraviNPCs")
		if npcFolder then table.insert(camFilter, npcFolder) end
		local gravZones = Workspace:FindFirstChild("GravityZones")
		if gravZones then table.insert(camFilter, gravZones) end
		local tpFolder = Workspace:FindFirstChild("TerrainPlanets")
		if tpFolder then table.insert(camFilter, tpFolder) end
		local structures = Workspace:FindFirstChild("Structures")
		if structures then table.insert(camFilter, structures) end

		local rayParams = RaycastParams.new()
		rayParams.FilterDescendantsInstances = camFilter
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

	local fovAlpha = math.clamp(self._distance / FOV_BLEND_DISTANCE, 0, 1)
	camera.FieldOfView = FOV_FIRST_PERSON + (FOV_THIRD_PERSON - FOV_FIRST_PERSON) * fovAlpha

	self.CameraLookOnSurface = (rotatedForward - upDir * rotatedForward:Dot(upDir)).Unit
	self.CameraRightOnSurface = (rotatedRight - upDir * rotatedRight:Dot(upDir)).Unit
	self.Pitch = self._pitch
end

function GraviBowCameraController:SetDigTarget(exitPos, exitUpDir)
	self._digTarget = {
		position = exitPos,
		upDir = exitUpDir,
	}
	self._digLerpAlpha = 0
end

function GraviBowCameraController:ClearDigTarget()
	self._digTarget = nil
	self._digLerpAlpha = 0
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
