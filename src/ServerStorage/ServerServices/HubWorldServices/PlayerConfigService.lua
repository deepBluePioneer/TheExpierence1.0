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
            -- Handle player joining if needed
        end,
        function(LeavingPlayer)
            --self:PlayerLeft(LeavingPlayer)
        end,
        function(Player, Character)
            self:HandleCharacterAdded(Player, Character)
        end
    )

    -- Add service startup logic here
end

function PlayerConfigService:KnitInit()
    -- Add service initialization logic here
end

function PlayerConfigService:HandleCharacterAdded(Player, Character)
    -- Set the player's walk speed to a faster value
    local humanoid = Character:FindFirstChildOfClass("Humanoid")
    if humanoid then
        humanoid.WalkSpeed = 45 -- Default is 16, change to desired speed
    end
end

return PlayerConfigService
