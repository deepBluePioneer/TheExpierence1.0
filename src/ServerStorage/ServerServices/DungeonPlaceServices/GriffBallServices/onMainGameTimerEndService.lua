local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CustomPackages = ReplicatedStorage.CustomPackages
local Packages = ReplicatedStorage.Packages
local Knit = require(Packages.Knit)

local onMainGameTimerEndService = Knit.CreateService {
    Name = "onMainGameTimerEndService",
    Client = {},
}

function onMainGameTimerEndService:KnitStart()
    local GameManagerService = Knit.GetService("GameManagerService")
    
    GameManagerService.OnGameTimerEnd:Connect(function()
        print("[onMainGameTimerEndService] Main game timer ended! Signal received.")
    end)
end

function onMainGameTimerEndService:KnitInit()
    -- Optional init logic
end

return onMainGameTimerEndService
