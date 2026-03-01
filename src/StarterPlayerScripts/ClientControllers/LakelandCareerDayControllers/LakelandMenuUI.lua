local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CustomPackages = ReplicatedStorage.CustomPackages
local Fusion = require(CustomPackages.FusionRoot.Fusion)

local New = Fusion.New
local Value = Fusion.Value
local Computed = Fusion.Computed
local Children = Fusion.Children
local OnEvent = Fusion.OnEvent
local Spring = Fusion.Spring
local ForValues = Fusion.ForValues

local LakelandMenuUI = {}

local function createLeaderboardRow(index, entry)
	local isTop = index <= 3
	local rankColors = {
		[1] = Color3.fromRGB(255, 215, 0),
		[2] = Color3.fromRGB(200, 200, 210),
		[3] = Color3.fromRGB(205, 127, 50),
	}
	local rankColor = rankColors[index] or Color3.fromRGB(180, 180, 190)

	return New "Frame" {
		Name = "Row_" .. index,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = Color3.fromRGB(30, 30, 45),
		BackgroundTransparency = isTop and 0.3 or 0.5,

		[Children] = {
			New "UICorner" {
				CornerRadius = UDim.new(0, 6),
			},

			New "UIPadding" {
				PaddingLeft = UDim.new(0.04, 0),
				PaddingRight = UDim.new(0.04, 0),
				PaddingTop = UDim.new(0, 4),
				PaddingBottom = UDim.new(0, 4),
			},

			New "UIListLayout" {
				FillDirection = Enum.FillDirection.Horizontal,
				VerticalAlignment = Enum.VerticalAlignment.Center,
				SortOrder = Enum.SortOrder.LayoutOrder,
				Padding = UDim.new(0.03, 0),
			},

			New "TextLabel" {
				Name = "Rank",
				LayoutOrder = 1,
				Size = UDim2.fromScale(0.1, 1),
				AutomaticSize = Enum.AutomaticSize.Y,
				BackgroundTransparency = 1,
				Text = "#" .. index,
				TextColor3 = rankColor,
				Font = Enum.Font.GothamBold,
				TextScaled = true,
				TextXAlignment = Enum.TextXAlignment.Left,
			},

			New "TextLabel" {
				Name = "PlayerName",
				LayoutOrder = 2,
				Size = UDim2.fromScale(0.55, 1),
				AutomaticSize = Enum.AutomaticSize.Y,
				BackgroundTransparency = 1,
				Text = entry.name or "---",
				TextColor3 = Color3.fromRGB(200, 200, 220),
				Font = Enum.Font.Gotham,
				TextScaled = true,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextTruncate = Enum.TextTruncate.AtEnd,
			},

			New "TextLabel" {
				Name = "Score",
				LayoutOrder = 3,
				Size = UDim2.fromScale(0.3, 1),
				AutomaticSize = Enum.AutomaticSize.Y,
				BackgroundTransparency = 1,
				Text = tostring(entry.score),
				TextColor3 = Color3.fromRGB(255, 255, 255),
				Font = isTop and Enum.Font.GothamBold or Enum.Font.Gotham,
				TextScaled = true,
				TextXAlignment = Enum.TextXAlignment.Right,
			},
		},
	}
end

