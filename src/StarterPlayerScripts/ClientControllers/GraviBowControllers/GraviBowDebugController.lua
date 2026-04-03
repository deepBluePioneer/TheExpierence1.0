local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Packages = ReplicatedStorage.Packages
local Knit = require(Packages.Knit)
local Trove = require(Packages.Trove)

local Gizmo
local ok, mod = pcall(require, Packages.imgizmo)
if ok then
	Gizmo = mod
	Gizmo.Init()
end

local LocalPlayer = Players.LocalPlayer

local RAY_LENGTH = 8

local COLOR_INPUT_DIR = Color3.fromRGB(0, 255, 100)
local COLOR_CHAR_FORWARD = Color3.fromRGB(255, 80, 80)
local COLOR_GRAVITY_DIR = Color3.fromRGB(100, 150, 255)
local COLOR_CAMERA_LOOK = Color3.fromRGB(255, 255, 0)
local COLOR_JUMP_VEC = Color3.fromRGB(255, 0, 255)
local COLOR_GROUND_NORMAL = Color3.fromRGB(0, 255, 255)

local GraviBowDebugController = Knit.CreateController({
	Name = "GraviBowDebugController",

	_trove = nil,
	_lastJumpDir = nil,
	_jumpStartDist = nil,
	_jumpPeakDist = nil,
	_jumpLat = nil,
	_jumpLon = nil,
	_wasGrounded = true,
	_lastJumpHeight = nil,
	_lastJumpLat = nil,
	_lastJumpLon = nil,
})

function GraviBowDebugController:KnitInit()
	self._trove = Trove.new()
end

function GraviBowDebugController:KnitStart()
	if not Gizmo then
		warn("[GraviBowDebugController] imgizmo not available -- debug gizmos disabled")
		return
	end

	self._gravityController = Knit.GetController("GraviBowGravityController")
	self._groundController = Knit.GetController("GraviBowGroundController")
	self._cameraController = Knit.GetController("GraviBowCameraController")
	self._characterController = Knit.GetController("GraviBowCharacterController")

	self._trove:Add(RunService.RenderStepped:Connect(function()
		self:_drawDebug()
	end), "Disconnect")

	self._trove:Add(UserInputService.JumpRequest:Connect(function()
		local gravityDir = self._gravityController.GravityDirection
		self._lastJumpDir = -gravityDir
	end), "Disconnect")

end

function GraviBowDebugController:_getInputWorldDir()
	local upDir = -self._gravityController.GravityDirection
	local forwardOnSurface = self._cameraController.CameraLookOnSurface
	local rightOnSurface = self._cameraController.CameraRightOnSurface

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

	if moveDir.Magnitude < 0.01 then
		return nil
	end
	moveDir = moveDir.Unit
	local worldDir = (rightOnSurface * moveDir.X + forwardOnSurface * -moveDir.Z)
	if worldDir.Magnitude < 0.001 then return nil end
	return worldDir.Unit
end

function GraviBowDebugController:_drawDebug()
	local character = LocalPlayer.Character
	if not character then return end
	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not hrp then return end

	local origin = hrp.Position
	local gravityDir = self._gravityController.GravityDirection
	local upDir = -gravityDir
	local charForward = hrp.CFrame.LookVector
	local camLook = self._cameraController.CameraLookOnSurface
	local inputWorldDir = self:_getInputWorldDir()
	local groundNormal = self._groundController.GroundNormal

	-- Gizmo lines disabled
	local _ = charForward, camLook, inputWorldDir, groundNormal

	local sphereCenter = self._gravityController._sphereCenter
	local offset = origin - sphereCenter
	local dist = offset.Magnitude
	local lat = math.deg(math.asin(math.clamp(offset.Y / math.max(dist, 0.001), -1, 1)))
	local lon = math.deg(math.atan2(offset.X, offset.Z))
	local isGrounded = self._groundController.IsGrounded

	if not self._wasGrounded and isGrounded then
		if self._jumpPeakDist and self._jumpStartDist then
			self._lastJumpHeight = self._jumpPeakDist - self._jumpStartDist
			self._lastJumpLat = self._jumpLat
			self._lastJumpLon = self._jumpLon
		end
		self._jumpStartDist = nil
		self._jumpPeakDist = nil
	end

	if isGrounded and not self._wasGrounded then
	elseif not isGrounded then
		if self._jumpStartDist == nil then
			self._jumpStartDist = dist
			self._jumpPeakDist = dist
			self._jumpLat = lat
			self._jumpLon = lon
		end
		if dist > self._jumpPeakDist then
			self._jumpPeakDist = dist
		end
	end

	self._wasGrounded = isGrounded

end

return GraviBowDebugController
