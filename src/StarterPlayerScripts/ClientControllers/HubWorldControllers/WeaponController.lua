local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CustomPackages = ReplicatedStorage.CustomPackages
local Packages = ReplicatedStorage.Packages
local Knit = require(Packages.Knit)
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local WeaponController = Knit.CreateController { Name = "WeaponController" }
local Mouse = require(Packages.Input).Mouse
local Player = Players.LocalPlayer

local WeaponsService



function WeaponController:KnitStart()
    task.wait(3)

    local VehicleService = Knit.GetService("VehicleService")

    VehicleService:GetPlayerVehicle():andThen(function(vehicleModel)
        if vehicleModel then
            self.VehicleModel = vehicleModel
            self.PrimaryPart = vehicleModel.PrimaryPart      
        else
            warn("No vehicle model found for the player")
        end
    end):catch(function(err)
        warn("Failed to get vehicle model:", err)
    end)
    

    local mouse = Mouse.new()

             -- Setup mouse left button down event to start firing rays
    mouse.LeftDown:Connect(function()
        self:StartAutomaticFiring()
    end)

    -- Setup mouse left button up event to stop firing rays
    mouse.LeftUp:Connect(function()
        self:StopAutomaticFiring()
    end)

end

function WeaponController:StartAutomaticFiring()
    self.isFiring = true
    self.lastFireTime = 0
    self.fireRate = 0.1 -- Fire rate in seconds (adjust as needed)

    self.fireConnection = RunService.RenderStepped:Connect(function()
        local currentTime = tick()
        if self.isFiring and (currentTime - self.lastFireTime) >= self.fireRate then
            self:FireRay(self.PrimaryPart)
            self.lastFireTime = currentTime
        end
    end)
end

function WeaponController:StopAutomaticFiring()
    self.isFiring = false
    if self.fireConnection then
        self.fireConnection:Disconnect()
        self.fireConnection = nil
    end
end

function WeaponController:FireRay(PrimaryPart)
    if self.PrimaryPart then
        local origin = self.PrimaryPart.Position

        -- Create RaycastParams
        local params = RaycastParams.new()
        params.FilterType = Enum.RaycastFilterType.Exclude
        params.FilterDescendantsInstances = {self.VehicleModel, Player.Character}
        params.IgnoreWater = true

        -- Perform the raycast from the mouse position
        local mouse = Mouse.new()
        local mouseRay = mouse:GetRay()
        local result = workspace:Raycast(mouseRay.Origin, mouseRay.Direction * 1000, params)

        local targetPoint
        if result then
            -- If the raycast hits something, use the hit position
            targetPoint = result.Position
        else
            -- If the raycast doesn't hit anything, use the projected position
            targetPoint = mouseRay.Origin + mouseRay.Direction * 1000
        end

        -- Ensure the target point is at the same height as the origin
        targetPoint = Vector3.new(targetPoint.X, origin.Y, targetPoint.Z)

        -- Define the radius for the circle (slightly larger than the ball size)
        local radius = 6.5 -- Adjust this value based on the ball's size (5) + some margin

        -- Calculate the direction from the vehicle's position to the mouse position
        local directionFromMouse = (targetPoint - origin).Unit

        -- Calculate the position on the circle's circumference based on the mouse's direction
        local circleOrigin = origin + directionFromMouse * radius

        -- Calculate the direction from the circle's position to the target point
        local direction = (targetPoint - circleOrigin).Unit * 1000 -- Adjust ray length as needed

        local rayData = {
            origin = circleOrigin,
            direction = direction
        }
        WeaponsService:SendRay(rayData, PrimaryPart)
    end
end


function WeaponController:KnitInit()
    WeaponsService = Knit.GetService("WeaponsService")
end

return WeaponController