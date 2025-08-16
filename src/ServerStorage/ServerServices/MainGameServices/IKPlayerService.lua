local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CustomPackages = ReplicatedStorage.CustomPackages
local Packages = ReplicatedStorage.Packages
local Knit = require(Packages.Knit)

local PlayerAddedController = CustomPackages.PlayerAddedController
local PlayerAddedFunctions = PlayerAddedController.PlayerAddedFunctions

local IKPlayerService = Knit.CreateService {
    Name = "IKPlayerService",
    Client = {},
}

function IKPlayerService:KnitStart()
    -- Add service startup logic here
      require(PlayerAddedFunctions)(
        function(JoiningPlayer)
            -- Handle player joining if needed
        end,
        function(LeavingPlayer)
            --self:PlayerLeft(LeavingPlayer)
        end,
        function(Player, Character)
           -- self:HandleCharacterAdded(Player, Character)
        end
    )

end

function IKPlayerService:KnitInit()
    -- Add service initialization logic here
end

return IKPlayerService