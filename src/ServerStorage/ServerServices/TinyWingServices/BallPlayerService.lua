--[[
	BallPlayerService
	
	Puts players inside a rolling sphere (Monkey Ball style).
	Disables default character movement and animations.
	The ball rolls purely based on physics - gravity and terrain slopes.
	
	Features:
	- Encases player in a transparent sphere
	- Disables Humanoid movement and animations
	- Ball rolls based on physics
	- Camera follows the ball
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local Knit = require(Packages.Knit)

local BallPlayerService = Knit.CreateService {
	Name = "BallPlayerService",
	Client = {
		BallCreated = Knit.CreateSignal(),  -- Fires when ball is created for a player
	},
	
	-- Store player balls
	_playerBalls = {},  -- [Player] = BallModel
}

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         CONFIGURATION                                       ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

local CONFIG = {
	-- Ball properties
	BallRadius = 5,                          -- Size of the ball (studs)
	BallColor = Color3.fromRGB(100, 200, 255), -- Light blue transparent ball
	BallTransparency = 0.5,                  -- How see-through the ball is
	BallMaterial = Enum.Material.ForceField, -- Cool force field look
	
	-- Physics properties
	BallDensity = 0.5,                       -- Lower = lighter, rolls easier
	BallFriction = 0.3,                      -- Surface friction
	BallElasticity = 0.2,                    -- Bounciness
	BallFrictionWeight = 1,
	BallElasticityWeight = 1,
	
	-- Player visibility inside ball
	PlayerTransparency = 0.3,                -- Make player slightly transparent
	HideAccessories = true,                  -- Hide hats etc for cleaner look
	
	-- Movement assist (optional gentle push in camera direction)
	EnableMovementAssist = true,
	MovementForce = 500,                     -- Force applied when pressing movement keys
	
	-- Guide sphere (follows spline, pulls ball along path)
	EnableGuide = true,
	GuideRadius = 2,                         -- Size of guide sphere
	GuideColor = Color3.fromRGB(255, 255, 100), -- Yellow guide
	GuideTransparency = 0.7,
	GuideMaterial = Enum.Material.Neon,
	GuideRopeLength = 8,                     -- Rod length (rigid distance from guide)
	GuideLookAhead = 10,                     -- How far ahead on spline the guide looks (studs)
}

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         BALL CREATION                                       ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

-- Create the ball for a player
function BallPlayerService:CreateBallForPlayer(player)
	local character = player.Character
	if not character then return nil end
	
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if not humanoid or not rootPart then return nil end
	
	-- Remove existing ball if any
	self:RemoveBallFromPlayer(player)
	
	print(string.format("[BallPlayerService] Creating ball for %s", player.Name))
	
	-- Create ball model
	local ballModel = Instance.new("Model")
	ballModel.Name = player.Name .. "_Ball"
	
	-- Create the sphere
	local ball = Instance.new("Part")
	ball.Name = "Ball"
	ball.Shape = Enum.PartType.Ball
	ball.Size = Vector3.new(CONFIG.BallRadius * 2, CONFIG.BallRadius * 2, CONFIG.BallRadius * 2)
	ball.Color = CONFIG.BallColor
	ball.Transparency = CONFIG.BallTransparency
	ball.Material = CONFIG.BallMaterial
	ball.Anchored = false
	ball.CanCollide = true
	ball.CastShadow = true
	
	-- Position ball at player's position
	ball.CFrame = rootPart.CFrame
	
	-- Set up physics properties
	local physProperties = PhysicalProperties.new(
		CONFIG.BallDensity,
		CONFIG.BallFriction,
		CONFIG.BallElasticity,
		CONFIG.BallFrictionWeight,
		CONFIG.BallElasticityWeight
	)
	ball.CustomPhysicalProperties = physProperties
	
	-- Make ball the primary part
	ball.Parent = ballModel
	ballModel.PrimaryPart = ball
	
	-- Create attachment for forces
	local attachment = Instance.new("Attachment")
	attachment.Name = "ForceAttachment"
	attachment.Parent = ball
	
	-- Add VectorForce for movement assist (controlled by client)
	if CONFIG.EnableMovementAssist then
		local vectorForce = Instance.new("VectorForce")
		vectorForce.Name = "MovementForce"
		vectorForce.Attachment0 = attachment
		vectorForce.Force = Vector3.new(0, 0, 0)
		vectorForce.RelativeTo = Enum.ActuatorRelativeTo.World
		vectorForce.ApplyAtCenterOfMass = true
		vectorForce.Parent = ball
	end
	
	-- Add angular velocity for spin control (optional)
	local angularVelocity = Instance.new("AngularVelocity")
	angularVelocity.Name = "SpinControl"
	angularVelocity.Attachment0 = attachment
	angularVelocity.AngularVelocity = Vector3.new(0, 0, 0)
	angularVelocity.MaxTorque = 0 -- Disabled by default, client can enable
	angularVelocity.RelativeTo = Enum.ActuatorRelativeTo.World
	angularVelocity.Parent = ball
	
	
	-- Parent ball model to workspace
	ballModel.Parent = Workspace
	
	-- SET NETWORK OWNERSHIP to player for smooth client-side physics
	ball:SetNetworkOwner(player)
	print(string.format("[BallPlayerService] Set network owner of ball to %s", player.Name))
	
	-- Now set up the character inside the ball
	self:SetupCharacterInBall(player, character, ball)
	
	-- NOTE: Guide sphere is now created entirely on the CLIENT (BallController)
	-- for smooth, lag-free spline following
	
	-- Store reference
	self._playerBalls[player] = ballModel
	
	-- Fire client event
	self.Client.BallCreated:Fire(player, ballModel)
	
	print(string.format("[BallPlayerService] Ball created for %s at position %s", 
		player.Name, tostring(ball.Position)))
	
	return ballModel
end

-- NOTE: Guide sphere is now created entirely on the CLIENT (BallController)
-- for smooth, lag-free spline following. See BallController.lua

-- Set up character inside the ball
function BallPlayerService:SetupCharacterInBall(player, character, ball)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local rootPart = character:FindFirstChild("HumanoidRootPart")
	
	if not humanoid or not rootPart then return end
	
	-- Disable humanoid movement completely
	humanoid.WalkSpeed = 0
	humanoid.JumpPower = 0
	humanoid.JumpHeight = 0
	humanoid.AutoRotate = false
	humanoid.PlatformStand = true  -- This prevents falling animation!
	
	-- Set humanoid state to Physics (prevents state changes)
	humanoid:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Freefall, false)
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Swimming, false)
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Climbing, false)
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Running, false)
	humanoid:SetStateEnabled(Enum.HumanoidStateType.GettingUp, false)
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, false)
	
	-- Force Physics state
	humanoid:ChangeState(Enum.HumanoidStateType.Physics)
	
	-- Disable the Animate script
	local animateScript = character:FindFirstChild("Animate")
	if animateScript then
		animateScript.Disabled = true
	end
	
	-- Disable animations - destroy the Animator to fully stop animations
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if animator then
		-- Stop all playing animations first
		for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
			track:Stop(0)
		end
		-- Destroy animator to prevent any new animations
		animator:Destroy()
	end
	
	-- Make character parts non-collidable and semi-transparent
	for _, part in ipairs(character:GetDescendants()) do
		if part:IsA("BasePart") then
			part.CanCollide = false
			if CONFIG.PlayerTransparency > 0 then
				part.Transparency = math.max(part.Transparency, CONFIG.PlayerTransparency)
			end
		end
		
		-- Hide accessories if configured
		if CONFIG.HideAccessories and part:IsA("Accessory") then
			part:Destroy()
		end
	end
	
	-- Weld character to ball center
	local weld = Instance.new("WeldConstraint")
	weld.Name = "BallWeld"
	weld.Part0 = ball
	weld.Part1 = rootPart
	weld.Parent = ball
	
	-- Position character at ball center
	rootPart.CFrame = ball.CFrame
	
	-- Make rootPart massless so it doesn't affect ball physics
	rootPart.Massless = true
	for _, part in ipairs(character:GetDescendants()) do
		if part:IsA("BasePart") then
			part.Massless = true
		end
	end
	
	-- Keep humanoid in Physics state (in case something tries to change it)
	local RunService = game:GetService("RunService")
	local timeSinceCheck = 0
	local checkInterval = 0.5  -- Only check every 0.5 seconds
	
	local stateConnection
	stateConnection = RunService.Heartbeat:Connect(function(deltaTime)
		-- Check if character/humanoid still exist
		if not character or not character.Parent or not humanoid or not humanoid.Parent then
			stateConnection:Disconnect()
			return
		end
		
		-- Only check periodically (not every frame)
		timeSinceCheck = timeSinceCheck + deltaTime
		if timeSinceCheck >= checkInterval then
			timeSinceCheck = 0
			if humanoid:GetState() ~= Enum.HumanoidStateType.Physics then
				humanoid:ChangeState(Enum.HumanoidStateType.Physics)
			end
		end
	end)
