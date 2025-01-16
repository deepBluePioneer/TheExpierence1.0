local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")
local StarterPlayerScripts = StarterPlayer.StarterPlayerScripts
local Knit = require(ReplicatedStorage.Packages.Knit)

-- Define the single Place ID
local PlaceID = 114700333834518 -- Set your Place ID here

-- Specify a single controller directory
local ClientControllers = StarterPlayerScripts.Source.ClientControllers
local ControllerDirectory = ClientControllers.SpaceProtoControllers -- Specify your controller directory here

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

-- Function to load controllers based on the place id
local function loadControllersForPlace(placeId)
    if placeId == PlaceID then
        -- Load the specified controller directory for the Place ID
        print("Loading controllers from: " .. ControllerDirectory.Name)
        requireControllers(ControllerDirectory)
    else
        warn("Unrecognized Place ID, no controllers loaded")
    end
end

-- Load the controllers for the specified place ID
loadControllersForPlace(game.PlaceId)

-- Start Knit
Knit.Start():andThen(function()
    print("Knit Started on the Client")
end):catch(function(err)
    warn("Error starting Knit: ", err)
end)
