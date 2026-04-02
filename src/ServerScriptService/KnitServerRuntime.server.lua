-- Access necessary services and the Knit framework
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")
local Knit = require(ReplicatedStorage.Packages.Knit)

-- Reference to server-side services
local ServerServices = ServerStorage.Source.ServerServices

-- Place IDs
local HubPlaceID = 91627323095607
local CityTrialPlaceID = 107271232251787
local LakelandCareerDayPlaceID = 108316442650035
local ProvingGroundsPlaceID = 83678239321664
local PacManPlaceID = 131551483824515
local CavesPlaceID = 135299039277049
local GraviBowPlaceID = 128815289098570

-- Service directories
local HubServices = ServerServices.HubServices
local CityTrialServices = ServerServices.CityTrialServices
local LakelandCareerDayServices = ServerServices.LakelandCareerDayServices
local EyeOfSauronServices = ServerServices.EyeOfSauronServices
local PacManServices = ServerServices.PacManServices
local CavesServices = ServerServices.CavesServices
local GraviBowServices = ServerServices.GraviBowServices

-- Function to require services recursively
local function requireServices(directory)
	for _, service in ipairs(directory:GetChildren()) do
		if service:IsA("ModuleScript") and service.Name:match("Service$") then
			local ok, err = pcall(require, service)
			if ok then
				print("[KnitServerRuntime] Loaded service: " .. service.Name)
			else
				warn("[KnitServerRuntime] FAILED to load service: " .. service.Name .. " -- " .. tostring(err))
			end
		elseif service:IsA("Folder") then
			requireServices(service)
		end
	end
end

-- Load services based on place ID
local function loadServicesForPlace(placeId)
	if placeId == HubPlaceID then
		requireServices(HubServices)
	elseif placeId == CityTrialPlaceID then
		requireServices(CityTrialServices)
	elseif placeId == LakelandCareerDayPlaceID then
		requireServices(LakelandCareerDayServices)
	elseif placeId == ProvingGroundsPlaceID then
		requireServices(EyeOfSauronServices)
	elseif placeId == PacManPlaceID then
		requireServices(PacManServices)
	elseif placeId == CavesPlaceID then
		requireServices(CavesServices)
	elseif placeId == GraviBowPlaceID then
		requireServices(GraviBowServices)
	elseif RunService:IsStudio() then
		warn("Studio detected with PlaceId " .. placeId .. " -- loading Lakeland Career Day services for testing")
		requireServices(LakelandCareerDayServices)
	else
		warn("Unrecognized Place ID: " .. placeId .. ", no services loaded")
		return
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
