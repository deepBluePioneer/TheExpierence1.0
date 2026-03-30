local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Knit = require(ReplicatedStorage.Packages.Knit)

local ProvingGroundsTestService = Knit.CreateService({
	Name = "ProvingGroundsTestService",
	Client = {},
})

function ProvingGroundsTestService:KnitInit()
	print("[ProvingGroundsTestService] KnitInit -- ProvingGroundsServices folder is loading correctly")
end

function ProvingGroundsTestService:KnitStart()
	print("[ProvingGroundsTestService] KnitStart -- Hello World from the Proving Grounds server!")
end

return ProvingGroundsTestService
