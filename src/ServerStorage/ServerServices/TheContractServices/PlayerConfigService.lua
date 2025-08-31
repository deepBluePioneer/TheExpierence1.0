-- Server/Services/PlayerConfigService.lua

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Packages = ReplicatedStorage:WaitForChild("Packages")
local Knit = require(Packages:WaitForChild("Knit"))

local PlayerConfigService = Knit.CreateService {
    Name = "PlayerConfigService",
    Client = {},
}

-- Setup player camera settings to first-person only
local function setupFirstPerson(player: Player)
    player.CameraMode = Enum.CameraMode.LockFirstPerson
    player.CharacterAdded:Connect(function(character)
        local humanoid = character:WaitForChild("Humanoid", 5)
        if humanoid then
            -- Optional: enforce again when respawning
            player.CameraMode = Enum.CameraMode.LockFirstPerson
        end
    end)
end

function PlayerConfigService:KnitInit()
    -- Handle existing players
    for _, player in ipairs(Players:GetPlayers()) do
        setupFirstPerson(player)
    end

    -- Handle future players
    Players.PlayerAdded:Connect(setupFirstPerson)
end

function PlayerConfigService:KnitStart()
    -- Nothing needed here for now
end

return PlayerConfigService
