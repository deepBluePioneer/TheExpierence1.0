local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")
local StarterPlayerScripts = StarterPlayer.StarterPlayerScripts
local Knit = require(ReplicatedStorage.Packages.Knit)

-- Define Place IDs
local CTF_HubWorld_PlaceID = 73294104737372
local CTF_Level_1_PlaceID = 104252418179975

-- Specify controller directories
local ClientControllers = StarterPlayerScripts.Source.ClientControllers
local ControllerDirectory_1 = ClientControllers.CTF_HubWorld_Controllers
local ControllerDirectory_2 = ClientControllers.CTF_Level_1_Controllers

-- Function to require controllers recursively
local function requireControllers(directory)
    for _, controller in ipairs(directory:GetChildren()) do
        if controller:IsA("ModuleScript") and controller.Name:match("Controller$") then
            require(controller)
        elseif controller:IsA("Folder") then
            requireControllers(controller)
        end
    end
end

-- Function to load controllers based on the current Place ID
local function loadControllersForPlace(placeId)
    if placeId == CTF_HubWorld_PlaceID then
        requireControllers(ControllerDirectory_1)
    elseif placeId == CTF_Level_1_PlaceID then
        requireControllers(ControllerDirectory_2)
    else
        warn("Unrecognized Place ID, no controllers loaded: ", placeId)
    end
end

-- Load controllers for the current Place ID
loadControllersForPlace(game.PlaceId)

-- Start Knit
Knit.Start():andThen(function()
    print("Knit Started on the Client")
end):catch(function(err)
    warn("Error starting Knit: ", err)
end)
