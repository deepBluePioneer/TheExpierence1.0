local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Packages = ReplicatedStorage.Packages
local Trove = require(Packages.Trove)

local CustomPackages = ReplicatedStorage.CustomPackages
local Fusion = require(CustomPackages.FusionRoot.Fusion)

local New = Fusion.New
local Value = Fusion.Value
local Computed = Fusion.Computed
local Children = Fusion.Children
local Spring = Fusion.Spring

local COUNTDOWN_SECONDS = 5
local GO_DISPLAY_TIME = 0.8

local LakelandCountdownUI = {}

function LakelandCountdownUI.new(playerGui, gameState, onCountdownDone)
	local trove = Trove.new()

	local countText = Value("")
	local punchScale = Value(1)
	local textColor = Value(Color3.fromRGB(255, 255, 255))

	local animatedScale = Spring(punchScale, 30, 0.6)

	local visible = Computed(function()
		return gameState:get() == "COUNTDOWN"
	end)

	local screenGui = New "ScreenGui" {
		Name = "LakelandCountdownUI",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = 200,
		Parent = playerGui,

		[Children] = {
			New "Frame" {
				Name = "Overlay",
				Size = UDim2.fromScale(1, 1),
				BackgroundColor3 = Color3.fromRGB(0, 0, 0),
				BackgroundTransparency = 0.7,
				Visible = visible,

				[Children] = {
					New "TextLabel" {
						Name = "CountdownNumber",
						AnchorPoint = Vector2.new(0.5, 0.5),
						Position = UDim2.fromScale(0.5, 0.45),
						Size = Computed(function()
							local s = animatedScale:get()
							return UDim2.fromScale(0.3 * s, 0.25 * s)
						end),
						BackgroundTransparency = 1,
						Text = countText,
						TextColor3 = textColor,
						Font = Enum.Font.GothamBlack,
						TextScaled = true,
					},
				},
			},
		},
	}

	local function runCountdown()
		for i = COUNTDOWN_SECONDS, 1, -1 do
			countText:set(tostring(i))
			textColor:set(i <= 2 and Color3.fromRGB(255, 100, 80) or Color3.fromRGB(255, 255, 255))

			punchScale:set(1.5)
			task.defer(function()
				punchScale:set(1)
			end)

			task.wait(1)

			if gameState:get() ~= "COUNTDOWN" then
				return
			end
		end

		countText:set("GO!")
		textColor:set(Color3.fromRGB(80, 255, 120))
		punchScale:set(2)
		task.defer(function()
			punchScale:set(1)
		end)

		task.wait(GO_DISPLAY_TIME)

		if onCountdownDone then
			onCountdownDone()
		end
	end

	local countdownThread = nil

	local function start()
		if countdownThread then
			task.cancel(countdownThread)
		end
		countdownThread = task.spawn(runCountdown)
		trove:Add(function()
			if countdownThread then
				task.cancel(countdownThread)
				countdownThread = nil
			end
		end)
	end

	local function destroy()
		trove:Destroy()
		screenGui:Destroy()
	end

	return {
		start = start,
		destroy = destroy,
	}
end

return LakelandCountdownUI
