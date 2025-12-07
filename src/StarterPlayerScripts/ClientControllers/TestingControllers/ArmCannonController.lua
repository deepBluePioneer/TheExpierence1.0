--[[
	ArmCannonController
	Handles arm cannon using ViewportFrame with dynamic motion effects
]]

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")

local Packages = game:GetService("ReplicatedStorage"):WaitForChild("Packages")
local Knit = require(Packages.Knit)

local CONFIG = require(script.Parent.LocomotionConfig)

local ArmCannonController = Knit.CreateController {
	Name = "ArmCannonController",
	
	-- State
	_character = nil,
	_hrp = nil,
	_humanoid = nil,
	
	-- Viewport system
	_screenGui = nil,
	_viewportFrame = nil,
	_viewportCamera = nil,
	_cannonModel = nil,
	_cannonParts = {},
	
	-- World-space cannon (for raycasting/hit detection)
	_worldCannon = nil,
	_worldCannonParts = {},
	
	-- Recoil (barrel slide)
	_recoilOffset = 0,
	
	-- Cannon positioning
	_cannonOffset = CFrame.new(0.8, -0.5, -1.5),  -- Right, Down, Forward from camera
	_cannonFOV = 70,
	
	-- === MOTION STATE ===
	_time = 0,
	_lastCameraLook = nil,
	_smoothedLook = nil,
	_walkBobPhase = 0,
	_landingDip = 0,
	_wasGrounded = true,
	_lastVerticalVel = 0,
	
	-- Recoil kick state
	_recoilKickBack = 0,      -- Current kick-back amount
	_recoilKickUp = 0,        -- Current kick-up rotation
	_recoilKickSide = 0,      -- Current sideways kick
	_recoilVelocityBack = 0,  -- Velocity for spring physics
	_recoilVelocityUp = 0,
	_recoilVelocitySide = 0,
}

-- === MOTION CONFIG ===
local MOTION = {
	-- Idle sway (breathing effect)
	IdleSwayAmount = 0.015,      -- How much the cannon sways
	IdleSwaySpeed = 1.5,         -- Speed of idle sway
	IdleRotationAmount = 0.3,    -- Degrees of rotation sway
	
	-- Walk bob
	WalkBobAmount = 0.04,        -- Vertical bob amount
	WalkBobSpeed = 10,           -- Bob speed (synced to footsteps)
	WalkSideAmount = 0.02,       -- Side-to-side sway
	WalkRotationAmount = 1.5,    -- Rotation during walk
	
	-- Sprint bob (more aggressive)
	SprintBobMultiplier = 1.8,   -- Multiply walk bob when sprinting
	SprintSpeedMultiplier = 1.3, -- Faster bob when sprinting
	
	-- Recoil kick (whole cannon movement on fire)
	RecoilKickBack = 0.12,       -- How far cannon kicks back
	RecoilKickUp = 4,            -- Degrees cannon kicks up
	RecoilKickSide = 1.5,        -- Random sideways kick (degrees)
	RecoilSpring = 80,           -- Spring stiffness (higher = snappier)
	RecoilDamping = 8,           -- Damping (higher = less oscillation)
	RecoilRecoverySpeed = 12,    -- How fast it returns to center
	
	-- Camera lag (weighty feel)
	CameraLagAmount = 0.08,      -- How much cannon lags behind camera rotation
	CameraLagSmoothing = 0.15,   -- How fast it catches up (lower = more lag)
	
	-- Landing impact
	LandingDipAmount = 0.15,     -- How much cannon dips on landing
	LandingDipRecovery = 8,      -- How fast it recovers
	LandingVelocityThreshold = -10, -- Minimum fall speed to trigger dip
	
	-- Jump
	JumpRiseAmount = 0.03,       -- Slight rise when jumping
}

-- === VIEWPORT SETUP ===

