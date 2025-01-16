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

    -- Hover parameters
    local targetHeight = 10 -- Target hover height
    local proportionalGain = 200 -- Adjust for stricter height control
    local dampingGain = 50 -- Adjust for vertical damping
    local defaultSpringConstant = 5 -- Default spring constant for horizontal oscillation
    local tightenedSpringConstant = 50 -- Spring constant when aligned with the target
    local dampingFactor = 0.85 -- Damping factor for inertia

    -- Gizmo properties
    Gizmo.PushProperty("Transparency", 0.5)

    -- Track the target player's HumanoidRootPart and Highlight
    local targetPlayerRootPart = nil
    local playerHighlight = Instance.new("Highlight")
    playerHighlight.Enabled = false
    playerHighlight.FillColor = Color3.new(1, 0, 0) -- Red for highlight
    playerHighlight.OutlineColor = Color3.new(1, 1, 1) -- White outline

    -- Player management
    require(PlayerAddedFunctions)(
        function(JoiningPlayer)
            -- Player added logic
        end,
        function(LeavingPlayer)
            -- Player leaving logic
        end,
        function(Player, Character)
            -- Update target player root part and attach highlight
            if Character then
                targetPlayerRootPart = Character:FindFirstChild("HumanoidRootPart")
                if targetPlayerRootPart then
                    playerHighlight.Adornee = Character
                    playerHighlight.Parent = Workspace
                end
            end
        end
    )

    -- Velocity for inertia (X and Z axes)
    local horizontalVelocity = Vector3.zero -- Initial velocity for the missile

    -- Update force and rotation dynamically
    game:GetService("RunService").RenderStepped:Connect(function()
        -- Raycast downward to detect ground
        local rayParams = RaycastParams.new()
        rayParams.FilterDescendantsInstances = {missile}
        rayParams.FilterType = Enum.RaycastFilterType.Blacklist

        local rayOrigin = missile.Position
        local rayDirection = Vector3.new(0, -1000, 0)
        local rayResult = Workspace:Raycast(rayOrigin, rayDirection, rayParams)

        local hoverForce = Vector3.zero -- To maintain vertical stability

        if rayResult then
            local distance = (rayOrigin - rayResult.Position).Magnitude
            local error = targetHeight - distance

            -- Calculate hover force using PID-like control
            local antiGravity = missile.AssemblyMass * Workspace.Gravity
            local verticalVelocity = missile.AssemblyLinearVelocity.Y
            local proportionalForce = error * proportionalGain
            local dampingForce = -verticalVelocity * dampingGain

            local verticalForce = antiGravity + proportionalForce + dampingForce
            hoverForce = Vector3.new(0, verticalForce, 0)

            -- Draw Gizmo arrow for raycast
            Gizmo.PushProperty("Color3", Color3.new(0, 1, 0)) -- Green for raycast
            Gizmo.Arrow:Draw(rayOrigin, rayOrigin + rayDirection.Unit * 5, 0.1, 0.3, 0.5, true)
        else
            -- No ground detected, apply minimal force to stabilize
            hoverForce = Vector3.new(0, missile.AssemblyMass * Workspace.Gravity, 0)
        end

        -- Rotate and overshoot towards the player (X and Z axes)
        if targetPlayerRootPart then
            local targetPosition = targetPlayerRootPart.Position
            local missilePosition = missile.Position

            -- Calculate spring force for overshooting (X and Z axes)
            local horizontalDisplacement = Vector3.new(
                targetPosition.X - missilePosition.X,
                0,
                targetPosition.Z - missilePosition.Z
            )
            local alignment = horizontalVelocity.Unit:Dot(horizontalDisplacement.Unit)
            local alignmentThreshold = 0.95 -- Adjust threshold for alignment sensitivity

            -- Adjust spring constant based on alignment
            local springConstant = alignment >= alignmentThreshold and tightenedSpringConstant or defaultSpringConstant

            -- Update spring force
            local springForce = horizontalDisplacement * springConstant
            horizontalVelocity = (horizontalVelocity + springForce) * dampingFactor -- Apply damping

            -- Combine forces (X, Y, Z)
            local combinedForce = Vector3.new(horizontalVelocity.X, hoverForce.Y, horizontalVelocity.Z)
            vectorForce.Force = combinedForce

            -- Enable or disable highlight based on alignment
            if alignment >= alignmentThreshold then
                playerHighlight.Enabled = true
            else
                playerHighlight.Enabled = false
            end

            -- Calculate rotation axis and angle for LookVector alignment
            local currentLookVector = missile.CFrame.LookVector
            local targetDirection = horizontalDisplacement.Unit
            local rotationAxis = currentLookVector:Cross(targetDirection)
            local rotationAngle = math.acos(math.clamp(currentLookVector:Dot(targetDirection), -1, 1))

            if rotationAxis.Magnitude > 0.001 then
                local rotation = CFrame.fromAxisAngle(rotationAxis.Unit, rotationAngle)
                missile.CFrame = missile.CFrame * rotation
            end

            -- Visualize Gizmo arrows
            Gizmo.PushProperty("Color3", Color3.new(1, 1, 1)) -- White for horizontal velocity
            Gizmo.Arrow:Draw(missilePosition, missilePosition + horizontalVelocity.Unit * 100, 0.1, 0.3, 0.5, true)
        end
    end)
end

function HoverController:KnitInit()
    -- Add controller initialization logic here
end

return HoverController
