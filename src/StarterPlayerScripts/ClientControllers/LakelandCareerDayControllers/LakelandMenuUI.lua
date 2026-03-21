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
local DIVIDER_COLOR = Color3.fromRGB(40, 50, 75)

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

local function panelStroke(b, color)
	return New "UIStroke" {
		Color = color,
		Thickness = Computed(function()
			return 1.5 + b:get() * 2
		end),
		Transparency = Computed(function()
			return 0.35 - b:get() * 0.25
		end),
	}
end

local function sectionHeader(text, color)
	return New "TextLabel" {
		Name = "Header",
		LayoutOrder = 0,
		Size = UDim2.new(1, 0, 0, 28),
		BackgroundTransparency = 1,
		Text = text,
		TextColor3 = color,
		Font = Enum.Font.GothamBlack,
		TextScaled = true,
		[Children] = { New "UITextSizeConstraint" { MaxTextSize = 28 } },
	}
end

local function divider(order)
	return New "Frame" {
		Name = "Divider",
		LayoutOrder = order,
		Size = UDim2.new(1, 0, 0, 2),
		BackgroundColor3 = DIVIDER_COLOR,
		BorderSizePixel = 0,
		[Children] = { New "UICorner" { CornerRadius = UDim.new(0.5, 0) } },
	}
end

--------------------------------------------------------------------
-- Leaderboard panel (left)
--------------------------------------------------------------------
local function makeLeaderboardPanel(topScores, b)
	local function makeEntry(rank, entry)
		local isEmpty = (entry.name == "---")
		local rankColor = RANK_COLORS[rank] or TEXT_DIM
		local medals = { "1ST", "2ND", "3RD" }
		local medalText = medals[rank] or ("#" .. rank)

		return New "Frame" {
			Name = "Row_" .. rank,
			LayoutOrder = rank,
			Size = UDim2.new(1, 0, 0, 26),
			BackgroundTransparency = 1,

			[Children] = {
				New "TextLabel" {
					Name = "Medal",
					AnchorPoint = Vector2.new(0, 0.5),
					Position = UDim2.fromScale(0, 0.5),
					Size = UDim2.fromScale(0.15, 1),
					BackgroundTransparency = 1,
					Text = medalText,
					TextColor3 = rankColor,
					Font = Enum.Font.GothamBlack,
					TextScaled = true,
					TextXAlignment = Enum.TextXAlignment.Left,
					[Children] = { New "UITextSizeConstraint" { MaxTextSize = 20 } },
				},

				New "TextLabel" {
					Name = "Name",
					AnchorPoint = Vector2.new(0, 0.5),
					Position = UDim2.fromScale(0.18, 0.5),
					Size = UDim2.fromScale(0.48, 1),
					BackgroundTransparency = 1,
					Text = isEmpty and "---" or entry.name,
					TextColor3 = isEmpty and Color3.fromRGB(40, 50, 70) or TEXT_WHITE,
					Font = Enum.Font.GothamBold,
					TextScaled = true,
					TextXAlignment = Enum.TextXAlignment.Left,
					TextTruncate = Enum.TextTruncate.AtEnd,
					[Children] = { New "UITextSizeConstraint" { MaxTextSize = 18 } },
				},

				New "TextLabel" {
					Name = "Score",
					AnchorPoint = Vector2.new(1, 0.5),
					Position = UDim2.fromScale(1, 0.5),
					Size = UDim2.fromScale(0.32, 1),
					BackgroundTransparency = 1,
					Text = isEmpty and "-" or formatNumber(entry.score),
					TextColor3 = isEmpty and Color3.fromRGB(40, 50, 70) or rankColor,
					Font = Enum.Font.GothamBlack,
					TextScaled = true,
					TextXAlignment = Enum.TextXAlignment.Right,
					[Children] = { New "UITextSizeConstraint" { MaxTextSize = 18 } },
				},
			},
		}
	end

	local entryFrames = Computed(function()
		local scores = topScores:get()
		local frames = {}
		for i = 1, 10 do
			local entry = scores[i]
			if entry then
				table.insert(frames, makeEntry(entry.rank or i, entry))
			else
				table.insert(frames, makeEntry(i, { name = "---", score = 0 }))
			end
		end
		return frames
	end)

	return New "Frame" {
		Name = "LeaderboardPanel",
		LayoutOrder = 1,
		Size = UDim2.fromScale(0.28, 1),
		BackgroundColor3 = PANEL_BG,
		BackgroundTransparency = 0.12,

		[Children] = {
			New "UICorner" { CornerRadius = UDim.new(0, 14) },
			panelStroke(b, ACCENT_CYAN),
			New "UIPadding" {
				PaddingLeft = UDim.new(0, 18),
				PaddingRight = UDim.new(0, 18),
				PaddingTop = UDim.new(0, 16),
				PaddingBottom = UDim.new(0, 16),
			},
			New "UIListLayout" {
				FillDirection = Enum.FillDirection.Vertical,
				HorizontalAlignment = Enum.HorizontalAlignment.Center,
				VerticalAlignment = Enum.VerticalAlignment.Top,
				Padding = UDim.new(0, 6),
				SortOrder = Enum.SortOrder.LayoutOrder,
			},

			sectionHeader("LEADERBOARD", ACCENT_CYAN),
			divider(1),
			entryFrames,
		},
	}
