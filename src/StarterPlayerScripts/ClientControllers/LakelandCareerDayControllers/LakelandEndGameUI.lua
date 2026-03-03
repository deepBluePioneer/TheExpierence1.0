local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CustomPackages = ReplicatedStorage.CustomPackages
local Fusion = require(CustomPackages.FusionRoot.Fusion)

local Packages = ReplicatedStorage.Packages
local Trove = require(Packages.Trove)

local New = Fusion.New
local Value = Fusion.Value
local Computed = Fusion.Computed
local Children = Fusion.Children
local Spring = Fusion.Spring

local BG_DARK = Color3.fromRGB(3, 5, 12)
local BG_PANEL = Color3.fromRGB(10, 16, 30)
local BORDER_CYAN = Color3.fromRGB(0, 140, 200)
local TEXT_PRIMARY = Color3.fromRGB(220, 235, 255)
local TEXT_DIM = Color3.fromRGB(70, 100, 140)
local SCORE_GOLD = Color3.fromRGB(255, 220, 60)
local PLAYER_CYAN = Color3.fromRGB(0, 210, 255)
local DIVIDER_COLOR = Color3.fromRGB(0, 70, 110)
local SUCCESS_GREEN = Color3.fromRGB(0, 220, 130)

local RANK_COLORS = {
	Color3.fromRGB(255, 215, 0),
	Color3.fromRGB(200, 200, 220),
	Color3.fromRGB(205, 140, 55),
}

local RANK_BG = {
	Color3.fromRGB(50, 42, 6),
	Color3.fromRGB(35, 38, 48),
	Color3.fromRGB(42, 30, 8),
}

local RANK_STROKE = {
	Color3.fromRGB(255, 225, 50),
	Color3.fromRGB(220, 220, 240),
	Color3.fromRGB(220, 160, 70),
}

local LakelandEndGameUI = {}

