local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Knit = require(ReplicatedStorage.Packages.Knit)

local HelloService = Knit.CreateService {
	Name = "HelloService",
	Client = {},
}

function HelloService:KnitInit()
end

function HelloService:KnitStart()
	print("Hello from the server")
end

return HelloService
