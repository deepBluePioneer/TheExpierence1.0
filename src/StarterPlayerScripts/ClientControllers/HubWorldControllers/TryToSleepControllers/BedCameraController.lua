local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CustomPackages = ReplicatedStorage.CustomPackages
local Packages = ReplicatedStorage.Packages
local Knit = require(Packages.Knit)
local Players= game:GetService("Players")

local BedCameraController = Knit.CreateController { Name = "BedCameraController" }
local bedService

function BedCameraController:KnitStart()

    bedService.EnterBed:Connect(function()
        -- Switch to third person
       Players.LocalPlayer.CameraMode = Enum.CameraMode.Classic
         Players.LocalPlayer.CameraMinZoomDistance = 10
         Players.LocalPlayer.CameraMaxZoomDistance = 20
    end)

    bedService.ExitBed:Connect(function()
        -- Return to first person
         Players.LocalPlayer.CameraMode = Enum.CameraMode.LockFirstPerson
         Players.LocalPlayer.CameraMinZoomDistance = 0.5
         Players.LocalPlayer.CameraMaxZoomDistance = 0.5
    end)
end


function BedCameraController:KnitInit()
  bedService = Knit.GetService("BedService")
  warn(bedService)
end

return BedCameraController


