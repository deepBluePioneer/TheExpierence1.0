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
	
	-- Guide physics (fake gravity & momentum)
	-- Speed is in "spline units per second" (0-1 range over spline length)
	GuideBaseSpeed = 0.15,                    -- Minimum speed (always moving forward)
	GuideMaxSpeed = 0.8,                      -- Maximum speed
	GuideGravity = 0.8,                       -- How much slope affects speed
	GuideDiveBoost = 1.2,                     -- Extra speed boost when diving on downhill
	GuideFriction = 0.992,                    -- Speed decay per frame (lower = more drag)
	
	-- Guide air/launch physics (more realistic)
	GuideLaunchThreshold = 0.35,              -- Min speed to launch off hills
	GuideLaunchMultiplier = 15,               -- How much speed converts to launch (lower = realistic)
	GuideAirGravity = 60,                     -- Realistic gravity (higher = falls faster)
	GuideAirDiveBoost = 40,                   -- Extra fall speed when diving in air
	GuideMaxAirHeight = 25,                   -- Max height above spline (lower = realistic)
	
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
local splineController = nil
local myBall = nil
local myGuide = nil
local isDiving = false
local isInAir = false
local guideT = 0  -- Guide position on spline (0-1)
local guideDirection = 1  -- 1 = forward, -1 = reverse
local guideVelocity = 0.2  -- Current speed of guide (studs/sec), has momentum
local guideInAir = false  -- Is guide currently airborne?
local lastSlope = 0  -- Track slope for launch detection

