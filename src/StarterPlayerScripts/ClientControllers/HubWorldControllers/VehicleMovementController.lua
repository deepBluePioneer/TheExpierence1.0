local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local CustomPackages = ReplicatedStorage.CustomPackages
local Packages = ReplicatedStorage.Packages
local Knit = require(Packages.Knit)
local signal = require(Packages.Signal)

local VehicleMovementController = Knit.CreateController {
     Name = "VehicleMovementController" ,
     OnMoveVehicle = signal.new() -- Create the signal within the table

    
}

local Keyboard = require(Packages.Input).Keyboard
local keyboard
local Camera = workspace.CurrentCamera
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Player = Players.LocalPlayer

function VehicleMovementController:KnitStart()
    task.wait(3)

    local VehicleService = Knit.GetService("VehicleService")

    VehicleService:GetPlayerVehicle():andThen(function(vehicleModel)
        if vehicleModel then
            self.VehicleModel = vehicleModel
            self.PrimaryPart = vehicleModel.PrimaryPart
            self:InitializeAlignOrientation()


        else
            warn("No vehicle model found for the player")
        end
    end):catch(function(err)
        warn("Failed to get vehicle model:", err)
    end)

    local WeaponController = Knit.GetController("WeaponController")



    WeaponController.FireRaySignal:Connect(function(rayData)
        -- Handle the rayData
        --self:UpdateOrientation(rayData.direction)
    end)

     -- Call UpdateOrientation in RenderStepped
     RunService.RenderStepped:Connect(function()
        local cameraForward = Camera.CFrame.LookVector
        self:UpdateOrientation(cameraForward)
    end)

    keyboard = Keyboard.new()
    self:SetupMovementControls(keyboard)

end

function VehicleMovementController:SetupMovementControls(keyboard)
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

function VehicleMovementController:UpdateOrientation(targetDirection)
    if self.AlignOrientation and self.Attachment then
        -- Only consider the horizontal component of the target direction
        local horizontalDirection = Vector3.new(targetDirection.X, 0, targetDirection.Z).Unit
        local lookAtPosition = self.PrimaryPart.Position + horizontalDirection
        self.AlignOrientation.CFrame = CFrame.lookAt(self.PrimaryPart.Position, lookAtPosition)
    end
end

function VehicleMovementController:InitializeAlignOrientation()
    if self.PrimaryPart then
        -- Create an attachment for the PrimaryPart
        local attachment = Instance.new("Attachment")
        attachment.Name = "VehicleAttachment"
        attachment.Parent = self.PrimaryPart
        self.Attachment = attachment

        -- Create the AlignOrientation constraint
        self.AlignOrientation = Instance.new("AlignOrientation")
        self.AlignOrientation.Attachment0 = attachment
        self.AlignOrientation.RigidityEnabled = true -- Use rigidity for immediate alignment
        self.AlignOrientation.Responsiveness = 50 -- Adjust responsiveness as needed
        self.AlignOrientation.MaxTorque = math.huge -- Unlimited torque
        self.AlignOrientation.Mode = Enum.OrientationAlignmentMode.OneAttachment
        self.AlignOrientation.PrimaryAxisOnly = false -- Align all axes
        self.AlignOrientation.AlignType = Enum.AlignType.AllAxes -- Align all axes
        self.AlignOrientation.Parent = self.PrimaryPart
    end
end



function VehicleMovementController:MoveVehicle(linearDirection)
    if self.PrimaryPart then
        local cameraCF = Camera.CFrame
        local moveDirection = cameraCF:VectorToWorldSpace(linearDirection)

        moveDirection = Vector3.new(moveDirection.X, 0, moveDirection.Z).Unit -- Ignore Y-axis for horizontal movement
        local impulse = moveDirection * 15000 -- Adjust impulse as needed
        self.OnMoveVehicle:Fire(moveDirection)

        -- Calculate angular impulse to roll the ball
       -- local angularImpulse = Vector3.new(moveDirection.Z, 0, -moveDirection.X) * 9000 -- Adjust angular impulse as needed

        self.PrimaryPart:ApplyImpulse(impulse)
        --self.PrimaryPart:ApplyAngularImpulse(angularImpulse)

        -- Cap the maximum speed
        self:CapMaxSpeed()

        -- Apply downward force if in the air
        self:ApplyGravity()
         

    end
end

function VehicleMovementController:CapMaxSpeed()
    local maxSpeed = 100 -- Adjust the maximum speed as needed
    local velocity = self.PrimaryPart.AssemblyLinearVelocity
    local speed = velocity.Magnitude

    if speed > maxSpeed then
        local excessSpeed = speed - maxSpeed
        local counterForce = velocity.Unit * -excessSpeed * self.PrimaryPart.AssemblyMass
        self.PrimaryPart:ApplyImpulse(counterForce)
    end
end

function VehicleMovementController:ApplyGravity()
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

function VehicleMovementController:KnitInit()
    -- Add controller initialization logic here
end

return VehicleMovementController