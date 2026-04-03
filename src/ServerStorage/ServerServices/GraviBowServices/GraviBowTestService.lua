local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Knit = require(ReplicatedStorage.Packages.Knit)

local GraviBowTestService = Knit.CreateService {
	Name = "GraviBowTestService",
	Client = {},
}

function GraviBowTestService:KnitInit()
end

function GraviBowTestService:KnitStart()
end

return GraviBowTestService
