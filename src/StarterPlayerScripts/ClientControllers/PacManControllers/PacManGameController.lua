local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local Packages = ReplicatedStorage.Packages
local Knit = require(Packages.Knit)
local Trove = require(Packages.Trove)
local Signal = require(Packages.Signal)

local LocalPlayer = Players.LocalPlayer

local PacManGameController = Knit.CreateController({
	Name = "PacManGameController",

	GameStateChanged = Signal.new(),

	_trove = nil,
})

function PacManGameController:KnitInit()
	self._trove = Trove.new()
end

function PacManGameController:KnitStart()
	self._dataService = Knit.GetService("PacManDataService")
	self._mazeService = Knit.GetService("PacManMazeService")

	self:_waitForMaze()
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

	print("[PacManGameController] Started")
end

function PacManGameController:_waitForMaze()
	local mazeFolder = Workspace:FindFirstChild("PacManMaze")
	if mazeFolder then return end

	local tries = 0
	while not Workspace:FindFirstChild("PacManMaze") and tries < 100 do
		task.wait(0.1)
		tries += 1
	end
end

function PacManGameController:_teleportToSpawn()
	local spawnPos = self._mazeService:GetSpawnPosition():expect()
	if not spawnPos then return end

	local character = LocalPlayer.Character
	if not character then
		character = LocalPlayer.CharacterAdded:Wait()
	end

	local hrp = character:WaitForChild("HumanoidRootPart", 10)
	if hrp then
		hrp.CFrame = CFrame.new(spawnPos)
	end
end

return PacManGameController
