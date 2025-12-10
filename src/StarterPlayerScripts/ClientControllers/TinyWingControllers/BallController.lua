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
	
	-- Guide physics (heightfield-based, world units)
	GuideBaseSpeed = 15,                      -- Minimum horizontal speed (studs/sec)
	GuideMaxSpeed = 150,                      -- Maximum horizontal speed
	GuideSlopeAccel = 300,                    -- How slope affects horizontal acceleration
	GuideDiveBoost = 600,                     -- Extra accel when diving on downhill (BOOSTED!)
	GuideFriction = 0.995,                    -- Horizontal speed decay per frame
	
	
	-- Terrain bounds
	GuideStartX = -200,                       -- Start of terrain
	GuideEndX = 1800,                         -- End of terrain
	GuideHeightOffset = 3,                    -- Height above terrain surface
	
	-- AlignPosition settings (pulls player toward guide)
	AlignMaxForce = 500000,                   -- Max force to pull player (very strong!)
	AlignResponsiveness = 50,                 -- How quickly it responds (higher = snappier, more rigid)
	
	-- Air detection
	AirThreshold = 3,           -- Distance from ground to count as "in air"
}

-- State
local player = Players.LocalPlayer
local camera = Workspace.CurrentCamera
local ballService = nil
local terrainController = nil
local splineController = nil  -- Keep for visualization only
local myBall = nil
local myGuide = nil
local isDiving = false
local isInAir = false

-- Guide ball state (simple heightfield physics)
local guideX = 0           -- World X position
local guideY = 0           -- World Y position  
local guideVX = 20         -- Horizontal velocity (studs/sec)
local guideDirection = 1   -- 1 = forward, -1 = reverse

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         INPUT HANDLING                                      ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

local function onInputBegan(input, gameProcessed)
	if gameProcessed then return end
	
	-- Dive on Space, W, Click, Touch, Down, S
	if input.KeyCode == Enum.KeyCode.Space 
		or input.KeyCode == Enum.KeyCode.W
		or input.KeyCode == Enum.KeyCode.Down
		or input.KeyCode == Enum.KeyCode.S
		or input.UserInputType == Enum.UserInputType.MouseButton1 
		or input.UserInputType == Enum.UserInputType.Touch then
		isDiving = true
	end
end

local function onInputEnded(input, gameProcessed)
	-- Stop diving
	if input.KeyCode == Enum.KeyCode.Space 
		or input.KeyCode == Enum.KeyCode.W
		or input.KeyCode == Enum.KeyCode.Down
		or input.KeyCode == Enum.KeyCode.S
		or input.UserInputType == Enum.UserInputType.MouseButton1 
		or input.UserInputType == Enum.UserInputType.Touch then
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

-- No direct forces on player - AlignPosition drags them behind the guide
-- Guide physics (gravity, momentum, dive) handles all the speed changes

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         CAMERA CONTROL                                      ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

local function updateCamera()
	-- Follow the guide ball instead of player ball
	if not myGuide then return end
	
	local guidePos = myGuide.Position
	local targetPos = guidePos + CONFIG.CameraOffset
	local currentPos = camera.CFrame.Position
	local newPos = currentPos:Lerp(targetPos, CONFIG.CameraSmoothing)
	
	camera.CFrame = CFrame.new(newPos, guidePos)
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
			-- Camera follows guide ball
			updateCamera()
			
			-- Check air state (for future use)
			isInAir = checkIfInAir(myBall)
			
			-- ═══════════════════════════════════════════════════════════════════════
			-- GUIDE PHYSICS - Sub-stepped for smooth movement at any speed
			-- ═══════════════════════════════════════════════════════════════════════
			if myGuide and myGuide.Parent and terrainController then
				-- Sub-step physics: more steps at higher speeds to prevent skipping
				local maxStepDistance = 2  -- Maximum distance per substep (studs)
				local frameDistance = guideVX * deltaTime
				local numSteps = math.max(1, math.ceil(frameDistance / maxStepDistance))
				local stepDelta = deltaTime / numSteps
				
				for step = 1, numSteps do
					-- Get terrain info at current position
					local slope = terrainController:GetSlopeAtX(guideX) * guideDirection
					
					-- Acceleration based on slope
					local slopeAccel = 0
					if slope < 0 then
						-- Downhill: gain speed
						slopeAccel = -slope * CONFIG.GuideSlopeAccel
						if isDiving then
							slopeAccel = slopeAccel + CONFIG.GuideDiveBoost
						end
					end
					
					-- Apply physics
					guideVX = guideVX + slopeAccel * stepDelta
					guideVX = guideVX * math.pow(CONFIG.GuideFriction, stepDelta * 60)
					guideVX = math.clamp(guideVX, CONFIG.GuideBaseSpeed, CONFIG.GuideMaxSpeed)
					
					-- Move along terrain
					guideX = guideX + guideVX * stepDelta * guideDirection
					
					-- Follow terrain surface
					guideY = terrainController:GetHeightAtX(guideX) + CONFIG.GuideHeightOffset
					
					-- Bounds check - reverse at ends
					if guideX >= CONFIG.GuideEndX then
						guideX = CONFIG.GuideEndX
						guideDirection = -1
						guideVX = CONFIG.GuideBaseSpeed
						break
					elseif guideX <= CONFIG.GuideStartX then
						guideX = CONFIG.GuideStartX
						guideDirection = 1
						guideVX = CONFIG.GuideBaseSpeed
						break
					end
				end
				
				-- Update guide position
				myGuide.Position = Vector3.new(guideX, guideY, 0)
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
					
					-- Initialize guide position at terrain start
					guideX = CONFIG.GuideStartX + 50  -- Start a bit into the terrain
					guideY = terrainController:GetHeightAtX(guideX) + CONFIG.GuideHeightOffset
					guideVX = CONFIG.GuideBaseSpeed
					guideOnGround = true
					
					myGuide = createGuideSphere(myBall, ballModel)
					print("[BallController] Guide sphere ready (heightfield mode)")
				end)
			end
			
			print("[BallController] Ball reference set")
		end
	end)
	
	print("[BallController] Controls: Hold Space/Click = DIVE (speed up on downhills!)")
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

function BallController:IsInAir()
	return isInAir
end

function BallController:IsGuideInAir()
	return false  -- Guide always follows terrain now
end

function BallController:GetGuideAirHeight()
	return 0  -- Guide always follows terrain now
end

function BallController:GetGuideVelocity()
	return guideVX
end

function BallController:GetGuidePosition()
	return Vector3.new(guideX, guideY, 0)
end

function BallController:SetCameraOffset(offset)
	CONFIG.CameraOffset = offset
end

function BallController:SetGuideLookAhead(lookAhead)
	CONFIG.GuideLookAhead = lookAhead
end

return BallController
