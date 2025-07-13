local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CustomPackages = ReplicatedStorage.CustomPackages
local Packages = ReplicatedStorage.Packages
local Knit = require(Packages.Knit)
local CollectionService = game:GetService("CollectionService")

local PatchLookController = Knit.CreateController { Name = "PatchLookController" }

function PatchLookController:KnitStart()
	task.wait(10)
    warn("looking")

	local Players = game:GetService("Players")
	local LocalPlayer = Players.LocalPlayer
	local Camera = workspace.CurrentCamera
	local RunService = game:GetService("RunService")

	local patches = CollectionService:GetTagged("powerupPatch")

	RunService.RenderStepped:Connect(function()
		for _, patch in ipairs(patches) do
			if not patch:IsA("BasePart") then continue end

			local patchPos = patch.Position
			local camPos = Camera.CFrame.Position

			-- Only use X and Z of camera, keep Y of patch
			local flatLook = Vector3.new(camPos.X, patchPos.Y, camPos.Z)

			patch.CFrame = CFrame.new(patchPos, flatLook)
		end
	end)
end



function PatchLookController:KnitInit()
    -- Add controller initialization logic here
end

return PatchLookController