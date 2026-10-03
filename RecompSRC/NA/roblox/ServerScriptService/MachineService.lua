--!strict
--[[
	Server entry: remotes, Seat Occupant mount detection, Heartbeat simulation.
	Place as Script under ServerScriptService.
	Machine PrimaryPart should be a Seat (or VehicleSeat); Occupant drives mount state.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")

local MachineSystem = ReplicatedStorage:WaitForChild("MachineSystem")
local MachineTypes = require(MachineSystem:WaitForChild("MachineTypes"))
local MachineController = require(MachineSystem:WaitForChild("MachineController"))
local Mount = require(MachineSystem:WaitForChild("Mount"))
local HitboxKnockback = require(MachineSystem:WaitForChild("HitboxKnockback"))

local controllers: { [Model]: any } = {}
local playerMachine: { [Player]: Model } = {}
local lastInput: { [Player]: MachineTypes.MachineInput } = {}
local seatConnections: { [Model]: RBXScriptConnection } = {}

local function ensureRemotes()
	local folder = ReplicatedStorage:FindFirstChild(MachineTypes.RemotesFolderName)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = MachineTypes.RemotesFolderName
		folder.Parent = ReplicatedStorage
	end

	local function ensure(name: string, className: string): Instance
		local existing = folder:FindFirstChild(name)
		if existing then
			return existing
		end
		local inst = Instance.new(className)
		inst.Name = name
		inst.Parent = folder
		return inst
	end

	ensure(MachineTypes.RemoteNames.Input, "UnreliableRemoteEvent")
	ensure(MachineTypes.RemoteNames.Mount, "RemoteEvent")
	ensure(MachineTypes.RemoteNames.Dismount, "RemoteEvent")
	ensure(MachineTypes.RemoteNames.CameraMode, "RemoteEvent")
	return folder
end

local remotes = ensureRemotes()
local inputRemote = remotes:WaitForChild(MachineTypes.RemoteNames.Input) :: UnreliableRemoteEvent
local mountRemote = remotes:WaitForChild(MachineTypes.RemoteNames.Mount) :: RemoteEvent
local dismountRemote = remotes:WaitForChild(MachineTypes.RemoteNames.Dismount) :: RemoteEvent
local cameraRemote = remotes:WaitForChild(MachineTypes.RemoteNames.CameraMode) :: RemoteEvent

local function getController(model: Model)
	local c = controllers[model]
	if not c then
		c = MachineController.new(model)
		controllers[model] = c

		local bridge = model:FindFirstChild("KnockbackBridge")
		if not bridge then
			bridge = Instance.new("BindableEvent")
			bridge.Name = "KnockbackBridge"
			bridge.Parent = model
		end
		;(bridge :: BindableEvent).Event:Connect(function(otherModel: Model, vel: Vector3, facing: Vector3)
			local other = controllers[otherModel]
			if not other then
				return
			end
			local impulse = HitboxKnockback.ComputeImpulse(vel, facing, 1)
			other:ApplyKnockback(impulse)
			c:ApplyKnockback(-impulse * 0.35)
		end)
	end
	return c
end

local function beginRide(player: Player, model: Model)
	if playerMachine[player] == model then
		return
	end
	-- Already on another machine?
	if playerMachine[player] and playerMachine[player] ~= model then
		return
	end

	local ctrl = getController(model)
	Mount.BindOccupant(player, model)
	ctrl:SetOwner(player)
	playerMachine[player] = model
	cameraRemote:FireClient(player, "Riding", model)
end

local function endRide(player: Player, model: Model, hopUp: boolean?)
	if playerMachine[player] ~= model then
		-- Still clear ownership if attribute matches
		if Mount.GetOwnerUserId(model) == player.UserId then
			model:SetAttribute(MachineTypes.Attr.OwnerUserId, nil)
		end
		return
	end

	local ctrl = controllers[model]
	-- Don't call Seat:Sit clear again if Occupant already nil — just attributes/hop
	if hopUp then
		local character = player.Character
		local hrp = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if hrp then
			hrp.AssemblyLinearVelocity = Vector3.new(0, 40, 0)
		end
	end

	model:SetAttribute(MachineTypes.Attr.OwnerUserId, nil)
	if ctrl then
		ctrl:SetOwner(nil)
		ctrl.Velocity = Vector3.zero
		if ctrl.Root then
			ctrl.Root.AssemblyLinearVelocity = Vector3.zero
		end
	end
	playerMachine[player] = nil
	cameraRemote:FireClient(player, "OnFoot", nil)
end

local function onSeatOccupantChanged(model: Model, seat: Mount.RideSeat)
	local occupant = seat.Occupant
	local player = Mount.GetPlayerFromOccupant(occupant)

	if player then
		beginRide(player, model)
	else
		-- Someone stood up / jumped off
		local previousId = Mount.GetOwnerUserId(model)
		if previousId then
			local prevPlayer = Players:GetPlayerByUserId(previousId)
			if prevPlayer then
				endRide(prevPlayer, model, true)
			else
				model:SetAttribute(MachineTypes.Attr.OwnerUserId, nil)
				local ctrl = controllers[model]
				if ctrl then
					ctrl:SetOwner(nil)
				end
			end
		end
	end
end

local function tryMount(player: Player, model: Model)
	if playerMachine[player] then
		return
	end
	if not CollectionService:HasTag(model, MachineTypes.CollectionTag) then
		return
	end
	-- Sit; Occupant signal commits ride
	Mount.Mount(player, model)
end

local function tryDismount(player: Player)
	local model = playerMachine[player]
	if not model then
		return
	end
	Mount.Dismount(player, model, false)
	-- Occupant clear will fire endRide; if it doesn't, force:
	task.defer(function()
		if playerMachine[player] == model then
			endRide(player, model, true)
		end
	end)
end

local function registerMachine(model: Model)
	if not model.PrimaryPart then
		warn("[MachineService] Machine missing PrimaryPart:", model:GetFullName())
		return
	end
	if not model:GetAttribute(MachineTypes.Attr.MachineId) then
		model:SetAttribute(MachineTypes.Attr.MachineId, model.Name)
	end

	local seat = Mount.GetSeat(model)
	if not seat then
		warn("[MachineService] AirRideMachine needs a Seat/VehicleSeat (PrimaryPart preferred):", model:GetFullName())
		return
	end

	Mount.PrepareSeat(seat)
	getController(model)

	if seatConnections[model] then
		seatConnections[model]:Disconnect()
	end
	seatConnections[model] = seat:GetPropertyChangedSignal("Occupant"):Connect(function()
		onSeatOccupantChanged(model, seat)
	end)
	-- Sync if already occupied (studio play mid-sit)
	if seat.Occupant then
		onSeatOccupantChanged(model, seat)
	end

	-- Optional prompt to call Seat:Sit
	if not seat:FindFirstChild("MountPrompt") then
		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "MountPrompt"
		prompt.ActionText = "Ride"
		prompt.ObjectText = model.Name
		prompt.MaxActivationDistance = 12
		prompt.Parent = seat
		prompt.Triggered:Connect(function(player: Player)
			tryMount(player, model)
		end)
	end
end

for _, model in CollectionService:GetTagged(MachineTypes.CollectionTag) do
	if model:IsA("Model") then
		registerMachine(model)
	end
end
CollectionService:GetInstanceAddedSignal(MachineTypes.CollectionTag):Connect(function(inst)
	if inst:IsA("Model") then
		registerMachine(inst)
	end
end)

inputRemote.OnServerEvent:Connect(function(player: Player, payload: any)
	if typeof(payload) ~= "table" then
		return
	end
	lastInput[player] = {
		Steer = tonumber(payload.Steer) or 0,
		Forward = tonumber(payload.Forward) or 0,
		ChargeHeld = payload.ChargeHeld == true,
	}
end)

mountRemote.OnServerEvent:Connect(function(player: Player, model: Instance?)
	if typeof(model) ~= "Instance" or not model:IsA("Model") then
		return
	end
	tryMount(player, model)
end)

dismountRemote.OnServerEvent:Connect(function(player: Player)
	tryDismount(player)
end)

Players.PlayerRemoving:Connect(function(player: Player)
	tryDismount(player)
	lastInput[player] = nil
end)

RunService.Heartbeat:Connect(function(dt)
	for model, ctrl in controllers do
		if not model.Parent then
			if seatConnections[model] then
				seatConnections[model]:Disconnect()
				seatConnections[model] = nil
			end
			ctrl:Destroy()
			controllers[model] = nil
			continue
		end
		local owner = ctrl.Owner
		if owner then
			local input = lastInput[owner]
			if input then
				ctrl:SetInput(input)
			end
			ctrl:Step(dt)
		else
			ctrl.StickX = 0
			ctrl.StickY = 0
			ctrl.Charging = false
			if ctrl.Velocity.Magnitude > 0.5 then
				ctrl:Step(dt)
			end
		end
	end
end)

print("[MachineService] Air Ride machine system ready (Seat Occupant mount)")
