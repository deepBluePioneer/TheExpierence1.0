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
	-- 2D UI
	_slotsContainer = nil,
	_slotFrames = {},
	-- 3D Viewport
	_viewportFrame = nil,
	_worldModel = nil,
	_camera = nil,
	_avatarClone = nil,
	_slot3DParts = {},
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
	PanelWidth = 200,
	
	-- Viewport settings (avatar with 3D boxes)
	ViewportHeight = 140,  -- Smaller to fit more slots
	ViewportCameraDistance = 7,
	ViewportCameraHeight = 3.5,
	ViewportCameraFOV = 50,
	
	-- 3D Box settings (above avatar head)
	Box3DSize = Vector3.new(1.5, 1.0, 1.5),
	Box3DSpacing = 0.1,
	Box3DStartHeight = 1.2,  -- Above head
	MaxVisible3DBoxes = 8,   -- Limit 3D boxes shown
	
	-- 2D Slot settings (square boxes)
	SlotSize = 24,  -- Square size in pixels (smaller to fit 20)
	SlotSpacing = 2,
	MaxVisibleSlots = 20,  -- Show all 20 boxes
	
	-- Industrial/Logistics Color Palette
	BackgroundColor = Color3.fromRGB(25, 28, 32),
	BorderColor = Color3.fromRGB(255, 180, 0),
	
	-- Slot colors (both 2D and 3D)
	SlotFilledColor = Color3.fromRGB(180, 130, 70),      -- Cardboard brown
	SlotFilledStroke = Color3.fromRGB(140, 100, 50),
	SlotNextColor = Color3.fromRGB(255, 200, 50),        -- Safety yellow
	SlotNextStroke = Color3.fromRGB(200, 160, 40),
	SlotLockedColor = Color3.fromRGB(45, 42, 40),        -- Dark
	SlotLockedStroke = Color3.fromRGB(60, 55, 50),
	SlotMaxedColor = Color3.fromRGB(218, 165, 32),
	
	-- UI Colors
	AccentColor = Color3.fromRGB(255, 180, 0),
	TextColor = Color3.fromRGB(255, 255, 255),
	ButtonColor = Color3.fromRGB(255, 200, 50),
	ButtonTextColor = Color3.fromRGB(30, 30, 30),
	
	-- Hazard stripe
	HazardYellow = Color3.fromRGB(255, 200, 0),
	HazardBlack = Color3.fromRGB(30, 30, 30),
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
	
	-- Create slot frames (squares, from bottom to top)
	local slotsToCreate = math.min(self._maxCapacity, CONFIG.MaxVisibleSlots)
	local size = CONFIG.SlotSize  -- Square size
	
	for i = 1, slotsToCreate do
		local slotFrame = Instance.new("Frame")
		slotFrame.Name = "Slot_" .. i
		slotFrame.Size = UDim2.new(0, size, 0, size)  -- Square!
		slotFrame.BackgroundColor3 = CONFIG.SlotLockedColor
		slotFrame.BorderSizePixel = 0
		slotFrame.LayoutOrder = slotsToCreate - i + 1
		slotFrame.Parent = self._slotsContainer
		
		-- Rounded corners
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 4)
		corner.Parent = slotFrame
		
		-- Border stroke
		local stroke = Instance.new("UIStroke")
		stroke.Name = "Stroke"
		stroke.Color = CONFIG.SlotLockedStroke
		stroke.Thickness = 2
		stroke.Parent = slotFrame
		
		-- Tape stripe (horizontal)
		local tape = Instance.new("Frame")
		tape.Name = "Tape"
		tape.Size = UDim2.new(1, 4, 0, 4)
		tape.Position = UDim2.new(0, -2, 0.5, -2)
		tape.BackgroundColor3 = Color3.fromRGB(200, 180, 140)
		tape.BackgroundTransparency = 0.3
		tape.BorderSizePixel = 0
		tape.Parent = slotFrame
		
		-- Box emoji centered
		local icon = Instance.new("TextLabel")
		icon.Name = "Icon"
		icon.Size = UDim2.new(1, 0, 1, 0)
		icon.BackgroundTransparency = 1
		icon.Text = "📦"
		icon.TextSize = 14
		icon.Parent = slotFrame
		
		self._slotFrames[i] = slotFrame
	end
	
	self:UpdateSlotColors()
end

