--[[
	ArrowBowController
	
	Handles client-side bow aiming and power charging.
	- RMB hold to charge power
	- Mouse position controls bow pitch (up/down aim)
	- Disables player movement when on platform
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local Knit = require(Packages.Knit)

local CustomPackages = ReplicatedStorage:WaitForChild("CustomPackages")
local Fusion = require(CustomPackages.FusionRoot.Fusion)

-- Fusion imports
local New = Fusion.New
local Value = Fusion.Value
local Computed = Fusion.Computed
local Spring = Fusion.Spring
local Children = Fusion.Children

local ArrowBowController = Knit.CreateController({
	Name = "ArrowBowController",
})

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                              CONFIGURATION                                  ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

local CONFIG = {
	-- Power Settings
	MaxPower = 100,
	PowerChargeRate = 50,     -- Power per second while holding RMB
	
	-- Aim Settings
	AimSensitivity = 0.15,    -- How much mouse Y affects pitch
	MinPitch = -45,
	MaxPitch = 60,
	
	-- UI Settings
	PowerBarWidth = 300,
	PowerBarHeight = 30,
	PowerBarPosition = UDim2.new(0.5, 0, 0.85, 0),
	
	-- Colors
	PowerBarBgColor = Color3.fromRGB(30, 30, 40),
	PowerBarLowColor = Color3.fromRGB(80, 200, 100),     -- Green
	PowerBarMedColor = Color3.fromRGB(255, 200, 80),     -- Yellow
	PowerBarHighColor = Color3.fromRGB(255, 80, 80),     -- Red
	PowerBarMaxColor = Color3.fromRGB(255, 50, 255),     -- Purple (max power)
}

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                              STATE                                          ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

local player = Players.LocalPlayer
local mouse = player:GetMouse()

-- Services
local ArrowBowService = nil
local ArrowPlayerPositionService = nil
local ArrowTurnService = nil
local ArrowMatchmakingService = nil

-- State
local isOnPlatform = Value(false)
local isMyTurn = Value(false)
local isAiming = Value(false)
local currentPower = Value(0)
local currentPitch = Value(0)
local isCharging = false
local movementDisabled = false

-- Connections
local aimConnection = nil
local chargeConnection = nil

-- UI
local screenGui = nil

-- Bow reference (client-side for direct manipulation)
local myBowModel = nil
local bowPartOffsets = {}
local bowBaseRotation = CFrame.Angles(0, math.rad(90), 0)
local bowPosition = nil

-- Projectile camera follow
local isFollowingProjectile = false
local projectileFollowConnection = nil
local currentProjectile = nil
local cameraFollowOffset = Vector3.new(0, 2, -15)  -- Behind and above projectile

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         MOVEMENT & CAMERA CONTROL                           ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

local originalCameraType = nil
local cameraPosition = nil

function ArrowBowController:DisableMovement()
	if movementDisabled then return end
	
	local character = player.Character
	if not character then return end
	
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.WalkSpeed = 0
		humanoid.JumpPower = 0
		humanoid.JumpHeight = 0
		movementDisabled = true
		print("[ArrowBowController] Movement disabled")
	end
end

function ArrowBowController:EnableMovement()
	if not movementDisabled then return end
	
	local character = player.Character
	if not character then return end
	
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.WalkSpeed = 16
		humanoid.JumpPower = 50
		humanoid.JumpHeight = 7.2
		movementDisabled = false
		print("[ArrowBowController] Movement enabled")
	end
end

local originalFOV = nil

function ArrowBowController:SetupScriptableCamera()
	local camera = workspace.CurrentCamera
	if not camera then return end
	
	-- Store original camera type and FOV
	originalCameraType = camera.CameraType
	originalFOV = camera.FieldOfView
	
	-- Set to scriptable so it doesn't orbit
	camera.CameraType = Enum.CameraType.Scriptable
	camera.FieldOfView = 100
	
	-- Get player position and set camera to the side (side-view)
	local character = player.Character
	if character then
		local rootPart = character:FindFirstChild("HumanoidRootPart")
		if rootPart then
			-- Ensure player faces left (-X direction)
			rootPart.CFrame = CFrame.new(rootPart.Position) * CFrame.Angles(0, math.rad(90), 0)
			
			-- Position camera to the side (on -Z axis), looking at player
			-- Player is centered in view
			local playerPos = rootPart.Position
			local cameraOffset = Vector3.new(0, 0, -25) -- Side view (negative Z)
			
			cameraPosition = playerPos + cameraOffset
			
			-- Look directly at player (centered)
			camera.CFrame = CFrame.lookAt(cameraPosition, playerPos)
		end
	end
	
	print("[ArrowBowController] Camera set to Scriptable (side view)")
end

function ArrowBowController:RestoreCamera()
	local camera = workspace.CurrentCamera
	if not camera then return end
	
	-- Restore original camera type
	if originalCameraType then
		camera.CameraType = originalCameraType
		originalCameraType = nil
	else
		camera.CameraType = Enum.CameraType.Custom
	end
	
	-- Restore original FOV
	if originalFOV then
		camera.FieldOfView = originalFOV
		originalFOV = nil
	else
		camera.FieldOfView = 70  -- Default FOV
	end
	
	print("[ArrowBowController] Camera restored")
end

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                      PROJECTILE CAMERA FOLLOW                               ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

function ArrowBowController:StartFollowingProjectile()
	if isFollowingProjectile then return end
	
	local camera = workspace.CurrentCamera
	if not camera then return end
	
	isFollowingProjectile = true
	print("[ArrowBowController] Starting to follow projectile...")
	
	-- Follow the projectile each frame (from the side, same as player view)
	projectileFollowConnection = RunService.RenderStepped:Connect(function()
		-- Find projectile if we don't have one yet
		if not currentProjectile or not currentProjectile.Parent then
			local projectilesFolder = workspace:FindFirstChild("ArrowProjectiles")
			if projectilesFolder then
				for _, child in ipairs(projectilesFolder:GetChildren()) do
					if child:IsA("BasePart") and child.Name == "ArrowProjectile" then
						currentProjectile = child
						print("[ArrowBowController] Found projectile to follow!")
						break
					end
				end
			end
		end
		
		-- If we still don't have a projectile, keep trying
		if not currentProjectile or not currentProjectile.Parent then
			return
		end
		
		-- Position camera to the side of the projectile (on -Z axis, same side view as player)
		local projectilePos = currentProjectile.Position
		
		-- Camera stays on the -Z side, following projectile's X and Y
		local cameraPos = Vector3.new(projectilePos.X, projectilePos.Y, projectilePos.Z - 25)
		
		-- Look at the projectile
		camera.CFrame = CFrame.lookAt(cameraPos, projectilePos)
	end)
end

function ArrowBowController:StopFollowingProjectile()
	if not isFollowingProjectile then return end
	
	print("[ArrowBowController] Stopping projectile follow...")
	
	isFollowingProjectile = false
	currentProjectile = nil
	
	if projectileFollowConnection then
		projectileFollowConnection:Disconnect()
		projectileFollowConnection = nil
	end
	
	-- Return to player view
	task.wait(0.1)  -- Small delay before returning
	if isOnPlatform:get() then
		self:SetupScriptableCamera()
	end
	
	print("[ArrowBowController] Returned to player view")
end

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         AIMING SYSTEM                                       ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

-- Find and cache the player's arrow for direct client-side manipulation
function ArrowBowController:FindMyBow()
	local bowsFolder = workspace:FindFirstChild("ArrowBows")
	if not bowsFolder then 
		print("[ArrowBowController] No ArrowBows folder found")
		return nil 
	end
	
	local bowName = player.Name .. "_Bow"
	myBowModel = bowsFolder:FindFirstChild(bowName)
	
	if not myBowModel then
		print("[ArrowBowController] Arrow not found:", bowName)
		return nil
	end
	
	-- Find the arrow part
	local arrowPart = myBowModel:FindFirstChild("ArrowPart")
	if arrowPart then
		bowPosition = arrowPart.Position
		print("[ArrowBowController] Found simple arrow at", bowPosition)
	end
	
	return myBowModel
end

-- Get the 3D world position where the mouse is pointing
function ArrowBowController:GetMouseWorldPosition()
	local camera = workspace.CurrentCamera
	if not camera then return nil end
	
	-- Create a ray from the mouse position
	local mouseLocation = UserInputService:GetMouseLocation()
	local ray = camera:ViewportPointToRay(mouseLocation.X, mouseLocation.Y)
	
	-- Raycast to find where the mouse is pointing
	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	raycastParams.FilterDescendantsInstances = {player.Character, myBowModel}
	
	local result = workspace:Raycast(ray.Origin, ray.Direction * 1000, raycastParams)
	
	if result then
		return result.Position
	else
		-- If no hit, project far in that direction
		return ray.Origin + ray.Direction * 500
	end
end

-- Update arrow rotation to point at mouse target (2D rotation like a clock hand)
function ArrowBowController:UpdateBowRotation()
	if not myBowModel or not bowPosition then return end
	
	-- Find the arrow part
	local arrowPart = myBowModel:FindFirstChild("ArrowPart")
	if not arrowPart then return end
	
	-- Get camera and mouse info
	local camera = workspace.CurrentCamera
	if not camera then return end
	
	-- Get mouse screen position
	local mouseLocation = UserInputService:GetMouseLocation()
	
	-- Create a ray from camera through mouse position
	local ray = camera:ViewportPointToRay(mouseLocation.X, mouseLocation.Y)
	
	-- Project the ray onto the plane at the arrow's Z position (X-Y plane)
	-- This gives us the 2D mouse position in world space at the same Z as the arrow
	local arrowZ = bowPosition.Z
	
	-- Calculate where the ray intersects the Z plane
	-- Ray: P = Origin + t * Direction
	-- Plane: Z = arrowZ
	-- Solve for t: Origin.Z + t * Direction.Z = arrowZ
	if math.abs(ray.Direction.Z) > 0.001 then
		local t = (arrowZ - ray.Origin.Z) / ray.Direction.Z
		local mouseWorldPos = ray.Origin + ray.Direction * t
		
		-- Calculate direction from arrow to mouse (in X-Y plane)
		local dx = mouseWorldPos.X - bowPosition.X
		local dy = mouseWorldPos.Y - bowPosition.Y
		
		-- Calculate angle in the X-Y plane (2D rotation)
		local angle = math.atan2(dy, dx)
		
		-- Arrow part's length is along local Z (5 studs)
		-- Pivot should be at the tail end, so offset by half the length
		local arrowLength = arrowPart.Size.Z
		local pivotOffset = arrowLength / 2
		
		-- First rotate Y by 90 to make local +Z point to world -X (left)
		-- Then rotate around local X for the clock-hand motion (negative to follow mouse correctly)
		-- Then offset along local Z so the tail is at the pivot point
		local newCFrame = CFrame.new(bowPosition) 
			* CFrame.Angles(0, math.rad(90), 0)   -- Point arrow along -X (left)
			* CFrame.Angles(-angle, 0, 0)          -- Rotate around local X (inverted to follow mouse)
			* CFrame.new(0, 0, pivotOffset)        -- Offset so tail is at pivot
		
		arrowPart.CFrame = newCFrame
		
		-- Store the angle for UI display (convert to degrees)
		currentPitch:set(math.deg(angle))
	end
end

function ArrowBowController:StartAiming()
	if aimConnection then return end
	
	isAiming:set(true)
	
	-- Find the bow model for direct manipulation
	task.spawn(function()
		-- Try to find bow multiple times in case it's not created yet
		for i = 1, 10 do
			if self:FindMyBow() then
				break
			end
			task.wait(0.2)
		end
	end)
	
	-- Don't lock mouse - let it move freely for aiming
	UserInputService.MouseBehavior = Enum.MouseBehavior.Default
	
	aimConnection = RunService.RenderStepped:Connect(function(deltaTime)
		if not isOnPlatform:get() then return end
		
		-- Update bow to point at mouse position (full 360 degree tracking)
		self:UpdateBowRotation()
	end)
	
	print("[ArrowBowController] Started aiming - bow follows mouse")
end

function ArrowBowController:StopAiming()
	if aimConnection then
		aimConnection:Disconnect()
		aimConnection = nil
	end
	
	isAiming:set(false)
	UserInputService.MouseBehavior = Enum.MouseBehavior.Default
	
	print("[ArrowBowController] Stopped aiming")
end

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         POWER CHARGING                                      ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

function ArrowBowController:StartCharging()
	if isCharging then return end
	isCharging = true
	currentPower:set(0)
	
	chargeConnection = RunService.RenderStepped:Connect(function(deltaTime)
		if not isCharging then return end
		
		local power = currentPower:get()
		power = math.min(CONFIG.MaxPower, power + CONFIG.PowerChargeRate * deltaTime)
		currentPower:set(power)
	end)
	
	print("[ArrowBowController] Started charging")
end

function ArrowBowController:StopCharging()
	if not isCharging then return end
	isCharging = false
	
	if chargeConnection then
		chargeConnection:Disconnect()
		chargeConnection = nil
	end
	
	-- Fire arrow with current power
	local power = currentPower:get()
	
	-- Check if it's our turn (if turn service exists)
	local canFire = true
	if ArrowTurnService then
		canFire = ArrowTurnService:IsMyTurn()
		if not canFire then
			print("[ArrowBowController] Not your turn! Cannot fire.")
			currentPower:set(0)
			return
		end
	end
	
	if power > 5 and bowPosition then
		-- Get the arrow part to determine direction
		local arrowPart = myBowModel and myBowModel:FindFirstChild("ArrowPart")
		if arrowPart then
			-- Arrow direction is along its local -Z axis (front of the part)
			local direction = arrowPart.CFrame.LookVector
			local origin = bowPosition
			
			-- Notify turn service that we fired
			if ArrowTurnService then
				ArrowTurnService:NotifyFired()
				isMyTurn:set(false)
			end
			
			-- Fire projectile through server
			-- Pass as simple values to avoid cyclic table issues
			local ArrowProjectileService = Knit.GetService("ArrowProjectileService")
			if ArrowProjectileService then
				ArrowProjectileService:FireArrow(
					Vector3.new(origin.X, origin.Y, origin.Z),
					Vector3.new(direction.X, direction.Y, direction.Z),
					power
				)
				print(string.format("[ArrowBowController] Fired arrow! Power: %.1f, Direction: %s", power, tostring(direction)))
				
				-- Start following the projectile with camera
				task.spawn(function()
					self:StartFollowingProjectile()
					
					-- Timeout: stop following after 5 seconds max
					task.delay(5, function()
						if isFollowingProjectile then
							print("[ArrowBowController] Projectile follow timeout")
							self:StopFollowingProjectile()
						end
					end)
				end)
			end
		end
	end
	
	-- Reset power
	currentPower:set(0)
	
	print("[ArrowBowController] Stopped charging")
end

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         UI CREATION                                         ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

function ArrowBowController:CreatePowerBarUI()
	-- Computed power color based on charge level
	local powerColor = Computed(function()
		local power = currentPower:get()
		local ratio = power / CONFIG.MaxPower
		
		if ratio >= 1 then
			return CONFIG.PowerBarMaxColor
		elseif ratio > 0.7 then
			-- Lerp from yellow to red
			local t = (ratio - 0.7) / 0.3
			return CONFIG.PowerBarMedColor:Lerp(CONFIG.PowerBarHighColor, t)
		elseif ratio > 0.3 then
			-- Lerp from green to yellow
			local t = (ratio - 0.3) / 0.4
			return CONFIG.PowerBarLowColor:Lerp(CONFIG.PowerBarMedColor, t)
		else
			return CONFIG.PowerBarLowColor
		end
	end)
	
	local powerFraction = Computed(function()
		return currentPower:get() / CONFIG.MaxPower
	end)
	
	local uiVisibility = Computed(function()
		return if isOnPlatform:get() then 1 else 0
	end)
	
	local springVisibility = Spring(uiVisibility, 20, 0.8)
	local springColor = Spring(powerColor, 15, 0.7)
	local springPower = Spring(powerFraction, 25, 0.6)
	
	-- Power text
	local powerText = Computed(function()
		return string.format("%.0f%%", currentPower:get())
	end)
	
	-- Pitch indicator text
	local pitchText = Computed(function()
		return string.format("Aim: %.0f°", currentPitch:get())
	end)
	
	screenGui = New "ScreenGui" {
		Name = "ArrowBowGui",
		Parent = player:WaitForChild("PlayerGui"),
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		
		[Children] = {
			-- Power Bar Container
			New "Frame" {
				Name = "PowerBarContainer",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = CONFIG.PowerBarPosition,
				Size = UDim2.new(0, CONFIG.PowerBarWidth, 0, CONFIG.PowerBarHeight + 40),
				BackgroundTransparency = 1,
				
				[Children] = {
					-- "POWER" Label
					New "TextLabel" {
						Name = "PowerLabel",
						AnchorPoint = Vector2.new(0.5, 1),
						Position = UDim2.new(0.5, 0, 0, -5),
						Size = UDim2.new(1, 0, 0, 20),
						BackgroundTransparency = 1,
						Text = "POWER",
						TextColor3 = Color3.fromRGB(200, 200, 210),
						TextTransparency = Computed(function()
							return 1 - springVisibility:get()
						end),
						FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Bold),
						TextSize = 16,
					},
					
					-- Power Bar Background
					New "Frame" {
						Name = "PowerBarBG",
						AnchorPoint = Vector2.new(0.5, 0),
						Position = UDim2.new(0.5, 0, 0, 20),
						Size = UDim2.new(1, 0, 0, CONFIG.PowerBarHeight),
						BackgroundColor3 = CONFIG.PowerBarBgColor,
						BackgroundTransparency = Computed(function()
							return 0.3 + (1 - springVisibility:get()) * 0.7
						end),
						
						[Children] = {
							New "UICorner" {
								CornerRadius = UDim.new(0, 8),
							},
							
							New "UIStroke" {
								Color = springColor,
								Thickness = 2,
								Transparency = Computed(function()
									return 0.3 + (1 - springVisibility:get()) * 0.7
								end),
							},
							
							-- Power Fill
							New "Frame" {
								Name = "PowerFill",
								Size = Computed(function()
									return UDim2.new(springPower:get(), 0, 1, 0)
								end),
								BackgroundColor3 = springColor,
								BackgroundTransparency = Computed(function()
									return 0.1 + (1 - springVisibility:get()) * 0.9
								end),
								
								[Children] = {
									New "UICorner" {
										CornerRadius = UDim.new(0, 8),
									},
									
									-- Gradient for depth
									New "UIGradient" {
										Color = ColorSequence.new({
											ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
											ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 255, 255)),
											ColorSequenceKeypoint.new(1, Color3.fromRGB(180, 180, 180)),
										}),
										Rotation = 90,
										Transparency = NumberSequence.new(0.7),
									},
								},
							},
							
							-- Power percentage text
							New "TextLabel" {
								Name = "PowerText",
								AnchorPoint = Vector2.new(0.5, 0.5),
								Position = UDim2.new(0.5, 0, 0.5, 0),
								Size = UDim2.new(1, 0, 1, 0),
								BackgroundTransparency = 1,
								Text = powerText,
								TextColor3 = Color3.fromRGB(255, 255, 255),
								TextTransparency = Computed(function()
									return 1 - springVisibility:get()
								end),
								FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Bold),
								TextSize = 18,
								
								[Children] = {
									New "UIStroke" {
										Color = Color3.fromRGB(0, 0, 0),
										Thickness = 1.5,
										Transparency = Computed(function()
											return 0.3 + (1 - springVisibility:get()) * 0.7
										end),
									},
								},
							},
						},
					},
					
					-- Aim indicator
					New "TextLabel" {
						Name = "AimLabel",
						AnchorPoint = Vector2.new(0.5, 0),
						Position = UDim2.new(0.5, 0, 1, 5),
						Size = UDim2.new(1, 0, 0, 18),
						BackgroundTransparency = 1,
						Text = pitchText,
						TextColor3 = Color3.fromRGB(180, 180, 190),
						TextTransparency = Computed(function()
							return 0.3 + (1 - springVisibility:get()) * 0.7
						end),
						FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Medium),
						TextSize = 14,
					},
				},
			},
			
			-- Crosshair
			New "Frame" {
				Name = "Crosshair",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.new(0.5, 0, 0.5, 0),
				Size = UDim2.new(0, 40, 0, 40),
				BackgroundTransparency = 1,
				Visible = Computed(function()
					return isOnPlatform:get()
				end),
				
				[Children] = {
					-- Horizontal line
					New "Frame" {
						AnchorPoint = Vector2.new(0.5, 0.5),
						Position = UDim2.new(0.5, 0, 0.5, 0),
						Size = UDim2.new(1, 0, 0, 2),
						BackgroundColor3 = Color3.fromRGB(255, 255, 255),
						BackgroundTransparency = 0.3,
					},
					
					-- Vertical line
					New "Frame" {
						AnchorPoint = Vector2.new(0.5, 0.5),
						Position = UDim2.new(0.5, 0, 0.5, 0),
						Size = UDim2.new(0, 2, 1, 0),
						BackgroundColor3 = Color3.fromRGB(255, 255, 255),
						BackgroundTransparency = 0.3,
					},
					
					-- Center dot
					New "Frame" {
						AnchorPoint = Vector2.new(0.5, 0.5),
						Position = UDim2.new(0.5, 0, 0.5, 0),
						Size = UDim2.new(0, 6, 0, 6),
						BackgroundColor3 = springColor,
						
						[Children] = {
							New "UICorner" {
								CornerRadius = UDim.new(1, 0),
							},
						},
					},
				},
			},
			
			-- Turn Indicator
			New "TextLabel" {
				Name = "TurnIndicator",
				AnchorPoint = Vector2.new(0.5, 0),
				Position = UDim2.new(0.5, 0, 0, 50),
				Size = UDim2.new(0, 300, 0, 50),
				BackgroundTransparency = 1,
				Text = Computed(function()
					return isMyTurn:get() and "YOUR TURN - FIRE!" or "OPPONENT'S TURN"
				end),
				TextColor3 = Computed(function()
					return isMyTurn:get() and Color3.fromRGB(80, 255, 80) or Color3.fromRGB(255, 200, 80)
				end),
				TextTransparency = Computed(function()
					return 1 - springVisibility:get()
				end),
				FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Bold),
				TextSize = 28,
				Visible = Computed(function()
					return isOnPlatform:get()
				end),
				
				[Children] = {
					New "UIStroke" {
						Color = Color3.fromRGB(0, 0, 0),
						Thickness = 2,
						Transparency = Computed(function()
							return 0.3 + (1 - springVisibility:get()) * 0.7
						end),
					},
				},
			},
			
			-- Instructions
			New "TextLabel" {
				Name = "Instructions",
				AnchorPoint = Vector2.new(0.5, 1),
				Position = UDim2.new(0.5, 0, 1, -20),
				Size = UDim2.new(0, 400, 0, 30),
				BackgroundTransparency = 1,
				Text = Computed(function()
					return isMyTurn:get() and "Hold RIGHT MOUSE BUTTON to charge • Release to fire" or "Wait for your turn..."
				end),
				TextColor3 = Color3.fromRGB(200, 200, 210),
				TextTransparency = Computed(function()
					return 0.4 + (1 - springVisibility:get()) * 0.6
				end),
				FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Medium),
				TextSize = 14,
				Visible = Computed(function()
					return isOnPlatform:get()
				end),
			},
		},
	}
	
	print("[ArrowBowController] ✓ Power bar UI created")
	return screenGui
