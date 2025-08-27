-- Server/Services/GravityHammerService.lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local Knit = require(ReplicatedStorage.Packages.Knit)

local GravityHammerService = Knit.CreateService {
	Name = "GravityHammerService",
	Client = {
		UseHammer = Knit.CreateSignal(), -- Signal from client
	},
}

function GravityHammerService:KnitInit()
	self.Client.UseHammer:Connect(function(player)
		warn(`[GravityHammerService] {player.Name} used the hammer!`)
		-- Do server-side effects here, like shockwaves or damage
	end)
end

function GravityHammerService:KnitStart()
	Players.PlayerAdded:Connect(function(player)
		player.CharacterAdded:Connect(function(character)
			task.wait(1) -- wait for Backpack to exist

			local backpack = player:FindFirstChild("Backpack")
			if not backpack then return end

			local tool = ReplicatedStorage:WaitForChild("Tools"):FindFirstChild("GravityHammer")
			if tool and not backpack:FindFirstChild(tool.Name) then
				local clonedTool = tool:Clone()
				clonedTool.Parent = backpack
			end
		end)
	end)
end

return GravityHammerService
