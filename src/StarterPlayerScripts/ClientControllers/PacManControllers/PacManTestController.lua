local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Knit = require(ReplicatedStorage.Packages.Knit)

local PacManTestController = Knit.CreateController {
	Name = "PacManTestController",
}

function PacManTestController:KnitInit()
	print("[PacManTestController] KnitInit -- PacManControllers folder is loading correctly")
end

function PacManTestController:KnitStart()
	print("[PacManTestController] KnitStart -- PacManControllers is running")
end

return PacManTestController
