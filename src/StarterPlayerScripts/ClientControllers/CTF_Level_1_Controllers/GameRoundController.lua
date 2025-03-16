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

-- Function to update the UI scores display
local function updateScoreDisplay(blueScore, redScore)
    local player = Players.LocalPlayer
    local playerGui = player:FindFirstChild("PlayerGui")
    if not playerGui then return end

    local screenGui = playerGui:FindFirstChild("Chesapeke")
    if screenGui then
        local scoreFrame = screenGui:FindFirstChild("Score")
        if scoreFrame then
            local frame = scoreFrame:FindFirstChild("Frame")
            if frame then
                local scoresFrame = frame:FindFirstChild("Scores")
                if scoresFrame then
                    local blueScoreLabel = scoresFrame:FindFirstChild("BlueScore")
                    local redScoreLabel = scoresFrame:FindFirstChild("RedScore")

                    if blueScoreLabel and blueScoreLabel:IsA("TextLabel") then
                        blueScoreLabel.Text = tostring(blueScore)
                    end

                    if redScoreLabel and redScoreLabel:IsA("TextLabel") then
                        redScoreLabel.Text = tostring(redScore)
                    end
                end
            end
        end
    end
end

function GameRoundController:DisableOwnFlagPrompt(flagClones)
    local player = Players.LocalPlayer
    local playerTeam = player.Team and player.Team.Name or nil

    if not playerTeam then
        warn("Player does not have a team assigned.")
        return
    end

    -- ✅ Get the player's own flag clone
    local ownFlag = flagClones[playerTeam]

    if ownFlag then
        warn("Children of flag for team:", playerTeam)

        -- ✅ Print all children of the flag object
        for _, child in ipairs(ownFlag:GetChildren()) do
            print(" -", child.Name, "(" .. child.ClassName .. ")")
        end

        -- ✅ Find the ProximityPrompt inside the flag object
        local promptLoc = ownFlag:FindFirstChild("PromptLoc")
        warn("Flag Parent:", ownFlag.Parent)

        if promptLoc then
            print("Found PromptLoc:", promptLoc.Name)
            for _, child in ipairs(promptLoc:GetChildren()) do
                print(" - Inside PromptLoc:", child.Name, "(" .. child.ClassName .. ")")
            end

            local proximityPrompt = promptLoc:FindFirstChildOfClass("ProximityPrompt")
            if proximityPrompt then
                proximityPrompt.Enabled = false -- ✅ Disable the prompt
                print("Disabled ProximityPrompt for", playerTeam, "flag.")
            else
                warn("ProximityPrompt missing inside PromptLoc for", playerTeam, "flag.")
            end
        else
            warn("PromptLoc missing in", playerTeam, "flag.")
        end
    else
        warn("No flag found for player's team:", playerTeam)
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

       -- Listen for the FlagGameScore replica for score updates
       ReplicaController.ReplicaOfClassCreated("FlagGameScore", function(score_replica)
        -- Listen for score updates and update UI
        score_replica:ListenToChange({"RedTeamScore"}, function(new_value)
            updateScoreDisplay(score_replica.Data.BlueTeamScore, new_value)
        end)

        score_replica:ListenToChange({"BlueTeamScore"}, function(new_value)
            updateScoreDisplay(new_value, score_replica.Data.RedTeamScore)
        end)
    end)
end

function GameRoundController:KnitStart()
    local FlagService = Knit.GetService("FlagService")

    -- ✅ Listen for FlagsSpawned event and pass received prompt data
    FlagService.FlagsSpawned:Connect(function(promptData)
        self:DisableOwnFlagPrompt(promptData)
    end)
end

return GameRoundController
