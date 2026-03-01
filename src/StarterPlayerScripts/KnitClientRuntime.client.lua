local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterPlayer = game:GetService("StarterPlayer")
local StarterPlayerScripts = StarterPlayer.StarterPlayerScripts
local Knit = require(ReplicatedStorage.Packages.Knit)

-- Place IDs
local HubPlaceID = 91627323095607
local CityTrialPlaceID = 107271232251787
local LakelandCareerDayPlaceID = 108316442650035

-- Controller directories
local ClientControllers = StarterPlayerScripts.Source.ClientControllers
local HubControllers = ClientControllers.HubControllers
local CityTrialControllers = ClientControllers.CityTrialControllers
local LakelandCareerDayControllers = ClientControllers.LakelandCareerDayControllers

-- Function to require controllers recursively
local function requireControllers(directory)
	for _, controller in ipairs(directory:GetChildren()) do
		if controller:IsA("ModuleScript") and controller.Name:match("Controller$") then
			local ok, err = pcall(require, controller)
			if ok then
				print("[KnitClientRuntime] Loaded controller: " .. controller.Name)
			else
				warn("[KnitClientRuntime] FAILED to load controller: " .. controller.Name .. " -- " .. tostring(err))
			end
		elseif controller:IsA("Folder") then
			requireControllers(controller)
		end
	end
end

-- Load controllers based on place ID
local function loadControllersForPlace(placeId)
	if placeId == HubPlaceID then
		requireControllers(HubControllers)
	elseif placeId == CityTrialPlaceID then
		requireControllers(CityTrialControllers)
	elseif placeId == LakelandCareerDayPlaceID then
		requireControllers(LakelandCareerDayControllers)
	elseif RunService:IsStudio() then
		warn("Studio detected with PlaceId " .. placeId .. " -- loading Lakeland Career Day controllers for testing")
		requireControllers(LakelandCareerDayControllers)
	else
		warn("Unrecognized Place ID: " .. placeId .. ", no controllers loaded")
		return
	end
end

-- Load the controllers appropriate for the current game's place ID
loadControllersForPlace(game.PlaceId)

-- Start Knit
Knit.Start():andThen(function()
	print("Knit Started on the Client")
end):catch(function(err)
	warn("Error starting Knit: ", err)
end)
