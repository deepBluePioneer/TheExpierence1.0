-- ServerScriptService.KnitServerInit
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Knit = require(ReplicatedStorage.Packages.Knit)

-- Define Place IDs
local CTF_HubWorld_PlaceID = 73294104737372
local CTF_Level_1_PlaceID = 104252418179975

-- Server-side service directories
local ServerServices = ServerStorage.Source.ServerServices
local ServiceDirectory_1 = ServerServices.CTF_HubWorld_Services
local ServiceDirectory_2 = ServerServices.CTF_Level_1_Services

-- Components directory
local Components = ReplicatedStorage.Source.Components

-- Recursively require services
local function requireServices(directory)
    for _, service in ipairs(directory:GetChildren()) do
        if service:IsA("ModuleScript") and service.Name:match("Service$") then
            require(service)
        elseif service:IsA("Folder") then
            requireServices(service)
        end
    end
end

-- Recursively require components
local function requireComponents(directory)
    for _, component in ipairs(directory:GetChildren()) do
        if component:IsA("ModuleScript") then
            require(component)
        elseif component:IsA("Folder") then
            requireComponents(component)
        end
    end
end

-- Load services based on PlaceId
local function loadServicesForPlace(placeId)
    if placeId == CTF_HubWorld_PlaceID then
        requireServices(ServiceDirectory_1)
    elseif placeId == CTF_Level_1_PlaceID then
        requireServices(ServiceDirectory_2)
    else
        warn("Unrecognized Place ID, no services loaded:", placeId)
    end
end

-- Initialize services and components
loadServicesForPlace(game.PlaceId)
requireComponents(Components)

-- Start Knit and THEN spawn flags after components are fully initialized
Knit.Start():andThen(function()
    print("[Server] Knit Started Successfully with Components.")

   

end):catch(function(err)
    warn("[Server] Error starting Knit:", err)
end)
