--[[
	BallController
	
	Tiny Wings-style gameplay controller.
	- Guide ball follows spline and pulls player via constraint
	- Tap/hold to DIVE into downslopes for extra speed
	- Release to glide up and launch off hills
	- Camera follows the ball
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local Knit = require(Packages.Knit)

local BallController = Knit.CreateController {
	Name = "BallController",
}

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         CONFIGURATION                                       ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

local CONFIG = {
	-- Camera settings (side view for Tiny Wings style)
	CameraOffset = Vector3.new(-5, 20, 50),
	CameraSmoothing = 0.15,
	
	-- Guide sphere settings
	GuideRadius = 2,
	GuideColor = Color3.fromRGB(255, 255, 0),
	GuideTransparency = 0.5,
	GuideMaterial = Enum.Material.Neon,
	GuideSpeed = 0.5,                          -- Constant speed along spline (studs/sec)
	
	-- AlignPosition settings (pulls player toward guide)
	AlignMaxForce = 500000,                   -- Max force to pull player (very strong!)
	AlignResponsiveness = 50,                 -- How quickly it responds (higher = snappier, more rigid)
	
	-- Tiny Wings dive physics
	DiveForce = 50000,          -- Downward force when diving (tap/hold)
	DiveSlopeBonus = 30000,     -- Extra forward force when diving on downslope
	SlopeBonusThreshold = -0.1, -- Slope threshold for bonus (negative = downhill)
	MaxSpeed = 200,             -- Maximum velocity cap
	
	-- Jump/boost
	JumpForce = 100000,         -- Upward force on space key (massive!)
	
	-- Air detection
	AirThreshold = 3,           -- Distance from ground to count as "in air"
}

-- State
local player = Players.LocalPlayer
local camera = Workspace.CurrentCamera
local ballService = nil
local terrainController = nil
local splineController = nil
local myBall = nil
local myGuide = nil
local vectorForce = nil
local isDiving = false
local isJumping = false
local isInAir = false
local guideT = 0  -- Guide position on spline (0-1), moves at constant speed
local guideDirection = 1  -- 1 = forward, -1 = reverse

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         INPUT HANDLING                                      ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

local function onInputBegan(input, gameProcessed)
	if gameProcessed then return end
	
	-- Jump on Space or W (upward force)
	if input.KeyCode == Enum.KeyCode.Space or input.KeyCode == Enum.KeyCode.W then
		isJumping = true
		print("[BallController] JUMP! Applying upward force:", CONFIG.JumpForce)
	end
	
	-- Dive on tap/click/touch/Down/S (downward force)
	if input.UserInputType == Enum.UserInputType.MouseButton1 
		or input.UserInputType == Enum.UserInputType.Touch
		or input.KeyCode == Enum.KeyCode.Down
		or input.KeyCode == Enum.KeyCode.S then
		isDiving = true
	end
end

local function onInputEnded(input, gameProcessed)
	-- Stop jumping
	if input.KeyCode == Enum.KeyCode.Space or input.KeyCode == Enum.KeyCode.W then
		isJumping = false
	end
	
	-- Stop diving
	if input.UserInputType == Enum.UserInputType.MouseButton1 
		or input.UserInputType == Enum.UserInputType.Touch
		or input.KeyCode == Enum.KeyCode.Down
		or input.KeyCode == Enum.KeyCode.S then
		isDiving = false
	end
end

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         GUIDE SPHERE (CLIENT-SIDE)                          ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

local function createGuideSphere(ball, ballModel)
	if not ball or not ballModel then return nil end
	
	print("[BallController] Creating guide sphere (client-side)")
	
	-- Create the guide sphere
	local guide = Instance.new("Part")
	guide.Name = "GuideSphere"
	guide.Shape = Enum.PartType.Ball
	guide.Size = Vector3.new(CONFIG.GuideRadius * 2, CONFIG.GuideRadius * 2, CONFIG.GuideRadius * 2)
	guide.Color = CONFIG.GuideColor
	guide.Transparency = CONFIG.GuideTransparency
	guide.Material = CONFIG.GuideMaterial
	guide.Anchored = true
	guide.CanCollide = false
	guide.CanQuery = false
	guide.CanTouch = false
	guide.Massless = true
	guide.CastShadow = false
	guide.Parent = ballModel
	
	-- Create attachment on guide (target)
	local guideAttachment = Instance.new("Attachment")
	guideAttachment.Name = "GuideAttachment"
	guideAttachment.Parent = guide
	
	-- Create attachment on ball
	local ballAttachment = Instance.new("Attachment")
	ballAttachment.Name = "BallGuideAttachment"
	ballAttachment.Parent = ball
	
	-- Create AlignPosition - pulls player ball toward guide
	-- Only affects the ball, NOT the guide (one-way force)
	local align = Instance.new("AlignPosition")
	align.Name = "GuideAlign"
	align.Attachment0 = ballAttachment      -- The part that moves (player ball)
	align.Attachment1 = guideAttachment     -- The target (guide sphere)
	align.MaxForce = CONFIG.AlignMaxForce
	align.Responsiveness = CONFIG.AlignResponsiveness
	align.Mode = Enum.PositionAlignmentMode.TwoAttachment
	align.ApplyAtCenterOfMass = true
	align.ReactionForceEnabled = false      -- KEY: Guide doesn't feel any force!
	align.Parent = ball
	
	print("[BallController] Guide sphere + AlignPosition created (one-way pull)")
	return guide
end

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         PHYSICS HELPERS                                     ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

local function checkIfInAir(ball)
	if not ball then return false end
	
	local ballPos = ball.Position
	local ballRadius = ball.Size.Y / 2
	
	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.FilterDescendantsInstances = {ball.Parent}
	
	local result = Workspace:Raycast(ballPos, Vector3.new(0, -(ballRadius + CONFIG.AirThreshold + 5), 0), rayParams)
	
	if result then
		local distanceToGround = (ballPos - result.Position).Magnitude - ballRadius
		return distanceToGround > CONFIG.AirThreshold
	end
	
	return true
end

local function getSlopeAtBall(ball)
	if not terrainController or not ball then return 0 end
	return terrainController:GetSlopeAtX(ball.Position.X)
end

local function applyForces(ball)
	if not ball then 
		return 
	end
	
	if not vectorForce then
		-- Try to find it again
		vectorForce = ball:FindFirstChild("MovementForce")
		if not vectorForce then
			warn("[BallController] MovementForce not found on ball!")
			return
		else
			print("[BallController] Found MovementForce!")
		end
	end
	
	local slope = getSlopeAtBall(ball)
	local speed = ball.AssemblyLinearVelocity.Magnitude
	
	local forceX = 0
	local forceY = 0
	local forceZ = 0
	
	-- Jump - upward force
	if isJumping then
		forceY = CONFIG.JumpForce
	end
	
	-- Dive - downward force (overrides jump if both pressed)
	if isDiving then
		forceY = -CONFIG.DiveForce
		
		-- Bonus forward force when diving on downslope (Tiny Wings feel!)
		if slope < CONFIG.SlopeBonusThreshold then
			forceX = math.abs(slope) * CONFIG.DiveSlopeBonus
		end
	end
	
	-- Cap speed
	if speed > CONFIG.MaxSpeed then
		forceX = 0
	end
	
	vectorForce.Force = Vector3.new(forceX, forceY, forceZ)
end

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         CAMERA CONTROL                                      ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

local function updateCamera(ball)
	if not ball then return end
	
	local ballPos = ball.Position
	local targetPos = ballPos + CONFIG.CameraOffset
	local currentPos = camera.CFrame.Position
	local newPos = currentPos:Lerp(targetPos, CONFIG.CameraSmoothing)
	
	camera.CFrame = CFrame.new(newPos, ballPos)
end

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         KNIT LIFECYCLE                                      ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

function BallController:KnitInit()
	print("[BallController] Initializing...")
end

function BallController:KnitStart()
	print("[BallController] Started")
	
	-- Get controllers
	terrainController = Knit.GetController("TerrainController")
	splineController = Knit.GetController("SplineController")
	
	-- Get ball service
	ballService = Knit.GetService("BallPlayerService")
	
	-- Set up input
	UserInputService.InputBegan:Connect(onInputBegan)
	UserInputService.InputEnded:Connect(onInputEnded)
	
	-- Disable default camera
	local PlayerScripts = player:WaitForChild("PlayerScripts")
	local PlayerModule = PlayerScripts:FindFirstChild("PlayerModule")
	if PlayerModule then
		PlayerModule:Destroy()
		print("[BallController] Disabled default PlayerModule")
	end
	
	camera.CameraType = Enum.CameraType.Scriptable
	camera.CameraSubject = nil
	
	-- RenderStepped: Camera + Guide update
	RunService.RenderStepped:Connect(function(deltaTime)
		if camera.CameraType ~= Enum.CameraType.Scriptable then
			camera.CameraType = Enum.CameraType.Scriptable
		end
		
		-- Get ball reference
		if not myBall then
			local ballModel = Workspace:FindFirstChild(player.Name .. "_Ball")
			if ballModel then
				myBall = ballModel:FindFirstChild("Ball")
				myGuide = ballModel:FindFirstChild("GuideSphere")
				
				-- Get VectorForce reference for dive
				if myBall then
					vectorForce = myBall:FindFirstChild("MovementForce")
				end
			end
		end
		
		-- Check for guide
		if myBall and not myGuide then
			local ballModel = myBall.Parent
			if ballModel then
				myGuide = ballModel:FindFirstChild("GuideSphere")
			end
		end
		
		-- Update
		if myBall and myBall.Parent then
			-- Camera
			updateCamera(myBall)
			
			-- Check air state
			isInAir = checkIfInAir(myBall)
			
			-- Apply jump/dive forces
			applyForces(myBall)
			
			-- Move guide sphere along spline at CONSTANT SPEED (independent of player)
			if myGuide and myGuide.Parent and splineController then
				local splineLength = splineController:GetLength()
				
				if splineLength > 0 then
					-- Advance guide at constant speed in current direction
					local speedPerFrame = CONFIG.GuideSpeed * deltaTime
					local tIncrement = speedPerFrame / splineLength
					guideT = guideT + (tIncrement * guideDirection)
					
					-- Reverse direction at ends (ping-pong)
					if guideT >= 1 then
						guideT = 1
						guideDirection = -1  -- Go reverse
					elseif guideT <= 0 then
						guideT = 0
						guideDirection = 1   -- Go forward
					end
					
					-- Get position from spline
					local targetGuidePos = splineController:GetPositionAt(guideT)
					
					if targetGuidePos then
						-- Set position directly (guide is anchored, no physics)
						myGuide.Position = targetGuidePos
					end
				end
			end
		else
			myBall = nil
			myGuide = nil
			vectorForce = nil
		end
	end)
	
	-- Listen for ball creation
	ballService.BallCreated:Connect(function()
		print("[BallController] Ball created signal received")
		task.wait(0.1)
		
		local ballModel = Workspace:FindFirstChild(player.Name .. "_Ball")
		if ballModel then
			myBall = ballModel:FindFirstChild("Ball")
			vectorForce = myBall and myBall:FindFirstChild("MovementForce")
			
			-- Create guide sphere
			if myBall and splineController then
				task.spawn(function()
					local maxWait = 5
					local waited = 0
					while splineController:GetLength() == 0 and waited < maxWait do
						task.wait(0.2)
						waited = waited + 0.2
					end
					
					if splineController:GetLength() > 0 then
						myGuide = createGuideSphere(myBall, ballModel)
						print("[BallController] Guide sphere ready")
					else
						warn("[BallController] Spline not ready, guide disabled")
					end
				end)
			end
			
			print("[BallController] Ball reference set")
		end
	end)
	
	print("[BallController] Controls: Space/W = JUMP up, S/Down/Click = DIVE down")
end

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         PUBLIC API                                          ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

function BallController:GetBall()
	return myBall
end

function BallController:GetGuide()
	return myGuide
end

function BallController:IsDiving()
	return isDiving
end

function BallController:IsJumping()
	return isJumping
end

function BallController:IsInAir()
	return isInAir
end

function BallController:SetCameraOffset(offset)
	CONFIG.CameraOffset = offset
end

function BallController:SetGuideLookAhead(lookAhead)
	CONFIG.GuideLookAhead = lookAhead
end

return BallController
