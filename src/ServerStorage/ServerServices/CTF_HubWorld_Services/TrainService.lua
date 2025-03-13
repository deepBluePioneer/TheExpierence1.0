local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CustomPackages = ReplicatedStorage.CustomPackages
local Packages = ReplicatedStorage.Packages
local Knit = require(Packages.Knit)

local TrainService = Knit.CreateService {
    Name = "TrainService",
    Client = {},
}

function TrainService:KnitStart()
    -- Add service startup logic here
end

function TrainService:KnitInit()
    -- Add service initialization logic here
end

return TrainService