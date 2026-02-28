local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Knit = require(ReplicatedStorage.Packages.Knit)

local HubTestService = Knit.CreateService {
	Name = "HubTestService",
	Client = {},
}

function HubTestService:KnitInit()
	print("[HubTestService] KnitInit -- HubServices folder is loading correctly")
end

function HubTestService:KnitStart()
	print("[HubTestService] KnitStart -- HubServices is running")
end

return HubTestService
