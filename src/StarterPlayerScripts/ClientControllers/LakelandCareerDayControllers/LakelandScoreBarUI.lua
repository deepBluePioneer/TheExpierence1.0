local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Packages = ReplicatedStorage.Packages
local Knit = require(Packages.Knit)
local Trove = require(Packages.Trove)

local CustomPackages = ReplicatedStorage.CustomPackages
local Fusion = require(CustomPackages.FusionRoot.Fusion)

local New = Fusion.New
local Value = Fusion.Value
local Computed = Fusion.Computed
local Children = Fusion.Children
local Spring = Fusion.Spring

local BG_PANEL = Color3.fromRGB(8, 14, 28)
local BORDER_CYAN = Color3.fromRGB(0, 140, 200)
local TRACK_BG = Color3.fromRGB(18, 28, 45)
local PLAYER_CYAN = Color3.fromRGB(0, 210, 255)

local RANK_COLORS = {
	Color3.fromRGB(255, 215, 0),
	Color3.fromRGB(200, 200, 220),
	Color3.fromRGB(205, 140, 55),
}

local function formatScore(n)
	if n >= 1000000 then
		return string.format("%.1fM", n / 1000000)
	elseif n >= 10000 then
		return string.format("%.0fk", n / 1000)
	elseif n >= 1000 then
		return string.format("%.1fk", n / 1000)
	end
	return tostring(math.floor(n))
end

local function createRankMarker(frac, label, color, scoreText)
	return New "Frame" {
		Name = "Rank" .. label,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = Computed(function()
			return UDim2.fromScale(0, 1 - frac:get())
		end),
		Size = UDim2.fromScale(1, 0),
		BackgroundTransparency = 1,

		Visible = Computed(function()
			return frac:get() > 0.001
		end),

		[Children] = {
			New "Frame" {
				Name = "Tick",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.new(0.65, 0, 0, 2),
				BackgroundColor3 = color,
				BackgroundTransparency = 0.15,
				BorderSizePixel = 0,
			},

			New "TextLabel" {
				Name = "RankLabel",
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.fromScale(-0.1, 0.5),
				Size = UDim2.new(0, 22, 0, 14),
				BackgroundTransparency = 1,
				Text = "#" .. label,
				TextColor3 = color,
				Font = Enum.Font.GothamBlack,
				TextScaled = true,
			},

			New "TextLabel" {
				Name = "ScoreLabel",
				AnchorPoint = Vector2.new(0, 0.5),
				Position = UDim2.fromScale(1.1, 0.5),
				Size = UDim2.new(0, 40, 0, 12),
				BackgroundTransparency = 1,
				Text = scoreText,
				TextColor3 = color,
				Font = Enum.Font.GothamBold,
				TextScaled = true,
				TextTransparency = 0.25,
				TextXAlignment = Enum.TextXAlignment.Left,
			},
		},
	}
end

local LakelandScoreBarUI = {}

