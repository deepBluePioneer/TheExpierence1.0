-- Access necessary services and the Knit framework
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local Knit = require(ReplicatedStorage.Packages.Knit)

-- Reference to server-side services
local ServerServices = ServerStorage.Source.ServerServices

-- Define the Place IDs for different game environments
local Level_1PlaceID = 93295390305658
local LobbyPlaceID = 116406282300852

-- Define service directories based on game type
local LobbyServices = ServerServices.LobbyServices
local Level_1Services = ServerServices.Level_1Services

-- Function to require services recursively
local function requireServices(directory)
    for _, service in ipairs(directory:GetChildren()) do
        if service:IsA("ModuleScript") and service.Name:match("Service$") then
            require(service)
        elseif service:IsA("Folder") then
            requireServices(service)
        end
    end
end

-- Function to require services based on the place id
local function loadServicesForPlace(placeId)
    local serviceDirectory
    if placeId == LobbyPlaceID then
        serviceDirectory = LobbyServices
    elseif placeId == Level_1PlaceID then
        serviceDirectory = Level_1Services
    else
        warn("Unrecognized Place ID, no services loaded")
        return
    end

    requireServices(serviceDirectory)
end

-- Load the services appropriate for the current game's place ID
loadServicesForPlace(game.PlaceId)

-- Start Knit
Knit.Start():andThen(function()
    print("Knit Started on the Server")
end):catch(function(err)
    warn("Error starting Knit:", err)
end)
