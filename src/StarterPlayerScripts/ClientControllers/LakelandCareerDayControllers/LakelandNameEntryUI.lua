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
local ForValues = Fusion.ForValues

local LakelandNameEntryUI = {}

function LakelandNameEntryUI.new(playerGui, gameState, previousNames, onNameConfirmed)
	local typedName = Value("")
	local selectedName = Value("")

	local confirmScale = Value(1)
	local animatedConfirmScale = Spring(confirmScale, 35, 0.7)

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
			return Color3.fromRGB(50, 180, 80)
		end
		return Color3.fromRGB(80, 80, 80)
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

	local nameButtons = ForValues(previousNames, function(name)
		local isSelected = Computed(function()
			return selectedName:get() == name
		end)

		return New "TextButton" {
			Name = "NameBtn_" .. name,
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundColor3 = Computed(function()
				if isSelected:get() then
					return Color3.fromRGB(50, 130, 200)
				end
				return Color3.fromRGB(35, 35, 50)
			end),
			BackgroundTransparency = 0.2,
			Text = name,
			TextColor3 = Color3.fromRGB(255, 255, 255),
			Font = Enum.Font.GothamBold,
			TextScaled = true,
			AutoButtonColor = false,

			[OnEvent "Activated"] = function()
				selectedName:set(name)
				typedName:set("")
			end,

			[Children] = {
				New "UICorner" {
					CornerRadius = UDim.new(0, 6),
				},

				New "UIPadding" {
					PaddingTop = UDim.new(0, 6),
					PaddingBottom = UDim.new(0, 6),
					PaddingLeft = UDim.new(0.04, 0),
					PaddingRight = UDim.new(0.04, 0),
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
				BackgroundColor3 = Color3.fromRGB(10, 10, 20),
				BackgroundTransparency = 0.2,
				Visible = visible,

				[Children] = {
					New "Frame" {
						Name = "Panel",
						AnchorPoint = Vector2.new(0.5, 0.5),
						Position = UDim2.fromScale(0.5, 0.45),
						Size = UDim2.fromScale(0.35, 0.55),
						BackgroundColor3 = Color3.fromRGB(20, 20, 35),
						BackgroundTransparency = 0.1,

						[Children] = {
							New "UICorner" {
								CornerRadius = UDim.new(0.03, 0),
							},

							New "UIStroke" {
								Color = Color3.fromRGB(80, 80, 100),
								Thickness = 2,
								Transparency = 0.4,
							},

							New "UIPadding" {
								PaddingTop = UDim.new(0.05, 0),
								PaddingBottom = UDim.new(0.05, 0),
								PaddingLeft = UDim.new(0.06, 0),
								PaddingRight = UDim.new(0.06, 0),
							},

							New "UIListLayout" {
								SortOrder = Enum.SortOrder.LayoutOrder,
								FillDirection = Enum.FillDirection.Vertical,
								HorizontalAlignment = Enum.HorizontalAlignment.Center,
								Padding = UDim.new(0.03, 0),
							},

							New "TextLabel" {
								Name = "Header",
								LayoutOrder = 1,
								Size = UDim2.fromScale(1, 0.1),
								BackgroundTransparency = 1,
								Text = "ENTER YOUR NAME",
								TextColor3 = Color3.fromRGB(255, 255, 255),
								Font = Enum.Font.GothamBold,
								TextScaled = true,
							},

							New "TextBox" {
								Name = "NameInput",
								LayoutOrder = 2,
								Size = UDim2.fromScale(1, 0.12),
								BackgroundColor3 = Color3.fromRGB(40, 40, 55),
								BackgroundTransparency = 0.1,
								Text = "",
								PlaceholderText = "Type your name...",
								PlaceholderColor3 = Color3.fromRGB(120, 120, 140),
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

								[Children] = {
									New "UICorner" {
										CornerRadius = UDim.new(0.2, 0),
									},

									New "UIPadding" {
										PaddingLeft = UDim.new(0.04, 0),
										PaddingRight = UDim.new(0.04, 0),
									},
								},
							},

							-- Previous names section
							New "TextLabel" {
								Name = "OrLabel",
								LayoutOrder = 3,
								Size = UDim2.fromScale(1, 0.06),
								BackgroundTransparency = 1,
								Text = "or select a previous name",
								TextColor3 = Color3.fromRGB(140, 140, 160),
								Font = Enum.Font.Gotham,
								TextScaled = true,
								Visible = hasPreviousNames,
							},

							New "ScrollingFrame" {
								Name = "PreviousNamesList",
								LayoutOrder = 4,
								Size = UDim2.fromScale(1, 0.35),
								BackgroundTransparency = 1,
								ScrollBarThickness = 3,
								ScrollBarImageColor3 = Color3.fromRGB(100, 100, 120),
								CanvasSize = UDim2.fromScale(0, 0),
								AutomaticCanvasSize = Enum.AutomaticSize.Y,
								Visible = hasPreviousNames,

								[Children] = {
									New "UIListLayout" {
										SortOrder = Enum.SortOrder.LayoutOrder,
										Padding = UDim.new(0, 4),
									},

									nameButtons,
								},
							},

							-- Confirm button
							New "TextButton" {
								Name = "ConfirmButton",
								LayoutOrder = 5,
								Size = Computed(function()
									local s = animatedConfirmScale:get()
									return UDim2.fromScale(0.5 * s, 0.1 * s)
								end),
								BackgroundColor3 = confirmColor,
								Text = "CONFIRM",
								TextColor3 = Color3.fromRGB(255, 255, 255),
								Font = Enum.Font.GothamBold,
								TextScaled = true,
								AutoButtonColor = false,

								[OnEvent "Activated"] = onConfirm,

								[OnEvent "MouseEnter"] = function()
									if canConfirm:get() then
										confirmScale:set(1.08)
									end
								end,

								[OnEvent "MouseLeave"] = function()
									confirmScale:set(1)
								end,

								[Children] = {
									New "UICorner" {
										CornerRadius = UDim.new(0.3, 0),
									},

									New "UIStroke" {
										Color = Computed(function()
											if canConfirm:get() then
												return Color3.fromRGB(80, 220, 120)
											end
											return Color3.fromRGB(60, 60, 60)
										end),
										Thickness = 2,
										Transparency = 0.3,
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