end

-- Remove ball from player
function BallPlayerService:RemoveBallFromPlayer(player)
	local ballModel = self._playerBalls[player]
	if ballModel then
		ballModel:Destroy()
		self._playerBalls[player] = nil
		print(string.format("[BallPlayerService] Removed ball from %s", player.Name))
	end
end

-- Get player's ball
function BallPlayerService:GetPlayerBall(player)
	return self._playerBalls[player]
end

-- Get the actual ball part
function BallPlayerService:GetBallPart(player)
	local ballModel = self._playerBalls[player]
	if ballModel then
		return ballModel:FindFirstChild("Ball")
	end
	return nil
end

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         MOVEMENT CONTROL                                    ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

-- Apply force to player's ball (called from client)
function BallPlayerService:ApplyForce(player, forceVector)
	local ball = self:GetBallPart(player)
	if not ball then return end
	
	local vectorForce = ball:FindFirstChild("MovementForce")
	if vectorForce then
		-- Clamp force magnitude
		local maxForce = CONFIG.MovementForce
		if forceVector.Magnitude > maxForce then
			forceVector = forceVector.Unit * maxForce
		end
		vectorForce.Force = forceVector
	end
end

-- Stop force on player's ball
function BallPlayerService:StopForce(player)
	local ball = self:GetBallPart(player)
	if not ball then return end
	
	local vectorForce = ball:FindFirstChild("MovementForce")
	if vectorForce then
		vectorForce.Force = Vector3.new(0, 0, 0)
	end
