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
    PlayerQuests = {},
    Quests = {}  -- Properly define the PlayerQuests table here

}

-- Initialize Quests
function QuestService:InitQuests()

    local QuestDefinitions = require(script.Parent.QuestDefinitions)
    local folderLoc = workspace:WaitForChild("objectivesLocations")
    -- Iterate through all the quests and objectives to set up quests
  
    local proximityPrompt = Instance.new("ProximityPrompt")
    proximityPrompt.ActionText = "Interact"
    proximityPrompt.ObjectText = "Important Object"
    proximityPrompt.Parent = folderLoc.Part1

    local proximityPrompt = Instance.new("ProximityPrompt")
    proximityPrompt.ActionText = "Interact"
    proximityPrompt.ObjectText = "Important Object"
    proximityPrompt.Parent = folderLoc.Part2
    

    local InteractWithObjectQuest = QuestLine.new("InteractWithObjectQuest", { Title = "Interact with the Object" })
    InteractWithObjectQuest:AddObjective(QuestLine.Proximity, folderLoc.Part1)
    InteractWithObjectQuest:AddObjective(QuestLine.Proximity, folderLoc.Part2)


    self.Quests = {
        InteractWithObjectQuest = InteractWithObjectQuest,
      

    }


    function QuestLine:OnComplete(player)
        print(player.Name .. " has completed the quest: " .. self.Title)
        -- Reward the player or trigger the next part of your game's story
    end
end

-- Register Player and Assign Quests
function QuestService:RegisterPlayer(player)
    local playerData = {}
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