end

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         INPUT HANDLING                                      ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

function ArrowBowController:SetupInputHandling()
	-- Right mouse button handling
	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed then return end
		if not isOnPlatform:get() then return end
		
		if input.UserInputType == Enum.UserInputType.MouseButton2 then
			self:StartCharging()
		end
	end)
	
	UserInputService.InputEnded:Connect(function(input, gameProcessed)
		if input.UserInputType == Enum.UserInputType.MouseButton2 then
			self:StopCharging()
		end
	end)
end

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         PUBLIC API                                          ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

function ArrowBowController:SetOnPlatform(value: boolean)
	isOnPlatform:set(value)
	
	if value then
		self:DisableMovement()
		self:SetupScriptableCamera()
		self:StartAiming()
	else
		self:EnableMovement()
		self:RestoreCamera()
		self:StopAiming()
	end
end

function ArrowBowController:GetPower()
	return currentPower:get()
end

function ArrowBowController:GetPitch()
	return currentPitch:get()
end

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         KNIT LIFECYCLE                                      ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

function ArrowBowController:KnitInit()
	print("[ArrowBowController] Initializing...")
end

function ArrowBowController:KnitStart()
	print("[ArrowBowController] Starting...")
	
	-- Get services
	ArrowBowService = Knit.GetService("ArrowBowService")
	ArrowPlayerPositionService = Knit.GetService("ArrowPlayerPositionService")
	ArrowTurnService = Knit.GetService("ArrowTurnService")
	ArrowMatchmakingService = Knit.GetService("ArrowMatchmakingService")
	
	-- Create UI
	self:CreatePowerBarUI()
	
	-- Setup input
	self:SetupInputHandling()
	
	-- Listen for when player is positioned on platform
	ArrowPlayerPositionService.PlayerPositioned:Connect(function(positionedPlayer, position)
		if positionedPlayer == player then
			print("[ArrowBowController] Player positioned on platform!")
			-- Start immediately - bow follows mouse right away
			self:SetOnPlatform(true)
		end
	end)
	
	-- Listen for matchmaking - when matched, set on platform
	if ArrowMatchmakingService then
		ArrowMatchmakingService.MatchFound:Connect(function(opponent, side)
			print(string.format("[ArrowBowController] Match found! Opponent: %s, Side: %s", opponent.Name, side))
			task.wait(1)  -- Wait for teleport
			self:SetOnPlatform(true)
		end)
	end
	
	-- Listen for turn changes
	if ArrowTurnService then
		ArrowTurnService.YourTurn:Connect(function(turnNumber)
			print(string.format("[ArrowBowController] YOUR TURN! (Turn %d)", turnNumber))
			isMyTurn:set(true)
		end)
		
		ArrowTurnService.OpponentTurn:Connect(function(opponent, turnNumber)
			print(string.format("[ArrowBowController] %s's turn (Turn %d)", opponent.Name, turnNumber))
			isMyTurn:set(false)
		end)
		
		ArrowTurnService.TurnResult:Connect(function(shooter, didHit, target)
			if didHit and target then
				print(string.format("[ArrowBowController] %s HIT %s!", shooter.Name, target.Name))
			else
				print(string.format("[ArrowBowController] %s missed!", shooter.Name))
			end
		end)
		
		ArrowTurnService.MatchEnded:Connect(function(winner, loser)
			if winner == player then
				print("[ArrowBowController] YOU WIN!")
			elseif loser == player then
				print("[ArrowBowController] You lost...")
			else
				print("[ArrowBowController] Match ended in a draw!")
			end
			
			-- Reset state
			task.delay(3, function()
				self:SetOnPlatform(false)
				isMyTurn:set(false)
			end)
		end)
	end
	
	-- Listen for bow creation
	ArrowBowService.BowCreated:Connect(function(bowPlayer, position)
		if bowPlayer == player then
			print("[ArrowBowController] Bow created for player!")
		end
	end)
	
	-- Listen for projectile hits to return camera to player
	local ArrowProjectileService = Knit.GetService("ArrowProjectileService")
	if ArrowProjectileService then
		ArrowProjectileService.ProjectileHit:Connect(function(firingPlayer, hitPosition, hitPartName)
			if firingPlayer == player and isFollowingProjectile then
				-- Small delay to see the impact
				task.delay(0.5, function()
					self:StopFollowingProjectile()
				end)
			end
		end)
	end
	
	print("[ArrowBowController] Ready")
end

return ArrowBowController

