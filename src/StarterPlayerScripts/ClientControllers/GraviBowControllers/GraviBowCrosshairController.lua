local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local TweenService = game:GetService("TweenService")
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

local HINT_BG = Color3.fromRGB(18, 18, 22)
local HINT_KEY_BG = Color3.fromRGB(32, 32, 40)
local HINT_DESC_COLOR = Color3.fromRGB(170, 170, 185)
local HINT_ACTIVE_ACCENT = Color3.fromRGB(255, 70, 70)
local HINT_ACTIVE_BG = Color3.fromRGB(255, 70, 70)
local HOMING_ACCENT = Color3.fromRGB(60, 180, 255)

local CROSSHAIR_SIZE = 24
local GAP = 6
local LINE_LENGTH = 10
local LINE_THICKNESS = 2
local DOT_SIZE = 4
local COLOR_DEFAULT = Color3.fromRGB(255, 255, 255)
local COLOR_AIM = Color3.fromRGB(255, 80, 80)

local RING_SIZE = 68
local RING_THICKNESS = 4
local RING_GLOW_THICKNESS = 10

local HOMING_DURATION = 5

local GraviBowCrosshairController = Knit.CreateController({
	Name = "GraviBowCrosshairController",
	_trove = nil,
	_flashFrame = nil,
})

function GraviBowCrosshairController:KnitInit()
	self._trove = Trove.new()
	self._isAiming = Value(false)
	self._isDrawing = Value(false)
	self._isHomingMode = Value(false)
	self._homingTimerText = Value("")
	self._homingTimerFrac = Value(1)
	self._isTargeting = Value(false)
	self._gameActive = Value(false)
	self._hasActiveTool = false
end

function GraviBowCrosshairController:FlashSalvo()
	if not self._flashFrame then return end
	local frame = self._flashFrame
	frame.BackgroundTransparency = 0.6
	TweenService:Create(frame, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		BackgroundTransparency = 1,
	}):Play()
end

