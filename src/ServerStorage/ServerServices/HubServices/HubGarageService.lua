local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Packages = ReplicatedStorage.Packages
local Knit = require(Packages.Knit)

local MachinesConfig = require(ReplicatedStorage.Source.MachinesConfig)
local Analytics = require(ReplicatedStorage.Source.Analytics)

local HubGarageService = Knit.CreateService {
	Name = "HubGarageService",
	Client = {},
}

function HubGarageService:KnitInit()
end

function HubGarageService:KnitStart()
end

function HubGarageService:GetOwnedMachines(player)
	local HubProfileService = Knit.GetService("HubProfileService")
	return HubProfileService:GetOwnedMachines(player)
end

function HubGarageService:GetSelectedMachine(player)
	local HubProfileService = Knit.GetService("HubProfileService")
	local data = HubProfileService:GetProfileData(player)
	return data and data.selectedMachineId or MachinesConfig.defaultMachineId
end

function HubGarageService:SelectMachine(player, machineId)
	local HubProfileService = Knit.GetService("HubProfileService")
	local data = HubProfileService:GetProfileData(player)
	if not data then
		return false, "Profile not loaded"
	end

	if not MachinesConfig.machines[machineId] then
		return false, "Invalid machine"
	end

	if not table.find(data.ownedMachines, machineId) then
		return false, "Machine not owned"
	end

	local ok, err = HubProfileService:SetSelectedMachine(player, machineId)
	if ok then
		Analytics.MachineSelected(player, machineId)
		Analytics.Funnel.GarageSelectedMachine(player, machineId)
		Analytics.Funnel.OnboardingSelectedMachine(player)
	end
	return ok, err
end

function HubGarageService:GetMachineUnlockStatus(player, machineId)
	local HubProfileService = Knit.GetService("HubProfileService")
	local data = HubProfileService:GetProfileData(player)
	if not data then return "unavailable" end

	if table.find(data.ownedMachines, machineId) then
		return "owned"
	end

	local config = MachinesConfig.machines[machineId]
	if not config then return "unavailable" end

	local unlock = config.unlock
	if unlock.type == "default" then
		return "owned"
	elseif unlock.type == "level" then
		if data.level >= unlock.requiredLevel then
			return "unlockable"
		else
			return "locked"
		end
	elseif unlock.type == "shop" then
		if data.currency >= unlock.price then
			return "purchasable"
		else
			return "locked"
		end
	elseif unlock.type == "achievement" then
		return "locked"
	end

	return "unavailable"
end

----------------------------------------------------------------
-- Client-exposed methods
----------------------------------------------------------------

function HubGarageService:LogGarageOpened(player)
	Analytics.Funnel.GarageOpened(player)
	Analytics.Funnel.OnboardingExploredHub(player)
end

function HubGarageService:LogMachineViewed(player, machineId)
	Analytics.Funnel.GarageViewedMachine(player, machineId)
end

function HubGarageService.Client:GetOwnedMachines(player)
	return self.Server:GetOwnedMachines(player)
end

function HubGarageService.Client:GetSelectedMachine(player)
	return self.Server:GetSelectedMachine(player)
end

function HubGarageService.Client:SelectMachine(player, machineId)
	return self.Server:SelectMachine(player, machineId)
end

function HubGarageService.Client:GetMachineUnlockStatus(player, machineId)
	return self.Server:GetMachineUnlockStatus(player, machineId)
end

function HubGarageService.Client:LogGarageOpened(player)
	self.Server:LogGarageOpened(player)
end

function HubGarageService.Client:LogMachineViewed(player, machineId)
	self.Server:LogMachineViewed(player, machineId)
end

return HubGarageService
