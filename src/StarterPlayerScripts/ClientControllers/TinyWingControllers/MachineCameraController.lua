--[[
	MachineCameraController
	
	Positions camera behind the machine when player is seated.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local Knit = require(Packages.Knit)

local MachineCameraController = Knit.CreateController {
	Name = "MachineCameraController",
}

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         CONFIGURATION                                       ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

local CONFIG = {
	-- Camera position (relative to machine)
	Distance = 20,          -- How far behind
	Height = 8,             -- How high above
	
	-- Smoothing
	PositionSmoothing = 10, -- Higher = snappier camera
	LookSmoothing = 15,     -- Higher = snappier look direction
	
	-- Look offset (where camera looks relative to machine)
	LookAheadDistance = 10, -- Look slightly ahead of machine
}

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         STATE                                               ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

local physicsController = nil
local isActive = false

local currentCameraPos = nil
local currentLookAt = nil

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         CAMERA UPDATE                                       ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

local function updateCamera(deltaTime)
	if not isActive then return end
	if not physicsController:IsActive() then return end
	
	local rootPart = physicsController:GetRootPart()
	if not rootPart then return end
	
	local rootPos = rootPart.Position
	
	-- Get FLAT horizontal direction (ignore tilt - only follow yaw)
	local lookVector = rootPart.CFrame.LookVector
	local flatLook = Vector3.new(lookVector.X, 0, lookVector.Z)
	if flatLook.Magnitude > 0.001 then
		flatLook = flatLook.Unit
	else
		flatLook = Vector3.new(0, 0, -1)
	end
	
	-- Use world up (flat camera, no tilt)
	local worldUp = Vector3.new(0, 1, 0)
	
	-- Calculate target camera position (behind and above, FLAT)
	local targetPos = rootPos 
		- flatLook * CONFIG.Distance 
		+ worldUp * CONFIG.Height
	
	-- Calculate look target (slightly ahead of machine, at machine height)
	local targetLookAt = rootPos + flatLook * CONFIG.LookAheadDistance
	
	-- Initialize if first frame
	if not currentCameraPos then
		currentCameraPos = targetPos
		currentLookAt = targetLookAt
	end
	
	-- Smooth interpolation
	local posAlpha = math.min(CONFIG.PositionSmoothing * deltaTime, 1)
	local lookAlpha = math.min(CONFIG.LookSmoothing * deltaTime, 1)
	
	currentCameraPos = currentCameraPos:Lerp(targetPos, posAlpha)
	currentLookAt = currentLookAt:Lerp(targetLookAt, lookAlpha)
	
	-- Apply camera
	camera.CameraType = Enum.CameraType.Scriptable
	camera.CFrame = CFrame.lookAt(currentCameraPos, currentLookAt)
end

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         PUBLIC API                                          ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

function MachineCameraController:Enable()
	isActive = true
	currentCameraPos = nil  -- Reset for fresh start
	currentLookAt = nil
	print("[MachineCameraController] Enabled")
end

function MachineCameraController:Disable()
	isActive = false
	camera.CameraType = Enum.CameraType.Custom  -- Return to default
	print("[MachineCameraController] Disabled")
end

function MachineCameraController:IsActive()
	return isActive
end

function MachineCameraController:GetConfig()
	return CONFIG
end

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         KNIT LIFECYCLE                                      ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

function MachineCameraController:KnitInit()
	-- Nothing needed
end

function MachineCameraController:KnitStart()
	physicsController = Knit.GetController("MachinePhysicsController")
	
	-- Camera update loop (RenderStepped for smoothest camera)
	RunService.RenderStepped:Connect(updateCamera)
	
	print("[MachineCameraController] Ready")
end

return MachineCameraController

