local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Teams = game:GetService("Teams")
local Players = game:GetService("Players")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local Knit = require(Packages.Knit)

local MAX_PLAYERS_PER_TEAM = 5

local TeamService = Knit.CreateService {
    Name = "TeamService",
    Client = {},
}

-- Creates the teams explicitly
function TeamService:CreateTeams()
    Teams:ClearAllChildren()

    local redTeam = Instance.new("Team")
    redTeam.Name = "Red"
    redTeam.TeamColor = BrickColor.new("Bright red")
    redTeam.AutoAssignable = false
    redTeam.Parent = Teams

    local blueTeam = Instance.new("Team")
    blueTeam.Name = "Blue"
    blueTeam.TeamColor = BrickColor.new("Bright blue")
    blueTeam.AutoAssignable = false
    blueTeam.Parent = Teams
end

-- Finds a team with available slots (< MAX_PLAYERS_PER_TEAM)
function TeamService:GetTeamWithSpace()
    local availableTeams = {}

    for _, team in ipairs(Teams:GetTeams()) do
        local count = #team:GetPlayers()
        if count < MAX_PLAYERS_PER_TEAM then
            table.insert(availableTeams, team)
        end
    end

    if #availableTeams == 0 then
        warn("No available team slots!")
        return nil
    end

    -- Randomly select one of the teams that have available slots
    return availableTeams[math.random(#availableTeams)]
end

-- Assign player to a balanced team and set default attributes
function TeamService:AssignPlayerToTeam(player)
    local team = self:GetTeamWithSpace()

    if team then
        player.Team = team
        player:SetAttribute("HasFlag", false) -- Initialize 'HasFlag' as false
        print(player.Name .. " assigned to team:", team.Name, " | HasFlag: ", player:GetAttribute("HasFlag"))
    else
        warn("All teams full, couldn't assign team to player:", player.Name)
    end
end

-- Update player's HasFlag attribute (true when they pick up the flag, false when dropped)
function TeamService:SetPlayerHasFlag(player, hasFlag)
    if player then
        player:SetAttribute("HasFlag", hasFlag)
        print(player.Name .. " HasFlag set to: " .. tostring(hasFlag))
    end
end

-- Knit lifecycle methods
function TeamService:KnitInit()
    self:CreateTeams() -- Create teams when Knit initializes

    Players.PlayerAdded:Connect(function(player)
        self:AssignPlayerToTeam(player)
    end)

    Players.PlayerRemoving:Connect(function(player)
        player.Team = nil -- Clear team when player leaves
        player:SetAttribute("HasFlag", nil) -- Clear the attribute
    end)
end

function TeamService:KnitStart()
    print("TeamService Started and ready.")
end

return TeamService
