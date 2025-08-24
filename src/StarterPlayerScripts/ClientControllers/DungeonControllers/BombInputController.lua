-- StarterPlayerScripts/Controllers/BombInputController.lua
local ContextActionService = game:GetService("ContextActionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Packages = ReplicatedStorage:WaitForChild("Packages")
local Knit = require(Packages.Knit)

local BombInputController = Knit.CreateController { Name = "BombInputController" }

function init()
     local BombService = Knit.GetService("BombService")

    ContextActionService:BindAction(
        "Bomb_Space",
        function(_, state)
            if state == Enum.UserInputState.Begin then
                BombService:OnSpace() -- hits BombService.Client:OnSpace on server
                return Enum.ContextActionResult.Sink
            end
            return Enum.ContextActionResult.Pass
        end,
        false,
        Enum.KeyCode.Space
    )
end

function BombInputController:KnitStart()
   
end

return BombInputController
