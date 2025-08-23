-- ServerScriptService/Services/BombService.lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Packages = ReplicatedStorage:WaitForChild("Packages")
local Knit = require(Packages.Knit)

local BombService = Knit.CreateService{
    Name = "BombService",
    Client = {}, -- must exist so clients can GetService + call methods
}

-- Client-callable method lives on the Client table:
function BombService.Client:OnSpace(player: Player)
    print(("Space pressed by %s"):format(player.Name))
end

return BombService
