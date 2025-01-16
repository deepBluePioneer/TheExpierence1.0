-- Access necessary services and the Knit framework
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local Knit = require(ReplicatedStorage.Packages.Knit)

-- Reference to server-side services
local ServerServices = ServerStorage.Source.ServerServices

-- Define the single Place ID
local PlaceID = 114700333834518 -- Set your Place ID here

-- Define service directories for the place
local ServiceDirectory = ServerServices.SpaceProtoServices -- Adjust this based on the Place ID

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

-- Function to load services based on the place id
local function loadServicesForPlace(placeId)
    if placeId == PlaceID then
        requireServices(ServiceDirectory)
    else
        warn("Unrecognized Place ID, no services loaded")
    end
end

-- Load the services for the specified place ID
loadServicesForPlace(game.PlaceId)

-- Start Knit
Knit.Start():andThen(function()
    print("Knit Started on the Server")
end):catch(function(err)
    warn("Error starting Knit:", err)
end)
