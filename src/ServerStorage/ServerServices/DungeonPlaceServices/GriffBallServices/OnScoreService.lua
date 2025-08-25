local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CustomPackages = ReplicatedStorage.CustomPackages
local Packages = ReplicatedStorage.Packages
local Knit = require(Packages.Knit)

local OnScoreService = Knit.CreateService {
    Name = "OnScoreService",
    Client = {},
}

function OnScoreService:KnitStart()
    local ScoreZonesService = Knit.GetService("ScoreZonesService")
    local BombSpawnService = Knit.GetService("BombSpawnService")
    local OnPreTimeEndService = Knit.GetService("OnPreTimeEndService")
    local GameManagerService = Knit.GetService("GameManagerService") -- Add this

    ScoreZonesService.TeamScored:Connect(function(scoringTeam, goalTeam)
        print(scoringTeam, "scored in", goalTeam, "goal!")

        -- Re-enable the barricades
        OnPreTimeEndService:EnableBarricades()

        -- Restart the pregame phase (reset timer)
        GameManagerService:RestartPreGamePhase()

        -- Respawn the bomb with short delay
        task.delay(1, function()
            BombSpawnService:SpawnBomb()
        end)
    end)
end

function OnScoreService:KnitInit()
    -- Optional init logic
end

return OnScoreService
