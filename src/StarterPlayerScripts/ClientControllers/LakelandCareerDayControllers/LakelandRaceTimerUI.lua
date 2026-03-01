local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Packages = ReplicatedStorage.Packages
local Trove = require(Packages.Trove)
local Timer = require(Packages.timer)

local CustomPackages = ReplicatedStorage.CustomPackages
local Fusion = require(CustomPackages.FusionRoot.Fusion)

local New = Fusion.New
local Value = Fusion.Value
local Computed = Fusion.Computed
local Children = Fusion.Children
local Spring = Fusion.Spring

local LakelandRaceTimerUI = {}

function LakelandRaceTimerUI.new(playerGui, gameState, raceDuration, onTimeUp)
	local trove = Trove.new()

	local timeRemaining = Value(raceDuration)

	local visible = Computed(function()
		return gameState:get() == "PLAYING"
	end)

	local timerText = Computed(function()
		local t = math.ceil(timeRemaining:get())
		local m = math.floor(t / 60)
		local s = t % 60
		return string.format("%d:%02d", m, s)
	end)

	local isLow = Computed(function()
		return timeRemaining:get() <= 10
	end)

	local timerColor = Computed(function()
		if isLow:get() then
			return Color3.fromRGB(255, 80, 60)
		end
		return Color3.fromRGB(255, 255, 255)
	end)

	local pulseScale = Value(1)
	local animatedPulse = Spring(pulseScale, 25, 0.7)

	local screenGui = New "ScreenGui" {
		Name = "LakelandRaceTimerUI",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = 50,
		Parent = playerGui,

		[Children] = {
			New "Frame" {
				Name = "TimerContainer",
				AnchorPoint = Vector2.new(0.5, 0),
				Position = UDim2.fromScale(0.5, 0.03),
				Size = Computed(function()
					local s = animatedPulse:get()
					return UDim2.fromScale(0.15 * s, 0.06 * s)
				end),
				BackgroundColor3 = Color3.fromRGB(20, 20, 30),
				BackgroundTransparency = 0.3,
				Visible = visible,

				[Children] = {
					New "UICorner" {
						CornerRadius = UDim.new(0.3, 0),
					},

					New "UIStroke" {
						Color = Computed(function()
							if isLow:get() then
								return Color3.fromRGB(255, 60, 40)
							end
							return Color3.fromRGB(100, 100, 120)
						end),
						Thickness = 2,
						Transparency = 0.4,
					},

					New "TextLabel" {
						Name = "TimerText",
						AnchorPoint = Vector2.new(0.5, 0.5),
						Position = UDim2.fromScale(0.5, 0.5),
						Size = UDim2.fromScale(0.9, 0.8),
						BackgroundTransparency = 1,
						Text = timerText,
						TextColor3 = timerColor,
						Font = Enum.Font.GothamBlack,
						TextScaled = true,
					},
				},
			},
		},
	}

	local tickTimer = nil
	local secondsElapsed = 0

	local function start()
		timeRemaining:set(raceDuration)
		secondsElapsed = 0

		if tickTimer then
			tickTimer:Destroy()
		end

		tickTimer = Timer.new(1)
		trove:Add(tickTimer)

		tickTimer.Tick:Connect(function()
			secondsElapsed = secondsElapsed + 1
			local remaining = raceDuration - secondsElapsed

			if remaining <= 0 then
				remaining = 0
				timeRemaining:set(0)
				tickTimer:Stop()

				if onTimeUp then
					onTimeUp()
				end
				return
			end

			timeRemaining:set(remaining)

			if remaining <= 10 then
				pulseScale:set(1.2)
				task.defer(function()
					pulseScale:set(1)
				end)
			end
		end)

		tickTimer:Start()
	end

	local function getTimeRemaining()
		return timeRemaining:get()
	end

	local function destroy()
		trove:Destroy()
		screenGui:Destroy()
	end

	return {
		start = start,
		destroy = destroy,
		getTimeRemaining = getTimeRemaining,
	}
end

return LakelandRaceTimerUI
