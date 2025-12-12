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

-- Default handling values (applied when no vehicle profile matches)
local DEFAULT_CONFIG = {
	-- Movement speeds
	BaseMoveSpeed = 80,
	BaseTurnSpeed = 3,
	BoostMultiplier = 1.5,
	
	-- Physics tuning
	AccelerationTime = 0.3,
	DecelerationTime = 0.5,
	
	-- Surface alignment
	AlignToSurface = true,
	AlignmentSpeed = 8,
	LandingAlignmentSpeed = 3,
	LandingSmoothTime = 0.5,
	
	-- Air arc alignment
	ArcAlignmentEnabled = true,
	ArcAlignmentSpeed = 5,
	MinArcSpeed = 10,
	
	-- Suspension
	HoverHeight = 3,
	SpringStiffness = 10,
	SpringDamping = 20,
	SpringRestLength = 30,
	MaxSpringExtension = 1,
	
	-- Dive mechanics
	DiveDownforce = 500,
	DiveStiffnessMultiplier = 1.5,
	
	-- World settings
	DrivingGravity = 100,
}

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                    VEHICLE PROFILES (Unique Handling)                       ║
-- ╚════════════════════════════════════════════════════════════════════════════╝
-- Each vehicle can have custom handling. Values override DEFAULT_CONFIG.
-- Vehicle name should match the model name in ReplicatedStorage.Prefabs.Machines

local VEHICLE_PROFILES = {
	-- ═══════════════════════════════════════════════════════════════════════
	-- MACHINE 1 - Balanced Starter
	-- ═══════════════════════════════════════════════════════════════════════
	["machine_1"] = {
		Name = "Starter",
		Description = "Well-balanced. Perfect for beginners.",
		
		BaseMoveSpeed = 80,
		BaseTurnSpeed = 3,
		BoostMultiplier = 1.5,
		
		HoverHeight = 3,
		SpringStiffness = 12,
		SpringDamping = 22,
		
		DiveDownforce = 500,
	},
	
	-- ═══════════════════════════════════════════════════════════════════════
	-- MACHINE 3 - Speeder (Fast & Agile)
	-- ═══════════════════════════════════════════════════════════════════════
	["machine_3"] = {
		Name = "Speeder",
		Description = "Fast and nimble. Light suspension for quick response.",
		
		BaseMoveSpeed = 120,
		BaseTurnSpeed = 4,
		BoostMultiplier = 1.8,
		AccelerationTime = 0.2,
		
		HoverHeight = 2.5,
		SpringStiffness = 15,
		SpringDamping = 25,
		
		DiveDownforce = 400,
		ArcAlignmentSpeed = 7,
	},
	
	-- ═══════════════════════════════════════════════════════════════════════
	-- MACHINE 5 - Tank (Heavy & Bouncy)
	-- ═══════════════════════════════════════════════════════════════════════
	["machine_5"] = {
		Name = "Tank",
		Description = "Heavy and powerful. Bouncy suspension, slow but strong.",
		
		BaseMoveSpeed = 60,
		BaseTurnSpeed = 2,
		BoostMultiplier = 1.3,
		AccelerationTime = 0.5,
		DecelerationTime = 0.8,
		
		HoverHeight = 4,
		SpringStiffness = 6,
		SpringDamping = 12,
		SpringRestLength = 35,
		
		DiveDownforce = 800,
		DiveStiffnessMultiplier = 2,
		ArcAlignmentSpeed = 3,
		
		DrivingGravity = 120,
	},
	
	-- ═══════════════════════════════════════════════════════════════════════
	-- MACHINE 7 - Glider (Floaty Air Control)
	-- ═══════════════════════════════════════════════════════════════════════
	["machine_7"] = {
		Name = "Glider",
		Description = "Floaty with excellent air control. Low gravity feel.",
		
		BaseMoveSpeed = 75,
		BaseTurnSpeed = 3.5,
		BoostMultiplier = 1.4,
		
		HoverHeight = 3.5,
		SpringStiffness = 8,
		SpringDamping = 15,
		MaxSpringExtension = 2,
		
		DiveDownforce = 300,
		ArcAlignmentSpeed = 8,
		MinArcSpeed = 5,
		
		DrivingGravity = 70,
	},
	
	-- ═══════════════════════════════════════════════════════════════════════
	-- MACHINE 8 - Racer (Pure Speed)
	-- ═══════════════════════════════════════════════════════════════════════
	["machine_8"] = {
		Name = "Racer",
		Description = "Built for speed. Stiff suspension, precise control.",
		
		BaseMoveSpeed = 140,
		BaseTurnSpeed = 3.5,
		BoostMultiplier = 2.0,
		AccelerationTime = 0.15,
		
		HoverHeight = 2,
		SpringStiffness = 20,
		SpringDamping = 30,
		SpringRestLength = 25,
		
		DiveDownforce = 600,
		AlignmentSpeed = 12,
		ArcAlignmentSpeed = 10,
		
		DrivingGravity = 110,
	},
	
	-- ═══════════════════════════════════════════════════════════════════════
	-- MACHINE 9 - Stunter (Trick Specialist)
	-- ═══════════════════════════════════════════════════════════════════════
	["machine_9"] = {
		Name = "Stunter",
		Description = "Trick specialist! Great air control and bouncy landings.",
		
		BaseMoveSpeed = 90,
		BaseTurnSpeed = 4.5,
		BoostMultiplier = 1.8,
		AccelerationTime = 0.2,
		DecelerationTime = 0.4,
		
		HoverHeight = 3.5,
		SpringStiffness = 7,
		SpringDamping = 12,
		SpringRestLength = 35,
		MaxSpringExtension = 0.7,
		
		DiveDownforce = 650,
		DiveStiffnessMultiplier = 2.0,
		ArcAlignmentSpeed = 8,
		MinArcSpeed = 8,
		
		DrivingGravity = 85,
	},
	
	-- ═══════════════════════════════════════════════════════════════════════
	-- MACHINE 10 - Bouncer (Super Bouncy)
	-- ═══════════════════════════════════════════════════════════════════════
	["machine_10"] = {
		Name = "Bouncer",
		Description = "Super bouncy! Hard to control but fun.",
		
		BaseMoveSpeed = 70,
		BaseTurnSpeed = 4,
		BoostMultiplier = 1.6,
		
		HoverHeight = 4,
		SpringStiffness = 4,
		SpringDamping = 5,
		SpringRestLength = 40,
		MaxSpringExtension = 0.5,
		
		DiveDownforce = 700,
		DiveStiffnessMultiplier = 2.5,
		ArcAlignmentSpeed = 4,
		
		DrivingGravity = 90,
	},
	
	-- ═══════════════════════════════════════════════════════════════════════
	-- MACHINE 12 - Drifter (Loose Handling)
	-- ═══════════════════════════════════════════════════════════════════════
	["machine_12"] = {
		Name = "Drifter",
		Description = "Loose handling. Slides through turns, great for tricks.",
		
		BaseMoveSpeed = 95,
		BaseTurnSpeed = 5,
		BoostMultiplier = 1.7,
		AccelerationTime = 0.25,
		DecelerationTime = 0.7,
		
		HoverHeight = 3,
		SpringStiffness = 9,
		SpringDamping = 14,
		
		DiveDownforce = 550,
		ArcAlignmentSpeed = 6,
		
		DrivingGravity = 95,
	},
}

