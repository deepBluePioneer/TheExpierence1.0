local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CustomPackages = ReplicatedStorage.CustomPackages
local Packages = ReplicatedStorage.Packages
local Knit = require(Packages.Knit)

local test = Knit.CreateService {
    Name = "test",
    Client = {},
}

function test:KnitStart()

    --print("Hello Re")
    -- Add service startup logic here
end

function test:KnitInit()
    -- Add service initialization logic here
end

return test