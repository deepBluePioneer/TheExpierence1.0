--!strict
--[[
	Action states (KAR Star Run / Charge / Boost / Fly / Land subset).
]]

local MachineStates = {}

MachineStates.Idle = "Idle"
MachineStates.Run = "Run"
MachineStates.Charge = "Charge"
MachineStates.Boost = "Boost"
MachineStates.Fly = "Fly"
MachineStates.Land = "Land"

MachineStates.All = {
	MachineStates.Idle,
	MachineStates.Run,
	MachineStates.Charge,
	MachineStates.Boost,
	MachineStates.Fly,
	MachineStates.Land,
}

function MachineStates.IsValid(name: string): boolean
	for _, s in MachineStates.All do
		if s == name then
			return true
		end
	end
	return false
end

return MachineStates
