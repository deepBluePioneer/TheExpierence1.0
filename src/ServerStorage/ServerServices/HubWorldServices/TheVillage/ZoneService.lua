local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CustomPackages = ReplicatedStorage.CustomPackages
local Packages = ReplicatedStorage.Packages
local Knit = require(Packages.Knit)
local CollectionService = game:GetService("CollectionService")

-- Zone Modules
local ZoneRoot = CustomPackages.ZoneRoot
local Zone = require(ZoneRoot.Zone)

local ZoneService = Knit.CreateService {
    Name = "ZoneService",
    Client = {},
}

function ZoneService:KnitStart()
    
    local safeZone = CollectionService:GetTagged("SafeZone")

    local zone = Zone.new(safeZone)


    zone.playerEntered:Connect(function(player)
        print(player.Name .. " entered the zone of part" )
       
    end)
    zone.playerExited:Connect(function(player)
        print(player.Name .. " exited the zone of part" )
    end)
    -- Add service startup logic here
end

function ZoneService:KnitInit()
    -- Add service initialization logic here
end

return ZoneService