local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")
local Knit = require(ReplicatedStorage.Packages.Knit)

local PlaceID = 138778098643510
local ServerServices = ServerStorage.Source.ServerServices

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

local function loadServicesForPlace(placeId)
	if placeId == PlaceID then
		requireServices(ServerServices)
	elseif RunService:IsStudio() then
		warn("Studio detected with PlaceId " .. placeId .. " -- loading ServerServices for testing")
		requireServices(ServerServices)
	else
		warn("Unrecognized Place ID: " .. placeId .. ", no services loaded")
		return
	end
end

loadServicesForPlace(game.PlaceId)

Knit.Start():andThen(function()
	print("Knit Started on the Server")
end):catch(function(err)
	warn("Error starting Knit:", err)
end)
