--[[
	LocomotionController
	Handles IK-driven procedural locomotion (walk cycle, foot placement, arm swing, body motion)
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Packages = game:GetService("ReplicatedStorage"):WaitForChild("Packages")
local Knit = require(Packages.Knit)

local CONFIG = require(script.Parent.LocomotionConfig)

local LocomotionController = Knit.CreateController {
	Name = "LocomotionController",
	
	-- State
	_character = nil,
	_humanoid = nil,
	_hrp = nil,
	
	-- IK Controls
	_ikControls = {},
	_ikTargets = {},
	
	-- Motor6D references
	_motors = {},
	
	-- Locomotion state
	_walkPhase = 0,
	_lastGroundedFoot = "Left",
	_leftFootPlanted = true,
	_rightFootPlanted = false,
	_leftFootTarget = CFrame.new(),
	_rightFootTarget = CFrame.new(),
	_lastLeftFootPos = Vector3.zero,
	_lastRightFootPos = Vector3.zero,
	_lastRightHandPos = nil,
	
	-- Movement state (shared with MovementController)
	_smoothedSpeed = 0,
	_smoothedDirection = Vector3.zero,
	
	-- Connections
	_connections = {},
}

-- === HELPER FUNCTIONS ===

local function lerp(a, b, t)
	return a + (b - a) * t
end

local function smoothstep(t)
	return t * t * (3 - 2 * t)
end

local function getMovementInfo(hrp)
	local velocity = hrp.AssemblyLinearVelocity
	local horizontalVel = Vector3.new(velocity.X, 0, velocity.Z)
	local speed = horizontalVel.Magnitude
	local direction = speed > 0.1 and horizontalVel.Unit or hrp.CFrame.LookVector
	return speed, direction, velocity.Y
end

local function raycastGround(origin, character)
	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.FilterDescendantsInstances = {character}
	
	local result = Workspace:Raycast(origin, Vector3.new(0, -CONFIG.FootRaycastDistance, 0), rayParams)
	
	if result then
		return result.Position, result.Normal, true
	else
		return origin + Vector3.new(0, -CONFIG.FootRaycastDistance, 0), Vector3.yAxis, false
	end
end

local function calculateFootArc(startPos, endPos, progress, stepHeight)
	local arcHeight = math.sin(progress * math.pi) * stepHeight
	local pos = startPos:Lerp(endPos, smoothstep(progress))
	return pos + Vector3.new(0, arcHeight, 0)
end

-- === IK SETUP ===

function LocomotionController:CreateIKTarget(name, parent)
	local target = Instance.new("Part")
	target.Name = name .. "Target"
	target.Size = Vector3.new(0.3, 0.3, 0.3)
	target.Anchored = true
	target.CanCollide = false
	target.CanQuery = false
	target.CanTouch = false
	target.Transparency = CONFIG.ShowTargets and 0 or 1
	target.Color = Color3.fromRGB(0, 255, 100)
	target.Material = Enum.Material.Neon
	target.Parent = parent
	return target
end

function LocomotionController:CreateIKControl(name, humanoid, endEffector, chainRoot, target)
	local ikControl = Instance.new("IKControl")
	ikControl.Name = name
	ikControl.Type = Enum.IKControlType.Transform
	ikControl.EndEffector = endEffector
	ikControl.ChainRoot = chainRoot
	ikControl.Target = target
	ikControl.Weight = 1
	ikControl.SmoothTime = CONFIG.IKSmoothTime
	ikControl.Parent = humanoid
	return ikControl
end

function LocomotionController:SetupAllIK(character)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then return false end
	
	local parts = {
		LeftFoot = character:FindFirstChild("LeftFoot"),
		RightFoot = character:FindFirstChild("RightFoot"),
		LeftHand = character:FindFirstChild("LeftHand"),
		RightHand = character:FindFirstChild("RightHand"),
		LeftUpperLeg = character:FindFirstChild("LeftUpperLeg"),
		RightUpperLeg = character:FindFirstChild("RightUpperLeg"),
		LeftUpperArm = character:FindFirstChild("LeftUpperArm"),
		RightUpperArm = character:FindFirstChild("RightUpperArm"),
		Head = character:FindFirstChild("Head"),
		UpperTorso = character:FindFirstChild("UpperTorso"),
	}
	
	for name, part in pairs(parts) do
		if not part then
			warn("[Locomotion] Missing body part:", name)
			return false
		end
	end
	
	local ikFolder = Instance.new("Folder")
	ikFolder.Name = "ProceduralIK"
	ikFolder.Parent = character
	
	-- Left Leg IK
	self._ikTargets.LeftFoot = self:CreateIKTarget("LeftFoot", ikFolder)
	self._ikControls.LeftLeg = self:CreateIKControl(
		"LeftLegIK", humanoid, parts.LeftFoot, parts.LeftUpperLeg, self._ikTargets.LeftFoot
	)
	
	-- Right Leg IK
	self._ikTargets.RightFoot = self:CreateIKTarget("RightFoot", ikFolder)
	self._ikControls.RightLeg = self:CreateIKControl(
		"RightLegIK", humanoid, parts.RightFoot, parts.RightUpperLeg, self._ikTargets.RightFoot
	)
	
	-- Left Arm IK
	self._ikTargets.LeftHand = self:CreateIKTarget("LeftHand", ikFolder)
	self._ikControls.LeftArm = self:CreateIKControl(
		"LeftArmIK", humanoid, parts.LeftHand, parts.LeftUpperArm, self._ikTargets.LeftHand
	)
	
	-- Right Arm IK
	self._ikTargets.RightHand = self:CreateIKTarget("RightHand", ikFolder)
	self._ikControls.RightArm = self:CreateIKControl(
		"RightArmIK", humanoid, parts.RightHand, parts.RightUpperArm, self._ikTargets.RightHand
	)
	
	return true
end

-- === ANIMATION DISABLING ===

function LocomotionController:DisableDefaultAnimations(character)
	local scriptsToRemove = {"Animate", "Health", "Sound"}
	
	for _, scriptName in ipairs(scriptsToRemove) do
		local script = character:FindFirstChild(scriptName)
		if script then
			script:Destroy()
		end
	end
	
	-- Disable RbxCharacterSounds
	local player = Players.LocalPlayer
	local playerScripts = player:FindFirstChild("PlayerScripts")
	if playerScripts then
		local rbxCharSounds = playerScripts:FindFirstChild("RbxCharacterSounds")
		if rbxCharSounds then
			rbxCharSounds.Disabled = true
			rbxCharSounds:Destroy()
		end
	end
	
	-- Remove all sounds in character
	for _, descendant in ipairs(character:GetDescendants()) do
		if descendant:IsA("Sound") then
			descendant.Volume = 0
			descendant:Stop()
			descendant:Destroy()
		end
	end
	
	-- Destroy HRP sounds
	local hrp = character:FindFirstChild("HumanoidRootPart")
	if hrp then
		for _, child in ipairs(hrp:GetChildren()) do
			if child:IsA("Sound") or child.Name == "Running" or child.Name == "Climbing" or 
			   child.Name == "Jumping" or child.Name == "GettingUp" or child.Name == "FreeFalling" or 
			   child.Name == "Landing" or child.Name == "Splash" or child.Name == "Swimming" then
				child:Destroy()
			end
		end
	end
	
	-- Destroy Head sounds
	local head = character:FindFirstChild("Head")
	if head then
		for _, child in ipairs(head:GetChildren()) do
			if child:IsA("Sound") then
				child:Destroy()
			end
		end
	end
	
	-- Watch for sounds added later
	local soundWatcher = character.DescendantAdded:Connect(function(descendant)
		if descendant:IsA("Sound") then
			task.defer(function()
				if descendant and descendant.Parent then
					descendant.Volume = 0
					descendant:Stop()
					descendant:Destroy()
				end
			end)
		end
	end)
	table.insert(self._connections, soundWatcher)
	
	-- Stop playing animation tracks
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		local animator = humanoid:FindFirstChildOfClass("Animator")
		if animator then
			for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
				track:Stop(0)
			end
		end
	end
	
	-- Get motor references
	self._motors = {}
	local motorNames = {
		"LeftHip", "LeftKnee", "LeftAnkle",
		"RightHip", "RightKnee", "RightAnkle",
		"LeftShoulder", "LeftElbow", "LeftWrist",
		"RightShoulder", "RightElbow", "RightWrist",
		"Waist", "Neck", "Root"
	}
	
	for _, descendant in ipairs(character:GetDescendants()) do
		if descendant:IsA("Motor6D") then
			for _, motorName in ipairs(motorNames) do
				if descendant.Name == motorName then
					self._motors[motorName] = descendant
				end
			end
		end
	end
end

-- === LOCOMOTION UPDATE ===

function LocomotionController:UpdateLocomotion(dt)
	if not self._hrp or not self._hrp.Parent then return end
	
	local speed, moveDir, verticalVel = getMovementInfo(self._hrp)
	local hrpCF = self._hrp.CFrame
	local hrpPos = hrpCF.Position
	
	-- Use smoothed values if available
	if CONFIG.MovementSmoothing and self._smoothedSpeed then
		speed = self._smoothedSpeed
		if self._smoothedDirection and self._smoothedDirection.Magnitude > 0.1 then
			moveDir = self._smoothedDirection.Unit
		end
	end
	
	-- Determine locomotion state
	local isIdle = speed < CONFIG.IdleThreshold
	local isRunning = speed > CONFIG.WalkThreshold
	
	-- Get speed-dependent values
	local strideLength = isRunning and CONFIG.StrideLengthRun or CONFIG.StrideLength
	local stepHeight = isRunning and CONFIG.StepHeightRun or CONFIG.StepHeight
	local bodyBob = isRunning and CONFIG.BodyBobAmountRun or CONFIG.BodyBobAmount
	local armSwing = isRunning and CONFIG.ArmSwingAmountRun or CONFIG.ArmSwingAmount
	
	-- Update walk phase
	if not isIdle then
		local cycleSpeed = speed / strideLength
		self._walkPhase = (self._walkPhase + cycleSpeed * dt) % 1
	end
	
	local leftPhase = self._walkPhase
	local rightPhase = (self._walkPhase + 0.5) % 1
	
	-- === FOOT PLACEMENT ===
	local hipOffset = 0.5
	local leftHipPos = hrpPos + hrpCF.RightVector * -hipOffset
	local rightHipPos = hrpPos + hrpCF.RightVector * hipOffset
	local strideOffset = strideLength / 2
	
	-- Left foot
	local leftFootProgress = leftPhase
	local leftGrounded = leftFootProgress < CONFIG.FootPlantDuration or leftFootProgress > (1 - CONFIG.FootPlantDuration)
	
	if isIdle then
		local leftRestPos = leftHipPos + Vector3.new(0, -2.5, 0) + hrpCF.RightVector * -0.2
		local groundPos, _, _ = raycastGround(leftRestPos + Vector3.new(0, 2, 0), self._character)
		self._leftFootTarget = CFrame.new(groundPos + Vector3.new(0, CONFIG.FootGroundOffset, 0))
	else
		if leftGrounded then
			if self._leftFootPlanted == false then
				local plantPos = leftHipPos + moveDir * -strideOffset + Vector3.new(0, -2, 0)
				local groundPos, _, _ = raycastGround(plantPos + Vector3.new(0, 2, 0), self._character)
				self._lastLeftFootPos = groundPos + Vector3.new(0, CONFIG.FootGroundOffset, 0)
				self._leftFootPlanted = true
			end
			self._leftFootTarget = CFrame.new(self._lastLeftFootPos) * CFrame.Angles(0, math.atan2(moveDir.X, moveDir.Z), 0)
		else
			self._leftFootPlanted = false
			local swingProgress = (leftFootProgress - CONFIG.FootPlantDuration) / (1 - 2 * CONFIG.FootPlantDuration)
			swingProgress = math.clamp(swingProgress, 0, 1)
			
			local targetPos = leftHipPos + moveDir * strideOffset + Vector3.new(0, -2, 0)
			local groundPos, _, _ = raycastGround(targetPos + Vector3.new(0, 2, 0), self._character)
			targetPos = groundPos + Vector3.new(0, CONFIG.FootGroundOffset, 0)
			
			local arcPos = calculateFootArc(self._lastLeftFootPos, targetPos, swingProgress, stepHeight)
			self._leftFootTarget = CFrame.new(arcPos) * CFrame.Angles(
				math.sin(swingProgress * math.pi) * 0.3,
				math.atan2(moveDir.X, moveDir.Z),
				0
			)
		end
	end
	
	-- Right foot
	local rightFootProgress = rightPhase
	local rightGrounded = rightFootProgress < CONFIG.FootPlantDuration or rightFootProgress > (1 - CONFIG.FootPlantDuration)
	
	if isIdle then
		local rightRestPos = rightHipPos + Vector3.new(0, -2.5, 0) + hrpCF.RightVector * 0.2
		local groundPos, _, _ = raycastGround(rightRestPos + Vector3.new(0, 2, 0), self._character)
		self._rightFootTarget = CFrame.new(groundPos + Vector3.new(0, CONFIG.FootGroundOffset, 0))
	else
		if rightGrounded then
			if self._rightFootPlanted == false then
				local plantPos = rightHipPos + moveDir * -strideOffset + Vector3.new(0, -2, 0)
				local groundPos, _, _ = raycastGround(plantPos + Vector3.new(0, 2, 0), self._character)
				self._lastRightFootPos = groundPos + Vector3.new(0, CONFIG.FootGroundOffset, 0)
				self._rightFootPlanted = true
			end
			self._rightFootTarget = CFrame.new(self._lastRightFootPos) * CFrame.Angles(0, math.atan2(moveDir.X, moveDir.Z), 0)
		else
			self._rightFootPlanted = false
			local swingProgress = (rightFootProgress - CONFIG.FootPlantDuration) / (1 - 2 * CONFIG.FootPlantDuration)
			swingProgress = math.clamp(swingProgress, 0, 1)
			
			local targetPos = rightHipPos + moveDir * strideOffset + Vector3.new(0, -2, 0)
			local groundPos, _, _ = raycastGround(targetPos + Vector3.new(0, 2, 0), self._character)
			targetPos = groundPos + Vector3.new(0, CONFIG.FootGroundOffset, 0)
			
			local arcPos = calculateFootArc(self._lastRightFootPos, targetPos, swingProgress, stepHeight)
			self._rightFootTarget = CFrame.new(arcPos) * CFrame.Angles(
				math.sin(swingProgress * math.pi) * 0.3,
				math.atan2(moveDir.X, moveDir.Z),
				0
			)
		end
	end
	
	-- Apply foot targets
	if self._ikTargets.LeftFoot then
		self._ikTargets.LeftFoot.CFrame = self._leftFootTarget
	end
	if self._ikTargets.RightFoot then
		self._ikTargets.RightFoot.CFrame = self._rightFootTarget
	end
	
	-- === ARM SWING ===
	local shoulderHeight = 1.3
	local shoulderWidth = 0.8
	local armLength = 1.8
	
	-- Left arm
	local leftArmSwing = isIdle and 0 or math.sin(rightPhase * math.pi * 2) * armSwing
	local leftShoulderPos = hrpPos + hrpCF.RightVector * -shoulderWidth + Vector3.new(0, shoulderHeight, 0)
	local leftArmDir = hrpCF.LookVector * (CONFIG.ArmForwardOffset + math.sin(leftArmSwing)) + Vector3.new(0, -1, 0)
	local leftHandPos = leftShoulderPos + leftArmDir.Unit * armLength
	
	if self._ikTargets.LeftHand then
		self._ikTargets.LeftHand.CFrame = CFrame.new(leftHandPos) * CFrame.Angles(leftArmSwing, 0, 0)
	end
	
	-- Right arm - handled by ArmCannonController if enabled, otherwise swing
	if not CONFIG.RightArmExtended then
		local rightArmSwing = isIdle and 0 or math.sin(leftPhase * math.pi * 2) * armSwing
		local rightShoulderPos = hrpPos + hrpCF.RightVector * shoulderWidth + Vector3.new(0, shoulderHeight, 0)
		local rightArmDir = hrpCF.LookVector * (CONFIG.ArmForwardOffset + math.sin(rightArmSwing)) + Vector3.new(0, -1, 0)
		local rightHandPos = rightShoulderPos + rightArmDir.Unit * armLength
		
		if self._ikTargets.RightHand then
			self._ikTargets.RightHand.CFrame = CFrame.new(rightHandPos) * CFrame.Angles(rightArmSwing, 0, 0)
		end
	end
	
	-- === BODY MOTION ===
	local bobPhase = self._walkPhase * 2
	local currentBob = isIdle and 0 or math.abs(math.sin(bobPhase * math.pi)) * bodyBob
	
	if self._motors.Waist then
		local tiltForward = isIdle and 0 or CONFIG.BodyTiltForward * (speed / CONFIG.WalkThreshold)
		local sway = isIdle and 0 or math.sin(self._walkPhase * math.pi * 2) * CONFIG.BodySwayAmount
		
		self._motors.Waist.Transform = CFrame.new(0, currentBob, 0) 
			* CFrame.Angles(tiltForward, 0, sway)
	end
	
	if self._motors.Root then
		self._motors.Root.Transform = CFrame.new(0, currentBob * 0.5, 0)
	end
end

function LocomotionController:ResetMotorTransforms()
	local overrideMotors = {
		"LeftHip", "LeftKnee", "LeftAnkle",
		"RightHip", "RightKnee", "RightAnkle",
		"LeftShoulder", "LeftElbow", "LeftWrist",
		"RightShoulder", "RightElbow", "RightWrist",
	}
	
	for _, motorName in ipairs(overrideMotors) do
		local motor = self._motors[motorName]
		if motor and motor.Parent then
			motor.Transform = CFrame.identity
		end
	end
end

function LocomotionController:UpdateRightArmToCamera()
	if not self._hrp or not self._hrp.Parent then return end
	if not CONFIG.RightArmExtended then return end
	if not self._ikTargets.RightHand then return end
	
	local hrpCF = self._hrp.CFrame
	local hrpPos = hrpCF.Position
	
	local shoulderHeight = 1.3
	local shoulderWidth = 0.8
	
	local camera = Workspace.CurrentCamera
	local cameraLook = camera and camera.CFrame.LookVector or hrpCF.LookVector
	
	local rightShoulderPos = hrpPos + hrpCF.RightVector * shoulderWidth + Vector3.new(0, shoulderHeight, 0)
	local targetHandPos = rightShoulderPos + cameraLook * CONFIG.RightArmForwardDistance
	
	if not self._lastRightHandPos then
		self._lastRightHandPos = targetHandPos
	end
	
	local smoothFactor = 0.5
	local smoothedHandPos = self._lastRightHandPos:Lerp(targetHandPos, smoothFactor)
	self._lastRightHandPos = smoothedHandPos
	
	local lookDir = (targetHandPos - rightShoulderPos).Unit
	
	self._ikTargets.RightHand.CFrame = CFrame.lookAt(smoothedHandPos, smoothedHandPos + lookDir)
		* CFrame.Angles(0, math.rad(-90), 0)
end

-- === SETUP & CLEANUP ===

function LocomotionController:EnsureCharacterVisible(character)
	local bodyParts = {
		"Head", "UpperTorso", "LowerTorso", "HumanoidRootPart",
		"LeftUpperArm", "LeftLowerArm", "LeftHand",
		"RightUpperArm", "RightLowerArm", "RightHand",
		"LeftUpperLeg", "LeftLowerLeg", "LeftFoot",
		"RightUpperLeg", "RightLowerLeg", "RightFoot",
	}
	
	for _, partName in ipairs(bodyParts) do
		local part = character:FindFirstChild(partName)
		if part and part:IsA("BasePart") then
			part.Transparency = 0
		end
	end
	
	for _, descendant in ipairs(character:GetDescendants()) do
		if descendant:IsA("BasePart") and descendant.Name ~= "HumanoidRootPart" then
			if descendant.Parent == character or 
			   (descendant.Parent and descendant.Parent.Parent == character) then
				if descendant.Transparency > 0 then
					descendant.Transparency = 0
				end
			end
		end
	end
end

function LocomotionController:SetupCharacter(character)
	self._character = character
	self._humanoid = character:WaitForChild("Humanoid", 10)
	self._hrp = character:WaitForChild("HumanoidRootPart", 10)
	
	if not self._humanoid or not self._hrp then
		warn("[Locomotion] Failed to find Humanoid or HRP")
		return false
	end
	
	self:EnsureCharacterVisible(character)
	
	local hrpPos = self._hrp.Position
	self._lastLeftFootPos = hrpPos + Vector3.new(-0.5, -2.5, 0)
	self._lastRightFootPos = hrpPos + Vector3.new(0.5, -2.5, 0)
	
	self:DisableDefaultAnimations(character)
	
	if not self:SetupAllIK(character) then
		warn("[Locomotion] Failed to setup IK")
		return false
	end
	
	return true
end

function LocomotionController:Cleanup()
	for _, conn in ipairs(self._connections) do
		if conn and conn.Connected then
			conn:Disconnect()
		end
	end
	self._connections = {}
	
	for _, ik in pairs(self._ikControls) do
		if ik and ik.Parent then
			ik:Destroy()
		end
	end
	self._ikControls = {}
	
	for _, target in pairs(self._ikTargets) do
		if target and target.Parent then
			target:Destroy()
		end
	end
	self._ikTargets = {}
	
	self._motors = {}
	self._character = nil
	self._humanoid = nil
	self._hrp = nil
end

-- === PUBLIC API ===

function LocomotionController:SetSmoothedValues(speed, direction)
	self._smoothedSpeed = speed
	self._smoothedDirection = direction
end

function LocomotionController:GetIKTargets()
	return self._ikTargets
end

function LocomotionController:GetMotors()
	return self._motors
end

function LocomotionController:GetCharacter()
	return self._character
end

function LocomotionController:GetHRP()
	return self._hrp
end

function LocomotionController:GetHumanoid()
	return self._humanoid
end

-- === KNIT LIFECYCLE ===

function LocomotionController:KnitInit()
end

function LocomotionController:KnitStart()
	-- This controller is managed by ProceduralLocomotionController
end

return LocomotionController

