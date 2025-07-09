local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CustomPackages = ReplicatedStorage.CustomPackages
local Packages = ReplicatedStorage.Packages
local Knit = require(Packages.Knit)

local TestService = Knit.CreateService {
    Name = "TestService",
    Client = {},
}

function TestService:KnitStart()
    -- Add service startup logic here
end

function TestService:KnitInit()

    print("HI")
    -- Add service initialization logic here
end

return TestService