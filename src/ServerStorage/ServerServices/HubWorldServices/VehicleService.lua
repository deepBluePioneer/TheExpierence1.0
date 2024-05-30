local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local CustomPackages = ReplicatedStorage:WaitForChild("CustomPackages")
local Packages = ReplicatedStorage:WaitForChild("Packages")
local Knit = require(Packages:WaitForChild("Knit"))

local PlayerAddedController = CustomPackages.PlayerAddedController
local PlayerAddedFunctions = PlayerAddedController.PlayerAddedFunctions

local PrefabsFolder = ReplicatedStorage.Prefabs

local Vehicle = require(script.Parent.Vehicles.VehicleClass)


local VehicleService = Knit.CreateService {
    Name = "VehicleService",
    Client = {},
}

VehicleService.Vehicles = {}

-- Function to create the vehicle model
function VehicleService:CreateVehicle()
    local vehicleModel = Instance.new("Model")
    vehicleModel.Name = "VehicleModel"
    
    local sphere = Instance.new("Part")
    sphere.Shape = Enum.PartType.Ball
    sphere.Size = Vector3.new(10, 10, 10) -- Example size
    sphere.Transparency = .5
    sphere.Name = "Sphere"
    sphere.Anchored = false
    sphere.CanCollide = true
    sphere.Parent = vehicleModel

    vehicleModel.PrimaryPart = sphere

    -- Create the firing point part
    local firingPoint = Instance.new("Part")
    firingPoint.Size = Vector3.new(1, 1, 1) -- Example size
    firingPoint.Transparency = .5
    firingPoint.Name = "FiringPoint"
    firingPoint.Anchored = false
    firingPoint.CanCollide = false
    firingPoint.Massless = true
    firingPoint.Color = Color3.new(1, 0, 0) -- Red color for visibility (can be adjusted)

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

    self:SeatDetector(seat)


    return vehicleModel
end


-- Function to detect when the player sits on the seat
function VehicleService:SeatDetector(seat)
    seat:GetPropertyChangedSignal("Occupant"):Connect(function()
        local occupant = seat.Occupant
        if occupant then
            local character = occupant.Parent
            local player = game.Players:GetPlayerFromCharacter(character)
            if player then
                print(player.Name .. " has sat on the seat.")
                self:BindPlayerToVehicle(player, character, seat.Parent)

                -- Additional actions when the player sits on the seat can be added here
            end
        else
            print("Seat is now empty.")
        end
    end)
end
function VehicleService:BindPlayerToVehicle(player, character, vehicleModel)
    local humanoidRootPart = character:WaitForChild("HumanoidRootPart")

    vehicleModel.PrimaryPart:SetNetworkOwner(player)
    character:SetPrimaryPartCFrame(vehicleModel.PrimaryPart.CFrame)

    local weld = Instance.new("WeldConstraint")
    weld.Part0 = vehicleModel.PrimaryPart
    weld.Part1 = humanoidRootPart
    weld.Parent = vehicleModel.PrimaryPart

    self.Vehicles[player.UserId] = vehicleModel
end

function VehicleService:HandleCharacterAdded(Player, Character)
    local vehicleModel = self:CreateVehicle()
    vehicleModel.Parent = Workspace
    local spawnPoint = Workspace:WaitForChild("SpawnLocation")
    vehicleModel:PivotTo(spawnPoint.CFrame)
    
    local humanoidRootPart = Character:WaitForChild("HumanoidRootPart")
    vehicleModel.PrimaryPart:SetNetworkOwner(Player)
    Character:SetPrimaryPartCFrame(vehicleModel.PrimaryPart.CFrame)
    
    local weld = Instance.new("WeldConstraint")
    weld.Part0 = vehicleModel.PrimaryPart
    weld.Part1 = humanoidRootPart
    weld.Parent = vehicleModel.PrimaryPart
    
    self.Vehicles[Player.UserId] = vehicleModel
end

function VehicleService:PlayerLeft(LeavingPlayer)
    local vehicle = self.Vehicles[LeavingPlayer.UserId]
    if vehicle then
        vehicle:Destroy()
        self.Vehicles[LeavingPlayer.UserId] = nil
    end
end

function VehicleService:KnitStart()
    require(PlayerAddedFunctions)(
        function(JoiningPlayer)
        end,
        function(LeavingPlayer)
            --self:PlayerLeft(LeavingPlayer)
        end,
        function(Player, Character)
           -- self:HandleCharacterAdded(Player, Character)
        end
    )

        -- Create vehicle at the start
        local vehicleModel = self:CreateVehicle()
        vehicleModel.Parent = Workspace
        local spawnPoint = Workspace:WaitForChild("SpawnLocation")
        vehicleModel:PivotTo(spawnPoint.CFrame)
        self.Vehicles["Initial"] = vehicleModel -- Use "Initial" as a key for the initial vehicle


          -- Create vehicle at the start
    local initialVehicle = Vehicle.new()
    initialVehicle.Model.Parent = Workspace
    local spawnPoint = Workspace:WaitForChild("SpawnLocation")
    initialVehicle.Model:PivotTo(spawnPoint.CFrame)
    self.Vehicles["Initial"] = initialVehicle -- Use "Initial" as a key for the initial vehicle
        
end

function VehicleService:KnitInit()
end

-- Remote method to get the player's vehicle
function VehicleService.Client:GetPlayerVehicle(Player)
    return self.Server.Vehicles[Player.UserId]
end

return VehicleService
