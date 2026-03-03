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

local BAR_HEIGHT = 0.1
local BAR_SLIDE_IN_SPEED = 22
local BAR_SLIDE_IN_DAMP = 0.8

local BG_DARK = Color3.fromRGB(4, 6, 14)
local ACCENT_CYAN = Color3.fromRGB(0, 200, 255)
local LAUNCH_GREEN = Color3.fromRGB(0, 255, 140)

local LakelandCountdownUI = {}

function LakelandCountdownUI.new(playerGui, gameState, onCountdownDone)
	local trove = Trove.new()

	local countText = Value("")
	local subText = Value("")
	local punchScale = Value(1)
	local textColor = Value(ACCENT_CYAN)

	local barVisible = Value(0)

	local animatedScale = Spring(punchScale, 30, 0.6)
	local topBarPos = Spring(Computed(function()
		return barVisible:get() == 1 and 0 or -BAR_HEIGHT
	end), BAR_SLIDE_IN_SPEED, BAR_SLIDE_IN_DAMP)
	local bottomBarPos = Spring(Computed(function()
		return barVisible:get() == 1 and (1 - BAR_HEIGHT) or 1
	end), BAR_SLIDE_IN_SPEED, BAR_SLIDE_IN_DAMP)

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
				Name = "TopBar",
				AnchorPoint = Vector2.new(0, 0),
				Position = Computed(function()
					return UDim2.fromScale(0, topBarPos:get())
				end),
				Size = UDim2.fromScale(1, BAR_HEIGHT),
				BackgroundColor3 = BG_DARK,
				BackgroundTransparency = 0,
				BorderSizePixel = 0,
				ZIndex = 10,
				Visible = visible,

				[Children] = {
					New "Frame" {
						Name = "CyanEdge",
						AnchorPoint = Vector2.new(0, 1),
						Position = UDim2.fromScale(0, 1),
						Size = UDim2.new(1, 0, 0, 2),
						BackgroundColor3 = ACCENT_CYAN,
						BackgroundTransparency = 0.3,
						BorderSizePixel = 0,
					},
				},
			},

			New "Frame" {
				Name = "BottomBar",
				AnchorPoint = Vector2.new(0, 0),
				Position = Computed(function()
					return UDim2.fromScale(0, bottomBarPos:get())
				end),
				Size = UDim2.fromScale(1, BAR_HEIGHT),
				BackgroundColor3 = BG_DARK,
				BackgroundTransparency = 0,
				BorderSizePixel = 0,
				ZIndex = 10,
				Visible = visible,

				[Children] = {
					New "Frame" {
						Name = "CyanEdge",
						AnchorPoint = Vector2.new(0, 0),
						Position = UDim2.fromScale(0, 0),
						Size = UDim2.new(1, 0, 0, 2),
						BackgroundColor3 = ACCENT_CYAN,
						BackgroundTransparency = 0.3,
						BorderSizePixel = 0,
					},
				},
			},

			New "TextLabel" {
				Name = "SubLabel",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.33),
				Size = UDim2.fromScale(0.4, 0.06),
				BackgroundTransparency = 1,
				Text = subText,
				TextColor3 = Color3.fromRGB(70, 130, 180),
				Font = Enum.Font.GothamBold,
				TextScaled = true,
				ZIndex = 11,
				Visible = visible,
			},

			New "TextLabel" {
				Name = "CountdownNumber",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.45),
				Size = Computed(function()
					local s = animatedScale:get()
					return UDim2.fromScale(0.35 * s, 0.3 * s)
				end),
				BackgroundTransparency = 1,
				Text = countText,
				TextColor3 = textColor,
				Font = Enum.Font.GothamBlack,
				TextScaled = true,
				ZIndex = 11,
				Visible = visible,
			},
		},
	}

	local function runCountdown()
		barVisible:set(1)
		subText:set("LAUNCH SEQUENCE")

		task.wait(0.35)

		for i = COUNTDOWN_SECONDS, 1, -1 do
			countText:set(tostring(i))
			if i <= 2 then
				textColor:set(Color3.fromRGB(255, 80, 50))
				subText:set("STANDBY")
			else
				textColor:set(ACCENT_CYAN)
				subText:set("LAUNCH SEQUENCE")
			end

			punchScale:set(1.5)
			task.defer(function()
				punchScale:set(1)
			end)

			task.wait(1)

			if gameState:get() ~= "COUNTDOWN" then
				barVisible:set(0)
				return
			end
		end

		countText:set("LAUNCH!")
		subText:set("")
		textColor:set(LAUNCH_GREEN)
		punchScale:set(2)
		task.defer(function()
			punchScale:set(1)
		end)

		task.wait(0.3)

		barVisible:set(0)

		task.wait(GO_DISPLAY_TIME - 0.3)

		countText:set("")
		subText:set("")

		if gameState:get() == "COUNTDOWN" and onCountdownDone then
			onCountdownDone()
		end
	end

	local countdownThread = nil

	local function start()
		if countdownThread then
			task.cancel(countdownThread)
		end
		countText:set("")
		subText:set("")
		barVisible:set(0)
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
