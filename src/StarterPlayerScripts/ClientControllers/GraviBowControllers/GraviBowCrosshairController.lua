local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Players = game:GetService("Players")

local Packages = ReplicatedStorage.Packages
local CustomPackages = ReplicatedStorage.CustomPackages
local Knit = require(Packages.Knit)
local Trove = require(Packages.Trove)
local Fusion = require(CustomPackages.FusionRoot.Fusion)

local New = Fusion.New
local Value = Fusion.Value
local Computed = Fusion.Computed
local Children = Fusion.Children
local Spring = Fusion.Spring

local LocalPlayer = Players.LocalPlayer

local CROSSHAIR_SIZE = 24
local GAP = 6
local LINE_LENGTH = 10
local LINE_THICKNESS = 2
local DOT_SIZE = 4
local COLOR_DEFAULT = Color3.fromRGB(255, 255, 255)
local COLOR_AIM = Color3.fromRGB(255, 80, 80)

local GraviBowCrosshairController = Knit.CreateController({
	Name = "GraviBowCrosshairController",
	_trove = nil,
})

function GraviBowCrosshairController:KnitInit()
	self._trove = Trove.new()
	self._isAiming = Value(false)
end

function GraviBowCrosshairController:KnitStart()
	UserInputService.MouseIconEnabled = false

	local viewmodelController = Knit.GetController("GraviBowViewmodelController")

	self._trove:Add(UserInputService.InputBegan:Connect(function(input, processed)
		if processed then return end
		if input.UserInputType == Enum.UserInputType.MouseButton2 then
			self._isAiming:set(true)
		end
	end), "Disconnect")

	self._trove:Add(UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton2 then
			self._isAiming:set(false)
		end
	end), "Disconnect")

	local crosshairColor = Spring(Computed(function()
		return self._isAiming:get() and COLOR_AIM or COLOR_DEFAULT
	end), 20)

	local gapSpring = Spring(Computed(function()
		return self._isAiming:get() and 3 or GAP
	end), 15)

	local lineAlpha = Spring(Computed(function()
		return self._isAiming:get() and 0 or 0.3
	end), 15)

	local function crosshairLine(rotation, name)
		return New "Frame" {
			Name = name,
			AnchorPoint = Vector2.new(0.5, 0),
			Position = Computed(function()
				return UDim2.new(0.5, 0, 0.5, gapSpring:get())
			end),
			Size = UDim2.fromOffset(LINE_THICKNESS, LINE_LENGTH),
			Rotation = rotation,
			BackgroundColor3 = crosshairColor,
			BackgroundTransparency = lineAlpha,
			BorderSizePixel = 0,

			[Children] = {
				New "UICorner" {
					CornerRadius = UDim.new(0, 1),
				},
				New "UIStroke" {
					Color = Color3.fromRGB(0, 0, 0),
					Thickness = 1,
					Transparency = Computed(function()
						return self._isAiming:get() and 0.3 or 0.5
					end),
				},
			},
		}
	end

	local gui = New "ScreenGui" {
		Name = "CrosshairGui",
		DisplayOrder = 200,
		IgnoreGuiInset = true,
		ResetOnSpawn = false,
		Parent = LocalPlayer.PlayerGui,

		[Children] = {
			New "Frame" {
				Name = "Crosshair",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromOffset(CROSSHAIR_SIZE * 2, CROSSHAIR_SIZE * 2),
				BackgroundTransparency = 1,

				[Children] = {
					New "Frame" {
						Name = "Dot",
						AnchorPoint = Vector2.new(0.5, 0.5),
						Position = UDim2.fromScale(0.5, 0.5),
						Size = UDim2.fromOffset(DOT_SIZE, DOT_SIZE),
						BackgroundColor3 = crosshairColor,
						BackgroundTransparency = lineAlpha,
						BorderSizePixel = 0,

						[Children] = {
							New "UICorner" {
								CornerRadius = UDim.new(1, 0),
							},
							New "UIStroke" {
								Color = Color3.fromRGB(0, 0, 0),
								Thickness = 1,
								Transparency = 0.5,
							},
						},
					},

					crosshairLine(0, "Top"),
					crosshairLine(90, "Right"),
					crosshairLine(180, "Bottom"),
					crosshairLine(270, "Left"),
				},
			},
		},
	}

	self._trove:Add(gui)
	self._trove:Add(function()
		UserInputService.MouseIconEnabled = true
	end)

	print("[GraviBowCrosshairController] Crosshair active")
end

return GraviBowCrosshairController
