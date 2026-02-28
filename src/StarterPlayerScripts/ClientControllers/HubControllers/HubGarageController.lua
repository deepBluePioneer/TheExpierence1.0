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
local Spring = Fusion.Spring
local OnEvent = Fusion.OnEvent

local MachinesConfig = require(ReplicatedStorage.Source.MachinesConfig)

local LocalPlayer = Players.LocalPlayer

local HubGarageController = Knit.CreateController {
	Name = "HubGarageController",
}

local _trove = Trove.new()
local _screenGui = nil
local _garageService = nil
local _shopService = nil

local isOpen = Value(false)
local selectedMachineId = Value(MachinesConfig.defaultMachineId)
local ownedMachines = Value({})
local playerCurrency = Value(0)
local playerLevel = Value(1)
local isSelecting = Value(false)

local isMobile = UserInputService.TouchEnabled

local STAT_NAMES = { "topSpeed", "acceleration", "handling", "weight", "boostPower", "maxHealth" }
local STAT_DISPLAY = {
	topSpeed = "Speed",
	acceleration = "Accel",
	handling = "Handling",
	weight = "Weight",
	boostPower = "Boost",
	maxHealth = "Health",
}
local STAT_COLORS = {
	topSpeed = Color3.fromRGB(80, 160, 255),
	acceleration = Color3.fromRGB(255, 160, 50),
	handling = Color3.fromRGB(80, 220, 100),
	weight = Color3.fromRGB(200, 80, 80),
	boostPower = Color3.fromRGB(255, 220, 50),
	maxHealth = Color3.fromRGB(220, 60, 80),
}
local STAT_MAX = {
	topSpeed = 150,
	acceleration = 10,
	handling = 10,
	weight = 10,
	boostPower = 60,
	maxHealth = 150,
}

