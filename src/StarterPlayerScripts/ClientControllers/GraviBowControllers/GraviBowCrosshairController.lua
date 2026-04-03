local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")
local UserInputService = game:GetService("UserInputService")
local Players = game:GetService("Players")

local Packages = ReplicatedStorage.Packages
local CustomPackages = ReplicatedStorage.CustomPackages
local Knit = require(Packages.Knit)
local Trove = require(Packages.Trove)
local Fusion = require(CustomPackages.FusionRoot.Fusion)

local New = Fusion.New
local Value = Fusion.Value
local Computed = Fusion.Computed
local Children = Fusion.Children
local Spring = Fusion.Spring

local LocalPlayer = Players.LocalPlayer

local HINT_BG = Color3.fromRGB(18, 18, 22)
local HINT_KEY_BG = Color3.fromRGB(32, 32, 40)
local HINT_DESC_COLOR = Color3.fromRGB(170, 170, 185)
local HINT_ACTIVE_ACCENT = Color3.fromRGB(255, 70, 70)
local HINT_ACTIVE_BG = Color3.fromRGB(255, 70, 70)

local CROSSHAIR_SIZE = 24
local GAP = 6
local LINE_LENGTH = 10
local LINE_THICKNESS = 2
local DOT_SIZE = 4
local COLOR_DEFAULT = Color3.fromRGB(255, 255, 255)
local COLOR_AIM = Color3.fromRGB(255, 80, 80)

local GraviBowCrosshairController = Knit.CreateController({
	Name = "GraviBowCrosshairController",
	_trove = nil,
})

function GraviBowCrosshairController:KnitInit()
	self._trove = Trove.new()
	self._isAiming = Value(false)
	self._isDrawing = Value(false)
end

