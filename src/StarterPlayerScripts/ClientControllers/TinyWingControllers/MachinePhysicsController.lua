--[[
	MachinePhysicsController
	
	Simple hover physics:
	- 4 corner raycasts to detect ground
	- PID controller to maintain hover height
	- Gizmo visualization
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local Knit = require(Packages.Knit)
local PID = require(Packages.PID)
local Gizmo = require(Packages.imgizmo)
local Iris = require(Packages.iris)

local MachinePhysicsController = Knit.CreateController {
	Name = "MachinePhysicsController",
}

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         CONFIGURATION                                       ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

local CONFIG = {
	-- Hover
	HoverHeight = 3,           -- Target height above ground
	RaycastDistance = 20,      -- How far to cast rays
	
	-- Hover PID Gains
	PID_P = 500,               -- Proportional (stiffness)
	PID_I = 0,                 -- Integral (usually 0)
	PID_D = 100,               -- Derivative (damping)
	MaxForce = 50000,          -- Maximum hover force
	
	-- Surface Alignment
	AlignmentStrength = 50000, -- How strongly to align to surface (higher = stiffer)
	AlignmentDamping = 5000,   -- Damping to prevent oscillation
	
	-- Throttle/Brake (W/S)
	ThrottleForce = 600,       -- Forward thrust (slow)
	BrakeForce = 600,          -- Braking power (slow)
	MaxSpeed = 40,             -- Speed cap (slow)
	ReverseSpeed = 15,         -- Max reverse speed (slow)
	Drag = 3,                  -- Air resistance (higher = more slowdown)
	
	-- Steering (A/D) - Yaw rotation
	SteerTorque = 1800,        -- Yaw turn power (slower)
	YawDamping = 300,          -- Damping when not steering
	
	-- Strafing (Left/Right arrows)
	StrafeForce = 400,         -- Sideways thrust (slow)
	
	-- Pitch Control (Up/Down arrows)
	PitchTorque = 600,         -- Pitch power (slow)
	MaxPitchAngle = 15,        -- Max pitch degrees (lower)
	
	-- Visual Tilt (meshVisual)
	VisualBankAngle = 5,       -- Max bank angle when steering (degrees)
	VisualPitchAngle = 1,      -- Max pitch angle on throttle/brake (degrees)
	VisualStrafeAngle = 5,     -- Max lean angle when strafing (degrees)
	VisualTiltSpeed = 6,       -- How fast visual tilts respond (slower)
	
	-- Debug
	ShowGizmos = true,
}

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         STATE                                               ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

-- Machine references
local currentMachine = nil
local rootPart = nil

-- Physics
local hoverForce = nil
local thrustForce = nil
local alignTorque = nil
local turnTorque = nil
local rootAttachment = nil
local hoverPID = nil
local raycastParams = nil

-- Ray results (for gizmos)
local rayResults = {}
local avgGroundDistance = 0
local avgNormal = Vector3.new(0, 1, 0)

-- Input state
local throttle = 0      -- W/S: 1 = forward, -1 = reverse
local steering = 0      -- A/D: -1 = left, 1 = right
local strafe = 0        -- Arrows: -1 = left, 1 = right
local pitch = 0         -- Arrows: 1 = nose up, -1 = nose down
local currentPitch = 0  -- Current pitch angle

-- Visual mesh
local meshVisual = nil
local meshVisualOffset = CFrame.new()  -- Original offset from RootPart

-- Visual tilt state (smoothed)
local visualBank = 0     -- Current bank angle
local visualPitch = 0    -- Current pitch angle
local visualStrafe = 0   -- Current strafe lean

-- World state
local originalGravity = 196.2

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         SETUP / CLEANUP                                     ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

function MachinePhysicsController:SetupPhysics(machine)
	currentMachine = machine
	rootPart = machine:FindFirstChild("RootPart")
	
	if not rootPart then
		warn("[MachinePhysicsController] No RootPart found!")
		return false
	end
	
	-- Disable built-in controller
	local controllerManager = machine:FindFirstChild("ControllerManager")
	if controllerManager then
		controllerManager.ActiveController = nil
		controllerManager.BaseMoveSpeed = 0
		controllerManager.BaseTurnSpeed = 0
	end
	
	-- Create PID controller
	hoverPID = PID.new(-CONFIG.MaxForce, CONFIG.MaxForce, CONFIG.PID_P, CONFIG.PID_I, CONFIG.PID_D)
	
	-- Setup raycast params (exclude machine and player)
	raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	raycastParams.FilterDescendantsInstances = {machine, player.Character}
	
	-- Create attachment for forces
	rootAttachment = rootPart:FindFirstChild("RootAttachment")
	if not rootAttachment then
		rootAttachment = Instance.new("Attachment")
		rootAttachment.Name = "RootAttachment"
		rootAttachment.Parent = rootPart
	end
	
	-- Create hover force
	hoverForce = Instance.new("VectorForce")
	hoverForce.Name = "HoverForce"
	hoverForce.Attachment0 = rootAttachment
	hoverForce.RelativeTo = Enum.ActuatorRelativeTo.World
	hoverForce.ApplyAtCenterOfMass = true
	hoverForce.Force = Vector3.zero
	hoverForce.Parent = rootPart
	
	-- Create alignment torque (rotates to match surface)
	alignTorque = Instance.new("Torque")
	alignTorque.Name = "AlignTorque"
	alignTorque.Attachment0 = rootAttachment
	alignTorque.RelativeTo = Enum.ActuatorRelativeTo.World
	alignTorque.Torque = Vector3.zero
	alignTorque.Parent = rootPart
	
	-- Create thrust force (W/S throttle)
	thrustForce = Instance.new("VectorForce")
	thrustForce.Name = "ThrustForce"
	thrustForce.Attachment0 = rootAttachment
	thrustForce.RelativeTo = Enum.ActuatorRelativeTo.World
	thrustForce.ApplyAtCenterOfMass = true
	thrustForce.Force = Vector3.zero
	thrustForce.Parent = rootPart
	
	-- Create turn torque (A/D steering)
	turnTorque = Instance.new("Torque")
	turnTorque.Name = "TurnTorque"
	turnTorque.Attachment0 = rootAttachment
	turnTorque.RelativeTo = Enum.ActuatorRelativeTo.World
	turnTorque.Torque = Vector3.zero
	turnTorque.Parent = rootPart
	
	-- Find visual mesh (in Folder/meshVisual)
	local folder = machine:FindFirstChild("Folder")
	if folder then
		meshVisual = folder:FindFirstChild("meshVisual")
		if meshVisual then
			-- Store original offset from RootPart
			meshVisualOffset = rootPart.CFrame:ToObjectSpace(meshVisual.CFrame)
			print("[MachinePhysicsController] Found meshVisual for visual tilting")
		end
	end
	
	-- Reset visual tilt
	visualBank = 0
	visualPitch = 0
	visualStrafe = 0
	
	-- Disable world gravity (we handle our own)
	originalGravity = Workspace.Gravity
	Workspace.Gravity = 0
	
	print("[MachinePhysicsController] Setup complete for:", machine.Name)
	return true
end

function MachinePhysicsController:ClearPhysics()
	if hoverForce then 
		hoverForce:Destroy() 
		hoverForce = nil 
	end
	
	if thrustForce then
		thrustForce:Destroy()
		thrustForce = nil
	end
	
	if alignTorque then
		alignTorque:Destroy()
		alignTorque = nil
	end
	
	if turnTorque then
		turnTorque:Destroy()
		turnTorque = nil
	end
	
	if hoverPID then 
		hoverPID:Destroy() 
		hoverPID = nil 
	end
	
	-- Restore gravity
	Workspace.Gravity = originalGravity
	
	-- Reset mesh visual tilt before clearing reference
	if meshVisual and rootPart then
		meshVisual.CFrame = rootPart.CFrame * meshVisualOffset
	end
	
	currentMachine = nil
	rootPart = nil
	meshVisual = nil
	meshVisualOffset = CFrame.new()
	raycastParams = nil
	rootAttachment = nil
	rayResults = {}
	visualBank = 0
	visualPitch = 0
	visualStrafe = 0
	
	print("[MachinePhysicsController] Cleared")
end

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         PHYSICS UPDATE                                      ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

function MachinePhysicsController:Update(deltaTime)
	if not currentMachine or not rootPart then return end
	if not hoverForce or not hoverPID then return end
	
	local mass = rootPart.AssemblyMass
	local rootCF = rootPart.CFrame
	local rootPos = rootPart.Position
	local rootSize = rootPart.Size
	
	-- ══════════════════════════════════════════════════════════════════════
	-- 4 CORNER RAYCASTS
	-- ══════════════════════════════════════════════════════════════════════
	
	-- Corner offsets (80% from center to edge)
	local halfX = rootSize.X * 0.4
	local halfZ = rootSize.Z * 0.4
	
	local cornerOffsets = {
		Vector3.new( halfX, 0,  halfZ),  -- Front-Right
		Vector3.new(-halfX, 0,  halfZ),  -- Front-Left
		Vector3.new( halfX, 0, -halfZ),  -- Back-Right
		Vector3.new(-halfX, 0, -halfZ),  -- Back-Left
	}
	
	-- Cast rays straight down (world Y)
	local rayDirection = Vector3.new(0, -CONFIG.RaycastDistance, 0)
	
	local hitCount = 0
	local totalDistance = 0
	local totalNormal = Vector3.zero
	rayResults = {}
	
	for i, offset in ipairs(cornerOffsets) do
		-- Transform offset to world space
		local worldOffset = rootCF:VectorToWorldSpace(offset)
		local rayOrigin = rootPos + worldOffset
		
		local result = Workspace:Raycast(rayOrigin, rayDirection, raycastParams)
		
		if result then
			hitCount = hitCount + 1
			totalDistance = totalDistance + result.Distance
			totalNormal = totalNormal + result.Normal
			
			rayResults[i] = {
				origin = rayOrigin,
				hit = result.Position,
				normal = result.Normal,
				distance = result.Distance,
			}
		else
			rayResults[i] = {
				origin = rayOrigin,
				hit = nil,
				normal = nil,
				distance = CONFIG.RaycastDistance,
			}
		end
	end
	
	-- Calculate average ground distance and normal
	if hitCount > 0 then
		avgGroundDistance = totalDistance / hitCount
		avgNormal = (totalNormal / hitCount).Unit
	else
		avgGroundDistance = CONFIG.RaycastDistance
		avgNormal = Vector3.new(0, 1, 0)
	end
	
	-- ══════════════════════════════════════════════════════════════════════
	-- PID HOVER FORCE
	-- ══════════════════════════════════════════════════════════════════════
	
	-- PID calculates force needed to reach target height
	local pidOutput = hoverPID:Calculate(CONFIG.HoverHeight, avgGroundDistance, deltaTime)
	
	-- Apply force in the direction of surface normal (not just world up)
	local forceVector = avgNormal * pidOutput * mass
	
	-- Safety check
	if forceVector == forceVector then  -- NaN check
		hoverForce.Force = forceVector
	end
	
	-- ══════════════════════════════════════════════════════════════════════
	-- SURFACE ALIGNMENT TORQUE (pitch/roll only, not yaw)
	-- ══════════════════════════════════════════════════════════════════════
	
	local shipUp = rootCF.UpVector
	local angularVelocity = rootPart.AssemblyAngularVelocity
	
	-- Calculate rotation needed to align ship up with surface normal
	local alignAxis = shipUp:Cross(avgNormal)
	local alignAngle = math.acos(math.clamp(shipUp:Dot(avgNormal), -1, 1))
	
	local torqueVector = Vector3.zero
	
	if alignAxis.Magnitude > 0.001 and alignAngle > 0.001 then
		alignAxis = alignAxis.Unit
		
		-- Proportional torque (stronger when more misaligned)
		local proportionalTorque = alignAxis * alignAngle * CONFIG.AlignmentStrength
		
		-- Damping torque - only damp pitch/roll, NOT yaw (so steering works)
		-- Remove the yaw component from angular velocity before damping
		local yawComponent = shipUp * angularVelocity:Dot(shipUp)
		local pitchRollVelocity = angularVelocity - yawComponent
		local dampingTorque = -pitchRollVelocity * CONFIG.AlignmentDamping
		
		torqueVector = proportionalTorque + dampingTorque
	else
		-- Already aligned - only damp pitch/roll
		local yawComponent = shipUp * angularVelocity:Dot(shipUp)
		local pitchRollVelocity = angularVelocity - yawComponent
		torqueVector = -pitchRollVelocity * CONFIG.AlignmentDamping
	end
	
	-- Safety check and apply
	if torqueVector == torqueVector then  -- NaN check
		alignTorque.Torque = torqueVector
	end
	
	-- ══════════════════════════════════════════════════════════════════════
	-- INPUT READING
	-- ══════════════════════════════════════════════════════════════════════
	
	-- Throttle/Brake (W/S)
	throttle = 0
	if UserInputService:IsKeyDown(Enum.KeyCode.W) then throttle = 1 end
	if UserInputService:IsKeyDown(Enum.KeyCode.S) then throttle = -1 end
	
	-- Steering (A/D) - inverted
	steering = 0
	if UserInputService:IsKeyDown(Enum.KeyCode.A) then steering = 1 end
	if UserInputService:IsKeyDown(Enum.KeyCode.D) then steering = -1 end
	
	-- Strafe (Left/Right arrows)
	strafe = 0
	if UserInputService:IsKeyDown(Enum.KeyCode.Left) then strafe = -1 end
	if UserInputService:IsKeyDown(Enum.KeyCode.Right) then strafe = 1 end
	
	-- Pitch (Up/Down arrows)
	pitch = 0
	if UserInputService:IsKeyDown(Enum.KeyCode.Up) then pitch = 1 end
	if UserInputService:IsKeyDown(Enum.KeyCode.Down) then pitch = -1 end
	
	-- ══════════════════════════════════════════════════════════════════════
	-- THROTTLE / BRAKE (W/S)
	-- ══════════════════════════════════════════════════════════════════════
	
	local velocity = rootPart.AssemblyLinearVelocity
	local shipForward = rootCF.LookVector
	local shipRight = rootCF.RightVector
	local forwardSpeed = velocity:Dot(shipForward)
	
	local thrustVector = Vector3.zero
	
	if throttle > 0 then
		-- Accelerate forward
		if forwardSpeed < CONFIG.MaxSpeed then
			thrustVector = shipForward * CONFIG.ThrottleForce * throttle
		end
	elseif throttle < 0 then
		-- Brake or reverse
		if forwardSpeed > 0 then
			-- Braking
			thrustVector = -shipForward * CONFIG.BrakeForce
		elseif forwardSpeed > -CONFIG.ReverseSpeed then
			-- Reversing
			thrustVector = shipForward * CONFIG.ThrottleForce * 0.5 * throttle
		end
	end
	
	-- ══════════════════════════════════════════════════════════════════════
	-- STRAFE (Left/Right arrows)
	-- ══════════════════════════════════════════════════════════════════════
	
	if strafe ~= 0 then
		thrustVector = thrustVector + shipRight * CONFIG.StrafeForce * strafe
	end
	
	-- ══════════════════════════════════════════════════════════════════════
	-- DRAG (when no throttle)
	-- ══════════════════════════════════════════════════════════════════════
	
	if throttle == 0 and velocity.Magnitude > 0.5 then
		thrustVector = thrustVector - velocity * CONFIG.Drag
	end
	
	-- Apply thrust
	local thrustForceVec = thrustVector * mass
	if thrustForceVec == thrustForceVec then
		thrustForce.Force = thrustForceVec
	end
	
	-- ══════════════════════════════════════════════════════════════════════
	-- STEERING (A/D) - Yaw rotation around ship's up axis
	-- ══════════════════════════════════════════════════════════════════════
	
	local shipUp = rootCF.UpVector
	local steerTorqueVec = Vector3.zero
	
	if steering ~= 0 then
		-- Apply yaw rotation around the ship's up vector
		steerTorqueVec = shipUp * CONFIG.SteerTorque * steering
	else
		-- Dampen yaw rotation when not steering
		local yawVelocity = angularVelocity:Dot(shipUp)
		steerTorqueVec = -shipUp * yawVelocity * CONFIG.YawDamping
	end
	
	-- ══════════════════════════════════════════════════════════════════════
	-- PITCH CONTROL (Up/Down arrows)
	-- ══════════════════════════════════════════════════════════════════════
	
	local pitchTorqueVec = Vector3.zero
	if pitch ~= 0 then
		-- Update pitch angle
		currentPitch = currentPitch + pitch * 60 * deltaTime
		currentPitch = math.clamp(currentPitch, -CONFIG.MaxPitchAngle, CONFIG.MaxPitchAngle)
	else
		-- Return to neutral
		currentPitch = currentPitch * (1 - 3 * deltaTime)
	end
	
	-- Apply pitch torque around right axis
	pitchTorqueVec = shipRight * math.rad(currentPitch) * CONFIG.PitchTorque
	
	-- Combine steering and pitch torques
	local combinedTurnTorque = steerTorqueVec + pitchTorqueVec
	if combinedTurnTorque == combinedTurnTorque then
		turnTorque.Torque = combinedTurnTorque
	end
	
	-- ══════════════════════════════════════════════════════════════════════
	-- VISUAL MESH TILTING
	-- ══════════════════════════════════════════════════════════════════════
	
	if meshVisual then
		local tiltSpeed = CONFIG.VisualTiltSpeed * deltaTime
		
		-- Target angles based on input
		local targetBank = -steering * CONFIG.VisualBankAngle      -- Bank into turns
		local targetPitch = -throttle * CONFIG.VisualPitchAngle    -- Pitch back on accel, forward on brake
		local targetStrafe = -strafe * CONFIG.VisualStrafeAngle    -- Lean into strafe
		
		-- Smooth interpolation
		visualBank = visualBank + (targetBank - visualBank) * math.min(tiltSpeed, 1)
		visualPitch = visualPitch + (targetPitch - visualPitch) * math.min(tiltSpeed, 1)
		visualStrafe = visualStrafe + (targetStrafe - visualStrafe) * math.min(tiltSpeed, 1)
		
		-- Calculate visual rotation (relative to RootPart)
		local visualRotation = CFrame.Angles(
			math.rad(visualPitch),           -- Pitch (X axis)
			0,                                -- No yaw offset
			math.rad(visualBank + visualStrafe)  -- Bank + strafe lean (Z axis)
		)
		
		-- Apply to meshVisual: RootPart position + original offset + visual rotation
		meshVisual.CFrame = rootPart.CFrame * meshVisualOffset * visualRotation
	end
	
	-- ══════════════════════════════════════════════════════════════════════
	-- GIZMOS
	-- ══════════════════════════════════════════════════════════════════════
	
	if CONFIG.ShowGizmos then
		self:DrawGizmos()
	end
end

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         GIZMOS                                              ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

function MachinePhysicsController:DrawGizmos()
	if not rootPart then return end
	
	local rootPos = rootPart.Position
	
	-- Colors
	local rayHitColor = Color3.fromRGB(0, 255, 100)      -- Green for hits
	local rayMissColor = Color3.fromRGB(255, 50, 50)    -- Red for misses
	local hitPointColor = Color3.fromRGB(255, 255, 0)   -- Yellow for hit points
	local normalColor = Color3.fromRGB(0, 200, 255)     -- Cyan for normals
	local hoverRingColor = Color3.fromRGB(100, 255, 150) -- Light green for hover ring
	local forceColor = Color3.fromRGB(255, 100, 255)    -- Magenta for force
	
	-- Draw each corner ray
	for i, ray in ipairs(rayResults) do
		if ray.hit then
			-- Line from origin to hit point (green)
			Gizmo.PushProperty("Color3", rayHitColor)
			Gizmo.Arrow:Draw(ray.origin, ray.hit, 0.05, 0.15, 6)
			
			-- Hit point sphere (yellow)
			Gizmo.PushProperty("Color3", hitPointColor)
			Gizmo.Sphere:Draw(CFrame.new(ray.hit), 0.3, 8, 360)
			
			-- Surface normal at hit (cyan arrow)
			Gizmo.PushProperty("Color3", normalColor)
			Gizmo.Arrow:Draw(ray.hit, ray.hit + ray.normal * 2, 0.1, 0.3, 8)
		else
			-- Ray miss (red arrow showing full length)
			Gizmo.PushProperty("Color3", rayMissColor)
			local endPoint = ray.origin + Vector3.new(0, -CONFIG.RaycastDistance, 0)
			Gizmo.Arrow:Draw(ray.origin, endPoint, 0.05, 0.15, 6)
		end
	end
	
	-- Draw average normal from center (cyan)
	Gizmo.PushProperty("Color3", normalColor)
	Gizmo.Arrow:Draw(rootPos, rootPos + avgNormal * 4, 0.15, 0.5, 8)
	
	-- Draw target hover height ring
	Gizmo.PushProperty("Color3", hoverRingColor)
	local hoverTargetPos = rootPos - Vector3.new(0, CONFIG.HoverHeight, 0)
	Gizmo.Circle:Draw(CFrame.new(hoverTargetPos, hoverTargetPos + Vector3.new(0, 1, 0)), 2, 16, 360)
	
	-- Draw current ground distance ring
	local currentGroundPos = rootPos - Vector3.new(0, avgGroundDistance, 0)
	Gizmo.PushProperty("Color3", hitPointColor)
	Gizmo.Circle:Draw(CFrame.new(currentGroundPos, currentGroundPos + Vector3.new(0, 1, 0)), 1.5, 16, 360)
	
	-- Draw hover force arrow (magenta)
	if hoverForce then
		local forceDir = hoverForce.Force
		if forceDir.Magnitude > 10 then
			Gizmo.PushProperty("Color3", forceColor)
			local forceScale = math.clamp(forceDir.Magnitude / 10000, 0.5, 5)
			Gizmo.Arrow:Draw(rootPos, rootPos + forceDir.Unit * forceScale, 0.2, 0.6, 8)
		end
	end
	
	-- Uncomment to draw ground plane connecting hit points:
	-- local hitPoints = {}
	-- for _, ray in ipairs(rayResults) do
	-- 	if ray.hit then
	-- 		table.insert(hitPoints, ray.hit)
	-- 	end
	-- end
	-- if #hitPoints >= 3 then
	-- 	Gizmo.PushProperty("Color3", rayHitColor)
	-- 	for i = 1, #hitPoints do
	-- 		local nextI = (i % #hitPoints) + 1
	-- 		Gizmo.Ray:Draw(hitPoints[i], hitPoints[nextI] - hitPoints[i])
	-- 	end
	-- end
end

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         PUBLIC API                                          ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

function MachinePhysicsController:IsActive()
	return currentMachine ~= nil
end

function MachinePhysicsController:GetMachine()
	return currentMachine
end

function MachinePhysicsController:GetRootPart()
	return rootPart
end

function MachinePhysicsController:GetGroundDistance()
	return avgGroundDistance
end

function MachinePhysicsController:GetConfig()
	return CONFIG
end

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         KNIT LIFECYCLE                                      ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

function MachinePhysicsController:KnitInit()
	-- Initialize Iris
	Iris.Init()
end

function MachinePhysicsController:KnitStart()
	-- Main physics update loop
	RunService.Heartbeat:Connect(function(deltaTime)
		if currentMachine then
			self:Update(deltaTime)
		end
	end)
	
	-- Iris GUI - Connect ONCE, Iris handles its own render loop
	Iris:Connect(function()
		if not currentMachine then return end
		
		Iris.Window({"Machine Physics Tuning"})
		
		-- ═══════════════════════════════════════════════════════════════
		-- HOVER SETTINGS
		-- ═══════════════════════════════════════════════════════════════
		if Iris.CollapsingHeader({"Hover Settings"}).state.isUncollapsed.value then
			local hoverHeight = Iris.SliderNum({"Hover Height", 0.1, 1, 10}, {number = Iris.State(CONFIG.HoverHeight)})
			if hoverHeight.numberChanged() then CONFIG.HoverHeight = hoverHeight.number:get() end
			
			local rayDist = Iris.SliderNum({"Raycast Distance", 1, 5, 50}, {number = Iris.State(CONFIG.RaycastDistance)})
			if rayDist.numberChanged() then CONFIG.RaycastDistance = rayDist.number:get() end
			
			Iris.Separator()
			Iris.Text({"PID Gains"})
			
			local pidP = Iris.SliderNum({"P (Stiffness)", 10, 0, 2000}, {number = Iris.State(CONFIG.PID_P)})
			if pidP.numberChanged() then 
				CONFIG.PID_P = pidP.number:get()
				if hoverPID then hoverPID:SetPGain(CONFIG.PID_P) end
			end
			
			local pidI = Iris.SliderNum({"I (Integral)", 1, 0, 100}, {number = Iris.State(CONFIG.PID_I)})
			if pidI.numberChanged() then 
				CONFIG.PID_I = pidI.number:get()
				if hoverPID then hoverPID:SetIGain(CONFIG.PID_I) end
			end
			
			local pidD = Iris.SliderNum({"D (Damping)", 10, 0, 500}, {number = Iris.State(CONFIG.PID_D)})
			if pidD.numberChanged() then 
				CONFIG.PID_D = pidD.number:get()
				if hoverPID then hoverPID:SetDGain(CONFIG.PID_D) end
			end
			
			local maxForce = Iris.SliderNum({"Max Force", 1000, 0, 200000}, {number = Iris.State(CONFIG.MaxForce)})
			if maxForce.numberChanged() then CONFIG.MaxForce = maxForce.number:get() end
		end
		Iris.End()
		
		-- ═══════════════════════════════════════════════════════════════
		-- SURFACE ALIGNMENT
		-- ═══════════════════════════════════════════════════════════════
		if Iris.CollapsingHeader({"Surface Alignment"}).state.isUncollapsed.value then
			local alignStr = Iris.SliderNum({"Alignment Strength", 1000, 0, 150000}, {number = Iris.State(CONFIG.AlignmentStrength)})
			if alignStr.numberChanged() then CONFIG.AlignmentStrength = alignStr.number:get() end
			
			local alignDamp = Iris.SliderNum({"Alignment Damping", 100, 0, 20000}, {number = Iris.State(CONFIG.AlignmentDamping)})
			if alignDamp.numberChanged() then CONFIG.AlignmentDamping = alignDamp.number:get() end
		end
		Iris.End()
		
		-- ═══════════════════════════════════════════════════════════════
		-- THROTTLE & MOVEMENT
		-- ═══════════════════════════════════════════════════════════════
		if Iris.CollapsingHeader({"Throttle & Movement"}).state.isUncollapsed.value then
			local throttleForce = Iris.SliderNum({"Throttle Force", 100, 0, 20000}, {number = Iris.State(CONFIG.ThrottleForce)})
			if throttleForce.numberChanged() then CONFIG.ThrottleForce = throttleForce.number:get() end
			
			local brakeForce = Iris.SliderNum({"Brake Force", 100, 0, 20000}, {number = Iris.State(CONFIG.BrakeForce)})
			if brakeForce.numberChanged() then CONFIG.BrakeForce = brakeForce.number:get() end
			
			local maxSpeed = Iris.SliderNum({"Max Speed", 5, 10, 300}, {number = Iris.State(CONFIG.MaxSpeed)})
			if maxSpeed.numberChanged() then CONFIG.MaxSpeed = maxSpeed.number:get() end
			
			local reverseSpeed = Iris.SliderNum({"Reverse Speed", 5, 5, 100}, {number = Iris.State(CONFIG.ReverseSpeed)})
			if reverseSpeed.numberChanged() then CONFIG.ReverseSpeed = reverseSpeed.number:get() end
			
			local drag = Iris.SliderNum({"Drag", 0.1, 0, 10}, {number = Iris.State(CONFIG.Drag)})
			if drag.numberChanged() then CONFIG.Drag = drag.number:get() end
		end
		Iris.End()
		
		-- ═══════════════════════════════════════════════════════════════
		-- STEERING (YAW)
		-- ═══════════════════════════════════════════════════════════════
		if Iris.CollapsingHeader({"Steering (A/D)"}).state.isUncollapsed.value then
			local steerTorque = Iris.SliderNum({"Steer Torque", 1000, 0, 100000}, {number = Iris.State(CONFIG.SteerTorque)})
			if steerTorque.numberChanged() then CONFIG.SteerTorque = steerTorque.number:get() end
			
			local yawDamp = Iris.SliderNum({"Yaw Damping", 10, 0, 1000}, {number = Iris.State(CONFIG.YawDamping)})
			if yawDamp.numberChanged() then CONFIG.YawDamping = yawDamp.number:get() end
		end
		Iris.End()
		
		-- ═══════════════════════════════════════════════════════════════
		-- STRAFING
		-- ═══════════════════════════════════════════════════════════════
		if Iris.CollapsingHeader({"Strafing (Arrows)"}).state.isUncollapsed.value then
			local strafeForce = Iris.SliderNum({"Strafe Force", 100, 0, 10000}, {number = Iris.State(CONFIG.StrafeForce)})
			if strafeForce.numberChanged() then CONFIG.StrafeForce = strafeForce.number:get() end
		end
		Iris.End()
		
		-- ═══════════════════════════════════════════════════════════════
		-- PITCH CONTROL
		-- ═══════════════════════════════════════════════════════════════
		if Iris.CollapsingHeader({"Pitch Control (Arrows)"}).state.isUncollapsed.value then
			local pitchTorque = Iris.SliderNum({"Pitch Torque", 100, 0, 10000}, {number = Iris.State(CONFIG.PitchTorque)})
			if pitchTorque.numberChanged() then CONFIG.PitchTorque = pitchTorque.number:get() end
			
			local maxPitch = Iris.SliderNum({"Max Pitch Angle", 1, 0, 45}, {number = Iris.State(CONFIG.MaxPitchAngle)})
			if maxPitch.numberChanged() then CONFIG.MaxPitchAngle = maxPitch.number:get() end
		end
		Iris.End()
		
		-- ═══════════════════════════════════════════════════════════════
		-- VISUAL TILT
		-- ═══════════════════════════════════════════════════════════════
		if Iris.CollapsingHeader({"Visual Tilt"}).state.isUncollapsed.value then
			local bankAngle = Iris.SliderNum({"Bank Angle", 1, 0, 45}, {number = Iris.State(CONFIG.VisualBankAngle)})
			if bankAngle.numberChanged() then CONFIG.VisualBankAngle = bankAngle.number:get() end
			
			local pitchAngle = Iris.SliderNum({"Pitch Angle", 1, 0, 30}, {number = Iris.State(CONFIG.VisualPitchAngle)})
			if pitchAngle.numberChanged() then CONFIG.VisualPitchAngle = pitchAngle.number:get() end
			
			local strafeAngle = Iris.SliderNum({"Strafe Angle", 1, 0, 30}, {number = Iris.State(CONFIG.VisualStrafeAngle)})
			if strafeAngle.numberChanged() then CONFIG.VisualStrafeAngle = strafeAngle.number:get() end
			
			local tiltSpeed = Iris.SliderNum({"Tilt Speed", 0.5, 1, 20}, {number = Iris.State(CONFIG.VisualTiltSpeed)})
			if tiltSpeed.numberChanged() then CONFIG.VisualTiltSpeed = tiltSpeed.number:get() end
		end
		Iris.End()
		
		-- ═══════════════════════════════════════════════════════════════
		-- DEBUG & INFO
		-- ═══════════════════════════════════════════════════════════════
		if Iris.CollapsingHeader({"Debug & Info"}).state.isUncollapsed.value then
			local showGizmos = Iris.Checkbox({"Show Gizmos"}, {isChecked = Iris.State(CONFIG.ShowGizmos)})
			if showGizmos.checked() or showGizmos.unchecked() then 
				CONFIG.ShowGizmos = showGizmos.isChecked:get() 
			end
			
			Iris.Separator()
			Iris.Text({"Status"})
			
			if rootPart then
				local speed = rootPart.AssemblyLinearVelocity.Magnitude
				Iris.Text({string.format("Speed: %.1f studs/s", speed)})
				Iris.Text({string.format("Ground Dist: %.2f", avgGroundDistance or 0)})
				Iris.Text({string.format("Throttle: %d | Steering: %d", throttle, steering)})
				Iris.Text({string.format("Strafe: %d | Pitch: %d", strafe, pitch)})
			end
		end
		Iris.End()
		
		Iris.End() -- Window
	end)
	
	print("[MachinePhysicsController] Ready - Simple hover mode with Iris GUI")
end

return MachinePhysicsController
