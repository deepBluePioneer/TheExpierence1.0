local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Packages = ReplicatedStorage:WaitForChild("Packages")
local Knit = require(Packages.Knit)

local BombPickupService = Knit.CreateService {
	Name = "BombPickupService",
	Client = {},
}


function BombPickupService:KnitInit()
	local BombSpawnService = Knit.GetService("BombSpawnService")

	BombSpawnService.BombSpawned:Connect(function(bombModel)
		print("[BombPickupService] Bomb spawned:", bombModel)
		-- Add .Touched or ProximityPrompt logic here
	end)

    BombSpawnService.BombPickedUp:Connect(function(player, bombModel)
		print("[BombPickupService] Bomb picked up by", player.Name)
	end)
end

function BombPickupService:KnitStart()

    
  


end

return BombPickupService