function UpgradeController:UpdateSlotColors()
	for i, slotFrame in ipairs(self._slotFrames) do
		if slotFrame then
			local stroke = slotFrame:FindFirstChild("Stroke")
			local tape = slotFrame:FindFirstChild("Tape")
			local numLabel = slotFrame:FindFirstChild("Number")
			local icon = slotFrame:FindFirstChild("Icon")
			
			if i <= self._maxStack then
				-- Owned slot - cardboard brown
				slotFrame.BackgroundColor3 = CONFIG.SlotFilledColor
				if stroke then stroke.Color = CONFIG.SlotFilledStroke end
				if tape then 
					tape.BackgroundColor3 = Color3.fromRGB(200, 180, 140)
					tape.BackgroundTransparency = 0.2
				end
				if numLabel then numLabel.TextTransparency = 0.3 end
				if icon then icon.TextTransparency = 0 end
				
			elseif i == self._maxStack + 1 and not self._isMaxed then
				-- Next purchasable - highlighted yellow
				slotFrame.BackgroundColor3 = CONFIG.SlotNextColor
				if stroke then stroke.Color = CONFIG.SlotNextStroke end
				if tape then 
					tape.BackgroundColor3 = Color3.fromRGB(255, 255, 200)
					tape.BackgroundTransparency = 0.1
				end
				if numLabel then numLabel.TextTransparency = 0 end
				if icon then icon.TextTransparency = 0 end
				
			else
				-- Locked slot - dark/faded
				slotFrame.BackgroundColor3 = CONFIG.SlotLockedColor
				if stroke then stroke.Color = CONFIG.SlotLockedStroke end
				if tape then 
					tape.BackgroundColor3 = Color3.fromRGB(80, 75, 70)
					tape.BackgroundTransparency = 0.7
				end
				if numLabel then numLabel.TextTransparency = 0.7 end
				if icon then icon.TextTransparency = 0.7 end
			end
		end
	end