function GraviBowCrosshairController:KnitStart()
	local viewmodelController = Knit.GetController("GraviBowViewmodelController")
	self._matchController = Knit.GetController("GraviBowMatchController")
	self._toolController = Knit.GetController("GraviBowToolController")

	UserInputService.MouseIconEnabled = false
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)

	self._trove:Add(UserInputService.InputBegan:Connect(function(input, processed)
		if processed then return end
		if not self._gameActive:get(false) then return end
		if input.KeyCode == Enum.KeyCode.Q then
			self._isHomingMode:set(not self._isHomingMode:get())
		elseif input.UserInputType == Enum.UserInputType.MouseButton2 then
			self._isAiming:set(true)
		elseif input.UserInputType == Enum.UserInputType.MouseButton1 then
			self._isDrawing:set(true)
		end
	end), "Disconnect")

	self._trove:Add(UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton2 then
			self._isAiming:set(false)
			self._isDrawing:set(false)
			self._isTargeting:set(false)
		elseif input.UserInputType == Enum.UserInputType.MouseButton1 then
			self._isDrawing:set(false)
		end
	end), "Disconnect")

	self._trove:Add(RunService.RenderStepped:Connect(function()
		local hasActiveTool = self._toolController:GetActiveTool() ~= nil
		local bowActive = viewmodelController._bowActive == true
		if hasActiveTool ~= self._hasActiveTool then
			self._hasActiveTool = hasActiveTool
			UserInputService.MouseIconEnabled = not hasActiveTool
		end
		local active = bowActive
		if active ~= self._gameActive:get(false) then
			self._gameActive:set(active)
			if not active then
				self._isAiming:set(false)
				self._isDrawing:set(false)
				self._isTargeting:set(false)
				self._isHomingMode:set(false)
			end
		end

		local targeting = viewmodelController._isTargeting
		self._isTargeting:set(targeting)
		if targeting then
			local t = math.max(0, viewmodelController._homingTimer)
			self._homingTimerText:set(string.format("%.1f", t))
			self._homingTimerFrac:set(math.clamp(t / HOMING_DURATION, 0, 1))
		else
			self._homingTimerFrac:set(1)
		end
	end), "Disconnect")

	local isHoming = self._isHomingMode
	local isTargeting = self._isTargeting
	local gameActive = self._gameActive

	local showNormalCrosshair = Computed(function()
		return not isHoming:get()
	end)

	local gameGuiVisible = Computed(function()
		return gameActive:get()
	end)

	local showBracketReticle = Computed(function()
		return isHoming:get() and self._isAiming:get()
	end)

	local crosshairColor = Spring(Computed(function()
		return self._isAiming:get() and COLOR_AIM or COLOR_DEFAULT
	end), 20)

	local gapSpring = Spring(Computed(function()
		return self._isAiming:get() and 3 or GAP
	end), 15)

	local lineAlpha = Spring(Computed(function()
		if isHoming:get() then return 1 end
		return self._isAiming:get() and 0 or 0.3
	end), 15)

	local dotAlpha = Spring(Computed(function()
		if isHoming:get() then return 1 end
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

	local bracketAlpha = Spring(Computed(function()
		return showBracketReticle:get() and 0 or 1
	end), 18)

	local bracketColor = Spring(Computed(function()
		return isTargeting:get() and HOMING_ACCENT or Color3.fromRGB(200, 200, 220)
	end), 15)

	local timerAlpha = Spring(Computed(function()
		return isTargeting:get() and 0 or 0.6
	end), 15)

	local ringGradientRotation = Computed(function()
		local frac = self._homingTimerFrac:get()
		return (1 - frac) * 360
	end)

	local rmbText = Computed(function()
		return self._isAiming:get() and "Aiming" or "Aim"
	end)

	local lmbText = Computed(function()
		if isHoming:get() then
			if isTargeting:get() then
				return "Targeting..."
			elseif self._isAiming:get() then
				return "Paint Targets"
			end
			return "Paint"
		end
		if self._isDrawing:get() then
			return "Drawing..."
		elseif self._isAiming:get() then
			return "Draw & Fire"
		end
		return "Draw"
	end)

	local qText = Computed(function()
		return isHoming:get() and "Homing" or "Normal"
	end)

	local rmbBadgeBg = Spring(Computed(function()
		return self._isAiming:get() and HINT_ACTIVE_BG or HINT_KEY_BG
	end), 18)

	local lmbBadgeBg = Spring(Computed(function()
		return self._isDrawing:get() and HINT_ACTIVE_BG or HINT_KEY_BG
	end), 18)

	local qBadgeBg = Spring(Computed(function()
		return isHoming:get() and HOMING_ACCENT or HINT_KEY_BG
	end), 18)

	local rmbStroke = Spring(Computed(function()
		return self._isAiming:get() and HINT_ACTIVE_ACCENT or Color3.fromRGB(60, 60, 72)
	end), 18)

	local lmbStroke = Spring(Computed(function()
		return self._isDrawing:get() and HINT_ACTIVE_ACCENT or Color3.fromRGB(60, 60, 72)
	end), 18)

	local qStroke = Spring(Computed(function()
		return isHoming:get() and HOMING_ACCENT or Color3.fromRGB(60, 60, 72)
	end), 18)

	local rmbKeyText = Spring(Computed(function()
		return self._isAiming:get() and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(200, 200, 210)
	end), 18)

	local lmbKeyText = Spring(Computed(function()
		return self._isDrawing:get() and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(200, 200, 210)
	end), 18)

	local qKeyText = Spring(Computed(function()
		return isHoming:get() and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(200, 200, 210)
	end), 18)

	local rmbDescColor = Spring(Computed(function()
		return self._isAiming:get() and HINT_ACTIVE_ACCENT or HINT_DESC_COLOR
	end), 18)

	local lmbDescColor = Spring(Computed(function()
		return self._isDrawing:get() and HINT_ACTIVE_ACCENT or HINT_DESC_COLOR
	end), 18)

	local qDescColor = Spring(Computed(function()
		return isHoming:get() and HOMING_ACCENT or HINT_DESC_COLOR
	end), 18)

	local function controlHint(keyLabel, descText, keyBgColor, keyTextColor, strokeColor, descColor)
		return New "Frame" {
			Name = keyLabel .. "Hint",
			Size = UDim2.fromOffset(180, 56),
			BackgroundColor3 = HINT_BG,
			BackgroundTransparency = 0.25,
			BorderSizePixel = 0,

			[Children] = {
				New "UICorner" {
					CornerRadius = UDim.new(0, 12),
				},
				New "UIStroke" {
					Color = strokeColor,
					Thickness = 1,
					Transparency = 0.5,
				},
				New "UIPadding" {
					PaddingLeft = UDim.new(0, 10),
					PaddingRight = UDim.new(0, 14),
				},

				New "Frame" {
					Name = "KeyBadge",
					AnchorPoint = Vector2.new(0, 0.5),
					Position = UDim2.new(0, 0, 0.5, 0),
					Size = UDim2.fromOffset(50, 36),
					BackgroundColor3 = keyBgColor,
					BorderSizePixel = 0,

					[Children] = {
						New "UICorner" {
							CornerRadius = UDim.new(0, 8),
						},
						New "UIStroke" {
							Color = strokeColor,
							Thickness = 1,
							Transparency = 0.4,
						},
						New "TextLabel" {
							Name = "Key",
							Size = UDim2.fromScale(1, 1),
							BackgroundTransparency = 1,
							Text = keyLabel,
							TextColor3 = keyTextColor,
							TextSize = 16,
							Font = Enum.Font.GothamBold,
						},
					},
				},

				New "TextLabel" {
					Name = "Desc",
					AnchorPoint = Vector2.new(1, 0.5),
					Position = UDim2.new(1, 0, 0.5, 0),
					Size = UDim2.fromOffset(100, 36),
					BackgroundTransparency = 1,
					Text = descText,
					TextColor3 = descColor,
					TextSize = 16,
					Font = Enum.Font.GothamMedium,
					TextXAlignment = Enum.TextXAlignment.Right,
				},
			},
		}
	end

	local flashFrame = New "Frame" {
		Name = "SalvoFlash",
		Size = UDim2.fromScale(1, 1),
		Position = UDim2.fromScale(0, 0),
		BackgroundColor3 = Color3.fromRGB(200, 230, 255),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = 100,
	}
	self._flashFrame = flashFrame

	local gui = New "ScreenGui" {
		Name = "CrosshairGui",
		DisplayOrder = 200,
		IgnoreGuiInset = true,
		ResetOnSpawn = false,
		Parent = LocalPlayer.PlayerGui,

		[Children] = {
			flashFrame,

			New "Frame" {
				Name = "Crosshair",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromOffset(CROSSHAIR_SIZE * 2, CROSSHAIR_SIZE * 2),
				BackgroundTransparency = 1,
				Visible = gameGuiVisible,

				[Children] = {
					New "Frame" {
						Name = "Dot",
						AnchorPoint = Vector2.new(0.5, 0.5),
						Position = UDim2.fromScale(0.5, 0.5),
						Size = UDim2.fromOffset(DOT_SIZE, DOT_SIZE),
						BackgroundColor3 = crosshairColor,
						BackgroundTransparency = dotAlpha,
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

			New "Frame" {
				Name = "BracketReticle",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromOffset(80, 80),
				BackgroundTransparency = 1,
				Visible = gameGuiVisible,

				[Children] = {
					New "TextLabel" {
						Name = "LeftBracket",
						AnchorPoint = Vector2.new(1, 0.5),
						Position = UDim2.new(0, -4, 0.5, 0),
						Size = UDim2.fromOffset(28, 48),
						BackgroundTransparency = 1,
						Text = "[",
						TextColor3 = bracketColor,
						TextTransparency = bracketAlpha,
						TextSize = 42,
						Font = Enum.Font.Code,
						TextStrokeTransparency = Computed(function()
							return showBracketReticle:get() and 0.3 or 1
						end),
						TextStrokeColor3 = Color3.fromRGB(0, 0, 0),
					},

					New "TextLabel" {
						Name = "RightBracket",
						AnchorPoint = Vector2.new(0, 0.5),
						Position = UDim2.new(1, 4, 0.5, 0),
						Size = UDim2.fromOffset(28, 48),
						BackgroundTransparency = 1,
						Text = "]",
						TextColor3 = bracketColor,
						TextTransparency = bracketAlpha,
						TextSize = 42,
						Font = Enum.Font.Code,
						TextStrokeTransparency = Computed(function()
							return showBracketReticle:get() and 0.3 or 1
						end),
						TextStrokeColor3 = Color3.fromRGB(0, 0, 0),
					},

					New "Frame" {
						Name = "CountdownRing",
						AnchorPoint = Vector2.new(0.5, 0.5),
						Position = UDim2.fromScale(0.5, 0.5),
						Size = UDim2.fromOffset(RING_SIZE, RING_SIZE),
						BackgroundTransparency = 1,

						[Children] = {
							New "Frame" {
								Name = "TrackRing",
								AnchorPoint = Vector2.new(0.5, 0.5),
								Position = UDim2.fromScale(0.5, 0.5),
								Size = UDim2.fromScale(1, 1),
								BackgroundTransparency = 1,
								BorderSizePixel = 0,

								[Children] = {
									New "UICorner" {
										CornerRadius = UDim.new(1, 0),
									},
									New "UIStroke" {
										Name = "TrackStroke",
										Color = Color3.fromRGB(40, 50, 60),
										Thickness = RING_THICKNESS,
										Transparency = Computed(function()
											return isTargeting:get() and 0.4 or 1
										end),
									},
								},
							},

							New "Frame" {
								Name = "GlowRing",
								AnchorPoint = Vector2.new(0.5, 0.5),
								Position = UDim2.fromScale(0.5, 0.5),
								Size = UDim2.fromScale(1, 1),
								BackgroundTransparency = 1,
								BorderSizePixel = 0,

								[Children] = {
									New "UICorner" {
										CornerRadius = UDim.new(1, 0),
									},
									New "UIStroke" {
										Name = "GlowStroke",
										Color = HOMING_ACCENT,
										Thickness = RING_GLOW_THICKNESS,
										Transparency = Computed(function()
											return isTargeting:get() and 0.75 or 1
										end),

										[Children] = {
											New "UIGradient" {
												Transparency = NumberSequence.new({
													NumberSequenceKeypoint.new(0, 0),
													NumberSequenceKeypoint.new(0.49, 0),
													NumberSequenceKeypoint.new(0.5, 1),
													NumberSequenceKeypoint.new(1, 1),
												}),
												Rotation = ringGradientRotation,
											},
										},
									},
								},
							},

							New "Frame" {
								Name = "FillRing",
								AnchorPoint = Vector2.new(0.5, 0.5),
								Position = UDim2.fromScale(0.5, 0.5),
								Size = UDim2.fromScale(1, 1),
								BackgroundTransparency = 1,
								BorderSizePixel = 0,

								[Children] = {
									New "UICorner" {
										CornerRadius = UDim.new(1, 0),
									},
									New "UIStroke" {
										Name = "FillStroke",
										Color = HOMING_ACCENT,
										Thickness = RING_THICKNESS,
										Transparency = Computed(function()
											return isTargeting:get() and 0 or 1
										end),

										[Children] = {
											New "UIGradient" {
												Transparency = NumberSequence.new({
													NumberSequenceKeypoint.new(0, 0),
													NumberSequenceKeypoint.new(0.49, 0),
													NumberSequenceKeypoint.new(0.5, 1),
													NumberSequenceKeypoint.new(1, 1),
												}),
												Rotation = ringGradientRotation,
											},
										},
									},
								},
							},
						},
					},

					New "TextLabel" {
						Name = "Timer",
						AnchorPoint = Vector2.new(0.5, 0),
						Position = UDim2.new(0.5, 0, 1, 8),
						Size = UDim2.fromOffset(60, 24),
						BackgroundTransparency = 1,
						Text = self._homingTimerText,
						TextColor3 = bracketColor,
						TextTransparency = timerAlpha,
						TextSize = 18,
						Font = Enum.Font.GothamBold,
						TextStrokeTransparency = Computed(function()
							return isTargeting:get() and 0.3 or 1
						end),
						TextStrokeColor3 = Color3.fromRGB(0, 0, 0),
					},

					New "Frame" {
						Name = "CenterDot",
						AnchorPoint = Vector2.new(0.5, 0.5),
						Position = UDim2.fromScale(0.5, 0.5),
						Size = UDim2.fromOffset(4, 4),
						BackgroundColor3 = bracketColor,
						BackgroundTransparency = bracketAlpha,
						BorderSizePixel = 0,

						[Children] = {
							New "UICorner" {
								CornerRadius = UDim.new(1, 0),
							},
						},
					},
				},
			},

			New "Frame" {
				Name = "ControlHints",
				AnchorPoint = Vector2.new(0.5, 1),
				Position = UDim2.new(0.5, 0, 1, -36),
				Size = UDim2.fromOffset(580, 56),
				BackgroundTransparency = 1,
				Visible = gameGuiVisible,

				[Children] = {
					New "UIListLayout" {
						FillDirection = Enum.FillDirection.Horizontal,
						HorizontalAlignment = Enum.HorizontalAlignment.Center,
						VerticalAlignment = Enum.VerticalAlignment.Center,
						Padding = UDim.new(0, 16),
						SortOrder = Enum.SortOrder.LayoutOrder,
					},

					controlHint("RMB", rmbText, rmbBadgeBg, rmbKeyText, rmbStroke, rmbDescColor),
					controlHint("LMB", lmbText, lmbBadgeBg, lmbKeyText, lmbStroke, lmbDescColor),
					controlHint("Q", qText, qBadgeBg, qKeyText, qStroke, qDescColor),
				},
			},
		},
	}

	self._trove:Add(gui)
	self._trove:Add(function()
		UserInputService.MouseIconEnabled = true
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, true)
	end)

end

return GraviBowCrosshairController
