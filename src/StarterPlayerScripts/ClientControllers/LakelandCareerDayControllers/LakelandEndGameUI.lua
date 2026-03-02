local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CustomPackages = ReplicatedStorage.CustomPackages
local Fusion = require(CustomPackages.FusionRoot.Fusion)

local Packages = ReplicatedStorage.Packages
local Trove = require(Packages.Trove)

local New = Fusion.New
local Value = Fusion.Value
local Computed = Fusion.Computed
local Children = Fusion.Children
local Spring = Fusion.Spring

local LakelandEndGameUI = {}

function LakelandEndGameUI.new(playerGui, gameState)
	local trove = Trove.new()

	local finalScore = Value(0)
	local finalDistance = Value(0)
	local playerName = Value("")
	local reason = Value("TIME UP")
	local statusText = Value("SAVING...")

	local visible = Computed(function()
		return gameState:get() == "GAME_OVER"
	end)

	local animatedScore = Spring(finalScore, 8, 0.9)
	local scoreDisplay = Computed(function()
		return string.format("%d", math.floor(animatedScore:get()))
	end)

	local distanceDisplay = Computed(function()
		local d = math.floor(finalDistance:get())
		if d >= 1000 then
			return string.format("%.1f km", d / 1000)
		end
		return d .. " m"
	end)

	local containerScale = Value(0.8)
	local animatedScale = Spring(containerScale, 20, 0.6)

	local screenGui = New "ScreenGui" {
		Name = "LakelandEndGameUI",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = 200,
		Parent = playerGui,

		[Children] = {
			New "Frame" {
			Name = "Overlay",
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = Color3.fromRGB(0, 0, 0),
			BackgroundTransparency = 1,
				Visible = visible,

				[Children] = {
					New "Frame" {
						Name = "Panel",
						AnchorPoint = Vector2.new(0.5, 0.5),
						Position = UDim2.fromScale(0.5, 0.5),
						Size = Computed(function()
							local s = animatedScale:get()
							return UDim2.fromScale(0.35 * s, 0.45 * s)
						end),
				BackgroundColor3 = Color3.fromRGB(20, 20, 35),
				BackgroundTransparency = 0.1,

						[Children] = {
							New "UICorner" {
								CornerRadius = UDim.new(0.04, 0),
							},

							New "UIStroke" {
								Color = Color3.fromRGB(100, 100, 130),
								Thickness = 2,
								Transparency = 0.3,
							},

							New "UIListLayout" {
								SortOrder = Enum.SortOrder.LayoutOrder,
								FillDirection = Enum.FillDirection.Vertical,
								HorizontalAlignment = Enum.HorizontalAlignment.Center,
								VerticalAlignment = Enum.VerticalAlignment.Center,
								Padding = UDim.new(0.02, 0),
							},

							New "UIPadding" {
								PaddingTop = UDim.new(0.05, 0),
								PaddingBottom = UDim.new(0.05, 0),
								PaddingLeft = UDim.new(0.05, 0),
								PaddingRight = UDim.new(0.05, 0),
							},

							New "TextLabel" {
								Name = "ReasonLabel",
								LayoutOrder = 1,
								Size = UDim2.fromScale(0.9, 0.12),
								BackgroundTransparency = 1,
								Text = reason,
								TextColor3 = Computed(function()
									if reason:get() == "DESTROYED" then
										return Color3.fromRGB(255, 80, 60)
									end
									return Color3.fromRGB(255, 200, 60)
								end),
								Font = Enum.Font.GothamBlack,
								TextScaled = true,
							},

							New "TextLabel" {
								Name = "NameLabel",
								LayoutOrder = 2,
								Size = UDim2.fromScale(0.8, 0.08),
								BackgroundTransparency = 1,
								Text = playerName,
								TextColor3 = Color3.fromRGB(180, 180, 200),
								Font = Enum.Font.GothamBold,
								TextScaled = true,
							},

							New "Frame" {
								Name = "Divider1",
								LayoutOrder = 3,
								Size = UDim2.fromScale(0.8, 0.005),
								BackgroundColor3 = Color3.fromRGB(80, 80, 100),
								BackgroundTransparency = 0.5,
								BorderSizePixel = 0,
							},

							New "TextLabel" {
								Name = "ScoreLabel",
								LayoutOrder = 4,
								Size = UDim2.fromScale(0.6, 0.07),
								BackgroundTransparency = 1,
								Text = "SCORE",
								TextColor3 = Color3.fromRGB(150, 150, 170),
								Font = Enum.Font.GothamBold,
								TextScaled = true,
							},

							New "TextLabel" {
								Name = "ScoreValue",
								LayoutOrder = 5,
								Size = UDim2.fromScale(0.9, 0.18),
								BackgroundTransparency = 1,
								Text = scoreDisplay,
								TextColor3 = Color3.fromRGB(255, 220, 80),
								Font = Enum.Font.GothamBlack,
								TextScaled = true,
							},

							New "TextLabel" {
								Name = "DistLabel",
								LayoutOrder = 6,
								Size = UDim2.fromScale(0.6, 0.06),
								BackgroundTransparency = 1,
								Text = Computed(function()
									return "DISTANCE: " .. distanceDisplay:get()
								end),
								TextColor3 = Color3.fromRGB(180, 180, 200),
								Font = Enum.Font.Gotham,
								TextScaled = true,
							},

							New "Frame" {
								Name = "Divider2",
								LayoutOrder = 7,
								Size = UDim2.fromScale(0.8, 0.005),
								BackgroundColor3 = Color3.fromRGB(80, 80, 100),
								BackgroundTransparency = 0.5,
								BorderSizePixel = 0,
							},

							New "TextLabel" {
								Name = "StatusLabel",
								LayoutOrder = 8,
								Size = UDim2.fromScale(0.8, 0.08),
								BackgroundTransparency = 1,
								Text = statusText,
								TextColor3 = Color3.fromRGB(120, 220, 120),
								Font = Enum.Font.GothamBold,
								TextScaled = true,
							},
						},
					},
				},
			},
		},
	}

	trove:Add(screenGui)

	local function show(data)
		finalScore:set(data.score or 0)
		finalDistance:set(data.distance or 0)
		playerName:set(data.name or "")
		reason:set(data.reason or "TIME UP")
		statusText:set("SAVING...")
		containerScale:set(0.8)
		task.defer(function()
			containerScale:set(1)
		end)
	end

	local function setStatus(text)
		statusText:set(text)
	end

	local function destroy()
		trove:Destroy()
	end

	return {
		show = show,
		setStatus = setStatus,
		destroy = destroy,
	}
end

return LakelandEndGameUI
