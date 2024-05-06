local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CustomPackages = ReplicatedStorage.CustomPackages
local Packages = ReplicatedStorage.Packages
local Knit = require(Packages.Knit)
local Players = game:GetService("Players")

local PlayerAddedController = CustomPackages.PlayerAddedController
local PlayerAddedFunctions =  PlayerAddedController.PlayerAddedFunctions

local QuestLine = require(CustomPackages.QuestLineFolder.QuestLine)

local QuestService = Knit.CreateService {
    Name = "QuestService",
    Client = {},
    PlayerQuests = {}  -- Properly define the PlayerQuests table here

}

-- Initialize Quests
function QuestService:InitQuests()
    local collectQuest = QuestLine.new("collectQuest", {Title = "Collect Items"})
    collectQuest:AddObjective(QuestLine.Touch, workspace.ItemPart)  -- Touch an item part to collect it

    local survivalQuest = QuestLine.new("survivalQuest", {Title = "Survive Time"})
    survivalQuest:AddObjective(QuestLine.Timer, 600, 10)  -- Survive for 10 minutes, update every 10 seconds

    local scoreQuest = QuestLine.new("scoreQuest", {Title = "Reach Score"})
    scoreQuest:AddObjective(QuestLine.Score, "Score", 100)  -- Reach 100 points on leaderstats

    self.Quests = {
        collectQuest = collectQuest,
        survivalQuest = survivalQuest,
        scoreQuest = scoreQuest
    }
end

-- Register Player and Assign Quests
function QuestService:RegisterPlayer(player)
    local playerData = {collectQuest = 0, survivalQuest = 0, scoreQuest = 0}
    QuestLine.registerPlayer(player, playerData)
    warn(player.UserId)
    -- Automatically assign quests
    self.PlayerQuests[player.UserId] = {}  -- Initialize player's quest list
    for questId, quest in pairs(self.Quests) do
        quest:Assign(player)
        table.insert(self.PlayerQuests[player.UserId], questId)  -- Store questId for later retrieval
    end
    self:PrintPlayerQuests(player)  -- Print quests after assigning
end


-- Print Player's Quests
function QuestService:PrintPlayerQuests(player)
    local playerQuestIds = self.PlayerQuests[player.UserId]
    if playerQuestIds then
        print("Quests for ", player.Name)
        for _, questId in ipairs(playerQuestIds) do
            local quest = QuestLine.getQuestById(questId)
            if quest then
                print(questId, ": ", quest.Title)
            end
        end
    end
end

-- Unregister Player
function QuestService:UnregisterPlayer(player)
    local playerData = QuestLine.unregisterPlayer(player)
    -- Logic to save playerData to a datastore could be added here
end

function QuestService:KnitStart()
    self:InitQuests()

    require(PlayerAddedFunctions)(
        function(JoiningPlayer)
            print("Joining: "..JoiningPlayer.Name)
            self:RegisterPlayer(JoiningPlayer)

        end,
        function(LeavingPlayer)
            print("LeavingPlayer: "..LeavingPlayer.Name)
            self:UnregisterPlayer(LeavingPlayer)

        end,
        function(Player, Character)
        
        end
    )

end

function QuestService:KnitInit()
    -- Initialization logic for the QuestService
    self.PlayerQuests = {}  -- Initialize here to ensure it exists before used

end

return QuestService
