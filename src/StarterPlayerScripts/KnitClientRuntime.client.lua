local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")
local StarterPlayerScripts = StarterPlayer.StarterPlayerScripts
local Knit = require(ReplicatedStorage.Packages.Knit)
local Level_1PlaceID = 93295390305658
local LobbyPlaceID = 116406282300852
local TestingPlaceID = 111394067928168
local NewGamePlaceID = 110712408304598
local TinyWingsPlaceID = 95282361907606
local TungTungLobbyPlaceID = 126368140107328
local TungTungMainGamePlaceID = 140527591728688
local SnapABrainRotPlaceID = 74172117295119
local ArrowGamePlaceID = 117931712857687
local BrainRotPuzzleLeaguePlaceID = 127615998073512

-- References to controller directories
local ClientControllers = StarterPlayerScripts.Source.ClientControllers
local LobbyControllers = ClientControllers.LobbyControllers
local Level_1Controllers = ClientControllers.Level_1Controllers
local TestingControllers = ClientControllers.TestingControllers
local NewGameControllers = ClientControllers.NewGameControllers
local TinyWingControllers = ClientControllers.TinyWingControllers
local WheresTungTungControllers = ClientControllers.WheresTungTungControllers
local SnapABrainRotControllers = ClientControllers.SnapABrainRotControllers
local ArrowGameControllers = ClientControllers.ArrowGameControllers
local BrainRotPuzzleLeagueControllers = ClientControllers.BrainRotPuzlleLeagueControllers

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
    if placeId == LobbyPlaceID then
        controllerDirectory = LobbyControllers
    elseif placeId == Level_1PlaceID then
        controllerDirectory = Level_1Controllers
    elseif placeId == TestingPlaceID then
        controllerDirectory = TestingControllers
    elseif placeId == NewGamePlaceID then
        controllerDirectory = NewGameControllers
    elseif placeId == TinyWingsPlaceID then
        controllerDirectory = TinyWingControllers
    elseif placeId == TungTungLobbyPlaceID or placeId == TungTungMainGamePlaceID then
        controllerDirectory = WheresTungTungControllers
    elseif placeId == SnapABrainRotPlaceID then
        controllerDirectory = SnapABrainRotControllers
    elseif placeId == BrainRotPuzzleLeaguePlaceID then
        controllerDirectory = BrainRotPuzzleLeagueControllers
    elseif placeId == ArrowGamePlaceID or placeId == 0 then
        -- Also load ArrowGame controllers when place ID is 0 (unpublished Studio testing)
        controllerDirectory = ArrowGameControllers
    else
        warn("Unrecognized Place ID:", placeId, "- no controllers loaded")
        return
    end

    print("[KnitClient] Loading controllers from:", controllerDirectory.Name)
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
