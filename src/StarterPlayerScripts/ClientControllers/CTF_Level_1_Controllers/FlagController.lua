-- ReplicatedStorage.Source.Controllers.FlagController
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local Packages = ReplicatedStorage:WaitForChild("Packages")
local Knit = require(Packages.Knit)
local CustomPackages = ReplicatedStorage.CustomPackages
local Replica = CustomPackages:WaitForChild("Replica")
local ReplicaController = require(Replica:WaitForChild("ReplicaController"))

local FlagController = Knit.CreateController {
    Name = "FlagController",
}

local function updateFlagLabel(flagModel, localPlayerTeam)
    local flagTeam = flagModel:GetAttribute("FlagColor")
    local waypoint = flagModel:FindFirstChild("waypoint")
    if not waypoint then return end

    local billboardGui = waypoint:FindFirstChildOfClass("BillboardGui")
    if not billboardGui then return end

    local frame = billboardGui:FindFirstChildOfClass("Frame")
    if not frame then return end

    local textLabel = frame:FindFirstChild("1")
    if not textLabel or not textLabel:IsA("TextLabel") then return end

    if localPlayerTeam == flagTeam then
        textLabel.Text = "DEFEND"
        textLabel.TextColor3 = Color3.new(0,1,0) -- Green for Defend
    else
        textLabel.Text = "TAKE"
        textLabel.TextColor3 = Color3.new(1,0,0) -- Red for Take
    end
end

function FlagController:UpdateAllFlagLabels()
    local localPlayerTeam = Players.LocalPlayer.Team.Name

    for _, flagModel in ipairs(CollectionService:GetTagged("Flag")) do
        updateFlagLabel(flagModel, localPlayerTeam)
    end
end

function FlagController:KnitStart()


    -- Initial update when player joins or team changes
    if Players.LocalPlayer.Team then
        self:UpdateAllFlagLabels()
    end

    -- Update flags whenever player's team changes
    Players.LocalPlayer:GetPropertyChangedSignal("Team"):Connect(function()
        self:UpdateAllFlagLabels()
    end)

    -- Update flags whenever a new flag is added to workspace
    CollectionService:GetInstanceAddedSignal("Flag"):Connect(function(flagModel)
        updateFlagLabel(flagModel, Players.LocalPlayer.Team.Name)
    end)
end

return FlagController
