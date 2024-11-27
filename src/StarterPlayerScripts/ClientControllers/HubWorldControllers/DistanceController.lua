local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players") -- Service to get the local player
local Knit = require(ReplicatedStorage.Packages.Knit)
local TweenService = game:GetService("TweenService") -- Service for tweening

local DistanceController = Knit.CreateController { Name = "DistanceController" }

-- Variables to track player position and distance
local LocalPlayer = Players.LocalPlayer
local spawnPosition = nil
local totalDistance = 0

function DistanceController:KnitStart()
    -- Ensure the LocalPlayer and their character exist
    if LocalPlayer and LocalPlayer.Character then
        -- Get the spawn position from the Character's initial position (HumanoidRootPart)
        local humanoidRootPart = LocalPlayer.Character:WaitForChild("HumanoidRootPart")
        spawnPosition = humanoidRootPart.Position  -- Set the spawn point as the initial position

        local playerGui = LocalPlayer:WaitForChild("PlayerGui") -- Access PlayerGui
        
        -- Locate the ScreenGui and its child elements
        local screenGui = playerGui:WaitForChild("ScreenGui")
        local frame = screenGui:WaitForChild("DistanceFrame")
        local textLabel = frame:WaitForChild("TextLabel")

        -- Tween settings for text transparency and text update
        local tweenInfo = TweenInfo.new(0.1, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1, false) -- Smooth transition

        -- Track distance traveled from the spawn point
        game:GetService("RunService").RenderStepped:Connect(function()
            local currentPosition = humanoidRootPart.Position
            if spawnPosition then
                local distanceFromSpawn = (currentPosition - spawnPosition).Magnitude
                totalDistance = distanceFromSpawn

                -- Create a tween to smoothly transition the text
                local targetText = string.format("%.2f m", totalDistance / 100)  -- Convert to 100 meters

                -- Tween the text transparency first
                local tween = TweenService:Create(textLabel, tweenInfo, {TextTransparency = 1})
                tween:Play()

                tween.Completed:Connect(function()
                    -- After transparency tween, change the text and reset transparency
                    textLabel.Text = targetText
                    local resetTween = TweenService:Create(textLabel, tweenInfo, {TextTransparency = 0})
                    resetTween:Play()
                end)
            end
        end)
    end
end

function DistanceController:KnitInit()
    -- Add controller initialization logic here
end

return DistanceController
