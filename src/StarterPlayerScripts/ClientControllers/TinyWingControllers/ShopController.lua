--[[
	ShopController
	
	Displays a shop UI with all available machines in a grid.
	Uses ViewportFrames to show 3D previews of each machine.
	
	Features:
	- SHOP button on screen
	- Grid of machines with 3D previews
	- Purchase buttons (placeholder functionality)
	- Rotating previews
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local Knit = require(Packages.Knit)

local ShopController = Knit.CreateController {
	Name = "ShopController",
}

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         CONFIGURATION                                       ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

local CONFIG = {
	-- Shop button
	ButtonSize = UDim2.new(0, 100, 0, 40),
	ButtonPosition = UDim2.new(0, 20, 0.5, 0),
	ButtonColor = Color3.fromRGB(0, 200, 255),
	ButtonTextColor = Color3.fromRGB(255, 255, 255),
	
	-- Shop window
	WindowSize = UDim2.new(0.8, 0, 0.8, 0),
	WindowColor = Color3.fromRGB(30, 35, 45),
	WindowBorderColor = Color3.fromRGB(0, 200, 255),
	
	-- Grid
	GridColumns = 4,
	CardSize = UDim2.new(0, 220, 0, 380),  -- Taller for stat bars
	CardSpacing = 15,
	CardColor = Color3.fromRGB(45, 50, 60),
	CardHoverColor = Color3.fromRGB(55, 60, 75),
	
	-- Viewport
	ViewportSize = UDim2.new(1, -20, 0, 160),
	CameraDistance = 15,
	RotationSpeed = 0.5,
	
	-- Preview machines location (far away from play area)
	PreviewLocation = Vector3.new(10000, 500, 10000),
	PreviewSpacing = 50,
	
	-- Prices (placeholder)
	MachinePrices = {
		["machine_1"] = 0,       -- Free starter
		["machine_3"] = 500,
		["machine_5"] = 750,
		["machine_7"] = 600,
		["machine_8"] = 1000,
		["machine_9"] = 1200,
		["machine_10"] = 800,
		["machine_12"] = 900,
	},
	
	-- Machine display names
	MachineNames = {
		["machine_1"] = "Starter",
		["machine_3"] = "Speeder",
		["machine_5"] = "Tank",
		["machine_7"] = "Glider",
		["machine_8"] = "Racer",
		["machine_9"] = "Stunter",
		["machine_10"] = "Bouncer",
		["machine_12"] = "Drifter",
	},
	
	-- Machine descriptions
	MachineDescriptions = {
		["machine_1"] = "Balanced & beginner-friendly",
		["machine_3"] = "Fast and nimble",
		["machine_5"] = "Heavy and powerful",
		["machine_7"] = "Floaty air control",
		["machine_8"] = "Pure speed machine",
		["machine_9"] = "Trick specialist!",
		["machine_10"] = "Super bouncy!",
		["machine_12"] = "Loose, drifty handling",
	},
	
	-- Machine stats (0-100 scale for display)
	-- Stats: Speed, Handling, Acceleration, Bounce, Air Control
	MachineStats = {
		["machine_1"] = { Speed = 50, Handling = 50, Acceleration = 50, Bounce = 50, AirControl = 50 },
		["machine_3"] = { Speed = 80, Handling = 75, Acceleration = 85, Bounce = 35, AirControl = 60 },
		["machine_5"] = { Speed = 30, Handling = 30, Acceleration = 25, Bounce = 90, AirControl = 25 },
		["machine_7"] = { Speed = 45, Handling = 60, Acceleration = 50, Bounce = 55, AirControl = 95 },
		["machine_8"] = { Speed = 100, Handling = 65, Acceleration = 95, Bounce = 20, AirControl = 70 },
		["machine_9"] = { Speed = 55, Handling = 80, Acceleration = 70, Bounce = 75, AirControl = 85 },
		["machine_10"] = { Speed = 40, Handling = 70, Acceleration = 55, Bounce = 100, AirControl = 45 },
		["machine_12"] = { Speed = 65, Handling = 90, Acceleration = 60, Bounce = 50, AirControl = 55 },
	},
	
	-- Stat display config
	StatBarHeight = 8,
	StatBarSpacing = 4,
	StatColors = {
		Speed = Color3.fromRGB(255, 100, 100),        -- Red
		Handling = Color3.fromRGB(100, 200, 255),    -- Blue
		Acceleration = Color3.fromRGB(255, 200, 50), -- Yellow
		Bounce = Color3.fromRGB(100, 255, 150),      -- Green
		AirControl = Color3.fromRGB(200, 150, 255),  -- Purple
	},
	StatOrder = { "Speed", "Handling", "Acceleration", "Bounce", "AirControl" },
	StatLabels = {
		Speed = "SPD",
		Handling = "HND",
		Acceleration = "ACC",
		Bounce = "BNC",
		AirControl = "AIR",
	},
}

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         STATE                                               ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

local player = Players.LocalPlayer
local shopOpen = false
local shopGui = nil
local shopButton = nil
local previewFolder = nil
local previewMachines = {}  -- { machineName = { model = Model, camera = Camera } }
local viewportConnections = {}

-- Global window state (shared via _G for simplicity)
-- Tracks if ANY window is currently open to prevent overlapping windows
if not _G.UIWindowState then
	_G.UIWindowState = {
		anyWindowOpen = false,
		currentWindow = nil,
		buttons = {},  -- { buttonName = buttonInstance }
	}
end

-- Helper to disable/enable all UI buttons
local function setButtonsEnabled(enabled, excludeButton)
	for name, button in pairs(_G.UIWindowState.buttons) do
		if button and button.Parent and button ~= excludeButton then
			button.Active = enabled
			button.AutoButtonColor = enabled
			if enabled then
				-- Restore original color
				local originalColor = button:GetAttribute("OriginalColor")
				if originalColor then
					button.BackgroundColor3 = originalColor
				end
				button.TextTransparency = 0
			else
				-- Store original color and grey out
				if not button:GetAttribute("OriginalColor") then
					button:SetAttribute("OriginalColor", button.BackgroundColor3)
				end
				button.BackgroundColor3 = Color3.fromRGB(80, 80, 80)
				button.TextTransparency = 0.5
			end
		end
	end
end

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         UI CREATION                                         ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

local function createShopButton(parent)
	local button = Instance.new("TextButton")
	button.Name = "ShopButton"
	button.Size = CONFIG.ButtonSize
	button.Position = CONFIG.ButtonPosition
	button.AnchorPoint = Vector2.new(0, 0.5)
	button.BackgroundColor3 = CONFIG.ButtonColor
	button.TextColor3 = CONFIG.ButtonTextColor
	button.Text = "🛒 SHOP"
	button.Font = Enum.Font.GothamBold
	button.TextSize = 18
	button.AutoButtonColor = true
	button.Parent = parent
	
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = button
	
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(255, 255, 255)
	stroke.Thickness = 2
	stroke.Transparency = 0.5
	stroke.Parent = button
	
	return button
end

-- Create a single stat bar (starts at 0 for animation)
local function createStatBar(statName, value, yPosition, parent)
	local barHeight = CONFIG.StatBarHeight
	local barColor = CONFIG.StatColors[statName] or Color3.fromRGB(150, 150, 150)
	local label = CONFIG.StatLabels[statName] or statName
	
	-- Container for the stat row
	local statRow = Instance.new("Frame")
	statRow.Name = "Stat_" .. statName
	statRow.Size = UDim2.new(1, -20, 0, barHeight + 2)
	statRow.Position = UDim2.new(0.5, 0, 0, yPosition)
	statRow.AnchorPoint = Vector2.new(0.5, 0)
	statRow.BackgroundTransparency = 1
	statRow.Parent = parent
	
	-- Stat label (left side)
	local statLabel = Instance.new("TextLabel")
	statLabel.Name = "Label"
	statLabel.Size = UDim2.new(0, 30, 1, 0)
	statLabel.Position = UDim2.new(0, 0, 0, 0)
	statLabel.BackgroundTransparency = 1
	statLabel.Text = label
	statLabel.TextColor3 = Color3.fromRGB(180, 180, 180)
	statLabel.Font = Enum.Font.GothamBold
	statLabel.TextSize = 9
	statLabel.TextXAlignment = Enum.TextXAlignment.Left
	statLabel.Parent = statRow
	
	-- Bar background
	local barBg = Instance.new("Frame")
	barBg.Name = "BarBackground"
	barBg.Size = UDim2.new(1, -40, 0, barHeight)
	barBg.Position = UDim2.new(0, 35, 0.5, 0)
	barBg.AnchorPoint = Vector2.new(0, 0.5)
	barBg.BackgroundColor3 = Color3.fromRGB(30, 35, 40)
	barBg.BorderSizePixel = 0
	barBg.Parent = statRow
	
	local bgCorner = Instance.new("UICorner")
	bgCorner.CornerRadius = UDim.new(0, 3)
	bgCorner.Parent = barBg
	
	-- Bar fill (starts at 0 for animation)
	local barFill = Instance.new("Frame")
	barFill.Name = "BarFill"
	barFill.Size = UDim2.new(0, 0, 1, 0)  -- Start at 0
	barFill.Position = UDim2.new(0, 0, 0, 0)
	barFill.BackgroundColor3 = barColor
	barFill.BorderSizePixel = 0
	barFill.Parent = barBg
	
	-- Store target value for animation
	barFill:SetAttribute("TargetValue", value)
	
	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(0, 3)
	fillCorner.Parent = barFill
	
	-- Gradient for bar fill
	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.new(1, 1, 1)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(200, 200, 200)),
	})
	gradient.Rotation = 90
	gradient.Parent = barFill
	
	return statRow, barFill
