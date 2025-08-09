local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CustomPackages = ReplicatedStorage.CustomPackages
local Packages = ReplicatedStorage.Packages
local Knit = require(Packages.Knit)

-- Load the iris module
local Packages = ReplicatedStorage.Packages
local Iris = require(Packages.iris)


local IrisController = Knit.CreateController { Name = "IrisController" }

function IrisController:KnitStart()
    -- Add controller startup logic here
end

function IrisController:KnitInit()
    -- Add controller initialization logic here
end

return IrisController