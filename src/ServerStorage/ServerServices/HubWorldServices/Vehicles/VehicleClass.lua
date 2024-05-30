local Vehicle = {}
Vehicle.__index = Vehicle

function Vehicle.new()
    local self = setmetatable({}, Vehicle)
    
    -- Create the vehicle model
    self.Model = Instance.new("Model")
    self.Model.Name = "VehicleModel"

    local sphere = Instance.new("Part")
    sphere.Shape = Enum.PartType.Ball
    sphere.Size = Vector3.new(10, 10, 10) -- Example size
    sphere.Transparency = 0.5
    sphere.Name = "Sphere"
    sphere.Anchored = false
    sphere.CanCollide = true
    sphere.Parent = self.Model

    self.Model.PrimaryPart = sphere

    -- Create the firing point part
    local firingPoint = Instance.new("Part")
    firingPoint.Size = Vector3.new(1, 1, 1) -- Example size
    firingPoint.Transparency = 0.5
    firingPoint.Name = "FiringPoint"
    firingPoint.Anchored = false
    firingPoint.CanCollide = false
    firingPoint.Massless = true
    firingPoint.Color = Color3.new(1, 0, 0) -- Red color for visibility

    -- Position the firing point at the front of the sphere
    local sphereSize = sphere.Size.X / 2 -- Assuming the sphere is a perfect ball
    firingPoint.CFrame = sphere.CFrame * CFrame.new(0, 0, -sphereSize - 0.5) -- Positioned just outside the front of the sphere

    firingPoint.Parent = sphere

    -- Weld the firing point to the sphere
    local weldConstraint = Instance.new("WeldConstraint")
    weldConstraint.Part0 = sphere
    weldConstraint.Part1 = firingPoint
    weldConstraint.Parent = sphere

    -- Create the seat
    local seat = Instance.new("VehicleSeat")
    seat.Name = "DriverSeat"
    seat.Size = Vector3.new(2, 1, 2) -- Example size
    seat.Anchored = false
    seat.CanCollide = true
    seat.Transparency = 0
    seat.CFrame = sphere.CFrame -- Position the seat at the center of the sphere
    seat.Parent = sphere

    -- Weld the seat to the sphere
    local seatWeld = Instance.new("WeldConstraint")
    seatWeld.Part0 = sphere
    seatWeld.Part1 = seat
    seatWeld.Parent = sphere

    -- Store references to parts
    self.Sphere = sphere
    self.Seat = seat

    self:SeatDetector(seat)

    return self
end


-- Function to detect when the player sits on the seat
function Vehicle:SeatDetector(seat)
    seat:GetPropertyChangedSignal("Occupant"):Connect(function()
        local occupant = seat.Occupant
        if occupant then
            local character = occupant.Parent
            local player = game.Players:GetPlayerFromCharacter(character)
            if player then
                print(player.Name .. " has sat on the seat.")
                self:BindPlayerToVehicle(player, character)

                -- Additional actions when the player sits on the seat can be added here
            end
        else
            print("Seat is now empty.")
        end
    end)
end

function Vehicle:BindPlayerToVehicle(player, character)
    local humanoidRootPart = character:WaitForChild("HumanoidRootPart")

    self.Model.PrimaryPart:SetNetworkOwner(player)
    character:SetPrimaryPartCFrame(self.Model.PrimaryPart.CFrame)

    local weld = Instance.new("WeldConstraint")
    weld.Part0 = self.Model.PrimaryPart
    weld.Part1 = humanoidRootPart
    weld.Parent = self.Model.PrimaryPart

    self.Player = player
end

return Vehicle