-- Server/Services/TeamAssignerService.lua

local Players            = game:GetService("Players")
local Teams              = game:GetService("Teams")
local Workspace          = game:GetService("Workspace")
local ReplicatedStorage  = game:GetService("ReplicatedStorage")

local CustomPackages     = ReplicatedStorage:WaitForChild("CustomPackages")
local Packages           = ReplicatedStorage:WaitForChild("Packages")
local Knit               = require(Packages:WaitForChild("Knit"))

local PlayerAddedController  = CustomPackages:WaitForChild("PlayerAddedController")
local PlayerAddedFunctions   = require(PlayerAddedController:WaitForChild("PlayerAddedFunctions"))

local TeamAssignerService = Knit.CreateService {
    Name = "TeamAssignerService",
    Client = {},
}

-- === CONFIG ===
local RED_COLOR   = BrickColor.new("Really red")
local BLUE_COLOR  = BrickColor.new("Really blue")
local RESPAWN_OFFSET_Y = 4

-- === STATE ===
local rng              = Random.new()
local SpawnsByColor    = { [RED_COLOR.Number] = {}, [BLUE_COLOR.Number] = {} }
local OccupiedBySpawn  = {}   -- [SpawnLocation] = Player
local ReservedByPlayer = {}   -- [Player] = SpawnLocation

-- === TEAM CREATION ===

local function ensureTeam(name: string, color: BrickColor)
	local existing = Teams:FindFirstChild(name)
	if existing and existing:IsA("Team") then
		existing.TeamColor = color
		existing.AutoAssignable = false
		return existing
	end

	local team = Instance.new("Team")
	team.Name = name
	team.TeamColor = color
	team.AutoAssignable = false
	team.Parent = Teams
	return team
end

-- === SPAWN HELPERS ===

local function isSpawnForTeam(spawn: Instance, color: BrickColor)
	if not spawn:IsA("SpawnLocation") then return false end
	local teamColor = (spawn.TeamColor ~= BrickColor.Black and spawn.TeamColor) or spawn.BrickColor
	return teamColor == color
end

local function collectTeamSpawns()
	table.clear(SpawnsByColor[RED_COLOR.Number])
	table.clear(SpawnsByColor[BLUE_COLOR.Number])

	for _, inst in ipairs(Workspace:GetDescendants()) do
		if inst:IsA("SpawnLocation") then
			if isSpawnForTeam(inst, RED_COLOR) then
				table.insert(SpawnsByColor[RED_COLOR.Number], inst)
			elseif isSpawnForTeam(inst, BLUE_COLOR) then
				table.insert(SpawnsByColor[BLUE_COLOR.Number], inst)
			end
		end
	end
end

local function getAvailableSpawns(color: BrickColor)
	local list = SpawnsByColor[color.Number] or {}
	local available = {}
	for _, s in ipairs(list) do
		if not OccupiedBySpawn[s] then
			table.insert(available, s)
		end
	end
	return available
end

