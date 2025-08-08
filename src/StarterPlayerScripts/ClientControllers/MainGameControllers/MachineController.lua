-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Players = game:GetService("Players")

-- Packages
local CustomPackages = ReplicatedStorage:WaitForChild("CustomPackages")
local Packages = ReplicatedStorage:WaitForChild("Packages")
local Knit = require(Packages.Knit)

-- Controllers
local CameraController

-- References
local LocalPlayer = Players.LocalPlayer
local MachineController = Knit.CreateController { Name = "MachineController" }
local movementConnection -- for controlling the RenderStepped connection
local movementPaused 
function MachineController:KnitStart()
     CameraController = Knit.GetController("CameraController")

	task.wait(5)
	local machines = CollectionService:GetTagged("machine")
	print("Found", #machines, "machines")

	for _, machine in ipairs(machines) do
		if machine:IsDescendantOf(workspace) then
			print("Machine:", machine:GetFullName())
			self:SetupMachine(machine)
		end
	end
end

function MachineController:SetupMachine(machine)
	local controllerManager = machine:FindFirstChildWhichIsA("ControllerManager", true)
	local groundController = machine:FindFirstChildWhichIsA("GroundController", true)
	local groundSensor = machine:FindFirstChildWhichIsA("ControllerPartSensor", true)
	local rootPart = machine:FindFirstChild("RootPart")
	local seat = machine:FindFirstChildWhichIsA("Seat", true)

	controllerManager.RootPart = rootPart
	controllerManager.GroundSensor = groundSensor
	controllerManager.ActiveController = groundController

	groundController.GroundOffset = 3
	groundSensor.SearchDistance = 5
	groundSensor.UpdateType = "OnRead"

	local isSeated = false

	local attachment = Instance.new("Attachment")
	attachment.Name = "RootAttachment"
	attachment.Parent = rootPart

	local thrustForce = Instance.new("VectorForce")
	thrustForce.Name = "ThrustForce"
	thrustForce.Attachment0 = attachment
	thrustForce.RelativeTo = Enum.ActuatorRelativeTo.World
	thrustForce.ApplyAtCenterOfMass = true
	thrustForce.Force = Vector3.zero
	thrustForce.Parent = rootPart

	local liftForce = Instance.new("VectorForce")
	liftForce.Name = "LiftForce"
	liftForce.Attachment0 = attachment
	liftForce.RelativeTo = Enum.ActuatorRelativeTo.World
	liftForce.ApplyAtCenterOfMass = true
	liftForce.Force = Vector3.zero
	liftForce.Parent = rootPart

	local angularVelocity = Instance.new("AngularVelocity")
	angularVelocity.Attachment0 = attachment
	angularVelocity.RelativeTo = Enum.ActuatorRelativeTo.Attachment0
	angularVelocity.MaxTorque = math.huge
	angularVelocity.AngularVelocity = Vector3.zero
	angularVelocity.Parent = rootPart

	local maxSpeed = 150
	local thrust = 8000
	local dragFactor = 8
	local turnSpeed = math.rad(80)
	local pitchSpeed = math.rad(60)
	local rollSpeed = math.rad(30)

	local fallVelocity = 0
	local gravityTarget = 196.2
	local gravityLerpTime = 2.5
	local gravityTimer = 0
	local gravityDisabled = false

	local steerInput = 0
	local pitchInput = 0
	local currentRoll = 0
	local currentPitch = 0

	local isCharging = false
	local boostCharge = 0
	local maxBoostCharge = 3
	local boostThrust = 30000
	local boostVelocity = Vector3.zero
	local boostDecay = 6
	local isBraking = false

	local fallGravity = Vector3.zero
	local hasRecentlyTouched = false

	-- Touched: Downforce and Knockback
	rootPart.Touched:Connect(function(hit)
		if not hasRecentlyTouched and hit:IsA("BasePart") and hit:IsDescendantOf(workspace) then
			local velocity = rootPart.Velocity
			local magnitude = velocity.Magnitude
			local mass = rootPart.AssemblyMass
			local downImpulse = Vector3.new(0, -1, 0) * magnitude * mass * 2
			fallGravity = downImpulse
			hasRecentlyTouched = true
			task.delay(0.3, function() hasRecentlyTouched = false end)
		end
	end)

	-- Input Handling
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then return end
		if input.KeyCode == Enum.KeyCode.A then steerInput = -1 end
		if input.KeyCode == Enum.KeyCode.D then steerInput = 1 end
		if input.KeyCode == Enum.KeyCode.W then pitchInput = -1 end
		if input.KeyCode == Enum.KeyCode.S then pitchInput = 1 end
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			isCharging = true
			isBraking = true
			CameraController.IsCharging = true
		end
	end)

	UserInputService.InputEnded:Connect(function(input)
		if input.KeyCode == Enum.KeyCode.A and steerInput == -1 then steerInput = 0 end
		if input.KeyCode == Enum.KeyCode.D and steerInput == 1 then steerInput = 0 end
		if input.KeyCode == Enum.KeyCode.W and pitchInput == -1 then pitchInput = 0 end
		if input.KeyCode == Enum.KeyCode.S and pitchInput == 1 then pitchInput = 0 end
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			local boostForce = math.clamp(boostCharge, 0, maxBoostCharge)
			boostVelocity = rootPart.CFrame.LookVector * boostForce * boostThrust
			boostCharge = 0
			isCharging = false
			isBraking = false
			CameraController.IsCharging = false
		end
	end)

	-- Movement + Physics
	local currentUp = Vector3.new(0, 1, 0)

	movementConnection = RunService.RenderStepped:Connect(function(dt)
		if not isSeated then return end
		if movementPaused then return end
		
		if isCharging then
			boostCharge = math.min(boostCharge + dt, maxBoostCharge)
		end

		boostVelocity = boostVelocity:Lerp(Vector3.zero, dt * boostDecay)

		local velocity = rootPart.Velocity
		local gravity = workspace.Gravity
		local mass = rootPart.AssemblyMass

		local targetUp = Vector3.new(0, 1, 0)
		if groundSensor.SensedPart then
			targetUp = groundSensor.HitNormal
		end

		currentUp = currentUp:Lerp(targetUp, dt * 8)
		local up = currentUp.Unit
		local forward = (rootPart.CFrame.LookVector - up * rootPart.CFrame.LookVector:Dot(up)).Unit
		local right = forward:Cross(up).Unit

		if groundSensor.SensedPart then
			fallVelocity = 0
			liftForce.Force = up * gravity * mass + fallGravity
		else
			fallVelocity += gravity * dt * 0.4
			liftForce.Force = Vector3.new(0, -fallVelocity * mass, 0) + fallGravity
		end

		fallGravity = fallGravity:Lerp(Vector3.zero, dt * 3)

		local isGrounded = groundSensor.SensedPart ~= nil
		if not isGrounded then
			if not gravityDisabled then
				workspace.Gravity = 0
				gravityTimer = 0
				gravityDisabled = true
			end
			if workspace.Gravity < gravityTarget then
				gravityTimer += dt
				local alpha = math.clamp(gravityTimer / gravityLerpTime, 0, 1)
				workspace.Gravity = math.clamp(alpha * gravityTarget, 0, gravityTarget)
			end
		else
			if gravityDisabled then
				workspace.Gravity = gravityTarget
				gravityDisabled = false
			end
		end

		local slopeGravity = -gravity * mass * up
		local slopeDragForce = up:Dot(forward) * slopeGravity.Magnitude

		local currentSpeed = velocity:Dot(forward)
		local thrustVector = Vector3.zero
		if isBraking then
			if currentSpeed > 0.1 then
				thrustVector = -forward * math.min(math.abs(currentSpeed * dragFactor * 20), thrust * 8)
			else
				thrustVector = Vector3.zero
			end
		elseif currentSpeed < maxSpeed then
			thrustVector = forward * (thrust + slopeDragForce)
		end

		local lateralVelocity = velocity:Dot(right)
		local lateralCorrection = -right * lateralVelocity * mass * 4
		local drag = forward * -currentSpeed * dragFactor

		local targetRoll = math.rad(steerInput * -20)
		local targetPitch = math.rad(pitchInput * 5)
		currentRoll += (targetRoll - currentRoll) * 0.15
		currentPitch += (targetPitch - currentPitch) * 0.15

		local baseCFrame = CFrame.lookAt(rootPart.Position, rootPart.Position + forward, up)
		rootPart.CFrame = baseCFrame * CFrame.Angles(currentPitch, 0, currentRoll)

		thrustForce.Force = thrustVector + drag + lateralCorrection + boostVelocity
		angularVelocity.AngularVelocity = Vector3.new(pitchInput * pitchSpeed, -steerInput * turnSpeed, steerInput * rollSpeed)
	end)

	-- Camera follow integration
	seat:GetPropertyChangedSignal("Occupant"):Connect(function()
		isSeated = seat.Occupant and seat.Occupant.Parent == LocalPlayer.Character

		if isSeated then
			CameraController:StartFollowing(seat, rootPart)
		else
			CameraController:StopFollowing()
		end
	end)
end
function MachineController:PauseMovement()
	if movementConnection then
		movementPaused = true
	end
end

function MachineController:ResumeMovement()
	if movementConnection then
		movementPaused = false
	end
end

return MachineController
