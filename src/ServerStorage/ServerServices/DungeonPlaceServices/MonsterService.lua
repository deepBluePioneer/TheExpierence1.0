local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local Packages = ReplicatedStorage.Packages
local Knit = require(Packages.Knit)
local CustomPackages = ReplicatedStorage.CustomPackages

local PlayerAddedController = CustomPackages.PlayerAddedController
local PlayerAddedFunctions =  PlayerAddedController.PlayerAddedFunctions

local MonsterService = Knit.CreateService { Name = "MonsterService" }

-- Variables to control the size and position of the spheres
local sphereRadius = 1
local numberOfSpheres = 5 -- Number of child spheres to create
local constraintLength = .15 -- Desired length of the RodConstraint
local numberOfTentacles = 5 -- Number of tentacles to create
local numberOfMonsters = 1 -- Number of monsters to create
local spawnRadius = 100 -- Radius within which monsters will spawn

local MoveSpeed = 0
local RotationSpeed = 00--500000

-- Function to create a sphere part
function MonsterService:CreateCylinderPart(size, position, parent, anchored)
    local part = Instance.new("Part")
    part.Shape = Enum.PartType.Cylinder
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
function MonsterService:CreateChildCylinder(rootPart)
    local previousPart = rootPart
    local currentRadius = sphereRadius

    for i = 1, numberOfSpheres do
        currentRadius = currentRadius * 0.8 -- Reduce the size of each subsequent sphere
        local offset = (previousPart.Size.X / 2) + (currentRadius) -- Calculate position offset to make spheres touch
        local childPosition = previousPart.Position + Vector3.new(offset, 0, 0) -- Position next to the previous sphere

        local childPart = self:CreateCylinderPart(currentRadius, childPosition, previousPart, false) -- Create and parent the next child sphere

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
function MonsterService:CreateTentacle(position, index, parent, core)
    local tentacleModel = Instance.new("Model")
    tentacleModel.Name = "Tentacle" .. index
    tentacleModel.Parent = parent -- Parent the model to the provided parent

    local rootPart = self:CreateCylinderPart(sphereRadius, position, tentacleModel, false) -- Create and parent the main sphere, not anchored
    self:CreateChildCylinder(rootPart) -- Create and parent child spheres to the main sphere

    -- Create attachment on the core part for this tentacle
    local coreAttachment = Instance.new("Attachment")
    coreAttachment.Name = "Attachment" .. index
    coreAttachment.Position = Vector3.new(math.cos(math.rad((index - 1) * (360 / numberOfTentacles))) , 0, math.sin(math.rad((index - 1) * (360 / numberOfTentacles))) )
    coreAttachment.Parent = core

    -- Create attachment on the root part of the tentacle
    local rootAttachment = Instance.new("Attachment")
    rootAttachment.Parent = rootPart

    -- Create a rod constraint between the core attachment and the root attachment
    local rodConstraint = Instance.new("RodConstraint")
    rodConstraint.Attachment0 = coreAttachment
    rodConstraint.Attachment1 = rootAttachment
    rodConstraint.Length = 2.5 -- Set the length of the constraint to the desired value

    rodConstraint.Parent = rootPart

    --rodConstraint.Length = (coreAttachment.Position - rootAttachment.Position).Magnitude -- Set the length of the rod constraint dynamically
end

function MonsterService:MoveCoreTowardsPlayer(corePart, Character)
   -- local localPlayer = Players.LocalPlayer
   -- local character = player.Character or player.CharacterAdded:Wait()
    local humanoidRootPart = Character:WaitForChild("HumanoidRootPart")

    -- Create attachment on the core part
    local coreAttachment = Instance.new("Attachment")
    coreAttachment.Parent = corePart

    -- Create the LinearVelocity constraint
    local linearVelocity = Instance.new("LinearVelocity")
    linearVelocity.Attachment0 = coreAttachment
    linearVelocity.RelativeTo = Enum.ActuatorRelativeTo.World -- Apply force in world coordinates
    linearVelocity.MaxForce = MoveSpeed -- Adjust the maximum force as needed
    linearVelocity.VectorVelocity = (humanoidRootPart.Position - corePart.Position).Unit * 10 -- Set the velocity towards the player's position
    linearVelocity.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
    linearVelocity.Parent = corePart

    -- Create the AngularVelocity constraint
    local angularVelocity = Instance.new("AngularVelocity")
    angularVelocity.Attachment0 = coreAttachment
    angularVelocity.RelativeTo = Enum.ActuatorRelativeTo.World -- Apply rotation in world coordinates
    angularVelocity.MaxTorque = RotationSpeed -- Adjust the maximum torque as needed
    angularVelocity.Parent = corePart

   
  
    local function Update()
        local direction = (humanoidRootPart.Position - corePart.Position).Unit
        linearVelocity.VectorVelocity = direction * 10
        
        -- Calculate the rotation axis and angular velocity
        local rotationAxis = Vector3.new(0, 1, 0):Cross(direction).Unit
        local angularVelocityVector = rotationAxis * 5
        
        angularVelocity.AngularVelocity = angularVelocityVector
    end

   
    local heartBeat = RunService.Heartbeat:Connect(Update)
