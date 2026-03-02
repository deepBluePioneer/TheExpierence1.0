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
local ForPairs = Fusion.ForPairs

local NUM_HEARTS = 4
local HEALTH_PER_HEART = 25

local LakelandHealthBarUI = {}

function LakelandHealthBarUI.new(playerGui, gameState)
	local trove = Trove.new()

	local currentHealth = Value(NUM_HEARTS * HEALTH_PER_HEART)
	local hitFlash = Value(0)
	local animatedFlash = Spring(hitFlash, 20, 0.8)

	local visible = Computed(function()
		return gameState:get() == "PLAYING"
	end)

	local slideY = Spring(Computed(function()
		return visible:get() and 0.09 or -0.05
	end), 18, 0.75)

	local heartStates = {}
	for i = 1, NUM_HEARTS do
		heartStates[i] = Value(1)
	end

	local heartScales = {}
	local animatedScales = {}
	for i = 1, NUM_HEARTS do
		heartScales[i] = Value(1)
		animatedScales[i] = Spring(heartScales[i], 22, 0.6)
	end

	local function updateHearts(health)
		for i = 1, NUM_HEARTS do
			local heartMin = (i - 1) * HEALTH_PER_HEART
			if health >= heartMin + HEALTH_PER_HEART then
				heartStates[i]:set(1)
			elseif health > heartMin then
				heartStates[i]:set((health - heartMin) / HEALTH_PER_HEART)
			else
				heartStates[i]:set(0)
			end
		end
	end

	local heartData = {}
	for i = 1, NUM_HEARTS do
		heartData[i] = i
	end

	local screenGui = New "ScreenGui" {
		Name = "LakelandHealthBarUI",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = 51,
		Enabled = visible,
		Parent = playerGui,

		[Children] = {
			New "Frame" {
				Name = "HeartsContainer",
				AnchorPoint = Vector2.new(0.5, 0),
				Position = Computed(function()
					return UDim2.fromScale(0.5, slideY:get())
				end),
				Size = UDim2.fromScale(0.16, 0.045),
				BackgroundTransparency = 1,
				Visible = visible,

				[Children] = {
					New "UIListLayout" {
						FillDirection = Enum.FillDirection.Horizontal,
						HorizontalAlignment = Enum.HorizontalAlignment.Center,
						VerticalAlignment = Enum.VerticalAlignment.Center,
						Padding = UDim.new(0.02, 0),
						SortOrder = Enum.SortOrder.LayoutOrder,
					},

					ForPairs(heartData, function(key, idx)
						local state = heartStates[idx]
						local scale = animatedScales[idx]

						local heartColor = Computed(function()
							local s = state:get()
							if s >= 1 then
								return Color3.fromRGB(255, 50, 60)
							elseif s > 0 then
								return Color3.fromRGB(255, 150, 50)
							else
								return Color3.fromRGB(60, 60, 80)
							end
						end)

						local heartTransparency = Computed(function()
							return state:get() <= 0 and 0.6 or 0
						end)

						return key, New "Frame" {
							Name = "Heart_" .. idx,
							Size = Computed(function()
								local s = scale:get()
								return UDim2.fromScale(0.22 * s, 1 * s)
							end),
							AnchorPoint = Vector2.new(0.5, 0.5),
							BackgroundTransparency = 1,
							LayoutOrder = idx,

							[Children] = {
								New "TextLabel" {
									Name = "HeartIcon",
									AnchorPoint = Vector2.new(0.5, 0.5),
									Position = UDim2.fromScale(0.5, 0.5),
									Size = UDim2.fromScale(1, 1),
									BackgroundTransparency = 1,
									Text = Computed(function()
										return state:get() > 0 and "\u{2764}" or "\u{1F5A4}"
									end),
									TextColor3 = heartColor,
									TextTransparency = heartTransparency,
									Font = Enum.Font.GothamBlack,
									TextScaled = true,
								},

								New "Frame" {
									Name = "FlashOverlay",
									AnchorPoint = Vector2.new(0.5, 0.5),
									Position = UDim2.fromScale(0.5, 0.5),
									Size = UDim2.fromScale(1, 1),
									BackgroundColor3 = Color3.fromRGB(255, 255, 255),
									BackgroundTransparency = Computed(function()
										return 1 - animatedFlash:get() * 0.5
									end),
									BorderSizePixel = 0,
									[Children] = {
										New "UICorner" {
											CornerRadius = UDim.new(0.5, 0),
										},
									},
								},
							},
						}
					end, Fusion.cleanup),
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
			currentHealth:set(health)
			updateHearts(health)
		end))

		table.insert(connections, raceController.HazardHit:Connect(function(health)
			local lostHeartIdx = math.ceil(health / HEALTH_PER_HEART) + 1
			if lostHeartIdx >= 1 and lostHeartIdx <= NUM_HEARTS then
				heartScales[lostHeartIdx]:set(1.5)
				task.defer(function()
					heartScales[lostHeartIdx]:set(1)
				end)
			end

			hitFlash:set(1)
			task.delay(0.15, function()
				hitFlash:set(0)
			end)
		end))
	end

	task.spawn(bind)

	local function reset()
		currentHealth:set(NUM_HEARTS * HEALTH_PER_HEART)
		updateHearts(NUM_HEARTS * HEALTH_PER_HEART)
		hitFlash:set(0)
		for i = 1, NUM_HEARTS do
			heartScales[i]:set(1)
		end
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
