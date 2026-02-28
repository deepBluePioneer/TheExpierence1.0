local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Packages = ReplicatedStorage.Packages
local Knit = require(Packages.Knit)
local Trove = require(Packages.Trove)

local CustomPackages = ReplicatedStorage.CustomPackages
local Fusion = require(CustomPackages.FusionRoot.Fusion)

local New = Fusion.New
local Value = Fusion.Value
local Computed = Fusion.Computed
local Children = Fusion.Children
local Spring = Fusion.Spring

local LocalPlayer = Players.LocalPlayer

local HubPanelManager = Knit.CreateController {
	Name = "HubPanelManager",
}

local _trove = Trove.new()
local _toastGui = nil

local activePanel = Value(nil)
local toasts = Value({})

local PANEL_CONTROLLERS = {
	shop = "HubShopController",
	garage = "HubGarageController",
	leaderboard = "HubLeaderboardController",
}

local TOAST_DURATION = 4
local MAX_VISIBLE_TOASTS = 3

function HubPanelManager:KnitInit()
end

function HubPanelManager:KnitStart()
	self:_createToastUI()
end

function HubPanelManager:OpenPanel(panelId)
	local current = activePanel:get()

	if current == panelId then return end

	if current then
		self:_setPanelOpen(current, false)
	end

	activePanel:set(panelId)
	self:_setPanelOpen(panelId, true)
end

function HubPanelManager:ClosePanel()
	local current = activePanel:get()
	if current then
		self:_setPanelOpen(current, false)
		activePanel:set(nil)
	end
end

function HubPanelManager:GetActivePanel()
	return activePanel:get()
end

function HubPanelManager:CloseAllForTeleport()
	self:ClosePanel()
end

function HubPanelManager:_setPanelOpen(panelId, open)
	local controllerName = PANEL_CONTROLLERS[panelId]
	if not controllerName then return end

	local ok, controller = pcall(function()
		return Knit.GetController(controllerName)
	end)

	if ok and controller and controller.SetOpen then
		controller:SetOpen(open)
	end
end

----------------------------------------------------------------
-- Toast notification system
----------------------------------------------------------------

local _toastIdCounter = 0

function HubPanelManager:ShowToast(message, color)
	_toastIdCounter = _toastIdCounter + 1

	local toast = {
		id = _toastIdCounter,
		message = message,
		color = color or Color3.fromRGB(60, 140, 220),
		timestamp = os.clock(),
	}

	local current = toasts:get()
	local newList = {}
	for _, t in ipairs(current) do
		table.insert(newList, t)
	end
	table.insert(newList, toast)

	while #newList > MAX_VISIBLE_TOASTS do
		table.remove(newList, 1)
	end

	toasts:set(newList)

	task.delay(TOAST_DURATION, function()
		local list = toasts:get()
		local filtered = {}
		for _, t in ipairs(list) do
			if t.id ~= toast.id then
				table.insert(filtered, t)
			end
		end
		toasts:set(filtered)
	end)
end

function HubPanelManager:_createToastUI()
	local toastChildren = Computed(function()
		local list = toasts:get()
		local children = {}

		for i, toast in ipairs(list) do
			children["toast_" .. toast.id] = New "Frame" {
				Name = "Toast_" .. toast.id,
				Size = UDim2.fromScale(1, 0.28),
				BackgroundColor3 = toast.color,
				BackgroundTransparency = 0.2,
				LayoutOrder = toast.id,

				[Children] = {
					New "UICorner" { CornerRadius = UDim.new(0.3, 0) },
					New "TextLabel" {
						AnchorPoint = Vector2.new(0.5, 0.5),
						Position = UDim2.fromScale(0.5, 0.5),
						Size = UDim2.fromScale(0.9, 0.7),
						BackgroundTransparency = 1,
						Text = toast.message,
						TextColor3 = Color3.fromRGB(255, 255, 255),
						Font = Enum.Font.GothamBold,
						TextScaled = true,
						TextXAlignment = Enum.TextXAlignment.Left,
					},
				},
			}
		end

		return children
	end)

	_toastGui = New "ScreenGui" {
		Parent = LocalPlayer:WaitForChild("PlayerGui"),
		Name = "ToastNotifications",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,

		[Children] = {
			New "Frame" {
				Name = "ToastContainer",
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.fromScale(0.99, 0.04),
				Size = UDim2.fromScale(0.25, 0.2),
				BackgroundTransparency = 1,
				ZIndex = 50,

				[Children] = {
					New "UIListLayout" {
						FillDirection = Enum.FillDirection.Vertical,
						VerticalAlignment = Enum.VerticalAlignment.Top,
						HorizontalAlignment = Enum.HorizontalAlignment.Right,
						Padding = UDim.new(0.04, 0),
						SortOrder = Enum.SortOrder.LayoutOrder,
					},
					toastChildren,
				},
			},
		},
	}

	_trove:Add(_toastGui)
end

function HubPanelManager:Destroy()
	_trove:Destroy()
end

return HubPanelManager
