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
		return visible:get() and 0.97 or 1.15
	end), 18, 0.75)

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
			return Color3.fromRGB(255, 140, 40)
		elseif frac > 0.75 then
			return Color3.fromRGB(255, 80, 60)
		elseif frac > 0.4 then
			return Color3.fromRGB(80, 180, 255)
		else
			return Color3.fromRGB(120, 220, 120)
		end
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
				return UDim2.fromScale(0.02, slideY:get())
			end),
			Size = UDim2.fromScale(0.14, 0.15),
			BackgroundColor3 = Color3.fromRGB(20, 20, 30),
			BackgroundTransparency = 0.3,
				Visible = visible,

				[Children] = {
					New "UICorner" {
						CornerRadius = UDim.new(0.1, 0),
					},

					New "UIStroke" {
						Color = Computed(function()
							if boosting:get() then
								return Color3.fromRGB(255, 140, 40)
							end
							return Color3.fromRGB(80, 80, 100)
						end),
						Thickness = 2,
						Transparency = 0.4,
					},

					New "TextLabel" {
						Name = "SpeedValue",
						AnchorPoint = Vector2.new(0.5, 0),
						Position = UDim2.fromScale(0.5, 0.05),
						Size = UDim2.fromScale(0.9, 0.45),
						BackgroundTransparency = 1,
						Text = speedText,
						TextColor3 = Color3.fromRGB(255, 255, 255),
						Font = Enum.Font.GothamBlack,
						TextScaled = true,
					},

					New "TextLabel" {
						Name = "SpeedUnit",
						AnchorPoint = Vector2.new(0.5, 0),
						Position = UDim2.fromScale(0.5, 0.48),
						Size = UDim2.fromScale(0.9, 0.15),
						BackgroundTransparency = 1,
						Text = "STUDS/S",
						TextColor3 = Color3.fromRGB(150, 150, 170),
						Font = Enum.Font.GothamBold,
						TextScaled = true,
					},

					New "Frame" {
						Name = "BarBg",
						AnchorPoint = Vector2.new(0.5, 0),
						Position = UDim2.fromScale(0.5, 0.68),
						Size = UDim2.fromScale(0.85, 0.12),
						BackgroundColor3 = Color3.fromRGB(40, 40, 50),
						BorderSizePixel = 0,

						[Children] = {
							New "UICorner" {
								CornerRadius = UDim.new(0.4, 0),
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
										CornerRadius = UDim.new(0.4, 0),
									},
								},
							},
						},
					},

					New "TextLabel" {
						Name = "BoostLabel",
						AnchorPoint = Vector2.new(0.5, 1),
						Position = UDim2.fromScale(0.5, 0.96),
						Size = UDim2.fromScale(0.9, 0.12),
						BackgroundTransparency = 1,
						Text = Computed(function()
							if boosting:get() then
								return "BOOST!"
							end
							return ""
						end),
						TextColor3 = Color3.fromRGB(255, 200, 60),
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
