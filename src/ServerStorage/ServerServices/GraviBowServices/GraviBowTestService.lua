local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Knit = require(ReplicatedStorage.Packages.Knit)

local GraviBowTestService = Knit.CreateService {
	Name = "GraviBowTestService",
	Client = {},
}

function GraviBowTestService:KnitInit()
	print("[GraviBowTestService] KnitInit -- GraviBowServices folder is loading correctly")
end

function GraviBowTestService:KnitStart()
	print("[GraviBowTestService] Hello World from GraviBow Server!")
end

return GraviBowTestService
