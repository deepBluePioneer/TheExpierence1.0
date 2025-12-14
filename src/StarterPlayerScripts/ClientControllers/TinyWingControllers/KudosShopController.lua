--[[
	KudosShopController
	
	Client-side UI for purchasing Kudos packs with Robux.
	Uses MarketplaceService to prompt purchases.
]]

local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local Knit = require(Packages.Knit)

local Player = Players.LocalPlayer
local PlayerGui = Player:WaitForChild("PlayerGui")

local KudosShopController = Knit.CreateController {
	Name = "KudosShopController",
	_screenGui = nil,
	_shopButton = nil,
	_shopPanel = nil,
	_isOpen = false,
	_packs = {},
}

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         CONFIG                                              ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

local CONFIG = {
	-- Button position (top right area)
	ButtonPosition = UDim2.new(1, -160, 0, 100),
	ButtonSize = UDim2.new(0, 140, 0, 40),
	
	-- Shop panel
	PanelSize = UDim2.new(0, 400, 0, 450),
	
	-- Colors
	BackgroundColor = Color3.fromRGB(20, 22, 28),
	AccentColor = Color3.fromRGB(255, 200, 50),      -- Gold/yellow
	SecondaryColor = Color3.fromRGB(100, 180, 255),  -- Blue
	TextColor = Color3.fromRGB(255, 255, 255),
	CardColor = Color3.fromRGB(30, 34, 42),
	BestValueColor = Color3.fromRGB(255, 180, 0),
}

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         UI CREATION                                         ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

function KudosShopController:CreateUI()
	-- Main ScreenGui
	self._screenGui = Instance.new("ScreenGui")
	self._screenGui.Name = "KudosShopGui"
	self._screenGui.ResetOnSpawn = false
	self._screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	self._screenGui.Parent = PlayerGui
	
	-- Shop button
	self._shopButton = Instance.new("TextButton")
	self._shopButton.Name = "ShopButton"
	self._shopButton.Size = CONFIG.ButtonSize
	self._shopButton.Position = CONFIG.ButtonPosition
	self._shopButton.AnchorPoint = Vector2.new(1, 0)
	self._shopButton.BackgroundColor3 = CONFIG.AccentColor
	self._shopButton.Text = "⭐ KUDOS SHOP"
	self._shopButton.TextColor3 = Color3.fromRGB(30, 30, 30)
	self._shopButton.TextSize = 14
	self._shopButton.Font = Enum.Font.GothamBold
	self._shopButton.AutoButtonColor = false
	self._shopButton.Parent = self._screenGui
	
	local btnCorner = Instance.new("UICorner")
	btnCorner.CornerRadius = UDim.new(0, 8)
	btnCorner.Parent = self._shopButton
	
	local btnStroke = Instance.new("UIStroke")
	btnStroke.Color = Color3.fromRGB(200, 160, 0)
	btnStroke.Thickness = 2
	btnStroke.Parent = self._shopButton
	
	-- Button hover effects
	self._shopButton.MouseEnter:Connect(function()
		TweenService:Create(self._shopButton, TweenInfo.new(0.15), {
			BackgroundColor3 = Color3.fromRGB(255, 220, 80)
		}):Play()
	end)
	
	self._shopButton.MouseLeave:Connect(function()
		TweenService:Create(self._shopButton, TweenInfo.new(0.15), {
			BackgroundColor3 = CONFIG.AccentColor
		}):Play()
	end)
	
	self._shopButton.MouseButton1Click:Connect(function()
		self:ToggleShop()
	end)
	
	-- Shop panel (initially hidden)
	self:CreateShopPanel()
	
	print("[KudosShopController] UI created")
end