-- Air trajectory (world position when airborne)
local guideAirPos = Vector3.new(0, 0, 0)  -- World position while in air
local guideAirVelX = 0  -- Horizontal velocity in air
local guideAirVelY = 0  -- Vertical velocity in air

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
			
			-- Check air state (for future use)
			isInAir = checkIfInAir(myBall)
			
			-- Move guide sphere with PHYSICS (gravity, momentum, launch, air trajectory)
			if myGuide and myGuide.Parent and splineController then
				local splineLength = splineController:GetLength()
				
				if splineLength > 0 then
					
					-- ═══════════════════════════════════════════════════════════
					-- AIR PHYSICS - Follow ballistic trajectory (not spline!)
					-- ═══════════════════════════════════════════════════════════
					if guideInAir then
						-- Apply gravity to Y velocity
						guideAirVelY = guideAirVelY - (CONFIG.GuideAirGravity * deltaTime)
						
						-- Dive in air - press space to fall faster
						if isDiving then
							guideAirVelY = guideAirVelY - (CONFIG.GuideAirDiveBoost * deltaTime)
						end
						
						-- Update world position based on velocity
						guideAirPos = guideAirPos + Vector3.new(
							guideAirVelX * deltaTime * guideDirection,
							guideAirVelY * deltaTime,
							0
						)
						
						-- Cap max height
						local splinePosAtX = splineController:GetPositionAtWorldX(guideAirPos.X)
						local maxY = splinePosAtX and (splinePosAtX.Y + CONFIG.GuideMaxAirHeight) or (guideAirPos.Y)
						if guideAirPos.Y > maxY then
							guideAirPos = Vector3.new(guideAirPos.X, maxY, guideAirPos.Z)
							guideAirVelY = 0
						end
						
						-- Check if we've landed (guide Y below spline Y at current X)
						if splinePosAtX then
							if guideAirPos.Y <= splinePosAtX.Y then
								-- LAND! Snap back to spline
								guideInAir = false
								
								-- Update guideT to match where we landed
								guideT = splineController:WorldXToSplineT(guideAirPos.X)
								
								-- Get landing slope to determine speed adjustment
								local landingDerivative = splineController:GetDerivativeAt(guideT)
								local landingSlope = 0
								if landingDerivative then
									landingSlope = landingDerivative.Unit.Y * guideDirection
								end
								
								-- Simple landing: resume with stored velocity
								-- Slight adjustment based on landing slope
								if landingSlope < -0.1 then
									-- Landing on downslope - small speed boost
									guideVelocity = guideVelocity * 1.1
								elseif landingSlope > 0.1 then
									-- Landing on upslope - lose some speed
									guideVelocity = guideVelocity * 0.85
								end
								-- Flat landing = no change
								
								guideVelocity = math.clamp(guideVelocity, CONFIG.GuideBaseSpeed, CONFIG.GuideMaxSpeed)
								
								guideAirVelX = 0
								guideAirVelY = 0
							end
						end
						
						-- Set guide position to air trajectory position
						myGuide.Position = guideAirPos
						
					-- ═══════════════════════════════════════════════════════════
					-- GROUND PHYSICS - Follow spline
					-- ═══════════════════════════════════════════════════════════
					else
						-- Get slope at current position
						local derivative = splineController:GetDerivativeAt(guideT)
						local slope = 0
						if derivative then
							local normalizedDir = derivative.Unit
							slope = normalizedDir.Y * guideDirection
						end
						
						-- Check for launch: need significant slope change AND high speed
						local slopeChange = slope - lastSlope
						-- Only launch if: big slope change, steep uphill, AND fast enough
						local isLaunchRamp = slopeChange > 0.05 and slope > 0.15 and lastSlope < 0
						
						if isLaunchRamp and guideVelocity >= CONFIG.GuideLaunchThreshold then
							-- LAUNCH! Start ballistic trajectory
							local currentPos = splineController:GetPositionAt(guideT)
							if currentPos then
								guideInAir = true
								guideAirPos = currentPos + Vector3.new(0, 0.5, 0)
								
								-- Convert spline velocity to world velocity (scaled down)
								local worldSpeed = guideVelocity * splineLength * 0.05
								guideAirVelX = worldSpeed
								
								-- Vertical launch based on speed and slope
								local launchAngle = math.min(slope, 0.5)
								guideAirVelY = worldSpeed * launchAngle * CONFIG.GuideLaunchMultiplier * 0.05
								
								guideVelocity = guideVelocity * 0.7
							end
						else
							-- Normal ground physics (no launch)
							local gravityAccel = -slope * CONFIG.GuideGravity
							
							-- Dive boost on ground - ONLY works on downhill or flat
							if isDiving then
								if slope <= 0 then
									gravityAccel = gravityAccel + CONFIG.GuideDiveBoost * math.abs(slope + 0.5)
								end
							end
							
							guideVelocity = guideVelocity + (gravityAccel * deltaTime)
							guideVelocity = guideVelocity * CONFIG.GuideFriction
						end
						
						lastSlope = slope
						
						-- Clamp velocity
						guideVelocity = math.clamp(guideVelocity, CONFIG.GuideBaseSpeed, CONFIG.GuideMaxSpeed)
						
						-- Advance along spline
						local tIncrement = (guideVelocity * deltaTime) / splineLength
						guideT = guideT + (tIncrement * guideDirection)
						
						-- Reverse direction at ends
						if guideT >= 1 then
							guideT = 1
							guideDirection = -1
							guideVelocity = CONFIG.GuideBaseSpeed
							guideInAir = false
						elseif guideT <= 0 then
							guideT = 0
							guideDirection = 1
							guideVelocity = CONFIG.GuideBaseSpeed
							guideInAir = false
						end
						
						-- Get position from spline
						local splinePos = splineController:GetPositionAt(guideT)
						if splinePos then
							myGuide.Position = splinePos
						end
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

function BallController:IsJumping()
	return isJumping
end

function BallController:IsInAir()
	return isInAir
end

function BallController:IsGuideInAir()
	return guideInAir
end

function BallController:GetGuideAirHeight()
	if guideInAir and splineController then
		local splinePos = splineController:GetPositionAtWorldX(guideAirPos.X)
		if splinePos then
			return guideAirPos.Y - splinePos.Y
		end
	end
	return 0
end

function BallController:GetGuideVelocity()
	return guideVelocity
end

function BallController:SetCameraOffset(offset)
	CONFIG.CameraOffset = offset
end

function BallController:SetGuideLookAhead(lookAhead)
	CONFIG.GuideLookAhead = lookAhead
end

return BallController
