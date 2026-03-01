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

local LakelandDistanceUI = {}

function LakelandDistanceUI.new(playerGui, gameState)
	local trove = Trove.new()

	local distance = Value(0)
	local score = Value(0)
	local coinPickupText = Value("")
	local coinPickupAlpha = Value(0)
	local animatedCoinAlpha = Spring(coinPickupAlpha, 12, 0.9)

	local visible = Computed(function()
		return gameState:get() == "PLAYING"
	end)

	local slideY = Spring(Computed(function()
		return visible:get() and 0.12 or -0.1
	end), 18, 0.75)

	local distanceText = Computed(function()
		local d = math.floor(distance:get())
		if d >= 1000 then
			return string.format("%.1fkm", d / 1000)
		end
		return d .. "m"
	end)

	local animatedScore = Spring(score, 12, 0.8)
	local scoreDisplay = Computed(function()
		return string.format("%06d", math.floor(animatedScore:get()))
	end)

	local screenGui = New "ScreenGui" {
		Name = "LakelandDistanceUI",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = 52,
		Parent = playerGui,

		[Children] = {
			New "Frame" {
				Name = "DistanceContainer",
				AnchorPoint = Vector2.new(0.5, 0),
				Position = Computed(function()
					return UDim2.fromScale(0.5, slideY:get())
				end),
				Size = UDim2.fromScale(0.18, 0.09),
				BackgroundColor3 = Color3.fromRGB(20, 20, 30),
				BackgroundTransparency = 0.3,
				Visible = visible,

				[Children] = {
					New "UICorner" {
						CornerRadius = UDim.new(0.15, 0),
					},

					New "UIStroke" {
						Color = Color3.fromRGB(80, 80, 100),
						Thickness = 2,
						Transparency = 0.4,
					},

					New "TextLabel" {
						Name = "ScoreLabel",
						AnchorPoint = Vector2.new(0.5, 0),
						Position = UDim2.fromScale(0.5, 0.05),
						Size = UDim2.fromScale(0.9, 0.15),
						BackgroundTransparency = 1,
						Text = "SCORE",
						TextColor3 = Color3.fromRGB(150, 150, 170),
						Font = Enum.Font.GothamBold,
						TextScaled = true,
					},

					New "TextLabel" {
						Name = "ScoreValue",
						AnchorPoint = Vector2.new(0.5, 0),
						Position = UDim2.fromScale(0.5, 0.2),
						Size = UDim2.fromScale(0.9, 0.35),
						BackgroundTransparency = 1,
						Text = scoreDisplay,
						TextColor3 = Color3.fromRGB(255, 220, 80),
						Font = Enum.Font.GothamBlack,
						TextScaled = true,
					},

					New "Frame" {
						Name = "Divider",
						AnchorPoint = Vector2.new(0.5, 0.5),
						Position = UDim2.fromScale(0.5, 0.58),
						Size = UDim2.fromScale(0.85, 0.01),
						BackgroundColor3 = Color3.fromRGB(80, 80, 100),
						BackgroundTransparency = 0.5,
						BorderSizePixel = 0,
					},

					New "TextLabel" {
						Name = "DistLabel",
						AnchorPoint = Vector2.new(0.5, 0),
						Position = UDim2.fromScale(0.5, 0.62),
						Size = UDim2.fromScale(0.9, 0.15),
						BackgroundTransparency = 1,
						Text = "DISTANCE",
						TextColor3 = Color3.fromRGB(150, 150, 170),
						Font = Enum.Font.GothamBold,
						TextScaled = true,
					},

					New "TextLabel" {
						Name = "DistValue",
						AnchorPoint = Vector2.new(0.5, 0),
						Position = UDim2.fromScale(0.5, 0.77),
						Size = UDim2.fromScale(0.9, 0.2),
						BackgroundTransparency = 1,
						Text = distanceText,
						TextColor3 = Color3.fromRGB(255, 255, 255),
						Font = Enum.Font.GothamBlack,
						TextScaled = true,
					},
				},
			},

			New "TextLabel" {
				Name = "CoinPickup",
				AnchorPoint = Vector2.new(0.5, 0),
				Position = UDim2.fromScale(0.5, 0.215),
				Size = UDim2.fromScale(0.12, 0.025),
				BackgroundTransparency = 1,
				Text = coinPickupText,
				TextColor3 = Color3.fromRGB(255, 220, 50),
				Font = Enum.Font.GothamBlack,
				TextScaled = true,
				TextTransparency = Computed(function()
					return 1 - animatedCoinAlpha:get()
				end),
				Visible = visible,
			},
		},
	}

	trove:Add(screenGui)

	local raceController = nil

	local function bind()
		raceController = Knit.GetController("LakelandRaceController")

		trove:Add(RunService.Heartbeat:Connect(function()
			if gameState:get() ~= "PLAYING" then return end
			local dist = raceController:GetDistance()
			local coinBonus = raceController:GetCoinScore()
			distance:set(dist)
			score:set(math.floor(dist * 10) + coinBonus)
		end))

		trove:Add(raceController.CoinCollected:Connect(function(totalCoinScore, totalCoins)
			coinPickupText:set("+50")
			coinPickupAlpha:set(1)
			task.delay(0.6, function()
				coinPickupAlpha:set(0)
			end)
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