function ArmCannonController:CreateViewport()
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")
	
	-- Create ScreenGui
	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "ArmCannonViewport"
	screenGui.ResetOnSpawn = false
	screenGui.IgnoreGuiInset = true
	screenGui.DisplayOrder = 10
	screenGui.Parent = playerGui
	self._screenGui = screenGui
	
	-- Create ViewportFrame (full screen)
	local viewportFrame = Instance.new("ViewportFrame")
	viewportFrame.Name = "CannonViewport"
	viewportFrame.Size = UDim2.new(1, 0, 1, 0)
	viewportFrame.Position = UDim2.new(0, 0, 0, 0)
	viewportFrame.BackgroundTransparency = 1
	viewportFrame.ImageTransparency = 0
	viewportFrame.LightDirection = Vector3.new(-1, -1, -1)
	viewportFrame.LightColor = Color3.new(1, 1, 1)
	viewportFrame.Ambient = Color3.fromRGB(150, 150, 150)
	viewportFrame.Parent = screenGui
	self._viewportFrame = viewportFrame
	
	-- Create camera for viewport
	local viewportCamera = Instance.new("Camera")
	viewportCamera.FieldOfView = self._cannonFOV
	viewportCamera.Parent = viewportFrame
	viewportFrame.CurrentCamera = viewportCamera
	self._viewportCamera = viewportCamera
end

-- === CANNON CREATION ===

function ArmCannonController:CreateCannonModel(parent)
	local cannonModel = Instance.new("Model")
	cannonModel.Name = "ArmCannon"
	
	local parts = {}
	
	-- 1. Shoulder Mount
	local shoulderMount = Instance.new("Part")
	shoulderMount.Name = "ShoulderMount"
	shoulderMount.Shape = Enum.PartType.Ball
	shoulderMount.Size = Vector3.new(0.8, 0.8, 0.8)
	shoulderMount.Color = CONFIG.CannonAccentColor
	shoulderMount.Material = Enum.Material.Metal
	shoulderMount.CanCollide = false
	shoulderMount.Anchored = true
	shoulderMount.Parent = cannonModel
	table.insert(parts, shoulderMount)
	
	-- 2. Upper Section
	local upperSection = Instance.new("Part")
	upperSection.Name = "UpperSection"
	upperSection.Size = Vector3.new(CONFIG.CannonBaseWidth, 0.8, CONFIG.CannonBaseWidth)
	upperSection.Color = CONFIG.CannonColor
	upperSection.Material = Enum.Material.SmoothPlastic
	upperSection.CanCollide = false
	upperSection.Anchored = true
	upperSection.Parent = cannonModel
	local upperMesh = Instance.new("SpecialMesh")
	upperMesh.MeshType = Enum.MeshType.Cylinder
	upperMesh.Parent = upperSection
	table.insert(parts, upperSection)
	
	-- 3. Elbow Ring
	local elbowRing = Instance.new("Part")
	elbowRing.Name = "ElbowRing"
	elbowRing.Shape = Enum.PartType.Cylinder
	elbowRing.Size = Vector3.new(0.15, 0.7, 0.7)
	elbowRing.Color = CONFIG.CannonAccentColor
	elbowRing.Material = Enum.Material.Metal
	elbowRing.CanCollide = false
	elbowRing.Anchored = true
	elbowRing.Parent = cannonModel
	table.insert(parts, elbowRing)
	
	-- 4. Main Body
	local mainBody = Instance.new("Part")
	mainBody.Name = "MainBody"
	mainBody.Size = Vector3.new(CONFIG.CannonBaseWidth * 1.2, 1.2, CONFIG.CannonBaseWidth * 1.2)
	mainBody.Color = CONFIG.CannonColor
	mainBody.Material = Enum.Material.SmoothPlastic
	mainBody.CanCollide = false
	mainBody.Anchored = true
	mainBody.Parent = cannonModel
	local mainMesh = Instance.new("SpecialMesh")
	mainMesh.MeshType = Enum.MeshType.Cylinder
	mainMesh.Parent = mainBody
	table.insert(parts, mainBody)
	
	-- 5. Barrel
	local barrel = Instance.new("Part")
	barrel.Name = "Barrel"
	barrel.Size = Vector3.new(CONFIG.CannonTipWidth, 0.8, CONFIG.CannonTipWidth)
	barrel.Color = CONFIG.CannonAccentColor
	barrel.Material = Enum.Material.Metal
	barrel.CanCollide = false
	barrel.Anchored = true
	barrel.Parent = cannonModel
	local barrelMesh = Instance.new("SpecialMesh")
	barrelMesh.MeshType = Enum.MeshType.Cylinder
	barrelMesh.Parent = barrel
	table.insert(parts, barrel)
	
	-- 6. Barrel Tip
	local barrelTip = Instance.new("Part")
	barrelTip.Name = "BarrelTip"
	barrelTip.Shape = Enum.PartType.Cylinder
	barrelTip.Size = Vector3.new(0.1, CONFIG.CannonTipWidth * 0.8, CONFIG.CannonTipWidth * 0.8)
	barrelTip.Color = CONFIG.CannonGlowColor
	barrelTip.Material = Enum.Material.Neon
	barrelTip.CanCollide = false
	barrelTip.Anchored = true
	barrelTip.Parent = cannonModel
	table.insert(parts, barrelTip)
	
	-- 7. Energy Core
	local energyCore = Instance.new("Part")
	energyCore.Name = "EnergyCore"
	energyCore.Shape = Enum.PartType.Ball
	energyCore.Size = Vector3.new(0.3, 0.3, 0.3)
	energyCore.Color = CONFIG.CannonGlowColor
	energyCore.Material = Enum.Material.Neon
	energyCore.CanCollide = false
	energyCore.Anchored = true
	energyCore.Parent = cannonModel
	table.insert(parts, energyCore)
	
	-- 8-9. Side Vents
	for i = 1, 2 do
		local vent = Instance.new("Part")
		vent.Name = "Vent" .. i
		vent.Size = Vector3.new(0.1, 0.3, 0.15)
		vent.Color = CONFIG.CannonAccentColor
		vent.Material = Enum.Material.Metal
		vent.CanCollide = false
		vent.Anchored = true
		vent.Parent = cannonModel
		table.insert(parts, vent)
	end
	
	cannonModel.Parent = parent
	return cannonModel, parts
