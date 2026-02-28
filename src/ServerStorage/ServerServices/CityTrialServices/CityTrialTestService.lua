local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Knit = require(ReplicatedStorage.Packages.Knit)

local CityTrialTestService = Knit.CreateService {
	Name = "CityTrialTestService",
	Client = {},
}

function CityTrialTestService:KnitInit()
	print("[CityTrialTestService] KnitInit -- CityTrialServices folder is loading correctly")
end

function CityTrialTestService:KnitStart()
	print("[CityTrialTestService] KnitStart -- CityTrialServices is running")
end

return CityTrialTestService
