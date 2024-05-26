local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CustomPackages = ReplicatedStorage.CustomPackages
local Packages = ReplicatedStorage.Packages
local Knit = require(Packages.Knit)
-- Zone Modules
local ZoneRoot = CustomPackages.ZoneRoot
local Zone = require(ZoneRoot.Zone)

local WaveSpawnerService = Knit.CreateService {
    Name = "WaveSpawnerService",
    Client = {},
    Monsters = {},  -- Global table to store the monsters
}

function WaveSpawnerService:KnitStart()
   

    -- Add service startup logic here
    local LevelGeneratorService = Knit.GetService("LevelGeneratorService")
    -- Access the balls table from LevelGeneratorService
    local balls = LevelGeneratorService.Balls

    -- Define the number of monsters to spawn
    local numberOfMonsters = 1
    -- Create monsters
    local monsterModel = self:SpawnMonsters(balls, numberOfMonsters)
    WaveSpawnerService:CreateZones(balls, monsterModel.monster)
end

function WaveSpawnerService:KnitInit()
    -- Add service initialization logic here
end

function WaveSpawnerService:CreateZones(balls, monster)

    for i, v in ipairs(balls) do
        local zone = Zone.new(v)

        zone.itemEntered:Connect(function(item)
           print("Monster hit bounds")
        end)

        zone.itemExited:Connect(function(item)
        
        end)

        -- Example: Track an additional item if needed
        zone:trackItem(monster)

    end

end

function WaveSpawnerService:SpawnMonsters(balls, numberOfMonsters)
    local chosenBalls = self:ChooseRandomElements(balls, numberOfMonsters)
    
    -- Create a model to group the monsters
    local monsterModel = Instance.new("Model")
    monsterModel.Name = "Monsters"
    monsterModel.Parent = workspace
    
    for _, ball in ipairs(chosenBalls) do
        local monster = Instance.new("Part")
        monster.Name = "monster"
        monster.Shape = Enum.PartType.Ball
        monster.Size = Vector3.new(5, 5, 5)  -- Example size
        monster.Position = ball.Position
        monster.Anchored = true
        monster.BrickColor = BrickColor.new("Bright red")  -- Different color to distinguish monsters
        monster.Parent = monsterModel

       
        table.insert(self.Monsters, monster)  -- Store the monster in the global table
    end

    -- Add a highlight component to the model
    local highlight = Instance.new("Highlight")
    highlight.Parent = monsterModel
    highlight.Adornee = monsterModel
    highlight.FillColor = Color3.new(1, 0, 0)  -- Red color
    highlight.OutlineColor = Color3.new(1, 0, 0)  -- White outline

    return monsterModel
end

function WaveSpawnerService:ChooseRandomElements(tbl, numElements)
    local result = {}
    local len = #tbl
    
    if numElements > len then
        numElements = len  -- Ensure we don't request more elements than are available
    end
    
    -- Fill the result with the first numElements elements
    for i = 1, numElements do
        result[i] = tbl[i]
    end
    
    -- Perform reservoir sampling
    for i = numElements + 1, len do
        local j = math.random(1, i)
        if j <= numElements then
            result[j] = tbl[i]
        end
    end
    
    return result
end

return WaveSpawnerService
