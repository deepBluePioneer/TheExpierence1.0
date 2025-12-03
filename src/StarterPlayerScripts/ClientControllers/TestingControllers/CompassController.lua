local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local Knit = require(Packages.Knit)

local CompassController = Knit.CreateController {
	Name = "CompassController",
	targetPosition = nil,
	enabled = false,
}

-- === CONFIG ===
local COMPASS_CONFIG = {
	-- Arrow dimensions (for 3D model) - sleeker proportions
	ShaftLength = 2.5,
	ShaftWidth = 0.5,
	HeadLength = 1.8,
	HeadWidth = 1.4,
	Thickness = 0.25,
	
	-- Default color scheme (Pure Yellow)
	ColorSchemes = {
		-- Pure Yellow - Default
		Default = {
			Primary = Color3.fromRGB(255, 255, 0),      -- Pure bright yellow
			Secondary = Color3.fromRGB(220, 200, 0),    -- Slightly darker yellow
			Glow = Color3.fromRGB(255, 255, 50),        -- Bright yellow glow
			Accent = Color3.fromRGB(255, 255, 150),     -- Light yellow highlight
		},
		Danger = {
			Primary = Color3.fromRGB(220, 60, 60),
			Secondary = Color3.fromRGB(150, 40, 40),
			Glow = Color3.fromRGB(255, 100, 100),
			Accent = Color3.fromRGB(255, 150, 150),
		},
		Objective = {
			Primary = Color3.fromRGB(60, 180, 220),
			Secondary = Color3.fromRGB(40, 120, 160),
			Glow = Color3.fromRGB(100, 200, 255),
			Accent = Color3.fromRGB(180, 230, 255),
		},
		Warning = {
			Primary = Color3.fromRGB(255, 160, 40),
			Secondary = Color3.fromRGB(200, 120, 20),
			Glow = Color3.fromRGB(255, 200, 80),
			Accent = Color3.fromRGB(255, 230, 150),
		},
		Safe = {
			Primary = Color3.fromRGB(60, 200, 100),
			Secondary = Color3.fromRGB(40, 150, 70),
			Glow = Color3.fromRGB(100, 255, 150),
			Accent = Color3.fromRGB(180, 255, 200),
		},
	},
	
	Material = Enum.Material.SmoothPlastic,
	GlowMaterial = Enum.Material.Neon,
	
	-- Above-head positioning
	HeightAboveHead = 3,        -- Studs above player's head
	ArrowScale = 0.6,           -- Slightly larger for visibility
	
	-- Animation
	RotationSmoothing = 0.12,   -- Smoother rotation
	BobEnabled = true,          -- Gentle bobbing motion
	BobSpeed = 1.5,
	BobAmount = 0.2,
	
	-- Distance display
	ShowDistance = true,
	DistanceUnits = "m",
}

-- === HELPERS ===

local function createPart(name, size, cframe, color, material, parent)
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = cframe
	part.Color = color
	part.Material = material
	part.Anchored = true
	part.CanCollide = false
	part.Parent = parent
	return part
end

local function createWedge(name, size, cframe, color, material, parent)
	local wedge = Instance.new("WedgePart")
	wedge.Name = name
	wedge.Size = size
	wedge.CFrame = cframe
	wedge.Color = color
	wedge.Material = material
	wedge.Anchored = true
	wedge.CanCollide = false
	wedge.Parent = parent
	return wedge
end

-- === ARROW MODEL CREATION (V/Chevron Shape) ===