end

local function createMachineCard(machineName, parent)
	local card = Instance.new("Frame")
	card.Name = machineName
	card.Size = CONFIG.CardSize
	card.BackgroundColor3 = CONFIG.CardColor
	card.BorderSizePixel = 0
	card.Parent = parent
	
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = card
	
	local stroke = Instance.new("UIStroke")
	stroke.Color = CONFIG.WindowBorderColor
	stroke.Thickness = 2
	stroke.Transparency = 0.5
	stroke.Parent = card
	
	-- Viewport Frame for 3D preview
	local viewport = Instance.new("ViewportFrame")
	viewport.Name = "MachinePreview"
	viewport.Size = CONFIG.ViewportSize
	viewport.Position = UDim2.new(0.5, 0, 0, 10)
	viewport.AnchorPoint = Vector2.new(0.5, 0)
	viewport.BackgroundColor3 = Color3.fromRGB(20, 25, 35)
	viewport.BorderSizePixel = 0
	viewport.Parent = card
	
	local viewportCorner = Instance.new("UICorner")
	viewportCorner.CornerRadius = UDim.new(0, 8)
	viewportCorner.Parent = viewport
	
	-- Machine name label
	local displayName = CONFIG.MachineNames[machineName] or machineName
	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "NameLabel"
	nameLabel.Size = UDim2.new(1, -20, 0, 22)
	nameLabel.Position = UDim2.new(0.5, 0, 0, 175)
	nameLabel.AnchorPoint = Vector2.new(0.5, 0)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Text = displayName
	nameLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.TextSize = 16
	nameLabel.Parent = card
	
	-- Description label
	local description = CONFIG.MachineDescriptions[machineName] or ""
	local descLabel = Instance.new("TextLabel")
	descLabel.Name = "DescLabel"
	descLabel.Size = UDim2.new(1, -20, 0, 16)
	descLabel.Position = UDim2.new(0.5, 0, 0, 197)
	descLabel.AnchorPoint = Vector2.new(0.5, 0)
	descLabel.BackgroundTransparency = 1
	descLabel.Text = description
	descLabel.TextColor3 = Color3.fromRGB(150, 150, 150)
	descLabel.Font = Enum.Font.Gotham
	descLabel.TextSize = 10
	descLabel.Parent = card
	
	-- Stats section
	local stats = CONFIG.MachineStats[machineName] or {}
	local statsStartY = 220
	local statSpacing = CONFIG.StatBarHeight + CONFIG.StatBarSpacing
	local statBars = {}  -- Collect stat bar fills for animation
	
	for i, statName in ipairs(CONFIG.StatOrder) do
		local value = stats[statName] or 50
		local yPos = statsStartY + (i - 1) * statSpacing
		local _, barFill = createStatBar(statName, value, yPos, card)
		table.insert(statBars, barFill)
	end
	
	-- Price / Purchase button
	local price = CONFIG.MachinePrices[machineName] or 999
	local buttonText = price == 0 and "✓ OWNED" or string.format("💰 %d", price)
	local buttonColor = price == 0 and Color3.fromRGB(50, 180, 80) or CONFIG.ButtonColor
	
	local purchaseButton = Instance.new("TextButton")
	purchaseButton.Name = "PurchaseButton"
	purchaseButton.Size = UDim2.new(1, -30, 0, 32)
	purchaseButton.Position = UDim2.new(0.5, 0, 1, -45)
	purchaseButton.AnchorPoint = Vector2.new(0.5, 0)
	purchaseButton.BackgroundColor3 = buttonColor
	purchaseButton.TextColor3 = Color3.fromRGB(255, 255, 255)
	purchaseButton.Text = buttonText
	purchaseButton.Font = Enum.Font.GothamBold
	purchaseButton.TextSize = 14
	purchaseButton.AutoButtonColor = true
	purchaseButton.Parent = card
	
	local buttonCorner = Instance.new("UICorner")
	buttonCorner.CornerRadius = UDim.new(0, 6)
	buttonCorner.Parent = purchaseButton
	
	-- Purchase button click handler
	purchaseButton.MouseButton1Click:Connect(function()
		if price == 0 then
			print(string.format("[Shop] %s is already owned!", displayName))
		else
			print(string.format("[Shop] Purchase %s for %d coins? (Not implemented)", displayName, price))
			-- TODO: Implement actual purchase logic
		end
	end)
	
	-- Hover effect
	card.MouseEnter:Connect(function()
		TweenService:Create(card, TweenInfo.new(0.2), {
			BackgroundColor3 = CONFIG.CardHoverColor
		}):Play()
		TweenService:Create(stroke, TweenInfo.new(0.2), {
			Transparency = 0
		}):Play()
	end)
	
	card.MouseLeave:Connect(function()
		TweenService:Create(card, TweenInfo.new(0.2), {
			BackgroundColor3 = CONFIG.CardColor
		}):Play()
		TweenService:Create(stroke, TweenInfo.new(0.2), {
			Transparency = 0.5
		}):Play()
	end)
	
	return card, viewport, statBars
