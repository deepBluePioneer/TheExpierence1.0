local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Packages = ReplicatedStorage.Packages
local Knit = require(Packages.Knit)
local Trove = require(Packages.Trove)

local ItemRegistry = require(ReplicatedStorage.Source.GraviBowItemRegistry)

local LocalPlayer = Players.LocalPlayer

local RADIAL_OPTIONS = ItemRegistry

local RADIAL_RING_RADIUS = 120
local RADIAL_SEGMENT_SIZE = 80
local RADIAL_BG_COLOR = Color3.fromRGB(10, 12, 20)
local RADIAL_HIGHLIGHT_COLOR = Color3.fromRGB(255, 200, 50)
local RADIAL_NORMAL_COLOR = Color3.fromRGB(40, 44, 60)
local RADIAL_TEXT_COLOR = Color3.fromRGB(220, 220, 240)
local RADIAL_TWEEN_INFO = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local GraviBowRadialMenuController = Knit.CreateController({
	Name = "GraviBowRadialMenuController",

	_trove = nil,
	_radialGui = nil,
	_radialVisible = false,
	_radialSegments = {},
	_selectedSegment = 0,
})

function GraviBowRadialMenuController:KnitInit()
	self._trove = Trove.new()
end

function GraviBowRadialMenuController:KnitStart()
	self._oreService = Knit.GetService("GraviBowOreService")
	self:_createRadialMenu()
end

function GraviBowRadialMenuController:IsRadialOpen()
	return self._radialVisible
end

function GraviBowRadialMenuController:Show()
	self:_showRadialMenu()
end

function GraviBowRadialMenuController:Hide()
	self:_hideRadialMenu()
end

function GraviBowRadialMenuController:ScrollSelection(dir)
	self:_scrollRadialSelection(dir)
end

function GraviBowRadialMenuController:_createRadialMenu()
	local gui = Instance.new("ScreenGui")
	gui.Name = "RadialMenuGui"
	gui.DisplayOrder = 110
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.Enabled = false
	gui.Parent = LocalPlayer.PlayerGui
	self._trove:Add(gui)
	self._radialGui = gui

	local overlay = Instance.new("Frame")
	overlay.Name = "Overlay"
	overlay.Size = UDim2.fromScale(1, 1)
	overlay.BackgroundColor3 = Color3.new(0, 0, 0)
	overlay.BackgroundTransparency = 0.6
	overlay.BorderSizePixel = 0
	overlay.Parent = gui

	local centerDot = Instance.new("Frame")
	centerDot.Name = "CenterDot"
	centerDot.AnchorPoint = Vector2.new(0.5, 0.5)
	centerDot.Position = UDim2.fromScale(0.5, 0.5)
	centerDot.Size = UDim2.fromOffset(12, 12)
	centerDot.BackgroundColor3 = Color3.fromRGB(200, 200, 220)
	centerDot.BackgroundTransparency = 0.3
	centerDot.BorderSizePixel = 0
	centerDot.Parent = gui
	local cdCorner = Instance.new("UICorner")
	cdCorner.CornerRadius = UDim.new(1, 0)
	cdCorner.Parent = centerDot

	self._radialSegments = {}
	local count = #RADIAL_OPTIONS
	for i, option in ipairs(RADIAL_OPTIONS) do
		local seg = Instance.new("Frame")
		seg.Name = "Segment_" .. option.name
		seg.AnchorPoint = Vector2.new(0.5, 0.5)
		seg.Size = UDim2.fromOffset(RADIAL_SEGMENT_SIZE, RADIAL_SEGMENT_SIZE)
		seg.BackgroundColor3 = RADIAL_NORMAL_COLOR
		seg.BackgroundTransparency = 0.15
		seg.BorderSizePixel = 0
		seg.Parent = gui

		local segCorner = Instance.new("UICorner")
		segCorner.CornerRadius = UDim.new(1, 0)
		segCorner.Parent = seg

		local segStroke = Instance.new("UIStroke")
		segStroke.Name = "Stroke"
		segStroke.Color = Color3.fromRGB(80, 85, 110)
		segStroke.Thickness = 2
		segStroke.Transparency = 0.3
		segStroke.Parent = seg

		local iconLabel = Instance.new("TextLabel")
		iconLabel.Name = "Icon"
		iconLabel.Size = UDim2.new(1, 0, 0.55, 0)
		iconLabel.Position = UDim2.fromScale(0, 0.05)
		iconLabel.BackgroundTransparency = 1
		iconLabel.Text = option.icon
		iconLabel.TextSize = 28
		iconLabel.Font = Enum.Font.GothamBold
		iconLabel.TextColor3 = Color3.new(1, 1, 1)
		iconLabel.Parent = seg

		local labelText = option.name
		if option.cost and option.cost > 0 then
			labelText = option.name .. " (" .. option.cost .. ")"
		end

		local nameLabel = Instance.new("TextLabel")
		nameLabel.Name = "Label"
		nameLabel.Size = UDim2.new(1, 0, 0.35, 0)
		nameLabel.Position = UDim2.fromScale(0, 0.6)
		nameLabel.BackgroundTransparency = 1
		nameLabel.Text = labelText
		nameLabel.TextSize = 12
		nameLabel.Font = Enum.Font.GothamBold
		nameLabel.TextColor3 = RADIAL_TEXT_COLOR
		nameLabel.Parent = seg

		self._radialSegments[i] = {
			frame = seg,
			stroke = segStroke,
			angle = 0,
			option = option,
		}
	end

	self:_positionRadialSegments()