local function createArrowModel(colorScheme)
	local config = COMPASS_CONFIG
	colorScheme = colorScheme or config.ColorSchemes.Default  -- Yellow by default
	
	local arrowModel = Instance.new("Model")
	arrowModel.Name = "CompassArrowModel"
	
	local position = Vector3.new(0, 0, 0)
	
	-- V-shape dimensions
	local vWidth = config.HeadWidth * 1.8      -- Total width of the V
	local vLength = config.HeadLength * 1.5    -- How far forward the point extends
	local vThickness = config.Thickness * 1.2  -- Thickness of the arms
	local armWidth = config.ShaftWidth * 0.8   -- Width of each arm
	
	-- Center point (invisible, for positioning)
	local centerPart = createPart(
		"Center",
		Vector3.new(0.1, 0.1, 0.1),
		CFrame.new(position),
		colorScheme.Primary,
		config.Material,
		arrowModel
	)
	centerPart.Transparency = 1
	
	-- === V-SHAPE ARMS ===
	local armAngle = 35  -- Angle of each arm from center (degrees)
	
	for _, side in ipairs({-1, 1}) do
		local angle = math.rad(side * armAngle)
		
		-- Calculate arm direction
		local armDirX = math.sin(angle)
		local armDirZ = math.cos(angle)
		local armLength = vLength / math.cos(angle)
		
		-- Main arm
		local arm = createPart(
			"Arm_" .. (side == -1 and "L" or "R"),
			Vector3.new(armWidth, vThickness, armLength),
			CFrame.new(position + Vector3.new(armDirX * armLength * 0.5, 0, armDirZ * armLength * 0.5))
				* CFrame.Angles(0, -angle, 0),
			colorScheme.Primary,
			config.Material,
			arrowModel
		)
		
		-- Glow stripe on arm
		createPart(
			"ArmGlow_" .. (side == -1 and "L" or "R"),
			Vector3.new(armWidth * 0.4, vThickness + 0.03, armLength * 0.85),
			CFrame.new(position + Vector3.new(armDirX * armLength * 0.5, 0.02, armDirZ * armLength * 0.5))
				* CFrame.Angles(0, -angle, 0),
			colorScheme.Glow,
			config.GlowMaterial,
			arrowModel
		)
		
		-- Outer edge glow
		local edgeOffset = armWidth * 0.45
		createPart(
			"ArmEdge_" .. (side == -1 and "L" or "R"),
			Vector3.new(armWidth * 0.1, vThickness + 0.02, armLength),
			CFrame.new(position + Vector3.new(
				armDirX * armLength * 0.5 + math.cos(angle) * edgeOffset * side,
				0.02,
				armDirZ * armLength * 0.5 - math.sin(angle) * edgeOffset * side
			)) * CFrame.Angles(0, -angle, 0),
			colorScheme.Accent or colorScheme.Glow,
			config.GlowMaterial,
			arrowModel
		)
		
		-- Arm tip (at the back ends of the V)
		local tipX = armDirX * armLength
		local tipZ = armDirZ * armLength
		createPart(
			"ArmTip_" .. (side == -1 and "L" or "R"),
			Vector3.new(armWidth * 1.3, vThickness * 1.1, armWidth * 0.5),
			CFrame.new(position + Vector3.new(tipX, 0, tipZ))
				* CFrame.Angles(0, -angle, 0),
			colorScheme.Secondary,
			config.Material,
			arrowModel
		)
		
		-- Tip glow
		createPart(
			"TipGlow_" .. (side == -1 and "L" or "R"),
			Vector3.new(armWidth * 0.6, vThickness * 0.8, armWidth * 0.3),
			CFrame.new(position + Vector3.new(tipX, 0.02, tipZ))
				* CFrame.Angles(0, -angle, 0),
			colorScheme.Glow,
			config.GlowMaterial,
			arrowModel
		)
	end
	
	-- === CENTER POINT (the tip of the V) ===
	-- Glowing point at front
	createPart(
		"PointGlow",
		Vector3.new(armWidth * 0.6, vThickness * 1.3, armWidth * 0.6),
		CFrame.new(position + Vector3.new(0, 0.02, 0)),
		colorScheme.Glow,
		config.GlowMaterial,
		arrowModel
	)
	
	-- Bright center accent
	createPart(
		"PointAccent",
		Vector3.new(armWidth * 0.35, vThickness * 1.5, armWidth * 0.35),
		CFrame.new(position + Vector3.new(0, 0.04, 0)),
		colorScheme.Accent or colorScheme.Glow,
		config.GlowMaterial,
		arrowModel
	)
	
	-- === POINT LIGHT for visibility ===
	local light = Instance.new("PointLight")
	light.Name = "ArrowLight"
	light.Color = colorScheme.Glow
	light.Brightness = 1
	light.Range = 8
	light.Parent = centerPart
	
	arrowModel.PrimaryPart = centerPart
	
	return arrowModel
