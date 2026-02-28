local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Packages = ReplicatedStorage.Packages
local Knit = require(Packages.Knit)
local Trove = require(Packages.Trove)

local CustomPackages = ReplicatedStorage.CustomPackages
local Fusion = require(CustomPackages.FusionRoot.Fusion)
local ReplicaController = require(CustomPackages.Replica.ReplicaController)

local New = Fusion.New
local Value = Fusion.Value
local Computed = Fusion.Computed
local Children = Fusion.Children
local ForPairs = Fusion.ForPairs
local Spring = Fusion.Spring
local OnEvent = Fusion.OnEvent

local ShopConfig = require(ReplicatedStorage.Source.ShopConfig)

local LocalPlayer = Players.LocalPlayer

local HubShopController = Knit.CreateController {
	Name = "HubShopController",
}

local _trove = Trove.new()
local _screenGui = nil
local _shopService = nil

local isOpen = Value(false)
local activeCategory = Value(ShopConfig.categories[1])
local playerCurrency = Value(0)
local playerLevel = Value(1)
local ownedItems = Value({})
local purchasingItemId = Value(nil)

local isMobile = UserInputService.TouchEnabled

local function getItemsByCategory(category)
	local result = {}
	for _, item in ipairs(ShopConfig.items) do
		if item.category == category then
			table.insert(result, item)
		end
	end
	return result
end

