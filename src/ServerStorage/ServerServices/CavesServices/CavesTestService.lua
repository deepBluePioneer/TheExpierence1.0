local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Knit = require(ReplicatedStorage.Packages.Knit)

local CavesTestService = Knit.CreateService {
	Name = "CavesTestService",
	Client = {},
}

function CavesTestService:KnitInit()
	print("[CavesTestService] KnitInit -- CavesServices folder is loading correctly")
end

function CavesTestService:KnitStart()
	print("[CavesTestService] Hello World from Caves Server!")
end

return CavesTestService
