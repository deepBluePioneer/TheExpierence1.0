-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Players = game:GetService("Players")

-- Packages
local Packages = ReplicatedStorage:WaitForChild("Packages")
local Knit = require(Packages.Knit)

-- References
local LocalPlayer = Players.LocalPlayer
local Camera = workspace.CurrentCamera

-- Controller
local machineSINController = Knit.CreateController { Name = "machineSINController" }

-- Bank + Damping setup
local function setupPhysics(rootPart)
	local attachment = rootPart:FindFirstChild("BankAttachment") or Instance.new("Attachment")
	attachment.Name = "BankAttachment"
	attachment.Parent = rootPart

	local torque = Instance.new("VectorForce")
	torque.Name = "BankTorque"
	torque.Attachment0 = attachment
	torque.Force = Vector3.zero
	torque.RelativeTo = Enum.ActuatorRelativeTo.Attachment0
	torque.ApplyAtCenterOfMass = true
	torque.Parent = rootPart

	local angVel = Instance.new("AngularVelocity")
	angVel.Name = "BankDamp"
	angVel.Attachment0 = attachment
	angVel.MaxTorque = 10000
	angVel.RelativeTo = Enum.ActuatorRelativeTo.Attachment0
	angVel.AngularVelocity = Vector3.zero
	angVel.Parent = rootPart

	return torque, angVel
end

-- Camera follow logic
local function createCameraFollow(seat, rootPart)
	local smoothedCameraCFrame = nil

	local function followCamera()
		if not seat.Occupant or seat.Occupant.Parent ~= LocalPlayer.Character then
			Camera.CameraType = Enum.CameraType.Custom
			RunService:UnbindFromRenderStep("FollowVehicleCamera")
			smoothedCameraCFrame = nil
			return
		end

		local rootPosition = rootPart.Position
		local flatLook = Vector3.new(rootPart.CFrame.LookVector.X, 0, rootPart.CFrame.LookVector.Z).Unit
		local right = flatLook:Cross(Vector3.new(0, 1, 0)).Unit
		local up = right:Cross(flatLook).Unit
		local rootCFrame = CFrame.fromMatrix(rootPosition, right, up)

		local cameraHeight = 8
		local cameraDistance = 15
		local cameraPos = rootCFrame.Position + up * cameraHeight - flatLook * cameraDistance
		local lookTarget = cameraPos + flatLook
		local targetCFrame = CFrame.new(cameraPos, lookTarget)

		smoothedCameraCFrame = smoothedCameraCFrame and smoothedCameraCFrame:Lerp(targetCFrame, 0.25) or targetCFrame
		Camera.CFrame = smoothedCameraCFrame
	end

	return followCamera
end

