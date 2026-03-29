local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Packages = ReplicatedStorage.Packages
local Knit = require(Packages.Knit)
local Trove = require(Packages.Trove)
local Shake = require(Packages.Shake)

local FOLLOW_OFFSET = Vector3.new(0, 8, 14)
local LOOK_AHEAD = 60
local SMOOTH_SPEED = 24
local BASE_FOV = 70
local BOOST_FOV = 95
local HYPER_FOV = 110
local FOV_ATTACK_SPEED = 12
local FOV_RECOVER_SPEED = 3

local LATERAL_STIFFNESS = 80
local LATERAL_DAMPING = 9

local LakelandCameraController = Knit.CreateController({
	Name = "LakelandCameraController",

	_trove = nil,
	_renderConn = nil,
	_active = false,
	_currentCFrame = CFrame.new(),
	_currentFOV = BASE_FOV,
	_targetFOV = BASE_FOV,
	_raceController = nil,
	_activeShakes = {},
	_zoomPunchOffset = 0,
	_zoomPunchVelocity = 0,
	_deathZoomActive = false,
	_deathZoomTarget = 0,
	_deathZoomElapsed = 0,
	_deathZoomDuration = 1.5,
	_lateralOffset = 0,
	_lateralVelocity = 0,
	_lastDesiredX = 0,
	_hyperdriveBlend = 0,
})

function LakelandCameraController:KnitInit()
	self._trove = Trove.new()
end

function LakelandCameraController:KnitStart()
	self._raceController = Knit.GetController("LakelandRaceController")

	local gameController = Knit.GetController("LakelandGameController")
	gameController.GameStateChanged:Connect(function(newState)
		if newState == "PLAYING" or newState == "GAME_OVER" then
			self:_activate()
		elseif newState == "LOBBY" then
			self:_deactivate()
		end
	end)
end

function LakelandCameraController:_activate()
	if self._active then return end
	self._active = true

	local camera = Workspace.CurrentCamera
	self._currentCFrame = CFrame.new()
	self._lateralOffset = 0
	self._lateralVelocity = 0
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

	for _, s in ipairs(self._activeShakes) do
		s:Stop()
	end
	table.clear(self._activeShakes)

	self._trove:Clean()

	local camera = Workspace.CurrentCamera
	camera.CameraType = Enum.CameraType.Custom

	print("[LakelandCameraController] Camera released")
end

function LakelandCameraController:ShakeCamera(amplitude, frequency, fadeIn, sustainTime, fadeOut, posInfluence, rotInfluence)
	local shake = Shake.new()
	shake.Amplitude = amplitude
	shake.Frequency = frequency
	shake.FadeInTime = fadeIn
	shake.SustainTime = sustainTime
	shake.FadeOutTime = fadeOut
	shake.PositionInfluence = posInfluence or Vector3.one
	shake.RotationInfluence = rotInfluence or Vector3.new(0.1, 0.1, 0.1)
	shake:Start()
	table.insert(self._activeShakes, shake)
	return shake
end

function LakelandCameraController:ZoomPunch(amount)
	self._zoomPunchOffset = -(amount or 8)
	self._zoomPunchVelocity = 0
end

function LakelandCameraController:DeathZoom(duration)
	self._deathZoomActive = true
	self._deathZoomTarget = -25
	self._deathZoomElapsed = 0
	self._deathZoomDuration = duration or 1.5
end

function LakelandCameraController:ResetZoom()
	self._deathZoomActive = false
end

function LakelandCameraController:SetHyperdriveFOV(blend)
	local prev = self._hyperdriveBlend
	self._hyperdriveBlend = blend or 0
	if prev > 0 and self._hyperdriveBlend == 0 then
		self._currentFOV = BASE_FOV
	end
end

