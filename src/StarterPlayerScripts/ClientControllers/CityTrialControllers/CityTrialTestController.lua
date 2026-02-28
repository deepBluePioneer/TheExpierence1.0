local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Knit = require(ReplicatedStorage.Packages.Knit)

local CityTrialTestController = Knit.CreateController {
	Name = "CityTrialTestController",
}

function CityTrialTestController:KnitInit()
	print("[CityTrialTestController] KnitInit -- CityTrialControllers folder is loading correctly")
end

function CityTrialTestController:KnitStart()
	print("[CityTrialTestController] KnitStart -- CityTrialControllers is running")
end

return CityTrialTestController