end

function ArmCannonController:CreateArmCannon(character)
	self._character = character
	self._hrp = character:FindFirstChild("HumanoidRootPart")
	self._humanoid = character:FindFirstChildOfClass("Humanoid")
	
	-- Hide character arms
	local armParts = {
		"RightUpperArm", "RightLowerArm", "RightHand",
		"LeftUpperArm", "LeftLowerArm", "LeftHand"
	}
	for _, partName in ipairs(armParts) do
		local part = character:FindFirstChild(partName)
		if part then
			part.Transparency = 1
			for _, child in ipairs(part:GetChildren()) do
				if child:IsA("BasePart") then
					child.Transparency = 1
				end
			end
		end
	end
	
	-- Create viewport system
	self:CreateViewport()
	
	-- Create cannon model in viewport
	self._cannonModel, self._cannonParts = self:CreateCannonModel(self._viewportFrame)
	
	-- Create invisible world-space cannon for raycasting
	self._worldCannon, self._worldCannonParts = self:CreateCannonModel(Workspace)
	for _, part in ipairs(self._worldCannonParts) do
		part.Transparency = 1
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
	end
	
	-- Initialize motion state
	self._time = 0
	self._walkBobPhase = 0
	self._landingDip = 0
	self._wasGrounded = true
	
	-- Initialize recoil kick state
	self._recoilKickBack = 0
	self._recoilKickUp = 0
	self._recoilKickSide = 0
	self._recoilVelocityBack = 0
	self._recoilVelocityUp = 0
	self._recoilVelocitySide = 0
end

-- === MOTION CALCULATIONS ===