function LakelandMenuUI.new(playerGui, gameState, topScores, onPlay)
	local isHovered = Value(false)

	local buttonScale = Spring(Computed(function()
		return isHovered:get() and 1.08 or 1
	end), 35, 0.7)

	local visible = Computed(function()
		return gameState:get() == "MENU"
	end)

	local leaderboardRows = ForValues(topScores, function(entry)
		return createLeaderboardRow(entry.rank, entry)
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
				BackgroundColor3 = Color3.fromRGB(10, 10, 20),
				BackgroundTransparency = 0.3,
				Visible = visible,

				[Children] = {
					-- Left side: Title + Play
					New "Frame" {
						Name = "LeftPanel",
						AnchorPoint = Vector2.new(0.5, 0.5),
						Position = UDim2.fromScale(0.35, 0.45),
						Size = UDim2.fromScale(0.4, 0.5),
						BackgroundTransparency = 1,

						[Children] = {
							New "UIListLayout" {
								SortOrder = Enum.SortOrder.LayoutOrder,
								FillDirection = Enum.FillDirection.Vertical,
								HorizontalAlignment = Enum.HorizontalAlignment.Center,
								VerticalAlignment = Enum.VerticalAlignment.Center,
								Padding = UDim.new(0.04, 0),
							},

							New "TextLabel" {
								Name = "Title",
								LayoutOrder = 1,
								Size = UDim2.fromScale(0.9, 0.2),
								BackgroundTransparency = 1,
								Text = "Lakeland Career Day",
								TextColor3 = Color3.fromRGB(255, 255, 255),
								Font = Enum.Font.GothamBold,
								TextScaled = true,
							},

							New "TextLabel" {
								Name = "Subtitle",
								LayoutOrder = 2,
								Size = UDim2.fromScale(0.6, 0.08),
								BackgroundTransparency = 1,
								Text = "The Race Begins",
								TextColor3 = Color3.fromRGB(180, 200, 255),
								Font = Enum.Font.Gotham,
								TextScaled = true,
							},

							New "TextButton" {
								Name = "PlayButton",
								LayoutOrder = 3,
								Size = Computed(function()
									local s = buttonScale:get()
									return UDim2.fromScale(0.35 * s, 0.12 * s)
								end),
								BackgroundColor3 = Color3.fromRGB(50, 180, 80),
								Text = "PLAY",
								TextColor3 = Color3.fromRGB(255, 255, 255),
								Font = Enum.Font.GothamBold,
								TextScaled = true,
								AutoButtonColor = false,

								[OnEvent "Activated"] = function()
									if onPlay then
										onPlay()
									end
								end,

								[OnEvent "MouseEnter"] = function()
									isHovered:set(true)
								end,

								[OnEvent "MouseLeave"] = function()
									isHovered:set(false)
								end,

								[Children] = {
									New "UICorner" {
										CornerRadius = UDim.new(0.3, 0),
									},

									New "UIStroke" {
										Color = Color3.fromRGB(80, 220, 120),
										Thickness = 2,
										Transparency = 0.3,
									},
								},
							},
						},
					},

					-- Right side: Leaderboard
					New "Frame" {
						Name = "LeaderboardPanel",
						AnchorPoint = Vector2.new(0.5, 0.5),
						Position = UDim2.fromScale(0.72, 0.45),
						Size = UDim2.fromScale(0.25, 0.55),
						BackgroundColor3 = Color3.fromRGB(15, 15, 25),
						BackgroundTransparency = 0.2,

						[Children] = {
							New "UICorner" {
								CornerRadius = UDim.new(0.03, 0),
							},

							New "UIStroke" {
								Color = Color3.fromRGB(80, 80, 100),
								Thickness = 1,
								Transparency = 0.5,
							},

							New "UIPadding" {
								PaddingLeft = UDim.new(0.05, 0),
								PaddingRight = UDim.new(0.05, 0),
								PaddingTop = UDim.new(0.04, 0),
								PaddingBottom = UDim.new(0.04, 0),
							},

							New "TextLabel" {
								Name = "LeaderboardTitle",
								LayoutOrder = 0,
								Size = UDim2.new(1, 0, 0.1, 0),
								BackgroundTransparency = 1,
								Text = "TOP SCORES",
								TextColor3 = Color3.fromRGB(255, 215, 0),
								Font = Enum.Font.GothamBold,
								TextScaled = true,
							},

							New "ScrollingFrame" {
								Name = "ScoresList",
								Position = UDim2.fromScale(0, 0.14),
								Size = UDim2.fromScale(1, 0.86),
								BackgroundTransparency = 1,
								ScrollBarThickness = 3,
								ScrollBarImageColor3 = Color3.fromRGB(100, 100, 120),
								CanvasSize = UDim2.fromScale(0, 0),
								AutomaticCanvasSize = Enum.AutomaticSize.Y,

								[Children] = {
									New "UIListLayout" {
										SortOrder = Enum.SortOrder.LayoutOrder,
										Padding = UDim.new(0, 4),
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
