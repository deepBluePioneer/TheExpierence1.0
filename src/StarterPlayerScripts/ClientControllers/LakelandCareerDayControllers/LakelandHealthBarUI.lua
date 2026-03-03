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

local BG_PANEL = Color3.fromRGB(8, 14, 28)
local BORDER_CYAN = Color3.fromRGB(0, 140, 200)
local TEXT_DIM = Color3.fromRGB(70, 100, 140)
local SHIELD_FULL = Color3.fromRGB(0, 200, 255)
local SHIELD_HALF = Color3.fromRGB(255, 160, 40)
local SHIELD_EMPTY = Color3.fromRGB(25, 35, 55)

local LakelandHealthBarUI = {}

function LakelandHealthBarUI.new(playerGui, gameState)
	local trove = Trove.new()

	local currentHealth = Value(NUM_HEARTS * HEALTH_PER_HEART)
	local hitFlash = Value(0)
	local animatedFlash = Spring(hitFlash, 20, 0.8)

	local visible = Computed(function()
		return gameState:get() == "PLAYING"
	end)

	local slideX = Spring(Computed(function()
		return visible:get() and 0.985 or 1.25
	end), 16, 0.75)

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
				Name = "ShieldContainer",
				AnchorPoint = Vector2.new(1, 0),
				Position = Computed(function()
					return UDim2.fromScale(slideX:get(), 0.015)
				end),
				Size = UDim2.fromScale(0.22, 0.06),
				BackgroundColor3 = BG_PANEL,
				BackgroundTransparency = 0.15,
				Visible = visible,

				[Children] = {
					New "UICorner" {
						CornerRadius = UDim.new(0.15, 0),
					},

					New "UIStroke" {
						Color = Computed(function()
							local h = currentHealth:get()
							if h <= HEALTH_PER_HEART then return Color3.fromRGB(255, 50, 50) end
							return BORDER_CYAN
						end),
						Thickness = 2,
						Transparency = 0.2,
					},

					New "UIGradient" {
						Color = ColorSequence.new(
							Color3.fromRGB(255, 255, 255),
							Color3.fromRGB(180, 190, 210)
						),
						Rotation = 90,
					},

					New "TextLabel" {
						Name = "ShieldLabel",
						AnchorPoint = Vector2.new(0, 0.5),
						Position = UDim2.fromScale(0.04, 0.5),
						Size = UDim2.fromScale(0.22, 0.5),
						BackgroundTransparency = 1,
						Text = "SHIELDS",
						TextColor3 = TEXT_DIM,
						Font = Enum.Font.GothamBold,
						TextScaled = true,
						TextXAlignment = Enum.TextXAlignment.Left,
					},

					New "Frame" {
						Name = "SegmentRow",
						AnchorPoint = Vector2.new(1, 0.5),
						Position = UDim2.fromScale(0.96, 0.5),
						Size = UDim2.fromScale(0.68, 0.55),
						BackgroundTransparency = 1,

						[Children] = {
							New "UIListLayout" {
								FillDirection = Enum.FillDirection.Horizontal,
								HorizontalAlignment = Enum.HorizontalAlignment.Right,
								VerticalAlignment = Enum.VerticalAlignment.Center,
								Padding = UDim.new(0.02, 0),
								SortOrder = Enum.SortOrder.LayoutOrder,
							},

							ForPairs(heartData, function(key, idx)
								local state = heartStates[idx]
								local scale = animatedScales[idx]

								local segColor = Computed(function()
									local s = state:get()
									if s >= 1 then return SHIELD_FULL end
									if s > 0 then return SHIELD_HALF end
									return SHIELD_EMPTY
								end)

								local segTransparency = Computed(function()
									return state:get() <= 0 and 0.5 or 0
								end)

								return key, New "Frame" {
									Name = "Segment_" .. idx,
									Size = Computed(function()
										local s = scale:get()
										return UDim2.fromScale(0.23 * s, 1 * s)
									end),
									AnchorPoint = Vector2.new(0.5, 0.5),
									BackgroundColor3 = segColor,
									BackgroundTransparency = segTransparency,
									LayoutOrder = idx,

									[Children] = {
										New "UICorner" {
											CornerRadius = UDim.new(0.2, 0),
										},

										New "UIStroke" {
											Color = Computed(function()
												local s = state:get()
												if s >= 1 then return Color3.fromRGB(0, 220, 255) end
												if s > 0 then return Color3.fromRGB(200, 130, 30) end
												return Color3.fromRGB(30, 45, 65)
											end),
											Thickness = 1,
											Transparency = 0.4,
										},

										New "Frame" {
											Name = "FlashOverlay",
											Size = UDim2.fromScale(1, 1),
											BackgroundColor3 = Color3.fromRGB(255, 255, 255),
											BackgroundTransparency = Computed(function()
												return 1 - animatedFlash:get() * 0.6
											end),
											BorderSizePixel = 0,
											[Children] = {
												New "UICorner" {
													CornerRadius = UDim.new(0.2, 0),
												},
											},
										},
									},
								}
							end, Fusion.cleanup),
						},
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
