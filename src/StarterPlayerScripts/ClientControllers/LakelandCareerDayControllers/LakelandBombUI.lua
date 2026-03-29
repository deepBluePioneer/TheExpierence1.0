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

local BG_PANEL = Color3.fromRGB(8, 14, 28)
local BORDER_GREEN = Color3.fromRGB(40, 200, 80)
local TEXT_PRIMARY = Color3.fromRGB(220, 235, 255)
local BOMB_GREEN = Color3.fromRGB(60, 255, 80)
local TIP_CYAN = Color3.fromRGB(0, 200, 255)

local LakelandBombUI = {}

function LakelandBombUI.new(playerGui, gameState, beatIntensity)
	local trove = Trove.new()

	local bombCount = Value(0)
	local punchScale = Value(1)
	local animatedPunch = Spring(punchScale, 25, 0.65)

	local tipText = Value("")
	local tipVisible = Value(false)
	local tipAlpha = Spring(Computed(function()
		return tipVisible:get() and 1 or 0
	end), 12, 0.8)

	local visible = Computed(function()
		return gameState:get() == "PLAYING"
	end)

	local bombVisible = Computed(function()
		return visible:get() and bombCount:get() > 0
	end)

	local slideY = Spring(Computed(function()
		return bombVisible:get() and 0.91 or 1.1
	end), 16, 0.75)

	local screenGui = New "ScreenGui" {
		Name = "LakelandBombUI",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = 52,
		Enabled = true,
		Parent = playerGui,

		[Children] = {
			New "Frame" {
				Name = "BombCounter",
				AnchorPoint = Vector2.new(0, 1),
				Position = Computed(function()
					return UDim2.fromScale(0.56, slideY:get())
				end),
				Size = Computed(function()
					local s = animatedPunch:get()
					return UDim2.fromScale(0.12 * s, 0.045 * s)
				end),
				BackgroundColor3 = BG_PANEL,
				BackgroundTransparency = 0.15,

				[Children] = {
					New "UICorner" {
						CornerRadius = UDim.new(0.2, 0),
					},

					New "UIStroke" {
						Color = BORDER_GREEN,
						Thickness = Computed(function()
							local b = beatIntensity and beatIntensity:get() or 0
							return 2 + b * 3
						end),
						Transparency = Computed(function()
							local b = beatIntensity and beatIntensity:get() or 0
							return 0.2 - b * 0.2
						end),
					},

					New "UIGradient" {
						Color = ColorSequence.new(
							Color3.fromRGB(255, 255, 255),
							Color3.fromRGB(180, 210, 190)
						),
						Rotation = 90,
					},

					New "TextLabel" {
						Name = "BombIcon",
						AnchorPoint = Vector2.new(0, 0.5),
						Position = UDim2.fromScale(0.06, 0.5),
						Size = UDim2.fromScale(0.25, 0.8),
						BackgroundTransparency = 1,
						Text = "BOMB",
						TextColor3 = BOMB_GREEN,
						Font = Enum.Font.GothamBlack,
						TextScaled = true,
						[Children] = { New "UITextSizeConstraint" { MaxTextSize = 14 } },
					},

					New "TextLabel" {
						Name = "CountLabel",
						AnchorPoint = Vector2.new(1, 0.5),
						Position = UDim2.fromScale(0.92, 0.5),
						Size = UDim2.fromScale(0.55, 0.85),
						BackgroundTransparency = 1,
						Text = Computed(function()
							local c = bombCount:get()
							if c <= 0 then return "" end
							return "x" .. tostring(c) .. "  [SPACE]"
						end),
						TextColor3 = TEXT_PRIMARY,
						Font = Enum.Font.GothamBold,
						TextScaled = true,
						TextXAlignment = Enum.TextXAlignment.Right,
						[Children] = { New "UITextSizeConstraint" { MaxTextSize = 16 } },
					},
				},
			},

			New "Frame" {
				Name = "TipContainer",
				AnchorPoint = Vector2.new(0.5, 0),
				Position = UDim2.fromScale(0.5, 0.14),
				Size = UDim2.fromScale(0.4, 0.045),
				BackgroundColor3 = BG_PANEL,
				BackgroundTransparency = Computed(function()
					return 1 - 0.85 * tipAlpha:get()
				end),

				[Children] = {
					New "UICorner" {
						CornerRadius = UDim.new(0.25, 0),
					},

					New "UIStroke" {
						Color = TIP_CYAN,
						Thickness = 2,
						Transparency = Computed(function()
							return 1 - 0.8 * tipAlpha:get()
						end),
					},

					New "TextLabel" {
						Name = "TipText",
						AnchorPoint = Vector2.new(0.5, 0.5),
						Position = UDim2.fromScale(0.5, 0.5),
						Size = UDim2.fromScale(0.9, 0.8),
						BackgroundTransparency = 1,
						Text = tipText,
						TextColor3 = TEXT_PRIMARY,
						Font = Enum.Font.GothamBold,
						TextScaled = true,
						TextTransparency = Computed(function()
							return 1 - tipAlpha:get()
						end),
						[Children] = { New "UITextSizeConstraint" { MaxTextSize = 18 } },
					},
				},
			},
		},
	}

	trove:Add(screenGui)

	local raceController = nil
	local connections = {}
	local shownTips = {}

	local tipThread = nil
	local function showTip(text, duration)
		if tipThread then
			task.cancel(tipThread)
			tipThread = nil
		end
		tipText:set(text)
		tipVisible:set(true)
		tipThread = task.delay(duration or 2.5, function()
			tipVisible:set(false)
			tipThread = nil
		end)
	end

	local function bind()
		raceController = Knit.GetController("LakelandRaceController")

		table.insert(connections, raceController.BombCollected:Connect(function(count)
			bombCount:set(count)
			punchScale:set(1.35)
			task.defer(function() punchScale:set(1) end)

			if not shownTips.bombPickup then
				shownTips.bombPickup = true
				showTip("BOMB ACQUIRED  -  Press SPACE to deploy!", 3)
			end
		end))

		table.insert(connections, raceController.BombDeployed:Connect(function()
			bombCount:set(raceController._bombCount or 0)
			punchScale:set(1.25)
			task.defer(function() punchScale:set(1) end)
		end))

		table.insert(connections, raceController.HazardHit:Connect(function(health)
			if not shownTips.hazardHit then
				shownTips.hazardHit = true
				showTip("DAMAGE!  Avoid RED cubes  -  Collect BLUE for points", 3)
			end
		end))

		table.insert(connections, raceController.BoostChanged:Connect(function(boosting)
			if boosting and not shownTips.boost then
				shownTips.boost = true
				showTip("BOOST PAD  -  Speed increase + bonus points!", 2.5)
			end
		end))
	end

	task.spawn(bind)

	local function reset()
		bombCount:set(0)
		punchScale:set(1)
		tipVisible:set(false)
		shownTips = {}
		if tipThread then
			task.cancel(tipThread)
			tipThread = nil
		end
	end

	local function destroy()
		for _, conn in ipairs(connections) do
			conn:Disconnect()
		end
		connections = {}
		if tipThread then
			task.cancel(tipThread)
			tipThread = nil
		end
		trove:Destroy()
	end

	return {
		reset = reset,
		destroy = destroy,
	}
end

return LakelandBombUI
