local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
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

	self:_startPelletBob()
	self:_startLightFlicker()

	print("[PacManGameController] Started")
end

local BOB_SPEED = 3
local BOB_AMPLITUDE = 1.2
local SPIN_SPEED = 2

local FLICKER_RANGE = 80
local FLICKER_MIN_BRIGHTNESS = 0.1
local FLICKER_SPEED = 20
local NORMAL_BRIGHTNESS = 3

function PacManGameController:_startPelletBob()
	local basePositions = {}

	self._trove:Add(RunService.RenderStepped:Connect(function()
		local t = os.clock()
		for _, pellet in ipairs(CollectionService:GetTagged("PacManPellet")) do
			if not basePositions[pellet] then
				basePositions[pellet] = pellet.Position
			end

			local base = basePositions[pellet]
			local offset = math.sin(t * BOB_SPEED + base.X * 0.5 + base.Z * 0.3) * BOB_AMPLITUDE
			local spin = t * SPIN_SPEED + base.X * 0.2
			pellet.CFrame = CFrame.new(base.X, base.Y + offset, base.Z) * CFrame.Angles(0, spin, 0)
		end
	end), "Disconnect")
end

function PacManGameController:_startLightFlicker()
	local mazeFolder = Workspace:WaitForChild("PacManMaze", 15)
	if not mazeFolder then return end
	local lightFolder = mazeFolder:WaitForChild("Lights", 5)
	if not lightFolder then return end

	self._trove:Add(RunService.Heartbeat:Connect(function()
		local t = os.clock()
		local pacmanPositions = {}

		for _, child in ipairs(Workspace:GetChildren()) do
			if not child.Name:match("^PacMan_") then continue end
			local anchor = child:FindFirstChildWhichIsA("BasePart", true)
			if anchor then
				table.insert(pacmanPositions, anchor.Position)
			end
		end

		if #pacmanPositions == 0 then return end

		for _, bulb in ipairs(lightFolder:GetChildren()) do
			local light = bulb:FindFirstChildOfClass("PointLight")
			if not light then continue end

			local closestDist = math.huge
			for _, pacPos in ipairs(pacmanPositions) do
				local dist = (bulb.Position - pacPos).Magnitude
				if dist < closestDist then
					closestDist = dist
				end
			end

			if closestDist < FLICKER_RANGE then
				local intensity = 1 - math.clamp(closestDist / FLICKER_RANGE, 0, 1)
				local flicker = math.sin(t * FLICKER_SPEED + bulb.Position.X * 3.7) *
					math.cos(t * FLICKER_SPEED * 0.7 + bulb.Position.Z * 2.3)
				local flickerAmount = intensity * (0.5 + 0.5 * flicker)
				local brightness = NORMAL_BRIGHTNESS * (1 - flickerAmount * 0.85)
				brightness = math.max(brightness, FLICKER_MIN_BRIGHTNESS)

				light.Brightness = brightness
				bulb.Transparency = 1 - (brightness / NORMAL_BRIGHTNESS) * 0.7
			else
				light.Brightness = NORMAL_BRIGHTNESS
				bulb.Transparency = 0
			end
		end
	end), "Disconnect")
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