function KudosShopController:CreateShopPanel()
	-- Main panel
	self._shopPanel = Instance.new("Frame")
	self._shopPanel.Name = "ShopPanel"
	self._shopPanel.Size = CONFIG.PanelSize
	self._shopPanel.Position = UDim2.new(0.5, 0, 0.5, 0)
	self._shopPanel.AnchorPoint = Vector2.new(0.5, 0.5)
	self._shopPanel.BackgroundColor3 = CONFIG.BackgroundColor
	self._shopPanel.Visible = false
	self._shopPanel.Parent = self._screenGui
	
	local panelCorner = Instance.new("UICorner")
	panelCorner.CornerRadius = UDim.new(0, 12)
	panelCorner.Parent = self._shopPanel
	
	local panelStroke = Instance.new("UIStroke")
	panelStroke.Color = CONFIG.AccentColor
	panelStroke.Thickness = 2
	panelStroke.Parent = self._shopPanel
	
	-- Header
	local header = Instance.new("Frame")
	header.Name = "Header"
	header.Size = UDim2.new(1, 0, 0, 50)
	header.BackgroundColor3 = Color3.fromRGB(25, 28, 35)
	header.BorderSizePixel = 0
	header.Parent = self._shopPanel
	
	local headerCorner = Instance.new("UICorner")
	headerCorner.CornerRadius = UDim.new(0, 12)
	headerCorner.Parent = header
	
	-- Fix bottom corners of header
	local headerFix = Instance.new("Frame")
	headerFix.Size = UDim2.new(1, 0, 0, 15)
	headerFix.Position = UDim2.new(0, 0, 1, -15)
	headerFix.BackgroundColor3 = Color3.fromRGB(25, 28, 35)
	headerFix.BorderSizePixel = 0
	headerFix.Parent = header
	
	-- Title
	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, -60, 1, 0)
	title.Position = UDim2.new(0, 15, 0, 0)
	title.BackgroundTransparency = 1
	title.Text = "⭐ KUDOS SHOP"
	title.TextColor3 = CONFIG.AccentColor
	title.TextSize = 22
	title.Font = Enum.Font.GothamBold
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Parent = header
	
	-- Close button
	local closeBtn = Instance.new("TextButton")
	closeBtn.Name = "CloseButton"
	closeBtn.Size = UDim2.new(0, 36, 0, 36)
	closeBtn.Position = UDim2.new(1, -43, 0.5, -18)
	closeBtn.BackgroundColor3 = Color3.fromRGB(180, 60, 60)
	closeBtn.Text = "✕"
	closeBtn.TextColor3 = Color3.new(1, 1, 1)
	closeBtn.TextSize = 18
	closeBtn.Font = Enum.Font.GothamBold
	closeBtn.Parent = header
	
	local closeBtnCorner = Instance.new("UICorner")
	closeBtnCorner.CornerRadius = UDim.new(0, 6)
	closeBtnCorner.Parent = closeBtn
	
	closeBtn.MouseButton1Click:Connect(function()
		self:CloseShop()
	end)
	
	-- Subtitle
	local subtitle = Instance.new("TextLabel")
	subtitle.Size = UDim2.new(1, -30, 0, 24)
	subtitle.Position = UDim2.new(0, 15, 0, 55)
	subtitle.BackgroundTransparency = 1
	subtitle.Text = "Purchase Kudos to upgrade your cargo capacity!"
	subtitle.TextColor3 = Color3.fromRGB(150, 150, 160)
	subtitle.TextSize = 13
	subtitle.Font = Enum.Font.Gotham
	subtitle.TextXAlignment = Enum.TextXAlignment.Left
	subtitle.Parent = self._shopPanel
	
	-- Packs container
	local packsContainer = Instance.new("ScrollingFrame")
	packsContainer.Name = "PacksContainer"
	packsContainer.Size = UDim2.new(1, -30, 1, -95)
	packsContainer.Position = UDim2.new(0, 15, 0, 85)
	packsContainer.BackgroundTransparency = 1
	packsContainer.ScrollBarThickness = 4
	packsContainer.ScrollBarImageColor3 = CONFIG.AccentColor
	packsContainer.CanvasSize = UDim2.new(0, 0, 0, 0)
	packsContainer.AutomaticCanvasSize = Enum.AutomaticSize.Y
	packsContainer.Parent = self._shopPanel
	
	local packsLayout = Instance.new("UIListLayout")
	packsLayout.SortOrder = Enum.SortOrder.LayoutOrder
	packsLayout.Padding = UDim.new(0, 10)
	packsLayout.Parent = packsContainer
	
	-- Create pack cards
	self:CreatePackCards(packsContainer)
