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

local BG_PANEL = Color3.fromRGB(10, 16, 30)
local BORDER_CYAN = Color3.fromRGB(0, 140, 200)
local ACCENT_CYAN = Color3.fromRGB(0, 200, 255)
local TEXT_PRIMARY = Color3.fromRGB(220, 235, 255)
local TEXT_DIM = Color3.fromRGB(60, 90, 130)
local LAUNCH_GREEN = Color3.fromRGB(0, 220, 110)
local LAUNCH_GREEN_GLOW = Color3.fromRGB(0, 255, 140)

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
	[2] = Color3.fromRGB(200, 200, 220),
	[3] = Color3.fromRGB(205, 140, 55),
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
		local rankColor = RANK_COLORS[rank] or Color3.fromRGB(100, 120, 155)
		local rankText = RANK_ICONS[rank] or ("#" .. rank)

		local rowBg
		if rank == 1 then
			rowBg = Color3.fromRGB(40, 34, 6)
		elseif rank == 2 then
			rowBg = Color3.fromRGB(28, 30, 40)
		elseif rank == 3 then
			rowBg = Color3.fromRGB(34, 24, 8)
		else
			rowBg = Color3.fromRGB(12, 18, 32)
		end

		return key, New "Frame" {
			Name = "Row_" .. rank,
			LayoutOrder = rank,
			Size = UDim2.new(1, 0, 0, isTop3 and 48 or 36),
			BackgroundColor3 = rowBg,
			BackgroundTransparency = isEmpty and 0.6 or 0.05,

			[Children] = {
				New "UICorner" {
					CornerRadius = UDim.new(0, 8),
				},

				New "UIStroke" {
					Color = isTop3 and rankColor or Color3.fromRGB(20, 35, 55),
					Thickness = isTop3 and 2 or 0,
					Transparency = isTop3 and 0.3 or 1,
				},

				New "TextLabel" {
					Name = "Rank",
					AnchorPoint = Vector2.new(0, 0.5),
					Position = UDim2.new(0.03, 0, 0.5, 0),
					Size = UDim2.fromScale(0.1, 0.6),
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
					Position = UDim2.new(0.15, 0, 0.5, 0),
					Size = UDim2.fromScale(0.52, 0.55),
					BackgroundTransparency = 1,
					Text = isEmpty and "- - -" or entry.name,
					TextColor3 = isEmpty and Color3.fromRGB(40, 55, 80) or TEXT_PRIMARY,
					Font = isTop3 and Enum.Font.GothamBold or Enum.Font.Gotham,
					TextScaled = true,
					TextXAlignment = Enum.TextXAlignment.Left,
					TextTruncate = Enum.TextTruncate.AtEnd,
				},

				New "TextLabel" {
					Name = "Score",
					AnchorPoint = Vector2.new(1, 0.5),
					Position = UDim2.new(0.97, 0, 0.5, 0),
					Size = UDim2.fromScale(0.28, 0.55),
					BackgroundTransparency = 1,
					Text = isEmpty and "-" or formatNumber(entry.score),
					TextColor3 = isEmpty and Color3.fromRGB(40, 55, 80) or (isTop3 and rankColor or Color3.fromRGB(150, 165, 195)),
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
						Name = "TitleBlock",
						AnchorPoint = Vector2.new(0.5, 0),
						Position = UDim2.fromScale(0.5, 0.02),
						Size = UDim2.fromScale(0.8, 0.15),
						BackgroundTransparency = 1,

						[Children] = {
							New "TextLabel" {
								Name = "Title",
								AnchorPoint = Vector2.new(0.5, 0),
								Position = UDim2.fromScale(0.5, 0),
								Size = UDim2.fromScale(1, 0.65),
								BackgroundTransparency = 1,
								Text = "DISASTER TRANSPORT",
								TextColor3 = TEXT_PRIMARY,
								Font = Enum.Font.GothamBlack,
								TextScaled = true,
							},

							New "Frame" {
								Name = "CyanLine",
								AnchorPoint = Vector2.new(0.5, 1),
								Position = UDim2.fromScale(0.5, 1),
								Size = UDim2.fromScale(0.5, 0.015),
								BackgroundColor3 = BORDER_CYAN,
								BackgroundTransparency = 0.5,
								BorderSizePixel = 0,

								[Children] = {
									New "UICorner" {
										CornerRadius = UDim.new(0.5, 0),
									},
								},
							},
						},
					},

					New "Frame" {
						Name = "ButtonGroup",
						AnchorPoint = Vector2.new(0.5, 0),
						Position = UDim2.fromScale(0.5, 0.19),
						Size = UDim2.fromScale(0.5, 0.18),
						BackgroundTransparency = 1,

						[Children] = {
							New "UIListLayout" {
								SortOrder = Enum.SortOrder.LayoutOrder,
								FillDirection = Enum.FillDirection.Vertical,
								HorizontalAlignment = Enum.HorizontalAlignment.Center,
								VerticalAlignment = Enum.VerticalAlignment.Center,
								Padding = UDim.new(0.08, 0),
							},

							New "TextButton" {
								Name = "PlayButton",
								LayoutOrder = 1,
								Size = Computed(function()
									local s = buttonScale:get()
									return UDim2.fromScale(0.50 * s, 0.45 * s)
								end),
								BackgroundColor3 = LAUNCH_GREEN,
								Text = "LAUNCH",
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
										CornerRadius = UDim.new(0.28, 0),
									},

									New "UIStroke" {
										Color = LAUNCH_GREEN_GLOW,
										Thickness = 3,
										Transparency = 0.1,
									},

									New "UIGradient" {
										Color = ColorSequence.new(
											Color3.fromRGB(255, 255, 255),
											Color3.fromRGB(170, 200, 170)
										),
										Rotation = 90,
									},

									New "UITextSizeConstraint" {
										MaxTextSize = 42,
									},
								},
							},

							New "TextLabel" {
								Name = "HintLabel",
								LayoutOrder = 2,
								Size = UDim2.fromScale(0.75, 0.2),
								BackgroundTransparency = 1,
								Text = "< >  Arrow keys to switch lanes",
								TextColor3 = TEXT_DIM,
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
						Position = UDim2.fromScale(0.5, 0.98),
						Size = UDim2.fromScale(0.65, 0.55),
						BackgroundColor3 = BG_PANEL,
						BackgroundTransparency = 0.03,

						[Children] = {
							New "UICorner" {
								CornerRadius = UDim.new(0.02, 0),
							},

							New "UIStroke" {
								Color = BORDER_CYAN,
								Thickness = 2,
								Transparency = 0.2,
							},

							New "UIGradient" {
								Color = ColorSequence.new(
									Color3.fromRGB(255, 255, 255),
									Color3.fromRGB(160, 175, 200)
								),
								Rotation = 90,
							},

							New "Frame" {
								Name = "Header",
								Size = UDim2.new(1, 0, 0, 44),
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
										Name = "Title",
										AnchorPoint = Vector2.new(0.5, 0.5),
										Position = UDim2.fromScale(0.5, 0.5),
										Size = UDim2.fromScale(0.45, 0.55),
										BackgroundTransparency = 1,
										Text = "FLIGHT RECORDS",
										TextColor3 = ACCENT_CYAN,
										Font = Enum.Font.GothamBlack,
										TextScaled = true,
									},
								},
							},

							New "ScrollingFrame" {
								Name = "ScoresList",
								Position = UDim2.new(0, 0, 0, 48),
								Size = UDim2.new(1, 0, 1, -54),
								BackgroundTransparency = 1,
								ScrollBarThickness = 4,
								ScrollBarImageColor3 = BORDER_CYAN,
								CanvasSize = UDim2.fromScale(0, 0),
								AutomaticCanvasSize = Enum.AutomaticSize.Y,

								[Children] = {
									New "UIListLayout" {
										SortOrder = Enum.SortOrder.LayoutOrder,
										Padding = UDim.new(0, 5),
									},

									New "UIPadding" {
										PaddingLeft = UDim.new(0.025, 0),
										PaddingRight = UDim.new(0.025, 0),
										PaddingTop = UDim.new(0, 5),
										PaddingBottom = UDim.new(0, 5),
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
