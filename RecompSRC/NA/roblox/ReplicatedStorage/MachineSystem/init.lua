--!strict
--[[
	Optional barrel export. In Studio you usually require children by name instead.
]]

return {
	MachineTypes = require(script.MachineTypes),
	MachineStates = require(script.MachineStates),
	MachineStats = require(script.MachineStats),
	GroundProbe = require(script.GroundProbe),
	Physics = require(script.Physics),
	StateMachine = require(script.StateMachine),
	MachineController = require(script.MachineController),
	HitboxKnockback = require(script.HitboxKnockback),
	Mount = require(script.Mount),
	CameraChase = require(script.CameraChase),
}
