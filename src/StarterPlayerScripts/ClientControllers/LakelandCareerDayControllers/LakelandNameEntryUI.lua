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

local BG_PANEL = Color3.fromRGB(10, 16, 30)
local BORDER_CYAN = Color3.fromRGB(0, 140, 200)
local ACCENT_CYAN = Color3.fromRGB(0, 200, 255)
local TEXT_PRIMARY = Color3.fromRGB(220, 235, 255)
local TEXT_DIM = Color3.fromRGB(60, 90, 130)
local DIVIDER_COLOR = Color3.fromRGB(0, 70, 110)
local LAUNCH_GREEN = Color3.fromRGB(0, 220, 110)
local LAUNCH_GREEN_GLOW = Color3.fromRGB(0, 255, 140)
local INPUT_BG = Color3.fromRGB(12, 20, 36)

local LakelandNameEntryUI = {}

function LakelandNameEntryUI.new(playerGui, gameState, previousNames, onNameConfirmed)
	local typedName = Value("")
	local selectedName = Value("")

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
		if canConfirm:get() then return LAUNCH_GREEN end
		return Color3.fromRGB(20, 30, 45)
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
			Size = UDim2.new(1, 0, 0, isFirst and 50 or 42),
			BackgroundColor3 = Computed(function()
				if isSelected:get() then
					return Color3.fromRGB(0, 45, 85)
				end
				return Color3.fromRGB(10, 18, 32)
			end),
			BackgroundTransparency = 0.02,
			Text = "",
			AutoButtonColor = false,

			[OnEvent "Activated"] = function()
				selectedName:set(name)
				typedName:set("")
			end,

			[Children] = {
				New "UICorner" {
					CornerRadius = UDim.new(0, 8),
				},

				New "UIStroke" {
					Color = Computed(function()
						if isSelected:get() then return ACCENT_CYAN end
						return Color3.fromRGB(20, 35, 55)
					end),
					Thickness = Computed(function()
						return isSelected:get() and 2 or 0
					end),
				},

				New "TextLabel" {
					Name = "NameText",
					AnchorPoint = Vector2.new(0, 0.5),
					Position = UDim2.new(0.04, 0, 0.5, 0),
					Size = UDim2.fromScale(0.72, 0.55),
					BackgroundTransparency = 1,
					Text = name,
					TextColor3 = Computed(function()
						if isSelected:get() then return ACCENT_CYAN end
						return TEXT_PRIMARY
					end),
					Font = isFirst and Enum.Font.GothamBlack or Enum.Font.GothamBold,
					TextScaled = true,
					TextXAlignment = Enum.TextXAlignment.Left,
				},

				New "TextLabel" {
					Name = "Badge",
					AnchorPoint = Vector2.new(1, 0.5),
					Position = UDim2.new(0.96, 0, 0.5, 0),
					Size = UDim2.fromScale(0.18, 0.45),
					BackgroundTransparency = 1,
					Text = isFirst and "LAST PILOT" or ("PILOT #" .. index),
					TextColor3 = isFirst and ACCENT_CYAN or TEXT_DIM,
					Font = Enum.Font.GothamBold,
					TextScaled = true,
					TextXAlignment = Enum.TextXAlignment.Right,
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
						Size = UDim2.fromScale(0.44, 0.78),
						BackgroundColor3 = BG_PANEL,
						BackgroundTransparency = 0.02,

						[Children] = {
							New "UICorner" {
								CornerRadius = UDim.new(0.02, 0),
							},

							New "UIStroke" {
								Color = BORDER_CYAN,
								Thickness = 2.5,
								Transparency = 0.15,
							},

							New "UIGradient" {
								Color = ColorSequence.new(
									Color3.fromRGB(255, 255, 255),
									Color3.fromRGB(155, 170, 195)
								),
								Rotation = 90,
							},

							New "Frame" {
								Name = "HeaderBar",
								AnchorPoint = Vector2.new(0.5, 0),
								Position = UDim2.fromScale(0.5, 0),
								Size = UDim2.fromScale(1, 0.10),
								BackgroundColor3 = Color3.fromRGB(5, 10, 22),
								BackgroundTransparency = 0.1,

								[Children] = {
									New "UICorner" {
										CornerRadius = UDim.new(0.02, 0),
									},

									New "Frame" {
										Name = "CyanLine",
										AnchorPoint = Vector2.new(0, 1),
										Position = UDim2.fromScale(0, 1),
										Size = UDim2.new(1, 0, 0, 2),
										BackgroundColor3 = BORDER_CYAN,
										BackgroundTransparency = 0.3,
										BorderSizePixel = 0,
									},

									New "TextLabel" {
										Name = "Header",
										AnchorPoint = Vector2.new(0.5, 0.5),
										Position = UDim2.fromScale(0.5, 0.45),
										Size = UDim2.fromScale(0.85, 0.55),
										BackgroundTransparency = 1,
										Text = "PILOT IDENTIFICATION",
										TextColor3 = ACCENT_CYAN,
										Font = Enum.Font.GothamBlack,
										TextScaled = true,
									},
								},
							},

							New "Frame" {
								Name = "Content",
								AnchorPoint = Vector2.new(0.5, 0),
								Position = UDim2.fromScale(0.5, 0.11),
								Size = UDim2.fromScale(0.88, 0.86),
								BackgroundTransparency = 1,

								[Children] = {
									New "UIListLayout" {
										SortOrder = Enum.SortOrder.LayoutOrder,
										FillDirection = Enum.FillDirection.Vertical,
										HorizontalAlignment = Enum.HorizontalAlignment.Center,
										Padding = UDim.new(0.015, 0),
									},

									New "TextLabel" {
										Name = "SubHeader",
										LayoutOrder = 1,
										Size = UDim2.fromScale(0.9, 0.04),
										BackgroundTransparency = 1,
										Text = "Enter your callsign or select a previous pilot",
										TextColor3 = TEXT_DIM,
										Font = Enum.Font.Gotham,
										TextScaled = true,
									},

									New "Frame" {
										Name = "InputWrap",
										LayoutOrder = 2,
										Size = UDim2.fromScale(1, 0.10),
										BackgroundColor3 = INPUT_BG,
										BackgroundTransparency = 0.02,

										[Children] = {
											New "UICorner" {
												CornerRadius = UDim.new(0.18, 0),
											},

											New "UIStroke" {
												Color = Computed(function()
													if #typedName:get() > 0 then return ACCENT_CYAN end
													return Color3.fromRGB(20, 35, 55)
												end),
												Thickness = 2,
												Transparency = 0.15,
											},

											New "TextBox" {
												Name = "NameInput",
												AnchorPoint = Vector2.new(0.5, 0.5),
												Position = UDim2.fromScale(0.5, 0.5),
												Size = UDim2.fromScale(0.9, 0.65),
												BackgroundTransparency = 1,
												Text = "",
												PlaceholderText = "Enter callsign...",
												PlaceholderColor3 = TEXT_DIM,
												TextColor3 = TEXT_PRIMARY,
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
											},
										},
									},

									New "Frame" {
										Name = "DividerRow",
										LayoutOrder = 3,
										Size = UDim2.fromScale(1, 0.04),
										BackgroundTransparency = 1,

										[Children] = {
											New "Frame" {
												AnchorPoint = Vector2.new(0, 0.5),
												Position = UDim2.new(0, 0, 0.5, 0),
												Size = UDim2.fromScale(0.4, 0.05),
												BackgroundColor3 = DIVIDER_COLOR,
												BackgroundTransparency = 0.2,
												BorderSizePixel = 0,
											},

											New "TextLabel" {
												AnchorPoint = Vector2.new(0.5, 0.5),
												Position = UDim2.fromScale(0.5, 0.5),
												Size = UDim2.fromScale(0.2, 0.7),
												BackgroundTransparency = 1,
												Text = "OR",
												TextColor3 = TEXT_DIM,
												Font = Enum.Font.GothamBold,
												TextScaled = true,
											},

											New "Frame" {
												AnchorPoint = Vector2.new(1, 0.5),
												Position = UDim2.new(1, 0, 0.5, 0),
												Size = UDim2.fromScale(0.4, 0.05),
												BackgroundColor3 = DIVIDER_COLOR,
												BackgroundTransparency = 0.2,
												BorderSizePixel = 0,
											},
										},
										Visible = hasPreviousNames,
									},

									New "ScrollingFrame" {
										Name = "PreviousNamesList",
										LayoutOrder = 4,
										Size = UDim2.fromScale(1, 0.52),
										BackgroundTransparency = 1,
										ScrollBarThickness = 4,
										ScrollBarImageColor3 = BORDER_CYAN,
										CanvasSize = UDim2.fromScale(0, 0),
										AutomaticCanvasSize = Enum.AutomaticSize.Y,
										Visible = hasPreviousNames,

										[Children] = {
											New "UIListLayout" {
												SortOrder = Enum.SortOrder.LayoutOrder,
												Padding = UDim.new(0, 6),
											},

											nameButtons,
										},
									},

									New "Frame" {
										Name = "Spacer",
										LayoutOrder = 5,
										Size = UDim2.fromScale(1, 0.01),
										BackgroundTransparency = 1,
									},

									New "TextButton" {
										Name = "ConfirmButton",
										LayoutOrder = 6,
										Size = Computed(function()
											local s = animatedConfirmScale:get()
											return UDim2.fromScale(0.6 * s, 0.10 * s)
										end),
										BackgroundColor3 = confirmColor,
										Text = "LAUNCH",
										TextColor3 = Computed(function()
											if canConfirm:get() then
												return Color3.fromRGB(255, 255, 255)
											end
											return Color3.fromRGB(40, 55, 75)
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
											New "UICorner" {
												CornerRadius = UDim.new(0.25, 0),
											},

											New "UIStroke" {
												Color = Computed(function()
													if canConfirm:get() then return LAUNCH_GREEN_GLOW end
													return Color3.fromRGB(20, 35, 50)
												end),
												Thickness = 2.5,
												Transparency = 0.1,
											},
										},
									},
								},
							},
						},
					},
				},
			},
		},
	}

	local function reset()
		typedName:set("")
		selectedName:set("")
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
