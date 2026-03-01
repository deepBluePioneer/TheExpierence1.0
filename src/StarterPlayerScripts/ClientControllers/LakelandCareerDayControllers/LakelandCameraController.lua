local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Packages = ReplicatedStorage.Packages
local Knit = require(Packages.Knit)
local Trove = require(Packages.Trove)

local FOLLOW_OFFSET = Vector3.new(0, 8, 14)
local LOOK_AHEAD = 60
local SMOOTH_SPEED = 50
local BASE_FOV = 70
local BOOST_FOV = 95
local FOV_ATTACK_SPEED = 12
local FOV_RECOVER_SPEED = 3

local LakelandCameraController = Knit.CreateController({
	Name = "LakelandCameraController",

	_trove = nil,
	_renderConn = nil,
	_active = false,
	_currentCFrame = CFrame.new(),
	_currentFOV = BASE_FOV,
	_targetFOV = BASE_FOV,
	_raceController = nil,
})

function LakelandCameraController:KnitInit()
	self._trove = Trove.new()
end

function LakelandCameraController:KnitStart()
	self._raceController = Knit.GetController("LakelandRaceController")

	local gameController = Knit.GetController("LakelandGameController")
	gameController.GameStateChanged:Connect(function(newState)
		if newState == "COUNTDOWN" or newState == "PLAYING" then
			self:_activate()
		else
			self:_deactivate()
		end
	end)
end

function LakelandCameraController:_activate()
	if self._active then return end
	self._active = true

	local camera = Workspace.CurrentCamera
	self._currentCFrame = camera.CFrame
	camera.CameraType = Enum.CameraType.Scriptable

	RunService:BindToRenderStep("LakelandCameraUpdate", Enum.RenderPriority.Camera.Value + 1, function(dt)
		self:_update(dt)
	end)
	self._renderConn = true
	self._trove:Add(function()
		if self._renderConn then
			RunService:UnbindFromRenderStep("LakelandCameraUpdate")
			self._renderConn = nil
		end
	end)

	print("[LakelandCameraController] Camera following machine")
end

function LakelandCameraController:_deactivate()
	if not self._active then return end
	self._active = false

	if self._renderConn then
		RunService:UnbindFromRenderStep("LakelandCameraUpdate")
		self._renderConn = nil
	end
	self._trove:Clean()

	local camera = Workspace.CurrentCamera
	camera.CameraType = Enum.CameraType.Custom

	print("[LakelandCameraController] Camera released")
end

function LakelandCameraController:_update(dt)
	local camera = Workspace.CurrentCamera

	local machineCF = self._raceController:GetMachineCFrame()
	if machineCF == CFrame.new() then return end

	local behind = machineCF * CFrame.new(FOLLOW_OFFSET)
	local lookTarget = machineCF.Position + machineCF.LookVector * LOOK_AHEAD

	local desiredCFrame = CFrame.lookAt(behind.Position, lookTarget)

	camera.CFrame = desiredCFrame

	local boosting = self._raceController:IsBoosting()
	self._targetFOV = boosting and BOOST_FOV or BASE_FOV

	local fovSpeed = (self._targetFOV > self._currentFOV) and FOV_ATTACK_SPEED or FOV_RECOVER_SPEED
	self._currentFOV = self._currentFOV + (self._targetFOV - self._currentFOV) * math.min(fovSpeed * dt, 1)
	camera.FieldOfView = self._currentFOV
end

return LakelandCameraController
