local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CustomPackages = ReplicatedStorage.CustomPackages
local Packages = ReplicatedStorage.Packages
local Knit = require(Packages.Knit)

local EnemySoundsService = Knit.CreateService {
    Name = "EnemySoundsService",
    Client = {},
}

function EnemySoundsService:KnitStart()
    -- Add service startup logic here
end

function EnemySoundsService:KnitInit()
    -- Add service initialization logic here
end

return EnemySoundsService