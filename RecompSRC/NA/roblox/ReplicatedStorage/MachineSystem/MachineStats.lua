--!strict
--[[
	Tunables mapped from KAR vehicle stats (+0x650 meanings).
	Start with Warp Star–ish placeholders; adjust by feel.
]]

export type Stats = {
	TopSpeed: number,
	Accel: number,
	Drag: number,
	TurnRateGround: number,
	TurnRateHigh: number,
	TurnSpeedBlend: number,
	AirTurnRate: number,
	ChargeHoverDelta: number,
	CruiseHoverDelta: number,
	HoverEnergyMax: number,
	RideHeight: number,
	LeaveGroundRayLength: number,
	ProbeRadius: number,
	FlyGravityScale: number,
	FlyAccel: number,
	AirTurnRateStick: number,
	PitchRate: number,
	MaxPitchDeg: number,
	BoostDuration: number,
	BoostAccel: number,
	BoostTopSpeedMult: number,
	LandDuration: number,
	KbMultiplier: number,
	KbDampFraction: number,
	HitstunTime: number,
	HeadOnSpeedMin: number,
	HeadOnSize: Vector3,
	HeadOnOffset: number,
	StickDeadzone: number,
}

local MachineStats = {}

MachineStats.Default = {
	TopSpeed = 80,
	Accel = 55,
	Drag = 8,
	TurnRateGround = 2.2,
	TurnRateHigh = 1.4,
	TurnSpeedBlend = 40,
	AirTurnRate = 1.6,
	ChargeHoverDelta = -18,
	CruiseHoverDelta = 2,
	HoverEnergyMax = 4,
	RideHeight = 2.5,
	LeaveGroundRayLength = 6,
	ProbeRadius = 1.2,
	FlyGravityScale = 0.35,
	FlyAccel = 25,
	AirTurnRateStick = 1.8,
	PitchRate = 1.5,
	MaxPitchDeg = 35,
	BoostDuration = 0.85,
	BoostAccel = 140,
	BoostTopSpeedMult = 1.45,
	LandDuration = 0.25,
	KbMultiplier = 1.1,
	KbDampFraction = 0.55,
	HitstunTime = 0.35,
	HeadOnSpeedMin = 28,
	HeadOnSize = Vector3.new(4, 3, 5),
	HeadOnOffset = 3,
	StickDeadzone = 0.12,
} :: Stats

function MachineStats.GetForMachineId(_machineId: string?): Stats
	-- Extend later per MachineId (Heavy, Slick, etc.)
	local copy = table.clone(MachineStats.Default)
	return copy
end

return MachineStats
