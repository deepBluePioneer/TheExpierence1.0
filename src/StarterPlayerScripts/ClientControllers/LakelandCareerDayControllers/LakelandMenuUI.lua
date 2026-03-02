local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CustomPackages = ReplicatedStorage.CustomPackages
local Fusion = require(CustomPackages.FusionRoot.Fusion)

local New = Fusion.New
local Value = Fusion.Value
local Computed = Fusion.Computed
local Children = Fusion.Children
local OnEvent = Fusion.OnEvent
local Spring = Fusion.Spring
local ForPairs = Fusion.ForPairs

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

local RANK_COLORS = {
	[1] = Color3.fromRGB(255, 215, 0),
	[2] = Color3.fromRGB(192, 192, 210),
	[3] = Color3.fromRGB(205, 137, 63),
}

local RANK_ICONS = {
	[1] = "1st",
	[2] = "2nd",
	[3] = "3rd",
}

function LakelandMenuUI.new(playerGui, gameState, topScores, onPlay)
	local isHovered = Value(false)

	local buttonScale = Spring(Computed(function()
		return isHovered:get() and 1.06 or 1
	end), 30, 0.7)

	local visible = Computed(function()
		return gameState:get() == "MENU"
	end)

	local leaderboardRows = ForPairs(topScores, function(key, entry)
		local rank = entry.rank
		local isTop3 = rank <= 3
		local isEmpty = (entry.name == "---")
		local rankColor = RANK_COLORS[rank] or Color3.fromRGB(140, 140, 155)
		local rankText = RANK_ICONS[rank] or ("#" .. rank)

		local rowBg
		if rank == 1 then
			rowBg = Color3.fromRGB(45, 40, 15)
		elseif rank == 2 then
			rowBg = Color3.fromRGB(35, 35, 42)
		elseif rank == 3 then
			rowBg = Color3.fromRGB(40, 30, 18)
		else
			rowBg = Color3.fromRGB(25, 25, 38)
		end

		return key, New "Frame" {
			Name = "Row_" .. rank,
			LayoutOrder = rank,
			Size = UDim2.new(1, 0, 0, isTop3 and 36 or 28),
			BackgroundColor3 = rowBg,
			BackgroundTransparency = isEmpty and 0.7 or 0.15,

			[Children] = {
				New "UICorner" {
					CornerRadius = UDim.new(0, 8),
				},

				New "UIStroke" {
					Color = isTop3 and rankColor or Color3.fromRGB(50, 50, 65),
					Thickness = isTop3 and 1.5 or 0,
					Transparency = isTop3 and 0.5 or 1,
				},

				New "TextLabel" {
					Name = "Rank",
					AnchorPoint = Vector2.new(0, 0.5),
					Position = UDim2.new(0.03, 0, 0.5, 0),
					Size = UDim2.fromScale(0.12, 0.7),
					BackgroundTransparency = 1,
					Text = rankText,
					TextColor3 = rankColor,
					Font = isTop3 and Enum.Font.GothamBlack or Enum.Font.GothamBold,
					TextScaled = true,
					TextXAlignment = Enum.TextXAlignment.Left,
				},

				New "TextLabel" {
					Name = "PlayerName",
					AnchorPoint = Vector2.new(0, 0.5),
					Position = UDim2.new(0.17, 0, 0.5, 0),
					Size = UDim2.fromScale(0.5, 0.65),
					BackgroundTransparency = 1,
					Text = isEmpty and "- - -" or entry.name,
					TextColor3 = isEmpty and Color3.fromRGB(80, 80, 95) or Color3.fromRGB(220, 220, 235),
					Font = isTop3 and Enum.Font.GothamBold or Enum.Font.Gotham,
					TextScaled = true,
					TextXAlignment = Enum.TextXAlignment.Left,
					TextTruncate = Enum.TextTruncate.AtEnd,
				},

				New "TextLabel" {
					Name = "Score",
					AnchorPoint = Vector2.new(1, 0.5),
					Position = UDim2.new(0.96, 0, 0.5, 0),
					Size = UDim2.fromScale(0.28, 0.65),
					BackgroundTransparency = 1,
					Text = isEmpty and "-" or formatNumber(entry.score),
					TextColor3 = isEmpty and Color3.fromRGB(80, 80, 95) or (isTop3 and rankColor or Color3.fromRGB(200, 200, 215)),
					Font = isTop3 and Enum.Font.GothamBlack or Enum.Font.GothamBold,
					TextScaled = true,
					TextXAlignment = Enum.TextXAlignment.Right,
				},
			},
		}
	end, Fusion.cleanup)

	local screenGui = New "ScreenGui" {
		Name = "LakelandMenuUI",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = 100,
		Parent = playerGui,

		[Children] = {
			New "Frame" {
				Name = "Background",
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				Visible = visible,

				[Children] = {
					New "Frame" {
						Name = "HeroGroup",
						AnchorPoint = Vector2.new(0.5, 0),
						Position = UDim2.fromScale(0.5, 0.08),
						Size = UDim2.fromScale(0.6, 0.42),
						BackgroundTransparency = 1,

						[Children] = {
							New "UIListLayout" {
								SortOrder = Enum.SortOrder.LayoutOrder,
								FillDirection = Enum.FillDirection.Vertical,
								HorizontalAlignment = Enum.HorizontalAlignment.Center,
								VerticalAlignment = Enum.VerticalAlignment.Center,
								Padding = UDim.new(0.02, 0),
							},

							New "TextLabel" {
								Name = "Title",
								LayoutOrder = 1,
								Size = UDim2.fromScale(1, 0.38),
								BackgroundTransparency = 1,
								Text = "LAKELAND",
								TextColor3 = Color3.fromRGB(255, 255, 255),
								Font = Enum.Font.GothamBlack,
								TextScaled = true,

								[Children] = {
									New "UITextSizeConstraint" {
										MaxTextSize = 72,
									},
								},
							},

						New "Frame" {
							Name = "Spacer",
							LayoutOrder = 2,
							Size = UDim2.fromScale(1, 0.04),
							BackgroundTransparency = 1,
						},

						New "TextButton" {
							Name = "PlayButton",
							LayoutOrder = 3,
								Size = Computed(function()
									local s = buttonScale:get()
									return UDim2.fromScale(0.35 * s, 0.14 * s)
								end),
								BackgroundColor3 = Color3.fromRGB(40, 170, 70),
								Text = "PLAY",
								TextColor3 = Color3.fromRGB(255, 255, 255),
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
									New "UICorner" {
										CornerRadius = UDim.new(0.35, 0),
									},

									New "UIStroke" {
										Color = Color3.fromRGB(70, 220, 110),
										Thickness = 2,
										Transparency = 0.2,
									},

									New "UIGradient" {
										Color = ColorSequence.new(
											Color3.fromRGB(255, 255, 255),
											Color3.fromRGB(200, 200, 200)
										),
										Rotation = 90,
									},

									New "UITextSizeConstraint" {
										MaxTextSize = 32,
									},
								},
							},

						New "TextLabel" {
							Name = "HintLabel",
							LayoutOrder = 4,
							Size = UDim2.fromScale(0.6, 0.08),
							BackgroundTransparency = 1,
							Text = "< >  Arrow keys to switch lanes",
							TextColor3 = Color3.fromRGB(150, 150, 175),
							Font = Enum.Font.GothamMedium,
							TextScaled = true,

							[Children] = {
								New "UITextSizeConstraint" {
									MaxTextSize = 18,
								},
							},
						},
						},
					},

					New "Frame" {
						Name = "LeaderboardPanel",
						AnchorPoint = Vector2.new(0.5, 1),
						Position = UDim2.fromScale(0.5, 0.96),
						Size = UDim2.fromScale(0.5, 0.38),
						BackgroundColor3 = Color3.fromRGB(12, 12, 22),
						BackgroundTransparency = 0.05,

						[Children] = {
							New "UICorner" {
								CornerRadius = UDim.new(0.03, 0),
							},

							New "UIStroke" {
								Color = Color3.fromRGB(60, 60, 80),
								Thickness = 1.5,
								Transparency = 0.3,
							},

							New "Frame" {
								Name = "Header",
								Size = UDim2.new(1, 0, 0, 36),
								BackgroundColor3 = Color3.fromRGB(18, 18, 30),
								BackgroundTransparency = 0.2,

								[Children] = {
									New "UICorner" {
										CornerRadius = UDim.new(0.03, 0),
									},

									New "TextLabel" {
										Name = "TrophyIcon",
										AnchorPoint = Vector2.new(0.5, 0.5),
										Position = UDim2.fromScale(0.44, 0.5),
										Size = UDim2.fromScale(0.04, 0.6),
										BackgroundTransparency = 1,
										Text = "T",
										TextColor3 = Color3.fromRGB(255, 215, 0),
										Font = Enum.Font.GothamBlack,
										TextScaled = true,
									},

									New "TextLabel" {
										Name = "Title",
										AnchorPoint = Vector2.new(0, 0.5),
										Position = UDim2.fromScale(0.47, 0.5),
										Size = UDim2.fromScale(0.3, 0.55),
										BackgroundTransparency = 1,
										Text = "LEADERBOARD",
										TextColor3 = Color3.fromRGB(255, 215, 0),
										Font = Enum.Font.GothamBlack,
										TextScaled = true,
										TextXAlignment = Enum.TextXAlignment.Left,
									},
								},
							},

							New "ScrollingFrame" {
								Name = "ScoresList",
								Position = UDim2.new(0, 0, 0, 40),
								Size = UDim2.new(1, 0, 1, -46),
								BackgroundTransparency = 1,
								ScrollBarThickness = 3,
								ScrollBarImageColor3 = Color3.fromRGB(80, 80, 100),
								CanvasSize = UDim2.fromScale(0, 0),
								AutomaticCanvasSize = Enum.AutomaticSize.Y,

								[Children] = {
									New "UIListLayout" {
										SortOrder = Enum.SortOrder.LayoutOrder,
										Padding = UDim.new(0, 4),
									},

									New "UIPadding" {
										PaddingLeft = UDim.new(0.03, 0),
										PaddingRight = UDim.new(0.03, 0),
										PaddingTop = UDim.new(0, 4),
										PaddingBottom = UDim.new(0, 4),
									},

									leaderboardRows,
								},
							},
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
