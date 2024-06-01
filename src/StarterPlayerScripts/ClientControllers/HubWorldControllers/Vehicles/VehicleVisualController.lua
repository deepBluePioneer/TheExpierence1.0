local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local CustomPackages = ReplicatedStorage.CustomPackages
local Packages = ReplicatedStorage.Packages
local Knit = require(Packages.Knit)

local VehicleVisualController = Knit.CreateController { Name = "VehicleVisualController" }

function VehicleVisualController:KnitStart()
    local VehicleService = Knit.GetService("VehicleService")

    VehicleService.SeatOccupied:Connect(function(vehicleModel)
        local VehicleMovementController = Knit.GetController("VehicleMovementController")
        VehicleMovementController.OnMoveVehicle:Connect(function(moveDirection)
            self:HandleVehicleMovement(vehicleModel, moveDirection)
        end)
    end)

    -- Add controller startup logic here
end

function VehicleVisualController:KnitInit()
    -- Add controller initialization logic here
end

function VehicleVisualController:HandleVehicleMovement(vehicleModel, moveDirection)
    local primaryPart = vehicleModel.PrimaryPart
    if not primaryPart then return end
    
    local rotationAngle
    local direction = moveDirection.Unit

    if direction.X < 0 then
        -- Rotate slightly to the left
        rotationAngle = math.rad(45) -- Adjust the angle as needed
    elseif direction.X > 0 then
        -- Rotate slightly to the right
        rotationAngle = math.rad(-45) -- Adjust the angle as needed
    else
        rotationAngle = 0 -- No rotation if moving forward or backward
    end

    local currentCFrame = primaryPart.CFrame
    local newCFrame = currentCFrame * CFrame.Angles(0, 0, rotationAngle)

    local tweenInfo = TweenInfo.new(0.15, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)
    local tween = TweenService:Create(primaryPart, tweenInfo, {CFrame = newCFrame})
    --tween:Play()
end

return VehicleVisualController
