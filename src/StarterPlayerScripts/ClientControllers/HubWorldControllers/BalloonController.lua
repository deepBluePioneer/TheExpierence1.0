local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CustomPackages = ReplicatedStorage.CustomPackages
local Packages = ReplicatedStorage.Packages
local Knit = require(Packages.Knit)

local BalloonController = Knit.CreateController { Name = "BalloonController" }

function BalloonController:KnitStart()

    task.wait(3)

    local VehicleService = Knit.GetService("VehicleService")
    local VehicleMovementController = Knit.GetController("VehicleMovementController")

    VehicleMovementController.OnMoveVehicle:Connect(function(MovementDirection)
        -- Apply opposite force to the balloons
        self:ApplyOppositeForces(MovementDirection)
    end)

    VehicleService:GetPlayerVehicle():andThen(function(vehicleModel)
        if vehicleModel then
            self.VehicleModel = vehicleModel
            self.PrimaryPart = vehicleModel.PrimaryPart

            -- Get the balloons from the vehicle model
            self.Balloons = {}
            self.BalloonForces = {}
            for _, child in ipairs(vehicleModel:GetChildren()) do
                warn(child)
                if child.Name == "BalloonPart" then
                    table.insert(self.Balloons, child)

                 
                end
            end

            -- Example: Change balloon color to blue
            for _, balloon in ipairs(self.Balloons) do
                balloon.BrickColor = BrickColor.new("Bright blue")
            end
        else
            warn("No vehicle model found for the player")
        end
    end):catch(function(err)
        warn("Failed to get vehicle model:", err)
    end)
end

function BalloonController:ApplyOppositeForces(MovementDirection)
    if not self.BalloonForces then return end

    for _, vectorForce in ipairs(self.BalloonForces) do
        local force = -MovementDirection * 1000 -- Adjust the multiplier as needed for force strength
        vectorForce.Force = force
    end
end

function BalloonController:KnitInit()
    -- Add controller initialization logic here
end

return BalloonController
