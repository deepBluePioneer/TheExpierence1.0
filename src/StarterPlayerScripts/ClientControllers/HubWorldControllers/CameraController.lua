local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CustomPackages = ReplicatedStorage.CustomPackages
local Packages = ReplicatedStorage.Packages
local Knit = require(Packages.Knit)

local TweenService = game:GetService("TweenService")

local CameraController = Knit.CreateController { Name = "CameraController" }

local function SetCamPosition()
     -- Add controller startup logic here
     local player = game.Players.LocalPlayer
     local camera = workspace.CurrentCamera
     local baseplate = workspace:FindFirstChild("Baseplate")
     
     if baseplate then
         task.wait(3)
         -- Ensure the camera is scriptable
         camera.CameraType = Enum.CameraType.Scriptable
 
         -- Calculate the position and orientation
         local centerPosition = baseplate.Position
         local cameraPosition = centerPosition + Vector3.new(0, 175, 0)  -- 175 units above the baseplate
         local lookAtPosition = centerPosition
         
         -- Create the tween
         local tweenInfo = TweenInfo.new(
             .75, -- Duration
             Enum.EasingStyle.Linear, -- Easing style
             Enum.EasingDirection.Out, -- Easing direction
             0, -- Times to repeat (0 = no repeat)
             false, -- Reverse (false = no reverse)
             0 -- Delay time
         )
         
         local goal = {
             CFrame = CFrame.new(cameraPosition, lookAtPosition)
         }
         
         local tween = TweenService:Create(camera, tweenInfo, goal)
         tween:Play()
 
         -- Lock camera zoom distance
         player.CameraMaxZoomDistance = 50
         player.CameraMinZoomDistance = 50
 
         -- Disable user camera control
         local userInputService = game:GetService("UserInputService")
         userInputService.InputBegan:Connect(function(input, gameProcessedEvent)
             if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
                 gameProcessedEvent = true
             end
         end)
         userInputService.InputChanged:Connect(function(input, gameProcessedEvent)
             if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
                 gameProcessedEvent = true
             end
         end)
     else
         warn("Baseplate not found in the workspace.")
     end
end

function CameraController:KnitStart()
    --SetCamPosition()
end

function CameraController:KnitInit()
    -- Add controller initialization logic here
end

return CameraController
