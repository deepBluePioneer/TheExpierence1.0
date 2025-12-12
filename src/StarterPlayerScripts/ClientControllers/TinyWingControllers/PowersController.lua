--[[
	PowersController
	
	Displays a Powers UI for purchasing temporary game effects.
	Uses Developer Products to allow players to affect the game in real-time.
	
	Available Powers:
	- Hide Crystals (30s)
	- Hide Blockades (30s)
	- Hide Rails (30s)
	- Hide Clouds (30s)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local MarketplaceService = game:GetService("MarketplaceService")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local Knit = require(Packages.Knit)

local PowersController = Knit.CreateController {
	Name = "PowersController",
}

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         CONFIGURATION                                       ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

local CONFIG = {
	-- Button
	ButtonSize = UDim2.new(0, 100, 0, 40),
	ButtonPosition = UDim2.new(0, 20, 0.5, 50),  -- Below shop button
	ButtonColor = Color3.fromRGB(255, 150, 50),  -- Orange
	ButtonTextColor = Color3.fromRGB(255, 255, 255),
	
	-- Window
	WindowSize = UDim2.new(0, 500, 0, 450),
	WindowColor = Color3.fromRGB(35, 30, 45),
	WindowBorderColor = Color3.fromRGB(255, 150, 50),
	
	-- Power cards
	CardSize = UDim2.new(1, -30, 0, 80),
	CardColor = Color3.fromRGB(50, 45, 60),
	CardHoverColor = Color3.fromRGB(65, 55, 75),
	
	-- Powers definition
	Powers = {
		{
			id = "hide_crystals",
			name = "Crystal Clear",
			description = "Hide all crystals for 30 seconds. Easier navigation!",
			icon = "💎",
			collection = "Crystals",
			duration = 30,
			price = 25,  -- Robux (placeholder)
			productId = nil,  -- Set to actual Developer Product ID
		},
		{
			id = "hide_blockades",
			name = "Clear Path",
			description = "Remove all blockades for 30 seconds. No obstacles!",
			icon = "🚧",
			collection = "Blockades",
			duration = 30,
			price = 50,
			productId = nil,
		},
		{
			id = "hide_rails",
			name = "Freedom Mode",
			description = "Hide all guide rails for 30 seconds. Go anywhere!",
			icon = "🛤️",
			collection = "Rails",
			duration = 30,
			price = 15,
			productId = nil,
		},
	},
}

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         STATE                                               ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

local player = Players.LocalPlayer
local powersOpen = false
local powersGui = nil
local hubService = nil

-- Active powers with cooldown timers
local activePowers = {}  -- { [powerId] = endTime }

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

local function createPowersButton(parent)
	local button = Instance.new("TextButton")
	button.Name = "PowersButton"
	button.Size = CONFIG.ButtonSize
	button.Position = CONFIG.ButtonPosition
	button.AnchorPoint = Vector2.new(0, 0.5)
	button.BackgroundColor3 = CONFIG.ButtonColor
	button.TextColor3 = CONFIG.ButtonTextColor
	button.Text = "⚡ POWERS"
	button.Font = Enum.Font.GothamBold
	button.TextSize = 16
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

local function createPowerCard(power, parent)
	local card = Instance.new("Frame")
	card.Name = power.id
	card.Size = CONFIG.CardSize
	card.BackgroundColor3 = CONFIG.CardColor
	card.BorderSizePixel = 0
	card.Parent = parent
	
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = card
	
	local stroke = Instance.new("UIStroke")
	stroke.Color = CONFIG.WindowBorderColor
	stroke.Thickness = 1
	stroke.Transparency = 0.7
	stroke.Parent = card
	
	-- Icon
	local icon = Instance.new("TextLabel")
	icon.Name = "Icon"
	icon.Size = UDim2.new(0, 50, 0, 50)
	icon.Position = UDim2.new(0, 15, 0.5, 0)
	icon.AnchorPoint = Vector2.new(0, 0.5)
	icon.BackgroundTransparency = 1
	icon.Text = power.icon
	icon.TextSize = 35
	icon.Font = Enum.Font.GothamBold
	icon.Parent = card
	
	-- Name
	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "Name"
	nameLabel.Size = UDim2.new(0, 200, 0, 25)
	nameLabel.Position = UDim2.new(0, 75, 0, 12)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Text = power.name
	nameLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.TextSize = 16
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.Parent = card
	
	-- Description
	local descLabel = Instance.new("TextLabel")
	descLabel.Name = "Description"
	descLabel.Size = UDim2.new(0, 280, 0, 35)
	descLabel.Position = UDim2.new(0, 75, 0, 38)
	descLabel.BackgroundTransparency = 1
	descLabel.Text = power.description
	descLabel.TextColor3 = Color3.fromRGB(180, 180, 180)
	descLabel.Font = Enum.Font.Gotham
	descLabel.TextSize = 12
	descLabel.TextXAlignment = Enum.TextXAlignment.Left
	descLabel.TextWrapped = true
	descLabel.Parent = card
	
	-- Duration badge
	local durationBadge = Instance.new("TextLabel")
	durationBadge.Name = "Duration"
	durationBadge.Size = UDim2.new(0, 50, 0, 20)
	durationBadge.Position = UDim2.new(0, 75, 1, -25)
	durationBadge.BackgroundColor3 = Color3.fromRGB(80, 80, 100)
	durationBadge.Text = string.format("%ds", power.duration)
	durationBadge.TextColor3 = Color3.fromRGB(200, 200, 200)
	durationBadge.Font = Enum.Font.GothamBold
	durationBadge.TextSize = 11
	durationBadge.Parent = card
	
	local durationCorner = Instance.new("UICorner")
	durationCorner.CornerRadius = UDim.new(0, 4)
	durationCorner.Parent = durationBadge
	
	-- Activate button
	local activateButton = Instance.new("TextButton")
	activateButton.Name = "ActivateButton"
	activateButton.Size = UDim2.new(0, 100, 0, 35)
	activateButton.Position = UDim2.new(1, -15, 0.5, 0)
	activateButton.AnchorPoint = Vector2.new(1, 0.5)
	activateButton.BackgroundColor3 = CONFIG.ButtonColor
	activateButton.TextColor3 = Color3.fromRGB(255, 255, 255)
	activateButton.Text = string.format("R$ %d", power.price)
	activateButton.Font = Enum.Font.GothamBold
	activateButton.TextSize = 14
	activateButton.AutoButtonColor = true
	activateButton.Parent = card
	
	local buttonCorner = Instance.new("UICorner")
	buttonCorner.CornerRadius = UDim.new(0, 6)
	buttonCorner.Parent = activateButton
	
	-- Status overlay (for active powers)
	local statusOverlay = Instance.new("Frame")
	statusOverlay.Name = "StatusOverlay"
	statusOverlay.Size = UDim2.new(1, 0, 1, 0)
	statusOverlay.BackgroundColor3 = Color3.fromRGB(0, 200, 100)
	statusOverlay.BackgroundTransparency = 0.9
	statusOverlay.Visible = false
	statusOverlay.Parent = card
	
	local overlayCorner = Instance.new("UICorner")
	overlayCorner.CornerRadius = UDim.new(0, 10)
	overlayCorner.Parent = statusOverlay
	
	local activeLabel = Instance.new("TextLabel")
	activeLabel.Name = "ActiveLabel"
	activeLabel.Size = UDim2.new(1, 0, 1, 0)
	activeLabel.BackgroundTransparency = 1
	activeLabel.Text = "ACTIVE"
	activeLabel.TextColor3 = Color3.fromRGB(0, 255, 100)
	activeLabel.Font = Enum.Font.GothamBold
	activeLabel.TextSize = 20
	activeLabel.Parent = statusOverlay
	
	-- Click handler
	activateButton.MouseButton1Click:Connect(function()
		-- Check if power is already active
		if activePowers[power.id] and activePowers[power.id] > tick() then
			print("[Powers] Power already active!")
			return
		end
		
		-- For now, directly activate (would normally prompt Developer Product purchase)
		print(string.format("[Powers] Activating '%s' for %ds", power.name, power.duration))
		
		-- Call server to hide collection
		local success = hubService:RequestHideCollection(power.collection, power.duration)
		
		if success then
			-- Track active power
			activePowers[power.id] = tick() + power.duration
			
			-- Show active state
			statusOverlay.Visible = true
			activateButton.Text = "ACTIVE"
			activateButton.BackgroundColor3 = Color3.fromRGB(50, 180, 80)
			
			-- Update timer
			task.spawn(function()
				while activePowers[power.id] and activePowers[power.id] > tick() do
					local remaining = math.ceil(activePowers[power.id] - tick())
					activeLabel.Text = string.format("ACTIVE: %ds", remaining)
					task.wait(0.5)
				end
				
				-- Reset card
				statusOverlay.Visible = false
				activateButton.Text = string.format("R$ %d", power.price)
				activateButton.BackgroundColor3 = CONFIG.ButtonColor
				activePowers[power.id] = nil
			end)
		end
	end)
	
	-- Hover effect
	card.MouseEnter:Connect(function()
		TweenService:Create(card, TweenInfo.new(0.2), {
			BackgroundColor3 = CONFIG.CardHoverColor
		}):Play()
	end)
	
	card.MouseLeave:Connect(function()
		TweenService:Create(card, TweenInfo.new(0.2), {
			BackgroundColor3 = CONFIG.CardColor
		}):Play()
	end)
	
	return card
end

local function createPowersWindow(parent)
	-- Background
	local background = Instance.new("Frame")
	background.Name = "PowersBackground"
	background.Size = UDim2.new(1, 0, 1, 0)
	background.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	background.BackgroundTransparency = 0.5
	background.BorderSizePixel = 0
	background.Parent = parent
	
	-- Window
	local window = Instance.new("Frame")
	window.Name = "PowersWindow"
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
	title.Text = "⚡ POWERS"
	title.TextColor3 = Color3.fromRGB(255, 255, 255)
	title.Font = Enum.Font.GothamBold
	title.TextSize = 22
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Parent = titleBar
	
	local subtitle = Instance.new("TextLabel")
	subtitle.Name = "Subtitle"
	subtitle.Size = UDim2.new(1, -20, 0, 20)
	subtitle.Position = UDim2.new(0, 20, 0, 50)
	subtitle.BackgroundTransparency = 1
	subtitle.Text = "Temporarily affect the game world!"
	subtitle.TextColor3 = Color3.fromRGB(180, 180, 180)
	subtitle.Font = Enum.Font.Gotham
	subtitle.TextSize = 12
	subtitle.TextXAlignment = Enum.TextXAlignment.Left
	subtitle.Parent = window
	
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
	
	-- Scrolling frame for power cards
	local scrollFrame = Instance.new("ScrollingFrame")
	scrollFrame.Name = "PowersList"
	scrollFrame.Size = UDim2.new(1, -30, 1, -90)
	scrollFrame.Position = UDim2.new(0.5, 0, 0, 80)
	scrollFrame.AnchorPoint = Vector2.new(0.5, 0)
	scrollFrame.BackgroundTransparency = 1
	scrollFrame.BorderSizePixel = 0
	scrollFrame.ScrollBarThickness = 6
	scrollFrame.ScrollBarImageColor3 = CONFIG.WindowBorderColor
	scrollFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
	scrollFrame.Parent = window
	
	-- List layout
	local listLayout = Instance.new("UIListLayout")
	listLayout.Padding = UDim.new(0, 10)
	listLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	listLayout.SortOrder = Enum.SortOrder.LayoutOrder
	listLayout.Parent = scrollFrame
	
	-- Auto-size canvas
	listLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
		scrollFrame.CanvasSize = UDim2.new(0, 0, 0, listLayout.AbsoluteContentSize.Y + 20)
	end)
	
	return background, window, scrollFrame, closeButton
end

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         POWERS LOGIC                                        ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

local openPowers
local closePowers

closePowers = function()
	if not powersOpen then return end
	
	local background = powersGui:FindFirstChild("PowersBackground")
	if background then
		local window = background:FindFirstChild("PowersWindow")
		
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
	
	powersOpen = false
	
	-- Update global window state
	_G.UIWindowState.anyWindowOpen = false
	_G.UIWindowState.currentWindow = nil
	
	-- Re-enable all buttons
	setButtonsEnabled(true, nil)
	
	print("[PowersController] Powers closed")
end

openPowers = function()
	-- Check if this window is already open
	if powersOpen then return end
	
	-- Check if ANY window is currently open
	if _G.UIWindowState.anyWindowOpen then
		print("[PowersController] Cannot open powers - another window is already open")
		return
	end
	
	powersOpen = true
	_G.UIWindowState.anyWindowOpen = true
	_G.UIWindowState.currentWindow = "Powers"
	
	-- Disable other buttons
	setButtonsEnabled(false, _G.UIWindowState.buttons["Powers"])
	
	-- Create window
	local background, window, scrollFrame, closeButton = createPowersWindow(powersGui)
	
	-- Close button handler
	closeButton.MouseButton1Click:Connect(function()
		closePowers()
	end)
	
	-- Click outside to close
	background.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			local mouse = player:GetMouse()
			local windowPos = window.AbsolutePosition
			local windowSize = window.AbsoluteSize
			
			if mouse.X < windowPos.X or mouse.X > windowPos.X + windowSize.X or
			   mouse.Y < windowPos.Y or mouse.Y > windowPos.Y + windowSize.Y then
				closePowers()
			end
		end
	end)
	
	-- Create power cards
	for i, power in ipairs(CONFIG.Powers) do
		local card = createPowerCard(power, scrollFrame)
		card.LayoutOrder = i
	end
	
	-- Animate open
	window.Size = UDim2.new(0, 0, 0, 0)
	background.BackgroundTransparency = 1
	
	TweenService:Create(background, TweenInfo.new(0.3), {
		BackgroundTransparency = 0.5
	}):Play()
	
	TweenService:Create(window, TweenInfo.new(0.3, Enum.EasingStyle.Back), {
		Size = CONFIG.WindowSize
	}):Play()
	
	print("[PowersController] Powers opened")
end

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         KNIT LIFECYCLE                                      ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

function PowersController:KnitInit()
	print("[PowersController] Initializing...")
end

function PowersController:KnitStart()
	print("[PowersController] Started")
	
	-- Get HubService
	hubService = Knit.GetService("HubService")
	
	-- Wait for PlayerGui
	local playerGui = player:WaitForChild("PlayerGui")
	
	-- Create main GUI
	powersGui = Instance.new("ScreenGui")
	powersGui.Name = "PowersGui"
	powersGui.ResetOnSpawn = false
	powersGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	powersGui.Parent = playerGui
	
	-- Create powers button
	local powersButton = createPowersButton(powersGui)
	powersButton:SetAttribute("OriginalColor", CONFIG.ButtonColor)
	_G.UIWindowState.buttons["Powers"] = powersButton
	
	powersButton.MouseButton1Click:Connect(function()
		if powersOpen then
			closePowers()
		else
			openPowers()
		end
	end)
	
	print("[PowersController] Powers button created. Click to open!")
end

return PowersController

