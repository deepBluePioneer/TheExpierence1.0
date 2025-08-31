local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CustomPackages = ReplicatedStorage.CustomPackages
local Packages = ReplicatedStorage.Packages
local Knit = require(Packages.Knit)

local PlayerConfigController = Knit.CreateController { Name = "PlayerConfigController" }

function PlayerConfigController:KnitStart()

    warn("Init")
    -- Add controller startup logic here
end

function PlayerConfigController:KnitInit()
    -- Add controller initialization logic here
end

return PlayerConfigController