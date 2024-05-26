local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CustomPackages = ReplicatedStorage.CustomPackages
local Packages = ReplicatedStorage.Packages
local Knit = require(Packages.Knit)

local PlayerAddedController = CustomPackages.PlayerAddedController
local PlayerAddedFunctions = PlayerAddedController.PlayerAddedFunctions

local PlayerConfigService = Knit.CreateService {
    Name = "PlayerConfigService",
    Client = {},
}

function PlayerConfigService:KnitStart()

    require(PlayerAddedFunctions)(
        function(JoiningPlayer)
            -- Logic for when a player joins
        end,
        function(LeavingPlayer)
            -- Logic for when a player leaves
        end,
        function(Player, Character)
            -- Logic for when a player's character is added
            self:AdjustPlayerSpeed(Character)
        end
    )
    -- Add service startup logic here
end

function PlayerConfigService:KnitInit()
    -- Add service initialization logic here
end

function PlayerConfigService:AdjustPlayerSpeed(Character)
    -- Ensure the character has a Humanoid
    local humanoid = Character:FindFirstChildOfClass("Humanoid")
    if humanoid then
        humanoid.WalkSpeed = 32  -- Adjust the speed value as needed
    end
end

return PlayerConfigService
