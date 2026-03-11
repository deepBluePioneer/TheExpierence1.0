local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Packages = ReplicatedStorage.Packages
local Trove = require(Packages.Trove)

local DISPLAY_ORDER = 998

local LakelandDemoOverlayUI = {}

function LakelandDemoOverlayUI.new(playerGui)
	local trove = Trove.new()
	local destroyed = false
	local tweens = {}

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "LakelandDemoOverlay"
	screenGui.ResetOnSpawn = false
	screenGui.IgnoreGuiInset = true
	screenGui.DisplayOrder = DISPLAY_ORDER
	screenGui.Enabled = false
	screenGui.Parent = playerGui
	trove:Add(screenGui)

	-- "DEMO MODE" centered title
	local demoTitle = Instance.new("TextLabel")
	demoTitle.Name = "DemoTitle"
	demoTitle.AnchorPoint = Vector2.new(0.5, 0.5)
	demoTitle.Position = UDim2.new(0.5, 0, 0.5, 0)
	demoTitle.Size = UDim2.new(0.9, 0, 0, 120)
	demoTitle.BackgroundTransparency = 1
	demoTitle.Font = Enum.Font.GothamBlack
	demoTitle.Text = "DEMO MODE"
	demoTitle.TextColor3 = Color3.fromRGB(255, 255, 255)
	demoTitle.TextScaled = true
	demoTitle.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	demoTitle.TextStrokeTransparency = 0
	demoTitle.TextTransparency = 1
	demoTitle.Parent = screenGui

	local titleConstraint = Instance.new("UITextSizeConstraint")
	titleConstraint.MaxTextSize = 96
	titleConstraint.MinTextSize = 36
	titleConstraint.Parent = demoTitle

	local titleStroke = Instance.new("UIStroke")
	titleStroke.Color = Color3.fromRGB(80, 160, 255)
	titleStroke.Thickness = 3
	titleStroke.Transparency = 1
	titleStroke.Parent = demoTitle

	-- "PRESS ANY BUTTON TO PLAY" bottom prompt
	local pressLabel = Instance.new("TextLabel")
	pressLabel.Name = "PressText"
	pressLabel.AnchorPoint = Vector2.new(0.5, 1)
	pressLabel.Position = UDim2.new(0.5, 0, 0.92, 0)
	pressLabel.Size = UDim2.new(0.85, 0, 0, 70)
	pressLabel.BackgroundTransparency = 1
	pressLabel.Font = Enum.Font.GothamBold
	pressLabel.Text = "PRESS ANY BUTTON TO PLAY"
	pressLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	pressLabel.TextScaled = true
	pressLabel.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	pressLabel.TextStrokeTransparency = 0
	pressLabel.TextTransparency = 1
	pressLabel.Parent = screenGui

	local pressConstraint = Instance.new("UITextSizeConstraint")
	pressConstraint.MaxTextSize = 56
	pressConstraint.MinTextSize = 24
	pressConstraint.Parent = pressLabel

	local pressStroke = Instance.new("UIStroke")
	pressStroke.Color = Color3.fromRGB(80, 160, 255)
	pressStroke.Thickness = 2
	pressStroke.Transparency = 1
	pressStroke.Parent = pressLabel

	local function stopTweens()
		for _, tw in ipairs(tweens) do
			tw:Cancel()
		end
		table.clear(tweens)
	end

	local function show()
		if destroyed then return end
		stopTweens()
		screenGui.Enabled = true

		demoTitle.TextTransparency = 1
		titleStroke.Transparency = 1
		pressLabel.TextTransparency = 1
		pressStroke.Transparency = 1

		-- Fade in both labels
		local titleFade = TweenService:Create(demoTitle, TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			TextTransparency = 0.15,
		})
		local titleStrokeFade = TweenService:Create(titleStroke, TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Transparency = 0.3,
		})
		local pressFade = TweenService:Create(pressLabel, TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			TextTransparency = 0,
		})
		local pressStrokeFade = TweenService:Create(pressStroke, TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Transparency = 0.3,
		})

		titleFade:Play()
		titleStrokeFade:Play()
		pressFade:Play()
		pressStrokeFade:Play()

		pressFade.Completed:Once(function()
			if destroyed or not screenGui.Enabled then return end

			-- Pulse "DEMO MODE" opacity
			local titlePulse = TweenService:Create(demoTitle, TweenInfo.new(1.2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), {
				TextTransparency = 0.55,
			})
			titlePulse:Play()
			table.insert(tweens, titlePulse)

			-- Pulse "PRESS ANY BUTTON" opacity
			local pressPulse = TweenService:Create(pressLabel, TweenInfo.new(0.9, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), {
				TextTransparency = 0.4,
			})
			pressPulse:Play()
			table.insert(tweens, pressPulse)
		end)
	end

	local function hide()
		if destroyed then return end
		stopTweens()
		screenGui.Enabled = false
	end

	local function destroy()
		destroyed = true
		stopTweens()
		trove:Destroy()
	end

	return {
		show = show,
		hide = hide,
		destroy = destroy,
	}
end

return LakelandDemoOverlayUI