function LakelandEndGameUI.new(playerGui, gameState)
	local trove = Trove.new()

	local finalScore = Value(0)
	local finalDistance = Value(0)
	local playerName = Value("")
	local reason = Value("TIME UP")
	local statusText = Value("SAVING...")
	local rankValue = Value(nil)

	local visible = Computed(function()
		return gameState:get() == "GAME_OVER"
	end)

	local animatedScore = Spring(finalScore, 8, 0.9)
	local scoreDisplay = Computed(function()
		local n = math.floor(animatedScore:get())
		local s = tostring(n)
		local parts = {}
		while #s > 3 do
			table.insert(parts, 1, s:sub(-3))
			s = s:sub(1, -4)
		end
		table.insert(parts, 1, s)
		return table.concat(parts, ",")
	end)

	local distanceDisplay = Computed(function()
		local d = math.floor(finalDistance:get())
		if d >= 1000 then
			return string.format("%.1f km", d / 1000)
		end
		return d .. " m"
	end)

	local containerScale = Value(0.75)
	local animatedScale = Spring(containerScale, 16, 0.55)

	local rankColor = Computed(function()
		local r = rankValue:get()
		if r and r <= 3 then return RANK_COLORS[r] end
		if r and r <= 10 then return PLAYER_CYAN end
		return TEXT_DIM
	end)

	local rankBgColor = Computed(function()
		local r = rankValue:get()
		if r and r <= 3 then return RANK_BG[r] end
		if r and r <= 10 then return Color3.fromRGB(6, 28, 42) end
		return Color3.fromRGB(18, 22, 34)
	end)

	local rankStrokeColor = Computed(function()
		local r = rankValue:get()
		if r and r <= 3 then return RANK_STROKE[r] end
		if r and r <= 10 then return PLAYER_CYAN end
		return Color3.fromRGB(50, 70, 100)
	end)

	local rankText = Computed(function()
		local r = rankValue:get()
		if not r then return "" end
		if r == 1 then return "NEW HIGH SCORE!" end
		if r <= 3 then return "TOP 3  —  #" .. r .. "!" end
		if r <= 10 then return "TOP 10  —  #" .. r end
		return "RANK #" .. r
	end)

	local screenGui = New "ScreenGui" {
		Name = "LakelandEndGameUI",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = 200,
		Parent = playerGui,

		[Children] = {
			New "Frame" {
				Name = "Overlay",
				Size = UDim2.fromScale(1, 1),
				BackgroundColor3 = BG_DARK,
				BackgroundTransparency = 0.15,
				Visible = visible,

				[Children] = {
					New "Frame" {
						Name = "Panel",
						AnchorPoint = Vector2.new(0.5, 0.5),
						Position = UDim2.fromScale(0.5, 0.5),
						Size = Computed(function()
							local s = animatedScale:get()
							return UDim2.fromScale(0.52 * s, 0.75 * s)
						end),
						BackgroundColor3 = BG_PANEL,
						BackgroundTransparency = 0.02,

						[Children] = {
							New "UICorner" {
								CornerRadius = UDim.new(0.025, 0),
							},

							New "UIStroke" {
								Color = BORDER_CYAN,
								Thickness = 3,
								Transparency = 0.1,
							},

							New "UIGradient" {
								Color = ColorSequence.new(
									Color3.fromRGB(255, 255, 255),
									Color3.fromRGB(150, 165, 195)
								),
								Rotation = 90,
							},

							New "Frame" {
								Name = "TopBar",
								AnchorPoint = Vector2.new(0.5, 0),
								Position = UDim2.fromScale(0.5, 0),
								Size = UDim2.fromScale(1, 0.0035),
								BackgroundColor3 = BORDER_CYAN,
								BackgroundTransparency = 0.2,
								BorderSizePixel = 0,
							},

							New "TextLabel" {
								Name = "GameOverLabel",
								AnchorPoint = Vector2.new(0.5, 0),
								Position = UDim2.fromScale(0.5, 0.03),
								Size = UDim2.fromScale(0.85, 0.12),
								BackgroundTransparency = 1,
								Text = "GAME OVER",
								TextColor3 = TEXT_PRIMARY,
								Font = Enum.Font.GothamBlack,
								TextScaled = true,
							},

							New "TextLabel" {
								Name = "ReasonLabel",
								AnchorPoint = Vector2.new(0.5, 0),
								Position = UDim2.fromScale(0.5, 0.145),
								Size = UDim2.fromScale(0.4, 0.035),
								BackgroundTransparency = 1,
								Text = reason,
								TextColor3 = Computed(function()
									if reason:get() == "DESTROYED" then
										return Color3.fromRGB(255, 80, 50)
									end
									return Color3.fromRGB(160, 140, 80)
								end),
								Font = Enum.Font.GothamBold,
								TextScaled = true,
							},

							New "TextLabel" {
								Name = "NameLabel",
								AnchorPoint = Vector2.new(0.5, 0),
								Position = UDim2.fromScale(0.5, 0.19),
								Size = UDim2.fromScale(0.7, 0.055),
								BackgroundTransparency = 1,
								Text = playerName,
								TextColor3 = PLAYER_CYAN,
								Font = Enum.Font.GothamBlack,
								TextScaled = true,
							},

							New "Frame" {
								Name = "Divider1",
								AnchorPoint = Vector2.new(0.5, 0),
								Position = UDim2.fromScale(0.5, 0.255),
								Size = UDim2.fromScale(0.8, 0.003),
								BackgroundColor3 = DIVIDER_COLOR,
								BackgroundTransparency = 0.2,
								BorderSizePixel = 0,
							},

							New "TextLabel" {
								Name = "ScoreLabel",
								AnchorPoint = Vector2.new(0.5, 0),
								Position = UDim2.fromScale(0.5, 0.27),
								Size = UDim2.fromScale(0.5, 0.04),
								BackgroundTransparency = 1,
								Text = "FINAL SCORE",
								TextColor3 = TEXT_DIM,
								Font = Enum.Font.GothamBold,
								TextScaled = true,
							},

							New "TextLabel" {
								Name = "ScoreValue",
								AnchorPoint = Vector2.new(0.5, 0),
								Position = UDim2.fromScale(0.5, 0.31),
								Size = UDim2.fromScale(0.9, 0.18),
								BackgroundTransparency = 1,
								Text = scoreDisplay,
								TextColor3 = SCORE_GOLD,
								Font = Enum.Font.GothamBlack,
								TextScaled = true,
							},

							New "Frame" {
								Name = "StatsRow",
								AnchorPoint = Vector2.new(0.5, 0),
								Position = UDim2.fromScale(0.5, 0.50),
								Size = UDim2.fromScale(0.85, 0.08),
								BackgroundColor3 = Color3.fromRGB(8, 14, 26),
								BackgroundTransparency = 0.3,

								[Children] = {
									New "UICorner" {
										CornerRadius = UDim.new(0.2, 0),
									},

									New "TextLabel" {
										Name = "DistIcon",
										AnchorPoint = Vector2.new(0, 0.5),
										Position = UDim2.fromScale(0.05, 0.5),
										Size = UDim2.fromScale(0.3, 0.5),
										BackgroundTransparency = 1,
										Text = "DISTANCE",
										TextColor3 = TEXT_DIM,
										Font = Enum.Font.GothamBold,
										TextScaled = true,
										TextXAlignment = Enum.TextXAlignment.Left,
									},

									New "TextLabel" {
										Name = "DistValue",
										AnchorPoint = Vector2.new(1, 0.5),
										Position = UDim2.fromScale(0.95, 0.5),
										Size = UDim2.fromScale(0.5, 0.6),
										BackgroundTransparency = 1,
										Text = distanceDisplay,
										TextColor3 = TEXT_PRIMARY,
										Font = Enum.Font.GothamBlack,
										TextScaled = true,
										TextXAlignment = Enum.TextXAlignment.Right,
									},
								},
							},

							New "Frame" {
								Name = "Divider2",
								AnchorPoint = Vector2.new(0.5, 0),
								Position = UDim2.fromScale(0.5, 0.60),
								Size = UDim2.fromScale(0.8, 0.003),
								BackgroundColor3 = DIVIDER_COLOR,
								BackgroundTransparency = 0.2,
								BorderSizePixel = 0,
							},

							New "Frame" {
								Name = "RankBadge",
								AnchorPoint = Vector2.new(0.5, 0),
								Position = UDim2.fromScale(0.5, 0.62),
								Size = UDim2.fromScale(0.85, 0.16),
								BackgroundColor3 = rankBgColor,
								BackgroundTransparency = 0.1,
								Visible = Computed(function()
									return rankValue:get() ~= nil
								end),

								[Children] = {
									New "UICorner" {
										CornerRadius = UDim.new(0.18, 0),
									},

									New "UIStroke" {
										Color = rankStrokeColor,
										Thickness = 2.5,
										Transparency = 0.1,
									},

									New "TextLabel" {
										Name = "RankText",
										AnchorPoint = Vector2.new(0.5, 0.5),
										Position = UDim2.fromScale(0.5, 0.5),
										Size = UDim2.fromScale(0.9, 0.65),
										BackgroundTransparency = 1,
										Text = rankText,
										TextColor3 = rankColor,
										Font = Enum.Font.GothamBlack,
										TextScaled = true,
									},
								},
							},

							New "Frame" {
								Name = "BottomBar",
								AnchorPoint = Vector2.new(0.5, 1),
								Position = UDim2.fromScale(0.5, 0.95),
								Size = UDim2.fromScale(0.7, 0.06),
								BackgroundTransparency = 1,

								[Children] = {
									New "TextLabel" {
										Name = "StatusLabel",
										AnchorPoint = Vector2.new(0.5, 0.5),
										Position = UDim2.fromScale(0.5, 0.5),
										Size = UDim2.fromScale(1, 0.7),
										BackgroundTransparency = 1,
										Text = statusText,
										TextColor3 = SUCCESS_GREEN,
										Font = Enum.Font.GothamBold,
										TextScaled = true,
									},
								},
							},
						},
					},
				},
			},
		},
	}

	trove:Add(screenGui)

	local function show(data)
		finalScore:set(data.score or 0)
		finalDistance:set(data.distance or 0)
		playerName:set(data.name or "")
		reason:set(data.reason or "TIME UP")
		rankValue:set(data.rank)
		statusText:set("SAVING...")
		containerScale:set(0.75)
		task.defer(function()
			containerScale:set(1)
		end)
	end

	local function setStatus(text)
		statusText:set(text)
	end

	local function setRank(rank)
		rankValue:set(rank)
	end

	local function destroy()
		trove:Destroy()
	end

	return {
		show = show,
		setStatus = setStatus,
		setRank = setRank,
		destroy = destroy,
	}
end

return LakelandEndGameUI
