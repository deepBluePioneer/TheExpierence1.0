--[[
	IKController (CLIENT-SIDE)
	Manages Inverse Kinematics for the local player's avatar
	Currently configured to extend the right arm forward
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Packages = game:GetService("ReplicatedStorage"):WaitForChild("Packages")
local Knit = require(Packages.Knit)

local IKController = Knit.CreateController {
	Name = "IKController",
	_ikControls = {},      -- Store active IK controls
	_targets = {},         -- Store target parts
	_connections = {},     -- Store RBXScriptConnections
	_disabledMotors = {},  -- Store disabled Motor6Ds to re-enable later
	_armMotors = {},       -- Store arm Motor6D references for manual override
}

-- === CONFIG ===
local IK_CONFIG = {
	Enabled = false,                 -- Disabled: Using ProceduralLocomotionController instead
	
	-- Right Arm IK Settings
	RightArmEnabled = true,
	RightArmForwardDistance = 3,     -- How far forward the arm extends (studs)
	RightArmHeightOffset = 0.5,      -- Vertical offset from HRP (positive = up)
	RightArmSideOffset = 0.3,        -- Horizontal offset (positive = right)
	
	-- Left Arm IK Settings (disabled by default)
	LeftArmEnabled = false,
	LeftArmForwardDistance = 3,
	LeftArmHeightOffset = 0.5,
	LeftArmSideOffset = -0.3,
	
	-- Animation Override Settings
	DisableArmMotors = false,        -- Keep false! Motors must stay enabled for IK to work
	SmoothTime = 0,                  -- 0 = instant IK, higher = smoother but slower
	OverrideAnimationManually = true, -- Manually override Motor6D transforms each frame
	
	-- Debug
	ShowTargets = false,             -- Make target parts visible for debugging
	TargetColor = Color3.fromRGB(0, 255, 100),
}

-- === HELPER FUNCTIONS ===

local function createTargetPart(name, parent)
	local target = Instance.new("Part")
	target.Name = name
	target.Size = Vector3.new(0.5, 0.5, 0.5)
	target.Anchored = true
	target.CanCollide = false
	target.CanQuery = false
	target.CanTouch = false
	target.Transparency = IK_CONFIG.ShowTargets and 0 or 1
	target.Color = IK_CONFIG.TargetColor
	target.Material = Enum.Material.Neon
	target.Parent = parent
	return target
end

local function createIKControl(name, humanoid, endEffector, chainRoot, target)
	local ikControl = Instance.new("IKControl")
	ikControl.Name = name
	ikControl.Type = Enum.IKControlType.Transform
	ikControl.EndEffector = endEffector
	ikControl.ChainRoot = chainRoot
	ikControl.Target = target
	ikControl.Weight = 1
	ikControl.SmoothTime = IK_CONFIG.SmoothTime  -- 0 = instant, no animation blending delay
	ikControl.Parent = humanoid
	return ikControl
end

-- Disable Motor6D joints for an arm to prevent animation influence
-- Returns a table of the disabled motors so we can re-enable them later
local function disableArmMotors(character, side)
	local disabledMotors = {}
	
	-- R15 arm joint names
	local jointNames = {
		side .. "Shoulder",     -- UpperTorso -> UpperArm
		side .. "Elbow",        -- UpperArm -> LowerArm
		side .. "Wrist",        -- LowerArm -> Hand
	}
	
	-- Search for motors in the character
	for _, descendant in ipairs(character:GetDescendants()) do
		if descendant:IsA("Motor6D") then
			for _, jointName in ipairs(jointNames) do
				if descendant.Name == jointName then
					-- Store original enabled state and disable
					disabledMotors[descendant] = descendant.Enabled
					descendant.Enabled = false
					print("[IKController] Disabled motor:", descendant.Name)
				end
			end
		end
	end
	
	return disabledMotors
end

-- Re-enable previously disabled motors
local function enableArmMotors(disabledMotors)
	for motor, wasEnabled in pairs(disabledMotors) do
		if motor and motor.Parent then
			motor.Enabled = wasEnabled
		end
	end
end

-- Get references to arm Motor6Ds (without disabling them)
local function getArmMotors(character, side)
	local motors = {}
	
	-- R15 arm joint names
	local jointNames = {
		side .. "Shoulder",
		side .. "Elbow", 
		side .. "Wrist",
	}
	
	for _, descendant in ipairs(character:GetDescendants()) do
		if descendant:IsA("Motor6D") then
			for _, jointName in ipairs(jointNames) do
				if descendant.Name == jointName then
					motors[descendant.Name] = descendant
				end
			end
		end
	end
	
	return motors
end

-- === SETUP FUNCTIONS ===

function IKController:SetupRightArmIK(character)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local hrp = character:FindFirstChild("HumanoidRootPart")
	local rightHand = character:FindFirstChild("RightHand")
	local rightUpperArm = character:FindFirstChild("RightUpperArm")
	
	if not (humanoid and hrp and rightHand and rightUpperArm) then
		warn("[IKController] Missing required parts for Right Arm IK")
		return
	end
	
	-- Get motor references for manual override (don't disable them!)
	if IK_CONFIG.OverrideAnimationManually then
		self._armMotors["RightArm"] = getArmMotors(character, "Right")
	end
	
	-- Legacy: disable motors if configured (not recommended)
	if IK_CONFIG.DisableArmMotors then
		self._disabledMotors["RightArm"] = disableArmMotors(character, "Right")
	end
	
	-- Create target part
	local target = createTargetPart("RightArmTarget", character)
	self._targets["RightArm"] = target
	
	-- Create IK control
	local ikControl = createIKControl("RightArmIK", humanoid, rightHand, rightUpperArm, target)
	self._ikControls["RightArm"] = ikControl
	
	print("[IKController] Right Arm IK setup complete")
end

function IKController:SetupLeftArmIK(character)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local hrp = character:FindFirstChild("HumanoidRootPart")
	local leftHand = character:FindFirstChild("LeftHand")
	local leftUpperArm = character:FindFirstChild("LeftUpperArm")
	
	if not (humanoid and hrp and leftHand and leftUpperArm) then
		warn("[IKController] Missing required parts for Left Arm IK")
		return
	end
	
	-- Get motor references for manual override (don't disable them!)
	if IK_CONFIG.OverrideAnimationManually then
		self._armMotors["LeftArm"] = getArmMotors(character, "Left")
	end
	
	-- Legacy: disable motors if configured (not recommended)
	if IK_CONFIG.DisableArmMotors then
		self._disabledMotors["LeftArm"] = disableArmMotors(character, "Left")
	end
	
	-- Create target part
	local target = createTargetPart("LeftArmTarget", character)
	self._targets["LeftArm"] = target
	
	-- Create IK control
	local ikControl = createIKControl("LeftArmIK", humanoid, leftHand, leftUpperArm, target)
	self._ikControls["LeftArm"] = ikControl
	
	print("[IKController] Left Arm IK setup complete")
end

function IKController:UpdateTargets(character)
	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not hrp then return end
	
	-- Update Right Arm target
	if self._targets["RightArm"] and IK_CONFIG.RightArmEnabled then
		local forward = hrp.CFrame.LookVector * IK_CONFIG.RightArmForwardDistance
		local up = Vector3.new(0, IK_CONFIG.RightArmHeightOffset, 0)
		local right = hrp.CFrame.RightVector * IK_CONFIG.RightArmSideOffset
		
		local targetPos = hrp.Position + forward + up + right
		
		-- Orient hand palm-down, facing forward
		self._targets["RightArm"].CFrame = CFrame.lookAt(targetPos, targetPos + hrp.CFrame.LookVector) 
			* CFrame.Angles(0, math.rad(-90), 0)
	end
	
	-- Update Left Arm target
	if self._targets["LeftArm"] and IK_CONFIG.LeftArmEnabled then
		local forward = hrp.CFrame.LookVector * IK_CONFIG.LeftArmForwardDistance
		local up = Vector3.new(0, IK_CONFIG.LeftArmHeightOffset, 0)
		local left = hrp.CFrame.RightVector * IK_CONFIG.LeftArmSideOffset
		
		local targetPos = hrp.Position + forward + up + left
		
		-- Orient hand palm-down, facing forward
		self._targets["LeftArm"].CFrame = CFrame.lookAt(targetPos, targetPos + hrp.CFrame.LookVector) 
			* CFrame.Angles(0, math.rad(90), 0)
	end
end

function IKController:SetupCharacterIK(character)
	-- Wait for character to be fully loaded
	if not character:IsDescendantOf(workspace) then
		character.AncestryChanged:Wait()
	end
	
	local humanoid = character:WaitForChild("Humanoid", 10)
	if not humanoid then
		warn("[IKController] No Humanoid found in character")
		return
	end
	
	-- Setup individual IK chains based on config
	if IK_CONFIG.RightArmEnabled then
		self:SetupRightArmIK(character)
	end
	
	if IK_CONFIG.LeftArmEnabled then
		self:SetupLeftArmIK(character)
	end
	
	-- Create update loop for target positions
	local heartbeatConnection = RunService.Heartbeat:Connect(function()
		if character and character.Parent then
			self:UpdateTargets(character)
		end
	end)
	table.insert(self._connections, heartbeatConnection)
	
	-- Manual animation override: Reset motor transforms AFTER animator runs
	-- This runs at RenderStepped (after animations) to override animation transforms
	if IK_CONFIG.OverrideAnimationManually then
		local renderConnection = RunService.RenderStepped:Connect(function()
			if not character or not character.Parent then return end
			
			-- Reset arm motor transforms to identity (removes animation influence)
			-- IKControl will then apply its own transforms on top
			for armName, motors in pairs(self._armMotors) do
				for motorName, motor in pairs(motors) do
					if motor and motor.Parent then
						-- Reset to identity - IK will override this
						motor.Transform = CFrame.identity
					end
				end
			end
		end)
		table.insert(self._connections, renderConnection)
	end
	
	-- Cleanup on death/respawn
	humanoid.Died:Connect(function()
		self:CleanupIK()
	end)
	
	print("[IKController] Character IK setup complete")
end

function IKController:CleanupIK()
	-- Disconnect all connections
	for _, connection in ipairs(self._connections) do
		if connection and connection.Connected then
			connection:Disconnect()
		end
	end
	self._connections = {}
	
	-- Re-enable disabled motors
	for _, motors in pairs(self._disabledMotors) do
		enableArmMotors(motors)
	end
	self._disabledMotors = {}
	
	-- Clear arm motor references
	self._armMotors = {}
	
	-- Destroy IK controls
	for _, ikControl in pairs(self._ikControls) do
		if ikControl and ikControl.Parent then
			ikControl:Destroy()
		end
	end
	self._ikControls = {}
	
	-- Destroy targets
	for _, target in pairs(self._targets) do
		if target and target.Parent then
			target:Destroy()
		end
	end
	self._targets = {}
	
	print("[IKController] IK cleaned up")
end

-- === PUBLIC API ===

-- Enable/disable right arm IK at runtime
function IKController:SetRightArmEnabled(enabled)
	IK_CONFIG.RightArmEnabled = enabled
	if self._ikControls["RightArm"] then
		self._ikControls["RightArm"].Weight = enabled and 1 or 0
	end
end

-- Enable/disable left arm IK at runtime
function IKController:SetLeftArmEnabled(enabled)
	IK_CONFIG.LeftArmEnabled = enabled
	if self._ikControls["LeftArm"] then
		self._ikControls["LeftArm"].Weight = enabled and 1 or 0
	end
end

-- Set the forward distance for right arm
function IKController:SetRightArmDistance(distance)
	IK_CONFIG.RightArmForwardDistance = distance
end

-- Set a custom target position for right arm (world space)
function IKController:SetRightArmTargetPosition(position)
	if self._targets["RightArm"] then
		self._targets["RightArm"].Position = position
	end
end

-- Set a custom target CFrame for right arm
function IKController:SetRightArmTargetCFrame(cframe)
	if self._targets["RightArm"] then
		self._targets["RightArm"].CFrame = cframe
	end
end

-- Get the IK weight for blending
function IKController:GetRightArmWeight()
	if self._ikControls["RightArm"] then
		return self._ikControls["RightArm"].Weight
	end
	return 0
end

-- Set IK weight for smooth blending (0-1)
function IKController:SetRightArmWeight(weight)
	if self._ikControls["RightArm"] then
		self._ikControls["RightArm"].Weight = math.clamp(weight, 0, 1)
	end
end

-- === KNIT LIFECYCLE ===

function IKController:KnitInit()
	print("[IKController] Initializing...")
end

function IKController:KnitStart()
	-- Early exit if disabled
	if not IK_CONFIG.Enabled then
		warn("[IKController] IK system is disabled")
		return
	end
	
	local player = Players.LocalPlayer
	
	-- Setup for current character
	if player.Character then
		task.spawn(function()
			self:SetupCharacterIK(player.Character)
		end)
	end
	
	-- Setup for future characters (respawns)
	player.CharacterAdded:Connect(function(character)
		-- Clean up old IK first
		self:CleanupIK()
		
		-- Small delay to ensure character is fully loaded
		task.wait(0.5)
		
		self:SetupCharacterIK(character)
	end)
	
	print("[IKController] Started - Right arm will extend forward")
end

return IKController

