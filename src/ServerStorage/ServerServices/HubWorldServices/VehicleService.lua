local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local CustomPackages = ReplicatedStorage:WaitForChild("CustomPackages")
local Packages = ReplicatedStorage:WaitForChild("Packages")
local Knit = require(Packages:WaitForChild("Knit"))


local PlayerAddedController = CustomPackages.PlayerAddedController
local PlayerAddedFunctions = PlayerAddedController.PlayerAddedFunctions

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
    sphere.Transparency = 0.5
    sphere.Name = "Sphere"
    sphere.Anchored = false
    sphere.CanCollide = true
    sphere.Parent = vehicleModel

    vehicleModel.PrimaryPart = sphere
    return vehicleModel
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
            self:PlayerLeft(LeavingPlayer)
        end,
        function(Player, Character)
            self:HandleCharacterAdded(Player, Character)
        end
    )
end

function VehicleService:KnitInit()
end

-- Remote method to get the player's vehicle
function VehicleService.Client:GetPlayerVehicle(Player)
    return self.Server.Vehicles[Player.UserId]
end

return VehicleService
