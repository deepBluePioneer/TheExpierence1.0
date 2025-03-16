local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CustomPackages = ReplicatedStorage.CustomPackages
local Packages = ReplicatedStorage.Packages
local Knit = require(Packages.Knit)

-- Zone Modules
local ZoneRoot = CustomPackages.ZoneRoot
local Zone = require(ZoneRoot.Zone)
local CollectionService = game:GetService("CollectionService")

local FlagReturnService = Knit.CreateService {
    Name = "FlagReturnService",
    Client = {},
}

-- Get FlagService for flag respawning
local FlagService

function FlagReturnService:KnitInit()
    FlagService = Knit.GetService("FlagService") -- Get FlagService reference

    local FlagReturnZones = CollectionService:GetTagged("FlagReturnZone")

    -- Iterate through all flag return zones
    for _, flagReturnZone in ipairs(FlagReturnZones) do
        if flagReturnZone then
            local zone = Zone.new(flagReturnZone)
            local zoneTeamColor = flagReturnZone:GetAttribute("TeamColor") -- "Red" or "Blue"

            -- ✅ Player enters zone
            zone.playerEntered:Connect(function(player)
                if not player then return end

                local playerTeam = player.Team and player.Team.Name or "None"
                local hasFlag = player:GetAttribute("HasFlag")

                -- ✅ Only proceed if the player has a flag
                if hasFlag then
                    -- ✅ Check if the player is carrying the **enemy flag** and is in **their own return zone**
                    if playerTeam == zoneTeamColor then
                        print(player.Name .. " has successfully returned the enemy flag!")

                

                        -- Reset player's flag attributes
                        player:SetAttribute("HasFlag", false)

                        -- Respawn the flag
                        FlagService:ResetFlag(playerTeam == "Red" and "Blue" or "Red") 

                        -- Handle flag scoring logic here if needed
                    else
                        print(player.Name .. " entered a flag return zone but does not have the correct flag.")
                    end
                end
            end)

            -- ✅ Player exits zone
            zone.playerExited:Connect(function(player)
                print(player.Name .. " left the flag return zone.")
            end)
        else
            print("Error: FlagReturnZone is not configured correctly.")
        end
    end
end




return FlagReturnService
