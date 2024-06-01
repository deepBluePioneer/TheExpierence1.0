--- @class Vehicle
--- A class that represents a vehicle with functionality for player interaction.
local Vehicle = {}
Vehicle.__index = Vehicle

--- Creates a new Vehicle instance.
--- @return Vehicle The newly created Vehicle instance.
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
    sphere.Anchored = true
    sphere.CanCollide = false
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

    self.Stats = {
        HP = 100,
        Boost = 0,
        Charge = 0,
        Turn = 0,
        Offense = 0,
        Defense = 0,
        Weight = 0,
        Glide = 0
    }

    self:SeatDetector(seat)
  
    return self
end

--- Detects when a player sits on the vehicle seat and binds the player to the vehicle.
--- @param seat VehicleSeat The vehicle seat instance.
function Vehicle:SeatDetector(seat)
    local currentPlayer = nil

    seat:GetPropertyChangedSignal("Occupant"):Connect(function()
        self.Model.PrimaryPart.Anchored = false
        self.Model.PrimaryPart.CanCollide = true
        local player 
        local occupant = seat.Occupant
        if occupant then
            local character = occupant.Parent
            player = game.Players:GetPlayerFromCharacter(character)
            if player then
                currentPlayer = player
                print(player.Name .. " has sat on the seat.")
                self:BindPlayerToVehicle(currentPlayer, character)
                -- Fire the signal to notify the client
                Knit.GetService("VehicleService").Client.SeatOccupied:Fire(currentPlayer, self.Model)

                -- Additional actions when the player sits on the seat can be added here
            end
        else
            self:UnbindPlayerFromVehicle()
            Knit.GetService("VehicleService").Client.SeatEjected:Fire(currentPlayer)
            self.Model.PrimaryPart.Anchored = true
            self.Model.PrimaryPart.CanCollide = false
            currentPlayer = nil
        end
    end)
end

--- Binds the player to the vehicle by welding the player's HumanoidRootPart to the vehicle.
--- @param player Player The player instance.
--- @param character Model The player's character model.
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

--- Unbinds the player from the vehicle and destroys the weld constraint.
function Vehicle:UnbindPlayerFromVehicle()
    if self.Player then
        print("UnbindPlayerFromVehicle")

        self.Model.PrimaryPart:SetNetworkOwner(nil)
        local humanoidRootPart = self.Player.Character and self.Player.Character:FindFirstChild("HumanoidRootPart")
        if humanoidRootPart then
            for _, constraint in pairs(self.Model.PrimaryPart:GetChildren()) do
                if constraint:IsA("WeldConstraint") and (constraint.Part1 == humanoidRootPart or constraint.Part0 == humanoidRootPart) then
                    constraint:Destroy()
                end
            end
        end
        self.Player = nil
    end
end

--- Prints the vehicle's stats to the output console.
function Vehicle:PrintStats()
    print("Vehicle Stats:")
    for stat, value in pairs(self.Stats) do
        print(stat .. ": " .. value)
    end
end

return Vehicle
