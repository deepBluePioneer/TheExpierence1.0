--!strict
--[[
	Shared enums / attribute names for Air Ride–style machines.
	Place as ModuleScript under ReplicatedStorage.MachineSystem
]]

local MachineTypes = {}

MachineTypes.CollectionTag = "AirRideMachine"

MachineTypes.Attr = {
	MachineId = "MachineId",
	OwnerUserId = "OwnerUserId",
	State = "MachineState",
	Grounded = "MachineGrounded",
}

MachineTypes.RemotesFolderName = "MachineRemotes"

MachineTypes.RemoteNames = {
	Input = "MachineInput", -- UnreliableRemoteEvent
	Mount = "MachineMount", -- RemoteEvent
	Dismount = "MachineDismount", -- RemoteEvent
	CameraMode = "MachineCameraMode", -- RemoteEvent (server -> client)
}

export type MachineInput = {
	Steer: number, -- Stick X, -1..1 (yaw)
	Forward: number, -- Stick Y, -1..1
	ChargeHeld: boolean,
}

export type OrientationBasis = {
	Facing: Vector3,
	Up: Vector3,
	Right: Vector3,
}

return MachineTypes
