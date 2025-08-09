local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CustomPackages = ReplicatedStorage.CustomPackages
local Packages = ReplicatedStorage.Packages
local Knit = require(Packages.Knit)
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")

local MachineService = Knit.CreateService {
    Name = "MachineService",
    Client = {},
}

-- Utility: Get player from humanoid
local function getPlayerFromHumanoid(humanoid)
	if not humanoid then return nil end
	local character = humanoid.Parent
	if not character then return nil end
	return Players:GetPlayerFromCharacter(character)
end

function MachineService:HandleSeat(seat, machine)
	seat:GetPropertyChangedSignal("Occupant"):Connect(function()
		local humanoid = seat.Occupant
		local player = getPlayerFromHumanoid(humanoid)

		if player then
			machine:SetAttribute("OwnerUserId", player.UserId)
			local rootPart = machine:FindFirstChild("RootPart")
			if rootPart then
				rootPart:SetNetworkOwner(player) -- ✅ Give client authority
			end
		else
			machine:SetAttribute("OwnerUserId", nil)
			local rootPart = machine:FindFirstChild("RootPart")
			if rootPart then
				rootPart:SetNetworkOwner(nil) -- Revoke ownership if empty
			end
		end
	end)
end

function init()
		local machines = CollectionService:GetTagged("machine")

	for _, machine in ipairs(machines) do
		if machine:IsDescendantOf(workspace) then
			local seat = machine:FindFirstChildWhichIsA("Seat", true)
			if seat then
				self:HandleSeat(seat, machine)
			end
		end
	end
end

function MachineService:KnitStart()

end

return MachineService