end

-- === 3D ARROW ABOVE HEAD ===

local function createCompassArrow(self)
	local config = COMPASS_CONFIG
	local player = Players.LocalPlayer
	
	-- Create the 3D arrow model that floats above player's head
	local arrowModel = createArrowModel(config.ColorSchemes.Danger)
	arrowModel.Name = "PlayerCompassArrow"
	
	-- Scale down the arrow for above-head display
	for _, part in ipairs(arrowModel:GetDescendants()) do
		if part:IsA("BasePart") then
			part.Size = part.Size * config.ArrowScale
			part.Position = part.Position * config.ArrowScale
			part.CanCollide = false
			part.CastShadow = false
		end
	end
	
	-- Parent to workspace (will be positioned each frame)
	arrowModel.Parent = workspace
	
	-- Add a BillboardGui for distance display
	local billboardGui = Instance.new("BillboardGui")
	billboardGui.Name = "DistanceBillboard"
	billboardGui.Size = UDim2.new(0, 100, 0, 30)
	billboardGui.StudsOffset = Vector3.new(0, -1.5, 0)
	billboardGui.AlwaysOnTop = true
	billboardGui.Parent = arrowModel.PrimaryPart
	
	local distanceLabel = Instance.new("TextLabel")
	distanceLabel.Name = "DistanceLabel"
	distanceLabel.Size = UDim2.new(1, 0, 1, 0)
	distanceLabel.BackgroundTransparency = 1
	distanceLabel.Font = Enum.Font.GothamBold
	distanceLabel.TextSize = 14
	distanceLabel.TextColor3 = Color3.fromRGB(220, 220, 220)
	distanceLabel.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	distanceLabel.TextStrokeTransparency = 0.3
	distanceLabel.Text = ""
	distanceLabel.Parent = billboardGui
	
	-- Store references
	self.arrowModel = arrowModel
	self.distanceLabel = distanceLabel
	
	-- Initially hidden
	arrowModel.Parent = nil
	
	return arrowModel
end

-- === UPDATE LOOP ===

local function getDirectionToTarget(self)
	local player = Players.LocalPlayer
	local character = player.Character
	if not character then return nil, nil, 0 end
	
	local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")
	if not humanoidRootPart then return nil, nil, 0 end
	
	local targetPos = self.targetPosition
	if not targetPos then return nil, nil, 0 end
	
	-- Get direction on XZ plane (ignore Y for compass)
	local playerPos = humanoidRootPart.Position
	local direction = (targetPos - playerPos) * Vector3.new(1, 0, 1)
	
	local distance = (targetPos - playerPos).Magnitude
	
	if direction.Magnitude < 0.1 then
		return nil, nil, distance
	end
	
	-- Normalize direction
	local normalizedDir = direction.Unit
	
	return normalizedDir, targetPos, distance
end