function ArmCannonController:CalculateMotionOffset(dt)
	self._time = self._time + dt
	
	local posOffset = Vector3.zero
	local rotOffset = Vector3.zero  -- pitch, yaw, roll in radians
	
	-- Get movement info
	local speed = 0
	local isGrounded = true
	local verticalVel = 0
	local isMoving = false
	local isSprinting = false
	
	if self._hrp and self._humanoid then
		local vel = self._hrp.AssemblyLinearVelocity
		local horizontalVel = Vector3.new(vel.X, 0, vel.Z)
		speed = horizontalVel.Magnitude
		verticalVel = vel.Y
		isMoving = speed > 1
		isSprinting = speed > CONFIG.WalkThreshold
		isGrounded = self._humanoid.FloorMaterial ~= Enum.Material.Air
	end
	
	-- === IDLE SWAY (always active, reduced when moving) ===
	local idleMultiplier = isMoving and 0.3 or 1
	local idleSwayX = math.sin(self._time * MOTION.IdleSwaySpeed) * MOTION.IdleSwayAmount * idleMultiplier
	local idleSwayY = math.sin(self._time * MOTION.IdleSwaySpeed * 0.7) * MOTION.IdleSwayAmount * 0.5 * idleMultiplier
	posOffset = posOffset + Vector3.new(idleSwayX, idleSwayY, 0)
	
	-- Idle rotation sway
	local idleRotX = math.sin(self._time * MOTION.IdleSwaySpeed * 0.8) * math.rad(MOTION.IdleRotationAmount) * idleMultiplier
	local idleRotZ = math.sin(self._time * MOTION.IdleSwaySpeed * 0.6) * math.rad(MOTION.IdleRotationAmount * 0.5) * idleMultiplier
	rotOffset = rotOffset + Vector3.new(idleRotX, 0, idleRotZ)
	
	-- === WALK/SPRINT BOB ===
	if isMoving and isGrounded then
		local bobSpeed = MOTION.WalkBobSpeed
		local bobAmount = MOTION.WalkBobAmount
		local sideAmount = MOTION.WalkSideAmount
		local rotAmount = MOTION.WalkRotationAmount
		
		if isSprinting then
			bobSpeed = bobSpeed * MOTION.SprintSpeedMultiplier
			bobAmount = bobAmount * MOTION.SprintBobMultiplier
			sideAmount = sideAmount * MOTION.SprintBobMultiplier
			rotAmount = rotAmount * MOTION.SprintBobMultiplier
		end
		
		-- Update bob phase
		self._walkBobPhase = self._walkBobPhase + dt * bobSpeed
		
		-- Vertical bob (figure-8 pattern)
		local bobY = math.abs(math.sin(self._walkBobPhase)) * bobAmount
		-- Side sway (slower, alternating)
		local bobX = math.sin(self._walkBobPhase * 0.5) * sideAmount
		
		posOffset = posOffset + Vector3.new(bobX, -bobY, 0)
		
		-- Walk rotation (tilt with steps)
		local walkRotZ = math.sin(self._walkBobPhase * 0.5) * math.rad(rotAmount)
		local walkRotX = math.sin(self._walkBobPhase) * math.rad(rotAmount * 0.3)
		rotOffset = rotOffset + Vector3.new(walkRotX, 0, walkRotZ)
	end
	
	-- === LANDING DIP ===
	-- Detect landing
	if not self._wasGrounded and isGrounded and self._lastVerticalVel < MOTION.LandingVelocityThreshold then
		-- Just landed with significant velocity
		local impactStrength = math.clamp(math.abs(self._lastVerticalVel) / 30, 0, 1)
		self._landingDip = MOTION.LandingDipAmount * impactStrength
	end
	self._wasGrounded = isGrounded
	self._lastVerticalVel = verticalVel
	
	-- Recover from landing dip
	if self._landingDip > 0 then
		self._landingDip = self._landingDip - dt * MOTION.LandingDipRecovery * self._landingDip
		if self._landingDip < 0.001 then
			self._landingDip = 0
		end
		posOffset = posOffset + Vector3.new(0, -self._landingDip, 0)
		-- Add slight forward tilt on landing
		rotOffset = rotOffset + Vector3.new(self._landingDip * 2, 0, 0)
	end
	
	-- === JUMP RISE ===
	if not isGrounded and verticalVel > 5 then
		local riseAmount = math.clamp(verticalVel / 30, 0, 1) * MOTION.JumpRiseAmount
		posOffset = posOffset + Vector3.new(0, riseAmount, 0)
		-- Tilt up slightly when rising
		rotOffset = rotOffset + Vector3.new(-riseAmount * 3, 0, 0)
	end
	
	-- === RECOIL KICK (spring physics) ===
	-- Update spring physics for kick-back
	local springForce = -self._recoilKickBack * MOTION.RecoilSpring
	local dampingForce = -self._recoilVelocityBack * MOTION.RecoilDamping
	self._recoilVelocityBack = self._recoilVelocityBack + (springForce + dampingForce) * dt
	self._recoilKickBack = self._recoilKickBack + self._recoilVelocityBack * dt
	
	-- Update spring physics for kick-up
	springForce = -self._recoilKickUp * MOTION.RecoilSpring
	dampingForce = -self._recoilVelocityUp * MOTION.RecoilDamping
	self._recoilVelocityUp = self._recoilVelocityUp + (springForce + dampingForce) * dt
	self._recoilKickUp = self._recoilKickUp + self._recoilVelocityUp * dt
	
	-- Update spring physics for kick-side
	springForce = -self._recoilKickSide * MOTION.RecoilSpring
	dampingForce = -self._recoilVelocitySide * MOTION.RecoilDamping
	self._recoilVelocitySide = self._recoilVelocitySide + (springForce + dampingForce) * dt
	self._recoilKickSide = self._recoilKickSide + self._recoilVelocitySide * dt
	
	-- Apply recoil kick to offsets
	posOffset = posOffset + Vector3.new(0, 0, self._recoilKickBack)  -- Push back (positive Z in local space)
	rotOffset = rotOffset + Vector3.new(
		-math.rad(self._recoilKickUp),   -- Pitch up (negative = up)
		math.rad(self._recoilKickSide),  -- Yaw side
		0
	)
	
	return posOffset, rotOffset
