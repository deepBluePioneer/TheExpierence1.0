local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CustomPackages = ReplicatedStorage.CustomPackages
local Packages = ReplicatedStorage.Packages
local Knit = require(Packages.Knit)
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local springModule = require(script.Parent.spring)

local CameraVehicleController = Knit.CreateController { Name = "CameraVehicleController" }
local Camera = workspace.CurrentCamera

-- Constants for camera adjustment
local baseOffset = Vector3.new(0, -10, -25) -- Position behind and above the vehicle
local lateralOffsetMagnitude = 10 -- Magnitude of lateral offset

local currentVehicleModel = nil
local position = nil
local velocity = nil
local goal = nil
local spring = nil
local leftPart, rightPart

function init()

    local VehicleService = Knit.GetService("VehicleService")

    VehicleService.SeatOccupied:Connect(function(vehicleModel)

        local player = Players.LocalPlayer
        player.CameraMinZoomDistance = 20 -- Set to the desired fixed zoom distance
        player.CameraMaxZoomDistance = 20 -- Set to the same fixed zoom distance to disable zoom

        currentVehicleModel = vehicleModel
        Camera.CameraType = Enum.CameraType.Scriptable -- Set the camera to Scriptable for custom behavior
        Camera.CameraSubject = nil

        position = {RightVector = Camera.CFrame.RightVector, UpVector = Camera.CFrame.UpVector, Position = Camera.CFrame.Position}
        velocity = {RightVector = Vector3.new(), UpVector = Vector3.new(), Position = Vector3.new()}
        goal = {RightVector = vehicleModel.PrimaryPart.CFrame.RightVector, UpVector = vehicleModel.PrimaryPart.CFrame.UpVector, Position = vehicleModel.PrimaryPart.Position + baseOffset}

        spring = springModule.new(position, velocity, goal)
        spring.frequency = 2
        spring.dampener = 1

        -- Create parts on the left and right of the primary part
        local primaryPart = currentVehicleModel.PrimaryPart
        local partSize = Vector3.new(2, 2, 2)

        -- Create the left part
        leftPart = Instance.new("Part")
        leftPart.Size = partSize
        leftPart.Anchored = false
        leftPart.CanCollide = false
        leftPart.Position = primaryPart.Position - primaryPart.CFrame.RightVector * lateralOffsetMagnitude
        leftPart.Parent = currentVehicleModel

        -- Create the right part
        rightPart = Instance.new("Part")
        rightPart.Size = partSize
        rightPart.Anchored = false
        rightPart.CanCollide = false
        rightPart.Position = primaryPart.Position + primaryPart.CFrame.RightVector * lateralOffsetMagnitude
        rightPart.Parent = currentVehicleModel

        -- Weld the left part to the primary part
        local leftWeld = Instance.new("WeldConstraint")
        leftWeld.Part0 = primaryPart
        leftWeld.Part1 = leftPart
        leftWeld.Parent = primaryPart

        -- Weld the right part to the primary part
        local rightWeld = Instance.new("WeldConstraint")
        rightWeld.Part0 = primaryPart
        rightWeld.Part1 = rightPart
        rightWeld.Parent = primaryPart
    end)

    RunService.Stepped:Connect(function(t, dt)
        if currentVehicleModel and currentVehicleModel.PrimaryPart then
            local primaryPart = currentVehicleModel.PrimaryPart

            -- Calculate the vehicle's direction and speed
            local velocity = primaryPart.AssemblyLinearVelocity
            local speed = velocity.Magnitude
            local direction = velocity.Unit

            -- Determine the target lateral offset based on direction and speed
            local targetOffset = Vector3.new()
            if speed > 0 then
                local dotProduct = direction:Dot(primaryPart.CFrame.RightVector)
                if dotProduct > 0 then
                    targetOffset = primaryPart.CFrame.RightVector * lateralOffsetMagnitude
                else
                    targetOffset = -primaryPart.CFrame.RightVector * lateralOffsetMagnitude
                end
            end

            -- Update the goal every step
            goal = {RightVector = primaryPart.CFrame.RightVector, UpVector = primaryPart.CFrame.UpVector, Position = primaryPart.Position + baseOffset *-1 + targetOffset}
            spring.goal = goal

            -- Call :update(), it returns a CFrame
            Camera.CFrame = CFrame.new(spring:update(dt).Position)
        end
    end)
    
end

function CameraVehicleController:KnitStart()

end

function CameraVehicleController:KnitInit()
    -- Disable camera zoom
end

return CameraVehicleController
