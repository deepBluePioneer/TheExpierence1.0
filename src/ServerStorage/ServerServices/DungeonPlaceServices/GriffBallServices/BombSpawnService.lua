local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local CollectionService = game:GetService("CollectionService")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local CustomPackages = ReplicatedStorage:WaitForChild("CustomPackages")
local Knit = require(Packages.Knit)
local Signal = require(Packages.Signal)

local Prefabs = ReplicatedStorage:WaitForChild("Prefabs")

local BombSpawnService = Knit.CreateService {
	Name = "BombSpawnService",
	Client = {},
	BombSpawned = Signal.new(),     -- Fires when the bomb spawns
	BombPickedUp = Signal.new(),    -- Fires when a player picks it up
	BombDestroyed = Signal.new(),   -- 🆕 Fires when the bomb is destroyed
}

-- Internal state
BombSpawnService._currentBomb = nil
BombSpawnService._bombCarrier = nil

-- Spawns the bomb
function BombSpawnService:SpawnBomb()
	self:DestroyBomb()

	local bombModels = CollectionService:GetTagged("bomb")
	local spawnModels = CollectionService:GetTagged("bombSpawn")

	if #bombModels == 0 then
		warn("[BombSpawnService] No models tagged 'bomb'")
		return
	end
	if #spawnModels == 0 then
		warn("[BombSpawnService] No models tagged 'bombSpawn'")
		return
	end

	local bombTemplate = bombModels[1]
	local spawnModel = spawnModels[1]

	if not bombTemplate:IsA("Model") or not spawnModel:IsA("Model") then
		warn("[BombSpawnService] Tagged instances must be Models")
		return
	end
	if not bombTemplate.PrimaryPart or not spawnModel.PrimaryPart then
		warn("[BombSpawnService] Missing PrimaryPart")
		return
	end

	local bombClone = bombTemplate:Clone()
	bombClone:PivotTo(spawnModel.PrimaryPart.CFrame)
	bombClone.Parent = Workspace
	self._currentBomb = bombClone

	-- Insert ProximityPrompt
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "BombPickupPrompt"
	prompt.ActionText = "Pick Up Bomb"
	prompt.ObjectText = "Bomb"
	prompt.RequiresLineOfSight = false
	prompt.MaxActivationDistance = 10
	prompt.HoldDuration = 0.5
	prompt.Parent = bombClone.PrimaryPart

	prompt.Triggered:Connect(function(player)
		print(player.Name .. " picked up the bomb.")

		prompt.Enabled = false

		local char = player.Character
		if not char then return end

		local hand = char:FindFirstChild("RightHand") or char:FindFirstChild("Right Arm")
		if not hand then
			warn("No hand found on character to attach bomb.")
			return
		end

		local offset = CFrame.new(0, -1, 0)
		bombClone:SetPrimaryPartCFrame(hand.CFrame * offset)

		local weld = Instance.new("WeldConstraint")
		weld.Name = "BombWeld"
		weld.Part0 = hand
		weld.Part1 = bombClone.PrimaryPart
		weld.Parent = bombClone.PrimaryPart

		local teamColor = player.TeamColor and player.TeamColor.Name or "Neutral"
		bombClone:SetAttribute("TeamColorName", teamColor)
		print("[BombSpawnService] Bomb assigned to team:", teamColor)

		self._bombCarrier = player

		self.BombPickedUp:Fire(player, bombClone)
	end)

	print("[BombSpawnService] Bomb spawned at", spawnModel.PrimaryPart.Position)
	self.BombSpawned:Fire(bombClone)
end

-- Destroys the current bomb, if any
function BombSpawnService:DestroyBomb()
	if self._currentBomb and self._currentBomb.Parent then
		self._currentBomb:Destroy()
		self._currentBomb = nil
		self._bombCarrier = nil
		print("[BombSpawnService] Bomb destroyed")
		self.BombDestroyed:Fire()
	end
end

function BombSpawnService:KnitStart()
	-- Optional
end

function BombSpawnService:KnitInit()
	local GameManagerService = Knit.GetService("GameManagerService")

	GameManagerService.OnPreGameTimerEnd:Connect(function()
		self:SpawnBomb()
	end)
end

return BombSpawnService