local function updateCompass(self, deltaTime)
	if not self.enabled or not self.arrowModel then return end
	if not self.targetPosition then return end
	
	local config = COMPASS_CONFIG
	local player = Players.LocalPlayer
	local character = player.Character
	if not character then return end
	
	local head = character:FindFirstChild("Head")
	if not head then return end
	
	local direction, targetPos, distance = getDirectionToTarget(self)
	if not direction then return end
	
	-- Calculate position above player's head
	local headPos = head.Position
	local bobOffset = 0
	if config.BobEnabled then
		bobOffset = math.sin(tick() * config.BobSpeed * math.pi) * config.BobAmount
	end
	
	local arrowPos = headPos + Vector3.new(0, config.HeightAboveHead + bobOffset, 0)
	
	-- Position and rotate arrow model
	local arrowModel = self.arrowModel
	if arrowModel and arrowModel.PrimaryPart then
		-- Calculate Y-axis rotation only (horizontal plane)
		-- atan2 gives us the angle from +Z axis to the direction vector
		local targetAngle = math.atan2(direction.X, direction.Z)
		
		-- Smooth the rotation
		self.currentAngle = self.currentAngle or targetAngle
		local angleDiff = targetAngle - self.currentAngle
		
		-- Normalize angle difference to [-pi, pi] for shortest rotation path
		while angleDiff > math.pi do angleDiff = angleDiff - math.pi * 2 end
		while angleDiff < -math.pi do angleDiff = angleDiff + math.pi * 2 end
		
		self.currentAngle = self.currentAngle + angleDiff * config.RotationSmoothing
		
		-- Create CFrame: position + Y-axis rotation only (flat, no tilt)
		local targetCFrame = CFrame.new(arrowPos) * CFrame.Angles(0, self.currentAngle, 0)
		
		arrowModel:SetPrimaryPartCFrame(targetCFrame)
	end
	
	-- Update distance label
	if config.ShowDistance and self.distanceLabel then
		local displayDistance = math.floor(distance)
		self.distanceLabel.Text = displayDistance .. " " .. config.DistanceUnits
	end
end

-- === TEST TARGET CREATION ===

local function createTestTarget(position)
	-- Clean up existing test target
	local existing = workspace:FindFirstChild("CompassTestTarget")
	if existing then existing:Destroy() end
	
	local targetModel = Instance.new("Model")
	targetModel.Name = "CompassTestTarget"
	targetModel.Parent = workspace
	
	-- Main beacon pillar
	local pillar = Instance.new("Part")
	pillar.Name = "Pillar"
	pillar.Size = Vector3.new(2, 8, 2)
	pillar.Position = position + Vector3.new(0, 4, 0)
	pillar.Color = Color3.fromRGB(220, 60, 60)
	pillar.Material = Enum.Material.Neon
	pillar.Anchored = true
	pillar.CanCollide = false
	pillar.Parent = targetModel
	
	-- Glowing orb on top
	local orb = Instance.new("Part")
	orb.Name = "Orb"
	orb.Shape = Enum.PartType.Ball
	orb.Size = Vector3.new(3, 3, 3)
	orb.Position = position + Vector3.new(0, 9.5, 0)
	orb.Color = Color3.fromRGB(255, 100, 100)
	orb.Material = Enum.Material.Neon
	orb.Anchored = true
	orb.CanCollide = false
	orb.Parent = targetModel
	
	-- Point light for visibility
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 100, 100)
	light.Brightness = 2
	light.Range = 30
	light.Parent = orb
	
	-- Base ring
	local ring = Instance.new("Part")
	ring.Name = "BaseRing"
	ring.Shape = Enum.PartType.Cylinder
	ring.Size = Vector3.new(0.5, 6, 6)
	ring.CFrame = CFrame.new(position + Vector3.new(0, 0.25, 0)) * CFrame.Angles(0, 0, math.rad(90))
	ring.Color = Color3.fromRGB(180, 50, 50)
	ring.Material = Enum.Material.Neon
	ring.Anchored = true
	ring.CanCollide = false
	ring.Parent = targetModel
	
	-- Rotating indicator rings
	for i = 1, 3 do
		local indicator = Instance.new("Part")
		indicator.Name = "Indicator_" .. i
		indicator.Shape = Enum.PartType.Cylinder
		indicator.Size = Vector3.new(0.3, 4 - i * 0.5, 4 - i * 0.5)
		indicator.CFrame = CFrame.new(position + Vector3.new(0, 2 + i * 2, 0)) * CFrame.Angles(0, 0, math.rad(90))
		indicator.Color = Color3.fromRGB(255, 80, 80)
		indicator.Material = Enum.Material.Neon
		indicator.Transparency = 0.3
		indicator.Anchored = true
		indicator.CanCollide = false
		indicator.Parent = targetModel
	end
	
	-- Billboard label
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "TargetLabel"
	billboard.Size = UDim2.new(0, 120, 0, 40)
	billboard.StudsOffset = Vector3.new(0, 6, 0)
	billboard.AlwaysOnTop = true
	billboard.Parent = orb
	
	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 1, 0)
	label.BackgroundColor3 = Color3.fromRGB(30, 30, 35)
	label.BackgroundTransparency = 0.3
	label.Font = Enum.Font.GothamBold
	label.TextSize = 16
	label.TextColor3 = Color3.fromRGB(255, 100, 100)
	label.Text = "TARGET"
	label.Parent = billboard
	
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = label
	
	targetModel.PrimaryPart = pillar
	
	return targetModel, position
