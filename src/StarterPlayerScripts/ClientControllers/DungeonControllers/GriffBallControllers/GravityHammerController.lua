local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CustomPackages = ReplicatedStorage.CustomPackages
local Packages = ReplicatedStorage.Packages
local Knit = require(Packages.Knit)
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local GravityHammerController = Knit.CreateController { Name = "GravityHammerController" }

function GravityHammerController:KnitStart()
	local GravityHammerService = Knit.GetService("GravityHammerService")
	local player = Players.LocalPlayer
	local backpack = player:WaitForChild("Backpack")

	-- Listen for LMB clicks
	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed then return end -- Ignore if UI is focused

		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			-- Optional: check if player has the hammer equipped
			local character = player.Character
			if character then
				local tool = character:FindFirstChildOfClass("Tool")
				if tool and tool.Name == "GravityHammer" then
					print("Left mouse clicked while holding GravityHammer")
					GravityHammerService.UseHammer:Fire()
				end
			end
		end
	end)
end

function GravityHammerController:KnitInit()
	-- Optional init logic
end

return GravityHammerController