local function createStatBar(statName, statValue)
	local maxVal = STAT_MAX[statName] or 100
	local fillFraction = Computed(function()
		return math.clamp(statValue / maxVal, 0, 1)
	end)

	local smoothFill = Spring(Computed(function()
		return UDim2.fromScale(fillFraction:get(), 1)
	end), 25, 1)

	return New "Frame" {
		Name = "Stat_" .. statName,
		Size = UDim2.fromScale(1, 1 / #STAT_NAMES),
		BackgroundTransparency = 1,

		[Children] = {
			New "TextLabel" {
				Name = "Label",
				Position = UDim2.fromScale(0, 0),
				Size = UDim2.fromScale(0.3, 1),
				BackgroundTransparency = 1,
				Text = STAT_DISPLAY[statName] or statName,
				TextColor3 = Color3.fromRGB(200, 200, 220),
				Font = Enum.Font.Gotham,
				TextScaled = true,
				TextXAlignment = Enum.TextXAlignment.Left,
			},

			New "Frame" {
				Name = "BarBg",
				Position = UDim2.fromScale(0.32, 0.15),
				Size = UDim2.fromScale(0.55, 0.7),
				BackgroundColor3 = Color3.fromRGB(50, 50, 70),

				[Children] = {
					New "UICorner" { CornerRadius = UDim.new(0.4, 0) },
					New "Frame" {
						Name = "Fill",
						Size = smoothFill,
						BackgroundColor3 = STAT_COLORS[statName] or Color3.fromRGB(150, 150, 150),

						[Children] = {
							New "UICorner" { CornerRadius = UDim.new(0.4, 0) },
						},
					},
				},
			},

			New "TextLabel" {
				Name = "Value",
				Position = UDim2.fromScale(0.9, 0),
				Size = UDim2.fromScale(0.1, 1),
				BackgroundTransparency = 1,
				Text = tostring(statValue),
				TextColor3 = Color3.fromRGB(255, 255, 255),
				Font = Enum.Font.GothamBold,
				TextScaled = true,
			},
		},
	}
end

local function createMachineCard(machineId, machineConfig)
	local isOwned = Computed(function()
		local owned = ownedMachines:get()
		return table.find(owned, machineId) ~= nil
	end)

	local isSelected = Computed(function()
		return selectedMachineId:get() == machineId
	end)

	local borderColor = Computed(function()
		if isSelected:get() then return Color3.fromRGB(80, 220, 255) end
		if isOwned:get() then return Color3.fromRGB(80, 160, 80) end
		return Color3.fromRGB(80, 80, 80)
	end)

	local badgeText = Computed(function()
		if isSelected:get() then return "SELECTED" end
		if isOwned:get() then return "OWNED" end

		local unlock = machineConfig.unlock
		if unlock.type == "level" then
			return "Lv." .. (unlock.requiredLevel or "?")
		elseif unlock.type == "shop" then
			return tostring(unlock.price or "?")
		end
		return "LOCKED"
	end)

	local badgeColor = Computed(function()
		if isSelected:get() then return Color3.fromRGB(80, 220, 255) end
		if isOwned:get() then return Color3.fromRGB(80, 160, 80) end
		return Color3.fromRGB(120, 80, 80)
	end)

	local statBars = {}
	for _, statName in ipairs(STAT_NAMES) do
		local val = machineConfig.baseStats[statName] or 0
		table.insert(statBars, createStatBar(statName, val))
	end

	return New "TextButton" {
		Name = "Machine_" .. machineId,
		Size = UDim2.fromScale(0.48, 0.9),
		BackgroundColor3 = Color3.fromRGB(35, 35, 55),
		BackgroundTransparency = 0.2,
		Text = "",
		AutoButtonColor = false,

		[Children] = {
			New "UICorner" { CornerRadius = UDim.new(0.04, 0) },
			New "UIStroke" {
				Color = borderColor,
				Thickness = 2,
			},

			-- Machine name
			New "TextLabel" {
				Position = UDim2.fromScale(0.05, 0.02),
				Size = UDim2.fromScale(0.6, 0.12),
				BackgroundTransparency = 1,
				Text = machineConfig.displayName,
				TextColor3 = Color3.fromRGB(255, 255, 255),
				Font = Enum.Font.GothamBold,
				TextScaled = true,
				TextXAlignment = Enum.TextXAlignment.Left,
			},

			-- Badge
			New "TextLabel" {
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.fromScale(0.95, 0.02),
				Size = UDim2.fromScale(0.3, 0.1),
				BackgroundColor3 = badgeColor,
				Text = badgeText,
				TextColor3 = Color3.fromRGB(255, 255, 255),
				Font = Enum.Font.GothamBold,
				TextScaled = true,

				[Children] = {
					New "UICorner" { CornerRadius = UDim.new(0.4, 0) },
					New "UIPadding" {
						PaddingLeft = UDim.new(0.1, 0),
						PaddingRight = UDim.new(0.1, 0),
					},
				},
			},

			-- Stats area
			New "Frame" {
				Name = "StatsArea",
				Position = UDim2.fromScale(0.05, 0.18),
				Size = UDim2.fromScale(0.9, 0.65),
				BackgroundTransparency = 1,

				[Children] = {
					New "UIListLayout" {
						FillDirection = Enum.FillDirection.Vertical,
						Padding = UDim.new(0.01, 0),
					},
					table.unpack(statBars),
				},
			},

			-- Select / Buy button
			New "TextButton" {
				Name = "ActionButton",
				AnchorPoint = Vector2.new(0.5, 1),
				Position = UDim2.fromScale(0.5, 0.96),
				Size = UDim2.fromScale(0.6, 0.1),
				BackgroundColor3 = Computed(function()
					if isSelected:get() then return Color3.fromRGB(60, 60, 80) end
					if isOwned:get() then return Color3.fromRGB(60, 160, 220) end
					return Color3.fromRGB(80, 80, 100)
				end),
				Text = Computed(function()
					if isSelected:get() then return "Selected" end
					if isOwned:get() then return "Select" end
					local unlock = machineConfig.unlock
					if unlock.type == "shop" then return "Buy " .. (unlock.price or "") end
					return "Locked"
				end),
				TextColor3 = Color3.fromRGB(255, 255, 255),
				Font = Enum.Font.GothamBold,
				TextScaled = true,

				[Children] = {
					New "UICorner" { CornerRadius = UDim.new(0.3, 0) },
				},

				[OnEvent "Activated"] = function()
					if isSelecting:get() then return end

					if isOwned:get() and not isSelected:get() then
						isSelecting:set(true)
						task.spawn(function()
							local ok, reason = _garageService:SelectMachine(machineId)
							isSelecting:set(false)
							if not ok then
								warn("[HubGarageController] Select failed: " .. tostring(reason))
							end
						end)
					elseif not isOwned:get() and machineConfig.unlock.type == "shop" then
						isSelecting:set(true)
						task.spawn(function()
							local ok, reason = _shopService:PurchaseMachine(machineId)
							isSelecting:set(false)
							if not ok then
								warn("[HubGarageController] Purchase failed: " .. tostring(reason))
							end
						end)
					end
				end,
			},
		},

		[OnEvent "Activated"] = function() end,
	}
end

local function createGarageUI()
	local machineCards = {}
	for machineId, config in pairs(MachinesConfig.machines) do
		table.insert(machineCards, createMachineCard(machineId, config))
	end

	local panelSize = isMobile and UDim2.fromScale(1, 1) or UDim2.fromScale(0.7, 0.75)

	_screenGui = New "ScreenGui" {
		Parent = LocalPlayer:WaitForChild("PlayerGui"),
		Name = "HubGarageUI",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Enabled = isOpen,

		[Children] = {
			New "TextButton" {
				Name = "Backdrop",
				Size = UDim2.fromScale(1, 1),
				BackgroundColor3 = Color3.fromRGB(0, 0, 0),
				BackgroundTransparency = 0.5,
				Text = "",
				AutoButtonColor = false,
				ZIndex = 1,

				[OnEvent "Activated"] = function()
					HubGarageController:Close()
				end,
			},

			New "Frame" {
				Name = "GaragePanel",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = panelSize,
				BackgroundColor3 = Color3.fromRGB(25, 25, 40),
				BackgroundTransparency = 0.1,
				ZIndex = 2,

				[Children] = {
					New "UICorner" { CornerRadius = UDim.new(0.02, 0) },

					New "TextLabel" {
						Position = UDim2.fromScale(0.02, 0.01),
						Size = UDim2.fromScale(0.5, 0.07),
						BackgroundTransparency = 1,
						Text = "Garage",
						TextColor3 = Color3.fromRGB(255, 255, 255),
						Font = Enum.Font.GothamBold,
						TextScaled = true,
						TextXAlignment = Enum.TextXAlignment.Left,
						ZIndex = 3,
					},

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
							New "UICorner" { CornerRadius = UDim.new(0.5, 0) },
							New "UIAspectRatioConstraint" { AspectRatio = 1 },
						},

						[OnEvent "Activated"] = function()
							HubGarageController:Close()
						end,
					},

					New "ScrollingFrame" {
						Name = "MachinesScroll",
						Position = UDim2.fromScale(0.02, 0.1),
						Size = UDim2.fromScale(0.96, 0.88),
						BackgroundTransparency = 1,
						ScrollBarThickness = 4,
						CanvasSize = UDim2.fromScale(0, 0),
						AutomaticCanvasSize = Enum.AutomaticSize.X,
						ScrollingDirection = Enum.ScrollingDirection.X,
						ZIndex = 3,

						[Children] = {
							New "UIListLayout" {
								FillDirection = Enum.FillDirection.Horizontal,
								Padding = UDim.new(0.02, 0),
								VerticalAlignment = Enum.VerticalAlignment.Center,
							},
							table.unpack(machineCards),
						},
					},
				},
			},
		},
	}

	_trove:Add(_screenGui)
