--[[
	UpgradeController
	
	Client-side controller for the stack capacity upgrade system.
	Shows avatar viewport with 3D boxes + 2D slot list.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local CustomPackages = ReplicatedStorage:WaitForChild("CustomPackages")
local Knit = require(Packages.Knit)

-- Replica Module
local Replica = CustomPackages:WaitForChild("Replica")
local ReplicaController = require(Replica.ReplicaController)

local Player = Players.LocalPlayer
local PlayerGui = Player:WaitForChild("PlayerGui")

local UpgradeController = Knit.CreateController {
	Name = "UpgradeController",
	_screenGui = nil,
	_panel = nil,
	-- UI Elements
	_headerTitle = nil,
	_slotsContainer = nil,
	_slotFrames = {},        -- 2D slot frames
	_capacityLabel = nil,
	_capacityFill = nil,
	_purchaseButton = nil,
	-- 3D Viewport (avatar only)
	_viewportFrame = nil,
	_worldModel = nil,
	_camera = nil,
	_avatarClone = nil,
	-- State
	_maxStack = 1,
	_maxCapacity = 20,
	_nextCost = 10,
	_isMaxed = false,
	_kudos = 0,
	_replica = nil,
	_kudosReplica = nil,
	_isPurchasing = false,
	_isPlayingReject = false,
}

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         CONFIG                                              ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

local CONFIG = {
	-- Master enable/disable
	Enabled = true,
	
	-- Panel position and size
	PanelPosition = UDim2.new(0, 20, 1, -20),
	PanelWidth = 180,
	
	-- Viewport settings (just the avatar, no 3D boxes)
	ViewportHeight = 100,
	ViewportCameraDistance = 8,
	ViewportCameraHeight = 3,
	ViewportCameraLookAtY = 2,
	ViewportCameraFOV = 40,
	
	-- 2D Slot settings (stacked vertically above viewport)
	SlotWidth = 50,      -- Width of each 2D slot
	SlotHeight = 22,     -- Height of each 2D slot
	SlotSpacing = 2,     -- Gap between slots
	MaxVisibleSlots = 20,
	
	-- Industrial/Logistics Color Palette
	BackgroundColor = Color3.fromRGB(20, 22, 28),
	BorderColor = Color3.fromRGB(255, 180, 0),
	HeaderColor = Color3.fromRGB(30, 34, 42),
	
	-- Slot colors (2D boxes)
	SlotFilledColor = Color3.fromRGB(180, 130, 70),      -- Cardboard brown
	SlotFilledStroke = Color3.fromRGB(140, 100, 50),
	SlotNextColor = Color3.fromRGB(100, 255, 100),       -- Green for purchasable
	SlotNextStroke = Color3.fromRGB(70, 180, 70),
	SlotLockedColor = Color3.fromRGB(45, 43, 40),        -- Dark grey
	SlotLockedStroke = Color3.fromRGB(55, 52, 48),
	SlotMaxedColor = Color3.fromRGB(218, 165, 32),       -- Gold
	
	-- UI Colors
	AccentColor = Color3.fromRGB(255, 180, 0),
	TextColor = Color3.fromRGB(255, 255, 255),
	SubtextColor = Color3.fromRGB(150, 150, 150),
	ButtonColor = Color3.fromRGB(80, 200, 80),           -- Green buy button
	ButtonHoverColor = Color3.fromRGB(100, 230, 100),
	ButtonTextColor = Color3.fromRGB(255, 255, 255),
	ButtonDisabledColor = Color3.fromRGB(60, 55, 50),
	ButtonDisabledText = Color3.fromRGB(100, 95, 90),
}

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         HELPER FUNCTIONS                                    ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

local function formatNumber(num)
	if num >= 1000000 then
		return string.format("%.1fM", num / 1000000)
	elseif num >= 1000 then
		return string.format("%.1fK", num / 1000)
	end
	return tostring(num)
end

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         2D SLOT UI                                          ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

function UpgradeController:CreateSlotFrames()
	-- Clear existing slots
	for _, frame in ipairs(self._slotFrames) do
		if frame then frame:Destroy() end
	end
	self._slotFrames = {}
	
	if not self._slotsContainer then return end
	
	-- Create 2D slot frames (stacked bottom to top)
	local slotsToCreate = math.min(self._maxCapacity, CONFIG.MaxVisibleSlots)
	
	for i = 1, slotsToCreate do
		local slotFrame = Instance.new("Frame")
		slotFrame.Name = "Slot_" .. i
		slotFrame.Size = UDim2.new(0, CONFIG.SlotWidth, 0, CONFIG.SlotHeight)
		slotFrame.BackgroundColor3 = CONFIG.SlotLockedColor
		slotFrame.BorderSizePixel = 0
		slotFrame.LayoutOrder = slotsToCreate - i + 1  -- Reverse order for bottom-to-top
		slotFrame.Parent = self._slotsContainer
		
		-- Rounded corners
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 4)
		corner.Parent = slotFrame
		
		-- Border stroke
		local stroke = Instance.new("UIStroke")
		stroke.Name = "Stroke"
		stroke.Color = CONFIG.SlotLockedStroke
		stroke.Thickness = 1
		stroke.Parent = slotFrame
		
		-- Slot number
		local numLabel = Instance.new("TextLabel")
		numLabel.Name = "Number"
		numLabel.Size = UDim2.new(1, 0, 1, 0)
		numLabel.BackgroundTransparency = 1
		numLabel.Text = tostring(i)
		numLabel.TextColor3 = Color3.fromRGB(150, 145, 140)
		numLabel.TextSize = 11
		numLabel.Font = Enum.Font.GothamBold
		numLabel.Parent = slotFrame
		
		self._slotFrames[i] = slotFrame
	end
	
	self:UpdateSlotColors()
end

function UpgradeController:UpdateSlotColors()
	for i, slotFrame in ipairs(self._slotFrames) do
		if slotFrame and slotFrame.Parent then
			local stroke = slotFrame:FindFirstChild("Stroke")
			local numLabel = slotFrame:FindFirstChild("Number")
			
			if i <= self._maxStack then
				-- Filled slot (owned)
				slotFrame.BackgroundColor3 = CONFIG.SlotFilledColor
				if stroke then stroke.Color = CONFIG.SlotFilledStroke end
				if numLabel then 
					numLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
					numLabel.TextTransparency = 0.2
				end
			elseif i == self._maxStack + 1 and not self._isMaxed then
				-- Next slot (purchasable) - green
				slotFrame.BackgroundColor3 = CONFIG.SlotNextColor
				if stroke then stroke.Color = CONFIG.SlotNextStroke end
				if numLabel then 
					numLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
					numLabel.TextTransparency = 0
				end
			else
				-- Locked slot
				slotFrame.BackgroundColor3 = CONFIG.SlotLockedColor
				if stroke then stroke.Color = CONFIG.SlotLockedStroke end
				if numLabel then 
					numLabel.TextColor3 = Color3.fromRGB(100, 95, 90)
					numLabel.TextTransparency = 0.5
				end
			end
		end
	end
end

-- Old 2D UpdateSlotColors removed - using 3D slots now

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         3D AVATAR VIEWPORT                                  ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

function UpgradeController:SetupAvatarViewport()
	-- Create WorldModel for avatar
	self._worldModel = Instance.new("WorldModel")
	self._worldModel.Parent = self._viewportFrame
	
	-- Create camera
	self._camera = Instance.new("Camera")
	self._camera.FieldOfView = CONFIG.ViewportCameraFOV
	self._viewportFrame.CurrentCamera = self._camera
	
	-- Position camera to see full avatar with all stacked boxes
	-- Camera looks at the middle of the stack from the front
	local lookAtY = CONFIG.ViewportCameraLookAtY or 10
	self._camera.CFrame = CFrame.new(
		Vector3.new(0, CONFIG.ViewportCameraHeight, CONFIG.ViewportCameraDistance),
		Vector3.new(0, lookAtY, 0)  -- Look at middle of box stack
	)
	
	-- Add lighting
	local light = Instance.new("Part")
	light.Anchored = true
	light.CanCollide = false
	light.Transparency = 1
	light.Size = Vector3.new(1, 1, 1)
	light.Position = Vector3.new(0, 6, 8)
	light.Parent = self._worldModel
	
	local pointLight = Instance.new("PointLight")
	pointLight.Brightness = 2
	pointLight.Range = 30
	pointLight.Parent = light
	
	-- Create avatar
	self:RefreshAvatarClone()
	
	-- Watch for character changes
	Player.CharacterAdded:Connect(function()
		task.wait(1)
		self:RefreshAvatarClone()
	end)
end

function UpgradeController:RefreshAvatarClone()
	if self._avatarClone then
		self._avatarClone:Destroy()
		self._avatarClone = nil
	end
	
	-- Create avatar from player's appearance
	local success, result = pcall(function()
		local desc = Players:GetHumanoidDescriptionFromUserId(Player.UserId)
		return Players:CreateHumanoidModelFromDescription(desc, Enum.HumanoidRigType.R15)
	end)
	
	if not success then
		success, result = pcall(function()
			local desc = Players:GetHumanoidDescriptionFromUserId(Player.UserId)
			return Players:CreateHumanoidModelFromDescription(desc, Enum.HumanoidRigType.R6)
		end)
	end
	
	if not success or not result then
		warn("[UpgradeController] Failed to create avatar")
		return
	end
	
	self._avatarClone = result
	
	-- Disable humanoid UI
	local humanoid = self._avatarClone:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	end
	
	-- Remove scripts
	for _, child in ipairs(self._avatarClone:GetDescendants()) do
		if child:IsA("BaseScript") then
			child:Destroy()
		end
	end
	
	-- Position avatar
	self._avatarClone.Parent = self._worldModel
	local hipHeight = humanoid and humanoid.HipHeight or 2
	self._avatarClone:PivotTo(CFrame.new(0, hipHeight + 1, 0) * CFrame.Angles(0, math.rad(180), 0))
	
	print("[UpgradeController] Avatar created")
end

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         UI CREATION                                         ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

function UpgradeController:CreateUI()
	-- Calculate dimensions
	local slotsHeight = self._maxCapacity * (CONFIG.SlotHeight + CONFIG.SlotSpacing)
	local slotsFrameHeight = slotsHeight + 8  -- Extra padding for frame
	local viewportHeight = CONFIG.ViewportHeight
	local headerHeight = 35
	local buttonHeight = 45
	local capacityHeight = 24
	local padding = 6
	
	-- Panel height: header + slotsFrame + viewport + capacity + button + padding
	local panelHeight = headerHeight + slotsFrameHeight + padding + viewportHeight + padding + capacityHeight + buttonHeight + padding
	
	-- Main ScreenGui
	self._screenGui = Instance.new("ScreenGui")
	self._screenGui.Name = "UpgradeGui"
	self._screenGui.ResetOnSpawn = false
	self._screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	self._screenGui.Parent = PlayerGui
	
	-- Main panel
	self._panel = Instance.new("Frame")
	self._panel.Name = "UpgradePanel"
	self._panel.Size = UDim2.new(0, CONFIG.PanelWidth, 0, panelHeight)
	self._panel.Position = CONFIG.PanelPosition
	self._panel.AnchorPoint = Vector2.new(0, 1)
	self._panel.BackgroundColor3 = CONFIG.BackgroundColor
	self._panel.ClipsDescendants = true
	self._panel.Parent = self._screenGui
	
	local panelCorner = Instance.new("UICorner")
	panelCorner.CornerRadius = UDim.new(0, 10)
	panelCorner.Parent = self._panel
	
	local panelStroke = Instance.new("UIStroke")
	panelStroke.Color = CONFIG.BorderColor
	panelStroke.Thickness = 2
	panelStroke.Parent = self._panel
	
	-- ═══════════════════════════════════════════════════════════════
	-- HEADER SECTION (at top)
	-- ═══════════════════════════════════════════════════════════════
	local header = Instance.new("Frame")
	header.Name = "Header"
	header.Size = UDim2.new(1, 0, 0, headerHeight)
	header.Position = UDim2.new(0, 0, 0, 0)
	header.BackgroundColor3 = CONFIG.HeaderColor
	header.BorderSizePixel = 0
	header.ZIndex = 10
	header.Parent = self._panel
	
	local headerCorner = Instance.new("UICorner")
	headerCorner.CornerRadius = UDim.new(0, 10)
	headerCorner.Parent = header
	
	local headerCover = Instance.new("Frame")
	headerCover.Size = UDim2.new(1, 0, 0, 10)
	headerCover.Position = UDim2.new(0, 0, 1, -10)
	headerCover.BackgroundColor3 = CONFIG.HeaderColor
	headerCover.BorderSizePixel = 0
	headerCover.Parent = header
	
	self._headerTitle = Instance.new("TextLabel")
	self._headerTitle.Size = UDim2.new(1, -12, 1, 0)
	self._headerTitle.Position = UDim2.new(0, 6, 0, 0)
	self._headerTitle.BackgroundTransparency = 1
	self._headerTitle.Text = "📦 1/20"
	self._headerTitle.TextColor3 = CONFIG.AccentColor
	self._headerTitle.TextSize = 14
	self._headerTitle.Font = Enum.Font.GothamBold
	self._headerTitle.TextXAlignment = Enum.TextXAlignment.Center
	self._headerTitle.Parent = header
	
	-- ═══════════════════════════════════════════════════════════════
	-- 2D SLOTS SECTION (in its own frame with background)
	-- ═══════════════════════════════════════════════════════════════
	local slotsY = headerHeight
	
	-- Outer frame for the slot stack (with background)
	local slotsFrame = Instance.new("Frame")
	slotsFrame.Name = "SlotsFrame"
	slotsFrame.Size = UDim2.new(1, -12, 0, slotsHeight + 8)
	slotsFrame.Position = UDim2.new(0, 6, 0, slotsY)
	slotsFrame.BackgroundColor3 = Color3.fromRGB(25, 28, 35)
	slotsFrame.ZIndex = 5
	slotsFrame.Parent = self._panel
	
	local slotsFrameCorner = Instance.new("UICorner")
	slotsFrameCorner.CornerRadius = UDim.new(0, 6)
	slotsFrameCorner.Parent = slotsFrame
	
	local slotsFrameStroke = Instance.new("UIStroke")
	slotsFrameStroke.Color = Color3.fromRGB(50, 55, 65)
	slotsFrameStroke.Thickness = 1
	slotsFrameStroke.Parent = slotsFrame
	
	-- Inner container for the actual slots
	self._slotsContainer = Instance.new("Frame")
	self._slotsContainer.Name = "SlotsContainer"
	self._slotsContainer.Size = UDim2.new(1, -8, 1, -8)
	self._slotsContainer.Position = UDim2.new(0, 4, 0, 4)
	self._slotsContainer.BackgroundTransparency = 1
	self._slotsContainer.Parent = slotsFrame
	
	local slotsLayout = Instance.new("UIListLayout")
	slotsLayout.SortOrder = Enum.SortOrder.LayoutOrder
	slotsLayout.Padding = UDim.new(0, CONFIG.SlotSpacing)
	slotsLayout.VerticalAlignment = Enum.VerticalAlignment.Bottom
	slotsLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	slotsLayout.Parent = self._slotsContainer
	
	self:CreateSlotFrames()
	
	-- ═══════════════════════════════════════════════════════════════
	-- VIEWPORT SECTION (Avatar - below the slots frame)
	-- ═══════════════════════════════════════════════════════════════
	local viewportY = slotsY + slotsFrameHeight + padding
	
	self._viewportFrame = Instance.new("ViewportFrame")
	self._viewportFrame.Name = "AvatarViewport"
	self._viewportFrame.Size = UDim2.new(1, -12, 0, viewportHeight)
	self._viewportFrame.Position = UDim2.new(0, 6, 0, viewportY)
	self._viewportFrame.BackgroundColor3 = Color3.fromRGB(15, 18, 22)
	self._viewportFrame.ZIndex = 1
	self._viewportFrame.Parent = self._panel
	
	local vpCorner = Instance.new("UICorner")
	vpCorner.CornerRadius = UDim.new(0, 6)
	vpCorner.Parent = self._viewportFrame
	
	self:SetupAvatarViewport()
	
	-- ═══════════════════════════════════════════════════════════════
	-- BOTTOM SECTION (Capacity bar + Buy Button)
	-- ═══════════════════════════════════════════════════════════════
	local bottomY = viewportY + viewportHeight + padding
	
	-- Capacity bar background
	local capacityBg = Instance.new("Frame")
	capacityBg.Name = "CapacityBg"
	capacityBg.Size = UDim2.new(1, -16, 0, capacityHeight)
	capacityBg.Position = UDim2.new(0, 8, 0, bottomY)
	capacityBg.BackgroundColor3 = Color3.fromRGB(35, 38, 45)
	capacityBg.Parent = self._panel
	
	local capBgCorner = Instance.new("UICorner")
	capBgCorner.CornerRadius = UDim.new(0, 6)
	capBgCorner.Parent = capacityBg
	
	-- Capacity fill bar
	self._capacityFill = Instance.new("Frame")
	self._capacityFill.Name = "CapacityFill"
	self._capacityFill.Size = UDim2.new(0.05, 0, 1, 0)
	self._capacityFill.BackgroundColor3 = CONFIG.AccentColor
	self._capacityFill.Parent = capacityBg
	
	local capFillCorner = Instance.new("UICorner")
	capFillCorner.CornerRadius = UDim.new(0, 6)
	capFillCorner.Parent = self._capacityFill
	
	-- Capacity label overlaid
	self._capacityLabel = Instance.new("TextLabel")
	self._capacityLabel.Size = UDim2.new(1, 0, 1, 0)
	self._capacityLabel.BackgroundTransparency = 1
	self._capacityLabel.Text = "1 / 20"
	self._capacityLabel.TextColor3 = CONFIG.TextColor
	self._capacityLabel.TextSize = 12
	self._capacityLabel.Font = Enum.Font.GothamBold
	self._capacityLabel.Parent = capacityBg
	
	-- Purchase button
	local buttonY = bottomY + capacityHeight + padding
	
	self._purchaseButton = Instance.new("TextButton")
	self._purchaseButton.Name = "PurchaseButton"
	self._purchaseButton.Size = UDim2.new(1, -16, 0, buttonHeight)
	self._purchaseButton.Position = UDim2.new(0, 8, 0, buttonY)
	self._purchaseButton.BackgroundColor3 = CONFIG.ButtonColor
	self._purchaseButton.Text = "+1 • 10 ⭐"
	self._purchaseButton.TextColor3 = CONFIG.ButtonTextColor
	self._purchaseButton.TextSize = 16
	self._purchaseButton.Font = Enum.Font.GothamBold
	self._purchaseButton.AutoButtonColor = false
	self._purchaseButton.Parent = self._panel
	
	local btnCorner = Instance.new("UICorner")
	btnCorner.CornerRadius = UDim.new(0, 8)
	btnCorner.Parent = self._purchaseButton
	
	local btnStroke = Instance.new("UIStroke")
	btnStroke.Color = Color3.fromRGB(60, 160, 60)
	btnStroke.Thickness = 2
	btnStroke.Parent = self._purchaseButton
	
	-- Button hover effects
	self._purchaseButton.MouseEnter:Connect(function()
		if not self._isMaxed and self._kudos >= self._nextCost then
			TweenService:Create(self._purchaseButton, TweenInfo.new(0.1), {
				BackgroundColor3 = CONFIG.ButtonHoverColor
			}):Play()
		end
	end)
	
	self._purchaseButton.MouseLeave:Connect(function()
		self:UpdateDisplay()
	end)
	
	self._purchaseButton.MouseButton1Click:Connect(function()
		self:TryPurchaseUpgrade()
	end)
	
	self:UpdateDisplay()
	print("[UpgradeController] UI created")
end

function UpgradeController:UpdateDisplay()
	-- Update header title with capacity
	if self._headerTitle then
		self._headerTitle.Text = string.format("📦 %d/%d", self._maxStack, self._maxCapacity)
	end
	
	-- Update capacity label
	if self._capacityLabel then
		self._capacityLabel.Text = string.format("%d / %d", self._maxStack, self._maxCapacity)
	end
	
	-- Update capacity fill bar
	if self._capacityFill then
		local fillPercent = self._maxStack / self._maxCapacity
		TweenService:Create(self._capacityFill, TweenInfo.new(0.3, Enum.EasingStyle.Quad), {
			Size = UDim2.new(fillPercent, 0, 1, 0)
		}):Play()
		
		-- Color based on fill level
		if self._isMaxed then
			self._capacityFill.BackgroundColor3 = CONFIG.SlotMaxedColor
		else
			self._capacityFill.BackgroundColor3 = CONFIG.AccentColor
		end
	end
	
	-- Update purchase button
	if self._purchaseButton then
		local btnStroke = self._purchaseButton:FindFirstChildOfClass("UIStroke")
		
		if self._isMaxed then
			self._purchaseButton.Text = "✓ MAX"
			self._purchaseButton.BackgroundColor3 = CONFIG.SlotMaxedColor
			self._purchaseButton.TextColor3 = Color3.fromRGB(30, 30, 30)
			if btnStroke then btnStroke.Color = Color3.fromRGB(180, 140, 20) end
		else
			local canAfford = self._kudos >= self._nextCost
			self._purchaseButton.Text = string.format("+1 • %s ⭐", formatNumber(self._nextCost))
			
			if canAfford then
				self._purchaseButton.BackgroundColor3 = CONFIG.ButtonColor
				self._purchaseButton.TextColor3 = CONFIG.ButtonTextColor
				if btnStroke then btnStroke.Color = Color3.fromRGB(60, 160, 60) end
			else
				self._purchaseButton.BackgroundColor3 = CONFIG.ButtonDisabledColor
				self._purchaseButton.TextColor3 = CONFIG.ButtonDisabledText
				if btnStroke then btnStroke.Color = Color3.fromRGB(50, 45, 40) end
			end
		end
	end
	
	-- Update 2D slot colors
	self:UpdateSlotColors()
end

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         UPGRADE LOGIC                                       ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

function UpgradeController:TryPurchaseUpgrade()
	if self._isPurchasing then return end
	
	if self._isMaxed then
		print("[UpgradeController] Already at max capacity!")
		return
	end
	
	if self._kudos < self._nextCost then
		print("[UpgradeController] Not enough kudos!")
		self:PlayRejectEffect()
		return
	end
	
	self._isPurchasing = true
	
	local PackagePlatformService = Knit.GetService("PackagePlatformService")
	local success, message = PackagePlatformService:RequestUpgrade()
	
	if success then
		print("[UpgradeController] Upgrade successful!")
		self:PlayUpgradeEffect()
	else
		warn("[UpgradeController] Upgrade failed: " .. tostring(message))
		self:PlayRejectEffect()
	end
	
	task.delay(0.3, function()
		self._isPurchasing = false
	end)
end

function UpgradeController:PlayUpgradeEffect()
	-- Flash the newly purchased 2D slot frame
	local newSlot = self._slotFrames[self._maxStack]
	if newSlot and newSlot.Parent then
		newSlot.BackgroundColor3 = Color3.new(1, 1, 1)  -- Flash white
		
		task.delay(0.1, function()
			if newSlot and newSlot.Parent then
				TweenService:Create(newSlot, TweenInfo.new(0.3, Enum.EasingStyle.Quad), {
					BackgroundColor3 = CONFIG.SlotFilledColor
				}):Play()
			end
		end)
	end
	
	-- Button feedback - pulse
	if self._purchaseButton then
		local originalSize = self._purchaseButton.Size
		TweenService:Create(self._purchaseButton, TweenInfo.new(0.1, Enum.EasingStyle.Back), {
			Size = UDim2.new(originalSize.X.Scale, originalSize.X.Offset + 8, originalSize.Y.Scale, originalSize.Y.Offset + 4)
		}):Play()
		task.delay(0.1, function()
			if self._purchaseButton then
				TweenService:Create(self._purchaseButton, TweenInfo.new(0.15, Enum.EasingStyle.Elastic), {
					Size = originalSize
				}):Play()
			end
		end)
	end
end

function UpgradeController:PlayRejectEffect()
	if self._isPlayingReject then return end
	self._isPlayingReject = true
	
	-- Flash the next 2D slot frame red
	local nextSlotIndex = self._maxStack + 1
	local nextSlot = self._slotFrames[nextSlotIndex]
	if nextSlot and nextSlot.Parent then
		-- Flash red
		nextSlot.BackgroundColor3 = Color3.fromRGB(255, 80, 80)
		task.delay(0.2, function()
			if nextSlot and nextSlot.Parent then
				TweenService:Create(nextSlot, TweenInfo.new(0.2), {
					BackgroundColor3 = CONFIG.SlotNextColor
				}):Play()
			end
		end)
	end
	
	-- Button shake
	if self._purchaseButton then
		local originalPos = self._purchaseButton.Position
		task.spawn(function()
			for i = 1, 3 do
				self._purchaseButton.Position = UDim2.new(originalPos.X.Scale, originalPos.X.Offset - 4, originalPos.Y.Scale, originalPos.Y.Offset)
				task.wait(0.04)
				self._purchaseButton.Position = UDim2.new(originalPos.X.Scale, originalPos.X.Offset + 4, originalPos.Y.Scale, originalPos.Y.Offset)
				task.wait(0.04)
			end
			self._purchaseButton.Position = originalPos
		end)
	end
	
	self:ShowRejectMessage()
	
	task.delay(0.5, function()
		self._isPlayingReject = false
	end)
end

function UpgradeController:ShowRejectMessage()
	local message = Instance.new("TextLabel")
	message.Name = "RejectMessage"
	message.Size = UDim2.new(0, 200, 0, 30)
	message.Position = UDim2.new(0.5, 0, 0.35, 0)
	message.AnchorPoint = Vector2.new(0.5, 0.5)
	message.BackgroundColor3 = Color3.fromRGB(180, 50, 50)
	message.BackgroundTransparency = 0.1
	message.Text = "⚠️ Need more kudos!"
	message.TextColor3 = Color3.new(1, 1, 1)
	message.TextSize = 14
	message.Font = Enum.Font.GothamBold
	message.Parent = self._screenGui
	
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = message
	
	message.BackgroundTransparency = 1
	message.TextTransparency = 1
	TweenService:Create(message, TweenInfo.new(0.15, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		BackgroundTransparency = 0.1,
		TextTransparency = 0
	}):Play()
	
	task.delay(1.2, function()
		if message and message.Parent then
			TweenService:Create(message, TweenInfo.new(0.2), {
				BackgroundTransparency = 1,
				TextTransparency = 1
			}):Play()
			task.delay(0.25, function()
				if message and message.Parent then
					message:Destroy()
				end
			end)
		end
	end)
end

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         PICKUP FAILED FEEDBACK                              ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

function UpgradeController:ShowPickupFailedMessage(text)
	local message = Instance.new("TextLabel")
	message.Name = "PickupFailedMessage"
	message.Size = UDim2.new(0, 300, 0, 40)
	message.Position = UDim2.new(0.5, 0, 0.4, 0)
	message.AnchorPoint = Vector2.new(0.5, 0.5)
	message.BackgroundColor3 = Color3.fromRGB(180, 50, 50)
	message.BackgroundTransparency = 0.15
	message.Text = text
	message.TextColor3 = Color3.new(1, 1, 1)
	message.TextSize = 20
	message.Font = Enum.Font.GothamBold
	message.Parent = self._screenGui
	
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = message
	
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(255, 100, 100)
	stroke.Thickness = 2
	stroke.Parent = message
	
	message.BackgroundTransparency = 1
	message.TextTransparency = 1
	message.Size = UDim2.new(0, 250, 0, 30)
	
	TweenService:Create(message, TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		BackgroundTransparency = 0.15,
		TextTransparency = 0,
		Size = UDim2.new(0, 300, 0, 40)
	}):Play()
	
	task.spawn(function()
		local originalPos = message.Position
		for i = 1, 3 do
			message.Position = UDim2.new(originalPos.X.Scale, originalPos.X.Offset - 5, originalPos.Y.Scale, originalPos.Y.Offset)
			task.wait(0.04)
			message.Position = UDim2.new(originalPos.X.Scale, originalPos.X.Offset + 5, originalPos.Y.Scale, originalPos.Y.Offset)
			task.wait(0.04)
		end
		message.Position = originalPos
	end)
	
	task.delay(1.5, function()
		if message and message.Parent then
			TweenService:Create(message, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
				Position = UDim2.new(0.5, 0, 0.35, 0),
				BackgroundTransparency = 1,
				TextTransparency = 1
			}):Play()
			task.delay(0.35, function()
				if message and message.Parent then
					message:Destroy()
				end
			end)
		end
	end)
