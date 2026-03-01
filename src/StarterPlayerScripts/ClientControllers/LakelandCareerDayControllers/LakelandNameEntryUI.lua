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
		if canConfirm:get() then
			return Color3.fromRGB(40, 170, 70)
		end
		return Color3.fromRGB(55, 55, 65)
	end)

	local function getActiveName()
		local typed = typedName:get()
		if #typed > 0 then
			return typed
		end
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
			Size = UDim2.new(1, 0, 0, isFirst and 38 or 32),
			BackgroundColor3 = Computed(function()
				if isSelected:get() then
					return Color3.fromRGB(40, 110, 200)
				end
				if isFirst then
					return Color3.fromRGB(40, 40, 55)
				end
				return Color3.fromRGB(30, 30, 42)
			end),
			BackgroundTransparency = 0.1,
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
						if isSelected:get() then
							return Color3.fromRGB(80, 160, 255)
						end
						return Color3.fromRGB(50, 50, 65)
					end),
					Thickness = Computed(function()
						return isSelected:get() and 1.5 or 0
					end),
				},

				New "TextLabel" {
					Name = "NameText",
					AnchorPoint = Vector2.new(0, 0.5),
					Position = UDim2.new(0.05, 0, 0.5, 0),
					Size = UDim2.fromScale(0.7, 0.6),
					BackgroundTransparency = 1,
					Text = name,
					TextColor3 = Computed(function()
						if isSelected:get() then
							return Color3.fromRGB(255, 255, 255)
						end
						return Color3.fromRGB(200, 200, 215)
					end),
					Font = isFirst and Enum.Font.GothamBlack or Enum.Font.GothamBold,
					TextScaled = true,
					TextXAlignment = Enum.TextXAlignment.Left,
				},

				New "TextLabel" {
					Name = "Badge",
					AnchorPoint = Vector2.new(1, 0.5),
					Position = UDim2.new(0.95, 0, 0.5, 0),
					Size = UDim2.fromScale(0.15, 0.5),
					BackgroundTransparency = 1,
					Text = isFirst and "LAST" or ("#" .. index),
					TextColor3 = isFirst and Color3.fromRGB(120, 180, 255) or Color3.fromRGB(90, 90, 110),
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
				BackgroundColor3 = Color3.fromRGB(6, 6, 14),
				BackgroundTransparency = 0.15,
				Visible = visible,

				[Children] = {
					New "Frame" {
						Name = "Panel",
						AnchorPoint = Vector2.new(0.5, 0.5),
						Position = UDim2.fromScale(0.5, 0.48),
						Size = UDim2.fromScale(0.32, 0.65),
						BackgroundColor3 = Color3.fromRGB(16, 16, 28),
						BackgroundTransparency = 0.05,

						[Children] = {
							New "UICorner" {
								CornerRadius = UDim.new(0.025, 0),
							},

							New "UIStroke" {
								Color = Color3.fromRGB(60, 60, 80),
								Thickness = 1.5,
								Transparency = 0.3,
							},

							New "UIPadding" {
								PaddingTop = UDim.new(0.04, 0),
								PaddingBottom = UDim.new(0.04, 0),
								PaddingLeft = UDim.new(0.06, 0),
								PaddingRight = UDim.new(0.06, 0),
							},

							New "UIListLayout" {
								SortOrder = Enum.SortOrder.LayoutOrder,
								FillDirection = Enum.FillDirection.Vertical,
								HorizontalAlignment = Enum.HorizontalAlignment.Center,
								Padding = UDim.new(0.02, 0),
							},

							New "TextLabel" {
								Name = "Header",
								LayoutOrder = 1,
								Size = UDim2.fromScale(1, 0.08),
								BackgroundTransparency = 1,
								Text = "WHO'S PLAYING?",
								TextColor3 = Color3.fromRGB(255, 255, 255),
								Font = Enum.Font.GothamBlack,
								TextScaled = true,
							},

							New "TextLabel" {
								Name = "SubHeader",
								LayoutOrder = 2,
								Size = UDim2.fromScale(0.8, 0.04),
								BackgroundTransparency = 1,
								Text = "Type a new name or pick one below",
								TextColor3 = Color3.fromRGB(100, 100, 125),
								Font = Enum.Font.Gotham,
								TextScaled = true,
							},

							New "Frame" {
								Name = "InputWrap",
								LayoutOrder = 3,
								Size = UDim2.fromScale(1, 0.1),
								BackgroundColor3 = Color3.fromRGB(30, 30, 45),
								BackgroundTransparency = 0.1,

								[Children] = {
									New "UICorner" {
										CornerRadius = UDim.new(0.25, 0),
									},

									New "UIStroke" {
										Color = Computed(function()
											if #typedName:get() > 0 then
												return Color3.fromRGB(80, 160, 255)
											end
											return Color3.fromRGB(50, 50, 65)
										end),
										Thickness = 1.5,
										Transparency = 0.3,
									},

									New "TextBox" {
										Name = "NameInput",
										AnchorPoint = Vector2.new(0.5, 0.5),
										Position = UDim2.fromScale(0.5, 0.5),
										Size = UDim2.fromScale(0.88, 0.7),
										BackgroundTransparency = 1,
										Text = "",
										PlaceholderText = "Type your name...",
										PlaceholderColor3 = Color3.fromRGB(90, 90, 110),
										TextColor3 = Color3.fromRGB(255, 255, 255),
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
								LayoutOrder = 4,
								Size = UDim2.fromScale(1, 0.035),
								BackgroundTransparency = 1,

								[Children] = {
									New "Frame" {
										AnchorPoint = Vector2.new(0, 0.5),
										Position = UDim2.new(0, 0, 0.5, 0),
										Size = UDim2.fromScale(0.38, 0.03),
										BackgroundColor3 = Color3.fromRGB(50, 50, 65),
										BorderSizePixel = 0,
									},

									New "TextLabel" {
										AnchorPoint = Vector2.new(0.5, 0.5),
										Position = UDim2.fromScale(0.5, 0.5),
										Size = UDim2.fromScale(0.24, 0.8),
										BackgroundTransparency = 1,
										Text = "OR",
										TextColor3 = Color3.fromRGB(80, 80, 100),
										Font = Enum.Font.GothamBold,
										TextScaled = true,
									},

									New "Frame" {
										AnchorPoint = Vector2.new(1, 0.5),
										Position = UDim2.new(1, 0, 0.5, 0),
										Size = UDim2.fromScale(0.38, 0.03),
										BackgroundColor3 = Color3.fromRGB(50, 50, 65),
										BorderSizePixel = 0,
									},
								},
								Visible = hasPreviousNames,
							},

							New "ScrollingFrame" {
								Name = "PreviousNamesList",
								LayoutOrder = 5,
								Size = UDim2.fromScale(1, 0.42),
								BackgroundTransparency = 1,
								ScrollBarThickness = 3,
								ScrollBarImageColor3 = Color3.fromRGB(70, 70, 90),
								CanvasSize = UDim2.fromScale(0, 0),
								AutomaticCanvasSize = Enum.AutomaticSize.Y,
								Visible = hasPreviousNames,

								[Children] = {
									New "UIListLayout" {
										SortOrder = Enum.SortOrder.LayoutOrder,
										Padding = UDim.new(0, 5),
									},

									nameButtons,
								},
							},

							New "Frame" {
								Name = "BottomSpacer",
								LayoutOrder = 6,
								Size = UDim2.fromScale(1, 0.015),
								BackgroundTransparency = 1,
							},

							New "TextButton" {
								Name = "ConfirmButton",
								LayoutOrder = 7,
								Size = Computed(function()
									local s = animatedConfirmScale:get()
									return UDim2.fromScale(0.55 * s, 0.09 * s)
								end),
								BackgroundColor3 = confirmColor,
								Text = "START RACE",
								TextColor3 = Computed(function()
									if canConfirm:get() then
										return Color3.fromRGB(255, 255, 255)
									end
									return Color3.fromRGB(100, 100, 110)
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
										CornerRadius = UDim.new(0.35, 0),
									},

									New "UIStroke" {
										Color = Computed(function()
											if canConfirm:get() then
												return Color3.fromRGB(70, 220, 110)
											end
											return Color3.fromRGB(50, 50, 60)
										end),
										Thickness = 2,
										Transparency = 0.2,
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
