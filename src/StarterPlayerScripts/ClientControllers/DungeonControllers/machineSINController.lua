local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Players = game:GetService("Players")

local CustomPackages = ReplicatedStorage:WaitForChild("CustomPackages")
local Packages = ReplicatedStorage:WaitForChild("Packages")
local Knit = require(Packages.Knit)
local promise = require(Packages.Promise)

local LocalPlayer = Players.LocalPlayer
local Camera = workspace.CurrentCamera

local machineSINController = Knit.CreateController { Name = "machineSINController" }

function machineSINController:KnitStart()
	task.wait(5)

	local machines = CollectionService:GetTagged("machine")
	print("Found", #machines, "machines")

	for _, machine in ipairs(machines) do
		if not machine:IsDescendantOf(workspace) then continue end

		print("Machine:", machine:GetFullName())

		local controllerManager = machine:FindFirstChildWhichIsA("ControllerManager", true)
		local groundController = machine:FindFirstChildWhichIsA("GroundController", true)
		local groundSensor = machine:FindFirstChildWhichIsA("ControllerPartSensor", true)
		local rootPart = machine:FindFirstChild("RootPart")
		local seat = machine:FindFirstChildWhichIsA("Seat", true)

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

			-- --- Input handling ---
			local steerAccel = 0.02
			local steerDecay = 0.1

			-- Yaw steering (A/D)
			if UserInputService:IsKeyDown(Enum.KeyCode.D) then
				steeringInput += steerAccel
			elseif UserInputService:IsKeyDown(Enum.KeyCode.A) then
				steeringInput -= steerAccel
			else
				steeringInput += (-steeringInput) * steerDecay
			end

			-- Pitch steering (W/S)
			local pitchInput = 0
			if UserInputService:IsKeyDown(Enum.KeyCode.W) then
				pitchInput = -1
			elseif UserInputService:IsKeyDown(Enum.KeyCode.S) then
				pitchInput = 1
			end

			steeringInput = math.clamp(steeringInput, -1, 1)

			-- Apply physics banking
			torque.Force = rootPart.CFrame.RightVector * steeringInput * -100
			angVel.AngularVelocity = Vector3.new(0, 0, -rootPart.RotVelocity.Z * 2)

			-- Smooth yaw turning
			local currentLook = rootPart.CFrame.LookVector
			local turnAmount = 2 -- smaller = tighter steering, larger = more subtle
			local targetLook = (currentLook + rootPart.CFrame.RightVector * steeringInput * turnAmount).Unit
			local smoothedLook = currentLook:Lerp(targetLook, 0.05)
			local baseCFrame = CFrame.lookAt(rootPart.Position, rootPart.Position + smoothedLook, rootPart.CFrame.UpVector)

			-- --- Visual tilt (roll and pitch) ---
			local targetRoll = math.rad(steeringInput * -5)
			local targetPitch = math.rad(pitchInput * 5)

			currentRoll += (targetRoll - currentRoll) * 0.15
			currentPitch += (targetPitch - currentPitch) * 0.15

			rootPart.CFrame = baseCFrame * CFrame.Angles(currentPitch, 0, currentRoll)

			-- Movement direction
			controllerManager.MovingDirection = rootPart.CFrame.LookVector
		end)



		-- Store current camera CFrame for smoothing
		local smoothedCameraCFrame = nil

		local function followCameraFunction()
			if not seat.Occupant or seat.Occupant.Parent ~= LocalPlayer.Character then
				Camera.CameraType = Enum.CameraType.Custom
				RunService:UnbindFromRenderStep("FollowVehicleCamera")
				isSeated = false
				smoothedCameraCFrame = nil
				return
			end

			-- Build yaw-only CFrame (no tilt)
			local rootPosition = rootPart.Position
			local flatLookVector = Vector3.new(rootPart.CFrame.LookVector.X, 0, rootPart.CFrame.LookVector.Z).Unit
			local flatRightVector = flatLookVector:Cross(Vector3.new(0, 1, 0)).Unit
			local flatUpVector = flatRightVector:Cross(flatLookVector).Unit
			local rootCFrame = CFrame.fromMatrix(rootPosition, flatRightVector, flatUpVector)

			-- Target camera position and look direction
			local cameraHeight = 8
			local cameraDistance = 15

			local cameraPos = rootCFrame.Position
				+ flatUpVector * cameraHeight
				- flatLookVector * cameraDistance

			local lookTarget = cameraPos + flatLookVector
			local targetCFrame = CFrame.new(cameraPos, lookTarget)

			-- Smooth transition
			if not smoothedCameraCFrame then
				smoothedCameraCFrame = targetCFrame
			else
				smoothedCameraCFrame = smoothedCameraCFrame:Lerp(targetCFrame, 0.25) 
			end

			Camera.CFrame = smoothedCameraCFrame
		end



		seat:GetPropertyChangedSignal("Occupant"):Connect(function()
			local occupant = seat.Occupant
			isSeated = occupant and occupant.Parent == LocalPlayer.Character

			if isSeated then
				Camera.CameraType = Enum.CameraType.Scriptable
				RunService:BindToRenderStep("FollowVehicleCamera", Enum.RenderPriority.Camera.Value + 1, followCameraFunction)
			else
				Camera.CameraType = Enum.CameraType.Custom
				RunService:UnbindFromRenderStep("FollowVehicleCamera")
			end
		end)
	end
end

return machineSINController
