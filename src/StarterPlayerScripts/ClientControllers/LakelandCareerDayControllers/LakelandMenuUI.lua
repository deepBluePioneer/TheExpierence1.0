local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CustomPackages = ReplicatedStorage.CustomPackages
local Fusion = require(CustomPackages.FusionRoot.Fusion)

local New = Fusion.New
local Value = Fusion.Value
local Computed = Fusion.Computed
local Children = Fusion.Children
local OnEvent = Fusion.OnEvent
local Spring = Fusion.Spring

local ACCENT_HOT = Color3.fromRGB(255, 30, 100)
local ACCENT_CYAN = Color3.fromRGB(0, 220, 255)
local TEXT_WHITE = Color3.fromRGB(255, 255, 255)
local TEXT_DIM = Color3.fromRGB(120, 130, 160)
local PANEL_BG = Color3.fromRGB(10, 12, 24)
local KEY_COLOR = ACCENT_CYAN
local CUBE_RED = Color3.fromRGB(255, 50, 80)
local CUBE_BLUE = Color3.fromRGB(60, 140, 255)
local CUBE_GREEN = Color3.fromRGB(60, 255, 80)

local RANK_COLORS = {
	[1] = Color3.fromRGB(255, 215, 0),
	[2] = Color3.fromRGB(200, 200, 220),
	[3] = Color3.fromRGB(205, 140, 55),
}

local LakelandMenuUI = {}

local function formatNumber(n)
	local s = tostring(math.floor(n))
	local parts = {}
	while #s > 3 do
		table.insert(parts, 1, s:sub(-3))
		s = s:sub(1, -4)
	end
	table.insert(parts, 1, s)
	return table.concat(parts, ",")
end

