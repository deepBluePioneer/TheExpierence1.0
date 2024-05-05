local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Knit = require(ReplicatedStorage.Packages.Knit)
local CustomPackages = ReplicatedStorage.CustomPackages
local PlayerAddedController = CustomPackages.PlayerAddedController
local PlayerAddedFunctions =  PlayerAddedController.PlayerAddedFunctions

local PlayerAddedService = Knit.CreateService {
    Name = "PlayerAddedService",
    Client = {},
}


function PlayerAddedService:KnitStart()


    require(PlayerAddedFunctions)(
        function(JoiningPlayer)
            print("Joining: "..JoiningPlayer.Name)
        
        end,
        function(LeavingPlayer)
            print("LeavingPlayer: "..LeavingPlayer.Name)

        end,
        function(Player, Character)
        
        end
    )
end


function PlayerAddedService:KnitInit()
    
end


return PlayerAddedService
