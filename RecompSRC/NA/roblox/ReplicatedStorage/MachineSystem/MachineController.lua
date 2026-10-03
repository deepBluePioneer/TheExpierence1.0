--!strict
--[[
	Per-machine runtime controller (server). Mirrors vehicle userdata + procs.
]]

local MachineTypes = require(script.Parent.MachineTypes)
local MachineStates = require(script.Parent.MachineStates)
local MachineStats = require(script.Parent.MachineStats)
local GroundProbe = require(script.Parent.GroundProbe)
local Physics = require(script.Parent.Physics)
local StateMachine = require(script.Parent.StateMachine)
local HitboxKnockback = require(script.Parent.HitboxKnockback)

export type Controller = {
	Model: Model,
	Root: BasePart,
	Stats: MachineStats.Stats,
	State: string,
	StickX: number,
	StickY: number,
	Charging: boolean,
	WasCharging: boolean,
	Velocity: Vector3,
	Facing: Vector3,
	Up: Vector3,
	Right: Vector3,
	HoverEnergy: number,
	Grounded: boolean,
	BoostTimer: number,
	LandTimer: number,
	Hitstun: number,
	Owner: Player?,
	RayParams: RaycastParams,
	Align: AlignOrientation?,
	_hitbox: BasePart?,
}

local MachineController = {}
MachineController.__index = MachineController

local function ensureAlign(root: BasePart): AlignOrientation
	local existing = root:FindFirstChild("MachineAlign") :: AlignOrientation?
	if existing then
		return existing
	end
	local att = root:FindFirstChild("MachineAlignAtt") :: Attachment?
	if not att then
		att = Instance.new("Attachment")
		att.Name = "MachineAlignAtt"
		att.Parent = root
	end
	local ao = Instance.new("AlignOrientation")
	ao.Name = "MachineAlign"
	ao.Mode = Enum.OrientationAlignmentMode.OneAttachment
	ao.Attachment0 = att
	ao.RigidityEnabled = false
	ao.MaxTorque = 1e7
	ao.Responsiveness = 25
	ao.Parent = root
	return ao
end

function MachineController.new(model: Model): Controller
	local root = model.PrimaryPart
	assert(root, "Machine model needs PrimaryPart")

	local machineId = model:GetAttribute(MachineTypes.Attr.MachineId) :: string?
	local stats = MachineStats.GetForMachineId(machineId)

	local look = root.CFrame.LookVector
	local up = root.CFrame.UpVector
	local facing, upU, right = Physics.RebuildBasis(look, up)

	local self: Controller = setmetatable({
		Model = model,
		Root = root,
		Stats = stats,
		State = MachineStates.Idle,
		StickX = 0,
		StickY = 0,
		Charging = false,
		WasCharging = false,
		Velocity = Vector3.zero,
		Facing = facing,
		Up = upU,
		Right = right,
		HoverEnergy = stats.HoverEnergyMax * 0.5,
		Grounded = true,
		BoostTimer = 0,
		LandTimer = 0,
		Hitstun = 0,
		Owner = nil,
		RayParams = GroundProbe.UpdateParams({ model }),
		Align = ensureAlign(root),
		_hitbox = nil,
	}, MachineController) :: any

	model:SetAttribute(MachineTypes.Attr.State, self.State)
	model:SetAttribute(MachineTypes.Attr.Grounded, self.Grounded)
	return self
end

function MachineController:SetInput(input: MachineTypes.MachineInput)
	if self.Hitstun > 0 then
		self.StickX = 0
		self.StickY = 0
		self.Charging = false
		return
	end
	self.StickX = math.clamp(input.Steer, -1, 1)
	self.StickY = math.clamp(input.Forward, -1, 1)
	self.Charging = input.ChargeHeld == true
end

function MachineController:SetOwner(player: Player?)
	self.Owner = player
	if player then
		self.Model:SetAttribute(MachineTypes.Attr.OwnerUserId, player.UserId)
	else
		self.Model:SetAttribute(MachineTypes.Attr.OwnerUserId, nil)
		self.StickX = 0
		self.StickY = 0
		self.Charging = false
		self.WasCharging = false
		StateMachine.Change(self, MachineStates.Idle)
	end
end

function MachineController:Step(dt: number)
	-- Ground probe
	local probe = GroundProbe.Cast(self.Root.Position, self.Up, self.Stats, self.RayParams)
	self.Grounded = probe.Grounded
	if probe.Normal then
		local targetUp = probe.Normal.Unit
		self.Up = self.Up:Lerp(targetUp, math.clamp(dt * 10, 0, 1))
	elseif not self.Grounded then
		self.Up = self.Up:Lerp(Vector3.yAxis, math.clamp(dt * 3, 0, 1))
	end

	self.Facing, self.Up, self.Right = Physics.RebuildBasis(self.Facing, self.Up)
	self.Facing = Physics.TurnYaw(self, dt)
	self.Facing, self.Up, self.Right = Physics.RebuildBasis(self.Facing, self.Up)

	StateMachine.Update(self, dt)

	local ctx: Physics.PhysContext = {
		State = self.State,
		StickX = self.StickX,
		StickY = self.StickY,
		Charging = self.Charging,
		Velocity = self.Velocity,
		Facing = self.Facing,
		Up = self.Up,
		Right = self.Right,
		HoverEnergy = self.HoverEnergy,
		BoostTimer = self.BoostTimer,
		Stats = self.Stats,
		Grounded = self.Grounded,
	}

	local accel = Physics.ComputeAccel(ctx, dt)
	accel = Physics.ClampAccelToTopSpeed(self.Velocity, accel, Physics.TopSpeed(ctx))
	self.Velocity = Physics.Integrate(self.Velocity, accel, dt)

	-- Project onto ground plane when grounded (slide, don't dig)
	if self.Grounded and probe.Normal then
		local n = probe.Normal.Unit
		self.Velocity = self.Velocity - n * self.Velocity:Dot(n)
		-- Keep near surface
		if probe.HitPosition then
			local desired = probe.HitPosition + n * self.Stats.RideHeight
			local err = desired - self.Root.Position
			self.Velocity += err * (12 * dt)
		end
	else
		-- Apply gravity in air (partially cancelled in ComputeAccel for Fly)
		if self.State == MachineStates.Fly then
			self.Velocity += Vector3.new(0, -workspace.Gravity * self.Stats.FlyGravityScale * dt, 0)
		else
			self.Velocity += Vector3.new(0, -workspace.Gravity * dt, 0)
		end
	end

	self.HoverEnergy = Physics.UpdateHoverEnergy(self, dt)

	self.Root.AssemblyLinearVelocity = self.Velocity

	-- Orientation
	local cf = CFrame.lookAt(self.Root.Position, self.Root.Position + self.Facing, self.Up)
	if self.Align then
		self.Align.CFrame = cf.Rotation
	end

	HitboxKnockback.Update(self, dt)

	self.Model:SetAttribute(MachineTypes.Attr.State, self.State)
	self.Model:SetAttribute(MachineTypes.Attr.Grounded, self.Grounded)
end

function MachineController:ApplyKnockback(worldImpulse: Vector3)
	local stats = self.Stats
	self.Velocity *= (1 - stats.KbDampFraction)
	self.Velocity += worldImpulse * stats.KbMultiplier
	self.Hitstun = math.max(self.Hitstun, stats.HitstunTime)
end

function MachineController:Destroy()
	HitboxKnockback.Cleanup(self)
	if self.Align then
		self.Align:Destroy()
	end
end

return MachineController
