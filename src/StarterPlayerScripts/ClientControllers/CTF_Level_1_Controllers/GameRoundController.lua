local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CustomPackages = ReplicatedStorage.CustomPackages
local Packages = ReplicatedStorage.Packages
local Knit = require(Packages.Knit)

local Replica = CustomPackages:WaitForChild("Replica")
local ReplicaController = require(Replica:WaitForChild("ReplicaController"))

local GameRoundController = Knit.CreateController { Name = "GameRoundController" }

-- Function to update the UI timer display
local function updateTimerDisplay(formattedTime)
    local player = Players.LocalPlayer
    local playerGui = player:FindFirstChild("PlayerGui")
    if not playerGui then return end

    local screenGui = playerGui:FindFirstChild("ScreenGui")
    if screenGui then
        local frame = screenGui:FindFirstChild("Frame")
        if frame then
            local txtTime = frame:FindFirstChild("txt_time")
            if txtTime and txtTime:IsA("TextLabel") then
                txtTime.Text = formattedTime
            end
        end
    end
end

function GameRoundController:KnitInit()
    ReplicaController.RequestData() -- Ensures data is requested once

    -- Listen for the GameTimerReplica when it's created
    ReplicaController.ReplicaOfClassCreated("GameTimerReplica", function(timer_replica)
        -- Listen for TimeRemaining updates and update UI
        timer_replica:ListenToChange({"FormattedTime"}, function(new_value)
            updateTimerDisplay(new_value)
        end)
    end)
end

return GameRoundController
