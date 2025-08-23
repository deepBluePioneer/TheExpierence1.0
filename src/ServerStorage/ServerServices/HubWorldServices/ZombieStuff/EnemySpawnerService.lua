-- Server/Services/EnemySpawnerService.lua

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")

local CustomPackages = ReplicatedStorage:WaitForChild("CustomPackages")
local Packages = ReplicatedStorage:WaitForChild("Packages")
local Knit = require(Packages:WaitForChild("Knit"))

local EnemySpawnerService = Knit.CreateService {
	Name = "EnemySpawnerService",
	Client = {},
}

-- === CONFIG ===
local BASEPLATE = Workspace:FindFirstChild("Baseplate")
local ENEMY_SIZE = Vector3.new(2, 5, 2)
local SPAWN_INTERVAL = 3 -- seconds
local ENEMY_SPEED = 12
local ENEMY_HEALTH = 50
local ZOMBIE_TAG = "zombie"

local enemies = {}

local function getRandomSpawnPosition()
	if not BASEPLATE then return Vector3.new(0, 5, 0) end
	local size = BASEPLATE.Size
	local pos = BASEPLATE.Position
	local x = math.random(-size.X / 2, size.X / 2)
	local z = math.random(-size.Z / 2, size.Z / 2)
	return Vector3.new(pos.X + x, pos.Y + 5, pos.Z + z)
end

local function getClosestPlayerPosition(enemyPos)
	local closestDist = math.huge
	local closestPos = nil
	for _, player in ipairs(Players:GetPlayers()) do
		local char = player.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		if hrp then
			local dist = (enemyPos - hrp.Position).Magnitude
			if dist < closestDist then
				closestDist = dist
				closestPos = hrp.Position
			end
		end
	end
	return closestPos
end

local function createEnemy()
	local part = Instance.new("Part")
	part.Size = ENEMY_SIZE
	part.Anchored = false
	part.CanCollide = true
	part.BrickColor = BrickColor.Red()
	part.Position = getRandomSpawnPosition()
	part.Name = "Zombie"

	-- Health as an attribute so other systems can modify it
	part:SetAttribute("Health", ENEMY_HEALTH)

	-- Tag it as a zombie so weapons can detect hits
	CollectionService:AddTag(part, ZOMBIE_TAG)

	part.Parent = Workspace
	table.insert(enemies, part)
end

function EnemySpawnerService:KnitStart()
	task.spawn(function()
		while true do
			createEnemy()
			task.wait(SPAWN_INTERVAL)
		end
	end)

	RunService.Heartbeat:Connect(function(dt)
		for i = #enemies, 1, -1 do
			local enemy = enemies[i]
			if not enemy or not enemy.Parent then
				table.remove(enemies, i)
				continue
			end
			local targetPos = getClosestPlayerPosition(enemy.Position)
			if targetPos then
				local dir = (targetPos - enemy.Position).Unit
				local vel = dir * ENEMY_SPEED
				enemy.AssemblyLinearVelocity = Vector3.new(vel.X, enemy.AssemblyLinearVelocity.Y, vel.Z)
			end
		end
	end)
end

function EnemySpawnerService:KnitInit() end

return EnemySpawnerService