end

function KudosShopController:CreatePackCards(container)
	print(string.format("[KudosShopController] Creating pack cards, %d packs available", #self._packs))
	
	if #self._packs == 0 then
		warn("[KudosShopController] No packs to display!")
		
		-- Create a message if no packs
		local noPacksLabel = Instance.new("TextLabel")
		noPacksLabel.Size = UDim2.new(1, -20, 0, 60)
		noPacksLabel.Position = UDim2.new(0, 10, 0, 10)
		noPacksLabel.BackgroundTransparency = 1
		noPacksLabel.Text = "⚠️ Shop loading...\nPlease try again in a moment"
		noPacksLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
		noPacksLabel.TextSize = 14
		noPacksLabel.Font = Enum.Font.Gotham
		noPacksLabel.TextWrapped = true
		noPacksLabel.Parent = container
		return
	end
	
	for i, pack in ipairs(self._packs) do
		print(string.format("[KudosShopController] Creating card for: %s (ID: %d)", pack.Name, pack.ProductId))
		local card = Instance.new("Frame")
		card.Name = "Pack_" .. i
		card.Size = UDim2.new(1, -8, 0, 90)
		card.BackgroundColor3 = CONFIG.CardColor
		card.LayoutOrder = i
		card.Parent = container
		
		local cardCorner = Instance.new("UICorner")
		cardCorner.CornerRadius = UDim.new(0, 8)
		cardCorner.Parent = card
		
		-- Best value highlight
		if pack.BestValue then
			local cardStroke = Instance.new("UIStroke")
			cardStroke.Color = CONFIG.BestValueColor
			cardStroke.Thickness = 2
			cardStroke.Parent = card
			
			local bestLabel = Instance.new("TextLabel")
			bestLabel.Size = UDim2.new(0, 80, 0, 20)
			bestLabel.Position = UDim2.new(1, -85, 0, -10)
			bestLabel.BackgroundColor3 = CONFIG.BestValueColor
			bestLabel.Text = "BEST VALUE"
			bestLabel.TextColor3 = Color3.fromRGB(30, 30, 30)
			bestLabel.TextSize = 10
			bestLabel.Font = Enum.Font.GothamBold
			bestLabel.Parent = card
			
			local bestCorner = Instance.new("UICorner")
			bestCorner.CornerRadius = UDim.new(0, 4)
			bestCorner.Parent = bestLabel
		end
		
		-- Icon
		local icon = Instance.new("TextLabel")
		icon.Size = UDim2.new(0, 50, 0, 50)
		icon.Position = UDim2.new(0, 12, 0.5, -25)
		icon.BackgroundTransparency = 1
		icon.Text = pack.Icon
		icon.TextSize = 36
		icon.Parent = card
		
		-- Pack name
		local name = Instance.new("TextLabel")
		name.Size = UDim2.new(0, 150, 0, 24)
		name.Position = UDim2.new(0, 70, 0, 12)
		name.BackgroundTransparency = 1
		name.Text = pack.Name
		name.TextColor3 = CONFIG.TextColor
		name.TextSize = 16
		name.Font = Enum.Font.GothamBold
		name.TextXAlignment = Enum.TextXAlignment.Left
		name.Parent = card
		
		-- Kudos amount
		local amount = Instance.new("TextLabel")
		amount.Size = UDim2.new(0, 150, 0, 22)
		amount.Position = UDim2.new(0, 70, 0, 38)
		amount.BackgroundTransparency = 1
		amount.Text = string.format("⭐ %s Kudos", self:FormatNumber(pack.KudosAmount))
		amount.TextColor3 = CONFIG.AccentColor
		amount.TextSize = 14
		amount.Font = Enum.Font.GothamBold
		amount.TextXAlignment = Enum.TextXAlignment.Left
		amount.Parent = card
		
		-- Value per robux
		local valuePerRobux = pack.KudosAmount / pack.RobuxPrice
		local value = Instance.new("TextLabel")
		value.Size = UDim2.new(0, 150, 0, 18)
		value.Position = UDim2.new(0, 70, 0, 60)
		value.BackgroundTransparency = 1
		value.Text = string.format("%.1f kudos per R$", valuePerRobux)
		value.TextColor3 = Color3.fromRGB(120, 120, 130)
		value.TextSize = 11
		value.Font = Enum.Font.Gotham
		value.TextXAlignment = Enum.TextXAlignment.Left
		value.Parent = card
		
		-- Buy button
		local buyBtn = Instance.new("TextButton")
		buyBtn.Name = "BuyButton"
		buyBtn.Size = UDim2.new(0, 90, 0, 40)
		buyBtn.Position = UDim2.new(1, -100, 0.5, -20)
		buyBtn.BackgroundColor3 = Color3.fromRGB(0, 180, 100)
		buyBtn.Text = string.format("R$ %d", pack.RobuxPrice)
		buyBtn.TextColor3 = Color3.new(1, 1, 1)
		buyBtn.TextSize = 14
		buyBtn.Font = Enum.Font.GothamBold
		buyBtn.AutoButtonColor = false
		buyBtn.Parent = card
		
		local buyBtnCorner = Instance.new("UICorner")
		buyBtnCorner.CornerRadius = UDim.new(0, 6)
		buyBtnCorner.Parent = buyBtn
		
		-- Store product ID on button
		buyBtn:SetAttribute("ProductId", pack.ProductId)
		
		-- Buy button interactions
		buyBtn.MouseEnter:Connect(function()
			TweenService:Create(buyBtn, TweenInfo.new(0.1), {
				BackgroundColor3 = Color3.fromRGB(0, 200, 120)
			}):Play()
		end)
		
		buyBtn.MouseLeave:Connect(function()
			TweenService:Create(buyBtn, TweenInfo.new(0.1), {
				BackgroundColor3 = Color3.fromRGB(0, 180, 100)
			}):Play()
		end)
		
		buyBtn.MouseButton1Click:Connect(function()
			self:PurchasePack(pack)
		end)
	end
end

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         SHOP FUNCTIONS                                      ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

function KudosShopController:ToggleShop()
	if self._isOpen then
		self:CloseShop()
	else
		self:OpenShop()
	end
end

function KudosShopController:OpenShop()
	if self._isOpen then return end
	self._isOpen = true
	
	self._shopPanel.Visible = true
	self._shopPanel.Size = UDim2.new(0, 0, 0, 0)
	
	TweenService:Create(self._shopPanel, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Size = CONFIG.PanelSize
	}):Play()
end

function KudosShopController:CloseShop()
	if not self._isOpen then return end
	self._isOpen = false
	
	local tween = TweenService:Create(self._shopPanel, TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		Size = UDim2.new(0, 0, 0, 0)
	})
	
	tween.Completed:Connect(function()
		if not self._isOpen then
			self._shopPanel.Visible = false
		end
	end)
	
	tween:Play()