end

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         PLAYER HANDLING                                     ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

-- Handle player character added
function BallPlayerService:OnCharacterAdded(player, character)
	-- Wait for character to load
	task.wait(0.5)
	
	-- Create ball for player
	self:CreateBallForPlayer(player)
end

-- Handle player added
function BallPlayerService:OnPlayerAdded(player)
	-- If character already exists
	if player.Character then
		self:OnCharacterAdded(player, player.Character)
	end
	
	-- Listen for future character spawns
	player.CharacterAdded:Connect(function(character)
		self:OnCharacterAdded(player, character)
	end)
end

-- Handle player leaving
function BallPlayerService:OnPlayerRemoving(player)
	self:RemoveBallFromPlayer(player)
end

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         KNIT LIFECYCLE                                      ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

function BallPlayerService:KnitInit()
	print("[BallPlayerService] Initializing...")
end

function BallPlayerService:KnitStart()
	print("[BallPlayerService] Started")
	
	-- Connect player events
	Players.PlayerAdded:Connect(function(player)
		self:OnPlayerAdded(player)
	end)
	
	Players.PlayerRemoving:Connect(function(player)
		self:OnPlayerRemoving(player)
	end)
	
	-- Handle existing players
	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(function()
			self:OnPlayerAdded(player)
		end)
	end
end

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         CLIENT API                                          ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

-- Client can request force application
function BallPlayerService.Client:ApplyForce(player, forceVector)
	self.Server:ApplyForce(player, forceVector)
end

function BallPlayerService.Client:StopForce(player)
	self.Server:StopForce(player)
end

-- Client can get their ball
function BallPlayerService.Client:GetMyBall(player)
	return self.Server:GetPlayerBall(player)
end

-- Client can get config
function BallPlayerService.Client:GetConfig(player)
	return CONFIG
end

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         PUBLIC API                                          ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

-- Get all player balls
function BallPlayerService:GetAllBalls()
	return self._playerBalls
end

-- Update config
function BallPlayerService:SetConfig(key, value)
	if CONFIG[key] ~= nil then
		CONFIG[key] = value
		print("[BallPlayerService] Config updated:", key, "=", tostring(value))
		return true
	end
	return false
end

-- Get config
function BallPlayerService:GetConfig()
	return CONFIG
end

-- Respawn player in ball at position
function BallPlayerService:RespawnAtPosition(player, position)
	local ball = self:GetBallPart(player)
	if ball then
		-- Reset velocity
		ball.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
		ball.AssemblyAngularVelocity = Vector3.new(0, 0, 0)
		-- Move to position
		ball.CFrame = CFrame.new(position)
	end
end

return BallPlayerService

