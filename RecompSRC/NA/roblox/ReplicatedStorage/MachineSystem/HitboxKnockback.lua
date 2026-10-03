--!strict
--[[
	Speed-gated head-on hitbox + knockback impulse (fn_setHeadOnHitBox_ / fn_801E2324 style).
]]

local CollectionService = game:GetService("CollectionService")

local MachineTypes = require(script.Parent.MachineTypes)

export type Host = {
	Model: Model,
	Root: BasePart,
	Velocity: Vector3,
	Facing: Vector3,
	Owner: Player?,
	Stats: {
		HeadOnSpeedMin: number,
		HeadOnSize: Vector3,
		HeadOnOffset: number,
		KbMultiplier: number,
	},
	_hitbox: BasePart?,
	ApplyKnockback: (self: any, impulse: Vector3) -> (),
}

local HitboxKnockback = {}

local cooldown: { [Model]: number } = {}

local function getOrCreateHitbox(host: Host): BasePart
	if host._hitbox and host._hitbox.Parent then
		return host._hitbox
	end
	local part = Instance.new("Part")
	part.Name = "HeadOnHitbox"
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = true
	part.Massless = true
	part.Transparency = 1
	part.Size = host.Stats.HeadOnSize
	part.Parent = host.Model
	host._hitbox = part

	part.Touched:Connect(function(other: BasePart)
		HitboxKnockback._onTouched(host, other)
	end)

	return part
end

function HitboxKnockback._onTouched(host: Host, other: BasePart)
	if not host.Owner then
		return
	end
	local otherModel = other:FindFirstAncestorOfClass("Model")
	if not otherModel or otherModel == host.Model then
		return
	end
	if not CollectionService:HasTag(otherModel, MachineTypes.CollectionTag) then
		return
	end

	local now = os.clock()
	local key = host.Model
	if cooldown[key] and now < cooldown[key] then
		return
	end
	cooldown[key] = now + 0.4

	-- Resolve other controller via attribute signal; MachineService binds Apply
	local binder = host.Model:FindFirstChild("KnockbackBridge")
	if binder and binder:IsA("BindableEvent") then
		(binder :: BindableEvent):Fire(otherModel, host.Velocity, host.Facing)
	end
end

function HitboxKnockback.Update(host: Host, _dt: number)
	local speed = host.Velocity.Magnitude
	local hitbox = getOrCreateHitbox(host)
	local active = host.Owner ~= nil and speed >= host.Stats.HeadOnSpeedMin

	hitbox.Size = host.Stats.HeadOnSize
	if active then
		local offset = host.Facing.Unit * host.Stats.HeadOnOffset
		hitbox.CFrame = CFrame.lookAt(host.Root.Position + offset, host.Root.Position + offset + host.Facing)
		hitbox.CanTouch = true
	else
		hitbox.CanTouch = false
		hitbox.CFrame = host.Root.CFrame
	end
end

function HitboxKnockback.ComputeImpulse(attackerVel: Vector3, facing: Vector3, strengthScale: number): Vector3
	local dir = facing
	if attackerVel.Magnitude > 1 then
		dir = attackerVel.Unit
	end
	local strength = math.clamp(attackerVel.Magnitude * 0.35, 20, 120) * strengthScale
	return dir * strength
end

function HitboxKnockback.Cleanup(host: Host)
	if host._hitbox then
		host._hitbox:Destroy()
		host._hitbox = nil
	end
	cooldown[host.Model] = nil
end

return HitboxKnockback