end

--------------------------------------------------------------------
-- Center panel (title + launch)
--------------------------------------------------------------------
local function makeCenterPanel(b, beatIntensity, onPlay)
	local isHovered = Value(false)

	local buttonScale = Spring(Computed(function()
		return isHovered:get() and 1.08 or 1
	end), 25, 0.6)

	local titleScale = Computed(function()
		return 1 + beatIntensity:get() * 0.04
	end)
	local strokePulse = Computed(function()
		return 2 + beatIntensity:get() * 3
	end)
	local strokeTrans = Computed(function()
		return 0.3 - beatIntensity:get() * 0.25
	end)

	return New "Frame" {
		Name = "CenterPanel",
		LayoutOrder = 2,
		Size = UDim2.fromScale(0.36, 1),
		BackgroundColor3 = PANEL_BG,
		BackgroundTransparency = 0.12,

		[Children] = {
			New "UICorner" { CornerRadius = UDim.new(0, 14) },
			panelStroke(b, ACCENT_HOT),

			-- Title
			New "Frame" {
				Name = "TitleBlock",
				AnchorPoint = Vector2.new(0.5, 0),
				Position = UDim2.fromScale(0.5, 0.06),
				Size = Computed(function()
					local s = titleScale:get()
					return UDim2.fromScale(0.9 * s, 0.32 * s)
				end),
				BackgroundTransparency = 1,

				[Children] = {
					New "TextLabel" {
						Name = "Title",
						AnchorPoint = Vector2.new(0.5, 0.5),
						Position = UDim2.fromScale(0.5, 0.45),
						Size = UDim2.fromScale(1, 0.75),
						BackgroundTransparency = 1,
						Text = "PULSE\nRIDER",
						TextColor3 = TEXT_WHITE,
						Font = Enum.Font.GothamBlack,
						TextScaled = true,

						[Children] = {
							New "UITextSizeConstraint" { MaxTextSize = 120 },
							New "UIStroke" {
								Color = ACCENT_HOT,
								Thickness = strokePulse,
								Transparency = strokeTrans,
							},
						},
					},

					New "Frame" {
						Name = "AccentLine",
						AnchorPoint = Vector2.new(0.5, 1),
						Position = UDim2.fromScale(0.5, 0.95),
						Size = UDim2.fromScale(0.45, 0.02),
						BackgroundColor3 = ACCENT_HOT,
						BorderSizePixel = 0,
						[Children] = { New "UICorner" { CornerRadius = UDim.new(0.5, 0) } },
					},
				},
			},

			-- Subtitle / tagline
			New "TextLabel" {
				Name = "Tagline",
				AnchorPoint = Vector2.new(0.5, 0),
				Position = UDim2.fromScale(0.5, 0.42),
				Size = UDim2.fromScale(0.8, 0.06),
				BackgroundTransparency = 1,
				Text = "RIDE THE BEAT. DODGE THE DROP.",
				TextColor3 = TEXT_DIM,
				Font = Enum.Font.GothamBold,
				TextScaled = true,
				[Children] = { New "UITextSizeConstraint" { MaxTextSize = 18 } },
			},

			-- Launch button
			New "TextButton" {
				Name = "PlayButton",
				AnchorPoint = Vector2.new(0.5, 0),
				Position = UDim2.fromScale(0.5, 0.56),
				Size = Computed(function()
					local s = buttonScale:get()
					local bp = 1 + b:get() * 0.02
					return UDim2.fromScale(0.6 * s * bp, 0.14 * s * bp)
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

			-- Version / credits
			New "TextLabel" {
				Name = "Version",
				AnchorPoint = Vector2.new(0.5, 1),
				Position = UDim2.fromScale(0.5, 0.96),
				Size = UDim2.fromScale(0.8, 0.04),
				BackgroundTransparency = 1,
				Text = "v1.0",
				TextColor3 = Color3.fromRGB(50, 55, 75),
				Font = Enum.Font.GothamBold,
				TextScaled = true,
				[Children] = { New "UITextSizeConstraint" { MaxTextSize = 14 } },
			},
		},
	}
end

--------------------------------------------------------------------
-- How to Play panel (right)
--------------------------------------------------------------------
local function makeHowToPlayPanel(b)
	local function controlRow(order, keyText, actionText)
		return New "Frame" {
			Name = "CtrlRow_" .. order,
			LayoutOrder = order,
			Size = UDim2.new(1, 0, 0, 30),
			BackgroundTransparency = 1,
			[Children] = {
				New "TextLabel" {
					AnchorPoint = Vector2.new(1, 0.5),
					Position = UDim2.fromScale(0.45, 0.5),
					Size = UDim2.fromScale(0.42, 1),
					BackgroundTransparency = 1,
					Text = keyText,
					TextColor3 = KEY_COLOR,
					Font = Enum.Font.GothamBlack,
					TextScaled = true,
					TextXAlignment = Enum.TextXAlignment.Right,
					[Children] = { New "UITextSizeConstraint" { MaxTextSize = 22 } },
				},
				New "TextLabel" {
					AnchorPoint = Vector2.new(0, 0.5),
					Position = UDim2.fromScale(0.50, 0.5),
					Size = UDim2.fromScale(0.48, 1),
					BackgroundTransparency = 1,
					Text = actionText,
					TextColor3 = TEXT_WHITE,
					Font = Enum.Font.GothamBold,
					TextScaled = true,
					TextXAlignment = Enum.TextXAlignment.Left,
					[Children] = { New "UITextSizeConstraint" { MaxTextSize = 22 } },
				},
			},
		}
	end

	local function legendItem(order, color, label)
		return New "Frame" {
			Name = "Leg_" .. label,
			LayoutOrder = order,
			Size = UDim2.new(1, 0, 0, 28),
			BackgroundTransparency = 1,
			[Children] = {
				New "UIListLayout" {
					FillDirection = Enum.FillDirection.Horizontal,
					VerticalAlignment = Enum.VerticalAlignment.Center,
					Padding = UDim.new(0, 8),
				},
				New "Frame" {
					LayoutOrder = 1,
					Size = UDim2.new(0, 18, 0, 18),
					BackgroundColor3 = color,
					[Children] = {
						New "UICorner" { CornerRadius = UDim.new(0.2, 0) },
					},
				},
				New "TextLabel" {
					LayoutOrder = 2,
					Size = UDim2.new(1, -28, 1, 0),
					BackgroundTransparency = 1,
					Text = label,
					TextColor3 = TEXT_WHITE,
					Font = Enum.Font.GothamBold,
					TextScaled = true,
					TextXAlignment = Enum.TextXAlignment.Left,
					[Children] = { New "UITextSizeConstraint" { MaxTextSize = 20 } },
				},
			},
		}
	end

	return New "Frame" {
		Name = "HowToPlayPanel",
		LayoutOrder = 3,
		Size = UDim2.fromScale(0.28, 1),
		BackgroundColor3 = PANEL_BG,
		BackgroundTransparency = 0.12,

		[Children] = {
			New "UICorner" { CornerRadius = UDim.new(0, 14) },
			panelStroke(b, ACCENT_HOT),
			New "UIPadding" {
				PaddingLeft = UDim.new(0, 18),
				PaddingRight = UDim.new(0, 18),
				PaddingTop = UDim.new(0, 16),
				PaddingBottom = UDim.new(0, 16),
			},
			New "UIListLayout" {
				FillDirection = Enum.FillDirection.Vertical,
				HorizontalAlignment = Enum.HorizontalAlignment.Center,
				VerticalAlignment = Enum.VerticalAlignment.Top,
				Padding = UDim.new(0, 8),
				SortOrder = Enum.SortOrder.LayoutOrder,
			},

			sectionHeader("HOW TO PLAY", ACCENT_HOT),
			divider(1),

			-- Controls sub-header
			New "TextLabel" {
				Name = "ControlsLabel",
				LayoutOrder = 2,
				Size = UDim2.new(1, 0, 0, 20),
				BackgroundTransparency = 1,
				Text = "CONTROLS",
				TextColor3 = TEXT_DIM,
				Font = Enum.Font.GothamBlack,
				TextScaled = true,
				[Children] = { New "UITextSizeConstraint" { MaxTextSize = 16 } },
			},

			controlRow(3, "A / D  or  < >", "SWITCH LANES"),
			controlRow(4, "SPACE", "DEPLOY BOMB"),

			divider(5),

			-- Legend sub-header
			New "TextLabel" {
				Name = "LegendLabel",
				LayoutOrder = 6,
				Size = UDim2.new(1, 0, 0, 20),
				BackgroundTransparency = 1,
				Text = "CUBES",
				TextColor3 = TEXT_DIM,
				Font = Enum.Font.GothamBlack,
				TextScaled = true,
				[Children] = { New "UITextSizeConstraint" { MaxTextSize = 16 } },
			},

			legendItem(7, CUBE_RED, "AVOID — deals damage"),
			legendItem(8, CUBE_BLUE, "COLLECT — score points"),
			legendItem(9, CUBE_GREEN, "BOMB — clears the lane"),
		},
	}
end

--------------------------------------------------------------------
-- Main entry
--------------------------------------------------------------------
function LakelandMenuUI.new(playerGui, gameState, topScores, beatIntensity, onPlay)
	local visible = Computed(function()
		return gameState:get() == "MENU"
	end)

	local b = beatIntensity or Value(0)

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
						Name = "PanelRow",
						AnchorPoint = Vector2.new(0.5, 0.5),
						Position = UDim2.fromScale(0.5, 0.5),
						Size = UDim2.fromScale(0.92, 0.72),
						BackgroundTransparency = 1,

						[Children] = {
							New "UIListLayout" {
								FillDirection = Enum.FillDirection.Horizontal,
								HorizontalAlignment = Enum.HorizontalAlignment.Center,
								VerticalAlignment = Enum.VerticalAlignment.Center,
								Padding = UDim.new(0.015, 0),
								SortOrder = Enum.SortOrder.LayoutOrder,
							},

							makeLeaderboardPanel(topScores, b),
							makeCenterPanel(b, b, onPlay),
							makeHowToPlayPanel(b),
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
