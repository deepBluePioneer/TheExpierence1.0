--!strict
--[[
	Mount / dismount via Seat or VehicleSeat Occupant.
	PrimaryPart (or a child named Seat) should be a Seat/VehicleSeat.
]]

local Players = game:GetService("Players")

local MachineTypes = require(script.Parent.MachineTypes)

local Mount = {}

export type RideSeat = Seat | VehicleSeat

local function isRideSeat(inst: Instance?): boolean
	return inst ~= nil and (inst:IsA("Seat") or inst:IsA("VehicleSeat"))
end

function Mount.GetSeat(model: Model): RideSeat?
	local primary = model.PrimaryPart
	if isRideSeat(primary) then
		return primary :: RideSeat
	end
	local named = model:FindFirstChild("Seat", true) or model:FindFirstChild("RiderAttach", true)
	if isRideSeat(named) then
		return named :: RideSeat
	end
	for _, d in model:GetDescendants() do
		if isRideSeat(d) then
			return d :: RideSeat
		end
	end
	return nil
end

function Mount.PrepareSeat(seat: RideSeat)
	-- Keep touch-to-sit; we drive with custom physics, not VehicleSeat throttle.
	if seat:IsA("VehicleSeat") then
		seat.MaxSpeed = 0
		seat.Torque = 0
		seat.TurnSpeed = 0
		seat.HeadsUpDisplay = false
	end
	seat.Disabled = false
end

function Mount.IsEmpty(model: Model): boolean
	local seat = Mount.GetSeat(model)
	if seat and seat.Occupant ~= nil then
		return false
	end
	local owner = model:GetAttribute(MachineTypes.Attr.OwnerUserId)
	return owner == nil
end

function Mount.GetOwnerUserId(model: Model): number?
	local owner = model:GetAttribute(MachineTypes.Attr.OwnerUserId)
	if typeof(owner) == "number" then
		return owner
	end
	return nil
end

function Mount.GetPlayerFromOccupant(occupant: Humanoid?): Player?
	if not occupant then
		return nil
	end
	local character = occupant.Parent
	if not character or not character:IsA("Model") then
		return nil
	end
	return Players:GetPlayerFromCharacter(character)
end

--[[
	Force-sit the player (ProximityPrompt / remote).
	Occupant-changed handler in MachineService commits ownership.
]]
function Mount.Mount(player: Player, model: Model): boolean
	local seat = Mount.GetSeat(model)
	if not seat then
		warn("[Mount] No Seat/VehicleSeat on", model:GetFullName())
		return false
	end
	if seat.Occupant ~= nil then
		return false
	end
	if not Mount.IsEmpty(model) and Mount.GetOwnerUserId(model) ~= player.UserId then
		return false
	end

	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return false
	end

	Mount.PrepareSeat(seat)
	seat:Sit(humanoid)
	return seat.Occupant == humanoid
end

--[[
	Called when Occupant becomes a player — bind ownership attribute only.
]]
function Mount.BindOccupant(player: Player, model: Model)
	model:SetAttribute(MachineTypes.Attr.OwnerUserId, player.UserId)
end

--[[
	Stand up / clear seat. hopUp applies exit impulse like getOffBike.
]]
function Mount.Dismount(player: Player, model: Model, hopUp: boolean?): boolean
	local seat = Mount.GetSeat(model)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local hrp = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?

	if seat and seat.Occupant and humanoid and seat.Occupant == humanoid then
		humanoid.Sit = false
		-- Nudge off seat weld
		task.defer(function()
			if humanoid and humanoid.Parent then
				humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
			end
		end)
	end

	model:SetAttribute(MachineTypes.Attr.OwnerUserId, nil)

	if hopUp and hrp then
		task.delay(0.05, function()
			if hrp and hrp.Parent then
				hrp.AssemblyLinearVelocity = Vector3.new(0, 40, 0)
			end
		end)
	end

	return true
end

function Mount.ForceClear(_player: Player)
	-- Seat weld is engine-owned; nothing extra to clear.
end

return Mount
