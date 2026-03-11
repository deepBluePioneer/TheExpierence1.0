local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CustomPackages = ReplicatedStorage.CustomPackages
local Fusion = require(CustomPackages.FusionRoot.Fusion)

local New = Fusion.New
local Value = Fusion.Value
local Computed = Fusion.Computed
local Children = Fusion.Children
local OnEvent = Fusion.OnEvent
local OnChange = Fusion.OnChange
local Spring = Fusion.Spring
local ForPairs = Fusion.ForPairs

local ACCENT_HOT = Color3.fromRGB(255, 30, 100)
local ACCENT_CYAN = Color3.fromRGB(0, 220, 255)
local PANEL_BG = Color3.fromRGB(8, 12, 24)
local TEXT_WHITE = Color3.fromRGB(255, 255, 255)
local TEXT_DIM = Color3.fromRGB(80, 100, 140)
local DIVIDER_COLOR = Color3.fromRGB(30, 50, 80)
local INPUT_BG = Color3.fromRGB(14, 22, 40)
local BUTTON_BG = Color3.fromRGB(12, 18, 34)
local BUTTON_SELECTED = Color3.fromRGB(15, 40, 75)
local CONFIRM_HOT = ACCENT_HOT
local CONFIRM_DIM = Color3.fromRGB(25, 30, 50)

local LakelandNameEntryUI = {}