local function createCategoryTab(category)
	local displayName = ShopConfig.categoryDisplayNames[category] or category
	local isActive = Computed(function()
		return activeCategory:get() == category
	end)

	local bgColor = Computed(function()
		return isActive:get() and Color3.fromRGB(80, 200, 255) or Color3.fromRGB(60, 60, 80)
	end)

	return New "TextButton" {
		Name = "Tab_" .. category,
		Size = UDim2.fromScale(1 / #ShopConfig.categories, 1),
		BackgroundColor3 = bgColor,
		Text = displayName,
		TextColor3 = Color3.fromRGB(255, 255, 255),
		Font = Enum.Font.GothamBold,
		TextScaled = true,

		[Children] = {
			New "UICorner" {
				CornerRadius = UDim.new(0.3, 0),
			},
			New "UIPadding" {
				PaddingLeft = UDim.new(0.05, 0),
				PaddingRight = UDim.new(0.05, 0),
			},
		},

		[OnEvent "Activated"] = function()
			activeCategory:set(category)
		end,
	}
end

local function createItemCard(item)
	local owned = Computed(function()
		local ownList = ownedItems:get()
		return ownList[item.id] == true
	end)

	local canAfford = Computed(function()
		return playerCurrency:get() >= item.price
	end)

	local meetsLevel = Computed(function()
		return playerLevel:get() >= (item.levelRequired or 0)
	end)

	local isPurchasing = Computed(function()
		return purchasingItemId:get() == item.id
	end)

	local buttonText = Computed(function()
		if owned:get() then return "Owned" end
		if isPurchasing:get() then return "..." end
		if not meetsLevel:get() then return "Lv." .. (item.levelRequired or 0) end
		if not canAfford:get() then return tostring(item.price) end
		return tostring(item.price)
	end)

	local buttonColor = Computed(function()
		if owned:get() then return Color3.fromRGB(60, 160, 60) end
		if not meetsLevel:get() then return Color3.fromRGB(80, 80, 80) end
		if not canAfford:get() then return Color3.fromRGB(120, 50, 50) end
		return Color3.fromRGB(60, 140, 220)
	end)

	local buttonEnabled = Computed(function()
		return not owned:get() and meetsLevel:get() and canAfford:get() and not isPurchasing:get()
	end)

	return New "Frame" {
		Name = "Item_" .. item.id,
		Size = UDim2.fromScale(0.3, 0.45),
		BackgroundColor3 = Color3.fromRGB(40, 40, 60),
		BackgroundTransparency = 0.3,

		[Children] = {
			New "UICorner" {
				CornerRadius = UDim.new(0.06, 0),
			},

			New "TextLabel" {
				Name = "ItemName",
				Position = UDim2.fromScale(0.05, 0.02),
				Size = UDim2.fromScale(0.9, 0.25),
				BackgroundTransparency = 1,
				Text = item.displayName,
				TextColor3 = Color3.fromRGB(255, 255, 255),
				Font = Enum.Font.GothamBold,
				TextScaled = true,
				TextXAlignment = Enum.TextXAlignment.Left,
			},

			New "TextLabel" {
				Name = "ItemPrice",
				Position = UDim2.fromScale(0.05, 0.3),
				Size = UDim2.fromScale(0.9, 0.2),
				BackgroundTransparency = 1,
				Text = Computed(function()
					if owned:get() then return "Owned" end
					return "Cost: " .. item.price
				end),
				TextColor3 = Computed(function()
					if owned:get() then return Color3.fromRGB(100, 220, 100) end
					if canAfford:get() then return Color3.fromRGB(255, 215, 0) end
					return Color3.fromRGB(200, 80, 80)
				end),
				Font = Enum.Font.Gotham,
				TextScaled = true,
				TextXAlignment = Enum.TextXAlignment.Left,
			},

			New "TextButton" {
				Name = "BuyButton",
				AnchorPoint = Vector2.new(0.5, 1),
				Position = UDim2.fromScale(0.5, 0.95),
				Size = UDim2.fromScale(0.8, 0.22),
				BackgroundColor3 = buttonColor,
				Text = buttonText,
				TextColor3 = Color3.fromRGB(255, 255, 255),
				Font = Enum.Font.GothamBold,
				TextScaled = true,
				AutoButtonColor = buttonEnabled,

				[Children] = {
					New "UICorner" {
						CornerRadius = UDim.new(0.3, 0),
					},
				},

				[OnEvent "Activated"] = function()
					if not buttonEnabled:get() then return end
					purchasingItemId:set(item.id)

					task.spawn(function()
						local ok, reason = _shopService:Purchase(item.id)
						purchasingItemId:set(nil)

						if not ok then
							warn("[HubShopController] Purchase failed: " .. tostring(reason))
						end
					end)
				end,
			},
		},
	}
end

local function createShopUI()
	local categoryTabs = {}
	for _, cat in ipairs(ShopConfig.categories) do
		table.insert(categoryTabs, createCategoryTab(cat))
	end

	local itemsFrame = Computed(function()
		local cat = activeCategory:get()
		local items = getItemsByCategory(cat)
		local cards = {}
		for _, item in ipairs(items) do
			table.insert(cards, createItemCard(item))
		end
		return cards
	end)

	local panelSize = isMobile and UDim2.fromScale(1, 1) or UDim2.fromScale(0.6, 0.7)

	_screenGui = New "ScreenGui" {
		Parent = LocalPlayer:WaitForChild("PlayerGui"),
		Name = "HubShopUI",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Enabled = isOpen,

		[Children] = {
			-- Dimmed backdrop
			New "TextButton" {
				Name = "Backdrop",
				Size = UDim2.fromScale(1, 1),
				BackgroundColor3 = Color3.fromRGB(0, 0, 0),
				BackgroundTransparency = 0.5,
				Text = "",
				AutoButtonColor = false,
				ZIndex = 1,

				[OnEvent "Activated"] = function()
					HubShopController:Close()
				end,
			},

			-- Main panel
			New "Frame" {
				Name = "ShopPanel",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = panelSize,
				BackgroundColor3 = Color3.fromRGB(25, 25, 40),
				BackgroundTransparency = 0.1,
				ZIndex = 2,

				[Children] = {
					New "UICorner" {
						CornerRadius = UDim.new(0.02, 0),
					},

					-- Title
					New "TextLabel" {
						Name = "Title",
						Position = UDim2.fromScale(0.02, 0.01),
						Size = UDim2.fromScale(0.6, 0.08),
						BackgroundTransparency = 1,
						Text = "Shop",
						TextColor3 = Color3.fromRGB(255, 255, 255),
						Font = Enum.Font.GothamBold,
						TextScaled = true,
						TextXAlignment = Enum.TextXAlignment.Left,
						ZIndex = 3,
					},

					-- Close button
					New "TextButton" {
						Name = "CloseButton",
						AnchorPoint = Vector2.new(1, 0),
						Position = UDim2.fromScale(0.98, 0.01),
						Size = UDim2.fromScale(0.06, 0.06),
						SizeConstraint = Enum.SizeConstraint.RelativeYY,
						BackgroundColor3 = Color3.fromRGB(200, 60, 60),
						Text = "X",
						TextColor3 = Color3.fromRGB(255, 255, 255),
						Font = Enum.Font.GothamBold,
						TextScaled = true,
						ZIndex = 3,

						[Children] = {
							New "UICorner" {
								CornerRadius = UDim.new(0.5, 0),
							},
							New "UIAspectRatioConstraint" {
								AspectRatio = 1,
							},
						},

						[OnEvent "Activated"] = function()
							HubShopController:Close()
						end,
					},

					-- Category tabs
					New "Frame" {
						Name = "CategoryTabs",
						Position = UDim2.fromScale(0.02, 0.1),
						Size = UDim2.fromScale(0.96, 0.08),
						BackgroundTransparency = 1,
						ZIndex = 3,

						[Children] = {
							New "UIListLayout" {
								FillDirection = Enum.FillDirection.Horizontal,
								HorizontalAlignment = Enum.HorizontalAlignment.Left,
								Padding = UDim.new(0.01, 0),
							},
							table.unpack(categoryTabs),
						},
					},

					-- Items scroll frame
					New "ScrollingFrame" {
						Name = "ItemsScroll",
						Position = UDim2.fromScale(0.02, 0.2),
						Size = UDim2.fromScale(0.96, 0.78),
						BackgroundTransparency = 1,
						ScrollBarThickness = 4,
						CanvasSize = UDim2.fromScale(0, 0),
						AutomaticCanvasSize = Enum.AutomaticSize.Y,
						ScrollingDirection = Enum.ScrollingDirection.Y,
						ZIndex = 3,

						[Children] = {
							New "UIGridLayout" {
								CellSize = UDim2.fromScale(0.3, 0.35),
								CellPadding = UDim2.fromScale(0.025, 0.02),
								FillDirection = Enum.FillDirection.Horizontal,
								SortOrder = Enum.SortOrder.LayoutOrder,
							},
							Computed(function()
								local cat = activeCategory:get()
								local items = getItemsByCategory(cat)
								local cards = {}
								for _, item in ipairs(items) do
									cards[item.id] = createItemCard(item)
								end
								return cards
							end),
						},
					},
				},
			},
		},
	}

	_trove:Add(_screenGui)
end

local function bindReplica(replica)
	local function updateFromData(data)
		playerCurrency:set(data.currency or 0)
		playerLevel:set(data.level or 1)

		local ownMap = {}
		for _, trailId in ipairs(data.ownedTrails or {}) do
			ownMap[trailId] = true
		end
		for _, titleId in ipairs(data.ownedTitles or {}) do
			ownMap[titleId] = true
		end
		ownedItems:set(ownMap)
	end

	updateFromData(replica.Data)

	_trove:Add(replica:ListenToChange({ "currency" }, function(newVal)
		playerCurrency:set(newVal)
	end))

	_trove:Add(replica:ListenToChange({ "level" }, function(newVal)
		playerLevel:set(newVal)
	end))

	_trove:Add(replica:ListenToChange({ "ownedTrails" }, function()
		updateFromData(replica.Data)
	end))

	_trove:Add(replica:ListenToChange({ "ownedTitles" }, function()
		updateFromData(replica.Data)
	end))
end

function HubShopController:KnitInit()
end

function HubShopController:KnitStart()
	_shopService = Knit.GetService("HubShopService")

	createShopUI()

	ReplicaController.ReplicaOfClassCreated("PlayerProfile", function(replica)
		if replica.Tags.Player == LocalPlayer then
			bindReplica(replica)
		end
	end)
end

function HubShopController:Open()
	local panelManager = Knit.GetController("HubPanelManager")
	if panelManager then
		panelManager:OpenPanel("shop")
	else
		isOpen:set(true)
	end
end

function HubShopController:Close()
	local panelManager = Knit.GetController("HubPanelManager")
	if panelManager then
		panelManager:ClosePanel()
	else
		isOpen:set(false)
	end
end

function HubShopController:SetOpen(open)
	isOpen:set(open)
end

function HubShopController:IsOpen()
	return isOpen:get()
end

function HubShopController:Destroy()
	_trove:Destroy()
end

return HubShopController
