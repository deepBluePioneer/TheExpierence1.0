local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Packages = ReplicatedStorage.Packages
local Prefabs = ReplicatedStorage:WaitForChild("Prefabs") -- Access the Prefabs folder
local Knit = require(Packages.Knit)

local CharacterAccessoryService = Knit.CreateService {
    Name = "CharacterAccessoryService",
    Client = {},
}

-- Function to add an accessory to a character
function CharacterAccessoryService:AddAccessoryToCharacter(character, accessoryName)
    -- Get the accessory from the Prefabs folder
    local accessory = Prefabs:FindFirstChild(accessoryName)
   

    -- Clone the accessory
    local clonedAccessory = accessory:Clone()
    --clonedAccessory.Parent = character -- Parent it to the character

    -- Attach the accessory
    if clonedAccessory:IsA("Accessory") then
        -- Use Humanoid:AddAccessory for proper attachment
        local humanoid = character:FindFirstChild("Humanoid")
        if humanoid then
            humanoid:AddAccessory(clonedAccessory)
        else
            warn("Humanoid not found in character. Cannot attach accessory.")
        end
  
    end
end

-- KnitStart function (executed when the service starts)
function CharacterAccessoryService:KnitStart()
    -- Example usage (remove or customize for actual game logic)
    game.Players.PlayerAdded:Connect(function(player)
        player.CharacterAdded:Connect(function(character)
            -- Automatically add "collar" accessory to characters
            self:AddAccessoryToCharacter(character, "collar")
        end)
    end)
end

-- KnitInit function (executed when the service initializes)
function CharacterAccessoryService:KnitInit()
    -- Initialization logic if needed
end

return CharacterAccessoryService
