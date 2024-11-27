local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService") -- Import UserInputService
local CustomPackages = ReplicatedStorage.CustomPackages
local Packages = ReplicatedStorage.Packages
local Knit = require(Packages.Knit)

local MouseController = Knit.CreateController { Name = "MouseController" }

function MouseController:KnitStart()
    -- Hide the mouse cursor
    --UserInputService.MouseIconEnabled = false
end

function MouseController:KnitInit()
    -- Add controller initialization logic here
end

return MouseController
