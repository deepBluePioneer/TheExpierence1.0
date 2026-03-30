local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Knit = require(ReplicatedStorage.Packages.Knit)

local ProvingGroundsTestController = Knit.CreateController({
	Name = "ProvingGroundsTestController",
})

function ProvingGroundsTestController:KnitInit()
	print("[ProvingGroundsTestController] KnitInit -- ProvingGroundsControllers folder is loading correctly")
end

function ProvingGroundsTestController:KnitStart()
	print("[ProvingGroundsTestController] KnitStart -- Hello World from the Proving Grounds client!")
end

return ProvingGroundsTestController
