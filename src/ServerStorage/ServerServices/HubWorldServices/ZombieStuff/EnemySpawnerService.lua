local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")

local CustomPackages = ReplicatedStorage:WaitForChild("CustomPackages")
local Packages = ReplicatedStorage:WaitForChild("Packages")
local Knit = require(Packages:WaitForChild("Knit"))
local Prefabs = ReplicatedStorage:WaitForChild("Prefabs")
local Brainrots = Prefabs:WaitForChild("brainrots")
local SoundService = game:GetService("SoundService")
local BreathingGroup = SoundService:WaitForChild("SoundGroup_Breathing")

local EnemySpawnerService = Knit.CreateService {
	Name = "EnemySpawnerService",
	Client = {},
}

-- === CONFIG ===
local SPAWN_INTERVAL = 3 -- seconds
local ENEMY_SPEED = 12
local ENEMY_HEALTH = 50
local ZOMBIE_TAG = "zombie"

local enemies = {}
local floorParts

-- === SOUND LOOP HELPER ===

local function getRandomBreathingSound()
	local sounds = BreathingGroup:GetChildren()
	if #sounds == 0 then return nil end
	return sounds[math.random(1, #sounds)]:Clone()
end

local function startBreathingLoop(part: BasePart)
	local sound = getRandomBreathingSound()
	if not sound then return end

	sound.RollOffMode = Enum.RollOffMode.InverseTapered
	sound.RollOffMinDistance = 10
	sound.RollOffMaxDistance = 500
	sound.Volume = 1
	sound.Looped = false
	sound.Parent = part

	task.spawn(function()
		while part:IsDescendantOf(workspace) do
			local waitBefore = math.random(3, 8)
			task.wait(waitBefore)

			if not sound.IsPlaying then
				sound:Play()
			end

			task.wait(sound.TimeLength or 2)
		end
	end)
end

-- === POSITION HELPERS ===

local function getRandomSpawnPosition()
	local floor = floorParts[math.random(1, #floorParts)]
	local size = floor.Size
	local pos = floor.Position
	return Vector3.new(pos.X, pos.Y + size.Y * 0.5 + 2, pos.Z)
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

local function getRandomBrainrotModel()
	local models = Brainrots:GetChildren()
	if #models == 0 then return nil end
	return models[math.random(1, #models)]:Clone()
end

local function playAnimationIfAvailable(model)
	local controller = model:FindFirstChildOfClass("AnimationController")
	if controller and controller:IsA("AnimationController") then
		local anim = model:FindFirstChildWhichIsA("Animation")
		if anim then
			local track = controller:LoadAnimation(anim)
			track.Looped = true
			track:Play()
		end
	end
end

-- === ENEMY CREATION ===

local function createEnemy()
	local model = getRandomBrainrotModel()
	if not model or not model:IsA("Model") then return end
	if not model.PrimaryPart then
		warn("[EnemySpawnerService] Model missing PrimaryPart:", model.Name)
		return
	end

	local spawnPos = getRandomSpawnPosition()
	model:PivotTo(CFrame.new(spawnPos))
	model.Parent = Workspace

	-- Upright orientation
	do
		local cf = model:GetPivot()
		local pos = cf.Position
		local forward = cf.LookVector
		local flatForward = Vector3.new(forward.X, 0, forward.Z)
		if flatForward.Magnitude < 1e-3 then
			flatForward = Vector3.new(0, 0, -1)
		end
		local uprightCF = CFrame.lookAt(pos, pos + flatForward.Unit, Vector3.yAxis)
		model:PivotTo(uprightCF)
	end

	model:SetAttribute("Health", ENEMY_HEALTH)

	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = false
			d.CanCollide = true
			CollectionService:AddTag(d, ZOMBIE_TAG)
			if d ~= model.PrimaryPart then
				local weld = Instance.new("WeldConstraint")
				weld.Part0 = model.PrimaryPart
				weld.Part1 = d
				weld.Parent = model.PrimaryPart
			end
		end
	end

	-- Lock roll/pitch with AlignOrientation
	local root = model.PrimaryPart
	local attach = Instance.new("Attachment")
	attach.Name = "UprightAttachment"
	attach.Parent = root

	local yaw = select(2, root.CFrame:ToEulerAnglesYXZ())
	local align = Instance.new("AlignOrientation")
	align.Attachment0 = attach
	align.Mode = Enum.OrientationAlignmentMode.OneAttachment
	align.RigidityEnabled = true
	align.Responsiveness = 200
	align.MaxTorque = math.huge
	align.CFrame = CFrame.Angles(0, yaw, 0)
	align.Parent = root

	playAnimationIfAvailable(model)
	startBreathingLoop(model.PrimaryPart)

	table.insert(enemies, model)
end

-- === LIFECYCLE ===

function EnemySpawnerService:KnitStart()
	task.wait(15)
	warn("[EnemySpawnerService] Starting enemy spawns.")
	floorParts = CollectionService:GetTagged("FloorTile")

	task.spawn(function()
		while true do
			createEnemy()
			task.wait(SPAWN_INTERVAL)
		end
	end)

	RunService.Heartbeat:Connect(function(dt)
		for i = #enemies, 1, -1 do
			local enemy = enemies[i]
			if not enemy or not enemy.Parent or not enemy.PrimaryPart then
				table.remove(enemies, i)
				continue
			end

			local root = enemy.PrimaryPart
			local targetPos = getClosestPlayerPosition(root.Position)
			if targetPos then
				local dir = (targetPos - root.Position).Unit
				local vel = dir * ENEMY_SPEED
				root.AssemblyLinearVelocity = Vector3.new(vel.X, root.AssemblyLinearVelocity.Y, vel.Z)

				local flatTarget = Vector3.new(targetPos.X, root.Position.Y, targetPos.Z)
				local faceCF = CFrame.lookAt(root.Position, flatTarget, Vector3.yAxis)

				local align = root:FindFirstChildOfClass("AlignOrientation")
				if align then
					align.CFrame = faceCF
				end
			end
		end
	end)
end

function EnemySpawnerService:KnitInit()
	-- no-op
end

return EnemySpawnerService
