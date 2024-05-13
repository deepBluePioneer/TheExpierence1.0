local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local Packages = ReplicatedStorage.Packages
local Knit = require(Packages.Knit)
local Players = game:GetService("Players") -- Get the Players service

local MonsterController = Knit.CreateController { Name = "MonsterController" }

-- Variables to control the size and position of the spheres
local sphereRadius = 3
local spherePosition = Vector3.new(0, 30, 0) -- Position to place the main sphere higher
local numberOfSpheres = 5 -- Number of child spheres to create
local constraintLength = .15-- Desired length of the RodConstraint
local numberOfTentacles = 8 -- Number of tentacles to create

-- Function to create a sphere part
function MonsterController:CreateSpherePart(size, position, parent, anchored)
    local part = Instance.new("Part")
    part.Shape = Enum.PartType.Ball
    part.Size = Vector3.new(size * 2, size * 2, size * 2) -- Set size using diameter
    part.Anchored = anchored -- Set anchoring based on the parameter
    part.Position = position -- Set the part's position
    local materialVariantName = "GoryMaterial" -- Replace with the desired material variant name
    part.Material = Enum.Material.Salt
    part.Massless = true
    part.MaterialVariant = materialVariantName

    part.Parent = parent -- Parent the part to the specified parent
    return part
end

-- Function to create progressively smaller child spheres, each touching the previous one
function MonsterController:CreateChildSpheres(rootPart)
    local previousPart = rootPart
    local currentRadius = sphereRadius

    for i = 1, numberOfSpheres do
        currentRadius = currentRadius * 0.8 -- Reduce the size of each subsequent sphere
        local offset = (previousPart.Size.X / 2) + (currentRadius) -- Calculate position offset to make spheres touch
        local childPosition = previousPart.Position + Vector3.new(offset, 0, 0) -- Position next to the previous sphere

        local childPart = self:CreateSpherePart(currentRadius, childPosition, previousPart, false) -- Create and parent the next child sphere

        -- Create attachment for the previous part
        local attachment1 = Instance.new("Attachment")
        attachment1.Position = Vector3.new(previousPart.Size.X / 2, 0, 0) -- Position the attachment at the edge of the previous sphere
        attachment1.Parent = previousPart

        -- Create attachment for the current part
        local attachment2 = Instance.new("Attachment")
        attachment2.Position = Vector3.new(-childPart.Size.X / 2, 0, 0) -- Position the attachment at the edge of the current sphere
        attachment2.Parent = childPart

        -- Create a constraint between the attachments
        local constraint = Instance.new("RodConstraint")
        constraint.Attachment0 = attachment1
        constraint.Attachment1 = attachment2
        constraint.Parent = previousPart
        constraint.Length = constraintLength -- Set the length of the constraint to the desired value

        previousPart = childPart -- Update the previous part to the current one
    end
end

-- Function to create a tentacle
function MonsterController:CreateTentacle(position, index, parent, core)
    local tentacleModel = Instance.new("Model")
    tentacleModel.Name = "Tentacle" .. index
    tentacleModel.Parent = parent -- Parent the model to the provided parent

    local rootPart = self:CreateSpherePart(sphereRadius, position, tentacleModel, false) -- Create and parent the main sphere, not anchored
    self:CreateChildSpheres(rootPart) -- Create and parent child spheres to the main sphere

    -- Create attachment on the core part for this tentacle
    local coreAttachment = Instance.new("Attachment")
    coreAttachment.Name = "Attachment" .. index
    coreAttachment.Position = Vector3.new(math.cos(math.rad((index - 1) * (360 / numberOfTentacles))) * 5, 0, math.sin(math.rad((index - 1) * (360 / numberOfTentacles))) * 5)
    coreAttachment.Parent = core

    -- Create attachment on the root part of the tentacle
    local rootAttachment = Instance.new("Attachment")
    rootAttachment.Parent = rootPart

    -- Create a rod constraint between the core attachment and the root attachment
    local rodConstraint = Instance.new("RodConstraint")
    rodConstraint.Attachment0 = coreAttachment
    rodConstraint.Attachment1 = rootAttachment
    rodConstraint.Parent = rootPart
    rodConstraint.Length = (coreAttachment.Position - rootAttachment.Position).Magnitude -- Set the length of the rod constraint dynamically
end

function MonsterController:MoveCoreTowardsLocalPlayer(corePart)
    local localPlayer = Players.LocalPlayer
    local character = localPlayer.Character or localPlayer.CharacterAdded:Wait()
    local humanoidRootPart = character:WaitForChild("HumanoidRootPart")

    -- Create attachment on the core part
    local coreAttachment = Instance.new("Attachment")
    coreAttachment.Parent = corePart

    -- Create the LinearVelocity constraint
    local linearVelocity = Instance.new("LinearVelocity")
    linearVelocity.Attachment0 = coreAttachment
    linearVelocity.RelativeTo = Enum.ActuatorRelativeTo.World -- Apply force in world coordinates
    linearVelocity.MaxForce = 5000000 -- Adjust the maximum force as needed
    linearVelocity.VectorVelocity = (humanoidRootPart.Position - corePart.Position).Unit * 10 -- Set the velocity towards the player's position
    linearVelocity.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
    linearVelocity.Parent = corePart

    -- Update the velocity to follow the player in a loop
    task.spawn(function()
        while character.Parent do
            linearVelocity.VectorVelocity = (humanoidRootPart.Position - corePart.Position).Unit * 10
            task.wait(0.1) -- Adjust the update interval as needed
        end
    end)
end

function MonsterController:KnitStart()
    local monsterModel = Instance.new("Model")
    monsterModel.Name = "Monster"
    monsterModel.Parent = Workspace -- Add the model to the Workspace

    -- Create the core part
    local corePart = Instance.new("Part")
    corePart.Name = "Core"
    corePart.Shape = Enum.PartType.Ball -- Set the core part to be a ball shape
    corePart.Size = Vector3.new(5, 5, 5)
    corePart.Anchored = false
    corePart.Position = spherePosition
    local materialVariantName = "GoryMaterial" -- Replace with the desired material variant name
    corePart.Material = Enum.Material.Salt

    corePart.MaterialVariant = materialVariantName
    corePart.Parent = monsterModel

    for i = 1, numberOfTentacles do
        local angle = (i - 1) * (360 / numberOfTentacles)
        local radians = math.rad(angle)
        local x = math.cos(radians) * 20 -- Adjust the 20 to change the distance from the center
        local z = math.sin(radians) * 20
        local tentaclePosition = spherePosition + Vector3.new(x, 0, z)

        self:CreateTentacle(tentaclePosition, i, monsterModel, corePart)
    end

    self:MoveCoreTowardsLocalPlayer(corePart) -- Move the core part towards the local player
end

function MonsterController:KnitInit()
    -- Initialization logic can be added here
end

return MonsterController