end

-- Trigger recoil kick (called when firing)
function ArmCannonController:TriggerRecoilKick()
	-- Add impulse velocity for spring
	self._recoilVelocityBack = self._recoilVelocityBack + MOTION.RecoilKickBack * 20
	self._recoilVelocityUp = self._recoilVelocityUp + MOTION.RecoilKickUp * 15
	-- Random side kick for variation
	self._recoilVelocitySide = self._recoilVelocitySide + (math.random() - 0.5) * 2 * MOTION.RecoilKickSide * 10
end

function ArmCannonController:CalculateCameraLag(cameraCF, dt)
	local currentLook = cameraCF.LookVector
	
	-- Initialize smoothed look
	if not self._smoothedLook then
		self._smoothedLook = currentLook
		self._lastCameraLook = currentLook
		return CFrame.identity
	end
	
	-- Smooth the look direction (creates lag)
	self._smoothedLook = self._smoothedLook:Lerp(currentLook, MOTION.CameraLagSmoothing)
	
	-- Calculate the difference between actual and smoothed
	local lagOffset = (currentLook - self._smoothedLook) * MOTION.CameraLagAmount * 10
	
	self._lastCameraLook = currentLook
	
	-- Convert lag to position offset (opposite direction for natural feel)
	return CFrame.new(-lagOffset.X, -lagOffset.Y * 0.5, 0)
end

-- === CANNON UPDATE ===

