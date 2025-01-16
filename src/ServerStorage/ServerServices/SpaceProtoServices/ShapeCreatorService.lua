local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local Knit = require(ReplicatedStorage.Packages.Knit)

local Octree = require(ReplicatedStorage.Source.octree) -- Ensure the Octree module is accessible
local _Button = ReplicatedStorage.Prefabs.PurchaseButton.Button -- Reference the button template

local ShapeCreatorService = Knit.CreateService {
    Name = "ShapeCreatorService",
    Client = {},
}

-- Initialize the Octree
local voxelOctree = Octree.new(4096) -- Larger size to accommodate a larger area

-- Utility function to create a unit cube
local function createUnitCube(position, parent)
    local cube = Instance.new("Part")
    cube.Size = Vector3.new(1, 1, 1)
    cube.Position = position
    cube.Anchored = true
    cube.Material = Enum.Material.SmoothPlastic
    cube.Color = Color3.new(0.968627, 1, 0.376470) -- Brown color for the structure
    cube.Parent = parent

    -- Add the cube to the Octree for collision checking
    voxelOctree:CreateNode(position, cube)
    return cube
end

local function createButton(position, parent)
    -- Clone the button model from the prefab
    local buttonModel = _Button:Clone()
    buttonModel.Parent = parent

    -- Ensure the button model has a primary part
    if buttonModel.PrimaryPart then
        -- Create a CFrame with position and a 90-degree rotation around the Y-axis
        local rotation = CFrame.Angles(0, 0, math.rad(-90))
        buttonModel:PivotTo(CFrame.new(position) * rotation) -- Apply position and rotation
    else
        warn("Button model does not have a PrimaryPart set!")
    end

    -- Add the button to the Octree for collision checking
    voxelOctree:CreateNode(position, buttonModel)
    return buttonModel
end


-- Space Colonization Algorithm for flat structures using unit cubes and buttons
local function spaceColonizationFlat(basePart, parent, attractorCount, influenceRadius, maxLength, branchLimit)
    -- Generate attraction points in a larger flat area
    local attractionPoints = {}
    for _ = 1, attractorCount do
        table.insert(attractionPoints, basePart.Position + Vector3.new(
            math.random(-256, 256), -- X range for a sprawling area
            0,                     -- Y stays constant for flat growth
            math.random(-256, 256) -- Z range for a sprawling area
        ))
    end

    -- Branch class
    local Branch = {}
    Branch.__index = Branch

    function Branch.new(position, direction, parentBranch)
        local self = setmetatable({}, Branch)
        self.Position = position
        self.Direction = direction.Unit
        self.Parent = parentBranch
        return self
    end

    -- Initialize root branch
    local root = Branch.new(basePart.Position, Vector3.new(1, 0, 0), nil)
    local branches = { root }

    -- Grow branches toward attraction points
    for _ = 1, branchLimit do
        local newBranches = {}

        -- Track influence for each branch
        local influences = {}
        for i, branch in ipairs(branches) do
            influences[i] = { branch = branch, directions = {} }
        end

        -- Determine which branches are influenced by attraction points
        for _, attractor in ipairs(attractionPoints) do
            local closestBranch = nil
            local minDist = math.huge

            for i, branch in ipairs(branches) do
                local dist = (branch.Position - attractor).Magnitude
                if dist < influenceRadius and dist < minDist then
                    closestBranch = influences[i]
                    minDist = dist
                end
            end

            if closestBranch then
                -- Record the influence of the attractor point on the branch
                local direction = (attractor - closestBranch.branch.Position).Unit
                table.insert(closestBranch.directions, direction)
            end
        end

        -- Create new branches based on influences
        for _, influence in ipairs(influences) do
            if #influence.directions > 0 then
                -- Average the directions
                local avgDirection = Vector3.new(0, 0, 0)
                for _, dir in ipairs(influence.directions) do
                    avgDirection += dir
                end
                avgDirection = avgDirection.Unit

                -- Create a new branch
                local newPosition = influence.branch.Position + avgDirection * maxLength
                local roundedPos = Vector3.new(
                    math.round(newPosition.X),
                    math.round(newPosition.Y),
                    math.round(newPosition.Z)
                ) -- Round to prevent precision errors

                -- Ensure no overlapping objects
                if #voxelOctree:RadiusSearch(roundedPos, 0.5) == 0 then
                    local newBranch = Branch.new(roundedPos, avgDirection, influence.branch)
                    table.insert(newBranches, newBranch)

                    -- Randomly create a button or a unit cube
                    if math.random() < 0.1 then -- 10% chance to create a button
                        createButton(roundedPos, parent)
                    else
                        createUnitCube(roundedPos, parent)
                    end
                end
            end
        end

        -- Add new branches to the main list
        for _, newBranch in ipairs(newBranches) do
            table.insert(branches, newBranch)
        end

        -- Remove attraction points close to any branch
        for i = #attractionPoints, 1, -1 do
            for _, branch in ipairs(branches) do
                if (branch.Position - attractionPoints[i]).Magnitude < maxLength then
                    table.remove(attractionPoints, i)
                    break
                end
            end
        end
    end
end

-- Create the encompassing structure
function ShapeCreatorService:CreateEncompassingStructure()
    -- Create the structure
    local structureParent = Instance.new("Model")
    structureParent.Name = "EncompassingStructure"
    structureParent.Parent = Workspace

    local basePart = Instance.new("Part")
    basePart.Position = Vector3.new(0, 0, 0) -- Start position at origin
    basePart.Anchored = true
    basePart.Size = Vector3.new(1, 1, 1)
    basePart.Transparency = 1 -- Invisible
    basePart.Parent = structureParent

    -- Generate sprawling structure using space colonization
    spaceColonizationFlat(
        basePart,
        structureParent,
        3000, -- More attraction points for denser coverage
        30,   -- Larger influence radius for broader growth
        4,    -- Longer branch steps
        1500  -- More branches for a more extensive structure
    )
end

function ShapeCreatorService:KnitStart()
    self:CreateEncompassingStructure()
end

function ShapeCreatorService:KnitInit()
    -- Add service initialization logic here
end

return ShapeCreatorService
