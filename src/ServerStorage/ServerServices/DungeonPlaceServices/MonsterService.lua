local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CustomPackages = ReplicatedStorage.CustomPackages
local Packages = ReplicatedStorage.Packages
local Knit = require(Packages.Knit)

local MonsterService = Knit.CreateService {
    Name = "MonsterService",
    Client = {},
}


function MonsterService:CreateCylinderSegments(numSegments, segmentHeight, radius)
    local basePart = Instance.new("Part")
    basePart.Shape = Enum.PartType.Cylinder
    basePart.Size = Vector3.new(radius * 2, segmentHeight, radius * 2)
    basePart.Anchored = true
    basePart.Material = Enum.Material.SmoothPlastic
    basePart.Color = Color3.fromRGB(255, 0, 0) -- Change color as needed

    for i = 1, numSegments do
        local segment = basePart:Clone()
        segment.Position = Vector3.new(0, (i - 1) * segmentHeight, 0) -- Stack segments vertically
        segment.Parent = game.Workspace -- You might want to parent this to a specific model or folder
    end
    basePart:Destroy() -- Cleanup the base part as it's not needed anymore
end

function MonsterService:KnitStart()
    self:CreateCylinderSegments(10, 2, 3) -- Creates 10 segments, each 2 studs high, with a radius of 3 studs
end

function MonsterService:KnitInit()
    -- Add service initialization logic here
end

return MonsterService