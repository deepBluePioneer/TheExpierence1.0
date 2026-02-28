local MachineInputMap = {
	keyboard = {
		throttle = Enum.KeyCode.W,
		brake = Enum.KeyCode.S,
		steerLeft = Enum.KeyCode.A,
		steerRight = Enum.KeyCode.D,
		boost = Enum.KeyCode.LeftShift,
		drift = Enum.KeyCode.Space,
		pitchUp = Enum.KeyCode.W,
		pitchDown = Enum.KeyCode.S,
	},

	gamepad = {
		throttle = Enum.KeyCode.ButtonR2,
		brake = Enum.KeyCode.ButtonL2,
		steerAxis = Enum.KeyCode.Thumbstick1,
		pitchAxis = Enum.KeyCode.Thumbstick2,
		boost = Enum.KeyCode.ButtonA,
		drift = Enum.KeyCode.ButtonX,
	},

	mobile = {
		autoThrottle = true,
		joystickSide = "Left",
		actionButtonSide = "Right",
		buttons = {
			{ action = "boost", label = "Boost", order = 1 },
			{ action = "drift", label = "Drift", order = 2 },
			{ action = "brake", label = "Brake", order = 3 },
		},
	},
}

return MachineInputMap
