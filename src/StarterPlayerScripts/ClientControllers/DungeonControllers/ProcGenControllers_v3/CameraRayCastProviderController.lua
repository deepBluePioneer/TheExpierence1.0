local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CustomPackages = ReplicatedStorage.CustomPackages
local Packages = ReplicatedStorage.Packages
local Mouse = require(Packages.Input).Mouse
local Knit = require(Packages.Knit)

local CameraRayCastProviderController = Knit.CreateController { Name = "CameraRayCastProviderController" }



function CameraRayCastProviderController:KnitStart()
    local WeaponsService = Knit.GetService("WeaponsService")

    local mouse = Mouse.new()
    mouse:LockCenter()

    mouse.LeftDown:Connect(function(player)
        local ray = Mouse:GetRay()
        WeaponsService.SendRay(player, ray)

    end)
    -- Store the mouse object for later use if needed
    self.mouse = mouse

end


function CameraRayCastProviderController:KnitInit()
    -- Add controller initialization logic here
end

return CameraRayCastProviderController