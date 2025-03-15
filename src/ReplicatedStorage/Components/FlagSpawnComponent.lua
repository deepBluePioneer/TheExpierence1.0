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
end

function FlagSpawn:Stop()
    local FlagService = Knit.GetService("FlagService")
    FlagService:UnregisterSpawn(self.Team, self.SpawnCFrame)
end

return FlagSpawn