-- Active config (merged DEFAULT + current vehicle profile)
local CONFIG = {}
for k, v in pairs(DEFAULT_CONFIG) do
	CONFIG[k] = v
end

-- Debug visualization (always from default, not per-vehicle)
CONFIG.DebugMode = false
CONFIG.DebugGizmos = true

-- Current vehicle profile name
local currentVehicleProfile = "Default"

-- Function to apply a vehicle profile
local function applyVehicleProfile(vehicleName)
	-- Reset to defaults first
	for k, v in pairs(DEFAULT_CONFIG) do
		CONFIG[k] = v
	end
	
	-- Find matching profile
	local profile = VEHICLE_PROFILES[vehicleName]
	if profile then
		-- Apply profile overrides
		for k, v in pairs(profile) do
			if k ~= "Name" and k ~= "Description" then
				CONFIG[k] = v
			end
		end
		currentVehicleProfile = profile.Name or vehicleName
		print(string.format("[MachineController] Applied vehicle profile: %s - %s", 
			currentVehicleProfile, profile.Description or ""))
	else
		currentVehicleProfile = "Default"
		print(string.format("[MachineController] No profile for '%s', using defaults", vehicleName))
	end
	
	-- Apply gravity immediately if in a machine
	if currentMachine then
		Workspace.Gravity = CONFIG.DrivingGravity
	end
end

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