local function pickRandom(list)
	if #list == 0 then return nil end
	return list[rng:NextInteger(1, #list)]
end

local function chooseTeamAndSpawn()
	local firstColor = (rng:NextInteger(0, 1) == 0) and RED_COLOR or BLUE_COLOR
	local secondColor = (firstColor == RED_COLOR) and BLUE_COLOR or RED_COLOR

	local availFirst = getAvailableSpawns(firstColor)
	if #availFirst > 0 then
		return firstColor, pickRandom(availFirst)
	end

	local availSecond = getAvailableSpawns(secondColor)
	if #availSecond > 0 then
		return secondColor, pickRandom(availSecond)
	end

	-- All spawns taken; allow fallback reuse
	local any = {}
	for _, s in ipairs(SpawnsByColor[RED_COLOR.Number])  do table.insert(any, s) end
	for _, s in ipairs(SpawnsByColor[BLUE_COLOR.Number]) do table.insert(any, s) end
	return firstColor, pickRandom(any)
end

local function findTeamByColor(color: BrickColor)
	for _, t in ipairs(Teams:GetChildren()) do
		if t:IsA("Team") and t.TeamColor == color then
			return t
		end
	end
	return nil
end

local function reserveSpawn(player: Player, spawn: SpawnLocation)
	OccupiedBySpawn[spawn] = player
	ReservedByPlayer[player] = spawn
end

local function releaseReservation(player: Player)
	local prev = ReservedByPlayer[player]
	if prev then
		OccupiedBySpawn[prev] = nil
		ReservedByPlayer[player] = nil
	end
end

local function placeCharacterAtSpawn(character: Model, spawn: SpawnLocation)
	local cf = spawn.CFrame
	local offset = Vector3.new(0, (spawn.Size.Y * 0.5) + RESPAWN_OFFSET_Y, 0)
	character:PivotTo(CFrame.new(cf.Position + offset))
end





-- === TEAM COLOR APPEARANCE ===

local function applyTeamColorToCharacter(character: Model, color: BrickColor)
	-- Remove existing highlight if any
	local existingHighlight = character:FindFirstChildWhichIsA("Highlight")
	if existingHighlight then
		existingHighlight:Destroy()
	end

	-- Create and apply new highlight
	local highlight = Instance.new("Highlight")
	highlight.Name = "TeamHighlight"
	highlight.Adornee = character
	highlight.FillColor = color.Color
	highlight.FillTransparency = 1
	highlight.OutlineColor = color.Color
	highlight.OutlineTransparency = 0
	highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	highlight.Parent = character
end


-- === CHARACTER HOOK ===
function TeamAssignerService:TeleportTeamToSpawn(teamColor: BrickColor)
	for _, player in ipairs(Players:GetPlayers()) do
		if player.TeamColor == teamColor and player.Character and player.Character:FindFirstChild("HumanoidRootPart") then
			local spawn = ReservedByPlayer[player] or pickRandom(getAvailableSpawns(teamColor))
			if spawn then
				reserveSpawn(player, spawn)
				placeCharacterAtSpawn(player.Character, spawn)
			end
		end
	end
end


function TeamAssignerService:HandleCharacterAdded(player: Player, character: Model)
	releaseReservation(player)

	local color, spawn = chooseTeamAndSpawn()
	if not spawn then
		warn("[TeamAssignerService] No spawn location available!")
		return
	end

	-- Assign team
	player.TeamColor = color
	local team = findTeamByColor(color)
	if team then
		player.Team = team
	end

	-- Apply visual tint
	applyTeamColorToCharacter(character, color)

	-- Move character
	reserveSpawn(player, spawn)
	placeCharacterAtSpawn(character, spawn)

	-- Free reservation on death
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.Died:Once(function()
			releaseReservation(player)
		end)
	end
end

-- === KNIT LIFECYCLE ===

function TeamAssignerService:KnitInit()
	-- Ensure teams exist
	ensureTeam("Red", RED_COLOR)
	ensureTeam("Blue", BLUE_COLOR)
end

function TeamAssignerService:KnitStart()
	-- Gather spawn pads
	collectTeamSpawns()

	-- Watch for added/removed spawns
	Workspace.DescendantAdded:Connect(function(inst)
		if inst:IsA("SpawnLocation") then
			collectTeamSpawns()
		end
	end)
	Workspace.DescendantRemoving:Connect(function(inst)
		if inst:IsA("SpawnLocation") then
			collectTeamSpawns()
		end
	end)

	-- Hook player events
	PlayerAddedFunctions(
		function(_player) end,
		function(player)
			releaseReservation(player)
		end,
		function(player, character)
			self:HandleCharacterAdded(player, character)
		end
	)

	Players.PlayerRemoving:Connect(function(player)
		releaseReservation(player)
	end)
end

return TeamAssignerService
