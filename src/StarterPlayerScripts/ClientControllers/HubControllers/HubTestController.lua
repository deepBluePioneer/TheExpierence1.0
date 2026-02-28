local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Knit = require(ReplicatedStorage.Packages.Knit)

local HubTestController = Knit.CreateController {
	Name = "HubTestController",
}

function HubTestController:KnitInit()
	print("[HubTestController] KnitInit -- HubControllers folder is loading correctly")
end

function HubTestController:KnitStart()
	print("[HubTestController] KnitStart -- HubControllers is running")
end

return HubTestController