end

local function bindReplica(replica)
	local function updateOwned(data)
		ownedMachines:set(data.ownedMachines or {})
		selectedMachineId:set(data.selectedMachineId or MachinesConfig.defaultMachineId)
		playerCurrency:set(data.currency or 0)
		playerLevel:set(data.level or 1)
	end

	updateOwned(replica.Data)

	_trove:Add(replica:ListenToChange({ "ownedMachines" }, function(newVal)
		ownedMachines:set(newVal)
	end))

	_trove:Add(replica:ListenToChange({ "selectedMachineId" }, function(newVal)
		selectedMachineId:set(newVal)
	end))

	_trove:Add(replica:ListenToChange({ "currency" }, function(newVal)
		playerCurrency:set(newVal)
	end))

	_trove:Add(replica:ListenToChange({ "level" }, function(newVal)
		playerLevel:set(newVal)
	end))
end

function HubGarageController:KnitInit()
end

function HubGarageController:KnitStart()
	_garageService = Knit.GetService("HubGarageService")
	_shopService = Knit.GetService("HubShopService")

	createGarageUI()

	ReplicaController.ReplicaOfClassCreated("PlayerProfile", function(replica)
		if replica.Tags.Player == LocalPlayer then
			bindReplica(replica)
		end
	end)
end

function HubGarageController:Open()
	local panelManager = Knit.GetController("HubPanelManager")
	if panelManager then
		panelManager:OpenPanel("garage")
	else
		isOpen:set(true)
	end
end

function HubGarageController:Close()
	local panelManager = Knit.GetController("HubPanelManager")
	if panelManager then
		panelManager:ClosePanel()
	else
		isOpen:set(false)
	end
end

function HubGarageController:SetOpen(open)
	isOpen:set(open)
end

function HubGarageController:IsOpen()
	return isOpen:get()
end

function HubGarageController:Destroy()
	_trove:Destroy()
end

return HubGarageController