end

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
	
	-- Position camera to see avatar from waist up
	self._camera.CFrame = CFrame.new(
		Vector3.new(0, CONFIG.ViewportCameraHeight, CONFIG.ViewportCameraDistance),
		Vector3.new(0, 3, 0)  -- Look at chest height
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
	-- Calculate heights (SlotSize is now a number for square boxes)
	local slotsToShow = math.min(self._maxCapacity, CONFIG.MaxVisibleSlots)
	local slotsHeight = slotsToShow * (CONFIG.SlotSize + CONFIG.SlotSpacing) + 8
	local viewportHeight = CONFIG.ViewportHeight
	local panelHeight = 8 + slotsHeight + viewportHeight + 75  -- padding + slots + viewport + bottom
	
	-- Main ScreenGui
	self._screenGui = Instance.new("ScreenGui")
	self._screenGui.Name = "UpgradeGui"
	self._screenGui.ResetOnSpawn = false
	self._screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	self._screenGui.Parent = PlayerGui
	
	-- Main panel (no header, just clean dark background)
	self._panel = Instance.new("Frame")
	self._panel.Name = "UpgradePanel"
	self._panel.Size = UDim2.new(0, CONFIG.PanelWidth, 0, panelHeight)
	self._panel.Position = CONFIG.PanelPosition
	self._panel.AnchorPoint = Vector2.new(0, 1)
	self._panel.BackgroundColor3 = CONFIG.BackgroundColor
	self._panel.Parent = self._screenGui
	
	local panelCorner = Instance.new("UICorner")
	panelCorner.CornerRadius = UDim.new(0, 8)
	panelCorner.Parent = self._panel
	
	local panelStroke = Instance.new("UIStroke")
	panelStroke.Color = CONFIG.BorderColor
	panelStroke.Thickness = 2
	panelStroke.Parent = self._panel
	
	-- Simple title at top
	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, 0, 0, 24)
	title.Position = UDim2.new(0, 0, 0, 4)
	title.BackgroundTransparency = 1
	title.Text = "📦 CARGO"
	title.TextColor3 = CONFIG.AccentColor
	title.TextSize = 14
	title.Font = Enum.Font.GothamBold
	title.Parent = self._panel
	
	-- 2D Slots container (square boxes above avatar)
	self._slotsContainer = Instance.new("Frame")
	self._slotsContainer.Name = "SlotsContainer"
	self._slotsContainer.Size = UDim2.new(1, -16, 0, slotsHeight)
	self._slotsContainer.Position = UDim2.new(0, 8, 0, 28)
	self._slotsContainer.BackgroundTransparency = 1
	self._slotsContainer.Parent = self._panel
	
	local slotsLayout = Instance.new("UIListLayout")
	slotsLayout.SortOrder = Enum.SortOrder.LayoutOrder
	slotsLayout.Padding = UDim.new(0, CONFIG.SlotSpacing)
	slotsLayout.VerticalAlignment = Enum.VerticalAlignment.Bottom
	slotsLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	slotsLayout.Parent = self._slotsContainer
	
	-- Create 2D slot frames
	self:CreateSlotFrames()
	
	-- Viewport frame (shows 3D avatar below the 2D slots)
	self._viewportFrame = Instance.new("ViewportFrame")
	self._viewportFrame.Name = "AvatarViewport"
	self._viewportFrame.Size = UDim2.new(1, -16, 0, viewportHeight)
	self._viewportFrame.Position = UDim2.new(0, 8, 0, 28 + slotsHeight)
	self._viewportFrame.BackgroundColor3 = Color3.fromRGB(15, 18, 22)
	self._viewportFrame.Parent = self._panel
	
	local vpCorner = Instance.new("UICorner")
	vpCorner.CornerRadius = UDim.new(0, 6)
	vpCorner.Parent = self._viewportFrame
	
	local vpStroke = Instance.new("UIStroke")
	vpStroke.Color = Color3.fromRGB(50, 55, 60)
	vpStroke.Thickness = 1
	vpStroke.Parent = self._viewportFrame
	
	-- Setup 3D avatar in viewport
	self:SetupAvatarViewport()
	
	-- Bottom info section
	local infoY = 28 + slotsHeight + viewportHeight + 8
	
	local infoFrame = Instance.new("Frame")
	infoFrame.Name = "InfoFrame"
	infoFrame.Size = UDim2.new(1, -16, 0, 60)
	infoFrame.Position = UDim2.new(0, 8, 0, infoY)
	infoFrame.BackgroundTransparency = 1
	infoFrame.Parent = self._panel
	
	-- Capacity label
	self._capacityLabel = Instance.new("TextLabel")
	self._capacityLabel.Size = UDim2.new(1, 0, 0, 22)
	self._capacityLabel.BackgroundTransparency = 1
	self._capacityLabel.Text = "1 / 20"
	self._capacityLabel.TextColor3 = CONFIG.AccentColor
	self._capacityLabel.TextSize = 20
	self._capacityLabel.Font = Enum.Font.GothamBold
	self._capacityLabel.Parent = infoFrame
	
	-- Purchase button
	self._purchaseButton = Instance.new("TextButton")
	self._purchaseButton.Name = "PurchaseButton"
	self._purchaseButton.Size = UDim2.new(1, 0, 0, 32)
	self._purchaseButton.Position = UDim2.new(0, 0, 0, 26)
	self._purchaseButton.BackgroundColor3 = CONFIG.ButtonColor
	self._purchaseButton.Text = "+1 📦 • 10 ⭐"
	self._purchaseButton.TextColor3 = CONFIG.ButtonTextColor
	self._purchaseButton.TextSize = 15
	self._purchaseButton.Font = Enum.Font.GothamBold
	self._purchaseButton.AutoButtonColor = false
	self._purchaseButton.Parent = infoFrame
	
	local btnCorner = Instance.new("UICorner")
	btnCorner.CornerRadius = UDim.new(0, 4)
	btnCorner.Parent = self._purchaseButton
	
	local btnStroke = Instance.new("UIStroke")
	btnStroke.Color = Color3.fromRGB(200, 160, 0)
	btnStroke.Thickness = 1
	btnStroke.Parent = self._purchaseButton
	
	self._purchaseButton.MouseEnter:Connect(function()
		if not self._isMaxed and self._kudos >= self._nextCost then
			self._purchaseButton.BackgroundColor3 = Color3.fromRGB(255, 220, 80)
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
	-- Update capacity label (digital counter style)
	if self._capacityLabel then
		self._capacityLabel.Text = string.format("%d / %d", self._maxStack, self._maxCapacity)
	end
	
	-- Update purchase button
	if self._purchaseButton then
		if self._isMaxed then
			self._purchaseButton.Text = "✓ MAX CAPACITY"
			self._purchaseButton.BackgroundColor3 = CONFIG.SlotMaxedColor
			self._purchaseButton.TextColor3 = Color3.fromRGB(255, 255, 255)
		else
			local canAfford = self._kudos >= self._nextCost
			self._purchaseButton.Text = string.format("+1 📦 • %s ⭐", formatNumber(self._nextCost))
			
			if canAfford then
				self._purchaseButton.BackgroundColor3 = CONFIG.ButtonColor
				self._purchaseButton.TextColor3 = CONFIG.ButtonTextColor
			else
				self._purchaseButton.BackgroundColor3 = Color3.fromRGB(60, 55, 50)
				self._purchaseButton.TextColor3 = Color3.fromRGB(120, 115, 110)
			end
		end
	end
	
	-- Update 3D slot colors
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
	-- Flash the newly purchased slot frame (2D)
	local newSlot = self._slotFrames[self._maxStack]
	if newSlot then
		local originalColor = CONFIG.SlotFilledColor
		newSlot.BackgroundColor3 = Color3.new(1, 1, 1)
		
		TweenService:Create(newSlot, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			BackgroundColor3 = originalColor
		}):Play()
	end
	
	-- Button feedback
	if self._purchaseButton then
		TweenService:Create(self._purchaseButton, TweenInfo.new(0.1), {
			Size = UDim2.new(1, 10, 0, 44)
		}):Play()
		task.delay(0.1, function()
			TweenService:Create(self._purchaseButton, TweenInfo.new(0.15), {
				Size = UDim2.new(1, 0, 0, 36)
			}):Play()
		end)
	end
end

function UpgradeController:PlayRejectEffect()
	if self._isPlayingReject then return end
	self._isPlayingReject = true
	
	-- Shake the next slot frame (2D)
	local nextSlotIndex = self._maxStack + 1
	local nextSlot = self._slotFrames[nextSlotIndex]
	if nextSlot then
		local originalColor = nextSlot.BackgroundColor3
		
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
