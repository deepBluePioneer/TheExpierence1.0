local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterPlayer = game:GetService("StarterPlayer")
local StarterPlayerScripts = StarterPlayer.StarterPlayerScripts
local Knit = require(ReplicatedStorage.Packages.Knit)

local PlaceID = 138778098643510
local ClientControllers = StarterPlayerScripts.Source.ClientControllers

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

local function loadControllersForPlace(placeId)
	if placeId == PlaceID then
		requireControllers(ClientControllers)
	elseif RunService:IsStudio() then
		warn("Studio detected with PlaceId " .. placeId .. " -- loading ClientControllers for testing")
		requireControllers(ClientControllers)
	else
		warn("Unrecognized Place ID: " .. placeId .. ", no controllers loaded")
		return
	end
end

loadControllersForPlace(game.PlaceId)

Knit.Start():andThen(function()
	print("Knit Started on the Client")
end):catch(function(err)
	warn("Error starting Knit: ", err)
end)