function LakelandCameraController:_update(dt)
	local camera = Workspace.CurrentCamera

	local machineCF = self._raceController:GetMachineCFrame()
	if machineCF == CFrame.new() then return end

	local behind = machineCF * CFrame.new(FOLLOW_OFFSET)
	local lookTarget = machineCF.Position + machineCF.LookVector * LOOK_AHEAD
	local desiredCFrame = CFrame.lookAt(behind.Position, lookTarget)

	if self._currentCFrame == CFrame.new() then
		self._currentCFrame = desiredCFrame
		self._lastDesiredX = desiredCFrame.Position.X
		self._lateralOffset = 0
		self._lateralVelocity = 0
	end

	local desiredX = desiredCFrame.Position.X
	local xError = desiredX - (self._lastDesiredX + self._lateralOffset)
	self._lateralVelocity = self._lateralVelocity + (LATERAL_STIFFNESS * xError - LATERAL_DAMPING * self._lateralVelocity) * dt
	self._lateralOffset = self._lateralOffset + self._lateralVelocity * dt
	self._lastDesiredX = desiredX

	local smoothAlpha = math.clamp(SMOOTH_SPEED * dt, 0, 1)
	local lerpedCFrame = self._currentCFrame:Lerp(desiredCFrame, smoothAlpha)

	local springPos = Vector3.new(
		desiredX + self._lateralOffset - desiredX,
		lerpedCFrame.Position.Y - desiredCFrame.Position.Y,
		0
	)
	local finalPos = desiredCFrame.Position + Vector3.new(self._lateralOffset, springPos.Y, 0)
	self._currentCFrame = CFrame.lookAt(
		Vector3.new(finalPos.X, lerpedCFrame.Position.Y, lerpedCFrame.Position.Z),
		lookTarget + Vector3.new(self._lateralOffset * 0.3, 0, 0)
	)

	local totalPos = Vector3.zero
	local totalRot = Vector3.zero
	for i = #self._activeShakes, 1, -1 do
		local shake = self._activeShakes[i]
		local pos, rot, isDone = shake:Update()
		totalPos = totalPos + pos
		totalRot = totalRot + rot
		if isDone then
			shake:Destroy()
			table.remove(self._activeShakes, i)
		end
	end

	local shaken = self._currentCFrame * CFrame.new(totalPos) * CFrame.Angles(totalRot.X, totalRot.Y, totalRot.Z)
	camera.CFrame = shaken

	local boosting = self._raceController:IsBoosting()
	local baseFOV = boosting and BOOST_FOV or BASE_FOV
	if self._hyperdriveBlend > 0 then
		self._currentFOV = baseFOV + (HYPER_FOV - baseFOV) * self._hyperdriveBlend
	else
		self._targetFOV = baseFOV
		local fovSpeed = (self._targetFOV > self._currentFOV) and FOV_ATTACK_SPEED or FOV_RECOVER_SPEED
		self._currentFOV = self._currentFOV + (self._targetFOV - self._currentFOV) * math.min(fovSpeed * dt, 1)
	end

	if self._deathZoomActive then
		self._deathZoomElapsed = (self._deathZoomElapsed or 0) + dt
		local frac = math.clamp(self._deathZoomElapsed / self._deathZoomDuration, 0, 1)
		local eased = frac * frac * (3 - 2 * frac)
		self._zoomPunchOffset = self._deathZoomTarget * eased
		self._zoomPunchVelocity = 0
	else
		local stiffness = 180
		local damping = 14
		self._zoomPunchVelocity = self._zoomPunchVelocity + (-stiffness * self._zoomPunchOffset - damping * self._zoomPunchVelocity) * dt
		self._zoomPunchOffset = self._zoomPunchOffset + self._zoomPunchVelocity * dt
		if math.abs(self._zoomPunchOffset) < 0.05 and math.abs(self._zoomPunchVelocity) < 0.1 then
			self._zoomPunchOffset = 0
			self._zoomPunchVelocity = 0
		end
	end

	camera.FieldOfView = self._currentFOV + self._zoomPunchOffset
end

return LakelandCameraController
