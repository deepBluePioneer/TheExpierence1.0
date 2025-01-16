local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local Packages = ReplicatedStorage.Packages
local Knit = require(Packages.Knit)

local GrassService = Knit.CreateService {
    Name = "GrassService",
    Client = {},
}

-- Utility function to create a unit cube for grass
local function createGrassVoxel(position, parent)
    local cube = Instance.new("Part")
    cube.Size = Vector3.new(0.5, math.random(2, 5), 0.5) -- Random height
    cube.Position = position
    cube.Anchored = true
    cube.Material = Enum.Material.SmoothPlastic
    cube.Color = Color3.fromRGB(60, 240, 60) -- Grass green
    cube.Transparency = 0.35
    cube.CFrame = CFrame.new(position) * CFrame.Angles(0, math.rad(math.random(0, 360)), 0) -- Random rotation
    cube.Parent = parent
    return cube
end

-- Function to create a grouping of grass voxels
local function createGrassCluster(centerPosition, clusterSize, parent)
    for x = -clusterSize, clusterSize do
        for z = -clusterSize, clusterSize do
            -- Random chance to skip some voxels for a more natural look
            if math.random() > 0.3 then
                local position = centerPosition + Vector3.new(x, 0, z)
                createGrassVoxel(position, parent)
            end
        end
    end
end

-- GrassService KnitStart
function GrassService:KnitStart()
    -- Create a model to hold all grass clusters
    local grassModel = Instance.new("Model")
    grassModel.Name = "GrassClusters"
    grassModel.Parent = Workspace

    -- Expand coverage to cover more of the Baseplate
    local baseplateSize = 512 -- Assuming the Baseplate is 512x512
    local grassClusterCount = 50 -- Increase the number of clusters
    local clusterArea = baseplateSize / 2 -- Define the area for clusters

    -- Generate clusters of grass
    for _ = 1, grassClusterCount do
        local clusterPosition = Vector3.new(
            math.random(-clusterArea, clusterArea), -- Random X position
            0,
            math.random(-clusterArea, clusterArea) -- Random Z position
        )
        createGrassCluster(clusterPosition, math.random(5, 10), grassModel) -- Larger cluster size for more coverage
    end
end

function GrassService:KnitInit()
    -- Add service initialization logic here
end

return GrassService