end

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         REPLICA SETUP                                       ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

function UpgradeController:SetupReplicaListeners()
	-- Listen for PlayerUpgrades replica
	ReplicaController.ReplicaOfClassCreated("PlayerUpgrades", function(replica)
		print("[UpgradeController] Upgrade replica received")
		self._replica = replica
		
		-- Initialize values
		self._maxStack = replica.Data.MaxStack or 1
		self._maxCapacity = replica.Data.MaxCapacity or 20
		self._nextCost = replica.Data.NextUpgradeCost or 10
		self._isMaxed = replica.Data.IsMaxed or false
		
		self:UpdateDisplay()
		
		-- Listen for changes
		replica:ListenToChange({"MaxStack"}, function(newValue)
			self._maxStack = newValue
			self:UpdateDisplay()
		end)
		
		replica:ListenToChange({"MaxCapacity"}, function(newValue)
			self._maxCapacity = newValue
			self:UpdateDisplay()
		end)
		
		replica:ListenToChange({"NextUpgradeCost"}, function(newValue)
			self._nextCost = newValue
			self:UpdateDisplay()
		end)
		
		replica:ListenToChange({"IsMaxed"}, function(newValue)
			self._isMaxed = newValue
			self:UpdateDisplay()
		end)
		
		replica:AddCleanupTask(function()
			self._replica = nil
		end)
	end)
	
	-- Listen for PlayerKudos replica
	ReplicaController.ReplicaOfClassCreated("PlayerKudos_" .. Player.UserId, function(replica)
		print("[UpgradeController] Kudos replica connected")
		self._kudosReplica = replica
		
		self._kudos = replica.Data.Kudos or 0
		self:UpdateDisplay()
		
		replica:ListenToChange({"Kudos"}, function(newValue)
			self._kudos = newValue
			self:UpdateDisplay()
		end)
		
		replica:AddCleanupTask(function()
			self._kudosReplica = nil
		end)
	end)
	
	print("[UpgradeController] Replica listeners setup complete")