end

function GraviBowRadialMenuController:_positionRadialSegments()
	if not self._radialGui then return end
	local count = #RADIAL_OPTIONS

	for i, data in ipairs(self._radialSegments) do
		local angle = ((i - 1) / count) * math.pi * 2 - math.pi / 2
		local ox = math.cos(angle) * RADIAL_RING_RADIUS
		local oy = math.sin(angle) * RADIAL_RING_RADIUS
		data.frame.Position = UDim2.new(0.5, ox, 0.5, oy)
		data.angle = angle
	end
end

function GraviBowRadialMenuController:_showRadialMenu()
	if self._radialVisible then return end
	self._radialVisible = true

	self:_positionRadialSegments()

	if self._radialGui then
		self._radialGui.Enabled = true
	end

	self._selectedSegment = 1
	self:_highlightRadialSegment()
end

function GraviBowRadialMenuController:_hideRadialMenu()
	if not self._radialVisible then return end
	self._radialVisible = false

	local selected = self._selectedSegment
	if selected >= 1 and selected <= #RADIAL_OPTIONS then
		local option = RADIAL_OPTIONS[selected]
		print("[GraviBowRadialMenuController] Selected build:", option.name)

		if option.cost and option.cost > 0 then
			self._oreService.PurchaseItem:Fire(option.name)
		end
	end

	if self._radialGui then
		self._radialGui.Enabled = false
	end

	self._selectedSegment = 0
end

function GraviBowRadialMenuController:_scrollRadialSelection(dir)
	local count = #RADIAL_OPTIONS
	if count == 0 then return end

	local newIdx = self._selectedSegment + dir
	if newIdx < 1 then
		newIdx = count
	elseif newIdx > count then
		newIdx = 1
	end

	self._selectedSegment = newIdx
	self:_highlightRadialSegment()
end

function GraviBowRadialMenuController:_highlightRadialSegment()
	local selected = self._selectedSegment

	for i, data in ipairs(self._radialSegments) do
		local isSelected = (i == selected)
		local targetBg = isSelected and RADIAL_HIGHLIGHT_COLOR or RADIAL_NORMAL_COLOR
		local targetSize = isSelected
			and UDim2.fromOffset(RADIAL_SEGMENT_SIZE + 10, RADIAL_SEGMENT_SIZE + 10)
			or UDim2.fromOffset(RADIAL_SEGMENT_SIZE, RADIAL_SEGMENT_SIZE)
		local targetStroke = isSelected and RADIAL_HIGHLIGHT_COLOR or Color3.fromRGB(80, 85, 110)

		TweenService:Create(data.frame, RADIAL_TWEEN_INFO, {
			BackgroundColor3 = targetBg,
			Size = targetSize,
		}):Play()
		TweenService:Create(data.stroke, RADIAL_TWEEN_INFO, {
			Color = targetStroke,
		}):Play()
	end
end

return GraviBowRadialMenuController
