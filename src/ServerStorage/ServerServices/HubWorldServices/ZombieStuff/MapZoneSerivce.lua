local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CustomPackages = ReplicatedStorage.CustomPackages
local Packages = ReplicatedStorage.Packages
local Knit = require(Packages.Knit)

local MapZoneSerivce = Knit.CreateService {
    Name = "MapZoneSerivce",
    Client = {},
}

function MapZoneSerivce:KnitStart()
    -- Add service startup logic here
end

function MapZoneSerivce:KnitInit()
    -- Add service initialization logic here
end

return MapZoneSerivce