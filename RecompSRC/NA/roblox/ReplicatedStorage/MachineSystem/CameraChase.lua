--!strict
--[[
	Client chase camera (cmlib subject bind approximation).
	Use from StarterPlayerScripts / MachineCameraClient.
]]

local CameraChase = {}

export type Mode = "OnFoot" | "Riding"

export type Config = {
	Distance: number,
	Height: number,
	LookAhead: number,
	Smooth: number,
	YawSensitivity: number,
	PitchSensitivity: number,
	MinPitch: number,
	MaxPitch: number,
}

local DEFAULT: Config = {
	Distance = 18,
	Height = 7,
	LookAhead = 4,
	Smooth = 12,
	YawSensitivity = 0.045,
	PitchSensitivity = 0.035,
	MinPitch = -0.35,
	MaxPitch = 0.55,
}

export type ChaseState = {
	Mode: Mode,
	Subject: BasePart?,
	Yaw: number,
	Pitch: number,
	Config: Config,
	CurrentEye: Vector3?,
	CurrentInterest: Vector3?,
}

function CameraChase.NewState(config: Config?): ChaseState
	return {
		Mode = "OnFoot",
		Subject = nil,
		Yaw = 0,
		Pitch = 0.15,
		Config = config or table.clone(DEFAULT),
		CurrentEye = nil,
		CurrentInterest = nil,
	}
end

function CameraChase.SetMode(state: ChaseState, mode: Mode, subject: BasePart?)
	state.Mode = mode
	state.Subject = subject
	if mode == "OnFoot" then
		state.Config.Distance = 12
		state.Config.Height = 4
	else
		state.Config.Distance = DEFAULT.Distance
		state.Config.Height = DEFAULT.Height
	end
end

function CameraChase.AddOrbit(state: ChaseState, dYaw: number, dPitch: number)
	local cfg = state.Config
	state.Yaw += dYaw * cfg.YawSensitivity
	state.Pitch = math.clamp(state.Pitch + dPitch * cfg.PitchSensitivity, cfg.MinPitch, cfg.MaxPitch)
end

function CameraChase.Step(state: ChaseState, camera: Camera, dt: number)
	local subject = state.Subject
	if not subject then
		return
	end

	local cfg = state.Config
	local subjectCf = subject.CFrame
	local look = subjectCf.LookVector
	local up = subjectCf.UpVector

	-- Orbit around subject facing
	local orbit = CFrame.Angles(0, state.Yaw, 0) * CFrame.Angles(state.Pitch, 0, 0)
	local back = orbit:VectorToWorldSpace(-look)
	if back.Magnitude < 1e-3 then
		back = -look
	end
	back = back.Unit

	local interest = subject.Position + look * cfg.LookAhead + up * 1.5
	local eye = subject.Position + back * cfg.Distance + up * cfg.Height

	local alpha = 1 - math.exp(-cfg.Smooth * dt)
	if state.CurrentEye then
		state.CurrentEye = state.CurrentEye:Lerp(eye, alpha)
		state.CurrentInterest = (state.CurrentInterest :: Vector3):Lerp(interest, alpha)
	else
		state.CurrentEye = eye
		state.CurrentInterest = interest
	end

	camera.CameraType = Enum.CameraType.Scriptable
	camera.CFrame = CFrame.lookAt(state.CurrentEye, state.CurrentInterest, up)
end

return CameraChase
