local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CustomPackages = ReplicatedStorage.CustomPackages
local Packages = ReplicatedStorage.Packages
local Knit = require(Packages.Knit)
local Players = game:GetService("Players")
local ContextActionService = game:GetService("ContextActionService")

local Keyboard = require(Packages.Input).Keyboard
local Mouse = require(Packages.Input).Mouse

local Player = Players.LocalPlayer
local Camera = workspace.CurrentCamera

local VehicleController = Knit.CreateController { Name = "VehicleController" }
local WeaponsService

function VehicleController:KnitStart()
    task.wait(3)
    local keyboard = Keyboard.new()
    local mouse = Mouse.new()

    local VehicleService = Knit.GetService("VehicleService")

    VehicleService:GetPlayerVehicle():andThen(function(vehicleModel)
        if vehicleModel then
            print("Player's vehicle model:", vehicleModel)
            self.VehicleModel = vehicleModel
            self.PrimaryPart = vehicleModel.PrimaryPart
            warn("Move")

            -- Disable default player controls and animations, set parts to massless, and configure humanoid
            self:DisablePlayerControlsAndAnimations()
            self:SetPlayerPartsMassless()
            self:DisableCharacterCollisions()
            self:ConfigureHumanoidSettings()

            -- Set the camera subject to the primary part of the vehicle
            Camera.CameraSubject = self.PrimaryPart

            -- Setup custom movement controls
            self:SetupMovementControls(keyboard)

            -- Setup mouse left button down event to fire a ray
            mouse.LeftDown:Connect(function()
                self:FireRay(vehicleModel.PrimaryPart)
            end)
        else
            warn("No vehicle model found for the player")
        end
    end):catch(function(err)
        warn("Failed to get vehicle model:", err)
    end)
end

function VehicleController:DisablePlayerControlsAndAnimations()
    -- Disable the default player controls by disabling the ControlModule
    local PlayerModule = require(Player:WaitForChild("PlayerScripts"):WaitForChild("PlayerModule"))
    local ControlModule = PlayerModule:GetControls()
    ControlModule:Disable()

    -- Disable the player's animations
    local character = Player.Character or Player.CharacterAdded:Wait()
    local animateScript = character:FindFirstChild("Animate")
    if animateScript then
        animateScript.Disabled = true
    end
end

function VehicleController:SetPlayerPartsMassless()
    -- Set all base parts of the player's character to massless
    local character = Player.Character or Player.CharacterAdded:Wait()
    for _, part in ipairs(character:GetDescendants()) do
        if part:IsA("BasePart") then
            part.Massless = true
        end
    end
end

function VehicleController:DisableCharacterCollisions()
    -- Disable collisions between the player's character and the vehicle
    local character = Player.Character or Player.CharacterAdded:Wait()
    for _, part in ipairs(character:GetDescendants()) do
        if part:IsA("BasePart") then
            part.CanCollide = false
        end
    end
end

function VehicleController:ConfigureHumanoidSettings()
    -- Configure humanoid settings
    local character = Player.Character or Player.CharacterAdded:Wait()
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    if humanoid then
        humanoid.WalkSpeed = 0                  -- Disable walking
        humanoid.JumpPower = 0                  -- Disable jumping
        humanoid.AutoRotate = false             -- Prevent automatic rotation
        humanoid:SetStateEnabled(Enum.HumanoidStateType.Physics, false) -- Disable physics state
        humanoid:ChangeState(Enum.HumanoidStateType.Physics) -- Force into physics state
        humanoid.EvaluateStateMachine = false   -- Disable state machine evaluation
        -- Add any other humanoid settings you want to configure here
    end
end

