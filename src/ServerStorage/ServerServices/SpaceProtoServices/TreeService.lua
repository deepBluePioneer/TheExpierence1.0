local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local Packages = ReplicatedStorage.Packages
local Knit = require(Packages.Knit)

local TreeService = Knit.CreateService {
    Name = "TreeService",
    Client = {},
}

-- Utility function to create a part
local function createPart(position, size, color, parent)
    local part = Instance.new("Part")
    part.Size = size
    part.Position = position
    part.Anchored = true
    part.Material = Enum.Material.SmoothPlastic
    part.Color = color
    part.Parent = parent
    return part
end

-- Generate a simple trunk
local function generateTrunk(basePosition, trunkHeight, parent)
    createPart(basePosition + Vector3.new(0, trunkHeight / 2, 0), Vector3.new(1, trunkHeight, 1), Color3.fromRGB(101, 67, 33), parent)
    return basePosition + Vector3.new(0, trunkHeight, 0) -- Position at the top of the trunk
end

-- Generate a simple branching structure
local function generateBranches(startPosition, branchCount, branchLength, parent)
    local branchAngleRange = math.rad(45) -- Angle variation for branches
    for _ = 1, branchCount do
        local angle = CFrame.Angles(
            math.random() * branchAngleRange - branchAngleRange / 2, -- X-axis variation
            math.random() * math.pi * 2, -- Full Y-axis rotation
            0
        )
        local branchDirection = (angle * Vector3.new(0, 1, 0)).Unit
        local endPosition = startPosition + branchDirection * branchLength

        createPart(
            (startPosition + endPosition) / 2, -- Midpoint for positioning
            Vector3.new(0.8, branchLength, 0.8), -- Thin branch
            Color3.fromRGB(101, 67, 33),
            parent
        )
    end
end

-- Generate sparse random leaf voxels
local function generateLeaves(centerPosition, leafCount, leafRadius, parent)
    for _ = 1, leafCount do
        local randomOffset = Vector3.new(
            math.random(-leafRadius, leafRadius),
            math.random(-leafRadius, leafRadius),
            math.random(-leafRadius, leafRadius)
        )
        if randomOffset.Magnitude <= leafRadius then
            createPart(centerPosition + randomOffset, Vector3.new(1, 1, 1), Color3.fromRGB(34, 139, 34), parent)
        end
    end
end

-- Function to generate a single optimized tree
local function generateTree(basePosition, parent)
    local treeModel = Instance.new("Model")
    treeModel.Name = "OptimizedTree"
    treeModel.Parent = parent

    -- Trunk
    local trunkHeight = math.random(8, 12)
    local trunkTop = generateTrunk(basePosition, trunkHeight, treeModel)

    -- Branches
    generateBranches(trunkTop, math.random(3, 5), math.random(5, 8), treeModel)

    -- Leaves
    generateLeaves(trunkTop, 50, math.random(4, 6), treeModel)
end

-- TreeService KnitStart
function TreeService:KnitStart()
    -- Create a model to hold all trees
    local treeModel = Instance.new("Model")
    treeModel.Name = "Trees"
    treeModel.Parent = Workspace

    -- Generate a single tree at a random position
    local treePosition = Vector3.new(math.random(-50, 50), 0, math.random(-50, 50))
    generateTree(treePosition, treeModel)
end

function TreeService:KnitInit()
    -- Add service initialization logic here
end

return TreeService
