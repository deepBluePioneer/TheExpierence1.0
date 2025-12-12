--[[
	MachineController
	
	Handles player input for driving anti-gravity hover machines.
	Uses Roblox's ControllerManager/GroundController system.
	
	Controls:
	- W/S or Up/Down: Forward/Backward
	- A/D or Left/Right: Turn left/right
	- Space: Boost (if available)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local Knit = require(Packages.Knit)
local Gizmo = require(Packages.imgizmo)
local Iris = require(Packages.iris)

local MachineController = Knit.CreateController {
	Name = "MachineController",
}

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         CONFIGURATION                                       ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

local CONFIG = {
	-- Movement speeds
	BaseMoveSpeed = 80,          -- Base movement speed (studs/sec)
	BaseTurnSpeed = 3,           -- Base turn speed (rad/sec)
	BoostMultiplier = 1.5,       -- Speed multiplier when boosting
	
	-- Physics tuning
	AccelerationTime = 0.3,      -- Time to reach full speed
	DecelerationTime = 0.5,      -- Time to stop
	
	-- Surface alignment (uses GroundSensor's HitNormal)
	AlignToSurface = true,       -- Align machine to surface normal
	AlignmentSpeed = 8,          -- How fast to align when grounded (higher = snappier)
	LandingAlignmentSpeed = 3,   -- Slower alignment when landing (smoother transition)
	LandingSmoothTime = 0.5,     -- How long to use landing speed after touching ground
	
	-- Air arc alignment (align to velocity trajectory when airborne)
	ArcAlignmentEnabled = true,  -- Align to velocity arc when in air
	ArcAlignmentSpeed = 5,       -- How fast to align to arc (lower = smoother)
	MinArcSpeed = 10,            -- Minimum speed to apply arc alignment
	
	-- ════════════════════════════════════════════════════════════════════
	-- TWO-SEGMENT POGO SUSPENSION (Tiny Wings style)
	-- ════════════════════════════════════════════════════════════════════
	-- Segment 1: Fixed hover offset (rigid, never changes)
	HoverHeight = 3,             -- Fixed visual height above terrain (studs)
	
	-- Segment 2: Dynamic spring (compresses/extends)
	SpringStiffness = 10,       -- Spring force multiplier (lower = softer/bouncier)
	SpringDamping = 20,          -- Damping to prevent oscillation (lower = more bounce)
	SpringRestLength = 30,        -- Rest length of spring segment
	MaxSpringExtension = 1,      -- Max extension before "airborne" (no force)
	
	-- Dive mechanics
	DiveDownforce = 500,         -- Extra downward force when diving
	DiveStiffnessMultiplier = 1.5, -- Spring gets stiffer when diving (slams harder)
	
	-- Debug visualization
	DebugMode = false,           -- Print debug info
	DebugGizmos = true,          -- Draw suspension gizmos with imgizmo
	
	-- World settings when driving
	DrivingGravity = 100,        -- Workspace gravity when in machine
}

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         STATE                                               ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

local player = Players.LocalPlayer
local currentMachine = nil           -- The machine model we're driving
local controllerManager = nil        -- ControllerManager instance
local groundController = nil         -- GroundController instance
local groundSensor = nil             -- ControllerPartSensor for surface detection
local seat = nil                     -- The Seat we're sitting in

-- Input state
local inputState = {
	forward = 0,    -- -1 to 1 (S to W)
	turn = 0,       -- -1 to 1 (A to D)
	boost = false,
	dive = false,   -- Space held = dive
}

-- Surface alignment state
local currentUpVector = Vector3.new(0, 1, 0)  -- Smoothed up vector for alignment

-- Suspension state
local lastGroundDistance = CONFIG.SpringRestLength  -- For velocity calculation
local isAirborne = false                             -- True when spring fully extended
local wasAirborne = false                            -- Previous frame's airborne state
local landingTimer = 0                               -- Time since landing (for smooth transition)

-- World state (saved when entering machine)
local originalGravity = 196.2                        -- Default Roblox gravity
local playerHumanoid = nil                           -- Reference to player's humanoid

-- Speed tracking (for display)
local currentSpeed = 0                               -- Current speed in studs/sec

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         INPUT HANDLING                                      ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

local keyStates = {
	W = false, S = false,
	A = false, D = false,
	Up = false, Down = false,
	Left = false, Right = false,
	Space = false,
	Shift = false,
}

local function updateInputState()
	-- Forward/backward
	local forward = 0
	if keyStates.W or keyStates.Up then forward = forward + 1 end
	if keyStates.S or keyStates.Down then forward = forward - 1 end
	inputState.forward = forward
	
	-- Turn left/right
	local turn = 0
	if keyStates.A or keyStates.Left then turn = turn + 1 end
	if keyStates.D or keyStates.Right then turn = turn - 1 end
	inputState.turn = turn
	
	-- Dive (Space) - compresses spring for speed on downslopes
	inputState.dive = keyStates.Space
	
	-- Boost (Shift)
	inputState.boost = keyStates.Shift
end

local function onInputBegan(input, gameProcessed)
	if gameProcessed then return end
	
	if input.KeyCode == Enum.KeyCode.W then keyStates.W = true
	elseif input.KeyCode == Enum.KeyCode.S then keyStates.S = true
	elseif input.KeyCode == Enum.KeyCode.A then keyStates.A = true
	elseif input.KeyCode == Enum.KeyCode.D then keyStates.D = true
	elseif input.KeyCode == Enum.KeyCode.Up then keyStates.Up = true
	elseif input.KeyCode == Enum.KeyCode.Down then keyStates.Down = true
	elseif input.KeyCode == Enum.KeyCode.Left then keyStates.Left = true
	elseif input.KeyCode == Enum.KeyCode.Right then keyStates.Right = true
	elseif input.KeyCode == Enum.KeyCode.Space then keyStates.Space = true
	elseif input.KeyCode == Enum.KeyCode.LeftShift or input.KeyCode == Enum.KeyCode.RightShift then keyStates.Shift = true
	end
	
	updateInputState()
end

local function onInputEnded(input, gameProcessed)
	if input.KeyCode == Enum.KeyCode.W then keyStates.W = false
	elseif input.KeyCode == Enum.KeyCode.S then keyStates.S = false
	elseif input.KeyCode == Enum.KeyCode.A then keyStates.A = false
	elseif input.KeyCode == Enum.KeyCode.D then keyStates.D = false
	elseif input.KeyCode == Enum.KeyCode.Up then keyStates.Up = false
	elseif input.KeyCode == Enum.KeyCode.Down then keyStates.Down = false
	elseif input.KeyCode == Enum.KeyCode.Left then keyStates.Left = false
	elseif input.KeyCode == Enum.KeyCode.Right then keyStates.Right = false
	elseif input.KeyCode == Enum.KeyCode.Space then keyStates.Space = false
	elseif input.KeyCode == Enum.KeyCode.LeftShift or input.KeyCode == Enum.KeyCode.RightShift then keyStates.Shift = false
	end
	
	updateInputState()
end

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         MACHINE CONTROL                                     ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

local function setupMachine(machine)
	currentMachine = machine
	
	-- Find ControllerManager
	controllerManager = machine:FindFirstChild("ControllerManager")
	if not controllerManager then
		warn("[MachineController] No ControllerManager found!")
		return false
	end
	
	-- Find GroundController
	groundController = controllerManager:FindFirstChild("GroundController")
	if not groundController then
		warn("[MachineController] No GroundController found!")
		return false
	end
	
	-- Configure the controller for movement
	controllerManager.BaseMoveSpeed = CONFIG.BaseMoveSpeed
	controllerManager.BaseTurnSpeed = CONFIG.BaseTurnSpeed
	
	groundController.MoveSpeedFactor = 1
	groundController.TurnSpeedFactor = 1
	groundController.AccelerationTime = CONFIG.AccelerationTime
	groundController.DecelerationTime = CONFIG.DecelerationTime
	
	-- Find the GroundSensor (ControllerPartSensor) on the RootPart
	local rootPart = machine:FindFirstChild("RootPart")
	if rootPart then
		groundSensor = rootPart:FindFirstChild("GroundSensor")
		if groundSensor then
			print("[MachineController] GroundSensor found - using HitNormal for surface alignment")
		else
			warn("[MachineController] No GroundSensor found on RootPart")
		end
		
		-- Initialize up vector from current orientation
		currentUpVector = rootPart.CFrame.UpVector
	end
	
	-- Set driving gravity
	originalGravity = Workspace.Gravity
	Workspace.Gravity = CONFIG.DrivingGravity
	
	-- Disable player jumping (so Space only dives, doesn't jump)
	if player.Character then
		playerHumanoid = player.Character:FindFirstChildOfClass("Humanoid")
		if playerHumanoid then
			playerHumanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)
			playerHumanoid.JumpPower = 0
			playerHumanoid.JumpHeight = 0
		end
	end
	
	if CONFIG.DebugMode then
		print("[MachineController] Machine configured:", machine.Name)
		print("  BaseMoveSpeed:", controllerManager.BaseMoveSpeed)
		print("  BaseTurnSpeed:", controllerManager.BaseTurnSpeed)
		print("  Surface alignment:", CONFIG.AlignToSurface)
		print("  GroundSensor:", groundSensor and "Found" or "Not found")
		print("  Gravity set to:", CONFIG.DrivingGravity)
	end
	
	return true
end

local function clearMachine()
	if controllerManager then
		-- Reset speeds when exiting
		controllerManager.BaseMoveSpeed = 0
		controllerManager.BaseTurnSpeed = 0
		controllerManager.MovingDirection = Vector3.zero
	end
	
	-- Restore original gravity
	Workspace.Gravity = originalGravity
	
	-- Re-enable player jumping
	if playerHumanoid then
		playerHumanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, true)
		playerHumanoid.JumpPower = 50  -- Default value
		playerHumanoid.JumpHeight = 7.2  -- Default value
		playerHumanoid = nil
	end
	
	currentMachine = nil
	controllerManager = nil
	groundController = nil
	groundSensor = nil
	seat = nil
	currentUpVector = Vector3.new(0, 1, 0)
	
	if CONFIG.DebugMode then
		print("[MachineController] Exited machine, gravity restored to:", originalGravity)
	end
end

local function updateMachineMovement(deltaTime)
	if not controllerManager or not currentMachine then return end
	
	local rootPart = currentMachine:FindFirstChild("RootPart")
	if not rootPart then return end
	
	-- ══════════════════════════════════════════════════════════════════════
	-- SURFACE NORMAL ALIGNMENT (using GroundSensor)
	-- ══════════════════════════════════════════════════════════════════════
	local targetUpVector = Vector3.new(0, 1, 0)  -- Default to world up
	local groundHitPoint = nil  -- For gizmo visualization
	local groundNormal = Vector3.new(0, 1, 0)
	
	if CONFIG.AlignToSurface and groundSensor then
		-- Use the GroundSensor's HitNormal - already computed by the physics system!
		local sensedPart = groundSensor.SensedPart
		if sensedPart then
			-- We have ground contact - use the hit normal
			targetUpVector = groundSensor.HitNormal
			groundNormal = groundSensor.HitNormal
			groundHitPoint = groundSensor.HitFrame.Position
			isAirborne = false
		else
			isAirborne = true
			
			-- ARC ALIGNMENT: When airborne, align to velocity trajectory
			if CONFIG.ArcAlignmentEnabled then
				local velocity = rootPart.AssemblyLinearVelocity
				local speed = velocity.Magnitude
				
				if speed > CONFIG.MinArcSpeed then
					-- Get velocity direction (the arc tangent)
					local velocityDir = velocity.Unit
					
					-- Calculate the "up" vector perpendicular to velocity
					-- This makes the machine's top always face "up" relative to the arc
					-- We want the right vector to stay horizontal, then derive up from that
					local worldUp = Vector3.new(0, 1, 0)
					local rightVector = velocityDir:Cross(worldUp)
					
					if rightVector.Magnitude > 0.1 then
						rightVector = rightVector.Unit
						-- Up is perpendicular to both velocity and right
						targetUpVector = rightVector:Cross(velocityDir).Unit
					end
					-- If moving straight up/down, keep current up vector
				end
			end
		end
	end
	
	-- Detect landing (transition from airborne to grounded)
	local justLanded = wasAirborne and not isAirborne
	if justLanded then
		landingTimer = CONFIG.LandingSmoothTime  -- Start landing smooth period
	end
	wasAirborne = isAirborne
	
	-- Decrease landing timer
	if landingTimer > 0 then
		landingTimer = landingTimer - deltaTime
	end
	
	-- Choose alignment speed based on state
	local alignSpeed
	if isAirborne then
		-- Use arc alignment speed when in air
		alignSpeed = CONFIG.ArcAlignmentSpeed * deltaTime
	elseif landingTimer > 0 then
		-- Blend from landing speed to normal speed as timer decreases
		local landingBlend = landingTimer / CONFIG.LandingSmoothTime
		local blendedSpeed = CONFIG.LandingAlignmentSpeed + (CONFIG.AlignmentSpeed - CONFIG.LandingAlignmentSpeed) * (1 - landingBlend)
		alignSpeed = blendedSpeed * deltaTime
	else
		alignSpeed = CONFIG.AlignmentSpeed * deltaTime
	end
	
	-- Smoothly interpolate toward the target up vector
	currentUpVector = currentUpVector:Lerp(targetUpVector, math.min(alignSpeed, 1))
	
	-- Update the ControllerManager's UpDirection for alignment
	controllerManager.UpDirection = currentUpVector
	
	-- ══════════════════════════════════════════════════════════════════════
	-- GIZMO VISUALIZATION (Two-Segment Pogo Suspension)
	-- ══════════════════════════════════════════════════════════════════════
	if CONFIG.DebugGizmos then
		local rootPos = rootPart.Position
		
		-- Calculate suspension points
		local hoverAnchorPoint = rootPos - Vector3.new(0, CONFIG.HoverHeight, 0)
		
		-- Segment 1: Fixed Hover Offset (BLUE - rigid, never changes)
		Gizmo.PushProperty("Color3", Color3.fromRGB(50, 150, 255))  -- Blue
		Gizmo.Ray:Draw(rootPos, hoverAnchorPoint)
		
		-- Root position marker (small blue sphere)
		Gizmo.Sphere:Draw(CFrame.new(rootPos), 0.5, 8, 360)
		
		-- Hover anchor point marker (cyan sphere)
		Gizmo.PushProperty("Color3", Color3.fromRGB(0, 255, 255))  -- Cyan
		Gizmo.Sphere:Draw(CFrame.new(hoverAnchorPoint), 0.4, 8, 360)
		
		if groundHitPoint then
			-- Segment 2: Dynamic Spring (color based on compression)
			local springLength = (hoverAnchorPoint - groundHitPoint).Magnitude
			local compression = CONFIG.SpringRestLength - springLength
			
			-- Color: Green (extended) -> Yellow (rest) -> Red (compressed)
			local springColor
			if compression > 0 then
				-- Compressed (red)
				local t = math.min(compression / CONFIG.SpringRestLength, 1)
				springColor = Color3.fromRGB(255, 255 * (1 - t), 0)
			else
				-- Extended (green)
				local t = math.min(-compression / CONFIG.MaxSpringExtension, 1)
				springColor = Color3.fromRGB(255 * t, 255, 0)
			end
			
			Gizmo.PushProperty("Color3", springColor)
			Gizmo.Ray:Draw(hoverAnchorPoint, groundHitPoint)
			
			-- Ground hit point marker (green sphere)
			Gizmo.PushProperty("Color3", Color3.fromRGB(50, 255, 50))  -- Green
			Gizmo.Sphere:Draw(CFrame.new(groundHitPoint), 0.3, 8, 360)
			
			-- Surface normal arrow (magenta)
			Gizmo.PushProperty("Color3", Color3.fromRGB(255, 0, 255))  -- Magenta
			local normalEnd = groundHitPoint + groundNormal * 3
			Gizmo.Arrow:Draw(groundHitPoint, normalEnd, 0.1, 0.5, 8)
		else
			-- Airborne - show extended spring (gray, dashed look)
			Gizmo.PushProperty("Color3", Color3.fromRGB(150, 150, 150))  -- Gray
			local extendedPoint = hoverAnchorPoint - Vector3.new(0, CONFIG.MaxSpringExtension, 0)
			Gizmo.Ray:Draw(hoverAnchorPoint, extendedPoint)
			
			-- Show velocity arc direction (yellow arrow)
			local velocity = rootPart.AssemblyLinearVelocity
			if velocity.Magnitude > CONFIG.MinArcSpeed then
				Gizmo.PushProperty("Color3", Color3.fromRGB(255, 255, 0))  -- Yellow
				local velocityEnd = rootPos + velocity.Unit * 8
				Gizmo.Arrow:Draw(rootPos, velocityEnd, 0.15, 0.6, 8)
				
				-- Show the target up vector (light blue)
				Gizmo.PushProperty("Color3", Color3.fromRGB(100, 200, 255))  -- Light blue
				local upEnd = rootPos + targetUpVector * 4
				Gizmo.Arrow:Draw(rootPos, upEnd, 0.1, 0.4, 8)
			end
		end
		
		-- Dive indicator (when diving, show downforce arrow)
		if inputState.dive then
			Gizmo.PushProperty("Color3", Color3.fromRGB(255, 100, 0))  -- Orange
			local diveArrowEnd = rootPos - Vector3.new(0, 5, 0)
			Gizmo.Arrow:Draw(rootPos, diveArrowEnd, 0.2, 0.8, 8)
		end
	end
	
	-- ══════════════════════════════════════════════════════════════════════
	-- MOVEMENT AND TURNING
	-- ══════════════════════════════════════════════════════════════════════
	
	-- Get current facing direction (projected onto the surface plane)
	local facingDirection = rootPart.CFrame.LookVector
	
	-- Project facing onto the surface plane (perpendicular to up vector)
	local projectedFacing = (facingDirection - currentUpVector * facingDirection:Dot(currentUpVector)).Unit
	if projectedFacing.Magnitude < 0.1 then
		projectedFacing = rootPart.CFrame.LookVector  -- Fallback
	end
	
	-- Calculate movement direction based on input
	local moveDirection = Vector3.zero
	
	if inputState.forward ~= 0 then
		moveDirection = projectedFacing * inputState.forward
	end
	
	-- Apply boost if active
	local speedMultiplier = inputState.boost and CONFIG.BoostMultiplier or 1
	controllerManager.BaseMoveSpeed = CONFIG.BaseMoveSpeed * speedMultiplier
	
	-- Set movement direction
	controllerManager.MovingDirection = moveDirection
	
	-- Handle turning by rotating around the current up vector
	if inputState.turn ~= 0 then
		local turnAmount = inputState.turn * CONFIG.BaseTurnSpeed * deltaTime
		-- Rotate facing direction around the up vector
		local rotationCFrame = CFrame.fromAxisAngle(currentUpVector, turnAmount)
		local newFacing = rotationCFrame:VectorToWorldSpace(projectedFacing)
		controllerManager.FacingDirection = newFacing.Unit
	else
		controllerManager.FacingDirection = projectedFacing
	end
	
	-- Track current speed (for GUI display)
	currentSpeed = rootPart.AssemblyLinearVelocity.Magnitude
	
	-- Debug output
	if CONFIG.DebugMode and (inputState.forward ~= 0 or inputState.turn ~= 0) then
		if math.floor(tick() * 2) % 2 == 0 then
			print(string.format("[Machine] Move: %.1f | Turn: %.1f | Speed: %.1f",
				inputState.forward, inputState.turn, currentSpeed))
		end
	end
end

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         SEAT DETECTION                                      ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

local function findMachineFromSeat(seatPart)
	-- The seat is inside a Folder which is inside the machine model
	local folder = seatPart.Parent
	if folder and folder:IsA("Folder") then
		local machine = folder.Parent
		if machine and machine:IsA("Model") then
			return machine
		end
	end
	return nil
end

local function onCharacterAdded(character)
	local humanoid = character:WaitForChild("Humanoid")
	
	-- Listen for sitting state changes
	humanoid.Seated:Connect(function(isSeated, seatPart)
		if isSeated and seatPart then
			-- Check if this seat belongs to a machine
			local machine = findMachineFromSeat(seatPart)
			if machine and machine:FindFirstChild("ControllerManager") then
				seat = seatPart
				if setupMachine(machine) then
					print("[MachineController] Now driving:", machine.Name)
				end
			end
		else
			-- Player got up from seat
			if currentMachine then
				clearMachine()
			end
		end
	end)
end

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         KNIT LIFECYCLE                                      ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

function MachineController:KnitInit()
	print("[MachineController] Initializing...")
end

function MachineController:KnitStart()
	print("[MachineController] Started")
	
	-- Input listeners
	UserInputService.InputBegan:Connect(onInputBegan)
	UserInputService.InputEnded:Connect(onInputEnded)
	
	-- Character setup
	if player.Character then
		onCharacterAdded(player.Character)
	end
	player.CharacterAdded:Connect(onCharacterAdded)
	
	-- Main update loop
	RunService.Heartbeat:Connect(function(deltaTime)
		if currentMachine then
			updateMachineMovement(deltaTime)
		end
	end)
	
	-- ══════════════════════════════════════════════════════════════════════
	-- IRIS DEBUG GUI
	-- ══════════════════════════════════════════════════════════════════════
	Iris.Init()
	
	Iris:Connect(function()
		-- Suspension Debug Window
		Iris.Window({"🔧 Suspension Debug", [Iris.Args.Window.NoClose] = true})
		
		-- Spring Settings
		Iris.Tree({"Spring Settings"})
		
		local stiffness = Iris.SliderNum({"Stiffness", 1, 1, 1000}, {number = CONFIG.SpringStiffness})
		if stiffness.numberChanged() then
			CONFIG.SpringStiffness = stiffness.number.value
		end
		
		local damping = Iris.SliderNum({"Damping", 1, 0, 100}, {number = CONFIG.SpringDamping})
		if damping.numberChanged() then
			CONFIG.SpringDamping = damping.number.value
		end
		
		local restLength = Iris.SliderNum({"Rest Length", 0.5, 0, 20}, {number = CONFIG.SpringRestLength})
		if restLength.numberChanged() then
			CONFIG.SpringRestLength = restLength.number.value
		end
		
		local maxExtension = Iris.SliderNum({"Max Extension", 0.5, 0, 20}, {number = CONFIG.MaxSpringExtension})
		if maxExtension.numberChanged() then
			CONFIG.MaxSpringExtension = maxExtension.number.value
		end
		
		Iris.End() -- Tree
		
		-- Hover Settings
		Iris.Tree({"Hover Settings"})
		
		local hoverHeight = Iris.SliderNum({"Hover Height", 0.5, 0, 10}, {number = CONFIG.HoverHeight})
		if hoverHeight.numberChanged() then
			CONFIG.HoverHeight = hoverHeight.number.value
		end
		
		local alignSpeed = Iris.SliderNum({"Alignment Speed", 1, 1, 20}, {number = CONFIG.AlignmentSpeed})
		if alignSpeed.numberChanged() then
			CONFIG.AlignmentSpeed = alignSpeed.number.value
		end
		
		local landingSpeed = Iris.SliderNum({"Landing Align Speed", 0.5, 0.5, 10}, {number = CONFIG.LandingAlignmentSpeed})
		if landingSpeed.numberChanged() then
			CONFIG.LandingAlignmentSpeed = landingSpeed.number.value
		end
		
		local landingTime = Iris.SliderNum({"Landing Smooth Time", 0.1, 0.1, 2}, {number = CONFIG.LandingSmoothTime})
		if landingTime.numberChanged() then
			CONFIG.LandingSmoothTime = landingTime.number.value
		end
		
		Iris.End() -- Tree
		
		-- Arc Alignment (Airborne)
		Iris.Tree({"Arc Alignment (Air)"}, {isUncollapsed = true})
		
		local arcEnabled = Iris.Checkbox({"Enable Arc Alignment"}, {isChecked = CONFIG.ArcAlignmentEnabled})
		if arcEnabled.checked() or arcEnabled.unchecked() then
			CONFIG.ArcAlignmentEnabled = arcEnabled.isChecked.value
		end
		
		Iris.Text({"Tilt Smoothness (lower = smoother):"})
		local arcSpeed = Iris.SliderNum({"Air Tilt Speed", 0.1, 0.1, 50}, {number = CONFIG.ArcAlignmentSpeed})
		if arcSpeed.numberChanged() then
			CONFIG.ArcAlignmentSpeed = arcSpeed.number.value
		end
		
		-- Quick presets
		Iris.SameLine()
		if Iris.Button({"Smooth (2)"}).clicked() then
			CONFIG.ArcAlignmentSpeed = 2
		end
		if Iris.Button({"Medium (5)"}).clicked() then
			CONFIG.ArcAlignmentSpeed = 5
		end
		if Iris.Button({"Snappy (12)"}).clicked() then
			CONFIG.ArcAlignmentSpeed = 12
		end
		Iris.End() -- SameLine
		
		Iris.Separator()
		
		local minArcSpeed = Iris.SliderNum({"Min Speed for Arc", 1, 0, 50}, {number = CONFIG.MinArcSpeed})
		if minArcSpeed.numberChanged() then
			CONFIG.MinArcSpeed = minArcSpeed.number.value
		end
		
		Iris.End() -- Tree
		
		-- Dive Settings
		Iris.Tree({"Dive Settings"})
		
		local diveForce = Iris.SliderNum({"Dive Downforce", 10, 0, 2000}, {number = CONFIG.DiveDownforce})
		if diveForce.numberChanged() then
			CONFIG.DiveDownforce = diveForce.number.value
		end
		
		local diveStiffness = Iris.SliderNum({"Dive Stiffness Mult", 0.1, 1, 5}, {number = CONFIG.DiveStiffnessMultiplier})
		if diveStiffness.numberChanged() then
			CONFIG.DiveStiffnessMultiplier = diveStiffness.number.value
		end
		
		Iris.End() -- Tree
		
		-- Movement Settings
		Iris.Tree({"Movement"})
		
		local moveSpeed = Iris.SliderNum({"Base Move Speed", 5, 0, 200}, {number = CONFIG.BaseMoveSpeed})
		if moveSpeed.numberChanged() then
			CONFIG.BaseMoveSpeed = moveSpeed.number.value
		end
		
		local turnSpeed = Iris.SliderNum({"Turn Speed", 0.5, 0, 10}, {number = CONFIG.BaseTurnSpeed})
		if turnSpeed.numberChanged() then
			CONFIG.BaseTurnSpeed = turnSpeed.number.value
		end
		
		local boostMult = Iris.SliderNum({"Boost Multiplier", 0.1, 1, 5}, {number = CONFIG.BoostMultiplier})
		if boostMult.numberChanged() then
			CONFIG.BoostMultiplier = boostMult.number.value
		end
		
		Iris.End() -- Tree
		
		-- World Settings
		Iris.Tree({"World"})
		
		local gravity = Iris.SliderNum({"Driving Gravity", 10, 10, 500}, {number = CONFIG.DrivingGravity})
		if gravity.numberChanged() then
			CONFIG.DrivingGravity = gravity.number.value
			-- Apply immediately if in a machine
			if currentMachine then
				Workspace.Gravity = CONFIG.DrivingGravity
			end
		end
		
		Iris.End() -- Tree
		
		-- Debug Toggles
		Iris.Separator()
		
		local gizmosEnabled = Iris.Checkbox({"Show Gizmos"}, {isChecked = CONFIG.DebugGizmos})
		if gizmosEnabled.checked() or gizmosEnabled.unchecked() then
			CONFIG.DebugGizmos = gizmosEnabled.isChecked.value
		end
		
		local debugMode = Iris.Checkbox({"Debug Mode (Console)"}, {isChecked = CONFIG.DebugMode})
		if debugMode.checked() or debugMode.unchecked() then
			CONFIG.DebugMode = debugMode.isChecked.value
		end
		
		-- Status display
		Iris.Separator()
		Iris.Text({"Status:"})
		Iris.Text({currentMachine and ("Driving: " .. currentMachine.Name) or "Not in machine"})
		Iris.Text({string.format("🚀 Speed: %.1f studs/sec", currentSpeed)})
		if isAirborne then
			Iris.Text({"🛫 AIRBORNE"})
		elseif landingTimer > 0 then
			Iris.Text({string.format("🛬 LANDING (%.1fs)", landingTimer)})
		else
			Iris.Text({"🛞 GROUNDED"})
		end
		if inputState.dive then
			Iris.Text({"⬇️ DIVING"})
		end
		if inputState.boost then
			Iris.Text({"💨 BOOSTING"})
		end
		
		Iris.End() -- Window
	end)
	
	print("[MachineController] Ready! Sit in a machine to drive it.")
	print("  Controls: W/S = Forward/Back, A/D = Turn, Space = Dive, Shift = Boost")
end

return MachineController