end

-- === KNIT LIFECYCLE ===

function CompassController:KnitInit()
	self.currentAngle = 0
	self.targetPosition = nil
	self.enabled = false
	self.arrowModel = nil
	self.distanceLabel = nil
	self.testTarget = nil
end

function CompassController:KnitStart()
	-- Create 3D arrow
	createCompassArrow(self)
	
	-- Handle character respawn
	local player = Players.LocalPlayer
	player.CharacterAdded:Connect(function()
		-- Re-show arrow if it was enabled
		if self.enabled and self.targetPosition then
			task.wait(0.5)  -- Wait for character to load
			self:Show()
		end
	end)
	
	-- Update loop
	RunService.RenderStepped:Connect(function(deltaTime)
		updateCompass(self, deltaTime)
	end)
	
	print("[CompassController] Initialized")
	
	-- === AUTO-START TEST MODE (remove in production) ===
	task.delay(2, function()
		self:StartTestMode()
	end)
end

-- === PUBLIC METHODS ===

function CompassController:SetTarget(position)
	if typeof(position) == "Vector3" then
		self.targetPosition = position
	elseif typeof(position) == "Instance" and position:IsA("BasePart") then
		-- If given a part, track it
		self.targetPosition = position.Position
		-- Could add continuous tracking here
	elseif position == nil then
		self.targetPosition = nil
	end
end

function CompassController:SetTargetPart(part)
	-- Track a part's position continuously
	if self.targetPartConnection then
		self.targetPartConnection:Disconnect()
	end
	
	if part and part:IsA("BasePart") then
		self.targetPosition = part.Position
		self.targetPartConnection = RunService.Heartbeat:Connect(function()
			if part and part.Parent then
				self.targetPosition = part.Position
			else
				self:ClearTarget()
			end
		end)
	end
end

function CompassController:ClearTarget()
	self.targetPosition = nil
	if self.targetPartConnection then
		self.targetPartConnection:Disconnect()
		self.targetPartConnection = nil
	end
end

function CompassController:Show()
	self.enabled = true
	if self.arrowModel then
		self.arrowModel.Parent = workspace
	end
end

function CompassController:Hide()
	self.enabled = false
	if self.arrowModel then
		self.arrowModel.Parent = nil
	end
end

function CompassController:Toggle()
	if self.enabled then
		self:Hide()
	else
		self:Show()
	end
end

function CompassController:SetColorScheme(schemeName)
	local config = COMPASS_CONFIG
	local scheme = config.ColorSchemes[schemeName]
	
	if not scheme then
		warn("[CompassController] Unknown color scheme:", schemeName)
		return
	end
	
	if self.arrowModel then
		for _, part in ipairs(self.arrowModel:GetDescendants()) do
			if part:IsA("BasePart") then
				local name = part.Name
				-- Glow parts (neon material)
				if name:find("Glow") then
					part.Color = scheme.Glow
				-- Accent parts (bright highlights, tips)
				elseif name:find("Tip") or name:find("Edge") then
					part.Color = scheme.Accent or scheme.Glow
				-- Secondary parts (tail, darker accents)
				elseif name:find("Tail") or name:find("Cap") or name:find("Secondary") then
					part.Color = scheme.Secondary
				-- Primary parts (main body)
				else
					part.Color = scheme.Primary
				end
			elseif part:IsA("PointLight") then
				part.Color = scheme.Glow
			end
		end
	end
