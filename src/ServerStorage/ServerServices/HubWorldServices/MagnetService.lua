local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CustomPackages = ReplicatedStorage.CustomPackages
local Packages = ReplicatedStorage.Packages

local Knit = require(Packages.Knit)

-- Zone Modules
local ZoneRoot = CustomPackages.ZoneRoot
local Zone = require(ZoneRoot.Zone)

local MagnetService = Knit.CreateService {
    Name = "MagnetService",
    Client = {},
}

function MagnetService:KnitStart()
    local magnetZones = CollectionService:GetTagged("magnetZone")

    -- Iterate through the list of magnet zones
    for _, magnetZone in ipairs(magnetZones) do
        -- Create a zone for each magnetZone
        local zone = Zone.new(magnetZone)

        -- Connect playerEntered and playerExited events for this zone
        zone.playerEntered:Connect(function(player)
            -- Optional: Add logic for when a player enters the magnet zone
            -- print(player.Name .. " entered a magnet zone.")
        end)

        zone.playerExited:Connect(function(player)
            -- Play the sound when the player exits the zone
            local sound = magnetZone:FindFirstChildWhichIsA("Sound")
            if sound then
                sound:Play()
            else
                warn("No sound found in magnetZone: " .. magnetZone.Name)
            end
        end)
    end
end

function MagnetService:KnitInit()
    -- Add service initialization logic here
end

return MagnetService