-- Crystal particle settings (synced with server)
local crystalParticleSettings = {
	BurstSize = 6,
	BurstLifetimeMin = 1.5,
	BurstLifetimeMax = 3,
	BurstSpeed = 50,
	BurstCount = 35,
	BurstGravity = -20,
	BurstDrag = 1.5,
	GlowSize = 10,
	GlowLifetimeMin = 1,
	GlowLifetimeMax = 2,
	GlowSpeed = 25,
	GlowCount = 15,
}
local hubService = nil  -- Will be set in KnitStart

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
	
	-- Apply vehicle-specific handling profile based on machine name
	local machineName = machine.Name
	applyVehicleProfile(machineName)
	
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
	
	-- Get HubService for crystal particle settings
	hubService = Knit.GetService("HubService")
	
	-- Fetch initial crystal particle settings from server
	task.spawn(function()
		local success, settings = pcall(function()
			return hubService:GetCrystalParticleSettings()
		end)
		if success and settings then
			crystalParticleSettings = settings
			print("[MachineController] Loaded crystal particle settings from server")
		end
	end)
	
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
		
		-- Crystal Particle Settings
		Iris.Tree({"✨ Crystal Particles"})
		
		Iris.Text({"Burst Particles:"})
		
		local burstSize = Iris.SliderNum({"Burst Size", 0.5, 1, 20}, {number = crystalParticleSettings.BurstSize})
		if burstSize.numberChanged() then
			crystalParticleSettings.BurstSize = burstSize.number.value
			hubService:UpdateCrystalParticleSettings({BurstSize = burstSize.number.value})
		end
		
		local burstLifeMin = Iris.SliderNum({"Lifetime Min", 0.1, 0.1, 10}, {number = crystalParticleSettings.BurstLifetimeMin})
		if burstLifeMin.numberChanged() then
			crystalParticleSettings.BurstLifetimeMin = burstLifeMin.number.value
			hubService:UpdateCrystalParticleSettings({BurstLifetimeMin = burstLifeMin.number.value})
		end
		
		local burstLifeMax = Iris.SliderNum({"Lifetime Max", 0.1, 0.1, 10}, {number = crystalParticleSettings.BurstLifetimeMax})
		if burstLifeMax.numberChanged() then
			crystalParticleSettings.BurstLifetimeMax = burstLifeMax.number.value
			hubService:UpdateCrystalParticleSettings({BurstLifetimeMax = burstLifeMax.number.value})
		end
		
		local burstSpeed = Iris.SliderNum({"Burst Speed", 5, 5, 200}, {number = crystalParticleSettings.BurstSpeed})
		if burstSpeed.numberChanged() then
			crystalParticleSettings.BurstSpeed = burstSpeed.number.value
			hubService:UpdateCrystalParticleSettings({BurstSpeed = burstSpeed.number.value})
		end
		
		local burstCount = Iris.SliderNum({"Burst Count", 1, 1, 100}, {number = crystalParticleSettings.BurstCount})
		if burstCount.numberChanged() then
			crystalParticleSettings.BurstCount = math.floor(burstCount.number.value)
			hubService:UpdateCrystalParticleSettings({BurstCount = math.floor(burstCount.number.value)})
		end
		
		local burstGravity = Iris.SliderNum({"Gravity", 5, -100, 100}, {number = crystalParticleSettings.BurstGravity})
		if burstGravity.numberChanged() then
			crystalParticleSettings.BurstGravity = burstGravity.number.value
			hubService:UpdateCrystalParticleSettings({BurstGravity = burstGravity.number.value})
		end
		
		local burstDrag = Iris.SliderNum({"Drag", 0.1, 0, 10}, {number = crystalParticleSettings.BurstDrag})
		if burstDrag.numberChanged() then
			crystalParticleSettings.BurstDrag = burstDrag.number.value
			hubService:UpdateCrystalParticleSettings({BurstDrag = burstDrag.number.value})
		end
		
		Iris.Separator()
		Iris.Text({"Glow Particles:"})
		
		local glowSize = Iris.SliderNum({"Glow Size", 0.5, 1, 30}, {number = crystalParticleSettings.GlowSize})
		if glowSize.numberChanged() then
			crystalParticleSettings.GlowSize = glowSize.number.value
			hubService:UpdateCrystalParticleSettings({GlowSize = glowSize.number.value})
		end
		
		local glowLifeMin = Iris.SliderNum({"Glow Life Min", 0.1, 0.1, 10}, {number = crystalParticleSettings.GlowLifetimeMin})
		if glowLifeMin.numberChanged() then
			crystalParticleSettings.GlowLifetimeMin = glowLifeMin.number.value
			hubService:UpdateCrystalParticleSettings({GlowLifetimeMin = glowLifeMin.number.value})
		end
		
		local glowLifeMax = Iris.SliderNum({"Glow Life Max", 0.1, 0.1, 10}, {number = crystalParticleSettings.GlowLifetimeMax})
		if glowLifeMax.numberChanged() then
			crystalParticleSettings.GlowLifetimeMax = glowLifeMax.number.value
			hubService:UpdateCrystalParticleSettings({GlowLifetimeMax = glowLifeMax.number.value})
		end
		
		local glowSpeed = Iris.SliderNum({"Glow Speed", 1, 5, 100}, {number = crystalParticleSettings.GlowSpeed})
		if glowSpeed.numberChanged() then
			crystalParticleSettings.GlowSpeed = glowSpeed.number.value
			hubService:UpdateCrystalParticleSettings({GlowSpeed = glowSpeed.number.value})
		end
		
		local glowCount = Iris.SliderNum({"Glow Count", 1, 1, 50}, {number = crystalParticleSettings.GlowCount})
		if glowCount.numberChanged() then
			crystalParticleSettings.GlowCount = math.floor(glowCount.number.value)
			hubService:UpdateCrystalParticleSettings({GlowCount = math.floor(glowCount.number.value)})
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
		
		-- Vehicle Profile Info
		Iris.Separator()
		Iris.Text({string.format("🚗 Vehicle: %s", currentVehicleProfile)})
		
		-- Show profile stats comparison
		local profile = VEHICLE_PROFILES[currentVehicleProfile]
		if profile and profile.Description then
			Iris.Text({profile.Description})
		end
		
		Iris.End() -- Window
	end)
	
	print("[MachineController] Ready! Sit in a machine to drive it.")
	print("  Controls: W/S = Forward/Back, A/D = Turn, Space = Dive, Shift = Boost")
end

return MachineController