end

function CompassController:SetHeightAboveHead(height)
	COMPASS_CONFIG.HeightAboveHead = height
end

function CompassController:SetScale(scale)
	-- Rescale the arrow model
	if self.arrowModel then
		local oldScale = COMPASS_CONFIG.ArrowScale
		local scaleFactor = scale / oldScale
		
		for _, part in ipairs(self.arrowModel:GetDescendants()) do
			if part:IsA("BasePart") then
				part.Size = part.Size * scaleFactor
			end
		end
		
		COMPASS_CONFIG.ArrowScale = scale
	end
end

-- === TEST MODE ===

function CompassController:StartTestMode(targetPosition)
	-- Create a test target at specified position or random position
	local player = Players.LocalPlayer
	local character = player.Character
	
	if not targetPosition then
		-- Default: place target 50-100 studs away in a random direction
		local spawnPos = Vector3.new(0, 0, 0)
		if character and character:FindFirstChild("HumanoidRootPart") then
			spawnPos = character.HumanoidRootPart.Position
		end
		
		local angle = math.random() * math.pi * 2
		local distance = 50 + math.random() * 50
		targetPosition = spawnPos + Vector3.new(
			math.cos(angle) * distance,
			0,
			math.sin(angle) * distance
		)
	end
	
	-- Ensure target is on the ground (Y = baseplate level or 0)
	local baseplate = workspace:FindFirstChild("Baseplate")
	local groundY = 0
	if baseplate and baseplate:IsA("BasePart") then
		groundY = baseplate.Position.Y + baseplate.Size.Y / 2
	end
	targetPosition = Vector3.new(targetPosition.X, groundY, targetPosition.Z)
	
	-- Create the visual test target
	self.testTarget = createTestTarget(targetPosition)
	
	-- Set the compass to track it
	self:SetTarget(targetPosition)
	self:Show()
	
	print("[CompassController] Test mode started - Target at:", targetPosition)
end

function CompassController:StopTestMode()
	-- Remove test target
	if self.testTarget then
		self.testTarget:Destroy()
		self.testTarget = nil
	end
	
	local existing = workspace:FindFirstChild("CompassTestTarget")
	if existing then existing:Destroy() end
	
	-- Clear compass
	self:ClearTarget()
	self:Hide()
	
	print("[CompassController] Test mode stopped")
end

function CompassController:MoveTestTarget(newPosition)
	-- Move the test target to a new position
	if self.testTarget and self.testTarget.PrimaryPart then
		local baseplate = workspace:FindFirstChild("Baseplate")
		local groundY = 0
		if baseplate and baseplate:IsA("BasePart") then
			groundY = baseplate.Position.Y + baseplate.Size.Y / 2
		end
		
		newPosition = Vector3.new(newPosition.X, groundY, newPosition.Z)
		
		-- Move all parts relative to primary part
		local offset = newPosition - self.testTarget.PrimaryPart.Position + Vector3.new(0, 4, 0)
		for _, part in ipairs(self.testTarget:GetDescendants()) do
			if part:IsA("BasePart") then
				part.Position = part.Position + offset
			end
		end
		
		-- Update compass target
		self:SetTarget(newPosition)
		
		print("[CompassController] Test target moved to:", newPosition)
	end
end

function CompassController:RandomizeTestTarget()
	-- Move test target to a new random position
	local player = Players.LocalPlayer
	local character = player.Character
	
	if character and character:FindFirstChild("HumanoidRootPart") then
		local spawnPos = character.HumanoidRootPart.Position
		local angle = math.random() * math.pi * 2
		local distance = 50 + math.random() * 100
		local newPos = spawnPos + Vector3.new(
			math.cos(angle) * distance,
			0,
			math.sin(angle) * distance
		)
		
		if self.testTarget then
			self:MoveTestTarget(newPos)
		else
			self:StartTestMode(newPos)
		end
	end
end

return CompassController

