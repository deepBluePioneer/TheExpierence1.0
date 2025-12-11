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

local Packages = ReplicatedStorage:WaitForChild("Packages")
local Knit = require(Packages.Knit)

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
	AlignmentSpeed = 8,          -- How fast to align (higher = snappier)
	
	-- Input
	DebugMode = false,           -- Print debug info
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
}

-- Surface alignment state
local currentUpVector = Vector3.new(0, 1, 0)  -- Smoothed up vector for alignment

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         INPUT HANDLING                                      ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

local keyStates = {
	W = false, S = false,
	A = false, D = false,
	Up = false, Down = false,
	Left = false, Right = false,
	Space = false,
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
	
	-- Boost
	inputState.boost = keyStates.Space
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
	
	if CONFIG.DebugMode then
		print("[MachineController] Machine configured:", machine.Name)
		print("  BaseMoveSpeed:", controllerManager.BaseMoveSpeed)
		print("  BaseTurnSpeed:", controllerManager.BaseTurnSpeed)
		print("  Surface alignment:", CONFIG.AlignToSurface)
		print("  GroundSensor:", groundSensor and "Found" or "Not found")
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
	
	currentMachine = nil
	controllerManager = nil
	groundController = nil
	groundSensor = nil
	seat = nil
	currentUpVector = Vector3.new(0, 1, 0)
	
	if CONFIG.DebugMode then
		print("[MachineController] Exited machine")
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
	
	if CONFIG.AlignToSurface and groundSensor then
		-- Use the GroundSensor's HitNormal - already computed by the physics system!
		local sensedPart = groundSensor.SensedPart
		if sensedPart then
			-- We have ground contact - use the hit normal
			targetUpVector = groundSensor.HitNormal
		end
		-- If no ground contact, keep default up vector (airborne)
	end
	
	-- Smoothly interpolate toward the target up vector
	local alignSpeed = CONFIG.AlignmentSpeed * deltaTime
	currentUpVector = currentUpVector:Lerp(targetUpVector, math.min(alignSpeed, 1))
	
	-- Update the ControllerManager's UpDirection for alignment
	controllerManager.UpDirection = currentUpVector
	
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
	
	-- Debug output
	if CONFIG.DebugMode and (inputState.forward ~= 0 or inputState.turn ~= 0) then
		if math.floor(tick() * 2) % 2 == 0 then
			print(string.format("[Machine] Move: %.1f | Turn: %.1f | Up: (%.2f, %.2f, %.2f)",
				inputState.forward, inputState.turn,
				currentUpVector.X, currentUpVector.Y, currentUpVector.Z))
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
	
	print("[MachineController] Ready! Sit in a machine to drive it.")
	print("  Controls: W/S = Forward/Back, A/D = Turn, Space = Boost")
end

return MachineController