end

function UpgradeController:SetupPickupFailedListener()
	local PackagePlatformService = Knit.GetService("PackagePlatformService")
	
	PackagePlatformService.PickupFailed:Connect(function(reason, cost)
		if reason == "not_enough_kudos" then
			self:ShowPickupFailedMessage("⚠️ Need " .. cost .. " ⭐ to pick up!")
		elseif reason == "max_capacity" then
			self:ShowPickupFailedMessage("⚠️ Stack is full! Upgrade capacity.")
		end
	end)
	
	print("[UpgradeController] Pickup failed listener setup")
end

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         KNIT LIFECYCLE                                      ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

function UpgradeController:KnitInit()
	print("[UpgradeController] Initializing...")
end

function UpgradeController:KnitStart()
	print("[UpgradeController] Starting...")
	
	if not CONFIG.Enabled then
		print("[UpgradeController] Disabled by config")
		return
	end
	
	-- Request replica data
	ReplicaController.RequestData()
	
	-- Setup replica listeners
	self:SetupReplicaListeners()
	
	-- Create the UI
	self:CreateUI()
	
	-- Listen for package pickup failures
	self:SetupPickupFailedListener()
	
	print("[UpgradeController] Started!")
end

function UpgradeController:KnitStop()
	if self._updateConnection then
		self._updateConnection:Disconnect()
		self._updateConnection = nil
	end
end

return UpgradeController
