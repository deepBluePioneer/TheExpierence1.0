local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local Knit = require(ReplicatedStorage.Packages.Knit)
local Gizmo = require(ReplicatedStorage.Packages.imgizmo)
local CustomPackages = ReplicatedStorage.CustomPackages
local PlayerAddedController = CustomPackages.PlayerAddedController
local PlayerAddedFunctions = PlayerAddedController.PlayerAddedFunctions

local HoverController = Knit.CreateController { Name = "HoverController" }

function HoverController:KnitStart()
    local sawModel = Workspace:FindFirstChild("Saw")
    local missile = sawModel:FindFirstChild("SawBlade") -- The hover object

    if not missile then
        warn("Missile not found!")
        return
    end

    -- Add attachments
    local attachment = Instance.new("Attachment")
    attachment.Name = "HoverAttachment"
    attachment.Parent = missile

    -- Configure VectorForce
    local vectorForce = Instance.new("VectorForce")
    vectorForce.Name = "HoverForce"
    vectorForce.Attachment0 = attachment
    vectorForce.RelativeTo = Enum.ActuatorRelativeTo.World
    vectorForce.ApplyAtCenterOfMass = true
    vectorForce.Force = Vector3.zero -- Initial force
    vectorForce.Parent = missile

    -- Configure AlignOrientation
    local alignOrientation = Instance.new("AlignOrientation")
    alignOrientation.Name = "HoverAlign"
    alignOrientation.Attachment0 = attachment
    alignOrientation.Responsiveness = 20 -- Adjust as needed
    alignOrientation.MaxTorque = math.huge
    alignOrientation.Mode = Enum.OrientationAlignmentMode.OneAttachment
    alignOrientation.Parent = missile

    -- Hover parameters
    local targetHeight = 10 -- Target hover height
    local damping = 0.9 -- Damping factor for velocity stabilization
    local forwardForceMagnitude = 5000 -- Adjust for desired forward speed

    -- Gizmo properties
    Gizmo.PushProperty("Transparency", 0.5)

    -- Track the target player's HumanoidRootPart
    local targetPlayerRootPart = nil

    -- Player management
    require(PlayerAddedFunctions)(
        function(JoiningPlayer)
            -- Player added logic
        end,
        function(LeavingPlayer)
            -- Player leaving logic
        end,
        function(Player, Character)
            -- Update target player root part
            if Character then
                targetPlayerRootPart = Character:FindFirstChild("HumanoidRootPart")
            end
        end
    )

    -- Update force and rotation dynamically
    game:GetService("RunService").RenderStepped:Connect(function()
        -- Raycast downward to detect ground
        local rayParams = RaycastParams.new()
        rayParams.FilterDescendantsInstances = {missile}
        rayParams.FilterType = Enum.RaycastFilterType.Blacklist

        local rayOrigin = missile.Position
        local rayDirection = Vector3.new(0, -1000, 0)
        local rayResult = Workspace:Raycast(rayOrigin, rayDirection, rayParams)

        if rayResult then
            local distance = (rayOrigin - rayResult.Position).Magnitude
            local error = targetHeight - distance

            -- Calculate hover force
            local antiGravity = missile.AssemblyMass * Workspace.Gravity
            local hoverForce = antiGravity + (error * 100) -- Adjust multiplier for responsiveness

            -- Apply hover force (Y-axis)
            vectorForce.Force = Vector3.new(vectorForce.Force.X, hoverForce, vectorForce.Force.Z)

            -- Align to ground normal
            alignOrientation.CFrame = CFrame.new(Vector3.new(), rayResult.Normal) * CFrame.Angles(-math.pi / 2, 0, 0)

            -- Draw Gizmo arrows
            Gizmo.PushProperty("Color3", Color3.new(0, 1, 0)) -- Green for raycast
            Gizmo.Arrow:Draw(rayOrigin, rayOrigin + rayDirection.Unit * 5, 0.1, 0.3, 0.5, true)

            Gizmo.PushProperty("Color3", Color3.new(0, 0, 1)) -- Blue for missile's look rotation
            local missileLookDir = missile.CFrame.LookVector
            Gizmo.Arrow:Draw(rayOrigin, rayOrigin + missileLookDir * 5, 0.1, 0.3, 0.5, true)
        else
            -- No ground detected, apply minimal force to stabilize
            vectorForce.Force = Vector3.new(vectorForce.Force.X, missile.AssemblyMass * Workspace.Gravity, vectorForce.Force.Z)
        end

        -- Rotate towards the player if the target exists
        if targetPlayerRootPart then
            local targetPosition = targetPlayerRootPart.Position
            local missilePosition = missile.Position
            local directionToTarget = (targetPosition - missilePosition).Unit
        
            local currentLookVector = missile.CFrame.LookVector
            local rotationAxis = currentLookVector:Cross(directionToTarget) -- Axis of rotation
            local angle = math.acos(currentLookVector:Dot(directionToTarget)) -- Angle of rotation
        
            -- Apply rotation directly using AngularVelocity
            local angularVelocity = rotationAxis.Unit * angle * rotationSpeed
            bodyAngularVelocity.AngularVelocity = angularVelocity
        end

        -- Apply forward force using the missile's current LookVector
        local forwardVector = missile.CFrame.LookVector
        local forwardForce = forwardVector * forwardForceMagnitude
        forwardForce = Vector3.new(forwardForce.X, 0, forwardForce.Z) -- Restrict to X and Z axes
        vectorForce.Force = Vector3.new(forwardForce.X, vectorForce.Force.Y, forwardForce.Z)

        -- Draw Gizmo arrow for forward force (blue arrow direction)
        Gizmo.PushProperty("Color3", Color3.new(0, 0, 1)) -- Blue for LookVector forward force
        Gizmo.Arrow:Draw(missile.Position, missile.Position + forwardVector * 5, 0.1, 0.3, 0.5, true)

        -- Apply damping to reduce excessive oscillation
        missile.AssemblyLinearVelocity *= damping
    end)
end

function HoverController:KnitInit()
    -- Add controller initialization logic here
end

return HoverController
