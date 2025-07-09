local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")
local StarterPlayerScripts = StarterPlayer.StarterPlayerScripts
local Knit = require(ReplicatedStorage.Packages.Knit)

-- Define the Place IDs for different game environments
local DungeonPlaceID = 17399051565
local HubWorldServiceID = 17399041158

-- References to controller directories
local ClientControllers = StarterPlayerScripts.Source.ClientControllers
local HubWorldControllers = ClientControllers.HubWorldControllers
local DungeonControllers = ClientControllers.DungeonControllers.ProcGenControllers_v3
local ProcGenControllers = DungeonControllers

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

-- Function to require controllers based on the place id
local function loadControllersForPlace(placeId)
    local controllerDirectory
    if placeId == HubWorldServiceID then
        controllerDirectory = HubWorldControllers
        print(controllerDirectory)
    elseif placeId == DungeonPlaceID then
        controllerDirectory = ProcGenControllers
        print(controllerDirectory)
    else
        warn("Unrecognized Place ID, no controllers loaded")
        return
    end

    requireControllers(controllerDirectory)
end

-- Load the controllers appropriate for the current game's place ID
loadControllersForPlace(game.PlaceId)

-- Start Knit
Knit.Start():andThen(function()
    print("Knit Started on the Client")
end):catch(function(err)
    warn("Error starting Knit: ", err)
end)
