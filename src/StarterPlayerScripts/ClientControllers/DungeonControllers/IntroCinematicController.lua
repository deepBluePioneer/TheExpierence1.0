local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CustomPackages = ReplicatedStorage.CustomPackages
local Packages = ReplicatedStorage.Packages
local Knit = require(Packages.Knit)

local IntroCinematicController = Knit.CreateController { Name = "IntroCinematicController" }

--Start intro camera cinematic before race and during setup and initialize anything

function IntroCinematicController:KnitStart()
    -- Add controller startup logic here
end

function IntroCinematicController:KnitInit()
    -- Add controller initialization logic here
end

return IntroCinematicController