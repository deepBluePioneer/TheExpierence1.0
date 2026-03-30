local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Knit = require(ReplicatedStorage.Packages.Knit)

local PacManTestService = Knit.CreateService {
	Name = "PacManTestService",
	Client = {},
}

function PacManTestService:KnitInit()
	print("[PacManTestService] KnitInit -- PacManServices folder is loading correctly")
end

function PacManTestService:KnitStart()
	print("[PacManTestService] KnitStart -- PacManServices is running")
end

return PacManTestService