function VehicleController:SetupMovementControls(keyboard)
    self.isMoving = {
        W = false,
        A = false,
        S = false,
        D = false
    }

    keyboard.KeyDown:Connect(function(key)
        if key == Enum.KeyCode.D then
            self.isMoving.D = true
        elseif key == Enum.KeyCode.A then
            self.isMoving.A = true
        elseif key == Enum.KeyCode.W then
            self.isMoving.W = true
        elseif key == Enum.KeyCode.S then
            self.isMoving.S = true
        end
    end)

    keyboard.KeyUp:Connect(function(key)
        if key == Enum.KeyCode.D then
            self.isMoving.D = false
        elseif key == Enum.KeyCode.A then
            self.isMoving.A = false
        elseif key == Enum.KeyCode.W then
            self.isMoving.W = false
        elseif key == Enum.KeyCode.S then
            self.isMoving.S = false
        end
    end)

    -- Start a loop to apply impulses
    task.spawn(function()
        while true do
            if self.isMoving.W then
                self:MoveVehicle(Vector3.new(0, 0, -1))
            end
            if self.isMoving.A then
                self:MoveVehicle(Vector3.new(-1, 0, 0))
            end
            if self.isMoving.S then
                self:MoveVehicle(Vector3.new(0, 0, 1))
            end
            if self.isMoving.D then
                self:MoveVehicle(Vector3.new(1, 0, 0))
            end
            task.wait(0.1) -- Adjust the frequency of impulses for smoother acceleration
        end
    end)
end

function VehicleController:MoveVehicle(linearDirection)
    if self.PrimaryPart then
        local cameraCF = Camera.CFrame
        local moveDirection = cameraCF:VectorToWorldSpace(linearDirection)
        moveDirection = Vector3.new(moveDirection.X, 0, moveDirection.Z).Unit -- Ignore Y-axis for horizontal movement
        local impulse = moveDirection * 15000 -- Adjust impulse as needed

        -- Calculate angular impulse to roll the ball
        local angularImpulse = Vector3.new(moveDirection.Z, 0, -moveDirection.X) * 9000 -- Adjust angular impulse as needed

        self.PrimaryPart:ApplyImpulse(impulse)
        self.PrimaryPart:ApplyAngularImpulse(angularImpulse)

        -- Cap the maximum speed
        self:CapMaxSpeed()

        -- Apply downward force if in the air
        self:ApplyGravity()
    end
end

function VehicleController:CapMaxSpeed()
    local maxSpeed = 50 -- Adjust the maximum speed as needed
    local velocity = self.PrimaryPart.AssemblyLinearVelocity
    local speed = velocity.Magnitude

    if speed > maxSpeed then
        local excessSpeed = speed - maxSpeed
        local counterForce = velocity.Unit * -excessSpeed * self.PrimaryPart.AssemblyMass
        self.PrimaryPart:ApplyImpulse(counterForce)
    end
end

function VehicleController:ApplyGravity()
    local rayOrigin = self.PrimaryPart.Position
    local rayDirection = Vector3.new(0, -10, 0) -- Ray downwards to check ground
    local raycastParams = RaycastParams.new()
    raycastParams.FilterDescendantsInstances = {self.VehicleModel, Player.Character}
    raycastParams.FilterType = Enum.RaycastFilterType.Exclude

    local result = workspace:Raycast(rayOrigin, rayDirection, raycastParams)
    if not result then
        -- Vehicle is in the air, apply downward force
        local gravityForce = Vector3.new(0, -196.2 * self.PrimaryPart.AssemblyMass, 0) -- Adjust gravity force as needed
        self.PrimaryPart:ApplyImpulse(gravityForce)
    end
end
function VehicleController:FireRay(PrimaryPart)
    if self.PrimaryPart then
        local origin = self.PrimaryPart.Position

        -- Create RaycastParams
        local params = RaycastParams.new()
        params.FilterType = Enum.RaycastFilterType.Exclude
        params.FilterDescendantsInstances = {self.VehicleModel, Player.Character}
        params.IgnoreWater = true

        -- Perform the raycast from the mouse position
        local result = Mouse:Raycast(params, 1000)

        local targetPoint
        if result then
            -- If the raycast hits something, use the hit position
            targetPoint = result.Position
        else
            -- If the raycast doesn't hit anything, use the projected position
            targetPoint = Mouse:Project(1000)
        end

        -- Ensure the target point is at the same height as the origin
        targetPoint = Vector3.new(targetPoint.X, origin.Y, targetPoint.Z)

        -- Calculate the direction from the vehicle's position to the target point
        local direction = (targetPoint - origin).Unit * 1000 -- Adjust ray length as needed

        local rayData = {
            origin = origin,
            direction = direction
        }
        WeaponsService:SendRay(rayData, PrimaryPart)
    end
end






function VehicleController:KnitInit()

    WeaponsService = Knit.GetService("WeaponsService")

    -- Add controller initialization logic here
end

return VehicleController
