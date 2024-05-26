local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CustomPackages = ReplicatedStorage.CustomPackages
local Packages = ReplicatedStorage.Packages
local Knit = require(Packages.Knit)
local RunService = game:GetService("RunService")

local VehicleService = Knit.CreateService {
    Name = "VehicleService",
    Client = {},
}

function VehicleService:GetHoverCraftModels()
    -- Get all instances tagged with "hoverCraftModel"
    local hoverCraftModels = CollectionService:GetTagged("hoverCraftModel")
    
    -- Table to store primary parts of the hoverCraftModels
    local primaryParts = {}
    
    for _, model in ipairs(hoverCraftModels) do
        if model:IsA("Model") then
            local primaryPart = model.PrimaryPart
            if primaryPart then
                table.insert(primaryParts, primaryPart)
            else
                warn("Model " .. model.Name .. " does not have a PrimaryPart set.")
            end
        end
    end
    
    return primaryParts
end

function VehicleService:ApplyHoveringForce()
    local primaryParts = self:GetHoverCraftModels()
    local hoverHeight = 10 -- Desired hover height in studs

    for _, primaryPart in ipairs(primaryParts) do
        -- Create an Attachment for the AlignPosition
        local attachment = Instance.new("Attachment")
        attachment.Parent = primaryPart
        
       

        -- Ensure the VehicleSeat works properly
        local vehicleSeat = primaryPart:FindFirstChildOfClass("VehicleSeat")
        if vehicleSeat then
            vehicleSeat.MaxSpeed = 50 -- Set the maximum speed
            vehicleSeat.Torque = 10000 -- Set the torque for acceleration
            vehicleSeat.TurnSpeed = 10000 -- Set the turn speed
            vehicleSeat.HeadsUpDisplay = true -- Enable the HUD display
            
            -- Create a LinearVelocity for movement
            local linearVelocity = Instance.new("LinearVelocity")
            linearVelocity.MaxForce = 4000 -- Adjust the max force as needed
            linearVelocity.RelativeTo = Enum.ActuatorRelativeTo.Attachment0
            linearVelocity.Attachment0 = attachment
            linearVelocity.Parent = primaryPart
            
            -- Create an AngularVelocity for rotation
            local angularVelocity = Instance.new("AngularVelocity")
            angularVelocity.MaxTorque = 10000 -- Adjust the max torque as needed
            angularVelocity.RelativeTo = Enum.ActuatorRelativeTo.Attachment0
            angularVelocity.Attachment0 = attachment
            angularVelocity.Parent = primaryPart
            
            -- Connect to the VehicleSeat's Changed event
            vehicleSeat.Changed:Connect(function()
                -- Update LinearVelocity based on throttle
                local throttle = vehicleSeat.ThrottleFloat
                local steer = vehicleSeat.SteerFloat
                local direction = primaryPart.CFrame.LookVector * throttle * vehicleSeat.MaxSpeed
                linearVelocity.VectorVelocity = Vector3.new(direction.X, linearVelocity.VectorVelocity.Y, direction.Z)
                
                -- Update AngularVelocity based on steer
                angularVelocity.AngularVelocity = Vector3.new(steer * vehicleSeat.TurnSpeed, 0, 0)
            end)
        end
    end
end

function VehicleService:KnitStart()
    self:ApplyHoveringForce()
end

function VehicleService:KnitInit()
    -- Add service initialization logic here
end

return VehicleService
