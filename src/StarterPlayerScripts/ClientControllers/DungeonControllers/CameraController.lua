-- CameraController.lua
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Knit = require(game:GetService("ReplicatedStorage").Packages.Knit)

local CameraController = Knit.CreateController {
	Name = "CameraController"
}

local LocalPlayer = Players.LocalPlayer
local Camera = workspace.CurrentCamera

-- Internal State
local smoothedCameraCFrame = nil
local lateralOffset = 0
local currentFOV = Camera.FieldOfView
local defaultFOV = 45
local zoomedFOV = 42
local currentTilt = 0
local smoothingSpeed = 15
local followConnection = nil

-- Public flag that can be set by other controllers
CameraController.IsCharging = false

function CameraController:StartFollowing(seat, rootPart)
	if followConnection then
		RunService:UnbindFromRenderStep("FollowVehicleCamera")
	end

	local function followCamera(dt)
		if not seat.Occupant or seat.Occupant.Parent ~= LocalPlayer.Character then
			Camera.CameraType = Enum.CameraType.Custom
			RunService:UnbindFromRenderStep("FollowVehicleCamera")
			smoothedCameraCFrame = nil
			Camera.FieldOfView = defaultFOV
			return
		end

		local renderCF = rootPart:GetRenderCFrame()
		local rootPosition = renderCF.Position
		local lookVector = renderCF.LookVector

		local flatLook = Vector3.new(lookVector.X, 0, lookVector.Z)
		if flatLook.Magnitude == 0 then
			flatLook = Vector3.new(0, 0, -1)
		end
		flatLook = flatLook.Unit

		local right = flatLook:Cross(Vector3.new(0, 1, 0)).Unit
		local up = right:Cross(flatLook).Unit
		local rootCFrame = CFrame.fromMatrix(rootPosition, right, up)

		local cameraHeight = 8
		local cameraDistance = 18

		local targetLateralOffset = 0
		if CameraController.IsCharging then
			if UserInputService:IsKeyDown(Enum.KeyCode.A) then
				targetLateralOffset = -5
			elseif UserInputService:IsKeyDown(Enum.KeyCode.D) then
				targetLateralOffset = 5
			end
		end
		lateralOffset += (targetLateralOffset - lateralOffset) * 0.15

		local cameraPos = rootCFrame.Position
			+ up * cameraHeight
			- flatLook * cameraDistance
			+ right * lateralOffset

		local lookTarget = cameraPos + flatLook
		local targetCFrame = CFrame.new(cameraPos, lookTarget)

		local targetTilt = math.rad(lateralOffset * -2.5)
		currentTilt += (targetTilt - currentTilt) * 0.50
		local tiltCFrame = CFrame.Angles(0, 0, currentTilt)

		local alpha = 1 - math.exp(-smoothingSpeed * dt)
		smoothedCameraCFrame = smoothedCameraCFrame
			and smoothedCameraCFrame:Lerp(targetCFrame * tiltCFrame, alpha)
			or (targetCFrame * tiltCFrame)

		Camera.CFrame = smoothedCameraCFrame

		local targetFOV = CameraController.IsCharging and zoomedFOV or defaultFOV
		currentFOV += (targetFOV - currentFOV) * 0.25
		Camera.FieldOfView = currentFOV
	end

	Camera.CameraType = Enum.CameraType.Scriptable
	RunService:BindToRenderStep("FollowVehicleCamera", Enum.RenderPriority.Camera.Value + 1, followCamera)
end

function CameraController:StopFollowing()
	RunService:UnbindFromRenderStep("FollowVehicleCamera")
	Camera.CameraType = Enum.CameraType.Custom
end
function CameraController:UpdateFixed(rootPart)
	local Camera = workspace.CurrentCamera
	if Camera.CameraType ~= Enum.CameraType.Scriptable then return end

	local renderCF = rootPart:GetRenderCFrame()
	local rootPosition = renderCF.Position
	local lookVector = renderCF.LookVector

	local flatLook = Vector3.new(lookVector.X, 0, lookVector.Z)
	if flatLook.Magnitude == 0 then
		flatLook = Vector3.new(0, 0, -1)
	end
	flatLook = flatLook.Unit

	local right = flatLook:Cross(Vector3.new(0, 1, 0)).Unit
	local up = right:Cross(flatLook).Unit
	local rootCFrame = CFrame.fromMatrix(rootPosition, right, up)

	local cameraHeight = 15
	local cameraDistance = 35
	local lateralOffset = 0 -- No side offset in fixed camera

	local cameraPos = rootCFrame.Position
		+ up * cameraHeight
		- flatLook * cameraDistance
		+ right * lateralOffset

	local lookTarget = cameraPos + flatLook
	local targetCFrame = CFrame.new(cameraPos, lookTarget)

	-- Tilt the camera downward
	local pitchAngle = math.rad(-10) -- Negative = tilt down
	Camera.CFrame = targetCFrame * CFrame.Angles(pitchAngle, 0, 0)
end







function CameraController:KnitStart()
	-- Add controller startup logic here if needed
end

function CameraController:KnitInit()
	-- Add controller initialization logic here if needed
end

return CameraController