end

function KudosShopController:PurchasePack(pack)
	if pack.ProductId == 0 then
		warn("[KudosShopController] Product not configured - ID is 0")
		self:ShowMessage("Shop not configured yet!", Color3.fromRGB(255, 100, 100))
		return
	end
	
	print(string.format("[KudosShopController] Initiating purchase: %s (Product ID: %d)", pack.Name, pack.ProductId))
	
	-- Prompt the purchase via MarketplaceService
	local success, err = pcall(function()
		MarketplaceService:PromptProductPurchase(Player, pack.ProductId)
	end)
	
	if not success then
		warn("[KudosShopController] Failed to prompt purchase: " .. tostring(err))
		self:ShowMessage("Purchase failed!", Color3.fromRGB(255, 100, 100))
	end
end

function KudosShopController:ShowMessage(text, color)
	-- Create floating message
	local message = Instance.new("TextLabel")
	message.Size = UDim2.new(0, 300, 0, 40)
	message.Position = UDim2.new(0.5, 0, 0.3, 0)
	message.AnchorPoint = Vector2.new(0.5, 0.5)
	message.BackgroundColor3 = color or CONFIG.AccentColor
	message.BackgroundTransparency = 0.1
	message.Text = text
	message.TextColor3 = Color3.new(1, 1, 1)
	message.TextSize = 16
	message.Font = Enum.Font.GothamBold
	message.Parent = self._screenGui
	
	local msgCorner = Instance.new("UICorner")
	msgCorner.CornerRadius = UDim.new(0, 8)
	msgCorner.Parent = message
	
	-- Animate out
	task.delay(2, function()
		TweenService:Create(message, TweenInfo.new(0.3), {
			Position = UDim2.new(0.5, 0, 0.25, 0),
			BackgroundTransparency = 1,
			TextTransparency = 1
		}):Play()
		
		task.delay(0.3, function()
			message:Destroy()
		end)
	end)
