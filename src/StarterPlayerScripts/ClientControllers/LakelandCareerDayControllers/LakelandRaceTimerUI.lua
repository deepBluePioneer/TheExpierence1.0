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

local BG_PANEL = Color3.fromRGB(8, 14, 28)
local BORDER_CYAN = Color3.fromRGB(0, 140, 200)
local TEXT_PRIMARY = Color3.fromRGB(220, 235, 255)
local TEXT_DIM = Color3.fromRGB(70, 100, 140)
local DANGER_RED = Color3.fromRGB(255, 50, 50)

local LakelandRaceTimerUI = {}

function LakelandRaceTimerUI.new(playerGui, gameState, raceDuration, beatIntensity, onTimeUp)
	local trove = Trove.new()
	local safeDuration = math.max(1, tonumber(raceDuration) or 120)
	local timeRemaining = Value(safeDuration)

	local visible = Computed(function()
		return gameState:get() == "PLAYING"
	end)

	local slideY = Spring(Computed(function()
		return visible:get() and 0.005 or -0.1
	end), 16, 0.75)

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
		if isLow:get() then return DANGER_RED end
		return TEXT_PRIMARY
	end)

	local borderColor = Computed(function()
		if isLow:get() then return DANGER_RED end
		return BORDER_CYAN
	end)

	local pulseScale = Value(1)
	local animatedPulse = Spring(pulseScale, 25, 0.7)

	local screenGui = New "ScreenGui" {
		Name = "LakelandRaceTimerUI",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = 56,
		Enabled = true,
		Parent = playerGui,

		[Children] = {
			New "Frame" {
				Name = "TimerContainer",
				AnchorPoint = Vector2.new(1, 0),
				Position = Computed(function()
					return UDim2.fromScale(0.98, slideY:get())
				end),
				Size = Computed(function()
					local s = animatedPulse:get()
					return UDim2.fromScale(0.12 * s, 0.06 * s)
				end),
				BackgroundColor3 = BG_PANEL,
				BackgroundTransparency = 0.15,
				Visible = visible,

				[Children] = {
					New "UICorner" {
						CornerRadius = UDim.new(0.12, 0),
					},

					New "UIStroke" {
						Color = borderColor,
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
							Color3.fromRGB(180, 190, 210)
						),
						Rotation = 90,
					},

					New "TextLabel" {
						Name = "TimerLabel",
						AnchorPoint = Vector2.new(0.5, 0),
						Position = UDim2.fromScale(0.5, 0.06),
						Size = UDim2.fromScale(0.9, 0.25),
						BackgroundTransparency = 1,
						Text = "TIME",
						TextColor3 = TEXT_DIM,
						Font = Enum.Font.GothamBold,
						TextScaled = true,
					},

					New "TextLabel" {
						Name = "TimerText",
						AnchorPoint = Vector2.new(0.5, 0.5),
						Position = UDim2.fromScale(0.5, 0.6),
						Size = UDim2.fromScale(0.85, 0.55),
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
				pulseScale:set(1.15)
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