end

-- Animate all stat bars from 0 to their target values
local function animateStatBars(allStatBars)
	for cardIndex, cardBars in ipairs(allStatBars) do
		-- Stagger animation per card
		local cardDelay = (cardIndex - 1) * 0.1
		
		for barIndex, barFill in ipairs(cardBars) do
			-- Stagger animation per bar within card
			local barDelay = cardDelay + (barIndex - 1) * 0.05
			local targetValue = barFill:GetAttribute("TargetValue") or 50
			
			task.delay(barDelay, function()
				if barFill and barFill.Parent then
					TweenService:Create(barFill, TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
						Size = UDim2.new(targetValue / 100, 0, 1, 0)
					}):Play()
				end
			end)
		end
	end
end

local function createShopWindow(parent)
	-- Darkened background
	local background = Instance.new("Frame")
	background.Name = "ShopBackground"
	background.Size = UDim2.new(1, 0, 1, 0)
	background.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	background.BackgroundTransparency = 0.5
	background.BorderSizePixel = 0
	background.Parent = parent
	
	-- Main window
	local window = Instance.new("Frame")
	window.Name = "ShopWindow"
	window.Size = CONFIG.WindowSize
	window.Position = UDim2.new(0.5, 0, 0.5, 0)
	window.AnchorPoint = Vector2.new(0.5, 0.5)
	window.BackgroundColor3 = CONFIG.WindowColor
	window.BorderSizePixel = 0
	window.Parent = background
	
	local windowCorner = Instance.new("UICorner")
	windowCorner.CornerRadius = UDim.new(0, 16)
	windowCorner.Parent = window
	
	local windowStroke = Instance.new("UIStroke")
	windowStroke.Color = CONFIG.WindowBorderColor
	windowStroke.Thickness = 3
	windowStroke.Parent = window
	
	-- Title bar
	local titleBar = Instance.new("Frame")
	titleBar.Name = "TitleBar"
	titleBar.Size = UDim2.new(1, 0, 0, 50)
	titleBar.BackgroundTransparency = 1
	titleBar.Parent = window
	
	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Size = UDim2.new(1, -100, 1, 0)
	title.Position = UDim2.new(0, 20, 0, 0)
	title.BackgroundTransparency = 1
	title.Text = "🚗 VEHICLE SHOP"
	title.TextColor3 = Color3.fromRGB(255, 255, 255)
	title.Font = Enum.Font.GothamBold
	title.TextSize = 24
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Parent = titleBar
	
	-- Close button
	local closeButton = Instance.new("TextButton")
	closeButton.Name = "CloseButton"
	closeButton.Size = UDim2.new(0, 40, 0, 40)
	closeButton.Position = UDim2.new(1, -50, 0.5, 0)
	closeButton.AnchorPoint = Vector2.new(0, 0.5)
	closeButton.BackgroundColor3 = Color3.fromRGB(200, 60, 60)
	closeButton.TextColor3 = Color3.fromRGB(255, 255, 255)
	closeButton.Text = "✕"
	closeButton.Font = Enum.Font.GothamBold
	closeButton.TextSize = 20
	closeButton.AutoButtonColor = true
	closeButton.Parent = titleBar
	
	local closeCorner = Instance.new("UICorner")
	closeCorner.CornerRadius = UDim.new(0, 8)
	closeCorner.Parent = closeButton
	
	-- Scrolling frame for grid
	local scrollFrame = Instance.new("ScrollingFrame")
	scrollFrame.Name = "MachineGrid"
	scrollFrame.Size = UDim2.new(1, -40, 1, -70)
	scrollFrame.Position = UDim2.new(0.5, 0, 0, 60)
	scrollFrame.AnchorPoint = Vector2.new(0.5, 0)
	scrollFrame.BackgroundTransparency = 1
	scrollFrame.BorderSizePixel = 0
	scrollFrame.ScrollBarThickness = 8
	scrollFrame.ScrollBarImageColor3 = CONFIG.WindowBorderColor
	scrollFrame.CanvasSize = UDim2.new(0, 0, 0, 0)  -- Auto-sized by UIGridLayout
	scrollFrame.Parent = window
	
	-- Grid layout
	local gridLayout = Instance.new("UIGridLayout")
	gridLayout.CellSize = CONFIG.CardSize
	gridLayout.CellPadding = UDim2.new(0, CONFIG.CardSpacing, 0, CONFIG.CardSpacing)
	gridLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	gridLayout.SortOrder = Enum.SortOrder.Name
	gridLayout.Parent = scrollFrame
	
	-- Auto-size canvas
	gridLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
		scrollFrame.CanvasSize = UDim2.new(0, 0, 0, gridLayout.AbsoluteContentSize.Y + 20)
	end)
	
	return background, window, scrollFrame, closeButton