end

function MonsterService:GenerateRandomPosition()
    local angle = math.random() * 2 * math.pi
    local distance = math.random() * spawnRadius
    local x = math.cos(angle) * distance
    local z = math.sin(angle) * distance
    return Vector3.new(x, 5, z)
end

function MonsterService:BoilSetup(corePart)
    -- Get the size and position of the core part
    local coreSize = corePart.Size
    local corePosition = corePart.Position

    -- Define the offset distance
    local offsetDistance = 2

    -- Create a table to store the offsets
    local offsets = {
        Vector3.new(offsetDistance, 0, 0),
        Vector3.new(-offsetDistance, 0, 0),
        Vector3.new(0, offsetDistance, 0),
        Vector3.new(0, -offsetDistance, 0),
        Vector3.new(0, 0, offsetDistance)
    }

    -- Loop through the offsets and create new parts
    for _, offset in ipairs(offsets) do
        -- Create a new part
        local newPart = Instance.new("Part")
        newPart.Shape = Enum.PartType.Ball
        newPart.Color = Color3.new(0.941176, 1, 0.270588)
        newPart.Size = coreSize / 2 -- Half the size of the core part
        newPart.Position = corePosition + offset
        newPart.CanCollide = false
        newPart.Anchored = false
        newPart.Name = "boil"

        newPart.Parent = corePart

        -- Create a WeldConstraint to attach the new part to the core part
        local weld = Instance.new("WeldConstraint")
        weld.Part0 = corePart
        weld.Part1 = newPart
        weld.Parent = corePart

        CollectionService:AddTag(newPart, "boil")

    end


    return corePart
end



function MonsterService:SpawnMonster(position, character)
    local monsterModel = Instance.new("Model")
    monsterModel.Name = "Monster"
    monsterModel.Parent = Workspace -- Add the model to the Workspace

    -- Create the core part
    local corePart = Instance.new("Part")
    corePart.Name = "Core"
    corePart.Shape = Enum.PartType.Ball -- Set the core part to be a ball shape
    corePart.Size = Vector3.new(5, 5, 5)
    corePart.Anchored = false
    corePart.Position = position
    local materialVariantName = "GoryMaterial" -- Replace with the desired material variant name
    corePart.Material = Enum.Material.Salt
    corePart.MaterialVariant = materialVariantName
    corePart = MonsterService:BoilSetup(corePart)
    corePart.Parent = monsterModel

    for i = 1, numberOfTentacles do
        local angle = (i - 1) * (360 / numberOfTentacles)
        local radians = math.rad(angle)
        local x = math.cos(radians) * 20 -- Adjust the 20 to change the distance from the center
        local z = math.sin(radians) * 20
        local tentaclePosition = position + Vector3.new(x, 0, z)

        self:CreateTentacle(tentaclePosition, i, monsterModel, corePart)
    end

    self:MoveCoreTowardsPlayer(corePart ,character) -- Move the core part towards the local player
end

function MonsterService:SetPlayer(_Character)
   
    for i = 1, numberOfMonsters do
        local randomPosition = self:GenerateRandomPosition()
        self:SpawnMonster(randomPosition, _Character)
    end
   

end

function MonsterService:KnitStart()


    require(PlayerAddedFunctions)(
        function(JoiningPlayer)

           
        end,
        function(LeavingPlayer)
           

        end,
        function(Player, Character)
            --player = Character
            --HumanoidRootPart =  Character:WaitForChild("HumanoidRootPart")
            self:SetPlayer(Character)
        end
    )
 
 
end 

function MonsterService:KnitInit()
   

end

return MonsterService
