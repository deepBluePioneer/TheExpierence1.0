-- Server/Services/ScoreZonesService.lua

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local CustomPackages = ReplicatedStorage:WaitForChild("CustomPackages")
local Knit = require(Packages:WaitForChild("Knit"))
local ZoneRoot = CustomPackages:WaitForChild("ZoneRoot")
local Zone = require(ZoneRoot:WaitForChild("Zone"))
local Signal = require(Packages:WaitForChild("Signal"))

local ScoreZonesService = Knit.CreateService {
	Name = "ScoreZonesService",
	Client = {},
	TeamScored = Signal.new(), -- Fires when a valid score occurs: (scoringTeamName, goalTeamName)
}

-- === Internal State ===
-- === Internal State ===
local BombSpawnService = nil
local TeamAssignerService = nil
local currentBomb = nil
local goalZones = {} -- [goalName] = Zone instance


-- Helper: track the current bomb's PrimaryPart in all zones
local function trackBombInAllZones()
	if not currentBomb or not currentBomb.PrimaryPart then
		return
	end
	for _, zone in pairs(goalZones) do
		-- Safe to call multiple times; ZonePlus will handle duplicate tracking gracefully
		zone:trackItem(currentBomb.PrimaryPart)
	end
end

-- === Setup individual zone ===
local function setupGoalZone(model: Model)
	if not (model:IsA("Model") and (model.Name == "RedGoal" or model.Name == "BlueGoal")) then
		return
	end

	local zonePart = model:FindFirstChild("zone")
	if not (zonePart and zonePart:IsA("BasePart")) then
		warn("[ScoreZonesService] Missing valid 'zone' part in", model.Name)
		return
	end

	local zone = Zone.new(zonePart)
    zone.accuracy = Zone.enum.Accuracy.Precise   -- during “hot” moments

	goalZones[model.Name] = zone

	-- Immediately track an already-spawned bomb (if present)
	trackBombInAllZones()

	-- Use itemEntered so anchored/welded/CFramed parts are detected reliably
	zone.itemEntered:Connect(function(item: BasePart)
		-- Only react if this item IS the current bomb's PrimaryPart
		if not currentBomb or not currentBomb.PrimaryPart then return end
		if item ~= currentBomb.PrimaryPart then return end

		-- Determine bomb team from its attribute (set when picked up)
		local bombTeam = currentBomb:GetAttribute("TeamColorName")
		if not bombTeam then
			warn("[ScoreZonesService] Bomb has no TeamColorName attribute")
			return
		end

		-- Determine which team's goal this is
		local goalTeam = model.Name:match("(%w+)Goal") -- "Red" or "Blue"
		if not goalTeam then
			warn("[ScoreZonesService] Invalid goal model name:", model.Name)
			return
		end

		-- Prevent scoring in own goal (bombTeam matches goalTeam)
		if bombTeam:lower():find(goalTeam:lower()) then
			print(("[ScoreZonesService] Invalid score: bomb team '%s' matches goal team '%s'"):format(bombTeam, goalTeam))
			return
		end

		-- VALID SCORE
		print(("[ScoreZonesService] Bomb scored in %s by team %s"):format(model.Name, bombTeam))
		ScoreZonesService.TeamScored:Fire(bombTeam, goalTeam)

		-- Reset round: teleport teams + destroy bomb (respawn handled elsewhere)
		TeamAssignerService:TeleportTeamToSpawn(BrickColor.new("Really red"))
		TeamAssignerService:TeleportTeamToSpawn(BrickColor.new("Really blue"))

		BombSpawnService:DestroyBomb()
	end)

	print("[ScoreZonesService] Zone created for", model.Name)
end

-- === Knit Init ===
function ScoreZonesService:KnitInit()
	-- Build zones for existing tagged models
	for _, model in ipairs(CollectionService:GetTagged("scoreZone")) do
		setupGoalZone(model)
	end

	-- React to zones added at runtime
	CollectionService:GetInstanceAddedSignal("scoreZone"):Connect(setupGoalZone)

	-- Services we depend on
	BombSpawnService = Knit.GetService("BombSpawnService")
	TeamAssignerService = Knit.GetService("TeamAssignerService")

	-- When a new bomb spawns, start tracking its PrimaryPart in all goal zones
	BombSpawnService.BombSpawned:Connect(function(bombModel: Model)
		if not bombModel.PrimaryPart then
			warn("[ScoreZonesService] Bomb model has no PrimaryPart!")
		end
		currentBomb = bombModel
		trackBombInAllZones()
		print("[ScoreZonesService] Bomb tracking updated.")
	end)
end

function ScoreZonesService:KnitStart()
	-- no-op
end

return ScoreZonesService
