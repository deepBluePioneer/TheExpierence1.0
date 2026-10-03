--!strict
--[[
	Run ↔ Charge ↔ Boost ↔ Fly ↔ Land transitions (KAR _4 style).
]]

local MachineStates = require(script.Parent.MachineStates)

export type MachineLike = {
	State: string,
	Grounded: boolean,
	Charging: boolean,
	WasCharging: boolean,
	BoostTimer: number,
	LandTimer: number,
	Velocity: Vector3,
	StickX: number,
	StickY: number,
	Stats: { StickDeadzone: number, BoostDuration: number, LandDuration: number },
	Hitstun: number,
}

local StateMachine = {}

local function stickMag(m: MachineLike): number
	local dz = m.Stats.StickDeadzone
	local x = if math.abs(m.StickX) <= dz then 0 else m.StickX
	local y = if math.abs(m.StickY) <= dz then 0 else m.StickY
	return math.sqrt(x * x + y * y)
end

function StateMachine.Change(m: MachineLike, newState: string)
	if m.State == newState then
		return
	end
	m.State = newState
	if newState == MachineStates.Boost then
		m.BoostTimer = m.Stats.BoostDuration
	elseif newState == MachineStates.Land then
		m.LandTimer = m.Stats.LandDuration
	end
end

function StateMachine.Update(m: MachineLike, dt: number)
	if m.Hitstun > 0 then
		m.Hitstun = math.max(0, m.Hitstun - dt)
	end

	local state = m.State
	local releasedCharge = m.WasCharging and not m.Charging

	if state == MachineStates.Idle then
		if m.Grounded and (stickMag(m) > 0.05 or m.Charging) then
			StateMachine.Change(m, if m.Charging then MachineStates.Charge else MachineStates.Run)
		elseif not m.Grounded then
			StateMachine.Change(m, MachineStates.Fly)
		end
	elseif state == MachineStates.Run then
		if not m.Grounded then
			StateMachine.Change(m, MachineStates.Fly)
		elseif m.Charging then
			StateMachine.Change(m, MachineStates.Charge)
		elseif stickMag(m) < 0.02 and m.Velocity.Magnitude < 3 then
			StateMachine.Change(m, MachineStates.Idle)
		end
	elseif state == MachineStates.Charge then
		if not m.Grounded then
			StateMachine.Change(m, MachineStates.Fly)
		elseif releasedCharge then
			StateMachine.Change(m, MachineStates.Boost)
		elseif not m.Charging then
			StateMachine.Change(m, MachineStates.Run)
		end
	elseif state == MachineStates.Boost then
		m.BoostTimer -= dt
		if not m.Grounded then
			StateMachine.Change(m, MachineStates.Fly)
		elseif m.BoostTimer <= 0 then
			StateMachine.Change(m, MachineStates.Run)
		elseif m.Charging then
			StateMachine.Change(m, MachineStates.Charge)
		end
	elseif state == MachineStates.Fly then
		if m.Grounded then
			StateMachine.Change(m, MachineStates.Land)
		end
	elseif state == MachineStates.Land then
		m.LandTimer -= dt
		if not m.Grounded then
			StateMachine.Change(m, MachineStates.Fly)
		elseif m.LandTimer <= 0 then
			StateMachine.Change(m, if m.Charging then MachineStates.Charge else MachineStates.Run)
		end
	end

	m.WasCharging = m.Charging
end

return StateMachine