end

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         PREVIEW MACHINES                                    ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

local function setupPreviewMachines()
	-- Create folder for preview machines
	previewFolder = Instance.new("Folder")
	previewFolder.Name = "ShopPreviewMachines"
	previewFolder.Parent = workspace
	
	-- Get machine prefabs
	local prefabsFolder = ReplicatedStorage:FindFirstChild("Prefabs")
	if not prefabsFolder then
		warn("[ShopController] No Prefabs folder found!")
		return
	end
	
	local machinesFolder = prefabsFolder:FindFirstChild("Machines")
	if not machinesFolder then
		warn("[ShopController] No Machines folder found in Prefabs!")
		return
	end
	
	-- Clone each machine for preview
	local index = 0
	for _, machine in ipairs(machinesFolder:GetChildren()) do
		if machine:IsA("Model") then
			local previewModel = machine:Clone()
			previewModel.Name = machine.Name .. "_Preview"
			
			-- Position far away
			local previewPos = CONFIG.PreviewLocation + Vector3.new(index * CONFIG.PreviewSpacing, 0, 0)
			
			-- Set position using PrimaryPart or first part
			if previewModel.PrimaryPart then
				previewModel:SetPrimaryPartCFrame(CFrame.new(previewPos))
			else
				local firstPart = previewModel:FindFirstChildWhichIsA("BasePart", true)
				if firstPart then
					local offset = firstPart.Position - previewModel:GetBoundingBox().Position
					previewModel:MoveTo(previewPos)
				end
			end
			
			-- Make non-collidable
			for _, part in ipairs(previewModel:GetDescendants()) do
				if part:IsA("BasePart") then
					part.CanCollide = false
					part.Anchored = true
				end
			end
			
			previewModel.Parent = previewFolder
			
			-- Create camera for this machine
			local camera = Instance.new("Camera")
			camera.Name = machine.Name .. "_Camera"
			camera.Parent = previewModel
			
			-- Store reference
			previewMachines[machine.Name] = {
				model = previewModel,
				camera = camera,
				position = previewPos,
			}
			
			index = index + 1
		end
	end
	
	print(string.format("[ShopController] Created %d preview machines", index))
