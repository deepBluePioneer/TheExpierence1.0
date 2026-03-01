local ReplicatedStorage = game:GetService("ReplicatedStorage")

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

local LakelandHealthBarUI = {}

function LakelandHealthBarUI.new(playerGui, gameState)
	local trove = Trove.new()

	local healthFrac = Value(1)
	local hitFlash = Value(0)
	local animatedFlash = Spring(hitFlash, 20, 0.8)

	local visible = Computed(function()
		return gameState:get() == "PLAYING"
	end)

	local slideY = Spring(Computed(function()
		return visible:get() and 0.09 or -0.05
	end), 18, 0.75)

	local barColor = Computed(function()
		local frac = healthFrac:get()
		if frac > 0.5 then
			return Color3.fromRGB(80, 220, 80)
		elseif frac > 0.25 then
			return Color3.fromRGB(255, 200, 50)
		else
			return Color3.fromRGB(255, 60, 40)
		end
	end)

	local screenGui = New "ScreenGui" {
		Name = "LakelandHealthBarUI",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = 51,
		Parent = playerGui,

		[Children] = {
			New "Frame" {
				Name = "HealthContainer",
				AnchorPoint = Vector2.new(0.5, 0),
				Position = Computed(function()
					return UDim2.fromScale(0.5, slideY:get())
				end),
				Size = UDim2.fromScale(0.2, 0.025),
				BackgroundColor3 = Color3.fromRGB(20, 20, 30),
				BackgroundTransparency = 0.3,
				Visible = visible,

				[Children] = {
					New "UICorner" {
						CornerRadius = UDim.new(0.4, 0),
					},

					New "UIStroke" {
						Color = Computed(function()
							local flash = animatedFlash:get()
							if flash > 0.1 then
								return Color3.fromRGB(255, 60, 40)
							end
							return Color3.fromRGB(80, 80, 100)
						end),
						Thickness = 2,
						Transparency = 0.4,
					},

					New "Frame" {
						Name = "BarFill",
						AnchorPoint = Vector2.new(0, 0.5),
						Position = UDim2.fromScale(0.02, 0.5),
						Size = Spring(Computed(function()
							local frac = math.clamp(healthFrac:get(), 0, 1)
							return UDim2.fromScale(0.96 * frac, 0.7)
						end), 18, 0.7),
						BackgroundColor3 = barColor,
						BorderSizePixel = 0,

						[Children] = {
							New "UICorner" {
								CornerRadius = UDim.new(0.4, 0),
							},
						},
					},

					New "TextLabel" {
						Name = "HealthText",
						AnchorPoint = Vector2.new(0.5, 0.5),
						Position = UDim2.fromScale(0.5, 0.5),
						Size = UDim2.fromScale(0.9, 0.8),
						BackgroundTransparency = 1,
						Text = Computed(function()
							return math.ceil(healthFrac:get() * 100) .. "%"
						end),
						TextColor3 = Color3.fromRGB(255, 255, 255),
						Font = Enum.Font.GothamBold,
						TextScaled = true,
					},
				},
			},
		},
	}

	trove:Add(screenGui)

	local raceController = nil
	local connections = {}

	local function bind()
		raceController = Knit.GetController("LakelandRaceController")

		table.insert(connections, raceController.HealthChanged:Connect(function(health)
			local max = raceController:GetMaxHealth()
			healthFrac:set(health / max)
		end))

		table.insert(connections, raceController.HazardHit:Connect(function()
			hitFlash:set(1)
			task.delay(0.15, function()
				hitFlash:set(0)
			end)
		end))
	end

	task.spawn(bind)

	local function reset()
		healthFrac:set(1)
		hitFlash:set(0)
	end

	local function destroy()
		for _, conn in ipairs(connections) do
			conn:Disconnect()
		end
		connections = {}
		trove:Destroy()
	end

	return {
		reset = reset,
		destroy = destroy,
	}
end

return LakelandHealthBarUI
