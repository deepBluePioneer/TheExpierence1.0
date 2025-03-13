-- Access necessary services and the Knit framework
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local Knit = require(ReplicatedStorage.Packages.Knit)

-- Define Place IDs
local CTF_HubWorld_PlaceID = 73294104737372
local CTF_Level_1_PlaceID = 104252418179975

-- Reference to server-side services directories
local ServerServices = ServerStorage.Source.ServerServices
local ServiceDirectory_1 = ServerServices.CTF_HubWorld_Services
local ServiceDirectory_2 = ServerServices.CTF_Level_1_Services

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

-- Function to load services based on the current PlaceId
local function loadServicesForPlace(placeId)
    if placeId == CTF_HubWorld_PlaceID then
        requireServices(ServiceDirectory_1)
    elseif placeId == CTF_Level_1_PlaceID then
        requireServices(ServiceDirectory_2)
    else
        warn("Unrecognized Place ID, no services loaded:", placeId)
    end
end

-- Load the services for the current PlaceId
loadServicesForPlace(game.PlaceId)

-- Start Knit
Knit.Start():andThen(function()
    print("Knit Started on the Server")
end):catch(function(err)
    warn("Error starting Knit:", err)
end)