-- Setup machine physics and movement loop
local function setupMachine(machine)
	local controllerManager = machine:FindFirstChildWhichIsA("ControllerManager", true)
	local groundController = machine:FindFirstChildWhichIsA("GroundController", true)
	local airController = machine:FindFirstChildWhichIsA("AirController", true)

	local groundSensor = machine:FindFirstChildWhichIsA("ControllerPartSensor", true)
	local rootPart = machine:FindFirstChild("RootPart")
	local seat = machine:FindFirstChildWhichIsA("Seat", true)

	local torque, angVel = setupPhysics(rootPart)

	-- Configure controllers
	groundSensor.UpdateType = "OnRead"
	controllerManager.RootPart = rootPart
	controllerManager.GroundSensor = groundSensor
	controllerManager.ActiveController = groundController

	controllerManager.BaseMoveSpeed = 50
	controllerManager.BaseTurnSpeed = 0

	groundController.MoveSpeedFactor = 1
	groundController.TurnSpeedFactor = 1
	groundController.AccelerationTime = 0
	groundController.DecelerationTime = 0
	groundController.Friction = 1

	-- Air config
	airController.MaintainLinearMomentum = true
	airController.MaintainAngularMomentum = true
	airController.MoveMaxForce = 50000
	airController.TurnMaxTorque = 5000
	airController.BalanceMaxTorque = 3000
	airController.BalanceSpeed = 3

	local baseOffset = 0.75
	local amplitude = 0.15
	local frequency = 1.5
	local currentOffset = baseOffset
	local steeringInput = 0
	local isSeated = false
	local currentRoll = 0
	local currentPitch = 0

	RunService.RenderStepped:Connect(function(dt)
		if not isSeated then return end

		local t = tick()
		local targetOffset = baseOffset + math.sin(t * frequency) * amplitude
		currentOffset += (targetOffset - currentOffset) * 0.1
		groundController.GroundOffset = currentOffset

		local steerAccel, steerDecay = 0.02, 0.1
		if UserInputService:IsKeyDown(Enum.KeyCode.D) then
			steeringInput += steerAccel
		elseif UserInputService:IsKeyDown(Enum.KeyCode.A) then
			steeringInput -= steerAccel
		else
			steeringInput += (-steeringInput) * steerDecay
		end

		local pitchInput = 0
		if UserInputService:IsKeyDown(Enum.KeyCode.W) then pitchInput = -1 end
		if UserInputService:IsKeyDown(Enum.KeyCode.S) then pitchInput = 1 end

		steeringInput = math.clamp(steeringInput, -1, 1)

		torque.Force = rootPart.CFrame.RightVector * steeringInput * -100
		angVel.AngularVelocity = Vector3.new(0, 0, -rootPart.RotVelocity.Z * 2)

		-- Ground check
		local isGrounded = groundSensor.SensedPart ~= nil
		controllerManager.ActiveController = isGrounded and groundController or airController

		-- Preserve forward motion manually (optional)
		if not isGrounded then
			local velocity = rootPart.AssemblyLinearVelocity
			local forwardDir = rootPart.CFrame.LookVector
			local horizontalVel = Vector3.new(forwardDir.X, 0, forwardDir.Z).Unit * velocity.Magnitude
			rootPart.AssemblyLinearVelocity = Vector3.new(horizontalVel.X, velocity.Y, horizontalVel.Z)
		end

		-- Align to slope
		local upVector = (isGrounded and groundSensor.HitNormal.Magnitude > 0) and groundSensor.HitNormal.Unit or Vector3.yAxis
		local forward = rootPart.CFrame.LookVector
		local targetForward = (forward + rootPart.CFrame.RightVector * steeringInput * 2).Unit
		local smoothedForward = forward:Lerp(targetForward, 0.05)

		local rightVector = smoothedForward:Cross(upVector).Unit
		local alignedForward = upVector:Cross(rightVector).Unit
		local alignedCFrame = CFrame.fromMatrix(rootPart.Position, rightVector, upVector)

		-- Visual tilt
		local targetRoll = math.rad(steeringInput * -50)
		local targetPitch = math.rad(pitchInput * 5)
		currentRoll += (targetRoll - currentRoll) * 0.15
		currentPitch += (targetPitch - currentPitch) * 0.15

		rootPart.CFrame = alignedCFrame * CFrame.Angles(currentPitch, 0, currentRoll)
		

		local trueForward = alignedCFrame.LookVector
		controllerManager.MovingDirection = trueForward



	end)

	-- Seat detection + camera follow
	local followCamera = createCameraFollow(seat, rootPart)
	seat:GetPropertyChangedSignal("Occupant"):Connect(function()
		isSeated = seat.Occupant and seat.Occupant.Parent == LocalPlayer.Character

		if isSeated then
			Camera.CameraType = Enum.CameraType.Scriptable
			RunService:BindToRenderStep("FollowVehicleCamera", Enum.RenderPriority.Camera.Value + 1, followCamera)
		else
			Camera.CameraType = Enum.CameraType.Custom
			RunService:UnbindFromRenderStep("FollowVehicleCamera")
		end
	end)
end

-- KnitStart
function machineSINController:KnitStart()
	task.wait(5)
	local machines = CollectionService:GetTagged("machine")
	print("Found", #machines, "machines")

	for _, machine in ipairs(machines) do
		if machine:IsDescendantOf(workspace) then
			print("Machine:", machine:GetFullName())
			setupMachine(machine)
		end
	end
end

return machineSINController
