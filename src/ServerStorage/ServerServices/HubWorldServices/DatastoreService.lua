local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CustomPackages = ReplicatedStorage.CustomPackages
local Packages = ReplicatedStorage.Packages
local DataStoreService = game:GetService("DataStoreService")
local PlayersDataStore = DataStoreService:GetDataStore("PlayersData")
local PlayerAddedController = CustomPackages.PlayerAddedController
local PlayerAddedFunctions =  PlayerAddedController.PlayerAddedFunctions
local Knit = require(Packages.Knit)

local DatastoreService = Knit.CreateService {
    Name = "DatastoreService",
    Client = {},
}

-- Function to save data
function DatastoreService:savePlayerData(playerName, data)
    local success, errorMessage = pcall(function()
        PlayersDataStore:SetAsync(playerName, data)
    end)

    if success then
        print("Data saved successfully for", playerName)
    else
        warn("Failed to save data for", playerName, "Error:", errorMessage)
    end
end

-- Function to load data
function DatastoreService:loadPlayerData(playerName)
    local success, result = pcall(function()
        return PlayersDataStore:GetAsync(playerName)
    end)

    if success then
        print("Data loaded for", playerName, ":", result)
        return result
    else
        warn("Failed to load data for", playerName)
        return nil
    end
end

function DatastoreService:KnitInit()
    -- Add service initialization logic here

end

--DatastoreService:savePlayerData("AA", {Experience  = 5, Gold = 5000})


function DatastoreService:KnitStart()

    require(PlayerAddedFunctions)(
        function(JoiningPlayer)
            local playerData = DatastoreService:loadPlayerData("StarFissure12")

            print("Joining Getting DS: "..JoiningPlayer.Name)
            print(playerData)

        
        end,
        function(LeavingPlayer)
            print("LeavingPlayer: "..LeavingPlayer.Name)

        end,
        function(Player, Character)
        
        end
    )

   
end



return DatastoreService