-- ReplicatedStorage.Source.Components.FlagSpawn
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Packages = ReplicatedStorage:WaitForChild("Packages")
local Knit = require(Packages.Knit)
local Component = require(Packages.Component)

local FlagSpawn = Component.new({
    Tag = "FlagSpawn",
    Ancestors = {workspace.FlagSpawns},
})

function FlagSpawn:Construct()
    self.Team = self.Instance:GetAttribute("Team")
    assert(self.Instance.PrimaryPart, "FlagSpawn Model must have PrimaryPart.")
    self.SpawnCFrame = self.Instance.PrimaryPart.CFrame
end

function FlagSpawn:Start()
    local FlagService = Knit.GetService("FlagService")
    FlagService:RegisterSpawn(self.Team, self.SpawnCFrame)

    -- ✅ Listen for when flags spawn and disable the ProximityPrompt
    FlagService.Client.FlagsSpawned:Connect(function(flagClones)
        warn(flagClones)
        self:DisableOwnFlagPrompt(flagClones)
    end)
end

function FlagSpawn:DisableOwnFlagPrompt(flagClones)
    local player = game.Players.LocalPlayer
    local playerTeam = player.Team and player.Team.Name or nil

    if not playerTeam or self.Team ~= playerTeam then
        return
    end

    -- ✅ Get the player's own flag clone
    local ownFlag = flagClones[self.Team]

    if ownFlag then
        local promptLoc = ownFlag:FindFirstChild("PromptLoc")
        if promptLoc then
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

function FlagSpawn:Stop()
    local FlagService = Knit.GetService("FlagService")
    FlagService:UnregisterSpawn(self.Team, self.SpawnCFrame)
end

return FlagSpawn
