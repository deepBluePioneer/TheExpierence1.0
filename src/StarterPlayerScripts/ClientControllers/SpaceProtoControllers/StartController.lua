local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CustomPackages = ReplicatedStorage.CustomPackages
local Packages = ReplicatedStorage.Packages
local Knit = require(Packages.Knit)

local StartController = Knit.CreateController { Name = "StartController" }

function StartController:KnitStart()
    -- Add controller startup logic here
end

function StartController:KnitInit()

    print("HEELoo")

    -- Add controller initialization logic here
end

return StartController