--!strict
--[[
	Accel build + top-speed clamp + integrate (accelerateStar + fn_801C6368 style).
]]

local MachineStates = require(script.Parent.MachineStates)
local MachineStats = require(script.Parent.MachineStats)

local function gravityLift(stats: MachineStats.Stats): number
	return workspace.Gravity * (1 - stats.FlyGravityScale)
end

export type PhysContext = {
	State: string,
	StickX: number,
	StickY: number,
	Charging: boolean,
	Velocity: Vector3,
	Facing: Vector3,
	Up: Vector3,
	Right: Vector3,
	HoverEnergy: number,
	BoostTimer: number,
	Stats: MachineStats.Stats,
	Grounded: boolean,
}

local Physics = {}

local function flat(v: Vector3, up: Vector3): Vector3
	local p = v - up * v:Dot(up)
	if p.Magnitude < 1e-5 then
		return Vector3.zero
	end
	return p.Unit
end

function Physics.RebuildBasis(facing: Vector3, up: Vector3): (Vector3, Vector3, Vector3)
	local upU = if up.Magnitude > 1e-4 then up.Unit else Vector3.yAxis
	local f = flat(facing, upU)
	if f.Magnitude < 1e-5 then
		f = flat(Vector3.zAxis, upU)
		if f.Magnitude < 1e-5 then
			f = flat(Vector3.xAxis, upU)
		end
	end
	f = f.Unit
	local right = upU:Cross(f)
	if right.Magnitude < 1e-5 then
		right = Vector3.xAxis
	else
		right = right.Unit
	end
	f = right:Cross(upU).Unit
	return f, upU, right
end

function Physics.ApplyDeadzone(v: number, deadzone: number): number
	local a = math.abs(v)
	if a <= deadzone then
		return 0
	end
	local sign = if v < 0 then -1 else 1
	return sign * ((a - deadzone) / (1 - deadzone))
end

function Physics.TopSpeed(ctx: PhysContext): number
	local s = ctx.Stats.TopSpeed
	if ctx.State == MachineStates.Boost then
		s *= ctx.Stats.BoostTopSpeedMult
	end
	return s
end

function Physics.ComputeAccel(ctx: PhysContext, dt: number): Vector3
	local stats = ctx.Stats
	local facing = ctx.Facing
	local up = ctx.Up
	local stickX = Physics.ApplyDeadzone(ctx.StickX, stats.StickDeadzone)
	local stickY = Physics.ApplyDeadzone(ctx.StickY, stats.StickDeadzone)

	local accel = Vector3.zero
	local speed = ctx.Velocity.Magnitude

	-- Drive / scrub / boost along facing
	if ctx.State == MachineStates.Charge then
		local scrub = facing * stats.ChargeHoverDelta
		accel += scrub
		-- Extra horizontal damp while charging
		accel += -flat(ctx.Velocity, up) * (stats.Drag * 2)
	elseif ctx.State == MachineStates.Boost then
		accel += facing * stats.BoostAccel
	elseif ctx.State == MachineStates.Run or ctx.State == MachineStates.Land then
		local throttle = math.clamp(stickY, -0.25, 1) -- slight reverse allowed
		if math.abs(throttle) > 0.05 then
			accel += facing * (stats.Accel * throttle)
		else
			accel += -flat(ctx.Velocity, up) * stats.Drag
		end
		-- Cruise hover energy nudge (feeds ride height feel)
		accel += up * (stats.CruiseHoverDelta * 0.15)
	elseif ctx.State == MachineStates.Fly then
		local throttle = math.clamp(stickY, -1, 1)
		accel += facing * (stats.FlyAccel * throttle)
		accel += -flat(ctx.Velocity, up) * (stats.Drag * 0.35)
		-- Partial gravity cancel
		accel += Vector3.yAxis * gravityLift(stats)
	elseif ctx.State == MachineStates.Idle then
		accel += -flat(ctx.Velocity, up) * (stats.Drag * 1.5)
	end

	-- Soft ground stick: pull toward ride height when grounded
	if ctx.Grounded and ctx.State ~= MachineStates.Fly then
		accel += up * (stats.CruiseHoverDelta * 0.05)
	end

	return accel
end

function Physics.ClampAccelToTopSpeed(vel: Vector3, accel: Vector3, topSpeed: number): Vector3
	-- accelerateStar: proposed = vel + accel; if over topSpeed, rewrite accel
	local proposed = vel + accel
	local speed = proposed.Magnitude
	if speed <= topSpeed or speed < 1e-5 then
		return accel
	end
	local clamped = proposed.Unit * topSpeed
	return clamped - vel
end

function Physics.Integrate(vel: Vector3, accel: Vector3, dt: number): Vector3
	return vel + accel * dt
end

function Physics.TurnYaw(ctx: PhysContext, dt: number): Vector3
	local stats = ctx.Stats
	local stickX = Physics.ApplyDeadzone(ctx.StickX, stats.StickDeadzone)
	if math.abs(stickX) < 1e-4 then
		return ctx.Facing
	end

	local speed = ctx.Velocity.Magnitude
	local rate
	if ctx.Grounded then
		local t = math.clamp(speed / math.max(stats.TurnSpeedBlend, 1), 0, 1)
		rate = stats.TurnRateGround * (1 - t) + stats.TurnRateHigh * t
	else
		rate = stats.AirTurnRateStick
	end

	local angle = -stickX * rate * dt
	local cf = CFrame.fromAxisAngle(ctx.Up, angle)
	return (cf:VectorToWorldSpace(ctx.Facing)).Unit
end

function Physics.UpdateHoverEnergy(ctx: PhysContext, dt: number): number
	local stats = ctx.Stats
	local e = ctx.HoverEnergy
	if ctx.State == MachineStates.Charge then
		e = math.clamp(e + stats.ChargeHoverDelta * dt * 0.05, 0, stats.HoverEnergyMax)
	elseif ctx.Grounded then
		e = math.clamp(e + stats.CruiseHoverDelta * dt * 0.05, 0, stats.HoverEnergyMax)
	end
	return e
end

return Physics