end

function KudosShopController:FormatNumber(num)
	if num >= 1000 then
		return string.format("%.1fK", num / 1000)
	end
	return tostring(num)
end

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         LIFECYCLE                                           ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

function KudosShopController:KnitInit()
	print("[KudosShopController] Initializing...")
end

function KudosShopController:KnitStart()
	print("[KudosShopController] Starting...")
	
	-- Get packs from server
	local KudosShopService = Knit.GetService("KudosShopService")
	
	print("[KudosShopController] Calling GetKudosPacks...")
	local success, result = pcall(function()
		return KudosShopService:GetKudosPacks()
	end)
	
	print(string.format("[KudosShopController] pcall success: %s, result type: %s", tostring(success), typeof(result)))
	
	if success then
		if result and typeof(result) == "table" then
			self._packs = result
			print(string.format("[KudosShopController] Loaded %d kudos packs from server", #result))
			for i, pack in ipairs(result) do
				print(string.format("  Pack %d: %s - %d kudos (ProductId: %d)", i, pack.Name, pack.KudosAmount, pack.ProductId))
			end
		else
			warn(string.format("[KudosShopController] Unexpected result: %s", tostring(result)))
			self._packs = {}
		end
	else
		warn(string.format("[KudosShopController] pcall failed: %s", tostring(result)))
	end
	
	-- Use fallback if no packs loaded
	if #self._packs == 0 then
		warn("[KudosShopController] Using fallback defaults")
		self._packs = {
			{ Name = "Starter Pack", ProductId = 3479973967, KudosAmount = 100, RobuxPrice = 25, Icon = "💰", BestValue = false },
			{ Name = "Value Pack", ProductId = 3479974190, KudosAmount = 500, RobuxPrice = 99, Icon = "💎", BestValue = false },
			{ Name = "Super Pack", ProductId = 3479974347, KudosAmount = 1200, RobuxPrice = 199, Icon = "🌟", BestValue = true },
			{ Name = "Mega Pack", ProductId = 3479974541, KudosAmount = 3000, RobuxPrice = 399, Icon = "👑", BestValue = false },
		}
	end
	
	-- Create UI
	self:CreateUI()
	
	-- Listen for purchase completion
	KudosShopService.PurchaseComplete:Connect(function(packName, kudosAmount)
		-- Skip animation for shop purchases - just update the counter
		local KudosController = Knit.GetController("KudosController")
		if KudosController then
			KudosController:SkipNextAnimation()
		end
		
		self:ShowMessage(string.format("✓ +%d Kudos!", kudosAmount), Color3.fromRGB(0, 200, 100))
		self:CloseShop()
	end)
	
	KudosShopService.PurchaseFailed:Connect(function(reason)
		self:ShowMessage("Purchase failed: " .. (reason or "Unknown error"), Color3.fromRGB(255, 100, 100))
	end)
	
	print("[KudosShopController] Started!")
end

return KudosShopController