function ArmCannonController:UpdateCannonParts(parts, baseCFrame, aimDir, recoilVector)
	local cylinderRotation = CFrame.Angles(0, math.rad(90), 0)
	
	-- 1. Shoulder Mount (no recoil)
	if parts[1] then
		parts[1].CFrame = baseCFrame
	end
	
	-- 2. Upper Section (no recoil)
	if parts[2] then
		local pos = baseCFrame.Position + aimDir * 0.5
		parts[2].CFrame = CFrame.lookAt(pos, pos + aimDir) * cylinderRotation
	end
	
	-- 3. Elbow Ring (no recoil)
	if parts[3] then
		local pos = baseCFrame.Position + aimDir * 0.9
		parts[3].CFrame = CFrame.lookAt(pos, pos + aimDir) * cylinderRotation
	end
	
	-- 4. Main Body (no recoil)
	if parts[4] then
		local pos = baseCFrame.Position + aimDir * 1.5
		parts[4].CFrame = CFrame.lookAt(pos, pos + aimDir) * cylinderRotation
	end
	
	-- 5. Barrel (RECOIL)
	if parts[5] then
		local pos = baseCFrame.Position + aimDir * 2.2 + recoilVector
		parts[5].CFrame = CFrame.lookAt(pos, pos + aimDir) * cylinderRotation
	end
	
	-- 6. Barrel Tip (RECOIL)
	if parts[6] then
		local pos = baseCFrame.Position + aimDir * CONFIG.CannonLength + recoilVector
		parts[6].CFrame = CFrame.lookAt(pos, pos + aimDir) * cylinderRotation
	end
	
	-- 7. Energy Core (pulsing, no recoil)
	if parts[7] then
		local pulse = 0.3 + math.sin(tick() * 4) * 0.1
		parts[7].Size = Vector3.new(pulse, pulse, pulse)
		local pos = baseCFrame.Position + aimDir * 1.5
		parts[7].CFrame = CFrame.new(pos)
	end
	
	-- 8-9. Side Vents (no recoil)
	local ventCF = CFrame.lookAt(baseCFrame.Position + aimDir * 1.3, baseCFrame.Position + aimDir * 2)
	if parts[8] then
		local pos = baseCFrame.Position + aimDir * 1.3 + ventCF.RightVector * 0.4
		parts[8].CFrame = CFrame.lookAt(pos, pos + aimDir)
	end
	if parts[9] then
		local pos = baseCFrame.Position + aimDir * 1.3 + ventCF.RightVector * -0.4
		parts[9].CFrame = CFrame.lookAt(pos, pos + aimDir)
	end
end

function ArmCannonController:UpdateArmCannon(dt)
	dt = dt or 0.016  -- Default to ~60fps if not provided
	
	if not self._viewportCamera or not self._cannonModel then return end
	
	local camera = Workspace.CurrentCamera
	if not camera then return end
	
	-- OPTIMIZATION: Cache camera CFrame to avoid multiple property reads
	local cameraCF = camera.CFrame
	local aimDir = cameraCF.LookVector
	
	-- Match viewport camera to world camera (only if changed significantly)
	-- OPTIMIZATION: Skip if camera hasn't moved much
	local cameraChanged = not self._lastCameraCF or (cameraCF.Position - self._lastCameraCF.Position).Magnitude > 0.01
	if cameraChanged then
		self._viewportCamera.CFrame = cameraCF
		self._lastCameraCF = cameraCF
	end
	
	-- Calculate motion offsets
	local posOffset, rotOffset = self:CalculateMotionOffset(dt)
	local cameraLagOffset = self:CalculateCameraLag(cameraCF, dt)
	
	-- Build motion CFrame
	local motionCF = CFrame.new(posOffset) 
		* CFrame.Angles(rotOffset.X, rotOffset.Y, rotOffset.Z)
		* cameraLagOffset
	
	-- Cannon base position (offset from camera + motion)
	local cannonBaseCF = cameraCF * self._cannonOffset * motionCF
	
	-- Calculate recoil
	local recoilAmount = (self._recoilOffset or 0) * CONFIG.RecoilAmount
	local recoilVector = -aimDir * recoilAmount
	
	-- Update viewport cannon
	self:UpdateCannonParts(self._cannonParts, cannonBaseCF, aimDir, recoilVector)
	
	-- OPTIMIZATION: Update world-space cannon less frequently (only when needed for shooting)
	-- World cannon is only used for raycasting, so we can update it less often
	self._worldCannonUpdateCounter = (self._worldCannonUpdateCounter or 0) + 1
	if self._worldCannonParts and #self._worldCannonParts > 0 and self._hrp and (self._worldCannonUpdateCounter % 3 == 0) then
		local hrpCF = self._hrp.CFrame
		local worldShoulderPos = hrpCF.Position + hrpCF.RightVector * 0.8 + Vector3.new(0, 1.3, 0)
		local worldBaseCF = CFrame.new(worldShoulderPos)
		self:UpdateCannonParts(self._worldCannonParts, worldBaseCF, aimDir, recoilVector)
	end
