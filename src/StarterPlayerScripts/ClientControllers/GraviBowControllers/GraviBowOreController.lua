local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Packages = ReplicatedStorage.Packages
local CustomPackages = ReplicatedStorage:WaitForChild("CustomPackages")
local Knit = require(Packages.Knit)
local Trove = require(Packages.Trove)
local ReplicaController = require(CustomPackages.Replica.ReplicaController)

local LocalPlayer = Players.LocalPlayer

local ORE_COLOR = Color3.fromRGB(255, 200, 50)
local BG_COLOR = Color3.fromRGB(15, 15, 25)
local TEXT_COLOR = Color3.fromRGB(240, 240, 255)
local BUMP_INFO = TweenInfo.new(0.15, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local FADE_INFO = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local GraviBowOreController = Knit.CreateController({
	Name = "GraviBowOreController",
	_trove = nil,
	_oreLabel = nil,
	_iconLabel = nil,
	_container = nil,
	_lastOre = 0,
})

function GraviBowOreController:KnitInit()
	self._trove = Trove.new()
end

function GraviBowOreController:KnitStart()
	self:_createUI()

	ReplicaController.ReplicaOfClassCreated("GraviBowOreState", function(replica)
		self._replica = replica
		self:_updateFromData(replica.Data)

		replica:ListenToRaw(function()
			self:_updateFromData(replica.Data)
		end)
	end)
end

function GraviBowOreController:_updateFromData(data)
	local ore = data.ore or 0

	if ore ~= self._lastOre then
		self._lastOre = ore
		self:_setOreDisplay(ore)
		if ore > 0 then
			self:_bump()
		end
	end
end

function GraviBowOreController:_setOreDisplay(amount)
	if self._oreLabel then
		self._oreLabel.Text = tostring(amount)
	end
end

function GraviBowOreController:_bump()
	if not self._container then return end
	self._container.Size = UDim2.fromOffset(160, 44)
	TweenService:Create(self._container, BUMP_INFO, {
		Size = UDim2.fromOffset(148, 40),
	}):Play()
end

function GraviBowOreController:_createUI()
	local gui = Instance.new("ScreenGui")
	gui.Name = "OreHUD"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = false
	gui.DisplayOrder = 5
	gui.Parent = LocalPlayer.PlayerGui
	self._trove:Add(gui)

	local container = Instance.new("Frame")
	container.Name = "OreContainer"
	container.AnchorPoint = Vector2.new(0, 0)
	container.Position = UDim2.new(0, 16, 0, 16)
	container.Size = UDim2.fromOffset(148, 40)
	container.BackgroundColor3 = BG_COLOR
	container.BackgroundTransparency = 0.3
	container.BorderSizePixel = 0
	container.Parent = gui
	self._container = container

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = container

	local stroke = Instance.new("UIStroke")
	stroke.Color = ORE_COLOR
	stroke.Thickness = 1.5
	stroke.Transparency = 0.5
	stroke.Parent = container

	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 12)
	pad.PaddingRight = UDim.new(0, 12)
	pad.Parent = container

	local icon = Instance.new("TextLabel")
	icon.Name = "Icon"
	icon.Size = UDim2.new(0, 24, 1, 0)
	icon.Position = UDim2.fromOffset(0, 0)
	icon.BackgroundTransparency = 1
	icon.Text = "💎"
	icon.TextSize = 20
	icon.Font = Enum.Font.GothamBold
	icon.TextXAlignment = Enum.TextXAlignment.Left
	icon.TextYAlignment = Enum.TextYAlignment.Center
	icon.Parent = container
	self._iconLabel = icon

	local label = Instance.new("TextLabel")
	label.Name = "OreLabel"
	label.Size = UDim2.new(0, 40, 1, 0)
	label.Position = UDim2.new(0, 28, 0, 0)
	label.BackgroundTransparency = 1
	label.Text = "Ore"
	label.TextColor3 = ORE_COLOR
	label.TextSize = 15
	label.Font = Enum.Font.GothamBold
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextYAlignment = Enum.TextYAlignment.Center
	label.Parent = container

	local count = Instance.new("TextLabel")
	count.Name = "Count"
	count.AnchorPoint = Vector2.new(1, 0)
	count.Size = UDim2.new(0, 60, 1, 0)
	count.Position = UDim2.new(1, 0, 0, 0)
	count.BackgroundTransparency = 1
	count.Text = "0"
	count.TextColor3 = TEXT_COLOR
	count.TextSize = 20
	count.Font = Enum.Font.GothamBold
	count.TextXAlignment = Enum.TextXAlignment.Right
	count.TextYAlignment = Enum.TextYAlignment.Center
	count.Parent = container
	self._oreLabel = count
end

return GraviBowOreController
