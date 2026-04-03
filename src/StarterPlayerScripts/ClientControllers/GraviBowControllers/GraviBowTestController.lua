local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Packages = ReplicatedStorage.Packages
local Knit = require(Packages.Knit)

local GraviBowTestController = Knit.CreateController {
	Name = "GraviBowTestController",
}

function GraviBowTestController:KnitInit() end

function GraviBowTestController:KnitStart()
end

return GraviBowTestController