function GraviBowCrosshairController:KnitStart()
	UserInputService.MouseIconEnabled = false
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)

	self._trove:Add(UserInputService.InputBegan:Connect(function(input, processed)
		if processed then return end
		if input.UserInputType == Enum.UserInputType.MouseButton2 then
			self._isAiming:set(true)
		elseif input.UserInputType == Enum.UserInputType.MouseButton1 then
			self._isDrawing:set(true)
		end
	end), "Disconnect")

	self._trove:Add(UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton2 then
			self._isAiming:set(false)
			self._isDrawing:set(false)
		elseif input.UserInputType == Enum.UserInputType.MouseButton1 then
			self._isDrawing:set(false)
		end
	end), "Disconnect")

	local crosshairColor = Spring(Computed(function()
		return self._isAiming:get() and COLOR_AIM or COLOR_DEFAULT
	end), 20)

	local gapSpring = Spring(Computed(function()
		return self._isAiming:get() and 3 or GAP
	end), 15)

	local lineAlpha = Spring(Computed(function()
		return self._isAiming:get() and 0 or 0.3
	end), 15)

	local function crosshairLine(rotation, name)
		return New "Frame" {
			Name = name,
			AnchorPoint = Vector2.new(0.5, 0),
			Position = Computed(function()
				return UDim2.new(0.5, 0, 0.5, gapSpring:get())
			end),
			Size = UDim2.fromOffset(LINE_THICKNESS, LINE_LENGTH),
			Rotation = rotation,
			BackgroundColor3 = crosshairColor,
			BackgroundTransparency = lineAlpha,
			BorderSizePixel = 0,

			[Children] = {
				New "UICorner" {
					CornerRadius = UDim.new(0, 1),
				},
				New "UIStroke" {
					Color = Color3.fromRGB(0, 0, 0),
					Thickness = 1,
					Transparency = Computed(function()
						return self._isAiming:get() and 0.3 or 0.5
					end),
				},
			},
		}
	end

	local rmbText = Computed(function()
		return self._isAiming:get() and "Aiming" or "Aim"
	end)

	local lmbText = Computed(function()
		if self._isDrawing:get() then
			return "Drawing..."
		elseif self._isAiming:get() then
			return "Draw & Fire"
		end
		return "Draw"
	end)

	local rmbBadgeBg = Spring(Computed(function()
		return self._isAiming:get() and HINT_ACTIVE_BG or HINT_KEY_BG
	end), 18)

	local lmbBadgeBg = Spring(Computed(function()
		return self._isDrawing:get() and HINT_ACTIVE_BG or HINT_KEY_BG
	end), 18)

	local rmbStroke = Spring(Computed(function()
		return self._isAiming:get() and HINT_ACTIVE_ACCENT or Color3.fromRGB(60, 60, 72)
	end), 18)

	local lmbStroke = Spring(Computed(function()
		return self._isDrawing:get() and HINT_ACTIVE_ACCENT or Color3.fromRGB(60, 60, 72)
	end), 18)

	local rmbKeyText = Spring(Computed(function()
		return self._isAiming:get() and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(200, 200, 210)
	end), 18)

	local lmbKeyText = Spring(Computed(function()
		return self._isDrawing:get() and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(200, 200, 210)
	end), 18)

	local rmbDescColor = Spring(Computed(function()
		return self._isAiming:get() and HINT_ACTIVE_ACCENT or HINT_DESC_COLOR
	end), 18)

	local lmbDescColor = Spring(Computed(function()
		return self._isDrawing:get() and HINT_ACTIVE_ACCENT or HINT_DESC_COLOR
	end), 18)

	local function controlHint(keyLabel, descText, keyBgColor, keyTextColor, strokeColor, descColor)
		return New "Frame" {
			Name = keyLabel .. "Hint",
			Size = UDim2.fromOffset(180, 56),
			BackgroundColor3 = HINT_BG,
			BackgroundTransparency = 0.25,
			BorderSizePixel = 0,

			[Children] = {
				New "UICorner" {
					CornerRadius = UDim.new(0, 12),
				},
				New "UIStroke" {
					Color = strokeColor,
					Thickness = 1,
					Transparency = 0.5,
				},
				New "UIPadding" {
					PaddingLeft = UDim.new(0, 10),
					PaddingRight = UDim.new(0, 14),
				},

				New "Frame" {
					Name = "KeyBadge",
					AnchorPoint = Vector2.new(0, 0.5),
					Position = UDim2.new(0, 0, 0.5, 0),
					Size = UDim2.fromOffset(50, 36),
					BackgroundColor3 = keyBgColor,
					BorderSizePixel = 0,

					[Children] = {
						New "UICorner" {
							CornerRadius = UDim.new(0, 8),
						},
						New "UIStroke" {
							Color = strokeColor,
							Thickness = 1,
							Transparency = 0.4,
						},
						New "TextLabel" {
							Name = "Key",
							Size = UDim2.fromScale(1, 1),
							BackgroundTransparency = 1,
							Text = keyLabel,
							TextColor3 = keyTextColor,
							TextSize = 16,
							Font = Enum.Font.GothamBold,
						},
					},
				},

				New "TextLabel" {
					Name = "Desc",
					AnchorPoint = Vector2.new(1, 0.5),
					Position = UDim2.new(1, 0, 0.5, 0),
					Size = UDim2.fromOffset(100, 36),
					BackgroundTransparency = 1,
					Text = descText,
					TextColor3 = descColor,
					TextSize = 16,
					Font = Enum.Font.GothamMedium,
					TextXAlignment = Enum.TextXAlignment.Right,
				},
			},
		}
	end

	local gui = New "ScreenGui" {
		Name = "CrosshairGui",
		DisplayOrder = 200,
		IgnoreGuiInset = true,
		ResetOnSpawn = false,
		Parent = LocalPlayer.PlayerGui,

		[Children] = {
			New "Frame" {
				Name = "Crosshair",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromOffset(CROSSHAIR_SIZE * 2, CROSSHAIR_SIZE * 2),
				BackgroundTransparency = 1,

				[Children] = {
					New "Frame" {
						Name = "Dot",
						AnchorPoint = Vector2.new(0.5, 0.5),
						Position = UDim2.fromScale(0.5, 0.5),
						Size = UDim2.fromOffset(DOT_SIZE, DOT_SIZE),
						BackgroundColor3 = crosshairColor,
						BackgroundTransparency = lineAlpha,
						BorderSizePixel = 0,

						[Children] = {
							New "UICorner" {
								CornerRadius = UDim.new(1, 0),
							},
							New "UIStroke" {
								Color = Color3.fromRGB(0, 0, 0),
								Thickness = 1,
								Transparency = 0.5,
							},
						},
					},

					crosshairLine(0, "Top"),
					crosshairLine(90, "Right"),
					crosshairLine(180, "Bottom"),
					crosshairLine(270, "Left"),
				},
			},

			New "Frame" {
				Name = "ControlHints",
				AnchorPoint = Vector2.new(0.5, 1),
				Position = UDim2.new(0.5, 0, 1, -36),
				Size = UDim2.fromOffset(380, 56),
				BackgroundTransparency = 1,

				[Children] = {
					New "UIListLayout" {
						FillDirection = Enum.FillDirection.Horizontal,
						HorizontalAlignment = Enum.HorizontalAlignment.Center,
						VerticalAlignment = Enum.VerticalAlignment.Center,
						Padding = UDim.new(0, 16),
						SortOrder = Enum.SortOrder.LayoutOrder,
					},

					controlHint("RMB", rmbText, rmbBadgeBg, rmbKeyText, rmbStroke, rmbDescColor),
					controlHint("LMB", lmbText, lmbBadgeBg, lmbKeyText, lmbStroke, lmbDescColor),
				},
			},
		},
	}

	self._trove:Add(gui)
	self._trove:Add(function()
		UserInputService.MouseIconEnabled = true
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, true)
	end)

end

return GraviBowCrosshairController
