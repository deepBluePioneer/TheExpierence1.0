local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CustomPackages = ReplicatedStorage.CustomPackages
local Packages = ReplicatedStorage.Packages
local Knit = require(Packages.Knit)
local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")

local CameraVehicleController = Knit.CreateController { Name = "CameraVehicleController" }

local CustomCamera = CustomPackages.CustomCamera
local CameraSystem = require(CustomCamera.CameraSystem.CameraSystem)
local Config = require(CustomCamera.CameraSystem.Configurations)

function CameraVehicleController:init()
  

    local VehicleService = Knit.GetService("VehicleService")
    CameraSystem.FollowMouse()

    -- Connect to the SeatOccupied event
    VehicleService.SeatOccupied:Connect(function(vehicleModel)
        self.vehicleModel = vehicleModel
        self.primaryPart = vehicleModel.PrimaryPart
        self.lastPosition = self.primaryPart.Position
        self.lastVelocity = self.primaryPart.Velocity

       
         --Config.CamLockOffset = Vector3.new(1, 5, 20)
    end)

    -- Update the camera offset based on the vehicle's speed and turning direction
    --self:updateLoop()
end

function CameraVehicleController:updateLoop()
    if self.primaryPart then
        local speed = self.primaryPart.Velocity.Magnitude
        local isTurning = self:IsTurning()

        if isTurning then
            self:UpdateCameraOffset(speed)
        else
            self:ResetCameraOffset()
        end

        -- Update the last velocity
        self.lastVelocity = self.primaryPart.Velocity
    end

    -- Schedule the next update
    delay(0.1, function()
        self:updateLoop()
    end)
end

function CameraVehicleController:IsTurning()
    local currentVelocity = self.primaryPart.Velocity
    local currentDirection = currentVelocity.Unit
    local lastDirection = self.lastVelocity.Unit

    -- Check if the angle between the current direction and the last direction is significant
    local angle = math.acos(currentDirection:Dot(lastDirection))
    return angle > 0.5 -- Adjust the threshold as needed
end

function CameraVehicleController:UpdateCameraOffset(speed)
    -- Adjust the X value of the camera offset based on speed and turning direction
    local offsetX = 1 + speed * 0.1 -- Adjust the multiplier as needed
    local targetOffset = Vector3.new(offsetX, 3, 15)

    -- Only create and play the tween if the target offset is different from the current offset
    if self.camLockOffsetBindable.Value ~= targetOffset then
        local tweenInfo = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
        local tween = TweenService:Create(self.camLockOffsetBindable, tweenInfo, { Value = targetOffset })
        tween:Play()
    end
end

function CameraVehicleController:ResetCameraOffset()
    -- Reset the X value of the camera offset to the default position
    local targetOffset = Vector3.new(1, 3, 15)

    -- Only create and play the tween if the target offset is different from the current offset
    if self.camLockOffsetBindable.Value ~= targetOffset then
        local tweenInfo = TweenInfo.new(0.2, Enum.EasingStyle.Linear, Enum.EasingDirection.Out)
        local tween = TweenService:Create(self.camLockOffsetBindable, tweenInfo, { Value = targetOffset })
        tween:Play()
    end
end

function CameraVehicleController:KnitStart()
 --self:init()
end

function CameraVehicleController:KnitInit()
    -- Disable camera zoom
end

return CameraVehicleController
