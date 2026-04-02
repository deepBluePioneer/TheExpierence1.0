local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Packages = ReplicatedStorage.Packages
local Knit = require(Packages.Knit)

local LocalPlayer = Players.LocalPlayer

local CavesTestController = Knit.CreateController {
	Name = "CavesTestController",
}

function CavesTestController:KnitInit() end

function CavesTestController:KnitStart()
	self._terrainService = Knit.GetService("CavesTerrainService")

	self:_teleportToSpawn()

	local camera = Workspace.CurrentCamera
	camera.CameraType = Enum.CameraType.Custom
	local character = LocalPlayer.Character
	if character then
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			camera.CameraSubject = humanoid
		end
	end

	print("[CavesTestController] Hello World from Caves Client!")
end

function CavesTestController:_teleportToSpawn()
	local spawnPos = self._terrainService:GetSpawnPosition():expect()
	if not spawnPos then return end

	local character = LocalPlayer.Character
	if not character then
		character = LocalPlayer.CharacterAdded:Wait()
	end

	local hrp = character:WaitForChild("HumanoidRootPart", 10)
	if hrp then
		hrp.CFrame = CFrame.new(spawnPos + Vector3.new(0, 5, 0))
	end
end

return CavesTestController