function LakelandMenuUI.new(playerGui, gameState, topScores, beatIntensity, onPlay)
	local isHovered = Value(false)

	local buttonScale = Spring(Computed(function()
		return isHovered:get() and 1.08 or 1
	end), 25, 0.6)

	local visible = Computed(function()
		return gameState:get() == "MENU"
	end)

	local b = beatIntensity or Value(0)

	local titleScale = Computed(function()
		return 1 + b:get() * 0.04
	end)
	local lineWidth = Computed(function()
		return 0.35 + b:get() * 0.08
	end)
	local strokePulse = Computed(function()
		return 2 + b:get() * 3
	end)
	local strokeTrans = Computed(function()
		return 0.3 - b:get() * 0.25
	end)

	local function makeTop3Entry(rank, entry)
		local isEmpty = (entry.name == "---")
		local rankColor = RANK_COLORS[rank] or TEXT_DIM
		local medals = { "1ST", "2ND", "3RD" }
		local medalText = medals[rank] or ("#" .. rank)

		return New "Frame" {
			Name = "Top3_" .. rank,
			LayoutOrder = rank,
			Size = UDim2.fromScale(0.30, 1),
			BackgroundTransparency = 1,

			[Children] = {
				New "UIListLayout" {
					FillDirection = Enum.FillDirection.Horizontal,
					HorizontalAlignment = Enum.HorizontalAlignment.Center,
					VerticalAlignment = Enum.VerticalAlignment.Center,
					Padding = UDim.new(0.03, 0),
				},

				New "TextLabel" {
					Name = "Medal",
					LayoutOrder = 1,
					Size = UDim2.fromScale(0.18, 0.7),
					BackgroundTransparency = 1,
					Text = medalText,
					TextColor3 = rankColor,
					Font = Enum.Font.GothamBlack,
					TextScaled = true,
					TextXAlignment = Enum.TextXAlignment.Right,
					[Children] = { New "UITextSizeConstraint" { MaxTextSize = 18 } },
				},

				New "TextLabel" {
					Name = "Name",
					LayoutOrder = 2,
					Size = UDim2.fromScale(0.48, 0.7),
					BackgroundTransparency = 1,
					Text = isEmpty and "---" or entry.name,
					TextColor3 = isEmpty and Color3.fromRGB(40, 50, 70) or TEXT_WHITE,
					Font = Enum.Font.GothamBold,
					TextScaled = true,
					TextXAlignment = Enum.TextXAlignment.Left,
					TextTruncate = Enum.TextTruncate.AtEnd,
					[Children] = { New "UITextSizeConstraint" { MaxTextSize = 16 } },
				},

				New "TextLabel" {
					Name = "Score",
					LayoutOrder = 3,
					Size = UDim2.fromScale(0.30, 0.7),
					BackgroundTransparency = 1,
					Text = isEmpty and "-" or formatNumber(entry.score),
					TextColor3 = isEmpty and Color3.fromRGB(40, 50, 70) or rankColor,
					Font = Enum.Font.GothamBlack,
					TextScaled = true,
					TextXAlignment = Enum.TextXAlignment.Right,
					[Children] = { New "UITextSizeConstraint" { MaxTextSize = 16 } },
				},
			},
		}
	end

	local top3Frames = Computed(function()
		local scores = topScores:get()
		local frames = {}
		for i = 1, math.min(3, #scores) do
			local entry = scores[i]
			if entry then
				table.insert(frames, makeTop3Entry(entry.rank or i, entry))
			end
		end
		return frames
	end)

	local screenGui = New "ScreenGui" {
		Name = "LakelandMenuUI",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = 100,
		Parent = playerGui,

		[Children] = {
			New "Frame" {
				Name = "Root",
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				Visible = visible,

				[Children] = {
					New "Frame" {
						Name = "TitleBlock",
						AnchorPoint = Vector2.new(0.5, 0),
						Position = UDim2.fromScale(0.5, 0.04),
						Size = Computed(function()
							local s = titleScale:get()
							return UDim2.fromScale(0.9 * s, 0.18 * s)
						end),
						BackgroundTransparency = 1,

						[Children] = {
							New "TextLabel" {
								Name = "Title",
								AnchorPoint = Vector2.new(0.5, 0),
								Position = UDim2.fromScale(0.5, 0),
								Size = UDim2.fromScale(1, 0.7),
								BackgroundTransparency = 1,
								Text = "HYPERDRIVE",
								TextColor3 = TEXT_WHITE,
								Font = Enum.Font.GothamBlack,
								TextScaled = true,

								[Children] = {
									New "UITextSizeConstraint" { MaxTextSize = 140 },
									New "UIStroke" {
										Color = ACCENT_HOT,
										Thickness = strokePulse,
										Transparency = strokeTrans,
									},
								},
							},

							New "Frame" {
								Name = "AccentLine",
								AnchorPoint = Vector2.new(0.5, 0),
								Position = UDim2.fromScale(0.5, 0.74),
								Size = Computed(function()
									return UDim2.fromScale(lineWidth:get(), 0.02)
								end),
								BackgroundColor3 = ACCENT_HOT,
								BorderSizePixel = 0,

								[Children] = {
									New "UICorner" { CornerRadius = UDim.new(0.5, 0) },
								},
							},
						},
					},

					New "Frame" {
						Name = "HowToPlay",
						AnchorPoint = Vector2.new(0.5, 0),
						Position = UDim2.fromScale(0.5, 0.25),
						Size = UDim2.fromScale(0.6, 0.30),
						BackgroundColor3 = PANEL_BG,
						BackgroundTransparency = 0.15,

						[Children] = {
							New "UICorner" { CornerRadius = UDim.new(0, 12) },
							New "UIStroke" {
								Color = ACCENT_HOT,
								Thickness = strokePulse,
								Transparency = Computed(function()
									return 0.5 - b:get() * 0.3
								end),
							},
							New "UIPadding" {
								PaddingLeft = UDim.new(0.04, 0),
								PaddingRight = UDim.new(0.04, 0),
								PaddingTop = UDim.new(0.04, 0),
								PaddingBottom = UDim.new(0.04, 0),
							},

							New "TextLabel" {
								Name = "Header",
								AnchorPoint = Vector2.new(0.5, 0),
								Position = UDim2.fromScale(0.5, 0),
								Size = UDim2.fromScale(1, 0.15),
								BackgroundTransparency = 1,
								Text = "HOW TO PLAY",
								TextColor3 = ACCENT_HOT,
								Font = Enum.Font.GothamBlack,
								TextScaled = true,
								[Children] = { New "UITextSizeConstraint" { MaxTextSize = 26 } },
							},

							New "Frame" {
								Name = "ControlsSection",
								AnchorPoint = Vector2.new(0.5, 0),
								Position = UDim2.fromScale(0.5, 0.20),
								Size = UDim2.fromScale(0.9, 0.40),
								BackgroundTransparency = 1,

								[Children] = {
									New "UIListLayout" {
										FillDirection = Enum.FillDirection.Vertical,
										HorizontalAlignment = Enum.HorizontalAlignment.Center,
										Padding = UDim.new(0.08, 0),
									},

									New "Frame" {
										Name = "Row1",
										LayoutOrder = 1,
										Size = UDim2.fromScale(1, 0.40),
										BackgroundTransparency = 1,
										[Children] = {
											New "TextLabel" {
												AnchorPoint = Vector2.new(0, 0.5),
												Position = UDim2.fromScale(0.05, 0.5),
												Size = UDim2.fromScale(0.35, 1),
												BackgroundTransparency = 1,
												Text = "A / D  or  < >",
												TextColor3 = KEY_COLOR,
												Font = Enum.Font.GothamBlack,
												TextScaled = true,
												TextXAlignment = Enum.TextXAlignment.Left,
												[Children] = { New "UITextSizeConstraint" { MaxTextSize = 22 } },
											},
											New "TextLabel" {
												AnchorPoint = Vector2.new(1, 0.5),
												Position = UDim2.fromScale(0.95, 0.5),
												Size = UDim2.fromScale(0.45, 1),
												BackgroundTransparency = 1,
												Text = "SWITCH LANES",
												TextColor3 = TEXT_WHITE,
												Font = Enum.Font.GothamBold,
												TextScaled = true,
												TextXAlignment = Enum.TextXAlignment.Right,
												[Children] = { New "UITextSizeConstraint" { MaxTextSize = 22 } },
											},
										},
									},

									New "Frame" {
										Name = "Row2",
										LayoutOrder = 2,
										Size = UDim2.fromScale(1, 0.40),
										BackgroundTransparency = 1,
										[Children] = {
											New "TextLabel" {
												AnchorPoint = Vector2.new(0, 0.5),
												Position = UDim2.fromScale(0.05, 0.5),
												Size = UDim2.fromScale(0.35, 1),
												BackgroundTransparency = 1,
												Text = "SPACE",
												TextColor3 = KEY_COLOR,
												Font = Enum.Font.GothamBlack,
												TextScaled = true,
												TextXAlignment = Enum.TextXAlignment.Left,
												[Children] = { New "UITextSizeConstraint" { MaxTextSize = 22 } },
											},
											New "TextLabel" {
												AnchorPoint = Vector2.new(1, 0.5),
												Position = UDim2.fromScale(0.95, 0.5),
												Size = UDim2.fromScale(0.45, 1),
												BackgroundTransparency = 1,
												Text = "DEPLOY BOMB",
												TextColor3 = TEXT_WHITE,
												Font = Enum.Font.GothamBold,
												TextScaled = true,
												TextXAlignment = Enum.TextXAlignment.Right,
												[Children] = { New "UITextSizeConstraint" { MaxTextSize = 22 } },
											},
										},
									},
								},
							},

							New "Frame" {
								Name = "Divider",
								AnchorPoint = Vector2.new(0.5, 0),
								Position = UDim2.fromScale(0.5, 0.62),
								Size = UDim2.fromScale(0.85, 0.005),
								BackgroundColor3 = Color3.fromRGB(40, 50, 75),
								BorderSizePixel = 0,
								[Children] = { New "UICorner" { CornerRadius = UDim.new(0.5, 0) } },
							},

							New "Frame" {
								Name = "LegendSection",
								AnchorPoint = Vector2.new(0.5, 1),
								Position = UDim2.fromScale(0.5, 1),
								Size = UDim2.fromScale(0.9, 0.30),
								BackgroundTransparency = 1,

								[Children] = {
									New "UIListLayout" {
										FillDirection = Enum.FillDirection.Horizontal,
										HorizontalAlignment = Enum.HorizontalAlignment.Center,
										VerticalAlignment = Enum.VerticalAlignment.Center,
										Padding = UDim.new(0.06, 0),
									},

									New "Frame" {
										Name = "LegRed",
										LayoutOrder = 1,
										Size = UDim2.fromScale(0.28, 0.8),
										BackgroundTransparency = 1,
										[Children] = {
											New "UIListLayout" {
												FillDirection = Enum.FillDirection.Horizontal,
												VerticalAlignment = Enum.VerticalAlignment.Center,
												Padding = UDim.new(0.06, 0),
											},
											New "Frame" {
												LayoutOrder = 1,
												Size = UDim2.fromScale(0.18, 0.6),
												BackgroundColor3 = CUBE_RED,
												[Children] = { New "UICorner" { CornerRadius = UDim.new(0.2, 0) }, New "UIAspectRatioConstraint" { AspectRatio = 1 } },
											},
											New "TextLabel" {
												LayoutOrder = 2,
												Size = UDim2.fromScale(0.7, 1),
												BackgroundTransparency = 1,
												Text = "AVOID",
												TextColor3 = TEXT_WHITE,
												Font = Enum.Font.GothamBold,
												TextScaled = true,
												TextXAlignment = Enum.TextXAlignment.Left,
												[Children] = { New "UITextSizeConstraint" { MaxTextSize = 18 } },
											},
										},
									},

									New "Frame" {
										Name = "LegBlue",
										LayoutOrder = 2,
										Size = UDim2.fromScale(0.28, 0.8),
										BackgroundTransparency = 1,
										[Children] = {
											New "UIListLayout" {
												FillDirection = Enum.FillDirection.Horizontal,
												VerticalAlignment = Enum.VerticalAlignment.Center,
												Padding = UDim.new(0.06, 0),
											},
											New "Frame" {
												LayoutOrder = 1,
												Size = UDim2.fromScale(0.18, 0.6),
												BackgroundColor3 = CUBE_BLUE,
												[Children] = { New "UICorner" { CornerRadius = UDim.new(0.2, 0) }, New "UIAspectRatioConstraint" { AspectRatio = 1 } },
											},
											New "TextLabel" {
												LayoutOrder = 2,
												Size = UDim2.fromScale(0.7, 1),
												BackgroundTransparency = 1,
												Text = "COLLECT",
												TextColor3 = TEXT_WHITE,
												Font = Enum.Font.GothamBold,
												TextScaled = true,
												TextXAlignment = Enum.TextXAlignment.Left,
												[Children] = { New "UITextSizeConstraint" { MaxTextSize = 18 } },
											},
										},
									},

									New "Frame" {
										Name = "LegGreen",
										LayoutOrder = 3,
										Size = UDim2.fromScale(0.28, 0.8),
										BackgroundTransparency = 1,
										[Children] = {
											New "UIListLayout" {
												FillDirection = Enum.FillDirection.Horizontal,
												VerticalAlignment = Enum.VerticalAlignment.Center,
												Padding = UDim.new(0.06, 0),
											},
											New "Frame" {
												LayoutOrder = 1,
												Size = UDim2.fromScale(0.18, 0.6),
												BackgroundColor3 = CUBE_GREEN,
												[Children] = { New "UICorner" { CornerRadius = UDim.new(0.2, 0) }, New "UIAspectRatioConstraint" { AspectRatio = 1 } },
											},
											New "TextLabel" {
												LayoutOrder = 2,
												Size = UDim2.fromScale(0.7, 1),
												BackgroundTransparency = 1,
												Text = "BOMB",
												TextColor3 = TEXT_WHITE,
												Font = Enum.Font.GothamBold,
												TextScaled = true,
												TextXAlignment = Enum.TextXAlignment.Left,
												[Children] = { New "UITextSizeConstraint" { MaxTextSize = 18 } },
											},
										},
									},
								},
							},
						},
					},

					New "Frame" {
						Name = "LaunchGroup",
						AnchorPoint = Vector2.new(0.5, 0),
						Position = UDim2.fromScale(0.5, 0.58),
						Size = UDim2.fromScale(0.55, 0.10),
						BackgroundTransparency = 1,

						[Children] = {
							New "TextButton" {
								Name = "PlayButton",
								AnchorPoint = Vector2.new(0.5, 0.5),
								Position = UDim2.fromScale(0.5, 0.5),
								Size = Computed(function()
									local s = buttonScale:get()
									local bp = 1 + b:get() * 0.02
									return UDim2.fromScale(0.65 * s * bp, 0.85 * s * bp)
								end),
								BackgroundColor3 = ACCENT_HOT,
								Text = "LAUNCH",
								TextColor3 = TEXT_WHITE,
								Font = Enum.Font.GothamBlack,
								TextScaled = true,
								AutoButtonColor = false,

								[OnEvent "Activated"] = function()
									if onPlay then onPlay() end
								end,

								[OnEvent "MouseEnter"] = function()
									isHovered:set(true)
								end,

								[OnEvent "MouseLeave"] = function()
									isHovered:set(false)
								end,

								[Children] = {
									New "UICorner" { CornerRadius = UDim.new(0.3, 0) },
									New "UIStroke" {
										Color = Color3.fromRGB(255, 80, 140),
										Thickness = Computed(function()
											return 3 + b:get() * 3
										end),
										Transparency = Computed(function()
											return 0.1 - b:get() * 0.1
										end),
									},
									New "UIGradient" {
										Color = ColorSequence.new(
											Color3.fromRGB(255, 255, 255),
											Color3.fromRGB(200, 180, 190)
										),
										Rotation = 90,
									},
									New "UITextSizeConstraint" { MaxTextSize = 52 },
								},
							},
						},
					},

					New "Frame" {
						Name = "Top3Strip",
						AnchorPoint = Vector2.new(0.5, 1),
						Position = UDim2.fromScale(0.5, 0.97),
						Size = UDim2.fromScale(0.85, 0.065),
						BackgroundColor3 = PANEL_BG,
						BackgroundTransparency = 0.2,

						[Children] = {
							New "UICorner" { CornerRadius = UDim.new(0, 8) },
							New "UIStroke" {
								Color = ACCENT_HOT,
								Thickness = 1.5,
								Transparency = Computed(function()
									return 0.5 - b:get() * 0.3
								end),
							},
							New "UIListLayout" {
								FillDirection = Enum.FillDirection.Horizontal,
								HorizontalAlignment = Enum.HorizontalAlignment.Center,
								VerticalAlignment = Enum.VerticalAlignment.Center,
								Padding = UDim.new(0.02, 0),
							},

							top3Frames,
						},
					},
				},
			},
		},
	}

	local function destroy()
		screenGui:Destroy()
	end

	return destroy
end

return LakelandMenuUI