end

local function setupViewport(viewport, machineName)
	local previewData = previewMachines[machineName]
	if not previewData then
		warn("[ShopController] No preview for machine:", machineName)
		return
	end
	
	-- Clone the preview model into the viewport
	local viewportModel = previewData.model:Clone()
	viewportModel.Parent = viewport
	
	-- Create viewport camera
	local camera = Instance.new("Camera")
	camera.CameraType = Enum.CameraType.Scriptable
	camera.Parent = viewport
	viewport.CurrentCamera = camera
	
	-- Calculate model bounds for camera positioning
	local cf, size = viewportModel:GetBoundingBox()
	local maxSize = math.max(size.X, size.Y, size.Z)
	local cameraDistance = maxSize * 1.5
	
	-- Store for rotation animation
	local startTime = tick()
	local connection
	
	connection = RunService.RenderStepped:Connect(function()
		if not viewport or not viewport.Parent then
			connection:Disconnect()
			return
		end
		
		local elapsed = tick() - startTime
		local angle = elapsed * CONFIG.RotationSpeed
		
		-- Orbit camera around the model
		local cameraPos = cf.Position + Vector3.new(
			math.sin(angle) * cameraDistance,
			cameraDistance * 0.3,
			math.cos(angle) * cameraDistance
		)
		
		camera.CFrame = CFrame.lookAt(cameraPos, cf.Position)
	end)
	
	table.insert(viewportConnections, connection)
