local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")
local PathfindingService = game:GetService("PathfindingService")
local Knit = require(ReplicatedStorage.Packages.Knit)
local CollectionService = game:GetService("CollectionService")

local MoneyBagsService = Knit.CreateService {
	Name = "MoneyBagsService",
	Client = {},
}

-- Settings
local ESCAPE_DISTANCE = 60
local CHECK_INTERVAL = 2
local MOVE_DISTANCE = 50
local NPC_NAME = "MoneyBags"

-- Signal to client for UI/reward
MoneyBagsService.Client.MoneyBagRewarded = Knit.CreateSignal()

-- References (wait for NPC)
local function getNPC()
	local npc = Workspace:FindFirstChild(NPC_NAME)
	if not npc then
		warn("MoneyBags NPC not found in Workspace")
		return nil
	end
	local humanoid = npc:FindFirstChildOfClass("Humanoid")
	local rootPart = npc:FindFirstChild("HumanoidRootPart")
	if not humanoid or not rootPart then
		warn("MoneyBags missing Humanoid or HumanoidRootPart")
		return nil
	end
	return npc, humanoid, rootPart
end

-- Get closest player within range
local function getNearestPlayer(rootPosition)
	local closestPlayer = nil
	local minDistance = math.huge

	for _, player in ipairs(Players:GetPlayers()) do
		local char = player.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		if hrp then
			local distance = (hrp.Position - rootPosition).Magnitude
			if distance < minDistance then
				minDistance = distance
				closestPlayer = player
			end
		end
	end

	return closestPlayer, minDistance
end

-- Compute an escape path and move
local function runAway(npc, humanoid, rootPart)
	local player, distance = getNearestPlayer(rootPart.Position)
	if not player or distance > ESCAPE_DISTANCE then return end

	local playerHRP = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not playerHRP then return end

	local awayVector = (rootPart.Position - playerHRP.Position).Unit
	local randomOffset = Vector3.new(math.random(-10, 10), 0, math.random(-10, 10))
	local targetPos = rootPart.Position + (awayVector * MOVE_DISTANCE) + randomOffset

	local path = PathfindingService:CreatePath({
		AgentRadius = 2,
		AgentHeight = 5,
		AgentCanJump = true,
		AgentJumpHeight = 10,
		AgentMaxSlope = 30,
	})

	path:ComputeAsync(rootPart.Position, targetPos)

    if path.Status == Enum.PathStatus.Success then
        local waypoints = path:GetWaypoints()
        for _, wp in ipairs(waypoints) do
            humanoid:MoveTo(wp.Position)
            humanoid.MoveToFinished:Wait(2)
        end
    end

end


function MoneyBagsService:KnitStart()
	local npc, humanoid, rootPart = getNPC()
	if not npc then return end


	-- Movement loop
	task.spawn(function()
		while npc and npc.Parent do
			runAway(npc, humanoid, rootPart)
			task.wait(CHECK_INTERVAL)
		end
	end)
end

function MoneyBagsService:KnitInit()
	-- Initialization logic if needed
end

return MoneyBagsService
