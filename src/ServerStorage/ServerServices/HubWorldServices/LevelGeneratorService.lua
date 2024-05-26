local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CustomPackages = ReplicatedStorage.CustomPackages
local Packages = ReplicatedStorage.Packages
local Knit = require(Packages.Knit)
local CollectionService = game:GetService("CollectionService")
-- Zone Modules
local ZoneRoot = CustomPackages.ZoneRoot
local Zone = require(ZoneRoot.Zone)

local LevelGeneratorService = Knit.CreateService {
    Name = "LevelGeneratorService",
    Client = {},
    Balls = {},  -- Global table to store the spheres
}

function LevelGeneratorService:KnitStart()
   
end

function LevelGeneratorService:KnitInit()
     -- Add service startup logic here
     local baseplate = workspace:FindFirstChild("Baseplate")
     if baseplate then
         local centerPosition = baseplate.Position
         self:CreateCircleOfBalls(centerPosition, 100, 100)  -- Increased radius and number of balls
     else
         warn("Baseplate not found in the workspace.")
     end
end

function LevelGeneratorService:CreateCircleOfBalls(centerPosition, radius, numberOfBalls)
    local model = Instance.new("Model")
    model.Name = "CircleOfBalls"
    model.Parent = workspace

    for i = 0, numberOfBalls - 1 do
        local angle = (i / numberOfBalls) * math.pi * 2
        local x = centerPosition.X + radius * math.cos(angle)
        local z = centerPosition.Z + radius * math.sin(angle)
        local ballPosition = Vector3.new(x, centerPosition.Y + 15, z)  -- +15 to ensure balls are slightly above the baseplate
        
        local ball = Instance.new("Part")
        ball.Shape = Enum.PartType.Ball
        ball.Size = Vector3.new(5, 5, 5)  -- Example size
        ball.Position = ballPosition
        
        ball.Anchored = true
        ball.Parent = model
      
        -- Add the ball to the "musicSpheres" collection
        CollectionService:AddTag(ball, "musicElement")
        
        table.insert(self.Balls, ball)  -- Store the ball in the global table
    end
end

return LevelGeneratorService
