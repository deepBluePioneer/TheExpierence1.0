local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Packages = ReplicatedStorage.Packages
local Trove = require(Packages.Trove)

local CustomPackages = ReplicatedStorage.CustomPackages
local Fusion = require(CustomPackages.FusionRoot.Fusion)

local New = Fusion.New
local Value = Fusion.Value
local Computed = Fusion.Computed
local Children = Fusion.Children

local BG_PANEL = Color3.fromRGB(8, 14, 28)
local BORDER_CYAN = Color3.fromRGB(0, 180, 255)
local TEXT_PRIMARY = Color3.fromRGB(220, 235, 255)
local TEXT_DIM = Color3.fromRGB(140, 160, 190)
local ACCENT_MAGENTA = Color3.fromRGB(255, 50, 180)

local SLIDE_IN_TIME = 0.4
local HOLD_TIME = 4
local SLIDE_OUT_TIME = 0.5

local LakelandBGMToastUI = {}

function LakelandBGMToastUI.new(playerGui)
	local trove = Trove.new()

	local screenGui = New "ScreenGui" {
		Name = "BGMToast",
		ResetOnSpawn = false,
		DisplayOrder = 250,
		IgnoreGuiInset = true,
		Parent = playerGui,
	}
	trove:Add(screenGui)

	local container = New "Frame" {
		Name = "ToastContainer",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 20, 0, 40),
		Size = UDim2.fromOffset(320, 60),
		BackgroundColor3 = BG_PANEL,
		BackgroundTransparency = 0.15,
		BorderSizePixel = 0,
		ClipsDescendants = true,
		Parent = screenGui,
		[Children] = {
			New "UICorner" {
				CornerRadius = UDim.new(0, 8),
			},
			New "UIStroke" {
				Color = BORDER_CYAN,
				Thickness = 1.5,
				Transparency = 0.3,
			},
			New "UIGradient" {
				Color = ColorSequence.new(
					Color3.fromRGB(12, 18, 35),
					Color3.fromRGB(8, 14, 28)
				),
				Rotation = 90,
			},
			New "Frame" {
				Name = "AccentBar",
				AnchorPoint = Vector2.new(0, 0.5),
				Position = UDim2.new(0, 0, 0.5, 0),
				Size = UDim2.new(0, 3, 1, -8),
				BackgroundColor3 = ACCENT_MAGENTA,
				BorderSizePixel = 0,
				[Children] = {
					New "UICorner" {
						CornerRadius = UDim.new(0, 2),
					},
				},
			},
			New "TextLabel" {
				Name = "NowPlaying",
				AnchorPoint = Vector2.new(0, 0),
				Position = UDim2.new(0, 16, 0, 8),
				Size = UDim2.new(1, -24, 0, 16),
				BackgroundTransparency = 1,
				Font = Enum.Font.GothamBold,
				Text = "NOW PLAYING",
				TextColor3 = TEXT_DIM,
				TextSize = 11,
				TextXAlignment = Enum.TextXAlignment.Left,
			},
			New "TextLabel" {
				Name = "TrackName",
				AnchorPoint = Vector2.new(0, 0),
				Position = UDim2.new(0, 16, 0, 26),
				Size = UDim2.new(1, -24, 0, 24),
				BackgroundTransparency = 1,
				Font = Enum.Font.GothamBold,
				Text = "",
				TextColor3 = TEXT_PRIMARY,
				TextSize = 16,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextTruncate = Enum.TextTruncate.AtEnd,
			},
		},
	}

	container.Position = UDim2.new(1, 340, 0, 40)

	local activeTween = nil

	local function show(trackName)
		local nameLabel = container:FindFirstChild("TrackName")
		if nameLabel then
			nameLabel.Text = trackName
		end

		if activeTween then
			activeTween:Cancel()
			activeTween = nil
		end

		local slideIn = TweenService:Create(container, TweenInfo.new(SLIDE_IN_TIME, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			Position = UDim2.new(1, -20, 0, 40),
		})
		slideIn:Play()

		activeTween = slideIn
		slideIn.Completed:Once(function()
			task.delay(HOLD_TIME, function()
				local slideOut = TweenService:Create(container, TweenInfo.new(SLIDE_OUT_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
					Position = UDim2.new(1, 340, 0, 40),
				})
				slideOut:Play()
				activeTween = slideOut
			end)
		end)
	end

	return {
		show = show,
		destroy = function()
			trove:Clean()
		end,
	}
end

return LakelandBGMToastUI