end

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         SHOP LOGIC                                          ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

-- Forward declaration
local openShop
local closeShop

closeShop = function()
	if not shopOpen then return end
	
	-- Find and animate close
	local background = shopGui:FindFirstChild("ShopBackground")
	if background then
		local window = background:FindFirstChild("ShopWindow")
		
		if window then
			TweenService:Create(window, TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.In), {
				Size = UDim2.new(0, 0, 0, 0)
			}):Play()
		end
		
		local tween = TweenService:Create(background, TweenInfo.new(0.2), {
			BackgroundTransparency = 1
		})
		tween:Play()
		tween.Completed:Connect(function()
			background:Destroy()
		end)
	end
	
	-- Disconnect viewport animations
	for _, connection in ipairs(viewportConnections) do
		connection:Disconnect()
	end
	viewportConnections = {}
	
	shopOpen = false
	
	-- Update global window state
	_G.UIWindowState.anyWindowOpen = false
	_G.UIWindowState.currentWindow = nil
	
	-- Re-enable all buttons
	setButtonsEnabled(true, nil)
	
	print("[ShopController] Shop closed")
end

openShop = function()
	-- Check if this window is already open
	if shopOpen then return end
	
	-- Check if ANY window is currently open
	if _G.UIWindowState.anyWindowOpen then
		print("[ShopController] Cannot open shop - another window is already open")
		return
	end
	
	shopOpen = true
	_G.UIWindowState.anyWindowOpen = true
	_G.UIWindowState.currentWindow = "Shop"
	
	-- Disable other buttons
	setButtonsEnabled(false, shopButton)
	
	local playerGui = player:WaitForChild("PlayerGui")
	
	-- Create shop window
	local background, window, scrollFrame, closeButton = createShopWindow(shopGui)
	
	-- Close button handler
	closeButton.MouseButton1Click:Connect(function()
		closeShop()
	end)
	
	-- Click outside to close
	background.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			-- Check if click was outside window
			local mouse = player:GetMouse()
			local windowPos = window.AbsolutePosition
			local windowSize = window.AbsoluteSize
			
			if mouse.X < windowPos.X or mouse.X > windowPos.X + windowSize.X or
			   mouse.Y < windowPos.Y or mouse.Y > windowPos.Y + windowSize.Y then
				closeShop()
			end
		end
	end)
	
	-- Create machine cards and collect stat bars for animation
	local allStatBars = {}
	for machineName, _ in pairs(previewMachines) do
		local card, viewport, statBars = createMachineCard(machineName, scrollFrame)
		setupViewport(viewport, machineName)
		table.insert(allStatBars, statBars)
	end
	
	-- Animate window opening
	window.Size = UDim2.new(0, 0, 0, 0)
	background.BackgroundTransparency = 1
	
	TweenService:Create(background, TweenInfo.new(0.3), {
		BackgroundTransparency = 0.5
	}):Play()
	
	local windowTween = TweenService:Create(window, TweenInfo.new(0.3, Enum.EasingStyle.Back), {
		Size = CONFIG.WindowSize
	})
	windowTween:Play()
	
	-- Animate stat bars after window opens
	windowTween.Completed:Connect(function()
		animateStatBars(allStatBars)
	end)
	
	print("[ShopController] Shop opened")
end

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         KNIT LIFECYCLE                                      ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

function ShopController:KnitInit()
	print("[ShopController] Initializing...")
end

function ShopController:KnitStart()
	print("[ShopController] Started")
	
	-- Wait for PlayerGui
	local playerGui = player:WaitForChild("PlayerGui")
	
	-- Create main shop GUI
	shopGui = Instance.new("ScreenGui")
	shopGui.Name = "ShopGui"
	shopGui.ResetOnSpawn = false
	shopGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	shopGui.Parent = playerGui
	
	-- Create shop button
	shopButton = createShopButton(shopGui)
	shopButton:SetAttribute("OriginalColor", CONFIG.ButtonColor)
	_G.UIWindowState.buttons["Shop"] = shopButton
	
	shopButton.MouseButton1Click:Connect(function()
		if shopOpen then
			closeShop()
		else
			openShop()
		end
	end)
	
	-- Setup preview machines
	task.spawn(function()
		task.wait(1)  -- Wait for prefabs to load
		setupPreviewMachines()
	end)
	
	print("[ShopController] Shop button created. Click to open!")
end

return ShopController

