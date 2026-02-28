local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")

local Packages = ReplicatedStorage.Packages
local Knit = require(Packages.Knit)
local Trove = require(Packages.Trove)
local Input = require(Packages.Input)

local MachineInputMap = require(ReplicatedStorage.Source.MachineInputMap)

local LocalPlayer = Players.LocalPlayer

local JOYSTICK_RADIUS = 60
local JOYSTICK_DEAD_ZONE = 0.15
local BUTTON_SIZE = UDim2.fromOffset(70, 70)
local BUTTON_PADDING = 12

local MobileMachineInputController = Knit.CreateController({
	Name = "MobileMachineInputController",

	_trove = nil,
	_gui = nil,
	_joystickFrame = nil,
	_joystickKnob = nil,
	_active = false,

	_joystickTouchId = nil,
	_joystickCenter = Vector2.zero,
	_joystickDelta = Vector2.zero,

	_buttonStates = {},
	_steer = 0,
	_throttle = 0,
})

function MobileMachineInputController:KnitStart()
	if Input.PreferredInput ~= "Touch" then return end

	self._trove = Trove.new()
	self._active = true
	self:_createUI()
end

function MobileMachineInputController:_createUI()
	local insets = GuiService:GetGuiInset()

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "MobileMachineInput"
	screenGui.ResetOnSpawn = false
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screenGui.Parent = LocalPlayer.PlayerGui
	self._gui = screenGui
	self._trove:Add(screenGui)

	self:_createJoystick(screenGui)
	self:_createActionButtons(screenGui)
end

function MobileMachineInputController:_createJoystick(parent)
	local mobileConfig = MachineInputMap.mobile
	local side = mobileConfig.joystickSide or "Left"
	local anchorX = side == "Left" and 0.15 or 0.85

	local outerFrame = Instance.new("Frame")
	outerFrame.Name = "JoystickOuter"
	outerFrame.Size = UDim2.fromOffset(JOYSTICK_RADIUS * 2, JOYSTICK_RADIUS * 2)
	outerFrame.Position = UDim2.new(anchorX, 0, 0.7, 0)
	outerFrame.AnchorPoint = Vector2.new(0.5, 0.5)
	outerFrame.BackgroundColor3 = Color3.fromRGB(40, 40, 60)
	outerFrame.BackgroundTransparency = 0.5
	outerFrame.Parent = parent
	self._joystickFrame = outerFrame

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = outerFrame

	local knob = Instance.new("Frame")
	knob.Name = "Knob"
	knob.Size = UDim2.fromOffset(40, 40)
	knob.Position = UDim2.fromScale(0.5, 0.5)
	knob.AnchorPoint = Vector2.new(0.5, 0.5)
	knob.BackgroundColor3 = Color3.fromRGB(200, 200, 220)
	knob.BackgroundTransparency = 0.2
	knob.Parent = outerFrame
	self._joystickKnob = knob

	local knobCorner = Instance.new("UICorner")
	knobCorner.CornerRadius = UDim.new(0.5, 0)
	knobCorner.Parent = knob

	self._trove:Add(outerFrame.InputBegan:Connect(function(inputObj)
		if inputObj.UserInputType ~= Enum.UserInputType.Touch then return end
		if self._joystickTouchId then return end

		self._joystickTouchId = inputObj
		local absPos = outerFrame.AbsolutePosition
		local absSize = outerFrame.AbsoluteSize
		self._joystickCenter = absPos + absSize / 2
	end), "Disconnect")

	self._trove:Add(UserInputService.TouchMoved:Connect(function(inputObj)
		if inputObj ~= self._joystickTouchId then return end

		local pos = Vector2.new(inputObj.Position.X, inputObj.Position.Y)
		local delta = pos - self._joystickCenter
		local dist = delta.Magnitude

		if dist > JOYSTICK_RADIUS then
			delta = delta.Unit * JOYSTICK_RADIUS
		end

		self._joystickDelta = delta / JOYSTICK_RADIUS

		local knobOffset = delta
		knob.Position = UDim2.new(0.5, knobOffset.X, 0.5, knobOffset.Y)
	end), "Disconnect")

	self._trove:Add(UserInputService.TouchEnded:Connect(function(inputObj)
		if inputObj ~= self._joystickTouchId then return end

		self._joystickTouchId = nil
		self._joystickDelta = Vector2.zero
		knob.Position = UDim2.fromScale(0.5, 0.5)
	end), "Disconnect")
end

function MobileMachineInputController:_createActionButtons(parent)
	local mobileConfig = MachineInputMap.mobile
	local buttons = mobileConfig.buttons
	local side = mobileConfig.actionButtonSide or "Right"
	local anchorX = side == "Right" and 1 or 0
	local dirMult = side == "Right" and -1 or 1

	for i, btnConfig in buttons do
		local btn = Instance.new("TextButton")
		btn.Name = "Action_" .. btnConfig.action
		btn.Size = BUTTON_SIZE
		btn.Position = UDim2.new(
			anchorX, dirMult * (BUTTON_PADDING + 10),
			1, -(BUTTON_PADDING + (i - 1) * (70 + BUTTON_PADDING) + 70 + 40)
		)
		btn.AnchorPoint = Vector2.new(anchorX, 0)
		btn.BackgroundColor3 = Color3.fromRGB(50, 50, 80)
		btn.BackgroundTransparency = 0.3
		btn.Text = btnConfig.label
		btn.TextColor3 = Color3.fromRGB(220, 220, 240)
		btn.TextSize = 16
		btn.Font = Enum.Font.GothamBold
		btn.Parent = parent

		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0.2, 0)
		corner.Parent = btn

		self._buttonStates[btnConfig.action] = false

		self._trove:Add(btn.InputBegan:Connect(function(inputObj)
			if inputObj.UserInputType == Enum.UserInputType.Touch then
				self._buttonStates[btnConfig.action] = true
				btn.BackgroundColor3 = Color3.fromRGB(100, 100, 160)
			end
		end), "Disconnect")

		self._trove:Add(btn.InputEnded:Connect(function(inputObj)
			if inputObj.UserInputType == Enum.UserInputType.Touch then
				self._buttonStates[btnConfig.action] = false
				btn.BackgroundColor3 = Color3.fromRGB(50, 50, 80)
			end
		end), "Disconnect")
	end
end

function MobileMachineInputController:GetInput()
	local mobileConfig = MachineInputMap.mobile
	local delta = self._joystickDelta

	local steer = 0
	if math.abs(delta.X) > JOYSTICK_DEAD_ZONE then
		steer = delta.X
	end

	local throttle = 0
	if mobileConfig.autoThrottle then
		throttle = 1
	else
		if delta.Y < -JOYSTICK_DEAD_ZONE then
			throttle = math.abs(delta.Y)
		end
	end

	return {
		throttle = throttle,
		steer = steer,
		boost = self._buttonStates.boost or false,
		drift = self._buttonStates.drift or false,
		brake = self._buttonStates.brake or false,
	}
end

function MobileMachineInputController:SetVisible(visible)
	if self._gui then
		self._gui.Enabled = visible
	end
end

function MobileMachineInputController:Destroy()
	if self._trove then
		self._trove:Destroy()
	end
end

return MobileMachineInputController
