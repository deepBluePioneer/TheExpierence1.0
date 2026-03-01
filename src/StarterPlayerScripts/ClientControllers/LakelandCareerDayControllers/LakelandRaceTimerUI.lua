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
	-- Clamp so timer never starts with zero or negative (avoids instant time-up)
	local safeDuration = math.max(1, tonumber(raceDuration) or 120)
	local timeRemaining = Value(safeDuration)

	local visible = Computed(function()
		return gameState:get() == "PLAYING"
	end)

	local slideY = Spring(Computed(function()
		return visible:get() and 0.03 or -0.08
	end), 18, 0.75)

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
				Position = Computed(function()
					local y = slideY:get()
					return UDim2.fromScale(0.5, y)
				end),
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

	local function stop()
		if tickTimer and tickTimer:IsRunning() then
			tickTimer:Stop()
		end
	end

	local function start()
		-- Only one run at a time; stop any existing timer (do not add to trove to avoid double-destroy)
		if tickTimer then
			tickTimer:Destroy()
			tickTimer = nil
		end

		timeRemaining:set(safeDuration)
		secondsElapsed = 0

		tickTimer = Timer.new(1)
		tickTimer.Tick:Connect(function()
			if not tickTimer or not tickTimer:IsRunning() then return end
			secondsElapsed = secondsElapsed + 1
			local remaining = safeDuration - secondsElapsed

			if remaining <= 0 then
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
		if tickTimer then
			tickTimer:Destroy()
			tickTimer = nil
		end
		trove:Destroy()
		screenGui:Destroy()
	end

	return {
		start = start,
		stop = stop,
		destroy = destroy,
		getTimeRemaining = getTimeRemaining,
	}
end

return LakelandRaceTimerUI