function LakelandNameEntryUI.new(playerGui, gameState, previousNames, onNameConfirmed)
	local typedName = Value("")
	local selectedName = Value("")
	local nameInputBox = nil

	local confirmScale = Value(1)
	local animatedConfirmScale = Spring(confirmScale, 30, 0.7)

	local visible = Computed(function()
		return gameState:get() == "NAME_ENTRY"
	end)

	local canConfirm = Computed(function()
		local typed = typedName:get()
		local selected = selectedName:get()
		return #typed > 0 or #selected > 0
	end)

	local confirmColor = Computed(function()
		if canConfirm:get() then return CONFIRM_HOT end
		return CONFIRM_DIM
	end)

	local function getActiveName()
		local typed = typedName:get()
		if #typed > 0 then return typed end
		return selectedName:get()
	end

	local function onConfirm()
		local name = getActiveName()
		if #name == 0 then return end
		if onNameConfirmed then
			onNameConfirmed(name)
		end
	end

	local nameButtons = ForPairs(previousNames, function(index, name)
		local isSelected = Computed(function()
			return selectedName:get() == name
		end)

		local isFirst = (index == 1)

		return index, New "TextButton" {
			Name = "NameBtn_" .. name,
			LayoutOrder = index,
			Size = UDim2.new(1, 0, 0, 56),
			BackgroundColor3 = Computed(function()
				if isSelected:get() then return BUTTON_SELECTED end
				return BUTTON_BG
			end),
			BackgroundTransparency = 0,
			Text = "",
			AutoButtonColor = false,

			[OnEvent "Activated"] = function()
				selectedName:set(name)
				typedName:set("")
			end,

			[Children] = {
				New "UICorner" { CornerRadius = UDim.new(0, 12) },

				New "UIStroke" {
					Color = Computed(function()
						if isSelected:get() then return ACCENT_CYAN end
						return Color3.fromRGB(30, 45, 70)
					end),
					Thickness = Computed(function()
						return isSelected:get() and 2.5 or 1
					end),
				},

				New "TextLabel" {
					Name = "NameText",
					AnchorPoint = Vector2.new(0, 0.5),
					Position = UDim2.new(0.05, 0, 0.5, 0),
					Size = UDim2.fromScale(0.62, 0.55),
					BackgroundTransparency = 1,
					Text = name,
					TextColor3 = Computed(function()
						if isSelected:get() then return ACCENT_CYAN end
						return TEXT_WHITE
					end),
					Font = Enum.Font.GothamBlack,
					TextScaled = true,
					TextXAlignment = Enum.TextXAlignment.Left,
					[Children] = { New "UITextSizeConstraint" { MaxTextSize = 24 } },
				},

				New "Frame" {
					Name = "BadgePill",
					AnchorPoint = Vector2.new(1, 0.5),
					Position = UDim2.new(0.95, 0, 0.5, 0),
					Size = UDim2.fromScale(0.28, 0.50),
					BackgroundColor3 = Computed(function()
						if isFirst then return Color3.fromRGB(0, 50, 90) end
						return Color3.fromRGB(20, 28, 50)
					end),
					BackgroundTransparency = 0.2,

					[Children] = {
						New "UICorner" { CornerRadius = UDim.new(0.4, 0) },
						New "TextLabel" {
							AnchorPoint = Vector2.new(0.5, 0.5),
							Position = UDim2.fromScale(0.5, 0.5),
							Size = UDim2.fromScale(0.9, 0.75),
							BackgroundTransparency = 1,
							Text = isFirst and "LAST PLAYED" or "PREVIOUS",
							TextColor3 = isFirst and ACCENT_CYAN or TEXT_DIM,
							Font = Enum.Font.GothamBold,
							TextScaled = true,
							[Children] = { New "UITextSizeConstraint" { MaxTextSize = 14 } },
						},
					},
				},
			},
		}
	end, Fusion.cleanup)

	local hasPreviousNames = Computed(function()
		return #previousNames:get() > 0
	end)

	local screenGui = New "ScreenGui" {
		Name = "LakelandNameEntryUI",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = 150,
		Parent = playerGui,

		[Children] = {
			New "Frame" {
				Name = "Overlay",
				Size = UDim2.fromScale(1, 1),
				BackgroundColor3 = Color3.fromRGB(3, 5, 12),
				BackgroundTransparency = 1,
				Visible = visible,

				[Children] = {
					New "Frame" {
						Name = "Panel",
						AnchorPoint = Vector2.new(0.5, 0.5),
						Position = UDim2.fromScale(0.5, 0.5),
						Size = UDim2.fromScale(0.48, 0.80),
						BackgroundColor3 = PANEL_BG,
						BackgroundTransparency = 0,

						[Children] = {
							New "UICorner" { CornerRadius = UDim.new(0, 18) },

							New "UIStroke" {
								Color = ACCENT_HOT,
								Thickness = 2.5,
								Transparency = 0.2,
							},

							New "UIPadding" {
								PaddingLeft = UDim.new(0.05, 0),
								PaddingRight = UDim.new(0.05, 0),
								PaddingTop = UDim.new(0.03, 0),
								PaddingBottom = UDim.new(0.03, 0),
							},

							New "UIListLayout" {
								SortOrder = Enum.SortOrder.LayoutOrder,
								FillDirection = Enum.FillDirection.Vertical,
								HorizontalAlignment = Enum.HorizontalAlignment.Center,
								Padding = UDim.new(0.015, 0),
							},

							-- Header
							New "TextLabel" {
								Name = "Header",
								LayoutOrder = 1,
								Size = UDim2.fromScale(1, 0.09),
								BackgroundTransparency = 1,
								Text = "ENTER YOUR NAME",
								TextColor3 = TEXT_WHITE,
								Font = Enum.Font.GothamBlack,
								TextScaled = true,
								[Children] = {
									New "UITextSizeConstraint" { MaxTextSize = 42 },
									New "UIStroke" {
										Color = ACCENT_HOT,
										Thickness = 1.5,
										Transparency = 0.4,
									},
								},
							},

							-- Accent line
							New "Frame" {
								Name = "AccentLine",
								LayoutOrder = 2,
								Size = UDim2.fromScale(0.5, 0.005),
								BackgroundColor3 = ACCENT_HOT,
								BorderSizePixel = 0,
								[Children] = { New "UICorner" { CornerRadius = UDim.new(0.5, 0) } },
							},

							-- Subtitle
							New "TextLabel" {
								Name = "SubHeader",
								LayoutOrder = 3,
								Size = UDim2.fromScale(0.95, 0.05),
								BackgroundTransparency = 1,
								Text = "Type a new name or pick a previous one below",
								TextColor3 = TEXT_DIM,
								Font = Enum.Font.GothamBold,
								TextScaled = true,
								[Children] = { New "UITextSizeConstraint" { MaxTextSize = 20 } },
							},

							-- Text input
							New "Frame" {
								Name = "InputWrap",
								LayoutOrder = 4,
								Size = UDim2.fromScale(1, 0.09),
								BackgroundColor3 = INPUT_BG,
								BackgroundTransparency = 0,

								[Children] = {
									New "UICorner" { CornerRadius = UDim.new(0, 12) },

									New "UIStroke" {
										Color = Computed(function()
											if #typedName:get() > 0 then return ACCENT_CYAN end
											return Color3.fromRGB(30, 45, 70)
										end),
										Thickness = 2,
										Transparency = 0.1,
									},

								New "TextBox" {
									Name = "NameInput",
									AnchorPoint = Vector2.new(0.5, 0.5),
									Position = UDim2.fromScale(0.5, 0.5),
									Size = UDim2.fromScale(0.9, 0.65),
									BackgroundTransparency = 1,
									Text = "",
									PlaceholderText = "Type your name...",
									PlaceholderColor3 = TEXT_DIM,
									TextColor3 = TEXT_WHITE,
									Font = Enum.Font.GothamBold,
									TextScaled = true,
									ClearTextOnFocus = false,

									[OnChange "Text"] = function(newText)
										local cleaned = string.sub(newText, 1, 20)
										typedName:set(cleaned)
										if #cleaned > 0 then
											selectedName:set("")
										end
									end,

										[Children] = { New "UITextSizeConstraint" { MaxTextSize = 28 } },
									},
								},
							},

							-- OR divider
							New "Frame" {
								Name = "DividerRow",
								LayoutOrder = 5,
								Size = UDim2.fromScale(1, 0.04),
								BackgroundTransparency = 1,
								Visible = hasPreviousNames,

								[Children] = {
									New "Frame" {
										AnchorPoint = Vector2.new(0, 0.5),
										Position = UDim2.new(0, 0, 0.5, 0),
										Size = UDim2.fromScale(0.38, 0.04),
										BackgroundColor3 = DIVIDER_COLOR,
										BorderSizePixel = 0,
									},

									New "TextLabel" {
										AnchorPoint = Vector2.new(0.5, 0.5),
										Position = UDim2.fromScale(0.5, 0.5),
										Size = UDim2.fromScale(0.24, 0.8),
										BackgroundTransparency = 1,
										Text = "OR SELECT",
										TextColor3 = TEXT_DIM,
										Font = Enum.Font.GothamBold,
										TextScaled = true,
										[Children] = { New "UITextSizeConstraint" { MaxTextSize = 16 } },
									},

									New "Frame" {
										AnchorPoint = Vector2.new(1, 0.5),
										Position = UDim2.new(1, 0, 0.5, 0),
										Size = UDim2.fromScale(0.38, 0.04),
										BackgroundColor3 = DIVIDER_COLOR,
										BorderSizePixel = 0,
									},
								},
							},

							-- Previous names list
							New "ScrollingFrame" {
								Name = "PreviousNamesList",
								LayoutOrder = 6,
								Size = UDim2.fromScale(1, 0.45),
								BackgroundTransparency = 1,
								ScrollBarThickness = 5,
								ScrollBarImageColor3 = ACCENT_HOT,
								CanvasSize = UDim2.fromScale(0, 0),
								AutomaticCanvasSize = Enum.AutomaticSize.Y,
								Visible = hasPreviousNames,

								[Children] = {
									New "UIListLayout" {
										SortOrder = Enum.SortOrder.LayoutOrder,
										Padding = UDim.new(0, 8),
									},

									nameButtons,
								},
							},

							-- Spacer
							New "Frame" {
								Name = "Spacer",
								LayoutOrder = 7,
								Size = UDim2.fromScale(1, 0.01),
								BackgroundTransparency = 1,
							},

							-- Confirm button
							New "TextButton" {
								Name = "ConfirmButton",
								LayoutOrder = 8,
								Size = Computed(function()
									local s = animatedConfirmScale:get()
									return UDim2.fromScale(0.65 * s, 0.10 * s)
								end),
								BackgroundColor3 = confirmColor,
								Text = "LAUNCH",
								TextColor3 = Computed(function()
									if canConfirm:get() then return TEXT_WHITE end
									return Color3.fromRGB(50, 60, 80)
								end),
								Font = Enum.Font.GothamBlack,
								TextScaled = true,
								AutoButtonColor = false,

								[OnEvent "Activated"] = onConfirm,

								[OnEvent "MouseEnter"] = function()
									if canConfirm:get() then
										confirmScale:set(1.06)
									end
								end,

								[OnEvent "MouseLeave"] = function()
									confirmScale:set(1)
								end,

								[Children] = {
									New "UICorner" { CornerRadius = UDim.new(0.3, 0) },

									New "UIStroke" {
										Color = Computed(function()
											if canConfirm:get() then return Color3.fromRGB(255, 80, 140) end
											return Color3.fromRGB(30, 40, 60)
										end),
										Thickness = 2.5,
										Transparency = 0.1,
									},

									New "UIGradient" {
										Color = ColorSequence.new(
											Color3.fromRGB(255, 255, 255),
											Color3.fromRGB(200, 180, 190)
										),
										Rotation = 90,
									},

									New "UITextSizeConstraint" { MaxTextSize = 44 },
								},
							},
						},
					},
				},
			},
		},
	}

	nameInputBox = screenGui:FindFirstChild("NameInput", true)

	local function reset()
		typedName:set("")
		selectedName:set("")
		if nameInputBox then
			nameInputBox.Text = ""
		end
	end

	local function destroy()
		screenGui:Destroy()
	end

	return {
		reset = reset,
		destroy = destroy,
	}
end

return LakelandNameEntryUI
