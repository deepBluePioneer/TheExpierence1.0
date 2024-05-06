-- Access necessary services and the Knit framework
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local Knit = require(ReplicatedStorage.Packages.Knit)

-- Reference to server-side services
local ServerServices = ServerStorage.Source.ServerServices

-- Define the Place IDs for different game environments
local DungeonPlaceID = 17399051565
local HubWorldServiceID = 17399041158

-- Define service directories based on game type
local HubWorldServices = ServerServices.HubWorldServices
local DungeonPlaceServices = ServerServices.DungeonPlaceServices

-- Function to require services based on the place id
local function loadServicesForPlace(placeId)
    local serviceDirectory
    if placeId == HubWorldServiceID then
        serviceDirectory = HubWorldServices
    elseif placeId == DungeonPlaceID then
        serviceDirectory = DungeonPlaceServices
    else
        warn("Unrecognized Place ID, no services loaded")
        return
    end

    for _, service in ipairs(serviceDirectory:GetChildren()) do
        if service:IsA("ModuleScript") and service.Name:match("Service$") then
            require(service)
        end
    end
end

-- Load the services appropriate for the current game's place ID
loadServicesForPlace(game.PlaceId)

-- Start Knit
Knit.Start():andThen(function()
    print("Knit Started on the Server")
end):catch(function(err)
    warn("Error starting Knit:", err)
end)
