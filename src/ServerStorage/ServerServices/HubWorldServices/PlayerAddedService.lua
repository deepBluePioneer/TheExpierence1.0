local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local CustomPackages = ReplicatedStorage:WaitForChild("CustomPackages")
local Packages = ReplicatedStorage:WaitForChild("Packages")
local Knit = require(Packages:WaitForChild("Knit"))

local PlayerAddedController = CustomPackages.PlayerAddedController
local PlayerAddedFunctions =  PlayerAddedController.PlayerAddedFunctions

local VehicleService = Knit.CreateService {
    Name = "VehicleService",
    Client = {},
}

-- Function to create the vehicle model
function VehicleService:CreateVehicle()
    -- Create the model
    local vehicleModel = Instance.new("Model")
    vehicleModel.Name = "VehicleModel"
    
    -- Create the sphere
    local sphere = Instance.new("Part")
    sphere.Shape = Enum.PartType.Ball
    sphere.Size = Vector3.new(10, 10, 10) -- Example size
    sphere.Transparency = 0.5 -- Semi-transparent
    sphere.Name = "Sphere"
    sphere.Anchored = false
    sphere.CanCollide = true
    sphere.Parent = vehicleModel

    -- Set the primary part of the model to the sphere
    vehicleModel.PrimaryPart = sphere

    -- Return the created vehicle model
    return vehicleModel
end

-- Function to handle character added
function VehicleService:HandleCharacterAdded(Player, Character)
    -- Create the vehicle model
    local vehicleModel = self:CreateVehicle()
    vehicleModel.Parent = workspace

    -- Get the spawn point and position the vehicle at the spawn location
    local spawnPoint = Workspace:WaitForChild("SpawnLocation")
    vehicleModel:PivotTo(spawnPoint.CFrame)

    -- Wait for the HumanoidRootPart to be available
    local humanoidRootPart = Character:WaitForChild("HumanoidRootPart")

    -- Position the character inside the sphere
    Character:SetPrimaryPartCFrame(vehicleModel.PrimaryPart.CFrame)

    -- Weld the HumanoidRootPart to the sphere
    local weld = Instance.new("WeldConstraint")
    weld.Part0 = vehicleModel.PrimaryPart
    weld.Part1 = humanoidRootPart
    weld.Parent = vehicleModel.PrimaryPart
end


-- Function to handle player leaving
function VehicleService:PlayerLeft(LeavingPlayer)
    print("LeavingPlayer: " .. LeavingPlayer.Name)
    -- Add logic if necessary to handle player leaving
end

-- KnitStart function
function VehicleService:KnitStart()
    require(PlayerAddedFunctions)(
        function(JoiningPlayer)
        end,
        function(LeavingPlayer)
        end,
        function(Player, Character)
            self:HandleCharacterAdded(Player, Character)
        end
    )
end

-- KnitInit function
function VehicleService:KnitInit()
    -- Add service initialization logic here
end

return VehicleService