function LakelandScoreBarUI.new(playerGui, gameState, topScores, playerName, beatIntensity)
	local trove = Trove.new()

	local currentScore = Value(0)
	local animatedScore = Spring(currentScore, 14, 0.85)

	local visible = Computed(function()
		return gameState:get() == "PLAYING"
	end)

	local slideX = Spring(Computed(function()
		return visible:get() and 0.02 or -0.06
	end), 16, 0.75)

	local function getTopScore(rank)
		return Computed(function()
			local entries = topScores:get()
			if entries[rank] and entries[rank].score then
				return entries[rank].score
			end
			return 0
		end)
	end

	local score1 = getTopScore(1)
	local score2 = getTopScore(2)
	local score3 = getTopScore(3)

	local maxBarScore = Computed(function()
		local s1 = score1:get()
		if s1 <= 0 then return 10000 end
		return s1 * 1.15
	end)

	local function scoreFrac(scoreVal)
		return Computed(function()
			local maxS = maxBarScore:get()
			if maxS <= 0 then return 0 end
			return math.clamp(scoreVal:get() / maxS, 0, 1)
		end)
	end

	local playerFrac = Computed(function()
		local maxS = maxBarScore:get()
		if maxS <= 0 then return 0 end
		return math.clamp(animatedScore:get() / maxS, 0, 1)
	end)

	local frac1 = scoreFrac(score1)
	local frac2 = scoreFrac(score2)
	local frac3 = scoreFrac(score3)

	local scoreText1 = Computed(function() return formatScore(score1:get()) end)
	local scoreText2 = Computed(function() return formatScore(score2:get()) end)
	local scoreText3 = Computed(function() return formatScore(score3:get()) end)

	local screenGui = New "ScreenGui" {
		Name = "LakelandScoreBarUI",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = 55,
		Enabled = visible,
		Parent = playerGui,

		[Children] = {
			New "Frame" {
				Name = "BarContainer",
				AnchorPoint = Vector2.new(0, 0.5),
				Position = Computed(function()
					return UDim2.fromScale(slideX:get(), 0.5)
				end),
				Size = UDim2.fromScale(0.035, 0.55),
				BackgroundColor3 = BG_PANEL,
				BackgroundTransparency = 0.15,
				Visible = visible,

				[Children] = {
					New "UICorner" {
						CornerRadius = UDim.new(0.15, 0),
					},

					New "UIStroke" {
						Color = BORDER_CYAN,
						Thickness = Computed(function()
							local b = beatIntensity and beatIntensity:get() or 0
							return 1.5 + b * 3
						end),
						Transparency = Computed(function()
							local b = beatIntensity and beatIntensity:get() or 0
							return 0.35 - b * 0.3
						end),
					},

					New "UIPadding" {
						PaddingTop = UDim.new(0.03, 0),
						PaddingBottom = UDim.new(0.03, 0),
					},

					New "Frame" {
						Name = "Track",
						AnchorPoint = Vector2.new(0.5, 0.5),
						Position = UDim2.fromScale(0.5, 0.5),
						Size = UDim2.fromScale(0.1, 1),
						BackgroundColor3 = TRACK_BG,
						BackgroundTransparency = 0.2,
						BorderSizePixel = 0,

						[Children] = {
							New "UICorner" {
								CornerRadius = UDim.new(0.5, 0),
							},
						},
					},

					New "Frame" {
						Name = "FillBar",
						AnchorPoint = Vector2.new(0.5, 1),
						Position = UDim2.fromScale(0.5, 1),
						Size = Computed(function()
							return UDim2.fromScale(0.1, math.clamp(playerFrac:get(), 0, 1))
						end),
						BackgroundColor3 = PLAYER_CYAN,
						BackgroundTransparency = Computed(function()
							local b = beatIntensity and beatIntensity:get() or 0
							return 0.4 - b * 0.4
						end),
						BorderSizePixel = 0,

						[Children] = {
							New "UICorner" {
								CornerRadius = UDim.new(0.5, 0),
							},
						},
					},

					New "Frame" {
						Name = "MarkersContainer",
						Size = UDim2.fromScale(1, 1),
						BackgroundTransparency = 1,

						[Children] = {
							createRankMarker(frac3, "3", RANK_COLORS[3], scoreText3),
							createRankMarker(frac2, "2", RANK_COLORS[2], scoreText2),
							createRankMarker(frac1, "1", RANK_COLORS[1], scoreText1),
						},
					},

					New "Frame" {
						Name = "PlayerMarker",
						AnchorPoint = Vector2.new(0.5, 0.5),
						Position = Computed(function()
							return UDim2.fromScale(0.5, 1 - math.clamp(playerFrac:get(), 0, 1))
						end),
						Size = UDim2.new(0, 12, 0, 12),
						BackgroundColor3 = PLAYER_CYAN,
						BackgroundTransparency = 0,
						Rotation = 45,
						BorderSizePixel = 0,

						[Children] = {
							New "UICorner" {
								CornerRadius = UDim.new(0.15, 0),
							},

							New "UIStroke" {
								Color = Color3.fromRGB(200, 245, 255),
								Thickness = 1.5,
								Transparency = 0.2,
							},
						},
					},

					New "TextLabel" {
						Name = "PlayerScoreLabel",
						AnchorPoint = Vector2.new(0, 0.5),
						Position = Computed(function()
							return UDim2.fromScale(1.15, 1 - math.clamp(playerFrac:get(), 0.03, 0.97))
						end),
						Size = UDim2.new(0, 48, 0, 13),
						BackgroundTransparency = 1,
						Text = Computed(function()
							return formatScore(animatedScore:get())
						end),
						TextColor3 = PLAYER_CYAN,
						Font = Enum.Font.GothamBlack,
						TextScaled = true,
						TextXAlignment = Enum.TextXAlignment.Left,
					},

					New "TextLabel" {
						Name = "YouLabel",
						AnchorPoint = Vector2.new(0, 0.5),
						Position = Computed(function()
							return UDim2.fromScale(1.15, 1 - math.clamp(playerFrac:get(), 0.03, 0.97) - 0.04)
						end),
						Size = UDim2.new(0, 56, 0, 12),
						BackgroundTransparency = 1,
						Text = Computed(function()
							local name = playerName and playerName:get() or ""
							if #name > 0 then return name end
							return "YOU"
						end),
						TextColor3 = PLAYER_CYAN,
						Font = Enum.Font.GothamBlack,
						TextScaled = true,
						TextTruncate = Enum.TextTruncate.AtEnd,
						TextXAlignment = Enum.TextXAlignment.Left,
					},
				},
			},
		},
	}

	trove:Add(screenGui)

	local raceController = nil

	local function bind()
		raceController = Knit.GetController("LakelandRaceController")

		trove:Add(RunService.RenderStepped:Connect(function()
			if gameState:get() ~= "PLAYING" then return end
			local dist = raceController:GetDistance()
			local coinBonus = raceController:GetCoinScore()
			currentScore:set(math.floor(dist * 10) + coinBonus)
		end))
	end

	task.spawn(bind)

	local function reset()
		currentScore:set(0)
	end

	local function destroy()
		trove:Destroy()
	end

	return {
		destroy = destroy,
		reset = reset,
	}
end

return LakelandScoreBarUI
