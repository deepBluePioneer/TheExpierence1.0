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
local TEXT_PRIMARY = Color3.fromRGB(220, 235, 255)
local TEXT_DIM = Color3.fromRGB(70, 100, 140)
local BAR_BG = Color3.fromRGB(20, 30, 45)
local BOOST_ORANGE = Color3.fromRGB(255, 160, 40)

local LakelandSpeedUI = {}

function LakelandSpeedUI.new(playerGui, gameState)
	local trove = Trove.new()

	local speed = Value(0)
	local maxSpeed = Value(220)
	local boosting = Value(false)

	local visible = Computed(function()
		return gameState:get() == "PLAYING"
	end)

	local slideY = Spring(Computed(function()
		return visible:get() and 0.97 or 1.2
	end), 16, 0.75)

	local speedFrac = Computed(function()
		return math.clamp(speed:get() / maxSpeed:get(), 0, 1)
	end)

	local animatedFrac = Spring(speedFrac, 14, 0.8)

	local speedText = Computed(function()
		return math.floor(speed:get()) .. ""
	end)

	local barColor = Computed(function()
		local frac = speedFrac:get()
		if boosting:get() then
			return BOOST_ORANGE
		elseif frac > 0.75 then
			return Color3.fromRGB(255, 60, 50)
		elseif frac > 0.4 then
			return Color3.fromRGB(0, 200, 255)
		else
			return Color3.fromRGB(0, 220, 160)
		end
	end)

	local borderColor = Computed(function()
		if boosting:get() then return BOOST_ORANGE end
		return BORDER_CYAN
	end)

	local screenGui = New "ScreenGui" {
		Name = "LakelandSpeedUI",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = 53,
		Enabled = visible,
		Parent = playerGui,

		[Children] = {
			New "Frame" {
				Name = "SpeedContainer",
				AnchorPoint = Vector2.new(0, 1),
				Position = Computed(function()
					return UDim2.fromScale(0.015, slideY:get())
				end),
				Size = UDim2.fromScale(0.13, 0.17),
				BackgroundColor3 = BG_PANEL,
				BackgroundTransparency = 0.12,
				Visible = visible,

				[Children] = {
					New "UICorner" {
						CornerRadius = UDim.new(0.1, 0),
					},

					New "UIStroke" {
						Color = borderColor,
						Thickness = 2,
						Transparency = 0.2,
					},

					New "UIGradient" {
						Color = ColorSequence.new(
							Color3.fromRGB(255, 255, 255),
							Color3.fromRGB(170, 185, 210)
						),
						Rotation = 90,
					},

					New "TextLabel" {
						Name = "SpeedValue",
						AnchorPoint = Vector2.new(0.5, 0),
						Position = UDim2.fromScale(0.5, 0.04),
						Size = UDim2.fromScale(0.9, 0.45),
						BackgroundTransparency = 1,
						Text = speedText,
						TextColor3 = TEXT_PRIMARY,
						Font = Enum.Font.GothamBlack,
						TextScaled = true,
					},

					New "TextLabel" {
						Name = "SpeedUnit",
						AnchorPoint = Vector2.new(0.5, 0),
						Position = UDim2.fromScale(0.5, 0.47),
						Size = UDim2.fromScale(0.9, 0.13),
						BackgroundTransparency = 1,
						Text = "STUDS/S",
						TextColor3 = TEXT_DIM,
						Font = Enum.Font.GothamBold,
						TextScaled = true,
					},

					New "Frame" {
						Name = "BarBg",
						AnchorPoint = Vector2.new(0.5, 0),
						Position = UDim2.fromScale(0.5, 0.66),
						Size = UDim2.fromScale(0.82, 0.13),
						BackgroundColor3 = BAR_BG,
						BorderSizePixel = 0,

						[Children] = {
							New "UICorner" {
								CornerRadius = UDim.new(0.35, 0),
							},

							New "Frame" {
								Name = "BarFill",
								AnchorPoint = Vector2.new(0, 0.5),
								Position = UDim2.fromScale(0, 0.5),
								Size = Spring(Computed(function()
									local frac = math.clamp(animatedFrac:get(), 0, 1)
									return UDim2.fromScale(frac, 1)
								end), 18, 0.7),
								BackgroundColor3 = barColor,
								BorderSizePixel = 0,

								[Children] = {
									New "UICorner" {
										CornerRadius = UDim.new(0.35, 0),
									},
								},
							},
						},
					},

					New "TextLabel" {
						Name = "BoostLabel",
						AnchorPoint = Vector2.new(0.5, 1),
						Position = UDim2.fromScale(0.5, 0.96),
						Size = UDim2.fromScale(0.9, 0.13),
						BackgroundTransparency = 1,
						Text = Computed(function()
							if boosting:get() then return "BOOST ACTIVE" end
							return ""
						end),
						TextColor3 = BOOST_ORANGE,
						Font = Enum.Font.GothamBlack,
						TextScaled = true,
					},
				},
			},
		},
	}

	trove:Add(screenGui)

	local function bind()
		local raceController = Knit.GetController("LakelandRaceController")
		maxSpeed:set(raceController:GetMaxSpeed())

		trove:Add(RunService.RenderStepped:Connect(function()
			if gameState:get() ~= "PLAYING" then return end
			speed:set(raceController:GetCurrentSpeed())
			boosting:set(raceController:IsBoosting())
		end))
	end

	task.spawn(bind)

	local function destroy()
		trove:Destroy()
	end

	return {
		destroy = destroy,
	}
end

return LakelandSpeedUI
