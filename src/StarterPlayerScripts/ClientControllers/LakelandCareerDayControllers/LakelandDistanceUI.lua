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
local TEXT_DIM = Color3.fromRGB(70, 100, 140)
local SCORE_GOLD = Color3.fromRGB(255, 220, 60)
local PLAYER_CYAN = Color3.fromRGB(0, 210, 255)
local BOOST_CYAN = Color3.fromRGB(50, 200, 255)
local COMBO_HOT = Color3.fromRGB(255, 50, 150)

local LakelandDistanceUI = {}

function LakelandDistanceUI.new(playerGui, gameState, playerName, beatIntensity)
	local trove = Trove.new()

	local score = Value(0)
	local coinPickupText = Value("")
	local coinPickupAlpha = Value(0)
	local animatedCoinAlpha = Spring(coinPickupAlpha, 12, 0.9)
	local boostActive = Value(false)
	local boostTally = Value(0)
	local boostAlpha = Spring(Computed(function()
		return boostActive:get() and 1 or 0
	end), 14, 0.8)
	local boostPulse = Value(1)
	local animatedBoostPulse = Spring(boostPulse, 20, 0.6)
	local boostText = Computed(function()
		return "BOOST +" .. tostring(boostTally:get())
	end)

	local comboCount = Value(0)
	local comboAlpha = Value(0)
	local animatedComboAlpha = Spring(comboAlpha, 14, 0.8)
	local comboPulse = Value(1)
	local animatedComboPulse = Spring(comboPulse, 22, 0.55)
	local comboText = Computed(function()
		local c = comboCount:get()
		return c >= 2 and ("x" .. tostring(c)) or ""
	end)

	local visible = Computed(function()
		return gameState:get() == "PLAYING"
	end)

	local slideY = Spring(Computed(function()
		return visible:get() and 0.015 or -0.15
	end), 16, 0.75)


	local animatedScore = Spring(score, 12, 0.8)
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

	local screenGui = New "ScreenGui" {
		Name = "LakelandDistanceUI",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = 52,
		Enabled = visible,
		Parent = playerGui,

		[Children] = {
			New "Frame" {
				Name = "HUDPanel",
				AnchorPoint = Vector2.new(0.5, 0),
				Position = Computed(function()
					return UDim2.fromScale(0.5, slideY:get())
				end),
				Size = Computed(function()
					local b = beatIntensity and beatIntensity:get() or 0
					local s = 1 + b * 0.06
					return UDim2.fromScale(0.18 * s, 0.13 * s)
				end),
				BackgroundColor3 = BG_PANEL,
				BackgroundTransparency = 0.12,
				Visible = visible,

				[Children] = {
					New "UICorner" {
						CornerRadius = UDim.new(0.08, 0),
					},

					New "UIStroke" {
						Color = BORDER_CYAN,
						Thickness = Computed(function()
							local b = beatIntensity and beatIntensity:get() or 0
							return 2 + b * 3
						end),
						Transparency = Computed(function()
							local b = beatIntensity and beatIntensity:get() or 0
							return 0.15 - b * 0.15
						end),
					},

					New "UIGradient" {
						Color = ColorSequence.new(
							Color3.fromRGB(255, 255, 255),
							Color3.fromRGB(170, 185, 210)
						),
						Rotation = 90,
					},

					New "Frame" {
						Name = "ScoreSection",
						AnchorPoint = Vector2.new(0, 0),
						Position = UDim2.fromScale(0.03, 0.08),
						Size = UDim2.fromScale(0.94, 0.84),
						BackgroundTransparency = 1,

						[Children] = {
							New "TextLabel" {
								Name = "ScoreLabel",
								AnchorPoint = Vector2.new(0, 0),
								Position = UDim2.fromScale(0, 0),
								Size = UDim2.fromScale(1, 0.22),
								BackgroundTransparency = 1,
								Text = "SCORE",
								TextColor3 = TEXT_DIM,
								Font = Enum.Font.GothamBold,
								TextScaled = true,
								TextXAlignment = Enum.TextXAlignment.Left,
							},

							New "TextLabel" {
								Name = "ScoreValue",
								AnchorPoint = Vector2.new(0, 0),
								Position = UDim2.fromScale(0, 0.20),
								Size = UDim2.fromScale(1, 0.45),
								BackgroundTransparency = 1,
								Text = scoreDisplay,
								TextColor3 = SCORE_GOLD,
								Font = Enum.Font.GothamBlack,
								TextScaled = true,
								TextXAlignment = Enum.TextXAlignment.Left,
							},

							New "TextLabel" {
								Name = "PlayerName",
								AnchorPoint = Vector2.new(0, 1),
								Position = UDim2.fromScale(0, 1),
								Size = UDim2.fromScale(1, 0.25),
								BackgroundTransparency = 1,
								Text = playerName or "",
								TextColor3 = PLAYER_CYAN,
								Font = Enum.Font.GothamBold,
								TextScaled = true,
								TextXAlignment = Enum.TextXAlignment.Left,
								TextTruncate = Enum.TextTruncate.AtEnd,
							},
						},
					},
				},
			},

			New "TextLabel" {
				Name = "CoinPickup",
				AnchorPoint = Vector2.new(0.5, 0),
				Position = UDim2.fromScale(0.5, 0.155),
				Size = UDim2.fromScale(0.15, 0.04),
				BackgroundTransparency = 1,
				Text = coinPickupText,
				TextColor3 = SCORE_GOLD,
				Font = Enum.Font.GothamBlack,
				TextScaled = true,
				TextTransparency = Computed(function()
					return 1 - animatedCoinAlpha:get()
				end),
				Visible = visible,
			},

			New "TextLabel" {
				Name = "ComboLabel",
				AnchorPoint = Vector2.new(0.5, 0),
				Position = UDim2.fromScale(0.5, 0.20),
				Size = Computed(function()
					local s = animatedComboPulse:get()
					return UDim2.fromScale(0.12 * s, 0.05 * s)
				end),
				BackgroundTransparency = 1,
				Text = comboText,
				TextColor3 = COMBO_HOT,
				Font = Enum.Font.GothamBlack,
				TextScaled = true,
				TextTransparency = Computed(function()
					return 1 - animatedComboAlpha:get()
				end),
				Visible = Computed(function()
					return visible:get() and animatedComboAlpha:get() > 0.01
				end),

				[Children] = {
					New "UIStroke" {
						Color = Color3.fromRGB(255, 255, 255),
						Thickness = 1,
						Transparency = Computed(function()
							return 1 - animatedComboAlpha:get() * 0.3
						end),
					},
				},
			},

			New "Frame" {
				Name = "BoostMultiplier",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.32),
				Size = Computed(function()
					local s = animatedBoostPulse:get()
					return UDim2.fromScale(0.16 * s, 0.06 * s)
				end),
				BackgroundColor3 = Color3.fromRGB(8, 30, 45),
				BackgroundTransparency = Computed(function()
					return 1 - boostAlpha:get() * 0.15
				end),
				Visible = Computed(function()
					return visible:get() and boostAlpha:get() > 0.01
				end),

				[Children] = {
					New "UICorner" {
						CornerRadius = UDim.new(0.3, 0),
					},

					New "UIStroke" {
						Color = BOOST_CYAN,
						Thickness = 2,
						Transparency = Computed(function()
							return 1 - boostAlpha:get() * 0.5
						end),
					},

					New "TextLabel" {
						Name = "MultiplierText",
						AnchorPoint = Vector2.new(0.5, 0.5),
						Position = UDim2.fromScale(0.5, 0.5),
						Size = UDim2.fromScale(0.9, 0.8),
						BackgroundTransparency = 1,
						Text = boostText,
						TextColor3 = Color3.fromRGB(255, 255, 255),
						Font = Enum.Font.GothamBlack,
						TextScaled = true,
						TextTransparency = Computed(function()
							return 1 - boostAlpha:get()
						end),
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
			score:set(math.floor(dist * 10) + coinBonus)
			if raceController:IsBoosting() then
				boostTally:set(raceController:GetBoostTally())
			end
			if raceController:GetComboCount() == 0 and comboAlpha:get() > 0 then
				comboAlpha:set(0)
			end
		end))

		trove:Add(raceController.CoinCollected:Connect(function(totalCoinScore, totalCoins, combo, earned)
			earned = earned or 50
			coinPickupText:set("+" .. tostring(earned))
			coinPickupAlpha:set(1)
			task.delay(0.6, function()
				coinPickupAlpha:set(0)
			end)
			combo = combo or 0
			if combo >= 2 then
				comboCount:set(combo)
				comboAlpha:set(1)
				comboPulse:set(1.4)
				task.defer(function()
					comboPulse:set(1)
				end)
			end
		end))

		trove:Add(raceController.BoostChanged:Connect(function(isBoosting, finalTally)
			boostActive:set(isBoosting)
			if isBoosting then
				boostTally:set(0)
				boostPulse:set(1.3)
				task.defer(function()
					boostPulse:set(1)
				end)
			end
		end))
	end

	task.spawn(bind)

	local function getScore()
		return math.floor(score:get())
	end

	local function destroy()
		trove:Destroy()
	end

	return {
		destroy = destroy,
		getScore = getScore,
	}
end

return LakelandDistanceUI
