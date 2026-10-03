local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Knit = require(ReplicatedStorage.Packages.Knit)

local HelloController = Knit.CreateController {
	Name = "HelloController",
}

function HelloController:KnitInit()
end

function HelloController:KnitStart()
	print("Hello from the client")
end

return HelloController