end

function ArmCannonController:DestroyArmCannon()
	-- Destroy viewport
	if self._screenGui then
		self._screenGui:Destroy()
		self._screenGui = nil
	end
	self._viewportFrame = nil
	self._viewportCamera = nil
	self._cannonModel = nil
	self._cannonParts = {}
	
	-- Destroy world cannon
	if self._worldCannon then
		self._worldCannon:Destroy()
		self._worldCannon = nil
	end
	self._worldCannonParts = {}
	
	-- Show arms again
	if self._character then
		local armParts = {
			"RightUpperArm", "RightLowerArm", "RightHand",
			"LeftUpperArm", "LeftLowerArm", "LeftHand"
		}
		for _, partName in ipairs(armParts) do
			local part = self._character:FindFirstChild(partName)
			if part then
				part.Transparency = 0
			end
		end
	end
	
	-- Reset motion state
	self._time = 0
	self._lastCameraLook = nil
	self._smoothedLook = nil
	self._walkBobPhase = 0
	self._landingDip = 0
	
	-- Reset recoil kick state
	self._recoilKickBack = 0
	self._recoilKickUp = 0
	self._recoilKickSide = 0
	self._recoilVelocityBack = 0
	self._recoilVelocityUp = 0
	self._recoilVelocitySide = 0
end

-- === PUBLIC API ===

function ArmCannonController:SetRecoilOffset(offset)
	-- Trigger kick when recoil starts (offset jumps to 1)
	if offset >= 0.9 and self._recoilOffset < 0.5 then
		self:TriggerRecoilKick()
	end
	self._recoilOffset = offset
end

function ArmCannonController:GetCannonTipPosition()
	-- Use world-space cannon for accurate raycasting
	local barrelTip = self._worldCannonParts and self._worldCannonParts[6]
	if not barrelTip then return nil, nil end
	
	local camera = Workspace.CurrentCamera
	local aimDir = camera and camera.CFrame.LookVector or Vector3.new(0, 0, -1)
	
	local tipPos = barrelTip.Position + aimDir * 0.2
	
	return tipPos, aimDir
end

function ArmCannonController:GetCannonParts()
	return self._cannonParts
end

function ArmCannonController:SetCannonOffset(offset)
	self._cannonOffset = offset
end

function ArmCannonController:SetCannonFOV(fov)
	self._cannonFOV = fov
	if self._viewportCamera then
		self._viewportCamera.FieldOfView = fov
	end
end

function ArmCannonController:SetCannonColors(main, accent, glow)
	CONFIG.CannonColor = main or CONFIG.CannonColor
	CONFIG.CannonAccentColor = accent or CONFIG.CannonAccentColor
	CONFIG.CannonGlowColor = glow or CONFIG.CannonGlowColor
	
	-- Update both viewport and world cannon colors
	local allParts = {self._cannonParts, self._worldCannonParts}
	for _, parts in ipairs(allParts) do
		for _, part in ipairs(parts) do
			if part.Name == "ShoulderMount" or part.Name == "ElbowRing" or part.Name == "Barrel" then
				part.Color = CONFIG.CannonAccentColor
			elseif part.Name == "BarrelTip" or part.Name == "EnergyCore" then
				part.Color = CONFIG.CannonGlowColor
			elseif part.Name:find("Vent") then
				part.Color = CONFIG.CannonAccentColor
			else
				part.Color = CONFIG.CannonColor
			end
		end
	end
end

function ArmCannonController:Cleanup()
	self:DestroyArmCannon()
	self._character = nil
	self._hrp = nil
	self._humanoid = nil
end

-- === KNIT LIFECYCLE ===

function ArmCannonController:KnitInit()
end

function ArmCannonController:KnitStart()
	-- This controller is managed by ProceduralLocomotionController
end

return ArmCannonController
